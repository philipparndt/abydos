import AbydosKit
import AppKit

/// A file as bytes, with a caret.
///
/// The drawing is the old read-only dump's: the file is a `ByteDocument`
/// over a mapping and only the rows in the dirty rect are formatted, so a
/// gigabyte scrolls at full speed. Everything the dump lacked is here or in
/// the two extensions beside it — the caret and selection in both columns
/// (`+Selection`), typing, deleting and the pasteboard (`+Editing`).
///
/// **The caret sits between bytes.** Zero is before the first, `count` is
/// after the last and where a typed byte is appended. A selection is the
/// bytes between the anchor and the caret. Pressing on a byte puts the caret
/// before it; dragging forward takes the caret past the byte under the
/// pointer, so a drag from 0x10 to 0x1F selects sixteen bytes and ⇧→ three
/// times from 0x20 selects three, which is what both gestures mean.
final class HexEditorView: NSView, ScaleFollowing {
	enum Column { case hex, text }

	let document: ByteDocument

	/// Told after the caret, the selection or the column changed.
	var onCaretChanged: ((HexEditorView) -> Void)?
	/// Told when insert mode was turned on or off.
	var onModeChanged: ((HexEditorView) -> Void)?
	/// Told when the view was asked for something it cannot do here — the
	/// find field, the offset field — so the controller can.
	var onFindRequested: (() -> Void)?

	// MARK: - State

	var bytesPerRow = 16 {
		didSet { guard bytesPerRow != oldValue else { return }; relayout() }
	}
	var encoding: ByteEncoding = .ascii {
		didSet { needsDisplay = true }
	}
	var caret = 0
	var anchor: Int?
	var activeColumn: Column = .hex
	/// Insert is a switch; overwrite is the mode. A nibble half typed is
	/// kept here until its other half arrives.
	var insertMode = false {
		didSet { onModeChanged?(self) }
	}
	var pendingNibble: UInt8?

	/// What find found, and which of them is current.
	var matches: [Int] = [] { didSet { needsDisplay = true } }
	var currentMatch: Int? { didSet { needsDisplay = true } }
	var matchLength = 0
	/// The structure field the caret is in, or the row chosen in the outline.
	var highlightedField: Range<Int>? { didSet { needsDisplay = true } }

	var selection: Range<Int>? {
		guard let anchor, anchor != caret else { return nil }
		return min(anchor, caret)..<max(anchor, caret)
	}

	/// The bytes the next edit acts on: the selection, or the one at the caret.
	var target: Range<Int> { selection ?? caret..<min(document.count, caret + 1) }

	// MARK: - Metrics

	private(set) var font = Theme.current.editorFont
	private(set) var rowHeight: CGFloat = 17
	private(set) var charWidth: CGFloat = 7
	private(set) var offsetColumnX: CGFloat = 12
	private(set) var hexColumnX: CGFloat = 0
	private(set) var textColumnX: CGFloat = 0
	let undo = UndoManager()

	init(document: ByteDocument) {
		self.document = document
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		document.undoManager = undo
		computeMetrics()
		sizeToFit()
		ScaledControls.register(self)
	}

	/// The zoom or the palette changed: the font, the metrics and the
	/// colours again, and the rows laid out to the new cell.
	func applyTheme() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		relayout()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }
	override var undoManager: UndoManager? { undo }

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return true
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return true
	}

	private func computeMetrics() {
		font = Theme.current.editorFont
		charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
		rowHeight = ceil((font.ascender - font.descender + font.leading) * Theme.current.lineHeightMultiple)
		offsetColumnX = Theme.current.scaled(12)
		hexColumnX = offsetColumnX + charWidth * 10
		textColumnX = hexColumnX + charWidth * hexWidthInCharacters + charWidth * 2
	}

	/// Three characters a byte and two more after every eight.
	private var hexWidthInCharacters: CGFloat {
		CGFloat(bytesPerRow * 3 - 1 + 2 * max(0, (bytesPerRow - 1) / 8))
	}

	/// One more than the bytes need, so the caret has a row to append on.
	var rowCount: Int { document.count / bytesPerRow + 1 }

	func relayout() {
		computeMetrics()
		sizeToFit()
		needsDisplay = true
	}

	func sizeToFit() {
		setFrameSize(NSSize(
			width: textColumnX + charWidth * CGFloat(bytesPerRow) + Theme.current.scaled(24),
			height: CGFloat(rowCount) * rowHeight + Theme.current.scaled(8)
		))
	}

	/// The x of byte `index` of a row in the hex column, with the gap after
	/// every eight.
	func hexX(_ index: Int) -> CGFloat {
		hexColumnX + charWidth * CGFloat(index * 3 + 2 * (index / 8))
	}

	func textX(_ index: Int) -> CGFloat {
		textColumnX + charWidth * CGFloat(index)
	}

	func rowY(_ row: Int) -> CGFloat { CGFloat(row) * rowHeight }

	func rect(of offset: Int, in column: Column) -> NSRect {
		let row = offset / bytesPerRow
		let index = offset % bytesPerRow
		return column == .hex
			? NSRect(x: hexX(index), y: rowY(row), width: charWidth * 2, height: rowHeight)
			: NSRect(x: textX(index), y: rowY(row), width: charWidth, height: rowHeight)
	}

	/// The byte under a point and which column it is in, or nil in the
	/// gutter. Past the end of a row is that row's last byte.
	func offset(at point: NSPoint) -> (Int, Column)? {
		let row = max(0, Int(floor(point.y / rowHeight)))
		let column: Column
		let index: Int
		if point.x >= textColumnX - charWidth {
			column = .text
			index = Int(floor((point.x - textColumnX) / charWidth))
		} else if point.x >= hexColumnX - charWidth {
			column = .hex
			// Undo the gaps: each group of eight is 26 characters wide.
			let characters = max(0, (point.x - hexColumnX) / charWidth)
			let group = Int(characters / 26)
			let within = Int((characters - CGFloat(group) * 26) / 3)
			index = group * 8 + min(7, within)
		} else {
			return nil
		}
		let clamped = max(0, min(bytesPerRow - 1, index))
		return (min(document.count, row * bytesPerRow + clamped), column)
	}

	/// The rows a rect covers, clamped to the file.
	func rows(in rect: NSRect) -> Range<Int> {
		let first = max(0, Int(floor(rect.minY / rowHeight)))
		let last = min(rowCount, Int(ceil(rect.maxY / rowHeight)) + 1)
		return first..<max(first, last)
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		let theme = Theme.current
		theme.editorBackground.setFill()
		dirtyRect.fill()

		let snapshot = document.snapshot()
		let edited = snapshot.editedRanges
		let focused = window?.firstResponder === self
		let offsetAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.gutterText]

		for row in rows(in: dirtyRect) {
			let y = rowY(row)
			let start = row * bytesPerRow
			let end = min(snapshot.count, start + bytesPerRow)

			if (row / 8) % 2 == 1 {
				theme.currentLineBackground.withAlphaComponent(0.4).setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: rowHeight).fill()
			}
			NSAttributedString(string: String(format: "%08X", start), attributes: offsetAttributes)
				.draw(at: NSPoint(x: offsetColumnX, y: y + 1))
			guard start < end || start == snapshot.count else { continue }

			// Backgrounds first, in both columns, in the order that lets the
			// most specific show: the field, then matches, then the edits,
			// then the selection on top.
			for offset in start..<end {
				var fill: NSColor?
				if let field = highlightedField, field.contains(offset) { fill = theme.selectionOccurrenceBackground }
				if let match = matchContaining(offset) {
					fill = match == currentMatch ? theme.searchMatchCurrentBackground : theme.searchMatchBackground
				}
				if edited.contains(where: { $0.contains(offset) }) { fill = theme.gitModified.withAlphaComponent(0.28) }
				if let selection, selection.contains(offset) {
					fill = theme.selection(.text, hasKeyboard: focused)
				}
				guard let fill else { continue }
				fill.setFill()
				var hexRect = rect(of: offset, in: .hex)
				// The cell plus the space after it, so a run reads as one band.
				if offset + 1 < end, offset % 8 != 7 || offset - start == bytesPerRow - 1 { hexRect.size.width += charWidth }
				if activeColumn == .hex || selection == nil { hexRect.fill() } else { fill.withAlphaComponent(0.35).setFill(); hexRect.fill(); fill.setFill() }
				let textRect = rect(of: offset, in: .text)
				if activeColumn == .text || selection == nil { textRect.fill() } else { fill.withAlphaComponent(0.35).setFill(); textRect.fill() }
			}

			if start < end {
				let bytes = snapshot.bytes(in: start..<end)
				drawHex(bytes, at: NSPoint(x: hexColumnX, y: y + 1), start: start)
				drawText(bytes, at: NSPoint(x: textColumnX, y: y + 1))
			}
		}

		drawCaret(focused: focused)
	}

	private func matchContaining(_ offset: Int) -> Int? {
		guard matchLength > 0, !matches.isEmpty else { return nil }
		// Matches are sorted; the last one starting at or before the offset
		// is the only one that can hold it.
		var low = 0, high = matches.count - 1
		while low < high {
			let mid = (low + high + 1) / 2
			if matches[mid] <= offset { low = mid } else { high = mid - 1 }
		}
		let start = matches[low]
		return (start <= offset && offset < start + matchLength) ? start : nil
	}

	private func drawHex(_ bytes: Data, at point: NSPoint, start: Int) {
		let theme = Theme.current
		let line = NSMutableAttributedString()
		let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.editorText]
		// Dimming zero bytes makes structure in binary data far easier to see.
		let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.gutterText]
		// **A byte with no character, told apart without a second hue.** The
		// text column beside this one already says which bytes are text —
		// printable in `gitAdded`, a grey dot for the rest — so giving the hex
		// a colour of its own would say the same thing twice and turn a wall
		// of digits into a wall of stripes. Instead the axis the zero dimming
		// already uses, one step short of it.
		//
		// **Most of the way to the gutter, not a little.** There is only so
		// much room here — the default scheme runs from `#E8D9C0` to `#6E5B45`,
		// about 120 of luma — and a third shade put near the top of it was
		// measured at 164 against text at 214 and could not be told apart at
		// a glance, which is the whole job. So the big gap goes where the
		// question is (text against not-text, 93 apart) and the small one
		// where a run of zeros gives the answer away anyway (31 apart).
		let quiet: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: theme.editorText.blended(withFraction: 0.75, of: theme.gutterText)
				?? theme.editorText,
		]
		for (index, byte) in bytes.enumerated() {
			var text = String(format: "%02X", byte)
			if index + 1 < bytes.count { text += index % 8 == 7 ? "   " : " " }
			var attributes: [NSAttributedString.Key: Any]
			switch encoding.shade(of: byte) {
			case .text:  attributes = plain
			case .quiet: attributes = quiet
			case .empty: attributes = dim
			}
			if let pendingNibble, start + index == caret, insertMode == false {
				// Half a byte typed: the high nibble shown as typed, the low
				// as what is still there, and the whole cell marked.
				text = String(format: "%X", pendingNibble) + String(text.dropFirst())
				attributes[.foregroundColor] = theme.gitModified
			}
			line.append(NSAttributedString(string: text, attributes: attributes))
		}
		line.draw(at: point)
	}

	private func drawText(_ bytes: Data, at point: NSPoint) {
		let theme = Theme.current
		let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.gitAdded]
		let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.gutterText]
		let line = NSMutableAttributedString()
		for byte in bytes {
			// One cell a byte whatever the encoding: a UTF-8 sequence shows
			// its lead byte's dot here and its character in the inspector,
			// because a column that is not one cell a byte cannot be clicked
			// at a byte.
			if encoding.isPrintable(byte), let text = String(data: Data([byte]), encoding: encoding == .latin1 ? .isoLatin1 : .ascii) {
				line.append(NSAttributedString(string: text, attributes: attributes))
			} else {
				line.append(NSAttributedString(string: ".", attributes: dim))
			}
		}
		line.draw(at: point)
	}

	private func drawCaret(focused: Bool) {
		guard focused, selection == nil else { return }
		let theme = Theme.current
		let caretRect: NSRect
		if caret < document.count {
			caretRect = rect(of: caret, in: activeColumn)
		} else {
			// After the last byte: on the next cell, which may be a new row.
			let row = caret / bytesPerRow, index = caret % bytesPerRow
			caretRect = activeColumn == .hex
				? NSRect(x: hexX(index), y: rowY(row), width: charWidth * 2, height: rowHeight)
				: NSRect(x: textX(index), y: rowY(row), width: charWidth, height: rowHeight)
		}
		theme.caret.setFill()
		NSRect(x: caretRect.minX - 1, y: caretRect.minY, width: 2, height: rowHeight).fill()
		// The mirror column shows where the same byte is, as an outline.
		let mirror = activeColumn == .hex ? Column.text : .hex
		let other = caret < document.count ? rect(of: caret, in: mirror) : NSRect(
			x: mirror == .hex ? hexX(caret % bytesPerRow) : textX(caret % bytesPerRow),
			y: rowY(caret / bytesPerRow), width: mirror == .hex ? charWidth * 2 : charWidth, height: rowHeight
		)
		theme.caret.withAlphaComponent(0.5).setStroke()
		NSBezierPath(rect: other.insetBy(dx: 0.5, dy: 0.5)).stroke()
	}

	// MARK: - Reporting

	/// What the status bar says: the caret in hex and decimal, and the
	/// selection's start, end and length when there is one.
	var statusText: String {
		var said: String
		if let selection {
			said = String(
				format: "0x%llX–0x%llX · %lld bytes", selection.lowerBound, selection.upperBound - 1, selection.count
			)
		} else {
			said = String(format: "0x%llX · %lld", caret, caret)
		}
		if insertMode { said += " · Insert" }
		return said
	}

	func setInsertMode(_ on: Bool) {
		guard insertMode != on else { return }
		pendingNibble = nil
		insertMode = on
		needsDisplay = true
	}

	/// Redraw after the document changed under the view.
	func documentChanged() {
		if caret > document.count { caret = document.count }
		if let anchor, anchor > document.count { self.anchor = document.count }
		sizeToFit()
		needsDisplay = true
		onCaretChanged?(self)
	}
}

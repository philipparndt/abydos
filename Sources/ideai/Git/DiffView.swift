import AppKit
import IdeaiKit

/// A unified diff, rendered as coloured lines, with the changed ones
/// selectable so parts of it can be staged.
///
/// Hand-drawn like the code view rather than built on `NSTextView`: a diff is a
/// list of short lines with one colour each, and the same virtualised drawing
/// keeps a large one — a lockfile, a generated file — instant to open.
final class DiffView: NSView {
	/// Stage or unstage the selected lines. The direction depends on which side
	/// of the index this diff came from, which the pane already knows.
	var onApplySelection: ((Set<Int>) -> Void)?
	/// Throw away the selected work-tree lines.
	var onDiscardSelection: ((Set<Int>) -> Void)?

	private var patch = GitPatch()
	private(set) var isStaged = false

	/// Flat rows: hunk headers and lines interleaved, as drawn.
	private var rows: [Row] = []
	/// Selected *line* indices, in `GitPatch`'s flat numbering.
	private var selection: Set<Int> = []
	/// Anchor for shift-click range selection.
	private var anchorRow: Int?

	private enum Row {
		case header(String)
		case hunkHeader(index: Int, text: String)
		case line(index: Int, line: GitPatch.Line)
	}

	private var font: NSFont = Theme.terminalFont(size: Theme.current.fontSize)
	private var lineHeight: CGFloat = 0
	private static let horizontalInset: CGFloat = 12
	/// Room for the selection marker down the left edge.
	private static let gutterWidth: CGFloat = 14

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		lineHeight = (font.ascender - font.descender + font.leading).rounded() + 2
	}

	func applyThemeChange() {
		updateMetrics()
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	// MARK: - Content

	func setDiff(_ text: String, staged: Bool) {
		isStaged = staged
		patch = GitPatch.parse(text)
		selection = []
		anchorRow = nil
		rebuildRows()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	private func rebuildRows() {
		rows = patch.header.map { Row.header($0) }

		var index = 0
		for (position, hunk) in patch.hunks.enumerated() {
			let heading = hunk.heading.isEmpty ? "" : " \(hunk.heading)"
			rows.append(.hunkHeader(index: position, text: "@@ hunk \(position + 1)\(heading)"))
			for line in hunk.lines {
				rows.append(.line(index: index, line: line))
				index += 1
			}
		}

		if patch.hunks.isEmpty {
			rows.append(.header(""))
			rows.append(.header("No textual changes."))
		}
	}

	// MARK: - Selection

	var hasSelection: Bool { !selection.isEmpty }
	var selectedLines: Set<Int> { selection }

	override func selectAll(_ sender: Any?) {
		selection = Set(patch.selectableIndices())
		needsDisplay = true
	}

	func clearSelection() {
		selection = []
		anchorRow = nil
		needsDisplay = true
	}

	/// Selects every changed line in a hunk, for "stage this hunk".
	func selectHunk(_ hunkIndex: Int) {
		selection = Set(patch.indices(inHunk: hunkIndex))
		needsDisplay = true
	}

	private func row(at point: NSPoint) -> Int? {
		let top = Theme.current.scaled(8)
		let index = Int((point.y - top) / lineHeight)
		return rows.indices.contains(index) ? index : nil
	}

	private func lineIndex(atRow row: Int) -> Int? {
		guard rows.indices.contains(row), case let .line(index, line) = rows[row], line.isSelectable else {
			return nil
		}
		return index
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		guard let row = row(at: convert(event.locationInWindow, from: nil)) else { return }

		// A click on a hunk header takes the whole hunk, which is the common
		// case — line-by-line is for when a hunk mixes two changes.
		if case let .hunkHeader(hunkIndex, _) = rows[row] {
			selectHunk(hunkIndex)
			anchorRow = row
			return
		}

		guard let index = lineIndex(atRow: row) else { return }

		if event.modifierFlags.contains(.shift), let anchor = anchorRow {
			// Range from the anchor, skipping context that falls between.
			let bounds = min(anchor, row)...max(anchor, row)
			for position in bounds {
				if let candidate = lineIndex(atRow: position) { selection.insert(candidate) }
			}
		} else if event.modifierFlags.contains(.command) {
			if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
			anchorRow = row
		} else {
			selection = [index]
			anchorRow = row
		}
		needsDisplay = true
	}

	override func mouseDragged(with event: NSEvent) {
		guard let anchor = anchorRow,
		      let row = row(at: convert(event.locationInWindow, from: nil))
		else { return }

		var updated: Set<Int> = []
		for position in min(anchor, row)...max(anchor, row) {
			if let index = lineIndex(atRow: position) { updated.insert(index) }
		}
		guard updated != selection else { return }
		selection = updated
		needsDisplay = true
	}

	override func keyDown(with event: NSEvent) {
		// Return applies, which is the whole point of having a selection here.
		if event.keyCode == 36 || event.keyCode == 76, hasSelection {
			onApplySelection?(selection)
			return
		}
		super.keyDown(with: event)
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		// Right-clicking outside the selection moves it there first, so the
		// command acts on what was aimed at.
		if let row = row(at: convert(event.locationInWindow, from: nil)) {
			if case let .hunkHeader(hunkIndex, _) = rows[row] {
				selectHunk(hunkIndex)
			} else if let index = lineIndex(atRow: row), !selection.contains(index) {
				selection = [index]
				anchorRow = row
				needsDisplay = true
			}
		}
		guard hasSelection else { return nil }

		let menu = NSMenu()
		menu.autoenablesItems = false

		let count = selection.count
		let suffix = count == 1 ? "" : " (\(count))"
		let apply = NSMenuItem(
			title: (isStaged ? "Unstage Selected Lines" : "Stage Selected Lines") + suffix,
			action: #selector(applySelection),
			keyEquivalent: ""
		)
		apply.target = self
		menu.addItem(apply)

		if !isStaged {
			menu.addItem(.separator())
			let discard = NSMenuItem(
				title: "Discard Selected Lines" + suffix,
				action: #selector(discardSelection),
				keyEquivalent: ""
			)
			discard.target = self
			menu.addItem(discard)
		}
		return menu
	}

	@objc private func applySelection() { onApplySelection?(selection) }
	@objc private func discardSelection() { onDiscardSelection?(selection) }

	// MARK: - Drawing

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: max(CGFloat(rows.count) * lineHeight + Theme.current.scaled(16), 10)
		)
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		let top = Theme.current.scaled(8)
		// Only the rows in view are laid out, which is what keeps a huge diff
		// as cheap to scroll as a small one.
		let first = max(0, Int((dirtyRect.minY - top) / lineHeight))
		let last = min(rows.count, Int((dirtyRect.maxY - top) / lineHeight) + 1)
		guard last > first else { return }

		for position in first..<last {
			draw(row: rows[position], at: top + CGFloat(position) * lineHeight)
		}
	}

	private func draw(row: Row, at y: CGFloat) {
		let textX = Self.horizontalInset + Self.gutterWidth

		switch row {
		case .header(let text):
			guard !text.isEmpty else { return }
			text.draw(at: NSPoint(x: textX, y: y), font: font, color: Theme.current.gitIgnored)

		case .hunkHeader(_, let text):
			NSColor.white.withAlphaComponent(0.05).setFill()
			NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
			text.draw(
				at: NSPoint(x: textX, y: y),
				font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
				color: Theme.current.gitModified
			)

		case .line(let index, let line):
			let isSelected = selection.contains(index)

			if let background = background(for: line.kind) {
				background.setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
			}

			if isSelected {
				// A tint over the whole row plus a bar in the gutter: the tint
				// alone is hard to see against a row that already has one.
				Theme.current.gitModified.withAlphaComponent(0.20).setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
				Theme.current.gitModified.setFill()
				NSRect(x: 0, y: y, width: Theme.current.scaled(3), height: lineHeight).fill()
			}

			let text = line.marker + line.text
			guard !text.isEmpty else { return }
			text.draw(at: NSPoint(x: textX, y: y), font: font, color: color(for: line.kind))
		}
	}

	private func background(for kind: GitPatch.Line.Kind) -> NSColor? {
		switch kind {
		case .added:   return Theme.current.gitAdded.withAlphaComponent(0.13)
		case .removed: return Theme.current.gitUnversioned.withAlphaComponent(0.13)
		default:       return nil
		}
	}

	private func color(for kind: GitPatch.Line.Kind) -> NSColor {
		switch kind {
		case .added:     return Theme.current.gitAdded
		case .removed:   return Theme.current.gitUnversioned
		case .noNewline: return Theme.current.gitIgnored
		case .context:   return Theme.current.sidebarText
		}
	}
}

private extension String {
	func draw(at point: NSPoint, font: NSFont, color: NSColor) {
		NSAttributedString(string: self, attributes: [
			.font: font,
			.foregroundColor: color,
		]).draw(at: point)
	}
}

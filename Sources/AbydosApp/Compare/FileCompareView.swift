import AppKit
import AbydosKit

/// Two whole files side by side, aligned line by line, with a curve between
/// the halves for every change.
///
/// Not `DiffView`. That view draws a patch — hunk headers, a `+`/`-` meaning
/// on every row, a selection that stages — and it is at the length ceiling
/// with three extensions beside it. This one holds `TextDiff` rows, which are
/// *pairs*: a line from each side, or a line and a gap, and a change is a run
/// of them with a curve through the gutter from its rows on the left to its
/// rows on the right. What is shared is what `DiffView`'s header says owns its
/// own state — `DiffTextRun` for the character selection — and the colours the
/// diff view uses, so the two read as one thing.
///
/// Both halves are one document view in one scroll view, not two kept in
/// step: two views kept in step are a frame late on every wheel event, and the
/// halves are rows of one alignment anyway.
final class FileCompareView: NSView {
	/// The current change moved, or the count did: `(index, count)`.
	var onChangeMoved: ((Int?, Int) -> Void)?

	private(set) var diff = TextDiff(leftLines: [], rightLines: [])
	private(set) var leftTokens: [Int: [HighlightToken]] = [:]
	private(set) var rightTokens: [Int: [HighlightToken]] = [:]
	/// The rows as drawn: the diff's rows with the long equal runs folded.
	private(set) var shown: [TextDiff.Shown] = []
	private var opened: Set<Int> = []
	/// The change the reader is on, as an index into `diff.changes`.
	private(set) var currentChange: Int?
	/// Where each drawn row begins, prefix-summed, with one entry past the
	/// last; the whole of the wrapped layout is this array.
	private var rowTops: [CGFloat] = [0]
	private var laidOutWidth: CGFloat = 0

	var font: NSFont = Theme.terminalFont(size: Theme.current.fontSize)
	var lineHeight: CGFloat = 0
	private(set) var wrapsLines = Settings.shared.wordWrap
	let textRun = DiffTextRun()
	private var hasKeyboard = false
	private var pressedFold: Int?

	static let horizontalInset: CGFloat = 8
	/// The gutter between the halves, where the curves are drawn.
	var gutterWidth: CGFloat { Theme.current.scaled(28) }
	private var topInset: CGFloat { Theme.current.scaled(8) }
	static let tabWidth = 4

	var characterWidth: CGFloat {
		("0" as NSString).size(withAttributes: [.font: font]).width
	}
	var numberWidth: CGFloat { characterWidth * 5 }
	var halfWidth: CGFloat { ((bounds.width - gutterWidth) / 2).rounded(.down) }
	/// The columns of text a half can show, for the wrap.
	var columns: Int? {
		guard wrapsLines else { return nil }
		return max(8, Int((halfWidth - numberWidth - Self.horizontalInset * 2) / characterWidth))
	}

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()
		describeRows()
		NotificationCenter.default.addObserver(
			self, selector: #selector(applySettingsNotification), name: .abydosSettingsChanged, object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit { NotificationCenter.default.removeObserver(self) }

	// MARK: - What is shown

	func setDiff(_ diff: TextDiff, leftTokens: [Int: [HighlightToken]], rightTokens: [Int: [HighlightToken]]) {
		self.diff = diff
		self.leftTokens = leftTokens
		self.rightTokens = rightTokens
		opened = []
		textRun.forget()
		rebuildRows()
		currentChange = diff.changes.isEmpty ? nil : 0
		onChangeMoved?(currentChange, diff.changes.count)
		DispatchQueue.main.async { [weak self] in self?.scrollToCurrentChange() }
	}

	private func rebuildRows() {
		shown = diff.shown(opened: opened)
		rebuildLayout()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// Row tops, from each row's height: one line, or with wrap on the taller
	/// of its two halves, by `WrapLayout`'s arithmetic on a fixed-advance font.
	private func rebuildLayout() {
		laidOutWidth = bounds.width
		let columns = columns
		var tops: [CGFloat] = [0]
		tops.reserveCapacity(shown.count + 1)
		var y: CGFloat = 0
		for entry in shown {
			var lines = 1
			if let columns, case .row(let index) = entry {
				let row = diff.rows[index]
				let left = row.left.map { WrapLayout.rowCount(in: diff.leftLines[$0], columns: columns, tabWidth: Self.tabWidth) } ?? 1
				let right = row.right.map { WrapLayout.rowCount(in: diff.rightLines[$0], columns: columns, tabWidth: Self.tabWidth) } ?? 1
				lines = max(left, right)
			}
			y += CGFloat(lines) * lineHeight
			tops.append(y)
		}
		rowTops = tops
		textRun.forget()
	}

	private func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		lineHeight = (font.ascender - font.descender + font.leading).rounded(.up) + 2
	}

	/// The wrap follows the editor's own switch, and the zoom is a settings
	/// change too — the diff view learnt that one the hard way.
	@objc private func applySettingsNotification() { applySettings() }

	func applySettings() {
		let wasCurrent = currentChange
		updateMetrics()
		wrapsLines = Settings.shared.wordWrap
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		rebuildRows()
		currentChange = wasCurrent
		scrollToCurrentChange()
	}

	override func layout() {
		super.layout()
		// A width change rewraps; a scroll changes none of what the layout
		// depends on, and rebuilding on every scroll is the cost `WrapLayout`
		// records.
		if wrapsLines, bounds.width != laidOutWidth {
			rebuildLayout()
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	override var intrinsicContentSize: NSSize {
		NSSize(width: NSView.noIntrinsicMetric, height: max((rowTops.last ?? 0) + topInset * 2, 10))
	}

	// MARK: - Rows and where they are

	func top(ofRow index: Int) -> CGFloat { topInset + rowTops[index] }
	func height(ofRow index: Int) -> CGFloat { rowTops[index + 1] - rowTops[index] }

	/// The drawn row at a y, by bisection over the tops.
	func rowIndex(atY y: CGFloat) -> Int? {
		let local = y - topInset
		guard !shown.isEmpty, local >= 0, local < rowTops[rowTops.count - 1] else { return nil }
		var low = 0, high = shown.count - 1
		while low < high {
			let mid = (low + high + 1) / 2
			if rowTops[mid] <= local { low = mid } else { high = mid - 1 }
		}
		return low
	}

	/// The line index on one side of a drawn row, if there is one there.
	func line(ofRow index: Int, in column: DiffTextRun.Column) -> Int? {
		guard shown.indices.contains(index), case .row(let rowIndex) = shown[index] else { return nil }
		let row = diff.rows[rowIndex]
		return column == .left ? row.left : row.right
	}

	/// What a half of a row says: the line, or nothing for a gap or a fold.
	func text(ofRow index: Int, in column: DiffTextRun.Column) -> String {
		guard let line = line(ofRow: index, in: column) else { return "" }
		return column == .left ? diff.leftLines[line] : diff.rightLines[line]
	}

	/// Where a half's text begins.
	func textOrigin(in column: DiffTextRun.Column) -> CGFloat {
		halfMinX(column) + Self.horizontalInset + numberWidth + Self.horizontalInset
	}

	func halfMinX(_ column: DiffTextRun.Column) -> CGFloat {
		column == .left ? 0 : halfWidth + gutterWidth
	}

	private func describeRows() {
		textRun.rowAt = { [weak self] row, column in
			guard let self else { return DiffTextRun.Row(text: "", font: .systemFont(ofSize: 12), origin: 0) }
			return DiffTextRun.Row(text: self.text(ofRow: row, in: column), font: self.font, origin: self.textOrigin(in: column))
		}
		textRun.textAt = { [weak self] row, column in self?.text(ofRow: row, in: column) ?? "" }
	}

	/// The visual rows of one half of a drawn row: the UTF-16 range each one
	/// shows. One entry, the whole line, when wrap is off.
	func segments(ofRow index: Int, in column: DiffTextRun.Column) -> [Range<Int>] {
		let text = text(ofRow: index, in: column)
		guard let columns else { return [0..<text.utf16.count] }
		let starts = WrapLayout.rowStarts(in: text, columns: columns, tabWidth: Self.tabWidth)
		let count = text.utf16.count
		return starts.indices.map { starts[$0]..<(($0 + 1 < starts.count) ? starts[$0 + 1] : count) }
	}

	// MARK: - Changes

	var changeCount: Int { diff.changes.count }

	func goToChange(_ index: Int) {
		guard diff.changes.indices.contains(index) else { return }
		currentChange = index
		// A fold hiding the change is opened: the change is what the reader
		// asked for.
		let change = diff.changes[index]
		for case .fold(let rows) in shown where rows.overlaps(change.rows) { opened.insert(rows.lowerBound) }
		shown = diff.shown(opened: opened)
		rebuildLayout()
		invalidateIntrinsicContentSize()
		scrollToCurrentChange()
		needsDisplay = true
		onChangeMoved?(currentChange, diff.changes.count)
	}

	func nextChange() {
		guard !diff.changes.isEmpty else { return }
		goToChange(min(diff.changes.count - 1, (currentChange ?? -1) + 1))
	}

	func previousChange() {
		guard !diff.changes.isEmpty else { return }
		goToChange(max(0, (currentChange ?? 1) - 1))
	}

	/// The drawn row a diff row is at, if it is not folded away.
	func shownIndex(ofDiffRow row: Int) -> Int? {
		shown.firstIndex { if case .row(let index) = $0 { return index == row } else { return false } }
	}

	/// Puts the current change a third of the way down the visible area, so
	/// there is context above it and the change itself below.
	func scrollToCurrentChange() {
		guard let current = currentChange, diff.changes.indices.contains(current),
		      let scroll = enclosingScrollView, let index = shownIndex(ofDiffRow: diff.changes[current].rows.lowerBound)
		else { return }
		let visible = scroll.contentView.bounds.height
		let y = max(0, top(ofRow: index) - visible / 3)
		let limit = max(0, bounds.height - visible)
		scroll.contentView.scroll(to: NSPoint(x: 0, y: min(y, limit)))
		scroll.reflectScrolledClipView(scroll.contentView)
	}

	func openFold(at index: Int) {
		guard shown.indices.contains(index), case .fold(let rows) = shown[index] else { return }
		opened.insert(rows.lowerBound)
		textRun.forget()
		shown = diff.shown(opened: opened)
		rebuildLayout()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	// MARK: - The keyboard

	override func becomeFirstResponder() -> Bool {
		hasKeyboard = true
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		hasKeyboard = false
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.resignFirstResponder()
	}

	var keyboardIsHere: Bool { hasKeyboard }

	override func keyDown(with event: NSEvent) {
		let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		let key = event.charactersIgnoringModifiers?.unicodeScalars.first?.value
		if flags == .command, key == 0xF701 { nextChange(); return }
		if flags == .command, key == 0xF700 { previousChange(); return }
		super.keyDown(with: event)
	}

	@objc func copy(_ sender: Any?) {
		guard let text = copiedText else { NSSound.beep(); return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc override func selectAll(_ sender: Any?) {
		guard !shown.isEmpty else { return }
		textRun.takeEverything(through: shown.count - 1, in: textRun.isEmpty ? .right : textRun.column)
		needsDisplay = true
	}

	/// The selected characters, from the rows of one half — a gap contributes
	/// nothing, so a selection dragged over a removed block on the other side
	/// does not come out with empty lines in it.
	var copiedText: String? {
		guard !textRun.isEmpty else { return nil }
		var lines: [String] = []
		for row in textRun.start.row...textRun.end.row {
			guard line(ofRow: row, in: textRun.column) != nil, let covered = textRun.covered(row: row) else { continue }
			let units = Array(text(ofRow: row, in: textRun.column).utf16)
			let upper = min(covered.upperBound, units.count)
			let lower = min(covered.lowerBound, upper)
			lines.append(String(decoding: units[lower..<upper], as: UTF16.self))
		}
		return lines.joined(separator: "\n")
	}

	// MARK: - The mouse

	/// Which half and row a point is over, and how far into the text.
	private func hit(_ point: NSPoint) -> (row: Int, column: DiffTextRun.Column, offset: Int)? {
		guard let row = rowIndex(atY: point.y) else { return nil }
		let column: DiffTextRun.Column = point.x < halfWidth + gutterWidth / 2 ? .left : .right
		return (row, column, offset(atPoint: point, row: row, in: column))
	}

	/// How far into a half's text a point is, on whichever visual row of it
	/// the point is on.
	func offset(atPoint point: NSPoint, row: Int, in column: DiffTextRun.Column) -> Int {
		let segments = segments(ofRow: row, in: column)
		let visualRow = min(segments.count - 1, max(0, Int((point.y - top(ofRow: row)) / lineHeight)))
		let segment = segments[visualRow]
		let text = text(ofRow: row, in: column)
		let units = Array(text.utf16)
		let piece = String(decoding: units[segment], as: UTF16.self)
		let line = CTLineCreateWithAttributedString(NSAttributedString(string: piece, attributes: [.font: font]))
		let local = point.x - textOrigin(in: column)
		guard local > 0 else { return segment.lowerBound }
		let found = CTLineGetStringIndexForPosition(line, CGPoint(x: local, y: 0))
		guard found != kCFNotFound else { return segment.upperBound }
		return segment.lowerBound + min(max(0, found), piece.utf16.count)
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let point = convert(event.locationInWindow, from: nil)
		guard let row = rowIndex(atY: point.y) else { return }
		if case .fold = shown[row] {
			pressedFold = row
			return
		}
		guard let hit = hit(point) else { return }
		switch event.clickCount {
		case 2: textRun.takeWord(row: hit.row, offset: hit.offset, in: hit.column)
		case 3: textRun.takeRow(hit.row, in: hit.column)
		default:
			if event.modifierFlags.contains(.shift), !textRun.isEmpty {
				textRun.extend(toRow: hit.row, offset: hit.offset)
			} else {
				textRun.press(row: hit.row, offset: hit.offset, in: hit.column)
			}
		}
		needsDisplay = true
	}

	override func mouseDragged(with event: NSEvent) {
		guard pressedFold == nil, textRun.isPressed else { return }
		let point = convert(event.locationInWindow, from: nil)
		let row = rowIndex(atY: point.y) ?? (point.y < topInset ? 0 : shown.count - 1)
		textRun.extend(toRow: row, offset: offset(atPoint: point, row: row, in: textRun.column))
		autoscroll(with: event)
		needsDisplay = true
	}

	override func mouseUp(with event: NSEvent) {
		if let fold = pressedFold {
			pressedFold = nil
			let point = convert(event.locationInWindow, from: nil)
			if rowIndex(atY: point.y) == fold { openFold(at: fold) }
		}
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		let menu = NSMenu()
		let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
		copy.target = self
		copy.isEnabled = !textRun.isEmpty
		menu.addItem(copy)
		menu.addItem(.separator())
		let next = NSMenuItem(title: "Next Change", action: #selector(nextChangeMenu), keyEquivalent: "")
		next.target = self
		menu.addItem(next)
		let previous = NSMenuItem(title: "Previous Change", action: #selector(previousChangeMenu), keyEquivalent: "")
		previous.target = self
		menu.addItem(previous)
		return menu
	}

	@objc private func nextChangeMenu() { nextChange() }
	@objc private func previousChangeMenu() { previousChange() }

	// MARK: - For a driven run

	var changeSaid: String {
		guard let current = currentChange else { return diff.changes.isEmpty ? "No changes" : "Change –" }
		return "Change \(current + 1) of \(diff.changes.count)"
	}

	var reportForTesting: String {
		var lines = [changeSaid, diff.counts.said, "rows \(shown.count), wrap \(wrapsLines ? "on" : "off")"]
		let folds = shown.compactMap { entry -> String? in
			if case .fold(let rows) = entry { return "\(rows.count) Unchanged Lines" } else { return nil }
		}
		if !folds.isEmpty { lines.append("folds: " + folds.joined(separator: ", ")) }
		lines.append("selection: " + textRun.said)
		if let text = copiedText { lines.append("copied: " + text.replacingOccurrences(of: "\n", with: "⏎")) }
		return lines.joined(separator: "\n")
	}
}

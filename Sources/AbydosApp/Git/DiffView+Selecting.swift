import AppKit
import AbydosKit

/// Where a character is in the diff, what a drag selects, and what gets copied.
extension DiffView {
	// MARK: - Where a character is

	/// Where a row's text begins, before its marker: the inset, the gutter the
	/// selection bar is drawn in, and the two number columns.
	var textX: CGFloat { Self.horizontalInset + Self.gutterWidth + numberWidth * 2 }

	/// Where the right-hand half of a side-by-side row begins, and the rule
	/// between the two.
	var pairMiddle: CGFloat { (bounds.width / 2).rounded() }

	/// The left edge of one half of a side-by-side row.
	///
	/// **One place says it**, because the drawing and the hit test have to
	/// agree about where a half begins: a highlight drawn from one number and
	/// hit-tested against another is a selection landing on the other file.
	func pairMinX(_ column: Column) -> CGFloat { column == .left ? 0 : pairMiddle + 1 }

	/// The bold face, for the two rows that are drawn in it.
	var boldFont: NSFont {
		NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
	}

	/// What a row *says*, with none of the diff's furniture on it — no number,
	/// no `+`/`-` marker, no gutter, and none of the emoji that marks a remark.
	///
	/// **This is the rule about what gets copied, and it lives here** so that
	/// drawing, hit-testing and copying cannot disagree about what a row's text
	/// is. The reason to take code out of a diff is to paste it somewhere that
	/// expects code, where a leading `+` makes every line wrong; and it is what
	/// makes the two arrangements copy the same characters, since side by side
	/// draws no marker at all.
	func text(ofRow index: Int, in column: Column = .only) -> String {
		guard rows.indices.contains(index) else { return "" }
		switch rows[index] {
		case let .header(text):        return text
		case let .scope(text):         return text
		case let .hunkHeader(_, text): return text
		case let .comment(_, text, _): return text
		case let .line(_, line, _, _): return line.text
		case let .pair(left, right):
			// The right-hand side unless the left was asked for: it is the side
			// that still exists, the same reading `lineIndex(atRow:)` makes.
			guard column == .left else { return right?.line.text ?? "" }
			return left?.line.text ?? ""
		}
	}

	/// Where that text is drawn from, which is where its highlight starts and
	/// where a pointer's x is measured against.
	///
	/// **The marker's measured width, not a column guessed off the font.** A
	/// line is drawn as a marker at `textX` and its text after it, and the
	/// expression that puts the text there used to live inside `draw(row:)` —
	/// so a highlight drawn from `textX` sat one marker-width to the left of the
	/// glyphs it was meant to be behind.
	func textOrigin(ofRow index: Int, in column: Column = .only) -> CGFloat {
		guard rows.indices.contains(index) else { return textX }
		switch rows[index] {
		case let .line(_, line, _, _):
			guard !line.marker.isEmpty else { return textX }
			return textX + line.marker.size(withAttributes: [.font: font]).width
		case let .comment(comment, _, isFirst):
			// ✍️ for one being written here, 💬 for one that has been said, and
			// three spaces for the rows under either.
			let prefix = isFirst ? (comment.isPending ? "✍️ " : "💬 ") : "   "
			return textX + prefix.size(withAttributes: [.font: isFirst ? boldFont : font]).width
		case .pair:
			return pairMinX(column) + Self.gutterWidth + numberWidth + Theme.current.scaled(6)
		default:
			return textX
		}
	}

	/// The face a row's text is drawn in, and therefore the one it is measured
	/// in: a hunk header and the heading of a remark are bold, and a bold row
	/// measured in the regular face puts the highlight short of the glyphs.
	private func face(ofRow index: Int) -> NSFont {
		guard rows.indices.contains(index) else { return font }
		switch rows[index] {
		case .hunkHeader:                 return boldFont
		case let .comment(_, _, isFirst): return isFirst ? boldFont : font
		default:                          return font
		}
	}

	/// What `DiffTextRun` is told a row is: what it says, the face it says it
	/// in, and where the saying starts. Set once, in `init`.
	///
	/// **One arrow out of the view and none back in.** The rule about what a
	/// row's text is lives above, in `text(ofRow:in:)`, and the arithmetic that
	/// turns a point into an offset in it lives in the collaborator — so
	/// drawing, hit-testing and copying cannot come to disagree about where a
	/// character is.
	func describeRows() {
		textRun.textAt = { [weak self] row, column in
			self?.text(ofRow: row, in: column) ?? ""
		}
		textRun.rowAt = { [weak self] row, column in
			guard let self, self.rows.indices.contains(row) else {
				return DiffTextRun.Row(text: "", font: self?.font ?? .systemFont(ofSize: 12), origin: 0)
			}
			return DiffTextRun.Row(
				text: self.text(ofRow: row, in: column),
				font: self.face(ofRow: row),
				origin: self.textOrigin(ofRow: row, in: column)
			)
		}
	}

	/// How far into a row's text a point is, in UTF-16 code units.
	func offset(at point: NSPoint, ofRow index: Int, in column: Column) -> Int {
		textRun.offset(atX: point.x, row: index, in: column)
	}

	/// What a point in the view is over, which is what decides which selection
	/// a press makes.
	enum Region: Equatable {
		/// The numbers and the gutter beside them: whole lines, the selection
		/// that stages, discards, stashes and carries a remark.
		case numbers(row: Int, column: Column)
		/// The code itself: characters. The marker belongs here at offset 0,
		/// which is what a press on any text does — nothing until it moves.
		case text(row: Int, column: Column)
		/// A hunk header, which takes its whole hunk however it is pressed.
		case header(row: Int)
		/// Past the last row.
		case none
	}

	/// Off the same x boundaries the drawing uses, in both arrangements.
	func region(at point: NSPoint) -> Region {
		guard let index = row(at: point) else { return .none }
		if case .hunkHeader = rows[index] { return .header(row: index) }
		guard case .pair = rows[index] else {
			// One column. Everything left of the code is the numbers, the
			// gutter included — it is where the selection bar for a line is
			// drawn, so it belongs with the lines.
			return point.x < textX
				? .numbers(row: index, column: .only)
				: .text(row: index, column: .only)
		}
		let column: Column = point.x < pairMiddle ? .left : .right
		return point.x < textOrigin(ofRow: index, in: column)
			? .numbers(row: index, column: column)
			: .text(row: index, column: column)
	}

	/// The row a point is on, brought inside the diff.
	///
	/// A drag runs past the last row — that is what autoscroll is for — and a
	/// selection that stopped answering there would stop at whatever row was
	/// last under the pointer.
	func clampedRow(at point: NSPoint) -> Int? {
		guard let last = rows.indices.last else { return nil }
		let top = Theme.current.scaled(8)
		let index = Int((point.y - top) / lineHeight)
		return min(max(0, index), last)
	}

	/// Whether the keyboard is here, which is what a selection is drawn from.
	///
	/// Asked of the window on each draw rather than kept, for the reason
	/// `CodeView` gives: AppKit posts nothing when the first responder changes.
	var hasKeyboard: Bool { window?.firstResponder === self }

	// MARK: - Selection

	var hasSelection: Bool { !selection.isEmpty }
	var selectedLines: Set<Int> { selection }

	/// Whether a run of characters is selected — which is a different question
	/// from `hasSelection`, and the one *Copy* is offered over.
	var hasTextSelection: Bool { !textRun.isEmpty }

	/// ⌘A takes all of the diff's text, which is what it means in every other
	/// view in this window.
	///
	/// **It used to select every line that could be staged**, and nothing
	/// outside this file invoked it: no menu item targets it and no driven run
	/// reached it. Staging everything is still the file row's *Stage*, and a
	/// hunk is still its header.
	override func selectAll(_ sender: Any?) {
		guard let last = rows.indices.last else { return }
		// Side by side, the new side — the one that still exists, and the one a
		// reader means by "the file".
		textRun.takeEverything(through: last, in: isSideBySide ? .right : .only)
		tookText()
	}

	func clearSelection() {
		selection = []
		anchorRow = nil
		textRun.clear()
		needsDisplay = true
	}

	/// Selects every changed line in a hunk, for "stage this hunk".
	func selectHunk(_ hunkIndex: Int) {
		setLineSelection(Set(patch.indices(inHunk: hunkIndex)))
	}

	/// Whole lines, and nothing else selected.
	///
	/// **The two selections are mutually exclusive and the last gesture wins.**
	/// One is a set of `GitPatch` indices with a `+`/`-` meaning and the other a
	/// pair of points, and the staging path is untouched by any of this: the
	/// only thing that changed for it is which pixels fill the set.
	func setLineSelection(_ lines: Set<Int>) {
		selection = lines
		textRun.clear()
		needsDisplay = true
	}

	/// A run of characters was just taken, so the line selection goes.
	private func tookText() {
		selection = []
		anchorRow = nil
		needsDisplay = true
	}

	/// A remark, all of its rows, the way a click on one takes it.
	func selectComment(_ comment: Comment, rows block: ClosedRange<Int>) {
		selectedComment = (comment, block)
		selection = []
		anchorRow = nil
		textRun.clear()
		needsDisplay = true
	}

	func row(at point: NSPoint) -> Int? {
		let top = Theme.current.scaled(8)
		let index = Int((point.y - top) / lineHeight)
		return rows.indices.contains(index) ? index : nil
	}

	func lineIndex(atRow row: Int) -> Int? {
		guard rows.indices.contains(row) else { return nil }
		// Side by side, a row is two lines and the right-hand one is the one a
		// remark or a stage is about — it is the side that still exists.
		if case let .pair(left, right) = rows[row] {
			guard let side = right ?? left else { return nil }
			guard side.line.isSelectable || (isReadOnly && right != nil) else { return nil }
			return side.index
		}
		guard case let .line(index, line, _, new) = rows[row] else {
			return nil
		}
		// **Staging can only touch a changed line; a remark can touch any line
		// that exists.** In a read-only diff there is nothing to stage, so
		// letting the selection cover context is free — and it is what makes
		// "comment on these five lines" possible, three of which are usually
		// context.
		guard line.isSelectable || (isReadOnly && new != nil) else { return nil }
		return index
	}

	/// The new-side numbers the selection covers, in the order they are drawn.
	var selectedNewLines: [Int] {
		rows.compactMap { row in
			switch row {
			case let .line(index, _, _, new):
				guard let new, selection.contains(index) else { return nil }
				return new
			case let .pair(_, right):
				guard let right, selection.contains(right.index) else { return nil }
				return right.number
			default:
				return nil
			}
		}
	}

	/// The new-side number a row carries, in either arrangement.
	func newNumber(atRow row: Int) -> Int? {
		guard rows.indices.contains(row) else { return nil }
		switch rows[row] {
		case let .line(_, _, _, new): return new
		case let .pair(_, right):     return right?.number
		default:                      return nil
		}
	}

	/// Which rows one remark occupies, given the row its heading is on.
	func commentBlock(startingAt row: Int) -> ClosedRange<Int>? {
		guard case let .comment(comment, _, isFirst) = rows[row], isFirst else { return nil }
		var last = row
		while last + 1 < rows.count,
		      case let .comment(next, _, isNext) = rows[last + 1],
		      !isNext, next == comment {
			last += 1
		}
		return row...last
	}

	/// The remark a row belongs to, whichever of its rows was clicked.
	func comment(atRow row: Int) -> (Comment, ClosedRange<Int>)? {
		guard rows.indices.contains(row), case .comment = rows[row] else { return nil }
		var first = row
		while first > 0 {
			if case let .comment(_, _, isFirst) = rows[first], isFirst { break }
			first -= 1
		}
		guard case let .comment(comment, _, isFirst) = rows[first], isFirst,
		      let block = commentBlock(startingAt: first)
		else { return nil }
		return (comment, block)
	}

	/// **Where the press landed decides which selection it makes.** The numbers
	/// take lines, the way a forge does it; the code takes characters, because
	/// the gesture over the code is needed for the code and there is one
	/// gesture. A hunk header — which is how most staging is actually done —
	/// does not move at all.
	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let point = convert(event.locationInWindow, from: nil)

		switch region(at: point) {
		case .none:
			return
		case let .header(row):
			selectedComment = nil
			// A click on a hunk header takes the whole hunk, which is the
			// common case — line-by-line is for when a hunk mixes two changes.
			guard case let .hunkHeader(hunkIndex, _) = rows[row] else { return }
			selectHunk(hunkIndex)
			anchorRow = row
		case let .numbers(row, _):
			pressLine(row: row, with: event)
		case let .text(row, column):
			pressText(row: row, in: column, at: point, with: event)
		}
	}

	/// The number column: whole lines, with shift and ⌘ behaving as they always
	/// have.
	func pressLine(row: Int, with event: NSEvent) {
		pressLine(
			row: row,
			shift: event.modifierFlags.contains(.shift),
			command: event.modifierFlags.contains(.command)
		)
	}

	/// The press itself, in the terms the gesture is made of — so a driven run
	/// makes the same press a pointer does.
	func pressLine(row: Int, shift: Bool, command: Bool) {
		// A remark has no numbers beside it, and a press anywhere on one takes
		// the remark: all of its rows, because a paragraph is one thing.
		if let (comment, block) = comment(atRow: row) {
			selectComment(comment, rows: block)
			return
		}
		selectedComment = nil
		guard let index = lineIndex(atRow: row) else { return }

		var updated = selection
		if shift, let anchor = anchorRow {
			// Range from the anchor, skipping context that falls between.
			for position in min(anchor, row)...max(anchor, row) {
				if let candidate = lineIndex(atRow: position) { updated.insert(candidate) }
			}
		} else if command {
			if updated.contains(index) { updated.remove(index) } else { updated.insert(index) }
			anchorRow = row
		} else {
			updated = [index]
			anchorRow = row
		}
		setLineSelection(updated)
	}

	/// The code: characters, from where the press landed.
	///
	/// A press with nothing dragged puts the caretless selection away — a click
	/// is how a selection is dismissed, not how one is made — and the two
	/// gestures a reader tries within the minute of discovering the drag are
	/// here too.
	func pressText(row: Int, in column: Column, at point: NSPoint, with event: NSEvent) {
		pressText(
			row: row,
			in: column,
			offset: offset(at: point, ofRow: row, in: column),
			clicks: event.clickCount,
			shift: event.modifierFlags.contains(.shift)
		)
	}

	/// The press itself, in the terms the gesture is made of rather than in
	/// AppKit's — so a driven run makes the same press a pointer does.
	func pressText(row: Int, in column: Column, offset: Int, clicks: Int, shift: Bool) {
		// A remark is one thing to *click* on and text to *drag over*: the click
		// takes the remark, and a drag from it hands the rows to the text
		// selection instead — see `mouseDragged`.
		if clicks == 1, !shift, let (comment, block) = comment(atRow: row) {
			selectComment(comment, rows: block)
		} else if clicks == 1 {
			selectedComment = nil
		}

		switch clicks {
		case 2:
			textRun.takeWord(row: row, offset: offset, in: column)
		case 3:
			textRun.takeRow(row, in: column)
		default:
			// Shift extends from where the gesture began, and only within the
			// half it began in.
			if shift, !textRun.isEmpty, textRun.column == column {
				textRun.extend(toRow: row, offset: offset)
			} else {
				textRun.press(row: row, offset: offset, in: column)
			}
		}
		tookText()
	}

	override func mouseDragged(with event: NSEvent) {
		// A selection that stops at the bottom of the visible rows is a
		// selection that cannot cover a hunk, and this view is inside a scroll
		// view in all five places it is used.
		autoscroll(with: event)
		let point = convert(event.locationInWindow, from: nil)

		if textRun.isPressed {
			guard let row = clampedRow(at: point) else { return }
			// **The half is carried through the drag**, which is how "a
			// selection belongs to one side" is enforced rather than checked
			// afterwards: a pointer past the divider goes on extending the side
			// it started on.
			textRun.extend(
				toRow: row, offset: offset(at: point, ofRow: row, in: textRun.column)
			)
			// A drag over a remark's rows is a selection of its text rather
			// than of the remark.
			if !textRun.isEmpty { selectedComment = nil }
			needsDisplay = true
			return
		}

		guard let anchor = anchorRow, let row = row(at: point) else { return }

		var updated: Set<Int> = []
		for position in min(anchor, row)...max(anchor, row) {
			if let index = lineIndex(atRow: position) { updated.insert(index) }
		}
		guard updated != selection else { return }
		selection = updated
		needsDisplay = true
	}

	/// The selection greys when the keyboard leaves and lifts when it comes
	/// back, and AppKit posts nothing when the first responder changes.
	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		// Return applies, which is the whole point of having a selection here.
		if event.keyCode == 36 || event.keyCode == 76, hasSelection {
			onApplySelection?(selection)
			return
		}
		super.keyDown(with: event)
	}

	// MARK: - Copying

	/// What ⌘C would put on the clipboard, and nothing at all where nothing is
	/// selected.
	///
	/// **Reads `rows`, not the layout.** No line is measured and nothing
	/// off-screen is laid out, so ⌘A then ⌘C over a five-thousand-row diff costs
	/// a string join — which is why the text comes from `GitPatch` by way of
	/// `text(ofRow:in:)` rather than from anything the drawing built.
	var copiedText: String? {
		if let copied = textRun.copiedText { return copied }

		// **A run of lines selected and nothing selected as text is copied as
		// those lines.** A selection that is visibly on the screen and copies
		// nothing is the complaint this answers, and which of the two selections
		// it is does not matter.
		guard !selection.isEmpty else { return nil }
		let lines = rows.compactMap { row -> String? in
			switch row {
			case let .line(index, line, _, _):
				return selection.contains(index) ? line.text : nil
			case let .pair(left, right):
				if let right, selection.contains(right.index) { return right.line.text }
				if let left, selection.contains(left.index) { return left.line.text }
				return nil
			default:
				return nil
			}
		}
		return lines.isEmpty ? nil : lines.joined(separator: "\n")
	}

	/// ⌘C, and *Copy* wherever it is pressed from.
	///
	/// The Edit menu's *Copy* is `NSText.copy(_:)` with no target, so it walks
	/// the responder chain and arrives here: this is the whole of the keyboard
	/// plumbing.
	@objc func copy(_ sender: Any?) {
		guard let copiedText else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(copiedText, forType: .string)
	}


}

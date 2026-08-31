import AppKit
import AbydosKit

/// The run of characters selected in a diff: where it begins, where the pointer
/// has taken it, and which half of a side-by-side row it belongs to.
///
/// **A collaborator rather than three more fields on the view.** The selection
/// is a piece of state with rules of its own — ends that order themselves, one
/// half of a row for the whole of its life, nothing at all until a press
/// happens — and the lines it measures are a cache with exactly the same
/// lifetime. Keeping them together here is what lets `DiffView` stay a view: it
/// owns the rows and how they are drawn, and this owns where a character in one
/// of them is.
///
/// It holds no rows. It is *given* the row it is asked about — what the row
/// says, the face it says it in, and where the saying starts — through `rowAt`,
/// which the view sets once. So the rule about what a row's text is lives in one
/// place, in the view, and cannot be disagreed with from here.
@MainActor
final class DiffTextRun {
	/// Which text column a point, a selection or a measured line belongs to.
	///
	/// Unified there is one; side by side there are two, and a selection belongs
	/// to exactly one of them from the press to the release. A selection
	/// covering both halves would copy two versions of a file interleaved row by
	/// row, which is not something anybody means to select and is not
	/// representable as text at all.
	enum Column: Hashable {
		/// The one column of a unified row, and of every row drawn the width of
		/// the view: a header, a scope rule, a hunk header, a remark.
		case only
		case left
		case right

		/// How a report names it.
		var said: String {
			switch self {
			case .only:  return ""
			case .left:  return ", left"
			case .right: return ", right"
			}
		}
	}

	/// A row as this needs to see it.
	struct Row {
		/// What the row says, with none of the diff's furniture on it.
		let text: String
		/// The face it is drawn in, which is what its width is measured with: a
		/// bold row measured in the regular face puts a highlight short of the
		/// glyphs.
		let font: NSFont
		/// Where that text is drawn from, measured from the view's left edge —
		/// the marker's own width included.
		let origin: CGFloat

		init(text: String, font: NSFont, origin: CGFloat) {
			self.text = text
			self.font = font
			self.origin = origin
		}
	}

	/// How to see a row, for the two questions that need it laid out: where a
	/// point in it is, and where an offset in it is. Set once, by the view that
	/// owns the rows.
	var rowAt: (Int, Column) -> Row = { _, _ in
		Row(text: "", font: .monospacedSystemFont(ofSize: 12, weight: .regular), origin: 0)
	}

	/// What a row *says*, which is a cheaper question and the only one copying
	/// asks.
	///
	/// **Separate from `rowAt` because the origin costs a measurement**: a
	/// line's text is drawn after its marker, and the marker's width comes from
	/// the font. Asking for it once per row turned ⌘A then ⌘C over a
	/// five-thousand-row diff from a string join into five thousand text
	/// measurements — 104 ms against under one, measured — for a number no copy
	/// has any use for.
	var textAt: (Int, Column) -> String = { _, _ in "" }

	/// Where the gesture began. Kept rather than the earlier end, because a drag
	/// upwards and a shift-click both extend from where it *began*.
	private(set) var anchor = DiffTextPoint(row: 0, offset: 0)
	private(set) var head = DiffTextPoint(row: 0, offset: 0)
	private(set) var column: Column = .only
	/// Whether a press has happened at all. A press with nothing dragged is a
	/// selection of no characters, which is how a click puts one away.
	private(set) var isPressed = false

	private struct Measured: Hashable {
		let row: Int
		let column: Column
	}

	private var measured: [Measured: CTLine] = [:]

	/// Whether anything is selected. A press with nothing dragged is not.
	var isEmpty: Bool { !isPressed || anchor == head }
	var start: DiffTextPoint { min(anchor, head) }
	var end: DiffTextPoint { max(anchor, head) }

	// MARK: - The gesture

	/// A press: a run of no characters, there.
	func press(row: Int, offset: Int, in column: Column) {
		anchor = DiffTextPoint(row: row, offset: offset)
		head = anchor
		self.column = column
		isPressed = true
	}

	/// The rest of a drag, and what shift does: the head moves and the half does
	/// not.
	func extend(toRow row: Int, offset: Int) {
		guard isPressed else { return }
		head = DiffTextPoint(row: row, offset: offset)
	}

	/// The word under an offset, for a double-click.
	///
	/// Word characters are letters, digits and `_`, which is what an identifier
	/// in code is made of. A press on anything else takes that one character
	/// rather than nothing at all, so the gesture always answers.
	func takeWord(row: Int, offset: Int, in column: Column) {
		let units = Array(textAt(row, column).utf16)
		guard !units.isEmpty else { return press(row: row, offset: offset, in: column) }

		func isWord(_ unit: UInt16) -> Bool {
			guard let scalar = Unicode.Scalar(unit) else { return false }
			return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
		}

		var lower = min(max(0, offset), units.count - 1)
		// A hit test answers with the boundary the pointer is nearest, so a
		// press on the right-hand half of a word's last letter arrives just
		// past it.
		if !isWord(units[lower]), lower > 0, isWord(units[lower - 1]) { lower -= 1 }
		var upper = lower
		if isWord(units[lower]) {
			while lower > 0, isWord(units[lower - 1]) { lower -= 1 }
			while upper + 1 < units.count, isWord(units[upper + 1]) { upper += 1 }
		}
		press(row: row, offset: lower, in: column)
		extend(toRow: row, offset: upper + 1)
	}

	/// The whole of a row's text, for a triple-click.
	func takeRow(_ row: Int, in column: Column) {
		press(row: row, offset: 0, in: column)
		extend(toRow: row, offset: textAt(row, column).utf16.count)
	}

	/// Every row, for ⌘A.
	func takeEverything(through lastRow: Int, in column: Column) {
		press(row: 0, offset: 0, in: column)
		extend(toRow: lastRow, offset: textAt(lastRow, column).utf16.count)
	}

	/// Nothing selected, and no press outstanding.
	func clear() {
		isPressed = false
		anchor = DiffTextPoint(row: 0, offset: 0)
		head = anchor
	}

	/// **The rows are about to be different rows.** A position is a place in
	/// *that* list of rows and a measured line is the width of one of them;
	/// neither survives the list being rebuilt, or the font changing under it.
	func forget() {
		clear()
		measured = [:]
	}

	/// How many rows have been measured — a number a driven run can watch go
	/// back to nothing.
	var measuredRows: Int { measured.count }

	// MARK: - Where a character is

	/// How far into a row's text a point is, in UTF-16 code units.
	///
	/// **Core Text rather than the terminal's arithmetic** — `column = (x -
	/// inset) / cellWidth`, which would be cheaper. The terminal draws a grid
	/// and a diff does not: a row is a marker of measured width followed by
	/// text, a hunk header is bold, a remark carries an emoji, and the code has
	/// tabs in it and the occasional glyph the monospace face does not have and
	/// a fallback supplies. Every one of those puts the arithmetic's answer a
	/// few pixels — and eventually a character — from where the glyph is, which
	/// is the terminal's own old bug and no reason to import it.
	func offset(atX x: CGFloat, row: Int, in column: Column) -> Int {
		let seen = rowAt(row, column)
		let length = seen.text.utf16.count
		guard length > 0, let line = line(row: row, in: column) else { return 0 }
		let local = x - seen.origin
		guard local > 0 else { return 0 }
		let found = CTLineGetStringIndexForPosition(line, CGPoint(x: local, y: 0))
		guard found != kCFNotFound else { return length }
		return min(max(0, found), length)
	}

	/// Where an offset into a row's text sits, measured from the view's left
	/// edge — the answer the highlight is drawn from.
	func x(ofOffset offset: Int, row: Int, in column: Column) -> CGFloat {
		let seen = rowAt(row, column)
		guard let line = line(row: row, in: column) else { return seen.origin }
		return seen.origin + CTLineGetOffsetForStringIndex(line, offset, nil)
	}

	/// What the selection covers on one row, in UTF-16 offsets — nothing where
	/// it does not reach that row.
	///
	/// The first row is cut at its offset, the last at its own, and everything
	/// between is whole; an offset past the end of the row it names is the end
	/// of that row, because a row can have been redrawn shorter since.
	func covered(row: Int) -> Range<Int>? {
		guard !isEmpty, row >= start.row, row <= end.row else { return nil }
		let length = textAt(row, column).utf16.count
		let from = row == start.row ? min(start.offset, length) : 0
		let to = row == end.row ? min(end.offset, length) : length
		guard to >= from else { return nil }
		return from..<to
	}

	/// The row's text, laid out, kept until the rows are rebuilt.
	///
	/// The colours are left off: a colour does not move a glyph, and the font is
	/// the whole of what an advance depends on here.
	private func line(row: Int, in column: Column) -> CTLine? {
		let key = Measured(row: row, column: column)
		if let line = measured[key] { return line }
		let seen = rowAt(row, column)
		let attributed = NSAttributedString(string: seen.text, attributes: [.font: seen.font])
		let line = CTLineCreateWithAttributedString(attributed)
		measured[key] = line
		return line
	}

	// MARK: - What it copies

	/// The characters the selection covers, and nothing where it covers none.
	///
	/// **Reads the rows, not the layout.** No line is measured and nothing
	/// off-screen is laid out, so ⌘A then ⌘C over a five-thousand-row diff costs
	/// a string join — see `DiffTextSpan`, which is where the cutting and the
	/// joining are claimed in a test.
	var copiedText: String? {
		guard !isEmpty else { return nil }
		return DiffTextSpan(
			from: start,
			to: end,
			rows: (start.row...end.row).map { textAt($0, column) }
		).text
	}

	/// Where it is, for a report: rows and offsets, so a driven run can see the
	/// drag land rather than only what it copied.
	var said: String {
		guard !isEmpty else { return "no text selected" }
		return "\(start.row).\(start.offset)-\(end.row).\(end.offset)" + column.said
	}
}

import Foundation

/// What ↑, ↓, Page Up and Page Down do to the caret's row.
///
/// The rows are *visual* rows — what folding and soft wrap leave on screen —
/// because that is what an arrow key moves by; the view turns a row back into an
/// offset, and that part needs a laid-out line and cannot live here.
///
/// The interesting case is the one this was written for. Asked to go up from the
/// first row, or down from the last, an editor that clamps the row lands back
/// where it started and the keystroke does nothing at all. Every Cocoa text view
/// — TextEdit, Xcode, Notes — takes the caret to the edge of the document
/// instead, and with Shift held takes the selection with it. So running off the
/// end is an answer of its own rather than a row that gets clamped.
public enum VerticalMotion {
	/// Where a vertical keystroke should put the caret.
	public enum Outcome: Equatable {
		/// Land on this visual row, at the column the caret is trying to keep.
		case row(Int)
		/// Offset zero: there was no row above.
		case startOfDocument
		/// The last offset in the document: there was no row below.
		case endOfDocument
		/// Nothing to do, which is only ever a delta of zero.
		case stay
	}

	/// - Parameters:
	///   - row: the visual row the caret is on now.
	///   - delta: rows to move, negative for up. Page Up and Page Down come
	///     through here too, with a delta of a screenful.
	///   - rows: how many visual rows the document has.
	///
	/// A page that overshoots the top gives the start of the document rather
	/// than the first row, which is again what Cocoa does: Page Up in a file
	/// shorter than the window puts the caret at offset zero, not at column
	/// whatever of line one.
	public static func outcome(from row: Int, by delta: Int, rows: Int) -> Outcome {
		guard delta != 0 else { return .stay }
		let target = row + delta
		if target < 0 { return .startOfDocument }
		// An empty document still has one row to be on; anything less is a
		// layout that has not been built yet, and running off it is safer than
		// asking for row -1.
		if target > max(0, rows - 1) { return .endOfDocument }
		return .row(target)
	}
}

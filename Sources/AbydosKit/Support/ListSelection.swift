import Foundation

/// Moving a selection through a list that has rows nobody can select.
///
/// The palette's list is headers and entries mixed together, so "down" is not
/// "the next row" — it is the next row somebody can choose, and a page is a
/// number of *those* rather than a number of rows.
///
/// Kept apart from the view because the two interesting cases are at the edges:
/// an arrow at the end of the list stays where it is, and a page at the end
/// goes to the last entry rather than nowhere. That is the difference between a
/// key that feels stuck and one that feels finished.
public enum ListSelection {
	/// Where the selection lands after moving by `steps` selectable rows, or
	/// nil when there is nowhere to go.
	///
	/// - Parameters:
	///   - current: the selected row, or a negative number for none.
	///   - steps: how many selectable rows to move, negative for upwards.
	///   - count: how many rows there are.
	///   - isSelectable: whether a row can be chosen.
	public static func move(
		from current: Int,
		by steps: Int,
		count: Int,
		isSelectable: (Int) -> Bool
	) -> Int? {
		guard count > 0, steps != 0 else { return nil }

		let forward = steps > 0
		var index = current
		var remaining = abs(steps)
		var lastFound: Int?

		while remaining > 0 {
			index += forward ? 1 : -1
			guard index >= 0, index < count else { break }
			guard isSelectable(index) else { continue }
			lastFound = index
			remaining -= 1
		}

		// A page that runs off the end lands on the last entry, which is what a
		// page key does everywhere; a page with nothing at all in front of it
		// stays where it is.
		return lastFound
	}

	/// How many rows a page is, for a list of this height with rows this tall.
	///
	/// One short of what fits, so the row somebody was looking at is still on
	/// screen after the page — the overlap is what makes it possible to read
	/// down a long list without losing the place.
	public static func pageSize(viewportHeight: CGFloat, rowHeight: CGFloat) -> Int {
		guard rowHeight > 0 else { return 1 }
		return max(1, Int(viewportHeight / rowHeight) - 1)
	}
}

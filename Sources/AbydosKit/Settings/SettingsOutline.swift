import Foundation

/// Which rows of a settings sidebar are showing, given what is folded away.
///
/// The list is a table over a flattened array of sections, each carrying how
/// deep it sits, and the row draws its own indentation. Folding is therefore a
/// filter on that array rather than a different kind of view: an outline view
/// would replace a list that works and reads for two levels of nesting and
/// eight tools.
///
/// Depths only, so this is arithmetic rather than anything about settings —
/// which is why it can be tested without a window.
public enum SettingsOutline {
	/// Whether the row at this index has anything under it.
	public static func hasChildren(depths: [Int], at index: Int) -> Bool {
		guard depths.indices.contains(index), index + 1 < depths.count else { return false }
		return depths[index + 1] > depths[index]
	}

	/// The rows the table shows, as indices into the flattened list.
	///
	/// Collapsing a row hides everything under it until the depth comes back
	/// up, which folds a collapsed row's own children away with it whether or
	/// not they were collapsed themselves.
	public static func visible(depths: [Int], collapsed: Set<Int>) -> [Int] {
		var shown: [Int] = []
		var hidingBelow: Int?
		for (index, depth) in depths.enumerated() {
			if let limit = hidingBelow {
				if depth > limit { continue }
				hidingBelow = nil
			}
			shown.append(index)
			if collapsed.contains(index) { hidingBelow = depth }
		}
		return shown
	}

	/// The row this one sits under: the nearest one before it that is shallower.
	public static func parent(depths: [Int], of index: Int) -> Int? {
		guard depths.indices.contains(index), depths[index] > 0 else { return nil }
		for candidate in stride(from: index - 1, through: 0, by: -1)
		where depths[candidate] < depths[index] {
			return candidate
		}
		return nil
	}

	/// Everything that has to be open for this row to be on screen.
	public static func ancestors(depths: [Int], of index: Int) -> Set<Int> {
		var found: Set<Int> = []
		var current = index
		while let above = parent(depths: depths, of: current) {
			found.insert(above)
			current = above
		}
		return found
	}

	// MARK: - The arrow keys

	/// Which way a sideways arrow key goes.
	public enum Fold: Sendable {
		/// Right: open what is folded, and step into what is already open.
		case open
		/// Left: fold what is open, and step out of what is not.
		case close
	}

	/// Where the list stands: what is folded away, and which row is selected.
	public struct FoldState: Equatable, Sendable {
		public var collapsed: Set<Int>
		public var selected: Int

		public init(collapsed: Set<Int>, selected: Int) {
			self.collapsed = collapsed
			self.selected = selected
		}
	}

	/// What Left or Right does, which is what `NSOutlineView` and the Finder do.
	///
	/// Right on a folded parent opens it and stays put; on an open parent it
	/// steps onto the first thing inside; on a leaf it does nothing. Left on an
	/// open parent folds it and stays put; on anything else — a child, or a
	/// parent that is already folded — it steps out to whatever the row sits
	/// under. Up and down are not here: those walk the rows that are showing,
	/// which is `visible(depths:collapsed:)` and the table's own business.
	///
	/// Returning the state rather than mutating one keeps this arithmetic, so
	/// the semantics above are settled by a test rather than by a window. A key
	/// that does nothing gives back exactly what it was given, which is how the
	/// view knows to leave the event alone.
	public static func fold(
		depths: [Int], collapsed: Set<Int>, selected: Int, _ key: Fold
	) -> FoldState {
		let unchanged = FoldState(collapsed: collapsed, selected: selected)
		guard depths.indices.contains(selected) else { return unchanged }
		let isParent = hasChildren(depths: depths, at: selected)

		switch key {
		case .open:
			guard isParent else { return unchanged }
			guard collapsed.contains(selected) else {
				// The first child is the next row along: `hasChildren` is true
				// only because that row is one deeper.
				return FoldState(collapsed: collapsed, selected: selected + 1)
			}
			return FoldState(collapsed: collapsed.subtracting([selected]), selected: selected)

		case .close:
			if isParent, !collapsed.contains(selected) {
				return FoldState(collapsed: collapsed.union([selected]), selected: selected)
			}
			guard let above = parent(depths: depths, of: selected) else { return unchanged }
			return FoldState(collapsed: collapsed, selected: above)
		}
	}
}

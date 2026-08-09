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
}

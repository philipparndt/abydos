import Foundation

/// What a tree has selected, carried across a rebuild as paths.
///
/// The project tree reloads on every filesystem event, and a reload replaces
/// every row: the indices afterwards mean nothing and the nodes are different
/// objects. So the selection is taken as paths beforehand and looked up again
/// after, which is the only thing that survives.
///
/// Singular is the trap. A build writes files for a minute and the tree
/// reloads over and over while it does; a restore that keeps the first path and
/// drops the rest shrinks a selection of five to one with nobody touching it,
/// and it looks like the selection was never made. That is the bug this exists
/// to have a test for.
public enum TreeSelection {
	/// The paths at the given rows, in the order the rows appear.
	///
	/// Tree order rather than the order they were clicked: it is what "copy the
	/// path of these" means, and it is what comes back after a reload anyway.
	public static func paths(rows: [Int], path: (Int) -> String?) -> [String] {
		rows.sorted().compactMap(path)
	}

	/// The rows those paths are at now.
	///
	/// A path the reload took away — trashed, renamed, or in a folder that
	/// collapsed — is dropped on its own rather than taking the rest of the
	/// selection with it. `row` answers a negative number for a path the tree
	/// no longer has, which is what `NSOutlineView.row(forItem:)` does.
	public static func rows(for paths: [String], row: (String) -> Int) -> [Int] {
		var seen = Set<Int>()
		var found: [Int] = []
		for path in paths {
			let index = row(path)
			guard index >= 0, seen.insert(index).inserted else { continue }
			found.append(index)
		}
		return found.sorted()
	}
}

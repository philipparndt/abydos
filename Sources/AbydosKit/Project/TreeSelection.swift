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

	/// Where the selection should go once these rows are deleted: the nearest
	/// row above them that is staying.
	///
	/// Deleting used to drop the selection at the top of the tree, which is a
	/// long way from where somebody was working and means the next keystroke
	/// acts on something they cannot see.
	///
	/// **Walking up the visible rows is the whole answer**, and it is why this
	/// is a loop rather than a walk through the tree. "The sibling above, or the
	/// parent when there is no sibling above" are the same movement in an
	/// outline view: the row above a folder's first child *is* that folder. One
	/// loop gives both, and gives the right answer for a selection with gaps in
	/// it, since it steps over anything else that is also going.
	///
	/// Nil when the first row itself was deleted and there is nothing above it.
	/// The selection lands at the top then — which is the behaviour being fixed,
	/// except that in that one case the top is genuinely where it belongs.
	public static func surviving(above doomed: Set<Int>, path: (Int) -> String?) -> String? {
		guard let first = doomed.min(), first > 0 else { return nil }
		for row in stride(from: first - 1, through: 0, by: -1) where !doomed.contains(row) {
			if let found = path(row) { return found }
		}
		return nil
	}

	/// Where the selection goes when nothing above it survives either.
	///
	/// **Above is the right answer until there is no above.** The row over the
	/// selection is usually its sibling or its parent, and both are still
	/// there after a stage. But a file that is the only thing in its folder
	/// takes the folder with it:
	///
	///     .vscode            ← empties, so it goes too
	///       launch.json      ← selected, and staged
	///     CLAUDE.md          ← what is left, and where the selection belongs
	///
	/// `surviving(above:)` answers `.vscode`, which is not there to be selected
	/// either, and walking up from it finds nothing. So the other direction is
	/// asked next: the first row *after* everything that is going.
	///
	/// Not merged into one function, because the order matters and a caller
	/// that could not see it would not know above is tried first.
	public static func surviving(below doomed: Set<Int>, rowCount: Int, path: (Int) -> String?) -> String? {
		guard let last = doomed.max() else { return nil }
		for row in (last + 1)..<max(last + 1, rowCount) where !doomed.contains(row) {
			if let found = path(row) { return found }
		}
		return nil
	}
}


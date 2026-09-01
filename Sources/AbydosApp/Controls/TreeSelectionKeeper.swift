import AppKit
import AbydosKit

/// Puts a tree's selection back after work that would lose it.
///
/// **The fault it exists for, in the words of the code that had it.** The
/// commit page answers an untracked directory's listing like this:
///
///     current.fill(with: rows)
///     self.refreshColumns(for: outline)
///     outline.reloadData()          // ← the selection dies here
///     outline.expandItem(current)
///
/// `reloadData()` clears an outline view's selection and nothing put it back,
/// so opening an untracked folder with → left it open with nothing selected —
/// and because the same call runs for every open untracked directory on every
/// filesystem event, a repository with one open was dropping the selection at
/// whatever rate something was writing to disk.
///
/// **And the other half, which is not the same fault.** Staging a file moves
/// its row out of the unstaged list, so a restore by path correctly finds
/// nothing — and then did nothing, because the restore returned early on a path
/// it could not find. A selection that goes away is survivable; a selection
/// that goes away *with nobody saying so* is why both of these were reported by
/// somebody watching rather than found by anybody reading.
///
/// So: take the paths, do the work, put them back — and where a path has gone,
/// land on the nearest surviving row above it and say in the log that it had
/// to. `TreeSelection` is the arithmetic underneath; this is the behaviour
/// around it that three panes had each written for themselves.
enum TreeSelectionKeeper {
	/// Runs `work` with the selection taken beforehand and put back after.
	///
	/// - Parameters:
	///   - outline: the tree whose selection is kept.
	///   - path: what a row is called — the handle that survives a reload.
	///   - row: where that name is now, or a negative number if nowhere.
	static func keepingSelection(
		in outline: NSOutlineView,
		path: (Int) -> String?,
		row: (String) -> Int,
		during work: () -> Void
	) {
		let held = TreeSelection.paths(rows: Array(outline.selectedRowIndexes), path: path)
		// Where the selection was, so a fallback can land near it rather than
		// at the top of a list somebody was reading the middle of.
		let wasAt = outline.selectedRowIndexes

		work()

		guard !held.isEmpty else { return }
		let found = TreeSelection.rows(for: held, row: row)
		if !found.isEmpty {
			outline.selectRowIndexes(IndexSet(found), byExtendingSelection: false)
			return
		}

		// Nothing came back. The rows were staged, unstaged, filtered away or
		// deleted — all of which are ordinary — so the selection goes to the
		// nearest row above where it was.
		let neighbour = TreeSelection.surviving(above: Set(wasAt)) { index in
			index < outline.numberOfRows ? path(index) : nil
		}
		guard let neighbour, case let index = row(neighbour), index >= 0 else {
			// The one case where the top is genuinely where it belongs: the
			// first row itself is what went.
			if outline.numberOfRows > 0 {
				outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			}
			NSLog("tree: the selection %@ has gone and there was nothing above it", held.first ?? "")
			return
		}
		outline.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
		// Said, because this is the moment the two reports were made at and
		// neither left a trace. The next one names itself.
		NSLog("tree: %@ has gone; the selection fell back to %@", held.first ?? "", neighbour)
	}
}

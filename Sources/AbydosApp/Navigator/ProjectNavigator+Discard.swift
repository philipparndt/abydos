import AppKit
import AbydosKit

/// *Discard Changes* over the tree's rows: the changes pane's question, the
/// pane's arithmetic and the pane's insurance, reached from the row somebody
/// was looking at.
///
/// Reported 2026-09-10 with the menu open on a changed file: Blame, Open as
/// Hex, Compare three ways, and nothing that put the file back the way the
/// last commit had it. The verb existed one pane over. What the tree adds is
/// nothing; what it borrows is everything.
extension ProjectNavigatorViewController {
	/// What discarding the rows under the menu would take, or nil when the
	/// item should not be offered.
	///
	/// Asked of the repository's last status read — the porcelain the colours
	/// come from, kept the pane's way in `GitRepository.lastKnownWorkingCopy` —
	/// so a folder's count is the number of files git will act on, and a file
	/// whose only change is staged is refused exactly as the pane refuses it.
	/// Synchronous, because it is asked while a menu is opening.
	///
	/// Off a repository there is nothing to ask. The root is left out: the pane
	/// never hands git "the lot", and a row that would put back every file in
	/// the checkout is not what anybody right-clicking the project's name meant.
	var discardTarget: GitDiscard.Target? {
		guard let project, let git = project.git else { return nil }
		let nodes = contextNodes.filter { $0 !== rootNode }
		guard !nodes.isEmpty else { return nil }

		// Estate-relative, which is what a `GitChange` carries: a file inside a
		// submodule is `sub/file` to the estate, and `grouped` later hands it
		// to the repository that owns it.
		var isFolder: [String: Bool] = [:]
		var paths: [String] = []
		for node in nodes {
			guard let place = project.place(of: node.url) else { continue }
			paths.append(place.estatePath)
			isFolder[place.estatePath] = node.isDirectory
		}
		return GitDiscard.target(over: paths, unstaged: git.lastKnownWorkingCopy.unstaged) { isFolder[$0] }
	}

	/// Asks, and only then hands the work to the window to throw away.
	///
	/// Asked again rather than kept from `menuNeedsUpdate`: the selection is
	/// the same, and a target held across the menu being open would be a
	/// statement about a working copy a build may have changed since.
	@objc func contextDiscard() {
		guard let target = discardTarget else { return }
		DestructiveAsk.askToDiscard(target, over: view.window) { [weak self] in
			self?.onDiscard?(target)
		}
	}

	// MARK: - Driving

	/// What the item would say over the selected rows and what the sheet would
	/// ask, as lines — the changes pane's own report, for the tree.
	///
	/// A screenshot of a menu cannot be asked whether the number in it is
	/// right, and "not offered" over an unchanged file or a conflict is the
	/// claim hardest of all to see in a picture.
	func discardWordingForTesting() -> String {
		let rows = selectedPathsForTesting().joined(separator: " ")
		guard let target = discardTarget else { return "discard \(rows): not offered" }
		return [
			"discard \(rows)",
			"  menu: " + target.menuTitle,
			"  asks: " + target.question,
			"  says: " + target.explanation,
			"  button: " + target.buttonTitle,
			"  git: " + target.paths.joined(separator: " "),
		].joined(separator: "\n")
	}
}

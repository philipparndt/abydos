import AppKit
import AbydosKit

/// Which repository a file's git verbs are aimed at, and the two verbs that
/// ask.
///
/// **Its own file because it is its own subject**, the way
/// `MainWindowController+Trust` is: the sidebar file is where the tools are
/// installed and torn down, and *which repository owns this file* is a question
/// about the estate that Compare, History, the diff tab and the change marks
/// all have to answer the same way. Keeping it in one place is what stops the
/// next verb answering it differently — which is exactly how Compare came to
/// ask the superproject about a file it holds only as a gitlink.
extension SidebarController {

	// MARK: - Which repository

	/// Where a file stands in its repository, for the compare verbs: the
	/// repository that owns it and the path git there knows it by. Nil outside
	/// the repository, where there is nothing to compare against.
	///
	/// **Asked of the estate**, which knows which submodule a file is inside.
	/// This used to be `project.gitRoot` and a path relative to it, and for a
	/// file inside a submodule that is the superproject and a path it holds
	/// nothing under: git answers with an empty diff and an empty log, exit 0,
	/// and Against Last Commit said the file matched the last commit while it
	/// did not. See `GitEstate.place(of:)`. Before the first git read the
	/// estate has no root, and the arithmetic it replaced still serves.
	func repositoryPlace(of url: URL) -> GitEstate.Place? {
		project()?.place(of: url)
	}

	/// The repository a change belongs to, and the path it knows the change
	/// by. `GitChange.path` is relative to the estate — the pane that lists
	/// changes across every submodule has one root — and git wants both the
	/// directory that owns the file and a path relative to it. `ChangesPane`
	/// says the same at its own diff.
	///
	/// With no submodules this is the project root, as it always was: an
	/// estate that has not been read yet has no root to offer.
	func owner(of path: String) -> (root: URL, path: String) {
		guard let project = project() else { return (URL(fileURLWithPath: "/"), path) }
		let estate = project.estate
		guard !estate.submodules.isEmpty else { return (project.root, path) }
		return (estate.repositoryRoot(containing: path), estate.relativePath(of: path))
	}

	/// Compare ▸ Against Last Commit: the file's diff against HEAD — staged
	/// and unstaged edits in one answer, the question the gutter's change
	/// marks answer — as a diff tab.
	func compareFileAgainstHead(_ url: URL) {
		guard let place = repositoryPlace(of: url), let project = project() else { return }
		Task { @MainActor in
			let text = await GitWorkingCopy.diffAgainstHead(for: place.path, in: place.root)
			guard let text, !text.isEmpty else {
				Toast.post(
					"Nothing to compare",
					detail: "\(url.lastPathComponent) matches the last commit.",
					kind: .information
				)
				return
			}
			// The tab is named by the estate's path against the estate's
			// root, which is where the file is; the verbs on it find their
			// repository through `owner(of:)`.
			editor.openDiff(
				for: GitChange(path: place.estatePath, kind: .modified, isStaged: false),
				root: gitCommandRoot() ?? project.root, text: text
			)
		}
	}

	/// Compare ▸ History…: the log page the "This File" segment reaches,
	/// arrived at from the file's own row.
	func showFileHistory(of url: URL) {
		guard let place = repositoryPlace(of: url) else { return }
		// The log of the repository that has the file's history, which for a
		// file inside a submodule is the submodule's own page.
		let page = showLogPage(scopedTo: nil, in: place.root)
		page?.offerScope(path: place.path)
		page?.setScope(path: place.path)
	}
}

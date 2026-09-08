import AbydosKit
import AppKit

/// Blame from where the file is, and a blame entry leading to its commit.
extension MainWindowController {
	/// *Blame* on a tree row or a tab: the file open and pinned, then the
	/// column on — one gesture for "who wrote this file".
	func blame(_ url: URL) {
		leaveTerminalFullScreen()
		editor.open(fileURL: url, focusEditor: true)
		editor.showBlame()
	}

	/// A click on a blame entry: the log page scoped to the file, at that
	/// commit, whose first row — the commit — the page selects as it loads,
	/// so the message and the diff of this file are on screen. An
	/// uncommitted line has nowhere to go and says so.
	func reveal(commit entry: GitBlame.Line, of file: URL) {
		guard !entry.isUncommitted else {
			Toast.post("Not committed yet", detail: "This line has no commit to go to.", kind: .information)
			return
		}
		// **The log of the repository the commit is in.** Blame is read in the
		// repository that owns the file, so for a file inside a submodule the
		// hash on the row is a commit of *that* repository and the
		// superproject has never heard of it. The project's log page, opened at
		// it, showed nothing. `sidebar.repositoryPlace(of:)` gives the owner,
		// and the page it opens is the submodule's own — beside the project's,
		// named for it, exactly as Compare ▸ History… opens it.
		guard let place = sidebar.repositoryPlace(of: file) else {
			Toast.post(entry.summary.isEmpty ? entry.shortCommit : entry.summary, detail: "\(entry.shortCommit) · \(entry.author)", kind: .information)
			return
		}
		let page = sidebar.showLogPage(scopedTo: entry.commit, in: place.root)
		// Scoped to the path the line had *in that commit*: a file moved since
		// — an archived change, a renamed module — has no history under
		// today's path back then, and the page came up empty. Blame's porcelain
		// names it relative to the repository blame ran in, which is the one
		// this page is about.
		if !entry.path.isEmpty {
			page?.setScope(path: entry.path)
			return
		}
		page?.setScope(path: place.path)
	}
}

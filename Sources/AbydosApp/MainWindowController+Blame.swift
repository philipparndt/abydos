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
		guard let root = project?.root else {
			Toast.post(entry.summary.isEmpty ? entry.shortCommit : entry.summary, detail: "\(entry.shortCommit) · \(entry.author)", kind: .information)
			return
		}
		sidebar.showLogPage(scopedTo: entry.commit)
		// Scoped to the path the line had *in that commit*: a file moved since
		// — an archived change, a renamed module — has no history under
		// today's path back then, and the page came up empty.
		if !entry.path.isEmpty {
			sidebar.logPage?.setScope(path: entry.path)
			return
		}
		let base = FilePath.canonical(root)
		let path = FilePath.canonical(file)
		if path.hasPrefix(base + "/") {
			sidebar.logPage?.setScope(path: String(path.dropFirst(base.count + 1)))
		}
	}
}

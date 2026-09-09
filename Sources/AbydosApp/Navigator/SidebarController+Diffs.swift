import AppKit
import AbydosKit

/// Moving the lines somebody selected in a diff: staging them, stashing them,
/// or throwing them away — and showing the diff they were selected in.
extension SidebarController {
	/// Moves the selected lines across the index, in whichever direction the
	/// diff's side implies.
	///
	/// - Parameter root: the repository the diff was read in, which is the
	///   submodule for a file inside one. Defaults to the project's own.
	func applyDiffSelection(
		change: GitChange, diff: String, lines: Set<Int>,
		in root: URL? = nil, from origin: DiffOrigin = .tab
	) {
		guard project() != nil, !lines.isEmpty else { return }
		// The diff came from the repository that owns the change, and its
		// headers name paths relative to it; applying it anywhere else fails.
		let root = root ?? owner(of: change.path).root
		Task { @MainActor in
			let result = change.isStaged
				? await GitWorkingCopy.unstage(lines: lines, ofDiff: diff, in: root)
				: await GitWorkingCopy.stage(lines: lines, ofDiff: diff, in: root)
			finishDiffOperation(result, change: change, from: origin)
		}
	}

	/// Puts just these lines aside.
	///
	/// **No new patch machinery at all.** `GitPatch.patch(selecting:)` already
	/// builds a partial patch and `GitWorkingCopy.stage(lines:ofDiff:)` already
	/// applies one to the index — so "stash these hunks" is staging them and
	/// stashing what is staged, which is what `--staged` is for.
	///
	/// The index is put back the way it was found: somebody who had staged
	/// something else and then stashed a hunk should not discover their staging
	/// had been swept up with it.
	func stashDiffSelection(
		change: GitChange, diff: String, lines: Set<Int>,
		in owner: URL? = nil, from origin: DiffOrigin = .tab
	) {
		guard let project = project(), !lines.isEmpty else { return }
		let root = owner ?? project.root

		Task { @MainActor in
			let alreadyStaged = await GitWorkingCopy.status(in: root).staged.map(\.path)
			guard alreadyStaged.isEmpty else {
				Toast.post(
					"Something is already staged",
					detail: "Stashing lines uses the index, so it needs the index empty. "
						+ "Commit or unstage what is there first."
				)
				return
			}

			let staged = await GitWorkingCopy.stage(lines: lines, ofDiff: diff, in: root)
			guard staged.exitCode == 0 else {
				finishDiffOperation(staged, change: change, from: origin)
				return
			}

			let name = "\(lines.count) line\(lines.count == 1 ? "" : "s") of \(change.name)"
			let put = await GitStash.pushStaged(in: root, message: name)
			finishDiffOperation(put, change: change, from: origin)
			if put.exitCode == 0 {
				Toast.post("Stashed \(name)", kind: .information)
			}
		}
	}

	func discardDiffSelection(
		change: GitChange, diff: String, lines: Set<Int>,
		in owner: URL? = nil, from origin: DiffOrigin = .tab
	) {
		guard project() != nil, !lines.isEmpty else { return }
		let root = owner ?? self.owner(of: change.path).root

		// Discarding is the one operation here that destroys work, so it asks.
		let alert = NSAlert()
		alert.messageText = "Discard \(lines.count) line\(lines.count == 1 ? "" : "s")?"
		alert.informativeText = "The change will be removed from \(change.name). This cannot be undone."
		alert.addButton(withTitle: "Discard")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			Task { @MainActor in
				// Reversing the patch against the work tree is the same operation
				// as unstaging, just without --cached.
				guard let patch = GitPatch.parse(diff).patch(selecting: lines, reverse: true) else { return }
				let result = await GitRepository.run(
					["apply", "--reverse", "--recount", "--whitespace=nowarn", "-"],
					in: root,
					input: Data(patch.utf8)
				)
				self.finishDiffOperation(result, change: change, from: origin)
			}
		}

		if let window = hostWindow() {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	private func finishDiffOperation(
		_ result: GitRepository.ProcessResult, change: GitChange, from origin: DiffOrigin = .tab
	) {
		if result.exitCode != 0 {
			notify(
				"git reported a problem",
				(result.stderr.isEmpty ? result.stdout : result.stderr)
					.trimmingCharacters(in: .whitespacesAndNewlines)
			)
			return
		}

		changesPane?.refresh()
		navigator.refreshGitStatus()
		// The diff on screen described the state before this ran, so it is
		// re-read rather than left showing lines that have already moved.
		//
		// **Back where it was selected.** From the page that is the page's own
		// diff, and opening a tab as well would answer a gesture made to avoid
		// tabs with one of them.
		switch origin {
		case .tab:  showDiff(for: change)
		case .page:
			commitPage?.refresh()
			commitPage?.rereadDiff()
		}
	}

	func showDiff(for change: GitChange) {
		guard let project = project() else { return }
		let owner = owner(of: change.path)
		Task { @MainActor in
			let text = await GitWorkingCopy.diff(
				for: owner.path,
				staged: change.isStaged,
				in: owner.root,
				isDirectory: change.isDirectory
			)
			editor.openDiff(for: change, root: project.root, text: text)
		}
	}

	/// Opens the diff a commit made to one of its files.
	func showCommitDiff(commit: GitCommit, file: GitCommitFile) {
		guard let project = project() else { return }
		Task { @MainActor in
			let text = await GitHistory.diff(of: commit.hash, path: file.path, in: project.root)
			editor.openCommitDiff(commit: commit, file: file, root: project.root, text: text)
		}
	}
}

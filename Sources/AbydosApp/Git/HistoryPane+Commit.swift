import AppKit
import AbydosKit

/// What can be done to a commit: the menu behind a right-click, and the
/// operations behind it.
///
/// Every one of them runs over the repository and then tells the window it
/// moved, because a log that shows the state before the operation is worse than
/// one that has not run it.
extension HistoryPane {

	// MARK: - What can be done to a commit

	/// Runs something over the repository and tells the window it moved.
	private func run(_ operation: @escaping () async -> GitRepository.ProcessResult) {
		Task { @MainActor in
			let result = await operation()
			if result.exitCode != 0 {
				Toast.post(
					"That did not work",
					detail: result.stderr.isEmpty ? result.stdout : result.stderr
				)
			}
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: nil)
			reload()
		}
	}

	/// Reports an outcome that has three answers rather than two.
	///
	/// A revert or a cherry-pick that stops in a conflict has *already* changed
	/// the work tree, so "that did not work" would be false about it — the
	/// files are there, half-merged, and somebody has to be told which ones.
	private func report(_ outcome: GitCommits.Outcome, verb: String) {
		switch outcome {
		case .done:
			Toast.post("\(verb) done", kind: .information)
		case let .conflicted(paths):
			Toast.post(Toast(
				kind: .warning,
				title: "\(verb) stopped in \(paths.count) file\(paths.count == 1 ? "" : "s")",
				detail: paths.joined(separator: "\n"),
				actionTitle: "Abort",
				action: { [weak self] in
					guard let self else { return }
					Task { @MainActor in
						let undone = await GitCommits.abort(in: self.root)
						self.report(undone, verb: "Abort")
					}
				}
			))
		case let .failed(said):
			Toast.post("\(verb) did not happen", detail: said)
		}
		NotificationCenter.default.post(name: .abydosRepositoryChanged, object: nil)
		reload()
	}

	/// What this log is narrowed to, for a session to write down: the ref and
	/// the file, each only where there is one. Empty for the everything-log,
	/// which is what reopening with nothing gives back.
	func scopeToRemember() -> [String: String] {
		var showing: [String: String] = [:]
		if let ref = scopedRef { showing["ref"] = ref }
		if let path = scopedPath { showing["path"] = path }
		return showing
	}

	/// How far now is from then, for the one file this log is scoped to.
	/// Selecting the commit already shows what it changed at the time; this
	/// is the other question.
	@objc func compareCommitWithWorkingCopy() {
		guard let commit = clickedCommit, let path = scopedPath else { return }
		Task { @MainActor in
			let text = await GitWorkingCopy.diffToWorkingCopy(
				since: commit.hash, for: path, in: self.root
			)
			guard !text.isEmpty else {
				Toast.post(
					"Nothing to compare",
					detail: "The working copy matches \(commit.shortHash).",
					kind: .information
				)
				return
			}
			self.onOpenWorkingCopyDiff?(
				GitChange(path: path, kind: .modified, isStaged: false),
				self.root, text
			)
		}
	}

	@objc func checkoutCommit() {
		guard let commit = clickedCommit else { return }
		// Detaching HEAD is not destructive — nothing is lost by standing
		// somewhere else — so it asks nothing and keeps nothing.
		run { await GitRepository.run(["checkout", commit.hash], in: self.root) }
	}

	@objc func branchFromHere() {
		guard let commit = clickedCommit else { return }
		promptForName(
			title: "New branch from \(commit.shortHash)",
			message: commit.subject,
			defaultValue: ""
		) { [weak self] name in
			guard let self, !name.isEmpty else { return }
			self.run { await GitRepository.run(["checkout", "-b", name, commit.hash], in: self.root) }
		}
	}

	@objc func tagHere() {
		guard let commit = clickedCommit else { return }
		promptForName(
			title: "Tag \(commit.shortHash)",
			message: commit.subject,
			defaultValue: ""
		) { [weak self] name in
			guard let self, !name.isEmpty else { return }
			self.run { await GitTags.create(name, at: commit.hash, in: self.root) }
		}
	}

	@objc func revertCommit() {
		guard let commit = clickedCommit else { return }
		Task { @MainActor in
			let outcome = await GitCommits.revert(commit.hash, in: root)
			report(outcome, verb: "Revert")
		}
	}

	@objc func cherryPickCommit() {
		guard let commit = clickedCommit else { return }
		Task { @MainActor in
			let outcome = await GitCommits.cherryPick(commit.hash, in: root)
			report(outcome, verb: "Cherry-pick")
		}
	}

	/// The one on this menu that can lose work, and the only one that asks.
	@objc func resetToCommit() {
		guard let commit = clickedCommit else { return }
		// The work tree, taken now rather than through `self` later: the sheet
		// is answered minutes afterwards and the pane may be gone by then,
		// while the repository it was reset against certainly is not.
		let root = self.root

		// Weak from the top and nowhere else. A weak capture inside a scope
		// that already holds a strong one reads as care that is not being
		// taken — the compiler says so, and `BranchesPane.recreateTag` learnt
		// it first.
		Task { @MainActor [weak self] in
			let leaving = await GitCommits.count(of: "HEAD", notIn: commit.hash, in: root)
			DestructiveAsk.run(
				.reset(to: commit.shortHash, commits: leaving, mode: .hard),
				in: root,
				over: self?.window
			) { _, _ in
				let outcome = await GitCommits.reset(to: commit.hash, mode: .hard, in: root)
				NotificationCenter.default.post(name: .abydosRepositoryChanged, object: nil)
				self?.reload()
				if case let .failed(said) = outcome { return said }
				return nil
			}
		}
	}

	/// Asks for a name, the way the branches pane does.
	private func promptForName(
		title: String,
		message: String,
		defaultValue: String,
		then act: @escaping (String) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
		field.stringValue = defaultValue
		alert.accessoryView = field

		let handle: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .alertFirstButtonReturn else { return }
			act(field.stringValue.trimmingCharacters(in: .whitespaces))
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: handle)
			window.makeFirstResponder(field)
		} else {
			handle(alert.runModal())
		}
	}
}

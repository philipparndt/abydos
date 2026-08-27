import AppKit
import AbydosKit

/// Deleting branches: what it would cost, what somebody is asked, and what it
/// then does.
///
/// **Its own file because the question outgrew a menu action.** A delete used
/// to be one `git branch -d` and a sentence about whether the commits were
/// somewhere else. Then it learnt to take several branches at once, and then it
/// met the refusal git gives for a branch a worktree has checked out — `cannot
/// delete branch 'x' used by worktree at …` — which the pane could do nothing
/// with except repeat it in git's words after the fact.
///
/// What somebody wants at that moment is nearly always to be rid of both, and
/// the directory is the part taking up the disk: the one that made `CLAUDE.md`
/// grow a section about orphaned worktrees was 4.9 GB of checkout and build
/// output, on a disk at 99% full.
///
/// One of these per press, holding what was true when the press happened, so a
/// refresh underneath cannot change what somebody is agreeing to.
@MainActor
final class BranchDeletion {
	private let root: URL
	private let worktrees: [GitWorktree]
	private weak var window: NSWindow?

	/// Said once at the end rather than per branch.
	var onFinished: (() -> Void)?
	var onFailure: ((String) -> Void)?

	init(root: URL, worktrees: [GitWorktree], window: NSWindow?) {
		self.root = root
		self.worktrees = worktrees
		self.window = window
	}

	/// The whole flow: work out what it would cost, then ask.
	func ask(about branches: [GitBranch], target: String) {
		guard !branches.isEmpty else { return }
		// **Asked before the question is put, because the answer is the
		// question.** "Three branches, all merged" and "three branches, one
		// carrying work nobody else has" are different things to be asked, and
		// a dialog saying the same sentence either way teaches somebody to
		// press Delete without reading it.
		Task { @MainActor in
			self.askAboutDeleting(await self.plan(for: branches, target: target), target: target)
		}
	}

	/// A branch that cannot be deleted while a checkout of it exists, and what
	/// that checkout is.
	///
	/// **Git refuses outright**: `cannot delete branch 'x' used by worktree at
	/// …`. The refusal is right and the answer was a shrug — the delete failed
	/// and the pane said so in somebody else's words. What somebody actually
	/// wants at that moment is nearly always to be rid of both, and the
	/// directory is the part that is taking up the disk.
	private struct HeldBranch {
		let branch: GitBranch
		let worktree: GitWorktree
		/// What the directory takes up, when `du` answered in time.
		let bytes: Int64?
		/// Whether there is anything in it git would not want thrown away —
		/// modified *or* untracked, which is git's own rule for the same
		/// question: `git worktree remove` refuses either way and wants
		/// `--force`. That is a thing to say before it is a thing to do, and
		/// untracked is the case that matters — a worktree's build output is
		/// untracked, and so is the file somebody has not committed yet.
		let hasChanges: Bool

		/// Where it is and what it costs, without the branch's name — which the
		/// single-branch wording has already said in its title.
		var place: String {
			var parts: [String] = [(worktree.path.path as NSString).abbreviatingWithTildeInPath]
			if worktree.isMissing {
				// Registered and not there — the state `git worktree prune`
				// exists for, and one git refuses the branch over just the
				// same. Nothing to free and nothing to lose.
				parts.append("directory already gone")
				return parts.joined(separator: " — ")
			}
			if let bytes { parts.append(ByteSize.said(bytes)) }
			if hasChanges { parts.append("modified or untracked files") }
			return parts.joined(separator: ", ")
		}

		var said: String { "\(branch.name) — \(place)" }
	}

	/// What a delete would act on, in the three kinds somebody has to be asked
	/// about separately.
	private struct DeletePlan {
		var merged: [GitBranch] = []
		var carrying: [GitBranch] = []
		var held: [HeldBranch] = []

		var all: [GitBranch] { merged + carrying + held.map(\.branch) }
		var count: Int { merged.count + carrying.count + held.count }
		var freed: Int64 { held.compactMap(\.bytes).reduce(0, +) }
		var anyWorktreeHasChanges: Bool { held.contains { $0.hasChanges } }
	}

	/// Sorts the selection into that plan, asking git the three questions it
	/// takes: is it merged, is it checked out somewhere, and how big is that.
	private func plan(for branches: [GitBranch], target: String) async -> DeletePlan {
		var plan = DeletePlan()
		let trees = worktrees
		for branch in branches {
			if let worktree = GitWorktrees.holder(of: branch.name, in: trees, excluding: root) {
				// A missing one is held all the same — git refuses the branch
				// over a registration, not over a directory — and it is not
				// measured or asked about changes, there being nothing there
				// to measure or lose.
				var bytes: Int64?
				var dirty = false
				if !worktree.isMissing {
					let status = await GitWorkingCopy.status(in: worktree.path)
					bytes = await ByteSize.ofDirectory(at: worktree.path)
					dirty = !(status.staged.isEmpty && status.unstaged.isEmpty)
				}
				plan.held.append(HeldBranch(
					branch: branch, worktree: worktree, bytes: bytes, hasChanges: dirty
				))
			} else if await GitBranches.isMerged(branch.name, into: target, in: root) {
				plan.merged.append(branch)
			} else {
				plan.carrying.append(branch)
			}
		}
		return plan
	}


	/// What to redraw when the delete dialog's worktree checkbox is ticked.
	/// Lives here because the checkbox needs an Objective-C target and the
	/// dialog is a local.
	private var worktreeBoxChanged: (() -> Void)?

	@objc private func worktreeBoxToggled() { worktreeBoxChanged?() }

	/// The dialog, written from what was found rather than from what was asked.
	private func askAboutDeleting(_ plan: DeletePlan, target: String) {
		let all = plan.all
		guard let first = all.first else { return }
		let alert = NSAlert()
		alert.messageText = all.count == 1
			? "Delete branch “\(first.name)”?"
			: "Delete \(all.count) branches?"

		func list(_ lines: [String]) -> String {
			lines.map { "  • \($0)" }.joined(separator: "\n")
		}

		var said: [String] = []
		if !plan.merged.isEmpty {
			// The harmless case, said plainly: every commit on these is already
			// on the branch being stood on, so the ref is the only thing going.
			said.append(all.count == 1
				? "Every commit on it is already on \(target), so nothing would be lost."
				: "Already on \(target) — nothing would be lost:"
					+ "\n\(list(plan.merged.map(\.name)))")
		}
		if !plan.carrying.isEmpty {
			said.append(all.count == 1
				? "It has commits that are not on \(target). They would be lost."
				: "Not on \(target) — these would lose commits:"
					+ "\n\(list(plan.carrying.map(\.name)))")
		}
		if !plan.held.isEmpty {
			// **Named as the reason, not as a failure.** Git will not delete a
			// branch that a worktree has checked out, and being told that
			// afterwards, in git's words, is what used to happen.
			let one = plan.held[0]
			said.append(all.count == 1
				? "It is checked out in a worktree — \(one.place). Git will not delete the "
					+ (one.worktree.isMissing
						? "branch while it still has a note of that worktree."
						: "branch while that worktree is there.")
				: "Checked out in a worktree — git will not delete these while the "
					+ "worktrees are there:\n\(list(plan.held.map(\.said)))")
		}
		alert.informativeText = said.joined(separator: "\n\n")

		// **The worktrees are a second question, so they get a second control.**
		// A dialog whose one button does two different destructive things —
		// deleting refs and deleting directories — is one that has to be read
		// twice, and the multiple-selection case is exactly where it would not
		// be. Off by default when anything in one of them is uncommitted.
		var removeWorktrees: NSButton?
		if !plan.held.isEmpty {
			let freed = plan.freed
			let allGone = plan.held.allSatisfy { $0.worktree.isMissing }
			var title: String
			if allGone {
				// Nothing to delete — the directories are gone and only git's
				// note of them is left. Saying "delete the worktree" of a
				// directory that is not there is a lie about what the press
				// does.
				title = plan.held.count == 1
					? "Also forget the worktree git still has a note of"
					: "Also forget the \(plan.held.count) worktrees git still has notes of"
			} else {
				title = plan.held.count == 1
					? "Also delete the worktree"
					: "Also delete the \(plan.held.count) worktrees"
				if freed > 0 { title += ", freeing \(ByteSize.said(freed))" }
			}
			let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
			// **An explicit frame.** `NSAlert` lays its accessory out from the
			// frame it is given, not from the view's intrinsic size, and a
			// checkbox handed over at zero by zero is a dialog with an
			// invisible control in it.
			box.frame = NSRect(origin: .zero, size: box.fittingSize)
			box.state = plan.anyWorktreeHasChanges ? .off : .on
			if plan.anyWorktreeHasChanges {
				box.toolTip = plan.held.count == 1
					? "It has modified or untracked files in it, which would go with it."
					: "One of them has modified or untracked files in it, which would go with it."
			}
			alert.accessoryView = box
			removeWorktrees = box
		}

		// The verb says which kind of delete this is, so it is not the same
		// press for both.
		alert.addButton(withTitle: plan.carrying.isEmpty ? "Delete" : "Delete Anyway")
		alert.addButton(withTitle: "Cancel")
		// Destructive where something would actually be lost — commits, or a
		// directory. A merged branch is a name, and marking that red is the boy
		// who cried wolf.
		let primary = alert.buttons.first
		// A worktree that is not there any more is not something to lose: what
		// would go is git's note of it, which is a tidying and not a deletion.
		let anythingOnDisk = plan.held.contains { !$0.worktree.isMissing }
		let markPrimary = { [weak primary] in
			let removing = removeWorktrees?.state == .on
			primary?.hasDestructiveAction = !plan.carrying.isEmpty || (removing && anythingOnDisk)
			// Nothing left to press: every branch selected is held by a
			// worktree, and the box saying to leave the worktrees alone leaves
			// the delete with nothing it is allowed to do.
			primary?.isEnabled = removing
				|| !plan.merged.isEmpty || !plan.carrying.isEmpty
		}
		markPrimary()
		if let removeWorktrees {
			// The checkbox changes what the button means, so the button is
			// redrawn when it is ticked: red and pressable with the worktrees
			// going, plain — or nothing to press at all — without them.
			worktreeBoxChanged = markPrimary
			removeWorktrees.target = self
			removeWorktrees.action = #selector(worktreeBoxToggled)
		}

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			self.delete(plan, removingWorktrees: removeWorktrees?.state == .on)
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	/// Deletes them, and says what happened once rather than per branch.
	///
	/// `-d` for the merged ones and `-D` only for those that carry work, so a
	/// wrong ancestry answer is caught by git rather than forced past it. One at
	/// a time, because `git branch -d` takes the repository's lock and a dozen
	/// at once would be a dozen ways to fail.
	///
	/// **The worktree goes before the branch it holds.** In the other order git
	/// refuses the branch, which is the refusal this whole flow exists to
	/// answer.
	private func delete(_ plan: DeletePlan, removingWorktrees: Bool) {
		let forced = Set(plan.carrying.map(\.name))
		Task { @MainActor in
			var failures: [String] = []
			var deleted: [String] = []
			var freed: Int64 = 0

			if removingWorktrees {
				for held in plan.held {
					// **Prune, not remove, for one that is already gone.**
					// `git worktree remove` on a directory that is not there
					// answers `is not a working tree` and leaves the
					// registration — which is the thing git is refusing the
					// branch over.
					let result = held.worktree.isMissing
						? await GitWorktrees.prune(in: self.root)
						// `--force` only where it is needed, and it is needed
						// exactly where the dialog said so: a worktree with
						// modified or untracked files in it.
						: await GitWorktrees.remove(
							held.worktree, force: held.hasChanges, in: self.root
						)
					if result.exitCode != 0 {
						let saidIt = result.stderr.isEmpty ? result.stdout : result.stderr
						failures.append("\(held.worktree.path.lastPathComponent): "
							+ saidIt.trimmingCharacters(in: .whitespacesAndNewlines))
					} else {
						freed += held.bytes ?? 0
					}
				}
			}

			// Only the branches whose way is now clear: one whose worktree
			// could not be removed is one git will still refuse, and a second
			// refusal in its own words helps nobody.
			let removedTrees = Set(
				removingWorktrees
					? plan.held.filter { held in
						!failures.contains { $0.hasPrefix(held.worktree.path.lastPathComponent + ":") }
					}.map(\.branch.name)
					: []
			)
			let branches = plan.merged + plan.carrying
				+ plan.held.map(\.branch).filter { removedTrees.contains($0.name) }

			for branch in branches {
				let result = await GitBranches.delete(
					branch.name, force: forced.contains(branch.name), in: self.root
				)
				if result.exitCode != 0 {
					let saidIt = result.stderr.isEmpty ? result.stdout : result.stderr
					failures.append(
						"\(branch.name): \(saidIt.trimmingCharacters(in: .whitespacesAndNewlines))"
					)
				} else {
					deleted.append(branch.name)
				}
			}

			if failures.isEmpty {
				var detail: String?
				if removingWorktrees, !plan.held.isEmpty {
					let gone = plan.held.allSatisfy { $0.worktree.isMissing }
					if gone {
						detail = plan.held.count == 1
							? "And the note git had of its worktree"
							: "And the notes git had of \(plan.held.count) worktrees"
					} else {
						detail = plan.held.count == 1
							? "And the worktree it was checked out in"
							: "And \(plan.held.count) worktrees"
						if freed > 0 { detail? += ", freeing \(ByteSize.said(freed))" }
					}
				} else if !plan.held.isEmpty {
					// Left alone on purpose, and said so — otherwise a count
					// smaller than the selection is a mystery.
					detail = plan.held.count == 1
						? "\(plan.held[0].branch.name) was left: its worktree is still there"
						: "\(plan.held.count) were left: their worktrees are still there"
				}
				Toast.post(
					deleted.count == 1
						? "Deleted \(deleted[0])"
						: "Deleted \(deleted.count) branches",
					detail: detail,
					kind: .information
				)
			} else {
				self.onFailure?(failures.joined(separator: "\n"))
			}
			self.onFinished?()
		}
	}

	// MARK: - Driven runs

	/// What the dialog would say, without putting it up.
	///
	/// The sentence *is* the feature here: "nothing would be lost", "these
	/// would lose commits" and "checked out in a worktree" are the three things
	/// somebody is being asked, and a check that only counted branches could
	/// not tell them apart.
	func wordingForTesting(about branches: [GitBranch], target: String) async -> String {
		let plan = await plan(for: branches, target: target)
		// The worktree half reports the *place* rather than the size, because
		// the size is a real `du` of a real directory and no two runs of a test
		// would agree about it.
		let held = plan.held.map {
			"\($0.branch.name)@\($0.worktree.path.lastPathComponent)"
				+ ($0.hasChanges ? "(dirty)" : "")
				+ ($0.worktree.isMissing ? "(gone)" : "")
		}
		let box = plan.held.isEmpty ? "none" : (plan.anyWorktreeHasChanges ? "off" : "on")
		// A note git is left holding is not a thing on disk to lose.
		let onDisk = plan.held.contains { !$0.worktree.isMissing }
		return "target=\(target) merged=[\(plan.merged.map(\.name).joined(separator: " "))] "
			+ "carrying=[\(plan.carrying.map(\.name).joined(separator: " "))] "
			+ "held=[\(held.joined(separator: " "))] worktreebox=\(box) "
			+ "button=\(plan.carrying.isEmpty ? "Delete" : "Delete Anyway") "
			+ "destructive=\(!plan.carrying.isEmpty || (box == "on" && onDisk)) "
			// Nothing to press: everything selected is held by a worktree the
			// box says to leave alone.
			+ "enabled=\(box == "on" || !plan.merged.isEmpty || !plan.carrying.isEmpty)"
	}

	/// Does the delete the dialog would do, with the checkbox as given — the
	/// half a driven run cannot reach, because the dialog itself is AppKit's.
	func deleteForTesting(
		about branches: [GitBranch], target: String, removingWorktrees: Bool
	) async {
		delete(await plan(for: branches, target: target), removingWorktrees: removingWorktrees)
	}
}

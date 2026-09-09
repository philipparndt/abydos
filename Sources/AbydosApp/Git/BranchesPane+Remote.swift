import AppKit
import AbydosKit

/// The remote, the stashes and the worktrees: the three sections of this tree
/// that are not branches, and each of which answers to its own git commands.
extension BranchesPane {
	// MARK: - The remote

	var remoteMenuTitle: String {
		remoteURL == nil ? "Add a Remote…" : "Change the Remote…"
	}


	@objc private func remoteFieldEdited() { remoteFieldChanged?() }

	@objc func setRemote() {
		let alert = NSAlert()
		alert.messageText = remoteURL == nil ? "Add a remote" : "Change the remote"
		// **Not the URL again.** It is in the field below, editable, and saying
		// it twice is what wrapped a long one across two lines in a sentence
		// nobody needed to read. What is worth saying is what the box is for.
		alert.informativeText = remoteURL == nil
			? "This repository has no remote, so there is nowhere to push."
			: "Where origin points. Everything that talks to a remote uses it."

		alert.addButton(withTitle: remoteURL == nil ? "Add" : "Change")
		alert.addButton(withTitle: "Cancel")

		// **One line, and it scrolls.** A remote URL is longer than any box that
		// fits in a dialog, and this one wrapped: pasting
		// `git@github.com:philipparndt/3d-models-general.git` left `general.git`
		// on screen with the rest above the visible line, which reads as a paste
		// that went wrong. A URL has no line breaks in it, so the field must not
		// have any either.
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 44))
		field.stringValue = remoteURL ?? ""
		field.placeholderString = "git@github.com:you/thing.git"
		field.usesSingleLineMode = true
		field.cell?.wraps = false
		field.cell?.isScrollable = true
		field.lineBreakMode = .byTruncatingHead
		field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

		// What it made of what is typed, under the box.
		//
		// **A URL is not a thing to be told about afterwards.** `origin` set to
		// something misread is a push that fails much later, in git's words,
		// about a host nobody meant — so the same parser the rest of the app
		// uses for a remote says here, before the press, which host and which
		// repository it took. It is also the only way to see that a paste
		// arrived whole.
		let read = NSTextField(labelWithString: "")
		read.font = .systemFont(ofSize: 11)
		read.textColor = .secondaryLabelColor
		read.lineBreakMode = .byTruncatingTail
		read.frame = NSRect(x: 0, y: 0, width: 420, height: 16)

		let stack = NSStackView(views: [field, read])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 6
		stack.frame = NSRect(x: 0, y: 0, width: 420, height: 46)
		// **Pinned, or the stack gives each row the width of its own text.** A
		// field sized to what is already in it is a field with no room to type
		// a longer one, which for a remote URL is most of them.
		for view in [field, read] {
			view.translatesAutoresizingMaskIntoConstraints = false
			view.widthAnchor.constraint(equalToConstant: 420).isActive = true
		}
		alert.accessoryView = stack

		let accept = alert.buttons.first
		let describe = {
			let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			if text.isEmpty {
				read.stringValue = ""
				accept?.isEnabled = false
			} else if let repository = GitForge.repository(fromRemote: text) {
				read.stringValue = "\(repository.host) · \(repository.owner)/\(repository.name)"
				read.textColor = .secondaryLabelColor
				accept?.isEnabled = true
			} else {
				// Not refused: a path, or a host this does not know, is a
				// perfectly good remote and git will say so if it is not. What
				// is said is only that nothing was recognised in it.
				read.stringValue = "not a GitHub-style URL — git will decide"
				read.textColor = .secondaryLabelColor
				accept?.isEnabled = true
			}
		}
		remoteFieldChanged = describe
		field.target = self
		field.action = #selector(remoteFieldEdited)
		field.delegate = self
		describe()

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			defer { self?.remoteFieldChanged = nil }
			guard response == .alertFirstButtonReturn, let self else { return }
			// Trimmed of newlines as well as spaces: a URL copied from a browser
			// or a terminal brings one, and `git remote add` takes it literally.
			let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !url.isEmpty, url != self.remoteURL else { return }
			self.run { await GitForge.setRemote(url, in: self.root) }
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
			window.makeFirstResponder(field)
		} else {
			act(alert.runModal())
		}
	}

	/// Puts the whole working copy aside, under a name.
	///
	/// **Untracked files are included by default**, which is not git's default
	/// and is deliberate. `git stash` without `--include-untracked` leaves new
	/// files where they are, so a work tree that was meant to be clean still has
	/// them in it — and the file somebody has just written, which is the one they
	/// are most likely to be putting aside, is exactly the kind that is still
	/// untracked. The box is there because the other answer is legitimate:
	/// build output is untracked too, and sweeping it into a stash is a slow
	/// surprise.
	@objc func stashWorkingCopy() {
		let count = working.staged.count + working.unstaged.count
		guard count > 0 else { return }

		let alert = NSAlert()
		alert.messageText = "Stash \(count) change\(count == 1 ? "" : "s")"
		alert.informativeText = "They come out of the working copy and wait under Stashes, "
			+ "under whatever this says."
		alert.addButton(withTitle: "Stash")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		field.placeholderString = "What this is"
		field.usesSingleLineMode = true
		field.cell?.wraps = false
		field.cell?.isScrollable = true

		let untracked = NSButton(
			checkboxWithTitle: "Include untracked files", target: nil, action: nil
		)
		untracked.state = .on
		untracked.toolTip = "New files git has never seen. Without this they stay "
			+ "in the working copy."

		let stack = NSStackView(views: [field, untracked])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		stack.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
		// An explicit width, or the stack gives each row the width of its own
		// text and the field has no room to type in — the fault the remote
		// dialog had.
		field.translatesAutoresizingMaskIntoConstraints = false
		field.widthAnchor.constraint(equalToConstant: 320).isActive = true
		alert.accessoryView = stack

		let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let message = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			let including = untracked.state == .on
			self.run {
				await GitStash.push(
					in: self.root, message: message, includeUntracked: including
				)
			}
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: handle)
			window.makeFirstResponder(field)
		} else {
			handle(alert.runModal())
		}
	}

	// MARK: - Stashes

	/// Puts a stash back into the working copy, having asked what should
	/// become of the entry.
	///
	/// Both answers are ordinary — one is `git stash apply`, the other `git
	/// stash pop` — and which is wanted depends on whether the work is being
	/// resumed or merely borrowed, which nothing here can know.
	@objc func applyStash() {
		guard let entry = selectedStashes.first else { return }
		apply(stash: entry)
	}

	/// **Named, rather than taken from the selection.** The stash page is not
	/// the tree, and its verbs are about the stash it is showing — routing them
	/// through `selectedStashes` made them act on whatever row happened to be
	/// highlighted in a pane the page is not in, which for a collapsed Stashes
	/// section is nothing at all. Driven: the press reached the pane and no
	/// dialog appeared.
	func apply(stash entry: GitStash.Entry) {
		let alert = NSAlert()
		alert.messageText = "Apply “\(entry.message)”?"
		alert.informativeText = "The changes go back into the working copy. "
			+ "The entry can stay in the list, or go now that it has been used."
		alert.addButton(withTitle: "Apply and Keep")
		alert.addButton(withTitle: "Apply and Drop")
		alert.addButton(withTitle: "Cancel")

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard let self, response != .alertThirdButtonReturn else { return }
			let keeping = response == .alertFirstButtonReturn
			self.run { await GitStash.apply(entry, in: self.root, keeping: keeping) }
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	@objc func dropStash() {
		let entries = selectedStashes
		guard !entries.isEmpty else { return }
		drop(stashes: entries)
	}

	func drop(stashes entries: [GitStash.Entry]) {
		guard !entries.isEmpty else { return }
		let alert = NSAlert()
		alert.messageText = entries.count == 1
			? "Drop “\(entries[0].message)”?"
			: "Drop \(entries.count) stashes?"
		alert.informativeText = "The work in "
			+ (entries.count == 1 ? "it" : "them")
			+ " is not on any branch, so this is the last of it."
		alert.addButton(withTitle: "Drop")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			self.run { await GitStash.drop(entries, in: self.root) }
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	@objc func renameStash() {
		guard let entry = selectedStashes.first else { return }

		let alert = NSAlert()
		alert.messageText = "Rename stash"
		alert.informativeText = "What the entry says in the list. The work itself is untouched."
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
		field.stringValue = entry.message
		alert.accessoryView = field

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let name = field.stringValue.trimmingCharacters(in: .whitespaces)
			guard !name.isEmpty, name != entry.message else { return }
			self.run { await GitStash.rename(entry, to: name, in: self.root) }
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
			window.makeFirstResponder(field)
		} else {
			act(alert.runModal())
		}
	}

	func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	func checkoutSelected() {
		// A file is staged or unstaged, which is what activating a change has
		// always meant here.
		if case let .change(node, staged, _) = clickedRow, !node.isFolder {
			run {
				staged
					? await GitWorkingCopy.unstage(paths: [node.path], in: self.root)
					: await GitWorkingCopy.stage(paths: [node.path], in: self.root)
			}
			return
		}

		// **Everything that holds something opens and shuts, through one
		// door.** A branch folder is not a place to be, a stash is not a place
		// to be, and neither is the working copy — so activating any of them
		// shows what is inside rather than doing something to it.
		if let node = selectedNode, !node.children.isEmpty {
			if tableView.isItemExpanded(node) {
				tableView.collapseItem(node)
			} else {
				tableView.expandItem(node)
			}
			return
		}

		// A worktree is opened rather than checked out: it is already a
		// checkout, which is the whole reason it exists.
		if let worktree = selectedWorktree {
			guard !worktree.isMissing else { return }
			onOpenWorktree?(worktree.path)
			return
		}
		guard let branch = selectedBranch, !branch.isCurrent else { return }
		// Its own task rather than `run`, so that a refusal goes through the one
		// explanation the titlebar and the switcher use: a branch another
		// checkout holds is offered that checkout, and everything else keeps
		// git's own message.
		Task { @MainActor in
			let result = await GitBranches.checkout(branch, in: self.root)
			if result.exitCode != 0 {
				// **The second refusal this app can act on.** `BranchInUse` set
				// the rule for the first — where a refusal is one the app can do
				// something about, offer the action rather than report the
				// sentence — and a work tree in the way is the other one, and
				// the place most stashes come from.
				//
				// Recognised through `GitPull.refusal`, which already knows the
				// several spellings git has for it. Two lists of the same
				// strings would drift, and the one that drifted would fail by
				// showing git's raw refusal to somebody this could have helped.
				if GitPull.refusal(from: result) == .workingCopyInTheWay {
					await self.offerToStash(before: branch)
				} else {
					await BranchMenu.explainRefusal(result, branch: branch.name, in: self.root)
				}
			} else {
				self.offerWhatWasLeftHere(on: branch.name)
			}
			self.refresh()
			self.onRepositoryChanged?()
		}
	}

	/// What a stash made on the way out of a branch is called.
	///
	/// Named rather than numbered, so coming back can find it: `stash@{0}` is a
	/// position and every drop renumbers it, while this survives.
	private static func leftBehindMessage(for branch: String) -> String {
		"Abydos: left on \(branch)"
	}

	/// Offers to get the work out of the way, switch, and give it back later.
	private func offerToStash(before branch: GitBranch) async {
		let status = await GitWorkingCopy.status(in: root)
		let changed = status.staged.count + status.unstaged.count
		let from = await GitRepository.head(in: root).name ?? ""
		let root = self.root

		DestructiveAsk.run(
			.switchBranch(to: branch.name, changedFiles: changed),
			in: root,
			over: window
		) { [weak self] chosen, _ in
			// Nought is stash and switch; one is switch and leave behind, whose
			// backup ref `DestructiveAsk` has already made by the time this
			// runs. The two are different operations rather than two ways of
			// confirming one, which is why the choice is passed in.
			if chosen == 0 {
				let put = await GitStash.push(
					in: root,
					message: Self.leftBehindMessage(for: from),
					includeUntracked: true
				)
				guard put.exitCode == 0 else { return put.stderr }
			}

			let again = await GitBranches.checkout(branch, in: root)
			if again.exitCode != 0 {
				// Forced only where somebody has just been told, in a count,
				// exactly what it will cost — and never otherwise.
				guard chosen == 1 else { return again.stderr }
				let forced = await GitRepository.run(
					["checkout", "--force", branch.checkoutName], in: root
				)
				guard forced.exitCode == 0 else { return forced.stderr }
			}
			await MainActor.run {
				self?.refresh()
				self?.onRepositoryChanged?()
			}
			return nil
		}
	}

	/// Offers back whatever was put aside on the way out of this branch.
	///
	/// The other half of "and back again when you come back": a promise made in
	/// a dialog and kept nowhere is worse than never having offered.
	private func offerWhatWasLeftHere(on branch: String) {
		let wanted = Self.leftBehindMessage(for: branch)
		let root = self.root
		Task { @MainActor [weak self] in
			guard let entry = await GitStash.list(in: root)
				.first(where: { $0.message == wanted }) else { return }

			Toast.post(Toast(
				kind: .information,
				title: "You left work on \(branch)",
				detail: "It was put aside when you switched away.",
				actionTitle: "Put It Back",
				action: {
					Task { @MainActor in
						let back = await GitStash.apply(entry, in: root, keeping: false)
						if back.exitCode != 0 {
							Toast.post("Could not put it back", detail: back.stderr)
						}
						self?.refresh()
						self?.onRepositoryChanged?()
					}
				}
			))
		}
	}

	// MARK: - Worktrees

	@objc func openWorktree() {
		guard let worktree = selectedWorktree, !worktree.isMissing else { return }
		onOpenWorktree?(worktree.path)
	}

	@objc func addWorktree() {
		let branch = selectedBranch
		let suggested = branch?.name ?? ""

        promptForName(
			title: "New Worktree",
			message: branch.map { "Checks out \($0.name) in a directory of its own." }
				?? "A second checkout of this repository, on a branch of its own.",
			defaultValue: suggested.isEmpty ? "worktree" : suggested
		) { [weak self] name in
			guard let self else { return }
			let path = GitWorktrees.suggestedPath(for: name, root: self.root)
			// An existing branch is checked out; anything else is created.
			let exists = self.branches.contains { $0.kind == .local && $0.name == name }
			self.run {
				await GitWorktrees.add(
					at: path, branch: name, createBranch: !exists, in: self.root
				)
			}
		}
	}

	@objc func removeWorktree() {
		guard let worktree = selectedWorktree, !worktree.isPrimary else { return }

		let alert = NSAlert()
		alert.messageText = "Remove the worktree “\(worktree.name)”?"
		alert.informativeText = worktree.isMissing
			? "Its directory is already gone; this forgets it."
			: "The directory and anything uncommitted in it are removed. The branch stays."
		alert.addButton(withTitle: "Remove")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			self.run { await GitWorktrees.remove(worktree, force: true, in: self.root) }
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	@objc func revealWorktree() {
		guard let worktree = selectedWorktree else { return }
		NSWorkspace.shared.activateFileViewerSelecting([worktree.path])
	}

	@objc func contextCheckout() { checkoutSelected() }

	@objc func newBranch() {
		promptForName(
			title: "New Branch",
			message: selectedBranch.map { "Branched from \($0.name)." } ?? "Branched from the current commit.",
			defaultValue: ""
		) { [weak self] name in
			guard let self else { return }
			let start = self.selectedBranch.map(\.checkoutName)
			self.run { await GitBranches.create(name, from: start, checkout: true, in: self.root) }
		}
	}

	@objc func fastForwardBranch() {
		guard let branch = selectedBranch, case .local = branch.kind else { return }
		let root = self.root

		Task { @MainActor [weak self] in
			let outcome = await GitFastForward.advance(branch: branch.name, in: root)
			guard let self else { return }

			// **Every one of these says what kind of news it is, and that is a
			// fix rather than a flourish.** `Toast.post` defaults to `.error`,
			// so a fast-forward that did exactly what was asked came up in red
			// under a window titled *Error*, saying "main moved 1 commit" — the
			// success and the failure were indistinguishable, and the one people
			// see most often is the success. Reported from use.
			switch outcome {
			case let .moved(commits):
				Toast.post(
					"\(branch.name) moved \(commits == 1 ? "1 commit" : "\(commits) commits")",
					detail: "Fast-forwarded to \(branch.upstream ?? "its upstream"). "
						+ "Nothing was checked out.",
					kind: .information
				)
			case .alreadyThere:
				Toast.post(
					"\(branch.name) is already up to date",
					detail: "It is already at \(branch.upstream ?? "its upstream").",
					kind: .information
				)
			// The three below did nothing, and none of them is a fault: there
			// was simply nothing to do, or what was asked for is not this
			// gesture. A warning says "read me" without saying "something broke".
			case .noUpstream:
				Toast.post(
					"\(branch.name) has no upstream",
					detail: "There is nothing to fast-forward it to.",
					kind: .warning
				)
			case let .diverged(ahead):
				// Named rather than refused silently: the branch has work on it,
				// and which work is the thing somebody needs to know before
				// deciding what to do about it.
				Toast.post(
					"\(branch.name) has moved on its own",
					detail: "\(ahead == 1 ? "One commit is" : "\(ahead) commits are") on it and not "
						+ "on \(branch.upstream ?? "its upstream"), so this is not a fast-forward. "
						+ "Merge or rebase it instead.",
					kind: .warning
				)
			case .checkedOut:
				Toast.post(
					"\(branch.name) is checked out",
					detail: "Bringing the branch you are on up to date is a pull.",
					kind: .warning
				)
			case let .refused(said):
				// The only one that is an error, and it keeps the red.
				self.presentFailure(said)
			}

			self.refresh()
			self.onRepositoryChanged?()
		}
	}

	@objc func mergeIntoCurrent() {
		guard let branch = selectedBranch else { return }
		run { await GitBranches.merge(branch.checkoutName, in: self.root) }
	}

	/// Replays the branch that is checked out on top of the one clicked.
	///
	/// **Asked first, unlike merge, and that is not an inconsistency.** A merge
	/// adds a commit and can be undone by removing it; a rebase rewrites every
	/// commit on the current branch, so the thing it changes is the work
	/// somebody has not pushed yet. One sentence naming both branches is what
	/// stops it being the wrong two.
	@objc func rebaseOntoBranch() {
		guard let branch = selectedBranch, !branch.isCurrent else { return }
		let onto = branch.checkoutName
		let current = currentBranchName ?? "this branch"

		let alert = NSAlert()
		alert.messageText = "Rebase \(current) on \(onto)"
		alert.informativeText = "Every commit on \(current) is rewritten on top of "
			+ "\(onto). \(onto) does not move. A conflict stops the rebase part-way "
			+ "and the changes list shows what to settle."
		alert.addButton(withTitle: "Rebase")
		alert.addButton(withTitle: "Cancel")
		guard alert.runModal() == .alertFirstButtonReturn else { return }

		run { await GitBranches.rebase(onto: onto, in: self.root) }
	}

	/// The local branches a delete would act on: never the one checked out, and
	/// never a remote branch or a tag.
	///
	/// Deleting a remote branch is a push, which `CLAUDE.md` forbids outright
	/// except when somebody asks for it by name — so it is not something a
	/// multiple selection should be able to do by accident.
	/// Whether this branch is finished: everything on it is somewhere else.
	///
	/// **Both kinds, asked of the right target.** A local branch is measured
	/// against the local default and a remote-tracking one against the remote's
	/// — which is why there are two sets rather than one. Until this, the
	/// pane marked a finished local branch and said nothing whatsoever about
	/// the remote copy of the same work, which is the copy somebody has to go
	/// and delete.
	func isMerged(_ branch: GitBranch) -> Bool {
		switch branch.kind {
		case .local:
			return !branch.isCurrent && mergedBranches.contains(branch.name)
		case .remote(let remote):
			return mergedRemoteBranches.contains("\(remote)/\(branch.name)")
		case .tag:
			return false
		}
	}

	var deletableBranches: [GitBranch] {
		selectedBranches.filter { $0.kind == .local && !$0.isCurrent }
	}

	@objc func deleteBranch() {
		deletion().ask(about: deletableBranches, target: currentBranchName ?? "HEAD")
	}

	/// The tags in the selection — and only where every selected row is one.
	///
	/// **A mixed selection is two questions.** A branch delete asks about
	/// worktrees and about commits nothing else has; a tag delete asks about a
	/// remote. Offering either over a selection holding both would act on half
	/// of it, so neither is offered.
	var deletableTags: [GitBranch] {
		let tags = selectedBranches.filter { $0.kind == .tag }
		return tags.count == selectedBranches.count ? tags : []
	}

	@objc func deleteTag() {
		let tags = deletableTags
		guard !tags.isEmpty else { return }
		madeDeletion().ask(about: tags)
	}

	/// One `TagDeletion` per press, told what this pane knows — the shape
	/// `deletion()` has for branches.
	private func madeDeletion() -> TagDeletion {
		// The remote from the rows the tree already holds rather than a fresh
		// `git remote`: the sheet opens on a press, and a process between the
		// press and the sheet is a press that hangs on a slow disk. `origin`
		// where there is one, since that is where a tag anybody else reads
		// lives; otherwise whichever remote the listing has.
		let named = branches.compactMap { branch -> String? in
			if case .remote(let name) = branch.kind { return name }
			return nil
		}
		let remote = named.contains("origin") ? "origin" : named.first
		let deletion = TagDeletion(root: root, remote: remote, window: window)
		deletion.onDeleting = { [weak self] names in
			guard let self else { return }
			self.deletingBranches = names
			self.reloadKeepingSelection { self.tableView.reloadData() }
		}
		deletion.onFinished = { [weak self] in
			self?.deletingBranches = []
			self?.refresh()
		}
		return deletion
	}

	/// Drives the tag delete from outside, through the same door the menu item
	/// goes through — the sheet included, for a run that photographs it.
	func deleteTagForTesting() { deleteTag() }

	/// The same delete with the sheet's answer given, for a run that cannot
	/// press a modal: it says what the sheet would have said and then does what
	/// agreeing to it does.
	func deleteTagForTesting(alsoOnRemote: Bool) {
		madeDeletion().askForTesting(about: deletableTags, alsoOnRemote: alsoOnRemote)
	}

	/// The remote branches in the selection, all on one remote.
	///
	/// **One remote at a time.** A selection spanning `origin` and a fork is
	/// two pushes to two places, and one dialog headed by one of them would be
	/// telling half the truth about what the press does. The remote taken is
	/// the one the row under the pointer belongs to.
	var deletableRemoteBranches: [GitBranch] {
		guard let remote = selectedRemote else { return [] }
		return selectedBranches.filter {
			if case .remote(let name) = $0.kind { return name == remote }
			return false
		}
	}

	/// Which remote the selection is on, when it is all on one.
	private var selectedRemote: String? {
		let remotes = Set(selectedBranches.compactMap { branch -> String? in
			if case .remote(let name) = branch.kind { return name }
			return nil
		})
		return remotes.count == 1 ? remotes.first : nil
	}

	@objc func deleteRemoteBranch() {
		guard let remote = selectedRemote else { return }
		let branches = deletableRemoteBranches
		guard !branches.isEmpty else { return }
		deletingRemote = remote
		// The remote's own default, which is what a branch has to be inside
		// before deleting it from there loses nothing.
		let target = "\(remote)/\(defaultBranch ?? "main")"
		deletion().askAboutRemote(branches, on: remote, target: target)
	}

	/// What a row is waiting on, which is also what it says while it waits —
	/// nil for a row that is not waiting on anything.
	///
	/// **Local rows only.** A remote row's `name` is the branch's name without
	/// its remote, so `origin/x` and `x` answer the same here, and pushing one
	/// used to set the other spinning.
	func busyNote(for branch: GitBranch) -> String? {
		switch branch.kind {
		case .local:
			if branch.name == pushingBranch { return "Pushing \(branch.name)…" }
			if deletingBranches.contains(branch.name) { return "Deleting \(branch.name)…" }
			return nil
		case .remote(let remote):
			// Only while a *remote* delete is running, which is the only thing
			// that touches these rows. `deletingRemote` is the remote whose
			// branches are going, and it is nil for a local delete — otherwise
			// deleting `x` locally would set `origin/x` spinning over work
			// nobody had asked for.
			guard deletingRemote == remote, deletingBranches.contains(branch.name) else {
				return nil
			}
			return "Deleting from \(remote)…"
		case .tag:
			return nil
		}
	}

	/// One `BranchDeletion` per press, told what this pane knows: where the
	/// repository is, what checkouts it has, and who to tell afterwards.
	func deletion() -> BranchDeletion {
		let made = BranchDeletion(root: root, worktrees: worktrees, window: window)
		made.onDeleting = { [weak self] names in
			guard let self else { return }
			self.deletingBranches = names
			self.reloadKeepingSelection { self.tableView.reloadData() }
		}
		made.onFinished = { [weak self] in
			self?.deletingRemote = nil
			self?.refresh()
			self?.onRepositoryChanged?()
		}
		made.onFailure = { [weak self] said in self?.presentFailure(said) }
		return made
	}

	/// Copies what the selected branches are called, one a line.
	///
	/// All of them, because selecting three and being given one is the same
	/// shrinking-selection surprise `TreeSelection` exists for elsewhere — and
	/// because the reason to select several branches at once is nearly always to
	/// paste the list somewhere.
	///
	/// `checkoutName` rather than the display name: what is copied should be
	/// what can be typed at git, and a remote branch's row says `main` where git
	/// wants `origin/main`.
	@objc func copyBranchName() {
		let names = selectedBranches.map(\.checkoutName)
		guard !names.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
	}

	/// Asks for a branch name, rejecting ones git would refuse.
	func promptForName(
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

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		field.stringValue = defaultValue
		alert.accessoryView = field

		let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			let name = field.stringValue.trimmingCharacters(in: .whitespaces)

			// Checked here so the failure is a sentence rather than git's
			// message about ref formats.
			if let problem = GitBranches.validationError(forName: name) {
				self?.presentFailure(problem)
				return
			}
			act(name)
		}

		if let window {
			alert.beginSheetModal(for: window) { response in
				// The field must be first responder for typing to reach it.
				handle(response)
			}
			window.makeFirstResponder(field)
		} else {
			handle(alert.runModal())
		}
	}

	func run(_ operation: @escaping () async -> GitRepository.ProcessResult) {
		Task { @MainActor in
			let result = await operation()
			if result.exitCode != 0 {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}
			refresh()
			onRepositoryChanged?()
		}
	}

	func presentFailure(_ message: String) {
		Toast.post(
			"git reported a problem",
			detail: message.trimmingCharacters(in: .whitespacesAndNewlines)
		)
	}

	func applyThemeChange() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		filterStrip?.applyThemeChange()
		// The palette moved, the rows did not: a theme change used to be the
		// one way to lose the selection without touching the repository.
		reloadKeepingSelection { tableView.reloadData() }
	}
}

import AppKit
import AbydosKit

/// Staging, discarding, and making a commit out of what is staged.
///
/// The message is here too — composed, drafted, remembered and restored —
/// because it is the same act: everything in this file ends in a commit or in
/// deciding not to make one.
extension ChangesPane {
	// MARK: - Discarding

	/// What a discard from the menu would take: the paths git is given, the
	/// unstaged changes they cover, and the row it is named after.
	///
	/// Nil for a staged row, which is the decision this entry turned on.
	/// `checkout --` restores the work tree *from the index*, so over a staged
	/// change it would throw away nothing that is staged: the change would
	/// survive, the row would not go away, and the menu would have offered to
	/// destroy something and then not done it. `restore --staged --worktree` was
	/// the other answer and is deliberately not this one — a file staged and
	/// then edited again is a row in each list, and discarding it from the
	/// staged row would also take the later edit, which is only shown in the
	/// other list. Unstage first: that is recoverable, it is one item up the
	/// same menu, and it puts the row where discard already is. The diff view
	/// hides Discard Selected Lines over a staged hunk for the same reason, and
	/// the two should not disagree about what the word means.
	///
	/// The selection when the click landed inside it and the clicked row
	/// otherwise — the rule stash and every other list here follows.
	func discardable() -> (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)? {
		guard let clicked = clickedNode, !clicked.isStaged else { return nil }
		return discardable(node: clicked.node)
	}

	/// The same question asked about a row by name, so that what the menu would
	/// say can be printed without a right-click. `clickedRow` is set by the
	/// event and by nothing else, which is what makes the split worth having.
	func discardable(
		node: GitChangeNode
	) -> (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)? {
		guard let table = unstagedTable else { return nil }
		let selected = selectedPaths(in: table)
		let paths = GitChangeTree.reduce(
			selected.contains(node.path) ? selected : [node.path]
		)
		let changes = GitDiscard.changes(status.unstaged, under: paths)
		guard !changes.isEmpty else { return nil }

		// Never over a conflict. `git checkout -- <unmerged path>` refuses with
		// "path is unmerged", so the entry would be one that always fails; and
		// throwing away a half-resolved merge is a different question, with
		// more than one right answer, that this item did not decide.
		guard !changes.contains(where: { $0.kind == .conflicted }) else { return nil }

		// One path may still be a folder standing for forty files, and it is not
		// necessarily the row that was clicked: `reduce` drops a file whose
		// folder is selected too, and the folder is what git is handed.
		let subject: GitDiscard.Subject
		if paths.count == 1, let only = unstagedSide.byPath[paths[0]] {
			subject = only.isFolder ? .folder(only.name) : .file(only.name)
		} else {
			subject = .rows
		}
		return (paths, changes, subject)
	}

	/// How many files a discard covers, and how many of those git has never seen.
	func discardCounts(
		_ target: (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)
	) -> (files: Int, untracked: Int) {
		(target.changes.count, target.changes.filter { $0.kind == .untracked }.count)
	}

	/// Asks, and only then throws the work away.
	///
	/// Everything else in this menu is recoverable — a stash can be popped,
	/// staging can be unstaged, a `.gitignore` line can be deleted. This is the
	/// one entry with no way back, and for an untracked file there is not even a
	/// git object left afterwards, so it is the one entry that asks.
	@objc func discardClicked() {
		guard let target = discardable() else { return }
		let counts = discardCounts(target)

		let alert = NSAlert()
		alert.messageText = GitDiscard.question(
			subject: target.subject, files: counts.files, untracked: counts.untracked
		)
		alert.informativeText = GitDiscard.explanation(
			files: counts.files, untracked: counts.untracked
		)
		alert.addButton(withTitle: GitDiscard.buttonTitle(
			files: counts.files, untracked: counts.untracked
		))
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			self?.performDiscard(target)
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	/// What pressing the confirmation's button does.
	func performDiscard(
		_ target: (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)
	) {
		// Discarding empties rows out of the tree exactly as staging does, so
		// the selection is given somewhere to land first.
		rememberWhereTheSelectionGoes(in: unstagedTable, staged: false)

		// **The most-used destructive verb in the app, now insured.** The
		// question above is `GitDiscard`'s and stays that way — it names the
		// folder and counts what git has never seen, which no general dialog
		// could — so what is borrowed from the safety net is the ref, made
		// before anything is restored, and the toast that says where it went.
		// **The safety net is asked once for the whole operation and every
		// repository is insured before any file is discarded.** Insuring and
		// discarding repository by repository has no way back from a failure
		// part way through — the ones before it have moved and only some were
		// recorded. Two hundred questions is also no question at all: a dialogue
		// repeated per repository is answered by holding Return, and two hundred
		// toasts afterwards are read by nobody.
		runAcrossOwners(target.paths, reporting: false) { paths, estate in
			let insured = await DestructiveAsk.insureEstate(estate.grouped(paths))
			let outcomes = await GitEstateOperation.discard(paths: paths, in: estate)
			DestructiveAsk.sayWhatHappened("discarded", outcomes, insured: insured)
			return outcomes
		}
	}

	/// Return, or a double-click.
	///
	/// A double-click on a folder opens it, as it does in the project tree, and
	/// only Return or the button stages one. Staging forty files off a stray
	/// second click is a lot to have to undo, and the two trees in this window
	/// answering the same gesture differently would be worse than either.
	func activate(row: Int, in outline: ChangesOutlineView) {
		if row >= 0, let node = outline.item(atRow: row) as? GitChangeNode, node.isFolder {
			if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
			return
		}
		if outline === stagedTable { unstageSelected() } else { stageSelected() }
	}

	@objc func stageClicked() {
		guard let clicked = clickedNode else { return }
		runAcrossOwners([clicked.node.path], moving: .toStaged) { await GitEstateOperation.stage(paths: $0, in: $1) }
	}

	@objc func unstageClicked() {
		guard let clicked = clickedNode else { return }
		runAcrossOwners([clicked.node.path], moving: .toUnstaged) { await GitEstateOperation.unstage(paths: $0, in: $1) }
	}

	/// Stages what is selected — a folder as one path, which is the whole of
	/// what folder staging costs.
	///
	/// `git add` has always taken a directory and `-A` already means a deletion
	/// under it is staged as a deletion, so a folder is one argument instead of
	/// forty in the same argument list. `unstage` is the same shape.
	func stageSelected() {
		StallWatch.mark("stage") {
			let paths = GitChangeTree.reduce(selectedPaths(in: unstagedTable))
			guard !paths.isEmpty else { return }
			runAcrossOwners(paths, moving: .toStaged) { await GitEstateOperation.stage(paths: $0, in: $1) }
		}
	}

	func unstageSelected() {
		StallWatch.mark("stage") {
			let paths = GitChangeTree.reduce(selectedPaths(in: stagedTable))
			guard !paths.isEmpty else { return }
			runAcrossOwners(paths, moving: .toUnstaged) { await GitEstateOperation.unstage(paths: $0, in: $1) }
		}
	}

	/// Clicks into the details field and types, and says what happened.
	///
	/// Through the window's hit testing, because what was wrong was that the
	/// click never reached the text view: a test that typed into it directly
	/// would have passed while the field stayed impossible to use.
	func typeInCommitBodyForTesting(_ text: String) -> String {
		guard let window, let root = window.contentView else { return "no window" }

		let middle = NSPoint(x: bodyView.bounds.midX, y: bodyView.bounds.midY)
		let inWindow = bodyView.convert(middle, to: nil)
		let hit = root.hitTest(inWindow)
		let landed = hit === bodyView || (hit?.isDescendant(of: bodyView) ?? false)

		if landed {
			window.makeFirstResponder(bodyView)
			bodyView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
		}

		let name = hit.map { String(describing: type(of: $0)) } ?? "nothing"
		return "hit=\(landed ? "body" : name) frame=\(NSStringFromRect(bodyView.frame))"
			+ " body=\(bodyView.string.debugDescription)"
	}

	/// Hands what has been typed to whoever opens the page.
	@objc func openPage() {
		onOpenPage?(subjectField.stringValue)
	}

	/// Fills the two fields from what is staged.
	///
	/// The last twenty commit messages, read from the log when the menu opens —
	/// opened rarely, costs milliseconds, and a cache would be one more thing
	/// to invalidate on every commit.
	@objc func openMessageHistory() {
		guard let button = historyButton else { return }
		Task { @MainActor [weak self] in
			guard let self else { return }
			let commits = await GitHistory.log(in: root, limit: 20)
			guard !commits.isEmpty else { return }
			let menu = NSMenu()
			for (index, commit) in commits.enumerated() {
				let item = NSMenuItem(
					title: Self.historyTitle(for: commit),
					action: #selector(useHistoryMessage(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.tag = index
				item.representedObject = [commit.subject, commit.body]
				menu.addItem(item)
			}
			menu.popUp(
				positioning: nil,
				at: NSPoint(x: 0, y: button.bounds.maxY + Theme.current.scaled(4)),
				in: button
			)
		}
	}

	/// The subject with its age beside it: the subject is how a commit is
	/// spoken about, and the age is what tells two "Fix build" entries apart.
	static func historyTitle(for commit: GitCommit) -> String {
		var subject = commit.subject
		if subject.count > 60 {
			subject = subject.prefix(29) + "…" + subject.suffix(29)
		}
		return "\(subject)   —   \(CommitRowView.age(of: commit.date))"
	}

	/// **Choosing replaces.** A history entry is the explicit decision to use
	/// that message, unlike a refresh, which never touches typing — and nobody
	/// wants yesterday's message concatenated onto today's half sentence.
	/// Nothing is staged and nothing committed; both fields stay editable.
	@objc private func useHistoryMessage(_ sender: NSMenuItem) {
		guard let parts = sender.representedObject as? [String], parts.count == 2 else { return }
		fill(subject: parts[0], body: parts[1])
	}

	func fill(subject: String, body: String) {
		subjectField.stringValue = subject
		bodyView.string = body
		updateCommitButton()
	}

	/// The message being composed, for the session to write down.
	///
	/// Both halves: the description is where the *why* goes and is the expensive
	/// one to lose. Nil where nothing has been typed, so that a pane somebody
	/// has not touched does not make a session out of two empty strings.
	var composedMessage: ProjectSession.ComposedMessage? {
		let message = ProjectSession.ComposedMessage(
			summary: subjectField.stringValue, description: bodyView.string
		)
		return message.isEmpty ? nil : message
	}

	/// Puts a remembered message back, and only where nothing has been typed
	/// since.
	///
	/// The rule the draft already follows: somebody who has started typing in
	/// this pane has said something more recent than the session file has. The
	/// description is opened where it has something in it, for the reason a
	/// draft opens it — a description behind a chevron reads as one that was
	/// not restored.
	func restore(message: ProjectSession.ComposedMessage) {
		if subjectField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
			subjectField.stringValue = message.summary
		}
		if bodyView.string.trimmingCharacters(in: .whitespaces).isEmpty {
			bodyView.string = message.description
		}
		if !bodyView.string.trimmingCharacters(in: .whitespaces).isEmpty {
			setDescription(showing: true)
		}
		updateCommitButton()
		// A draft may have come back while this project was away. Asked after
		// the remembered message is in, so a draft meeting restored words
		// becomes an offer rather than writing over them.
		applyHeldDraft()
	}

	/// **A draft, and never a commit.** Nothing is staged, nothing is
	/// committed, both fields stay editable, and `Commit` is not disabled while
	/// this is thinking — a slow answer must not become a blocked one.
	@objc func draftMessage() {
		guard draftButton != nil else { return }
		let root = self.root

		// **Taking an offer comes before the consent question**, and getting
		// that order wrong made the offer unpressable: nothing is sent when an
		// answer already in hand is written into the fields, but the guard
		// below asked to send anyway and opened the consent sheet instead.
		// Driven, and that is how it was caught.
		//
		// The button *is* the offer, so there is no second control to find.
		if draftState == .offering {
			takeHeldDraft()
			return
		}

		// **Said once, before it happens.** The staged diff leaves this machine
		// when this button is pressed, and that is not something to find out
		// from a release note afterwards. Per project, because agreeing for a
		// scratch repository is not agreeing for a client's.
		guard Settings.shared.maySendDiffs(from: root) else {
			askBeforeSending(from: root)
			return
		}

		draftState = .drafting
		let hand = onDraft

		Task { @MainActor [weak self] in
			let answer = await ClaudeDraft.draft(
				in: root, conventional: Settings.shared.conventionalCommitDrafts
			)

			switch answer {
			case let .success(draft):
				// **Handed over, not written in.** `guard let self` used to
				// stand here: a pane released by a project switch dropped the
				// answer without a word, and a pane still on screen for the
				// project somebody just left took it and had it written into
				// the *new* project's session at the next save. The inbox is
				// keyed by the root this was asked for, and outlives both.
				hand?(root, draft)
				// And applied here only if this pane is still the one that
				// asked — which the inbox decides, not this closure.
				self?.applyHeldDraft()
			case .failure(.nothingStaged):
				self?.draftState = .idle
				Toast.post("Nothing is staged", detail: "There is no commit to describe yet.")
			case .failure(.notInstalled):
				self?.draftState = .idle
				Toast.post("claude is not on the PATH")
			case let .failure(.said(what)):
				self?.draftState = .idle
				Toast.post("The draft did not come back", detail: what)
			}
		}
	}

	/// Takes whatever the inbox is holding for this pane's project, if this
	/// pane is one that should have it.
	///
	/// **The pane's own root decides, not the window's project.** The window is
	/// already on B while A's pane is still on screen — that gap is where the
	/// report lives — and a pane's root is the one thing about it that is true
	/// from the moment it is built.
	///
	/// Empty fields are filled; fields with words in them make an offer. The
	/// draft stays in the inbox until it is taken, so a pane rebuilt in between
	/// finds it again.
	func applyHeldDraft() {
		guard window != nil, let draft = heldDraft?(root) else { return }

		let hasSubject = !subjectField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
		let hasBody = !bodyView.string.trimmingCharacters(in: .whitespaces).isEmpty
		guard !hasSubject, !hasBody else {
			// **Whole or nothing.** Filling whichever field was empty is what
			// this used to half-do, and it made messages nobody wrote: a typed
			// subject with an empty body took the draft's description and lost
			// its summary.
			draftState = .offering
			return
		}

		onDraftTaken?(root)
		fill(subject: draft.summary, body: draft.description)
		// The one moment the description fills without anybody typing in it,
		// and so the one moment the collapsed default would hide work that has
		// just been done. A draft that wrote three paragraphs behind a chevron
		// would read as a draft that failed.
		if !bodyView.string.trimmingCharacters(in: .whitespaces).isEmpty {
			setDescription(showing: true)
		}
		draftState = .idle
	}

	/// Replaces both fields with what is being offered, which is what pressing
	/// *Use draft instead* means.
	///
	/// Both, and not the empty one: replacing is the semantics choosing from
	/// the history already has, and a draft merged into typed words is a third
	/// message nobody wrote.
	private func takeHeldDraft() {
		guard let draft = heldDraft?(root) else {
			draftState = .idle
			return
		}
		onDraftTaken?(root)
		fill(subject: draft.summary, body: draft.description)
		if !bodyView.string.trimmingCharacters(in: .whitespaces).isEmpty {
			setDescription(showing: true)
		}
		draftState = .idle
	}

	/// Says what drafting will do, once per project, before it does it.
	private func askBeforeSending(from root: URL) {
		let alert = NSAlert()
		alert.messageText = "Send this project's staged diff to Anthropic?"
		alert.informativeText = "Drafting a message runs the claude command with what is staged, "
			+ "and the last twenty commit subjects from this repository, so the summary matches "
			+ "how this project is written.\n\nAsked once for this project."
		alert.addButton(withTitle: "Draft Messages Here")
		alert.addButton(withTitle: "Cancel")

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			Settings.shared.agreeToSendDiffs(from: root)
			self?.draftMessage()
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	@objc func amendToggled() {
		// Turning amend on offers the previous message, since rewording is the
		// usual reason to amend. It is not forced on a message already typed.
		if amendCheckbox.state == .on, subjectField.stringValue.isEmpty, bodyView.string.isEmpty {
			Task { @MainActor in
				guard let previous = await GitWorkingCopy.lastCommitMessage(in: root) else { return }
				subjectField.stringValue = previous.subject
				bodyView.string = previous.body
				updateCommitButton()
			}
		}
		updateCommitButton()
	}

	@objc func commit() {
		let subject = subjectField.stringValue
		let body = bodyView.string
		let amend = amendCheckbox.state == .on
		guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else { return }

		isBusy = true
		// A commit runs `.git/hooks/pre-commit`, which is code the project
		// carries and a clone brings with it. An untrusted project's hooks are
		// declined rather than the commit being refused — and it is said here,
		// where the commit was made, because the danger of `--no-verify` is
		// somebody not knowing it happened.
		let hooks = ProjectTrust.shared.isTrusted(root)
		Task { @MainActor in
			let result = await GitWorkingCopy.commit(
				subject: subject, body: body, amend: amend, in: root, runsHooks: hooks
			)
			endBusy()

			guard result.exitCode == 0 else {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
				return
			}
			if !hooks {
				Toast.post("Committed without hooks", detail: GitWorkingCopy.hooksDeclined, kind: .information)
			}

			subjectField.stringValue = ""
			bodyView.string = ""
			amendCheckbox.state = .off
			// The offer went with the message it was offered against: a draft
			// describing a commit that has just been made is not a draft for
			// the next one.
			if draftState == .offering {
				onDraftTaken?(root)
				draftState = .idle
			}
			refresh()
			onWorkingCopyChanged?()
		}
	}

	/// Runs a git command, then refreshes both this view and the navigator.
	/// Stages, unstages or discards, in whichever repositories own the paths.
	///
	/// One command per owning repository, which is correctness before it is
	/// thrift: `git add`, `restore`, `reset` and `clean` resolve a pathspec
	/// against the repository they run in, so a submodule's file handed to the
	/// superproject stages nothing and says `pathspec did not match`. See
	/// `GitEstateOperation`.
	/// - Parameter reporting: whether to say what failed. False where the
	///   operation says more than that for itself — a discard reports every
	///   repository and its backup ref, and two reports would be one too many.
	/// Which side an operation's rows land on, for showing the landing before
	/// the status read confirms it.
	enum OptimisticMove { case toStaged, toUnstaged }

	/// The operation in flight, so the next one starts after it rather than
	/// beside it. Two stages clicked quickly enough raced each other for
	/// git's `index.lock`: whichever `git add` lost the race failed, and the
	/// click it stood for was silently gone — found by driving exactly that
	/// pair of clicks.
}

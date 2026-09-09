import AppKit
import AbydosKit

/// What the tree is showing: reading the refs, arranging them into sections and
/// folders, and keeping the folds and the selection across a reload.
extension BranchesPane {
	// MARK: - Data

	/// The refresh verb: re-read everything this pane shows, and say that it is
	/// happening.
	///
	/// The spinner is the point. `refresh` is several git calls and on a large
	/// repository it takes long enough that a button with no feedback reads as a
	/// button that did nothing — so somebody presses it again.
	/// The `Fetch` verb beside the traffic one.
	///
	/// **Only where there is a remote**, and nothing where there is not. The
	/// glyph used to fall back to a local re-read there, which was doing what
	/// the pane's own filesystem watcher already does on every event — and a
	/// control quietly meaning two different things depending on state is
	/// half of why the glyph was unreadable. Re-reading is `Read the
	/// Repository Again` on this row's menu, where it was already.
	func fetchPressed() {
		guard trafficState?.hasRemote == true else { return }
		fetch(pruning: false)
	}

	/// Asks the remote, then re-reads everything the answer changes.
	///
	/// Failure is said and the read still happens: a fetch that could not reach
	/// the remote leaves the repository exactly as it was, and a pane that
	/// refused to redraw because the network was down would be showing stale
	/// counts *and* refusing to admit it.
	private func fetch(pruning: Bool) {
		activity = PaneActivityView.install(
			over: self, message: pruning ? "Fetching and pruning…" : "Fetching…"
		)
		let root = self.root
		Task { @MainActor [weak self] in
			let result = await GitPull.fetch(in: root, pruning: pruning)
			guard let self else { return }
			if result.exitCode != 0 {
				self.presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}
			self.refresh()
			self.refreshConflicts()
			self.refreshTraffic()
			self.onRepositoryChanged?()
		}
	}

	/// What the repository row offers on a right-click: every remote verb, and
	/// when the remote was last asked.
	///
	/// The four are all here rather than only the one the row happens to be
	/// drawing. `Push` while `1 ahead` is a claim about a tracking ref that is
	/// as old as the last fetch, and until this menu the only way to check it
	/// was a terminal.
	func remoteMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		let state = trafficState

		// **When, said first.** Every count on this row is a statement about a
		// tracking ref, and a tracking ref is a copy of what the remote said
		// the last time somebody asked.
		let when = NSMenuItem(title: lastFetchWording, action: nil, keyEquivalent: "")
		when.isEnabled = false
		menu.addItem(when)
		menu.addItem(.separator())

		for (title, pruning) in [("Fetch", false), ("Fetch and Prune", true)] {
			let item = NSMenuItem(
				title: title,
				action: pruning ? #selector(fetchPruning) : #selector(fetchPlainly),
				keyEquivalent: ""
			)
			item.target = self
			item.isEnabled = state?.hasRemote == true
			menu.addItem(item)
		}
		// Prune is the answer to an upstream somebody deleted, so it says so
		// where that is the state the row is in.
		if state?.upstreamIsGone == true {
			menu.items.last?.toolTip = "The upstream is gone — pruning clears the tracking ref"
		}

		menu.addItem(.separator())
		let pull = NSMenuItem(title: "Pull…", action: #selector(pullWithDialog), keyEquivalent: "")
		pull.target = self
		pull.isEnabled = state?.hasRemote == true && state?.upstream != nil
		menu.addItem(pull)

		let push = NSMenuItem(
			title: "Push", action: #selector(pushCurrentBranchFromMenu), keyEquivalent: ""
		)
		push.target = self
		push.isEnabled = state?.canPush == true
		menu.addItem(push)

		menu.addItem(.separator())
		// The local read the glyph used to be, kept: after a rebase in a
		// terminal there is nothing to fetch and no reason to wait for one.
		let reread = NSMenuItem(
			title: "Read the Repository Again", action: #selector(rereadOnly), keyEquivalent: ""
		)
		reread.target = self
		menu.addItem(reread)
		return menu
	}

	/// How long ago the remote was last asked, in words.
	private var lastFetchWording: String {
		guard let when = lastFetchedAt else { return "Never fetched here" }
		let seconds = Date().timeIntervalSince(when)
		if seconds < 90 { return "Fetched just now" }
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return "Fetched \(formatter.localizedString(for: when, relativeTo: Date()))"
	}

	@objc private func fetchPlainly() { fetch(pruning: false) }
	@objc private func fetchPruning() { fetch(pruning: true) }
	@objc private func pushCurrentBranchFromMenu() { pushCurrentBranch() }

	@objc private func rereadOnly() {
		activity = PaneActivityView.install(over: self, message: "Reading branches…")
		refresh()
		refreshConflicts()
		refreshTraffic()
	}

	@objc func refresh() {
		Task { @MainActor in
			// **The default branch is read first**, because the listing is
			// measured against it: a branch that has never been pushed has no
			// upstream to count from, and how far it has come from the branch
			// it will go back into is the only thing that can be said about it.
			self.defaultBranch = await BranchGrouping.defaultBranch(in: root)
			let fresh = await GitBranches.list(in: root, comparedTo: self.defaultBranch)
			self.working = await self.readEstate()
			// Before the trees are built, so `add(changes:)` fills from a cache
			// that holds only directories git still reports.
			let directories = Set(
				(self.working.unstaged + self.working.staged).filter(\.isDirectory).map(\.path)
			)
			self.untrackedContents = self.untrackedContents.filter { directories.contains($0.key) }
			// In the estate, so a submodule is a repository row above its folders —
			// the same tree the commit page draws, from the same paths.
			self.unstagedRoots = GitChangeTree.build(
				self.working.unstaged, against: self.working.staged,
				in: self.submodules.estate
			)
			self.stagedRoots = GitChangeTree.build(
				self.working.staged, against: self.working.unstaged,
				in: self.submodules.estate
			)
			// Only the repository's own checkouts, and only when there is more
			// than one: a repository nobody has added a worktree to should not
			// carry a section explaining that it has one.
			let trees = await GitWorktrees.list(in: root)
			let put = await GitStash.list(in: root)
			remoteURL = await GitForge.remoteURL(in: root)
			if let main = self.defaultBranch {
				self.mergedBranches = await GitBranches.merged(into: main, in: root)
				// The remote's own default, per remote. `origin/main` is the
				// ref a branch has to be inside before deleting it from the
				// remote loses nothing — and `origin` is a convention rather
				// than a rule, so the list is asked for rather than assumed.
				var finished: Set<String> = []
				for remote in await GitBranches.remotes(in: root) {
					finished.formUnion(await GitBranches.mergedRemotes(
						into: "\(remote)/\(main)", in: root
					))
				}
				self.mergedRemoteBranches = finished
			} else {
				self.mergedBranches = []
				self.mergedRemoteBranches = []
			}
			self.refreshTraffic()
			self.refreshConflicts()
			forge = remoteURL.flatMap { GitForge.repository(fromRemote: $0) }
			// Before the comparison, so an unchanged answer still stops the
			// spinner — which for a repository nobody has touched is every
			// answer after the first.
			finishFirstRead()
			// The working copy is re-read every time and the rows rebuilt with it,
			// so an edit in the editor shows here without anything else moving.
			guard fresh != branches || trees != worktrees || put != stashes else {
				rebuildRows()
				return
			}
			branches = fresh
			worktrees = trees
			stashes = put
			rebuildRows()
		}
	}

	/// Says whether a merge has stopped, and what there is to do about it.
	private func refreshConflicts() {
		let root = self.root
		Task { @MainActor [weak self] in
			guard let self else { return }
			let operation = await GitConflicts.operation(in: root)
			let paths = await GitConflicts.paths(in: root)

			// **Not `paths != conflictPaths` any more.** That early return was
			// what made the banner vanish the moment the last file was
			// resolved: the paths went empty, the guard below hid the strip,
			// and the rebase — still in progress, still needing a
			// `--continue` — was left with nothing on screen saying so. The
			// operation is the thing that decides, and it changes at moments
			// the path list does not.
			guard let operation else {
				self.conflictPaths = paths
				self.currentOperation = nil
				self.conflictsThisStop = []
				self.conflictStopAt = nil
				self.conflictHeight.constant = 0
				self.conflictBanner.isHidden = true
				return
			}
			self.conflictPaths = paths
			self.currentOperation = operation

			let what = await GitConflicts.describe(in: root)
			let staged = await GitWorkingCopy.status(in: root).staged.isEmpty == false
			let progress = await GitConflicts.progress(in: root)
			let sides = await GitConflicts.sides(of: operation, in: root)

			// **A new stop starts a new set.** A rebase that carries on lands
			// on the next commit with its own conflicts, and remembering the
			// last one's would leave rows ticked for files this stop has never
			// been waiting on.
			if self.conflictStopAt != progress?.position {
				self.conflictStopAt = progress?.position
				self.conflictsThisStop = []
			}
			self.conflictsThisStop.formUnion(paths)
			// **And what git wrote down before it stopped.** The pane's memory
			// starts when the window opens; a merge reopened tomorrow would
			// otherwise show only what is still unresolved and count that as
			// the whole job. `.git/MERGE_MSG` holds the set under
			// `# Conflicts:`, which is the same list a day later — and git
			// removes the file when the stop is over, so it is never a
			// previous commit's set. A rebase writes one too.
			self.conflictsThisStop.formUnion(await GitConflicts.recorded(in: root))
			let waiting = await GitConflicts.waiting(
				in: root, alsoShowing: self.conflictsThisStop
			)

			self.conflictBanner.isHidden = false
			self.conflictBanner.show(
				operation: operation, waiting: waiting, staged: staged,
				what: what, sides: sides, progress: progress
			)
			// The strip asks for its own height: what it shows decides how
			// much it needs, and a constant here was a second opinion about
			// the same thing.
			self.conflictHeight.constant = self.conflictBanner.wantedHeight
		}
	}

	/// Clears one file, and says so when git will not.
	///
	/// **The refresh is the feedback.** Taking a side or staging a hand-edited
	/// file has no toast on success: the row ticks, the count under the
	/// headline moves, and `Continue` lights when the last one turns — which
	/// says more than a message that has to be read and dismissed.
	func resolveConflict(
		_ path: String, by work: @escaping @Sendable (URL) async -> String?
	) {
		let root = self.root
		Task { @MainActor [weak self] in
			let complaint = await work(root)
			guard let self else { return }
			if let complaint {
				// Git's own words. `error: path 'x' does not have our version`
				// is what a delete/modify conflict says, and it is better than
				// anything this could write over the top of it.
				Toast.post(
					"\(URL(fileURLWithPath: path).lastPathComponent) was not resolved",
					detail: complaint,
					kind: .warning
				)
			}
			self.refresh()
		}
	}

	/// `--continue` or `--skip`, and what to do when git will not.
	///
	/// The whole flow this pane was missing. Resolving the files was as far as
	/// it went; carrying the rebase on meant leaving for a terminal, and the
	/// commit page — which is where somebody naturally goes next — makes an
	/// ordinary commit, which is the wrong move in the middle of a rebase.
	func step(_ step: GitConflicts.Step) {
		guard let operation = currentOperation else { return }
		let root = self.root
		Task { @MainActor [weak self] in
			let outcome = await GitConflicts.run(step, on: operation, in: root)
			guard let self else { return }
			switch outcome {
			case .finished:
				Toast.post("\(operation.titled) finished", kind: .information)
			case .stopped:
				// It moved and stopped again — the next commit, or a conflict
				// in it. Nothing to say: the banner is about to redraw itself
				// with where it stopped, which says more than a toast could.
				break
			case .refused(let complaint):
				// Git's own words. `you must edit all merge conflicts and then
				// mark them as resolved using git add` is better advice than
				// anything this could write over the top of it.
				Toast.post(
					"\(operation.titled) would not \(step == .skip ? "skip" : "continue")",
					detail: complaint,
					kind: .warning
				)
			}
			self.refresh()
		}
	}

	/// Throwing the operation away is asked about first: `--abort` puts the
	/// work tree back where it was, and everything resolved since it stopped
	/// goes with it.
	func askAboutAborting() {
		guard let operation = currentOperation else { return }
		let alert = NSAlert()
		alert.messageText = "Abort the \(operation.noun)?"
		alert.informativeText = "The work tree goes back to where it was before the "
			+ "\(operation.noun) started. Anything resolved since it stopped is lost."
		alert.addButton(withTitle: "Abort \(operation.titled)")
		alert.addButton(withTitle: "Keep Going")
		alert.alertStyle = .warning
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		step(.abort)
	}

	/// Reads where the branch stands, and says it on the repository row.
	///
	/// The row decides its own wording and its own verb — which of behind,
	/// ahead, level, gone or no-remote it is looking at, and whether the pane
	/// is wide enough to say it in words. All this does is hand it the answer.
	private func refreshTraffic() {
		Task { @MainActor [weak self] in
			guard let self else { return }
			let state = await GitPush.state(in: self.root)
			let head = await GitRepository.head(in: self.root)
			let operation = await GitConflicts.operation(in: self.root)
			self.trafficState = state
			// Read beside the counts it dates: `1 ahead` is a claim about a
			// tracking ref, and this is when that ref was last true.
			self.lastFetchedAt = await GitPull.lastFetch(in: self.root)
			// **The tree row says where, the banner says what.** Both of them
			// saying both put `detached at c8bdfef0 · r…` in a row too narrow
			// for either half. Off the banner — no operation in progress —
			// the row is the only thing that can say it, so it says all of it.
			self.headNotice = Self.notice(
				head: head, operation: operation, sayingTheOperation: operation != nil ? false : true
			)
			// **Not on the repository row while the banner is up.** The strip
			// above it already says the operation, at length and with the
			// verbs — the row saying it too, truncated, put the same sentence
			// on screen twice in twenty-four points. Off the banner, the row
			// is the only thing that says it.
			// **Nothing where there is nowhere to fetch from.** A permanently
			// grey button is furniture; a repository with no remote simply has
			// no second verb, and its menu still carries the local re-read.
			self.repositoryRow.secondaryAction = state?.hasRemote == true
				? RowAction(
					title: "Fetch",
					help: "Fetch from the remote and read the repository again — "
						+ "right-click the row for pull, push and prune",
					isAlwaysShown: true
				)
				: nil
			self.repositoryRow.show(
				branch: self.currentBranchName,
				state: state,
				notice: operation == nil ? self.headNotice : nil,
				submodules: self.submodules.estate.count
			)

			// The tree says it too: the local section has no checkmark on
			// anything while the head is detached, and a row is where somebody
			// looks for where they are.
			self.rebuildRows()
		}
	}

	/// The state of the head, in the words both the row and the tree use — or
	/// nil when there is nothing out of the ordinary to say.
	private static func notice(
		head: GitRepository.Head,
		operation: GitConflicts.Operation?,
		sayingTheOperation: Bool = true
	) -> String? {
		var parts: [String] = []
		if head.isDetached, let display = head.display { parts.append(display) }
		if let operation, sayingTheOperation {
			// Titled when it starts the notice, which is a row of its own —
			// `Rebasing`, not `rebasing`. After a detached head it is the
			// second clause and stays lowercase.
			parts.append(parts.isEmpty ? operation.titled : operation.said)
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}

	/// Fetch, pull or push, whichever the counter is showing.
	/// The branch the work tree is on, for the repository row.
	var currentBranchName: String? {
		branches.first { $0.isCurrent && $0.kind == .local }?.name
	}

	/// `↓` off the pinned row and into the tree, so the two read as one list.
	func moveKeyboardIntoTree() {
		window?.makeFirstResponder(tableView)
		if tableView.selectedRow < 0, tableView.numberOfRows > 0 {
			tableView.selectRowIndexes([0], byExtendingSelection: false)
		}
	}

	/// `↑` off the top of the tree and onto the pinned row, which is what a
	/// list with a row above it does everywhere else.
	func moveKeyboardToRepositoryRow() {
		window?.makeFirstResponder(repositoryRow)
	}

	/// Scrolls the tree, so a driven run can ask whether the pinned row moved.
	func scrollTreeForTesting(toBottom: Bool) {
		let rows = tableView.numberOfRows
		guard rows > 0 else { return }
		tableView.scrollRowToVisible(toBottom ? rows - 1 : 0)
		layoutSubtreeIfNeeded()
	}

	/// What the pinned row says, and where it and the tree are.
	///
	/// The geometry is here because *pinned* and *the tree starts at the top*
	/// are claims about position, and a screenshot is somebody's eye rather
	/// than a measurement.
	func repositoryRowForTesting() -> String {
		layoutSubtreeIfNeeded()
		let row = repositoryRow.frame
		let scroll = tableView.enclosingScrollView
		let tree = scroll?.frame ?? .zero
		return repositoryRow.reportForTesting
			+ " · row at \(Int(row.minY))–\(Int(row.maxY)) of \(Int(bounds.height))"
			+ " · tree from \(Int(tree.minY))"
			+ " · scrolled \(Int(scroll?.contentView.bounds.minY ?? 0))"
			+ " · fired \(repositoryRow.firesForTesting)"
	}

	@objc func trafficPressed() {
		guard let state = trafficState, state.hasRemote else { return }

		// An upstream that is gone is answered by fetching — a prune clears the
		// tracking — and it lands here anyway, being neither behind nor
		// pushable. Said out loud so this and the row's `Fetch` cannot drift.
		if state.upstreamIsGone {
			run { await GitPull.fetch(in: self.root) }
			return
		}
		if state.behind > 0 {
			pullWithDialog()
			return
		}
		if state.canPush {
			// **HEAD, not whatever is selected in the tree.** This row's every
			// word is about the branch the work tree is on — `GitPush.state`
			// reads HEAD — so its verb has to act on that one. It used to call
			// `pushBranch`, which acts on the *selection*, so pressing a row
			// that said "not published" about the checked-out branch pushed
			// whichever branch happened to be highlighted below it. Reported
			// after it published `main` from a pane whose row was about
			// something else entirely.
			pushCurrentBranch()
			return
		}
		run { await GitPull.fetch(in: self.root) }
	}

	/// Puts the pull dialog up and does what it says.
	@objc func pullWithDialog() {
		let root = self.root
		Task { @MainActor [weak self] in
			guard let situation = await PullSheet.situation(in: root) else {
				Toast.post("There is no remote to pull from")
				return
			}
			PullSheet.ask(situation, over: self?.window) { answer in
				Task { @MainActor in
					// **A rebase rewrites your commits, so the branch is kept
					// first.** The one place a pull becomes destructive, and the
					// safety net is the same one everything else here uses.
					if answer.rebasing, situation.going > 0 {
						_ = await GitBackup.keep(
							ref: "HEAD", subject: situation.into, at: Date(), in: root
						)
					}

					let result = await GitPull.pull(
						in: root,
						remote: answer.remote,
						branch: answer.branch,
						rebasing: answer.rebasing,
						stashing: answer.stashing
					)

					if let refusal = GitPull.refusal(from: result) {
						Self.say(refusal, result: result)
					} else {
						Toast.post(
							"Pulled from \(answer.remote)/\(answer.branch)", kind: .information
						)
					}
					self?.refresh()
					self?.onRepositoryChanged?()
				}
			}
		}
	}

	/// Says why a pull did not work, in words somebody can act on.
	private static func say(_ refusal: GitPull.Refusal, result: GitRepository.ProcessResult) {
		switch refusal {
		case .needsCredential:
			// **Otherwise this is silence.** `GIT_TERMINAL_PROMPT=0` and an
			// askpass of `/usr/bin/false` are right — nothing should hang on a
			// prompt nobody can see — and they turn "this needs a password"
			// into an exit code with very little beside it.
			Toast.post(
				"git wanted a credential",
				detail: "It cannot ask for one from here. Set up a credential helper or an "
					+ "SSH key, or pull from a terminal once to store it."
			)
		case .noRemote:
			Toast.post("There is no remote to pull from")
		case .workingCopyInTheWay:
			Toast.post(
				"Your working copy is in the way",
				detail: "Tick “Stash and reapply local changes” and try again."
			)
		case let .conflicted(paths):
			Toast.post(
				"The pull stopped in \(paths.count) file\(paths.count == 1 ? "" : "s")",
				detail: paths.joined(separator: "\n"),
				kind: .warning
			)
		case let .other(said):
			Toast.post("The pull did not work", detail: said)
		}
	}
}

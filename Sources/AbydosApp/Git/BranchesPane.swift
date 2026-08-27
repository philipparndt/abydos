import AppKit
import AbydosKit

/// Local branches, remotes and tags, with checkout and the operations that go
/// with it.
///
/// A filter field at the top, because the useful case is a repository with more
/// branches than fit on screen — a list you have to scroll is one you would
/// rather have typed into.
final class BranchesPane: NSView {
	/// Something changed the repository: refresh the rest of the window.
	var onRepositoryChanged: (() -> Void)?
	/// Open a worktree as a project, which is the point of having one.
	var onOpenWorktree: ((URL) -> Void)?
	/// Somebody wants the commit page.
	var onOpenCommitPage: (() -> Void)?
	/// Open these paths in the editor.
	var onOpenFiles: (([String]) -> Void)?
	/// Somebody wants the log, for a ref or for the repository.
	var onShowLog: ((String?) -> Void)?
	/// A change was selected, to show its diff.
	var onSelectChange: ((GitChange) -> Void)?

	private let root: URL

	/// The work tree this pane is showing, so the window can tell whether the
	/// one it has is the one it wants rather than building another.
	var repositoryRoot: URL { root }

	private var branches: [GitBranch] = []
	/// Where this repository lives on the web, when it lives anywhere: read
	/// from the remote, so GitHub and an Enterprise install are the same case.
	private var forge: GitForge.Repository?
	/// The branch everything merges into, read alongside the rest.
	///
	/// It pins `main` to the top of `LOCAL`, which is what the branch pill in
	/// the titlebar already does — `BranchGrouping.arrange` pins the current
	/// branch and then the default. Two lists of the same branches in one
	/// window disagreeing about their order is the fault this avoids.
	private var defaultBranch: String?
	/// Local branches whose work is already in the default branch.
	///
	/// Drawn dimmed rather than moved or hidden: where a branch sits in this
	/// list is how it is found, so a branch that moves when it merges is one
	/// somebody hunts for, and one that disappears vanishes at the moment it
	/// becomes safe to delete. Dimming says *nothing here* without saying
	/// *gone*.
	private var mergedBranches: Set<String> = []
	/// What origin points at, or nil when there is no origin at all.
	private var remoteURL: String?
	/// The branch currently being pushed, if one is.
	///
	/// A push talks to another machine and can take a while over a slow link,
	/// and a list that looks exactly as it did is indistinguishable from a
	/// click that never landed.
	private var pushingBranch: String?
	/// Kept alive while the recreate sheet is up: it is the combo's delegate,
	/// and a delegate nobody holds is one nobody hears from.
	private var tagSourceWatcher: TagSourceWatcher?
	private var worktrees: [GitWorktree] = []
	private var stashes: [GitStash.Entry] = []
	/// The tree as it stands, and what somebody has folded shut.
	private var roots: [GitNode] = []
	/// **The working copy arrives shut.** Every change unrolled under the first
	/// row pushes the branches off the bottom of a column, and the question the
	/// tree is usually asked is "where am I" rather than "what have I changed"
	/// — which is what the commit page is for. The count on the row answers the
	/// other one without spending forty rows on it.
	private var collapsedKeys: Set<String> = ["working"]
	/// Set while expansion is being put back after a rebuild, so the pane's own
	/// work is not mistaken for somebody's — the rule `ChangesPane` keeps.
	private var isRestoring = false
	private var filterText = ""

	/// What has changed in the working copy, and the trees drawn from it.
	///
	/// **The first row of the tree, and a thing of the same kind as the rest.**
	/// The working copy is the commit that has not happened yet, which is why
	/// it sits above the stashes and the branches rather than in a pane of its
	/// own with a button of its own.
	private var working = GitWorkingCopyStatus()
	private var unstagedRoots: [GitChangeNode] = []
	private var stagedRoots: [GitChangeNode] = []
	/// What a wholly untracked directory turned out to hold, by path.
	///
	/// The rows are rebuilt from scratch on every filesystem event, so an open
	/// folder's insides are new objects each time and have to be put back before
	/// the tree is built — otherwise a folder somebody is reading closes under
	/// them. Asked for again afterwards, because the directory may have gained a
	/// file since.
	private var untrackedContents: [String: [GitChangeNode]] = [:]
	/// **Shut to begin with.** Every change in the repository unrolled under
	/// the first row pushes the branches off the bottom of a 300 pt column, and
	/// the question the tree is usually asked is not "what have I changed" —
	/// that is what the commit page is for — but "where am I". The count on the
	/// row answers the other question without spending forty rows on it.
	/// Sections somebody has folded away, by title.
	/// Change folders somebody has folded, by side and path.
	/// Which of the two sides is open. Both, until somebody says otherwise.

	/// Stashes somebody has opened, by the commit each one is.
	///
	/// By commit and not by `stash@{n}`, because dropping one renumbers every
	/// entry after it and a set of positions would open the wrong rows.
	/// What each opened stash holds, and whether it would still go back.
	///
	/// Read when a stash is opened rather than on every refresh: `wouldApply`
	/// captures the working copy and merges three trees, which is nothing to do
	/// once and too much to do for every entry on every filesystem event.
	private var stashFiles: [String: [GitCommitFile]] = [:]
	private var stashApplies: [String: GitStash.Applicability] = [:]

	/// Folders somebody has folded shut, by section and prefix.
	///
	/// Keyed by both because `feature/` exists under Local and under every
	/// remote that has one, and folding the local one should not fold theirs.
	/// Held the positive way round — the negative of `ChangesPane`'s rule, and
	/// for the opposite reason: a refs tree that opened everything would put
	/// forty branches on screen to show you the one you are on, where a changes
	/// tree that folded anything would hide work that has just appeared.

	/// Said when a merge has stopped, and nothing else on screen says it.
	private var conflictBanner: OperationBanner!
	private var conflictHeight: NSLayoutConstraint!
	private var conflictPaths: [String] = []
	/// What git is in the middle of, as of the last refresh. The banner's
	/// verbs are its verbs, so they are only offered while this is set.
	private var currentOperation: GitConflicts.Operation?
	/// The filter, when it is open. Nil is the ordinary state.
	private var filterStrip: PaneFilterStrip?
	/// The repository, drawn as the first row and pinned above the scrolling
	/// ones — see `RepositoryRowView` for why it does not scroll.
	private var repositoryRow: RepositoryRowView!
	private var tableView: BranchesOutlineView!
	/// Where this branch stands against its remote, for what the counter says.
	private var trafficState: GitPush.State?
	/// The delete whose sheet is up, held so its callbacks outlive the press.
	private var openDeletion: BranchDeletion?
	/// Where the head is when it is not on a branch, and what git has stopped
	/// in the middle of — nil when there is nothing unusual to say. Drawn on
	/// the repository row and as a row of its own at the top of Local.
	private var headNotice: String?

	enum Row {
		case header(String)
		/// The working copy, and how much has changed in it.
		case workingCopy(changed: Int)
		/// Staged or unstaged, and how many are on that side.
		case side(String, staged: Bool, count: Int)
		/// One changed file, or a folder of them.
		case change(GitChangeNode, staged: Bool, depth: Int)
		/// A prefix several branches share. `key` is the section and the prefix
		/// together, which is what folding is remembered by; `display` is what
		/// the row says, which for a folded chain is more than one component.
		case folder(key: String, display: String, count: Int, depth: Int)
		/// A branch, how far it is indented, and what it says — which is not
		/// `branch.name`: under `feature/`, the row reads `tags`.
		case branch(GitBranch, depth: Int, display: String)
		case worktree(GitWorktree)
		case stash(GitStash.Entry)
		/// One file inside an opened stash.
		case stashFile(GitStash.Entry, GitCommitFile)
		/// Where the head is when it is on no branch, and what git has stopped
		/// in the middle of. A row rather than a decoration because that is
		/// what the rest of this section is: `for-each-ref` marks nothing
		/// current while the head is detached, so without this the list of
		/// local branches simply has no tick anywhere in it and says nothing
		/// about where you are.
		case detachedHead(String)

	}

	/// One row of the tree, and what hangs off it.
	///
	/// **A real tree, drawn by `NSOutlineView`.** This was a flat table with
	/// indentation, chevrons, arrow keys, page keys and expansion state all
	/// written out by hand — and every one of them was reported broken, because
	/// each was a re-implementation of something AppKit already does correctly
	/// and the project tree and the changes tree both already use. The rows are
	/// the same; what draws them is not.
	final class GitNode {
		/// Stable across a rebuild, which is how expansion survives one: the
		/// tree is thrown away and built again on every filesystem event, and
		/// identity is the only thing that does not survive that.
		let key: String
		fileprivate let row: Row
		fileprivate(set) var children: [GitNode] = []

		fileprivate init(key: String, row: Row) {
			self.key = key
			self.row = row
		}

		fileprivate func add(_ child: GitNode) { children.append(child) }

		fileprivate func insert(_ child: GitNode, at index: Int) {
			children.insert(child, at: min(index, children.count))
		}
	}

	init(root: URL) {
		self.root = root
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		beginFirstRead()
		refresh()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(refresh),
			name: .abydosRepositoryChanged,
			object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Shown until the first read comes back — see `ChangesPane.activity` for
	/// why it is the first only.
	private var activity: PaneActivityView?

	private func beginFirstRead() {
		activity = PaneActivityView.install(over: self, message: "Reading branches…")
	}

	private func finishFirstRead() {
		activity?.finish()
		activity = nil
	}
	deinit { NotificationCenter.default.removeObserver(self) }

	// MARK: - Layout

	private func build() {
		// **The repository, as a control**, which is what the button above this
		// tree used to be: fetch when level, pull when behind, push when ahead.
		// Its own comment gave the reason it was a button — *a verb here hangs
		// off the row that draws its object, and nothing drew the repository*.
		// Something does now, so the verb is on it and the button is gone.
		repositoryRow = RepositoryRowView()
		repositoryRow.translatesAutoresizingMaskIntoConstraints = false
		repositoryRow.onAction = { [weak self] in self?.trafficPressed() }
		// **Re-reading the repository is a verb on the repository**, so it hangs
		// off the row that draws one — this pane has no header to put a button
		// in, and its own comment above says why it does not.
		//
		// It is here as well as on every filesystem event because the two are
		// different questions: the watcher notices what happens *here*, and a
		// fetch, a rebase or a branch deleted in another window happens
		// somewhere else and arrives silently.
		repositoryRow.secondaryAction = RowAction(
			symbol: "arrow.clockwise",
			help: "Read the repository again",
			isAlwaysShown: true
		)
		repositoryRow.onSecondaryAction = { [weak self] in self?.refreshPressed() }
		repositoryRow.onDownArrow = { [weak self] in self?.moveKeyboardIntoTree() }

		tableView = BranchesOutlineView()
		tableView.headerView = nil
		tableView.backgroundColor = Theme.current.sidebarBackground
		tableView.selectionHighlightStyle = .regular
		// So that several stashes can be dropped in one go. Branches ignore it:
		// nothing here acts on more than one of those.
		tableView.allowsMultipleSelection = true
		tableView.rowSizeStyle = .custom
		tableView.intercellSpacing = .zero
		tableView.gridStyleMask = []
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branch"))
		tableView.addTableColumn(column)
		// The column the disclosure triangles sit in, which an outline view
		// will not draw one without.
		tableView.outlineTableColumn = column
		tableView.indentationPerLevel = Theme.current.scaled(14)
		tableView.autoresizesOutlineColumn = false
		tableView.delegate = self
		tableView.dataSource = self
		tableView.menu = makeMenu()
		tableView.onActivate = { [weak self] in self?.checkoutSelected() }
		tableView.onRowAction = { [weak self] in self?.fireSelectedRowAction() }
		tableView.onLeaveTop = { [weak self] in self?.moveKeyboardToRepositoryRow() }

		conflictBanner = OperationBanner()
		conflictBanner.onOpenFiles = { [weak self] in
			guard let self else { return }
			self.onOpenFiles?(self.conflictPaths)
		}
		conflictBanner.onOpenInFork = { [weak self] in
			guard let self, let fork = ForkIntegration.applicationURL() else { return }
			NSWorkspace.shared.open(
				[self.root], withApplicationAt: fork,
				configuration: NSWorkspace.OpenConfiguration()
			)
		}
		conflictBanner.onCopyPrompt = { [weak self] in
			guard let self else { return }
			let root = self.root
			Task { @MainActor in
				guard let prompt = await GitConflicts.prompt(in: root) else { return }
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(prompt, forType: .string)
				Toast.post(
					"The conflict is on the clipboard",
					detail: "Paste it into a session in the terminal below.",
					kind: .information
				)
			}
		}

		conflictBanner.onCarryOn = { [weak self] in self?.step(.carryOn) }
		conflictBanner.onSkip = { [weak self] in self?.step(.skip) }
		conflictBanner.onAbort = { [weak self] in self?.askAboutAborting() }

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.sidebarBackground
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle

		for view in [conflictBanner, repositoryRow, scrollView] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		// Shut to nothing unless there is a conflict, so a clean repository
		// pays nothing for it.
		conflictHeight = conflictBanner.heightAnchor.constraint(equalToConstant: 0)
		conflictHeight.isActive = true

		NSLayoutConstraint.activate([
			conflictBanner.topAnchor.constraint(equalTo: topAnchor),
			conflictBanner.leadingAnchor.constraint(equalTo: leadingAnchor),
			conflictBanner.trailingAnchor.constraint(equalTo: trailingAnchor),

			// **Nothing between the conflict banner and the repository row.**
			// The filter field and the New Branch button were 58 points of
			// chrome above a list; the filter is on ⌘F and the new branch is a
			// verb on the LOCAL row it belongs to.
			repositoryRow.topAnchor.constraint(equalTo: conflictBanner.bottomAnchor),
			repositoryRow.leadingAnchor.constraint(equalTo: leadingAnchor),
			repositoryRow.trailingAnchor.constraint(equalTo: trailingAnchor),
			repositoryRow.heightAnchor.constraint(equalToConstant: Theme.current.scaled(24)),

			scrollView.topAnchor.constraint(equalTo: repositoryRow.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	// MARK: - Data

	/// The refresh verb: re-read everything this pane shows, and say that it is
	/// happening.
	///
	/// The spinner is the point. `refresh` is several git calls and on a large
	/// repository it takes long enough that a button with no feedback reads as a
	/// button that did nothing — so somebody presses it again.
	private func refreshPressed() {
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
			self.working = await GitWorkingCopy.status(in: root)
			// Before the trees are built, so `add(changes:)` fills from a cache
			// that holds only directories git still reports.
			let directories = Set(
				(self.working.unstaged + self.working.staged).filter(\.isDirectory).map(\.path)
			)
			self.untrackedContents = self.untrackedContents.filter { directories.contains($0.key) }
			self.unstagedRoots = GitChangeTree.build(self.working.unstaged, against: self.working.staged)
			self.stagedRoots = GitChangeTree.build(self.working.staged, against: self.working.unstaged)
			// Only the repository's own checkouts, and only when there is more
			// than one: a repository nobody has added a worktree to should not
			// carry a section explaining that it has one.
			let trees = await GitWorktrees.list(in: root)
			let put = await GitStash.list(in: root)
			remoteURL = await GitForge.remoteURL(in: root)
			if let main = self.defaultBranch {
				self.mergedBranches = await GitBranches.merged(into: main, in: root)
			} else {
				self.mergedBranches = []
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
				self.conflictHeight.constant = 0
				self.conflictBanner.isHidden = true
				return
			}
			self.conflictPaths = paths
			self.currentOperation = operation

			let what = await GitConflicts.describe(in: root)
			let staged = await GitWorkingCopy.status(in: root).staged.isEmpty == false
			let progress = await GitConflicts.progress(in: root)
			self.conflictBanner.isHidden = false
			self.conflictBanner.show(
				operation: operation, conflicted: paths.count, staged: staged,
				what: what, progress: progress
			)
			// The strip asks for its own height: what it shows decides how
			// much it needs, and a constant here was a second opinion about
			// the same thing.
			self.conflictHeight.constant = self.conflictBanner.wantedHeight
		}
	}

	/// `--continue` or `--skip`, and what to do when git will not.
	///
	/// The whole flow this pane was missing. Resolving the files was as far as
	/// it went; carrying the rebase on meant leaving for a terminal, and the
	/// commit page — which is where somebody naturally goes next — makes an
	/// ordinary commit, which is the wrong move in the middle of a rebase.
	private func step(_ step: GitConflicts.Step) {
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
	private func askAboutAborting() {
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
			self.repositoryRow.show(
				branch: self.currentBranchName,
				state: state,
				notice: operation == nil ? self.headNotice : nil
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
	private var currentBranchName: String? {
		branches.first { $0.isCurrent && $0.kind == .local }?.name
	}

	/// `↓` off the pinned row and into the tree, so the two read as one list.
	private func moveKeyboardIntoTree() {
		window?.makeFirstResponder(tableView)
		if tableView.selectedRow < 0, tableView.numberOfRows > 0 {
			tableView.selectRowIndexes([0], byExtendingSelection: false)
		}
	}

	/// `↑` off the top of the tree and onto the pinned row, which is what a
	/// list with a row above it does everywhere else.
	fileprivate func moveKeyboardToRepositoryRow() {
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

	@objc private func trafficPressed() {
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
			pushBranch()
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

	private func rebuildRows() {
		let needle = filterText.lowercased()
		let matching = needle.isEmpty
			? branches
			: branches.filter { $0.name.lowercased().contains(needle) }

		roots = []

		// The working copy first: it is what you are doing, and everything
		// below it is where that work might go or has been.
		let changed = working.staged.count + working.unstaged.count
		let copy = GitNode(key: "working", row: .workingCopy(changed: changed))
		roots.append(copy)
		if changed > 0 {
			add(side: "Staged", stagedRoots, staged: true, to: copy)
			add(side: "Unstaged", unstagedRoots, staged: false, to: copy)
		}

		// Local first: it is what you switch between. Remotes and tags are
		// there to branch from, not to live on.
		appendSection("Local", matching.filter { $0.kind == .local })

		// At the top of Local, and only when there is something to say. Inside
		// the section rather than above it because it is standing in for the
		// row that would have had the tick.
		if let headNotice,
			let local = roots.first(where: { $0.key == "section:Local" }) {
			local.insert(GitNode(key: "head:detached", row: .detachedHead(headNotice)), at: 0)
		}

		let remotes = matching.filter { if case .remote = $0.kind { return true } else { return false } }
		let byRemote = Dictionary(grouping: remotes) { branch -> String in
			if case .remote(let name) = branch.kind { return name }
			return ""
		}
		for remote in byRemote.keys.sorted() {
			appendSection(remote, byRemote[remote] ?? [])
		}

		appendSection("Tags", matching.filter { $0.kind == .tag })

		// Worktrees last: they are places, not refs, and the list is short.
		let matchingTrees = needle.isEmpty
			? worktrees
			: worktrees.filter {
				$0.name.lowercased().contains(needle) || ($0.branch ?? "").lowercased().contains(needle)
			}
		if matchingTrees.count > 1 || (matchingTrees.count == 1 && !matchingTrees[0].isPrimary) {
			let section = GitNode(key: "section:Worktrees", row: .header("Worktrees"))
			roots.append(section)
			for tree in matchingTrees {
				section.add(GitNode(key: "worktree:\(tree.path.path)", row: .worktree(tree)))
			}
		}

		// Stashes last, and only when there are any: work put aside belongs
		// with the branches it was put aside from, which is what saves this
		// from being another view of its own.
		let matchingStashes = needle.isEmpty
			? stashes
			: stashes.filter {
				$0.message.lowercased().contains(needle) || $0.branch.lowercased().contains(needle)
			}
		if !matchingStashes.isEmpty {
			let section = GitNode(key: "section:Stashes", row: .header("Stashes"))
			roots.append(section)
			for entry in matchingStashes {
				let node = GitNode(key: "stash:\(entry.commit)", row: .stash(entry))
				section.add(node)
				for file in stashFiles[entry.commit] ?? [] {
					node.add(GitNode(
						key: "stashfile:\(entry.commit):\(file.path)",
						row: .stashFile(entry, file)
					))
				}
			}
		}

		// **A rebuild must not take the keyboard away.** `reloadData` drops the
		// selection, and a list with nothing selected gives up first responder,
		// so folding a row left the tree unfocused and the next keypress went
		// to the window. Remembered by key rather than by row, because a
		// rebuild moves every row.
		let hadFocus = window?.firstResponder === tableView
		// **Every selected row, not the first.** This kept one key, so a rebuild
		// — which happens on every filesystem event — quietly cut a selection of
		// five branches down to one. Nobody notices until a menu that said
		// "Delete 5 Branches…" says "Delete…" a moment later, which is the
		// shrinking-selection fault `TreeSelection` exists for elsewhere in this
		// app.
		let selectedKeys = tableView.selectedRowIndexes.compactMap {
			(tableView.item(atRow: $0) as? GitNode)?.key
		}

		// **The flag covers the selection too, and that is the whole of it.**
		// Putting the selection back is a selection change as far as AppKit is
		// concerned, and this pane answers one by opening the diff of what was
		// picked. Cleared a line too early, every refresh — and a refresh is
		// every filesystem event — opened an editor tab, which changed the
		// window, which refreshed the pane.
		isRestoring = true
		tableView.reloadData()
		restoreExpansion(roots)

		let rows = selectedKeys.compactMap { key -> Int? in
			guard let again = node(forKey: key) else { return nil }
			let row = tableView.row(forItem: again)
			return row >= 0 ? row : nil
		}
		if !rows.isEmpty {
			tableView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		}
		isRestoring = false

		if hadFocus { window?.makeFirstResponder(tableView) }
	}

	/// Opens everything nobody has shut.
	///
	/// The positive way round, so a tree arrives open — with one exception the
	/// working copy makes for itself: forty changed files unrolled under the
	/// first row pushes the branches off the bottom of a column, and the count
	/// on the row answers the usual question without spending forty rows on it.
	private func restoreExpansion(_ nodes: [GitNode]) {
		for node in nodes where !node.children.isEmpty {
			if collapsedKeys.contains(node.key) {
				tableView.collapseItem(node)
			} else {
				tableView.expandItem(node)
				restoreExpansion(node.children)
			}
		}
	}

	/// Finds a node again after a rebuild has replaced every object.
	private func node(forKey key: String) -> GitNode? {
		var stack = roots
		while let node = stack.popLast() {
			if node.key == key { return node }
			stack.append(contentsOf: node.children)
		}
		return nil
	}

	/// The node under the pointer, or the selected one.
	private var selectedNode: GitNode? {
		let clicked = tableView.clickedRow
		let row = clicked >= 0 ? clicked : tableView.selectedRow
		return tableView.item(atRow: row) as? GitNode
	}

	/// One side of the index, and the folders it changed.
	private func add(
		side title: String, _ trees: [GitChangeNode], staged: Bool, to parent: GitNode
	) {
		guard !trees.isEmpty else { return }
		let count = staged ? working.staged.count : working.unstaged.count
		let side = GitNode(key: "side:\(title)", row: .side(title, staged: staged, count: count))
		parent.add(side)
		add(changes: trees, staged: staged, to: side)
	}

	private func add(changes: [GitChangeNode], staged: Bool, to parent: GitNode) {
		for change in changes {
			// An open untracked directory gets what it held put back, so the row
			// the outline is about to be handed has its children already.
			if change.change?.isDirectory == true, !change.isFilled,
			   let known = untrackedContents[change.path] {
				change.fill(with: known)
			}
			let node = GitNode(
				key: "change:\(staged):\(change.path)",
				row: .change(change, staged: staged, depth: 0)
			)
			parent.add(node)
			// `holdsFiles`, not `isFolder`: an untracked directory has children
			// once it has been opened, and they are rows like any others.
			guard change.holdsFiles else { continue }
			add(changes: change.children, staged: staged, to: node)
		}
	}

	private func appendSection(_ title: String, _ entries: [GitBranch]) {
		guard !entries.isEmpty else { return }
		let section = GitNode(key: "section:\(title)", row: .header(title))
		roots.append(section)

		// **Filtering flattens.** A tree you have to expand to reach a name you
		// have just typed is worse than no tree, so a filtered list is whole
		// names and no folders at all.
		guard filterText.isEmpty else {
			for branch in entries.sorted(by: {
				$0.isCurrent != $1.isCurrent ? $0.isCurrent : $0.name < $1.name
			}) {
				section.add(GitNode(
					key: "\(title):\(branch.id)",
					row: .branch(branch, depth: 0, display: branch.name)
				))
			}
			return
		}

		// **Current first, then the default**, which is the order the branch
		// pill pins them in — the branch you are on and the branch everything
		// merges into are the two anybody looks for and the two worst to hunt
		// for, the default especially: it is almost never the most recently
		// touched and so sinks in any list ordered by anything else.
		//
		// `backup` keeps its row however few refs are under it. It is a folder
		// this program makes and one the refs tree gives a verb of its own —
		// sweeping the entries older than a given age — and folding it away
		// takes the verb with it.
		let main = defaultBranch
		let tree = PathTree.build(
			entries.map { (path: $0.name, payload: $0) },
			folding: true,
			keeping: ["backup"],
			promoting: { branch in
				if branch.isCurrent { return 0 }
				if let main, branch.name == main { return 1 }
				return nil
			}
		)
		add(refs: tree, under: title, to: section)
	}

	private func add(refs: [PathNode<GitBranch>], under section: String, to parent: GitNode) {
		for ref in refs {
			if let branch = ref.payload {
				parent.add(GitNode(
					key: "\(section):\(branch.id)",
					row: .branch(branch, depth: 0, display: ref.name)
				))
				continue
			}
			let key = "\(section):\(ref.path)"
			let folder = GitNode(
				key: key,
				row: .folder(key: key, display: ref.name, count: ref.count, depth: 0)
			)
			parent.add(folder)
			add(refs: ref.children, under: section, to: folder)
		}
	}

	/// The row under the pointer, or the selected one.
	private var clickedRow: Row? { selectedNode?.row }

	/// The change under the pointer, for staging and for showing its diff.
	private var clickedChange: (node: GitChangeNode, staged: Bool)? {
		guard case let .change(node, staged, _) = clickedRow else { return nil }
		return (node, staged)
	}

	@objc private func stageClicked() {
		guard let picked = clickedChange else { return }
		run {
			picked.staged
				? await GitWorkingCopy.unstage(paths: [picked.node.path], in: self.root)
				: await GitWorkingCopy.stage(paths: [picked.node.path], in: self.root)
		}
	}

	/// The folder the pointer is on, or the selection when it is not on one.
	private var selectedFolder: (key: String, display: String)? {
		guard case let .folder(key, display, _, _) = selectedNode?.row else { return nil }
		return (key, display)
	}

	/// Opens a stash to what is in it, or shuts it again.
	///
	/// **Reading it is the point.** Three entries called "wip" are a guessing
	/// game, and `applyStash` restored blind — so what it holds and whether it
	/// would still go back are read here, once, and kept until the repository
	/// moves under them.
	private func readInside(_ entry: GitStash.Entry) {
		Task { @MainActor [weak self] in
			guard let self else { return }
			let held = await GitStash.files(entry, in: self.root)
			let applies = await GitStash.wouldApply(entry, in: self.root)
			self.stashFiles[entry.commit] = held
			self.stashApplies[entry.commit] = applies
			self.rebuildRows()
		}
	}

	/// The stash under the pointer, whether its own row or one of its files.
	private var clickedStash: GitStash.Entry? {
		switch selectedNode?.row {
		case let .stash(entry):        return entry
		case let .stashFile(entry, _): return entry
		default:                       return nil
		}
	}

	/// Makes a branch where the stash was made and puts the work there.
	///
	/// What to offer when the check says the apply would conflict: applied on
	/// the commit it came from, it cannot.
	@objc private func branchFromStash() {
		guard let entry = selectedStashes.first ?? clickedStash else { return }
		promptForName(
			title: "Branch from “\(entry.message)”",
			message: "A branch at the commit the stash was made on, with the work put back on it. "
				+ "It cannot conflict, which is why it is the answer when applying would.",
			defaultValue: ""
		) { [weak self] name in
			guard let self, !name.isEmpty else { return }
			self.run { await GitStash.branch(entry, named: name, in: self.root) }
		}
	}

	@objc private func expandFolder() {
		guard let node = selectedNode else { return }
		// Everything beneath it too, which is what "all" has to mean or the
		// item is the disclosure triangle with extra steps.
		tableView.expandItem(node, expandChildren: true)
	}

	@objc private func collapseFolder() {
		guard let node = selectedNode else { return }
		tableView.collapseItem(node, collapseChildren: true)
	}

	/// Deletes the backup refs past a chosen age. See `BackupSweep`.
	@objc private func sweepBackups() {
		BackupSweep.run(in: root, over: window) { [weak self] in self?.refresh() }
	}

	@objc private func copyFolderPrefix() {
		guard let folder = selectedFolder else { return }
		// The prefix as git knows it, without the section name in front of it.
		let prefix = folder.key.split(separator: ":", maxSplits: 1).last.map(String.init) ?? folder.key
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(prefix + "/", forType: .string)
	}

	private var selectedBranch: GitBranch? {
		guard case let .branch(branch, _, _) = selectedNode?.row else { return nil }
		return branch
	}

	/// What the push item should say, or nil when there is nothing to send.
	///
	/// A branch nobody has pushed has no upstream and counts nothing, which is
	/// not the same as being level with one — and it is the case where the
	/// menu is most useful, since publishing is otherwise a trip to a terminal.
	private func pushTitle(for branch: GitBranch) -> String? {
		guard branch.upstream != nil else { return "Publish Branch" }
		guard branch.ahead > 0 else { return nil }
		return "Push \(branch.ahead) Commit\(branch.ahead == 1 ? "" : "s")"
	}

	/// The stashes the menu applies to.
	///
	/// A right-click inside the selection means all of it — that is what makes
	/// dropping several at once possible — and a right-click anywhere else
	/// means the row under the pointer, as every list does.
	private var selectedStashes: [GitStash.Entry] {
		let clicked = tableView.clickedRow
		let selected = tableView.selectedRowIndexes

		let indexes = clicked >= 0 && !selected.contains(clicked)
			? IndexSet(integer: clicked)
			: (clicked >= 0 ? selected : selected)
		return indexes.compactMap {
			guard case let .stash(entry) = (tableView.item(atRow: $0) as? GitNode)?.row else {
				return nil
			}
			return entry
		}
	}

	/// The branches the menu applies to.
	///
	/// The same rule the stashes above follow, and for the same reason: a
	/// right-click inside the selection means all of it, and a right-click
	/// anywhere else means the row under the pointer, as every list does.
	///
	/// Only *Copy Name* reads this. Checkout, merge and delete are each about
	/// one branch and say so — a menu that quietly deleted three refs because
	/// the pointer happened to be inside a selection would be a different kind
	/// of thing entirely.
	private var selectedBranches: [GitBranch] {
		let clicked = tableView.clickedRow
		let selected = tableView.selectedRowIndexes
		let indexes = clicked >= 0 && !selected.contains(clicked)
			? IndexSet(integer: clicked)
			: selected
		return indexes.compactMap {
			guard case let .branch(branch, _, _) = (tableView.item(atRow: $0) as? GitNode)?.row else {
				return nil
			}
			return branch
		}
	}

	private var selectedWorktree: GitWorktree? {
		guard case let .worktree(worktree) = selectedNode?.row else { return nil }
		return worktree
	}

	// MARK: - Actions

	/// Sends a branch to its remote, publishing it if it has never been there.
	///
	/// Any branch, not only the one checked out: having to check a branch out
	/// to push it is a detour through the working copy for something that does
	/// not touch it.
	@objc private func pushBranch() {
		guard let branch = selectedBranch, case .local = branch.kind else { return }
		let publishing = branch.upstream == nil

		pushingBranch = branch.name
		tableView.reloadData()

		Task { @MainActor in
			defer {
				pushingBranch = nil
				tableView.reloadData()
			}
			let result = await GitPush.push(
				in: root,
				setUpstream: publishing,
				// HEAD for the current branch: pushing it by name would work
				// too, but naming HEAD is what git does and what the log says.
				branch: branch.isCurrent ? nil : branch.name
			)
			// git reports a push on stderr, which is where the branch and the
			// range it sent are named.
			let output = (result.stderr.isEmpty ? result.stdout : result.stderr)
				.trimmingCharacters(in: .whitespacesAndNewlines)

			if result.exitCode == 0 {
				Toast.post("Pushed \(branch.name)", detail: output, kind: .information)
			} else {
				Toast.post("Could not push \(branch.name)", detail: output, kind: .error)
			}
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			refresh()
		}
	}

	/// Opens the branch's page in a browser.
	/// Writes over what is on the remote, having said how much that is.
	///
	/// **The one destructive thing here that is not insured, and must not
	/// pretend to be.** No ref on this machine can bring back somebody else's
	/// commits from a remote — `GitDestructive` answers `nil` for the backup on
	/// this one alone — so what is offered instead is the count, before the
	/// fact, in a sentence somebody can act on.
	@objc private func forcePushBranch() {
		guard let branch = selectedBranch, case .local = branch.kind else { return }
		let root = self.root
		DestructiveAsk.run(
			.forcePush(branch: branch.name, overwriting: branch.behind),
			in: root,
			over: window
		) { [weak self] _, _ in
			let result = await GitRepository.run(
				["push", "--force-with-lease", "origin", branch.name],
				in: root,
				environment: [
					"GIT_TERMINAL_PROMPT": "0",
					"GIT_ASKPASS": "/usr/bin/false",
					"SSH_ASKPASS": "/usr/bin/false",
				]
			)
			await MainActor.run {
				self?.refresh()
				self?.onRepositoryChanged?()
			}
			// `--force-with-lease` rather than `--force`: it refuses if the
			// remote has moved since this app last looked, which is exactly the
			// case where the count somebody was shown is already out of date.
			guard result.exitCode != 0 else { return nil }
			return result.stderr.isEmpty ? result.stdout : result.stderr
		}
	}

	/// Opens the commit page, where a message with a body gets written.
	@objc private func openCommitPage() { onOpenCommitPage?() }

	/// The menu's way to the commit view, saying what the row's verb says.
	private var commitEntryTitle: String {
		let changed = working.staged.count + working.unstaged.count
		return "\(Self.reviewChangesTitle(max(1, changed))) ⇧⌘K"
	}

	/// What the three ways to the commit view all say.
	///
	/// One place, because a row, a menu entry and a shortcut that disagree about
	/// what they open are three things somebody has to try.
	static func reviewChangesTitle(_ changed: Int) -> String {
		changed == 1 ? "Review 1 change\u{2026}" : "Review \(changed) changes\u{2026}"
	}

	/// The selected row's own verb, for `⌘⏎`.
	///
	/// Asked of the row's view rather than of a table kept beside the model: the
	/// view is where the action was put, and a second table saying which rows
	/// have one is a second thing to keep in step.
	private func fireSelectedRowAction() {
		let row = tableView.selectedRow
		guard row >= 0,
		      let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
		      	as? ActionableRowView
		else { return }
		view.fireAction()
	}

	/// Selects a row by its position, for a driven run.
	func selectRowForTesting(_ row: Int) {
		guard row >= 0, row < tableView.numberOfRows else { return }
		tableView.selectRowIndexes([row], byExtendingSelection: false)
	}

	/// Fires the selected row's verb, as `⌘⏎` does.
	func fireSelectedRowActionForTesting() { fireSelectedRowAction() }

	/// What each visible row offers, for a driven run.
	func rowActionsForTesting() -> [String] {
		(0..<tableView.numberOfRows).compactMap { row in
			guard let node = tableView.item(atRow: row) as? GitNode else { return nil }
			let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
			let offer = (view as? ActionableRowView)?.actionReportForTesting ?? "-"
			return "\(node.key): \(offer)"
		}
	}

	/// Makes a tag at a branch's tip.
	///
	/// The other half of `create`: a tag is nearly always cut at the tip of the
	/// branch a release is on, and until now the only way to make one was on a
	/// commit in the log.
	@objc private func newTagOnBranch() {
		guard let branch = selectedBranch else { return }
		promptForName(
			title: "New tag on “\(branch.name)”",
			message: branch.subject.isEmpty
				? "At the tip of \(branch.checkoutName)."
				: "At \(branch.checkoutName) — \(branch.subject)",
			defaultValue: ""
		) { [weak self] name in
			guard let self, !name.isEmpty else { return }
			self.run { await GitTags.create(name, at: branch.checkoutName, in: self.root) }
		}
	}

	/// Opens the log scoped to the branch under the pointer.
	@objc private func showLogForBranch() {
		guard let branch = selectedBranch else { return }
		onShowLog?(branch.checkoutName)
	}

	/// What the pull-request entry says, or nothing when there is none to make.
	///
	/// Nothing for a remote-tracking branch or a tag, which are not somewhere
	/// work happens; nothing without a forge to open it on; and nothing for the
	/// default branch, a pull request from `main` into `main` being a page that
	/// tells you there is nothing to compare.
	private func pullRequestTitle(for branch: GitBranch) -> String? {
		guard case .local = branch.kind, forge != nil else { return nil }
		guard branch.name != defaultBranch else { return nil }
		// **Whether the host has it, not whether it has an upstream.** A branch
		// whose remote branch was deleted still names an upstream — `[gone]` —
		// and a compare page for it is the same 404 as one for a branch that
		// was never pushed. Both need publishing first, so both are offered it.
		return isOnForge(branch)
			? "Open Pull Request\u{2026}"
			: "Publish and Open Pull Request\u{2026}"
	}

	/// Opens the compare page, publishing the branch first when it has to.
	/// See `PullRequestFlow`.
	@objc private func openPullRequest() {
		guard let branch = selectedBranch, let forge else { return }
		guard !isOnForge(branch) else {
			PullRequestFlow.open(branch.name, on: forge, into: defaultBranch)
			return
		}
		pushingBranch = branch.name
		tableView.reloadData()
		PullRequestFlow.publishThenOpen(
			branch, on: forge, into: defaultBranch, in: root
		) { [weak self] in
			guard let self else { return }
			self.pushingBranch = nil
			self.tableView.reloadData()
			self.refresh()
		}
	}

	/// Whether the forge has a copy of this ref to open.
	///
	/// **Asked of the listing rather than of the upstream.** A branch is on the
	/// forge when a remote-tracking ref of the same name is, which is a better
	/// question than *does it have an upstream configured*: a branch pushed
	/// without `--set-upstream` is on the host and has no upstream, and one
	/// whose upstream is `[gone]` has an upstream and is not. Both fall out of
	/// the same test, and it costs nothing — the refs were listed already.
	private func isOnForge(_ branch: GitBranch) -> Bool {
		guard case .local = branch.kind else { return true }
		return branches.contains { other in
			guard case .remote = other.kind else { return false }
			return other.name == branch.name
		}
	}

	@objc private func openBranchOnForge() {
		guard let branch = selectedBranch, let forge else { return }
		// **A page for a branch the host has never heard of is a 404**, which
		// is a worse answer than not offering. Said as well as disabled, in
		// case something other than the menu ever calls this.
		guard isOnForge(branch) else {
			Toast.post("\(branch.name) is not on \(forge.displayName) yet")
			return
		}
		guard let url = forge.url(forBranch: branch.name) else { return }
		NSWorkspace.shared.open(url)
	}

	/// Pushes a branch by name, so the spinner can be looked at.
	func pushForTesting(branch name: String) {
		guard let found = firstNode(where: {
			if case let .branch(branch, _, _) = $0.row { return branch.name == name }
			return false
		}) else { return }
		let row = tableView.row(forItem: found)
		guard row >= 0 else { return }
		tableView.selectRowIndexes([row], byExtendingSelection: false)
		pushBranch()
	}

	/// Pops the context menu open on a row, as a right-click would.
	/// The rows as they stand, one per line, indented by depth.
	///
	/// **A line of text rather than a picture.** What this pane turns on now is
	/// whether a prefix folded, whether one branch under a prefix stayed flat,
	/// and whether filtering flattened the lot — none of which a screenshot
	/// settles without somebody counting pixels, and all of which diff.
	/// Selects the rows for these branches, by the name git would take.
	///
	/// The selection is what the menu reads, so this is the half that has to be
	/// driven rather than called.
	func selectBranchesForTesting(_ names: [String]) -> String {
		var rows = IndexSet()
		var missing: [String] = []
		for name in names {
			let found = (0..<tableView.numberOfRows).first { index in
				guard case let .branch(branch, _, _) = (tableView.item(atRow: index) as? GitNode)?.row
				else { return false }
				return branch.checkoutName == name
			}
			if let found { rows.insert(found) } else { missing.append(name) }
		}
		tableView.selectRowIndexes(rows, byExtendingSelection: false)
		return "selected \(rows.count)" + (missing.isEmpty ? "" : ", no row for \(missing.joined(separator: " "))")
	}

	/// What the delete dialog would say about the selection, **without deleting
	/// anything**.
	///
	/// The sentence *is* the feature here: "nothing would be lost" and "these
	/// would lose commits" are the two things somebody is being asked, and a
	/// check that only counted branches could not tell them apart.
	func deleteWordingForTesting() async -> String {
		let branches = deletableBranches
		guard !branches.isEmpty else { return "nothing deletable is selected" }
		return await deletion().wordingForTesting(
			about: branches, target: currentBranchName ?? "HEAD"
		)
	}

	/// Opens the real dialog, for a report of what is on it.
	func askAboutDeletingForTesting() {
		// Held for as long as the sheet is: the object owns the dialog's
		// callbacks, and one let go of while its sheet is up takes them with
		// it.
		let made = deletion()
		openDeletion = made
		made.ask(about: deletableBranches, target: currentBranchName ?? "HEAD")
	}

	/// What is on the sheet that is up, with the frames it was laid out at.
	///
	/// A screenshot cannot see it — `--screenshot` captures the window and a
	/// sheet is a window of its own — and the frame is the thing worth
	/// checking: `NSAlert` lays its accessory out from the frame it is given
	/// rather than the view's intrinsic size, so a checkbox at zero by zero is
	/// a control that is there and cannot be seen.
	func deleteSheetForTesting() -> String {
		guard let sheet = window?.attachedSheet else { return "SHEET none" }
		var lines: [String] = []
		func walk(_ view: NSView) {
			if let button = view as? NSButton, !button.title.isEmpty {
				let kind = button.frame.size == .zero ? "ZERO-SIZED " : ""
				lines.append("  \(kind)\(button.title)"
					+ " [\(button.isEnabled ? "on" : "off")"
					+ "\(button.hasDestructiveAction ? " destructive" : "")"
					+ "\(button.state == .on ? " ticked" : "")"
					+ " \(Int(button.frame.width))×\(Int(button.frame.height))]")
			}
			if let text = view as? NSTextField, !text.stringValue.isEmpty, !(view is NSButton) {
				lines.append("  “\(text.stringValue.replacingOccurrences(of: "\n", with: " / "))”")
			}
			view.subviews.forEach(walk)
		}
		sheet.contentView.map(walk)
		return "SHEET:\n" + lines.joined(separator: "\n")
	}

	/// Does the delete the dialog would do, with the checkbox as given — the
	/// half a driven run cannot reach, because the dialog itself is AppKit's.
	func deleteForTesting(removingWorktrees: Bool) async {
		let branches = deletableBranches
		guard !branches.isEmpty else { return }
		await deletion().deleteForTesting(
			about: branches,
			target: currentBranchName ?? "HEAD",
			removingWorktrees: removingWorktrees
		)
	}

	/// What *Copy Name* would put on the pasteboard — **without putting it
	/// there**.
	///
	/// The pasteboard belongs to whoever is at the keyboard, and a driven run
	/// that clobbered it would be the same trespass as a driven run typing into
	/// somebody's shell. What is worth checking is which names and in what
	/// order; `setString` is the line after this one.
	func copyNameTextForTesting() -> String {
		selectedBranches.map(\.checkoutName).joined(separator: "\n")
	}

	/// What the context menu would offer over the selection.
	func branchMenuTitlesForTesting() -> [String] {
		let menu = NSMenu()
		// Through the delegate the real menu goes through, so what is reported is
		// what would be shown — titles included, which is where the count is.
		menuNeedsUpdate(menu)
		return menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
	}

	/// What the operation banner says and offers.
	func operationBannerForTesting() -> String { conflictBanner.reportForTesting }

	/// Presses one of its buttons — `continue`, `skip`, `abort`. Abort goes
	/// straight to the verb: the alert in front of it is AppKit's and a driven
	/// run cannot answer it.
	func pressBannerForTesting(_ name: String) {
		if name == "abort" { step(.abort) } else { conflictBanner.pressForTesting(name) }
	}

	func rowsForTesting() -> String {
		(0..<tableView.numberOfRows).compactMap { index -> String? in
			guard let node = tableView.item(atRow: index) as? GitNode else { return nil }
			let depth = tableView.level(forRow: index)
			let indent = String(repeating: "  ", count: depth)
			let mark = node.children.isEmpty
				? ""
				: (tableView.isItemExpanded(node) ? "▾ " : "▸ ")

			switch node.row {
			case let .header(title):
				return indent + mark + "# \(title)"
			case let .detachedHead(notice):
				return indent + mark + "! \(notice)"
			case let .folder(_, display, count, _):
				return indent + mark + "\(display)/ (\(count))"
			case let .branch(branch, _, display):
				// What the row says on its right-hand end, which is now
				// sometimes words rather than counts.
				// The symbol by name, not the sentence it replaced: this is a
				// report of what the row draws, and a row that says
				// `not published` in a report and draws a cloud in the pane is
				// a report that cannot catch the cloud being wrong.
				let merged = branch.kind == .local
					&& !branch.isCurrent
					&& mergedBranches.contains(branch.name)
				var marks: [String] = []
				if branch.isUnpublished {
					// Against the default branch, and said so: the same arrow
					// means a different thing on this row.
					let ahead = branch.aheadOfDefault ?? 0
					if ahead > 0 { marks.append("↑\(ahead) of the default") }
				} else if branch.ahead > 0 || branch.behind > 0 {
					marks.append("↑\(branch.ahead) ↓\(branch.behind)")
				}
				if merged { marks.append("checkmark") }
				else if branch.upstreamIsGone { marks.append("xmark.icloud") }
				else if branch.isUnpublished { marks.append("icloud.and.arrow.up") }
				let tracking = marks.isEmpty ? "" : " [" + marks.joined(separator: " ") + "]"
				return indent + display + (branch.isCurrent ? " *" : "") + tracking
			case let .worktree(worktree):
				let review = ReviewCheckouts.shared.number(of: worktree.path)
					.map { " PR #\($0)" } ?? ""
				return indent + "= \(worktree.name)\(review)"
			case let .stash(entry):
				let applies: String
				switch stashApplies[entry.commit] {
				case .clean:                applies = " ✓"
				case let .conflicts(paths): applies = " ⚠\(paths.count)"
				case .unknown, .none:       applies = ""
				}
				return indent + mark + "~ \(entry.message)\(applies)"
			case let .workingCopy(changed):
				return indent + mark + "◆ Working copy · \(changed)"
			case let .side(title, _, count):
				return indent + mark + "\(title) (\(count))"
			case let .change(change, _, _):
				return indent + mark + change.name + (change.isFolder ? "/" : "")
			case let .stashFile(_, file):
				return indent + file.name
			}
		}.joined(separator: "\n")
	}

	/// The first node answering a question, for the driver.
	private func firstNode(where matches: (GitNode) -> Bool) -> GitNode? {
		var stack = roots
		while let node = stack.popLast() {
			if matches(node) { return node }
			stack.append(contentsOf: node.children)
		}
		return nil
	}

	/// Opens the nth stash to what is in it, and waits for the reading.
	func openStashForTesting(_ index: Int) {
		let entries = stashes
		guard entries.indices.contains(index),
		      let node = node(forKey: "stash:\(entries[index].commit)") else { return }
		tableView.expandItem(node)
	}

	/// Folds a node shut or opens it, by the key it was built with.
	func setFolderForTesting(_ key: String, collapsed: Bool) {
		guard let node = node(forKey: key) else { return }
		if collapsed { tableView.collapseItem(node) } else { tableView.expandItem(node) }
	}

	/// Types into the filter, as somebody would — opening it first if it is
	/// shut, because that is now a thing it can be.
	func filterForTesting(_ text: String) {
		if filterStrip == nil { showFilter() }
		filterStrip?.setTextForTesting(text)
	}

	/// Puts the keyboard on the pinned row and presses ⌘⏎ on it, which is the
	/// one action in this pane the tree's own `fire` cannot reach.
	func fireRepositoryRowForTesting() {
		window?.makeFirstResponder(repositoryRow)
		repositoryRow.keyDown(with: SidebarController.commandReturnEvent())
	}

	/// The outline itself, so a driven run can put the keyboard in it.
	var tableViewForTesting: NSView { tableView }

	/// Whether the filter is open, and what is in it.
	func filterStateForTesting() -> String {
		guard let strip = filterStrip else { return "shut · tree \(tableView.numberOfRows) rows" }
		let focused = window?.firstResponder is NSText
			&& (window?.firstResponder as? NSView)?.isDescendant(of: strip) != false
		return "open · “\(strip.text)” · keyboard \(focused ? "in it" : "elsewhere")"
			+ " · tree \(tableView.numberOfRows) rows"
	}

	/// `⌘F`, when this pane holds the keyboard.
	///
	/// **Claimed from the responder chain, not from a second menu item.** The
	/// Find item targets nil, so the chain answers it: the editor's controller
	/// gets it when the editor has the keyboard and this pane gets it when this
	/// pane does, which is the arrangement rather than a fight over a key.
	@objc func findInFile(_ sender: Any?) { showFilter() }

	/// Opens the filter over the list and puts the keyboard in it.
	func showFilter() {
		if let strip = filterStrip {
			strip.takeKeyboard()
			return
		}
		let strip = PaneFilterStrip(placeholder: "Filter branches")
		strip.translatesAutoresizingMaskIntoConstraints = false
		strip.onTextChanged = { [weak self] text in
			guard let self else { return }
			self.filterText = text
			self.rebuildRows()
		}
		strip.onClose = { [weak self] in self?.hideFilter() }
		addSubview(strip)
		guard let scrollView = tableView.enclosingScrollView else { return }
		NSLayoutConstraint.activate([
			strip.topAnchor.constraint(equalTo: scrollView.topAnchor),
			strip.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
			strip.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
			strip.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30)),
		])
		filterStrip = strip
		layoutSubtreeIfNeeded()
		strip.takeKeyboard()
	}

	/// Shuts it, unfilters the tree, and hands the keyboard back to the list.
	func hideFilter() {
		guard let strip = filterStrip else { return }
		strip.removeFromSuperview()
		filterStrip = nil
		guard !filterText.isEmpty else {
			window?.makeFirstResponder(tableView)
			return
		}
		filterText = ""
		rebuildRows()
		window?.makeFirstResponder(tableView)
	}

	/// What a row's context menu offers, without opening it.
	///
	/// **Built, not popped.** `showMenuForTesting` puts a real menu on screen,
	/// and a driven run that opens a menu is a driven run that stops — so the
	/// question *does this folder carry its verb* had no way to be asked.
	func menuTitlesForTesting(row: Int) -> String {
		guard row >= 0, row < tableView.numberOfRows else { return "no such row" }
		tableView.selectRowIndexes([row], byExtendingSelection: false)
		let menu = NSMenu()
		menu.delegate = self
		menuNeedsUpdate(menu)
		return menu.items
			.map { $0.isSeparatorItem ? "—" : $0.title + ($0.isEnabled ? "" : " (off)") }
			.joined(separator: " · ")
	}

	func showMenuForTesting(row: Int) {
		guard row >= 0, row < tableView.numberOfRows else { return }
		tableView.selectRowIndexes([row], byExtendingSelection: false)
		let rect = tableView.rect(ofRow: row)
		tableView.menu?.popUp(
			positioning: nil,
			at: NSPoint(x: rect.midX, y: rect.maxY),
			in: tableView
		)
	}

	/// Moves a tag to another commit, and offers to move it on the remote too.
	///
	/// For the moving tags every GitHub Action expects — `v1` kept at the
	/// newest `v1.x` — which git can do but only as delete-and-write, twice,
	/// with a force push nobody remembers the spelling of.
	@objc private func recreateTag() {
		guard let tag = selectedBranch, case .tag = tag.kind else { return }

		// Weak from the top: the alert is modal and the pane can go while it is
		// up, and a weak capture inside a scope that already holds a strong one
		// reads as care that is not being taken.
		Task { @MainActor [weak self] in
			guard let self else { return }
			let suggestion = await GitTags.likelySource(for: tag.name, in: root)
			let now = await GitTags.describe(tag.name, in: root)

			let alert = NSAlert()
			alert.messageText = "Recreate “\(tag.name)”"
			alert.informativeText = [
				now.map { "It is at \($0)." },
				"Give anything git can resolve: a tag, a branch, or a commit.",
			].compactMap { $0 }.joined(separator: "\n")
			alert.addButton(withTitle: "Recreate")
			alert.addButton(withTitle: "Cancel")

			// **A picker over the refs already loaded, not a bare field.**
			// `recreate` has always taken anything git can resolve — its own
			// parameter says "a commit, a branch, a tag" — so pointing `v1` at
			// `main` worked from the first day and nobody could do it, because
			// the only way in was typing a name into an empty box with no way
			// to see where the tag was about to land.
			//
			// Editable, because sometimes the answer is a hash and no list can
			// hold every one of those.
			let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
			field.addItems(withObjectValues: self.tagSources(excluding: tag.name))
			field.completes = true
			field.numberOfVisibleItems = 12
			field.stringValue = suggestion
			field.placeholderString = "HEAD"

			// What the chosen source resolves to, under the field, before the
			// button is pressed rather than after. `describe` takes any rev,
			// which is why the tag's own reader can answer for a branch.
			let resolved = NSTextField(labelWithString: " ")
			resolved.font = Theme.current.uiFont(11)
			resolved.textColor = Theme.current.gitAdded
			resolved.lineBreakMode = .byTruncatingTail
			resolved.frame = NSRect(x: 0, y: 0, width: 280, height: 16)

			let follow = TagSourceWatcher(field: field, label: resolved, root: root)
			self.tagSourceWatcher = follow
			follow.refresh()

			// The point of moving a tag is that something else reads it, and
			// that something reads it from the remote.
			let push = NSButton(checkboxWithTitle: "Force-push to origin", target: nil, action: nil)
			push.state = .on
			push.frame = NSRect(x: 0, y: 0, width: 280, height: 20)

			let stack = NSStackView(views: [field, resolved, push])
			stack.orientation = .vertical
			stack.alignment = .leading
			stack.spacing = 8
			stack.frame = NSRect(x: 0, y: 0, width: 280, height: 76)
			alert.accessoryView = stack

			let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
				guard response == .alertFirstButtonReturn, let self else { return }
				let source = field.stringValue.trimmingCharacters(in: .whitespaces)
				guard !source.isEmpty else { return }
				let pushes = push.state == .on

				self.run {
					let moved = await GitTags.recreate(tag.name, at: source, in: self.root)
					guard moved.exitCode == 0 else { return moved }
					guard pushes else {
						Toast.post(
							"\(tag.name) now points at \(source)",
							detail: "It has not been pushed.",
							kind: .information
						)
						return moved
					}
					let sent = await GitTags.push(tag.name, in: self.root)
					if sent.exitCode == 0 {
						Toast.post(
							"\(tag.name) now points at \(source)",
							detail: "Pushed to origin.",
							kind: .information
						)
					}
					return sent
				}
			}
			if let window {
				alert.beginSheetModal(for: window, completionHandler: act)
				window.makeFirstResponder(field)
			} else {
				act(alert.runModal())
			}
		}
	}

	/// Everything a tag could be pointed at, in the order somebody would look.
	///
	/// `HEAD` first because it is the other usual answer; then the branches,
	/// which is what this whole control exists for; then the tags newest first,
	/// which is the `v1` → newest `v1.x` case `likelySource` already knows.
	func tagSources(excluding name: String) -> [String] {
		var sources = ["HEAD"]
		sources += branches.filter { $0.kind == .local }.map(\.name)
		sources += branches.filter { $0.kind == .tag }.map(\.name).filter { $0 != name }
		return sources
	}

	/// What the sheet would offer, for a driver to read.
	func tagSourcesForTesting(excluding name: String) -> String {
		tagSources(excluding: name).joined(separator: "\n")
	}

	// MARK: - The remote

	private var remoteMenuTitle: String {
		remoteURL == nil ? "Add a Remote…" : "Change the Remote…"
	}

	/// Points origin somewhere, or gives the repository one.
	///
	/// A clone has one and nobody thinks about it; a repository made with `git
	/// init` has none, and everything that talks to a remote — pushing,
	/// opening it on GitHub — has nothing to say until it does.
	@objc private func setRemote() {
		let alert = NSAlert()
		alert.messageText = remoteURL == nil ? "Add a remote" : "Change the remote"
		alert.informativeText = remoteURL.map { "origin is \($0)." }
			?? "This repository has no remote, so there is nowhere to push."
		alert.addButton(withTitle: remoteURL == nil ? "Add" : "Change")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		field.stringValue = remoteURL ?? ""
		field.placeholderString = "git@github.com:you/thing.git"
		alert.accessoryView = field

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let url = field.stringValue.trimmingCharacters(in: .whitespaces)
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

	// MARK: - Stashes

	/// Puts a stash back into the working copy, having asked what should
	/// become of the entry.
	///
	/// Both answers are ordinary — one is `git stash apply`, the other `git
	/// stash pop` — and which is wanted depends on whether the work is being
	/// resumed or merely borrowed, which nothing here can know.
	@objc private func applyStash() {
		guard let entry = selectedStashes.first else { return }

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

	@objc private func dropStash() {
		let entries = selectedStashes
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

	@objc private func renameStash() {
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

	private func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	private func checkoutSelected() {
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

	@objc private func openWorktree() {
		guard let worktree = selectedWorktree, !worktree.isMissing else { return }
		onOpenWorktree?(worktree.path)
	}

	@objc private func addWorktree() {
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

	@objc private func removeWorktree() {
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

	@objc private func revealWorktree() {
		guard let worktree = selectedWorktree else { return }
		NSWorkspace.shared.activateFileViewerSelecting([worktree.path])
	}

	@objc private func contextCheckout() { checkoutSelected() }

	@objc private func newBranch() {
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

	@objc private func fastForwardBranch() {
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

	@objc private func mergeIntoCurrent() {
		guard let branch = selectedBranch else { return }
		run { await GitBranches.merge(branch.checkoutName, in: self.root) }
	}

	/// The local branches a delete would act on: never the one checked out, and
	/// never a remote branch or a tag.
	///
	/// Deleting a remote branch is a push, which `CLAUDE.md` forbids outright
	/// except when somebody asks for it by name — so it is not something a
	/// multiple selection should be able to do by accident.
	private var deletableBranches: [GitBranch] {
		selectedBranches.filter { $0.kind == .local && !$0.isCurrent }
	}

	@objc private func deleteBranch() {
		deletion().ask(about: deletableBranches, target: currentBranchName ?? "HEAD")
	}

	/// One `BranchDeletion` per press, told what this pane knows: where the
	/// repository is, what checkouts it has, and who to tell afterwards.
	private func deletion() -> BranchDeletion {
		let made = BranchDeletion(root: root, worktrees: worktrees, window: window)
		made.onFinished = { [weak self] in
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
	@objc private func copyBranchName() {
		let names = selectedBranches.map(\.checkoutName)
		guard !names.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
	}

	/// Asks for a branch name, rejecting ones git would refuse.
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

	private func run(_ operation: @escaping () async -> GitRepository.ProcessResult) {
		Task { @MainActor in
			let result = await operation()
			if result.exitCode != 0 {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}
			refresh()
			onRepositoryChanged?()
		}
	}

	private func presentFailure(_ message: String) {
		Toast.post(
			"git reported a problem",
			detail: message.trimmingCharacters(in: .whitespacesAndNewlines)
		)
	}

	func applyThemeChange() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		filterStrip?.applyThemeChange()
		tableView.reloadData()
	}
}

// MARK: - The tree

extension BranchesPane: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		((item as? GitNode)?.children ?? roots).count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		((item as? GitNode)?.children ?? roots)[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let node = item as? GitNode else { return false }
		if !node.children.isEmpty { return true }
		// A wholly untracked directory has nothing under it until somebody asks,
		// and it needs the triangle in order to be asked. Before this it was
		// drawn as a file with no way in.
		if case let .change(change, _, _) = node.row { return change.holdsFiles }
		return false
	}

	/// Fills an untracked directory the first time it is opened.
	func outlineViewItemWillExpand(_ notification: Notification) {
		guard let node = notification.userInfo?["NSObject"] as? GitNode,
		      case let .change(change, staged, _) = node.row,
		      change.change?.isDirectory == true, !change.isFilled
		else { return }

		if let known = untrackedContents[change.path] {
			change.fill(with: known)
			add(changes: change.children, staged: staged, to: node)
			tableView.reloadItem(node, reloadChildren: true)
			return
		}

		let path = change.path
		Task { @MainActor in
			// Scoped to one directory, which is what makes it affordable at all:
			// `GitWorkingCopy.status` refuses `-uall` over the work tree because
			// it measured seven seconds there against 0.11 s.
			let files = await GitWorkingCopy.untrackedFiles(inDirectory: path, in: self.root)
			self.untrackedContents[path] = GitChangeTree.contents(
				ofUntrackedDirectory: path, files: files, staged: staged
			)
			// Rebuilt rather than patched: the rows may have been thrown away
			// and remade while this was out, and `rebuildRows` puts the contents
			// back on the way through.
			self.rebuildRows()
		}
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		guard let node = item as? GitNode else { return Theme.current.scaled(24) }
		if case .header = node.row { return Theme.current.scaled(22) }
		return Theme.current.scaled(24)
	}

	/// The theme's selection colour rather than the system's blue.
	///
	/// `ThemedRowView` exists for exactly this, and was written the last time
	/// two lists in one window disagreed about what "selected" looks like.
	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		ThemedRowView()
	}

	func outlineView(
		_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any
	) -> NSView? {
		guard let node = item as? GitNode else { return nil }
		switch node.row {
		case .header(let title):
			let view = BranchSectionView(title: title)
			// The verb that belongs to a set of local branches is the one that
			// adds to it — which is what the button above the tree was.
			if title == "Local" {
				view.action = RowAction(
					symbol: "plus", help: "New branch from here", isAlwaysShown: false
				)
				view.onAction = { [weak self] in self?.newBranch() }
			}
			return view
		case let .workingCopy(changed):
			let view = WorkingCopyRowView(changed: changed)
			// **Not `Commit…`**, which reads as *commit now, after a
			// confirmation*. Nothing is committed by pressing it: it opens the
			// view where hunks are chosen and a message written, and committing
			// happens there, later, by a different press.
			if changed > 0 {
				view.action = RowAction(
					title: Self.reviewChangesTitle(changed),
					shortTitle: "Review\u{2026}",
					help: "Open the commit view",
					isAlwaysShown: true
				)
				view.onAction = { [weak self] in self?.openCommitPage() }
			}
			return view
		case let .side(title, _, count):
			return BranchFolderRowView(display: title, count: count)
		case let .change(change, staged, _):
			return WorkingCopyChangeRowView(node: change, staged: staged)
		case let .folder(_, display, count, _):
			return BranchFolderRowView(display: display, count: count)
		case let .branch(branch, _, display):
			return BranchRowView(
				branch: branch,
				display: display,
				isPushing: branch.name == pushingBranch,
				isMerged: branch.kind == .local && mergedBranches.contains(branch.name),
				base: defaultBranch
			)
		case .worktree(let worktree):
			return WorktreeRowView(worktree: worktree)
		case .stash(let entry):
			return StashRowView(entry: entry, applies: stashApplies[entry.commit])
		case let .stashFile(_, file):
			return StashFileRowView(file: file)
		case let .detachedHead(notice):
			return DetachedHeadRowView(notice: notice)
		}
	}

	/// What somebody folds stays folded across a rebuild.
	///
	/// Recorded here rather than decided here: the outline is the thing that
	/// knows what is open, and this only remembers what it was told so that a
	/// tree rebuilt on the next filesystem event comes back the same shape.
	func outlineViewItemDidExpand(_ notification: Notification) {
		guard !isRestoring, let node = notification.userInfo?["NSObject"] as? GitNode else { return }
		collapsedKeys.remove(node.key)

		// A stash reads what is in it the first time it is opened: the check
		// costs a three-way merge and the files cost a diff, which is nothing
		// to do once and far too much to do for every entry on every event.
		if case let .stash(entry) = node.row, stashFiles[entry.commit] == nil {
			readInside(entry)
		}
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		guard !isRestoring, let node = notification.userInfo?["NSObject"] as? GitNode else { return }
		collapsedKeys.insert(node.key)
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard !isRestoring, case let .change(change, _, _) = selectedNode?.row,
		      let picked = change.change else { return }
		onSelectChange?(picked)
	}
}

extension BranchesPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		func item(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			item.isEnabled = enabled
			return item
		}

		if let picked = clickedChange {
			let verb = picked.staged ? "Unstage" : "Stage"
			let title = picked.node.isFolder
				? "\(verb) “\(picked.node.name)” (\(picked.node.count) file"
					+ "\(picked.node.count == 1 ? "" : "s"))"
				: verb
			menu.addItem(item(title, #selector(stageClicked)))
			menu.addItem(.separator())
			menu.addItem(item(commitEntryTitle, #selector(openCommitPage)))
			return
		}

		if case .workingCopy = clickedRow {
			menu.addItem(item(commitEntryTitle, #selector(openCommitPage)))
			return
		}

		let stashes = selectedStashes.isEmpty ? [clickedStash].compactMap { $0 } : selectedStashes
		if !stashes.isEmpty {
			menu.addItem(item(
				"Apply…", #selector(applyStash), enabled: stashes.count == 1
			))
			menu.addItem(item(
				"Branch from Stash\u{2026}", #selector(branchFromStash), enabled: stashes.count == 1
			))
			menu.addItem(item(
				"Rename…", #selector(renameStash), enabled: stashes.count == 1
			))
			menu.addItem(.separator())
			menu.addItem(item(
				stashes.count == 1 ? "Drop…" : "Drop \(stashes.count) Stashes…",
				#selector(dropStash)
			))
			return
		}

		if let worktree = selectedWorktree {
			menu.addItem(item("Open", #selector(openWorktree), enabled: !worktree.isMissing))
			menu.addItem(item("Reveal in Finder", #selector(revealWorktree), enabled: !worktree.isMissing))
			menu.addItem(.separator())
			menu.addItem(item("New Worktree…", #selector(addWorktree)))
			menu.addItem(item("Remove…", #selector(removeWorktree), enabled: !worktree.isPrimary))
			return
		}

		if selectedFolder != nil, let node = selectedNode {
			let shut = !tableView.isItemExpanded(node)
			menu.addItem(item(
				shut ? "Expand All" : "Collapse All",
				shut ? #selector(expandFolder) : #selector(collapseFolder)
			))
			menu.addItem(.separator())
			// **The verb that made this folder worth keeping.** `git-refs-tree`
			// has said the backup folder carries deleting the entries older
			// than a given age since it was written, and nothing offered it:
			// the menu had the three verbs every folder has and no more. It is
			// here now, and the folder it hangs off is here however few refs
			// are under it — which is the other half of the same fix.
			if selectedFolder?.display == "backup" {
				menu.addItem(item("Delete Backups Older Than…", #selector(sweepBackups)))
			}
			menu.addItem(item("Copy Prefix", #selector(copyFolderPrefix)))
			return
		}

		guard let branch = selectedBranch else {
			menu.addItem(item("New Worktree…", #selector(addWorktree)))
			menu.addItem(.separator())
			menu.addItem(item(remoteMenuTitle, #selector(setRemote)))
			return
		}

		menu.addItem(item("Checkout", #selector(contextCheckout), enabled: !branch.isCurrent))
		// **Where this branch has been**, which is the question a branch row is
		// asked most often after "take me there". The log is a page now, so
		// there is somewhere to put the answer.
		menu.addItem(item("Show Log ⇧⌘L", #selector(showLogForBranch)))
		menu.addItem(item("New Branch from Here…", #selector(newBranch)))
		menu.addItem(item("New Tag Here\u{2026}", #selector(newTagOnBranch)))

		// Sending a branch somewhere, and looking at it where it went.
		if case .local = branch.kind, let title = pushTitle(for: branch) {
			menu.addItem(.separator())
			menu.addItem(item(title, #selector(pushBranch)))
		}
		// Diverged: an ordinary push will be refused, and the only thing that
		// gets past that writes over commits somebody else may be standing on.
		if case .local = branch.kind, branch.behind > 0, branch.ahead > 0 {
			menu.addItem(item("Force-push\u{2026}", #selector(forcePushBranch)))
		}
		// **The two halves of opening a pull request, as one entry each.**
		// Making one from a branch nobody else can see is two steps, and having
		// to know that — push first, then find the compare page — is what made
		// this the part of the job people leave the app for.
		//
		// Above `Open on …`, and next to `Publish Branch`, because the three
		// read in the order they are done: send it, propose it, go and look.
		if let title = pullRequestTitle(for: branch) {
			menu.addItem(item(title, #selector(openPullRequest)))
		}
		if let forge {
			menu.addItem(item(
				"Open on \(forge.displayName)",
				#selector(openBranchOnForge),
				enabled: isOnForge(branch)
			))
		}

		// **Bringing a branch up to date without standing on it.** `main ↓4`
		// while the work happens on a feature branch was three operations —
		// checkout, pull, checkout back — and a working copy touched twice for a
		// ref that could simply be moved. Offered only where it is a
		// fast-forward: behind its upstream and with nothing of its own on it,
		// which is exactly when moving the ref loses nothing.
		if case .local = branch.kind, !branch.isCurrent,
		   branch.upstream != nil, branch.behind > 0, branch.ahead == 0 {
			menu.addItem(.separator())
			menu.addItem(item(
				"Fast-forward to \(branch.upstream ?? "Upstream")",
				#selector(fastForwardBranch)
			))
		}

		menu.addItem(.separator())
		menu.addItem(item(
			"Merge into Current",
			#selector(mergeIntoCurrent),
			enabled: !branch.isCurrent
		))
		menu.addItem(.separator())
		// Saying how many, so a menu opened over a selection of three does not
		// look like it is about the one row under the pointer.
		let copying = selectedBranches.count
		menu.addItem(item(
			copying > 1 ? "Copy \(copying) Names" : "Copy Name",
			#selector(copyBranchName)
		))
		menu.addItem(item("New Worktree from Here…", #selector(addWorktree)))
		menu.addItem(item(remoteMenuTitle, #selector(setRemote)))

		if case .local = branch.kind {
			// How many, for the same reason Copy Name says it: a menu opened over
			// a selection of three must not read as being about one row.
			let deleting = deletableBranches.count
			menu.addItem(item(
				deleting > 1 ? "Delete \(deleting) Branches…" : "Delete…",
				#selector(deleteBranch),
				enabled: deleting > 0
			))
		}
		if case .tag = branch.kind {
			menu.addItem(.separator())
			menu.addItem(item("Recreate…", #selector(recreateTag)))
		}
	}
}

/// Table that reports Return and double-click, for checkout.
/// Says what the chosen source resolves to, while it is being chosen.
///
/// Its own object rather than the pane, because the pane is already the
/// delegate of a search field and a table: one `controlTextDidChange` cannot
/// answer for three controls without asking which one it came from, and that
/// question has a wrong answer.
@MainActor
private final class TagSourceWatcher: NSObject, NSComboBoxDelegate {
	private let field: NSComboBox
	private let label: NSTextField
	private let root: URL

	init(field: NSComboBox, label: NSTextField, root: URL) {
		self.field = field
		self.label = label
		self.root = root
		super.init()
		field.delegate = self
	}

	func controlTextDidChange(_ notification: Notification) { refresh() }
	func comboBoxSelectionDidChange(_ notification: Notification) {
		// The field still holds the old text at this moment; the selection is
		// what was just picked.
		let index = field.indexOfSelectedItem
		guard index >= 0, let value = field.itemObjectValue(at: index) as? String else { return }
		describe(value)
	}

	func refresh() { describe(field.stringValue) }

	private func describe(_ source: String) {
		let asked = source.trimmingCharacters(in: .whitespaces)
		guard !asked.isEmpty else {
			label.stringValue = " "
			return
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			guard let found = await GitTags.describe(asked, in: self.root) else {
				// Said plainly rather than left blank: an empty line under a
				// name somebody has mistyped looks exactly like one under a
				// name that is fine.
				self.label.textColor = Theme.current.gitConflict
				self.label.stringValue = "git does not know “\(asked)”"
				return
			}
			self.label.textColor = Theme.current.gitAdded
			self.label.stringValue = "→ \(found)"
		}
	}
}

/// The tree, drawn by AppKit rather than by hand.
///
/// **What is left here is only what an outline view does not already do.**
/// Indentation, disclosure triangles and the clicks on them, ← and →, and
/// keeping the keyboard through an expansion are all AppKit's — and each one of
/// them was written out by hand here first, and each was reported broken.
private final class BranchesOutlineView: NSOutlineView {
	var onActivate: (() -> Void)?
	/// `⌘⏎` — the selected row's own verb, whatever that row is.
	var onRowAction: (() -> Void)?
	/// `↑` from the first row, which leaves for the row pinned above the tree.
	var onLeaveTop: (() -> Void)?

	/// A click from an inactive window lands on the row rather than being spent
	/// activating the app, which is what the project tree has always done.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	/// Redraw when focus moves, so the highlight dims with it.
	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		// **⌘⏎ before ⏎.** A row's verb needs a key of its own, or it is a
		// mouse-only feature — which these panes were fixed not to be. ⏎ is
		// taken: on a branch it checks it out, and one key meaning two things on
		// two rows is the overload this avoids.
		if event.keyCode == 36 || event.keyCode == 76 {
			if event.modifierFlags.contains(.command) {
				onRowAction?()
			} else {
				onActivate?()
			}
			return
		}

		// Home, End, Page Up and Page Down. An outline view interprets the
		// arrows and leaves these four to the scroll view, which moves the
		// paper and not the selection — so the list scrolled and the highlight
		// stayed where it was, which is not what any of them means in a list.
		// ↑ off the top goes to the row pinned above, which is the repository.
		if event.keyCode == 126, selectedRow == 0 {
			onLeaveTop?()
			return
		}

		let last = numberOfRows - 1
		guard last >= 0 else { return super.keyDown(with: event) }
		let page = max(1, Int(visibleRect.height / max(1, rowHeight)) - 1)
		let here = selectedRow < 0 ? 0 : selectedRow

		switch event.keyCode {
		case 115: select(row: 0)
		case 119: select(row: last)
		case 116: select(row: max(0, here - page))
		case 121: select(row: min(last, here + page))
		default:  super.keyDown(with: event)
		}
	}

	private func select(row: Int) {
		let found = min(max(0, row), numberOfRows - 1)
		guard found >= 0 else { return }
		selectRowIndexes([found], byExtendingSelection: false)
		scrollRowToVisible(found)
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?() }
	}
}

/// A merge that has stopped, and the three things somebody does next.
///
/// **Three, and deliberately not four.** Opening the files is the work; Fork is
/// where this change has already said a three-way merge editor belongs, so the
/// handoff has a home rather than being a dead end; and a prompt on the
/// clipboard hands the conflict to an agent in this app's own terminal, which
/// is the thing this app is for. Aborting is not here — the banner is about
/// resolving, and abandoning belongs on the operation that started the merge,
/// where what would be lost can be counted.
private final class BranchSectionView: ActionableRowView {
	private let title: String

	init(title: String) {
		self.title = title
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// What kind of thing a section holds.
	///
	/// **Icons at the root too.** Without one the indentation under a section
	/// reads as text that has been pushed sideways for no reason: every row
	/// below has a glyph, and the row above it had a gap where one should be.
	private var symbol: String {
		switch title {
		case "Local":     return "arrow.trianglehead.branch"
		case "Tags":      return "tag"
		case "Stashes":   return "tray.full"
		case "Worktrees": return "folder.badge.gearshape"
		// Anything else is a remote, named after the remote.
		default:          return "cloud"
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		// **No triangle of its own.** The outline view draws one, and a second
		// drawn here put two side by side on every section.
		RowMetrics.glyph(symbol, colour: Theme.current.gitIgnored, in: bounds)

		let label = NSAttributedString(string: title.uppercased(), attributes: [
			.font: Theme.current.uiFont(10, weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		label.draw(at: NSPoint(
			x: RowMetrics.textInset,
			y: bounds.midY - label.size().height / 2
		))

		drawAction()
	}
}

private final class BranchRowView: NSView {
	private let branch: GitBranch
	/// What the row says, which under a folder is one component of the name
	/// rather than all of it.
	private let display: String
	private let depth: Int
	private let isPushing: Bool
	/// Its work is already in the default branch: nothing on it that is not
	/// somewhere else. Drawn faded, and never for the branch you are on.
	private let isMerged: Bool
	/// What an unpublished branch's count is measured against, for the tooltip.
	private let base: String?
	private var spinner: NSProgressIndicator?
	override var isFlipped: Bool { true }

	init(
		branch: GitBranch,
		display: String? = nil,
		depth: Int = 0,
		isPushing: Bool = false,
		isMerged: Bool = false,
		base: String? = nil
	) {
		self.branch = branch
		self.display = display ?? branch.name
		self.depth = depth
		self.isPushing = isPushing
		self.base = base
		// **The branch you are standing on never dims, whatever the reading
		// says.** The default branch is trivially merged into itself and any
		// branch you have just merged and not left is finished by the same
		// test — and a faded row for the branch the window is on reads as
		// something being wrong rather than as something being done.
		self.isMerged = isMerged && !branch.isCurrent
		super.init(frame: .zero)
		guard !isPushing else {
			toolTip = "Pushing \(branch.name)…"
			return
		}
		// **The words the symbols replaced live here.** A symbol on a row is a
		// note somebody has to be able to look up, and the row already had a
		// tooltip to put it in.
		var notes: [String] = [branch.checkoutName]
		if !branch.subject.isEmpty { notes.append(branch.subject) }
		if self.isMerged { notes.append("already merged") }
		if branch.upstreamIsGone { notes.append("its upstream has been deleted") }
		else if branch.isUnpublished {
			let ahead = branch.aheadOfDefault ?? 0
			notes.append(ahead > 0
				? "never published — \(ahead) commit\(ahead == 1 ? "" : "s") of its own"
				: "never published")
			// The half the row does not draw, said here in words rather than
			// in an arrow that would be read as remote traffic.
			if let behind = branch.behindDefault, behind > 0 {
				notes.append("\(base ?? "the default branch")"
					+ " has moved on by \(behind) commit\(behind == 1 ? "" : "s")")
			}
		}
		toolTip = notes.joined(separator: " — ")

		guard isPushing else { return }
		// A real spinner rather than something drawn by hand: it has to keep
		// turning while a push waits on another machine, and that is exactly
		// what this control is for.
		let wheel = NSProgressIndicator()
		wheel.style = .spinning
		wheel.controlSize = .small
		wheel.isIndeterminate = true
		wheel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(wheel)
		NSLayoutConstraint.activate([
			wheel.centerYAnchor.constraint(equalTo: centerYAnchor),
			wheel.trailingAnchor.constraint(
				equalTo: trailingAnchor, constant: -Theme.current.scaled(10)
			),
			wheel.widthAnchor.constraint(equalToConstant: Theme.current.scaled(12)),
			wheel.heightAnchor.constraint(equalToConstant: Theme.current.scaled(12)),
		])
		wheel.startAnimation(nil)
		spinner = wheel
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		// **One text column for every kind of row.** The outline view has
		// already indented this view by its depth; anything added here is an
		// offset of its own, and five row kinds each adding a different one is
		// what made the tree look ragged.
		//
		// A constant now the trailing mark is right-aligned: nothing after the
		// name needs to know where the name ended.
		let x = RowMetrics.textInset

		// **What kind of thing this row is, said by a glyph.** A folded prefix
		// and a branch are both a name at a depth, and with only indentation to
		// tell them apart somebody has to count. The current branch keeps its
		// tick — that is how git itself marks it, and it outranks saying what
		// kind of ref it is, which is obvious for the one you are standing on.
		let mark: (name: String, colour: NSColor) = {
			if branch.isCurrent { return ("checkmark", Theme.current.gitAdded) }
			if case .tag = branch.kind { return ("tag", Theme.current.gitModified) }
			return ("arrow.trianglehead.branch", Theme.current.gitIgnored)
		}()
		// **A merged branch is faded, not greyed.** A fixed dim colour would be
		// a fourth meaning for a row's colour, next to current, tag and plain;
		// an alpha keeps whatever the row already said and says it quietly.
		let fade: (NSColor) -> NSColor = { [isMerged] colour in
			isMerged ? colour.withAlphaComponent(0.45) : colour
		}
		RowMetrics.glyph(mark.name, colour: fade(mark.colour), in: bounds)

		let colour = fade(branch.isCurrent ? Theme.current.gitAdded : Theme.current.sidebarText)
		let font = branch.isCurrent
			? NSFont.systemFont(ofSize: Theme.current.scaled(12), weight: .semibold)
			: Theme.current.uiFont(12)

		// **The trailing end of the row is a column**, right-aligned, so a list
		// of these reads down rather than along a ragged edge made of whatever
		// each name happened to leave. The changes tree's counts had the same
		// fault and it is fixed the same way.
		//
		// What sits in it is either news or a standing fact, and they are said
		// differently. Ahead and behind are news — somebody moved — and they
		// are numbers because the number is the point. Merged, never published,
		// and an upstream that has been deleted are facts about the branch that
		// do not change while you look at them, and they are symbols: two words
		// of English on every row of a list is a paragraph nobody reads.
		//
		// **Merged outranks the other two.** A branch whose pull request was
		// merged and whose remote branch went with it is both merged and
		// upstream-gone, and of the two only one of them is what you wanted to
		// know: the work is in, and this row can go. `not published` on a
		// branch that is already merged is a note about how it got there.
		//
		// The other two are `icloud` symbols because both are about the copy on
		// the other machine — one that was never made, one that has gone. The
		// counts could never have said either: nought ahead and nought behind
		// is what a branch level with its remote reads.
		let standing: (symbol: String, said: String)? = {
			if isMerged { return ("checkmark", "already merged") }
			if branch.upstreamIsGone { return ("xmark.icloud", "upstream gone") }
			if branch.isUnpublished { return ("icloud.and.arrow.up", "not published") }
			return nil
		}()

		// **A branch that has never been pushed still has a count worth
		// showing** — against the default branch, there being no upstream to
		// count from. The cloud stays beside it: *never published* and *three
		// commits of your own* are both true and neither implies the other.
		//
		// **Only the ahead half, and that is the whole care taken here.** `↑`
		// and `↓` are this pane's remote vocabulary — what is waiting to go up
		// and what is waiting to come down — and `↓1557` against the default
		// branch borrows the second of those to say something else entirely:
		// not *there are commits to pull* but *main has moved on, and you may
		// want to rebase*. It was read as the first, which is the only way it
		// could be read on a row where every other arrow means that.
		//
		// `↑` survives because it does not change meaning: commits this branch
		// has that the other side has not, which is both the work on it and
		// exactly what publishing would send. The number that could not be said
		// without misleading is not said — it is in the tooltip, in words,
		// where there is room to name what it is measured against.
		var counts = ""
		if branch.isUnpublished {
			let own = branch.aheadOfDefault ?? 0
			if own > 0 { counts = "↑\(own)" }
		} else if standing == nil {
			if branch.ahead > 0 { counts += "↑\(branch.ahead)" }
			if branch.behind > 0 { counts += (counts.isEmpty ? "" : " ") + "↓\(branch.behind)" }
		}

		let countsFont = Theme.current.uiFont(10.5)
		let countsWidth = counts.isEmpty ? 0 : ceil(NSAttributedString(
			string: counts, attributes: [.font: countsFont]
		).size().width)
		let symbolWidth = standing == nil ? 0 : RowMetrics.trailingGlyphSize
		let inner = countsWidth > 0 && symbolWidth > 0 ? Theme.current.scaled(5) : 0
		let trailingWidth = countsWidth + inner + symbolWidth

		// While pushing, the spinner has the right-hand end of the row.
		let right = bounds.maxX - RowMetrics.trailingInset
			- (isPushing ? Theme.current.scaled(18) : 0)
		let gap = Theme.current.scaled(6)

		RowMetrics.draw(
			display, font: font, colour: colour,
			at: x, in: bounds,
			limit: trailingWidth == 0 ? right : right - trailingWidth - gap
		)

		// The symbol takes the edge and the counts sit inside it, so the marks
		// of a kind line up with each other down the pane.
		if let standing {
			// **The tick is not faded, though everything beside it is.** It is
			// the reason the row is dim, and dimming the answer along with the
			// question leaves somebody looking at a grey row with nothing on it
			// saying why.
			RowMetrics.trailingGlyph(
				standing.symbol,
				colour: isMerged ? Theme.current.gitIgnored : fade(Theme.current.gitIgnored),
				in: bounds, rightAt: right
			)
		}
		guard !counts.isEmpty else { return }
		RowMetrics.drawTrailing(
			counts, font: countsFont,
			colour: fade(Theme.current.gitModified), in: bounds,
			rightAt: right - symbolWidth - inner
		)
	}
}

/// One file inside an opened stash.
/// The working copy: what you are doing, and how much of it there is.
private final class WorkingCopyRowView: ActionableRowView {
	private let changed: Int

	init(changed: Int) {
		self.changed = changed
		super.init(frame: .zero)
		toolTip = changed == 0
			? "Nothing has changed"
			: "\(changed) changed file\(changed == 1 ? "" : "s")"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let colour = changed > 0 ? Theme.current.gitModified : Theme.current.gitIgnored
		RowMetrics.glyph(
			changed > 0 ? "pencil.circle" : "checkmark.circle", colour: colour, in: bounds
		)
		// Measured first: the row's own text has to be laid out inside what the
		// action leaves, or the two are drawn over each other.
		let taken = actionWidth
		let after = RowMetrics.draw(
			"Working copy",
			font: Theme.current.uiFont(12, weight: .semibold),
			colour: colour,
			at: RowMetrics.textInset, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - taken
		)
		RowMetrics.draw(
			changed == 0 ? "clean" : "\(changed)",
			font: Theme.current.uiFont(10.5),
			colour: Theme.current.gitIgnored,
			at: after + Theme.current.scaled(8), in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - taken
		)
		drawAction()
	}
}

/// One changed file, or a folder of them, under the working copy.
///
/// Its own name rather than `ChangeRowView`, which `ChangesPane` already has:
/// two files each holding a private class of one name is legal and is a trap
/// for whoever reads a stack trace next.
private final class WorkingCopyChangeRowView: NSView {
	private let node: GitChangeNode
	private let staged: Bool
	override var isFlipped: Bool { true }

	init(node: GitChangeNode, staged: Bool) {
		self.node = node
		self.staged = staged
		super.init(frame: .zero)
		toolTip = node.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private var letter: String {
		guard let kind = node.change?.kind else { return "" }
		switch kind {
		case .added:      return "A"
		case .deleted:    return "D"
		case .renamed:    return "R"
		case .copied:     return "C"
		case .untracked:  return "?"
		case .conflicted: return "U"
		default:          return "M"
		}
	}

	private var colour: NSColor {
		guard let kind = node.change?.kind else { return Theme.current.gitIgnored }
		switch kind {
		case .added:      return Theme.current.gitAdded
		case .untracked:  return Theme.current.gitUnversioned
		case .deleted:    return Theme.current.gitConflict
		case .conflicted: return Theme.current.gitConflict
		default:          return Theme.current.gitModified
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		var x = RowMetrics.textInset

		// A folder of changes gets a folder, like a folder of branches; a file
		// gets the letter for what happened to it, in the same column.
		//
		// `holdsFiles`, so a wholly untracked directory gets one too — in the
		// colour its own kind is drawn in, which is what tells it apart from a
		// folder this tree invented. There is one column and it cannot hold both
		// a folder and a letter, so the tint carries the `?`.
		if node.holdsFiles {
			RowMetrics.glyph(
				"folder",
				colour: node.isFolder ? Theme.current.gitIgnored : colour,
				in: bounds
			)
		} else if !letter.isEmpty {
			RowMetrics.draw(
				letter, font: Theme.current.uiFont(11, weight: .semibold), colour: colour,
				at: RowMetrics.glyphInset + Theme.current.scaled(4), in: bounds,
				limit: bounds.maxX - RowMetrics.trailingInset
			)
		}

		x = RowMetrics.draw(
			node.name,
			font: Theme.current.uiFont(12),
			colour: node.isFolder ? Theme.current.sidebarText : colour,
			at: x, in: bounds, limit: bounds.maxX - RowMetrics.trailingInset
		)

		// A folder says how much of it is on this side, which is the one thing
		// a folder row has to say that a file row does not: two lists make a
		// folder in Staged look finished, and somebody reads it that way and
		// commits half of it.
		guard node.isFolder else { return }
		RowMetrics.draw(
			node.isPartial ? "\(node.count) of \(node.total)" : "\(node.count)",
			font: Theme.current.uiFont(10.5),
			colour: node.isPartial ? Theme.current.gitModified : Theme.current.gitIgnored,
			at: x + Theme.current.scaled(6), in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

private final class StashFileRowView: NSView {
	private let file: GitCommitFile
	override var isFlipped: Bool { true }

	init(file: GitCommitFile) {
		self.file = file
		super.init(frame: .zero)
		toolTip = file.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private var letter: String {
		switch file.kind {
		case .added:      return "A"
		case .deleted:    return "D"
		case .renamed:    return "R"
		case .copied:     return "C"
		case .untracked:  return "?"
		case .conflicted: return "U"
		default:          return "M"
		}
	}

	private var colour: NSColor {
		switch file.kind {
		case .added, .untracked: return Theme.current.gitAdded
		case .deleted:           return Theme.current.gitConflict
		case .conflicted:        return Theme.current.gitConflict
		default:                 return Theme.current.gitModified
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		RowMetrics.draw(
			letter, font: Theme.current.uiFont(10.5), colour: colour,
			at: RowMetrics.glyphInset, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
		var x = RowMetrics.textInset
		// The name, with the folder it is in behind it — a stash of four files
		// three directories apart is unreadable as bare basenames.
		x = RowMetrics.draw(
			file.name, font: Theme.current.uiFont(12), colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: bounds.maxX - RowMetrics.trailingInset
		)
		guard !file.directory.isEmpty else { return }
		RowMetrics.draw(
			file.directory, font: Theme.current.uiFont(10.5),
			colour: Theme.current.gitIgnored,
			at: x + Theme.current.scaled(6), in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

/// A prefix several branches share, and how many are under it.
/// Where the head is when it is on no branch, and what git has stopped in the
/// middle of.
///
/// It sits where the ticked branch would be, and takes the tick's place in the
/// conflict colour rather than the added one: this is a place to be, but not a
/// place to commit onto — a commit made here belongs to no branch until one is
/// put on it, which is the thing this row exists to keep somebody from
/// discovering afterwards.
private final class DetachedHeadRowView: NSView {
	private let notice: String
	override var isFlipped: Bool { true }

	init(notice: String) {
		self.notice = notice
		super.init(frame: .zero)
		toolTip = "Not on a branch — \(notice). A commit here belongs to no branch "
			+ "until one is put on it."
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		RowMetrics.glyph(
			"exclamationmark.triangle", colour: Theme.current.gitConflict, in: bounds
		)
		RowMetrics.draw(
			notice,
			font: Theme.current.uiFont(12, weight: .medium),
			colour: Theme.current.gitConflict,
			at: RowMetrics.textInset, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

private final class BranchFolderRowView: NSView {
	private let display: String
	private let count: Int
	override var isFlipped: Bool { true }

	init(display: String, count: Int) {
		self.display = display
		self.count = count
		super.init(frame: .zero)
		toolTip = "\(count) branch\(count == 1 ? "" : "es") under \(display)/"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		// No twisty and no indent: an outline view draws both, and drawing a
		// second set beside them is what made this look like several trees.
		//
		// A folder does get a folder, which is the whole of what tells it from
		// a branch of the same name at the same depth.
		RowMetrics.glyph("folder", colour: Theme.current.gitIgnored, in: bounds)
		let x = RowMetrics.textInset
		// **No trailing slash.** It was there to say "a prefix, not a branch
		// called `feature`" back when this was a flat list with nothing else to
		// say it. The disclosure triangle says it now — and the same row draws
		// `Staged` and `Unstaged`, which are not prefixes at all and read as
		// nonsense with one.
		let after = RowMetrics.draw(
			display,
			font: Theme.current.uiFont(12),
			colour: Theme.current.sidebarText,
			at: x, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - Theme.current.scaled(24)
		)
		RowMetrics.draw(
			"\(count)",
			font: Theme.current.uiFont(10.5),
			colour: Theme.current.gitIgnored,
			at: after + Theme.current.scaled(6), in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

/// A stash: what it was called, and how long it has been waiting.
private final class StashRowView: NSView {
	private let entry: GitStash.Entry
	private let isOpen: Bool
	/// Whether it would still go back, once that has been asked. Nil until the
	/// row has been opened, because asking costs a three-way merge.
	private let applies: GitStash.Applicability?
	override var isFlipped: Bool { true }

	init(entry: GitStash.Entry, isOpen: Bool = false, applies: GitStash.Applicability? = nil) {
		self.entry = entry
		self.isOpen = isOpen
		self.applies = applies
		super.init(frame: .zero)

		var said = [entry.reference, entry.branch.isEmpty ? nil : "on \(entry.branch)", entry.age]
			.compactMap { $0 }
		switch applies {
		case .clean:                 said.append("applies cleanly")
		case let .conflicts(paths):  said.append("would conflict in \(paths.joined(separator: ", "))")
		case .unknown, .none:        break
		}
		toolTip = said.joined(separator: " — ")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = RowMetrics.textInset

		RowMetrics.glyph(
			isOpen ? "tray.full.fill" : "tray.full",
			colour: Theme.current.sidebarText, in: bounds
		)

		// How long it has been sitting there decides whether it is still
		// wanted, so it keeps its room and the message gives way first.
		let ageFont = Theme.current.uiFont(10.5)
		let ageWidth = entry.age.isEmpty ? 0 : NSAttributedString(
			string: entry.age, attributes: [.font: ageFont]
		).size().width + Theme.current.scaled(8)

		// Whether it would still go back, in the colour that already means
		// "this is fine" and "this is not" everywhere else in this window.
		var mark = ""
		var markColour = Theme.current.gitAdded
		switch applies {
		case .clean:
			mark = "✓"
		case let .conflicts(paths):
			mark = "⚠\(paths.count)"
			markColour = Theme.current.gitModified
		case .unknown, .none:
			break
		}
		let markFont = Theme.current.uiFont(10.5)
		let markWidth = mark.isEmpty ? 0 : NSAttributedString(
			string: mark, attributes: [.font: markFont]
		).size().width + Theme.current.scaled(8)

		let limit = bounds.maxX - RowMetrics.trailingInset
		x = RowMetrics.draw(
			entry.message, font: Theme.current.uiFont(12), colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: limit - ageWidth - markWidth
		)

		if !entry.age.isEmpty {
			x = RowMetrics.draw(
				entry.age, font: ageFont,
				colour: Theme.current.sidebarText.withAlphaComponent(0.55),
				at: x + Theme.current.scaled(8), in: bounds, limit: limit - markWidth
			)
		}
		guard !mark.isEmpty else { return }
		RowMetrics.draw(
			mark, font: markFont, colour: markColour,
			at: x + Theme.current.scaled(8), in: bounds, limit: limit
		)
	}
}

/// A worktree: where it is, what is checked out there, and whether it is still
/// on disk.
private final class WorktreeRowView: NSView {
	private let worktree: GitWorktree
	override var isFlipped: Bool { true }

	init(worktree: GitWorktree) {
		self.worktree = worktree
		super.init(frame: .zero)
		toolTip = worktree.path.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(18)

		// The one the repository was cloned into is marked, since it is the one
		// that cannot be removed.
		let symbol = worktree.isPrimary ? "house" : (worktree.isMissing ? "questionmark.circle" : "folder")
		let tint = worktree.isMissing ? Theme.current.gitUnversioned : Theme.current.gitIgnored
		if let icon = Theme.symbol(symbol, size: 10 * Theme.current.scale, color: tint) {
			let size = Theme.current.scaled(11)
			icon.drawFitted(in: NSRect(
				x: Theme.current.scaled(4), y: bounds.midY - size / 2, width: size, height: size
			))
		}

		let limit = bounds.maxX - RowMetrics.trailingInset
		x = RowMetrics.draw(
			worktree.name,
			font: Theme.current.uiFont(12),
			colour: worktree.isMissing ? Theme.current.gitIgnored : Theme.current.sidebarText,
			at: x, in: bounds, limit: limit
		)

		var note = worktree.branch ?? "detached"
		// **Which ones this program made to read somebody else's work.** A
		// checkout made for a review is temporary and belongs to a pull request
		// rather than to a piece of work; saying so is what makes them
		// collectable, and a reviewer who opens three a day would otherwise grow
		// three checkouts a day named after strangers' branches.
		if let number = ReviewCheckouts.shared.number(of: worktree.path) {
			note += " · PR #\(number)"
		}
		if worktree.isMissing { note += " · missing" }
		if worktree.isLocked { note += " · locked" }

		RowMetrics.draw(
			note,
			font: Theme.current.uiFont(10),
			colour: worktree.isMissing ? Theme.current.gitUnversioned : Theme.current.gitIgnored,
			at: x + Theme.current.scaled(6), in: bounds, limit: limit
		)
	}
}

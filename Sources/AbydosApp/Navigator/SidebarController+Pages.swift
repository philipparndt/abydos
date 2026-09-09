import AppKit
import AbydosKit

/// The pages the sidebar opens in the editor: the log, the commit, a stash and
/// the estate — and what has to be reopened when a project is opened again.
///
/// A page is not a sidebar tool. It goes in the editor's tab group, it is the
/// thing somebody reads at width, and the sidebar is only what asked for it.
extension SidebarController {
	///   Its page is its own, beside the project's, and is not written into
	///   the session: a page whose identity is a directory that may not be
	///   there next time is left closed rather than guessed at, which is what
	///   `reopen(page:)` does with every identifier it does not know.
	@discardableResult
	func showLogPage(scopedTo ref: String?, asked: Bool = true, in owner: URL? = nil) -> HistoryPane? {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return nil }

		let estateRoot = gitCommandRoot() ?? project.root
		let root = owner ?? estateRoot
		let isProjects = root.standardizedFileURL.path == estateRoot.standardizedFileURL.path
		let identifier = isProjects ? "log" : "log:" + root.standardizedFileURL.path
		let page = (group.page(identifier: identifier) as? HistoryPane)
			?? HistoryPane(root: root, layout: .page)
		// The project's own log is the one the blame column, the editor's
		// "This File" and the session all reach for; a submodule's is not
		// theirs to scope.
		if isProjects { logPage = page }
		page.onOpenWorkingCopyDiff = { [weak self] change, root, text in
			self?.editor.openDiff(for: change, root: root, text: text)
		}

		// Named for what it is showing: two log tabs both called "Log" would be
		// the tab strip saying nothing, and a log scoped to a branch is a
		// different question from the one about where you are standing. A
		// submodule's log says whose it is, for the same reason.
		let name = isProjects ? nil : root.lastPathComponent
		group.openPage(
			page,
			title: (["Log", name, ref].compactMap { $0 }).joined(separator: " · "),
			identifier: identifier,
			symbol: "clock.arrow.circlepath"
		)
		// **It does not take the window.** It used to, on the argument that a
		// graph and a diff want the room — which is true and is not this page's
		// call to make. The panel's height and the tree's width are somebody's
		// own arrangement, chosen for what they were doing a minute ago, and
		// rearranging it to show them a log is the mode `giveTheEditorTheWindow`
		// already refuses to undo on the way out. The commit page stopped doing
		// this for the same reason; the log had been left behind.
		//
		// The two gestures that give it the room are the ones that always did:
		// double-click the tab, or the View menu.
		//
		// Opened to be read, and read with the arrows: a page whose keyboard is
		// still in whatever opened it needs a click before it can be walked.
		DispatchQueue.main.async { [weak page] in page?.focusList() }
		page.setRef(ref)
		return page
	}

	/// The message being composed, wherever it is being composed.
	///
	/// The page first: somebody who promoted the message with `…` is typing in
	/// the page, and the sidebar's field holds what they left behind. Nil when
	/// nothing has been typed in either.
	var composedMessage: ProjectSession.ComposedMessage? {
		commitPage?.composedMessage ?? changesPane?.composedMessage
	}

	/// The pages that are open, with what each is showing.
	///
	/// Read off the editor's own tabs rather than the weak handles here: a page
	/// this controller never opened — a pull request review, the settings page —
	/// is still a page the window had.
	/// What the trees are folded into now, for the session.
	///
	/// Asked of the panes that exist: a tool nobody has opened in this sitting
	/// has no pane, and what was read out of the session for it is handed back
	/// unchanged rather than being replaced with nothing. Otherwise opening a
	/// project and never touching the git tool would erase the folds in it.
	func foldsToRemember(carrying stored: [String: ProjectSession.TreeFolds])
		-> [String: ProjectSession.TreeFolds] {
		var folds = stored
		if let branchesPane { folds["refs"] = branchesPane.foldsWorthKeeping }
		if let changesPane {
			let sides = changesPane.folds
			folds["changes.unstaged"] = sides["changes.unstaged"]
			folds["changes.staged"] = sides["changes.staged"]
		}
		folds["tree"] = navigator.folds
		return folds.compactMapValues { $0.isEmpty ? nil : $0 }
	}

	/// Which tool is in front, by the name the session keeps it under.
	var toolToRemember: String { currentSidebarTool.stored }

	func openPagesToRemember() -> [ProjectSession.OpenPage] {
		editor.openPageIdentifiers().map { identifier in
			switch identifier {
			case "log":
				return ProjectSession.OpenPage(
					identifier: identifier, showing: logPage?.scopeToRemember() ?? [:]
				)
			case "stash":
				return ProjectSession.OpenPage(
					identifier: identifier, showing: stashPage?.stashToRemember() ?? [:]
				)
			default:
				return ProjectSession.OpenPage(identifier: identifier)
			}
		}
	}

	/// Reopens the pages a session remembered, once the repository is readable.
	///
	/// **After the git read, and not before.** Every opener below refuses while
	/// `project.git` is nil, which is the state a window is in for the second or
	/// two after it opens — reopening there would drop the lot in silence. The
	/// openers are the ones a click uses and each reuses an existing tab, so a
	/// restore that races somebody opening the same page cannot make two.
	func reopen(pages: [ProjectSession.OpenPage]) {
		guard !pages.isEmpty else { return }
		Task { @MainActor [weak self] in
			await self?.project()?.loadGit()
			guard let self, let project = self.project(), project.git != nil else { return }
			for page in pages { self.reopen(page: page) }
		}
	}

	/// **Nothing here asked for anything.** These pages are coming back with a
	/// project, which happens by itself: a window following its terminal
	/// switches project when the shell walks into another one, and switching a
	/// tmux window is how a shell walks. Reported as the maximised terminal
	/// being lost on a tab switch — and only for a project that had a log or a
	/// commit page open, which is what pointed at these four calls.
	/// Restores the pages a run names, so the path can be driven at all.
	///
	/// **A driven run never reads a real session** — `SessionStore.read`
	/// refuses one, which is half of item 0522 — so the restore this is about
	/// cannot happen by itself in a run. The pages come from the run instead
	/// of from somebody's project, and everything after that is the app's own
	/// code.
	func restorePagesForTesting(_ identifiers: [String]) -> String {
		reopen(pages: identifiers.map { ProjectSession.OpenPage(identifier: $0) })
		return "restoring: " + identifiers.joined(separator: ", ")
	}

	private func reopen(page: ProjectSession.OpenPage) {
		switch page.identifier {
		case "commit":
			showCommitPage(carrying: nil, asked: false)
		case "log":
			showLogPage(scopedTo: page.showing["ref"], asked: false)
			if let path = page.showing["path"] {
				logPage?.offerScope(path: path)
				logPage?.setScope(path: path)
			}
		case "stash":
			// **By commit, not by index.** `stash@{0}` is a different commit
			// after one `git stash push`, so an index would reopen the page on
			// somebody else's work. The commit may also be gone — popped from
			// another window — and a page about a stash that no longer exists
			// has nothing to show, so it stays closed.
			guard let commit = page.showing["commit"],
			      let root = gitCommandRoot() ?? project()?.root else { return }
			Task { @MainActor [weak self] in
				let entries = await GitStash.list(in: root)
				guard let entry = entries.first(where: { $0.commit == commit }) else { return }
				self?.showStashPage(entry, asked: false)
			}
		case "estate":
			showEstatePage(asked: false)
		case "launch":
			// **Written into every session file and read by nothing.** The
			// `sessions` capability already requires "the pages whose identity
			// is their identifier alone" to come back, and these two were
			// captured, stored and dropped on the way in — a requirement that
			// existed and was unmet rather than a new one.
			openLaunchConfigurationsPage()
		case "settings":
			openSettingsPage()
		default:
			// A compare page carries its two sides in its identifier; a side
			// that is gone is the page's own to say.
			if let sides = ComparePageIdentity.sides(of: page.identifier) {
				onOpenComparePage?(sides.left, sides.right)
				break
			}
			// A page this version has no opener for — one a later version wrote
			// down, or one whose owner is elsewhere in the app. Left closed
			// rather than guessed at.
			break
		}
	}

	/// Opens the commit view as a page in the editor area.
	///
	/// **The same pane at the size it needs**, exactly as the log is: the tree,
	/// folder staging and the discard question are the same questions at either
	/// size, so there is one class and two arrangements rather than two classes
	/// that drift.
	///
	/// - Parameter carrying: what has been typed into the sidebar's summary, so
	///   pressing `…` is promoting a message rather than starting a second one.
	/// - Parameter asked: whether somebody asked for this page. Only then does
	///   it give the editor the window back: while the terminal panel has the
	///   whole window the editor is *hidden*, so a page opened into it could
	///   not be seen — and a page being restored with a project asked for
	///   nothing. See `reopen(page:)`, which is the other caller.
	func showCommitPage(carrying summary: String?, asked: Bool = true) {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return }

		let page: ChangesPane
		let wanted = gitCommandRoot() ?? project.root
		if let existing = group.page(identifier: "commit") as? ChangesPane,
		   existing.repositoryRoot.standardizedFileURL == wanted.standardizedFileURL {
			// **Its root is checked, which it was not.** A page is reused by
			// identifier, so a commit page left over from another project was
			// handed this project's remembered message and this project's
			// draft — the report's fault by a second door.
			page = existing
		} else {
			page = ChangesPane(root: gitCommandRoot() ?? project.root, layout: .page)
			page.onWorkingCopyChanged = { [weak self] in
				self?.navigator.refreshGitStatus()
				self?.changesPane?.refresh()
			}
			// The verbs over the page's own diff. Without these the menu is
			// still offered — `DiffView` builds it for any diff that is not
			// read-only — and pressing it does nothing at all.
			page.onApplyDiffSelection = { [weak self] change, diff, lines, owner in
				self?.applyDiffSelection(
					change: change, diff: diff, lines: lines, in: owner, from: .page
				)
			}
			page.onDiscardDiffSelection = { [weak self] change, diff, lines, owner in
				self?.discardDiffSelection(
					change: change, diff: diff, lines: lines, in: owner, from: .page
				)
			}
			// **Offered only where git can do it**, as the editor's diff is:
			// `stash push --staged` arrived in 2.35, and on an older one the
			// item is absent rather than failing when pressed.
			// Held rather than captured weakly: the check is one command and the
			// page is the caller's. Named for what it is now that `asked` means
			// "somebody asked for this page" in this function's signature.
			let thePage = page
			Task { @MainActor [weak self] in
				guard await GitStash.canPushStaged(in: thePage.repositoryRoot) else { return }
				thePage.onStashDiffSelection = { [weak self] change, diff, lines, owner in
					self?.stashDiffSelection(
						change: change, diff: diff, lines: lines, in: owner, from: .page
					)
				}
			}
		}
		commitPage = page
		// **No longer takes the window.** It did because the page was unreadable
		// small: a fixed 224 points of message area left four lines of diff on a
		// short page. The message is two rows now and under the diff rather than
		// across the width, so the page is worth opening at whatever size it is
		// given — and taking somebody's tree and terminal away to show them a
		// commit is a thing to do only when the page cannot be read otherwise.
		group.openPage(page, title: "Commit", identifier: "commit", symbol: "checkmark.circle")
		DispatchQueue.main.async { [weak page] in page?.focusList() }

		if let summary, !summary.isEmpty { page.carrySummaryForTesting(summary) }
		wireDrafts(of: page)
		// A page reopened by a session is where the message was being written
		// if `…` had been pressed, so it is offered here too — into empty
		// fields only, so promoting a summary from the sidebar still wins.
		if let message = rememberedMessage() { page.restore(message: message) }
		page.applyHeldDraft()
		page.refresh()
	}

	/// Asks whichever panes exist to take what the inbox holds for them.
	///
	/// What a late answer does: the pane that asked applies it if it is still
	/// the pane for that project, and any other pane declines.
	func applyHeldDraftsForTesting() {
		changesPane?.applyHeldDraft()
		commitPage?.applyHeldDraft()
	}

	/// Gives a pane the inbox, both ways.
	///
	/// One function for both construction sites, because a pane that can hand a
	/// draft in and not ask for one is a pane that loses drafts silently —
	/// which is the fault this is fixing, in a new place.
	func wireDrafts(of pane: ChangesPane) {
		pane.onDraft = { [weak self] root, draft in self?.holdDraft(root, draft) }
		pane.heldDraft = { [weak self] root in self?.heldDraft(root) }
		pane.onDraftTaken = { [weak self] root in self?.discardDraft(root) }
	}

	/// One stash, as a page — see `StashPage`.
	///
	/// **One page, re-pointed.** Reviewing a second stash re-uses the first
	/// page rather than opening a tab per stash: `openPage` already keys by
	/// identifier, and a row of near-identical tabs called `Stash` would be a
	/// tab strip nobody can read.
	func showStashPage(_ entry: GitStash.Entry, asked: Bool = true) {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else {
			return
		}
		let root = gitCommandRoot() ?? project.root
		let page: StashPage
		if let existing = group.page(identifier: "stash") as? StashPage {
			page = existing
			page.show(entry)
		} else {
			page = StashPage(root: root, entry: entry)
			// **Through the pane, because the questions live there.** Applying
			// asks whether the entry should stay, branching asks for a name,
			// and dropping says the work is on no branch — three dialogs this
			// page would otherwise own a second copy of.
			page.onApply = { [weak self] entry in self?.branchesPane?.apply(stash: entry) }
			page.onBranch = { [weak self] entry in self?.branchesPane?.branch(fromStash: entry) }
			page.onDrop = { [weak self] entry in self?.branchesPane?.drop(stashes: [entry]) }
		}
		stashPage = page
		group.openPage(page, title: "Stash", identifier: "stash", symbol: "tray.full")
	}

	/// Every submodule in the estate, as a page — see `EstateOverviewPage`.
	func showEstatePage(asked: Bool = true) {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return }

		let page = (group.page(identifier: "estate") as? EstateOverviewPage)
			?? EstateOverviewPage(root: gitCommandRoot() ?? project.root)
		page.onOpenPullRequest = { [weak self] number, root in
			_ = self?.pullRequests.openFromEstate(number: number, in: root)
		}
		page.onOpenSubmodule = { [weak self] path in
			// The submodule's own changes, in the page that already draws them —
			// landing on that repository's row, not merely opening a page that
			// looks the same as it did before the row was pressed.
			guard let self else { return }
			showCommitPage(carrying: nil)
			// After the page has read the working copy, or the row it is being
			// asked to select does not exist yet.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
				self?.commitPage?.select(path: path)
			}
		}
		estatePage = page
		group.openPage(
			page, title: "Submodules", identifier: "estate", symbol: "square.stack.3d.up"
		)
		giveTheEditorTheWindow()
	}
}

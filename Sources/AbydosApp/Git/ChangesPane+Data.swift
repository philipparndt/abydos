import AppKit
import AbydosKit

/// What the pane is showing: reading the status, arranging it into the two
/// lists, and keeping the selection across a reload.
extension ChangesPane {
	// MARK: - Data

	func refresh() { refresh(.everything) }

	/// A refresh asked for while an operation was in flight, kept for when it
	/// ends. Dropped, it was the second double-click during a stage vanishing:
	/// the trees then waited for an unrelated event to come true again. The
	/// navigator's `wantsAnotherGitStatus` is the same shape for the same
	/// reason.
	/// Ends an operation and runs the refresh that arrived during it, if one
	/// did. For the paths that do not refresh unconditionally afterwards —
	/// a failed commit returns early, and a kept refresh must not be kept
	/// for ever.
	func endBusy() {
		isBusy = false
		guard wantsAnotherRefresh else { return }
		wantsAnotherRefresh = false
		refresh()
	}

	func refresh(_ read: EstateChanges.Read) {
		guard read != .nothing else { return }
		guard !isBusy else {
			wantsAnotherRefresh = true
			return
		}
		// Outside the comparison below: a clean working copy produces the same
		// status every time, and the branch can still have moved ahead of its
		// remote since the last look.
		refreshPushState()
		Task { @MainActor in
			// **The count goes to the strip that is already up.** A cold sweep
			// of an estate is minutes of waiting that used to look identical to
			// a hung pane; this is the same wait with the number in it. Nil
			// once the first read is done, so a later sweep — a checkout, a
			// pull — moves nothing on a pane that has rows on it.
			// Not `[weak self]`: the `Task` around this already holds `self`
			// for the whole span in which the sweep can call back, so the weak
			// capture bought nothing and only disagreed with its own scope.
			let fresh = await submodules.refresh(read) { done, total in
				Task { @MainActor in
					self.activity?.count(
						done, of: total,
						saying: "Reading \(done) of \(total) repositories…"
					)
				}
			}
			let statusReturned = Date()
			// Taken down before the comparison below, not after it. An
			// unchanged status is still an answer, and a spinner that only
			// stopped when something had changed span for ever over a clean
			// working copy.
			finishFirstRead()
			guard fresh != status else { return }
			status = fresh
			reload()
			sayOperationTiming(statusReturned: statusReturned, reloadDone: Date())
		}
	}

	/// Shown until the first `git status` comes back.
	///
	/// Only the first: after that the pane has rows on it, and covering them
	/// every time a build writes a file would be worse than a moment of
	/// staleness.
	/// Puts the spinner up. Called once, as the pane is built, because that is
	/// when there is nothing on screen and the wait is longest.
	/// **The words start as the one repository's and change when there turn
	/// out to be many.** The inventory is read inside the sweep, so nothing
	/// here knows yet whether this is one repository or two hundred; the count
	/// arrives with its own sentence and replaces this one when it does.
	func beginFirstRead() {
		activity = PaneActivityView.install(over: self, message: "Reading changes…")
	}

	/// Puts the sweep's progress strip up with numbers of somebody's choosing,
	/// for a driven run — and says what it reads, because a bar in a
	/// photograph cannot be grepped.
	///
	/// A warm estate answers in half a second and a cold one is what this is
	/// about, so the strip cannot be caught by waiting for it.
	func showProgressForTesting(done: Int, of total: Int) -> String {
		if activity == nil { beginFirstRead() }
		activity?.count(done, of: total, saying: "Reading \(done) of \(total) repositories…")
		return activity?.reportForTesting ?? "no strip"
	}

	private func finishFirstRead() {
		activity?.finish()
		activity = nil
	}

	func reload() {
		// Marked, because the stall log said `idle` 491 times out of 498 while
		// staging felt slow: a rebuild that stalls has to name itself before
		// anybody can shorten it.
		StallWatch.mark("changes reload") { reloadMarked() }
	}

	private func reloadMarked() {
		rebuild(unstagedTable, staged: false, changes: status.unstaged, against: status.staged)
		rebuild(stagedTable, staged: true, changes: status.staged, against: status.unstaged)
		// Files, not rows: "Commit 7 Files" has to keep meaning seven files
		// however many folders they are spread over.
		unstagedHeader.setCount(status.unstaged.count)
		stagedHeader.setCount(status.staged.count)
		updateCommitButton()
	}

	/// **The pane no longer asks how much changed.** It ran one
	/// `git diff --numstat` a side and then one more per submodule that had
	/// changes, all to fill the `+192 −46` at the end of every row — and those
	/// numbers are gone from the rows. On an estate of two hundred services
	/// that was a second fan-out of git processes behind the panel opening, for
	/// something nothing draws. The commit page's own file list still shows
	/// counts and reads them its own way, per commit, through
	/// `GitEstateLineCounts` — which is why that stays.
	///
	/// Builds one side's tree again and puts back what was on screen.
	///
	/// `refreshGitStatus` runs on every filesystem event, so this is the path a
	/// build writing files takes dozens of times a minute. A rebuild that let
	/// the tree fold itself up would collapse the pane under somebody halfway
	/// through reviewing it, which is the fault this ordering exists to avoid.
	/// Nothing here takes the side as `inout`. `reloadData` asks the data source
	/// for the rows while it runs, and the data source reads the very property
	/// that would be exclusively held — which Swift traps on, and did.

	private func rebuild(
		_ outline: ChangesOutlineView,
		staged: Bool,
		changes: [GitChange],
		against other: [GitChange]
	) {
		let selected = selectedPaths(in: outline)
		let collapsed = collapsedPaths(in: outline)
		let roots = GitChangeTree.build(changes, against: other, in: submodules.estate)
		let byPath = GitChangeTree.index(roots)
		if staged {
			stagedSide.roots = roots
			stagedSide.byPath = byPath
			stagedSide.collapsed = collapsed
			// Anything that has gone away since stops being remembered, or the
			// set grows for the life of the window.
			stagedSide.opened.formIntersection(byPath.keys)
			stagedSide.untrackedContents = stagedSide.untrackedContents.filter { byPath[$0.key] != nil }
		} else {
			unstagedSide.roots = roots
			unstagedSide.byPath = byPath
			unstagedSide.collapsed = collapsed
			unstagedSide.opened.formIntersection(byPath.keys)
			unstagedSide.untrackedContents = unstagedSide.untrackedContents.filter { byPath[$0.key] != nil }
		}

		// Before `reloadData`, so the rows are under the open directories by the
		// time the view asks for them.
		refill(side(for: outline), in: outline, staged: staged)

		isRestoring = true
		outline.reloadData()
		expand(roots, in: outline, collapsed: collapsed)
		// The auto-expansion above deliberately skips untracked directories —
		// opening one costs a git call, so it is never done on anybody's behalf.
		// These are the ones somebody opened by hand.
		for path in side(for: outline).opened {
			if let node = byPath[path] { outline.expandItem(node) }
		}
		restore(selection: selected, in: outline, staged: staged)
		stopRestoring()
		// Rows arrive after the page opens, so the keyboard may have been put
		// into a list that was empty at the time. Now that there are rows, move
		// it to one that has some — but only if it is still sitting somewhere
		// with nothing in it, so a list somebody is actually working in is never
		// taken from them.
		moveKeyboardOffAnEmptyList()
	}

	/// Which folders are folded shut, read off the tree rather than remembered
	/// as it happened.
	///
	/// Asking the view is the only way to get this right. `collapseItem` posts
	/// `didCollapse` for every folder *under* the one that was folded as well —
	/// they have stopped being displayed — and a set built from those
	/// notifications says somebody shut six folders when they shut one, so
	/// opening it again gave back a folder whose insides were all closed.
	///
	/// The visible rows only, and starting from what was already known: a
	/// folder inside a shut one is not a row and nothing here has anything to
	/// say about it, so whatever it was last seen doing it keeps doing.
	private func collapsedPaths(in outline: NSOutlineView) -> Set<String> {
		var found = side(for: outline).collapsed
		for row in 0..<outline.numberOfRows {
			guard let node = outline.item(atRow: row) as? GitChangeNode, node.isFolder else { continue }
			if outline.isItemExpanded(node) { found.remove(node.path) } else { found.insert(node.path) }
		}
		return found
	}

	func expand(_ nodes: [GitChangeNode], in outline: NSOutlineView, collapsed: Set<String>) {
		// Counted first, because `expandItem` is not free and there is a number
		// of them past which opening everything is not a favour. A work tree
		// holding untracked build output has thousands of folders in it, and
		// expanding every one meant thousands of `expandItem` calls on the main
		// thread on every filesystem event — a pane that took seconds to appear
		// and then could not be scrolled.
		//
		// Past the limit the top level is opened and the rest is left folded,
		// which is also the more useful shape: a tree that arrives entirely open
		// and ten thousand rows long has told you nothing.
		var folders = 0
		count(nodes, into: &folders, upTo: Self.expandEverythingBelow)
		let deep = folders <= Self.expandEverythingBelow
		expand(nodes, in: outline, collapsed: collapsed, recursively: deep)
	}

	/// How many folders a side may have before it stops opening all of them.
	private static let expandEverythingBelow = 500

	private func count(_ nodes: [GitChangeNode], into total: inout Int, upTo limit: Int) {
		for node in nodes where node.isFolder {
			total += 1
			// Stops as soon as the answer cannot change, so counting a tree of
			// fifteen thousand folders costs five hundred.
			guard total <= limit else { return }
			count(node.children, into: &total, upTo: limit)
			guard total <= limit else { return }
		}
	}

	func expand(
		_ nodes: [GitChangeNode],
		in outline: NSOutlineView,
		collapsed: Set<String>,
		recursively: Bool
	) {
		for node in nodes where node.isFolder && !collapsed.contains(node.path) {
			outline.expandItem(node)
			guard recursively else { continue }
			expand(node.children, in: outline, collapsed: collapsed, recursively: true)
		}
	}

	/// The paths of every selected row, in tree order.
	///
	/// All of them rather than the first: this is the shrinking-selection fault
	/// `TreeSelection` was written for, and a pane that quietly cut a selection
	/// of five down to one every time a file was saved would be the same bug in
	/// a second place.
	func selectedPaths(in outline: NSOutlineView) -> [String] {
		TreeSelection.paths(rows: Array(outline.selectedRowIndexes)) { row in
			(outline.item(atRow: row) as? GitChangeNode)?.path
		}
	}

	private func restore(selection paths: [String], in outline: NSOutlineView, staged: Bool) {
		let side = self.side(for: outline)
		let rows = TreeSelection.rows(for: paths) { path in
			guard let node = side.byPath[path] else { return -1 }
			return outline.row(forItem: node)
		}
		if !rows.isEmpty {
			outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
			// **The fallback is not cleared here, and that was the bug.**
			// Staging writes `.git/index`, the watcher sees it, and a refresh
			// runs *between* the fallback being recorded and the rows actually
			// going. That rebuild still finds the selected row — it is still
			// there — restores it, and threw the fallback away on its way past.
			// The rebuild that then loses the row had nothing to fall back to.
			//
			// It is only ever read when the whole selection has gone, and every
			// operation records a fresh one, so keeping it costs nothing and
			// removes a whole class of "something rebuilt in between".
			return
		}

		// Everything that was selected has gone — which is the ordinary outcome
		// of staging, since a folder with nothing left under it stops being a
		// row. Land on the nearest row above where it was rather than nowhere:
		// the next Return should act on something near what was just staged,
		// and a pane that empties its own selection makes the keyboard useless
		// exactly when it is being used.
		guard !paths.isEmpty else { return }
		for target in side.fallback {
			var candidate: String? = target
			while let path = candidate {
				if let node = side.byPath[path] {
					let row = outline.row(forItem: node)
					if row >= 0 {
						outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
						return
					}
				}
				// The row above may have been staged in the same gesture, so
				// its folder is gone too; the folder above that is still a row.
				let parent = (path as NSString).deletingLastPathComponent
				candidate = parent.isEmpty ? nil : parent
			}
		}
	}

	/// Notes where the selection should land once these rows have been staged
	/// away, before the command that takes them.
	///
	/// `TreeSelection.surviving` answers it: the nearest row above that is not
	/// going. In an outline view "the sibling above, or the parent when there
	/// is no sibling above" is the same movement, which is why one walk up the
	/// visible rows gives both.
	func rememberWhereTheSelectionGoes(in outline: NSOutlineView, staged: Bool) {
		let doomed = Set(outline.selectedRowIndexes)
		let at: (Int) -> String? = { (outline.item(atRow: $0) as? GitChangeNode)?.path }
		// **Above, then below.** Above is the right answer almost always — it
		// is the sibling or the parent, and both survive a stage. It is not the
		// answer when the file was the only one in its folder, because then the
		// folder empties and goes too, and there is nothing above to land on.
		setFallback([
			TreeSelection.surviving(above: doomed, path: at),
			TreeSelection.surviving(below: doomed, rowCount: outline.numberOfRows, path: at),
		].compactMap { $0 }, staged: staged)
	}

	private func setFallback(_ paths: [String], staged: Bool) {
		if staged { stagedSide.fallback = paths } else { unstagedSide.fallback = paths }
	}

	/// The side an outline view belongs to.
	func side(for outline: NSOutlineView) -> Side {
		outline === stagedTable ? stagedSide : unstagedSide
	}

	/// Notes that an untracked directory is open, so a rebuild puts it back.
	func remember(opened path: String, staged: Bool) {
		if staged { stagedSide.opened.insert(path) } else { unstagedSide.opened.insert(path) }
	}

	/// Asks git what one untracked directory holds, and puts the answer under
	/// the row.
	///
	/// `-uall` scoped to one path: it costs what that directory holds rather
	/// than what the work tree holds, which is the difference between 0.11 s and
	/// the seven seconds `GitWorkingCopy.status` measured and refused.
	/// The directories being asked about right now. One ask at a time per
	/// directory: a refresh rebuilds the tree more than once — the optimistic
	/// pass, then the confirming one — and each rebuild sent its own
	/// `git status -uall` per opened directory. The cached listing is already
	/// back on the row by the time this runs; this is only the re-check, and
	/// one in flight answers them all.
	func fill(_ node: GitChangeNode, in outline: ChangesOutlineView, staged: Bool) {
		let path = node.path
		let key = (staged ? "staged:" : "unstaged:") + path
		guard !fillsInFlight.contains(key) else { return }
		fillsInFlight.insert(key)
		Task { @MainActor in
			defer { self.fillsInFlight.remove(key) }
			// The same question as the diff: an untracked directory inside a
			// submodule is listed by that submodule, and asking the
			// superproject for it lists nothing.
			let estate = self.submodules.estate
			let files = await GitWorkingCopy.untrackedFiles(
				inDirectory: estate.relativePath(of: path),
				in: estate.repositoryRoot(containing: path)
			).map { inside -> String in
				guard let submodule = estate.submodule(containing: path) else { return inside }
				return "\(submodule.path)/\(inside)"
			}
			let rows = GitChangeTree.contents(
				ofUntrackedDirectory: path, files: files, staged: staged
			)
			// The tree may have been rebuilt while this was out, in which case
			// the row it was asked about is not the row on screen any more. The
			// answer is kept against the path either way, and the current row —
			// if there still is one — is the one filled.
			if staged {
				stagedSide.untrackedContents[path] = rows
			} else {
				unstagedSide.untrackedContents[path] = rows
			}
			guard let current = self.side(for: outline).byPath[path] else { return }
			// **Nothing to do when the answer has not changed**, which is the
			// usual case: `refill` sends this out for every open untracked
			// directory on every filesystem event, and the directory is
			// almost always exactly as it was. Reloading anyway is where the
			// flicker while staging came from — two rebuilds and then a third
			// from here, all drawing the same rows.
			let unchanged = current.isFilled
				&& current.children.map(\.path) == rows.map(\.path)
			guard !unchanged else { return }
			current.fill(with: rows)
			// **The selection is kept across this**, and two reports are the
			// one fault here. `reloadData()` clears an outline view's
			// selection; this call is asynchronous, so it lands *after* the
			// rebuild has carefully put the selection back. Expanding an
			// untracked folder with → left it open with nothing selected, and
			// staging anything in a repository with an untracked folder open
			// did the same — the rebuild restored, and this wiped it a moment
			// later. One keeper closes both.
			TreeSelectionKeeper.keepingSelection(
				in: outline,
				path: { (outline.item(atRow: $0) as? GitChangeNode)?.path },
				row: { path in
					guard let node = self.side(for: outline).byPath[path] else { return -1 }
					return outline.row(forItem: node)
				},
				during: {
					outline.reloadData()
					outline.expandItem(current)
				}
			)
		}
	}

	/// Puts back what open untracked directories held, before the view asks.
	///
	/// The tree is rebuilt from scratch on every filesystem event, so every row
	/// under an open directory is a new object with nothing in it. Filling from
	/// what is already known keeps the row open without a git call; the call
	/// goes out afterwards, because the directory may have gained a file since.
	private func refill(_ side: Side, in outline: ChangesOutlineView, staged: Bool) {
		for path in side.opened {
			guard let node = side.byPath[path] else { continue }
			if let known = side.untrackedContents[path] { node.fill(with: known) }
			fill(node, in: outline, staged: staged)
		}
	}


	func updateCommitButton() {
		let count = status.staged.count
		let hasSubject = !subjectField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty

		// There has to *be* a last commit to amend. In a repository that has
		// been `git init`ed and not committed to yet the box was live, and
		// ticking it and pressing the button put `fatal: You have nothing to
		// amend` on screen — git's answer to a question the page should not
		// have asked.
		let canAmend = pushState?.hasCommits ?? true
		if !canAmend, amendCheckbox.state == .on { amendCheckbox.state = .off }
		amendCheckbox.isEnabled = canAmend
		amendCheckbox.toolTip = canAmend ? nil : "There is no commit to amend yet"

		// The same fact gates the history: a repository with no commits has no
		// messages to offer.
		historyButton?.isHidden = !canAmend

		// Re-checked on every refresh, so installing `claude` enables the draft
		// without a restart. Only while idle: drafting and offering own the
		// button's word, colour and availability, and this used to fight them
		// by reading the label to find out which state it was in.
		if draftState == .idle { applyDraftState() }

		// Amend can commit nothing new — rewording the last commit is a normal
		// thing to want — so it is the one case where an empty index is allowed.
		let isAmending = amendCheckbox.state == .on
		commitButton.isEnabled = hasSubject && (count > 0 || isAmending)
		commitButton.setLabel(count > 0
			? "Commit \(count) File\(count == 1 ? "" : "s")"
			: (isAmending ? "Amend" : "Commit"))

		// The count as a tag beside the word, and a spinner in its place
		// while the push is out — see `DrawnButton.isWorking`.
		pushButton.setLabel(
			isPushing ? "Pushing" : pushState?.buttonWord ?? "Push",
			count: isPushing ? nil : pushState?.buttonCount
		)
		pushButton.isWorking = isPushing
		pushButton.isEnabled = !isBusy && pushState?.canPush == true
		pushButton.toolTip = pushTooltip

		// The accent goes to whichever action the page is actually for: with
		// nothing staged there is nothing to commit, and what is left to do is
		// send what is already committed. Return follows the accent, since the
		// default button is what Return means.
		let primary = CommitPageAction.primary(
			staged: count, isAmending: isAmending, canPush: pushButton.isEnabled
		)
		commitButton.keyEquivalent = primary == .commit ? "\r" : ""
		pushButton.keyEquivalent = primary == .push ? "\r" : ""
		// **Neither is filled.** The accent used to follow `primary`, but drawn
		// it is the caret colour — a white block on the dark page — and it
		// landed on Push, the one action not about the message being written.
		// Return still follows `primary`; the words and the enabled state say
		// the rest.
		commitButton.prominence = .normal
		pushButton.prominence = .normal
	}

	/// Nil only where there is no branch at all — a detached HEAD, or a pane
	/// still waiting for its first read. Every other reason the button is the
	/// way it is comes from the state itself, so that it can be checked without
	/// a window.
	private var pushTooltip: String {
		pushState?.explanation ?? "Push this branch"
	}

	/// Re-reads where the branch stands, and says so on the button.
	private func refreshPushState() {
		Task { @MainActor in
			pushState = await GitPush.state(in: root)
			updateCommitButton()
		}
	}

	@objc func push() {
		guard let state = pushState, state.canPush else { return }
		let setsUpstream = state.upstream == nil

		isBusy = true
		isPushing = true
		updateCommitButton()
		Task { @MainActor in
			let result = await GitPush.push(in: root, setUpstream: setsUpstream)
			isPushing = false
			endBusy()
			updateCommitButton()

			if result.exitCode == 0 {
				// git reports a push on stderr, which is where the branch and
				// the range it sent are named.
				let summary = result.stderr.isEmpty ? result.stdout : result.stderr
				Toast.post(
					"Pushed \(state.branch)",
					detail: summary.trimmingCharacters(in: .whitespacesAndNewlines),
					kind: .information
				)
			} else {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}

			refreshPushState()
			// The history and the branch list both show what has been pushed.
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			onWorkingCopyChanged?()
		}
	}
}

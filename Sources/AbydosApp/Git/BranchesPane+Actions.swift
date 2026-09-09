import AppKit
import AbydosKit

/// What can be done to a branch, and what each verb asks before it does it.
extension BranchesPane {
	// MARK: - Actions

	/// Sends a branch to its remote, publishing it if it has never been there.
	///
	/// Any branch, not only the one checked out: having to check a branch out
	/// to push it is a detour through the working copy for something that does
	/// not touch it.
	@objc func pushBranch() {
		guard let branch = selectedBranch, case .local = branch.kind else { return }
		// **Nowhere to push is a thing to fix, not a thing to fail at.** A
		// repository made with `git init` has no remote, so publishing was
		// `git push origin` answering `'origin' does not appear to be a git
		// repository` — git's words, about a state the app could see coming and
		// could do something about. It asks for the remote instead, and the
		// push is what somebody does next rather than what this pretends to do
		// for them: a URL typed into a box is not consent to send commits.
		guard remoteURL != nil else { setRemote(); return }
		send(
			branch.name,
			setUpstream: branch.upstream == nil,
			// HEAD for the current branch: pushing it by name would work
			// too, but naming HEAD is what git does and what the log says.
			naming: branch.isCurrent ? nil : branch.name
		)
	}

	/// Sends the branch the work tree is on, whatever the tree has selected.
	///
	/// The repository row's own verb. It is a different question from
	/// `pushBranch`, and telling them apart is the whole of the fix: that one
	/// acts on a row somebody picked, this one on the branch this row is
	/// describing.
	func pushCurrentBranch() {
		guard remoteURL != nil else { setRemote(); return }
		guard let state = trafficState, state.canPush else { return }
		send(
			currentBranchName ?? state.branch,
			setUpstream: state.upstream == nil,
			// Nil is HEAD, which is the only spelling that cannot be out of
			// step with what the work tree is actually on.
			naming: nil
		)
	}

	/// One push, one report, so the two callers cannot drift about what they
	/// say when it works or when it does not.
	private func send(_ name: String, setUpstream: Bool, naming branch: String?) {
		pushingBranch = name
		// A bare `reloadData()` drops the selection: pressing push on a branch
		// left nothing selected, so ⌘⏎ a moment later had no row to act on.
		reloadKeepingSelection { tableView.reloadData() }

		Task { @MainActor in
			defer {
				pushingBranch = nil
				tableView.reloadData()
			}
			let result = await GitPush.push(
				in: root, setUpstream: setUpstream, branch: branch
			)
			// git reports a push on stderr, which is where the branch and the
			// range it sent are named.
			let output = (result.stderr.isEmpty ? result.stdout : result.stderr)
				.trimmingCharacters(in: .whitespacesAndNewlines)

			if result.exitCode == 0 {
				Toast.post("Pushed \(name)", detail: output, kind: .information)
			} else {
				Toast.post("Could not push \(name)", detail: output, kind: .error)
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
	@objc func forcePushBranch() {
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
	@objc func openCommitPage() { onOpenCommitPage?() }

	/// The menu's way to the commit view, saying what the row's verb says.
	var commitEntryTitle: String {
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
	func fireSelectedRowAction() {
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
	@objc func newTagOnBranch() {
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
	@objc func showLogForBranch() {
		guard let branch = selectedBranch else { return }
		onShowLog?(branch.checkoutName)
	}

	/// What the pull-request entry says, or nothing when there is none to make.
	///
	/// Nothing for a remote-tracking branch or a tag, which are not somewhere
	/// work happens; nothing without a forge to open it on; and nothing for the
	/// default branch, a pull request from `main` into `main` being a page that
	/// tells you there is nothing to compare.
	func pullRequestTitle(for branch: GitBranch) -> String? {
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
	@objc func openPullRequest() {
		guard let branch = selectedBranch, let forge else { return }
		guard !isOnForge(branch) else {
			PullRequestFlow.open(branch.name, on: forge, into: defaultBranch)
			return
		}
		pushingBranch = branch.name
		reloadKeepingSelection { tableView.reloadData() }
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
	func isOnForge(_ branch: GitBranch) -> Bool {
		guard case .local = branch.kind else { return true }
		return branches.contains { other in
			guard case .remote = other.kind else { return false }
			return other.name == branch.name
		}
	}

	@objc func openBranchOnForge() {
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

	/// Opens the real dialog, for a report of what is on it — **through the
	/// menu item's own action**, so a driven run is pressing what somebody
	/// presses. A step of its own that did the same thing a little differently
	/// is how a delete that did nothing at all went unnoticed: the report was of
	/// a dialog nobody could have opened.
	func askAboutDeletingForTesting() {
		deleteBranch()
	}

	/// What is on the sheet that is up, with the frames it was laid out at.
	///
	/// A screenshot cannot see it — `--screenshot` captures the window and a
	/// sheet is a window of its own — and the frame is the thing worth
	/// checking: `NSAlert` lays its accessory out from the frame it is given
	/// rather than the view's intrinsic size, so a checkbox at zero by zero is
	/// a control that is there and cannot be seen.
	/// Opens the stash dialog, the way the working copy's menu item does.
	func stashWorkingCopyForTesting() { stashWorkingCopy() }

	/// Fills the stash dialog in and presses Stash. `untracked: false` unticks
	/// the box first, which is the half a screenshot cannot show.
	@discardableResult
	func answerStashForTesting(_ name: String, untracked: Bool) -> String {
		guard let sheet = window?.attachedSheet else { return "no sheet" }
		var field: NSTextField?
		var box: NSButton?
		func walk(_ view: NSView) {
			if let button = view as? NSButton, button.allowsMixedState || button.title.hasPrefix("Include") {
				box = button
			}
			if let text = view as? NSTextField, text.isEditable, field == nil { field = text }
			view.subviews.forEach(walk)
		}
		sheet.contentView.map(walk)
		field?.stringValue = name
		if !untracked { box?.state = .off }
		let pressed = BranchDeletion.pressSheetButtonForTesting("Stash", in: window)
		return "field=\(field == nil ? "missing" : "found") "
			+ "box=\(box.map { $0.state == .on ? "on" : "off" } ?? "missing") "
			+ "press=\(pressed)"
	}

	/// Opens the remote dialog, the way the menu item does.
	func setRemoteForTesting() { setRemote() }

	/// Types into the remote field, so what the dialog makes of a paste can be
	/// read rather than photographed.
	func typeRemoteForTesting(_ text: String) {
		guard let sheet = window?.attachedSheet else { return }
		func walk(_ view: NSView) -> NSTextField? {
			if let field = view as? NSTextField, field.isEditable { return field }
			for child in view.subviews { if let found = walk(child) { return found } }
			return nil
		}
		guard let field = sheet.contentView.flatMap(walk) else { return }
		field.stringValue = text
		remoteFieldChanged?()
	}

	/// Presses the selected branch's publish/push, the way the menu item does.
	func pushSelectedForTesting() { pushBranch() }

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
				// The width with the words, because the fault this dialog was
				// changed for was a *rendering* one — names wrapped mid-name in
				// a field too narrow for them — and a report of the strings
				// alone cannot catch the accessory being clipped.
				lines.append("  “\(text.stringValue.replacingOccurrences(of: "\n", with: " / "))”"
					+ " [\(Int(text.frame.width))pt"
					+ "\(text.lineBreakMode == .byWordWrapping ? " wraps" : "")]")
			}
			view.subviews.forEach(walk)
		}
		sheet.contentView.map(walk)
		return "SHEET:\n" + lines.joined(separator: "\n")
	}

	/// Does the delete the dialog would do, with the checkbox as given — the
	/// dialog skipped rather than answered.
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
		// **And whether it can be chosen**, as the per-row report already says:
		// an item that is shown and disabled over a selection it cannot act on
		// is a different answer from one that is not there, and a report that
		// could not tell them apart made a mixed selection look like an offer.
		return menu.items.map { item in
			guard !item.isSeparatorItem else { return "—" }
			return item.title + (item.isEnabled ? "" : " (off)")
		}
	}

	/// What the operation banner says and offers.
	func operationBannerForTesting() -> String { conflictBanner.reportForTesting }

	/// Opens the remote-delete question for the branches selected, the way the
	/// menu item does.
	func deleteRemoteForTesting() { deleteRemoteBranch() }

	/// Whether the pane thinks this branch is finished — asked by ref, so
	/// `origin/x` and `x` are two questions and not one.
	func mergedMarkForTesting() -> String {
		branches.map { branch -> String in
			let where_: String
			switch branch.kind {
			case .local:            where_ = branch.name
			case .remote(let name): where_ = "\(name)/\(branch.name)"
			case .tag:              where_ = "tag:\(branch.name)"
			}
			return where_ + (isMerged(branch) ? " merged" : "")
		}.joined(separator: ", ")
	}

	/// What the repository row offers on a right-click, and when it last
	/// fetched — neither of which a shot of a closed menu can be asked about.
	func remoteMenuForTesting() -> String {
		remoteMenu().items.map {
			$0.isSeparatorItem ? "—" : ($0.isEnabled ? $0.title : "\($0.title)(off)")
		}.joined(separator: " | ")
	}

	/// Presses the glyph beside the traffic verb, the way a click does.
	func pressFetchForTesting() { fetchPressed() }

	/// What one of the banner's menus holds. Empty argument means the `⋯` one.
	func bannerMenuForTesting(_ which: String) -> String {
		conflictBanner.menuForTesting(which)
	}

	/// Resolves one conflicted file the way its row's menu does.
	func resolveConflictForTesting(_ path: String, how: String) -> String {
		conflictBanner.resolveForTesting(path, how)
	}

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
				let merged = isMerged(branch)
				var marks: [String] = []
				if branch.isUnpublished {
					// Against the default branch, and said so: the same arrow
					// means a different thing on this row.
					let ahead = branch.aheadOfDefault ?? 0
					if ahead > 0 { marks.append("↑\(ahead) of the default") }
				} else if branch.ahead > 0 || branch.behind > 0 {
					marks.append("↑\(branch.ahead) ↓\(branch.behind)")
				}
				// The wheel, so a driven run can see the row is waiting on
				// something without a screenshot of it turning — and asked of
				// the *view*, not of the state behind it. A mark taken from the
				// state would have said "spinner" for all the time the real one
				// sat below a `return` and never appeared.
				if let view = tableView.view(atColumn: 0, row: index, makeIfNecessary: false),
					view.subviews.contains(where: { $0 is NSProgressIndicator }) {
					marks.append("spinner")
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
			case let .submodule(row):
				return indent + mark + "\u{25A0} \(row.path) · \(SubmoduleRowView.said(row))"
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

	/// Clicks and arrows on the tree, and what was selected after each, for
	/// the claim that one tree behaviour holds here as it does in the other
	/// three: a click gives the tree the keyboard, an arrow then moves the
	/// selection, and ← and → over a section fold and open it.
	///
	/// Steps joined with `+`: `click<row>`, `down`, `up`, `left`, `right`,
	/// `who`, `selected`. The selection is reported by key, which is what a
	/// row is remembered by across a rebuild.
	func keysForTesting(_ steps: String) -> String {
		var said: [String] = []
		func selection() -> String {
			let keys = tableView.selectedRowIndexes.compactMap {
				(tableView.item(atRow: $0) as? GitNode)?.key
			}
			return keys.isEmpty ? "nothing" : keys.joined(separator: "+")
		}
		for step in steps.split(separator: "+").map(String.init) {
			if step.hasPrefix("click") {
				let row = Int(step.dropFirst("click".count)) ?? 0
				said.append(TreeKeys.click(row: row, in: tableView)
					+ " keyboard=\(TreeKeys.keyboardHolder(in: window)) \(selection())")
			} else if let arrow = TreeKeys.arrow(step) {
				TreeKeys.press(arrow.code, arrow.scalar, in: window)
				said.append("\(step) \(selection())")
			} else if step == "who" {
				said.append("keyboard=\(TreeKeys.keyboardHolder(in: window))")
			} else if step == "selected" {
				said.append("selected=\(selection())")
			} else {
				said.append("unknown step \(step)")
			}
		}
		return said.joined(separator: " | ")
	}

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
			.map { item in
				guard !item.isSeparatorItem else { return "—" }
				// The tick is half of what a checkable item says — a sort
				// order the report cannot see is one no test can claim.
				let tick = item.state == .on ? "✓ " : ""
				return tick + item.title + (item.isEnabled ? "" : " (off)")
			}
			.joined(separator: " · ")
	}

	/// Fires the menu item with this title on the selected row, the way a
	/// person choosing it would, so a driven run can change a sort order and
	/// read the rows again.
	func chooseMenuItemForTesting(row: Int, titled title: String) -> String {
		guard row >= 0, row < tableView.numberOfRows else { return "no such row" }
		tableView.selectRowIndexes([row], byExtendingSelection: false)
		let menu = NSMenu()
		menu.delegate = self
		menuNeedsUpdate(menu)
		guard let item = menu.items.first(where: { $0.title == title }) else {
			return "no item titled \(title)"
		}
		guard let action = item.action else { return "\(title) has no action" }
		NSApp.sendAction(action, to: item.target, from: item)
		return "chose \(title)"
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
	@objc func recreateTag() {
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
			// **The subject in quotes, not run on.** `describe` answers
			// `fd19672 Say what it is now` — a hash and a commit subject — and
			// dropped straight into a sentence it read as one clause: *It is at
			// fd19672 Say what it is now, not what it started as.* A commit
			// message is somebody else's words and has to look like it.
			alert.informativeText = now.map { said in
				let parts = said.split(separator: " ", maxSplits: 1).map(String.init)
				guard parts.count == 2 else { return "It is at \(said)." }
				return "It is at \(parts[0]) — “\(parts[1])”."
			} ?? "Pick where it should point."
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
			// **Wide enough for the names in it, and laid out by frame.** The
			// accessory was a stack of 280-point views inside an alert whose
			// content is 272 — so the combo box overhung the dialog and the
			// one part of it that fell outside was the chevron on its trailing
			// edge. Reported as "the reference selection is cut off, and is
			// only a text box as far I see", which is exactly what a combo box
			// with its chevron clipped away is.
			//
			// `NSAlert` lays an accessory out from the frame it is given rather
			// than from any intrinsic or fitting size — which the delete
			// dialog's own accessory records — and a stack view resizing its
			// arranged subviews under that is a second opinion about the same
			// width. Plain views, one width, set once.
			let width: CGFloat = 380
			let caption = NSTextField(
				labelWithString: "Point it at a tag, a branch, or a commit"
			)
			caption.font = Theme.current.uiFont(11)
			caption.textColor = .secondaryLabelColor
			caption.lineBreakMode = .byTruncatingTail
			caption.frame = NSRect(x: 0, y: 0, width: width, height: 15)

			let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: width, height: 25))
			field.addItems(withObjectValues: self.tagSources(excluding: tag.name))
			field.completes = true
			field.numberOfVisibleItems = 12
			field.stringValue = suggestion
			field.placeholderString = "HEAD"
			field.toolTip = "Anything git can resolve — a tag, a branch, or a commit hash"

			// What the chosen source resolves to, under the field, before the
			// button is pressed rather than after. `describe` takes any rev,
			// which is why the tag's own reader can answer for a branch.
			let resolved = NSTextField(labelWithString: " ")
			resolved.font = Theme.current.uiFont(11)
			resolved.textColor = Theme.current.gitAdded
			resolved.lineBreakMode = .byTruncatingTail
			resolved.cell?.usesSingleLineMode = true
			resolved.frame = NSRect(x: 0, y: 0, width: width, height: 16)

			let follow = TagSourceWatcher(field: field, label: resolved, root: root)
			self.tagSourceWatcher = follow
			follow.refresh()

			// The point of moving a tag is that something else reads it, and
			// that something reads it from the remote.
			let push = NSButton(checkboxWithTitle: "Force-push to origin", target: nil, action: nil)
			push.state = .on
			push.frame = NSRect(x: 0, y: 0, width: width, height: 18)

			alert.accessoryView = Self.stacked(
				[caption, field, resolved, push], gaps: [4, 6, 10], width: width
			)

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

	/// Stacks views for an `NSAlert` accessory, top down, at one width.
	///
	/// **Frames, not a stack view.** `NSAlert` lays its accessory out from the
	/// frame it is given rather than from any intrinsic or fitting size, so a
	/// view that decides its own size under that is a second opinion about the
	/// same number — and the one it wins with is the one the dialog then clips.
	/// `BranchDeletion.accessory` does the same thing for the same reason.
	///
	/// - Parameter gaps: the space under each view but the last, so a caption
	///   can sit close to the field it introduces while the checkbox under them
	///   both stands apart.
	private static func stacked(
		_ views: [NSView], gaps: [CGFloat], width: CGFloat
	) -> NSView {
		let height = views.map(\.frame.height).reduce(0, +) + gaps.reduce(0, +)
		let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
		// Top down: an `NSView` here is not flipped, so the first view named is
		// the one that should end up highest.
		var y = height
		for (index, view) in views.enumerated() {
			y -= view.frame.height
			view.frame = NSRect(x: 0, y: y, width: width, height: view.frame.height)
			container.addSubview(view)
			if index < gaps.count { y -= gaps[index] }
		}
		return container
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
	/// Opens the recreate question for the selected tag, the way the menu does.
	func recreateTagForTesting() { recreateTag() }

	func tagSourcesForTesting(excluding name: String) -> String {
		tagSources(excluding: name).joined(separator: "\n")
	}
}

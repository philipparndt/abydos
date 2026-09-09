import AppKit
import AbydosKit

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
		TreeRowView()
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
			// The section shows what needs something; all of them are on the
			// overview, which is where a refactoring across forty services is read.
			if title.hasPrefix("Submodules") {
				view.action = RowAction(
					symbol: "square.stack.3d.up",
					help: "Open the submodules overview",
					isAlwaysShown: false
				)
				view.onAction = { [weak self] in self?.onOpenEstate?() }
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
				busy: busyNote(for: branch),
				isMerged: isMerged(branch),
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
		case let .submodule(row):
			return SubmoduleRowView(row: row)
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
		// A section that starts shut needs the opposite record kept, or it
		// would close again on the next filesystem event — which is every
		// keystroke in a file, and the shape of the tree is not a thing to
		// have to keep re-establishing.
		openedKeys.insert(node.key)

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
		openedKeys.remove(node.key)
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard !isRestoring, case let .change(change, _, _) = selectedNode?.row,
		      let picked = change.change else { return }
		onSelectChange?(picked)
	}
}

extension BranchesPane: NSTextFieldDelegate {
	/// Redraws what the remote dialog says it read, as it is typed.
	///
	/// The field's `action` fires on Return and on losing focus, which is after
	/// the decision rather than during it — and a paste is exactly the case
	/// where somebody wants to see what arrived before they press anything.
	func controlTextDidChange(_ notification: Notification) {
		remoteFieldChanged?()
	}
}

extension BranchesPane: NSMenuDelegate {
	/// A sort order picked on a section header. The header is read back from
	/// the selection rather than carried in the item: the menu is open over
	/// it, so it cannot have moved.
	@objc private func chooseSortOrder(_ sender: NSMenuItem) {
		guard let raw = sender.representedObject as? String,
		      let order = RefsSortOrder(rawValue: raw),
		      let header = selectedRefsHeader else { return }
		switch header {
		case "Local": Settings.shared.refsSortLocal = order
		case "Tags":  Settings.shared.refsSortTags = order
		default:      Settings.shared.refsSortRemotes = order
		}
		rebuildRows()
	}

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
			// **Put aside rather than committed.** The other thing anybody does
			// with a working copy they are not ready to commit, and until now it
			// was reachable only from the commit page — a trip to a tab to press
			// something that does not commit anything.
			menu.addItem(item(
				"Stash Changes\u{2026}",
				#selector(stashWorkingCopy),
				enabled: !working.isEmpty
			))
			return
		}

		let stashes = selectedStashes.isEmpty ? [clickedStash].compactMap { $0 } : selectedStashes
		if !stashes.isEmpty {
			// **First, because looking comes before deciding.** The tree opens
			// a stash to a list of file names and stops there, so the only way
			// to find out what a week-old one held was to apply it over a clean
			// working copy — the one move somebody with work in progress cannot
			// make. It is the same word the working copy's row uses, for the
			// same page shape.
			menu.addItem(item(
				"Review\u{2026}", #selector(reviewStash), enabled: stashes.count == 1
			))
			menu.addItem(.separator())
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

		// A section header names a set of refs, and the set's order is the
		// set's own option. Two checkable items rather than a submenu: there
		// are two answers, and hiding them a level down would cost more clicks
		// than the list saves.
		if let header = selectedRefsHeader {
			for order in RefsSortOrder.allCases {
				let choice = item(
					order == .newestFirst ? "Newest First" : "By Name",
					#selector(chooseSortOrder(_:))
				)
				choice.representedObject = order.rawValue
				choice.state = sortOrder(forSection: header) == order ? .on : .off
				menu.addItem(choice)
			}
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

		// **Bringing this branch up to date**, in whichever of the two ways
		// applies to it. `main ↓4` while the work happens on a feature branch
		// was three operations — checkout, pull, checkout back — and a working
		// copy touched twice for a ref that could simply be moved; standing on
		// `main ↓3` was no operation at all, because the verb for that case was
		// on the repository row and never on the row that says the number.
		// `BranchCatchUp` decides which, and is where the reasoning is written.
		switch BranchCatchUp.offer(for: branch) {
		case .fastForward(let upstream):
			menu.addItem(.separator())
			menu.addItem(item("Fast-forward to \(upstream)", #selector(fastForwardBranch)))
		case .pull:
			menu.addItem(.separator())
			// The ellipsis is the pull sheet, which is where the remote, the
			// branch and rebase-or-merge are chosen — the same item the
			// repository row above offers, on the row it is about.
			menu.addItem(item("Pull\u{2026}", #selector(pullWithDialog)))
		case nil:
			break
		}

		menu.addItem(.separator())
		menu.addItem(item(
			"Merge into Current",
			#selector(mergeIntoCurrent),
			enabled: !branch.isCurrent
		))
		// **The other way of catching up, and the menu had only one.** Merge
		// makes a commit; rebase replays what is here on top of there. Named
		// for the row it hangs off, which is the destination: right-clicking
		// `main` and asking to rebase means putting this branch on top of main.
		menu.addItem(item(
			"Rebase on \(branch.checkoutName)\u{2026}",
			#selector(rebaseOntoBranch),
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
		// **Named for where it deletes from.** A remote branch's row sits under
		// a section headed by its remote and says only the branch's own name,
		// so a plain `Delete…` there is the same word for two operations — one
		// that removes a ref from this disk and one that removes it from
		// everybody's. The remote is in the title so the press cannot be a
		// surprise.
		if case .remote(let remote) = branch.kind {
			let deleting = deletableRemoteBranches.count
			menu.addItem(item(
				deleting > 1
					? "Delete \(deleting) Branches from \(remote)…"
					: "Delete from \(remote)…",
				#selector(deleteRemoteBranch),
				enabled: deleting > 0
			))
		}
		if case .tag = branch.kind {
			menu.addItem(.separator())
			menu.addItem(item("Recreate…", #selector(recreateTag)))
			// How many, as Copy Name and the branch deletes say it: a menu
			// opened over three selected tags must not read as being about the
			// one row under the pointer.
			let deleting = deletableTags.count
			menu.addItem(item(
				deleting > 1 ? "Delete \(deleting) Tags…" : "Delete Tag…",
				#selector(deleteTag),
				enabled: deleting > 0
			))
		}
	}
}

/// Table that reports Return and double-click, for checkout.
/// Says what the chosen source resolves to, while it is being chosen.
///
/// Its own object rather than the pane, because the pane is already the
/// delegate of a search field and a table: one `controlTextDidChange` cannot

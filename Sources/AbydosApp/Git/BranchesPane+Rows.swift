import AppKit
import AbydosKit

/// Building the rows the tree shows: the sections, the folders a slash in a
/// branch name makes, the working copy and what is changed in it, and putting
/// the folds and the selection back afterwards.
extension BranchesPane {
	func rebuildRows() {
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
			sectionsThatStartShut.insert("section:\(remote)")
		}

		appendSection("Tags", matching.filter { $0.kind == .tag })
		sectionsThatStartShut.insert("section:Tags")

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

		// The submodules, after the refs and before the places. They are things
		// this repository *has*, which is why `One tree holds everything the
		// repository has` puts them here rather than in a tool of their own —
		// and a section of two hundred rows would break that same requirement's
		// other half, that every row says enough to be understood. So: only the
		// ones with something to report, and a count of the rest.
		appendSubmodules(matching: needle)

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

		// **The flag covers the selection too, and that is the whole of it.**
		// Putting the selection back is a selection change as far as AppKit is
		// concerned, and this pane answers one by opening the diff of what was
		// picked. Cleared a line too early, every refresh — and a refresh is
		// every filesystem event — opened an editor tab, which changed the
		// window, which refreshed the pane.
		isRestoring = true
		reloadKeepingSelection {
			tableView.reloadData()
			restoreExpansion(roots)
		}
		isRestoring = false

		if hadFocus { window?.makeFirstResponder(tableView) }
	}

	/// Reloads the tree with its selection held across the reload, by key.
	///
	/// **Every selected row, not the first.** This pane once kept one key, so
	/// a rebuild — which happens on every filesystem event — quietly cut a
	/// selection of five branches down to one, and nobody noticed until a menu
	/// that said "Delete 5 Branches…" said "Delete…" a moment later. Then it
	/// kept every key and put back whichever it found, and a branch that had
	/// just been deleted or filtered away left nothing selected and nothing
	/// said. `TreeSelectionKeeper` is the same behaviour the changes tree and
	/// the project tree have, with the half this pane lacked: a key that has
	/// gone lands the selection on the nearest surviving row and says so.
	///
	/// A key rather than a path, because a ref is not a file: `branch:main`,
	/// `section:Stashes`, `stashfile:<commit>:<path>` — whatever names the row
	/// so that it can be found again after every row has moved.
	func reloadKeepingSelection(_ reload: () -> Void) {
		TreeSelectionKeeper.keepingSelection(
			in: tableView,
			path: { [weak self] row in (self?.tableView.item(atRow: row) as? GitNode)?.key },
			row: { [weak self] key in
				guard let self, let node = self.node(forKey: key) else { return -1 }
				return self.tableView.row(forItem: node)
			},
			during: reload
		)
	}

	/// Opens everything nobody has shut.
	///
	/// The positive way round, so a tree arrives open — with one exception the
	/// working copy makes for itself: forty changed files unrolled under the
	/// first row pushes the branches off the bottom of a column, and the count
	/// on the row answers the usual question without spending forty rows on it.
	private func restoreExpansion(_ nodes: [GitNode]) {
		for node in nodes where !node.children.isEmpty {
			let shutByDefault = sectionsThatStartShut.contains(node.key)
				&& !openedKeys.contains(node.key)
			if collapsedKeys.contains(node.key) || shutByDefault {
				// **The children are restored first, then the section shut over
				// them.** An outline keeps its own record per item, and a
				// folder inside a section nobody has opened yet has never been
				// walked — so opening `origin` showed every folder under it
				// shut, which is not what a folder nobody has touched should
				// look like. Expanding hidden rows costs nothing and they are
				// already open when the section opens over them.
				restoreExpansion(node.children)
				tableView.collapseItem(node)
			} else {
				tableView.expandItem(node)
				restoreExpansion(node.children)
			}
		}
	}

	/// What somebody folded and unfolded here, for the project's session.
	///
	/// **Both sets, unmerged.** `collapsedKeys` is the negative way round —
	/// open unless shut — and `openedKeys` the positive one, for the two
	/// sections that are somebody else's account of things. One list of
	/// "expanded keys" would have to carry which rule each key was under.
	var folds: ProjectSession.TreeFolds {
		get {
			ProjectSession.TreeFolds(
				shut: Array(collapsedKeys), opened: Array(openedKeys)
			)
		}
		set {
			// Replacing rather than merging: what is written down is the whole
			// of what somebody arranged, and a key that has since stopped
			// naming a row simply finds nothing in `restoreExpansion`.
			collapsedKeys = Set(newValue.shut)
			openedKeys = Set(newValue.opened)
		}
	}

	/// What the tree looks like *now*, for the session.
	///
	/// **Asked of the rows and not of the two sets**, which was the first
	/// answer and is wrong: the sets say what somebody has decided, and the
	/// outline holds the rest. A section nobody has touched is shut because a
	/// freshly built row is not expanded, not because it is in `collapsedKeys`
	/// — so a capture from the sets came back with everything not explicitly
	/// shut *open*, and a round trip left the tree more unrolled than somebody
	/// left it. Driven, and that is how it was caught.
	///
	/// The two answers here are exactly the two `restoreExpansion` asks, so
	/// what is written down reproduces the screen rather than approximating it:
	/// a row the outline has collapsed is shut, and a row that starts shut and
	/// is open was opened.
	///
	/// A key that names no row is dropped by construction — this walks the
	/// rows. Nothing is written while the tree is empty, since "no rows" then
	/// means the repository has not been read rather than that a fold has gone.
	var foldsWorthKeeping: ProjectSession.TreeFolds {
		guard !roots.isEmpty else { return folds }
		var shut: [String] = []
		var opened: [String] = []

		func walk(_ nodes: [GitNode]) {
			for node in nodes where !node.children.isEmpty {
				if tableView.isItemExpanded(node) {
					if sectionsThatStartShut.contains(node.key) { opened.append(node.key) }
				} else {
					shut.append(node.key)
				}
				walk(node.children)
			}
		}
		walk(roots)
		return ProjectSession.TreeFolds(shut: shut.sorted(), opened: opened.sorted())
	}

	/// Finds a node again after a rebuild has replaced every object.
	func node(forKey key: String) -> GitNode? {
		var stack = roots
		while let node = stack.popLast() {
			if node.key == key { return node }
			stack.append(contentsOf: node.children)
		}
		return nil
	}

	/// The node under the pointer, or the selected one.
	var selectedNode: GitNode? {
		let clicked = tableView.clickedRow
		let row = clicked >= 0 ? clicked : tableView.selectedRow
		return tableView.item(atRow: row) as? GitNode
	}

	/// One side of the index, and the folders it changed.
	func add(
		side title: String, _ trees: [GitChangeNode], staged: Bool, to parent: GitNode
	) {
		guard !trees.isEmpty else { return }
		let count = staged ? working.staged.count : working.unstaged.count
		let side = GitNode(key: "side:\(title)", row: .side(title, staged: staged, count: count))
		parent.add(side)
		add(changes: trees, staged: staged, to: side)
	}

	func add(changes: [GitChangeNode], staged: Bool, to parent: GitNode) {
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

	/// The submodules worth a row, and how many are not.
	///
	/// **Two hundred submodules each holding branches, stashes and tags is not
	/// a tree anybody scrolls.** So the section shows what needs something —
	/// conflicted, changed, ahead, or pointing somewhere the superproject does
	/// not record — and says how many are clean rather than listing them. All
	/// of them are readable on the overview, which the header opens.
	/// Reads the submodules and gives back the estate's changes as one status.
	///
	/// **The estate's changes, not the superproject's.** With
	/// `--ignore-submodules=dirty` the superproject reports moved gitlinks and
	/// nothing about a submodule's dirty work tree — so a working-copy row
	/// built from it alone said `1` while three submodules were dirty. Driving
	/// an estate is what showed that; the flattened status is what the commit
	/// page already draws, and the two views must agree.
	///
	/// The branches are one cheap call a submodule, bounded, so this section
	/// and the overview say the same thing about the same repository. They
	/// differed: with no branch read, a submodule with commits to push fell
	/// through to `moved`, which is true and is not what the overview said.
	///
	/// A repository with no submodules pays two git calls that answer nothing —
	/// 0.01 s — and gets exactly the status it always got.
	func readEstate() async -> GitWorkingCopyStatus {
		let status = await submodules.refresh(.everything)
		let branches = await GitEstateBranches.branches(
			of: submodules.estate.submodules, in: root
		)
		estateRows = GitEstateOverview.rows(
			in: submodules.estate,
			status: submodules.status,
			branches: branches
		)
		return status
	}

	private func appendSubmodules(matching needle: String) {
		guard !estateRows.isEmpty else { return }

		let matching = needle.isEmpty
			? estateRows
			: estateRows.filter { $0.path.lowercased().contains(needle) }
		let worthARow = matching.filter(\.needsSomething)
		let quiet = matching.count - worthARow.count

		// A filter that matched nothing here is a section with nothing to say,
		// rather than a section saying "200 clean".
		guard !matching.isEmpty else { return }

		let title = worthARow.isEmpty
			? "Submodules · \(quiet) clean"
			: (quiet > 0 ? "Submodules · and \(quiet) clean" : "Submodules")
		let section = GitNode(key: "section:Submodules", row: .header(title))
		roots.append(section)

		for row in worthARow {
			let node = GitNode(key: "submodule:\(row.path)", row: .submodule(row))
			section.add(node)
			// **Its changed files, and not its branches.** Opening a submodule's
			// own refs is opening that repository, which is a different thing
			// from reading this one — and it is what would turn this section
			// into two hundred trees.
			guard let own = submodules.status.status(of: row.path) else { continue }
			for change in GitChangeTree.build(own.unstaged, against: own.staged) {
				node.add(GitNode(
					key: "submodulechange:\(row.path):\(change.path)",
					row: .change(change, staged: false, depth: 0)
				))
			}
		}
	}

	/// Which order a section shows its refs in. The sections collapse to three
	/// kinds on purpose — local, remotes, tags — because that is the choice the
	/// headers offer, and a per-remote memory would be keys for a question
	/// nobody asks per remote.
	func sortOrder(forSection title: String) -> RefsSortOrder {
		switch title {
		case "Local": return Settings.shared.refsSortLocal
		case "Tags":  return Settings.shared.refsSortTags
		default:      return Settings.shared.refsSortRemotes
		}
	}

	private func appendSection(_ title: String, _ entries: [GitBranch]) {
		guard !entries.isEmpty else { return }
		let section = GitNode(key: "section:\(title)", row: .header(title))
		roots.append(section)
		let order = sortOrder(forSection: title)

		// **Filtering flattens.** A tree you have to expand to reach a name you
		// have just typed is worse than no tree, so a filtered list is whole
		// names and no folders at all. A filter narrows what is shown, not how
		// it is ordered, so the section's own order applies here too.
		guard filterText.isEmpty else {
			for branch in entries.sorted(by: {
				if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
				return order.orderedBefore($0, $1)
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
		// **A slash is always a folder here.** Folding used to merge a folder
		// holding exactly one branch into it, so `renovate/configure` was one
		// row reading its whole path while `feature/a` and `feature/b` got a
		// `feature` folder — the tree's shape changed character with the count,
		// and a section with one prefixed branch in it looked like a section
		// that did not group at all. Reported against `origin/renovate/…`.
		//
		// The argument the fold was written on is in `PathTree`: a `hotfix/`
		// folder holding only `hotfix/0472` turns one row into two and says
		// nothing, there being no such thing as checking out a folder of
		// branches. That is true of the row and not of the tree, and it is the
		// tree somebody reads. `keeping: ["backup"]` goes with it: it existed
		// to stop this fold reaching the one folder that has a verb of its own,
		// and there is no fold left to stop.
		let main = defaultBranch
		let tree = PathTree.build(
			entries.map { (path: $0.name, payload: $0) },
			folding: false,
			promoting: { branch in
				if branch.isCurrent { return 0 }
				if let main, branch.name == main { return 1 }
				return nil
			},
			// Nil for the name order, which is the builder's own default: the
			// parameter exists for the departure, not for restating the rule.
			ordering: order == .name ? nil : order.orderedBefore
		)
		add(refs: tree, under: title, to: section)
	}

	func add(refs: [PathNode<GitBranch>], under section: String, to parent: GitNode) {
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
	var clickedRow: Row? { selectedNode?.row }

	/// The change under the pointer, for staging and for showing its diff.
	var clickedChange: (node: GitChangeNode, staged: Bool)? {
		guard case let .change(node, staged, _) = clickedRow else { return nil }
		return (node, staged)
	}

	@objc func stageClicked() {
		guard let picked = clickedChange else { return }
		run {
			picked.staged
				? await GitWorkingCopy.unstage(paths: [picked.node.path], in: self.root)
				: await GitWorkingCopy.stage(paths: [picked.node.path], in: self.root)
		}
	}

	/// The folder the pointer is on, or the selection when it is not on one.
	var selectedFolder: (key: String, display: String)? {
		guard case let .folder(key, display, _, _) = selectedNode?.row else { return nil }
		return (key, display)
	}

	/// The section header the pointer is on — `Local`, a remote's name,
	/// `Tags` — when it is one of the sections that hold refs. `Worktrees` and
	/// `Stashes` are headers too, and they are not this: their contents have
	/// no order to choose.
	var selectedRefsHeader: String? {
		guard case let .header(title) = selectedNode?.row else { return nil }
		if title == "Local" || title == "Tags" { return title }
		let isRemote = branches.contains {
			if case .remote(let remote) = $0.kind { return remote == title }
			return false
		}
		return isRemote ? title : nil
	}

	/// Opens a stash to what is in it, or shuts it again.
	///
	/// **Reading it is the point.** Three entries called "wip" are a guessing
	/// game, and `applyStash` restored blind — so what it holds and whether it
	/// would still go back are read here, once, and kept until the repository
	/// moves under them.
	func readInside(_ entry: GitStash.Entry) {
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
	var clickedStash: GitStash.Entry? {
		switch selectedNode?.row {
		case let .stash(entry):        return entry
		case let .stashFile(entry, _): return entry
		default:                       return nil
		}
	}


	@objc func reviewStash() {
		guard let entry = selectedStashes.first ?? clickedStash else { return }
		onReviewStash?(entry)
	}

	/// Opens the stash page from a driven run, the way the menu item does.
	func reviewStashForTesting(_ reference: String) -> String {
		guard let entry = stashes.first(where: { $0.reference == reference }) else {
			return "no stash called \(reference)"
		}
		onReviewStash?(entry)
		return "reviewing \(reference)"
	}

	@objc func branchFromStash() {
		guard let entry = selectedStashes.first ?? clickedStash else { return }
		branch(fromStash: entry)
	}

	func branch(fromStash entry: GitStash.Entry) {
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

	@objc func expandFolder() {
		guard let node = selectedNode else { return }
		// Everything beneath it too, which is what "all" has to mean or the
		// item is the disclosure triangle with extra steps.
		tableView.expandItem(node, expandChildren: true)
	}

	@objc func collapseFolder() {
		guard let node = selectedNode else { return }
		tableView.collapseItem(node, collapseChildren: true)
	}

	/// Deletes the backup refs past a chosen age. See `BackupSweep`.
	@objc func sweepBackups() {
		BackupSweep.run(in: root, over: window) { [weak self] in self?.refresh() }
	}

	@objc func copyFolderPrefix() {
		guard let folder = selectedFolder else { return }
		// The prefix as git knows it, without the section name in front of it.
		let prefix = folder.key.split(separator: ":", maxSplits: 1).last.map(String.init) ?? folder.key
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(prefix + "/", forType: .string)
	}

	var selectedBranch: GitBranch? {
		guard case let .branch(branch, _, _) = selectedNode?.row else { return nil }
		return branch
	}

	/// What the push item should say, or nil when there is nothing to send.
	///
	/// A branch nobody has pushed has no upstream and counts nothing, which is
	/// not the same as being level with one — and it is the case where the
	/// menu is most useful, since publishing is otherwise a trip to a terminal.
	func pushTitle(for branch: GitBranch) -> String? {
		guard branch.upstream != nil else { return "Publish Branch" }
		guard branch.ahead > 0 else { return nil }
		return "Push \(branch.ahead) Commit\(branch.ahead == 1 ? "" : "s")"
	}

	/// The stashes the menu applies to.
	///
	/// A right-click inside the selection means all of it — that is what makes
	/// dropping several at once possible — and a right-click anywhere else
	/// means the row under the pointer, as every list does.
	var selectedStashes: [GitStash.Entry] {
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
	var selectedBranches: [GitBranch] {
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

	var selectedWorktree: GitWorktree? {
		guard case let .worktree(worktree) = selectedNode?.row else { return nil }
		return worktree
	}
}

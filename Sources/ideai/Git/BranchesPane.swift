import AppKit
import IdeaiKit

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

	private let root: URL

	private var branches: [GitBranch] = []
	/// Where this repository lives on the web, when it lives anywhere: read
	/// from the remote, so GitHub and an Enterprise install are the same case.
	private var forge: GitForge.Repository?
	private var worktrees: [GitWorktree] = []
	private var stashes: [GitStash.Entry] = []
	private var rows: [Row] = []
	private var filterText = ""

	private var filterField: NSSearchField!
	private var tableView: BranchesTableView!

	private enum Row {
		case header(String)
		case branch(GitBranch)
		case worktree(GitWorktree)
		case stash(GitStash.Entry)

		var isSelectable: Bool {
			if case .header = self { return false }
			return true
		}
	}

	init(root: URL) {
		self.root = root
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		refresh()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(refresh),
			name: .ideaiRepositoryChanged,
			object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }
	deinit { NotificationCenter.default.removeObserver(self) }

	// MARK: - Layout

	private func build() {
		filterField = NSSearchField()
		filterField.placeholderString = "Filter branches"
		filterField.font = Theme.current.uiFont(12)
		filterField.focusRingType = .none
		filterField.delegate = self
		filterField.sendsWholeSearchString = false

		let newButton = NSButton(title: "New Branch…", target: self, action: #selector(newBranch))
		newButton.bezelStyle = .rounded
		newButton.controlSize = .small
		newButton.font = Theme.current.uiFont(11)

		tableView = BranchesTableView()
		tableView.headerView = nil
		tableView.backgroundColor = Theme.current.sidebarBackground
		tableView.selectionHighlightStyle = .regular
		// So that several stashes can be dropped in one go. Branches ignore it:
		// nothing here acts on more than one of those.
		tableView.allowsMultipleSelection = true
		tableView.rowSizeStyle = .custom
		tableView.intercellSpacing = .zero
		tableView.gridStyleMask = []
		tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branch")))
		tableView.delegate = self
		tableView.dataSource = self
		tableView.menu = makeMenu()
		tableView.onActivate = { [weak self] in self?.checkoutSelected() }

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.sidebarBackground
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle

		for view in [filterField, newButton, scrollView] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			filterField.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			filterField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			filterField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			newButton.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: inset / 2),
			newButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),

			scrollView.topAnchor.constraint(equalTo: newButton.bottomAnchor, constant: inset / 2),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	// MARK: - Data

	@objc func refresh() {
		Task { @MainActor in
			let fresh = await GitBranches.list(in: root)
			// Only the repository's own checkouts, and only when there is more
			// than one: a repository nobody has added a worktree to should not
			// carry a section explaining that it has one.
			let trees = await GitWorktrees.list(in: root)
			let put = await GitStash.list(in: root)
			forge = await GitForge.repository(in: root)
			guard fresh != branches || trees != worktrees || put != stashes else { return }
			branches = fresh
			worktrees = trees
			stashes = put
			rebuildRows()
		}
	}

	private func rebuildRows() {
		let needle = filterText.lowercased()
		let matching = needle.isEmpty
			? branches
			: branches.filter { $0.name.lowercased().contains(needle) }

		rows = []
		// Local first: it is what you switch between. Remotes and tags are
		// there to branch from, not to live on.
		appendSection("Local", matching.filter { $0.kind == .local })

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
			rows.append(.header("Worktrees"))
			rows += matchingTrees.map { Row.worktree($0) }
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
			rows.append(.header("Stashes"))
			rows += matchingStashes.map { Row.stash($0) }
		}

		tableView.reloadData()
	}

	private func appendSection(_ title: String, _ entries: [GitBranch]) {
		guard !entries.isEmpty else { return }
		rows.append(.header(title))
		// Current first, then alphabetically — the one you are on is the one
		// you look for.
		for branch in entries.sorted(by: {
			$0.isCurrent != $1.isCurrent ? $0.isCurrent : $0.name < $1.name
		}) {
			rows.append(.branch(branch))
		}
	}

	private var selectedBranch: GitBranch? {
		let clicked = tableView.clickedRow
		let row = clicked >= 0 ? clicked : tableView.selectedRow
		guard rows.indices.contains(row), case let .branch(branch) = rows[row] else { return nil }
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
			guard rows.indices.contains($0), case let .stash(entry) = rows[$0] else { return nil }
			return entry
		}
	}

	private var selectedWorktree: GitWorktree? {
		let clicked = tableView.clickedRow
		let row = clicked >= 0 ? clicked : tableView.selectedRow
		guard rows.indices.contains(row), case let .worktree(worktree) = rows[row] else { return nil }
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

		Toast.post(
			publishing ? "Publishing \(branch.name)…" : "Pushing \(branch.name)…",
			detail: publishing ? "Setting its upstream on origin." : nil,
			kind: .information
		)

		Task { @MainActor in
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
			NotificationCenter.default.post(name: .ideaiRepositoryChanged, object: root)
			refresh()
		}
	}

	/// Opens the branch's page in a browser.
	@objc private func openBranchOnForge() {
		guard let branch = selectedBranch, let forge else { return }
		guard let url = forge.url(forBranch: branch.name) else { return }
		NSWorkspace.shared.open(url)
	}

	/// Pops the context menu open on a row, as a right-click would.
	func showMenuForTesting(row: Int) {
		guard rows.indices.contains(row) else { return }
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

		Task { @MainActor in
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

			let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
			field.stringValue = suggestion
			field.placeholderString = "HEAD"

			// The point of moving a tag is that something else reads it, and
			// that something reads it from the remote.
			let push = NSButton(checkboxWithTitle: "Force-push to origin", target: nil, action: nil)
			push.state = .on
			push.frame = NSRect(x: 0, y: 0, width: 280, height: 20)

			let stack = NSStackView(views: [field, push])
			stack.orientation = .vertical
			stack.alignment = .leading
			stack.spacing = 8
			stack.frame = NSRect(x: 0, y: 0, width: 280, height: 56)
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
		// A stash is applied rather than checked out: it is not a place to be,
		// it is work waiting to come back.
		if !selectedStashes.isEmpty {
			applyStash()
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
		run { await GitBranches.checkout(branch, in: self.root) }
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

	@objc private func mergeIntoCurrent() {
		guard let branch = selectedBranch else { return }
		run { await GitBranches.merge(branch.checkoutName, in: self.root) }
	}

	@objc private func deleteBranch() {
		guard let branch = selectedBranch, case .local = branch.kind, !branch.isCurrent else { return }

		let alert = NSAlert()
		alert.messageText = "Delete branch “\(branch.name)”?"
		alert.informativeText = "Unmerged commits on it would be lost."
		alert.addButton(withTitle: "Delete")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			self.run { await GitBranches.delete(branch.name, force: false, in: self.root) }
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	@objc private func copyBranchName() {
		guard let branch = selectedBranch else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(branch.checkoutName, forType: .string)
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
		filterField.font = Theme.current.uiFont(12)
		tableView.reloadData()
	}
}

// MARK: - Table

extension BranchesPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		guard rows.indices.contains(row) else { return 0 }
		if case .header = rows[row] { return Theme.current.scaled(22) }
		return Theme.current.scaled(24)
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		rows.indices.contains(row) && rows[row].isSelectable
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard rows.indices.contains(row) else { return nil }
		switch rows[row] {
		case .header(let title): return BranchSectionView(title: title)
		case .branch(let branch): return BranchRowView(branch: branch)
		case .worktree(let worktree): return WorktreeRowView(worktree: worktree)
		case .stash(let entry): return StashRowView(entry: entry)
		}
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

		let stashes = selectedStashes
		if !stashes.isEmpty {
			menu.addItem(item(
				"Apply…", #selector(applyStash), enabled: stashes.count == 1
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

		guard let branch = selectedBranch else {
			menu.addItem(item("New Worktree…", #selector(addWorktree)))
			return
		}

		menu.addItem(item("Checkout", #selector(contextCheckout), enabled: !branch.isCurrent))
		menu.addItem(item("New Branch from Here…", #selector(newBranch)))

		// Sending a branch somewhere, and looking at it where it went.
		if case .local = branch.kind, let title = pushTitle(for: branch) {
			menu.addItem(.separator())
			menu.addItem(item(title, #selector(pushBranch)))
		}
		if let forge {
			menu.addItem(item("Open on \(forge.displayName)", #selector(openBranchOnForge)))
		}

		menu.addItem(.separator())
		menu.addItem(item(
			"Merge into Current",
			#selector(mergeIntoCurrent),
			enabled: !branch.isCurrent
		))
		menu.addItem(.separator())
		menu.addItem(item("Copy Name", #selector(copyBranchName)))
		menu.addItem(item("New Worktree from Here…", #selector(addWorktree)))

		if case .local = branch.kind {
			menu.addItem(item("Delete…", #selector(deleteBranch), enabled: !branch.isCurrent))
		}
		if case .tag = branch.kind {
			menu.addItem(.separator())
			menu.addItem(item("Recreate…", #selector(recreateTag)))
		}
	}
}

extension BranchesPane: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		filterText = filterField.stringValue.trimmingCharacters(in: .whitespaces)
		rebuildRows()
	}
}

/// Table that reports Return and double-click, for checkout.
private final class BranchesTableView: NSTableView {
	var onActivate: (() -> Void)?

	override func keyDown(with event: NSEvent) {
		if event.keyCode == 36 || event.keyCode == 76 {
			onActivate?()
			return
		}
		super.keyDown(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?() }
	}
}

private final class BranchSectionView: NSView {
	private let title: String
	override var isFlipped: Bool { true }

	init(title: String) {
		self.title = title
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let label = NSAttributedString(string: title.uppercased(), attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(10), weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		label.draw(at: NSPoint(
			x: Theme.current.scaled(10),
			y: bounds.midY - label.size().height / 2
		))
	}
}

/// How much of a row is inside the selection.
///
/// The pill AppKit draws is inset from the row it belongs to, so text laid out
/// to the row's own edge runs past the highlight and out of the sidebar. Every
/// row here stops here instead.
private enum RowMetrics {
	static var trailingInset: CGFloat { Theme.current.scaled(12) }

	/// Draws one line, cut short with an ellipsis rather than run past, and
	/// says where it ended.
	@discardableResult
	static func draw(
		_ text: String,
		font: NSFont,
		colour: NSColor,
		at x: CGFloat,
		in bounds: NSRect,
		limit: CGFloat
	) -> CGFloat {
		guard limit > x else { return x }

		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let string = NSAttributedString(string: text, attributes: [
			.font: font,
			.foregroundColor: colour,
			.paragraphStyle: paragraph,
		])

		let height = string.size().height
		let width = min(string.size().width, limit - x)
		string.draw(in: NSRect(x: x, y: bounds.midY - height / 2, width: width, height: height))
		return x + width
	}
}

private final class BranchRowView: NSView {
	private let branch: GitBranch
	override var isFlipped: Bool { true }

	init(branch: GitBranch) {
		self.branch = branch
		super.init(frame: .zero)
		toolTip = branch.subject.isEmpty ? branch.checkoutName : "\(branch.checkoutName) — \(branch.subject)"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(18)

		// The current branch gets a tick, which is how git itself marks it.
		if branch.isCurrent,
		   let tick = Theme.symbol("checkmark", size: 10 * Theme.current.scale, color: Theme.current.gitAdded) {
			let size = Theme.current.scaled(11)
			tick.drawFitted(in: NSRect(x: Theme.current.scaled(4), y: bounds.midY - size / 2, width: size, height: size))
		}

		let colour = branch.isCurrent ? Theme.current.gitAdded : Theme.current.sidebarText
		let font = branch.isCurrent
			? NSFont.systemFont(ofSize: Theme.current.scaled(12), weight: .semibold)
			: Theme.current.uiFont(12)

		// Ahead/behind counts, which are the reason to look at this list at all
		// when deciding whether to push or pull. Reserved first: they are the
		// short part and the part worth keeping when a name is too long.
		var tracking = ""
		if branch.ahead > 0 { tracking += "↑\(branch.ahead)" }
		if branch.behind > 0 { tracking += (tracking.isEmpty ? "" : " ") + "↓\(branch.behind)" }

		let countsFont = Theme.current.uiFont(10.5)
		let countsWidth = tracking.isEmpty ? 0 : NSAttributedString(
			string: tracking, attributes: [.font: countsFont]
		).size().width + Theme.current.scaled(6)

		let limit = bounds.maxX - RowMetrics.trailingInset
		x = RowMetrics.draw(
			branch.name, font: font, colour: colour,
			at: x, in: bounds, limit: limit - countsWidth
		)
		guard !tracking.isEmpty else { return }

		RowMetrics.draw(
			tracking, font: countsFont, colour: Theme.current.gitModified,
			at: x + Theme.current.scaled(6), in: bounds, limit: limit
		)
	}
}

/// A stash: what it was called, and how long it has been waiting.
private final class StashRowView: NSView {
	private let entry: GitStash.Entry
	override var isFlipped: Bool { true }

	init(entry: GitStash.Entry) {
		self.entry = entry
		super.init(frame: .zero)
		toolTip = [entry.reference, entry.branch.isEmpty ? nil : "on \(entry.branch)", entry.age]
			.compactMap { $0 }
			.joined(separator: " — ")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(18)

		if let box = Theme.symbol(
			"tray.full", size: 10 * Theme.current.scale, color: Theme.current.sidebarText
		) {
			let size = Theme.current.scaled(11)
			box.drawFitted(in: NSRect(
				x: Theme.current.scaled(4), y: bounds.midY - size / 2, width: size, height: size
			))
		}

		// How long it has been sitting there decides whether it is still
		// wanted, so it keeps its room and the message gives way first.
		let ageFont = Theme.current.uiFont(10.5)
		let ageWidth = entry.age.isEmpty ? 0 : NSAttributedString(
			string: entry.age, attributes: [.font: ageFont]
		).size().width + Theme.current.scaled(8)

		let limit = bounds.maxX - RowMetrics.trailingInset
		x = RowMetrics.draw(
			entry.message, font: Theme.current.uiFont(12), colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: limit - ageWidth
		)
		guard !entry.age.isEmpty else { return }

		RowMetrics.draw(
			entry.age, font: ageFont,
			colour: Theme.current.sidebarText.withAlphaComponent(0.55),
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

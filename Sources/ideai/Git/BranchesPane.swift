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

	private let root: URL

	private var branches: [GitBranch] = []
	private var rows: [Row] = []
	private var filterText = ""

	private var filterField: NSSearchField!
	private var tableView: BranchesTableView!

	private enum Row {
		case header(String)
		case branch(GitBranch)

		var isSelectable: Bool {
			if case .branch = self { return true }
			return false
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
			guard fresh != branches else { return }
			branches = fresh
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

	// MARK: - Actions

	private func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	private func checkoutSelected() {
		guard let branch = selectedBranch, !branch.isCurrent else { return }
		run { await GitBranches.checkout(branch, in: self.root) }
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
		let alert = NSAlert()
		alert.messageText = "git reported a problem"
		alert.informativeText = message.trimmingCharacters(in: .whitespacesAndNewlines)
		if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
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
		}
	}
}

extension BranchesPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		guard let branch = selectedBranch else { return }

		func item(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			item.isEnabled = enabled
			return item
		}

		menu.addItem(item("Checkout", #selector(contextCheckout), enabled: !branch.isCurrent))
		menu.addItem(item("New Branch from Here…", #selector(newBranch)))
		menu.addItem(.separator())
		menu.addItem(item(
			"Merge into Current",
			#selector(mergeIntoCurrent),
			enabled: !branch.isCurrent
		))
		menu.addItem(.separator())
		menu.addItem(item("Copy Name", #selector(copyBranchName)))

		if case .local = branch.kind {
			menu.addItem(item("Delete…", #selector(deleteBranch), enabled: !branch.isCurrent))
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
			tick.draw(
				in: NSRect(x: Theme.current.scaled(4), y: bounds.midY - size / 2, width: size, height: size),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
		}

		let colour = branch.isCurrent ? Theme.current.gitAdded : Theme.current.sidebarText
		let font = branch.isCurrent
			? NSFont.systemFont(ofSize: Theme.current.scaled(12), weight: .semibold)
			: Theme.current.uiFont(12)

		let name = NSAttributedString(string: branch.name, attributes: [
			.font: font,
			.foregroundColor: colour,
		])
		name.draw(at: NSPoint(x: x, y: bounds.midY - name.size().height / 2))
		x += name.size().width + Theme.current.scaled(6)

		// Ahead/behind counts, which are the reason to look at this list at all
		// when deciding whether to push or pull.
		var tracking = ""
		if branch.ahead > 0 { tracking += "↑\(branch.ahead)" }
		if branch.behind > 0 { tracking += (tracking.isEmpty ? "" : " ") + "↓\(branch.behind)" }
		guard !tracking.isEmpty else { return }

		let counts = NSAttributedString(string: tracking, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitModified,
		])
		counts.draw(at: NSPoint(x: x, y: bounds.midY - counts.size().height / 2))
	}
}

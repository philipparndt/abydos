import AppKit
import AbydosKit

/// The dropdown anchored to the project pill: actions on top, then open
/// projects, then recents — each with its badge and home-relative path.
enum ProjectSwitcherPopover {
	private static var active: NSPopover?
	private static weak var activeController: SwitcherViewController?

	/// Drives the filter from a capture run, so the filtered state can be seen.
	static func applyFilterForTesting(_ text: String) {
		activeController?.setFilter(text)
	}

	/// Presses a key in the list and says where the selection ended up.
	///
	/// Through the same door the keyboard uses — the field editor's
	/// `doCommandBy` — because the question is not whether the movement rule is
	/// right but whether Page Down reaches it at all: which selector that key
	/// sends depends on the field it lands in.
	static func pressForTesting(_ command: String) -> String {
		guard let controller = activeController else { return "no palette" }
		let selectors: [String: Selector] = [
			"down": #selector(NSResponder.moveDown(_:)),
			"up": #selector(NSResponder.moveUp(_:)),
			"pageDown": #selector(NSResponder.pageDown(_:)),
			"pageUp": #selector(NSResponder.pageUp(_:)),
			"scrollPageDown": #selector(NSResponder.scrollPageDown(_:)),
			"scrollPageUp": #selector(NSResponder.scrollPageUp(_:)),
			"end": #selector(NSResponder.moveToEndOfDocument(_:)),
			"start": #selector(NSResponder.moveToBeginningOfDocument(_:)),
		]
		guard let selector = selectors[command] else { return "unknown key \(command)" }
		return controller.pressForTesting(selector)
	}

	/// - Parameter anchorRect: which part of the control the popover points at,
	///   for one that is wider than the half being clicked.
	static func show(
		relativeTo pill: some NSView & TitlebarMenuAnchor,
		anchorRect: NSRect? = nil,
		currentProject: Project?,
		owner: MainWindowController? = nil
	) {
		// Clicking the pill while open should dismiss rather than stack popovers.
		if let active, active.isShown {
			active.close()
			Self.active = nil
			return
		}

		let controller = SwitcherViewController(currentProject: currentProject, owner: owner)
		let popover = NSPopover()
		popover.contentViewController = controller
		popover.behavior = .transient
		popover.appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)

		controller.onDismiss = { [weak popover] in popover?.close() }
		pill.isMenuOpen = true
		popover.willClose = {
			pill.isMenuOpen = false
			Self.active = nil
		}

		active = popover
		activeController = controller
		popover.show(relativeTo: anchorRect ?? pill.bounds, of: pill, preferredEdge: .maxY)
		// The table needs to be first responder for arrow keys to work immediately.
		controller.focusTable()
	}
}

/// NSPopover has no close callback, so this small subclass-free shim routes
/// `popoverWillClose` through a stored closure.
private extension NSPopover {
	private static var willCloseKey: UInt8 = 0

	var willClose: (() -> Void)? {
		get { (objc_getAssociatedObject(self, &Self.willCloseKey) as? ClosureBox)?.closure }
		set {
			objc_setAssociatedObject(self, &Self.willCloseKey, newValue.map(ClosureBox.init), .OBJC_ASSOCIATION_RETAIN)
			if delegate == nil { delegate = PopoverCloseObserver.shared }
		}
	}
}

private final class ClosureBox: NSObject {
	let closure: () -> Void
	init(_ closure: @escaping () -> Void) { self.closure = closure }
}

private final class PopoverCloseObserver: NSObject, NSPopoverDelegate {
	static let shared = PopoverCloseObserver()

	func popoverWillClose(_ notification: Notification) {
		guard let popover = notification.object as? NSPopover else { return }
		popover.willClose?()
	}
}

// MARK: - Content

private final class SwitcherViewController: NSViewController {
	enum Row {
		case action(title: String, symbol: String, shortcut: String?, detail: String?, handler: () -> Void)
		case header(String)
		case project(RecentProject, isOpen: Bool)
		case branch(String, isCurrent: Bool)

		var isSelectable: Bool {
			if case .header = self { return false }
			return true
		}

		var height: CGFloat { Theme.current.scaled(26) }
	}

	var onDismiss: (() -> Void)?

	private let currentProject: Project?
	/// The window the choice was made in, which is the one that changes
	/// project unless the setting says to open another.
	private weak var owner: MainWindowController?
	private var rows: [Row] = []
	private var tableView: NSTableView!
	private var filterField: NSSearchField!
	/// What the user has typed. Empty shows the full menu.
	private var filterText = ""

	/// The current repository's branches, and where it lives on the web. Both
	/// arrive after the popover is on screen — git is asked once, and the list
	/// is rebuilt when it answers.
	private var branches: [String] = []
	private var currentBranch: String?
	private var forge: GitForge.Repository?

	init(currentProject: Project?, owner: MainWindowController?) {
		self.currentProject = currentProject
		self.owner = owner
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Asks git what this repository has, once, and rebuilds when it answers.
	private func readRepository() {
		guard let root = currentProject?.root else { return }
		Task { @MainActor [weak self] in
			async let names = BranchMenu.branches(in: root)
			async let current = BranchMenu.currentBranch(in: root)
			async let repository = GitForge.repository(in: root)

			let (branches, head, forge) = await (names, current, repository)
			guard let self, self.isViewLoaded else { return }
			self.branches = branches
			self.currentBranch = head
			self.forge = forge
			// Only the filtered list shows any of this, so there is nothing to
			// redraw until something has been typed.
			guard !self.filterText.isEmpty else { return }
			self.buildRows()
			self.tableView.reloadData()
			self.updatePreferredSize()
		}
	}

	override func loadView() {
		buildRows()
		readRepository()

		// The cached scan is shown immediately and refreshed behind it, so the
		// popover never waits on the file system to appear.
		DiscoveryCache.refresh { [weak self] in
			guard let self, self.isViewLoaded else { return }
			self.buildRows()
			self.tableView.reloadData()
			self.updatePreferredSize()
		}

		let table = SwitcherTableView()
		table.headerView = nil
		table.backgroundColor = .clear
		// Same reason as the navigator: `.none` would stop drawSelection running.
		table.selectionHighlightStyle = .regular
		table.intercellSpacing = .zero
		table.rowSizeStyle = .custom
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.action = #selector(rowClicked)
		table.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
		tableView = table

		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.autohidesScrollers = true

		// A visible field, so what you type is on screen and obviously a filter,
		// rather than an invisible jump-to-match you have to guess at.
		let field = NSSearchField()
		field.placeholderString = "Search  ·  > actions  ·  : line"
		field.font = Theme.current.uiFont(12)
		field.delegate = self
		field.focusRingType = .none
		filterField = field

		let container = ColoredView(color: Theme.current.sidebarBackground)
		container.colourSource = { Theme.current.sidebarBackground }
		container.addSubview(field)
		container.addSubview(scrollView)
		field.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			field.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
			field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
			field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

			scrollView.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 6),
			scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
		])

		view = container
		updatePreferredSize()
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		selectFirstSelectableRow()
	}

	/// The field takes focus, so typing filters immediately. Arrow keys are
	/// forwarded to the list from there.
	func focusTable() {
		view.window?.makeFirstResponder(filterField)
	}

	/// Sets the filter programmatically, used by capture runs.
	func setFilter(_ text: String) {
		filterField.stringValue = text
		applyFilter(text)
	}

	/// Height tracks content up to a cap, so a short list yields a short menu.
	private func updatePreferredSize() {
		let contentHeight = rows.reduce(0) { $0 + $1.height } + Theme.current.scaled(52)
		preferredContentSize = NSSize(
			width: Theme.current.scaled(340),
			height: min(max(contentHeight, Theme.current.scaled(120)), Theme.current.scaled(560))
		)
	}

	/// Checkouts found by scanning, refreshed in the background.
	///
	/// Cached on the type rather than the popover: the popover is rebuilt on
	/// every open, and a fresh scan each time would make the first frame wait on
	/// the file system.
	private enum DiscoveryCache {
		private static var projects: [RecentProject] = []
		private static var isScanning = false

		static var current: [RecentProject] { projects }

		/// Rescans unless one is already in flight.
		static func refresh(completion: @escaping () -> Void) {
			guard !isScanning else { return }
			isScanning = true

			let paths = Settings.shared.projectSearchPaths
			let depth = Settings.shared.projectSearchDepth

			DispatchQueue.global(qos: .userInitiated).async {
				let roots = ProjectDiscovery.resolve(searchPaths: paths)
				let found = ProjectDiscovery.scan(roots: roots, maxDepth: depth)

				// Presented as recents so every downstream rule — filtering,
				// badges, row layout — applies unchanged. The date is when the
				// checkout was last worked on rather than last opened here, which
				// is the ordering the list wants anyway.
				let converted = found.map {
					RecentProject(path: $0.url.path, lastOpened: $0.lastActivity)
				}

				DispatchQueue.main.async {
					projects = converted
					isScanning = false
					completion()
				}
			}
		}
	}

	/// Discovered checkouts that are not already listed above.
	private func discoveredProjects(excluding paths: Set<String>) -> [RecentProject] {
		DiscoveryCache.current.filter { !paths.contains($0.path) }
	}

	// MARK: - Rows

	private func buildRows() {
		let delegate = NSApp.delegate as? AppDelegate
		RecentProjects.shared.pruneMissing()

		// While filtering, the list is only matching projects: the New/Open/Clone
		// actions are not things a filter can match, and keeping them would push
		// the results down.
		guard filterText.isEmpty else {
			buildFilteredRows(delegate: delegate)
			return
		}

		rows = []

		let openRoots = delegate?.openProjectRoots ?? []
		let openPaths = Set(openRoots.map(\.path))

		if !openRoots.isEmpty {
			rows.append(.header("Open Projects"))
			let recents = RecentProjects.shared.entries
			for root in openRoots {
				let entry = recents.first { $0.path == root.path }
					?? RecentProject(path: root.path, lastOpened: Date())
				rows.append(.project(entry, isOpen: true))
			}
		}

		// Recents excludes what is already listed above to avoid duplicates.
		let recents = RecentProjects.shared.entries.filter { !openPaths.contains($0.path) }
		if !recents.isEmpty {
			rows.append(.header("Recent Projects"))
			for entry in recents {
				rows.append(.project(entry, isOpen: false))
			}
		}

		// Everything else found on disk. A switcher that lists only what has
		// been opened before cannot help with the case it exists for: opening a
		// project for the first time.
		var listed = openPaths
		listed.formUnion(recents.map(\.path))
		let discovered = discoveredProjects(excluding: listed)
		if !discovered.isEmpty {
			rows.append(.header("All Projects"))
			for entry in discovered {
				rows.append(.project(entry, isOpen: false))
			}
		}

		// Underneath, not on top. This list is opened to reach a project, and
		// the three commands that are not one were standing in front of them.
		// They stay here rather than moving to the menu bar because only Open
		// is there today.
		rows.append(.header("Elsewhere"))
		if let root = currentProject?.root {
			// The folder this window is actually looking at, which on a linked
			// worktree is the worktree rather than the repository it came from.
			rows.append(.action(title: "Reveal in Finder", symbol: "magnifyingglass", shortcut: nil, detail: nil) { [weak self] in
				self?.onDismiss?()
				NSWorkspace.shared.activateFileViewerSelecting([root])
			})
		}
		rows.append(.action(title: "Open…", symbol: "folder", shortcut: nil, detail: nil) { [weak self] in
			self?.onDismiss?()
			delegate?.openProjectPanel(nil)
		})
		rows.append(.action(title: "New Project…", symbol: "plus", shortcut: nil, detail: nil) { [weak self] in
			self?.onDismiss?()
			self?.newProject()
		})
		rows.append(.action(title: "Clone Repository…", symbol: "arrow.trianglehead.branch", shortcut: nil, detail: nil) { [weak self] in
			self?.onDismiss?()
			self?.cloneRepository()
		})
	}

	/// How many matching projects a filtered list shows before the branches and
	/// actions below them would be pushed off the end.
	private static let projectLimit = 8

	/// What the typing is asking for.
	///
	/// The prefixes are VS Code's, because this is the field VS Code taught
	/// people to open and they arrive already knowing what `>` does.
	private enum Scope {
		/// Everything at once, ranked: projects, then branches, then actions.
		case everything(String)
		/// `>` — actions only, which is what a command palette normally is.
		case commands(String)
		/// `:` — a line in the file being edited.
		case line(Int?)
	}

	private var scope: Scope {
		if filterText.hasPrefix(">") {
			return .commands(rest(after: ">").lowercased())
		}
		if filterText.hasPrefix(":") {
			let digits = rest(after: ":")
			return .line(digits.isEmpty ? nil : Int(digits))
		}
		return .everything(filterText.lowercased())
	}

	private func rest(after prefix: String) -> String {
		String(filterText.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
	}

	/// Matches on both name and path, so "3d" finds everything under ~/dev/3d.
	private func buildFilteredRows(delegate: AppDelegate?) {
		let needle: String
		switch scope {
		case let .commands(query):
			rows = [.header("Actions")]
			rows.append(contentsOf: matchingActions(query))
			return
		case let .line(number):
			buildLineRows(number)
			return
		case let .everything(query):
			needle = query
		}

		let openPaths = Set((delegate?.openProjectRoots ?? []).map(\.path))

		var candidates = RecentProjects.shared.entries
		for root in delegate?.openProjectRoots ?? [] where !candidates.contains(where: { $0.path == root.path }) {
			candidates.append(RecentProject(path: root.path, lastOpened: Date()))
		}

		// Typing searches everything on disk, not just what has been opened.
		let known = Set(candidates.map(\.path))
		candidates.append(contentsOf: discoveredProjects(excluding: known))

		let projects = ProjectFilter.match(candidates, query: needle)

		rows = []
		if !projects.isEmpty {
			// Capped, and the header says so. A short query matches half the
			// disk, and without a limit the branches and actions underneath sit
			// below a hundred rows of projects, which is the same as not being
			// there. Narrowing the query is how the rest are reached.
			let shown = projects.prefix(Self.projectLimit)
			rows.append(.header(
				projects.count > shown.count
					? "Projects — \(shown.count) of \(projects.count)"
					: "Projects"
			))
			rows.append(contentsOf: shown.map {
				Row.project($0, isOpen: openPaths.contains($0.path))
			})
		}

		// Branches of the repository already open. Typing a branch name is the
		// same gesture as typing a project's, and ends in the same place the
		// branch menu would have.
		let matched = branches.filter { $0.lowercased().contains(needle) }
		if !matched.isEmpty {
			rows.append(.header("Branches"))
			for branch in matched {
				rows.append(.branch(branch, isCurrent: branch == currentBranch))
			}
		}

		let actions = matchingActions(needle)
		if !actions.isEmpty {
			rows.append(.header("Actions"))
			rows.append(contentsOf: actions)
		}
	}

	/// What `:` offers: one row, once there is a number to go to.
	private func buildLineRows(_ number: Int?) {
		rows = [.header("Go to Line")]
		guard let number, number > 0 else {
			// Nothing to do yet, but the header alone reads as a broken list.
			rows.append(.action(title: "Type a line number", symbol: "number", shortcut: nil, detail: nil, handler: {}))
			return
		}
		rows.append(.action(title: "Line \(number)", symbol: "arrow.right", shortcut: nil, detail: nil, handler: { [weak self] in
			self?.onDismiss?()
			self?.owner?.goTo(line: number)
		}))
	}

	/// The things this window can be asked to do, as rows.
	///
	/// The same two handoffs the branch menu offers, flattened: a submenu cannot
	/// be typed at, so the host's pages become rows of their own and are found
	/// by the words in them.
	private func matchingActions(_ needle: String) -> [Row] {
		var actions: [(title: String, symbol: String, handler: () -> Void)] = []

		if let root = currentProject?.root {
			if let fork = ForkIntegration.applicationURL() {
				actions.append((title: "Open in Fork", symbol: "arrow.up.forward.app", handler: {
					ForkIntegration.open(repository: root, application: fork)
				}))
			}
			actions.append((title: "Reveal in Finder", symbol: "magnifyingglass", handler: {
				NSWorkspace.shared.activateFileViewerSelecting([root])
			}))
		}

		if let forge {
			let host = forge.displayName
			if let branch = currentBranch, let url = forge.url(forBranch: branch) {
				actions.append((title: "Open Branch on \(host)", symbol: "globe", handler: {
					NSWorkspace.shared.open(url)
				}))
			}
			if let url = forge.pullRequestsURL {
				actions.append((title: "Open Pull Requests on \(host)", symbol: "globe", handler: {
					NSWorkspace.shared.open(url)
				}))
			}
			if let url = forge.webURL {
				actions.append((title: "Open Repository on \(host)", symbol: "globe", handler: {
					NSWorkspace.shared.open(url)
				}))
			}
		}

		let delegate = NSApp.delegate as? AppDelegate
		actions.append((title: "Open…", symbol: "folder", handler: { [weak self] in
			self?.onDismiss?()
			delegate?.openProjectPanel(nil)
		}))
		actions.append((title: "New Project…", symbol: "plus", handler: { [weak self] in
			self?.onDismiss?()
			self?.newProject()
		}))
		actions.append((title: "Clone Repository…", symbol: "arrow.trianglehead.branch", handler: { [weak self] in
			self?.onDismiss?()
			self?.cloneRepository()
		}))

		// Everything the menus offer, which is everything the app can do: a
		// command added to a menu tomorrow is in here the moment it is added,
		// with whatever key it answers to, and nobody has to remember this
		// list exists. The few above are the ones with no menu item of their
		// own — what this project's forge can do, which depends on the
		// repository rather than on the app.
		let contextual = actions.map {
			CommandDescriptor(title: $0.title, path: ["Project"], shortcut: nil)
		}
		let fromMenus = MenuCommands.all()

		let ranked = CommandSearch.match(contextual + fromMenus.map(\.descriptor), query: needle)

		return ranked.compactMap { command -> Row? in
			if let contextualIndex = actions.firstIndex(where: {
				$0.title == command.title && command.path == ["Project"]
			}) {
				let action = actions[contextualIndex]
				return .action(
					title: action.title, symbol: action.symbol,
					shortcut: nil, detail: nil, handler: action.handler
				)
			}

			guard let entry = fromMenus.first(where: {
				$0.descriptor.title == command.title && $0.descriptor.path == command.path
			}) else { return nil }

			return .action(
				title: command.title,
				symbol: "command",
				shortcut: command.shortcut,
				detail: command.path.joined(separator: " › "),
				handler: { [weak self] in
					self?.onDismiss?()
					// After the popover has gone: a menu action that opens a
					// sheet or moves the keyboard cannot do it while a popover
					// still has the window.
					DispatchQueue.main.async { entry.perform() }
				}
			)
		}
	}

	private func applyFilter(_ text: String) {
		filterText = text.trimmingCharacters(in: .whitespaces)
		buildRows()
		tableView.reloadData()
		updatePreferredSize()
		selectFirstSelectableRow()
	}

	// MARK: - Actions

	@objc private func rowClicked() {
		activateRow(at: tableView.clickedRow)
	}

	private func activateRow(at index: Int) {
		guard rows.indices.contains(index) else { return }
		switch rows[index] {
		case let .action(_, _, _, _, handler):
			handler()
		case .header:
			break
		case let .project(entry, _):
			onDismiss?()
			(NSApp.delegate as? AppDelegate)?.open(projectAt: entry.url, from: owner)
		case let .branch(branch, isCurrent):
			onDismiss?()
			// Checking out the branch already on is a slow way of doing nothing.
			guard !isCurrent, let root = currentProject?.root else { return }
			BranchMenu.checkout(branch, in: root)
		}
	}

	private func newProject() {
		let panel = NSSavePanel()
		panel.title = "New Project"
		panel.prompt = "Create"
		panel.nameFieldLabel = "Project name:"
		panel.canCreateDirectories = true

		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			(NSApp.delegate as? AppDelegate)?.open(projectAt: url, from: owner)
		} catch {
			Toast.post("Could not open that folder", detail: error.localizedDescription)
		}
	}

	private func cloneRepository() {
		let alert = NSAlert()
		alert.messageText = "Clone Repository"
		alert.informativeText = "Enter a repository URL. It will be cloned into a directory you choose."
		alert.addButton(withTitle: "Choose Location…")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		field.placeholderString = "https://github.com/owner/repo.git"
		alert.accessoryView = field
		alert.window.initialFirstResponder = field

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let remote = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !remote.isEmpty else { return }

		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.prompt = "Clone Here"
		guard panel.runModal() == .OK, let parent = panel.url else { return }

		// Derive the destination the way `git clone` would.
		let name = URL(fileURLWithPath: remote).deletingPathExtension().lastPathComponent
		let destination = parent.appendingPathComponent(name)

		Task {
			let result = await GitRepository.run(["clone", remote, destination.path], in: parent)
			await MainActor.run {
				if result.exitCode == 0 {
					(NSApp.delegate as? AppDelegate)?.open(projectAt: destination, from: owner)
				} else {
					Toast.post(
						"Clone failed",
						detail: result.stderr.isEmpty
							? "git exited with code \(result.exitCode)."
							: result.stderr
					)
				}
			}
		}
	}

	// MARK: - Keyboard

	/// Sends the field editor's command, and reports the row it left selected.
	func pressForTesting(_ selector: Selector) -> String {
		let handled = control(filterField, textView: NSTextView(), doCommandBy: selector)
		let row = tableView.selectedRow
		let what = rows.indices.contains(row) ? describeForTesting(rows[row]) : "none"
		return "handled=\(handled) row=\(row) of \(rows.count): \(what)"
	}

	private func describeForTesting(_ row: Row) -> String {
		switch row {
		case let .action(title, _, _, _, _): return "action \(title)"
		case let .header(title):             return "header \(title)"
		case let .project(project, _):       return "project \(project.path)"
		case let .branch(name, _):           return "branch \(name)"
		}
	}

	private func selectFirstSelectableRow() {
		if let index = rows.firstIndex(where: { $0.isSelectable }) {
			tableView.selectRowIndexes([index], byExtendingSelection: false)
		}
	}

	/// Returns true when the event was consumed.
	private func handleKeyDown(_ event: NSEvent) -> Bool {
		switch event.keyCode {
		case 36, 76: // Return, Keypad Enter
			activateRow(at: tableView.selectedRow)
			return true
		case 53: // Escape
			onDismiss?()
			return true
		case 125: // Down
			moveSelection(by: 1)
			return true
		case 126: // Up
			moveSelection(by: -1)
			return true
		default:
			// Everything else belongs to the filter field.
			return false
		}
	}

	/// Moves the selection by that many *selectable* rows — headers are stepped
	/// over rather than landed on.
	private func moveSelection(by delta: Int) {
		guard let index = ListSelection.move(
			from: tableView.selectedRow,
			by: delta,
			count: rows.count,
			isSelectable: { rows[$0].isSelectable }
		) else { return }

		tableView.selectRowIndexes([index], byExtendingSelection: false)
		tableView.scrollRowToVisible(index)
	}

	/// How far a page moves: what fits in the list, less one row of overlap so
	/// the place somebody was reading is still on screen afterwards.
	private var pageSize: Int {
		ListSelection.pageSize(
			viewportHeight: tableView.enclosingScrollView?.contentSize.height ?? tableView.bounds.height,
			rowHeight: rows.first?.height ?? Theme.current.scaled(26)
		)
	}

}

// MARK: - Table data

extension SwitcherViewController: NSSearchFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		applyFilter(filterField.stringValue)
	}

	/// Arrows and Return work while the field has focus, so filtering and
	/// choosing are one continuous gesture.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.moveDown(_:)):
			moveSelection(by: 1)
			return true
		case #selector(NSResponder.moveUp(_:)):
			moveSelection(by: -1)
			return true
		// Both spellings: which one a key sends depends on the field it is sent
		// to, and a list that answers only one of them works in some places and
		// not others.
		case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
			moveSelection(by: pageSize)
			return true
		case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
			moveSelection(by: -pageSize)
			return true
		// ⌘↑ and ⌘↓ — the ends of the list, which is what somebody reaches for
		// after paging twice.
		case #selector(NSResponder.moveToBeginningOfDocument(_:)),
		     #selector(NSResponder.scrollToBeginningOfDocument(_:)):
			moveSelection(by: -rows.count)
			return true
		case #selector(NSResponder.moveToEndOfDocument(_:)),
		     #selector(NSResponder.scrollToEndOfDocument(_:)):
			moveSelection(by: rows.count)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			activateRow(at: tableView.selectedRow)
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			// Escape clears the filter first, and only then closes.
			if filterText.isEmpty {
				onDismiss?()
			} else {
				filterField.stringValue = ""
				applyFilter("")
			}
			return true
		default:
			return false
		}
	}
}

extension SwitcherViewController: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		rows[row].height
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		rows[row].isSelectable
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		SwitcherRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		switch rows[row] {
		case let .action(title, symbol, shortcut, detail, _):
			return SwitcherActionCell(title: title, symbol: symbol, shortcut: shortcut, detail: detail)
		case let .header(title):
			return SwitcherHeaderCell(title: title)
		case let .project(entry, isOpen):
			return SwitcherProjectCell(entry: entry, isOpen: isOpen, filter: filterText)
		case let .branch(name, isCurrent):
			return SwitcherBranchCell(name: name, isCurrent: isCurrent, filter: filterText)
		}
	}
}

// MARK: - Table subclass

private final class SwitcherTableView: NSTableView {
	var onKeyDown: ((NSEvent) -> Bool)?

	/// Row under the pointer, so rows light up on hover the way a menu does.
	private var hoveredRow: Int = -1
	private var trackingArea: NSTrackingArea?

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	// The popover's table should take focus so arrow keys work on open.
	override var acceptsFirstResponder: Bool { true }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		setHovered(row(at: point))
	}

	override func mouseExited(with event: NSEvent) {
		setHovered(-1)
	}

	private func setHovered(_ newRow: Int) {
		guard newRow != hoveredRow else { return }
		let previous = hoveredRow
		hoveredRow = newRow

		// Repaint only the two rows involved rather than the whole table.
		for candidate in [previous, newRow] where candidate >= 0 {
			(rowView(atRow: candidate, makeIfNecessary: false) as? SwitcherRowView)?
				.setHovered(candidate == newRow)
		}
	}
}

/// Draws the blue selection band, and a lighter band on hover.
private final class SwitcherRowView: NSTableRowView {
	private var isHovered = false

	func setHovered(_ hovered: Bool) {
		guard hovered != isHovered else { return }
		isHovered = hovered
		needsDisplay = true
	}

	override func drawBackground(in dirtyRect: NSRect) {
		super.drawBackground(in: dirtyRect)
		// Only when not selected, so hover never competes with the selection.
		guard isHovered, !isSelected else { return }
		NSColor.white.withAlphaComponent(0.07).setFill()
		bounds.fill()
	}

	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selectionActive.setFill()
		bounds.fill()
	}

	override var isEmphasized: Bool {
		get { true }
		set {}
	}
}

// MARK: - Cells

private final class SwitcherActionCell: NSView {
	private let title: String
	private let symbol: String
	/// The key this already answers to, so the palette teaches it rather than
	/// being the only way to reach it.
	private let shortcut: String?
	/// Where it lives — the menu it was found under — for telling two commands
	/// of the same name apart.
	private let detail: String?

	init(title: String, symbol: String, shortcut: String? = nil, detail: String? = nil) {
		self.title = title
		self.symbol = symbol
		self.shortcut = shortcut
		self.detail = detail
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let tint = Theme.current.sidebarText
		var x: CGFloat = 12

		// Colour baked into the symbol configuration — see Theme.symbol.
		if let rendered = Theme.symbol(symbol, size: 12 * Theme.current.scale, color: tint) {
			// respectFlipped: this view is flipped; without it the glyph mirrors.
			rendered.drawFitted(in: NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14))
		}
		x += 22

		// The shortcut first, from the right, so the name can be shortened
		// against it rather than drawn underneath it.
		var rightEdge = bounds.maxX - 12
		if let shortcut, !shortcut.isEmpty {
			let keys = NSAttributedString(string: shortcut, attributes: [
				.font: Theme.current.uiFont(12),
				.foregroundColor: tint.withAlphaComponent(0.75),
			])
			let size = keys.size()
			keys.draw(at: NSPoint(x: rightEdge - size.width, y: bounds.midY - size.height / 2))
			rightEdge -= size.width + 14
		}

		let attributed = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(13),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		attributed.draw(at: NSPoint(x: x, y: bounds.midY - attributed.size().height / 2))
		x += attributed.size().width + 8

		guard let detail, !detail.isEmpty, x < rightEdge - 20 else { return }
		let where_ = NSAttributedString(string: detail, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: tint.withAlphaComponent(0.55),
		])
		where_.draw(with: NSRect(x: x, y: bounds.midY - where_.size().height / 2,
		                        width: rightEdge - x, height: where_.size().height),
		            options: [.usesLineFragmentOrigin])
	}
}

private final class SwitcherHeaderCell: NSView {
	private let title: String

	init(title: String) {
		self.title = title
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// A hairline above the group, except at the very top of the list.
		if bounds.minY > 0 {
			Theme.current.separator.setFill()
			NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
		}

		let attributed = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(11, weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		attributed.draw(at: NSPoint(x: 12, y: bounds.height - attributed.size().height - 4))
	}
}

/// One branch, laid out like a project so the two lists read as one.
private final class SwitcherBranchCell: NSView {
	private let name: String
	private let isCurrent: Bool
	private let filter: String

	init(name: String, isCurrent: Bool, filter: String) {
		self.name = name
		self.isCurrent = isCurrent
		self.filter = filter
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let tint = Theme.current.sidebarText
		let iconSize = Theme.current.scaled(13)
		if let icon = Theme.symbol("arrow.trianglehead.branch", size: 11 * Theme.current.scale, color: tint)
			?? Theme.symbol("arrow.triangle.branch", size: 11 * Theme.current.scale, color: tint) {
			icon.drawFitted(in: NSRect(
				x: Theme.current.scaled(12),
				y: bounds.midY - iconSize / 2,
				width: iconSize,
				height: iconSize
			))
		}

		let text = NSMutableAttributedString(string: name, attributes: [
			.font: Theme.current.uiFont(13, weight: isCurrent ? .semibold : .regular),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		if !filter.isEmpty,
		   let range = name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			text.addAttribute(
				.foregroundColor,
				value: Theme.current.gitModified,
				range: NSRange(range, in: name)
			)
		}
		let size = text.size()
		text.draw(at: NSPoint(x: Theme.current.scaled(33), y: bounds.midY - size.height / 2))

		guard isCurrent else { return }
		let marker = NSAttributedString(string: "current", attributes: [
			.font: Theme.current.monoFont(11),
			.foregroundColor: Theme.current.gitIgnored,
		])
		let markerSize = marker.size()
		marker.draw(at: NSPoint(
			x: bounds.maxX - Theme.current.scaled(12) - ceil(markerSize.width),
			y: bounds.midY - markerSize.height / 2
		))
	}
}

/// One project, on one line.
///
/// The colour is a rail on the leading edge rather than a lettered square: the
/// initials never said anything the name beside them did not, and the square is
/// most of what made this list look like somebody else's IDE. On one line
/// instead of two, twice as many projects fit — and the paths, right-aligned in
/// a fixed face, line up into a column that can be read down.
private final class SwitcherProjectCell: NSView {
	private let entry: RecentProject
	private let isOpen: Bool
	private let filter: String

	init(entry: RecentProject, isOpen: Bool, filter: String) {
		self.entry = entry
		self.isOpen = isOpen
		self.filter = filter
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private static var railWidth: CGFloat { Theme.current.scaled(3) }
	private static var leading: CGFloat { Theme.current.scaled(13) }
	private static var trailing: CGFloat { Theme.current.scaled(12) }

	override func draw(_ dirtyRect: NSRect) {
		ProjectBadge.color(for: entry.name, colorIndex: entry.colorIndex).setFill()
		NSRect(x: 0, y: 0, width: Self.railWidth, height: bounds.height).fill()

		let name = NSMutableAttributedString(string: entry.name, attributes: [
			.font: Theme.current.uiFont(13, weight: isOpen ? .semibold : .regular),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		// What the typing matched, lit — so it is clear why this row is here.
		if !filter.isEmpty,
		   let range = entry.name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) {
			name.addAttribute(
				.foregroundColor,
				value: Theme.current.gitModified,
				range: NSRange(range, in: entry.name)
			)
		}

		let nameSize = name.size()
		let nameX = Self.leading
		name.draw(at: NSPoint(x: nameX, y: bounds.midY - nameSize.height / 2))

		// A fixed face, right-aligned, truncated at the front: the tail of a
		// path is the part that says which one this is, and `/var/folders/…`
		// is never it.
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .right
		paragraph.lineBreakMode = .byTruncatingHead

		let path = NSAttributedString(string: entry.displayPath, attributes: [
			.font: Theme.current.monoFont(11),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
		let left = nameX + ceil(nameSize.width) + Theme.current.scaled(12)
		let available = bounds.maxX - Self.trailing - left
		guard available > Theme.current.scaled(30) else { return }
		path.draw(in: NSRect(
			x: left,
			y: bounds.midY - path.size().height / 2,
			width: available,
			height: path.size().height
		))
	}
}

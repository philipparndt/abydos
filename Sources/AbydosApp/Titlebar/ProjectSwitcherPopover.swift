import AppKit
import AbydosKit

/// The dropdown anchored to the project pill: actions on top, then open
/// projects, then recents — each with its badge and home-relative path.
enum ProjectSwitcherPopover {
	/// What the popover is for when it opens.
	///
	/// The same list, the same styling and the same filter field — the branch
	/// pill wanted a branch picker with folders and a filter, and this popover
	/// already was one for everything else. Two of them would be two things to
	/// keep looking the same.
	enum Focus {
		/// Projects, branches and actions, ranked — what ⇧⌘P opens.
		case everything
		/// Branches only, grouped into their folders — what the branch pill
		/// opens.
		case branches
		/// What the project can run, with the goals of a reactor folded — what
		/// the run control opens.
		case runs
	}

	/// Everything the run list needs, handed over by the window that knows it.
	///
	/// A carrier rather than something this popover works out for itself: what
	/// a chosen row *does* differs by where it came from — a launch.json entry
	/// is selected, a scheme is started, a Makefile goal is turned into a run —
	/// and the window has that dispatch already. This takes the arrangement and
	/// gives back the configuration that was chosen.
	struct RunList {
		var arrangement: RunPicker.Arrangement
		/// The one the play button is pointed at, marked the way the current
		/// branch is marked.
		var selected: String?
		var choose: (RunConfiguration) -> Void
		/// The rows at the bottom: Edit…, New…, Open launch.json.
		var actions: [(title: String, symbol: String, handler: () -> Void)] = []
	}

	/// Whether a driven run wants the pill's timings and rows printed.
	nonisolated(unsafe) static var reportsForTesting = false

	private static var active: NSPopover?
	/// The window the key's palette lives in, and the window it was opened
	/// over — kept so that the key can close it again and a driven run can ask
	/// where it landed.
	private static var activePanel: PalettePanel?
	private static weak var activeParent: NSWindow?
	private static weak var activeController: SwitcherViewController?

	/// What the popover is showing, headings and all, so a driven run can check
	/// the arrangement rather than photograph it.
	static func rowsForTesting() -> [String] {
		activeController?.rowsForTesting() ?? ["no popover"]
	}

	/// Opens a goal's places from a capture run, and says what is in them.
	static func openGoalForTesting(_ name: String) -> [String] {
		activeController?.openGoalForTesting(name) ?? ["no popover"]
	}

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
		owner: MainWindowController? = nil,
		focus: Focus = .everything,
		runs: RunList? = nil
	) {
		// Clicking the pill while open should dismiss rather than stack popovers.
		guard !dismissedWhatWasOpen() else { return }

		let controller = makeController(
			currentProject: currentProject, owner: owner, focus: focus, runs: runs
		)
		let popover = NSPopover()
		popover.contentViewController = controller
		popover.behavior = .transient
		popover.appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)

		controller.onDismiss = { [weak popover] in popover?.close() }
		pill.isMenuOpen = true
		popover.willClose = {
			pill.isMenuOpen = false
			Self.active = nil
			Self.activeController = nil
		}

		active = popover
		activeController = controller
		popover.show(relativeTo: anchorRect ?? pill.bounds, of: pill, preferredEdge: .maxY)
		// The table needs to be first responder for arrow keys to work immediately.
		controller.focusTable()
	}

	/// The same list, centred over the window whose menu answered ⇧⌘P.
	///
	/// **A key's list belongs where the eyes are; a click's belongs at the
	/// control.** ⇧⌘A had put the running-sessions list in the middle of its
	/// window since it was added, and this one — the same gesture, a key
	/// pressed by somebody looking at the middle of a wide window — opened in
	/// the top-left corner, because the key had been given the pill's geometry.
	/// The pill, the branch pill and the run control keep that geometry, which
	/// is theirs: a list that jumped to the middle when a corner control was
	/// clicked would have lost the thing it is about.
	///
	/// One controller either way, as the running-sessions list is one
	/// controller in two windows — this is where it stands, not a second
	/// palette.
	static func showCentred(
		over parent: NSWindow?,
		currentProject: Project?,
		owner: MainWindowController? = nil,
		focus: Focus = .everything,
		runs: RunList? = nil
	) {
		guard let parent else { return }
		// The key pressed again puts it away, which is what the panel's own
		// `onKey` below catches; this covers the other openings — the pill
		// while the panel is up, and a driven run asking twice.
		guard !dismissedWhatWasOpen() else { return }

		let controller = makeController(
			currentProject: currentProject, owner: owner, focus: focus, runs: runs
		)
		// A nominal frame: the list's own size is known only once the view has
		// loaded, which setting the content controller below is what does, and
		// `place` gives the window that size a moment later.
		let window = PalettePanel(
			contentRect: NSRect(x: 0, y: 0, width: Theme.current.scaled(340), height: Theme.current.scaled(360)),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: true
		)
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.isMovableByWindowBackground = true
		window.contentViewController = controller

		controller.onDismiss = { closeCentred() }
		controller.onWantedSize = { [weak window] size in
			guard let window, window.isVisible else { return }
			PalettePanel.resize(window, to: size)
		}
		window.onResignKey = { closeCentred() }
		// ⇧⌘P again, caught here because a child window's responder chain does
		// not run through its parent: while this panel has the keyboard nothing
		// answers `showProjectSwitcher(_:)`, the menu item is disabled, and the
		// keystroke arrives at this window instead. The same place ⇧⌘A catches
		// its own key.
		window.onKey = { event in
			guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
			      event.charactersIgnoringModifiers?.lowercased() == "p"
			else { return false }
			closeCentred()
			return true
		}

		activePanel = window
		activeParent = parent
		activeController = controller
		PalettePanel.place(window, over: parent, size: controller.preferredContentSize)
		parent.addChildWindow(window, ordered: .above)
		// The keyboard only if the app already has it: opening this is an
		// answer to a keystroke, so it always does in use, and never does in a
		// capture run — where taking it would take it from somebody's terminal.
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
		} else {
			window.orderFront(nil)
		}
		controller.focusTable()
	}

	/// Whichever of the two was open, put away — so that the gesture that
	/// opens one closes the other rather than stacking them.
	@discardableResult
	private static func dismissedWhatWasOpen() -> Bool {
		if let active, active.isShown {
			active.close()
			Self.active = nil
			Self.activeController = nil
			return true
		}
		if activePanel?.isVisible == true {
			closeCentred()
			return true
		}
		return false
	}

	private static func closeCentred() {
		guard let window = activePanel else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		activePanel = nil
		activeParent = nil
		activeController = nil
	}

	/// ⇧⌘P again, delivered where that key actually arrives while the palette
	/// holds the keyboard — the panel itself, the menu item being disabled —
	/// so a run can claim the second press closes it. The answer is where the
	/// palette is afterwards, which for a working close is "not open".
	static func pressTheKeyAgainForTesting() -> String {
		guard let window = activePanel, window.isVisible else { return "not open" }
		guard let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.command, .shift],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window.windowNumber,
			context: nil,
			characters: "P",
			charactersIgnoringModifiers: "p",
			isARepeat: false,
			keyCode: 35
		) else { return "no event" }
		window.keyDown(with: event)
		return placementForTesting()
	}

	/// Where the centred palette sits against the window it was opened over, so
	/// a driven run checks the placement without a screenshot.
	static func placementForTesting() -> String {
		// A click's list is a popover hanging off the control, which has no
		// frame of its own to measure and needs none: that it is the anchored
		// one is the whole claim.
		if let active, active.isShown { return "anchored to the control" }
		return PalettePanel.placementForTesting(activePanel, over: activeParent)
	}

	private static func makeController(
		currentProject: Project?,
		owner: MainWindowController?,
		focus: Focus,
		runs: RunList?
	) -> SwitcherViewController {
		SwitcherViewController(currentProject: currentProject, owner: owner, focus: focus, runs: runs)
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

final class SwitcherViewController: NSViewController {
	enum Row {
		case action(title: String, symbol: String, shortcut: String?, detail: String?, handler: () -> Void)
		case header(String)
		case project(RecentProject, isOpen: Bool)
		case branch(String, isCurrent: Bool)
		/// A file in the open project, by its path relative to the root.
		case file(String)
		/// Something the project can run. `where` is the module it runs in,
		/// shown beside the name — two rows called `run Main` are told apart by
		/// nothing else.
		///
		/// The title is carried rather than taken from the configuration,
		/// because inside an opened goal it is not the name that varies: a
		/// hundred and eighty-four rows all reading `mvn package` with the
		/// module in the margin is the same word printed down the screen. There
		/// the place *is* the name, and the goal is in the row above.
		case run(RunConfiguration, title: String, where: String?, isCurrent: Bool)
		/// A goal that exists once per module, named once. `places` is how many
		/// there are, so the row can say so rather than hiding it.
		case goal(RunPicker.Goal)

		var isSelectable: Bool {
			if case .header = self { return false }
			return true
		}

		var height: CGFloat { Theme.current.scaled(26) }
	}

	var onDismiss: (() -> Void)?
	/// How tall the list wants to be, for a window that has to be told —
	/// `NSPopover` watches `preferredContentSize` itself; a panel does not.
	var onWantedSize: ((NSSize) -> Void)?

	let currentProject: Project?
	/// The window the choice was made in, which is the one that changes
	/// project unless the setting says to open another.
	weak var owner: MainWindowController?
	var rows: [Row] = []
	var tableView: NSTableView!
	var filterField: NSSearchField!
	/// What the user has typed. Empty shows the full menu.
	var filterText = ""

	/// The current repository's branches, and where it lives on the web. Both
	/// arrive after the popover is on screen — git is asked once, and the list
	/// is rebuilt when it answers.
	var branches: [String] = []
	/// When each branch came to be, for the newest-first order.
	var branchDates: [String: Date] = [:]
	var currentBranch: String?
	var forge: GitForge.Repository?

	let focus: ProjectSwitcherPopover.Focus
	/// The branch git treats as this repository's default, once asked.
	var defaultBranch: String?

	/// What the project can run, when this is the run control's popover.
	let runs: ProjectSwitcherPopover.RunList?
	/// The goal whose modules are being shown, when one has been opened.
	var openGoal: RunPicker.Goal?

	/// The files matching what has been typed, and the query they answer.
	///
	/// Kept beside the rows rather than looked up while building them, because
	/// the lookup is an `await` into the index actor and building rows is not
	/// async — and must not become so. `filesQuery` is what makes a late answer
	/// safe to drop: two keystrokes in flight land in whatever order they land.
	var fileMatches: [String] = []
	var filesQuery: String?
	/// Whether the index has finished its first build. Until it has, the heading
	/// says so — an empty list under "Files" reads as "there is no such file",
	/// which is a different and wrong answer.
	var filesAreReady = false
	var fileSearch: Task<Void, Never>?

	init(
		currentProject: Project?,
		owner: MainWindowController?,
		focus: ProjectSwitcherPopover.Focus = .everything,
		runs: ProjectSwitcherPopover.RunList? = nil
	) {
		self.currentProject = currentProject
		self.owner = owner
		self.focus = focus
		self.runs = runs
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Asks git what this repository has, once, and rebuilds when it answers.
	func readRepository() {
		guard let root = currentProject?.root else { return }
		Task { @MainActor [weak self] in
			async let names = BranchMenu.branches(in: root)
			async let current = BranchMenu.currentBranch(in: root)
			async let repository = GitForge.repository(in: root)
			// Asked alongside the rest rather than after it: it is one more
			// `symbolic-ref`, and the whole point of pinning the default is that
			// it is there when the list first draws.
			async let fallback = BranchGrouping.defaultBranch(in: root)

			let (branches, head, forge, main) = await (names, current, repository, fallback)
			guard let self, self.isViewLoaded else { return }
			self.branches = branches.names
			self.branchDates = branches.created
			self.currentBranch = head
			self.forge = forge
			self.defaultBranch = main
			// The branch list is the whole popover when that is what was opened,
			// so it always redraws; everywhere else only the filtered list shows
			// any of this, and there is nothing to redraw until something has
			// been typed.
			if case .everything = self.focus, self.filterText.isEmpty { return }
			self.buildRows()
			self.tableView.reloadData()
			self.updatePreferredSize()
		}
	}

	override func loadView() {
		buildRows()
		readRepository()
		prepareFiles()

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
		field.placeholderString = switch focus {
		case .branches: "Filter branches"
		case .runs: "Filter runs  ·  module/goal"
		case .everything: "Search  ·  > actions  ·  : line"
		}
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
	func updatePreferredSize() {
		let contentHeight = rows.reduce(0) { $0 + $1.height } + Theme.current.scaled(52)
		preferredContentSize = NSSize(
			width: Theme.current.scaled(340),
			height: min(max(contentHeight, Theme.current.scaled(120)), Theme.current.scaled(560))
		)
		onWantedSize?(preferredContentSize)
	}

	/// Checkouts found by scanning, refreshed in the background.
	///
	/// Cached on the type rather than the popover: the popover is rebuilt on
	/// every open, and a fresh scan each time would make the first frame wait on
	/// the file system.
	enum DiscoveryCache {
		static var projects: [RecentProject] = []
		static var isScanning = false

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
	func discoveredProjects(excluding paths: Set<String>) -> [RecentProject] {
		DiscoveryCache.current.filter { !paths.contains($0.path) }
	}

}

import AppKit
import AbydosKit

/// The project window: titlebar pills, the left tool strip, the navigator, and
/// the editor area.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
	private(set) var project: Project?

	/// What each project had open, so going back to one looks as it was left.
	private var sessions = ProjectSessions()
	/// Whether the window follows the terminal's working directory.
	/// Whether this window follows the terminal into another project.
	///
	/// Starts from the setting and is a per-window switch afterwards: one
	/// window following a terminal about while another stays where it was put
	/// is a reasonable way to work.
	private(set) var followsTerminal = Settings.shared.followsTerminalProject

	/// True for a window made by dragging a tab out of another one.
	///
	/// Such a window exists only to hold what was dragged into it, so it closes
	/// once that is gone — dragging the last tab back should not leave an empty
	/// window behind. It is also passed over when looking for the window that
	/// already has a project open, so opening that project focuses the original.
	private(set) var isTornOff = false

	/// A tab was dragged clear of every window and needs one of its own.
	var onTearOffTab: ((EditorViewController.Tab, NSPoint, MainWindowController) -> Void)?

	func markAsTornOff() { isTornOff = true }

	// MARK: - Testing

	func openForTesting(_ url: URL) { editor.open(fileURL: url, focusEditor: true) }
	func tearOffForTesting(index: Int, at screenPoint: NSPoint) {
		editor.tearOffForTesting(index: index, at: screenPoint)
	}
	func dropForTesting(payload: EditorTabDrag.Payload, at index: Int) {
		editor.dropForTesting(payload: payload, at: index)
	}
	var activeGroupIDForTesting: UUID? { editor.activeGroupID }
	var tabCountForTesting: Int { editor.activeTabCount }

	/// Rings the bell, as a program printing \u{07} would.
	func ringTerminalBellForTesting() {
		setPanelVisible(true)
		bottomPanel.showTerminal()?.terminalView.writeForTesting("\u{07}")
	}

	/// Draws the terminal through Metal and writes the result out.
	func renderTerminalWithMetal(to path: String) {
		setPanelVisible(true)
		guard let terminal = bottomPanel.showTerminal()?.terminalView else {
			print("METAL: no terminal")
			return
		}
		terminal.layoutSubtreeIfNeeded()
		let ok = terminal.renderWithMetalForTesting(to: path)
		print("METAL: \(ok ? "wrote \(path)" : "failed")")
	}

	/// Times a full terminal redraw, which is what every byte of output costs
	/// once the screen has to be shown again.
	func benchmarkTerminalRendering() {
		setPanelVisible(true)
		guard let terminal = bottomPanel.showTerminal()?.terminalView else {
			print("BENCH render: no terminal")
			return
		}

		// A screenful of coloured text, as a busy program produces.
		// Two shapes of screen. Ordinary output holds a colour for a whole line,
		// so a row is a handful of runs; the fire benchmark changes colour on
		// every cell, so a row is as many runs as it has columns. Whether that
		// distinction costs anything is the question.
		let fireLike = ProcessInfo.processInfo.environment["ABYDOS_BENCH_FIRE"] != nil
		var filler = ""
		for row in 0..<40 {
			if fireLike {
				for column in 0..<198 {
					filler += "\u{1B}[38;5;\((row * 7 + column) % 256);48;5;\((column * 3) % 256)m▀"
				}
			} else {
				filler += "\u{1B}[3\(row % 8)m"
				filler += String(repeating: "abcdefghij ", count: 18)
			}
			filler += "\u{1B}[0m\r\n"
		}
		terminal.writeForTesting(filler)
		terminal.layoutSubtreeIfNeeded()

		// A fixed 40-row screenful, so the number means the same thing whatever
		// height the panel happens to have been left at.
		let rowHeight = terminal.bounds.height / CGFloat(max(1, terminal.totalRowsForTesting))
		let bounds = NSRect(x: 0, y: 0, width: terminal.bounds.width, height: rowHeight * 40)
        guard bounds.width > 1, bounds.height > 1,
              let rep = terminal.bitmapImageRepForCachingDisplay(in: bounds) else {
			print("BENCH render: no drawable size \(bounds)")
			return
		}

		// One pass first, so one-off font and colour setup is not counted.
		terminal.cacheDisplay(in: bounds, to: rep)

		// Best of several rounds. A machine doing anything else moves the mean
		// by a factor of two, which is more than most of the changes worth
		// measuring; the least interrupted round is far steadier.
		let frames = 30
		var perFrame = Double.greatestFiniteMagnitude
		for _ in 0..<8 {
			let start = Date()
			for _ in 0..<frames { terminal.cacheDisplay(in: bounds, to: rep) }
			perFrame = min(perFrame, -start.timeIntervalSinceNow / Double(frames) * 1000)
		}
		print("BENCH render: \(String(format: "%.2f", perFrame)) ms/frame "
			+ "(\(String(format: "%.0f", 1000 / perFrame)) fps ceiling) at \(Int(bounds.width))x\(Int(bounds.height))")

		// What a printed line actually costs now that only what changed is
		// painted: one row rather than the whole screen.
		let rowHeightPoints = bounds.height / 40
		let rowRect = NSRect(x: 0, y: 0, width: bounds.width, height: rowHeightPoints)
		guard let rowRep = terminal.bitmapImageRepForCachingDisplay(in: rowRect) else { return }
		terminal.cacheDisplay(in: rowRect, to: rowRep)

		var perRow = Double.greatestFiniteMagnitude
		for _ in 0..<8 {
			let rowStart = Date()
			for _ in 0..<frames { terminal.cacheDisplay(in: rowRect, to: rowRep) }
			perRow = min(perRow, -rowStart.timeIntervalSinceNow / Double(frames) * 1000)
		}
		print("BENCH render: \(String(format: "%.3f", perRow)) ms for one row "
			+ "(\(String(format: "%.0f", perFrame / perRow))x cheaper than a full frame)")
	}

	/// Takes a tab dragged out of another window.
	func adopt(_ tab: EditorViewController.Tab) {
		editor.adopt(tab)
	}
	var onClose: (() -> Void)?

	private let navigator = ProjectNavigatorViewController()
	/// The editor area, which may hold several split groups.
	private let editor = EditorAreaController()
	private let toolStrip = ToolWindowBar()
	private let bottomPanel = BottomPanel()

	private var splitView: NSSplitView!
	private var verticalSplitView: NSSplitView!
	/// How wide the tree is, kept as a constraint so nothing else decides.
	private var navigatorWidthConstraint: NSLayoutConstraint!
	private var panelHeight: CGFloat = 260
	/// True while the panel is being rounded to whole rows, so the resize that
	/// causes cannot ask for another one.
	fileprivate var isSnappingPanel = false
	private var navigatorContainer: ColoredView!
	private var changesPane: ChangesPane?
	private var branchesPane: BranchesPane?
	private var structurePane: StructurePane?
	private var scratchesPane: ScratchesPane?
	private var historyPane: HistoryPane?
	private var primaryToolView: NSView?
	private var primaryToolTop: NSLayoutConstraint?
	private var primaryContainer: NSView!
	/// The pane below the sidebar's tool, for anything docked there.
	private var dockContainer: ColoredView!
	private var sidebarSplit: NSSplitView!
	/// What is docked, so it can be swapped or sent back to a window.
	private var dockedView: NSView?
	private(set) var currentSidebarTool: SidebarToolKind = .project
	/// Height the titlebar covers, applied to sidebar panes that do not inset
	/// themselves.
	private var sidebarTopInset: CGFloat = 0
	private var runControl: RunControl?
	/// The terminal a launch configuration is running in, so the play button can
	/// become a stop button that stops the right thing.
	private weak var runningPane: TerminalPane?
	/// Painted behind the toolbar, since the titlebar itself is transparent.
	/// Everywhere the editor has been, and where in it we are.
	private var navigation = NavigationHistory()
	/// Set while going back or forward, so retracing steps is not itself a step.
	private var isNavigatingHistory = false

	/// Watches `.git` so a commit made in a terminal shows up here.
	private var repositoryWatcher: RepositoryWatcher?
	private var titlebarBackdrop: ColoredView?
	private var titlebarBackdropHeight: NSLayoutConstraint?
	private var titlebarSeam: TitlebarSeam?
	/// Held while open: the panel is a child window and nothing else owns it.
	/// Held while open, for the same reason.
	private var processPicker: ProcessPicker?
	/// What the run control acts on, remembered per project.
	///
	/// Written down as it changes rather than at quit. A window that never gets
	/// to say goodbye — a crash, a force quit, a capture run — should still
	/// come back pointing at whatever was last run from it.
	private var selectedConfigurationName: String? {
		didSet {
			guard selectedConfigurationName != oldValue else { return }
			rememberOpenEditors()
		}
	}
	private var capsule: TitlebarCapsule!
	private var subprojectPill: SubprojectPillButton!
	/// Reading the repository, as a job rather than an answer.
	///
	/// The toolbar builds its items when it chooses, and in a repository small
	/// enough git answers first — so a pill that is only ever *told* the branch
	/// misses it. Anything that needs the branch awaits this instead, whenever
	/// it happens to come into existence.
	private var branchRead: Task<String?, Never>?
	private var titlebarContainer: NSView?
	private var toolStripWidthConstraint: NSLayoutConstraint!

	private var navigatorWidth: CGFloat = 260

	/// Go to a symbol by name.
	private lazy var symbolPalette: SymbolPalette = {
		let palette = SymbolPalette()
		palette.provider = { [weak self] query, scope in
			await self?.symbols(matching: query, scope: scope) ?? []
		}
		palette.emptyReason = { [weak self] query, scope in
			self?.reasonForNoSymbols(query: query, scope: scope) ?? ""
		}
		palette.onOpen = { [weak self] location in
			guard let url = location.url else { return }
			self?.editor.open(fileURL: url, atLine: location.range.start.line + 1)
		}
		return palette
	}()

	/// Where everywhere-this-is-used is listed.
	private lazy var usagesPanel: UsagesPanel = {
		let panel = UsagesPanel()
		panel.onOpen = { [weak self] location in
			guard let url = location.url else { return }
			self?.editor.open(fileURL: url, atLine: location.range.start.line + 1)
		}
		panel.onDock = { [weak self] view, title in
			self?.dockInSidebar(view, title: title)
		}
		return panel
	}()

	/// Where news the user did not ask for goes.
	private lazy var toasts = ToastPresenter(window: window)

	/// Says something without stopping anything.
	///
	/// Automatic modals are banned here: they take the keyboard and demand
	/// dismissal for news as small as "no go.mod in this project". A toast
	/// says it in the corner and opens the details if it turns out to matter.
	func notify(
		_ title: String,
		detail: String? = nil,
		kind: Toast.Kind = .error,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) {
		toasts.show(Toast(
			kind: kind, title: title, detail: detail, actionTitle: actionTitle, action: action
		))
	}

	// MARK: - Claude sessions in the terminal

	/// The tmux session the panel's tabs are showing, if they are showing one.
	var mirroredTmuxSession: String? { bottomPanel.mirroredTmuxSession }

	/// Which of those windows is the active one.
	var activeTmuxWindow: Int? { bottomPanel.activeTmuxWindow }

	/// Drags a tmux tab from one position to another.
	func dragTmuxTabForTesting(from: Int, to: Int) {
		bottomPanel.dragTmuxTabForTesting(from: from, to: to)
	}

	/// Presses the + on tmux's strip, for testing what it does.
	func addTmuxWindowForTesting() { bottomPanel.addTmuxWindowForTesting() }

	/// Closes a tmux tab from its menu, for testing what it does.
	func closeTmuxTabForTesting(_ index: Int) {
		bottomPanel.closeTmuxTabForTesting(index)
	}

	/// Presses the + on the terminal strip, for testing what it does.
	/// Panes in the panel, for proving the tmux + added none.
	var paneCountForTesting: Int { bottomPanel.paneCountForTesting }

	func addTerminalTabForTesting() {
		bottomPanel.addTabForTesting()
	}

	func closeTerminalTabsForTesting() {
		bottomPanel.closeTerminalTabsForTesting()
	}

	func clickPanelTabForTesting(_ index: Int) -> String {
		bottomPanel.clickPanelTabForTesting(index)
	}

	/// Brings a tmux window forward, as clicking its tab would.
	func revealTmuxWindow(_ index: Int) {
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		bottomPanel.revealTmuxWindow(index)
	}

	/// Shows a toast raised from somewhere with no window of its own.
	///
	/// Exactly one window says it, so a message does not appear three times on
	/// a machine with three of them open.
	@objc private func toastPosted(_ notification: Notification) {
		guard speaksForTheApp, let toast = notification.userInfo?["toast"] as? Toast else { return }
		toasts.show(toast)
	}

	/// Whether this window is the one to say something the whole app has to
	/// say.
	///
	/// The key window when there is one. When there is not — the app is in the
	/// background, which is exactly where it is while a language server takes
	/// its first few seconds to fail — the frontmost window says it instead,
	/// and it is still there when somebody comes back. "Only the key window"
	/// meant that news dropped silently whenever nobody was looking, which is
	/// most of the time news arrives.
	private var speaksForTheApp: Bool {
		guard let window else { return false }
		if let key = NSApp.keyWindow { return window === key }
		if let main = NSApp.mainWindow { return window === main }
		return window === NSApp.orderedWindows.first(where: { $0.isVisible })
	}

	// MARK: - Init

	init() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
			// fullSizeContentView lets the split view run up behind the titlebar,
			// which is what makes the sidebar meet the toolbar the way IDEA's does.
			styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.titleVisibility = .hidden
		// Transparent so the titlebar shows what the content view paints there
		// — which is a strip this app owns, and can colour while a program is
		// running.
		window.titlebarAppearsTransparent = true
		window.backgroundColor = Theme.current.windowBackground
		window.tabbingMode = .disallowed

		// Centred, then the autosaved frame restores over it if there is one.
		// Setting the autosave name first would let AppKit place the window at
		// the bottom-left default before any frame is restored, which is where
		// a second window with no saved frame of its own would land.
		window.center()
		// The stored names keep their old spelling on purpose. They are the keys
		// a saved window frame and split position live under, so changing them
		// moves everybody's window and panes back to the defaults the first time
		// they open the app after the rename — a rename should not rearrange
		// somebody's desk.
		window.setFrameAutosaveName("IdeaiMainWindow")

		// A second window must not sit exactly on top of the first, so AppKit
		// steps it down and across from whatever is already open.
		if NSApp.windows.contains(where: { $0.isVisible && $0 !== window }) {
			window.setFrameOrigin(window.cascadeTopLeft(from: .zero))
		}

		super.init(window: window)
		window.delegate = self

		buildContent()
		buildToolbar()
		buildTitlebarBackdrop()

		editor.onNavigated = { [weak self] departure, arrival in
			guard let self, !self.isNavigatingHistory else { return }
			// The place being left is recorded first, and at the line the caret
			// was actually on — otherwise going back returns to wherever that
			// file happened to open, which is rarely where you were reading.
			if let departure { self.navigation.record(departure) }
			self.navigation.record(arrival)
		}

		// Preference changes apply live rather than on next launch.
		NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.applySettings()
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Layout

	private func buildContent() {
		let root = ColoredView(color: Theme.current.windowBackground)
		root.colourSource = { Theme.current.windowBackground }

		toolStrip.onToggleNavigator = { [weak self] in self?.showSidebarTool(.project) }
		toolStrip.onToggleTerminal = { [weak self] in self?.toggleTerminal(nil) }
		toolStrip.onReviewBranch = { [weak self] in self?.reviewBranch(nil) }
		toolStrip.onReviewUncommitted = { [weak self] in self?.reviewUncommittedChanges(nil) }
		toolStrip.onToggleChanges = { [weak self] in self?.showSidebarTool(.changes) }
		toolStrip.onToggleBranches = { [weak self] in self?.showSidebarTool(.branches) }
		toolStrip.onToggleStructure = { [weak self] in self?.showSidebarTool(.structure) }
		toolStrip.onToggleScratches = { [weak self] in self?.showSidebarTool(.scratches) }
		toolStrip.onToggleHistory = { [weak self] in self?.showSidebarTool(.history) }
		NotificationCenter.default.addObserver(
			self, selector: #selector(toastPosted(_:)), name: .abydosToast, object: nil
		)

		toolStrip.onToggleDebug = { [weak self] in self?.showDebugPanel(nil) }
		toolStrip.isDebugRunning = { [weak self] in self?.bottomPanel.activeDebugSession != nil }
		toolStrip.isGoProject = { [weak self] in
			guard let root = self?.project?.root else { return false }
			return GoTooling.isGoModule(root) || !RunConfigurationDiscovery
				.searchDirectories(from: root)
				.filter(GoTooling.isGoModule)
				.isEmpty
		}
		toolStrip.onDebugGoPackage = { [weak self] in self?.goDebug(nil) }
		toolStrip.onDebugExecutable = { [weak self] in self?.debugExecutable(nil) }
		toolStrip.onAttachToProcess = { [weak self] in self?.attachToProcess(nil) }

		navigatorContainer = ColoredView(color: Theme.current.sidebarBackground)
		navigatorContainer.colourSource = { Theme.current.sidebarBackground }

		// The sidebar is two stacked panes: the tool on top, and whatever has
		// been docked underneath it. The lower one takes no room until
		// something is in it.
		let sidebarSplit = ThinDividerSplitView()
		sidebarSplit.isVertical = false
		sidebarSplit.dividerStyle = .thin
		sidebarSplit.translatesAutoresizingMaskIntoConstraints = false
		navigatorContainer.addSubview(sidebarSplit)
		NSLayoutConstraint.activate([
			sidebarSplit.topAnchor.constraint(equalTo: navigatorContainer.topAnchor),
			sidebarSplit.bottomAnchor.constraint(equalTo: navigatorContainer.bottomAnchor),
			sidebarSplit.leadingAnchor.constraint(equalTo: navigatorContainer.leadingAnchor),
			sidebarSplit.trailingAnchor.constraint(equalTo: navigatorContainer.trailingAnchor),
		])

		let toolContainer = ColoredView(color: Theme.current.sidebarBackground)
		toolContainer.colourSource = { Theme.current.sidebarBackground }
		dockContainer = ColoredView(color: Theme.current.sidebarBackground)
		dockContainer.colourSource = { Theme.current.sidebarBackground }
		dockContainer.isHidden = true
		sidebarSplit.addArrangedSubview(toolContainer)
		sidebarSplit.addArrangedSubview(dockContainer)
		self.sidebarSplit = sidebarSplit

		primaryContainer = toolContainer

		primaryContainer.addSubview(navigator.view)
		navigator.view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			navigator.view.topAnchor.constraint(equalTo: primaryContainer.topAnchor),
			navigator.view.bottomAnchor.constraint(equalTo: primaryContainer.bottomAnchor),
			navigator.view.leadingAnchor.constraint(equalTo: primaryContainer.leadingAnchor),
			navigator.view.trailingAnchor.constraint(equalTo: primaryContainer.trailingAnchor),
		])
		primaryToolView = navigator.view

		splitView = ThinDividerSplitView()
		splitView.isVertical = true
		splitView.dividerStyle = .thin
		splitView.addArrangedSubview(navigatorContainer)
		splitView.addArrangedSubview(editor.view)
		splitView.autosaveName = "IdeaiSplit"
		// The tree keeps the width it was given; the editor takes the rest.
		// Without this the split view re-divides whenever what is in the editor
		// changes shape — and opening a page of controls made the tree jump
		// wider, which is not what opening a page means.
		splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
		splitView.setHoldingPriority(.defaultLow + 10, forSubviewAt: 1)

		// The tree is as wide as it was left, said as a constraint rather than
		// left to the split view to work out. Whatever is in the editor changes
		// shape — a page of controls, a wide file, a diff — and every time it
		// did, the split view re-divided the window and the tree jumped.
		navigatorWidthConstraint = navigatorContainer.widthAnchor
			.constraint(equalToConstant: navigatorWidth)
		navigatorWidthConstraint.priority = .defaultHigh
		navigatorWidthConstraint.isActive = true
		splitView.delegate = self

		// The tree's own contents must not be able to demand a width. A row
		// showing a long path has an enormous natural size, and any layout pass
		// that consults it — such as the one that happens when a page opens in
		// the editor — would widen the tree to fit a path that is meant to be
		// truncated.
		for view in [navigatorContainer, navigator.view] as [NSView] {
			view.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
		}

		// The panel spans the full width below both the tree and the editor,
		// which is where IDEA puts its tool windows.
		verticalSplitView = ThinDividerSplitView()
		verticalSplitView.isVertical = false
		verticalSplitView.dividerStyle = .thin
		verticalSplitView.addArrangedSubview(splitView)
		verticalSplitView.addArrangedSubview(bottomPanel)
		verticalSplitView.autosaveName = "IdeaiPanelSplit"
		// For `splitViewDidResizeSubviews`, which rounds the panel down to
		// whole terminal rows.
		verticalSplitView.delegate = self

		bottomPanel.onRequestHide = { [weak self] in self?.setPanelVisible(false) }
		bottomPanel.onToggleMaximize = { [weak self] in self?.togglePanelMaximized() }
		// Written when they change rather than only on the way out: a terminal
		// that survives a restart has to survive the kind of exit nobody plans.
		bottomPanel.onTerminalsChanged = { [weak self] in self?.rememberOpenEditors() }
		bottomPanel.onTearOffTerminal = { [weak self] detached, screenPoint in
			self?.openTerminalWindow(detached, at: screenPoint)
		}
		// The setting decides how a window starts; the control on the panel is
		// what changes it afterwards.
		bottomPanel.isFollowingProject = followsTerminal
		bottomPanel.onToggleFollowProject = { [weak self] in self?.toggleFollowTerminal() }
		bottomPanel.onWorkingDirectoryChanged = { [weak self] directory in
			self?.terminalDirectoryChanged(to: directory)
		}
		// A finding opens the file at its line, in the editor above the panel.
		bottomPanel.onOpenSymbol = { [weak self] frame in
			guard let self else { return }
			// The profiler knows a name, not a place; the symbol search is what
			// turns one into the other.
			self.symbolPalette.show(
				scope: .workspace,
				query: ProfileFrame.symbolName(in: frame),
				over: self.window
			)
		}
		// The debugger's own toolbar, once the program has ended: whatever the
		// play button up in the titlebar would start is what these start too.
		// A run or a debugger brought forward takes the window back to the
		// project it belongs to — while the window is following its terminal,
		// which is the only time it is anywhere else.
		bottomPanel.onPaneNeedsProject = { [weak self] root in
			guard let self, self.followsTerminal else { return }
			// Following, so the same rule as a shell that moved: the panel is
			// where the change came from and is not to be moved by it.
			self.switchProject(to: root, followingTerminal: true)
		}
		bottomPanel.onRunAgain = { [weak self] in self?.runSelectedConfiguration(debug: false) }
		bottomPanel.onDebugAgain = { [weak self] in self?.runSelectedConfiguration(debug: true) }
		bottomPanel.onOpenFinding = { [weak self] url, line in
			self?.editor.open(fileURL: url, atLine: line)
		}
		// Set synchronously, not deferred: anything that opens the panel during
		// launch would otherwise be undone when the deferred block ran.
		bottomPanel.isHidden = true

		root.addSubview(toolStrip)
		root.addSubview(verticalSplitView)
		toolStrip.translatesAutoresizingMaskIntoConstraints = false
		verticalSplitView.translatesAutoresizingMaskIntoConstraints = false

		toolStripWidthConstraint = toolStrip.widthAnchor.constraint(equalToConstant: ToolWindowBar.width)

		NSLayoutConstraint.activate([
			toolStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			toolStrip.topAnchor.constraint(equalTo: root.topAnchor),
			toolStrip.bottomAnchor.constraint(equalTo: root.bottomAnchor),
			toolStripWidthConstraint,

			verticalSplitView.leadingAnchor.constraint(equalTo: toolStrip.trailingAnchor),
			verticalSplitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
			verticalSplitView.topAnchor.constraint(equalTo: root.topAnchor),
			verticalSplitView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
		])

		window?.contentView = root

		// A click in the tree opens provisionally and keeps focus in the tree;
		// Return or a double-click pins the tab and moves focus to the editor.
		navigator.onSelectFile = { [weak self] url, focusEditor in
			guard let self else { return }
			// Only when it is being opened to look at: arrowing through the
			// tree in a popover should not throw the terminal out of the window
			// on the way past.
			if focusEditor { self.leaveTerminalFullScreen() }
			self.editor.open(fileURL: url, focusEditor: focusEditor, preview: !focusEditor)
		}
		navigator.onOpenTerminal = { [weak self] directory in
			self?.openTerminal(in: directory)
		}
		navigator.onOpenSubproject = { [weak self] url in self?.openSubproject(at: url) }
		navigator.onLeaveSubproject = { [weak self] in self?.leaveSubproject() }
		navigator.onPreviewModel = { url in
			MainWindowController.previewModel(at: url)
		}
		navigator.currentEditorFile = { [weak self] in self?.editor.activeGroup?.activeTabURL }
		// The tree reads the working copy's status anyway; the strip shows it.
		navigator.onChangeCount = { [weak self] count in
			guard let self else { return }
			self.toolStrip.uncommittedCount = count
			// What is committed but not sent is worth the same glance: the
			// same read the push button uses, on the same occasion the tree
			// reads the working copy.
			Task { @MainActor in
				guard let root = self.scopeRoot ?? self.project?.root else { return }
				let state = await GitPush.state(in: root)
				self.toolStrip.unpushedCount = state?.ahead ?? 0
			}
		}
		navigator.onFilesChanged = { [weak self] in
			// Something wrote inside the project — possibly a file that is open.
			self?.editor.reloadExternallyChangedFiles()
			self?.changesPane?.refresh()
			// A new main.go or Makefile target should get its play button
			// without reopening the project.
			self?.refreshRunConfigurations()
		}
		// Switching tabs moves the tree's selection to match.
		editor.onTearOffTab = { [weak self] tab, screenPoint in
			guard let self else { return }
			onTearOffTab?(tab, screenPoint, self)
		}
		editor.onBecameEmpty = { [weak self] in
			guard let self, isTornOff else { return }
			// Nothing left in the window that was made to hold it.
			window?.close()
		}
		editor.onActiveFileChanged = { [weak self] url in
			// The outline belongs to the file in front, so it follows the tabs.
			self?.refreshStructure()
			// The history offers to narrow itself to whatever is in front.
			self?.historyPane?.offerScope(path: self?.relativePathOfActiveFile())
			guard let url else { return }
			self?.navigator.selectWithoutOpening(url: url)
		}
		// Clicking the breakpoint gutter reaches the running debug session, and
		// is remembered even when nothing is running yet.
		editor.onFindUsages = { [weak self] url, line, character in
			self?.findUsages(in: url, line: line, character: character)
		}
		editor.onWatch = { [weak self] expression in
			self?.watchFromEditor(expression)
		}
		editor.onFixWithAI = { [weak self] url, line, diagnostic in
			self?.fixWithAI(url: url, line: line, diagnostic: diagnostic)
		}
		editor.onEditBreakpoint = { [weak self] url, line in
			self?.editBreakpoint(file: url, line: line)
		}
		editor.onToggleBreakpoint = { [weak self] url, line in
			self?.toggleBreakpoint(file: url, line: line)
		}
		editor.onSetBreakpointEnabled = { [weak self] url, line, enabled in
			self?.setBreakpoint(file: url, line: line, enabled: enabled)
		}
		editor.onDeleteBreakpoint = { [weak self] url, line in
			self?.deleteBreakpoint(file: url, line: line)
		}
		editor.onSetOtherBreakpointsEnabled = { [weak self] url, line, enabled in
			self?.setOtherBreakpoints(file: url, line: line, enabled: enabled)
		}
		editor.onLinesChanged = { [weak self] url, first, removed, inserted in
			self?.moveBreakpoints(inFile: url, editedFrom: first, removed: removed, inserted: inserted)
		}
		editor.onFileReloaded = { [weak self] url in
			self?.reanchorBreakpoints(inFile: url)
		}
		editor.onRunLine = { [weak self] url, line in
			self?.runConfiguration(forFile: url, line: line)
		}
		editor.onApplyDiffSelection = { [weak self] change, diff, selected in
			self?.applyDiffSelection(change: change, diff: diff, lines: selected)
		}
		editor.onDiscardDiffSelection = { [weak self] change, diff, selected in
			self?.discardDiffSelection(change: change, diff: diff, lines: selected)
		}

		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.splitView.setPosition(self.navigatorWidth, ofDividerAt: 0)
			self.verticalSplitView.adjustSubviews()
		}
	}

	// MARK: - Titlebar

	/// Puts the pills in a real `NSToolbar`.
	///
	/// macOS 26 draws a rounded capsule behind custom-view toolbar items and
	/// there is no opt-out — `NSToolbarItemStyle` offers only plain and
	/// prominent. The alternatives are worse: a titlebar accessory has no
	/// capsule but the window then falls back to the old, smaller corner radius,
	/// and an *empty* toolbar plus an accessory reserves a second titlebar row.
	/// Keeping the toolbar keeps the modern window shape and a single row, so
	/// the capsule is the accepted cost.
	/// Watches the repository behind a project, and tells the views that show
	/// it when it moves.
	private func startWatchingRepository(at root: URL) {
		repositoryWatcher?.stop()
		repositoryWatcher = nil

		// Weak the whole way down. Binding self strongly out here and asking
		// for a weak one again inside would keep the window alive for as long
		// as the lookup takes and read as though it did not.
		Task { @MainActor [weak self] in
			guard let directory = await RepositoryWatcher.directory(forRepositoryAt: root),
			      // Another project may have been opened while this was asked.
			      self?.project?.root == root
			else { return }

			let watcher = RepositoryWatcher(gitDirectory: directory) { [weak self] in
				guard let self, let current = self.project else { return }
				NotificationCenter.default.post(
					name: .abydosRepositoryChanged, object: current.root
				)
				self.navigator.refreshGitStatus()
				// The branch itself may be what changed — a checkout in a
				// terminal is exactly the case this watcher exists for.
				Task { @MainActor in
					await current.loadGit()
					self.capsule?.setBranch(await current.git?.currentBranch())
					self.layoutTitlebarPills()
				}
			}
			watcher.start()
			self?.repositoryWatcher = watcher
		}
	}

	/// The strip the toolbar sits on.
	///
	/// The window is `fullSizeContentView`, so the area behind the titlebar is
	/// ours to paint; with a transparent titlebar this is what shows there.
	private func buildTitlebarBackdrop() {
		guard let contentView = window?.contentView else { return }
		// Always drawn, so the titlebar is one strip across the whole window:
		// the panes below run up behind it and their edges would otherwise
		// show through, with the sidebar's colour meeting the editor's part
		// way along a row that belongs to neither.
		let backdrop = ColoredView(color: Theme.current.windowBackground)
		backdrop.actsAsTitlebar = true
		backdrop.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(backdrop, positioned: .above, relativeTo: nil)

		let height = backdrop.heightAnchor.constraint(equalToConstant: 0)
		NSLayoutConstraint.activate([
			backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
			backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			height,
		])
		titlebarBackdrop = backdrop
		titlebarBackdropHeight = height

		// The line along the bottom of the strip, which is both the boundary
		// under the titlebar and the only thing in the window that says a run is
		// happening.
		let seam = TitlebarSeam()
		seam.translatesAutoresizingMaskIntoConstraints = false
		backdrop.addSubview(seam)
		NSLayoutConstraint.activate([
			seam.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
			seam.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
			seam.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
			seam.heightAnchor.constraint(equalToConstant: TitlebarSeam.height),
		])
		titlebarSeam = seam
	}

	/// Says what the run is doing, on the line under the titlebar.
	private func setTitlebarRunState(_ state: TitlebarSeam.State) {
		guard let backdrop = titlebarBackdrop else { return }
		// Everything added since sits above it, so it is raised each time
		// rather than once.
		backdrop.superview?.addSubview(backdrop, positioned: .above, relativeTo: nil)
		titlebarSeam?.set(state)
	}

	private func buildToolbar() {
		let toolbar = NSToolbar(identifier: "IdeaiToolbar")
		toolbar.delegate = self
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = false
		window?.toolbar = toolbar
		// .unified keeps the items on the traffic-light row rather than in a
		// second bar below it — the arrangement in the reference screenshot.
		window?.toolbarStyle = .unified
	}

	/// Re-measures the pills after their content changes, so the toolbar item
	/// grows to fit a longer project name or a branch that arrived late.
	private func layoutTitlebarPills() {
		// The height is a constraint rather than an intrinsic size, because that
		// is the only part of a toolbar item's size the toolbar reads, so the
		// zoom has to be pushed into it by hand.
		capsule?.updateHeight()
		capsule?.invalidateIntrinsicContentSize()
		subprojectPill?.invalidateIntrinsicContentSize()
		// The run strip measures itself from the theme's scale, so it has to be
		// asked again — otherwise zooming the window leaves the one control
		// that is always on screen at the old size.
		runControl?.invalidateIntrinsicContentSize()
		runControl?.applyThemeChange()
	}

	/// Pushes the measured titlebar height down to the navigator and editor.
	///
	/// The window uses `fullSizeContentView`, so its content view runs up behind
	/// the titlebar and every child must inset itself. The height differs with
	/// and without a toolbar and changes in full screen, so it is measured rather
	/// than assumed — guessing it is what clipped the tab bar.
	private func updateTopInsets() {
		guard let window, let contentView = window.contentView else { return }
		let layoutRect = window.contentLayoutRect
		let inset = max(0, contentView.bounds.height - layoutRect.height - layoutRect.origin.y)

		titlebarBackdropHeight?.constant = inset
		// Views added after it would otherwise cover it.
		if let backdrop = titlebarBackdrop {
			backdrop.superview?.addSubview(backdrop, positioned: .above, relativeTo: nil)
		}
		navigator.setTopInset(inset)
		sidebarTopInset = inset
		if isPanelMaximized { bottomPanel.setTopInset(inset) }
		primaryToolTop?.constant = inset
		editor.setTopInset(inset)
		toolStrip.setTopInset(inset)
	}

	// MARK: - Loading

	/// The part of the project being worked on, when it is not the whole of it.
	///
	/// A repository is often not one thing: `ideai-examples` holds eight
	/// projects, a work checkout holds a service and its front end. The tree
	/// stays whole, because that is how somebody navigates — but everything
	/// scoped follows this: the launch configurations, the build's working
	/// directory, the work tree git acts on, the root the language server is
	/// given, and where a terminal opens.
	private(set) var subprojectRoot: URL?

	/// Where launch configurations are read from and written to.
	///
	/// The subproject when one is open: `ideai-examples` has eight sets of
	/// configurations, one per project in it, and the run button must offer
	/// the ones belonging to the part being worked on.
	var launchRoot: URL { subprojectRoot ?? project?.root ?? URL(fileURLWithPath: ".") }

	/// What scoped things work against.
	var scopeRoot: URL? { subprojectRoot ?? project?.root }

	/// Works on part of the project instead of the whole of it.
	func openSubproject(at url: URL) {
		guard let project else { return }
		guard Subprojects.resolve(Subprojects.relativePath(url, to: project.root), in: project.root) != nil
		else { return }
		guard url.path != subprojectRoot?.path else { return }

		subprojectRoot = url.standardizedFileURL
		applyScope()
	}

	/// Back to the whole project.
	func leaveSubproject() {
		guard subprojectRoot != nil else { return }
		subprojectRoot = nil
		applyScope()
	}

	/// Reads the repository for the current scope, and tells the window.
	///
	/// One task, kept: it is what the branch pill awaits when the toolbar gets
	/// around to building it.
	@discardableResult
	private func readGit() -> Task<String?, Never> {
		branchRead?.cancel()
		let read = Task { @MainActor [weak self] () -> String? in
			guard let self, let project = self.project else { return nil }
			await project.loadGit()
			return await project.git?.currentBranch()
		}
		branchRead = read

		Task { @MainActor [weak self] in
			let branch = await read.value
			guard let self, !Task.isCancelled else { return }
			self.capsule?.setBranch(branch)
			// The capsule only gets its width once it has a name to show.
			self.layoutTitlebarPills()
			self.navigator.refreshGitStatus()

			// Changes, history and branches hold on to one repository, so a
			// different work tree needs them built again.
			if self.currentSidebarTool == .changes || self.currentSidebarTool == .branches {
				self.install(tool: self.currentSidebarTool, force: true)
			}
			self.refreshRunConfigurations()
		}
		return read
	}

	/// Names the window after the repository rather than after the directory.
	///
	/// A linked worktree is another checkout of the same project, so
	/// `ideai/.claude/worktrees/titlebar-capsule` is still ideai — naming it
	/// after its folder would name the checkout and lose the project. The chip
	/// beside the name says which checkout it is.
	///
	/// Asked of git rather than read off the path: a worktree can be created
	/// anywhere, including outside the repository it belongs to.
	private func readWorktree() {
		guard let project else { return }
		let root = project.root

		Task { @MainActor [weak self] in
			let worktrees = await GitWorktrees.list(in: root)
			// Another project may have been opened while git was answering.
			guard let self, self.project?.root == root else { return }

			// The window may be opened at the worktree itself or somewhere
			// inside it, so the deepest one containing this root is the one.
			let containing = worktrees
				.filter { root.path == $0.path.path || root.path.hasPrefix($0.path.path + "/") }
				.max { $0.path.path.count < $1.path.path.count }

			guard let containing, !containing.isPrimary,
			      let primary = worktrees.first(where: { $0.isPrimary })
			else {
				self.capsule?.setWorktree(nil)
				self.layoutTitlebarPills()
				return
			}

			self.capsule?.setProject(name: primary.name)
			self.capsule?.setWorktree(containing.name)
			self.layoutTitlebarPills()
		}
	}

	/// Points everything scoped at the current scope.
	private func applyScope() {
		guard let project, let scope = scopeRoot else { return }

		// Set before anything reads it: a git load started for the whole project
		// may still be in flight, and both must look in the same place.
		project.scope = subprojectRoot

		selectedConfigurationName = nil
		refreshRunControl()
		LanguageService.shared.warmUp(project: scope)
		startWatchingRepository(at: scope)
		bottomPanel.setWorkingDirectory(scope)

		subprojectPill?.setSubproject(
			subprojectRoot.map { Subprojects.relativePath($0, to: project.root) }
		)
		layoutTitlebarPills()
		navigator.setSubproject(subprojectRoot)
		rememberOpenEditors()

		// Git is per work tree, and a subproject may be its own repository — a
		// checkout of several is the case this exists for.
		readGit()
	}

	func load(project: Project, focusTree: Bool = true) {
		self.project = project
		subprojectRoot = nil
		subprojectPill?.setSubproject(nil)
		window?.title = project.name

		// No badge and no colour: which project this is gets stated once, by the
		// name, and colour is kept for the switcher — where there is more than
		// one project on screen and it has something to tell apart.
		capsule?.setProject(name: project.name)
		capsule?.setWorktree(nil)
		capsule?.setBranch(nil)
		layoutTitlebarPills()
		readWorktree()

		navigator.load(project: project)
		editor.setProject(project)

		// A project brought in from a `.vscode/launch.json` keeps its
		// configurations once, so editing one here does not change a file the
		// rest of the team shares with another editor.
		if !AbydosFolder.exists(in: project.root) {
			_ = try? LaunchStore.importVSCode(in: project.root)
		}
		// Started now rather than when a file of that language is first opened,
		// so asking for a symbol straight after opening a project works.
		LanguageService.shared.warmUp(project: project.root)
		selectedConfigurationName = nil
		refreshRunControl()
		startWatchingRepository(at: project.root)
		scratchesPane?.setProject(project.root)
		bottomPanel.setWorkingDirectory(project.root)

		// What was open here last time, from the folder beside the project —
		// which is what makes opening it again feel like coming back rather
		// than starting.
		if let remembered = SessionStore.read(in: project.root) {
			if !editor.hasOpenFiles { editor.restore(remembered) }
			// Where the work was left off, which for a repository of several
			// projects is as much a part of it as the open files.
			if let path = remembered.subprojectPath,
			   let url = Subprojects.resolve(path, in: project.root) {
				subprojectRoot = url
				applyScope()
			}
			// And what the play button was pointing at. Set before the
			// configurations have finished loading, which is fine: it is a
			// name, and the list is only needed when something is run.
			if let chosen = remembered.selectedConfiguration {
				selectedConfigurationName = chosen
				refreshRunControl()
			}
			xcodeDestinations = remembered.xcodeDestinations

			// The gutter, from what was there last time. Only when nothing has
			// set any yet: a window that already has breakpoints is one where
			// somebody has been working, and a file restored over that would
			// take them away.
			if pendingBreakpoints.isEmpty, !remembered.breakpoints.isEmpty {
				pendingBreakpoints = remembered.breakpoints
				showPendingBreakpoints()
			}
		}

		// The terminal is where half the work happens, so a window arrives with
		// it up — unless this project was left with it closed, which is a
		// decision and outlives the default.
		// One tmux session per project, for whoever asked for tmux at all.
		bottomPanel.tmuxSession = TmuxSessionName.of(project.root)

		// Once per window. Opening another project in the same window is not a
		// window opening, and having the terminal take the screen again — in
		// the middle of switching to something — is a jump nobody asked for.
		let wanted = hasArrangedTerminal ? "keep" : Settings.shared.terminalAtStartup
		hasArrangedTerminal = true
		if wanted != "closed", wanted != "keep" {
			// The setting is explicit and wins over what the project was last
			// left with: somebody who asked for the terminal to fill the window
			// asked for every window, not for the ones whose session happens to
			// agree.
			setPanelVisible(true)
			let remembered = SessionStore.read(in: project.root)
			// A panel with nothing in it is not a terminal being open. The
			// session's own terminals come back a moment later if it had any;
			// this is for the window that has none.
			if !bottomPanel.hasTerminals, remembered?.terminals.isEmpty ?? true {
				_ = bottomPanel.showTerminal()
			}
			if wanted == "full" { maximizeTerminalWhenLaidOut() }
		}

		// Scratches come back with the project. Only when the window is empty:
		// following a terminal into a project puts back what it had open, and
		// that already includes whichever scratches were among it.
		if !editor.hasOpenFiles { editor.restoreScratches() }

		// Deferred: the titlebar has no measurable height until the window has
		// laid out at least once.
		DispatchQueue.main.async { [weak self] in
			self?.updateTopInsets()
			// The tree takes focus on open, so arrow keys work without clicking.
			// Not when the terminal is what moved us here: the user is typing in
			// it, and taking the keyboard away mid-command would be worse than
			// not following at all.
			if focusTree { self?.navigator.focusTree() }
		}

		readGit()
		refreshRunConfigurations()
	}

	/// Opens a file as a permanent tab and selects it in the tree.
	func openFile(at url: URL) {
		editor.open(fileURL: url, focusEditor: true, preview: false)
		navigator.selectWithoutOpening(url: url)
	}

	/// Opens a file provisionally, as a single click in the tree would.
	func previewFile(at url: URL) {
		editor.open(fileURL: url, focusEditor: false, preview: true)
		navigator.selectWithoutOpening(url: url)
	}

	/// Flushes every dirty document in this window.
	func autoSaveAll() {
		editor.autoSaveAll()
	}

	/// Applies changed preferences: editor metrics, and tree filters that change
	/// which files exist at all.
	private func applySettings() {
		// A palette change reaches everything that draws. Most of it reads the
		// theme as it draws and needs only a repaint; the colours that were
		// copied into a layer or a control when it was built are recognised and
		// swapped for their counterparts.
		if Theme.apply() { applyPalette() }

		editor.applySettings()
		navigator.applySettings()
		toolStrip.applySettings()
		bottomPanel.applySettings()

		// The pills re-measure at the new scale, and the toolbar item has to be
		// told to re-lay-out around them.
		layoutTitlebarPills()
		window?.toolbar?.validateVisibleItems()

		// The tool strip's width changed, which moves everything to its right.
		toolStripWidthConstraint?.constant = ToolWindowBar.width
		updateTopInsets()
	}

	/// Re-reads the palette everywhere it was copied when a view was built.
	private func applyPalette() {
		window?.backgroundColor = Theme.current.windowBackground
		window?.appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)

		if let content = window?.contentView {
			ThemeSwap.apply(from: Theme.previous, to: Theme.current, in: content)
		}
		splitView.needsDisplay = true

		// The terminal keeps its palette as a table of components, and the
		// theme-following scheme is a different table in daylight.
		TerminalPalette.invalidate()
		bottomPanel.applySettings()

		// Rebuilt rather than swapped: a sidebar pane is cheap to make and
		// draws a dozen shades that are chosen as it builds.
		install(tool: currentSidebarTool, force: true)
	}

	/// Draws the sidebar's pane into a file, whatever the window is doing.
	///
	/// The window capture goes through the compositor and a pane that has just
	/// been built is not always in it yet; this asks the view itself.
	func snapshotSidebarForTesting(to path: String) {
		guard let view = primaryToolView, view.bounds.width > 1 else { return }
		guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
		view.cacheDisplay(in: view.bounds, to: rep)
		guard let data = rep.representation(using: .png, properties: [:]) else { return }
		try? data.write(to: URL(fileURLWithPath: path))
	}

	/// Opens the sidebar to a width, for looking at a pane in a screenshot.
	func openSidebarForTesting(width: CGFloat) {
		navigatorWidth = width
		navigatorWidthConstraint.constant = width
		navigatorContainer.isHidden = false
		splitView.setPosition(width, ofDividerAt: 0)
		splitView.adjustSubviews()
		updateSidebarSelection()
	}

	/// Gives the project tree keyboard focus.
	func focusNavigator() {
		navigator.focusTree()
	}

	/// Also reachable by double-clicking the empty part of the tab strip.
	@objc func newScratchFile(_ sender: Any?) {
		editor.newScratch()
	}

	/// Uses the empty page's button when there is one, so the capture exercises
	/// the control rather than what it happens to call.
	func newScratchForTesting() {
		if !editor.clickScratchPlaceholderForTesting() { newScratchFile(nil) }
	}

	// MARK: - Debugging anything

	/// Debugs a binary, whatever produced it.
	///
	/// The other half of "Go Debug": a native executable is debugged by LLDB,
	/// which speaks the same protocol, so nothing above the adapter changes.
	@objc func debugExecutable(_ sender: Any?) {
		// Works with no project open: a binary is a thing you can debug on its
		// own, and needing a project first would be a rule for its own sake.
		let root = project?.root ?? FileManager.default.homeDirectoryForCurrentUser

		let panel = NSOpenPanel()
		panel.title = "Debug an executable"
		panel.message = "Pick a compiled program. It is debugged as it is, and not rebuilt."
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.allowsMultipleSelection = false
		panel.directoryURL = root

		let start: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .OK, let url = panel.url, let self else { return }
			// Judged from where the binary is when there is no project to judge
			// from — a Go binary sitting next to a go.mod is still Go's.
			let adapter = DebugAdapters.adapter(
				forProgramAt: url.path,
				projectRoot: self.project?.root ?? url.deletingLastPathComponent()
			)
			guard let executable = DebugAdapters.executable(for: adapter) else {
				self.presentGoError("Could not find `\(adapter.command)`. \(adapter.installHint)")
				return
			}
			self.setPanelVisible(true)
			guard let session = self.bottomPanel.startDebugging(
				adapter: adapter,
				executable: executable,
				start: .launch(program: FilePath.canonical(url), arguments: []),
				breakpoints: self.pendingBreakpoints
			) else { return }
			self.wire(session)
		}
		if let window { panel.beginSheetModal(for: window, completionHandler: start) } else { start(panel.runModal()) }
	}

	/// Attaches to something already running.
	///
	/// The case launching cannot cover: a server that is already up, or a
	/// process that only misbehaves after an hour of work.
	@objc func attachToProcess(_ sender: Any?) {
		let processes = RunningProcesses.list()
		guard !processes.isEmpty else {
			notify("Nothing to attach to", detail: "No running processes were found.")
			return
		}

		let picker = ProcessPicker()
		processPicker = picker
		picker.onAttach = { [weak self] chosen in
			guard let self else { return }
			self.processPicker = nil
			self.attach(to: chosen)
		}
		picker.show(processes: processes, over: window)
	}

	/// Starts a session on a process that is already running.
	private func attach(to process: RunningProcess) {
		let adapter = DebugAdapters.adapter(
			forProgramAt: process.path,
			projectRoot: project?.root ?? URL(fileURLWithPath: process.path).deletingLastPathComponent()
		)
		guard let executable = DebugAdapters.executable(for: adapter) else {
			notify("\(adapter.name) is not installed", detail: adapter.installHint)
			return
		}

		setPanelVisible(true)
		guard let session = bottomPanel.startDebugging(
			adapter: adapter,
			executable: executable,
			start: .attach(pid: process.pid),
			breakpoints: pendingBreakpoints
		) else { return }
		wire(session)
	}

	// MARK: - Debugging

	/// The session the debug commands act on, if one is running.
	private var debugSession: DebugSession? { bottomPanel.activeDebugSession }

	/// Where execution is stopped, for saying so.
	private var executionMarker: (file: String, line: Int)?

	@objc func debugContinue(_ sender: Any?) { debugSession?.resume() }
	@objc func debugPause(_ sender: Any?) { debugSession?.pause() }
	@objc func debugStepOver(_ sender: Any?) { debugSession?.stepOver() }
	@objc func debugStepInto(_ sender: Any?) { debugSession?.stepInto() }
	@objc func debugStepOut(_ sender: Any?) { debugSession?.stepOut() }
	@objc func debugStop(_ sender: Any?) { debugSession?.stop() }

	/// Greys out the debug commands when nothing is being debugged.
	///
	/// A menu full of commands that do nothing is worse than one that says so.
	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		// A shortcut the terminal needs belongs to the terminal while somebody
		// is typing in one. ⌃D ends a shell and answers k9s; ⌃R searches a
		// shell's history; ⌃P and ⌃N walk it. A menu item that claims those
		// swallows them before the program ever sees them — and a disabled item
		// lets the keystroke carry on down to the view that wants it.
		if bottomPanel.hasKeyboardFocus, Self.terminalShortcuts.contains(where: {
			$0.key == item.keyEquivalent
				&& item.keyEquivalentModifierMask.subtracting(.function) == $0.modifiers
		}) {
			return false
		}

		if item.action == #selector(choosePreviewMode(_:)) {
			guard let state = previewModeState(),
			      let raw = item.representedObject as? String,
			      let mode = PreviewMode(rawValue: raw)
			else {
				item.state = .off
				return false
			}
			item.state = mode == state.current ? .on : .off
			return state.available.contains(mode)
		}

		switch item.action {
		case #selector(debugContinue(_:)), #selector(debugPause(_:)),
		     #selector(debugStepOver(_:)), #selector(debugStepInto(_:)),
		     #selector(debugStepOut(_:)), #selector(debugStop(_:)):
			return debugSession?.isActive ?? false
		case #selector(newTerminalTab(_:)):
			return bottomPanel.hasKeyboardFocus
		case #selector(navigateBack(_:)):
			return canNavigateBack
		case #selector(navigateForward(_:)):
			return canNavigateForward
		case #selector(togglePresentationMode(_:)):
			// Ticked while presenting, since the whole point is that it is a
			// mode you are in rather than a change you made.
			item.state = Settings.shared.presenting ? .on : .off
			return true
		default:
			return true
		}
	}

	/// Types a small block the way somebody would, and prints the result.
	///
	/// Through the editor's own insertion path, so what is measured is what
	/// return actually does rather than what the indent rules would say.
	func exerciseReturnIndentForTesting() {
		editor.moveCaretToEndForTesting()
		editor.simulateTyping("\n")

		// A function, its body, and a nested block — typed exactly as somebody
		// would, with no manual indentation at all.
		editor.simulateTyping("func demo() {")
		editor.simulateReturn()
		editor.simulateTyping("if ready {")
		editor.simulateReturn()
		editor.simulateTyping("run()")
		editor.simulateReturn()
		editor.simulateTyping("}")
		editor.simulateReturn()
		editor.simulateTyping("}")

		print("RETURN:")
		for line in editor.textTailLinesForTesting(6) {
			print("RETURN: |\(line)|")
		}
	}

	/// Presses ⌘T in the editor and then in the terminal.
	///
	/// Through the menu's own validation and action, which is what the key
	/// press does — checking the method exists would prove nothing about
	/// whether the shortcut reaches it or is enabled at the right moment.
	func exerciseTerminalTabKeyForTesting() {
		let item = NSMenuItem(
			title: "New Terminal Tab", action: #selector(newTerminalTab(_:)), keyEquivalent: "t"
		)

		editor.focusForTesting()
		print("TAB: in editor   focused=\(isTerminalFocused) enabled=\(validateMenuItem(item)) "
			+ "sessions=\(terminalSessionCountForTesting)")
		if validateMenuItem(item) { newTerminalTab(nil) }

		toggleTerminal(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
			guard let self else { return }
			print("TAB: in terminal focused=\(self.isTerminalFocused) "
				+ "enabled=\(self.validateMenuItem(item)) sessions=\(self.terminalSessionCountForTesting)")
			if self.validateMenuItem(item) { self.newTerminalTab(nil) }

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				print("TAB: after ⌘T   sessions=\(self.terminalSessionCountForTesting)")
			}
		}
	}

	/// Debugs a binary, choosing the adapter the way the menu item does.
	func debugBinaryForTesting(_ path: String) {
		guard let project else { return }
		let adapter = DebugAdapters.adapter(forProgramAt: path, projectRoot: scopeRoot ?? project.root)
		guard let executable = DebugAdapters.executable(for: adapter) else {
			print("BINARY: no \(adapter.command) installed")
			return
		}
		print("BINARY: \(adapter.name) at \(executable)")
		setPanelVisible(true)
		guard let session = bottomPanel.startDebugging(
			adapter: adapter,
			executable: executable,
			start: .launch(program: FilePath.canonical(URL(fileURLWithPath: path)), arguments: []),
			breakpoints: pendingBreakpoints
		) else { return }
		wire(session)
	}

	/// Lets it run to the end and reports how it exited.
	func reportExitForTesting() {
		debugContinue(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
			guard let self else { return }
			self.bottomPanel.writeDebugToolbarImageForTesting(to: "build/exit-toolbar.png")
			let state = self.debugSession.map { String(describing: $0.state) } ?? "none"
			print("EXIT: code=\(self.debugSession?.exitCode.map(String.init) ?? "none") state=\(state)")
		}
	}

	/// Looks at where the debugger stopped, without moving it.
	func inspectDebugStateForTesting() {
		let stoppedAt = executionMarker.map { "\(($0.file as NSString).lastPathComponent):\($0.line)" }
			?? "not stopped"
		print("INSPECT: stopped at \(stoppedAt)")
		bottomPanel.exerciseDebugExtrasForTesting()

		// And the editor's way in, which is the one somebody actually uses:
		// select an expression, ask to watch it, and the answer should be in
		// front of them rather than behind the console tab.
		watchFromEditor("answer * 3")
		let pane = bottomPanel.activeDebugPane
		let added = pane?.debugSession.watches.contains { $0.expression == "answer * 3" } ?? false
		print("EDITORWATCH: added=\(added) showsConsole=\(pane?.showsConsoleForTesting ?? true)")
	}

	/// Puts a condition on a breakpoint before the program runs.
	func setBreakpointConditionForTesting(line: Int, condition: String) {
		guard let url = editor.activeGroup?.activeTabURL else { return }
		setBreakpointOptions(
			file: FilePath.canonical(url), line: line,
			condition: condition, hitCondition: nil, logMessage: nil
		)
		print("COND: \(condition) on line \(line)")
	}

	/// Walks the debugger a step at a time, saying where it stopped.
	func reportDebugStepForTesting(step: Int) {
		guard let session = debugSession else {
			print("DEBUG: no session yet (step \(step))")
			return
		}
		let where_ = executionMarker.map { "\(($0.file as NSString).lastPathComponent):\($0.line)" }
			?? "not stopped"
		print("DEBUG: step \(step) state=\(session.isActive ? "active" : "inactive") at \(where_)")

		if step == 0 {
			bottomPanel.writeDebugToolbarImageForTesting(to: "build/debug-toolbar.png")
		}

		// Menu commands, the same ones the function keys send.
		switch step {
		case 0, 1: debugStepOver(nil)
		case 2: debugStepInto(nil)
		case 3: debugStepOut(nil)
		// The last step lets it run to the end, so there is an exit code to
		// report rather than one we killed before it had one.
		default: debugContinue(nil)
		}

		if step >= 3 {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
				guard let self else { return }
				self.bottomPanel.writeDebugToolbarImageForTesting(to: "build/exit-toolbar.png")
				let state = self.debugSession.map { String(describing: $0.state) } ?? "none"
				print("EXIT: code=\(self.debugSession?.exitCode.map(String.init) ?? "none") state=\(state)")
			}
		}
	}

	/// Steps as the keyboard would, for checking the commands are connected.
	func debugCommandForTesting(_ name: String) -> String {
		guard let session = debugSession else { return "no session" }
		switch name {
		case "over": session.stepOver()
		case "into": session.stepInto()
		case "out": session.stepOut()
		case "continue": session.resume()
		case "pause": session.pause()
		case "stop": session.stop()
		default: return "unknown command"
		}
		return "sent \(name), active=\(session.isActive)"
	}

	/// Every state this file has been in, including abandoned branches.
	@objc func showFileHistory(_ sender: Any?) {
		editor.toggleFileHistory()
	}

	@objc func closeTab(_ sender: Any?) {
		// Falls back to closing the window when nothing is open, matching ⌘W.
		if editor.hasOpenFiles {
			editor.closeActiveTab()
		} else {
			window?.performClose(nil)
		}
	}

	// MARK: - Bottom panel

	private var isPanelVisible: Bool { !bottomPanel.isHidden }

	/// Whether the panel has the window to itself, and what to restore.
	private var isPanelMaximized = false
	private var heightBeforeMaximize: CGFloat?

	/// Gives the panel the whole window, or hands it back.
	///
	/// Everything above it goes: the tree, the editors and their tabs. The
	/// panel's own tabs stay, since they are how you get between terminals.
	/// Gives the window back, for anything that needs the editor to be visible.
	///
	/// A page opened while the terminal has the whole window would open behind
	/// it: the editor is hidden, not merely small. Asking for one is asking to
	/// look at it.
	private func leaveTerminalFullScreen() {
		guard isPanelMaximized else { return }
		togglePanelMaximized(nil)
	}

	/// Puts the panel at a stated height, for a capture that has to look the
	/// same twice.
	///
	/// The split position is remembered per machine, so a screenshot taken
	/// where somebody had dragged the terminal to the top of the window shows
	/// the terminal and nothing else. Zero closes it, which is what a shot of
	/// the editor alone wants.
	func setPanelHeightForTesting(_ height: Double) {
		guard height > 0 else {
			setPanelVisible(false)
			return
		}
		if isPanelMaximized { togglePanelMaximized(nil) }
		setPanelVisible(true)
		panelHeight = CGFloat(height)

		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			let total = self.verticalSplitView.bounds.height
			guard total > 200 else { return }
			self.verticalSplitView.setPosition(total - CGFloat(height), ofDividerAt: 0)
			self.tellTerminalsTheySizeChanged()
		}
	}

	/// Gives the editor enough of the window to show where execution stopped.
	///
	/// Two things can hide the line a breakpoint is on, and both are ordinary:
	/// the terminal can have the whole window, in which case the editor is
	/// hidden rather than small; and the panel can simply be tall, because it
	/// was dragged that way while reading a log. Neither is a state somebody
	/// chose *for debugging* — they chose it for the thing they were doing a
	/// minute ago, and a debugger that stops behind them has nothing to show.
	///
	/// Half the window is the most the panel keeps. Not a fixed height: the
	/// stack, the variables and the console all need room too, and taking the
	/// panel down to a strip to reveal one line is the opposite mistake.
	private func makeRoomForTheStoppedLine() {
		leaveTerminalFullScreen()
		guard isPanelVisible else { return }

		// After layout: leaving full screen lays out on the next pass, and a
		// divider position set before that is computed against the old
		// geometry — which puts it in the wrong place and looks like a bug in
		// the debugger rather than in the arithmetic.
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			let total = self.verticalSplitView.bounds.height
			guard total > 200 else { return }

			let half = (total / 2).rounded(.down)
			guard self.bottomPanel.frame.height > half else { return }
			self.verticalSplitView.setPosition(total - half, ofDividerAt: 0)
			self.tellTerminalsTheySizeChanged()
		}
	}

	@objc func togglePanelMaximized(_ sender: Any? = nil) {
		if isPanelMaximized {
			toolPopover?.performClose(nil)
			isPanelMaximized = false
			bottomPanel.isMaximized = false
			splitView.isHidden = false
			bottomPanel.setTopInset(0)
			verticalSplitView.adjustSubviews()
			let total = verticalSplitView.bounds.height
			let restored = heightBeforeMaximize ?? panelHeight
			if total > 200 { verticalSplitView.setPosition(total - restored, ofDividerAt: 0) }
			tellTerminalsTheySizeChanged()

			// The sidebar comes back as it was left, whatever was looked at
			// over the terminal in the meantime — and the strip says so, which
			// it could not while there was no sidebar to point at.
			install(tool: currentSidebarTool, force: true)
			updateTopInsets()
			updateSidebarSelection()
			return
		}

		setPanelVisible(true)
		isPanelMaximized = true
		bottomPanel.isMaximized = true
		// Nothing in the sidebar is showing any more, and the strip should not
		// claim otherwise; what it offers now opens over the terminal.
		toolStrip.setSidebarSelection(visible: false, tool: currentSidebarTool)
		heightBeforeMaximize = max(160, bottomPanel.frame.height)
		// Hidden rather than resized to nothing: a split view will not put a
		// pane fully away, and a sliver of editor left showing is not what
		// "give the terminal the window" means.
		splitView.isHidden = true
		bottomPanel.setTopInset(sidebarTopInset)
		verticalSplitView.adjustSubviews()
		verticalSplitView.setPosition(0, ofDividerAt: 0)
		tellTerminalsTheySizeChanged()
	}

	/// Once layout has settled, so the size read is the one the pane ended up
	/// with rather than the one it had.
	private func tellTerminalsTheySizeChanged() {
		DispatchQueue.main.async { [weak self] in
			self?.bottomPanel.viewportChanged()
		}
	}

	// MARK: - Following the terminal

	/// Turns following on or off.
	@objc func toggleFollowTerminal(_ sender: Any? = nil) {
		followsTerminal.toggle()
		bottomPanel.isFollowingProject = followsTerminal
		guard followsTerminal else { return }
		// Catch up straight away rather than waiting for the shell to move.
		bottomPanel.reportWorkingDirectory()
	}

	/// The terminal moved. Follow it, if the window was asked to.
	///
	/// Only whole projects: moving between directories inside one changes
	/// nothing, which is what makes this bearable to leave switched on.
	func terminalDirectoryChanged(to directory: URL) {
		// Never during a capture. A screenshot is of a project somebody named
		// on the command line, and a restored tmux session whose shell sits in
		// another checkout would quietly swap it for that one — which is a
		// screenshot of the wrong program, taken without complaint.
		guard !LaunchOptions.parse().isScreenshotRun else { return }
		guard followsTerminal else { return }
		guard let root = ProjectRoot.find(from: directory) else { return }
		switchProject(to: root, followingTerminal: true)
	}

	/// Swaps one project for another in place, keeping what each had open.
	///
	/// - Parameter followingTerminal: whether the terminal is what moved. Then
	///   the window it is showing is the one somebody just chose, and neither
	///   half of remembering a tmux window applies: see the two notes below,
	///   which between them are why this parameter exists.
	func switchProject(to root: URL, followingTerminal: Bool = false) {
		let root = root.standardizedFileURL
		guard root.path != project?.root.standardizedFileURL.path else { return }

		if let current = project?.root {
			var session = editor.captureSession()
			session.terminals = bottomPanel.captureTerminals()
			session.isPanelVisible = isPanelVisible
			// The window it was left in, which is not the one showing when the
			// switch is *because* the terminal moved: see the rule itself, in
			// ProjectSession, for what recording that leads to.
			session.tmuxWindow = ProjectSession.rememberedWindow(
				showing: bottomPanel.currentTmuxWindowID,
				stored: sessions.session(for: current)?.tmuxWindow
					?? SessionStore.read(in: current)?.tmuxWindow,
				followingTerminal: followingTerminal
			)
			session.subprojectPath = subprojectRoot.map { Subprojects.relativePath($0, to: current) }
			session.selectedConfiguration = selectedConfigurationName
			session.xcodeDestinations = xcodeDestinations
			session.breakpoints = breakpointsToRemember()
			sessions.store(session, for: current)
			// And beside the project, so tomorrow's window opens on today's
			// files: what was open is a property of the project, not of the
			// application that happened to be running.
			try? SessionStore.write(session, in: current)
		}

		// Read before anything is loaded: opening a project touches the editor
		// and the panel, and anything that writes the session on the way past
		// would overwrite the very thing being restored.
		let previous = sessions.take(for: root) ?? SessionStore.read(in: root)

		load(project: Project(root: root), focusTree: false)
		RecentProjects.shared.record(url: root)

		if let previous {
			editor.restore(previous)
		} else {
			editor.closeAllTabs()
			editor.restoreScratches()
		}

		// The terminals a project had, but only into a window that has none.
		//
		// A terminal is a place somebody is, not a property of the project: the
		// window follows the shell around when that is turned on, so closing
		// the shell that just changed directory would kill the thing doing the
		// navigating — and with it any way of navigating back.
		// The window it was left in, before the terminals — tmux has to be
		// attached for either, and going back to the right window first means
		// the tabs come up showing it rather than showing one and then moving.
		//
		// Never while following the terminal: the window showing then is the one
		// somebody selected a moment ago, and this is the app arguing with them
		// about it. It is also the other half of the loop described above —
		// selecting a window moves the shell, which moves the project, which
		// selects a window.
		if !followingTerminal, let window = previous?.tmuxWindow {
			bottomPanel.restoreTmuxWindow(window)
		}

		if !bottomPanel.hasTerminals, let previous, !previous.terminals.isEmpty {
			bottomPanel.restoreTerminals(previous.terminals)
			// And the panel itself, if it was showing: terminals that came back
			// behind a closed panel look like terminals that did not.
			if previous.isPanelVisible { setPanelVisible(true) }
		}
	}

	/// Writes what is open beside the project, so the next window on it opens
	/// where this one left off.
	func rememberOpenEditors() {
		guard let root = project?.root, !isTornOff else { return }
		var session = editor.captureSession()
		session.terminals = bottomPanel.captureTerminals()
		session.isPanelVisible = isPanelVisible
		session.tmuxWindow = bottomPanel.currentTmuxWindowID
		session.subprojectPath = subprojectRoot.map { Subprojects.relativePath($0, to: root) }
		session.selectedConfiguration = selectedConfigurationName
		session.xcodeDestinations = xcodeDestinations
		session.breakpoints = breakpointsToRemember()
		try? SessionStore.write(session, in: root)
	}

	private func setPanelVisible(_ visible: Bool) {
		guard visible != isPanelVisible else { return }

		toolStrip.setTerminalSelected(visible)

		if visible {
			bottomPanel.isHidden = false
			verticalSplitView.adjustSubviews()
			// Deferred: at launch the split view has no height yet, so computing
			// the divider position now would place it at zero.
			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				let total = self.verticalSplitView.bounds.height
				guard total > 200 else { return }
				self.verticalSplitView.setPosition(total - self.panelHeight, ofDividerAt: 0)
			}
		} else {
			if isPanelMaximized {
				isPanelMaximized = false
				bottomPanel.isMaximized = false
				bottomPanel.setTopInset(0)
				splitView.isHidden = false
			}
			// Remember the height so reopening restores the same size.
			panelHeight = max(160, bottomPanel.frame.height)
			bottomPanel.isHidden = true
			verticalSplitView.adjustSubviews()
			editor.focusActiveEditor()
		}
	}

	@objc func toggleTerminal(_ sender: Any?) {
		if isPanelVisible, bottomPanel.hasSessions {
			setPanelVisible(false)
		} else {
			setPanelVisible(true)
			bottomPanel.showTerminal()
		}
	}

	/// Hands a model to GoSTL.
	///
	/// Launched rather than embedded: GoSTL's package vends an executable, and
	/// an executable target cannot also be linked into another app. It watches
	/// the file it is given, so editing a .scad here refreshes the preview
	/// there on its own.
	static func previewModel(at url: URL) {
		guard let executable = ModelPreview.executable() else { return }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = [url.path]
		try? process.run()
	}

	/// Opens a shell in a specific directory, from the navigator's context menu.
	func openTerminal(in directory: URL) {
		setPanelVisible(true)
		bottomPanel.newTerminal(in: directory)
	}

	/// Writes text into the active terminal, as though typed.
	func sendToTerminal(_ text: String) {
		bottomPanel.showTerminal()?.terminalView.send(text)
	}

	@objc func findInFile(_ sender: Any?) {
		editor.showFind()
	}

	func setFindQuery(_ query: String) { editor.setFindQuery(query) }

	func setProjectSearchQuery(_ query: String) {
		setPanelVisible(true)
		bottomPanel.showSearch(query: query)
	}

	@objc func findNext(_ sender: Any?) { editor.findNext() }
	@objc func findPrevious(_ sender: Any?) { editor.findPrevious() }

	@objc func findInProject(_ sender: Any?) {
		setPanelVisible(true)
		// Seed from the selection, which is what you usually want to search for.
		bottomPanel.showSearch(query: editor.selectedTextForSearch())
	}

	// MARK: - Go

	@objc func goRun(_ sender: Any?) { runGo(.run) }
	@objc func goBuild(_ sender: Any?) { runGo(.build) }
	@objc func goTest(_ sender: Any?) { runGo(.test) }
	@objc func goTrace(_ sender: Any?) { runGo(.trace) }
	@objc func goProfile(_ sender: Any?) { runGo(.profile) }
	@objc func goDebug(_ sender: Any?) { runGo(.debug) }

	/// Breakpoints set before a session exists, so they survive between runs.
	/// Breakpoints set before a session exists, with whatever conditions they
	/// were given. Whole breakpoints rather than line numbers, or a condition
	/// put on one before launching — which is when somebody actually sets them
	/// — would be dropped on the way in.
	private var pendingBreakpoints: [String: [Breakpoint]] = [:]

	/// The breakpoints worth writing down: the running session's if there is
	/// one, since it holds what the adapter has confirmed, and the pending set
	/// otherwise.
	private func breakpointsToRemember() -> [String: [Breakpoint]] {
		bottomPanel.activeDebugSession?.breakpoints ?? pendingBreakpoints
	}

	/// Draws the pending breakpoints in the gutter, which is what makes a
	/// restored one visible rather than merely remembered.
	/// Writes them down as soon as they change, the way the terminals do.
	///
	/// Not only when the window closes: a breakpoint costs a moment to place
	/// and is worth nothing after a crash that took the note of it, and the
	/// window may be closed by something that never asks — a restart, a build
	/// that replaces the app underneath it.
	private func rememberBreakpoints() {
		rememberOpenEditors()
	}

	private func showPendingBreakpoints() {
		var marks: [String: [Int: CodeView.BreakpointMark]] = [:]
		var conditional: [String: Set<Int>] = [:]
		for (file, list) in pendingBreakpoints {
			marks[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, Self.mark(for: $0)) })
			conditional[file] = Set(list.filter(\.isConditional).map(\.line))
		}
		editor.setBreakpoints(marks)
		editor.setConditionalBreakpoints(conditional)
	}

	private func toggleBreakpoint(file: URL, line: Int) {
		// The debugger reports files by their real path, so breakpoints are
		// keyed the same way or they are set against a name nothing else uses.
		let path = FilePath.canonical(file)

		// Anchored either way: what it was put on is only knowable now, while the
		// file still looks the way it did when it was clicked.
		defer { scheduleAnchoring(inFile: file) }

		if let session = bottomPanel.activeDebugSession {
			session.toggleBreakpoint(file: path, line: line)
			syncBreakpointsToEditor(from: session)
			rememberBreakpoints()
			return
		}

		// No session yet: remember it, and hand the set over when one starts.
		var list = pendingBreakpoints[path] ?? []
		if let index = list.firstIndex(where: { $0.line == line }) {
			list.remove(at: index)
		} else {
			list.append(Breakpoint(file: path, line: line))
			list.sort { $0.line < $1.line }
		}
		pendingBreakpoints[path] = list.isEmpty ? nil : list
		publishPendingBreakpoints()
		rememberBreakpoints()
	}

	/// A file's breakpoints, from the session when one is running and from the
	/// pending set otherwise — the two are kept in step, so either answers.
	private func breakpoints(inFile path: String) -> [Breakpoint] {
		bottomPanel.activeDebugSession?.breakpoints(inFile: path) ?? pendingBreakpoints[path] ?? []
	}

	/// Puts a file's breakpoints back, wherever they are being kept.
	private func replaceBreakpoints(inFile path: String, with list: [Breakpoint]) {
		if let session = bottomPanel.activeDebugSession {
			session.replaceBreakpoints(inFile: path, with: list)
			syncBreakpointsToEditor(from: session)
			return
		}
		pendingBreakpoints[path] = list.isEmpty ? nil : list
		publishPendingBreakpoints()
	}

	/// What the gutter needs to know about a breakpoint.
	private static func mark(for breakpoint: Breakpoint) -> CodeView.BreakpointMark {
		CodeView.BreakpointMark(
			isEnabled: breakpoint.isEnabled,
			isVerified: breakpoint.isVerified,
			isConditional: breakpoint.isConditional
		)
	}

	/// Moves the breakpoints in a file with the text they were put on.
	///
	/// Typing above a breakpoint used to leave it on its line number while the
	/// code moved out from under it — so it stopped somewhere nobody had asked
	/// it to. A breakpoint on a line that is deleted goes with it.
	private func moveBreakpoints(inFile url: URL, editedFrom first: Int, removed: Int, inserted: Int) {
		guard removed != inserted else { return }
		let path = FilePath.canonical(url)
		let list = breakpoints(inFile: path)
		guard !list.isEmpty else { return }

		replaceBreakpoints(inFile: path, with: list.compactMap { breakpoint in
			guard let line = BreakpointAnchors.moved(
				line: breakpoint.line, editedFrom: first, removed: removed, inserted: inserted
			) else { return nil }
			guard line != breakpoint.line else { return breakpoint }
			return Breakpoint(
				file: breakpoint.file,
				line: line,
				isEnabled: breakpoint.isEnabled,
				// Where it is now is not where the adapter bound it, so it
				// is drawn as unbound until the adapter says otherwise.
				isVerified: false,
				condition: breakpoint.condition,
				hitCondition: breakpoint.hitCondition,
				logMessage: breakpoint.logMessage,
				anchor: breakpoint.anchor
			)
		}
		.sorted { $0.line < $1.line })

		// The anchors now describe where these were before the edit. Taking them
		// again is a query over the whole file, so it waits for typing to stop.
		scheduleAnchoring(inFile: url)
	}

	/// Anchoring waiting for the file to stop changing, per file.
	private var anchoringWork: [String: DispatchWorkItem] = [:]

	private func scheduleAnchoring(inFile url: URL) {
		let path = FilePath.canonical(url)
		anchoringWork[path]?.cancel()
		let work = DispatchWorkItem { [weak self] in
			self?.anchoringWork[path] = nil
			self?.anchorBreakpoints(inFile: url)
		}
		anchoringWork[path] = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
	}

	/// Records where a file's breakpoints sit in its code.
	///
	/// A line number is enough right up until something rewrites the file
	/// without saying what it changed. What survives that is the symbol the
	/// breakpoint is inside and the line it is on, which can only be read while
	/// the file still looks the way the breakpoint was set against.
	private func anchorBreakpoints(inFile url: URL) {
		let path = FilePath.canonical(url)
		let lines = breakpoints(inFile: path).map(\.line)
		guard !lines.isEmpty, let document = editor.document(for: url) else { return }

		// The symbols come off the parser's own queue, behind whatever reparse
		// the last edit left running, so this sees the tree for the text as it
		// is now rather than an outline that is one edit behind.
		document.symbols { [weak self] symbols in
			var anchors: [Int: BreakpointAnchors.Anchor] = [:]
			for line in lines where line <= document.lineCount {
				anchors[line] = BreakpointAnchors.anchor(
					line: line,
					text: document.lineText(line - 1),
					in: symbols,
					lineCount: document.lineCount
				)
			}
			self?.applyAnchors(anchors, inFile: path)
		}
	}

	private func applyAnchors(_ anchors: [Int: BreakpointAnchors.Anchor], inFile path: String) {
		if let session = bottomPanel.activeDebugSession {
			session.setBreakpointAnchors(inFile: path, anchors)
			pendingBreakpoints = session.breakpoints
			return
		}
		guard var list = pendingBreakpoints[path] else { return }
		for index in list.indices {
			guard let anchor = anchors[list[index].line] else { continue }
			list[index].anchor = anchor
		}
		pendingBreakpoints[path] = list
	}

	/// Puts a file's breakpoints back on the code they were set on, after
	/// something else rewrote the file.
	///
	/// Nothing reported an edit — an agent, a `git checkout` and a formatter all
	/// just leave a different file behind — so there is nothing to shift the
	/// lines by. Each breakpoint goes to wherever its anchor now points.
	private func reanchorBreakpoints(inFile url: URL) {
		let path = FilePath.canonical(url)
		guard !breakpoints(inFile: path).isEmpty, let document = editor.document(for: url) else {
			return
		}

		// Any anchoring still pending was scheduled against the text this file
		// has just stopped holding; letting it run would pin the breakpoints to
		// the new file at the old lines, which is the thing being undone here.
		anchoringWork[path]?.cancel()
		anchoringWork[path] = nil

		// The reload abandoned the old tree and queued a parse of the new text;
		// this query is behind it on the same queue, so it waits for the parse
		// rather than reading an empty outline and concluding every breakpoint
		// has lost its symbol.
		document.symbols { [weak self] symbols in
			guard let self else { return }
			let lines = (0..<document.lineCount).map { document.lineText($0) }
			self.replaceBreakpoints(
				inFile: path,
				with: BreakpointAnchors.resolve(
					// Read again rather than captured: the parse took a moment,
					// and a breakpoint set in it is one somebody just clicked.
					breakpoints: self.breakpoints(inFile: path), in: symbols, lines: lines
				)
			)
		}
	}

	/// Turns a breakpoint off, or on again, wherever it is kept.
	func setBreakpoint(file: URL, line: Int, enabled: Bool) {
		let path = FilePath.canonical(file)
		if let session = bottomPanel.activeDebugSession {
			session.setBreakpoint(file: path, line: line, enabled: enabled)
			syncBreakpointsToEditor(from: session)
			return
		}
		guard var list = pendingBreakpoints[path],
		      let index = list.firstIndex(where: { $0.line == line })
		else { return }
		list[index].isEnabled = enabled
		if !enabled { list[index].isVerified = false }
		pendingBreakpoints[path] = list
		publishPendingBreakpoints()
	}

	/// Takes a breakpoint away — dragging it out of the gutter, or Delete.
	func deleteBreakpoint(file: URL, line: Int) {
		let path = FilePath.canonical(file)
		if let session = bottomPanel.activeDebugSession {
			session.removeBreakpoint(file: path, line: line)
			syncBreakpointsToEditor(from: session)
			return
		}
		guard var list = pendingBreakpoints[path] else { return }
		list.removeAll { $0.line == line }
		pendingBreakpoints[path] = list.isEmpty ? nil : list
		publishPendingBreakpoints()
	}

	/// Silences every breakpoint but one, or brings them all back.
	func setOtherBreakpoints(file: URL, line: Int, enabled: Bool) {
		let path = FilePath.canonical(file)
		if let session = bottomPanel.activeDebugSession {
			session.setOtherBreakpoints(file: path, line: line, enabled: enabled)
			syncBreakpointsToEditor(from: session)
			return
		}
		for (candidate, list) in pendingBreakpoints {
			var updated = list
			for index in updated.indices where !(candidate == path && updated[index].line == line) {
				updated[index].isEnabled = enabled
				if !enabled { updated[index].isVerified = false }
			}
			pendingBreakpoints[candidate] = updated
		}
		publishPendingBreakpoints()
	}

	/// Draws the breakpoints that exist before anything is running.
	private func publishPendingBreakpoints() {
		var mapped: [String: [Int: CodeView.BreakpointMark]] = [:]
		var conditional: [String: Set<Int>] = [:]
		for (file, list) in pendingBreakpoints {
			mapped[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, Self.mark(for: $0)) })
			conditional[file] = Set(list.filter(\.isConditional).map(\.line))
		}
		editor.setBreakpoints(mapped)
		editor.setConditionalBreakpoints(conditional)
	}

	private func syncBreakpointsToEditor(from session: DebugSession) {
		var mapped: [String: [Int: CodeView.BreakpointMark]] = [:]
		var conditional: [String: Set<Int>] = [:]
		for (file, list) in session.breakpoints {
			mapped[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, Self.mark(for: $0)) })
			conditional[file] = Set(list.filter(\.isConditional).map(\.line))
		}
		// Kept, so they survive the session ending and are there for the next
		// one — conditions included.
		pendingBreakpoints = session.breakpoints
		editor.setBreakpoints(mapped)
		editor.setConditionalBreakpoints(conditional)
	}

	/// Applies breakpoint options, to the session if there is one and to the
	/// pending set either way.
	func setBreakpointOptions(
		file path: String,
		line: Int,
		condition: String?,
		hitCondition: String?,
		logMessage: String?
	) {
		if let session = bottomPanel.activeDebugSession {
			session.setBreakpointOptions(
				file: path, line: line,
				condition: condition, hitCondition: hitCondition, logMessage: logMessage
			)
			syncBreakpointsToEditor(from: session)
			return
		}

		var list = pendingBreakpoints[path] ?? []
		if let index = list.firstIndex(where: { $0.line == line }) {
			list[index].condition = condition?.isEmpty == true ? nil : condition
			list[index].hitCondition = hitCondition?.isEmpty == true ? nil : hitCondition
			list[index].logMessage = logMessage?.isEmpty == true ? nil : logMessage
			pendingBreakpoints[path] = list
			publishPendingBreakpoints()
		}
	}

	/// Asks what a breakpoint should do, and tells the session.
	///
	/// A breakpoint you have to sit and press Continue at four hundred times
	/// because the interesting case is the last one is not much of a
	/// breakpoint; a condition is what makes it one.
	private func editBreakpoint(file: URL, line: Int) {
		let path = FilePath.canonical(file)

		// Works whether or not anything is running: conditions are nearly always
		// set while writing the code, before the first launch.
		let session = bottomPanel.activeDebugSession
		let existing = session?.breakpoint(file: path, line: line)
			?? pendingBreakpoints[path]?.first { $0.line == line }
			?? {
				// Right-clicking a line with no breakpoint sets one there
				// first: it is plainly what was meant.
				toggleBreakpoint(file: file, line: line)
				return session?.breakpoint(file: path, line: line)
					?? pendingBreakpoints[path]?.first { $0.line == line }
					?? Breakpoint(file: path, line: line)
			}()

		let sheet = BreakpointOptionsSheet(
			line: line,
			fileName: file.lastPathComponent,
			// The file's own language, so a Go condition is coloured as Go and
			// a Swift one as Swift.
			languageId: LanguageRegistry.shared.languageId(for: file) ?? "",
			existing: existing
		) { [weak self] condition, hits, message in
			self?.setBreakpointOptions(
				file: path,
				line: line,
				condition: condition,
				hitCondition: hits,
				logMessage: message
			)
		}
		// A window of its own, begun on this one. `presentAsSheet` needs a view
		// controller to present from and this window has a content view rather
		// than a controller — asking for one returns nil, and the sheet simply
		// never appeared.
		guard let window else { return }
		window.beginSheet(NSWindow(contentViewController: sheet), completionHandler: nil)
	}

	private enum GoAction { case run, build, test, trace, profile, debug }

	private func runGo(_ action: GoAction) {
		guard let project else { return }
		// The module need not be at the project root — a Go repository commonly
		// keeps go.mod in a subdirectory — so the modules found by discovery
		// decide where these commands run.
		guard let moduleRoot = chooseModuleRoot(in: scopeRoot ?? project.root) else { return }
		guard let go = GoTooling.findGoExecutable() else {
			presentGoError("Could not find the `go` executable. Install Go, or make sure it is in /opt/homebrew/bin or /usr/local/go/bin.")
			return
		}

		// Whatever is about to read these files reads them from disk, so what
		// is in the editor has to be there first. IDEA does the same before a
		// run, and it is what makes a long idle timer safe.
		autoSaveAll()

		let command: GoTooling.Command
		switch action {
		case .run, .build, .debug:
			// These need a specific main package; ask when there is a choice.
			guard let package = chooseMainPackage(in: moduleRoot) else { return }
			switch action {
			case .run: command = GoTooling.runCommand(executable: go, package: package)
			case .build: command = GoTooling.buildCommand(executable: go, package: package)
			default:
				guard let delve = GoTooling.findDelveExecutable() else {
					presentGoError("Could not find `dlv`. Install Delve with: go install github.com/go-delve/delve/cmd/dlv@latest")
					return
				}
				startNativeDebugger(delve: delve, package: package)
				return
			}
		case .test: command = GoTooling.testCommand(executable: go)
		case .trace: command = GoTooling.traceCommand(executable: go)
		case .profile: command = GoTooling.profileCommand(executable: go)
		}

		setPanelVisible(true)
		bottomPanel.runCommand(
			title: command.title,
			executable: command.executable,
			arguments: command.arguments,
			// In the module, not the project root: `go test ./...` from a
			// directory with no go.mod fails whatever the arguments say.
			workingDirectory: moduleRoot,
			// One console per Go action per module: `go test` run again lands
			// where the last one was, and does not sit beside `go run`.
			reusing: "go:\(command.title):\(moduleRoot.path)"
		)
	}

	/// Starts the native debugger and wires its state to the editor.
	private func startNativeDebugger(delve: String, package: String) {
		setPanelVisible(true)
		// The titlebar follows the session from here on — `wire` reports every
		// state change to it — but the gap before the adapter answers is worth
		// filling, or pressing debug looks like it did nothing.
		runControl?.setStatus("Starting…", busy: true)
		// Breakpoints go in with the session, not after it: the adapter only
		// asks for them once, immediately after launch.
		guard let session = bottomPanel.startDebugging(
			delve: delve,
			package: package,
			breakpoints: pendingBreakpoints
		) else { return }
		wire(session)
	}

	/// Connects a session to the window, whichever debugger is behind it.
	///
	/// Every way of starting one goes through here. Wiring it at the Go entry
	/// point instead meant a session started any other way ran perfectly and
	/// told the editor nothing: no execution marker, no breakpoint state.
	func wire(_ session: DebugSession) {
		session.onBreakpointsChanged = { [weak self, weak session] in
			guard let self, let session else { return }
			self.syncBreakpointsToEditor(from: session)
		}
		session.observeStopped { [weak self] file, line in
			guard let self else { return }
			// Room to see it, before opening it. Stopping somewhere is the one
			// moment the editor has to be visible, and the panel is often not
			// merely tall but the whole window.
			self.makeRoomForTheStoppedLine()
			self.executionMarker = (file, line)
			self.editor.open(fileURL: URL(fileURLWithPath: file), atLine: line)
			self.editor.setExecutionLocation(file: file, line: line)
		}
		toolStrip.setDebugRunning(true)
		session.observeState { [weak self, weak session] state in
			self?.toolStrip.setDebugRunning(state != .idle && state != .terminated)
			self?.updateRunControl(for: state, session: session)
			// The marker must go when execution resumes or the process ends.
			switch state {
			case .running, .terminated, .idle:
				self?.executionMarker = nil
				self?.editor.setExecutionLocation(file: nil, line: nil)
			default:
				break
			}
		}
		syncBreakpointsToEditor(from: session)
	}

	/// Picks the main package, prompting only when there is more than one.
	/// The Go module these commands should act on.
	///
	/// The project root itself when it holds go.mod, otherwise whichever module
	/// was found below it — asking only when there is genuinely a choice.
	private func chooseModuleRoot(in root: URL) -> URL? {
		if GoTooling.isGoModule(root) { return root }

		let modules = RunConfigurationDiscovery
			.searchDirectories(from: root)
			.filter { GoTooling.isGoModule($0) }

		if modules.isEmpty {
			presentGoError("No go.mod was found in this project or below it.")
			return nil
		}
		if modules.count == 1 { return modules[0] }

		let alert = NSAlert()
		alert.messageText = "Which module?"
		alert.informativeText = "This project contains several Go modules."
		alert.addButton(withTitle: "Choose")
		alert.addButton(withTitle: "Cancel")

		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
		popup.addItems(withTitles: modules.map { relativeDescription(of: $0, from: root) })
		alert.accessoryView = popup

		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		return modules[popup.indexOfSelectedItem]
	}

	private func relativeDescription(of url: URL, from root: URL) -> String {
		guard url.path.hasPrefix(root.path + "/") else { return url.lastPathComponent }
		return String(url.path.dropFirst(root.path.count + 1))
	}

	private func chooseMainPackage(in root: URL) -> String? {
		let packages = GoTooling.findMainPackages(in: root)
		if packages.isEmpty {
			presentGoError("No package main found in this module.")
			return nil
		}
		if packages.count == 1 { return packages[0] }

		let alert = NSAlert()
		alert.messageText = "Which command?"
		alert.informativeText = "This module contains several main packages."
		alert.addButton(withTitle: "Run")
		alert.addButton(withTitle: "Cancel")

		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		popup.addItems(withTitles: packages)
		alert.accessoryView = popup

		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		return packages[popup.indexOfSelectedItem]
	}

	private func presentGoError(_ message: String) {
		// The first line is what fits in the corner; the rest is behind it.
		let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
		notify(firstLine, detail: message.count > firstLine.count ? message : nil)
	}

	// MARK: - Running

	/// What this project can run, refreshed off the main thread.
	private(set) var runConfigurations: [RunConfiguration] = []

	/// Where each Xcode scheme was last sent, by scheme name. Kept with the
	/// project's session, so a scheme that went to the phone yesterday goes
	/// there again today rather than back to a simulator.
	var xcodeDestinations: [String: String] = [:]

	func refreshRunConfigurations() {
		guard let project else { return }
		let root = project.root
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let found = RunConfigurationDiscovery.discover(in: root)
			DispatchQueue.main.async {
				guard let self else { return }
				self.runConfigurations = found

				// Group by file so the gutter can put a play button beside each
				// entry point and each make target.
				var byFile: [String: Set<Int>] = [:]
				for configuration in found {
					guard let file = configuration.file, let line = configuration.line else { continue }
					byFile[file, default: []].insert(line)
				}
				self.editor.setRunnableLines(byFile)
			}
		}
	}

	/// Offers what can be done with the line the play button sits on.
	///
	/// A menu rather than running straight away: run and debug are both things
	/// you want from the same marker, and a button that starts a process on a
	/// single click with no way to say which is a button you learn to distrust.
	private func runConfiguration(forFile url: URL, line: Int) {
		let path = RunConfigurationDiscovery.canonicalPath(url)
		let matching = runConfigurations.filter { $0.file == path && $0.line == line }

		// The marker is drawn from the same list, so an empty match means the
		// two have drifted — say so rather than appearing to do nothing.
		guard !matching.isEmpty else {
			presentNothingToRun(at: line, in: url)
			return
		}

		let menu = NSMenu()
		menu.autoenablesItems = false

		for (index, configuration) in matching.enumerated() {
			// The name above the verbs rather than inside them. A Go
			// configuration is called "go run app", because that is what it
			// does, and putting it after a verb produced "Run go run app" —
			// which reads as a stutter and gets longer with every source that
			// names its configurations after a command line.
			if index > 0 { menu.addItem(.separator()) }
			let header = NSMenuItem(title: configuration.name, action: nil, keyEquivalent: "")
			header.isEnabled = false
			menu.addItem(header)

			let runItem = NSMenuItem(
				title: "Run",
				action: #selector(runMenuItem(_:)),
				keyEquivalent: ""
			)
			runItem.target = self
			runItem.representedObject = configuration.id
			runItem.toolTip = configuration.commandLine
			menu.addItem(runItem)

			// Only Go can be debugged so far, and only through Delve. Listing a
			// Debug that cannot start would be worse than leaving it out.
			if configuration.isDebuggable {
				let debugItem = NSMenuItem(
					title: "Debug",
					action: #selector(debugMenuItem(_:)),
					keyEquivalent: ""
				)
				debugItem.target = self
				debugItem.representedObject = configuration.id
				menu.addItem(debugItem)
			}

			// The gutter is where a program is run the first time, so it is
			// also where the configuration for it should come from: pressing
			// play twice from the same arrow should not mean typing it in.
			//
			// Except for a test. Tests are run from every function in a file
			// and saving one for each would leave hundreds nobody wants.
			if configuration.isDebuggable, !RunConfigurationDiscovery.isTest(configuration) {
				let save = NSMenuItem(
					title: "Save as Launch Configuration\u{2026}",
					action: #selector(saveGutterConfiguration(_:)),
					keyEquivalent: ""
				)
				save.target = self
				save.representedObject = configuration.id
				menu.addItem(save)
			}
		}

		popUpAtPointer(menu)
	}

	/// Shows a menu where the pointer is, in this window's coordinates.
	private func popUpAtPointer(_ menu: NSMenu) {
		guard let contentView = window?.contentView, let window else {
			menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
			return
		}
		let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
		menu.popUp(positioning: nil, at: contentView.convert(inWindow, from: nil), in: contentView)
	}

	private func presentNothingToRun(at line: Int, in url: URL) {
		notify("Nothing to run here", detail: """
		No run configuration was found for \(url.lastPathComponent):\(line). 		This is a bug — the marker is drawn from the same list.
		""")
	}

	/// Writes a launch configuration for what the gutter would have run.
	///
	/// The arrow beside `func main` knows the package, the arguments and where
	/// it runs; a configuration written from it is the same thing with a name,
	/// and it opens for editing so the arguments can be filled in before the
	/// first run.
	@objc private func saveGutterConfiguration(_ sender: NSMenuItem) {
		guard let project, let discovered = configuration(for: sender) else { return }

		let package = MakeLaunch.relativeToWorkspace(
			path: discovered.workingDirectory, root: project.root
		)
		// A Java configuration names a class rather than a directory, and its
		// arguments are the program's — the goals that got Maven to start it are
		// not something to carry into a launch configuration.
		var configuration = discovered.mainClass.map { mainClass in
			LaunchConfiguration(
				name: discovered.name,
				type: "java",
				request: "launch",
				program: mainClass,
				workingDirectory: package,
				environment: discovered.environment
			)
		} ?? LaunchConfiguration(
			name: discovered.name,
			type: "go",
			request: "launch",
			program: package,
			arguments: discovered.arguments.filter { $0 != "run" && $0 != "." },
			workingDirectory: package,
			environment: discovered.environment
		)
		// A name that is already taken would replace something somebody else
		// wrote; the file is shared with the rest of the team.
		configuration.name = LaunchNames.free(
			like: discovered.name, avoiding: launchConfigurations.map(\.name)
		)
		presentConfigurationEditor(configuration, isNew: true)
	}

	@objc private func runMenuItem(_ sender: NSMenuItem) {
		guard let configuration = configuration(for: sender) else { return }
		run(configuration)
	}

	@objc private func debugMenuItem(_ sender: NSMenuItem) {
		guard let configuration = configuration(for: sender) else { return }
		debug(configuration)
	}

	private func configuration(for item: NSMenuItem) -> RunConfiguration? {
		guard let id = item.representedObject as? String else { return nil }
		return runConfigurations.first { $0.id == id }
	}

	/// Starts the native debugger on a configuration's package.
	func debug(_ configuration: RunConfiguration) {
		guard configuration.isDebuggable else { return }

		// Java does not go through Delve, and it does not go through a program
		// at all: the adapter is inside the language server.
		if configuration.source == .javaMain, let mainClass = configuration.mainClass {
			startJavaDebug(
				name: configuration.name,
				mainClass: mainClass,
				anchorFile: configuration.file.map { URL(fileURLWithPath: $0) },
				workingDirectory: URL(fileURLWithPath: configuration.workingDirectory),
				arguments: [],
				environment: configuration.environment
			)
			return
		}

		guard let delve = GoTooling.findDelveExecutable() else {
			notify(
				"Delve is not installed",
				detail: "Install it with: go install github.com/go-delve/delve/cmd/dlv@latest"
			)
			return
		}
		// Delve is told the directory, which is where the package lives.
		startNativeDebugger(delve: delve, package: configuration.workingDirectory)
	}

	/// Runs a configuration in a terminal session of its own.
	///
	/// A terminal rather than a captured-output pane: the thing being run is
	/// usually interactive, or prints as it goes, and watching it in a real
	/// shell is what makes it debuggable.
	func run(_ configuration: RunConfiguration) {
		// A scheme is not a command line until somewhere to run it is known,
		// and finding that out means asking `xcodebuild`, which takes long
		// enough that it cannot happen while a list of runnable things is being
		// drawn. So it happens here, once, on the way to the first run.
		if let target = configuration.xcode {
			runScheme(configuration, target: target)
			return
		}

		setPanelVisible(true)
		// Through the same reporting as anything else started here: a run from
		// the gutter is a run, and it should colour the titlebar, offer a stop
		// button, and say how it went.
		runControl?.setStatus("Running \(configuration.name)…", busy: true)

		let pane = bottomPanel.runCommand(
			title: configuration.name,
			command: configuration.commandLine,
			directory: URL(fileURLWithPath: configuration.workingDirectory),
			environment: configuration.environment,
			// This configuration's console, and it keeps it. Running the same
			// thing five times left five finished consoles behind, and the one
			// being read was whichever was on top.
			reusing: "run:\(configuration.id)"
		)
		followRunningPane(pane)
	}

	/// Watches what is selected in the editor.
	///
	/// Selecting an expression and asking to watch it is the short way round:
	/// the long way is reading it, remembering it, finding the watch field and
	/// typing it back in — during which the thing being debugged has not moved,
	/// but the attention has.
	func watchFromEditor(_ expression: String) {
		guard let pane = bottomPanel.activeDebugPane else {
			// Rather than nothing at all: the menu item is offered whenever
			// something is selected, so the answer to "why did that do nothing"
			// has to come from somewhere.
			notify(
				"Nothing to watch it in",
				detail: "Watching an expression needs a debug session. Start one and try again."
			)
			return
		}

		setPanelVisible(true)
		pane.watch(expression)
	}

	/// Runs a scheme where it went last time, or where it makes sense to.
	///
	/// The destination is asked for rather than assumed even when one is
	/// remembered, because a remembered one can be a simulator that has been
	/// deleted or a phone that is in somebody's pocket, and a build aimed at a
	/// destination that is not there fails several minutes in with a message
	/// about a scheme.
	func runScheme(_ configuration: RunConfiguration, target: XcodeTarget) {
		setPanelVisible(true)
		let directory = URL(fileURLWithPath: configuration.workingDirectory)
		let remembered = xcodeDestinations[target.scheme.name]

		// Asked once per project per session: the second run of a scheme starts
		// building immediately rather than spending twelve seconds finding out
		// what it already knows.
		let known = XcodeDestinations.shared.known(for: target)
		if let chosen = known.first(where: { $0.id == remembered })
			?? (remembered == nil ? XcodeDestinations.shared.preferred(among: known) : nil)
		{
			start(configuration, target: target, on: chosen)
			return
		}

		runControl?.setStatus("Finding where \(configuration.name) can run…", busy: true)
		Task { @MainActor in
			let found = await XcodeDestinations.shared.destinations(
				for: target, workingDirectory: directory
			)
			guard let destination = found.first(where: { $0.id == remembered })
				?? XcodeDestinations.shared.preferred(among: found)
			else {
				self.runControl?.setStatus("No destination for \(configuration.name)", failed: true)
				self.notify(
					"Nowhere to run \(configuration.name)",
					detail: "xcodebuild lists no destination for this scheme. "
						+ "A device has to be connected and unlocked, and a simulator has to be "
						+ "installed for the deployment target."
				)
				return
			}
			self.start(configuration, target: target, on: destination)
		}
	}

	/// Builds, installs and launches, in the terminal where the output is.
	func start(_ configuration: RunConfiguration, target: XcodeTarget, on destination: XcodeDestination) {
		xcodeDestinations[target.scheme.name] = destination.id


		let directory = URL(fileURLWithPath: configuration.workingDirectory)
		let derived = XcodeRun.derivedDataPath(for: target.scheme, in: directory)
		let command = XcodeRun.command(
			project: target.project,
			scheme: target.scheme,
			destination: destination,
			derivedData: derived
		) ?? XcodeRun.build(
			project: target.project,
			scheme: target.scheme,
			destination: destination,
			derivedData: derived
		)

		runControl?.setStatus("Running \(configuration.name) on \(destination.title)…", busy: true)
		let pane = bottomPanel.runCommand(
			// The destination in the title, because "docscanner-ios" twice over
			// is two tabs nobody can tell apart, and where it went is the thing
			// that differs.
			title: "\(configuration.name) · \(destination.title)",
			command: command,
			directory: directory,
			environment: configuration.environment,
			reusing: "run:\(configuration.id)"
		)
		followRunningPane(pane)
	}

	/// Watches a pane's process, so the titlebar says what became of it.
	private func followRunningPane(_ pane: TerminalPane?) {
		runningPane = pane
		// The panel sets this too — it is how a tab learns its process has
		// gone, and so how a run tab stops wearing the running green. Taking
		// the handler rather than adding to it left the tab green over
		// `[process exited]`.
		let panelHandler = pane?.terminalView.onProcessExit
		pane?.terminalView.onProcessExit = { [weak self, weak pane] code in
			panelHandler?(code)
			MainActor.assumeIsolated {
				guard let self, self.runningPane === pane else { return }
				self.runningPane = nil
				self.runControl?.setStatus(
					code == 0 ? "Finished — exit code 0" : "Failed — exit code \(code)",
					failed: code != 0
				)
			}
		}
	}

	/// What this project offers to run, as the picker would group it.
	func runConfigurationsForTesting() -> String {
		guard !runConfigurations.isEmpty else { return "nothing" }
		return runConfigurations
			.map { "\(title(for: $0.source)): \($0.name) → \($0.executable) \($0.arguments.joined(separator: " "))" }
			.joined(separator: "\n  ")
	}

	/// Shows every configuration, for the Run menu.
	@objc func showRunConfigurations(_ sender: Any?) {
		guard !runConfigurations.isEmpty else {
			notify(
				"Nothing to run",
				detail: "No run configurations, makefiles or Go entry points were found in this project."
			)
			return
		}

		let menu = NSMenu()
		menu.autoenablesItems = false
		var lastSource: RunConfiguration.Source?

		for configuration in runConfigurations {
			if configuration.source != lastSource {
				if lastSource != nil { menu.addItem(.separator()) }
				let header = NSMenuItem(title: title(for: configuration.source), action: nil, keyEquivalent: "")
				header.isEnabled = false
				menu.addItem(header)
				lastSource = configuration.source
			}

			let item = NSMenuItem(title: configuration.name, action: #selector(runMenuItem(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = configuration.id
			item.toolTip = configuration.commandLine

			// A scheme runs somewhere, and where is a second choice beside it
			// rather than an entry of its own for each combination: a machine
			// with several simulator runtimes offers dozens, and a list of
			// dozens is not a list anybody reads.
			if let target = configuration.xcode {
				item.submenu = destinationMenu(for: configuration, target: target)
			}
			menu.addItem(item)
		}

		// Centred in the window: this is reached from the menu bar and from ⌃R,
		// so the pointer is not where the user is looking. The previous version
		// converted a screen point that was already in screen coordinates and
		// placed the menu off the window entirely.
		guard let contentView = window?.contentView else { return }
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY),
			in: contentView
		)
	}

	/// The one run mark, kept between menus and remade when the zoom changes.
	private static var cachedRunMark: (scale: CGFloat, image: NSImage?) = (0, nil)

	/// The mark on a menu item that will run something, in place of a tick.
	///
	/// A ticked list is what a settings menu looks like — "Word Wrap", "Show
	/// Invisibles", things somebody turns on — and neither the schemes nor the
	/// destinations under them are that: clicking one runs the app. The glyph is
	/// the play button's own, in the play button's own green, so the menu and
	/// the button it hangs off say the same thing. It goes in the tick's column
	/// rather than beside the title, which is what keeps the titles lined up
	/// with each other and with the headings above them.
	///
	/// One image rather than one per item, which is also what lets a printed
	/// dump tell a run mark from a tick.
	private static func runMark() -> NSImage? {
		let scale = Theme.current.scale
		if cachedRunMark.scale == scale { return cachedRunMark.image }
		let image = Theme.symbol("play.fill", size: 10 * scale, color: Theme.current.gitAdded)
		// Not a template: AppKit re-tints a template state image with the menu's
		// own ink, and the colour is half of what this glyph is for.
		image?.isTemplate = false
		cachedRunMark = (scale, image)
		return image
	}

	/// Marks the one item a click would actually start, the way the tick used to.
	///
	/// The tick is left alone if there is no glyph to put there: a menu item
	/// whose on-state image is nil shows nothing at all, and an unmarked list is
	/// worse than the one this was meant to fix.
	private func markWillRun(_ item: NSMenuItem, _ willRun: Bool) {
		item.state = willRun ? .on : .off
		if let mark = MainWindowController.runMark() { item.onStateImage = mark }
	}

	/// Where a scheme can go, with a run mark beside where it went last.
	///
	/// Filled in as the answer arrives rather than before the menu opens: the
	/// question takes about twelve seconds and a menu that waits for it is a
	/// menu that does not open. Items are added to a menu that may already be
	/// on screen, which AppKit allows and which is the whole point — the list
	/// grows under the pointer instead of appearing a keystroke later.
	private func destinationMenu(for configuration: RunConfiguration, target: XcodeTarget) -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false

		let known = XcodeDestinations.shared.known(for: target)
		if known.isEmpty {
			let waiting = NSMenuItem(title: "Finding destinations…", action: nil, keyEquivalent: "")
			waiting.isEnabled = false
			menu.addItem(waiting)

			let directory = URL(fileURLWithPath: configuration.workingDirectory)
			Task { @MainActor in
				let found = await XcodeDestinations.shared.destinations(
					for: target, workingDirectory: directory
				)
				menu.removeAllItems()
				if found.isEmpty {
					let empty = NSMenuItem(title: "No destinations", action: nil, keyEquivalent: "")
					empty.isEnabled = false
					menu.addItem(empty)
					return
				}
				self.fill(menu, with: found, for: configuration, target: target)
			}
		} else {
			fill(menu, with: known, for: configuration, target: target)
		}
		return menu
	}

	private func fill(
		_ menu: NSMenu,
		with destinations: [XcodeDestination],
		for configuration: RunConfiguration,
		target: XcodeTarget
	) {
		let remembered = xcodeDestinations[target.scheme.name]
			?? XcodeDestinations.shared.preferred(among: destinations)?.id

		// This Mac and the devices on the desk in full, then one simulator per
		// family — the newest of each — and the other seventy-odd behind a
		// dialog that can be typed into. A real project answers with 79
		// destinations, of which 75 are simulators, and a menu that long is a
		// column running off the screen with no way to search it.
		let shortlist = XcodeDestinationMenu.newestOfEachFamily(among: destinations)
		let rest = XcodeDestinationMenu.rest(among: destinations, shown: shortlist)
		let inMenu = destinations.filter { $0.kind != .simulator } + shortlist

		// This Mac, then the phones and iPads, then the simulators — the order
		// somebody scans in. `xcodebuild` happens to answer in this order;
		// sorting says so rather than relying on it.
		let order: [XcodeDestination.Kind] = [.mac, .device, .simulator]
		let sorted = inMenu.enumerated().sorted { left, right in
			let a = order.firstIndex(of: left.element.kind) ?? order.count
			let b = order.firstIndex(of: right.element.kind) ?? order.count
			// Within a kind, the order they came in: simulators arrive grouped
			// by model and sorted by runtime, which is more useful than
			// alphabetical.
			return a != b ? a < b : left.offset < right.offset
		}.map(\.element)

		var lastKind: XcodeDestination.Kind?
		for destination in sorted {
			if destination.kind != lastKind {
				if lastKind != nil { menu.addItem(.separator()) }
				lastKind = destination.kind
				// Said rather than implied. A simulator and the phone on the
				// desk are one list of names otherwise, and "iPad (A16)" reads
				// like a device somebody owns — the runtime in brackets after
				// it is not what anybody notices first.
				//
				// This Mac belongs with the devices: it is a real machine, and
				// the heading is about what the thing is rather than what
				// `xcodebuild` calls its platform.
				let heading = NSMenuItem(
					title: destination.kind == .simulator ? "Simulators" : "Devices",
					action: nil, keyEquivalent: ""
				)
				heading.isEnabled = false
				menu.addItem(heading)
			}

			// How it is attached, beside its name: a phone on a cable and one
			// paired over Wi-Fi are offered identically by `xcodebuild`, and
			// the difference only shows up minutes later as an install that
			// times out.
			let attachment = XcodeDestinations.shared.attachment(of: destination)?.attachment
			let item = NSMenuItem(
				title: attachment.map { "\(destination.title) — \($0)" } ?? destination.title,
				action: #selector(runOnDestination(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = [configuration.id, destination.id]
			// The same mark as the scheme above it, because it means the same
			// thing one level down: the scheme says what will run and the
			// destination says where, and together they are the single path the
			// play button takes. Two different marks for one sentence is what
			// made this pair read as two unrelated settings.
			markWillRun(item, destination.id == remembered)
			menu.addItem(item)
		}

		// Nothing is hidden, only moved: everything the shortlist left out is
		// here, and a chosen one is remembered like any other.
		guard !rest.isEmpty else { return }
		menu.addItem(.separator())
		let more = NSMenuItem(
			title: "Other Simulators… (\(rest.count))",
			action: #selector(chooseOtherDestination(_:)),
			keyEquivalent: ""
		)
		more.target = self
		more.representedObject = [configuration.id]
		menu.addItem(more)

		// A device plugged in since is noticed on its own — `devicectl` is
		// asked every time this menu opens and is quick about it. A simulator
		// installed since is not: nothing cheap reports one, and asking
		// `xcodebuild` costs twelve seconds, which is not a thing to spend
		// every time somebody looks at a menu. So it is offered.
		let again = NSMenuItem(
			title: "Look Again…",
			action: #selector(refreshDestinations(_:)),
			keyEquivalent: ""
		)
		again.target = self
		again.representedObject = [configuration.id]
		menu.addItem(again)
	}

	@objc private func refreshDestinations(_ sender: NSMenuItem) {
		guard let pair = sender.representedObject as? [String], let id = pair.first,
		      let configuration = runConfigurations.first(where: { $0.id == id }),
		      let target = configuration.xcode
		else { return }

		Task { @MainActor in
			_ = await XcodeDestinations.shared.destinations(
				for: target,
				workingDirectory: URL(fileURLWithPath: configuration.workingDirectory),
				refresh: true
			)
			// Rebuilt rather than left to the next opening: somebody who asks
			// for this is standing in front of the menu waiting for it.
			refreshRunConfigurations()
		}
	}

	@objc private func chooseOtherDestination(_ sender: NSMenuItem) {
		guard let pair = sender.representedObject as? [String], let id = pair.first,
		      let configuration = runConfigurations.first(where: { $0.id == id }),
		      let target = configuration.xcode
		else { return }

		let all = XcodeDestinations.shared.known(for: target)
		let shortlist = XcodeDestinationMenu.newestOfEachFamily(among: all)
		let rest = XcodeDestinationMenu.rest(among: all, shown: shortlist)
		DestinationPicker.show(among: rest, relativeTo: window) { [weak self] chosen in
			guard let self else { return }
			self.selectedConfigurationName = configuration.name
			self.start(configuration, target: target, on: chosen)
		}
	}

	@objc private func runOnDestination(_ sender: NSMenuItem) {
		guard let pair = sender.representedObject as? [String],
		      pair.count == 2,
		      let configuration = runConfigurations.first(where: { $0.id == pair[0] }),
		      let target = configuration.xcode
		else { return }

		let chosen = XcodeDestinations.shared.known(for: target).first { $0.id == pair[1] }
		guard let chosen else { return }

		// Chosen on purpose, so it becomes what the play button repeats.
		selectedConfigurationName = configuration.name
		start(configuration, target: target, on: chosen)
	}

	private func title(for source: RunConfiguration.Source) -> String {
		switch source {
		case .intelliJ:  return "IntelliJ"
		case .vscode:    return "VS Code"
		case .make:      return "Make"
		case .goModule:  return "Go"
		case .maven:     return "Maven"
		case .gradle:    return "Gradle"
		case .javaMain:  return "Java"
		case .xcodeScheme: return "Schemes"
		case .bazel:     return "Bazel"
		case .conan:     return "Conan"
		}
	}

	/// Starts an agent review of this branch, reported over MCP.
	@objc func reviewBranch(_ sender: Any?) {
		setPanelVisible(true)

		Task { @MainActor in
			// Compare against the repository's default branch when we can tell
			// what it is, rather than assuming "main".
			let base = await defaultBaseBranch()
			startReview(scope: .branch(base: base))
		}
	}

	/// Reviews what is in the working tree but not yet committed.
	@objc func reviewUncommittedChanges(_ sender: Any?) {
		Task { @MainActor in
			// Checked first: starting an agent, waiting for it to look around and
			// report nothing is a slow way to learn there was nothing to review.
			if let project, let git = project.git {
				let root = await git.root
				let status = await GitRepository.run(["status", "--porcelain"], in: root)
				if status.exitCode == 0,
				   status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					presentReviewProblem(
						title: "Nothing to review",
						message: "The working tree is clean — there are no uncommitted changes."
					)
					return
				}
			}

			setPanelVisible(true)
			startReview(scope: .uncommitted)
		}
	}

	private func startReview(scope: AgentLauncher.ReviewScope) {
		if case let .failure(error) = bottomPanel.startReview(scope: scope) {
			presentReviewProblem(title: "Could not start the review", message: error.message)
		}
	}

	/// Reports a reason a review did not start.
	///
	/// A sheet rather than an application-modal alert: it is attached to the
	/// window it concerns and does not stop the rest of the app, which matters
	/// for something as ordinary as a clean working tree.
	private func presentReviewProblem(title: String, message: String) {
		notify(title, detail: message)
	}

	/// Best guess at the branch a review should compare against.
	private func defaultBaseBranch() async -> String {
		guard let project, let git = project.git else { return "main" }
		let root = await git.root

		// origin/HEAD names the default branch when the remote has been fetched.
		let result = await GitRepository.run(["symbolic-ref", "refs/remotes/origin/HEAD"], in: root)
		if result.exitCode == 0 {
			let reference = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
			if let name = reference.split(separator: "/").last, !name.isEmpty {
				return String(name)
			}
		}
		// Otherwise prefer whichever of the usual names exists.
		for candidate in ["main", "master"] {
			let exists = await GitRepository.run(["rev-parse", "--verify", candidate], in: root)
			if exists.exitCode == 0 { return candidate }
		}
		return "main"
	}

	@objc func newTerminal(_ sender: Any?) {
		setPanelVisible(true)
		bottomPanel.newTerminal()
	}

	/// Follows ⌘-click, through the same path the click takes.
	func exerciseGoToDefinitionForTesting(line: Int, character: Int) {
		let before = editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing"
		editor.goToDefinitionForTesting(line: line, character: character)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
			guard let self else { return }
			let after = self.editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing"
			print("DEFINITION: \(before) → \(after) \(self.editor.caretReportForTesting)")
		}
	}

	/// Right-clicks in the editor and finds usages of whatever is at the caret.
	func exerciseFindUsagesForTesting(line: Int, character: Int) {
		guard let url = editor.activeGroup?.activeTabURL else { return }
		findUsages(in: url, line: line, character: character)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
			guard let self else { return }
			let rows = self.usagesPanel.rowsForTesting
			print("USAGES: \(rows.count) rows")
			for row in rows.prefix(8) { print("USAGE: \(row)") }

			if self.shouldDockUsagesForTesting {
				self.usagesPanel.dockForTesting()
				print("USAGES: docked=\(self.hasDockedPaneForTesting)")
			}
		}
	}

	/// Opens the palette, types a query, and says what came back.
	func exerciseSymbolPaletteForTesting(_ query: String, project: Bool) {
		symbolPalette.show(scope: project ? .workspace : .document, over: window)
		symbolPalette.setQueryForTesting(query)

		DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
			guard let self else { return }
			let results = self.symbolPalette.resultsForTesting
			print("SYMBOLS: \(results.count) for “\(query)” reason=“\(self.reasonForNoSymbols(query: query, scope: project ? .workspace : .document))”")
			for result in results.prefix(6) { print("SYMBOL: \(result)") }

			self.symbolPalette.openFirstForTesting()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				print("SYMBOLS: opened \(self.editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing")")
			}
		}
	}

	/// Everything in this file, or everything in the project.
	@objc func goToSymbolInFile(_ sender: Any?) {
		symbolPalette.show(scope: .document, over: window)
	}

	@objc func goToSymbolInProject(_ sender: Any?) {
		symbolPalette.show(scope: .workspace, over: window)
	}

	/// Puts an agent on what the language server is complaining about.
	///
	/// The same Claude Code that reviews a branch, given one problem instead:
	/// the file, the line, the message, and the instruction to keep the change
	/// to what is wrong. It opens in the panel so the fix can be read, argued
	/// with, and undone like any other edit.
	private func fixWithAI(url: URL, line: Int, diagnostic: LSPDiagnostic) {
		guard let root = project?.root else { return }
		let relative = url.path.replacingOccurrences(of: FilePath.canonical(root) + "/", with: "")

		let prompt = """
		Fix this problem, reported by the language server in \(relative) at line \(line + 1):

		\(diagnostic.message)

		Read the file first. Change as little as possible: the fix is for this \
		problem, not for anything else you find on the way. Say in one sentence \
		what you changed and why.
		"""

		setPanelVisible(true)
		if case let .failure(error) = bottomPanel.startAgent(title: "Fix", prompt: prompt) {
			notify("Could not start the agent", detail: error.message)
		}
	}

	/// Opens the profiler on the bottom panel.
	@objc func showProfiler(_ sender: Any?) {
		setPanelVisible(true)
		bottomPanel.showProfiler(address: Self.lastProfilerAddress)
	}

	/// Remembered for the session: the same program is usually profiled more
	/// than once in a sitting.
	static var lastProfilerAddress = "localhost:6060"

	/// Puts a view in the sidebar, under whichever tool is showing.
	///
	/// Results are worth keeping beside the code rather than on top of it: a
	/// list of usages is something you work through, and a window that covers
	/// what you are reading is in the way by the second one.
	func dockInSidebar(_ view: NSView, title: String) {
		dockedView?.removeFromSuperview()

		let host = DockedPane(title: title, content: view)
		host.onClose = { [weak self] in self?.undockFromSidebar() }
		host.translatesAutoresizingMaskIntoConstraints = false
		dockContainer.addSubview(host)
		NSLayoutConstraint.activate([
			host.topAnchor.constraint(equalTo: dockContainer.topAnchor),
			host.bottomAnchor.constraint(equalTo: dockContainer.bottomAnchor),
			host.leadingAnchor.constraint(equalTo: dockContainer.leadingAnchor),
			host.trailingAnchor.constraint(equalTo: dockContainer.trailingAnchor),
		])
		dockedView = host

		dockContainer.isHidden = false
		if navigatorContainer.isHidden { toggleNavigator(nil) }

		// The tool keeps the larger share the first time, and the divider can be
		// dragged to whatever suits after that. Positioned once the split has a
		// height: asking before it has laid out sets a divider in a view that
		// is still zero tall, which leaves the docked pane filling everything.
		placeDockDivider(attemptsLeft: 20)
	}

	private func placeDockDivider(attemptsLeft: Int) {
		navigatorContainer.layoutSubtreeIfNeeded()
		let height = sidebarSplit.bounds.height
		guard height > 200 else {
			guard attemptsLeft > 0 else { return }
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
				self?.placeDockDivider(attemptsLeft: attemptsLeft - 1)
			}
			return
		}
		sidebarSplit.setPosition(height * 0.6, ofDividerAt: 0)
	}

	func undockFromSidebar() {
		dockedView?.removeFromSuperview()
		dockedView = nil
		dockContainer.isHidden = true
	}

	var hasDockedPaneForTesting: Bool { dockedView != nil }
	var shouldDockUsagesForTesting = false

	/// Everywhere the symbol at a position is used.
	///
	/// The server's answer rather than a text search: it knows a `Close` on one
	/// type from a `Close` on another, which grep never will.
	private func findUsages(in url: URL, line: Int, character: Int) {
		guard let project, let languageId = editor.activeGroup?.activeDocument?.languageId else { return }

		Task { @MainActor in
			let locations = await LanguageService.shared.references(
				url: url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: project.root
			)
			guard !locations.isEmpty else {
				notify("No usages found", kind: .information)
				return
			}
			// One result is not a list; it is the place to go.
			if locations.count == 1, let only = locations.first, let target = only.url {
				editor.open(fileURL: target, atLine: only.range.start.line + 1)
				return
			}
			usagesPanel.show(locations: locations, over: window)
		}
	}

	/// Why the symbol list is empty, in a sentence somebody can act on.
	private func reasonForNoSymbols(query: String, scope: SymbolPalette.Scope) -> String {
		guard let project else { return "No project is open." }
		let status = LanguageService.shared.serverStatus(project: project.root)

		// About the file that is open, not about the project. A project with
		// Go and TypeScript in it is missing the TypeScript server whether or
		// not that has anything to do with the Go file on screen — and being
		// told to install a TypeScript server while looking at main.go reads
		// like the editor has lost track of what it is showing.
		if scope == .document {
			guard let languageId = editor.activeGroup?.activeDocument?.languageId else {
				return "Open a file to see what it declares."
			}
			if let missing = status.missing.first(where: { $0.language == languageId }) {
				return "No language server for \(missing.language).\n\(missing.hint)"
			}
			// A server that has already said it cannot work is the answer to
			// "why is this empty" — better than the guess that it might still
			// be starting, which it will never stop doing.
			if let failure = LanguageService.shared.failures[languageId] {
				return "The \(languageId) language server cannot read this project.\n\(failure)"
					+ "\n\n\(LanguageService.logPath) has the rest."
			}
			return query.isEmpty
				? "Nothing declared in this file, or the language server is still starting."
				: "Nothing matching \u{201C}\(query)\u{201D}."
		}

		if status.running.isEmpty, let missing = status.missing.first {
			return "No language server for \(missing.language).\n\(missing.hint)"
		}
		if status.running.isEmpty {
			return "No language server is running for this project."
		}
		if scope == .workspace, query.isEmpty {
			return "Type to search \(status.running.joined(separator: ", "))."
		}
		if scope == .document, editor.activeGroup?.activeTabURL == nil {
			return "Open a file to see what it declares."
		}
		return query.isEmpty ? "Nothing to show." : "Nothing matching “\(query)”."
	}

	private func symbols(matching query: String, scope: SymbolPalette.Scope) async -> [LSPSymbol] {
		guard let project else { return [] }

		switch scope {
		case .workspace:
			// An empty query would ask the server for every symbol it knows,
			// which for a large project is a great deal of nothing useful.
			guard !query.isEmpty else { return [] }
			return await LanguageService.shared
				.workspaceSymbols(matching: query, project: project.root)
				.sorted { better($0, than: $1, for: query) }
				.prefix(200)
				.map { $0 }

		case .document:
			guard let url = editor.activeGroup?.activeTabURL,
			      let languageId = editor.activeGroup?.activeDocument?.languageId
			else { return [] }

			// A Makefile has no language server, and the grammar it borrows is
			// bash's, which knows nothing about targets — so the one file in a
			// project that is a list of named things was the one file this
			// could not list. Its own parser already reads them.
			//
			// Asked of the file, not of the language. Borrowing bash's grammar
			// means the language *is* bash, so the question this used to ask
			// ("is the language makefile?") had no answer but no, and ⇧⌘O on a
			// Makefile came back empty in every project.
			// A build file is in the same position, for the same reason: a POM
			// borrows HTML's grammar and a Gradle build borrows Groovy's or
			// Kotlin's, and none of those knows a module from a dependency. The
			// build files' own parsers do.
			let buildSymbols: [LSPSymbol]? = {
				if Makefile.isMakefile(url) { return Makefile.symbols(at: url) }
				if MavenProject.isPom(url) { return MavenProject.symbols(at: url) }
				if GradleBuild.isBuildFile(url) { return GradleBuild.symbols(at: url) }
				return nil
			}()
			if let buildSymbols {
				guard !query.isEmpty else { return buildSymbols }
				return buildSymbols.filter { $0.name.localizedCaseInsensitiveContains(query) }
			}

			let all = await LanguageService.shared
				.documentSymbols(url: url, languageId: languageId, project: project.root)
			guard !query.isEmpty else { return all }
			return all
				.filter { $0.name.localizedCaseInsensitiveContains(query) }
				.sorted { better($0, than: $1, for: query) }
		}
	}

	/// Exact match first, then prefix, then merely containing it.
	///
	/// Servers match loosely — sourcekit-lsp will happily return a five-hundred
	/// character initialiser for a three-letter query — so the sort has to put
	/// what was actually asked for at the top. Ties go to the shorter name,
	/// which is nearly always the one meant.
	private func better(_ left: LSPSymbol, than right: LSPSymbol, for query: String) -> Bool {
		let leftRank = rank(left, for: query)
		let rightRank = rank(right, for: query)
		if leftRank != rightRank { return leftRank < rightRank }
		if left.name.count != right.name.count { return left.name.count < right.name.count }
		return left.name < right.name
	}

	private func rank(_ symbol: LSPSymbol, for query: String) -> Int {
		let name = symbol.name.lowercased()
		let needle = query.lowercased()
		if name == needle { return 0 }
		if name.hasPrefix(needle) { return 1 }
		if name.contains(needle) { return 2 }
		return 3
	}

	// MARK: - Launch configurations

	/// What the project defines, plus a suggestion when it defines nothing.
	private var launchConfigurations: [LaunchConfiguration] {
		guard project != nil else { return [] }
		return LaunchStore.read(in: launchRoot)
	}

	/// What the play button is pointed at, decided in one place.
	///
	/// The strip and the button used to work this out separately, and disagreed
	/// exactly where it mattered: with a Makefile goal chosen in a project that
	/// has launch configurations of its own, the strip fell back to the first
	/// configuration while the button ran the goal.
	private var runTarget: RunSelection.Target {
		RunSelection.resolve(
			configurations: launchConfigurations.map(\.name),
			makeRun: selectedMakeRun?.name,
			selected: selectedConfigurationName
		)
	}

	private var selectedConfiguration: LaunchConfiguration? {
		guard case let .configuration(name) = runTarget else { return nil }
		return launchConfigurations.first { $0.name == name }
	}

	func refreshRunControl() {
		runControl?.setConfiguration(RunSelection.displayName(
			configurations: launchConfigurations.map(\.name),
			makeRun: selectedMakeRun?.name,
			selected: selectedConfigurationName
		))
	}

	/// Keeps the titlebar saying what the session is doing.
	private func updateRunControl(for state: DebugSession.State, session: DebugSession?) {
		switch state {
		case .starting:
			runControl?.setStatus("Starting…", busy: true)
		case .running:
			runControl?.setStatus("Running", busy: true)
		case let .stopped(reason):
			runControl?.setStatus("Paused — \(reason)", busy: true)
		case .terminated:
			guard let code = session?.exitCode else {
				runControl?.setStatus("Finished")
				return
			}
			runControl?.setStatus(
				code == 0 ? "Finished — exit code 0" : "Failed — exit code \(code)",
				failed: code != 0
			)
		case .idle:
			runControl?.setStatus("")
		}
	}

	/// Runs or debugs what is selected.
	///
	/// A project with nothing configured gets one written for it from what is
	/// actually there, rather than a dialog asking a question nobody has the
	/// information to answer before the first run.
	/// Stops whichever of the two is running.
	private func stopRunning() {
		// A launch still working its way through the cluster is the thing most
		// worth being able to stop: it is the part that waits.
		if let task = clusterTask {
			clusterTask = nil
			task.cancel()
			stopDevPodForwards()
			clusterLog("stopped")
			runControl?.setStatus("Stopped")
			return
		}
		if devPodClient != nil {
			stopDevPod()
			return
		}
		if let pane = runningPane {
			runningPane = nil
			pane.terminalView.terminateProcess()
			// The tab is showing a running program; it has just stopped being
			// one.
			bottomPanel.refreshTabs()
			runControl?.setStatus("Stopped")
			return
		}
		debugStop(nil)
	}

	func pushChangesForTesting() { changesPane?.pushForTesting() }

	/// Clicks into the commit details field and types there.
	///
	/// Opens the pane first: it is only built once the repository has been
	/// read, so asking too early finds nothing and says so.
	func typeInCommitBodyForTesting(_ text: String) -> String {
		if changesPane == nil { showSidebarTool(.changes) }
		guard let pane = changesPane else { return "no changes pane" }
		window?.layoutIfNeeded()
		return pane.typeInCommitBodyForTesting(text)
	}

	/// Runs a tab's close command and prints what is left.
	func closeTabsForTesting(_ command: String, at index: Int) {
		guard let group = editor.activeGroup else { return }
		group.closeTabsForTesting(command, at: index)
		print("TABS: \(group.tabTitlesForTesting.joined(separator: ", "))")
	}

	/// Chooses a configuration by name, as the menu does.
	func selectConfigurationForTesting(named name: String) {
		selectedConfigurationName = name
		refreshRunControl()
	}

	/// Runs the selected configuration and puts the profiler on it.
	func profileSelectedForTesting() { profileSelectedConfiguration() }

	/// Opens two terminals side by side, as dropping one tab on the other's
	/// edge does.
	func splitTerminalsForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		bottomPanel.newTerminal()
		bottomPanel.splitForTesting()
	}

	/// Puts the profiler beside a terminal, as the tab menu does.
	func splitPanesForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		bottomPanel.showProfiler(address: Self.lastProfilerAddress)
		bottomPanel.splitFirstBesideForTesting()
	}

	/// Splits, then does the things that used to collapse a split: opens a
	/// terminal, and activates another tab.
	func splitThenDisturbForTesting() {
		splitPanesForTesting()
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			self?.bottomPanel.newTerminal()
			self?.bottomPanel.selectTabForTesting(0)
		}
	}

	/// One terminal, then "put it beside" — which is what somebody does first
	/// and what used to do nothing at all.
	func splitActiveForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
			self?.bottomPanel.splitActiveBesideForTesting()
		}
	}

	/// Puts settings in a group beside the editor and drags the divider between
	/// them, which is the only way to see this without a hand on the mouse.
	///
	/// A drag is a `setPosition` and the layout passes that follow it, so the
	/// position is set and then every stage is measured: the moment it is set,
	/// after the split has laid out, after the window has, and again once the
	/// run loop has been round. A width that is right at one stage and wrong at
	/// the next says which pass took it back.
	///
	/// `settings: false` is the control: the same two panes with a file in each,
	/// which says whether what happens is the page's doing or the split's.
	func dragSettingsDividerForTesting(to position: Double, settings: Bool = true) {
		guard editor.activeGroup?.activeTabURL != nil else {
			print("DIVIDER: nothing open to split")
			return
		}
		splitEditorRight(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
			guard let self else { return }
			if settings { self.showSettingsPage(nil) }
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				self.reportDividerDrag(to: CGFloat(position))
			}
		}
	}

	private func reportDividerDrag(to position: CGFloat) {
		guard let split = editor.rootSplitForTesting, split.arrangedSubviews.count == 2 else {
			print("DIVIDER: no split of two groups")
			return
		}
		func report(_ stage: String) {
			let panes = split.arrangedSubviews
				.map { String(format: "%.0f", $0.frame.width) }
				.joined(separator: "|")
			print(String(
				format: "DIVIDER %@: window=%.0f total=%.0f panes=%@",
				stage, self.window?.frame.width ?? 0, split.bounds.width, panes
			))
		}
		for (index, pane) in split.arrangedSubviews.enumerated() {
			print(String(
				format: "DIVIDER pane%d: autoresizing=%@ fitting=%.0f",
				index,
				pane.translatesAutoresizingMaskIntoConstraints ? "yes" : "no",
				pane.fittingSize.width
			))
		}
		report("before")
		if let groups = split as? EditorGroupSplitView {
			groups.dragDividerForTesting(to: position)
		} else {
			split.setPosition(position, ofDividerAt: 0)
		}
		report("set")
		split.layoutSubtreeIfNeeded()
		report("split laid out")
		window?.contentView?.layoutSubtreeIfNeeded()
		report("window laid out")
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			report("settled")
			// And what a narrower window does to the position somebody set,
			// which is the other half of a divider staying where it was put.
			// Put back afterwards, since the window remembers its size and a
			// run that measures something should not change it.
			if let window = self.window {
				let frame = window.frame
				var narrower = frame
				narrower.size.width -= 300
				window.setFrame(narrower, display: true, animate: false)
				window.contentView?.layoutSubtreeIfNeeded()
				report("window narrowed")
				window.setFrame(frame, display: true, animate: false)
				window.contentView?.layoutSubtreeIfNeeded()
				report("window back")
			}
			for (index, pane) in split.arrangedSubviews.enumerated() {
				for constraint in pane.constraintsAffectingLayout(for: .horizontal) {
					print("DIVIDER pane\(index) width: \(constraint)")
				}
			}
			fflush(stdout)
		}
	}

	/// Shows the split preview a drag would show.
	func previewTerminalDropForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		bottomPanel.previewDropForTesting()
	}

	func tearOffTerminalForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		let point = window.map { NSPoint(x: $0.frame.maxX + 80, y: $0.frame.midY) } ?? .zero
		bottomPanel.tearOffForTesting(at: point)
	}

	/// Renames the terminal in front, the way a double-click on its tab does.
	func renameActiveTerminalForTesting(to name: String) {
		setPanelVisible(true)
		// An empty name opens the editor and leaves it there, which is how the
		// field itself gets captured.
		if name.isEmpty {
			bottomPanel.beginRenameActiveForTesting()
		} else {
			bottomPanel.renameActiveForTesting(to: name)
		}
	}

	/// What the toolbar is showing, and what it has put away.
	func reportToolbarForTesting() {
		guard let toolbar = window?.toolbar else { return }
		let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier.rawValue))
		let all = toolbar.items.map(\.itemIdentifier.rawValue)
		let hidden = all.filter { !visible.contains($0) && !$0.hasPrefix("NSToolbar") }
		print("TOOLBAR visible=\(visible.filter { !$0.hasPrefix("NSToolbar") }.sorted()) hidden=\(hidden)")

		for item in toolbar.items where !visible.contains(item.itemIdentifier.rawValue) {
			let menu = item.menuFormRepresentation
			print("  put away: \(item.itemIdentifier.rawValue) menu=\(menu?.title ?? "none") "
				+ "submenu=\(menu?.submenu?.items.map(\.title).prefix(4) ?? [])")
		}

		if let capsule {
			print("  capsule height=\(capsule.frame.height) in row=\(capsule.superview?.frame.height ?? 0)")
		}
	}

	/// Derives a launch configuration from the gutter's arrow and prints it.
	func saveGutterConfigurationForTesting(file: URL, line: Int) {
		let path = RunConfigurationDiscovery.canonicalPath(file)
		guard let discovered = runConfigurations.first(where: { $0.file == path && $0.line == line })
			?? runConfigurations.first
		else {
			print("GUTTER: nothing to run at \(file.lastPathComponent):\(line)")
			return
		}
		let item = NSMenuItem()
		item.representedObject = discovered.id
		saveGutterConfiguration(item)
		print("GUTTER: opened the editor for \(discovered.name)")
	}

	/// Derives a configuration from a make goal and starts it.
	/// Picks a Makefile goal from the run menu exactly as clicking it does, and
	/// says what the run control shows afterwards.
	func chooseMakeRunForTesting(_ goal: String) {
		let goals = makeGoals()
		print("MAKE RUNS: \(goals.map(\.name))")
		guard let found = goals.first(where: { $0.name == goal }) else {
			print("MAKE: no goal called \(goal)")
			return
		}
		let item = NSMenuItem()
		item.representedObject = [found.makefile.path.path, found.name]
		makeGoalChosen(item)
		print("MAKE SELECTED: \(runControl?.selectedNameForTesting ?? "(none)")")
	}

	/// What play would start right now, without starting it.
	func describeRunTargetForTesting() {
		switch runTarget {
		case let .make(name):          print("MAKE PLAY: \(name)")
		case let .configuration(name): print("MAKE PLAY: \(name)")
		case .none:                    print("MAKE PLAY: (nothing)")
		}
	}

	func runMakeGoalForTesting(_ goal: String, debug: Bool) {
		guard let project else { return }
		let goals = debuggableMakeGoals()
		print("MAKE GOALS: \(goals.map(\.name))")

		guard let found = goals.first(where: { $0.name == goal }),
		      let configuration = MakeLaunch.configuration(
		          for: goal, in: found.makefile, projectRoot: project.root
		      )
		else {
			print("MAKE: no plan for \(goal)")
			return
		}
		_ = try? LaunchStore.save(configuration, in: launchRoot)
		selectedConfigurationName = configuration.name
		refreshRunControl()

		print("MAKE CONFIG: \(configuration.json)")
		if debug {
			debugConfiguration(configuration, in: launchRoot)
		} else {
			runConfiguration(configuration, in: launchRoot)
		}
	}

	func showPodsForTesting(filter: String, choose: Bool, kind: String?) {
		setPanelVisible(true)
		bottomPanel.showProfiler(address: "localhost:6060")?
			.showPodPickerForTesting(filter: filter, choose: choose, kind: kind)
	}

	func profileForTesting(address: String, kind: String) {
		setPanelVisible(true)
		guard let pane = bottomPanel.showProfiler(address: address) else { return }
		pane.connectForTesting(address: address)
		// After the index page has answered, since the kind list comes from it.
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
			pane.collectForTesting(kind: kind, seconds: 2)
			DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
				print("PROFILER: \(pane.statusForTesting) top=\(pane.topFunctionsForTesting)")
			}
		}
	}

	var editorForTesting: EditorAreaController { editor }

	/// Puts the caret on a line of the file being edited, for `:` in the palette.
	func goTo(line: Int) { editor.goTo(line: line) }

	func highlightPillsForTesting() {
		capsule?.isMenuOpen = true
	}

	func showAttachPickerForTesting(filter: String) {
		attachToProcess(nil)
		guard !filter.isEmpty else { return }
		processPicker?.filterForTesting(filter)
		print("ATTACH: \(processPicker?.shownNamesForTesting.prefix(5).joined(separator: ", ") ?? "none")")
	}

	/// Walks the history and reports where each step landed.
	func navigateForTesting(_ steps: String) {
		for step in steps.split(separator: ",") {
			switch step {
			case "back": navigateBack(nil)
			case "forward": navigateForward(nil)
			default: continue
			}
			let place = editor.currentPlace
			print("NAV \(step): \(place.map { "\($0.url.lastPathComponent):\($0.line)" } ?? "nowhere")")
		}
	}

	/// Drives the project tree and reports what the editor did about it.
	///
	/// Arrowing through the tree is supposed to show each file it lands on, and
	/// that is a claim about two views at once — which is why this prints both.
	/// Selects a row in the tree and copies it the way ⌘C does, then says what
	/// landed on the pasteboard.
	///
	/// Through `NSApp.sendAction`, which is exactly what the Edit menu's Copy
	/// does: what could be wrong here is not the copying but whether the tree
	/// is ever asked, and calling the method directly would answer the wrong
	/// question. The pasteboard is put back afterwards — a test has no business
	/// throwing away whatever somebody had copied.
	func copyPathForTesting(steps: String) -> String {
		let saved = NSPasteboard.general.string(forType: .string)
		defer {
			NSPasteboard.general.clearContents()
			if let saved { NSPasteboard.general.setString(saved, forType: .string) }
		}

		navigator.focusTree()
		for step in steps.split(separator: ",") {
			switch step {
			case "down": navigator.pressKeyForTesting(125)
			// So that copying several rows can be asked for at all.
			case "shift-down": navigator.pressKeyForTesting(125, extendingSelection: true)
			default: continue
			}
		}

		let sent = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
		let copied = NSPasteboard.general.string(forType: .string) ?? "nothing"
		// Newlines would break the one-line report into several that look like
		// separate answers.
		let onOneLine = (copied as String).replacingOccurrences(of: "\n", with: " | ")
		return "sent=\(sent) clipboard=\(onOneLine)"
	}

	func treeStepsForTesting(_ steps: String) {
		for step in steps.split(separator: ",") {
			switch step {
			case "focus": navigator.focusTree()
			case "down": navigator.pressKeyForTesting(125)
			case "up": navigator.pressKeyForTesting(126)
			case "right": navigator.pressKeyForTesting(124)
			case "left": navigator.pressKeyForTesting(123)
			case "return": navigator.pressKeyForTesting(36)
			// ⇧↓ and ⇧↑: a run of rows, selected the way somebody selects one.
			case "shift-down": navigator.pressKeyForTesting(125, extendingSelection: true)
			case "shift-up": navigator.pressKeyForTesting(126, extendingSelection: true)
			// What a build writing files does to the tree, on demand: the point
			// is what is still selected afterwards.
			case "reload": navigator.reloadForTesting()
			case "copy":
				print("TREE copy: clipboard=\(navigator.copyTextForTesting().replacingOccurrences(of: "\n", with: " | "))")
				continue
			case "collapse": navigator.collapseAll()
			case "locate": navigator.selectFileInEditor()
			// The field on the row, left standing: where its text sits and how
			// far it reaches are the whole of what is wrong with it, and
			// `rename:` commits too quickly to photograph.
			case "rename-begin":
				navigator.beginRename()
				print("TREE rename-begin: \(navigator.renameFieldReportForTesting)")
			default:
				// `rename:new-name.swift`, which is the whole gesture: the field
				// appears on the row, takes the name, and commits it.
				guard step.hasPrefix("rename:") else { continue }
				navigator.renameSelectionForTesting(String(step.dropFirst("rename:".count)))
			}
			let selection = navigator.selectionForTesting
			let showing = editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing"
			print("TREE \(step): selected=\(selection.name) rows=\(selection.rows) editor=\(showing)")
		}
	}

	/// Types into the terminal at a human rate and reports what each keystroke
	/// cost, so "it feels slower" can be answered with numbers.
	func measureTypingForTesting(presses: Int, interval: TimeInterval) {
		guard let terminal = bottomPanel.showTerminal()?.terminalView else { return }
		window?.makeFirstResponder(terminal)
		let letters = Array("abcdefghijklmnopqrstuvwxyz")
		for press in 0..<presses {
			DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(press)) {
				self.window?.makeFirstResponder(terminal)
				terminal.typeForTesting(String(letters[press % letters.count]))
			}
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(presses) + 0.5) {
			InputProbe.report()
		}
	}

	/// Pushes a branch from the branches view, for looking at what it does
	/// while it is happening.
	func pushBranchForTesting(_ name: String) {
		showSidebarTool(.branches)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			self?.branchesPane?.pushForTesting(branch: name)
		}
	}

	/// Folds a merge in the history, for checking the graph.
	func collapseHistoryRowForTesting(_ row: Int) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
			guard let pane = self?.historyPane else {
				print("FOLD no history pane")
				return
			}
			print("FOLD " + pane.toggleCollapseForTesting(row: row))
		}
	}

	/// Opens the branches view's own menu on a row, so what it offers for a
	/// branch or a stash can be looked at rather than assumed.
	func branchMenuForTesting(row: Int) {
		showSidebarTool(.branches)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
			self?.branchesPane?.showMenuForTesting(row: row)
		}
	}

	/// Right-clicks the tmux status line and then moves the pointer up through
	/// the menu it opens, which is the gesture that was dead.
	func tmuxMenuForTesting(hovers: Int) {
		let grid = bottomPanel.terminalGridForTesting
		guard grid.rows > 4 else { return }
		// The window tab, not the session name: `[menu]  [0:zsh]` — the tab is
		// what has a menu bound to it. Held down, because a tmux menu is a
		// press-drag-release affair.
		bottomPanel.terminalMenuDragForTesting(
			from: (row: grid.rows, column: 12),
			over: (0..<max(1, hovers)).map { (row: grid.rows - 2 - $0, column: 14) }
		)
	}

	/// What the terminal's geometry is, for checking that the bottom row is on
	/// screen at all.
	func terminalGeometryForTesting() -> String {
		bottomPanel.terminalGeometryForTesting()
	}

	/// Where the terminal in front says it is — the answer the window follows.
	func terminalDirectoryForTesting() -> URL? {
		bottomPanel.activeTerminalDirectoryForTesting()
	}

	func showDebugConsoleForTesting() {
		bottomPanel.showDebugConsoleForTesting()
	}

	func echoDebugOutputForTesting() {
		bottomPanel.debugOutput = { text in
			FileHandle.standardError.write(Data("[debug] \(text)".utf8))
		}
	}

	/// Prints what the run control's menu offers, rather than opening it.
	///
	/// Opening it is what a person does and exactly what a capture run cannot:
	/// a menu runs a nested event loop, so the window is never drawn, the
	/// screenshot never taken, and the run has to be killed — which throws away
	/// the output that would have said what was in the menu.
	func showConfigurationMenuForTesting() {
		// The destinations first, because they are the part worth checking and
		// they arrive about twelve seconds after the menu is drawn — printing
		// before they land prints "Finding destinations…" and proves nothing.
		Task { @MainActor in
			for configuration in self.runConfigurations where configuration.source == .xcodeScheme {
				guard let target = configuration.xcode else { continue }
				_ = await XcodeDestinations.shared.destinations(
					for: target,
					workingDirectory: URL(fileURLWithPath: configuration.workingDirectory)
				)
			}
			self.printConfigurationMenuForTesting()
		}
	}

	private func printConfigurationMenuForTesting() {
		for item in configurationMenu().items {
			print("MENU: \(item.isSeparatorItem ? "—" : item.title)\(markForTesting(item))")
			for entry in item.submenu?.items ?? [] {
				print("MENU:     \(entry.isSeparatorItem ? "—" : entry.title)\(markForTesting(entry))")
			}
		}
		// Redirected to a file, stdout is fully buffered, and this run has no
		// natural end — the window stays up until it is killed, which throws the
		// buffer away along with the only thing the run was for.
		fflush(stdout)
	}

	/// What is drawn in an item's mark column, as something printable.
	///
	/// The two marks are the point of the dump: ▶ is the run glyph, on the
	/// things a click starts, and ✓ is the tick that still means "this one is
	/// selected". A list where they are muddled is the bug, and a picture of a
	/// menu is not something a test can read.
	private func markForTesting(_ item: NSMenuItem) -> String {
		guard item.state == .on else { return "" }
		return item.onStateImage === MainWindowController.runMark() ? " ▶" : " ✓"
	}

	/// Opens the editor on the selected configuration, making one if there is
	/// none yet — what pressing play would have done first.
	func editConfigurationForTesting() {
		guard let configuration = selectedConfiguration ?? createSuggestedConfiguration() else { return }
		selectedConfigurationName = configuration.name
		refreshRunControl()
		presentConfigurationEditor(configuration, isNew: false)
	}

	// MARK: - Navigation history

	@objc func navigateBack(_ sender: Any?) {
		guard let place = navigation.back() else { return }
		go(to: place)
	}

	@objc func navigateForward(_ sender: Any?) {
		guard let place = navigation.forward() else { return }
		go(to: place)
	}

	private func go(to place: NavigationHistory.Place) {
		// A file that has been deleted since is dropped rather than reopened
		// empty, and the step is taken again so the shortcut still moves.
		guard FileManager.default.fileExists(atPath: place.file.path) else {
			navigation.forget(file: place.file)
			return
		}
		isNavigatingHistory = true
		editor.open(fileURL: place.file, atLine: place.line)
		DispatchQueue.main.async { [weak self] in self?.isNavigatingHistory = false }
	}

	var canNavigateBack: Bool { navigation.canGoBack }
	var canNavigateForward: Bool { navigation.canGoForward }

	@objc func stopSelected(_ sender: Any?) { stopRunning() }

	@objc func runSelected(_ sender: Any?) { runSelectedConfiguration(debug: false) }
	@objc func debugSelected(_ sender: Any?) { runSelectedConfiguration(debug: true) }

	private func runSelectedConfiguration(debug: Bool) {
		guard project != nil else { return }

		// A make goal nothing can debug runs as make runs it, in the terminal,
		// for both buttons: there is no debugger to offer and refusing to start
		// would be worse than starting without one.
		if case let .make(name) = runTarget, let goal = selectedMakeRun, goal.name == name {
			run(goal)
			return
		}

		guard let configuration = selectedConfiguration ?? createSuggestedConfiguration() else {
			notify(
				"Nothing to run",
				detail: "No launch configuration, and nothing recognisable to make one from."
			)
			return
		}
		selectedConfigurationName = configuration.name
		refreshRunControl()

		if debug {
			debugConfiguration(configuration, in: launchRoot)
		} else {
			runConfiguration(configuration, in: launchRoot)
		}
	}

	/// Writes a configuration for a project that has none, and says so.
	private func createSuggestedConfiguration() -> LaunchConfiguration? {
		guard project != nil, let suggestion = LaunchFile.suggestion(for: launchRoot) else { return nil }
		do {
			_ = try LaunchStore.save(suggestion, in: launchRoot)
			notify(
				"Created a launch configuration",
				detail: "Written to .vscode/launch.json as “\(suggestion.name)”. Edit it from the run menu.",
				kind: .information
			)
			return suggestion
		} catch {
			notify("Could not write launch.json", detail: error.localizedDescription)
			return nil
		}
	}

	/// Runs the build and produces the environment a configuration needs, then
	/// hands both to whatever starts it.
	///
	/// Both steps are skipped by configurations that declare neither, which is
	/// every one written by hand — this is the price of a configuration
	/// derived from a Makefile, and only those pay it.
	private func prepare(
		_ configuration: LaunchConfiguration,
		in root: URL,
		then start: @escaping ([String: String]) -> Void
	) {
		let evaluate = { [weak self] in
			guard let self else { return }
			let commands = configuration.environmentCommands
			guard !commands.isEmpty else {
				start(configuration.expandedEnvironment(root: root))
				return
			}

			self.runControl?.setStatus("Reading \(configuration.name)'s environment…", busy: true)
			Task { @MainActor in
				let directory = URL(
					fileURLWithPath: configuration.expandedWorkingDirectory(root: root)
				)
				let produced = await ShellEnvironment.evaluate(commands, in: directory)
				if !produced.failures.isEmpty {
					// Started anyway: the program is the one that knows whether
					// it can do without, and it says so better than a guess.
					self.notify(
						"Some environment could not be read",
						detail: produced.failures
							.map { "\($0.key): \($0.value.isEmpty ? "produced nothing" : $0.value)" }
							.sorted()
							.joined(separator: "\n")
					)
				}
				start(configuration.expandedEnvironment(root: root).merging(produced.values) { _, new in new })
			}
		}

		guard let step = configuration.makeStep else {
			evaluate()
			return
		}

		setPanelVisible(true)
		runControl?.setStatus("Building \(configuration.name)…", busy: true)
		let pane = bottomPanel.runCommand(
			title: "make",
			command: step.commandLine(root: root),
			directory: root,
			// The build console for this configuration, kept apart from the
			// console the program itself runs in.
			reusing: "build:\(configuration.id)"
		)
		runningPane = pane
		pane?.terminalView.onProcessExit = { [weak self, weak pane] code in
			MainActor.assumeIsolated {
				guard let self, self.runningPane === pane else { return }
				self.runningPane = nil
				guard code == 0 else {
					// Nothing starts on a failed build: what would run is the
					// last binary that built, which is the wrong one.
					self.runControl?.setStatus("Build failed — exit code \(code)", failed: true)
					return
				}
				evaluate()
			}
		}
	}

	private func runConfiguration(_ configuration: LaunchConfiguration, in root: URL) {
		prepare(configuration, in: root) { [weak self] environment in
			guard let self else { return }
			if configuration.devPod != nil {
				self.runInCluster(configuration, in: root, environment: environment, debug: false)
			} else {
				self.startRun(configuration, in: root, environment: environment)
			}
		}
	}

	// MARK: - Running in a cluster

	/// The tunnel and the debugger's tunnel, while a dev pod session is on.
	private var devPodForwards: [PortForward] = []
	/// The pod running something of ours, so stop can tell it to stop.
	private var devPodClient: DevPodClient?
	/// The launch in progress, so it can be cancelled.
	private var clusterTask: Task<Void, Never>?

	/// Writes a line into the launch log.
	///
	/// Everything a cluster launch does happens somewhere else and takes
	/// seconds: which context, which pod, what helm is doing, what the cluster
	/// says about it. A spinner and one line of status is not enough to tell a
	/// slow step from a stuck one.
	private func clusterLog(_ line: String, reset: Bool = false) {
		bottomPanel.appendLaunchLog(line, reset: reset)
	}

	/// Builds for the cluster, pushes the binary into a pod, and starts it.
	///
	/// The same configuration as any other: the package, the arguments and the
	/// environment do not change because the machine does. What changes is
	/// where the binary lands and who runs it.
	private func runInCluster(
		_ configuration: LaunchConfiguration,
		in root: URL,
		environment: [String: String],
		debug: Bool
	) {
		guard let settings = configuration.devPod else { return }
		stopDevPodForwards()
		setPanelVisible(true)
		runControl?.setStatus("Looking for a pod\u{2026}", busy: true)
		clusterLog("launching \(configuration.name)", reset: true)

		// Kept, so the stop button has something to stop. Everything here waits
		// on a cluster, and waiting on a cluster is exactly when somebody wants
		// to change their mind.
		clusterTask = Task { @MainActor in
			defer { clusterTask = nil }
			do {
				// Which cluster, and whether this configuration is allowed on
				// it: one that follows the current context follows it
				// everywhere, and everybody has a production cluster in their
				// kubeconfig.
				let current = settings.followsCurrentContext
					? await Kubernetes.currentContext(kubeconfig: settings.kubeconfig)
					: nil
				let context: String?
				switch settings.resolve(current: current) {
				case let .success(name):
					context = name
				case let .failure(refusal):
					throw refusal
				}
				let kubeconfig = settings.kubeconfig.isEmpty ? nil : settings.kubeconfig
				clusterLog("cluster \(context ?? "current")"
					+ (settings.namespace.isEmpty ? "" : ", namespace \(settings.namespace)"))

				// A project with a chart of its own gets that chart, with one
				// container of it put into development mode. Everything the
				// chart gives that container — its environment, its secrets,
				// what it sits beside — is what the program will find.
				if let chart = configuration.helm {
					try await prepareChart(
						chart,
						configuration: configuration,
						settings: settings,
						context: context,
						kubeconfig: kubeconfig,
						root: root
					)
				}

				let pods = await DevPods.list(
					context: context,
					namespace: settings.namespace.isEmpty ? nil : settings.namespace,
					kubeconfig: kubeconfig
				).filter { $0.isRunning }

				// This project's own pod. Two projects sharing a namespace each
				// get a release named after them, and taking whichever pod is
				// listed first means one project's binary lands in the other's
				// pod — which looks, from the logs, like a stale build.
				// A chart of the project's own names its own release, and the
				// pod is whichever one holds the patched container.
				let release = configuration.helm?.release ?? DevPodInstall.releaseName(for: root)
				var candidates = settings.pod.isEmpty
					? pods.filter { $0.name.hasPrefix(release) }
					: pods
				if candidates.isEmpty, configuration.helm != nil {
					throw DevPodClient.Failure.unreachable(
						"The chart's pod did not come up. The launch log has what helm and the "
							+ "cluster said about it."
					)
				}
				if candidates.isEmpty {
					// Nowhere to run this yet, so make somewhere: pressing run
					// should not stop to say a chart is missing.
					guard settings.allowInstall else {
						throw DevPodClient.Failure.unreachable(
							"No development pod is running in "
								+ "\(context ?? "the current context")"
								+ (settings.namespace.isEmpty ? "" : "/\(settings.namespace)")
								+ ", and this configuration does not install one."
						)
					}
					try await installDevPod(
							configuration: configuration, settings: settings,
							context: context, root: root
						)
					candidates = await DevPods.list(
						context: context,
						namespace: settings.namespace.isEmpty ? nil : settings.namespace,
						kubeconfig: kubeconfig
					).filter { $0.isRunning && (settings.pod.isEmpty ? $0.name.hasPrefix(release) : true) }
				}

				// A pod that is running is not necessarily a pod that is
				// published. What the chart was installed with is compared
				// against what this configuration asks for, and the release is
				// upgraded when they have drifted apart.
				if !candidates.isEmpty, settings.allowInstall, configuration.helm == nil {
					let desired = DevPodFiles.helmValues(
							for: settings,
							image: DevPodImage.resolved(settings.image, for: configuration, root: root)
						)
					let release = DevPodInstall.releaseName(for: root)
					let deployed = await DevPodInstall.deployedValues(
						release: release,
						namespace: settings.namespace.isEmpty ? "abydos-dev" : settings.namespace,
						context: context,
						kubeconfig: kubeconfig
					)
					if DevPodInstall.upgradeNeeded(desired: desired, deployed: deployed) {
						clusterLog("the pod is not set up the way this configuration asks for")
						try await installDevPod(
							configuration: configuration, settings: settings,
							context: context, root: root
						)
						candidates = await DevPods.list(
							context: context,
							namespace: settings.namespace.isEmpty ? nil : settings.namespace,
							kubeconfig: kubeconfig
						).filter { $0.isRunning && (settings.pod.isEmpty ? $0.name.hasPrefix(release) : true) }
					}
				}

				guard let pod = candidates.first(where: { settings.pod.isEmpty || $0.name == settings.pod })
					?? candidates.first
				else {
					throw DevPodClient.Failure.unreachable(
						"No development pod is running there, and installing one produced none."
					)
				}

				// The node decides what the binary has to be: a laptop is arm64
				// and a shared cluster usually is not.
				try Task.checkCancellation()
				clusterLog("pod \(pod.namespace)/\(pod.name)")
				let architecture = await DevPods.architecture(context: context, kubeconfig: kubeconfig)
					?? "amd64"
				runControl?.setStatus("Building for linux/\(architecture)…", busy: true)
				clusterLog("building for linux/\(architecture)")

				let output = FileManager.default.temporaryDirectory
					.appendingPathComponent("abydos-devpod-\(configuration.name.replacingOccurrences(of: " ", with: "-"))")
				// The project, not the working directory: what a build needs to
				// know — where go.mod is, where build.zig is, where make runs —
				// hangs off the project, and `cwd` is where the program runs.
				let binary = try await DevPodBuild.build(
					configuration: configuration,
					root: root,
					architecture: architecture,
					output: output,
					progress: { line in Task { @MainActor in self.clusterLog(line) } }
				)

				let attributes = try? FileManager.default.attributesOfItem(atPath: binary.path)
				let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
				runControl?.setStatus(
					"Sending \(ProfileValue.format(size, unit: "bytes")) to \(pod.name)…",
					busy: true
				)
				let control = try await PortForward.start(
					to: PodTarget(
						namespace: pod.namespace, name: pod.name, phase: pod.phase,
						containers: [], port: pod.controlPort, portSource: .containerPort
					),
					context: context,
					remotePort: pod.controlPort,
					kubeconfig: kubeconfig
				)
				devPodForwards.append(control)

				let client = DevPodClient(localPort: control.localPort)

				// Whatever the program reads goes first, and before it starts:
				// a service told where its configuration is cannot find it in
				// a pod that has never seen the file, and "no such file" says
				// nothing about the pod being empty.
				let plan = DevPodFiles.plan(
					files: settings.files,
					arguments: configuration.expandedArguments(root: root),
					root: root
				)
				for transfer in plan.transfers {
					try Task.checkCancellation()
					clusterLog("sending \(transfer.local.lastPathComponent) to \(transfer.remote)")
					try await client.push(file: transfer.local, to: transfer.remote)
				}
				if !plan.transfers.isEmpty {
					runControl?.setStatus(
						"Sent \(plan.transfers.count) file\(plan.transfers.count == 1 ? "" : "s")…",
						busy: true
					)
				}

				// Delve debugs Go; a JVM debugs itself, given the flag; and
				// everything else is held by gdbserver and driven by the LLDB on
				// this machine.
				// Nothing recognised means the full image is in the pod, which has
				// both; gdbserver is the one that works on a binary from anywhere.
				let debugger = DevPodBuild.debugger(for: configuration, root: root)
				let isGo = debugger == .delve
				let isJava = debugger == .jdwp
				let mode: String
				switch (debug, debugger) {
				case (false, .jdwp): mode = "jvm"
				case (false, _): mode = "run"
				case (true, .delve): mode = "debug"
				case (true, .jdwp): mode = "jvm-debug"
				case (true, _): mode = "native-debug"
				}

				try Task.checkCancellation()
				clusterLog("sending the binary, mode \(mode)")
				let status = try await client.push(
					binary: binary,
					mode: mode,
					// In debug mode the editor says what to launch, so these
					// would be said twice; in run mode the pod is on its own.
					arguments: debug ? [] : plan.arguments,
					environment: debug ? [:] : environment
				)
				guard status.architecture.isEmpty || status.architecture == architecture else {
					throw DevPodClient.Failure.wrongArchitecture(
						binary: architecture, pod: status.architecture
					)
				}

				if debug {
					clusterLog("attaching the debugger")
					try await attachDebugger(
						to: pod, context: context, kubeconfig: kubeconfig,
						arguments: plan.arguments, environment: environment,
						nativeBinary: isGo || isJava ? nil : binary,
						java: isJava
							? JavaDebug.Request(
								kind: .attach,
								mainClass: configuration.javaMainClass ?? "",
								projectName: nil
							)
							: nil,
						root: root
					)
					// What the program prints goes to the pod's stdout, which
					// the debugger never sees. Followed into the console beside
					// the debugger's own output, so one pane has both.
					if let started = bottomPanel.activeDebugSession {
						followDevPodLogs(client, pod: pod, debugging: started)
					}
				} else {
					// Busy: the program is up in the cluster until somebody
					// stops it, and the strip is where that is said and done.
					// The size is what proves the push landed: a program that
					// looks unchanged is the first thing to doubt.
					runControl?.setStatus(
						"Running \(ProfileValue.format(Int64(status.binarySize), unit: "bytes")) "
							+ "in \(pod.namespace)/\(pod.name)",
						busy: true
					)
					clusterLog("running in \(pod.namespace)/\(pod.name)")
					devPodClient = client
					followDevPodLogs(client, pod: pod)
					await openServicePort(settings: settings, pod: pod, context: context, kubeconfig: kubeconfig)

					if profileAfterRun {
						profileAfterRun = false
						await openProfiler(on: pod, context: context, kubeconfig: kubeconfig)
					}
				}
			} catch is CancellationError {
				stopDevPodForwards()
				clusterLog("stopped")
				runControl?.setStatus("Stopped")
			} catch {
				let detail = Self.describe(devPod: error)
				stopDevPodForwards()
				clusterLog(detail)
				// The strip gets the headline; the whole story is in the toast
				// and in the launch log, where there is room for it.
				runControl?.setStatus(Self.headline(of: detail), failed: true)
				notify("Could not run in the cluster", detail: detail)
			}
		}
	}

	/// The chart that travels with the app.
	///
	/// Looked for by hand in every place it could be: inside the resource
	/// bundle a package target produces, beside the executable, inside the
	/// application bundle, and in the repository when running from a checkout.
		static var bundledChart: URL? {
		// `Bundle.module` is not used here. Its generated accessor calls
		// `fatalError` when it cannot find the resource bundle, so a build that
		// shipped without one does not fall back — it takes the app down, which
		// is what happened when somebody pressed run in a cluster.
		// SwiftPM names it `<package>_<target>.bundle`, so it followed the
		// rename: a stale name here is a run in a cluster that cannot find the
		// chart it ships with.
		let resource = "Abydos_AbydosApp.bundle"
		var candidates: [URL] = []

		if let main = Bundle.main.resourceURL {
			candidates.append(main.appendingPathComponent(resource))
			candidates.append(main)
		}
		// Beside the executable, which is where a plain `swift build` puts it.
		let beside = Bundle.main.bundleURL.deletingLastPathComponent()
		candidates.append(beside.appendingPathComponent(resource))
		candidates.append(Bundle.main.bundleURL.appendingPathComponent(resource))
		// Running from the repository, where the source is the chart.
		candidates.append(
			URL(fileURLWithPath: #filePath)
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.appendingPathComponent("DevPod")
		)

		let manager = FileManager.default
		for candidate in candidates {
			for chart in [
				candidate.appendingPathComponent("devpod-chart"),
				candidate.appendingPathComponent("Contents/Resources/devpod-chart"),
				candidate.appendingPathComponent("chart/abydos-devpod"),
			] where manager.fileExists(atPath: chart.appendingPathComponent("Chart.yaml").path) {
				return chart
			}
		}
		return nil
	}

	/// Puts a development pod in the cluster for this project.
	///
	/// One release per project, named after it: two projects sharing a pod
	/// would overwrite each other's binary, and the name is what somebody sees
	/// in `helm list` when they wonder what this is.
	private func installDevPod(
		configuration: LaunchConfiguration,
		settings: LaunchConfiguration.DevPodSettings,
		context: String?,
		root: URL
	) async throws {
		guard let chart = Self.bundledChart else { throw DevPodInstall.Failure.noChart }

		let release = DevPodInstall.releaseName(for: root)
		let namespace = settings.namespace.isEmpty ? "abydos-dev" : settings.namespace
		let kubeconfig = settings.kubeconfig.isEmpty ? nil : settings.kubeconfig
		// The slim image for whatever this project is written in, unless the
		// configuration names one itself: a pod that only ever debugs Go has no
		// use for gdbserver, and one that never sees Go has none for Delve.
		let image = DevPodImage.resolved(settings.image, for: configuration, root: root)
		runControl?.setStatus("Installing \(release) in \(namespace)…", busy: true)
		clusterLog("installing \(release) in \(namespace), image \(image)")

		// The install and a watch on what it produces, side by side. helm waits
		// in silence and then reports its own deadline — "context deadline
		// exceeded" — while the cluster has been saying since the fourth second
		// that it cannot pull the image. Whichever finishes first wins: a pod
		// that will never start ends this now rather than in two minutes.
		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask { @MainActor [weak self] in
				try await DevPodInstall.install(
					chart: chart,
					release: release,
					namespace: namespace,
					// The resolved context, not what the configuration says: it
					// may say `${currentContext}`, which is not a cluster.
					context: context,
					kubeconfig: kubeconfig,
					image: image,
					// What the chart has to publish, and on which port.
					values: DevPodFiles.helmValues(for: settings, image: image),
					progress: { line in
						Task { @MainActor in self?.clusterLog(line) }
					}
				)
			}
			group.addTask { @MainActor [weak self] in
				try await self?.watchInstall(
					release: release, namespace: namespace,
					context: context, kubeconfig: kubeconfig, image: image
				)
			}

			defer { group.cancelAll() }
			try await group.next()
		}
		notify(
			"Installed a development pod",
			detail: "\(release) in \(namespace). Remove it with: helm uninstall \(release) -n \(namespace)",
			kind: .information
		)
	}

	// MARK: - The other ways to start

	/// Runs what is selected and puts the profiler in front of it.
	///
	/// The program has to be serving pprof for this to find anything, which for
	/// a Go service usually means `net/http/pprof` on 6060 — the profiler says
	/// so plainly when there is nothing there, which is the only useful thing
	/// to say about a program that is not instrumented.
	private func profileSelectedConfiguration() {
		guard let configuration = selectedConfiguration else {
			notify("Nothing to profile", detail: "Choose a configuration first.", kind: .information)
			return
		}

		// Asked for now, done when there is something to profile. A cluster run
		// opens the profiler on the pod it just started; a local one waits for
		// the program to be listening.
		profileAfterRun = true
		runSelectedConfiguration(debug: false)

		guard configuration.devPod == nil else { return }
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 1_500_000_000)
			guard profileAfterRun else { return }
			profileAfterRun = false
			setPanelVisible(true)
			bottomPanel.showProfiler(address: Self.lastProfilerAddress, connecting: true)
		}
	}

	/// Set while a run is on its way to being profiled.
	private var profileAfterRun = false

	/// The profiler, on the pod this run just started.
	private func openProfiler(on pod: DevPodTarget, context: String?, kubeconfig: String?) async {
		do {
			let forward = try await PortForward.start(
				to: PodTarget(
					namespace: pod.namespace, name: pod.name, phase: pod.phase,
					containers: [], port: 6060, portSource: .containerPort
				),
				context: context,
				remotePort: 6060,
				kubeconfig: kubeconfig
			)
			devPodForwards.append(forward)
			setPanelVisible(true)
			bottomPanel.showProfiler(address: "localhost:\(forward.localPort)", connecting: true)
			clusterLog("profiling through localhost:\(forward.localPort)")
		} catch {
			clusterLog("no profiler on port 6060: \(error.localizedDescription)")
			notify(
				"Could not reach the pod's profiler",
				detail: "Nothing answered on port 6060 in \(pod.name). A Go service serves "
					+ "pprof there when it imports net/http/pprof.\n\n"
					+ error.localizedDescription
			)
		}
	}

	/// Runs the tests with coverage, and reports what they covered.
	///
	/// The tests rather than the program: coverage is a property of a test run,
	/// and a program run by hand covers whatever the person doing it happened
	/// to touch.
	private func runSelectedWithCoverage() {
		guard let root = project?.root else { return }
		guard FileManager.default.fileExists(atPath: root.appendingPathComponent("go.mod").path) else {
			notify(
				"Coverage is Go-only so far",
				detail: "This project has no go.mod. Coverage for other languages is not built yet.",
				kind: .information
			)
			return
		}

		let profile = AbydosFolder.url(in: root).appendingPathComponent("coverage.out")
		_ = try? AbydosFolder.create(in: root)
		setPanelVisible(true)
		bottomPanel.runCommand(
			title: "coverage",
			command: "go test ./... -coverprofile='\(profile.path)' -covermode=atomic"
				+ " && echo && go tool cover -func='\(profile.path)' | tail -30",
			directory: root,
			reusing: "coverage:\(root.path)"
		)
	}

	/// A window for a terminal dragged out of a panel — including out of one of
	/// these windows, which is why it hands itself along.
	private func openTerminalWindow(_ detached: DetachedTerminal, at screenPoint: NSPoint) {
		TerminalWindowController(
			detached: detached,
			at: screenPoint,
			workingDirectory: project?.root,
			openAnother: { [weak self] next, point in
				self?.openTerminalWindow(next, at: point)
			}
		).show()
	}

	/// Makes what the program serves reachable from here.
	///
	/// A microservice is tested by talking to it, and a pod in a cluster is not
	/// somewhere a browser can reach. A forward to the port it listens on costs
	/// nothing and turns "it is running" into a link. The ingress, when the
	/// configuration asks for one, is the other way in — and the one that other
	/// people can use.
	private func openServicePort(
		settings: LaunchConfiguration.DevPodSettings,
		pod: DevPodTarget,
		context: String?,
		kubeconfig: String?
	) async {
		if !settings.ingressHost.isEmpty {
			clusterLog("published at http://\(settings.ingressHost)")
		}

		let port = settings.port > 0 ? settings.port : 8080
		do {
			let forward = try await PortForward.start(
				to: PodTarget(
					namespace: pod.namespace, name: pod.name, phase: pod.phase,
					containers: [], port: port, portSource: .containerPort
				),
				context: context,
				remotePort: port,
				kubeconfig: kubeconfig
			)
			devPodForwards.append(forward)
			clusterLog("reachable at http://localhost:\(forward.localPort) (pod port \(port))")
		} catch {
			// Not a failure: plenty of programs serve nothing at all.
			clusterLog("no forward to port \(port): \(error.localizedDescription)")
		}
	}

	/// Installs the project's own chart, and puts one of its containers into
	/// development mode.
	///
	/// Two steps, both of which somebody could do by hand and neither of which
	/// anybody wants to: `helm upgrade` with this stage's values, and a patch
	/// that swaps the named container's image and command for the supervisor.
	/// The pod keeps everything else the chart gave it.
	private func prepareChart(
		_ chart: LaunchConfiguration.HelmSettings,
		configuration: LaunchConfiguration,
		settings: LaunchConfiguration.DevPodSettings,
		context: String?,
		kubeconfig: String?,
		root: URL
	) async throws {
		let namespace = settings.namespace.isEmpty ? "default" : settings.namespace

		let present = await HelmRelease.exists(
			release: chart.release, namespace: namespace, context: context, kubeconfig: kubeconfig
		)
		if !present || chart.install {
			guard chart.install else {
				throw HelmRelease.Failure(
					"The release \(chart.release) is not installed in \(namespace), and this "
						+ "configuration does not install it."
				)
			}
			runControl?.setStatus("Installing \(chart.release)…", busy: true)
			clusterLog("installing \(chart.release) from \(chart.chart)")
			try await HelmRelease.upgrade(
				chart,
				root: root,
				namespace: namespace,
				context: context,
				kubeconfig: kubeconfig,
				progress: { line in Task { @MainActor in self.clusterLog(line) } }
			)
		}
		try Task.checkCancellation()

		// Which deployment holds the container this configuration is for. A pod
		// with an application and a web front end in it is two configurations,
		// and each replaces its own container.
		let deployments = await HelmRelease.deployments(
			release: chart.release, namespace: namespace, context: context, kubeconfig: kubeconfig
		)
		guard let deployment = HelmRelease.deployment(holding: chart.container, in: deployments) else {
			throw HelmRelease.Failure(
				"No deployment in \(chart.release) has a container called "
					+ "\(chart.container.isEmpty ? "anything" : chart.container). "
					+ "It has: " + deployments.map(\.name).joined(separator: ", ") + "."
			)
		}

		let image = DevPodImage.resolved(settings.image, for: configuration, root: root)
		let container = chart.container.isEmpty
			? (deployments.first { $0.name == deployment }?.containers.first ?? "app")
			: chart.container

		runControl?.setStatus("Putting \(container) into development mode…", busy: true)
		clusterLog("patching \(deployment)/\(container) to run the supervisor")

		let patch = await Kubernetes.run(
			[
				"patch", "deployment", deployment, "--namespace", namespace,
				"--type", "strategic",
				// Under helm's name: the cluster records who owns each field,
				// and a patch under a name of its own makes the next `helm
				// upgrade` a conflict rather than an upgrade.
				"--field-manager", "helm",
				"-p", DevContainerPatch.json(container: container, image: image),
			],
			context: context,
			kubeconfig: kubeconfig
		)
		guard patch.exitCode == 0 else {
			throw HelmRelease.Failure(patch.stderr.isEmpty ? patch.stdout : patch.stderr)
		}
		clusterLog(patch.stdout.trimmingCharacters(in: .whitespacesAndNewlines))

		// And wait for it, because the next thing that happens is a binary
		// being pushed into a pod that has to exist first.
		runControl?.setStatus("Waiting for \(deployment)…", busy: true)
		let rollout = await Kubernetes.run(
			[
				"rollout", "status", "deployment/" + deployment,
				"--namespace", namespace, "--timeout", "120s",
			],
			context: context,
			kubeconfig: kubeconfig
		)
		clusterLog(rollout.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
		guard rollout.exitCode == 0 else {
			throw HelmRelease.Failure(
				(rollout.stderr.isEmpty ? rollout.stdout : rollout.stderr)
					+ "\n\nThe container was patched but the pod did not come up. "
					+ "`kubectl rollout undo deployment/\(deployment) -n \(namespace)` puts it back."
			)
		}
	}

	/// Reports what the cluster is doing with the pods an install just asked
	/// for, and gives up when there is nothing left to wait for.
	///
	/// Only failure ends this: readiness is helm's to decide, and a pod that
	/// looks ready for a moment is not the same as a release that is.
	private func watchInstall(
		release: String,
		namespace: String,
		context: String?,
		kubeconfig: String?,
		image: String
	) async throws {
		var reported: Set<String> = []
		while !Task.isCancelled {
			try await Task.sleep(nanoseconds: 1_500_000_000)
			let states = await DevPodWatch.states(
				release: release, namespace: namespace,
				context: context, kubeconfig: kubeconfig
			)
			for state in states where !reported.contains(state.line) {
				reported.insert(state.line)
				clusterLog("  " + state.line)
			}
			if let hopeless = states.first(where: \.isHopeless) {
				throw DevPodInstall.Failure.failed(DevPodWatch.explain(hopeless, image: image))
			}
		}
	}

	/// Connects the debugger to the `dlv dap` the pod is now running.
	/// How a pod is named in the toolbar: the namespace and the pod, which is
	/// what `kubectl` would want to be told to find it again.
	private func label(for pod: DevPodTarget) -> String {
		"\(pod.namespace)/\(pod.name)"
	}

	private func attachDebugger(
		to pod: DevPodTarget,
		context: String?,
		kubeconfig: String?,
		arguments: [String],
		environment: [String: String],
		nativeBinary: URL? = nil,
		java: JavaDebug.Request? = nil,
		root: URL? = nil
	) async throws {
		let debugForward = try await PortForward.start(
			to: PodTarget(
				namespace: pod.namespace, name: pod.name, phase: pod.phase,
				containers: [], port: pod.debugPort, portSource: .containerPort
			),
			context: context,
			remotePort: pod.debugPort,
			kubeconfig: kubeconfig
		)
		devPodForwards.append(debugForward)

		runControl?.setStatus("Debugging in \(pod.name)…", busy: true)

		// A JVM in a pod holds itself at its first instruction — `suspend=y` —
		// and waits for a debugger on the port the supervisor opened. What
		// connects to it is the adapter inside the language server here, so the
		// sources it shows are the ones on this disk.
		if var request = java {
			guard let root else { return }
			let port = try await LanguageService.shared.startJavaDebugAdapter(project: root)
			request.host = "127.0.0.1"
			request.port = debugForward.localPort
			// The class files here, so a frame from the pod lands on the source
			// it was compiled from rather than on a decompiled stub.
			if let anchor = JavaTooling.mainClasses(in: root).first.map({ URL(fileURLWithPath: $0.file) }),
			   let resolved = await LanguageService.shared.javaClasspath(for: anchor, project: root) {
				request.classPaths = resolved.classPaths
				request.projectName = resolved.projectName
			}

			guard let session = bottomPanel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: port, request: request),
				breakpoints: pendingBreakpoints,
				location: label(for: pod)
			) else { return }
			wire(session)
			return
		}

		// A native program is held by gdbserver in the pod and driven by the
		// LLDB here, against the binary that was pushed — which was built here,
		// so its debug information points at these sources.
		if let nativeBinary {
			guard let lldb = DebugAdapters.executable(for: DebugAdapters.lldb) else {
				throw DevPodClient.Failure.unreachable(
					"Debugging a native program in a cluster needs LLDB's adapter here: "
						+ DebugAdapters.lldb.installHint
				)
			}
			guard let session = bottomPanel.startDebugging(
				adapter: DebugAdapters.lldb,
				executable: lldb,
				start: .nativeRemote(
					host: "127.0.0.1", port: debugForward.localPort, binary: nativeBinary
				),
				breakpoints: pendingBreakpoints,
				location: label(for: pod)
			) else { return }
			wire(session)
			return
		}

		guard let session = bottomPanel.startDebugging(
			adapter: DebugAdapters.delve,
			executable: "",
			start: .remote(
				host: "127.0.0.1",
				port: debugForward.localPort,
				// The path inside the pod, which is where the supervisor put it.
				program: "/app/current",
				arguments: arguments,
				workingDirectory: "/app",
				environment: environment
			),
			breakpoints: pendingBreakpoints,
			location: label(for: pod)
		) else { return }
		wire(session)
	}

	/// Shows what the program in the pod is printing.
	///
	/// While debugging it goes to the debug console rather than to a tab of its
	/// own. The adapter's output events carry what the *debugger* says; a
	/// program in a pod writes to the pod's stdout, which the debugger never
	/// sees — so the console sat empty through a whole session while
	/// `kubectl logs` had the story.
	private func followDevPodLogs(
		_ client: DevPodClient,
		pod: DevPodTarget,
		debugging debugSession: DebugSession? = nil
	) {
		Task { @MainActor in
			// A poll rather than a stream: the supervisor keeps a tail, the
			// interesting output arrives in the first seconds, and a websocket
			// for this would be a protocol to maintain.
			//
			// A run is watched for a while; a debug session for as long as it
			// lasts, since the line worth reading is often the one printed just
			// before a breakpoint somebody took ten minutes to reach.
			var remaining = debugSession == nil ? 20 : Int.max
			// The console is appended to rather than replaced, so the same two
			// hundred lines must not arrive every second — and cannot simply be
			// replaced either, since the debugger's own output is interleaved
			// with the program's.
			var tail = LogTail()
			while remaining > 0 {
				remaining -= 1
				try? await Task.sleep(nanoseconds: 1_000_000_000)
				if let debugSession, debugSession.state == .terminated { return }
				guard let text = try? await client.logs(tail: 200), !text.isEmpty else { continue }
				guard debugSession != nil else {
					bottomPanel.showDevPodOutput(text, from: "\(pod.namespace)/\(pod.name)")
					continue
				}
				let fresh = tail.newText(in: text)
				if !fresh.isEmpty { bottomPanel.activeDebugPane?.appendOutput(fresh) }
			}
		}
	}

	private func stopDevPodForwards() {
		for forward in devPodForwards { forward.stop() }
		devPodForwards = []
	}

	/// Stops a program running in a cluster, and closes the tunnels to it.
	private func stopDevPod() {
		guard let client = devPodClient else { return }
		devPodClient = nil
		runControl?.setStatus("Stopping…", busy: true)
		Task { @MainActor in
			try? await client.stop()
			stopDevPodForwards()
			runControl?.setStatus("Stopped")
		}
	}

	/// The first line of a message, for somewhere a line is all there is.
	static func headline(of message: String) -> String {
		let first = message
			.split(separator: "\n", omittingEmptySubsequences: false)
			.first
			.map(String.init)?
			.trimmingCharacters(in: .whitespaces) ?? message
		return first.count > 140 ? String(first.prefix(139)) + "\u{2026}" : first
	}

	private static func describe(devPod error: any Error) -> String {
		switch error {
		case let refusal as ContextRefusal:
			return refusal.message
		case let failure as DevPodClient.Failure:
			switch failure {
			case let .unreachable(reason): return reason
			case let .refused(code, body): return "The pod answered \(code): \(body)"
			case let .wrongArchitecture(binary, pod):
				return "Built for \(binary), but the pod runs \(pod)"
			}
		case let failure as DevPodBuild.Failure:
			switch failure {
			case .noToolchain: return "No Go toolchain was found"
			case let .failed(output): return output
			case let .unsupported(reason): return reason
			}
		case let failure as DevPodInstall.Failure:
			switch failure {
			case .noHelm:
				return "helm is not installed. The development pod is a chart, and helm is what installs it."
			case .noChart:
				return "The development pod's chart is missing from this build of Abydos."
			case let .failed(output):
				return output.isEmpty ? "helm failed and said nothing." : output
			}
		case let failure as PortForward.Failure:
			switch failure {
			case .noKubectl: return "kubectl is not installed"
			case .noFreePort: return "No local port was free"
			case .timedOut: return "kubectl did not answer"
			case let .failed(reason): return reason
			}
		default:
			return error.localizedDescription
		}
	}

	private func startRun(
		_ configuration: LaunchConfiguration,
		in root: URL,
		environment: [String: String]
	) {
		let program = configuration.expandedProgram(root: root)
		let directory = configuration.expandedWorkingDirectory(root: root)
		let arguments = configuration.expandedArguments(root: root)

		setPanelVisible(true)
		runControl?.setStatus("Running \(configuration.name)…", busy: true)

		// A Go configuration names a package, which is `go run`'s argument; any
		// other names a binary, which is simply executed.
		let words = configuration.type == "go"
			? ["go", "run", program] + arguments
			: [program] + arguments
		let pane = bottomPanel.runCommand(
			title: configuration.name,
			command: words.map(Self.shellQuoted).joined(separator: " "),
			directory: URL(fileURLWithPath: directory),
			environment: environment,
			reusing: "run:\(configuration.id)"
		)
		// The shell reports what the program exited with, which is the one thing
		// worth saying in the titlebar once it is over.
		followRunningPane(pane)
	}

	/// A word the shell will pass through as it was written.
	private static func shellQuoted(_ word: String) -> String {
		guard word.contains(where: { !$0.isLetter && !$0.isNumber && !"-_./=:@".contains($0) })
		else { return word }
		return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}

	private func debugConfiguration(_ configuration: LaunchConfiguration, in root: URL) {
		prepare(configuration, in: root) { [weak self] environment in
			guard let self else { return }
			if configuration.devPod != nil {
				self.runInCluster(configuration, in: root, environment: environment, debug: true)
			} else {
				self.startDebug(configuration, in: root, environment: environment)
			}
		}
	}

	private func startDebug(
		_ configuration: LaunchConfiguration,
		in root: URL,
		environment: [String: String]
	) {
		let adapter = DebugAdapters.adapter(id: configuration.adapterID) ?? DebugAdapters.lldb

		// Nothing to find on disk for Java: the adapter is started by the
		// language server, which is either running or is the thing to fix.
		if adapter.transport == .languageServer {
			guard let mainClass = configuration.javaMainClass else {
				notify(
					"This configuration does not say what to start",
					detail: "A Java configuration needs a mainClass — the fully qualified name of "
						+ "the class with the main method."
				)
				return
			}
			startJavaDebug(
				name: configuration.name,
				mainClass: mainClass,
				anchorFile: nil,
				workingDirectory: URL(fileURLWithPath: configuration.expandedWorkingDirectory(root: root)),
				arguments: configuration.expandedArguments(root: root),
				vmArguments: configuration.javaVMArguments,
				environment: environment
			)
			return
		}

		guard let executable = DebugAdapters.executable(for: adapter) else {
			notify("\(adapter.name) is not installed", detail: adapter.installHint)
			return
		}

		setPanelVisible(true)
		runControl?.setStatus("Debugging \(configuration.name)…", busy: true)
		guard let session = bottomPanel.startDebugging(
			adapter: adapter,
			executable: executable,
			start: .launch(
				program: configuration.expandedProgram(root: root),
				arguments: configuration.expandedArguments(root: root),
				workingDirectory: URL(
					fileURLWithPath: configuration.expandedWorkingDirectory(root: root)
				),
				environment: environment
			),
			breakpoints: pendingBreakpoints
		) else { return }
		wire(session)
	}

	/// Starts a Java debug session.
	///
	/// Two things have to be asked of the language server first, and neither can
	/// be worked out here: the port its debug adapter is listening on, and the
	/// classpath of the module the class belongs to. A JVM started without the
	/// second one fails with `ClassNotFoundException` on the class it was asked
	/// to run, which reads like the class is missing rather than the classpath.
	private func startJavaDebug(
		name: String,
		mainClass: String,
		anchorFile: URL?,
		workingDirectory: URL,
		arguments: [String],
		vmArguments: [String] = [],
		environment: [String: String]
	) {
		guard let project else { return }
		let root = project.root

		setPanelVisible(true)
		runControl?.setStatus("Debugging \(name)…", busy: true)

		Task { @MainActor in
			let port: Int
			do {
				port = try await LanguageService.shared.startJavaDebugAdapter(project: root)
			} catch {
				runControl?.setStatus("Java cannot be debugged yet", failed: true)
				// The missing bundle gets the whole manual rather than one line:
				// it is the one failure here nobody can guess the fix for.
				var detail = error.localizedDescription
				if let failure = error as? LanguageService.JavaDebugFailure, case .noBundle = failure {
					detail = JavaTooling.debugPluginManual
				}
				notify("Java cannot be debugged yet", detail: detail)
				return
			}

			// Any file in the module will do — the question is about the project
			// the file belongs to, not the file — so the class's own source is
			// used when there is one and any main class in the project otherwise.
			let anchor = anchorFile
				?? JavaTooling.mainClasses(in: root)
					.first { $0.name == mainClass }
					.map { URL(fileURLWithPath: $0.file) }
			var classPaths: [String] = []
			var projectName: String?
			if let anchor,
			   let resolved = await LanguageService.shared.javaClasspath(for: anchor, project: root) {
				classPaths = resolved.classPaths
				projectName = resolved.projectName
			}

			let request = JavaDebug.Request(
				kind: .launch,
				mainClass: mainClass,
				classPaths: classPaths,
				projectName: projectName,
				workingDirectory: workingDirectory.path,
				arguments: arguments,
				vmArguments: vmArguments,
				environment: environment
			)
			guard let session = bottomPanel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: port, request: request),
				breakpoints: pendingBreakpoints
			) else { return }
			wire(session)
		}
	}

	/// The list of configurations, and the ways to change them.
	private func showConfigurationMenu(at point: NSPoint, in view: NSView) {
		configurationMenu().popUp(positioning: nil, at: point, in: view)
	}

	/// Everything the run control offers: the project's configurations, its
	/// schemes and where each can go, and the Makefile's goals.
	private func configurationMenu() -> NSMenu {
		let menu = NSMenu()
		let all = launchConfigurations

		for configuration in all {
			let item = NSMenuItem(
				title: configuration.name, action: #selector(configurationChosen(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = configuration.name
			// A tick here, and it is the right mark: clicking one of these
			// selects it and nothing starts. The schemes below start when they
			// are clicked, which is why they are marked differently.
			item.state = configuration.name == selectedConfiguration?.name ? .on : .off
			menu.addItem(item)
		}
		if all.isEmpty {
			let empty = NSMenuItem(title: "No configurations yet", action: nil, keyEquivalent: "")
			empty.isEnabled = false
			menu.addItem(empty)
		}

		// The schemes of an Xcode project, each with the destinations it can go
		// to. Here as well as in the Run menu, because this is the control
		// somebody presses to choose what runs, and a device picker reachable
		// only from a menu bar is a device picker nobody finds.
		let schemes = runConfigurations.filter { $0.source == .xcodeScheme }
		if !schemes.isEmpty {
			menu.addItem(.separator())
			let heading = NSMenuItem(title: "Schemes", action: nil, keyEquivalent: "")
			heading.isEnabled = false
			menu.addItem(heading)

			for configuration in schemes {
				let item = NSMenuItem(
					title: configuration.name,
					action: #selector(runMenuItem(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.representedObject = configuration.id
				markWillRun(item, configuration.name == selectedConfigurationName)
				if let target = configuration.xcode {
					item.submenu = destinationMenu(for: configuration, target: target)
				}
				menu.addItem(item)
			}
		}

		// The goals a Makefile already defines, so a project that says how to
		// run itself does not have to be told a second time.
		//
		// All of them, not only the ones a debugger could be attached to: a
		// project whose `make dev` builds and runs a Swift app is exactly as
		// runnable as one whose Makefile builds Go, and offering nothing for it
		// was reading the Makefile and then pretending it said nothing.
		let goals = makeGoals()
		if !goals.isEmpty {
			menu.addItem(.separator())
			let heading = NSMenuItem(title: "From the Makefile", action: nil, keyEquivalent: "")
			heading.isEnabled = false
			menu.addItem(heading)

			for goal in goals where !all.contains(where: { $0.name == "make \(goal.name)" }) {
				// The ones a debugger can be attached to become configurations;
				// the rest run as make runs them, in the terminal, which is
				// what a `make dev` that builds and launches a Swift app wants
				// anyway.
				// One action for all of them: what a goal turns into is decided
				// when it is clicked, by the same code the tests exercise —
				// deciding it here, from a list built moments earlier, is how a
				// goal came to be offered as debuggable and then do nothing.
				let item = NSMenuItem(
					title: "make \(goal.name)",
					action: #selector(makeGoalChosen(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.representedObject = [goal.makefile.path.path, goal.name]
				item.toolTip = goal.summary.isEmpty ? nil : goal.summary
				menu.addItem(item)
			}
		}

		// The same for a Maven or Gradle project, which says how to run itself
		// in its build file exactly as a Makefile does.
		let buildGoals = runConfigurations.filter {
			$0.source == .maven || $0.source == .gradle || $0.source == .javaMain
		}
		if !buildGoals.isEmpty {
			menu.addItem(.separator())
			let heading = NSMenuItem(title: "From the build", action: nil, keyEquivalent: "")
			heading.isEnabled = false
			menu.addItem(heading)

			for goal in buildGoals where !all.contains(where: { $0.name == goal.name }) {
				let item = NSMenuItem(
					title: goal.name, action: #selector(buildGoalChosen(_:)), keyEquivalent: ""
				)
				item.target = self
				item.representedObject = goal.id
				item.toolTip = goal.commandLine
				menu.addItem(item)
			}
		}

		menu.addItem(.separator())
		let edit = NSMenuItem(
			title: "Edit\u{2026}", action: #selector(editSelectedConfiguration), keyEquivalent: ""
		)
		edit.target = self
		edit.isEnabled = selectedConfiguration != nil
		menu.addItem(edit)

		// One local and one in the cluster differ by two fields, so the way to
		// get the second is a copy of the first rather than typing it again.
		let duplicate = NSMenuItem(
			title: "Duplicate\u{2026}", action: #selector(duplicateSelectedConfiguration), keyEquivalent: ""
		)
		duplicate.target = self
		duplicate.isEnabled = selectedConfiguration != nil
		menu.addItem(duplicate)

		let add = NSMenuItem(title: "New\u{2026}", action: #selector(addConfiguration), keyEquivalent: "")
		add.target = self
		menu.addItem(add)

		let reveal = NSMenuItem(
			title: "Open launch.json", action: #selector(openLaunchFile), keyEquivalent: ""
		)
		reveal.target = self
		menu.addItem(reveal)

		return menu
	}

	/// The goals in the project's Makefiles that start a Go program.
	///
	/// Read fresh each time the menu opens: a Makefile is edited while the
	/// project is open, and a stale list would offer goals that no longer
	/// exist and hide the ones just added.
	private func debuggableMakeGoals() -> [(makefile: Makefile, name: String, summary: String)] {
		makeGoals().filter { MakeLaunch.plan(for: $0.name, in: $0.makefile) != nil }
	}

	/// Every goal the project's Makefiles define, worth offering to run.
	///
	/// Read here rather than taken from the discovered configurations: those
	/// are found on a background queue when the project opens, and a menu
	/// opened before that finished showed nothing at all — which is what "why
	/// is `make dev` not offered" turned out to be.
	///
	/// Goals that clean, install or explain themselves are left out: a run
	/// menu is a list of ways to start the thing being worked on.
	private func makeGoals() -> [(makefile: Makefile, name: String, summary: String)] {
		guard let project else { return [] }
		var found: [(Makefile, String, String)] = []

		let uninteresting: Set<String> = [
			"help", "clean", "distclean", "install", "uninstall", "all",
		]
		for url in Makefile.find(in: project.root) {
			guard let makefile = Makefile.read(at: url) else { continue }
			for target in makefile.targets
			where !uninteresting.contains(target.name) && !target.recipe.isEmpty {
				found.append((makefile, target.name, target.summary))
			}
		}
		return found
	}

	/// Every goal every Makefile in the project defines, for the dialog.
	///
	/// Unfiltered, unlike the ones offered beside the play button. That list
	/// leaves out the goals nobody wants suggested — `help`, `clean`,
	/// `install` — because suggesting them is noise; but somebody who came
	/// here has said which one they want, and refusing to show `install`
	/// because it is usually uninteresting is refusing the thing they asked
	/// for.
	private func allMakeGoals() -> [(makefile: Makefile, name: String, summary: String)] {
		guard let project else { return [] }
		var found: [(Makefile, String, String)] = []
		for url in Makefile.find(in: project.root) {
			guard let makefile = Makefile.read(at: url) else { continue }
			for target in makefile.targets where !target.recipe.isEmpty {
				found.append((makefile, target.name, target.summary))
			}
		}
		return found
	}

	/// Makes a launch configuration out of any goal in the project.
	@objc func newFromMakeGoal(_ sender: Any?) {
		let goals = allMakeGoals()
		guard !goals.isEmpty else {
			notify("No Makefile goals here", detail: "Nothing in this project defines any.")
			return
		}

		let alert = NSAlert()
		alert.messageText = "New from Make goal"
		alert.informativeText = "It becomes a launch configuration you can run, edit and keep."
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
		for goal in goals {
			// The summary beside the name, since a Makefile that documents
			// itself has already said what each one is for.
			let title = goal.summary.isEmpty ? goal.name : "\(goal.name) — \(goal.summary)"
			picker.addItem(withTitle: title)
		}
		alert.accessoryView = picker

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let goal = goals[max(0, min(goals.count - 1, picker.indexOfSelectedItem))]

        let directory = goal.makefile.path.deletingLastPathComponent()
		let configuration = LaunchConfiguration(
			name: LaunchNames.free(
				like: "make \(goal.name)", avoiding: launchConfigurations.map(\.name)
			),
			type: "shell",
			program: "make",
			arguments: [goal.name],
			workingDirectory: directory.path
		)
		do {
			_ = try LaunchStore.save(configuration, in: launchRoot)
		} catch {
			notify("Could not write the configuration", detail: error.localizedDescription)
			return
		}
		refreshRunConfigurations()
		selectedConfigurationName = configuration.name
		refreshRunControl()
	}

	/// Runs a goal the Makefile defines but nothing here can debug.
	///
	/// Exactly what `make <goal>` does, in the terminal, where its output
	/// belongs — the same path the play button beside a target in a Makefile
	/// takes.
	@objc private func makeGoalRunChosen(_ sender: NSMenuItem) {
		guard let parts = sender.representedObject as? [String], parts.count == 2 else { return }
		// Chosen, not started: picking something from a list of things to run
		// says which one, and the play button says when. Starting a build
		// because somebody looked at the menu is a surprise.
		selectedMakeRun = RunConfiguration(
			name: "make \(parts[1])",
			source: .make,
			executable: "make",
			arguments: [parts[1]],
			workingDirectory: URL(fileURLWithPath: parts[0]).deletingLastPathComponent().path
		)
		selectedConfigurationName = selectedMakeRun?.name
		refreshRunControl()
	}

	/// A goal from a build file chosen from the menu that has no launch
	/// configuration — a make target, a Maven goal, a Gradle task. Play runs it
	/// the way its build tool would.
	///
	/// Named for make because make was the first, and the selection model calls
	/// it that too. Nothing about it is make-specific.
	private var selectedMakeRun: RunConfiguration?

	/// Runs a goal of a Maven or Gradle build, chosen from the run menu.
	///
	/// Chosen, not started — the same bargain as a make goal: picking from a
	/// list says which one, and the play button says when.
	@objc private func buildGoalChosen(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? String,
		      let configuration = runConfigurations.first(where: { $0.id == id })
		else { return }

		selectedMakeRun = configuration
		selectedConfigurationName = configuration.name
		refreshRunControl()
	}

	@objc private func makeGoalChosen(_ sender: NSMenuItem) {
		guard let project,
		      let parts = sender.representedObject as? [String], parts.count == 2,
		      let makefile = Makefile.read(at: URL(fileURLWithPath: parts[0]))
		else {
			notify("That Makefile could not be read")
			return
		}

		// Chosen, not started: picking something from a list of things to run
		// says which one, and the play button says when.
		switch MakeLaunch.choice(for: parts[1], in: makefile, projectRoot: project.root) {
		case let .run(configuration):
			selectedMakeRun = configuration
			selectedConfigurationName = configuration.name
			refreshRunControl()

		case let .debug(configuration):
			do {
				_ = try LaunchStore.save(configuration, in: launchRoot)
				selectedMakeRun = nil
				selectedConfigurationName = configuration.name
				refreshRunControl()
				notify(
					"Added “\(configuration.name)”",
					detail: Self.describe(configuration, root: launchRoot),
					kind: .information
				)
			} catch {
				notify("Could not write launch.json", detail: error.localizedDescription)
			}
		}
	}

	/// What a derived configuration will actually do, in a sentence or three.
	private static func describe(_ configuration: LaunchConfiguration, root: URL) -> String {
		var lines: [String] = []
		if let step = configuration.makeStep {
			lines.append("Builds with make \(step.targets.joined(separator: " ")) first.")
		}
		lines.append("Debugs \(configuration.program) with the arguments the recipe passes.")
		if !configuration.environmentCommands.isEmpty {
			let names = configuration.environmentCommands.keys.sorted().joined(separator: ", ")
			lines.append("\(names) come from the shell each time it starts.")
		}
		return lines.joined(separator: "\n")
	}

	@objc private func configurationChosen(_ sender: NSMenuItem) {
		selectedMakeRun = nil
		selectedConfigurationName = sender.representedObject as? String
		refreshRunControl()
	}

	@objc private func openLaunchFile() {
		guard project != nil else { return }
		let file = LaunchFile.url(in: launchRoot)
		guard FileManager.default.fileExists(atPath: file.path) else {
			notify("No launch.json yet", detail: "Press run once and one will be written.", kind: .information)
			return
		}
		editor.open(fileURL: file, focusEditor: true)
	}

	@objc private func addConfiguration() {
		guard let project else { return }
		let suggestion = LaunchFile.suggestion(for: launchRoot)
			?? LaunchConfiguration(name: project.name, type: "lldb", program: "${workspaceFolder}")
		presentConfigurationEditor(suggestion, isNew: true)
	}

	/// Copies the selected configuration under a free name and opens it.
	///
	/// The copy is what somebody wanted: the same program and arguments, run
	/// somewhere else. It opens in the editor because the name and the one
	/// field that differs are the reason for making it.
	@objc private func duplicateSelectedConfiguration() {
		guard let configuration = selectedConfiguration else { return }
		var copy = configuration
		copy.name = LaunchNames.copy(
			of: configuration.name, avoiding: launchConfigurations.map(\.name)
		)
		presentConfigurationEditor(copy, isNew: true)
	}

	@objc private func editSelectedConfiguration() {
		guard let configuration = selectedConfiguration else { return }
		presentConfigurationEditor(configuration, isNew: false)
	}

	/// Asks for the parts of a configuration worth changing by hand.
	///
	/// Arguments, working directory and environment — the three that differ
	/// between one run and the next. Everything else in the entry is left
	/// alone, including keys this app knows nothing about.
	private func presentConfigurationEditor(_ configuration: LaunchConfiguration, isNew: Bool) {
		guard project != nil else { return }

		// A configuration that is not written down yet is written now, so the
		// page has something to select. Nothing is lost by it: an unwanted one
		// is deleted with the same button that deletes any other.
		if isNew {
			let free = LaunchNames.free(
				like: configuration.name, avoiding: launchConfigurations.map(\.name)
			)
			var stored = configuration
			stored.name = free
			do {
				_ = try LaunchStore.save(stored, in: launchRoot)
			} catch {
				notify("Could not write the configuration", detail: error.localizedDescription)
				return
			}
			selectedConfigurationName = free
			refreshRunControl()
			showLaunchConfigurations(selecting: free)
			return
		}
		showLaunchConfigurations(selecting: configuration.name)
	}

	/// Opens the settings as a page in the editor.
	///
	/// A page rather than a window: a setting is judged by what it does to the
	/// thing beside it, and a preferences window covers exactly that.
	@objc func showSettingsPage(_ sender: Any?) {
		leaveTerminalFullScreen()
		guard let group = editor.activeGroup else { return }
		let page = (group.page(identifier: "settings") as? SettingsPage) ?? SettingsPage()
		group.openPage(page, title: "Settings", identifier: "settings", symbol: "gearshape")
		if let section = settingsSectionForTesting { page.show(named: section) }
		if let folded = settingsFoldForTesting { page.toggleFold(named: folded) }
	}

	/// Which section a capture run asked for.
	var settingsSectionForTesting: String?

	/// And which one it asked to be folded away, since a triangle needs a click.
	var settingsFoldForTesting: String?

	/// Opens the launch configurations as a page in the editor.
	///
	/// A page rather than a dialog: a configuration is edited while looking at
	/// the code it runs, and a modal panel takes the project away for as long
	/// as it is open.
	func showLaunchConfigurations(selecting name: String? = nil) {
		leaveTerminalFullScreen()
		guard project != nil, let group = editor.activeGroup else { return }

		let page = (group.page(identifier: "launch") as? LaunchConfigurationsPage)
			?? LaunchConfigurationsPage()
		page.onSave = { [weak self] updated, previousName in
			guard let self else { return }
			do {
				// Renaming replaces rather than duplicating.
				if let previousName, previousName != updated.name {
					_ = try LaunchStore.remove(named: previousName, in: launchRoot)
					if self.selectedConfigurationName == previousName {
						self.selectedConfigurationName = updated.name
					}
				}
				_ = try LaunchStore.save(updated, in: launchRoot)
				self.refreshRunControl()
			} catch {
				self.notify("Could not write the configuration", detail: error.localizedDescription)
			}
		}
		page.onDelete = { [weak self] name in
			guard let self else { return }
			_ = try? LaunchStore.remove(named: name, in: launchRoot)
			if self.selectedConfigurationName == name { self.selectedConfigurationName = nil }
			self.refreshRunControl()
		}
		page.onStart = { [weak self] configuration, mode in
			guard let self else { return }
			self.selectedConfigurationName = configuration.name
			self.refreshRunControl()
			switch mode {
			case .run: self.runSelectedConfiguration(debug: false)
			case .debug: self.runSelectedConfiguration(debug: true)
			case .profile: self.profileSelectedConfiguration()
			case .coverage: self.runSelectedWithCoverage()
			}
		}

		group.openPage(page, title: "Launch Configurations", identifier: "launch", symbol: "play.square")

		// The part being worked on, not the repository around it: a subproject
		// has its own configurations, and a page showing the ones belonging to
		// somewhere else is a page showing nothing.
		page.load(
			LaunchStore.read(in: launchRoot),
			root: launchRoot,
			selecting: name ?? selectedConfigurationName
		)

		// The clusters this machine knows about, once kubectl has answered:
		// asking takes a moment and the rest of the page should not wait.
		if Kubernetes.isAvailable {
			Task { @MainActor [weak page] in
				let contexts = await Kubernetes.contexts()
				page?.setContexts(contexts)
			}
		}
	}

	/// Brings the debug panel forward.
	///
	/// Only that: what to start when nothing is running is a question with more
	/// than one answer, and the strip's button asks it rather than guessing.
	@objc func showDebugPanel(_ sender: Any?) {
		setPanelVisible(true)
		bottomPanel.showDebug()
	}

	/// ⌘T while the keyboard is in the terminal: another tab.
	///
	/// Enabled only there, so the shortcut belongs to the terminal the way it
	/// does in a terminal application, and is not taken away from anything
	/// else that might want it elsewhere in the window.
	@objc func newTerminalTab(_ sender: Any?) {
		guard bottomPanel.hasKeyboardFocus else { return }
		bottomPanel.newTerminal()
	}

	var isTerminalFocused: Bool { bottomPanel.hasKeyboardFocus }

	/// Keystrokes a terminal has a prior claim on.
	///
	/// Control and a letter is the shell's own alphabet: this app may borrow
	/// one for a menu, but not while the keyboard is in a terminal.
	private static let terminalShortcuts: [(key: String, modifiers: NSEvent.ModifierFlags)] = [
		("a", [.control]), ("c", [.control]), ("d", [.control]), ("e", [.control]),
		("k", [.control]), ("l", [.control]), ("n", [.control]), ("p", [.control]),
		("r", [.control]), ("u", [.control]), ("w", [.control]), ("z", [.control]),
	]
	var terminalSessionCountForTesting: Int { bottomPanel.sessionCountForTesting }

	// MARK: - Zoom

	@objc func zoomIn(_ sender: Any?) {
		Settings.shared.zoomIn()
	}

	@objc func zoomOut(_ sender: Any?) {
		Settings.shared.zoomOut()
	}

	@objc func resetZoom(_ sender: Any?) {
		Settings.shared.resetZoom()
	}

	/// Sets the window up to be shown to a room, or puts it back.
	///
	/// Both halves are one switch: the zoom a room needs and a palette a
	/// projector can actually show. Neither overwrites what was there — they
	/// are a second pair of preferences — so coming back is exact, whatever was
	/// zoomed or re-themed during the talk.
	@objc func togglePresentationMode(_ sender: Any?) {
		Settings.shared.presenting.toggle()
	}

	@objc func splitEditorRight(_ sender: Any?) {
		editor.splitActiveGroup(vertical: true)
	}

	@objc func splitEditorDown(_ sender: Any?) {
		editor.splitActiveGroup(vertical: false)
	}

	func previewDropZone(_ zone: EditorTabDrag.Zone) {
		editor.previewDropZoneForTesting(zone)
	}

	/// Selects a sidebar tool window, the way a tab strip does.
	///
	/// The strip buttons are tabs, not independent toggles: picking one shows
	/// it, whatever was showing before. Clicking the tool that is already
	/// showing closes the sidebar, which is what IDEA does and the only way to
	/// reclaim the space.
	func showSidebarTool(_ tool: SidebarToolKind) {
		// The terminal has the window: there is no sidebar to put anything in,
		// so the tool comes out over the top of it instead. Shrinking the
		// terminal to show a file tree is not what "give me the window" meant.
		if isPanelMaximized {
			showToolPopover(tool)
			return
		}

		// Hidden, or dragged shut until there is nothing left of it — which is
		// the same thing to look at and was not the same thing to the code:
		// pressing ⌘2 on a sidebar somebody had dragged closed did nothing at
		// all, twice, because it thought it was already showing.
		let isCollapsed = navigatorContainer.isHidden
			|| splitView.isSubviewCollapsed(navigatorContainer)
			|| navigatorContainer.frame.width < 2

		if !isCollapsed, tool == currentSidebarTool {
			toggleNavigator(nil)
			return
		}

		install(tool: tool)
		if isCollapsed { openNavigator() }
		updateSidebarSelection()
	}

	/// Shows a sidebar tool over the terminal, hanging off its own button.
	///
	/// The same views the sidebar would hold — built the same way, and put back
	/// where they belong when the popover closes.
	private func showToolPopover(_ tool: SidebarToolKind) {
		// Asking for the one already showing puts it away, which is what the
		// button does everywhere else.
		if toolPopover?.isShown == true, popoverTool == tool {
			toolPopover?.performClose(nil)
			return
		}
		toolPopover?.performClose(nil)

		guard let anchor = toolStrip.button(for: tool) else { return }
		guard let view = makeToolView(tool) else {
			installWhenRepositoryIsReady(tool)
			return
		}

		let holder = NSViewController()
		let background = ColoredView(color: Theme.current.sidebarBackground)
		background.colourSource = { Theme.current.sidebarBackground }
		holder.view = background
		view.translatesAutoresizingMaskIntoConstraints = false
		holder.view.addSubview(view)

		// A popover has no titlebar to duck under. The tree insets itself for
		// one and would leave a hand's width of nothing at the top; the panes
		// that do not are given a little room instead of starting hard against
		// the edge.
		if tool == .project { navigator.setTopInset(0) }
		let top = tool == .project ? 0 : Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: holder.view.topAnchor, constant: top),
			view.bottomAnchor.constraint(
				equalTo: holder.view.bottomAnchor, constant: -Theme.current.scaled(4)
			),
			view.leadingAnchor.constraint(equalTo: holder.view.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: holder.view.trailingAnchor),
		])
		holder.view.frame = NSRect(
			x: 0, y: 0,
			width: Theme.current.scaled(340),
			height: min(Theme.current.scaled(560), (window?.frame.height ?? 700) - 120)
		)

		let popover = NSPopover()
		popover.contentViewController = holder
		popover.behavior = .transient
		popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)

		toolPopover = popover
		popoverTool = tool
		// What the sidebar is showing is not changed by looking at something
		// over the terminal: it is what comes back when the terminal gives the
		// window up.
		toolStrip.setSidebarSelection(visible: true, tool: tool)

		// The views are the sidebar's own — the tree especially — so when the
		// popover goes away they are put back into it, ready for whenever the
		// terminal gives the window back.
		popoverObserver = NotificationCenter.default.addObserver(
			forName: NSPopover.didCloseNotification,
			object: popover,
			queue: .main
		) { [weak self] _ in
			guard let self else { return }
			self.toolPopover = nil
			self.popoverTool = nil
			self.toolStrip.setSidebarSelection(visible: false, tool: self.currentSidebarTool)
			// The popover borrowed the sidebar's own views — the tree most of
			// all — so they are put back where they belong.
			self.install(tool: self.currentSidebarTool, force: true)
			// The tree ducks under the titlebar again once it is back in the
			// sidebar.
			self.updateTopInsets()
			if let observer = self.popoverObserver {
				NotificationCenter.default.removeObserver(observer)
				self.popoverObserver = nil
			}
		}
	}

	/// The tool showing over the terminal, if one is.
	private var toolPopover: NSPopover?
	private var popoverTool: SidebarToolKind?
	private var popoverObserver: NSObjectProtocol?

	private func updateSidebarSelection() {
		let visible = !navigatorContainer.isHidden
		toolStrip.setSidebarSelection(visible: visible, tool: currentSidebarTool)
	}

	/// Puts a tool's view in the sidebar's primary pane, replacing what was
	/// there.
	///
	/// The panes are built on demand rather than kept alive: each watches the
	/// work tree or the open file, and several doing that while one is visible
	/// is work nobody asked for.
	/// Puts a tool up once the repository has been read.
	///
	/// The panes that need git are built with a repository in hand, and asking
	/// for one before the read has finished used to leave the sidebar blank.
	private func installWhenRepositoryIsReady(_ tool: SidebarToolKind) {
		// Remembered so the strip shows what will appear, and so a second ask
		// for the same tool does not queue a second wait.
		guard pendingSidebarTool != tool else { return }
		pendingSidebarTool = tool

		Task { @MainActor [weak self] in
			await self?.project?.loadGit()
			guard let self, self.pendingSidebarTool == tool else { return }
			self.pendingSidebarTool = nil
			guard self.makeToolView(tool) != nil else { return }
			self.install(tool: tool, force: true)
			self.updateSidebarSelection()
		}
	}

	/// A tool asked for before the project it needs had been read.
	private var pendingSidebarTool: SidebarToolKind?

	/// Whether this window has already arranged its terminal the way the
	/// setting asks. Only the first project it opens counts.
	private var hasArrangedTerminal = false

	/// Gives the terminal the window, once there is a window to give.
	///
	/// Maximising divides the window's height, and a window that has not been
	/// laid out has none to divide — the split silently does nothing and the
	/// terminal stays where it was, which is what "not reliably" looked like.
	/// So it waits for a height, and gives up after a second rather than
	/// spinning if one never arrives.
	private func maximizeTerminalWhenLaidOut(attempt: Int = 0) {
		DispatchQueue.main.async { [weak self] in
			guard let self, !self.isPanelMaximized else { return }
			guard self.verticalSplitView.bounds.height > 200 else {
				guard attempt < 60 else { return }
				self.maximizeTerminalWhenLaidOut(attempt: attempt + 1)
				return
			}
			self.togglePanelMaximized(nil)
		}
	}

	private func install(tool: SidebarToolKind, force: Bool = false) {
		guard force || currentSidebarTool != tool || primaryToolView == nil else { return }

		// Cleared before building, not after: building is what sets the new
		// one, and clearing afterwards threw away the reference that had just
		// been made — which is how the history pane came to exist on screen
		// while nothing could reach it.
		changesPane = nil
		branchesPane = nil
		structurePane = nil
		scratchesPane = nil
		historyPane = nil

		// Built before anything is taken down. The panes that need a repository
		// cannot be built until it has been read, and tearing the sidebar down
		// first left it empty until somebody thought to close and reopen it.
		guard let view = makeToolView(tool) else {
			installWhenRepositoryIsReady(tool)
			return
		}

		primaryToolView?.removeFromSuperview()
		primaryToolTop = nil
		navigator.view.removeFromSuperview()

		currentSidebarTool = tool
		primaryToolView = install(view: view, for: tool)
	}

	/// Puts a built view into the sidebar and returns it.
	private func install(view: NSView, for tool: SidebarToolKind) -> NSView {
		view.translatesAutoresizingMaskIntoConstraints = false
		primaryContainer.addSubview(view)

		// The navigator insets itself for the titlebar; the other panes are
		// plain views, so the container does it for them.
		let inset = tool == .project ? 0 : sidebarTopInset
		let top = view.topAnchor.constraint(equalTo: primaryContainer.topAnchor, constant: inset)
		NSLayoutConstraint.activate([
			top,
			view.bottomAnchor.constraint(equalTo: primaryContainer.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: primaryContainer.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: primaryContainer.trailingAnchor),
		])

		primaryToolTop = tool == .project ? nil : top
		updateTopInsets()
		return view
	}

	/// Builds a tool's view, or nil when what it needs is not there yet.
	private func makeToolView(_ tool: SidebarToolKind) -> NSView? {
		let view: NSView

		switch tool {
		case .project:
			view = navigator.view
		case .changes:
			// Nothing to show until the project's repository has been read,
			// which the caller waits for rather than leaving the sidebar empty.
			guard let project, project.git != nil else { return nil }
			let pane = ChangesPane(root: scopeRoot ?? project.root)
			pane.onSelectChange = { [weak self] change in self?.showDiff(for: change) }
			pane.onWorkingCopyChanged = { [weak self] in self?.navigator.refreshGitStatus() }
			changesPane = pane
			view = pane
		case .branches:
			// Nothing to show until the project's repository has been read,
			// which the caller waits for rather than leaving the sidebar empty.
			guard let project, project.git != nil else { return nil }
			let pane = BranchesPane(root: scopeRoot ?? project.root)
			// A worktree is a project in its own right, so opening one is
			// switching to it rather than checking anything out.
			pane.onOpenWorktree = { [weak self] path in
				self?.switchProject(to: path)
			}
			pane.onRepositoryChanged = { [weak self] in
				// A checkout changes the branch the titlebar shows, so the
				// repository is read again — the same read everything else
				// awaits.
				self?.readGit()
			}
			branchesPane = pane
			view = pane
		case .history:
			// Nothing to show until the project's repository has been read,
			// which the caller waits for rather than leaving the sidebar empty.
			guard let project, project.git != nil else { return nil }
			let pane = HistoryPane(root: scopeRoot ?? project.root)
			pane.offerScope(path: relativePathOfActiveFile())
			pane.onSelectFile = { [weak self] commit, file in
				self?.showCommitDiff(commit: commit, file: file)
			}
			historyPane = pane
			view = pane
		case .scratches:
			let pane = ScratchesPane(projectRoot: project?.root)
			pane.onOpen = { [weak self] url, preview in
				self?.editor.open(fileURL: url, focusEditor: !preview, preview: preview)
			}
			pane.onMoved = { [weak self] from, to in
				self?.editor.scratchMoved(from: from, to: to)
			}
			pane.onWillModify = { [weak self] url in self?.editor.saveIfOpen(url) }
			scratchesPane = pane
			view = pane
		case .structure:
			let pane = StructurePane()
			pane.onSelectSymbol = { [weak self] line in
				guard let url = self?.editor.activeGroup.activeTabURL else { return }
				self?.editor.open(fileURL: url, atLine: line + 1)
			}
			structurePane = pane
			view = pane
			refreshStructure()
		}

		return view
	}

	/// Hands the active file's outline to the structure view.
	func refreshStructure() {
		guard let pane = structurePane else { return }
		guard let document = editor.activeGroup.activeDocument else {
			pane.setSymbols([], fileName: nil)
			return
		}
		let name = editor.activeGroup.activeTabURL?.lastPathComponent
		document.symbols { [weak pane] symbols in
			pane?.setSymbols(symbols, fileName: name)
		}
	}

	/// Kept for the menu items and the screenshot harness.
	@objc func showProjectView(_ sender: Any?) { showSidebarTool(.project) }
	@objc func toggleChanges(_ sender: Any?) { showSidebarTool(.changes) }
	@objc func toggleBranchesView(_ sender: Any?) { showSidebarTool(.branches) }
	@objc func toggleStructureView(_ sender: Any?) { showSidebarTool(.structure) }
	@objc func toggleScratchesView(_ sender: Any?) { showSidebarTool(.scratches) }
	@objc func toggleHistoryView(_ sender: Any?) { showSidebarTool(.history) }

	/// Moves the selected lines across the index, in whichever direction the
	/// diff's side implies.
	private func applyDiffSelection(change: GitChange, diff: String, lines: Set<Int>) {
		guard let project, !lines.isEmpty else { return }
		Task { @MainActor in
			let result = change.isStaged
				? await GitWorkingCopy.unstage(lines: lines, ofDiff: diff, in: project.root)
				: await GitWorkingCopy.stage(lines: lines, ofDiff: diff, in: project.root)
			finishDiffOperation(result, change: change)
		}
	}

	private func discardDiffSelection(change: GitChange, diff: String, lines: Set<Int>) {
		guard let project, !lines.isEmpty else { return }

		// Discarding is the one operation here that destroys work, so it asks.
		let alert = NSAlert()
		alert.messageText = "Discard \(lines.count) line\(lines.count == 1 ? "" : "s")?"
		alert.informativeText = "The change will be removed from \(change.name). This cannot be undone."
		alert.addButton(withTitle: "Discard")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			Task { @MainActor in
				// Reversing the patch against the work tree is the same operation
				// as unstaging, just without --cached.
				guard let patch = GitPatch.parse(diff).patch(selecting: lines, reverse: true) else { return }
				let result = await GitRepository.run(
					["apply", "--reverse", "--recount", "--whitespace=nowarn", "-"],
					in: project.root,
					input: Data(patch.utf8)
				)
				self.finishDiffOperation(result, change: change)
			}
		}

		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	private func finishDiffOperation(_ result: GitRepository.ProcessResult, change: GitChange) {
		if result.exitCode != 0 {
			notify(
				"git reported a problem",
				detail: (result.stderr.isEmpty ? result.stdout : result.stderr)
					.trimmingCharacters(in: .whitespacesAndNewlines)
			)
			return
		}

		changesPane?.refresh()
		navigator.refreshGitStatus()
		// The diff on screen described the state before this ran, so it is
		// re-read rather than left showing lines that have already moved.
		showDiff(for: change)
	}

	/// Opens the diff for a change as an editor tab.
	private func showDiff(for change: GitChange) {
		guard let project else { return }
		Task { @MainActor in
			let text = await GitWorkingCopy.diff(
				for: change.path,
				staged: change.isStaged,
				in: project.root
			)
			editor.openDiff(for: change, root: project.root, text: text)
		}
	}

	/// Opens the diff a commit made to one of its files.
	private func showCommitDiff(commit: GitCommit, file: GitCommitFile) {
		guard let project else { return }
		Task { @MainActor in
			let text = await GitHistory.diff(of: commit.hash, path: file.path, in: project.root)
			editor.openCommitDiff(commit: commit, file: file, root: project.root, text: text)
		}
	}

	/// What the editor has open, relative to the project — the file a history
	/// view offers to narrow itself to.
	private func relativePathOfActiveFile() -> String? {
		guard let project, let url = editor.activeGroup?.activeTabURL else { return nil }
		let root = project.root.standardizedFileURL.path
		guard url.path.hasPrefix(root + "/") else { return nil }
		return String(url.path.dropFirst(root.count + 1))
	}

	/// Sets a breakpoint as a gutter click would, for verifying alignment.
	/// Presses stop, as the titlebar button does.
	func stopRunningForTesting() { stopRunning() }

	/// Sets a breakpoint and turns it off, as clicking its marker does.
	func disableBreakpointForTesting(line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		toggleBreakpoint(file: url, line: line)
		setBreakpoint(file: url, line: line, enabled: false)
	}

	/// Opens the breakpoint options sheet, as right-clicking the gutter does.
	func editBreakpointForTesting(line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		editBreakpoint(file: url, line: line)
	}

	/// Presses a key with Option held in the terminal, and says what it sent.
	func optionKeyForTesting(bare: String, composed: String) -> String {
		setPanelVisible(true)
		return bottomPanel.optionKeyForTesting(bare: bare, composed: composed)
	}

	/// Feeds the terminal a burst of frames, as a program running unwatched does.
	func burstForTesting(frames: Int) -> Int {
		setPanelVisible(true)
		return bottomPanel.burstForTesting(frames: frames)
	}

	/// Presses keys by key code in the terminal, and says what each one did.
	func deadKeyForTesting(presses: [(code: UInt16, shift: Bool)]) -> String {
		setPanelVisible(true)
		return bottomPanel.deadKeyForTesting(presses: presses)
	}

	/// What the editor is holding, saved or not.
	func editorTextForTesting() -> String? { editor.textForTesting }

	/// Clicks below the last line of the open file, and says what happened.
	func clickBelowLastLineForTesting() -> String { editor.clickBelowLastLineForTesting() }

	func globalScratchDirectoryForTesting() -> String { editor.globalScratchDirectoryForTesting() }

	func layoutReportForTesting() -> String { editor.layoutReportForTesting() }

	/// What a right-click on the tab strip offers, over a tab and over the rest.
	func tabMenuTitlesForTesting(overTab: Bool) -> [String] {
		editor.tabMenuTitlesForTesting(overTab: overTab)
	}

	/// Indents or outdents a block, and prints what the file became.
	func exerciseIndentForTesting(from: Int, to: Int, outdent: Bool) {
		guard let text = editor.indentForTesting(fromLine: from, toLine: to, outdent: outdent) else {
			print("INDENT: no editor")
			return
		}
		let lines = text.components(separatedBy: "\n").prefix(6)
		print("INDENT\(outdent ? "-OUT" : "-IN"):")
		for (index, line) in lines.enumerated() {
			print("  \(index): \(line.replacingOccurrences(of: "\t", with: "→"))")
		}
	}

	func toggleBreakpointForTesting(line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		toggleBreakpoint(file: url, line: line)
	}

	/// Where the open file's breakpoints are and what each is anchored to.
	///
	/// Anchoring is invisible until a file is rewritten under it, and the gutter
	/// only says which line — not what the breakpoint believes it is on. This
	/// says both, so a rewrite can be checked rather than looked at.
	func breakpointReportForTesting() -> String {
		guard let url = editor.activeGroup.activeTabURL else { return "no file open" }
		let list = breakpoints(inFile: FilePath.canonical(url))
		guard !list.isEmpty else { return "no breakpoints" }

		return list.map { breakpoint in
			guard let anchor = breakpoint.anchor else { return "line \(breakpoint.line): unanchored" }
			let symbol = anchor.path.isEmpty ? "(no symbol)" : anchor.path.joined(separator: ".")
			return "line \(breakpoint.line): \(symbol)+\(anchor.offset) \"\(anchor.text)\""
		}
		.joined(separator: "\n")
	}

	/// Invokes the gutter's run action, for verifying it end to end.
	func runLineForTesting(_ line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		runConfiguration(forFile: url, line: line)
	}

	/// Runs, or debugs, the configuration on a line without going through the
	/// menu — which is a separate window the harness cannot reach.
	func invokeForTesting(line: Int, debug wantsDebug: Bool) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		let path = RunConfigurationDiscovery.canonicalPath(url)
		guard let configuration = runConfigurations.first(where: {
			$0.file == path && $0.line == line
		}) else { return }
		if wantsDebug { debug(configuration) } else { run(configuration) }
	}

	func createFolderForTesting(named name: String) {
		navigator.createFolderForTesting(named: name)
	}

	func searchScratchesForTesting(_ query: String) {
		if !query.isEmpty { scratchesPane?.setQueryForTesting(query) }
	}

	func selectHistoryForTesting(commit: Int, file: Int) {
		historyPane?.selectCommitForTesting(commit)
		// The files of a commit are read after it is selected.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
			self?.historyPane?.selectFileForTesting(file)
		}
	}

	/// Underlines invented problems on the open file, so the drawing can be
	/// looked at without a server having to agree to produce any.
	func injectDiagnosticsForTesting() {
		guard let url = editor.activeGroup?.activeTabURL else { return }
		LanguageService.shared.injectForTesting([
			LSPDiagnostic(
				range: LSPRange(
					start: LSPPosition(line: 4, character: 8),
					end: LSPPosition(line: 4, character: 20)
				),
				severity: .error,
				message: "cannot find 'nonesuch' in scope",
				source: "swiftc"
			),
			LSPDiagnostic(
				range: LSPRange(
					start: LSPPosition(line: 6, character: 4),
					end: LSPPosition(line: 6, character: 16)
				),
				severity: .warning,
				message: "initialization of immutable value was never used",
				source: "swiftc"
			),
			LSPDiagnostic(
				range: LSPRange(
					start: LSPPosition(line: 8, character: 0),
					end: LSPPosition(line: 8, character: 30)
				),
				severity: .information,
				message: "consider using a computed property",
				source: "swiftlint"
			),
		], for: url)
	}

	/// Presses Run twice on whatever is selected, and says what the panel is
	/// holding after each — the whole question being whether that is one
	/// console or two.
	func rerunSelectedForTesting(_ goal: String?) {
		if let goal { chooseMakeRunForTesting(goal) }
		runSelected(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
			guard let self else { return }
			print("RERUN: after one run \(self.bottomPanel.runConsolesForTesting)")
			self.runSelected(nil)
			DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
				print("RERUN: after two runs \(self.bottomPanel.runConsolesForTesting)")
			}
		}
	}

	/// Says whether the missing-server bar is up, and what it says.
	func reportServerBannerForTesting() {
		print("BANNER: \(editor.activeGroup?.serverBannerReportForTesting ?? "no editor")")
	}

	/// Presses one of the bar's buttons: details, ignore, or dismiss.
	func pressServerBannerForTesting(_ button: String) {
		editor.activeGroup?.pressServerBannerForTesting(button)
		print("BANNER: pressed \(button) -> \(editor.activeGroup?.serverBannerReportForTesting ?? "no editor")")
	}

	/// Says what a real server had to say by the time this ran.
	func reportDiagnosticsForTesting() {
		let running = LanguageService.shared.runningNames
		guard let url = editor.activeGroup?.activeTabURL else {
			print("LSP: no file open (servers: \(running))")
			return
		}
		let diagnostics = LanguageService.shared.diagnostics(for: url)
		print("LSP: servers=\(running) diagnostics=\(diagnostics.count) for \(url.lastPathComponent)")
		for diagnostic in diagnostics.prefix(5) {
			print("LSP:   \(diagnostic.severity) line \(diagnostic.range.start.line + 1): \(diagnostic.message)")
		}
	}

	/// Types, undoes, types something else, and shows the history.
	///
	/// The sequence a plain undo stack cannot survive: the first attempt is
	/// destroyed the moment the second is typed.
	func exerciseUndoTreeForTesting() {
		editor.moveCaretToEndForTesting()
		editor.simulateTyping("\n// first attempt\n")
		print("UNDO: after first  \(editor.fileHistoryReportForTesting)")

		editor.undoForTesting()
		print("UNDO: after undo   \(editor.fileHistoryReportForTesting)")

		editor.simulateTyping("\n// second attempt\n")
		print("UNDO: after second \(editor.fileHistoryReportForTesting)")

		editor.toggleFileHistory()
		print("UNDO: states       \(editor.historySummariesForTesting)")

		// Back to the abandoned branch, which no amount of redo would reach.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
			guard let self else { return }
			let summaries = self.editor.historySummariesForTesting
			if let index = summaries.firstIndex(where: { $0.contains("first attempt") }) {
				self.editor.travelToHistoryRowForTesting(index)
				print("UNDO: travelled to the first attempt")
			}
			print("UNDO: text tail    \(self.editor.textTailForTesting)")
		}
	}

	/// Types at the end of the file and leaves the completion list up.
	func exerciseCompletionForTesting(typing text: String) {
		editor.moveCaretToEndForTesting()
		editor.simulateTyping("\n")
		editor.simulateTyping(text)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
			guard let self else { return }
			print("COMPLETE: \(self.editor.completionReportForTesting)")

			self.editor.writeCompletionImageForTesting(to: "build/completion-list.png")

			// Down once, then take it, so what lands in the document is the
			// second suggestion rather than whatever was highlighted first.
			self.editor.moveCompletionSelectionForTesting(by: 1)
			let committed = self.editor.commitCompletionForTesting()
			print("COMMIT: \(committed) → \(self.editor.caretReportForTesting)")
		}
	}

	/// Walks the caret by word and says where it landed at each step.
	func exerciseWordNavigationForTesting() {
		print("WORD: start \(editor.caretReportForTesting)")
		editor.simulateArrow("right", modifiers: .option)
		print("WORD: ⌥→ \(editor.caretReportForTesting)")
		editor.simulateArrow("right", modifiers: .option)
		print("WORD: ⌥→ \(editor.caretReportForTesting)")
		editor.simulateArrow("right", modifiers: [.option, .shift])
		print("WORD: ⇧⌥→ \(editor.caretReportForTesting)")
		editor.simulateArrow("left", modifiers: .option)
		print("WORD: ⌥← \(editor.caretReportForTesting)")
		editor.simulateArrow("left", modifiers: .option)
		print("WORD: ⌥← \(editor.caretReportForTesting)")
	}

	func openFirstScratchForTesting() {
		scratchesPane?.openFirstForTesting()
	}

	func createFileForTesting(named name: String) {
		navigator.createFileForTesting(named: name)
	}

	func selectFirstChangeForTesting() {
		changesPane?.selectFirstChangeForTesting()
	}

	func selectDiffHunkForTesting(_ hunk: Int) {
		editor.selectDiffHunkForTesting(hunk)
	}

	func setWordWrap(_ enabled: Bool) {
		guard Settings.shared.wordWrap != enabled else { return }
		toggleWordWrap(nil)
	}

	func setPreviewMode(_ mode: PreviewMode) {
		editor.setPreviewMode(mode)
	}

	/// The four preview modes, as menu commands.
	///
	/// One action rather than four: the mode is on the item, which is what the
	/// tab strip's own dropdown already does, and it keeps the four of them
	/// from drifting apart. Being menu commands is what gives them keys at all,
	/// and — since the palette is the menus — what puts them in the palette.
	@objc func choosePreviewMode(_ sender: Any?) {
		guard let item = sender as? NSMenuItem,
		      let raw = item.representedObject as? String,
		      let mode = PreviewMode(rawValue: raw)
		else { return }
		setPreviewMode(mode)
	}

	/// Which modes the file in front can be shown in, and which it is in now.
	func previewModeState() -> (available: [PreviewMode], current: PreviewMode)? {
		guard let url = editor.activeGroup?.activeTabURL else { return nil }
		let modes = FilePreview.availableModes(for: url)
		guard modes.count > 1 else { return nil }
		return (modes, editor.activeGroup?.currentPreviewMode ?? .source)
	}

	@objc func toggleBlame(_ sender: Any?) {
		editor.toggleBlame()
	}

	@objc func toggleWordWrap(_ sender: Any?) {
		editor.toggleWordWrap()
	}

	@objc func toggleMarkdownPreview(_ sender: Any?) {
		editor.toggleMarkdownPreview()
	}

	@objc func selectNextTab(_ sender: Any?) { editor.selectNextTab(offset: 1) }
	@objc func selectPreviousTab(_ sender: Any?) { editor.selectNextTab(offset: -1) }

	/// Expands the first level of the tree, used by capture runs and after
	/// opening a project so the navigator is not just a single root row.
	func expandNavigatorTree() {
		navigator.expandTopLevel()
	}

	/// Drives the editor's real text-input path, so a capture run exercises the
	/// same code a keystroke does rather than poking the buffer directly.
	func simulateTyping(_ text: String) {
		editor.simulateTyping(text)
	}

	// MARK: - Actions

	/// Opens the sidebar, whichever way it came to be shut.
	private func openNavigator() {
		guard let navigatorContainer else { return }
		// A width of nothing is what a sidebar dragged shut leaves behind, and
		// opening it to nothing is the same as not opening it.
		navigatorWidth = max(200, navigatorWidth)
		navigatorWidthConstraint.constant = navigatorWidth
		navigatorContainer.isHidden = false
		splitView.setPosition(navigatorWidth, ofDividerAt: 0)
		toolStrip.setSidebarSelection(visible: true, tool: currentSidebarTool)
		splitView.adjustSubviews()
	}

	@objc func toggleNavigator(_ sender: Any?) {
		guard let navigatorContainer else { return }
		let collapsed = splitView.isSubviewCollapsed(navigatorContainer)
			|| navigatorContainer.isHidden
			|| navigatorContainer.frame.width < 2
		if collapsed {
			navigatorWidthConstraint.constant = navigatorWidth
			splitView.setPosition(navigatorWidth, ofDividerAt: 0)
			navigatorContainer.isHidden = false
		} else {
			navigatorWidth = max(180, navigatorContainer.frame.width)
			navigatorContainer.isHidden = true
		}
		// Selection follows which tool is showing, not merely that one is: the
		// strip is a tab strip now.
		toolStrip.setSidebarSelection(visible: collapsed, tool: currentSidebarTool)
		splitView.adjustSubviews()
	}

	@objc func saveDocument(_ sender: Any?) {
		editor.save()
	}

	@objc func collapseAllFolds(_ sender: Any?) {
		editor.collapseAllFolds()
	}

	@objc func expandAllFolds(_ sender: Any?) {
		editor.expandAllFolds()
	}

	/// Walks a sequence of theme settings and says what each one resolved to.
	///
	/// The sequence is the point: switching to "system" after a fixed theme is
	/// the case that was broken, and asking about "system" on its own would
	/// never have shown it — the app only answers with the appearance it was
	/// forced once something has forced one.
	func appearanceWalkForTesting(_ steps: String) -> String {
		var said: [String] = ["system is \(Theme.systemIsDark ? "dark" : "light")"]
		for step in steps.split(separator: ",") {
			Settings.shared.appearance = String(step)
			Theme.apply()
			said.append("\(step) → \(Theme.current.name)")
		}
		return said.joined(separator: " | ")
	}

	/// What the palette offers for a query, with the keys each answers to.
	///
	/// Read from the menus, which is where they come from: a list that says how
	/// many there are and what they are called is the only way to see that a
	/// command added to a menu arrived here without anybody doing anything.
	func paletteCommandsForTesting(query: String) -> String {
		// Menu validation answers about the responder chain of the key window,
		// so a run that never came to the front sees every item disabled and
		// the palette reports nothing at all.
		NSApp.activate(ignoringOtherApps: true)
		window?.makeKeyAndOrderFront(nil)

		let commands = CommandSearch.match(MenuCommands.all().map(\.descriptor), query: query)
		let lines = commands.prefix(12).map { command in
			"  \(command.qualifiedTitle)\(command.shortcut.map { "  [\($0)]" } ?? "")"
		}
		return "\(commands.count) commands\n" + lines.joined(separator: "\n")
	}

	@objc func showProjectSwitcher(_ sender: Any?) {
		guard let capsule else { return }
		capsule.menuHalf = .project
		ProjectSwitcherPopover.show(
			relativeTo: capsule,
			anchorRect: capsule.projectRect,
			currentProject: project,
			owner: self
		)
	}

	// MARK: - NSWindowDelegate

	func windowDidResize(_ notification: Notification) {
		// Entering or leaving full screen changes the titlebar height.
		updateTopInsets()
	}

	func windowDidEnterFullScreen(_ notification: Notification) { updateTopInsets() }
	func windowDidExitFullScreen(_ notification: Notification) { updateTopInsets() }

	/// Coming back to the window is when an external edit is most likely to
	/// have happened, and the file system watcher does not fire for a file
	/// written while the app was in the background on every volume.
	func windowDidBecomeKey(_ notification: Notification) {
		editor.reloadExternallyChangedFiles()
		// The tree needs the same treatment: an agent or a checkout that adds
		// files while the app is in the background should not leave the
		// navigator showing yesterday's directory listing.
		navigator.refreshFromDisk()
	}

	func windowWillClose(_ notification: Notification) {
		rememberOpenEditors()
		bottomPanel.shutdown()
		editor.windowWillClose()
		navigator.windowWillClose()
		onClose?()
	}
}

// MARK: - Toolbar items

extension MainWindowController: NSToolbarDelegate {
	// These identifiers keep their old spelling for the same reason the window
	// autosave names do: AppKit stores a toolbar's arrangement under them, and
	// renaming would rebuild everybody's toolbar from the default.
	private static let capsuleItem = NSToolbarItem.Identifier("ideai.capsule")
	private static let subprojectItem = NSToolbarItem.Identifier("ideai.subproject")
	private static let runItem = NSToolbarItem.Identifier("ideai.run")

	/// Next to the traffic lights, where a window says what it is.
	///
	/// Centred was tried and reads as decoration: the eye starts at the top left
	/// of a window, and putting the one thing that answers "where am I" anywhere
	/// else makes it something to go looking for.
	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[Self.capsuleItem, Self.subprojectItem, .flexibleSpace, Self.runItem]
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarDefaultItemIdentifiers(toolbar)
	}

	func toolbar(
		_ toolbar: NSToolbar,
		itemForItemIdentifier identifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar flag: Bool
	) -> NSToolbarItem? {
		switch identifier {
		case Self.capsuleItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let capsule = TitlebarCapsule()
			capsule.onProject = { [weak self] in self?.showProjectSwitcher(nil) }
			capsule.onBranch = { [weak self] in self?.showBranchMenu() }
			if let project { capsule.setProject(name: project.name) }
			// Whatever the current read of the repository says, whenever it
			// says it: this item may be built before or after git answers.
			if let read = branchRead {
				Task { @MainActor in capsule.setBranch(await read.value) }
			}
			self.capsule = capsule
			item.view = capsule

			// What the overflow menu shows when the window is too narrow to
			// hold this. Without it AppKit drops the item and says nothing.
			let menu = NSMenuItem(title: "Project", action: nil, keyEquivalent: "")
			menu.submenu = {
				let submenu = NSMenu()
				submenu.addItem(menuItem("Switch Project…", #selector(showProjectSwitcher(_:))))
				submenu.addItem(menuItem("Branch…", #selector(showBranchMenuItem(_:))))
				return submenu
			}()
			item.menuFormRepresentation = menu
			// The switcher is also in the menu bar, so this is the first thing
			// that can go when there is no room.
			item.visibilityPriority = .standard
			return item

		case Self.runItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let control = RunControl()
			control.onRun = { [weak self] in self?.runSelectedConfiguration(debug: false) }
			control.onDebug = { [weak self] in self?.runSelectedConfiguration(debug: true) }
			control.onStop = { [weak self] in self?.stopRunning() }
			control.onProfile = { [weak self] in self?.profileSelectedConfiguration() }
			control.onCoverage = { [weak self] in self?.runSelectedWithCoverage() }
			control.onChooseConfiguration = { [weak self] point in
				self?.showConfigurationMenu(at: point, in: control)
			}
			control.onRunStateChanged = { [weak self] state in
				self?.setTitlebarRunState(state)
			}
			runControl = control
			item.view = control
			refreshRunControl()

			// The whole strip in a menu: run, debug, stop and the list of
			// configurations, so a narrow window loses the buttons but not the
			// ability to press them.
			let menu = NSMenuItem(title: "Run", action: nil, keyEquivalent: "")
			menu.submenu = runOverflowMenu()
			item.menuFormRepresentation = menu
			// Last to go: it is the one thing here that is pressed rather than
			// read.
			item.visibilityPriority = .high
			return item

		case Self.subprojectItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = SubprojectPillButton()
			pill.onClick = { [weak self] in self?.showSubprojectMenu() }
			pill.onLeave = { [weak self] in self?.leaveSubproject() }
			pill.setSubproject(
				subprojectRoot.flatMap { url in
					project.map { Subprojects.relativePath(url, to: $0.root) }
				}
			)
			subprojectPill = pill
			item.view = pill
			item.menuFormRepresentation = menuItem("Subproject", #selector(showSubprojectMenuItem(_:)))
			item.visibilityPriority = .low
			return item

		default:
			return nil
		}
	}

	/// A menu item pointing back at this window.
	private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		return item
	}

	@objc fileprivate func showBranchMenuItem(_ sender: Any?) { showBranchMenu() }

	@objc fileprivate func showSubprojectMenuItem(_ sender: Any?) { showSubprojectMenu() }

	/// The projects inside this one, so moving between them is a menu rather
	/// than a hunt through the tree.
	@objc func showSubprojectMenu() {
		guard let project else { return }
		let menu = NSMenu()

		let whole = NSMenuItem(
			title: project.name, action: #selector(leaveSubprojectFromMenu), keyEquivalent: ""
		)
		whole.target = self
		whole.state = subprojectRoot == nil ? .on : .off
		menu.addItem(whole)

		let found = Subprojects.find(in: project.root)
		if !found.isEmpty { menu.addItem(.separator()) }
		for url in found {
			let relative = Subprojects.relativePath(url, to: project.root)
			let item = NSMenuItem(
				title: relative, action: #selector(openSubprojectFromMenu(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = url
			item.state = url.path == subprojectRoot?.path ? .on : .off
			menu.addItem(item)
		}

		let anchor: NSView? = subprojectPill ?? capsule
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: (anchor?.bounds.maxY ?? 0) + Theme.current.scaled(4)),
			in: anchor
		)
	}

	@objc private func openSubprojectFromMenu(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL else { return }
		openSubproject(at: url)
	}

	@objc private func leaveSubprojectFromMenu() { leaveSubproject() }

	/// The run strip's commands, for when there is no room to draw it.
	private func runOverflowMenu() -> NSMenu {
		let menu = NSMenu()
		menu.addItem(menuItem("Run", #selector(runSelected(_:))))
		menu.addItem(menuItem("Debug", #selector(debugSelected(_:))))
		menu.addItem(menuItem("Stop", #selector(stopSelected(_:))))
		menu.addItem(.separator())

		for configuration in launchConfigurations {
			let item = NSMenuItem(
				title: configuration.name,
				action: #selector(configurationChosen(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = configuration.name
			item.state = configuration.name == selectedConfiguration?.name ? .on : .off
			menu.addItem(item)
		}
		return menu
	}

	fileprivate func showBranchMenu() {
		guard let project, let capsule else { return }
		capsule.menuHalf = .branch
		BranchMenu.show(relativeTo: capsule, anchorRect: capsule.branchRect, project: project)
	}
}

// MARK: - Small view helpers

/// A view that fills itself with a flat colour. Used instead of relying on
/// `NSBox` or vibrancy so the palette matches the theme exactly.
class ColoredView: NSView {
	/// Whether a double-click here means what one in a titlebar means.
	///
	/// The strip across the top of this window is a view of this app's, drawn
	/// where the titlebar would be — `fullSizeContentView` puts the content
	/// there. A view swallows a double-click, so the one gesture every macOS
	/// window has, and which people use without thinking, did nothing at all.
	var actsAsTitlebar = false

	private var color: NSColor

	/// What it is painted with, for anything swapping palettes.
	var colour: NSColor { color }

	/// Where the colour comes from, for views that follow the palette.
	///
	/// The colour itself is copied into a layer, so a theme change has to hand
	/// it over again — and only the view knows which colour it was.
	var colourSource: (() -> NSColor)? {
		didSet { refreshColour() }
	}

	/// Takes the colour again from whatever supplies it.
	func refreshColour() {
		guard let colourSource else { return }
		setColor(colourSource())
	}

	override func mouseDown(with event: NSEvent) {
		guard actsAsTitlebar, event.clickCount == 2 else {
			super.mouseDown(with: event)
			return
		}
		TitlebarDoubleClick.perform(on: window)
	}

	/// Repaints in another colour, for a strip that means something by it.
	func setColor(_ colour: NSColor) {
		guard colour != color else { return }
		color = colour
		layer?.backgroundColor = colour.cgColor
		needsDisplay = true
	}

	init(color: NSColor) {
		self.color = color
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = color.cgColor
	}

	/// Subclasses draw over their subviews, so drawing order matters to them.
	override var wantsDefaultClipping: Bool { true }

	required init?(coder: NSCoder) { fatalError("not used") }

	override func updateLayer() {
		layer?.backgroundColor = color.cgColor
	}
}

/// What a project's tmux session is called.
///
/// The folder's name, with anything tmux would object to replaced: a session
/// name cannot hold a colon or a full stop, and a project called `v1.2` would
/// otherwise fail to attach with a message about a window index.
enum TmuxSessionName {
	static func of(_ root: URL) -> String {
		let name = root.lastPathComponent
		let cleaned = name.map { character -> Character in
			character.isLetter || character.isNumber || character == "-" || character == "_"
				? character
				: "-"
		}
		let text = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
		return text.isEmpty ? "Abydos" : text
	}
}

/// Split view with a 1px themed divider instead of the system's.
final class ThinDividerSplitView: NSSplitView {
	override var dividerColor: NSColor { Theme.current.separator }
	override var dividerThickness: CGFloat { 1 }
}



/// Keeping the tree the width it was dragged to.
///
/// The constraint is what decides the width, and only dragging the divider
/// changes the constraint. Left to itself the split view re-divides the window
/// whenever what is in the editor changes shape — a page of controls, a wide
/// file — and the tree jumps for reasons that have nothing to do with the tree.
extension MainWindowController: NSSplitViewDelegate {
	/// Gives back the part of the panel that is not a whole row.
	///
	/// The grid is `floor(height / rowHeight)` rows, so whatever is left over
	/// is drawn as a strip of a row against the top of the viewport — a line
	/// cut through the middle rather than a line that is simply not shown. At
	/// 1× that strip is a point or two and nobody minds; scaling multiplies it
	/// along with everything else, and at 2× it is half a line.
	///
	/// So the panel is rounded down to whole rows and the divider sits where
	/// that leaves it, which is the trade this was decided on: the divider does
	/// not land exactly where it was dragged, and the terminal always looks
	/// like a terminal.
	///
	/// Runs after the split has resized rather than while it is being dragged,
	/// because a drag is not the only thing that changes the height — the
	/// window, the zoom and the font all do. It converges in one step: the
	/// second pass finds nothing left over and stops.
	func splitViewDidResizeSubviews(_ notification: Notification) {
		guard notification.object as? NSSplitView === verticalSplitView else { return }
		guard isPanelVisible, !isPanelMaximized, !bottomPanel.isHidden else { return }
		// Moving the divider resizes the subviews, which is this notification
		// again — and `setPosition` sends it synchronously, so without this the
		// second pass runs inside the first. It converges on the arithmetic
		// alone, but "converges" is not "terminates": the first version of this
		// took the app out with a stack overflow before the remainder ever
		// reached zero.
		guard !isSnappingPanel else { return }
		guard let remainder = bottomPanel.terminalHeightRemainder, remainder > 0.5 else { return }

		let total = verticalSplitView.bounds.height
		let wanted = bottomPanel.frame.height - remainder
		// Not below what the panel is allowed to be: a terminal four rows tall
		// is the floor everywhere else, and shaving a row off to make the
		// arithmetic tidy would be tidying the wrong thing.
		guard total > 200, wanted >= 160 else { return }

		isSnappingPanel = true
		// Next turn rather than inside the layout that is reporting to us:
		// setting a divider position from within a layout pass is how the
		// terminal came to be told two different sizes for one pane.
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.verticalSplitView.setPosition(total - wanted, ofDividerAt: 0)
			self.isSnappingPanel = false
		}
	}

	func splitView(
		_ splitView: NSSplitView,
		constrainSplitPosition proposedPosition: CGFloat,
		ofSubviewAt dividerIndex: Int
	) -> CGFloat {
		guard splitView === self.splitView, dividerIndex == 0 else { return proposedPosition }
		let width = max(140, min(proposedPosition, splitView.bounds.width - 260))
		navigatorWidthConstraint.constant = width
		navigatorWidth = width
		return width
	}
}

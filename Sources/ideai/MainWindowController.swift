import AppKit
import IdeaiKit

/// The project window: titlebar pills, the left tool strip, the navigator, and
/// the editor area.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
	private(set) var project: Project?

	/// What each project had open, so going back to one looks as it was left.
	private var sessions = ProjectSessions()
	/// Whether the window follows the terminal's working directory.
	private(set) var followsTerminal = false

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
		let fireLike = ProcessInfo.processInfo.environment["IDEAI_BENCH_FIRE"] != nil
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
	private var panelHeight: CGFloat = 260
	private var navigatorContainer: NSView!
	private var changesPane: ChangesPane?
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
	/// Held while open: the panel is a child window and nothing else owns it.
	private var configurationEditor: LaunchConfigurationEditor?
	/// What the run control acts on, remembered per project.
	private var selectedConfigurationName: String?
	private var projectPill: ProjectPillButton!
	private var branchPill: BranchPillButton!
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
	func notify(_ title: String, detail: String? = nil, kind: Toast.Kind = .error) {
		toasts.show(Toast(kind: kind, title: title, detail: detail))
	}

	/// Shows a toast raised from somewhere with no window of its own.
	///
	/// Only the key window, so a message does not appear three times on a
	/// machine with three of them open.
	@objc private func toastPosted(_ notification: Notification) {
		guard window?.isKeyWindow == true, let toast = notification.userInfo?["toast"] as? Toast else { return }
		toasts.show(toast)
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
		window.titlebarAppearsTransparent = false
		window.backgroundColor = Theme.current.windowBackground
		window.tabbingMode = .disallowed

		// Centred, then the autosaved frame restores over it if there is one.
		// Setting the autosave name first would let AppKit place the window at
		// the bottom-left default before any frame is restored, which is where
		// a second window with no saved frame of its own would land.
		window.center()
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

		// Preference changes apply live rather than on next launch.
		NotificationCenter.default.addObserver(
			forName: .ideaiSettingsChanged,
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
			self, selector: #selector(toastPosted(_:)), name: .ideaiToast, object: nil
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
		dockContainer = ColoredView(color: Theme.current.sidebarBackground)
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

		// The panel spans the full width below both the tree and the editor,
		// which is where IDEA puts its tool windows.
		verticalSplitView = ThinDividerSplitView()
		verticalSplitView.isVertical = false
		verticalSplitView.dividerStyle = .thin
		verticalSplitView.addArrangedSubview(splitView)
		verticalSplitView.addArrangedSubview(bottomPanel)
		verticalSplitView.autosaveName = "IdeaiPanelSplit"

		bottomPanel.onRequestHide = { [weak self] in self?.setPanelVisible(false) }
		bottomPanel.onToggleMaximize = { [weak self] in self?.togglePanelMaximized() }
		bottomPanel.onToggleFollowProject = { [weak self] in self?.toggleFollowTerminal() }
		bottomPanel.onWorkingDirectoryChanged = { [weak self] directory in
			self?.terminalDirectoryChanged(to: directory)
		}
		// A finding opens the file at its line, in the editor above the panel.
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
			self?.editor.open(fileURL: url, focusEditor: focusEditor, preview: !focusEditor)
		}
		navigator.onOpenTerminal = { [weak self] directory in
			self?.openTerminal(in: directory)
		}
		navigator.onPreviewModel = { url in
			MainWindowController.previewModel(at: url)
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
		editor.onEditBreakpoint = { [weak self] url, line in
			self?.editBreakpoint(file: url, line: line)
		}
		editor.onToggleBreakpoint = { [weak self] url, line in
			self?.toggleBreakpoint(file: url, line: line)
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
		projectPill?.invalidateIntrinsicContentSize()
		branchPill?.invalidateIntrinsicContentSize()
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

		navigator.setTopInset(inset)
		sidebarTopInset = inset
		if isPanelMaximized { bottomPanel.setTopInset(inset) }
		primaryToolTop?.constant = inset
		editor.setTopInset(inset)
		toolStrip.setTopInset(inset)
	}

	// MARK: - Loading

	func load(project: Project, focusTree: Bool = true) {
		self.project = project
		window?.title = project.name

		projectPill?.configure(
			name: project.name,
			colorIndex: RecentProjects.shared.entries.first { $0.path == project.root.path }?.colorIndex
		)
		branchPill?.setBranch(nil)
		layoutTitlebarPills()

		navigator.load(project: project)
		editor.setProject(project)
		// Started now rather than when a file of that language is first opened,
		// so asking for a symbol straight after opening a project works.
		LanguageService.shared.warmUp(project: project.root)
		selectedConfigurationName = nil
		refreshRunControl()
		scratchesPane?.setProject(project.root)
		bottomPanel.setWorkingDirectory(project.root)

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

		Task { @MainActor in
			await project.loadGit()
			let branch = await project.git?.currentBranch()
			self.branchPill?.setBranch(branch)
			// The branch pill only gets a width once it has a name to show.
			self.layoutTitlebarPills()
			self.navigator.refreshGitStatus()

			// Changes and branches are built around one repository and hold on
			// to it, so a different project needs them built again. Done here
			// rather than when the project is set, because until git has been
			// read there is no repository to build them around.
			if self.currentSidebarTool == .changes || self.currentSidebarTool == .branches {
				self.install(tool: self.currentSidebarTool, force: true)
			}
		}
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
			presentGoError("No processes to attach to.")
			return
		}

		let alert = NSAlert()
		alert.messageText = "Attach to a process"
		alert.informativeText = "The debugger stops it where it is."
		alert.addButton(withTitle: "Attach")
		alert.addButton(withTitle: "Cancel")

		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
		popup.addItems(withTitles: processes.map { "\($0.pid)  \($0.name)" })
		alert.accessoryView = popup

		let attach: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let chosen = processes[popup.indexOfSelectedItem]
			let adapter = DebugAdapters.adapter(
				forProgramAt: chosen.path,
				projectRoot: self.project?.root ?? URL(fileURLWithPath: chosen.path).deletingLastPathComponent()
			)
			guard let executable = DebugAdapters.executable(for: adapter) else {
				self.presentGoError("Could not find `\(adapter.command)`. \(adapter.installHint)")
				return
			}
			self.setPanelVisible(true)
			guard let session = self.bottomPanel.startDebugging(
				adapter: adapter,
				executable: executable,
				start: .attach(pid: chosen.pid),
				breakpoints: self.pendingBreakpoints
			) else { return }
			self.wire(session)
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: attach) } else { attach(alert.runModal()) }
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
		switch item.action {
		case #selector(debugContinue(_:)), #selector(debugPause(_:)),
		     #selector(debugStepOver(_:)), #selector(debugStepInto(_:)),
		     #selector(debugStepOut(_:)), #selector(debugStop(_:)):
			return debugSession?.isActive ?? false
		case #selector(newTerminalTab(_:)):
			return bottomPanel.hasKeyboardFocus
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
		let adapter = DebugAdapters.adapter(forProgramAt: path, projectRoot: project.root)
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
	@objc func togglePanelMaximized(_ sender: Any? = nil) {
		if isPanelMaximized {
			isPanelMaximized = false
			bottomPanel.isMaximized = false
			splitView.isHidden = false
			bottomPanel.setTopInset(0)
			verticalSplitView.adjustSubviews()
			let total = verticalSplitView.bounds.height
			let restored = heightBeforeMaximize ?? panelHeight
			if total > 200 { verticalSplitView.setPosition(total - restored, ofDividerAt: 0) }
			tellTerminalsTheySizeChanged()
			return
		}

		setPanelVisible(true)
		isPanelMaximized = true
		bottomPanel.isMaximized = true
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
		guard followsTerminal else { return }
		guard let root = ProjectRoot.find(from: directory) else { return }
		switchProject(to: root)
	}

	/// Swaps one project for another in place, keeping what each had open.
	func switchProject(to root: URL) {
		let root = root.standardizedFileURL
		guard root.path != project?.root.standardizedFileURL.path else { return }

		if let current = project?.root {
			sessions.store(editor.captureSession(), for: current)
		}

		load(project: Project(root: root), focusTree: false)
		RecentProjects.shared.record(url: root)

		// Whatever was open here before, or nothing if this is the first visit.
		if let previous = sessions.take(for: root) {
			editor.restore(previous)
		} else {
			editor.closeAllTabs()
			editor.restoreScratches()
		}
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

	private func toggleBreakpoint(file: URL, line: Int) {
		// The debugger reports files by their real path, so breakpoints are
		// keyed the same way or they are set against a name nothing else uses.
		let path = FilePath.canonical(file)

		if let session = bottomPanel.activeDebugSession {
			session.toggleBreakpoint(file: path, line: line)
			syncBreakpointsToEditor(from: session)
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
	}

	/// Draws the breakpoints that exist before anything is running.
	private func publishPendingBreakpoints() {
		var mapped: [String: [Int: Bool]] = [:]
		var conditional: [String: Set<Int>] = [:]
		for (file, list) in pendingBreakpoints {
			mapped[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, $0.isVerified) })
			conditional[file] = Set(list.filter(\.isConditional).map(\.line))
		}
		editor.setBreakpoints(mapped)
		editor.setConditionalBreakpoints(conditional)
	}

	private func syncBreakpointsToEditor(from session: DebugSession) {
		var mapped: [String: [Int: Bool]] = [:]
		var conditional: [String: Set<Int>] = [:]
		for (file, list) in session.breakpoints {
			mapped[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, $0.isVerified) })
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

		let alert = NSAlert()
		alert.messageText = "Breakpoint on line \(line)"
		alert.informativeText = "Leave a field empty to drop that part."
		alert.addButton(withTitle: "Apply")
		alert.addButton(withTitle: "Cancel")

		let width: CGFloat = 320
		let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 96))

		func field(_ placeholder: String, _ value: String?, y: CGFloat) -> NSTextField {
			let label = NSTextField(labelWithString: placeholder)
			label.font = .systemFont(ofSize: 10)
			label.textColor = .secondaryLabelColor
			label.frame = NSRect(x: 0, y: y + 20, width: width, height: 14)
			container.addSubview(label)

			let input = NSTextField(frame: NSRect(x: 0, y: y, width: width, height: 22))
			input.stringValue = value ?? ""
			container.addSubview(input)
			return input
		}

		let logInput = field("Log this and carry on, e.g. i is {i}", existing.logMessage, y: 0)
		let hitInput = field("Stop after this many hits, e.g. > 5", existing.hitCondition, y: 36)
		let conditionInput = field("Stop only when true, e.g. i > 5", existing.condition, y: 72)
		alert.accessoryView = container

		let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			self.setBreakpointOptions(
				file: path,
				line: line,
				condition: conditionInput.stringValue,
				hitCondition: hitInput.stringValue,
				logMessage: logInput.stringValue
			)
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: apply) } else { apply(alert.runModal()) }
	}

	private enum GoAction { case run, build, test, trace, profile, debug }

	private func runGo(_ action: GoAction) {
		guard let project else { return }
		// The module need not be at the project root — a Go repository commonly
		// keeps go.mod in a subdirectory — so the modules found by discovery
		// decide where these commands run.
		guard let moduleRoot = chooseModuleRoot(in: project.root) else { return }
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
			workingDirectory: moduleRoot
		)
	}

	/// Starts the native debugger and wires its state to the editor.
	private func startNativeDebugger(delve: String, package: String) {
		setPanelVisible(true)
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
			if matching.count > 1 {
				if index > 0 { menu.addItem(.separator()) }
				let header = NSMenuItem(title: configuration.name, action: nil, keyEquivalent: "")
				header.isEnabled = false
				menu.addItem(header)
			}

			let runItem = NSMenuItem(
				title: matching.count > 1 ? "Run" : "Run \(configuration.name)",
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
					title: matching.count > 1 ? "Debug" : "Debug \(configuration.name)",
					action: #selector(debugMenuItem(_:)),
					keyEquivalent: ""
				)
				debugItem.target = self
				debugItem.representedObject = configuration.id
				menu.addItem(debugItem)
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
		setPanelVisible(true)
		bottomPanel.runCommand(
			title: configuration.name,
			command: configuration.commandLine,
			directory: URL(fileURLWithPath: configuration.workingDirectory),
			environment: configuration.environment
		)
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

	private func title(for source: RunConfiguration.Source) -> String {
		switch source {
		case .intelliJ: return "IntelliJ"
		case .vscode:   return "VS Code"
		case .make:     return "Make"
		case .goModule: return "Go"
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

		if let missing = status.missing.first {
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
		guard let project else { return [] }
		return LaunchFile.read(in: project.root)
	}

	private var selectedConfiguration: LaunchConfiguration? {
		let all = launchConfigurations
		if let name = selectedConfigurationName, let found = all.first(where: { $0.name == name }) {
			return found
		}
		return all.first
	}

	func refreshRunControl() {
		runControl?.setConfiguration(selectedConfiguration?.name)
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
		if let pane = runningPane {
			runningPane = nil
			pane.terminalView.terminateProcess()
			runControl?.setStatus("Stopped")
			return
		}
		debugStop(nil)
	}

	func showDebugConsoleForTesting() {
		bottomPanel.showDebugConsoleForTesting()
	}

	func echoDebugOutputForTesting() {
		bottomPanel.debugOutput = { text in
			FileHandle.standardError.write(Data("[debug] \(text)".utf8))
		}
	}

	func showConfigurationMenuForTesting() {
		guard let control = runControl else { return }
		showConfigurationMenu(at: NSPoint(x: 0, y: control.bounds.height), in: control)
	}

	/// Opens the editor on the selected configuration, making one if there is
	/// none yet — what pressing play would have done first.
	func editConfigurationForTesting() {
		guard let configuration = selectedConfiguration ?? createSuggestedConfiguration() else { return }
		selectedConfigurationName = configuration.name
		refreshRunControl()
		presentConfigurationEditor(configuration, isNew: false)
	}

	@objc func runSelected(_ sender: Any?) { runSelectedConfiguration(debug: false) }
	@objc func debugSelected(_ sender: Any?) { runSelectedConfiguration(debug: true) }

	private func runSelectedConfiguration(debug: Bool) {
		guard let project else { return }

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
			debugConfiguration(configuration, in: project.root)
		} else {
			runConfiguration(configuration, in: project.root)
		}
	}

	/// Writes a configuration for a project that has none, and says so.
	private func createSuggestedConfiguration() -> LaunchConfiguration? {
		guard let project, let suggestion = LaunchFile.suggestion(for: project.root) else { return nil }
		do {
			_ = try LaunchFile.save(suggestion, in: project.root)
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

	private func runConfiguration(_ configuration: LaunchConfiguration, in root: URL) {
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
			environment: configuration.expandedEnvironment(root: root)
		)
		runningPane = pane
		// The shell reports what the program exited with, which is the one thing
		// worth saying in the titlebar once it is over.
		pane?.terminalView.onProcessExit = { [weak self, weak pane] code in
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

	/// A word the shell will pass through as it was written.
	private static func shellQuoted(_ word: String) -> String {
		guard word.contains(where: { !$0.isLetter && !$0.isNumber && !"-_./=:@".contains($0) })
		else { return word }
		return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}

	private func debugConfiguration(_ configuration: LaunchConfiguration, in root: URL) {
		let adapter = DebugAdapters.adapter(id: configuration.adapterID) ?? DebugAdapters.lldb
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
				environment: configuration.expandedEnvironment(root: root)
			),
			breakpoints: pendingBreakpoints
		) else { return }
		wire(session)
	}

	/// The list of configurations, and the ways to change them.
	private func showConfigurationMenu(at point: NSPoint, in view: NSView) {
		let menu = NSMenu()
		let all = launchConfigurations

		for configuration in all {
			let item = NSMenuItem(
				title: configuration.name, action: #selector(configurationChosen(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = configuration.name
			item.state = configuration.name == selectedConfiguration?.name ? .on : .off
			menu.addItem(item)
		}
		if all.isEmpty {
			let empty = NSMenuItem(title: "No configurations yet", action: nil, keyEquivalent: "")
			empty.isEnabled = false
			menu.addItem(empty)
		}

		menu.addItem(.separator())
		let edit = NSMenuItem(
			title: "Edit\u{2026}", action: #selector(editSelectedConfiguration), keyEquivalent: ""
		)
		edit.target = self
		edit.isEnabled = selectedConfiguration != nil
		menu.addItem(edit)

		let add = NSMenuItem(title: "New\u{2026}", action: #selector(addConfiguration), keyEquivalent: "")
		add.target = self
		menu.addItem(add)

		let reveal = NSMenuItem(
			title: "Open launch.json", action: #selector(openLaunchFile), keyEquivalent: ""
		)
		reveal.target = self
		menu.addItem(reveal)

		menu.popUp(positioning: nil, at: point, in: view)
	}

	@objc private func configurationChosen(_ sender: NSMenuItem) {
		selectedConfigurationName = sender.representedObject as? String
		refreshRunControl()
	}

	@objc private func openLaunchFile() {
		guard let project else { return }
		let file = LaunchFile.url(in: project.root)
		guard FileManager.default.fileExists(atPath: file.path) else {
			notify("No launch.json yet", detail: "Press run once and one will be written.", kind: .information)
			return
		}
		editor.open(fileURL: file, focusEditor: true)
	}

	@objc private func addConfiguration() {
		guard let project else { return }
		let suggestion = LaunchFile.suggestion(for: project.root)
			?? LaunchConfiguration(name: project.name, type: "lldb", program: "${workspaceFolder}")
		presentConfigurationEditor(suggestion, isNew: true)
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
		guard let project else { return }

		let editor = LaunchConfigurationEditor(configuration: configuration, isNew: isNew)
		configurationEditor = editor
		editor.onApply = { [weak self] updated in
			guard let self else { return }
			self.configurationEditor = nil

			guard let updated else {
				_ = try? LaunchFile.remove(named: configuration.name, in: project.root)
				self.selectedConfigurationName = nil
				self.refreshRunControl()
				return
			}
			do {
				// Renaming replaces rather than duplicating.
				if updated.name != configuration.name, !isNew {
					_ = try LaunchFile.remove(named: configuration.name, in: project.root)
				}
				_ = try LaunchFile.save(updated, in: project.root)
				self.selectedConfigurationName = updated.name
				self.refreshRunControl()
			} catch {
				self.notify("Could not write launch.json", detail: error.localizedDescription)
			}
		}
		editor.show(over: window)
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
		let isCollapsed = navigatorContainer.isHidden

		if !isCollapsed, tool == currentSidebarTool {
			toggleNavigator(nil)
			return
		}

		install(tool: tool)
		if isCollapsed { toggleNavigator(nil) }
		updateSidebarSelection()
	}

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
	private func install(tool: SidebarToolKind, force: Bool = false) {
		guard force || currentSidebarTool != tool || primaryToolView == nil else { return }

		primaryToolView?.removeFromSuperview()
		primaryToolView = nil
		primaryToolTop = nil
		changesPane = nil
		structurePane = nil
		scratchesPane = nil
		historyPane = nil
		navigator.view.removeFromSuperview()

		currentSidebarTool = tool
		let view: NSView

		switch tool {
		case .project:
			view = navigator.view
		case .changes:
			guard let project, project.git != nil else { return }
			let pane = ChangesPane(root: project.root)
			pane.onSelectChange = { [weak self] change in self?.showDiff(for: change) }
			pane.onWorkingCopyChanged = { [weak self] in self?.navigator.refreshGitStatus() }
			changesPane = pane
			view = pane
		case .branches:
			guard let project, project.git != nil else { return }
			let pane = BranchesPane(root: project.root)
			// A worktree is a project in its own right, so opening one is
			// switching to it rather than checking anything out.
			pane.onOpenWorktree = { [weak self] path in
				self?.switchProject(to: path)
			}
			pane.onRepositoryChanged = { [weak self] in
				guard let self else { return }
				self.navigator.refreshGitStatus()
				// The titlebar shows the branch, so a checkout has to reach it.
				Task { @MainActor in
					let branch = await self.project?.git?.currentBranch()
					self.branchPill?.setBranch(branch)
					self.layoutTitlebarPills()
				}
			}
			view = pane
		case .history:
			guard let project, project.git != nil else { return }
			let pane = HistoryPane(root: project.root)
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

		primaryToolView = view
		primaryToolTop = tool == .project ? nil : top
		updateTopInsets()
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
	func toggleBreakpointForTesting(line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		toggleBreakpoint(file: url, line: line)
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

	@objc func toggleNavigator(_ sender: Any?) {
		guard let navigatorContainer else { return }
		let collapsed = splitView.isSubviewCollapsed(navigatorContainer)
		if collapsed {
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

	@objc func showProjectSwitcher(_ sender: Any?) {
		guard let pill = projectPill else { return }
		ProjectSwitcherPopover.show(relativeTo: pill, currentProject: project)
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
		bottomPanel.shutdown()
		editor.windowWillClose()
		navigator.windowWillClose()
		onClose?()
	}
}

// MARK: - Toolbar items

extension MainWindowController: NSToolbarDelegate {
	private static let projectItem = NSToolbarItem.Identifier("ideai.project")
	private static let branchItem = NSToolbarItem.Identifier("ideai.branch")
	private static let runItem = NSToolbarItem.Identifier("ideai.run")

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[Self.projectItem, Self.branchItem, .flexibleSpace, Self.runItem]
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
		case Self.projectItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = ProjectPillButton()
			pill.onClick = { [weak self] in self?.showProjectSwitcher(nil) }
			if let project {
				pill.configure(
					name: project.name,
					colorIndex: RecentProjects.shared.entries.first { $0.path == project.root.path }?.colorIndex
				)
			}
			projectPill = pill
			item.view = pill
			return item

		case Self.runItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let control = RunControl()
			control.onRun = { [weak self] in self?.runSelectedConfiguration(debug: false) }
			control.onDebug = { [weak self] in self?.runSelectedConfiguration(debug: true) }
			control.onStop = { [weak self] in self?.stopRunning() }
			control.onChooseConfiguration = { [weak self] point in
				self?.showConfigurationMenu(at: point, in: control)
			}
			runControl = control
			item.view = control
			refreshRunControl()
			return item

		case Self.branchItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = BranchPillButton()
			pill.onClick = { [weak self] in self?.showBranchMenu() }
			branchPill = pill
			item.view = pill
			return item

		default:
			return nil
		}
	}

	fileprivate func showBranchMenu() {
		guard let project, let branchPill else { return }
		BranchMenu.show(relativeTo: branchPill, project: project)
	}
}

// MARK: - Small view helpers

/// A view that fills itself with a flat colour. Used instead of relying on
/// `NSBox` or vibrancy so the palette matches the theme exactly.
class ColoredView: NSView {
	private let color: NSColor

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

/// Split view with a 1px themed divider instead of the system's.
final class ThinDividerSplitView: NSSplitView {
	override var dividerColor: NSColor { Theme.current.separator }
	override var dividerThickness: CGFloat { 1 }
}


import AppKit
import IdeaiKit

/// The project window: titlebar pills, the left tool strip, the navigator, and
/// the editor area.
final class MainWindowController: NSWindowController, NSWindowDelegate {
	private(set) var project: Project?

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

	/// Times a full terminal redraw, which is what every byte of output costs
	/// once the screen has to be shown again.
	func benchmarkTerminalRendering() {
		setPanelVisible(true)
		guard let terminal = bottomPanel.showTerminal()?.terminalView else {
			print("BENCH render: no terminal")
			return
		}

		// A screenful of coloured text, as a busy program produces.
		var filler = ""
		for row in 0..<40 {
			filler += "\u{1B}[3\(row % 8)m"
			filler += String(repeating: "abcdefghij ", count: 18)
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

		let frames = 60
		let start = Date()
		for _ in 0..<frames { terminal.cacheDisplay(in: bounds, to: rep) }
		let elapsed = -start.timeIntervalSinceNow

		let perFrame = elapsed / Double(frames) * 1000
		print("BENCH render: \(String(format: "%.2f", perFrame)) ms/frame "
			+ "(\(String(format: "%.0f", 1000 / perFrame)) fps ceiling) at \(Int(bounds.width))x\(Int(bounds.height))")

		// What a printed line actually costs now that only what changed is
		// painted: one row rather than the whole screen.
		let rowHeightPoints = bounds.height / 40
		let rowRect = NSRect(x: 0, y: 0, width: bounds.width, height: rowHeightPoints)
		guard let rowRep = terminal.bitmapImageRepForCachingDisplay(in: rowRect) else { return }
		terminal.cacheDisplay(in: rowRect, to: rowRep)

		let rowStart = Date()
		for _ in 0..<frames { terminal.cacheDisplay(in: rowRect, to: rowRep) }
		let rowElapsed = -rowStart.timeIntervalSinceNow
		let perRow = rowElapsed / Double(frames) * 1000
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
	private var primaryToolView: NSView?
	private var primaryToolTop: NSLayoutConstraint?
	private var primaryContainer: NSView!
	private(set) var currentSidebarTool: SidebarToolKind = .project
	/// Height the titlebar covers, applied to sidebar panes that do not inset
	/// themselves.
	private var sidebarTopInset: CGFloat = 0
	private var projectPill: ProjectPillButton!
	private var branchPill: BranchPillButton!
	private var titlebarContainer: NSView?
	private var toolStripWidthConstraint: NSLayoutConstraint!

	private var navigatorWidth: CGFloat = 260

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

		navigatorContainer = ColoredView(color: Theme.current.sidebarBackground)
		primaryContainer = navigatorContainer

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
			guard let url else { return }
			self?.navigator.selectWithoutOpening(url: url)
		}
		// Clicking the breakpoint gutter reaches the running debug session, and
		// is remembered even when nothing is running yet.
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
		primaryToolTop?.constant = inset
		editor.setTopInset(inset)
		toolStrip.setTopInset(inset)
	}

	// MARK: - Loading

	func load(project: Project) {
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
		bottomPanel.setWorkingDirectory(project.root)

		// Deferred: the titlebar has no measurable height until the window has
		// laid out at least once.
		DispatchQueue.main.async { [weak self] in
			self?.updateTopInsets()
			// The tree takes focus on open, so arrow keys work without clicking.
			self?.navigator.focusTree()
		}

		Task { @MainActor in
			await project.loadGit()
			let branch = await project.git?.currentBranch()
			self.branchPill?.setBranch(branch)
			// The branch pill only gets a width once it has a name to show.
			self.layoutTitlebarPills()
			self.navigator.refreshGitStatus()
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
	private var pendingBreakpoints: [String: [Int: Bool]] = [:]

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
		var lines = pendingBreakpoints[path] ?? [:]
		if lines.removeValue(forKey: line) == nil { lines[line] = false }
		pendingBreakpoints[path] = lines.isEmpty ? nil : lines
		editor.setBreakpoints(pendingBreakpoints)
	}

	private func syncBreakpointsToEditor(from session: DebugSession) {
		var mapped: [String: [Int: Bool]] = [:]
		for (file, list) in session.breakpoints {
			mapped[file] = Dictionary(uniqueKeysWithValues: list.map { ($0.line, $0.isVerified) })
		}
		pendingBreakpoints = mapped
		editor.setBreakpoints(mapped)
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

		session.onBreakpointsChanged = { [weak self, weak session] in
			guard let self, let session else { return }
			self.syncBreakpointsToEditor(from: session)
		}
		session.onStoppedAt = { [weak self] file, line in
			guard let self else { return }
			self.editor.open(fileURL: URL(fileURLWithPath: file), atLine: line)
			self.editor.setExecutionLocation(file: file, line: line)
		}
		session.onStateChange = { [weak self] state in
			// The marker must go when execution resumes or the process ends.
			switch state {
			case .running, .terminated, .idle:
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
		let alert = NSAlert()
		alert.messageText = "Cannot run this Go command"
		alert.informativeText = message
		alert.runModal()
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
		let alert = NSAlert()
		alert.messageText = "Nothing to run here"
		alert.informativeText = """
		No run configuration was found for \(url.lastPathComponent):\(line). 		This is a bug — the marker is drawn from the same list.
		"""
		if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
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
			let alert = NSAlert()
			alert.messageText = "Delve is not installed"
			alert.informativeText = "Install it with: go install github.com/go-delve/delve/cmd/dlv@latest"
			if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
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
			let alert = NSAlert()
			alert.messageText = "Nothing to run"
			alert.informativeText = "No run configurations, makefiles or Go entry points were found in this project."
			if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
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
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		guard let window else {
			alert.runModal()
			return
		}
		alert.beginSheetModal(for: window)
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
	private func install(tool: SidebarToolKind) {
		guard currentSidebarTool != tool || primaryToolView == nil else { return }

		primaryToolView?.removeFromSuperview()
		primaryToolView = nil
		primaryToolTop = nil
		changesPane = nil
		structurePane = nil
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
			let alert = NSAlert()
			alert.messageText = "git reported a problem"
			alert.informativeText = (result.stderr.isEmpty ? result.stdout : result.stderr)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
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

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[Self.projectItem, Self.branchItem, .flexibleSpace]
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


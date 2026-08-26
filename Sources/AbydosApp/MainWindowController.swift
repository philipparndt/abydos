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
	private let bottomPanel = BottomPanel()

	/// The left rail and the tools it opens.
	///
	/// Not an `NSViewController`: the rail is a subview of the window's root and
	/// the tool it opens lives inside `navigatorContainer`, so there is no one
	/// view for it to control. The window builds the hierarchy and hands it the
	/// two pieces; it owns which tool is showing and every pane behind that.
	private lazy var sidebar: SidebarController = {
		let bar = SidebarController(editor: editor, navigator: navigator)
		bar.project = { [weak self] in self?.project }
		bar.hostWindow = { [weak self] in self?.window }
		bar.gitCommandRoot = { [weak self] in self?.gitCommandRoot }
		bar.relativePathOfActiveFile = { [weak self] in self?.relativePathOfActiveFile() }
		bar.symbols = { [weak self] query, scope in
			await self?.symbols(matching: query, scope: scope) ?? []
		}
		bar.notify = { [weak self] title, detail in self?.notify(title, detail: detail) }
		bar.isNavigatorVisible = { [weak self] in
			guard let self, let container = self.navigatorContainer else { return false }
			return !container.isHidden
				&& !self.splitView.isSubviewCollapsed(container)
				&& container.frame.width >= 2
		}
		bar.showNavigator = { [weak self] in self?.openNavigator() }
		bar.hideNavigator = { [weak self] in self?.toggleNavigator(nil) }
		bar.isPanelMaximized = { [weak self] in self?.isPanelMaximized ?? false }
		bar.leaveMaximised = { [weak self] in self?.togglePanelMaximized(nil) }
		bar.leaveTerminalFullScreen = { [weak self] in self?.leaveTerminalFullScreen() }
		bar.onInsetsChanged = { [weak self] in self?.updateTopInsets() }
		bar.isPanelVisible = { [weak self] in self?.isPanelVisible ?? false }
		bar.readGit = { [weak self] in self?.readGit() }
		bar.openProject = { [weak self] url in
			guard let self else { return }
			(NSApp.delegate as? AppDelegate)?.open(projectAt: url, from: self)
		}
		return bar
	}()

	var sidebarForTesting: SidebarController { sidebar }

	/// Breakpoints and the stopped line, which outlive any one session.
	lazy var debug: DebugCoordinator = {
		let coordinator = DebugCoordinator(editor: editor, panel: bottomPanel)
		coordinator.debugSession = { [weak self] in self?.bottomPanel.activeDebugSession }
		coordinator.hostWindow = { [weak self] in self?.window }
		coordinator.onRememberBreakpoints = { [weak self] in self?.rememberBreakpoints() }
		coordinator.onDebugContinue = { [weak self] in self?.debugContinue($0) }
		coordinator.onDebugStepOver = { [weak self] in self?.debugStepOver($0) }
		coordinator.onDebugStepInto = { [weak self] in self?.debugStepInto($0) }
		coordinator.onDebugStepOut = { [weak self] in self?.debugStepOut($0) }
		coordinator.onWatchFromEditor = { [weak self] expression in self?.watchFromEditor(expression) }
		return coordinator
	}()

	private var debugSession: DebugSession? { bottomPanel.activeDebugSession }

	var debugForTesting: DebugCoordinator { debug }

	/// Running a program, wherever it runs.
	private lazy var run: RunCoordinator = {
		let coordinator = RunCoordinator(panel: bottomPanel, editor: editor)
		coordinator.currentProject = { [weak self] in self?.project }
		coordinator.currentLaunchRoot = { [weak self] in self?.launchRoot ?? URL(fileURLWithPath: ".") }
		coordinator.debugCoordinator = { [weak self] in self?.debug }
		coordinator.hostWindow = { [weak self] in self?.window }
		coordinator.onSetPanelVisible = { [weak self] visible in self?.setPanelVisible(visible) }
		coordinator.onNotify = { [weak self] title, detail, kind, actionTitle, action in
			self?.notify(title, detail: detail, kind: kind, actionTitle: actionTitle, action: action)
		}
		coordinator.onWire = { [weak self] session in self?.wire(session) }
		coordinator.onRememberOpenEditors = { [weak self] in self?.rememberOpenEditors() }
		coordinator.onLeaveTerminalFullScreen = { [weak self] in self?.leaveTerminalFullScreen() }
		coordinator.onAttachToProcess = { [weak self] sender in self?.attachToProcess(sender) }
		coordinator.onMenuItem = { [weak self] title, action in
			self?.menuItem(title, action) ?? NSMenuItem(title: title, action: action, keyEquivalent: "")
		}
		coordinator.onRunSelected = { [weak self] sender in self?.runSelected(sender) }
		coordinator.onDebugSelected = { [weak self] sender in self?.debugSelected(sender) }
		coordinator.onStopSelected = { [weak self] sender in self?.stopSelected(sender) }
		coordinator.onShowConfigurationMenu = { [weak self] rect, control in
			self?.showConfigurationMenu(from: rect, in: control)
		}
		return coordinator
	}()

	var runForTesting: RunCoordinator { run }

	// Menu-bar selectors, which AppKit resolves against the responder chain and
	// finds here rather than on the coordinator.
	@objc func showRunConfigurations(_ sender: Any?) { run.showRunConfigurations(sender) }
	@objc func newFromMakeGoal(_ sender: Any?) { run.newFromMakeGoal(sender) }
	@objc func debugStop(_ sender: Any?) { run.debugStop(sender) }

	/// The run strip in the titlebar.
	///
	/// Built here rather than by `TitlebarController`: it sits in that toolbar
	/// and every button on it is about running, which is this class's until
	/// there is a run coordinator to take it.
	func makeRunToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
		let item = NSToolbarItem(itemIdentifier: identifier)
		let control = RunControl()
		control.onRun = { [weak self] in self?.run.runSelectedConfiguration(debug: false) }
		control.onDebug = { [weak self] in self?.run.runSelectedConfiguration(debug: true) }
		control.onStop = { [weak self] in self?.run.stopRunning() }
		control.onProfile = { [weak self] in self?.run.profileSelectedConfiguration() }
		control.onCoverage = { [weak self] in self?.run.runSelectedWithCoverage() }
		control.onChooseConfiguration = { [weak self, weak control] rect in
			guard let control else { return }
			self?.showConfigurationMenu(from: rect, in: control)
		}
		control.onRunStateChanged = { [weak self] state in
			self?.titlebar.setRunState(state)
		}
		run.runControl = control
		item.view = control
		run.refreshRunControl()

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
	}

	/// The list of configurations, and the ways to change them.
	///
	/// **A popover rather than the flat menu it used to be.** The menu printed
	/// goals × modules: a reactor of a hundred modules offering three goals came
	/// to three hundred rows, two hundred and ninety-seven of them saying the
	/// same three words, running off the bottom of the screen and under a scroll
	/// arrow — and an `NSMenu` cannot be typed at, so there was nothing to do
	/// but scroll it. `RunPicker` names each goal once and treats the module as
	/// the second choice it is; this is the same popover the project pill and
	/// the branch pill use, so the filtering and the keys are the ones already
	/// there.
	func showConfigurationMenu(from rect: NSRect, in control: RunControl) {
		ProjectSwitcherPopover.show(
			relativeTo: control,
			anchorRect: rect,
			currentProject: project,
			owner: self,
			focus: .runs,
			runs: run.runList()
		)
	}

	func runOverflowMenu() -> NSMenu {
		let menu = NSMenu()
		menu.addItem(menuItem("Run", #selector(runSelected(_:))))
		menu.addItem(menuItem("Debug", #selector(debugSelected(_:))))
		menu.addItem(menuItem("Stop", #selector(stopSelected(_:))))
		menu.addItem(.separator())

		for configuration in run.launchConfigurations {
			let item = NSMenuItem(
				title: configuration.name,
				action: #selector(RunCoordinator.configurationChosen(_:)),
				keyEquivalent: ""
			)
			item.target = run
			item.representedObject = configuration.name
			item.state = configuration.name == run.selectedConfiguration?.name ? .on : .off
			menu.addItem(item)
		}
		return menu
	}

	// Menu-bar items find their target through the responder chain, and this
	// class is on it while `SidebarController` is not. So the actions stay
	// here, one line each, and the work is the sidebar's.
	@objc func showLogPage(_ sender: Any?) { sidebar.showLogPage(scopedTo: nil) }
	@objc func showCommitPage(_ sender: Any?) { sidebar.showCommitPage(carrying: nil) }

	/// Flips how the git page arranges a commit's files, and ticks itself.
	@objc func toggleCommitFilesByFolder(_ sender: Any?) {
		Settings.shared.commitFilesByFolder.toggle()
		sidebar.logPage?.applyFileArrangement()
		(sender as? NSMenuItem)?.state = Settings.shared.commitFilesByFolder ? .on : .off
	}
	private var toolStrip: ToolWindowBar { sidebar.rail }

	/// The strip across the top: the capsule, the pills, the backdrop and the
	/// seam, and the toolbar's delegate.
	///
	/// It owns those views and what they say; what pressing one *means* stays
	/// here, and arrives there as a closure. The run item is the exception — it
	/// sits in that toolbar and belongs to running, so this builds it and hands
	/// it over until there is a run coordinator to do so.
	private lazy var titlebar: TitlebarController = {
		let bar = TitlebarController(window: window)
		bar.project = { [weak self] in self?.project }
		bar.subprojectRoot = { [weak self] in self?.subprojectRoot }
		bar.branchRead = { [weak self] in self?.branchRead }
		bar.devContainerRoot = { [weak self] in self?.devContainerRoot }
		bar.devContainerChoices = { [weak self] in self?.devContainerChoices ?? [] }
		bar.choiceCarriedBy = { [weak self] sender in self?.choice(carriedBy: sender) }
		bar.scopeRoot = { [weak self] in self?.scopeRoot }
		bar.containerName = { choice, root in Self.containerName(for: choice, in: root) }
		bar.containerMark = Self.containerMark
		bar.containerTerminalTitle = Self.containerTerminalTitle
		bar.containerMenuItem = { [weak self] choice in
			self?.makeContainerMenuItem(for: choice) ?? NSMenuItem()
		}
		bar.makeRunItem = { [weak self] identifier in self?.makeRunToolbarItem(identifier) }
		bar.relayoutRunControl = { [weak self] in
			self?.run.runControl?.invalidateIntrinsicContentSize()
			self?.run.runControl?.applyThemeChange()
		}
		bar.onProjectPressed = { [weak self] in self?.showProjectSwitcher(nil) }
		bar.onBranchPressed = { [weak self] in self?.showBranchMenu() }
		bar.onLeaveSubproject = { [weak self] in self?.leaveSubproject() }
		bar.onOpenSubproject = { [weak self] url in self?.openSubproject(at: url) }
		bar.onOpenWorktree = { [weak self] url in
			guard let self else { return }
			(NSApp.delegate as? AppDelegate)?.open(projectAt: url, from: self)
		}
		bar.onShowAllWorktrees = { [weak self] in self?.toggleBranchesView(nil) }
		bar.onOpenFile = { [weak self] url in self?.openFile(at: url) }
		return bar
	}()

	var titlebarForTesting: TitlebarController { titlebar }

	/// Where an answer to a question about the code is shown, and where it moves.
	///
	/// Wired rather than owned: it is handed the two views it presents into and
	/// the handful of things only the window knows, and it holds no reference
	/// back. `dockInSidebar` and `undockFromSidebar` are lent from here because
	/// the lower half of the sidebar is the sidebar's, not a results list's.
	private lazy var results: ResultsPresenter = {
		let presenter = ResultsPresenter(editor: editor, panel: bottomPanel)
		presenter.hostWindow = { [weak self] in self?.window }
		presenter.scopeRoot = { [weak self] in self?.project?.scopeRoot }
		presenter.showPanel = { [weak self] in self?.setPanelVisible(true) }
		// These two used to be the window's, lent to the presenter because there
		// was nowhere else for them. There is now.
		presenter.dockInSidebar = { [weak self] pane, focusList in
			self?.sidebar.dockInSidebar(pane, focusList: focusList)
		}
		presenter.undockFromSidebar = { [weak self] pane in self?.sidebar.undockFromSidebar(pane) }
		presenter.sidebarDockHost = { [weak self] in self?.sidebar.dockHost }
		presenter.askUsagesAgain = { [weak self] url, line, character in
			self?.findUsages(in: url, line: line, character: character)
		}
		presenter.symbolsMatching = { [weak self] query, scope in
			await self?.symbols(matching: query, scope: scope) ?? []
		}
		presenter.reasonForNoSymbols = { [weak self] query, scope in
			self?.reasonForNoSymbols(query: query, scope: scope) ?? ""
		}
		return presenter
	}()

	private var splitView: NSSplitView!
	private var verticalSplitView: NSSplitView!
	/// How wide the tree is, kept as a constraint so nothing else decides.
	private var navigatorWidthConstraint: NSLayoutConstraint!
	private var panelHeight: CGFloat = 260
	/// True while the panel is being rounded to whole rows, so the resize that
	/// causes cannot ask for another one.
	fileprivate var isSnappingPanel = false
	private var navigatorContainer: ColoredView!
	/// Painted behind the toolbar, since the titlebar itself is transparent.
	/// Everywhere the editor has been, and where in it we are.
	private var navigation = NavigationHistory()
	/// Set while going back or forward, so retracing steps is not itself a step.
	private var isNavigatingHistory = false

	/// Watches `.git` so a commit made in a terminal shows up here.
	private var repositoryWatcher: RepositoryWatcher?

	/// Reading the repository, as a job rather than an answer.
	///
	/// The toolbar builds its items when it chooses, and in a repository small
	/// enough git answers first — so a pill that is only ever *told* the branch
	/// misses it. Anything that needs the branch awaits this instead, whenever
	/// it happens to come into existence.
	/// The whole of HEAD and not just its name: a branch with nothing committed
	/// on it is drawn differently, and the capsule cannot tell from a string.
	private var branchRead: Task<GitRepository.Head?, Never>?
	private var toolStripWidthConstraint: NSLayoutConstraint!

	private var navigatorWidth: CGFloat = 260

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

	/// Which panes the window is giving its room to.
	///
	/// The one thing a screenshot of a maximised editor cannot settle: an editor
	/// filling the window looks the same whether the tree is hidden or merely
	/// dragged to nothing, and "the panel is down" and "the panel is up behind
	/// the editor" are the same picture.
	var windowLayoutReportForTesting: String {
		let navigator = (navigatorContainer?.isHidden ?? true)
			|| (navigatorContainer?.frame.width ?? 0) < 2
			? "hidden" : "\(Int(navigatorContainer?.frame.width ?? 0))pt"
		return "navigator=\(navigator) "
			+ "panel=\(bottomPanel.isHidden ? "hidden" : "\(Int(bottomPanel.frame.height))pt") "
			+ "editorMaximized=\(isEditorMaximized) "
			+ "panelMaximized=\(isPanelMaximized)"
	}

	/// Double-clicks a tab, and says what the window looks like afterwards.
	func doubleClickTabForTesting(_ index: Int) -> String {
		let took = editor.doubleClickTabForTesting(index: index)
		return "\(took) — \(windowLayoutReportForTesting)"
	}

	/// Shuts the panel, for `--close-panel`.
	func closePanelForTesting() {
		setPanelVisible(false)
	}

	/// Tells the rail which panes are in front.
	///
	/// The same shape as the `setSidebarSelection` call beside it, which is the
	/// point: both groups of the rail now answer one question in one way.

	// MARK: - Remembered layout

	/// What AppKit files this window's frame and dividers under.
	///
	/// Renamed with the app, and **carried across rather than simply renamed**:
	/// these are the only `ideai` names that held something a person would miss.
	/// A rename on its own puts the window back at its default size and both
	/// dividers back to the middle, once, for everybody — which is a small loss
	/// but an avoidable one, and nobody would connect it to a rename.
	static let mainWindowLayoutName = "AbydosMainWindow"
	static let splitLayoutName = "AbydosSplit"
	static let panelSplitLayoutName = "AbydosPanelSplit"

	/// Copies what the old names saved onto the new ones, once.
	///
	/// The defaults keys are AppKit's own spelling — `NSWindow Frame <name>` and
	/// `NSSplitView Subview Frames <name>` — which is why they are written out
	/// here rather than derived: they are somebody else's format and worth being
	/// able to read.
	///
	/// Only when the new key is absent, so this cannot undo a later change; and
	/// the old keys are left where they are, because a copy nobody reads costs a
	/// few bytes and deleting somebody's data to save them is the wrong trade.
	static func carryRememberedLayoutAcross() {
		let defaults = UserDefaults.standard
		let moves = [
			("NSWindow Frame IdeaiMainWindow", "NSWindow Frame \(mainWindowLayoutName)"),
			("NSSplitView Subview Frames IdeaiSplit", "NSSplitView Subview Frames \(splitLayoutName)"),
			("NSSplitView Subview Frames IdeaiPanelSplit",
			 "NSSplitView Subview Frames \(panelSplitLayoutName)"),
		]
		for (old, new) in moves where defaults.object(forKey: new) == nil {
			guard let saved = defaults.object(forKey: old) else { continue }
			defaults.set(saved, forKey: new)
		}
	}

	private func updateRailForPanel() {
		toolStrip.setPanelSelection(bottomPanel.frontPaneKinds)
	}

	/// A hook event said something about the sessions of some project. The
	/// navigator decides whether it was the one this window is showing.
	func claudeSessionsChanged(slug: String) {
		navigator.claudeSessionsChanged(slug: slug)
	}

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
		// Answered while `Toast.post` is still on the stack, which is what lets a
		// question that landed in a gap between windows be asked again rather than
		// vanishing. See `Toast.ask`.
		(notification.userInfo?["taken"] as? Toast.Taken)?.value = true
	}

	/// A question in the corner is no longer worth asking.
	///
	/// Every window rather than the one that speaks for the app: the question was
	/// shown by whichever window was frontmost when it was asked, which is not
	/// necessarily this one now, and a question withdrawn from the wrong window is
	/// a question left on screen.
	@objc private func toastWithdrawn(_ notification: Notification) {
		guard let identifier = notification.userInfo?["identifier"] as? String else { return }
		toasts.withdraw(identifier)
	}

	/// What the corner is saying, for the harness.
	func toastReportForTesting() -> String { toasts.reportForTesting() }

	/// Presses one of a question's answers by its words.
	func answerToastForTesting(_ title: String) -> Bool { toasts.answerForTesting(title) }

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
		//
		// A driven run reads the remembered frame and does not register to save
		// one. AppKit's autosave is a write to `UserDefaults.standard` that no
		// injected store can intercept — it happens inside the framework, under
		// `NSWindow Frame AbydosMainWindow` — so the only way a driven run leaves
		// somebody's window where they left it is not to take the name. 0522
		// caught this by driving a run and diffing `defaults` either side of it:
		// nothing this program writes had moved, and the split frames had.
		if DrivenRun.isActive {
			Self.carryRememberedLayoutAcross()
		window.setFrameUsingName(Self.mainWindowLayoutName)
		} else {
			window.setFrameAutosaveName(Self.mainWindowLayoutName)
		}

		// A second window must not sit exactly on top of the first, so AppKit
		// steps it down and across from whatever is already open.
		if NSApp.windows.contains(where: { $0.isVisible && $0 !== window }) {
			window.setFrameOrigin(window.cascadeTopLeft(from: .zero))
		}

		super.init(window: window)
		window.delegate = self

		buildContent()
		buildToolbar()
		titlebar.buildBackdrop()
		// From the moment there is a window, not only from the moment somebody
		// clicks on one: a driven run never makes a window key, and a server
		// asking to apply an edit in that gap would be told there was nowhere to
		// apply it.
		takeServerEdits()

		editor.onMaximize = { [weak self] in self?.toggleEditorMaximized(nil) }
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

		// A diagram exported as a picture: the tree shows where it went. The
		// watcher will find the file by itself a moment later, so this is about
		// pointing at it rather than about knowing it exists.
		NotificationCenter.default.addObserver(
			forName: .abydosDiagramExported,
			object: nil,
			queue: .main
		) { [weak self] note in
			guard let url = note.userInfo?["url"] as? URL else { return }
			MainActor.assumeIsolated { self?.navigator.revealExported(url) }
		}

		// A container came up or went away — because a file was opened and its
		// server went inside one, or because somebody opened a terminal in it, or
		// because it was turned off. The titlebar says which project is being
		// worked on in one, and none of those moments is a moment it could ask.
		NotificationCenter.default.addObserver(
			forName: .abydosDevContainersChanged,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.titlebar.refreshDevContainer() }
		}

		// And when the answer changes rather than the container: a project whose
		// servers were moved onto this machine keeps its container up, and the
		// pill has to stop claiming the project is being worked on inside it.
		NotificationCenter.default.addObserver(
			forName: .ideaiLanguageServersMoved,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.titlebar.refreshDevContainer() }
		}

		// And when where they run changes without anybody having said anything: a
		// container that was asked for and would not come up puts the project's
		// servers on this machine, and until 0444 nothing told the titlebar, which
		// went on saying the container was starting for the rest of the session.
		NotificationCenter.default.addObserver(
			forName: .ideaiLanguageServersChanged,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.titlebar.refreshDevContainer() }
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Layout

	private func buildContent() {
		let root = ColoredView(color: Theme.current.windowBackground)
		root.colourSource = { Theme.current.windowBackground }

		toolStrip.onToggleNavigator = { [weak self] in self?.sidebar.showSidebarTool(.project) }
		toolStrip.onToggleTerminal = { [weak self] in self?.toggleTerminal(nil) }
		toolStrip.onReviewBranch = { [weak self] in self?.reviewBranch(nil) }
		toolStrip.onReviewUncommitted = { [weak self] in self?.reviewUncommittedChanges(nil) }
		toolStrip.onToggleChanges = { [weak self] in self?.sidebar.showSidebarTool(.changes) }
		toolStrip.onToggleBranches = { [weak self] in self?.sidebar.showSidebarTool(.branches) }
		toolStrip.onToggleStructure = { [weak self] in self?.sidebar.showSidebarTool(.structure) }
		toolStrip.onToggleScratches = { [weak self] in self?.sidebar.showSidebarTool(.scratches) }
		toolStrip.onToggleHistory = { [weak self] in self?.sidebar.showSidebarTool(.history) }
		toolStrip.onToggleBacklog = { [weak self] in self?.showBacklog(nil) }
		NotificationCenter.default.addObserver(
			self, selector: #selector(toastPosted(_:)), name: .abydosToast, object: nil
		)
		NotificationCenter.default.addObserver(
			self, selector: #selector(toastWithdrawn(_:)), name: .abydosToastWithdrawn, object: nil
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

		// The sidebar holds the tool, and a results list under it when one has
		// been put there.
		//
		// It used to be a split with a second pane underneath for a docked view,
		// and the only thing ever docked there was the usages list — which item
		// 470 moved into the bottom panel beside search, where the checklist it
		// shares already lives. It was made one view again because "a split with
		// one pane in it and a divider nobody can reach is not worth keeping for
		// a route nothing takes".
		//
		// **That reason was about the route, not about the split, and item 506 is
		// the route.** So the split is back, with the objection answered rather
		// than repeated: `sidebar.sidebarSplit` holds exactly one arranged subview
		// whenever nothing is docked below, and an `NSSplitView` with one subview
		// draws no divider at all. There is nothing to reach until there is
		// something to reach for.
		let toolContainer = ColoredView(color: Theme.current.sidebarBackground)
		toolContainer.colourSource = { Theme.current.sidebarBackground }

		sidebar.sidebarSplit = ThinDividerSplitView()
		sidebar.sidebarSplit.isVertical = false
		sidebar.sidebarSplit.dividerStyle = .thin
		sidebar.sidebarSplit.addArrangedSubview(toolContainer)
		sidebar.sidebarSplit.translatesAutoresizingMaskIntoConstraints = false
		navigatorContainer.addSubview(sidebar.sidebarSplit)
		NSLayoutConstraint.activate([
			sidebar.sidebarSplit.topAnchor.constraint(equalTo: navigatorContainer.topAnchor),
			sidebar.sidebarSplit.bottomAnchor.constraint(equalTo: navigatorContainer.bottomAnchor),
			sidebar.sidebarSplit.leadingAnchor.constraint(equalTo: navigatorContainer.leadingAnchor),
			sidebar.sidebarSplit.trailingAnchor.constraint(equalTo: navigatorContainer.trailingAnchor),
		])

		sidebar.primaryContainer = toolContainer

		sidebar.primaryContainer.addSubview(navigator.view)
		navigator.view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			navigator.view.topAnchor.constraint(equalTo: sidebar.primaryContainer.topAnchor),
			navigator.view.bottomAnchor.constraint(equalTo: sidebar.primaryContainer.bottomAnchor),
			navigator.view.leadingAnchor.constraint(equalTo: sidebar.primaryContainer.leadingAnchor),
			navigator.view.trailingAnchor.constraint(equalTo: sidebar.primaryContainer.trailingAnchor),
		])
		sidebar.primaryToolView = navigator.view

		splitView = ThinDividerSplitView()
		splitView.isVertical = true
		splitView.dividerStyle = .thin
		splitView.addArrangedSubview(navigatorContainer)
		splitView.addArrangedSubview(editor.view)
		// No name in a driven run, for the reason the window frame gives: an
		// autosaved split writes `UserDefaults.standard` from inside AppKit. A
		// capture that wants a particular sidebar says so with `--sidebar-width`,
		// which is what `Scripts/screenshots.sh` has always done and why.
		splitView.autosaveName = DrivenRun.isActive ? "" : Self.splitLayoutName
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
		verticalSplitView.autosaveName = DrivenRun.isActive ? "" : Self.panelSplitLayoutName
		// For `splitViewDidResizeSubviews`, which rounds the panel down to
		// whole terminal rows.
		verticalSplitView.delegate = self

		bottomPanel.onRequestHide = { [weak self] in self?.setPanelVisible(false) }
		bottomPanel.onToggleMaximize = { [weak self] in self?.togglePanelMaximized() }
		bottomPanel.onRequestNewTerminalMenu = { [weak self] view, point in
			guard let self else { return }
			self.newTerminalMenu().popUp(positioning: nil, at: point, in: view)
		}
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
			self.results.showSymbols(query: ProfileFrame.symbolName(in: frame))
		}
		// The debugger's own toolbar, once the program has ended: whatever the
		// play button up in the titlebar would start is what these start too.
		// A run or a debugger brought forward takes the window back to the
		// project it belongs to — while the window is following its terminal,
		// which is the only time it is anywhere else.
		// Every route into a pane comes through the panel's column rebuild —
		// the button, ⇧⌘B, the Agent menu, a tab closing and leaving another in
		// front, a split. So the rail is told from there rather than from each
		// of the places somebody can open one.
		bottomPanel.onFrontPanesChanged = { [weak self] in self?.updateRailForPanel() }

		bottomPanel.onPaneNeedsProject = { [weak self] root in
			guard let self, self.followsTerminal else { return }
			// The other place a pane's report moves the window, and reachable in
			// a driven run: `--debug-steps` and `--run-line` both bring a pane
			// forward. Guarded where the report is acted on rather than by
			// filtering what a driven run is allowed to read, so the rule is in
			// the two places that could move the window and nowhere else.
			guard !LaunchOptions.parse().isDrivenRun else { return }
			// Following, so the same rule as a shell that moved: the panel is
			// where the change came from and is not to be moved by it.
			self.switchProject(to: root, followingTerminal: true)
		}
		bottomPanel.onRunAgain = { [weak self] in self?.run.runSelectedConfiguration(debug: false) }
		bottomPanel.onDebugAgain = { [weak self] in self?.run.runSelectedConfiguration(debug: true) }
		// Room first, for the reason `makeRoomForTheEditor` already gives about a
		// breakpoint's line: everything that comes through here is a *pane*
		// asking for a file, and a pane can have the whole window. A backlog
		// item opened from a maximised board, a review finding, a search result
		// — each of them opened the file behind the thing that opened it, which
		// from the outside is indistinguishable from nothing happening.
		bottomPanel.onOpenFinding = { [weak self] url, line in
			guard let self else { return }
			self.makeRoomForTheEditor()
			self.editor.open(fileURL: url, atLine: line)
		}
		// A checklist row, which also says whether the keyboard goes with it. Room
		// is made for the editor either way — a preview nobody can see is not one
		// — but a preview leaves the keyboard in the list.
		bottomPanel.onOpenResult = { [weak self] url, match, intent in
			guard let self else { return }
			self.makeRoomForTheEditor()
			self.results.openFromChecklist(url, match: match, intent: intent)
		}
		bottomPanel.onOpenFileFromTerminal = { [weak self] request in
			self?.openFromTerminal(request)
		}
		// Through the delegate rather than `switchProject`, so a worktree
		// opened from a backlog card obeys the same rule as one opened from
		// the project switcher: this window or a new one, whichever the
		// setting says, and an already-open checkout is raised rather than
		// opened twice.
		bottomPanel.onOpenProject = { [weak self] root in
			guard let self else { return }
			(NSApp.delegate as? AppDelegate)?.open(projectAt: root, from: self)
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
		navigator.onFilesChanged = { [weak self] change in
			// Something wrote inside the project — possibly a file that is open.
			self?.editor.reloadExternallyChangedFiles()
			self?.sidebar.changesPane?.refresh()
			// A new main.go or Makefile target should get its play button
			// without reopening the project — but only when what was written
			// could be one. See `run.refreshRunConfigurations(because:)`.
			self?.run.refreshRunConfigurations(because: change)
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
		editor.onFilesDropped = { [weak self] urls in self?.openDropped(urls) }
		editor.onActiveFileChanged = { [weak self] url in
			// The outline belongs to the file in front, so it follows the tabs.
			self?.sidebar.refreshStructure()
			// The history offers to narrow itself to whatever is in front.
			self?.sidebar.historyPane?.offerScope(path: self?.relativePathOfActiveFile())
			guard let url else { return }
			self?.navigator.selectWithoutOpening(url: url)
		}
		// Clicking the breakpoint gutter reaches the running debug session, and
		// is remembered even when nothing is running yet.
		editor.onFindUsages = { [weak self] url, line, character in
			self?.findUsages(in: url, line: line, character: character)
		}
		editor.onRename = { [weak self] url, line, character in
			self?.renameSymbol(in: url, line: line, character: character)
		}
		editor.onWatch = { [weak self] expression in
			self?.watchFromEditor(expression)
		}
		editor.onFixWithAI = { [weak self] url, line, diagnostic in
			self?.fixWithAI(url: url, line: line, diagnostic: diagnostic)
		}
		editor.onCopyLink = { [weak self] url, form, line, endLine in
			self?.copyLink(to: url, form: form, line: line, endLine: endLine)
		}
		editor.onEditBreakpoint = { [weak self] url, line in
			self?.debug.editBreakpoint(file: url, line: line)
		}
		editor.onToggleBreakpoint = { [weak self] url, line in
			self?.debug.toggleBreakpoint(file: url, line: line)
		}
		editor.onSetBreakpointEnabled = { [weak self] url, line, enabled in
			self?.debug.setBreakpoint(file: url, line: line, enabled: enabled)
		}
		editor.onDeleteBreakpoint = { [weak self] url, line in
			self?.debug.deleteBreakpoint(file: url, line: line)
		}
		editor.onSetOtherBreakpointsEnabled = { [weak self] url, line, enabled in
			self?.debug.setOtherBreakpoints(file: url, line: line, enabled: enabled)
		}
		editor.onLinesChanged = { [weak self] url, first, removed, inserted in
			self?.moveBreakpoints(inFile: url, editedFrom: first, removed: removed, inserted: inserted)
		}
		editor.onFileReloaded = { [weak self] url in
			self?.debug.reanchorBreakpoints(inFile: url)
		}
		editor.onRunLine = { [weak self] url, line in
			self?.run.runConfiguration(forFile: url, line: line)
		}
		editor.onApplyDiffSelection = { [weak self] change, diff, selected in
			self?.sidebar.applyDiffSelection(change: change, diff: diff, lines: selected)
		}
		editor.onDiscardDiffSelection = { [weak self] change, diff, selected in
			self?.sidebar.discardDiffSelection(change: change, diff: diff, lines: selected)
		}
		// **Offered only where git can do it.** `stash push --staged` arrived
		// in 2.35; on an older one the item is absent rather than a menu entry
		// that fails when pressed. Asked once, when the window is built.
		if let root = project?.root {
			Task { @MainActor [weak self] in
				guard await GitStash.canPushStaged(in: root) else { return }
				self?.editor.onStashDiffSelection = { [weak self] change, diff, selected in
					self?.sidebar.stashDiffSelection(change: change, diff: diff, lines: selected)
				}
			}
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
					let head = await current.git?.currentHead()
					self.titlebar.setBranch(head?.name, isUnborn: head?.isUnborn ?? false)
					self.titlebar.relayout()
				}
			}
			watcher.start()
			self?.repositoryWatcher = watcher
		}
	}

	private func buildToolbar() {
		let toolbar = NSToolbar(identifier: "AbydosToolbar")
		toolbar.delegate = titlebar
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = false
		window?.toolbar = toolbar
		// .unified keeps the items on the traffic-light row rather than in a
		// second bar below it — the arrangement in the reference screenshot.
		window?.toolbarStyle = .unified
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

		titlebar.setInset(inset)
		// Views added after it would otherwise cover it.
		navigator.setTopInset(inset)
		sidebar.sidebarTopInset = inset
		if isPanelMaximized { bottomPanel.setTopInset(inset) }
		sidebar.primaryToolTop?.constant = inset
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

	/// The directory git commands belong in, which is not `scopeRoot`.
	///
	/// `git status` reports paths from the work tree root whatever directory it
	/// ran in, while `git add` and friends resolve a pathspec against the
	/// current one — so a pane running git inside a subproject and handing it
	/// those root-relative paths made git look for `sub/sub/…` and refuse.
	/// Staging did not work at all while a subproject was open.
	///
	/// Falls back to the scope only until the repository has been found, which
	/// is also the one case where there is nothing better to say.
	var gitCommandRoot: URL? { project?.gitRoot ?? scopeRoot }

	/// Works on part of the project instead of the whole of it.
	func openSubproject(at url: URL) {
		guard let project else { return }
		guard Subprojects.resolve(Subprojects.relativePath(url, to: project.root), in: project.root) != nil
		else { return }
		guard url.path != subprojectRoot?.path else { return }

		leftScope()
		subprojectRoot = url.standardizedFileURL
		applyScope()
	}

	/// Back to the whole project.
	func leaveSubproject() {
		guard subprojectRoot != nil else { return }
		leftScope()
		subprojectRoot = nil
		applyScope()
	}

	/// The window is about to stop showing this scope.
	///
	/// A question in the corner about the scope's devcontainer goes with it: it
	/// names a project, and asking it over a window now showing a different one
	/// would put an answer about somewhere else one click away. Nothing is
	/// decided by this — the project asks again the next time something needs the
	/// container — and the pill in the titlebar is the standing way in either
	/// way.
	private func leftScope() {
		guard let scope = scopeRoot else { return }
		LanguageService.shared.withdrawDevContainerQuestion(for: scope)
	}

	/// Reads the repository for the current scope, and tells the window.
	///
	/// One task, kept: it is what the branch pill awaits when the toolbar gets
	/// around to building it.
	@discardableResult
	private func readGit() -> Task<GitRepository.Head?, Never> {
		branchRead?.cancel()
		let askedAt = Date()
		// Said before the asking, because the asking is the part that takes the
		// time. This is the 784 ms the pill used to spend absent.
		titlebar.isReadingBranch = true
		titlebar.relayout()
		let read = Task { @MainActor [weak self] () -> GitRepository.Head? in
			guard let self, let project = self.project else { return nil }
			await project.loadGit()
			return await project.git?.currentHead()
		}
		branchRead = read

		Task { @MainActor [weak self] in
			let head = await read.value
			guard let self, !Task.isCancelled else { return }
			self.titlebar.setBranch(head?.name, isUnborn: head?.isUnborn ?? false)
			if ProjectSwitcherPopover.reportsForTesting {
				print(String(format: "BRANCHPILL appeared after %8.2f ms  (%@)",
					Date().timeIntervalSince(askedAt) * 1000, head?.name ?? "no branch"))
				fflush(stdout)
			}
			// The capsule only gets its width once it has a name to show.
			self.titlebar.relayout()
			self.navigator.refreshGitStatus()

			// Changes, history and branches hold on to one repository, so a
			// *different* work tree needs them built again — which is what
			// this said and not what it did. Rebuilding whatever the answer
			// came back as threw away a pane somebody was already using:
			// reading the repository finishes a second or two after a window
			// opens, and it took with it the commit message half typed into the
			// pane and the folders unfolded in it.
			if self.sidebar.currentSidebarTool == .changes || self.sidebar.currentSidebarTool == .branches {
				let holding = self.sidebar.currentSidebarTool == .changes
					? self.sidebar.changesPane?.repositoryRoot
					: self.sidebar.branchesPane?.repositoryRoot
				if holding != (self.scopeRoot ?? self.project?.root) {
					self.sidebar.install(tool: self.sidebar.currentSidebarTool, force: true)
				}
			}
			self.run.refreshRunConfigurations()
		}
		return read
	}

	/// Points everything scoped at the current scope.
	private func applyScope() {
		guard let project, let scope = scopeRoot else { return }

		// Set before anything reads it: a git load started for the whole project
		// may still be in flight, and both must look in the same place.
		project.scope = subprojectRoot

		run.selectedConfigurationName = nil
		run.refreshRunControl()
		LanguageService.shared.warmUp(project: scope)
		// The files already on screen belong to the new scope's servers now.
		// Without this the container's server comes up knowing about nothing,
		// and the file somebody is looking at is the one it has not been told
		// about — which is 0432 from the other end.
		editor.rescope()
		startWatchingRepository(at: scope)
		bottomPanel.setWorkingDirectory(scope)

		titlebar.setSubprojectPath(
			subprojectRoot.map { Subprojects.relativePath($0, to: project.root) }
		)
		// The devcontainer is the subproject's whenever it has one, so moving
		// between them moves which container the titlebar is talking about.
		titlebar.refreshDevContainer()
		titlebar.relayout()
		navigator.setSubproject(subprojectRoot)
		rememberOpenEditors()

		// Git is per work tree, and a subproject may be its own repository — a
		// checkout of several is the case this exists for.
		readGit()
	}

	func load(project: Project, focusTree: Bool = true) {
		// **Read before a single thing is touched.** `switchProject` says this
		// above its own read and it is right — "anything that writes the session
		// on the way past would overwrite the very thing being restored" — but
		// this function then read the file a *second* time, at the bottom, and
		// that is the read the subproject comes from. In between,
		// `selectedConfigurationName = nil` fires its own `didSet`, which calls
		// `rememberOpenEditors` for a window whose project is already the new one
		// and whose `subprojectRoot` has just been cleared. So the session on disk
		// was rewritten without its `subproject` before the line that needed it
		// looked.
		let remembered = SessionStore.read(in: project.root)

		self.project = project
		subprojectRoot = nil
		// And on the project itself, which is what everything scoped reads: a
		// Project handed back by the switcher may be one that was open before,
		// with the scope it had then still on it.
		project.scope = nil
		titlebar.setSubprojectPath(nil)
		window?.title = project.name

		// No badge and no colour: which project this is gets stated once, by the
		// name, and colour is kept for the switcher — where there is more than
		// one project on screen and it has something to tell apart.
		titlebar.setProjectName(project.name)
		// Cleared rather than left standing: the pill of the project being left
		// would sit in the titlebar of the one arriving until git answered, and
		// the two repositories have nothing to do with each other.
		titlebar.clearWorktrees()
		titlebar.setBranch(nil, isUnborn: false)
		// Reading, not absent: this window is about to ask git about the project
		// that has just arrived, and that is what the half should say meanwhile.
		titlebar.isReadingBranch = true
		titlebar.refreshDevContainer()
		titlebar.relayout()
		titlebar.readWorktrees()

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
		run.selectedConfigurationName = nil
		run.refreshRunControl()
		startWatchingRepository(at: project.root)
		sidebar.scratchesPane?.setProject(project.root)
		// The panes that are about a project follow it. Told with `project.root`
		// rather than through `setWorkingDirectory`, which also carries a
		// subproject scope — see `BottomPanel.setProject`.
		bottomPanel.setProject(project.root)
		bottomPanel.setWorkingDirectory(project.root)

		// What was open here last time, from the folder beside the project —
		// which is what makes opening it again feel like coming back rather
		// than starting.
		if let remembered {
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
				run.selectedConfigurationName = chosen
				run.refreshRunControl()
			}
			run.xcodeDestinations = remembered.xcodeDestinations

			// The gutter, from what was there last time. Only when nothing has
			// set any yet: a window that already has debug.breakpoints is one where
			// somebody has been working, and a file restored over that would
			// take them away.
			if debug.pendingBreakpoints.isEmpty, !remembered.breakpoints.isEmpty {
				debug.pendingBreakpoints = remembered.breakpoints
				debug.showPendingBreakpoints()
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
		run.refreshRunConfigurations()
	}

	/// Opens a file as a permanent tab and selects it in the tree.
	func openFile(at url: URL) {
		editor.open(fileURL: url, focusEditor: true, preview: false)
		navigator.selectWithoutOpening(url: url)
	}

	/// `abydos <file>`, typed in one of this window's terminals.
	///
	/// Three things, and the third is what makes it a gesture rather than a
	/// background event: the file opens in *this* window's editor, the keyboard
	/// goes with it, and the terminal comes back to a split if it had the window
	/// to itself. A file opened into a pane nobody can see is the same as not
	/// opening it, and the next thing typed would still go to the shell.
	///
	/// The panel stays down afterwards. Sending it back up when the editor loses
	/// focus would be a mode nobody asked for, and it would fight with the next
	/// click; this is the same restore the debugger and the tree already do.
	///
	/// It comes back to the height it had before it was maximised, and then to
	/// half the window if that height was more — the same rule the debugger
	/// uses, for the same reason. A terminal maximised from a panel that was
	/// already most of the window restores to most of the window, and a file
	/// opened behind a strip of editor is a file nobody can read.
	///
	/// A file outside the project opens here as a loose tab rather than being
	/// refused or taking the window to another project. Somebody typing
	/// `abydos ~/notes.md` in a pane is asking to read it beside what they are
	/// working on, not to stop working on it.
	func openFromTerminal(_ request: TerminalOpenRequest) {
		let url = URL(fileURLWithPath: request.path).standardizedFileURL
		// A directory is a project, whoever asked; that is what `abydos` with no
		// arguments means and it is not this window's to reinterpret.
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
		      !isDirectory.boolValue else { return }

		makeRoomForTheEditor()
		// The pane may be in a torn-off terminal window, in which case this one
		// is not in front and the file would open behind it.
		window?.makeKeyAndOrderFront(nil)
		if let line = request.line {
			editor.open(fileURL: url, atLine: line)
		} else {
			editor.open(fileURL: url, focusEditor: true, preview: false)
		}
		navigator.selectWithoutOpening(url: url)
	}

	/// Opens what was dropped on the editor.
	///
	/// **The window's project does not change.** `openFromTerminal` is the
	/// precedent and the reason is what switching costs: the tree, git, the run
	/// configurations, the language servers and the remembered session all belong
	/// to the project, so re-pointing them because somebody dragged a file in is
	/// a very large answer to a very small gesture. A file dropped on the *Dock
	/// icon* is a different case — that one is addressed to the application,
	/// which has no window in mind and must find one, and it does switch.
	///
	/// A folder is a project, which it means everywhere else here — `abydos
	/// <dir>`, the Dock icon, the switcher — so it goes through the same opening
	/// as those and obeys the same setting about taking this window or another.
	///
	/// Files open in order, last in front, and none of them provisional: a
	/// preview tab is the answer to a single click in the tree, where the next
	/// click replaces it, and a drag is deliberate.
	func openDropped(_ urls: [URL]) {
		let (folders, files) = EditorDrop.separate(urls)

		// **Folders first, and the files go to the window that results.**
		//
		// The other order was tried and measured: a file opened here and a
		// folder opened after it left `project=inner-project tabs=[]` — the file
		// was opened into the project being left, and switching restored the
		// arriving project's session over the top of it. The file was simply
		// lost, which is not "each does what it would have done alone".
		var target = self
		for folder in folders {
			guard let opened = (NSApp.delegate as? AppDelegate)?.open(projectAt: folder, from: target)
			else { continue }
			// The first folder's window takes the files. A drag with several
			// folders opens several projects; the files belong with the first,
			// which is the one the drop was aimed at.
			if target === self { target = opened }
		}

		for file in files {
			target.makeRoomForTheEditor()
			target.editor.open(fileURL: file, focusEditor: true, preview: false)
			target.navigator.selectWithoutOpening(url: file)
		}
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

		// Whatever the theme did, the terminal's palette may have moved on its
		// own: "Terminal colours" is a setting of its own and can change while
		// the theme stands still. `applyPalette` above runs only when the theme
		// actually changed, so this cannot live in there.
		//
		// It matters now in a way it did not before: `TerminalScheme.current` used
		// to be worked out on every access, so a changed scheme took effect by
		// itself and nobody had to say so. It is remembered now, because working
		// it out meant two `UserDefaults` reads per frame, so forgetting it is
		// something that has to be *done* — and this is the moment a preference
		// changed. Cheap: it nils a cache, and the table is rebuilt on the next
		// draw rather than here.
		TerminalPalette.invalidate()

		editor.applySettings()
		navigator.applySettings()
		toolStrip.applySettings()
		bottomPanel.applySettings()

		// The pills re-measure at the new scale, and the toolbar item has to be
		// told to re-lay-out around them.
		titlebar.relayout()
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
		sidebar.install(tool: sidebar.currentSidebarTool, force: true)
	}

	/// Opens the sidebar to a width, for looking at a pane in a screenshot.
	func openSidebarForTesting(width: CGFloat) {
		navigatorWidth = width
		navigatorWidthConstraint.constant = width
		navigatorContainer.isHidden = false
		splitView.setPosition(width, ofDividerAt: 0)
		splitView.adjustSubviews()
		sidebar.updateSidebarSelection()
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
				breakpoints: self.debug.pendingBreakpoints
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
		run.processPicker = picker
		picker.onAttach = { [weak self] chosen in
			guard let self else { return }
			self.run.processPicker = nil
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
			breakpoints: debug.pendingBreakpoints
		) else { return }
		wire(session)
	}

	// MARK: - Debugging

	@objc func debugContinue(_ sender: Any?) { debugSession?.resume() }
	@objc func debugPause(_ sender: Any?) { debugSession?.pause() }
	@objc func debugStepOver(_ sender: Any?) { debugSession?.stepOver() }
	@objc func debugStepInto(_ sender: Any?) { debugSession?.stepInto() }
	@objc func debugStepOut(_ sender: Any?) { debugSession?.stepOut() }

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
		case #selector(newTerminalTab(_:)), #selector(newTerminalTabBeside(_:)):
			return bottomPanel.hasKeyboardFocus
		case #selector(newTerminalInContainer(_:)):
			// Off for the projects that have no such file, which is most of
			// them: an item that is always there and always fails is worse than
			// one that says by being grey which projects it is for.
			//
			// Named here rather than once at build time because which container
			// it means changes with the subproject being worked in, and this is
			// the moment before it is read.
			//
			// An item carrying a choice is named after *that* one: the chevron's
			// menu has one entry per devcontainer and they all come through here,
			// so naming them all after the preferred one would make every entry
			// in a project with two read the same.
			item.title = devContainerMenuTitle(for: choice(carriedBy: item))
			return hasDevContainer
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
			+ "sessions=\(bottomPanel.terminalSessionCountForTesting)")
		if validateMenuItem(item) { newTerminalTab(nil) }

		toggleTerminal(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
			guard let self else { return }
			print("TAB: in terminal focused=\(self.isTerminalFocused) "
				+ "enabled=\(self.validateMenuItem(item)) sessions=\(self.bottomPanel.terminalSessionCountForTesting)")
			if self.validateMenuItem(item) { self.newTerminalTab(nil) }

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				print("TAB: after ⌘T   sessions=\(self.bottomPanel.terminalSessionCountForTesting)")
			}
		}
	}

	/// Opens a couple of tabs and presses ⌘D, then says what is in each column.
	///
	/// The claim is that the new shell is *beside* the one in front — both on
	/// screen at once — and that is only visible per column: a tab that landed
	/// in the same strip and a pane that landed in a column of its own both read
	/// as "one more terminal" from the count alone, which is how the first
	/// attempt at this looked right and was not.
	func exerciseTerminalTabBesideForTesting() {
		// The command is gated on the terminal having the keyboard, and a run
		// that never came to the front has given it to nobody — so without this
		// the harness measures the gate rather than the placement.
		NSApp.activate(ignoringOtherApps: true)
		window?.makeKeyAndOrderFront(nil)
		toggleTerminal(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			guard let self else { return }
			for _ in 0..<2 { self.bottomPanel.newTerminal() }
			print("BESIDE: opened     \(self.bottomPanel.columnsForTesting)")

			self.bottomPanel.selectAndFocusTabForTesting(1)
			print("BESIDE: selected   \(self.bottomPanel.columnsForTesting)")

			let item = NSMenuItem(
				title: "New Terminal Tab Here",
				action: #selector(self.newTerminalTabBeside(_:)),
				keyEquivalent: "d"
			)
			// Two things, reported apart, because they fail apart: whether the
			// command is offered at all — which needs the keyboard, and a
			// capture run has no key window to give it — and where the tab
			// lands, which is what this change is.
			print("BESIDE: enabled=\(self.validateMenuItem(item)) "
				+ "keyWindow=\(self.window?.isKeyWindow ?? false)")
			self.bottomPanel.newTerminalBesideCurrent()

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				print("BESIDE: after ⌘D   \(self.bottomPanel.columnsForTesting)")
				fflush(stdout)
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
			breakpoints: debug.pendingBreakpoints
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
			fflush(stdout)
		}
	}

	/// Presses Stop and says what the session left behind.
	///
	/// The report the change is about: after a stop, what the panes are still
	/// showing. `EXIT` already prints the code for a program that ended on its
	/// own — this is the other path, the one somebody takes when the program is
	/// sitting at a breakpoint and they have seen enough.
	///
	/// Printed twice, before and after, because the fault is a difference: the
	/// goroutine list is right while the program is there and wrong a moment
	/// later, and one line cannot show that.
	func reportDebugStopForTesting(_ phase: String) {
		guard let session = debugSession else {
			print("STOP: \(phase) no session")
			fflush(stdout)
			return
		}
		if phase == "press" {
			session.stop()
			print("STOP: pressed")
			fflush(stdout)
			return
		}
		// The other ending: let it run to the end rather than stopping it. This
		// is the path where Delve reports a status at all — stopped, it says
		// "Detaching and terminating target process" and there is no status,
		// because the program did not exit.
		if phase == "finish" {
			session.resume()
			print("STOP: released")
			fflush(stdout)
			return
		}
		// Built a piece at a time. As one expression this was six interpolations
		// and two optional maps joined by `+`, which the type checker gave up
		// on — "unable to type-check this expression in reasonable time".
		let reply = session.disconnectReplyTimeForTesting.map { String(format: "%.3fs", $0) } ?? "none"
		let code = session.exitCode.map(String.init) ?? "none"
		var line = "STOP: \(phase) state=\(session.state)"
		line += " reply=\(reply) code=\(code)"
		line += " threads=\(session.threads.count)"
		line += " frames=\(session.stackFrames.count)"
		line += " scopes=\(session.scopes.count)"
		print(line)
		for thread in session.threads {
			print("STOP: \(phase) thread \(thread.id) \(thread.name)")
		}
		fflush(stdout)
	}

	/// Whether the project that was left is still being watched.
	///
	/// **The half that fails silently.** `watch()` starts a watcher only where
	/// there is none, so a pane that kept its old ones would be woken by the
	/// folder it no longer shows and never by the one it does — right when it is
	/// opened and stale a moment later, which is harder to notice than being
	/// stale throughout.
	///
	/// Checked by writing an item into the project that was left and looking
	/// again. The board must not move. Count-based rather than wall-clock: what
	/// is asserted is what the board holds, not that a second passed.
	func checkTheOldProjectIsUnwatchedForTesting(_ oldRoot: URL) {
		let folder = oldRoot.appendingPathComponent(".abydos/backlog/open", isDirectory: true)
		guard FileManager.default.fileExists(atPath: folder.path) else {
			print("PANES watch: \(oldRoot.lastPathComponent) has no backlog to touch")
			fflush(stdout)
			return
		}
		let file = folder.appendingPathComponent("9999-written-after-the-switch.md")
		try? "# 9999 Written after the switch\n".write(to: file, atomically: true, encoding: .utf8)
		print("PANES watch: wrote an item into \(oldRoot.lastPathComponent)")
		fflush(stdout)

		// Long enough for a watcher to have fired if one were still on it —
		// FSEvents is subsecond, and the reload behind it is a directory walk.
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
			self?.reportPanesForTesting("after touching the old project")
			try? FileManager.default.removeItem(at: file)
			exit(0)
		}
	}

	/// Which project the panes are reading, either side of a switch.
	///
	/// The whole of the fault in one line: the window moves and the pane goes on
	/// naming — and showing — the project it was made for. `--switch-project`
	/// already existed and did the switching; what it could not do was say what
	/// the panes then held.
	func reportPanesForTesting(_ phase: String) {
		let window = project?.root.lastPathComponent ?? "none"
		let board = bottomPanel.existingBacklogPane?.projectReportForTesting ?? "no pane"
		print("PANES \(phase): window=\(window) board=[\(board)]")
		fflush(stdout)
	}

	/// Drops files on the editor the way the Finder would, and says what happened.
	///
	/// A real drag cannot be scripted, so this puts the URLs on a pasteboard and
	/// hands it to the group's drop view exactly as AppKit does — the same
	/// `draggingEntered` and `performDragOperation`, so what is checked is the
	/// path a drag actually takes rather than the opening underneath it.
	///
	/// The project is printed either side: a dropped file must not move it, and
	/// that is the half a report of tabs alone would not show.
	func dropFilesForTesting(_ paths: [String]) {
		let urls = paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
		print("DROP before: project=\(project?.root.lastPathComponent ?? "none")"
			+ " tabs=[\(editor.openTabNamesForTesting)]")
		fflush(stdout)

		guard let group = editor.activeGroup, let target = group.view as? EditorDropView else {
			print("DROP: no drop view")
			fflush(stdout)
			return
		}

		let board = NSPasteboard(name: .init("dev.abydos.drop-test"))
		board.clearContents()
		board.writeObjects(urls.map { $0 as NSURL })
		let drag = TestingDrag(pasteboard: board, at: NSPoint(x: 200, y: 200))

		let entered = target.draggingEntered(drag)
		print("DROP offered: \(entered.contains(.copy) ? "copy" : (entered.isEmpty ? "nothing" : "other"))")
		let took = target.performDragOperation(drag)
		print("DROP accepted: \(took)")
		fflush(stdout)

		// After the open, which reaches the editor through the window.
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
			guard let self else { return }
			print("DROP after: project=\(self.project?.root.lastPathComponent ?? "none")"
				+ " tabs=[\(self.editor.openTabNamesForTesting)]")
			fflush(stdout)
			exit(0)
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

	/// Gives the editor enough of the window to be looked at.
	///
	/// Two things can hide the line a breakpoint is on — or the file `abydos
	/// notes.md` just opened — and both are ordinary: the terminal can have the
	/// whole window, in which case the editor is hidden rather than small; and
	/// the panel can simply be tall, because it was dragged that way while
	/// reading a log. Neither is a state somebody chose *for this* — they chose
	/// it for the thing they were doing a minute ago, and something that arrives
	/// behind them has nothing to show.
	///
	/// Half the window is the most the panel keeps. Not a fixed height: the
	/// stack, the variables and the console all need room too, and taking the
	/// panel down to a strip to reveal one line is the opposite mistake.
	private func makeRoomForTheEditor() {
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

	/// Whether the editor has the window, and what to put back when it gives it
	/// up.
	///
	/// The two answers are remembered rather than assumed: somebody who was
	/// working with the sidebar already shut does not want it opened for them by
	/// un-maximising, and the panel is the same. Nil while nothing is maximised,
	/// so a stale pair cannot be restored over a window somebody has since
	/// rearranged by hand.
	private var beforeEditorMaximized: (navigator: Bool, panel: Bool)?

	var isEditorMaximized: Bool { beforeEditorMaximized != nil }

	/// Gives the editor the whole window, or gives it back.
	///
	/// A double-click on a tab that is already permanent, and the mirror of
	/// `togglePanelMaximized` — which does the same for the terminal, from the
	/// other side. Both hide rather than resize, for the reason that one records:
	/// a split view will not put a pane fully away, and a sliver of tree left
	/// showing is not what "give the editor the window" means.
	@objc func toggleEditorMaximized(_ sender: Any? = nil) {
		if let before = beforeEditorMaximized {
			beforeEditorMaximized = nil
			if before.navigator { openNavigator() }
			if before.panel { setPanelVisible(true) }
			updateTopInsets()
			return
		}

		// The terminal cannot have the window at the same moment. Un-maximising
		// it first, rather than refusing, because the gesture says what somebody
		// wants and the two states are exclusive.
		if isPanelMaximized { togglePanelMaximized(nil) }

		let navigatorShowing = !(navigatorContainer?.isHidden ?? true)
			&& (navigatorContainer?.frame.width ?? 0) >= 2
		beforeEditorMaximized = (navigator: navigatorShowing, panel: isPanelVisible)
		if navigatorShowing { toggleNavigator(nil) }
		if isPanelVisible { setPanelVisible(false) }
		updateTopInsets()
	}

	@objc func togglePanelMaximized(_ sender: Any? = nil) {
		if isPanelMaximized {
			sidebar.toolPopover?.performClose(nil)
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
			sidebar.install(tool: sidebar.currentSidebarTool, force: true)
			updateTopInsets()
			sidebar.updateSidebarSelection()
			return
		}

		setPanelVisible(true)
		isPanelMaximized = true
		bottomPanel.isMaximized = true
		// Nothing in the sidebar is showing any more, and the strip should not
		// claim otherwise; what it offers now opens over the terminal.
		toolStrip.setSidebarSelection(visible: false, tool: sidebar.currentSidebarTool)
		heightBeforeMaximize = max(160, bottomPanel.frame.height)
		// Hidden rather than resized to nothing: a split view will not put a
		// pane fully away, and a sliver of editor left showing is not what
		// "give the terminal the window" means.
		splitView.isHidden = true
		bottomPanel.setTopInset(sidebar.sidebarTopInset)
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
	/// nothing, which is what makes this bearable to leave switched on. Inside
	/// *the project*, not inside the repository around it — `projectToFollow`
	/// is where that distinction lives and why it has to be made.
	func terminalDirectoryChanged(to directory: URL) {
		// Never during a capture. A screenshot is of a project somebody named
		// on the command line, and a restored tmux session whose shell sits in
		// another checkout would quietly swap it for that one — which is a
		// screenshot of the wrong program, taken without complaint.
		//
		// The sentence above was true when nobody was photographing anything
		// too, and 0509 is what it cost. The guard stays: a driven run is about
		// a named project and must not follow a shell anywhere, including
		// somewhere the rule below would rightly follow it.
		//
		// **It asked about the picture and it meant the driving**, which is
		// 0534. A run with a verb and no `--screenshot` was not guarded at all,
		// so a terminal whose working directory had been deleted underneath it
		// took the window somewhere nobody named — reproduced five times out of
		// five, and the driver then did its work to whatever that window had
		// open. 0509 had already found this rule broader than photography once;
		// the comment was widened then and the test was not.
		guard !LaunchOptions.parse().isDrivenRun else { return }
		guard followsTerminal else { return }
		guard let root = ProjectRoot.projectToFollow(from: directory, current: project?.root)
		else { return }
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

		// Named, so that a stall inside a switch says "project switch" rather
		// than "idle". It used to say idle — a two-and-a-half-second stall with
		// nothing to say for itself — which is the one thing the stall log
		// exists not to do.
		StallWatch.mark("project switch") {
			switchProjectBody(to: root, followingTerminal: followingTerminal)
		}
	}

	private func switchProjectBody(to root: URL, followingTerminal: Bool) {
		leftScope()

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
			session.selectedConfiguration = run.selectedConfigurationName
			session.xcodeDestinations = run.xcodeDestinations
			session.breakpoints = debug.breakpointsToRemember()
			sessions.store(session, for: current)
			// And beside the project, so tomorrow's window opens on today's
			// files: what was open is a property of the project, not of the
			// application that happened to be running.
			try? SessionStore.write(session, in: current)
			// Its language servers stay running. Switching back has to be
			// instant, and stopping one costs a re-index — see 0427, where that
			// is decided and what it costs is written down.
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
		session.selectedConfiguration = run.selectedConfigurationName
		session.xcodeDestinations = run.xcodeDestinations
		session.breakpoints = debug.breakpointsToRemember()
		try? SessionStore.write(session, in: root)
	}

	private func setPanelVisible(_ visible: Bool) {
		guard visible != isPanelVisible else { return }

		// **This used to be `setTerminalSelected(visible)`, and that was the
		// reported fault.** The panel being open lit the *terminal* button, so a
		// window showing the backlog had the terminal lit and the backlog not.
		// The rail now asks which panes are in front, which is empty while the
		// panel is closed — so closing it still unlights the group, by the rule
		// rather than by a special case.
		defer { updateRailForPanel() }

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

	/// Edit ▸ Toggle Comment, which is ⌘/.
	///
	/// The work is `CodeView.toggleLineComment()` and through it `LineComment`;
	/// the only thing that happens here is the refusal, because saying something
	/// needs the window's corner and the code view does not have one.
	///
	/// **The refusal is said every press, not once per file.** A stylesheet has no
	/// line comment and never will, and remembering that it had already been
	/// mentioned would make the second ⌘/ the silent keystroke this is here to
	/// avoid — which is the worst of the three ways to answer a gesture a language
	/// cannot do.
	@objc func toggleLineComment(_ sender: Any?) {
		guard let codeView = editor.activeGroup?.activeCodeView else { return }
		say(codeView.toggleLineComment())
	}

	/// The refusal, out loud. Split out so the menu item and the driver that
	/// exercises it produce the same sentence rather than two that can drift.
	private func say(_ outcome: LineComment.Outcome) {
		guard case let .unavailable(reason) = outcome else { return }
		notify("Nothing was commented out", detail: reason, kind: .information)
	}

	/// Presses ⌘/ over the caret or selection a spec names, and says what came of
	/// it — which way it went, the sentence a refusal produces, and where the
	/// selection ended up. `--comment 3:5` or `--comment 3@8`.
	func toggleCommentForTesting(_ spec: String) {
		guard let (outcome, report) = editor.toggleCommentForTesting(spec) else {
			print("COMMENT \(spec): no editor")
			return
		}
		say(outcome)
		switch outcome {
		case let .toggled(toggle):
			print("COMMENT \(spec) \(toggle.commenting ? "commented" : "uncommented") — \(report)")
		case .nothing:
			print("COMMENT \(spec) nothing to do — \(report)")
		case let .unavailable(reason):
			print("COMMENT \(spec) refused: \(reason)")
		}
		fflush(stdout)
	}

	/// Whether ⌘/ is wired up, which is a different question from whether the
	/// toggle works and the only one the suite cannot answer.
	///
	/// **Not by pressing the key**, and that was tried first. A menu's key
	/// equivalent is matched against the *key window's* responder chain, and a
	/// binary launched from a terminal never becomes key — activation is a request
	/// to the window server that this process is not granted, and it must not be:
	/// stealing focus from whoever is working is worse than not being tested. So a
	/// synthesised ⌘/ came back unhandled with no key window, which is
	/// indistinguishable from a shortcut that is not there. The command palette is
	/// blank in the same launch for the same reason, for every item in the menu.
	///
	/// So the three things that can actually be wrong are checked directly: that
	/// an item carries `/` with ⌘ and nothing else, that its action is the one this
	/// class implements, and that walking up from the first responder reaches
	/// something that answers to it. Given those three, AppKit's own routing is
	/// what carries the press, and it carries every other item in the same menu.
	///
	/// **Those three were not enough**, and 0479 is what they missed. All three
	/// were satisfied on a German keyboard — the item was there, the mask was ⌘
	/// alone, the chain answered — while no press a person could make reached it:
	/// the system had moved the shortcut from `/` to ß, and this report printed
	/// `key=ß` without anybody reading it as a shortcut nobody would find. So it
	/// now also says which press matches, from `MenuKeyReport`, because *which key*
	/// is the question and the wiring was never the part that was wrong.
	func commentKeyReportForTesting() {
		let selector = #selector(MainWindowController.toggleLineComment(_:))
		let items = (NSApp.mainMenu?.items ?? [])
			.compactMap(\.submenu)
			.flatMap(\.items)
			.filter { $0.action == selector }

		var chain: [String] = []
		var responder: NSResponder? = window?.firstResponder
		var answers = false
		while let current = responder {
			chain.append("\(type(of: current))")
			if current.responds(to: selector) { answers = true; break }
			responder = current.nextResponder
		}

		for item in items {
			print("COMMENTKEY item “\(item.title)” in “\(item.menu?.title ?? "?")” "
				+ "key=\(item.keyEquivalent) modifiers=\(item.keyEquivalentModifierMask.rawValue) "
				+ "command-only=\(item.keyEquivalentModifierMask == [.command])")
		}
		if items.isEmpty { print("COMMENTKEY no menu item performs toggleLineComment:") }
		print("COMMENTKEY responder chain answers=\(answers) via \(chain.joined(separator: " → "))")
		if let layout = KeyboardLayout.current() {
			let sweep = MenuKeyReport.findings(in: NSApp.mainMenu, layout: layout)
				.filter { finding in items.contains { $0.title == finding.title } }
			for finding in sweep {
				print("COMMENTKEY on “\(layout.name)” the menu says \(finding.shortcut), "
					+ "and it is pressed as "
					+ (finding.presses.isEmpty ? "NOTHING" : finding.presses.joined(separator: " or ")))
			}
		}

		// And then each of those presses, at the real menu bar, with the text watched
		// either side of it. The sweep says a press *matches*; this says the match
		// reaches the editor and changes the file, which is the question somebody
		// asking "does ⌘/ work" is actually asking. Everything but the window
		// server's own delivery is in this path.
		//
		// Every press rather than the first, because they are not the same key: on a
		// German keyboard ⌘⇧7 is the slash on the main block and ⌘/ is the one on the
		// numeric keypad, and somebody who reaches for the keypad is asking a
		// question the first press cannot answer.
		if let item = items.first {
			for (name, event) in MenuKeyReport.presses(reaching: item) {
				let before = editor.editorTextForTesting()
				let handled = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
				let after = editor.editorTextForTesting()
				print("COMMENTKEY \(name) at the real menu: answered "
					+ "\(handled ? "it" : "NOTHING") and the text "
					+ "\(before == after ? "DID NOT CHANGE" : "changed")")
			}
		}
		fflush(stdout)
	}

	func setFindQuery(_ query: String) { editor.setFindQuery(query) }

	func setProjectSearchQuery(_ query: String) {
		results.showProjectSearch(query: query)
	}

	/// Works the search results the way somebody working through them does, and
	/// says what the list holds afterwards.
	///
	/// Recursive around `settle` for the same reason `treeStepsForTesting` is:
	/// the search itself streams in on the main queue, and a nested
	/// `RunLoop.run(until:)` here would wait without ever letting a batch land.
	func searchStepsForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		guard let pane = bottomPanel.existingSearchPane else {
			print("SEARCH: no results pane")
			return
		}
		for (index, step) in script.enumerated() {
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.0
					: 1.0
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.searchStepsForTesting(rest)
				}
				return
			}
			// ⌘Z the way the Edit menu sends it — at nobody in particular, down
			// the chain from whatever has the keyboard. Which of the window's undo
			// stacks answers is decided there and nowhere else, so asking the pane
			// directly would be answering the easier question.
			if step == "undo-key" || step == "redo-key" {
				NSApp.activate(ignoringOtherApps: true)
				window?.makeKeyAndOrderFront(nil)
				let selector = Selector((step == "undo-key" ? "undo:" : "redo:"))
				var responder = window?.firstResponder
				while let hop = responder, !hop.responds(to: selector) { responder = hop.nextResponder }
				func named(_ object: Any?) -> String {
					object.map { String(describing: type(of: $0)) } ?? "nobody"
				}
				print("SEARCH \(step): chain=\(named(responder)) "
					+ "appkit=\(named(NSApp.target(forAction: selector))) "
					+ "first=\(named(window?.firstResponder))")
				if !NSApp.sendAction(selector, to: nil, from: nil) {
					_ = responder?.tryToPerform(selector, with: nil)
				}
				continue
			}
			// ⇧⌘F again, which is the only way to ask where the *next* search
			// answers. The claim item 506 has to make about remembering is about
			// the next question and not about this pane, so a step that moved the
			// pane would be checking something else.
			if step == "again" {
				findInProject(nil)
				continue
			}
			// What the *editor* is showing after the row the walk has landed on,
			// which is the whole of item 533 and is a question about the other half
			// of the window. Between two `down`s it says whether the match the
			// selection moved onto is on the screen, and whether the view moved to
			// put it there.
			if step == "shown" {
				print("SEARCH shown: \(editor.revealReportForTesting)")
				fflush(stdout)
				continue
			}
			pane.stepForTesting(step)
		}
	}

	@objc func findNext(_ sender: Any?) { editor.findNext() }
	@objc func findPrevious(_ sender: Any?) { editor.findPrevious() }

	@objc func findInProject(_ sender: Any?) {
		// No `setPanelVisible(true)` here since item 506: the panel is one of
		// four homes now, and showing it for a search that is about to appear
		// under the project view is a panel opening for nothing.
		//
		// Seed from the selection, which is what you usually want to search for.
		results.showProjectSearch(query: editor.selectedTextForSearch())
	}

	// MARK: - Go

	@objc func goRun(_ sender: Any?) { runGo(.run) }
	@objc func goBuild(_ sender: Any?) { runGo(.build) }
	@objc func goTest(_ sender: Any?) { runGo(.test) }
	@objc func goTrace(_ sender: Any?) { runGo(.trace) }
	@objc func goProfile(_ sender: Any?) { runGo(.profile) }
	@objc func goDebug(_ sender: Any?) { runGo(.debug) }

	/// Draws the pending debug.breakpoints in the gutter, which is what makes a
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

	/// Moves the debug.breakpoints in a file with the text they were put on.
	///
	/// Typing above a breakpoint used to leave it on its line number while the
	/// code moved out from under it — so it stopped somewhere nobody had asked
	/// it to. A breakpoint on a line that is deleted goes with it.
	private func moveBreakpoints(inFile url: URL, editedFrom first: Int, removed: Int, inserted: Int) {
		guard removed != inserted else { return }
		let path = FilePath.canonical(url)
		let list = debug.breakpoints(inFile: path)
		guard !list.isEmpty else { return }

		debug.replaceBreakpoints(inFile: path, with: list.compactMap { breakpoint in
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
		debug.scheduleAnchoring(inFile: url)
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
					presentGoError("Could not find `dlv`. Install Delve with: go sidebar.install github.com/go-delve/delve/cmd/dlv@latest")
					return
				}
				run.startNativeDebugger(delve: delve, package: package)
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

	/// Connects a session to the window, whichever debugger is behind it.
	///
	/// Every way of starting one goes through here. Wiring it at the Go entry
	/// point instead meant a session started any other way ran perfectly and
	/// told the editor nothing: no execution marker, no breakpoint state.
	func wire(_ session: DebugSession) {
		session.onHotSwap = { [weak self, weak session] event, wasStopped in
			guard let self, let session else { return }
			self.run.reportHotSwap(event, wasStopped: wasStopped, in: session)
		}
		session.onBreakpointsChanged = { [weak self, weak session] in
			guard let self, let session else { return }
			self.debug.syncBreakpointsToEditor(from: session)
		}
		// The values, on every stop and every frame change — the pane rebuilds
		// its tree from the same callback, and the editor draws the same numbers
		// at the ends of the lines that name them.
		session.observeVariables { [weak self, weak session] in
			self?.editor.setInlineValues(session?.inlineValues)
		}
		// Opening one asks the adapter for its children, by the reference it
		// gave — the same request the panel's tree makes, from the one function
		// that makes it.
		editor.setVariableChildren { [weak session] reference in
			await session?.variables(reference: reference) ?? []
		}
		session.observeStopped { [weak self] file, line in
			guard let self else { return }
			// Room to see it, before opening it. Stopping somewhere is the one
			// moment the editor has to be visible, and the panel is often not
			// merely tall but the whole window.
			self.makeRoomForTheEditor()
			self.debug.executionMarker = (file, line)
			self.editor.open(fileURL: URL(fileURLWithPath: file), atLine: line)
			self.editor.setExecutionLocation(file: file, line: line)
		}
		toolStrip.setDebugRunning(true)
		session.observeState { [weak self, weak session] state in
			self?.toolStrip.setDebugRunning(state != .idle && state != .terminated)
			self?.run.updateRunControl(for: state, session: session)
			// The marker must go when execution resumes or the process ends.
			switch state {
			case .running, .terminated, .idle:
				self?.debug.executionMarker = nil
				self?.editor.setExecutionLocation(file: nil, line: nil)
				// A value that was true at the last breakpoint is not true a
				// microsecond after `continue`, and it is drawn in the same grey
				// either way.
				self?.editor.setInlineValues(nil)
			default:
				break
			}
		}
		debug.syncBreakpointsToEditor(from: session)
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

	/// Says what the Cadova pane in the tab in front is doing, once a second.
	///
	/// Over time rather than once, because what 0499 claims is a *sequence*: a
	/// pane that says `building`, then `model` with a file beside it, and then —
	/// when somebody changes a constant and saves — `building` and `model` again
	/// with the run count one higher. A single reading cannot tell any of that
	/// from a pane that was showing a model all along. Flushed for the reason
	/// below.
	func watchCadovaForTesting(seconds: Double) {
		for second in 0...Int(seconds) {
			DispatchQueue.main.asyncAfter(deadline: .now() + Double(second)) { [weak self] in
				guard let self else { return }
				guard let pane = self.editorForTesting.cadovaPreview else {
					// **Never a bare "not found".** 0499 was watched green and shipped
					// broken because this line said only `no cadova pane in the tab in
					// front`, which is consistent with the pane being missing, with the
					// tab in front being some other file, and with there being no tab at
					// all — and the first of those was assumed. What the tab in front
					// *is* costs one line and tells the three apart.
					let groups = self.editorForTesting.groups
					let described = groups.isEmpty
						? "no editor group"
						: groups.map(\.activeTabDescriptionForTesting).joined(separator: " | ")
					print("CADOVA: \(second)s no cadova pane — \(described)")
					fflush(stdout)
					return
				}
				print("\(second)s \(pane.reportForTesting)")
				fflush(stdout)
			}
		}
	}

	/// Says where the diagram pane in the tab in front puts its message and its
	/// indicator, once a second.
	///
	/// 0512's instrument. A diagram pane goes through its states in the seconds
	/// after a file opens — a message with nothing turning, then the indicator
	/// over it while a tool runs, then a picture — and the claim the item makes
	/// is about the two rectangles at every one of them, so this prints them all
	/// rather than whichever moment a screenshot happened to catch. Flushed for
	/// the reason `--cadova-watch` is: a driver run ends in a kill, and a report
	/// still in stdout's buffer when the signal arrives never happened.
	func watchDiagramForTesting(seconds: Double) {
		for second in 0...Int(seconds) {
			DispatchQueue.main.asyncAfter(deadline: .now() + Double(second)) { [weak self] in
				guard let self else { return }
				guard let pane = self.editorForTesting.activeGroup?.diagramPreview else {
					// Never a bare "not found", for the reason above it: what the tab
					// in front *is* costs one line and tells three different failures
					// apart.
					let groups = self.editorForTesting.groups
					let described = groups.isEmpty
						? "no editor group"
						: groups.map(\.activeTabDescriptionForTesting).joined(separator: " | ")
					print("DIAGRAM: \(second)s no diagram pane — \(described)")
					fflush(stdout)
					return
				}
				print("\(second)s \(pane.reportForTesting)")
				fflush(stdout)
			}
		}
	}

	/// Shows the backlog: the list and the board, over `.abydos/backlog`.
	@objc func showBacklog(_ sender: Any?) {
		setPanelVisible(true)
		guard bottomPanel.showBacklog() != nil else {
			notify("No project is open", detail: "A backlog lives beside a project, in .abydos/backlog.")
			return
		}
	}

	/// Chooses which of the dashboard's two presentations is showing.
	///
	/// Only for `--backlog list|board`, which is how the two are photographed
	/// without a click. The segmented control is how anybody else gets there.
	func showBacklogMode(list: Bool) {
		bottomPanel.showBacklog()?.showList(list)
	}

	/// Which record the pane shows, for `--backlog openspec`.
	func showBacklogSource(openSpec: Bool) {
		bottomPanel.showBacklog()?.showOpenSpec(openSpec)
	}

	/// What is on the board and what the archive holds, for `--backlog openspec`.
	func backlogBoardReportForTesting() -> String {
		bottomPanel.showBacklog()?.boardReportForTesting ?? "no project"
	}

	/// Whether the first card of a column can be dragged.
	///
	/// By the column's name, which the pane resolves against whichever record is
	/// showing — the two no longer share a vocabulary, so `BacklogState` is the
	/// wrong thing to parse it into here.
	func backlogDragReportForTesting(state: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.dragReportForTesting(column: state)
	}

	/// What the pane offers a project with no record of work, for
	/// `--backlog-offer`.
	func backlogOfferReportForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.offerReportForTesting ?? "no offer: this project has a record of work"
	}

	/// The same, of a pane already open, **without showing it**.
	///
	/// `showBacklog()` reloads on the way past, so a report that asks through it
	/// cannot tell a pane that keeps itself up to date from one that is re-read
	/// by being asked. This is the question somebody sitting in front of the
	/// pane is asking: has it noticed yet, on its own?
	func backlogOfferAsItStandsForTesting() -> String {
		guard let pane = bottomPanel.existingBacklogPane else { return "no pane is open" }
		return pane.offerReportForTesting ?? "no offer: this project has a record of work"
	}

	/// Presses the OpenSpec offer, for `--backlog-offer openspec`.
	///
	/// Through the pane's own verb, so what is driven is what the button does
	/// and not a second path to the same command.
	func pressOpenSpecOfferForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		pane.setUpOpenSpec()
		return OpenSpec.commandLine() == nil
			? "refused, because openspec is not installed"
			: "ran \(OpenSpec.initCommand()) in a terminal"
	}

	/// What a card's context menu offers, for `--backlog-menu`.
	func backlogMenuForTesting(number: Int) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.menuTitlesForTesting(number: number)
	}

	/// The same for a change, which is named rather than numbered.
	func backlogMenuForTesting(change: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.menuTitlesForTesting(change: change)
	}

	/// Files an item from the pane and says where it landed, for `--backlog-new`.
	func newBacklogItemForTesting(titled title: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.newItemForTesting(titled: title)
	}

	/// Whether the pane is offering to make a backlog, and then making one.
	func backlogAbsentForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.isOfferingToMakeOneForTesting ? "offering to make one" : "showing a backlog"
	}

	func makeBacklogForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.makeBacklogForTesting()
	}

	/// Picks up the lowest-numbered ready item without opening the board first.
	///
	/// Worth its own command: once a backlog is in the habit of being worked
	/// this way, "start the next thing" is the whole of what somebody wants
	/// from it, and making them look at a board to press one button is making
	/// them look at a board.
	@objc func startNextBacklogItem(_ sender: Any?) {
		guard let root = project?.root else {
			notify("No project is open", detail: "A backlog lives beside a project, in .abydos/backlog.")
			return
		}
		let backlog = Backlog(projectRoot: root)
		guard backlog.exists else {
			notify(
				"This project has no backlog",
				detail: "Run `abydos-backlog init` in \(root.lastPathComponent) to make one."
			)
			return
		}
		guard let item = BacklogRunner.next(in: backlog) else {
			notify("Nothing is ready", detail: "Move an item into ready/ before an agent can pick it up.")
			return
		}

		setPanelVisible(true)
		bottomPanel.onBacklogNotice = { [weak self] title, detail in self?.notify(title, detail: detail) }
		bottomPanel.startBacklogItem(item)
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
				let root = git.root
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
		let root = git.root

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

	/// What the chevron beside the panel's + offers.
	///
	/// The kinds of terminal there are: an ordinary one, and one inside each
	/// container this project says it can be worked on in. The + itself goes on
	/// making the ordinary one, exactly as the play button goes on running while
	/// the chevron beside it offers profiling and coverage — the same shape and
	/// the same bargain, because it is the same gesture.
	///
	/// **This is the menu the several-devcontainer refusal was waiting for.** A
	/// project with `.devcontainer/alpine` beside `.devcontainer/go` was refused
	/// whole, because picking one quietly is picking somebody's toolchain for
	/// them and there was nowhere to ask. There is now, so both are here, each
	/// named after itself.
	///
	/// Every item is the menu bar's own: the same selectors, put through the same
	/// `validateMenuItem`, so what the View menu offers and what this offers
	/// cannot drift apart, and a devcontainer entry is greyed out here for the
	/// projects it is greyed out for there.
	private func newTerminalMenu() -> NSMenu {
		let menu = NSMenu()
		// Validated by hand below, item by item: left to itself AppKit asks the
		// responder chain, and a menu popped up from a view in the panel is not
		// always where this window is.
		menu.autoenablesItems = false

		let plain = NSMenuItem(
			title: "New Terminal", action: #selector(newTerminal(_:)), keyEquivalent: ""
		)
		plain.target = self
		menu.addItem(plain)

		let choices = devContainerChoices
		// One grey generic entry when there is nothing to name, so that the menu
		// says by being grey which projects this is for rather than by being
		// absent.
		for item in choices.isEmpty ? [makeContainerMenuItem(for: nil)] : choices.map(makeContainerMenuItem) {
			item.target = self
			// This is what names it after the container as well as what greys it
			// out — the item says "New Terminal in <the devcontainer's own name> ⬢"
			// for a project that has one, and stays grey and generic for the rest.
			item.isEnabled = validateMenuItem(item)
			menu.addItem(item)
		}
		return menu
	}

	/// Shows the panel and nothing else, so the strip has a layout to be asked
	/// about.
	///
	/// Deliberately not "open a terminal": the first terminal in a window
	/// attaches to tmux, and a window that is following its terminal then goes
	/// to wherever that session left its shell — a different project, with a
	/// different answer about devcontainers, which is what this dump is for.
	func showTerminalPanelForTesting() { setPanelVisible(true) }

	/// What that menu holds, for the harness: a menu cannot be photographed
	/// while it is open, which is why these dumps exist.
	func newTerminalMenuForTesting() -> String {
		newTerminalMenu().items
			.map { "\($0.title) enabled=\($0.isEnabled)" }
			.joined(separator: " | ")
	}

	/// A shell inside the container this project says it is worked on in.
	///
	/// The container is started if it is not up and reused if it is — which is
	/// what makes the second terminal, and coming back to the project, instant.
	/// Everything that can go wrong says what it was in one sentence rather than
	/// opening a shell somewhere half-configured: 0424 is explicit that a
	/// container missing what the file asked for looks like a broken editor.
	///
	/// **The tab opens now, not when it is ready.** The first time, this is a
	/// pull or a Dockerfile build and then everything the file asks to have run
	/// once the container exists, which together are minutes; a pane that stays
	/// empty for that long and then produces a prompt is a feature that looks
	/// like a hang. So the tab appears at once, the work is written into it, and
	/// that same pane becomes the shell — see `PreparingTerminal`.
	@objc func newTerminalInContainer(_ sender: Any?) {
		// The same root the menu item was enabled and named by, so that what is
		// started is what was clicked. Falling back to the scope when there is no
		// devcontainer anywhere keeps the "no devcontainer.json" message below,
		// which names the folder it looked in.
		guard let root = devContainerRoot ?? scopeRoot else { return }
		// Which of them was clicked. The item carries its own choice, because a
		// project offering two containers has two entries and the title is not
		// something an action can act on; nothing carrying one — the View menu's
		// single item, the harness — means the preferred one.
		let choice = choice(carriedBy: sender) ?? devContainerChoices.first
		setPanelVisible(true)
		// Named before anything is started, from the same file the menu item is
		// named from, so the tab is called what was clicked from the moment it
		// appears rather than being renamed under somebody at the end.
		let preparing = bottomPanel.newPreparingTerminal(
			title: Self.containerTabTitle(for: choice, in: root), subject: root.lastPathComponent
		)
		guard let choice else {
			preparing.refuse(
				"\(root.lastPathComponent) has no devcontainer.json — a project says what it "
					+ "needs to be worked on in .devcontainer/devcontainer.json."
			)
			return
		}
		preparing.step("Opening \(root.lastPathComponent) in \(choice.name)…")

		Task { @MainActor in
			guard let runtime = ContainerRuntime.discover(
				preference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
					?? .automatic
			) else {
				preparing.refuse(
					"Opening a project in its devcontainer needs a container runtime, and neither "
						+ "Docker nor Apple's `container` was found on this machine."
				)
				return
			}
			let outcome = await DevContainers.shared.session(
				for: choice.file,
				in: root,
				using: runtime,
				progress: preparing.progress
			)
			switch outcome {
			case let .refused(reason):
				preparing.refuse(reason)
			case let .running(session):
				// A terminal is an attach, which is the moment `postAttachCommand`
				// names. Not waited for: it is the one lifecycle command whose job
				// is to greet somebody, and a shell that opens a second later
				// because of it is worse than one that opens now.
				Task { await DevContainers.shared.attach(to: session) }
				preparing.becomeShell(running: DevContainers.terminalCommand(session))
			}
		}
	}

	/// How long something nobody asked to watch may take before the panel is
	/// opened to show it happening.
	///
	/// **Nobody asked for a pane here**, which is what the number is for. The
	/// language servers start a container because a file was opened, and a warm
	/// start is `docker run` and an attach — a second or two, after which a panel
	/// that had shown itself would be a panel that opened for nothing and has to
	/// be put away by hand. Past this, the thing being waited for is a pull, a
	/// build or a `postCreateCommand`, all of which are minutes, and minutes of
	/// silence is the complaint 0444's part 4 comes from.
	///
	/// The same number governs an image being fetched or built (0459), and for the
	/// same arithmetic rather than by analogy: an image already on the machine is
	/// answered for in milliseconds, and one that is not is a gigabyte or a
	/// compiler.
	private static let containerBuildRevealDelay: TimeInterval = 3

	/// A pane for a devcontainer that is being brought up for this project's
	/// language servers, or nil when no window is showing that project.
	///
	/// **Found by project rather than told to a window**, because the caller is
	/// `LanguageService`, which has no window: it starts containers for whichever
	/// project a file was opened in, from `warmUp`, which runs while the window is
	/// still being built. Nil is an ordinary answer and means the toasts that were
	/// there before.
	static func watchDevContainerStarting(
		project: URL, choice: DevContainerFile.Choice
	) -> PreparingTerminal? {
		let root = FilePath.canonical(project)
		let window = NSApp.windows.lazy
			.compactMap { $0.windowController as? MainWindowController }
			.first { $0.devContainerRoot.map(FilePath.canonical) == root }
		return window?.watchDevContainerStarting(choice: choice)
	}

	/// The same, for the window that is showing the project.
	///
	/// **The panel is not opened yet**, and that is the one decision here. The tab
	/// is made at once so that everything the start says is in it from the first
	/// line — there is no second chance at the output of a `docker build` — but a
	/// panel that shows itself is a panel that moved under somebody who was
	/// reading a file, so it waits to see whether there is anything worth showing.
	/// The keyboard is never touched either way: `takesFocus` is false, so even
	/// the shell this becomes leaves the editor where it was.
	private func watchDevContainerStarting(choice: DevContainerFile.Choice) -> PreparingTerminal {
		let root = devContainerRoot ?? choice.file.deletingLastPathComponent()
		let preparing = paneThatOpensLate(
			title: Self.containerTabTitle(for: choice, in: root),
			subject: root.lastPathComponent
		)
		preparing.step("Starting \(root.lastPathComponent) in \(choice.name)…")
		return preparing
	}

	/// A pane for an image being fetched or built for this project, or nil when
	/// no window is showing that project.
	///
	/// The same shape as `watchDevContainerStarting`, found the same way and for
	/// the same reason: the caller is `LanguageService` or a diagram, neither of
	/// which has a window, and the project is the only thing either of them knows
	/// that a window can be found by. Nil means the toast that was there before.
	///
	/// Either root, because either is what somebody would call this project: a
	/// language server is started for a subproject when one is open, and a
	/// diagram is exported against the project as a whole.
	static func watchImageArriving(
		project: URL, title: String, subject: String
	) -> PreparingTerminal? {
		let root = FilePath.canonical(project)
		let window = NSApp.windows.lazy
			.compactMap { $0.windowController as? MainWindowController }
			.first { controller in
				[controller.scopeRoot, controller.project?.root]
					.compactMap { $0 }
					.contains { FilePath.canonical($0) == root }
			}
		return window.map { $0.paneThatOpensLate(title: title, subject: subject) }
	}

	/// A pane for work nobody asked to watch: the tab is made now and shown
	/// later, or never.
	///
	/// **The panel is not opened yet**, and that is the one decision here. The tab
	/// is made at once so that everything the work says is in it from the first
	/// line — there is no second chance at the output of a `docker build` — but a
	/// panel that shows itself is a panel that moved under somebody who was
	/// reading a file, so it waits to see whether there is anything worth showing.
	/// The keyboard is never touched either way: `takesFocus` is false, so even a
	/// shell this becomes leaves the editor where it was.
	///
	/// One method for both the devcontainer coming up and the image arriving,
	/// because the terms are one decision rather than two that happen to agree —
	/// 0444 settled them and 0459 took them unchanged, and two copies would be two
	/// things to keep in step.
	private func paneThatOpensLate(title: String, subject: String) -> PreparingTerminal {
		let preparing = bottomPanel.newPreparingTerminal(
			title: title, subject: subject, takesFocus: false, select: false
		)
		// Work too quick to have been watched takes its tab away again rather than
		// leaving a pane nobody asked for — see `vanishesUnlessRevealed`, where the
		// arithmetic of one tab per session is written down.
		preparing.vanishesUnlessRevealed = true
		preparing.onRefused = { [weak self, weak preparing] in
			preparing?.reveal()
			self?.setPanelVisible(true)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.containerBuildRevealDelay) {
			[weak self, weak preparing] in
			// Still going: work that finished while nobody was looking has nothing
			// left to show, and a tab that was closed meanwhile is somebody saying
			// they do not want to watch.
			guard let preparing, preparing.isOpen, !preparing.isDone else { return }
			preparing.reveal()
			self?.setPanelVisible(true)
		}
		return preparing
	}

	/// The choice a menu item is carrying, if it is carrying one.
	private func choice(carriedBy sender: Any?) -> DevContainerFile.Choice? {
		guard let file = (sender as? NSMenuItem)?.representedObject as? URL else { return nil }
		return devContainerChoices.first { $0.file == file }
	}

	/// What the tab in the container is called.
	///
	/// The devcontainer's own `name`, which is what the menu item that opens it
	/// says too — a window scoped to one subproject of ten that each have a
	/// devcontainer cannot say which one it means by saying "container", and
	/// neither can a project offering two of them. The folder the file sits in is
	/// the answer when it has no name of its own.
	static func containerTabTitle(for choice: DevContainerFile.Choice?, in root: URL) -> String {
		"\(containerName(for: choice, in: root)) \(containerMark)"
	}

	/// The mark of working inside a container.
	///
	/// Written once, because three things wear it and they have to be the same
	/// character: the terminal tab whose shell is in there, the menu item that
	/// opens one, and — since 0444 took the name off it — the whole of what the
	/// titlebar's pill shows.
	static let containerMark = "⬢"

	/// The same name without the `⬢`.
	///
	/// The hexagon is the mark of being *inside* — it is on the tab whose shell
	/// is in the container — so the titlebar pill wears it only while this
	/// project's tools are in there, and the dimmed pill for a container that is
	/// not in use does not (0438).
	static func containerName(for choice: DevContainerFile.Choice?, in root: URL) -> String {
		choice?.name ?? root.lastPathComponent
	}

	/// Where the devcontainer this window would open is, or nil when there is
	/// none to open.
	///
	/// **The subproject wins.** A repository of subprojects with a devcontainer
	/// each is not an unusual shape — `abydos-examples` is exactly that, and is
	/// the repository the examples live in — and the part somebody is working in
	/// is the part they mean. Asking `project?.root` alone made every one of
	/// those invisible to the menu.
	///
	/// The project root is still the answer when the subproject has none, which
	/// is every ordinary project and every subproject of one that carries the
	/// container for the whole repository.
	var devContainerRoot: URL? {
		if let subprojectRoot, DevContainerFile.exists(in: subprojectRoot) { return subprojectRoot }
		guard let root = project?.root, DevContainerFile.exists(in: root) else { return nil }
		return root
	}

	/// Whether this project has a devcontainer at all, which is what the menu
	/// item is enabled by.
	var hasDevContainer: Bool { devContainerRoot != nil }

	/// Every devcontainer this window can offer, named, in the order they are
	/// preferred.
	///
	/// Usually one. A project with `.devcontainer/alpine` beside
	/// `.devcontainer/go` has two, which used to refuse the project outright for
	/// want of anywhere to ask which one somebody meant.
	var devContainerChoices: [DevContainerFile.Choice] {
		guard let root = devContainerRoot else { return [] }
		return DevContainerFile.choices(in: root)
	}

	/// What the item is called when there is no container of ours to name.
	static let containerTerminalTitle = "New Terminal in Container"

	/// What a menu item says it will open.
	///
	/// Named after the container, exactly as the tab it opens is: a window
	/// scoped to one subproject of ten that each have a devcontainer cannot say
	/// which one it means by saying "Container", and neither can a project
	/// offering two at once. The devcontainer's own `name` is what the tab shows,
	/// so it is what this shows too, and the folder the file sits in is the
	/// answer when it has none.
	func devContainerMenuTitle(for choice: DevContainerFile.Choice?) -> String {
		// Nothing carried means the preferred one — which is the View menu's
		// single item, and every project that has only one.
		guard let root = devContainerRoot, let named = choice ?? devContainerChoices.first
		else { return Self.containerTerminalTitle }
		// The tab's own name, so the item and the tab it opens cannot drift.
		return "New Terminal in \(Self.containerTabTitle(for: named, in: root))"
	}

	// MARK: - The devcontainer in the titlebar

	/// What the language servers are doing, for the pill's tool tip.
	///
	/// Nothing at all for a project with none — a folder of Markdown has no
	/// servers to be waiting for, and a line saying so would be an answer to a
	/// question nobody asked.
	/// Presses the pill menu's entry whose words are these.
	@discardableResult
	func pressDevContainerMenuForTesting(_ title: String) -> Bool {
		guard let item = titlebar.devContainerPillMenu().items.first(where: { $0.title == title }),
		      let action = item.action, item.isEnabled
		else { return false }
		NSApp.sendAction(action, to: item.target, from: item)
		return true
	}

	/// What the View menu's single item says it will open.
	///
	/// **It opens the project's preferred devcontainer, and says which one that
	/// is.** A menu item is one command with one title; the alternative — turning
	/// it into a submenu when a project has several — costs the two things that
	/// make the ordinary case right, because AppKit does not send
	/// `validateMenuItem:` to an item that has a submenu, so it could no longer
	/// be renamed after the container it opens nor greyed out by the same rule as
	/// everything else in that menu. So it stays one item, and it does not
	/// disagree with the chevron's menu: it is that menu's first container entry,
	/// with the same title, opening the same container, through the same
	/// selector and the same validation. What it offers is a subset; what it says
	/// is never wrong.
	var devContainerMenuTitle: String { devContainerMenuTitle(for: nil) }

	/// Opens a terminal in the project's devcontainer and says what came back.
	///
	/// Through the menu item's own validation and action, because that is what
	/// the click does: a shell that works when a test calls the kit directly
	/// proves nothing about whether the menu reaches it.
	/// - Parameter which: the devcontainer to open, counting from one in the
	///   order the menu offers them, or nil for the one the View menu's item
	///   opens. A project offering two has to be openable in each, or "both are
	///   in the menu" is all that is ever proved.
	func exerciseDevContainerTerminalForTesting(which: Int? = nil) {
		let choices = devContainerChoices
		let chosen = which.flatMap { $0 >= 1 && $0 <= choices.count ? choices[$0 - 1] : nil }
		let item = makeContainerMenuItem(for: chosen)
		// The root as well as the answer: "there is no devcontainer here" is not
		// actionable without "here", and the project that is open is not always
		// the folder that was asked for. The container's root is printed beside
		// it because it is the subproject's rather than the project's whenever
		// the subproject has one, and the title because that is what somebody
		// reads before clicking.
		let enabled = validateMenuItem(item)
		print("DEVCONTAINER: root=\(project?.root.path ?? "-") "
			+ "scope=\(scopeRoot?.path ?? "-") container=\(devContainerRoot?.path ?? "-") "
			+ "file=\(hasDevContainer) choices=\(choices.count) enabled=\(enabled) "
			+ "title=\(item.title)")
		fflush(stdout)
		guard enabled else { return }
		// Through the item rather than through nil, so that which one was asked
		// for travels the way a click's does.
		item.target = self
		newTerminalInContainer(item)
		waitForContainerShellForTesting(seconds: 0)
	}

	/// The same, once for every devcontainer the project offers, each after the
	/// last has answered.
	///
	/// One at a time rather than all at once, and not on a clock: two shells
	/// coming up together would be two panes racing to be the active one, and
	/// what is being proved here is that a project really can have two containers
	/// up at the same time with somebody typing in each.
	func exerciseEveryDevContainerTerminalForTesting(from index: Int = 1) {
		let count = devContainerChoices.count
		guard index <= count else { return }
		exerciseDevContainerTerminalForTesting(which: index)
		guard index < count else { return }
		afterContainerShellForTesting = { [weak self] in
			self?.exerciseEveryDevContainerTerminalForTesting(from: index + 1)
		}
	}

	/// Waits for the tab to stop being a report and start being a shell, then
	/// types into it.
	///
	/// Asked of the pane rather than counted on a clock, because how long this
	/// takes is not something a number can be right about: a pull is minutes, a
	/// Dockerfile build is minutes, and `postCreateCommand` is however long
	/// somebody else's sidebar.install takes. The tab is there from the first moment
	/// either way — that is the point of it — so what is being waited for is the
	/// shell, and nothing else.
	private func waitForContainerShellForTesting(seconds: Int) {
		let outOfPatience = 180
		if bottomPanel.activeTerminalShowsOutputOnly, seconds < outOfPatience {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
				self?.waitForContainerShellForTesting(seconds: seconds + 1)
			}
			return
		}
		print("DEVCONTAINER: tab=\(bottomPanel.activeTerminalTitle ?? "-") ready after \(seconds)s")
		fflush(stdout)
		sendToTerminal("printf 'IN:%s:%s\\n' \"$(pwd)\" \"$(cat /etc/hostname)\"\n")
		DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
			guard let self else { return }
			for line in self.bottomPanel.terminalTextForTesting.split(separator: "\n")
			where line.contains("IN:") {
				print("DEVCONTAINER: \(line.trimmingCharacters(in: .whitespaces))")
			}
			fflush(stdout)
			let next = self.afterContainerShellForTesting
			self.afterContainerShellForTesting = nil
			next?()
		}
	}

	/// What to do once the shell being waited for has answered, so that a second
	/// container is opened after the first rather than beside it.
	private var afterContainerShellForTesting: (() -> Void)?

	/// Right-clicks in the editor and finds usages of whatever is at the caret.
	/// Renames the symbol at a position, the way somebody would, and says what
	/// happened to the files.
	///
	/// Through the same door the context menu uses, and through the field: the
	/// name really is typed into `RenameField` and committed, so what this drives
	/// is the gesture and not a shortcut past it.
	func exerciseRenameForTesting(line: Int, character: Int, to newName: String) {
		guard let url = editor.activeGroup?.activeTabURL else {
			print("RENAME: no file open")
			return
		}
		renameSymbol(in: url, line: line, character: character)

		DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
			guard let self, let codeView = self.editor.activeGroup?.activeCodeView else { return }
			guard codeView.isRenaming else {
				print("RENAME: no field opened")
				return
			}
			print("RENAME: field open on “\(codeView.renameTextForTesting ?? "")”")
			codeView.commitRenameForTesting(newName)

			DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
				let buffer = self.editor.activeGroup?.activeDocument?.rope.string ?? ""
				print("RENAME: the open buffer "
					+ (buffer.contains(newName) ? "says" : "does not say") + " \(newName)")
				let root = self.project?.scopeRoot
				let hits = root.map { Self.filesContaining(newName, under: $0) } ?? []
				print("RENAME: \(hits.count) files on disk say \(newName)")
				for name in hits.prefix(10) { print("RENAME FILE: \(name)") }
			}
		}
	}

	/// Which files under a directory hold a word. For the driver above only.
	private static func filesContaining(_ word: String, under root: URL) -> [String] {
		guard let walk = FileManager.default.enumerator(
			at: root, includingPropertiesForKeys: nil
		) else { return [] }
		var found: [String] = []
		for case let url as URL in walk {
			guard !url.hasDirectoryPath else { continue }
			guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
			if text.contains(word) { found.append(url.lastPathComponent) }
		}
		return found.sorted()
	}

	func exerciseFindUsagesForTesting(line: Int, character: Int) {
		guard let url = editor.activeGroup?.activeTabURL else { return }
		results.exerciseFindUsagesForTesting(line: line, character: character, in: url)
	}

	/// Everything in this file, or everything in the project.
	@objc func goToSymbolInFile(_ sender: Any?) { results.goToSymbolInFile() }

	@objc func goToSymbolInProject(_ sender: Any?) { results.goToSymbolInProject() }

	/// Puts an agent on what the language server is complaining about.
	///
	/// The same Claude Code that reviews a branch, given one problem instead:
	/// the file, the line, the message, and the instruction to keep the change
	/// to what is wrong. It opens in the panel so the fix can be read, argued
	/// with, and undone like any other edit.
	private func fixWithAI(url: URL, line: Int, diagnostic: LSPDiagnostic) {
		guard let root = project?.root else { return }
		// Canonical on both sides. Subtracting the root from the file only
		// works when the two were reached the same way, and this canonicalised
		// one of them: under `/tmp` or `/var`, both symlinks on macOS, the
		// subtraction did nothing and the agent was told to fix a problem in an
		// absolute path on somebody's machine. Same asymmetry as 0430.
		let relative = FilePath.canonical(url)
			.replacingOccurrences(of: FilePath.canonical(root) + "/", with: "")

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
		bottomPanel.showProfiler(address: RunCoordinator.lastProfilerAddress)
	}

	/// Everywhere the symbol at a position is used.
	///
	/// The server's answer rather than a text search: it knows a `Close` on one
	/// type from a `Close` on another, which grep never will.
	// MARK: - Renaming a symbol

	/// Renaming the symbol at a position, from the offer to the files on disk.
	///
	/// The whole of 0453's gesture, and it is four steps with a decision at each
	/// of the first three:
	///
	///  1. **Is there anything to rename here, and will this server do it?**
	///     Asked before a field appears, because an offer that fails is worse
	///     than an absence.
	///  2. **The name is typed where the old one is** — `RenameField`, over the
	///     symbol, in the text. Not a dialog: the navigator renames a file in
	///     place on its row, and this is that gesture one layer in.
	///  3. **The server is asked**, and what comes back is a description of a
	///     change rather than a change.
	///  4. **The change is worked out in full and then made**, by
	///     `WorkspaceEditPlan` and `WorkspaceEditApplier`, which is where every
	///     hard part of this lives: open documents against closed ones, files
	///     that move, one undo, and what to do when it fails halfway.
	/// Edit ▸ Rename…, which is ⇧F6.
	///
	/// The same gesture the context menu offers, from the caret rather than from
	/// where somebody right-clicked. Silent when there is no file open: a menu
	/// item that does nothing is better than one that says so.
	@objc func renameSymbol(_ sender: Any?) {
		guard let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let url = group.activeTabURL,
		      let position = codeView.caretPositionForRequest()
		else { return }
		renameSymbol(in: url, line: position.line, character: position.character)
	}

	private func renameSymbol(in url: URL, line: Int, character: Int) {
		guard let project,
		      let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let languageId = group.activeDocument?.languageId
		else { return }

		let position = LSPPosition(line: line, character: character)
		let word = codeView.wordAtCaret()
		let fallback = word.map {
			RenameSubject(
				name: $0.text,
				range: LSPRange(
					start: LSPPosition(line: line, character: character),
					end: LSPPosition(line: line, character: character)
				)
			)
		}

		// `[weak self]` on the task and not only on the callback inside it. The
		// callback's weak capture is load-bearing for a different reason — the
		// code view keeps that closure, so a strong one is a cycle — but a task
		// capturing the window controller strongly held it alive for the whole of
		// the `renameOffer` round trip, which is a language server being asked a
		// question over a pipe and can be seconds. A window closed in that gap
		// stayed alive until the server answered, and the answer was then laid
		// over a code view nobody is looking at.
		Task { @MainActor [weak self] in
			// The file's own root, not the scope: a rename is asked of the
			// server that was told about this file, and the scope pill may be
			// pointing at another subproject entirely.
			let offer = await LanguageService.shared.renameOffer(
				url: url, position: position, languageId: languageId,
				project: LanguageService.shared.root(
					for: url, languageId: languageId, project: project.root
				),
				fallback: fallback
			)
			// Closed while the server was being asked. Nothing to say and nowhere
			// to put a field.
			guard let self else { return }

			guard case let .offered(subject) = offer else {
				// Two of the three refusals say nothing at all — no server, and
				// the server's own "nothing here", which is what the caret being
				// on a bracket looks like every time.
				if let refusal = offer.refusal {
					notify("Cannot rename here", detail: refusal, kind: .information)
				}
				return
			}

			// The extent to lay the field over. The server's range where it gave
			// one, since it knows things the editor's idea of a word does not —
			// a Swift `` `default` `` is one symbol and three tokens.
			guard let extent = self.utf16Range(of: subject, in: codeView, fallback: word?.range) else {
				return
			}

			codeView.beginRename(
				utf16Range: extent, name: subject.name, caveat: subject.caveat
			) { [weak self] newName in
				guard let self else { return true }
				self.performRename(
					in: url, position: position, to: newName,
					languageId: languageId,
					project: LanguageService.shared.root(
						for: url, languageId: languageId, project: project.root
					)
				)
				return true
			}
		}
	}

	/// The symbol's extent in the document, from whichever of the two answers
	/// there is.
	private func utf16Range(
		of subject: RenameSubject, in codeView: CodeView, fallback: Range<Int>?
	) -> Range<Int>? {
		guard let document = codeView.document else { return fallback }
		let rope = document.rope
		func offset(_ position: LSPPosition) -> Int? {
			guard position.line >= 0, position.line < rope.lineCount else { return nil }
			let start = rope.utf16Offset(fromByte: rope.byteOffset(ofLine: position.line))
			return start + position.character
		}
		guard let start = offset(subject.range.start), let end = offset(subject.range.end),
		      end > start
		else { return fallback }
		return start..<end
	}

	/// Asks for the edit and makes it.
	private func performRename(
		in url: URL, position: LSPPosition, to newName: String,
		languageId: String, project: URL
	) {
		Task { @MainActor in
			let answer = await LanguageService.shared.rename(
				url: url, position: position, to: newName, languageId: languageId, project: project
			)

			// The sentences live on `RenameAnswer`, where the other rename
			// sentences do, so what is said can be read without a window.
			guard let refusal = answer.refusal else {
				if let edit = answer.edit { self.apply(edit, named: newName) }
				return
			}
			notify(
				refusal.title, detail: refusal.detail,
				kind: refusal.isFailure ? .error : .information
			)
		}
	}

	// MARK: - Copying a place in the code

	/// Copies where somebody is, in the form they asked for.
	///
	/// **Two forms because there are two audiences, and they want different
	/// strings.** An assistant or a terminal wants `path:line`, which needs
	/// nothing but the project root and is openable by `abydos`. A person, and a
	/// bookmark for Monday, wants a permalink pinned to a commit, because a link
	/// into a branch is wrong the next time somebody edits above the line.
	/// Edit ▸ Copy Reference, which is ⌘⇧C.
	@objc func copyReference(_ sender: Any?) { copyLinkFromTheCaret(.reference) }

	/// Edit ▸ Copy Permalink.
	@objc func copyPermalink(_ sender: Any?) { copyLinkFromTheCaret(.permalink) }

	/// The same gesture the context menu makes, from the caret rather than from
	/// where somebody right-clicked. Silent with no file open: a menu item that
	/// does nothing is better than one that says so.
	private func copyLinkFromTheCaret(_ form: CodeView.LinkForm) {
		guard let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let url = group.activeTabURL,
		      let span = codeView.lineSpanForReference()
		else { return }
		copyLink(to: url, form: form, line: span.line, endLine: span.endLine)
	}

	private func copyLink(to url: URL, form: CodeView.LinkForm, line: Int, endLine: Int?) {
		let place = CodePlace(url: url, in: project?.root, line: line, endLine: endLine)

		switch form {
		case .reference:
			copyToPasteboard(place.text)
			notify(
				place.lineCount > 1 ? "Copied \(place.lineCount) lines" : "Copied the reference",
				detail: place.text, kind: .information
			)

		case .permalink:
			Task { @MainActor [weak self] in
				guard let self else { return }
				let found = await GitRepository.discover(from: url.deletingLastPathComponent())
				// Read once and kept, rather than reached for three times.
				guard let root = found?.root else {
					self.notify(
						"No repository to link to",
						detail: "A permalink names a commit, and this file is not in a checkout.",
						kind: .information
					)
					return
				}
				// **Two roots, and they can differ.** The forge serves paths
				// relative to the repository; a reference is relative to the
				// project, which in a monorepo is a directory inside it. Each is
				// right for its own audience.
				let inRepository = CodePlace(url: url, in: root, line: line, endLine: endLine)
				guard let link = await CodeLink.permalink(
					for: inRepository,
					repositoryPath: inRepository.path,
					repository: root
				) else {
					self.notify(
						"Nothing to link to",
						detail: "This checkout has no remote this app recognises, "
							+ "so there is no address to build.",
						kind: .information
					)
					return
				}
				self.copyToPasteboard(link.url.absoluteString)
				// The caveat is the whole point of this path: the two ways a
				// permalink is a dead letter are both invisible to whoever
				// receives it.
				self.notify(
					link.caveat == nil ? "Copied the permalink" : "Copied, with something to know",
					detail: link.caveat ?? link.url.absoluteString,
					kind: link.caveat == nil ? .information : .warning
				)
			}
		}
	}

	/// Edit ▸ Go to Copied Place, which is ⌘⇧V.
	///
	/// **The way in, with no URL scheme to rely on.** A permalink is not
	/// clickable into this app — registering a scheme is its own item — so the
	/// pasteboard is the door: whatever is on it, a reference or one of this
	/// app's permalinks, is opened.
	@objc func goToCopiedPlace(_ sender: Any?) {
		let copied = NSPasteboard.general.string(forType: .string) ?? ""

		// A permalink first, because it is the specific shape: `path:line` would
		// otherwise match the tail of a URL that has a colon and a number in it.
		if let followed = CodeLink.follow(copied) {
			follow(followed)
			return
		}
		guard let place = CodePlace.parse(copied) else {
			notify(
				"Nothing to go to",
				detail: "What is copied is neither a reference like “path:12” nor a permalink.",
				kind: .information
			)
			return
		}
		// **A reference from anywhere else is opened at the number, with nothing
		// inferred.** This app has no idea what that file looked like when the
		// reference was made, and re-finding a line from a guess about its text
		// would be inventing.
		let url = place.url(in: project?.root)
		guard FileManager.default.fileExists(atPath: url.path) else {
			notify("No such file", detail: place.text, kind: .warning)
			return
		}
		editor.open(fileURL: url, atLine: place.line)
	}

	/// Opens one of this app's own permalinks, at the line the text is on now.
	private func follow(_ followed: CodeLink.Followed) {
		Task { @MainActor [weak self] in
			guard let self, let project = self.project else { return }
			let root = await GitRepository.discover(from: project.root)?.root
			guard let root else {
				self.notify(
					"Not a checkout",
					detail: "This link names a commit, and this project is not in a repository.",
					kind: .information
				)
				return
			}
			let file = root.appendingPathComponent(followed.path)
			guard FileManager.default.fileExists(atPath: file.path) else {
				self.notify(
					"That file is not in this project",
					detail: followed.path + " — the link may be for another repository.",
					kind: .warning
				)
				return
			}
			let landing = await CodeLink.land(followed, in: root)
			self.editor.open(fileURL: file, atLine: landing.line)
			// Said only when there is something to say. A destination that
			// quietly differs from the one in the link is worse than a wrong
			// one, because nobody knows to check.
			if let said = landing.said(commit: followed.commit) {
				self.notify("Followed the link", detail: said, kind: .information)
			}
		}
	}

	private func copyToPasteboard(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	/// Switches to a branch the way the titlebar does, and says what came of it
	/// — for `--checkout-branch`.
	///
	/// Through `BranchMenu.checkout`, which is the function the titlebar and the
	/// switcher share, so what is driven is what a click does.
	func checkoutBranchForTesting(_ branch: String, pressing: Bool) {
		guard let root = project?.root else {
			print("BRANCH: no project")
			fflush(stdout)
			return
		}
		let before = toasts.saidForTesting.count
		BranchMenu.checkout(branch, in: root)

		// git and the worktree list are two processes; give them a moment.
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
			guard let self else { return }
			let said = self.toasts.saidForTesting.dropFirst(before)
			print("BRANCH \(branch): \(said.isEmpty ? "nothing said" : said.joined(separator: " / "))")
			Task { @MainActor in
				let on = await BranchMenu.currentBranchForTesting(in: root)
				print("BRANCH \(branch): on \(on ?? "none") in \(root.lastPathComponent)")
				fflush(stdout)
			}
			guard pressing else { return }

			let pressed = self.toasts.pressLastOfferForTesting()
			print("BRANCH pressed: \(pressed)")
			fflush(stdout)
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
				guard let self else { return }
				print("BRANCH after: project=\(self.project?.root.lastPathComponent ?? "none")"
					+ " said=\(self.toasts.saidForTesting.dropFirst(before).joined(separator: " / "))")
				fflush(stdout)
			}
		}
	}

	/// Copies a link the way the menu does, and says what came of it — for
	/// `--copy-link`.
	///
	/// **Through the same call the menu makes**, so what is watched is what the
	/// gesture does: the pasteboard afterwards is the deliverable, and the
	/// sentence beside it is the other half.
	func copyLinkForTesting(_ form: String, line: Int, endLine: Int?) {
		guard let group = editor.activeGroup, let url = group.activeTabURL else {
			print("LINK: nothing open")
			fflush(stdout)
			return
		}
		let said = toasts.saidForTesting.count
		copyLink(
			to: url,
			form: form == "permalink" ? .permalink : .reference,
			line: line, endLine: endLine
		)
		// The permalink asks git, so the answer is a moment away.
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
			guard let self else { return }
			print("LINK copied: \(NSPasteboard.general.string(forType: .string) ?? "nothing")")
			print("LINK said: \(self.toasts.saidForTesting.dropFirst(said).joined(separator: " / "))")
			fflush(stdout)
		}
	}

	/// Puts a link on the pasteboard and follows it, saying where the caret
	/// ended up — for `--follow-link`.
	func followLinkForTesting(_ text: String) {
		copyToPasteboard(text)
		let said = toasts.saidForTesting.count
		goToCopiedPlace(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
			guard let self else { return }
			let where_ = self.editor.activeGroup?.activeCodeView?.caretPositionForRequest()
			print("LINK followed: \(self.editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing")"
				+ " line \(where_.map { $0.line + 1 } ?? -1)")
			print("LINK said: \(self.toasts.saidForTesting.dropFirst(said).joined(separator: " / "))")
			fflush(stdout)
		}
	}

	// MARK: - What a server offers

	/// What a server offers about the caret — ⌥⏎.
	///
	/// **A keystroke and not a mark, and that was measured rather than
	/// preferred.** Asked at every line of a real file, gopls answered something
	/// about 16 lines of 16 and jdtls about 10 of 10; an indicator meaning "there
	/// is something here" would therefore be on every row of every file, which is
	/// an indicator nobody reads. Asking when somebody asks costs one request and
	/// is never noise.
	/// ⌃Space, which is IDEA's and Eclipse's, and what everybody presses.
	@objc func completeAtCaret(_ sender: Any?) {
		editor.completeAtCaret()
	}

	@objc func showCodeActions(_ sender: Any?) {
		offerCodeActions(fileWide: false)
	}

	/// What a server offers about the *file* — organise imports, fix all of a
	/// kind. These have no caret, so they are not in the menu that opens at one.
	@objc func showSourceActions(_ sender: Any?) {
		offerCodeActions(fileWide: true)
	}

	private func offerCodeActions(fileWide: Bool) {
		guard let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let url = group.activeTabURL,
		      let languageId = group.activeDocument?.languageId,
		      let project,
		      let caret = codeView.caretPositionForRequest()
		else { return }

		let position = LSPPosition(line: caret.line, character: caret.character)
		// The file's own root rather than the scope's, the way a rename asks:
		// the server that was told about this file is the one with anything to
		// say about it.
		let root = LanguageService.shared.root(for: url, languageId: languageId, project: project.root)
		// A file-wide question is asked about the whole file rather than about
		// where somebody happens to be standing, and asked with `only`, so a
		// server that can answer it cheaply does.
		let range = fileWide
			? LSPRange(start: LSPPosition(line: 0, character: 0), end: position)
			: LSPRange(start: position, end: position)

		Task { @MainActor [weak self] in
			let offer = await LanguageService.shared.codeActions(
				url: url, range: range, languageId: languageId, project: root,
				only: fileWide ? ["source"] : nil
			)
			guard let self else { return }
			guard let offer else {
				// No server for this file. Silent for the reason a rename is:
				// it is most files in most projects, and what there is to say
				// about a missing server is the strip above the file.
				return
			}

			// `source.*` is about the file: in the caret's menu it would be a
			// list of things that have nothing to do with where somebody is.
			let wanted = offer.actions.filter { fileWide ? $0.isSourceAction : !$0.isSourceAction }
			guard !wanted.isEmpty else {
				self.notify(
					fileWide ? "Nothing to do to this file" : "Nothing on offer here",
					detail: "\(offer.server) offers nothing "
						+ (fileWide ? "about this file." : "about this line."),
					kind: .information
				)
				return
			}

			let menu = self.codeActionMenu(
				wanted, from: offer, url: url, languageId: languageId, project: root
			)
			guard let point = codeView.caretScreenPoint() else { return }
			menu.popUp(positioning: nil, at: NSPoint(x: point.x, y: point.y), in: nil)
		}
	}

	/// The menu of what a server offers, in the server's own words.
	///
	/// **Whatever it offers is what is shown**, unedited and unsorted — the same
	/// rule rename follows. The only thing added is who is talking: 0449 lets a
	/// project choose its server, and a syntactic one's list is shorter and
	/// different in kind. Somebody should be able to tell which they are getting
	/// rather than wondering why the menu changed.
	private func codeActionMenu(
		_ actions: [LSPCodeAction],
		from offer: LanguageService.CodeActionOffer,
		url: URL,
		languageId: String,
		project: URL
	) -> NSMenu {
		let menu = NSMenu()
		for action in actions {
			let entry = NSMenuItem(
				title: action.title,
				action: #selector(takeCodeActionFromMenu(_:)),
				keyEquivalent: ""
			)
			entry.target = self
			entry.representedObject = TakenCodeAction(
				action: action, url: url, languageId: languageId, project: project
			)
			// A server may send an action it will not run, with a reason meant
			// to be read. Shown and not runnable, rather than dropped.
			if let reason = action.disabledReason {
				entry.isEnabled = false
				entry.toolTip = reason
			}
			menu.addItem(entry)
		}
		menu.addItem(.separator())
		let who = NSMenuItem(
			title: offer.isSyntactic
				? "from \(offer.server), which matches names rather than types"
				: "from \(offer.server)",
			action: nil,
			keyEquivalent: ""
		)
		who.isEnabled = false
		menu.addItem(who)
		return menu
	}

	/// One action, and everything needed to carry it out.
	private final class TakenCodeAction: NSObject {
		let action: LSPCodeAction
		let url: URL
		let languageId: String
		let project: URL

		init(action: LSPCodeAction, url: URL, languageId: String, project: URL) {
			self.action = action
			self.url = url
			self.languageId = languageId
			self.project = project
		}
	}

	@objc private func takeCodeActionFromMenu(_ sender: NSMenuItem) {
		guard let taken = sender.representedObject as? TakenCodeAction else { return }
		take(taken)
	}

	/// Carries out one action: resolve it if it arrived empty, apply its edit,
	/// run its command.
	///
	/// **In that order, and all three.** An action may carry an edit *and* a
	/// command — the protocol allows it and jdtls uses it — and doing only the
	/// first half of one is worse than doing neither.
	private func take(_ taken: TakenCodeAction) {
		Task { @MainActor [weak self] in
			guard let self else { return }
			// **Resolved on the way to being applied, never treated as empty.**
			// A server that answers cheaply and fills in the work when asked is
			// the normal case, not the corner one: of 83 actions jdtls offered
			// in the measurement, 81 arrived with nothing in them.
			let action = await LanguageService.shared.resolve(
				taken.action, url: taken.url, languageId: taken.languageId, project: taken.project
			)

			if action.needsResolving {
				self.notify(
					"“\(action.title)” could not be worked out",
					detail: "The server offered it and then had nothing to do for it.",
					kind: .warning
				)
				return
			}

			if let edit = action.edit, !edit.isEmpty {
				self.apply(edit, named: action.title)
			}
			if let command = action.command {
				let taken = await LanguageService.shared.run(
					command, url: taken.url, languageId: taken.languageId, project: taken.project
				)
				// The server may now ask this window to apply an edit, which
				// arrives as `workspace/applyEdit` and is answered there.
				if !taken {
					self.notify(
						"“\(action.title)” was refused",
						detail: "The server would not run it.",
						kind: .warning
					)
				}
			}
		}
	}

	/// Says that this window will carry out the edits servers ask for.
	///
	/// **The same applying a rename uses, and deliberately not a second one.**
	/// An edit arriving through `workspace/applyEdit` touches open documents and
	/// closed files exactly as a rename's does, wants the same single undo entry
	/// and the same refusal when part of it cannot be done — and a second
	/// implementation of that is the one thing 0453 exists to prevent.
	func takeServerEdits() {
		LanguageService.shared.applyEditFromServer = { [weak self] edit, label, answer in
			guard let self else {
				answer(false, "The window the edit was for has closed.")
				return
			}
			let outcome = self.apply(edit, named: label ?? "the server’s edit")
			switch outcome {
			case .applied:
				answer(true, nil)
			case let .refused(reasons):
				answer(false, reasons.joined(separator: " "))
			case let .putBack(failure):
				answer(false, failure)
			case let .halfDone(failure, changed, _):
				// The state this whole design exists to make rare. The server is
				// told `false` — the edit it asked for did not happen as asked —
				// and told which files are not as either side believes.
				answer(false, failure + " Left changed: "
					+ changed.map(\.lastPathComponent).joined(separator: ", "))
			}
		}
	}

	/// Turns a workspace edit into files, and puts one entry on the undo stack
	/// for the whole of it.
	@discardableResult
	private func apply(_ edit: WorkspaceEdit, named newName: String) -> WorkspaceEditApplier.Outcome {
		let files = workspaceEditFiles()
		let plan = WorkspaceEditPlan.make(edit, contents: files.contents, exists: files.exists)

		// Tabs on files that are about to move are closed first, so that nothing
		// auto-saves a buffer back to a path the move has just emptied.
		let reopening = plan.moves.compactMap { move -> (from: URL, to: URL)? in
			editor.document(for: move.from) != nil ? (move.from, move.to) : nil
		}
		for move in reopening { editor.closeTab(showing: move.from) }

		let outcome = WorkspaceEditApplier.apply(plan, to: files)

		for move in reopening where FileManager.default.fileExists(atPath: move.to.path) {
			editor.open(fileURL: move.to)
		}
		navigator.reloadTree()

		if let summary = outcome.summary {
			notify(summary.title, detail: summary.detail, kind: outcome.isUntouched ? .warning : .error)
		}

		guard case let .applied(applied) = outcome, !applied.isEmpty else { return outcome }
		remember(applied, named: newName)
		return outcome
	}

	/// The one undo entry for the whole rename.
	///
	/// One entry however many files it was — the rule `FileUndo` settled for
	/// what the tree does, and this is the editor's version of it. Forty files
	/// renamed and undone forty times is not an undo, and neither is forty
	/// presses that each take back one file's worth of a refactoring that only
	/// makes sense whole.
	///
	/// On the *tree's* undo stack rather than each document's, and that is the
	/// only place it can be: a document's `UndoTree` is that document's history
	/// and knows nothing of the thirty-nine others, and a rename that also moved
	/// a file is not a text edit at all.
	private func remember(_ plan: WorkspaceEditPlan, named newName: String) {
		navigator.rememberWorkspaceEdit(plan, title: "Rename to “\(newName)”") { [weak self] plan in
			guard let self else { return }
			let files = self.workspaceEditFiles()
			// Same shape as applying: the tabs on files that are about to move
			// back are closed first.
			let reopening = plan.moves.compactMap { move -> (from: URL, to: URL)? in
				self.editor.document(for: move.to) != nil ? (move.to, move.from) : nil
			}
			for move in reopening { self.editor.closeTab(showing: move.from) }

			let outcome = WorkspaceEditApplier.reverse(plan, in: files)

			for move in reopening where FileManager.default.fileExists(atPath: move.to.path) {
				self.editor.open(fileURL: move.to)
			}
			self.navigator.reloadTree()
			if let summary = outcome.summary {
				self.notify(summary.title, detail: summary.detail)
			}
		}
	}

	/// The files a workspace edit acts on, in this window.
	///
	/// **This is where an open document stops being a file.** A file with an
	/// editor on it is read from its rope and written through it, so the buffer
	/// and the disk never come to say different things; everything else is read
	/// and written on disk without an editor being made for it, which is what a
	/// rename across five hundred bundles needs.
	private func workspaceEditFiles() -> WorkspaceEditFiles {
		let disk = WorkspaceEditFiles.disk
		return WorkspaceEditFiles(
			contents: { [weak self] url in
				self?.editor.document(for: url)?.rope.string ?? disk.contents(url)
			},
			exists: disk.exists,
			write: { [weak self] url, text in
				guard self?.editor.applyRenamedText(text, to: url) != true else { return }
				try disk.write(url, text)
			},
			move: disk.move,
			trash: disk.trash
		)
	}

	private func findUsages(in url: URL, line: Int, character: Int) {
		guard let project, let languageId = editor.activeGroup?.activeDocument?.languageId else { return }
		results.noteUsagesRequest(url: url, line: line, character: character)

		Task { @MainActor in
			let locations = await LanguageService.shared.references(
				url: url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: LanguageService.shared.root(
					for: url, languageId: languageId, project: project.root
				)
			)
			guard !locations.isEmpty else {
				notify("No usages found", kind: .information)
				return
			}
			// One result is not a list; it is the place to go.
			if locations.count == 1, let only = locations.first, let target = only.url {
				editor.open(
					fileURL: target,
					atLine: only.range.start.line + 1,
					column: only.range.start.character + 1,
					length: only.range.widthOnOneLine
				)
				return
			}
			results.showUsages(
				locations,
				of: symbolName(in: url, line: line, character: character),
				at: "\(url.path):\(line):\(character)"
			)
		}
	}

	/// The word the caret is on, for the heading and the tab.
	///
	/// Read out of the open document rather than asked of the server: the server
	/// has already answered the only question worth a round trip, and a heading
	/// that says "usages of `Close`" is worth more than one that says "usages"
	/// only if it arrives with the list.
	private func symbolName(in url: URL, line: Int, character: Int) -> String {
		guard let text = editor.document(for: url)?.rope.string else { return "" }
		let lines = text.components(separatedBy: "\n")
		guard lines.indices.contains(line) else { return "" }
		let units = Array(lines[line].utf16)
		guard character <= units.count else { return "" }

		func isWord(_ unit: UInt16) -> Bool {
			guard let scalar = Unicode.Scalar(unit) else { return false }
			return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
		}

		var start = min(character, max(0, units.count - 1))
		var end = start
		while start > 0, isWord(units[start - 1]) { start -= 1 }
		while end < units.count, isWord(units[end]) { end += 1 }
		guard end > start else { return "" }
		return String(decoding: units[start..<end], as: UTF16.self)
	}

	// MARK: - Under the project view

	// MARK: - A window of its own

	/// Why the symbol list is empty, in a sentence somebody can act on.
	private func reasonForNoSymbols(query: String, scope: SymbolPalette.Scope) -> String {
		guard let project else { return "No project is open." }
		let status = LanguageService.shared.serverStatus(project: project.scopeRoot)

		// About the file that is open, not about the project. A project with
		// Go and TypeScript in it is missing the TypeScript server whether or
		// not that has anything to do with the Go file on screen — and being
		// told to sidebar.install a TypeScript server while looking at main.go reads
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
			// The server that would have answered about this file, which is the
			// one filed under the file's own root.
			if let failure = LanguageService.shared.failure(
				forLanguage: languageId,
				project: editor.activeGroup?.activeTabURL.map {
					LanguageService.shared.root(for: $0, languageId: languageId, project: project.root)
				} ?? project.scopeRoot
			) {
				return "The \(languageId) language server cannot read this project.\n\(failure)"
					+ "\n\n\(LanguageService.logPath) has the rest."
			}
			// **Definitively, rather than as the hedge this used to be.** "Nothing
			// declared in this file, or the language server is still starting"
			// is two answers in one sentence and neither of them is actionable:
			// the reader cannot tell whether to wait or to go and look at the
			// file. The service knows which it is.
			if let notReady = LanguageService.shared.notReadySentence(
				languageId: languageId,
				project: editor.activeGroup?.activeTabURL.map {
					LanguageService.shared.root(for: $0, languageId: languageId, project: project.root)
				} ?? project.scopeRoot
			) {
				return "\(notReady)\nThis list fills in by itself when it is ready."
			}
			return query.isEmpty
				? "Nothing declared in this file."
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
				.workspaceSymbols(matching: query, project: project.scopeRoot)
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

			// A document's symbols come from the server that was told about that
			// document, which is the one its own root is filed under.
			let all = await LanguageService.shared
				.documentSymbols(
					url: url, languageId: languageId,
					project: LanguageService.shared.root(
						for: url, languageId: languageId, project: project.root
					)
				)
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

	func pushChangesForTesting() { sidebar.changesPane?.pushForTesting() }

	/// Runs the selected configuration and puts the profiler on it.
	func profileSelectedForTesting() { run.profileSelectedConfiguration() }

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
		bottomPanel.showProfiler(address: RunCoordinator.lastProfilerAddress)
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

	// The sub-controllers a driven run reaches, and the only state this class
	// exposes to one. A driving verb is declared on the thing it drives, so what
	// `AppDelegate` needs from the window is which editor, which panel and which
	// navigator — not the fields any of them keep.
	var editorForTesting: EditorAreaController { editor }
	var panelForTesting: BottomPanel { bottomPanel }
	var navigatorForTesting: ProjectNavigatorViewController { navigator }
	var resultsForTesting: ResultsPresenter { results }

	/// Puts the caret on a line of the file being edited, for `:` in the palette.
	func goTo(line: Int) { editor.goTo(line: line) }

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

	/// Presses a mouse button over a named view, and says where the editor
	/// landed — `--mouse 3@editor,4@terminal`.
	///
	/// **The event goes to the view the pointer would be over**, not to the
	/// function it should end up calling. What was broken here was the path
	/// rather than the destination: `navigateBack` worked and nothing reached
	/// it, and the terminal ate the events on the way past. Calling
	/// `navigateBack` from a test would have passed the whole time.
	///
	/// The event is built through a `CGEvent` because that is the only way to
	/// set `buttonNumber` — `NSEvent.mouseEvent` has no parameter for it, and
	/// the number is the entire question. It carries a screen position rather
	/// than one in a window, so the cell a terminal would report it at is not
	/// meaningful; nothing here asks for one, and the side buttons never reach
	/// that code.
	func pressMouseForTesting(_ steps: String) {
		for step in steps.split(separator: ",") {
			let parts = step.split(separator: "@")
			guard let number = Int(parts.first ?? "") else { continue }
			let over = parts.count > 1 ? String(parts[1]) : "editor"
			guard let target = viewForMouseTesting(named: over) else {
				print("MOUSE \(step): there is no \(over) to press over")
				fflush(stdout)
				continue
			}
			pressForTesting(button: number, on: target)
			let place = editor.currentPlace
			print("MOUSE \(step): editor at "
				+ (place.map { "\($0.url.lastPathComponent):\($0.line)" } ?? "nowhere"))
			fflush(stdout)
		}
	}

	/// The views a press can be aimed at, which are the two paths that differ:
	/// the terminal has mouse handlers of its own, and the editor has none and
	/// passes everything up.
	private func viewForMouseTesting(named name: String) -> NSView? {
		switch name {
		case "terminal": return bottomPanel.showTerminal()?.terminalView
		case "tree":     return navigator.view
		default:         return editor.view
		}
	}

	private func pressForTesting(button number: Int, on view: NSView) {
		let middle = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
		let inWindow = view.convert(middle, to: nil)
		let onScreen = view.window?.convertPoint(toScreen: inWindow) ?? .zero
		let flipped = CGPoint(
			x: onScreen.x,
			y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y
		)
		for type in [CGEventType.otherMouseDown, .otherMouseUp] {
			guard let raw = CGEvent(
				mouseEventSource: nil,
				mouseType: type,
				mouseCursorPosition: flipped,
				mouseButton: .center
			) else { continue }
			raw.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
			guard let event = NSEvent(cgEvent: raw) else { continue }
			if type == .otherMouseDown {
				view.otherMouseDown(with: event)
			} else {
				view.otherMouseUp(with: event)
			}
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
			case "shift-down": navigator.pressKeyForTesting(125, modifiers: .shift)
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

	/// Drives the picture in front through the View menu's **own** zoom actions,
	/// one step per word: `in`, `out`, `actual`, `fit`, `pinch:0.25`.
	///
	/// **Down the responder chain rather than by calling the pane**, and that is
	/// the whole reason this verb exists rather than `--image-fit` growing a
	/// number. What item 0537 changes is not arithmetic — `ImageFit` is tested
	/// without a window — it is *where ⌘+ arrives*: the picture pane takes the
	/// keyboard and answers `zoomIn(_:)` before the window controller does. A
	/// driver that called `pane.zoomIn(nil)` would pass with that routing removed,
	/// which makes it a test of nothing. So the report says **who took it**, and
	/// `took=ImageFileView` against `took=MainWindowController` is the whole of
	/// this item in one word.
	///
	/// It also prints the interface's zoom beside the picture's, because the
	/// claim being checked is about two numbers: one moves and the other does not.
	func zoomImageForTesting(_ raw: String) {
		guard let pane = editor.activeGroup?.imagePreview else {
			print("IMAGE: nothing showing a picture")
			return
		}
		window?.makeFirstResponder(pane)
		var took: [String] = []
		for step in raw.split(separator: ",").map({
			$0.trimmingCharacters(in: .whitespaces).lowercased()
		}) {
			switch step {
			case "in":  took.append(sendToKeyboard(#selector(MainWindowController.zoomIn(_:))))
			case "out": took.append(sendToKeyboard(#selector(MainWindowController.zoomOut(_:))))
			case "actual":
				took.append(sendToKeyboard(#selector(MainWindowController.resetZoom(_:))))
			// The two that are not keys and so have no chain to walk: `Fit to
			// Window` lives only in the pane's own menu, and a pinch goes to the
			// view under the pointer. Said as `direct` rather than dressed up as a
			// class that answered, since nothing was asked.
			case "fit":
				pane.setFit(.pane)
				took.append("direct")
			case let pinch where pinch.hasPrefix("pinch:"):
				pane.magnify(by: CGFloat(Double(pinch.dropFirst("pinch:".count)) ?? 0))
				took.append("direct")
			default:
				print("IMAGE: --image-zoom does not know \(step)")
			}
		}
		let holder = (window?.firstResponder).map { String(describing: type(of: $0)) } ?? "nobody"
		print("IMAGE zoom: keyboard=\(holder) took=\(took.joined(separator: ",")) \(pane.reportForTesting)")
	}

	/// The first responder from the keyboard outwards that answers a selector,
	/// having answered it — and its class, for the report.
	///
	/// The chain is walked here rather than handed to `NSApp.sendAction(_:to:
	/// from:)`, which is what a menu item with no target uses, because that one
	/// starts at the **key** window and a driven run has none: every step came
	/// back `reached nobody` while the pane plainly held the keyboard. This walks
	/// the same links AppKit would — first responder, then `nextResponder` out
	/// through the view tree, the window and this controller — so it still
	/// answers the question the item asks, which is who is in front of whom.
	private func sendToKeyboard(_ selector: Selector) -> String {
		var responder: NSResponder? = window?.firstResponder
		while let current = responder {
			if current.responds(to: selector) {
				current.perform(selector, with: nil)
				return String(describing: type(of: current))
			}
			responder = current.nextResponder
		}
		return "nobody"
	}

	func treeStepsForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// `settle`, and `settle:3` for longer. Everything after it goes back
			// to the run loop rather than being waited for here, because the trash
			// answers on the main queue and a nested `RunLoop.run(until:)` does not
			// drain it — measured, not assumed, when a script that trashed and then
			// pressed ⌘Z found an empty stack however long it "waited".
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.treeStepsForTesting(rest)
				}
				return
			}

			switch step {
			case "focus": navigator.focusTree()
			// What a right-click over the selection offers, submenus included.
			case "menu":
				print("TREE menu: \(navigator.contextMenuTitlesForTesting().joined(separator: " | "))")
				continue
			case "down": navigator.pressKeyForTesting(125)
			case "up": navigator.pressKeyForTesting(126)
			case "right": navigator.pressKeyForTesting(124)
			case "left": navigator.pressKeyForTesting(123)
			case "return": navigator.pressKeyForTesting(36)
			// The four keys the navigator answers, each one a different gesture
			// from the same key without its modifier: F2 and ⌥⏎ both rename, ⌘⌫
			// trashes the selection, ⌘↓ opens as it always did.
			case "f2": navigator.pressKeyForTesting(120)
			case "alt-return": navigator.pressKeyForTesting(36, modifiers: .option)
			case "cmd-delete": navigator.pressKeyForTesting(51, modifiers: .command)
			case "cmd-down": navigator.pressKeyForTesting(125, modifiers: .command)
			case "escape": navigator.pressKeyForTesting(53)
			// ⇧↓ and ⇧↑: a run of rows, selected the way somebody selects one.
			case "shift-down": navigator.pressKeyForTesting(125, modifiers: .shift)
			case "shift-up": navigator.pressKeyForTesting(126, modifiers: .shift)
			// What a build writing files does to the tree, on demand: the point
			// is what is still selected afterwards.
			case "reload": navigator.reloadForTesting()
			case "copy":
				print("TREE copy: clipboard=\(navigator.copyTextForTesting().replacingOccurrences(of: "\n", with: " | "))")
				continue
			// ⌘C for real and then ⌘V or ⌥⌘V, through the general pasteboard, so
			// what the copy writes is what the paste reads rather than two
			// closures agreeing with each other.
			case "copy-files":
				navigator.copyToPasteboardForTesting()
				continue
			case "paste": navigator.pasteForTesting(move: false)
			case "paste-move": navigator.pasteForTesting(move: true)
			// ⌘Z the way the Edit menu sends it: at nobody in particular, down the
			// responder chain from whatever has the keyboard. That is the half
			// `undo` cannot answer — which of the two stacks a ⌘Z reaches is
			// decided by the chain, so the harness has to ask the chain rather
			// than the tree.
			case "undo-key":
				// Key first: `target(forAction:)` starts at the *key* window's
				// first responder, and an app launched from a terminal need not
				// have one — which showed up as "answered by nobody" while the
				// tree plainly had the keyboard.
				NSApp.activate(ignoringOtherApps: true)
				window?.makeKeyAndOrderFront(nil)
				let selector = Selector(("undo:"))
				// The chain walked by hand as well, because it is the mechanism
				// under test and it can be named. AppKit's own answer is printed
				// beside it so the two can be seen to agree.
				var responder = window?.firstResponder
				while let step = responder, !step.responds(to: selector) {
					responder = step.nextResponder
				}
				func named(_ object: Any?) -> String {
					object.map { String(describing: type(of: $0)) } ?? "nobody"
				}
				print("TREE undo-key: chain=\(named(responder)) "
					+ "appkit=\(named(NSApp.target(forAction: selector))) "
					+ "first=\(named(window?.firstResponder))")
				// Sent the way the menu sends it, and by hand only when there is no
				// key window to send it through — either way the chain decides who
				// answers, which is the whole question.
				if !NSApp.sendAction(selector, to: nil, from: nil) {
					_ = responder?.tryToPerform(selector, with: nil)
				}
			// And the tree's own, straight at the outline view, for scripts that
			// only want the file half.
			case "undo": navigator.undoForTesting()
			// What is standing in the corner, which is where an undo that refused
			// says so.
			case "toasts":
				print("TREE \(toastReportForTesting())")
				continue
			// And the key itself, which is the half `paste-move` cannot ask
			// about: ⌥⌘V is in no menu, so `handleKeyDown` is the only thing
			// standing between the keystroke and the move.
			case "alt-cmd-v": navigator.pressKeyForTesting(9, modifiers: [.command, .option])
			case "collapse": navigator.collapseAll()
			case "locate": navigator.selectFileInEditor()
			// How far the text in front can be scrolled sideways. Here rather
			// than in `--navigate` for the same reason `type:` is: only this
			// list can put an edit and a question in a chosen order, and the
			// question is only interesting *after* something has been typed.
			//
			// A screenshot cannot answer it. An overlay scroller is invisible
			// until somebody scrolls, so "there is no scrollbar" and "there is
			// nothing to scroll to" look exactly alike in a picture — which is
			// how a document view that never grew past its pane went unnoticed.
			case "scroll":
				print("EDITOR scroll: "
					+ (editor.activeGroup?.activeCodeView?.scrollReportForTesting ?? "no code view in front"))
				continue
			// The header's third button. A row count with it off and the same
			// count with it on is the whole claim this change makes, and `rows`
			// is what says both.
			case "compact": navigator.toggleCompactPackages()
			// The Dependencies section, which is not on disk and so is the one
			// part of the tree `ls:` can say nothing about. `deps` is what the
			// section holds whether or not anything is open; `rows` is what the
			// pane is actually showing, which is the half that proves the rows
			// arrived rather than only the model.
			case "deps":
				print("TREE deps: \(navigator.dependencyReportForTesting().joined(separator: " | "))")
				continue
			case "rows":
				print("TREE rows: \(navigator.rowsForTesting().joined(separator: " | "))")
				continue
			// The section sits below the whole tree, which on a repository of
			// eight subprojects is several screens down.
			// Which roots the tree has, and what the third of them holds — the
			// one thing a screenshot of a tree several screens long cannot say.
			case "roots":
				print("TREE roots: \(navigator.rootsForTesting())")
			case "session-right-click":
				print("TREE session-right-click:\n    \(navigator.sessionRightClicksForTesting())")
			case "session-menu":
				print("TREE session-menu: \(navigator.sessionMenuForTesting())")
			case "sessions-rebuild": navigator.rebuildSessionsForTesting()
			case "sessions-open": navigator.openSessionsForTesting(files: false)
			case "sessions-open-all": navigator.openSessionsForTesting(files: true)
			case "deps-open": navigator.openDependenciesForTesting(groups: false)
			case "deps-open-all": navigator.openDependenciesForTesting(groups: true)
			// The field on the row, left standing: where its text sits and how
			// far it reaches are the whole of what is wrong with it, and
			// `rename:` commits too quickly to photograph.
			case "rename-begin":
				navigator.beginRename()
				print("TREE rename-begin: \(navigator.renameFieldReportForTesting)")
			default:
				// What is on disk under the project root, so "Escape left nothing
				// behind" is answered by the file system rather than by the tree
				// agreeing with itself. `ls:.` for the root, `ls:Sources` for a
				// folder inside it.
				// A file by absolute path, revealed the way activating its tab
				// does — the gesture item 508 is about, driven without a symbol
				// to follow. It prints which package the file turned out to be
				// in and where that package came from, which is what a
				// screenshot cannot say.
				if step.hasPrefix("reveal:") {
					navigator.revealForTesting(String(step.dropFirst("reveal:".count)))
					continue
				}
				if step.hasPrefix("ls:") {
					let folder = String(step.dropFirst("ls:".count))
					guard let root = project?.root else { continue }
					let url = folder == "." ? root : root.appendingPathComponent(folder)
					let names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
						.sorted()
					print("TREE ls \(folder): \(names.joined(separator: " "))")
					continue
				}
				// `type:abc`, into whatever the editor is showing. Here rather than
				// only in `--type` so that one script can put an edit and a file
				// gesture in a chosen order and then press ⌘Z once: which of the two
				// undo stacks answers is the question, and it cannot be asked from
				// two flags that fire at different times.
				if step.hasPrefix("type:") {
					simulateTyping(String(step.dropFirst("type:".count)))
					break
				}
				// `export:png`, the file's own context-menu action on whatever the
				// tree has selected.
				if step.hasPrefix("export:") {
					let raw = String(step.dropFirst("export:".count)).lowercased()
					let editable = raw.hasPrefix("editable-")
					guard let format = DiagramFormat(
						rawValue: editable ? String(raw.dropFirst("editable-".count)) : raw
					) else { continue }
					navigator.exportSelectionForTesting(format, editable: editable)
					continue
				}
				// `drop:a.swift+b.swift>Sources`, and `drop-copy:` for the ⌥
				// version — the whole of what a drag does once the mouse is up,
				// without a mouse. Everything is relative to the project root.
				if step.hasPrefix("drop:") || step.hasPrefix("drop-copy:") {
					let move = step.hasPrefix("drop:")
					let body = String(step.dropFirst(move ? "drop:".count : "drop-copy:".count))
					guard let root = project?.root, let arrow = body.firstIndex(of: ">") else { continue }
					let sources = body[..<arrow].split(separator: "+").map {
						root.appendingPathComponent(String($0))
					}
					navigator.dropForTesting(
						sources, into: root.appendingPathComponent(String(body[body.index(after: arrow)...])),
						move: move
					)
					continue
				}
				// `new-begin:file`, `new-begin:folder`, `new-begin:py` — the row
				// put in the tree with the field on it and left standing, which
				// is the half a committed name cannot show: where the row went,
				// what the field starts with, and which part of it is selected.
				if step.hasPrefix("new-begin:") {
					navigator.beginNewForTesting(kind: String(step.dropFirst("new-begin:".count)))
					print("TREE new-begin: \(navigator.renameFieldReportForTesting)")
				} else if step.hasPrefix("new:") {
					// `new:file:notes.txt`, `new:folder:docs`, `new:py:script` — the
					// whole gesture, the way `rename:` is: the row appears, takes
					// the name, and Return writes it. A kind fills the extension
					// in, so `new:py:script` makes `script.py`.
					let parts = step.dropFirst("new:".count).split(separator: ":", maxSplits: 1)
					guard let kind = parts.first else { continue }
					navigator.createSelectionForTesting(
						kind: String(kind), name: parts.count > 1 ? String(parts[1]) : nil
					)
				} else {
					// `rename:new-name.swift`, which is the whole gesture: the field
					// appears on the row, takes the name, and commits it.
					guard step.hasPrefix("rename:") else { continue }
					navigator.renameSelectionForTesting(String(step.dropFirst("rename:".count)))
				}
			}
			let selection = navigator.selectionForTesting
			let showing = editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing"
			// Arrowing shows a file without leaving the tree, so which pane has
			// the keyboard is what separates Return opening a file from Return
			// merely selecting one — and `renaming` is what separates it from
			// Return doing what it did last week.
			let renaming = navigator.renamingNameForTesting
			let focus: String
			if renaming != nil {
				focus = "rename-field"
			} else if let responder = window?.firstResponder as? NSView {
				if responder.isDescendant(of: navigator.view) {
					focus = "tree"
				} else if responder.isDescendant(of: editor.view) {
					focus = "editor"
				} else {
					focus = "elsewhere"
				}
			} else {
				focus = "elsewhere"
			}
			print(
				"TREE \(step): selected=\(selection.name) rows=\(selection.rows) "
					+ "editor=\(showing) focus=\(focus) renaming=\(renaming ?? "no")"
			)
		}
	}

	/// Everything 0428 asks a running window for, printed in one place.
	///
	/// One report rather than a flag per number, because these have to be read
	/// together: a "time to something usable" of four seconds means one thing
	/// beside a tree of 400 rows and another beside a tree of 40,000, and the
	/// load average has to sit next to both or neither can be argued with later.
	func scaleReportForTesting(typing presses: Int) {
		// First, and the whole path. Driving this app with `--open` has come up
		// on something from the recent list before now, and a set of timings
		// labelled "platform" that were taken on whatever was open last is
		// worse than no timings: they look like an answer. A harness can refuse
		// to believe the rest of this report unless this line names what it
		// asked for.
		print("OPEN project \(project?.root.path ?? "nothing")")
		for line in LaunchClock.report() { print(line) }
		for line in navigator.scaleReportForTesting() { print(line) }
		// Beside the watcher's batches, because the pair is the finding: before
		// 0446 these were the same number, and the whole of the fix is the
		// distance between them.
		let runs = RunCoordinator.runConfigurationTallyForTesting
		print(String(format: "OPEN %-24s %8d asked, %d skipped, %d coalesced, %d walked",
			("run configurations" as NSString).utf8String!,
			runs.asked, runs.skipped, runs.coalesced, runs.walked))

		if presses > 0 {
			let costs = editor.measureTypingForTesting(presses: presses)
			if costs.isEmpty {
				print("OPEN keystroke                no file open")
			} else {
				let walls = costs.map { $0.wall }.sorted()
				let cpus = costs.map { $0.cpu }.sorted()
				// Median and worst, not the mean. The mean of a hundred
				// keystrokes hides the one that took 300 ms, and the one that
				// took 300 ms is the entire complaint.
				func at(_ values: [TimeInterval], _ fraction: Double) -> Double {
					values[min(values.count - 1, Int(Double(values.count) * fraction))] * 1000
				}
				print(String(format: "OPEN keystroke wall       %8.2f ms median, %.2f ms p90, %.2f ms worst",
					at(walls, 0.5), at(walls, 0.9), walls.last! * 1000))
				print(String(format: "OPEN keystroke cpu        %8.2f ms median, %.2f ms p90, %.2f ms worst",
					at(cpus, 0.5), at(cpus, 0.9), cpus.last! * 1000))
			}
		}

		// The main thread going away is what "usable" fails to be, so the worst
		// of them are printed with the numbers rather than left in the log.
		for stall in StallWatch.worst(limit: 8) { print("OPEN stall \(stall.line)") }
	}

	/// What switching to another project costs, in the one number that matters:
	/// how long the main thread is gone.
	///
	/// The complaint is not that a large project takes a while to finish
	/// arriving — it is that the window stops answering while it does, so
	/// switching between projects "feels like it crashed" and the terminal
	/// stops drawing with it. The wall time around `switchProject` *is* that
	/// number: it runs on the main thread, so nothing else can happen inside it.
	///
	/// The stalls are printed beside it because the total says a switch was
	/// slow and `StallWatch` says which part of it was, which is the difference
	/// between a number and a lead.
	func measureProjectSwitchForTesting(to root: URL) {
		StallWatch.clear()
		let before = Date()
		switchProject(to: root)
		let elapsed = Date().timeIntervalSince(before) * 1000

		print(String(format: "SWITCH main thread held    %8.2f ms", elapsed))
		// The load beside the number, which the house rules ask for: a timing
		// without it cannot be told from a regression.
		var average = [Double](repeating: 0, count: 3)
		getloadavg(&average, 3)
		print(String(format: "SWITCH load                %.2f %.2f %.2f",
			average[0], average[1], average[2]))

		// After the run loop has turned a few times: the work this is about
		// finishing off the main thread is exactly the work that would not show
		// up in a reading taken the instant the call returned.
		DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
			for stall in StallWatch.worst(limit: 8) { print("SWITCH stall \(stall.line)") }
			// What arrived after the switch returned. The point of moving the
			// walks off the main thread is that these land *later*, so a reading
			// that did not check them would be measuring the app forgetting to
			// do the work rather than doing it elsewhere.
			print("SWITCH deps \(self.navigator.dependencyReportForTesting().joined(separator: " | "))")
			print("SWITCH settled")
			// Flushed, because stdout to a pipe is block-buffered and a harness
			// that kills the app when it has seen enough would otherwise lose
			// every line written after the last flush — which is all of these.
			fflush(stdout)
		}
	}

	/// Asks the language server a real question, over and over, until it answers.
	///
	/// 0428's missing number — *time until Java answers* — and the reason it went
	/// missing twice over. Once because the app was burning eight cores beside
	/// the server, so any figure would have described the app rather than the
	/// server; 0446 fixed that. And once because there was no way to ask: every
	/// other driver flag puts one question at a fixed delay, which can only tell
	/// you whether the delay happened to be long enough. On a Tycho reactor the
	/// honest answer is minutes, and a twelve-second `--lsp-wait` reports silence
	/// from a server that was working perfectly well.
	///
	/// Three questions rather than one, because they become answerable at
	/// different moments and the distance between them is the finding. An outline
	/// of the open file needs only that file parsed; completion and
	/// go-to-definition need the classpath, which for jdtls means the reactor
	/// imported. A server that answers the first at once and the last at four
	/// minutes is a very different thing to wait for than one that answers
	/// nothing until it is ready.
	///
	/// **And two more, for the debugger**, which is 0452's question and could not
	/// be asked either: whether the adapter inside the server is listening, and
	/// whether the import has got far enough to say what a launch would *run*.
	/// Taken on the same run as the file questions on purpose — one machine, one
	/// load — so that "the adapter was ready at fifty seconds while completion
	/// was still silent at eleven minutes" is a comparison rather than two
	/// readings from two afternoons.
	///
	/// **In a loop of their own, and that is not tidiness.** The first reading
	/// taken here put all five in one round and reported the adapter at 50.6
	/// seconds — five milliseconds after the outline, in the same round, which is
	/// the shape of a number bounded by its neighbours rather than measured. A
	/// round is as slow as the slowest question in it, `completion` was timing out
	/// at thirty seconds a go, and the adapter had very likely been listening for
	/// most of that. Two loops, one request each, and the two figures are then
	/// about the two things.
	///
	/// The file questions are asked together each round so a round costs one
	/// request timeout rather than three, and the granularity of every figure
	/// below is therefore the round — a second, plus however long the server took
	/// to refuse.
	func measureFirstAnswerForTesting(line: Int, character: Int, deadline: TimeInterval) {
		guard let project else {
			print("ANSWER no project")
			fflush(stdout)
			return
		}
		let position = LSPPosition(line: line, character: character)

		func say(_ what: String, _ detail: String) {
			let at = Date().timeIntervalSince(LaunchClock.processStart)
			print(String(format: "ANSWER %-16s %8.0f ms  %@  (%@)",
				(what as NSString).utf8String!, at * 1000,
				detail as NSString, LaunchClock.loadSaid as NSString))
			fflush(stdout)
		}

		func silence(_ what: String, _ waited: TimeInterval) {
			print(String(format: "ANSWER %-16s      —     still silent at %.0f s",
				(what as NSString).utf8String!, waited))
			fflush(stdout)
		}

		/// The file on screen, once the editor has finished opening it. On a large
		/// project the window arrives before the file does.
		func onScreen() -> (url: URL, languageId: String)? {
			guard let url = editor.activeGroup?.activeTabURL,
			      let languageId = editor.activeGroup?.activeDocument?.languageId
			else { return nil }
			return (url, languageId)
		}

		// What the editor asks for.
		Task { @MainActor in
			var outline = false, completion = false, definition = false
			while !(outline && completion && definition),
			      Date().timeIntervalSince(LaunchClock.processStart) < deadline {
				guard let (url, languageId) = onScreen() else {
					try? await Task.sleep(nanoseconds: 500_000_000)
					continue
				}

				let service = LanguageService.shared
				// The file's own root, not the scope. Measuring against the
				// scope would time a server that was never going to answer
				// about this file — which is the fault this verb is being used
				// to check, measured wrongly.
				let root = service.root(for: url, languageId: languageId, project: project.root)
				async let symbols = service.documentSymbols(url: url, languageId: languageId, project: root)
				async let completions = service.completions(
					url: url, position: position, languageId: languageId, project: root)
				async let locations = service.definition(
					url: url, position: position, languageId: languageId, project: root)
				let (foundSymbols, foundCompletions, foundLocations) =
					await (symbols, completions, locations)

				if !outline, !foundSymbols.isEmpty {
					outline = true
					say("outline", "\(foundSymbols.count) symbols in \(url.lastPathComponent)")
				}
				if !completion, !foundCompletions.isEmpty {
					completion = true
					say("completion", "\(foundCompletions.count) suggestions")
				}
				if !definition, let first = foundLocations.first {
					definition = true
					say("definition", first.url?.lastPathComponent ?? "somewhere")
				}
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}

			// Silence is a result and has to be printed as one. A missing line
			// reads as a harness that crashed; "still silent at 300 s" is the
			// answer to the question that was asked.
			let waited = Date().timeIntervalSince(LaunchClock.processStart)
			for (what, answered) in [
				("outline", outline), ("completion", completion), ("definition", definition),
			] where !answered { silence(what, waited) }
			print(String(format: "ANSWER done               %8.0f ms  %@", waited * 1000,
				LaunchClock.loadSaid as NSString))
			fflush(stdout)
		}

		// What the debugger asks for, on its own clock.
		Task { @MainActor in
			var adapter = false, classpath = false
			while !(adapter && classpath),
			      Date().timeIntervalSince(LaunchClock.processStart) < deadline {
				guard let open = onScreen() else {
					try? await Task.sleep(nanoseconds: 500_000_000)
					continue
				}
				// A file that is open and is not Java: nothing here hosts an
				// adapter, so these are not questions this project can be asked.
				// Left unsaid rather than reported as silence, which would put two
				// lines about a debugger at the end of every run that was not
				// about Java.
				guard open.languageId == "java" else { return }
				let url = open.url
				let ready = await LanguageService.shared
					.javaDebugReadinessForTesting(
						url: url,
						project: LanguageService.shared.root(
							for: url, languageId: open.languageId, project: project.root
						)
					)
				if !adapter, let port = ready.port {
					adapter = true
					say("debug adapter", "listening on port \(port)")
				}
				// An answer with nothing in it is an answer, and it is reported as
				// one. jdtls does that on a Tycho bundle — promptly, and for ever —
				// and a harness that counted it as silence would report a wait that
				// was never going to end as a wait.
				if !classpath, let count = ready.classPaths {
					classpath = true
					say("debug classpath", count == 0
						? "answered, and empty — nothing to launch a JVM with"
						: "\(count) entries")
				}
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}

			let waited = Date().timeIntervalSince(LaunchClock.processStart)
			for (what, answered) in [("debug adapter", adapter), ("debug classpath", classpath)]
			where !answered { silence(what, waited) }
		}
	}

	/// Whether the terminal panel is showing, what is in it, and what the pane in
	/// front last said — for 0444's part 4, whose whole claim is about a pane that
	/// appears without being asked for and must not be asked for again to be seen.
	func panelTabsForTesting(tail: Int = 0) -> String {
		var said = "PANEL: visible=\(isPanelVisible) \(bottomPanel.tabsForTesting)"
		if tail > 0 { said += "\n  last: " + bottomPanel.activeTerminalTailForTesting(lines: tail) }
		return said
	}

	/// Which project the window is on, and what it has open.
	///
	/// Beside the terminal's directory rather than instead of it, because 0509 is
	/// exactly the two disagreeing: a shell that never moved, and a window that
	/// left the project anyway. One of the two numbers alone says nothing — the
	/// directory is right in both builds, and a project name on its own cannot be
	/// told from a window that was opened on that project to begin with. The tabs
	/// are here because they are what the switch destroys.
	func projectReportForTesting() -> String {
		let root = project?.root.lastPathComponent ?? "none"
		let scope = subprojectRoot?.lastPathComponent ?? "whole"
		let titles = editor.activeGroup?.tabTitlesForTesting ?? []
		return "project=\(root) subproject=\(scope) tabs=[\(titles.joined(separator: " "))]"
	}

	/// Opens the run list and prints what is in it.
	///
	/// **This used to print a menu it built and threw away**, because opening
	/// the real one was what a capture run could not do: an `NSMenu` runs a
	/// nested event loop, so the window was never drawn, the screenshot never
	/// taken, and the run had to be killed — taking the output with it. A
	/// popover does not do that, so the harness can now open the thing somebody
	/// actually sees instead of a second copy of it that was free to drift.
	func showConfigurationMenuForTesting(open goal: String? = nil) {
		// The destinations first, because they are the part worth checking and
		// they arrive about twelve seconds after the menu is drawn — printing
		// before they land prints "Finding destinations…" and proves nothing.
		Task { @MainActor in
			// And discovery before that. A reactor of a hundred modules is a
			// walk of some seconds, and a run that printed at 1.2 s printed
			// "No configurations yet" whatever the project held — which is a
			// harness that cannot tell an empty project from a slow one.
			// Generous: a reactor of a hundred and eighty modules takes 94 s to
			// walk, measured, and most of that is the 45,772 Java files the main
			// classes are found in.
			let deadline = Date().addingTimeInterval(240)
			while self.run.runConfigurations.isEmpty, Date() < deadline {
				try? await Task.sleep(for: .milliseconds(200))
			}

			for configuration in self.run.runConfigurations where configuration.source == .xcodeScheme {
				guard let target = configuration.xcode else { continue }
				_ = await XcodeDestinations.shared.destinations(
					for: target,
					workingDirectory: URL(fileURLWithPath: configuration.workingDirectory)
				)
			}
			self.run.printConfigurationMenuForTesting(open: goal)
		}
	}

	/// What is drawn in an item's mark column, as something printable.
	///
	/// The two marks are the point of the dump: ▶ is the run glyph, on the
	/// things a click starts, and ✓ is the tick that still means "this one is
	/// selected". A list where they are muddled is the bug, and a picture of a
	/// menu is not something a test can read.
	private func markForTesting(_ item: NSMenuItem) -> String {
		guard item.state == .on else { return "" }
		return item.onStateImage === RunCoordinator.runMark() ? " ▶" : " ✓"
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

	/// The side buttons, taken here so that every view gets them.
	///
	/// **At the window, not in a view.** A window controller is in the responder
	/// chain behind everything in its window, so the editor, the tree, the panes
	/// and the terminal all reach this without any of them opting in — and a
	/// view that wants a side button for something of its own can still take it
	/// first, which is how the chain is meant to work.
	///
	/// The same `navigateBack` and `navigateForward` the menu items call: one
	/// history, one set of rules about when a step is possible, and one place
	/// where a file deleted since is dealt with. Both already return without
	/// doing anything where there is nowhere to go, which is what a button at
	/// the end of the history should do and needs no second check here.
	override func otherMouseDown(with event: NSEvent) {
		MouseReport.say("window down", event)
		// Consumed, so that a press nothing acted on does not arrive somewhere
		// else as one. What it will become happens on the release.
		switch MouseButtons.purpose(of: event.buttonNumber) {
		case .navigateBack, .navigateForward: return
		case .middleClick, .unclaimed: super.otherMouseDown(with: event)
		}
	}

	/// **On the release**, because a navigation changes what is on screen and a
	/// button still held is a hand still deciding — the same reason a click is a
	/// press and a release in the same place.
	override func otherMouseUp(with event: NSEvent) {
		MouseReport.say("window up", event)
		switch MouseButtons.purpose(of: event.buttonNumber) {
		case .navigateBack: navigateBack(nil)
		case .navigateForward: navigateForward(nil)
		case .middleClick, .unclaimed: super.otherMouseUp(with: event)
		}
	}

	@objc func stopSelected(_ sender: Any?) { run.stopRunning() }

	@objc func runSelected(_ sender: Any?) { run.runSelectedConfiguration(debug: false) }
	@objc func debugSelected(_ sender: Any?) { run.runSelectedConfiguration(debug: true) }

	// MARK: - Running in a cluster


	// MARK: - The other ways to start

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




	// MARK: - Hot code replace

	/// A save during a Java debug session, which is what makes a swap happen.
	///
	/// **The compile is all this app asks for.** In `AUTO` the provider inside
	/// the bundle is listening to the workspace and redefines whatever jdtls
	/// writes, so the swap follows the compile finishing rather than this app
	/// guessing when it has.
	///
	/// One build at a time with at most one queued, the shape `refreshGitStatus`
	/// uses for the same reason: saves come faster than a workspace build
	/// finishes.
	func compileForHotSwapIfDebugging(_ url: URL) {
		guard url.pathExtension == "java", let project else { return }
		guard let session = bottomPanel.activeDebugSession, !session.cannotHotSwap else { return }
		// A session that has ended is not one a swap can reach, and asking for a
		// workspace build on every save after a debugging run would be the cost
		// of the feature without the feature.
		if case .terminated = session.state { return }
		if case .idle = session.state { return }
		run.queueHotSwapCompile(project: project.scopeRoot)
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

	/// ⌘D: the same shell, in a column beside the one in front.
	@objc func newTerminalTabBeside(_ sender: Any?) {
		guard bottomPanel.hasKeyboardFocus else { return }
		bottomPanel.newTerminalBesideCurrent()
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

	/// Kept for the menu items and the screenshot harness.
	@objc func showProjectView(_ sender: Any?) { sidebar.showSidebarTool(.project) }
	@objc func toggleChanges(_ sender: Any?) { sidebar.showSidebarTool(.changes) }
	@objc func toggleBranchesView(_ sender: Any?) { sidebar.showSidebarTool(.branches) }
	@objc func toggleStructureView(_ sender: Any?) { sidebar.showSidebarTool(.structure) }
	@objc func toggleScratchesView(_ sender: Any?) { sidebar.showSidebarTool(.scratches) }
	@objc func toggleHistoryView(_ sender: Any?) { sidebar.showSidebarTool(.history) }

	/// A key that used to open something and now opens the git tool.
	///
	/// **Doing nothing would be the worse answer.** ⌘2 and ⌘6 have been Commit
	/// and History for as long as this app has had them, and fingers do not
	/// read release notes. For one release they land somewhere sensible and say
	/// where the thing they used to open has gone.
	@objc func movedShortcut(_ sender: Any?) {
		sidebar.showSidebarTool(.branches)
		guard let item = sender as? NSMenuItem else { return }
		if item.keyEquivalent == "5" {
			Toast.post(
				"Committing is ⇧⌘K now",
				detail: "The working copy is in the git tool on ⌘2, and the message is written "
					+ "on a page of its own.",
				kind: .information
			)
		} else {
			Toast.post(
				"The log is ⇧⌘L now",
				detail: "It opens as a page, where a graph has room for its lanes.",
				kind: .information
			)
		}
	}

	/// What the editor has open, relative to the project — the file a history
	/// view offers to narrow itself to.
	private func relativePathOfActiveFile() -> String? {
		guard let project, let url = editor.activeGroup?.activeTabURL else { return nil }
		// Canonical on both sides. A tab carries whatever URL opened it, and a
		// tab opened by a language server or a debugger carries the real path
		// while one opened from the tree carries the path the project was opened
		// by — so with the root normalised one way and the file the other, a
		// file under `/tmp` or `/var` narrowed the history to nothing. Same
		// asymmetry as 0430.
		// Against the *git* root, which is what a path handed to `git log` is
		// resolved from, and which may sit above the project root — a project
		// opened on a subdirectory of a checkout is the ordinary case. Measured
		// from the project root instead, the path was short by however many
		// components separate the two, and the history came back empty.
		let root = FilePath.canonical(gitCommandRoot ?? project.root)
		let path = FilePath.canonical(url)
		guard path.hasPrefix(root + "/") else { return nil }
		return String(path.dropFirst(root.count + 1))
	}

	/// Sets a breakpoint as a gutter click would, for verifying alignment.
	/// Presses stop, as the titlebar button does.
	func stopRunningForTesting() { run.stopRunning() }

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

	/// Invokes the gutter's run action, for verifying it end to end.
	func runLineForTesting(_ line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		run.runConfiguration(forFile: url, line: line)
	}

	/// Presses Run twice on whatever is selected, and says what the panel is
	/// holding after each — the whole question being whether that is one
	/// console or two.
	func rerunSelectedForTesting(_ goal: String?) {
		if let goal { run.chooseMakeRunForTesting(goal) }
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

	/// Opens the first value on the stopped line that has anything under it, and
	/// says what came back — for `--open-value`.
	///
	/// Through the same callback the click uses, so what is driven is what a
	/// click does. The count either side is the claim that drawing asks the
	/// adapter for nothing: scrolling a stopped file with values beside every
	/// line must not move it.
	func openValueForTesting() {
		guard let session = debugSession else { return print("VALUE: no session") }
		let before = session.childrenRequestsForTesting
		editor.scrollStoppedFileForTesting()
		print("VALUE: children requests after scrolling = \(session.childrenRequestsForTesting - before)")
		guard let opened = editor.openFirstInlineValueForTesting() else {
			print("VALUE: nothing on the stopped line can be opened")
			// The pane's tree is there regardless, and it is checked regardless:
			// this early return is why the pane's own selection bug was driven
			// and never seen.
			bottomPanel.walkThePaneForTesting()
			return
		}
		print("VALUE: opened \(opened)")
		// The fetch is a `Task`; give it the hop it needs before reading.
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
			guard let self else { return }
			print("VALUE: children requests total = \(session.childrenRequestsForTesting - before)")
			print("VALUE tree:\n\(self.editor.openValueReportForTesting())")
			// A value with nothing under it is a piece of text, and a click on
			// it belongs to the editor.
			print("VALUE leaf: \(self.editor.inlineValueClickForTesting(named: "stage"))")
			// And a field inside it, which is the second request and the first
			// one that was not made until somebody reached for it.
			print("VALUE expand: \(self.editor.expandInsideOpenValueForTesting())")
			print("VALUE \(self.editor.openValueMenuForTesting())")
			// The arrows, on the window that opened: down onto the field.
			print("VALUE walk down: \(self.editor.walkOpenValueForTesting(["down"]))")
			// Down onto a field, then → to open it: the case where the
			// selection used to be lost, read after the children arrive.
			// → on a row whose children have never been fetched: the branch
			// that reloads the tree, and the one that lost the selection.
			self.editor.walkOpenValueThenSettleForTesting(["right"]) { after in
				print("VALUE right on a fresh field, once its children arrived: \(after)")
				fflush(stdout)
			}
			print("VALUE placement: \(self.editor.openValueReportForTesting().split(separator: "\n").first ?? "")")
			print("VALUE selection: \(self.editor.openValueSelectionColourForTesting())")
			// And the panel's own tree, which never had the keyboard either.
			bottomPanel.walkThePaneForTesting()

			// And letting the program go takes it away, which is the other half
			// of what makes this safe to leave open.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				print("VALUE after expanding: requests = \(session.childrenRequestsForTesting - before)")
				print("VALUE tree:\n\(self.editor.openValueReportForTesting())")
				fflush(stdout)

				// And letting the program go takes it away, which is the other
				// half of what makes this safe to leave open.
				session.resume()
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					print("VALUE after resuming: \(self.editor.openValueReportForTesting())")
					fflush(stdout)
				}
			}
		}
	}

	/// What a server offers about a line, taken, with the file before and after
	/// — for `--code-actions`.
	///
	/// **Driven through the same path the keystroke takes**, so what is watched
	/// is what ⌥⏎ does: the offer is asked for exactly as `showCodeActions`
	/// asks, and the action is taken exactly as the menu takes it. A report that
	/// called the client directly would prove the client works and say nothing
	/// about the editor.
	func reportCodeActionsForTesting(line: Int, character: Int = 0, take wanted: String?) {
		guard let group = editor.activeGroup,
		      let url = group.activeTabURL,
		      let languageId = group.activeDocument?.languageId,
		      let project
		else {
			print("ACTIONS: nothing open")
			fflush(stdout)
			return
		}
		let root = LanguageService.shared.root(for: url, languageId: languageId, project: project.root)
		let position = LSPPosition(line: line, character: character)

		Task { @MainActor [weak self] in
			guard let self else { return }
			let caret = await LanguageService.shared.codeActions(
				url: url, range: LSPRange(start: position, end: position),
				languageId: languageId, project: root
			)
			guard let caret else {
				print("ACTIONS line \(line): no server for this file")
				fflush(stdout)
				return
			}
			let atTheCaret = caret.actions.filter { !$0.isSourceAction }
			print("ACTIONS line \(line) from \(caret.server): "
				+ (atTheCaret.isEmpty
					? "nothing on offer"
					: atTheCaret.prefix(8).map(\.title).joined(separator: " | ")))
			print("ACTIONS line \(line) needing resolve: "
				+ "\(atTheCaret.filter(\.needsResolving).count) of \(atTheCaret.count)")

			// The file's own, asked separately and never shown at the caret.
			let file = await LanguageService.shared.codeActions(
				url: url,
				range: LSPRange(start: LSPPosition(line: 0, character: 0), end: position),
				languageId: languageId, project: root, only: ["source"]
			)
			print("ACTIONS source: "
				+ ((file?.actions.filter(\.isSourceAction).map(\.title).prefix(6).joined(separator: " | "))
					.map { $0.isEmpty ? "nothing on offer" : $0 } ?? "no server"))
			fflush(stdout)

			// The caret's list first, then the file's: a source action is taken
			// the same way, from the place it belongs.
			// The gesture itself, so that what a person would see is what is
			// reported: the menu at the caret, or the sentence when there is
			// nothing to put in it.
			if wanted == nil {
				self.showCodeActions(nil)
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
					print("ACTIONS said: \(self.toasts.saidForTesting.last ?? "nothing")")
					fflush(stdout)
				}
			}

			guard let wanted,
			      let chosen = atTheCaret.first(where: { $0.title.contains(wanted) })
				?? file?.actions.first(where: { $0.isSourceAction && $0.title.contains(wanted) })
			else {
				if wanted != nil { print("ACTIONS: nothing offered called \(wanted ?? "")") }
				fflush(stdout)
				return
			}
			let before = LanguageService.shared.serverEditsForTesting
			print("ACTIONS taking a \(chosen.command == nil ? "plain edit" : "command")")
			print("ACTIONS taking: \(chosen.title)")
			fflush(stdout)
			self.take(TakenCodeAction(
				action: chosen, url: url, languageId: languageId, project: root
			))

			// The edit arrives through the rope or the disk; either way it is
			// the file afterwards that says whether this worked.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				let text = self.editor.document(for: url)?.rope.string
					?? (try? String(contentsOf: url, encoding: .utf8))
					?? ""
				let head = text.components(separatedBy: "\n").prefix(6).joined(separator: " ⏎ ")
				print("ACTIONS file after: \(head)")
				// The other half of a command: the server asking this program to
				// apply an edit, which is a request it waits on.
				print("ACTIONS edits the server asked for: "
					+ "\(LanguageService.shared.serverEditsForTesting - before)")
				fflush(stdout)
			}
		}
	}

	/// Presses ⌃Space on an empty line and says what came back.
	///
	/// An empty line on purpose: with nothing typed there is no prefix, which is
	/// the case the typing rule can never answer and the whole reason the key
	/// exists. What it must never print here is nothing at all.
	func exerciseExplicitCompletionForTesting() {
		editor.moveCaretToEndForTesting()
		editor.simulateTyping("\n")
		completeAtCaret(nil)
		// Twice, a second apart: the first says whether anything appeared at
		// all, the second whether what appeared was the answer or the notice.
		// A server asked cold answers some way after it is asked.
		for delay in [1.0, 6.0] {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
				guard let self else { return }
				print("COMPLETENOW +\(delay)s: \(self.editor.completionReportForTesting)")
				fflush(stdout)
			}
		}
	}

	/// Presses ↑ on the first line and ↓ on the last, the page keys, and ⌘↑ and
	/// ⌘↓ from the middle — each with Shift and without — and says where the
	/// caret and the selection ended up every time.
	///
	/// Started from the middle of a line rather than from its edge, or the
	/// selection ⇧↑ makes would be empty and the run would read the same
	/// whether the caret had moved or not.
	///
	/// Worth running twice, the second time with `--wrap`: the rows a vertical
	/// key moves by are then segments of a line rather than lines, and a caret
	/// partway along a wrapped first line has a row above it to go to even
	/// though it has no line above it. So the run says which mode it is in
	/// rather than leaving it to be worked out from the offsets — and the
	/// setting persists between launches, which is exactly how a run gets read
	/// as the wrong one of the two.
	func exerciseVerticalNavigationForTesting() {
		// Flushed line by line: the app has to be killed to end a run, and a
		// report still sitting in stdout's buffer when the signal arrives is a
		// run that looks like it never happened. `--word-nav` reads as silent
		// for that reason and not because it does nothing.
		func say(_ label: String) {
			let padded = label.padding(toLength: 12, withPad: " ", startingAt: 0)
			print("VERT: \(padded)\(editor.caretReportForTesting)")
			fflush(stdout)
		}
		func place(_ label: String, line: Int, column: Int) {
			editor.setCaretForTesting(line: line, column: column)
			say(label)
		}
		func press(_ key: String, _ label: String, _ modifiers: NSEvent.ModifierFlags) {
			editor.simulateKey(key, modifiers: modifiers)
			say(label)
		}

		print("VERT: word wrap is \(Settings.shared.wordWrap ? "on" : "off")")
		fflush(stdout)

		place("at 0@8", line: 0, column: 8)
		press("up", "⇧↑", .shift)
		place("at 0@8", line: 0, column: 8)
		press("up", "↑", [])

		place("at last@4", line: -1, column: 4)
		press("down", "⇧↓", .shift)
		place("at last@4", line: -1, column: 4)
		press("down", "↓", [])

		// The column has to survive the jump: ⇧↓ to the end of the file and then
		// ↑ belongs back at the column the run started from, and not at whatever
		// column the last line happens to end at.
		place("at last@4", line: -1, column: 4)
		press("down", "⇧↓", .shift)
		press("up", "then ↑", [])

		// The page keys are the same motion with a screenful as the step, and a
		// file shorter than the window is all edge: both of these overshoot.
		place("at 0@8", line: 0, column: 8)
		press("pageup", "⇞", [])
		place("at last@4", line: -1, column: 4)
		press("pagedown", "⇧⇟", .shift)

		// Partway along the first line, which the file this is pointed at wants
		// to make a long one. Wrapped, the first ↑ is the row above and still
		// inside line 0, and only the second one runs out of rows and goes to
		// the start of the file; unwrapped there is no row above at all and the
		// first ↑ is already the start of the file. The column stops at the end
		// of the line, so a short first line makes this its end rather than
		// nothing.
		place("at 0@400", line: 0, column: 400)
		press("up", "↑", [])
		press("up", "↑ again", [])
		place("at 0@400", line: 0, column: 400)
		press("down", "↓", [])
		press("down", "↓ again", [])

		// ⌘↑ and ⌘↓ and their shifted twins, from the middle of the file so that
		// both directions have something to select — from either edge one of the
		// four would select nothing and read the same as the dead key it used to
		// be. Before 0495 the shifted pair were selectors `doCommand` had no case
		// for, so they printed the line placing the caret, unchanged.
		place("at 3@4", line: 3, column: 4)
		press("up", "⌘↑", .command)
		place("at 3@4", line: 3, column: 4)
		press("up", "⌘⇧↑", [.command, .shift])
		place("at 3@4", line: 3, column: 4)
		press("down", "⌘↓", .command)
		place("at 3@4", line: 3, column: 4)
		press("down", "⌘⇧↓", [.command, .shift])
	}

	/// Presses the emacs motions — ⌃B, ⌃F and their shifted twins, with ⌃P and
	/// ⌃N as the control — and says where the caret and the selection landed.
	///
	/// A separate driver from `--vertical-nav` rather than four more lines in
	/// it: these are letter keys with a modifier, they need a file with
	/// ordinary short lines rather than one 723 characters long, and the run
	/// people will want to read is the four keystrokes together.
	///
	/// The caret goes back to the same place before each press, so every line
	/// is an independent keystroke and not a run — a ⌃B after a ⌃F would land
	/// back where it started and say nothing about either.
	func exerciseEmacsNavigationForTesting() {
		func say(_ label: String) {
			let padded = label.padding(toLength: 12, withPad: " ", startingAt: 0)
			print("EMACS: \(padded)\(editor.caretReportForTesting)")
			fflush(stdout)
		}
		func place(_ label: String, line: Int, column: Int) {
			editor.setCaretForTesting(line: line, column: column)
			say(label)
		}
		func press(_ key: String, _ label: String, _ modifiers: NSEvent.ModifierFlags) {
			editor.simulateKey(key, modifiers: modifiers)
			say(label)
		}

		// Said out loud because the setting persists between launches and has
		// twice now made a run read as the wrong one of two. It makes no
		// difference to anything below — every motion here is `caret ± 1` in
		// document offsets, and none of them asks what row it is on.
		print("EMACS: word wrap is \(Settings.shared.wordWrap ? "on" : "off")")
		// Which document the offsets below are offsets into. The first run of
		// this driver reported a caret in a file nobody had asked for — the
		// app opens `--file` some time after launch, and until it lands the
		// active tab is whatever the last session left. A report of caret=26
		// is unfalsifiable without this line, and looks exactly like a motion
		// gone wrong.
		print("EMACS: the file ends \(editor.textTailForTesting)")
		fflush(stdout)

		// Mid-line, so both directions have somewhere to go and the shifted
		// pair have something to select.
		place("at 2@6", line: 2, column: 6)
		press("f", "⌃F", .control)
		place("at 2@6", line: 2, column: 6)
		press("b", "⌃B", .control)
		place("at 2@6", line: 2, column: 6)
		press("f", "⇧⌃F", [.control, .shift])
		place("at 2@6", line: 2, column: 6)
		press("b", "⇧⌃B", [.control, .shift])

		// The edges. At column 0 the character before the caret is the newline
		// that ended the line above, so ⌃B goes to the end of that line rather
		// than staying put — the same step, over a character that happens not
		// to be printable. At offset 0 there is nothing behind the caret at
		// all and the clamp keeps it there.
		place("at 2@0", line: 2, column: 0)
		press("b", "⌃B", .control)
		place("at 0@0", line: 0, column: 0)
		press("b", "⌃B", .control)

		// The control the whole item is built on: the vertical half of the
		// same family, which arrives as plain `moveUp:`/`moveDown:` and has
		// always worked.
		place("at 2@6", line: 2, column: 6)
		press("p", "⌃P", .control)
		place("at 2@6", line: 2, column: 6)
		press("n", "⌃N", .control)

		// The paragraph family: ⌃A, ⌃E and their shifted twins, the two ⌥
		// arrows whose second selector is one of them, and ⌥⇧↑/⌥⇧↓, which are
		// `moveParagraph…AndModifySelection:` and not a pair at all.
		place("at 2@6", line: 2, column: 6)
		press("a", "⌃A", .control)
		place("at 2@6", line: 2, column: 6)
		press("e", "⌃E", .control)
		place("at 2@6", line: 2, column: 6)
		press("a", "⇧⌃A", [.control, .shift])
		place("at 2@6", line: 2, column: 6)
		press("e", "⇧⌃E", [.control, .shift])

		// An indented line, because a paragraph motion that went to the first
		// non-blank instead of to column zero would be right here and wrong
		// below: 3@4 is the first non-blank of a line indented four spaces,
		// and it is where the ⌥↑ two lines further on starts from.
		place("at 3@11", line: 3, column: 11)
		press("a", "⌃A", .control)
		place("at 3@4", line: 3, column: 4)
		press("a", "⌃A", .control)

		// ⌥↑ and ⌥↓ are `['moveBackward:', 'moveToBeginningOfParagraph:']` and
		// `['moveForward:', 'moveToEndOfParagraph:']` — two selectors sent in
		// order. Mid-line the leading nudge makes no difference; at a boundary
		// it is the whole point, and it is why the second selector must be a
		// plain "go to the hard edge" rather than anything that reads where
		// the caret already is.
		place("at 2@6", line: 2, column: 6)
		press("up", "⌥↑", .option)
		place("at 2@6", line: 2, column: 6)
		press("down", "⌥↓", .option)
		place("at 2@0", line: 2, column: 0)
		press("up", "⌥↑ at start", .option)
		place("at 2@end", line: 2, column: 999)
		press("down", "⌥↓ at end", .option)
		place("at 3@4", line: 3, column: 4)
		press("up", "⌥↑ indent", .option)

		// The shifted pair are *not* the shifted version of the two above.
		// `StandardKeyBinding.dict` sends ⌥⇧↑ as the single selector
		// `moveParagraphBackwardAndModifySelection:`, with no nudge in front
		// of it, so that one selector has to step to the previous paragraph
		// by itself when the caret is already at a boundary.
		place("at 2@6", line: 2, column: 6)
		press("up", "⌥⇧↑", [.option, .shift])
		place("at 2@6", line: 2, column: 6)
		press("down", "⌥⇧↓", [.option, .shift])
		place("at 2@0", line: 2, column: 0)
		press("up", "⌥⇧↑ start", [.option, .shift])

		// ⌃K last, and with the line printed either side of it, because a
		// caret report cannot show a deletion — the caret does not move. It
		// is last because it edits the document and the app autosaves, so
		// everything above would be reading a file this run had changed.
		// Regenerate the scratch file between runs.
		place("at 2@6", line: 2, column: 6)
		print("EMACS: line 2 is “\(editor.lineTextForTesting(2))”")
		press("k", "⌃K", .control)
		print("EMACS: line 2 is “\(editor.lineTextForTesting(2))”")
		// At the end of a line there is nothing left of the paragraph to
		// take, and the newline is the boundary rather than part of it, so
		// this is a no-op and does not join the two lines.
		place("at 3@end", line: 3, column: 999)
		press("k", "⌃K", .control)
		print("EMACS: lines 3-4 are “\(editor.lineTextForTesting(3))” / “\(editor.lineTextForTesting(4))”")
		fflush(stdout)
		// ⌃O — open-line, and the one key here that edits the file. macOS
		// sends it as a *pair* of selectors, `insertNewlineIgnoringFieldEditor:`
		// and then `moveBackward:`, so the caret ends where it started with
		// the line split under it — and the caret report alone cannot tell
		// that apart from a key that did nothing, since both say the caret is
		// where it was put. Each press prints the lines as well as the caret.
		//
		// Bottom of the file upwards, because unlike every motion above these
		// presses do not undo themselves: each one adds a line, and going up
		// leaves the line numbers underneath still the ones written here.
		func open(_ label: String, line: Int, column: Int) {
			editor.setCaretForTesting(line: line, column: column)
			say(label)
			print("EMACS:             \(editor.caretLinesForTesting)")
			editor.simulateKey("o", modifiers: .control)
			say("⌃O")
			print("EMACS:             \(editor.caretLinesForTesting)")
			fflush(stdout)
		}
		// An empty line: nothing on either side of the caret, so what ⌃O
		// leaves behind is two empty lines with the caret still on the first.
		open("at 5@0", line: 5, column: 0)
		// The end of an indented line, which is where copying the indent and
		// not copying it differ: the caret does not go to the new line, so a
		// copied indent would be whitespace on a line nobody is on.
		open("at 4@end", line: 4, column: 999)
		// Mid-word, the ordinary case: the word is split and the caret stays
		// in front of the newline, at the end of the first half.
		open("at 2@8", line: 2, column: 8)
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
		// Asked of the group, which asks the tab. A menu is validated on every open,
		// so this cannot be a question that reads the file — the tab decided it once,
		// when it opened. See 0482.
		guard let modes = editor.activeGroup?.activeTabPreviewModes else { return nil }
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
		toolStrip.setSidebarSelection(visible: true, tool: sidebar.currentSidebarTool)
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
		toolStrip.setSidebarSelection(visible: collapsed, tool: sidebar.currentSidebarTool)
		splitView.adjustSubviews()
	}

	@objc func saveDocument(_ sender: Any?) {
		// Read before the save, because a save can close nothing but can change
		// which tab is active on some paths, and the file that was written is the
		// one the swap is about.
		let written = editor.activeGroupTabURL
		editor.save()
		// **And into the running JVM, if one is being debugged.** The compile is
		// all that is asked for: the adapter is in `AUTO` and listening to the
		// workspace, so it redefines what jdtls writes. Nothing happens when
		// nothing is being debugged, which is most saves.
		if let written { compileForHotSwapIfDebugging(written) }
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
		guard let capsule = titlebar.capsuleView else { return }
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
		// A server's own edit is applied where the open documents are, and that
		// is a window. The one in front takes it.
		takeServerEdits()
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
		// The project's language servers are not stopped here, and no window
		// asks what the other windows are showing any more. Both went with the
		// decision in 0427: a server ends when the app does. That also settles
		// the torn-off case for good — a window sharing another's project can no
		// longer take its servers away, because closing a window takes none.
		onClose?()
	}
}

// MARK: - Toolbar items

extension MainWindowController {

	/// The run strip's commands, for when there is no room to draw it.
	/// A menu item pointing back at this window.
	private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		return item
	}

	fileprivate func showBranchMenu() {
		guard let project, let capsule = titlebar.capsuleView else { return }
		capsule.menuHalf = .branch
		// The switcher's popover rather than an `NSMenu`, in its branches mode.
		//
		// It already was a branch picker — it lists them, filters them and
		// checks them out — and it had the filter field and the styling that a
		// hundred branches need. A second control that had to be kept looking
		// the same would be the thing that stopped looking the same.
		//
		// It also opens when git has not answered yet, which the menu could not:
		// `BranchMenu.show` returned without opening anything if the repository
		// was still being read, so a click in the first second of a project did
		// nothing at all, said nothing, and read as a slow menu. This one opens
		// and says what it is waiting for.
		ProjectSwitcherPopover.show(
			relativeTo: capsule,
			anchorRect: capsule.branchRect,
			currentProject: project,
			owner: self,
			focus: .branches
		)
	}

	func showBranchMenuForTesting() { showBranchMenu() }

	/// One entry offering a shell in one container, or the grey generic one.
	///
	/// The choice travels on the item, because with several of them the title is
	/// not enough to act on — what is clicked has to name the file it meant, or
	/// the second entry would open the first entry's container.
	func makeContainerMenuItem(for choice: DevContainerFile.Choice?) -> NSMenuItem {
		let item = NSMenuItem(
			title: Self.containerTerminalTitle,
			action: #selector(newTerminalInContainer(_:)),
			keyEquivalent: ""
		)
		item.representedObject = choice?.file
		return item
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
	///
	/// Whether to move anything at all is asked twice, once here and once on
	/// the turn that would act. See the second for why.
	func splitViewDidResizeSubviews(_ notification: Notification) {
		guard notification.object as? NSSplitView === verticalSplitView else { return }
		// Moving the divider resizes the subviews, which is this notification
		// again — and `setPosition` sends it synchronously, so without this the
		// second pass runs inside the first. It converges on the arithmetic
		// alone, but "converges" is not "terminates": the first version of this
		// took the app out with a stack overflow before the remainder ever
		// reached zero.
		guard !isSnappingPanel else { return }
		guard PanelRowSnap.dividerPosition(for: panelSnapState) != nil else { return }

		isSnappingPanel = true
		// Next turn rather than inside the layout that is reporting to us:
		// setting a divider position from within a layout pass is how the
		// terminal came to be told two different sizes for one pane.
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			// Cleared after the move rather than before it, so the notification
			// that `setPosition` sends synchronously still finds the guard up.
			defer { self.isSnappingPanel = false }

			// Asked again rather than acted on from a turn ago. A great deal
			// can happen in a turn, and one thing did: at startup
			// `terminalAtStartup = full` maximises the panel between the resize
			// that asks this question and the turn that answers it. Answering
			// with the old numbers hands the editor its half of the window back
			// while the window still believes the panel has all of it — so the
			// panel keeps the inset it wears under the titlebar, and that inset
			// is an empty band above the tabs.
			guard let position = PanelRowSnap.dividerPosition(for: self.panelSnapState) else { return }
			self.verticalSplitView.setPosition(position, ofDividerAt: 0)
		}
	}

	/// What the panel looks like this instant, for the question above.
	private var panelSnapState: PanelRowSnap.State {
		PanelRowSnap.State(
			isVisible: isPanelVisible,
			isMaximized: isPanelMaximized,
			total: verticalSplitView.bounds.height,
			panelHeight: bottomPanel.frame.height,
			remainder: bottomPanel.terminalHeightRemainder
		)
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

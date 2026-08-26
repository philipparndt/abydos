import AppKit
import AbydosKit

/// The project window: titlebar pills, the left tool strip, the navigator, and
/// the editor area.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
	private(set) var project: Project?

	/// What to do once the shell being waited for has answered, so that a second
	/// container is opened after the first rather than beside it.
	var afterContainerShellForTesting: (() -> Void)?

	/// Which section a capture run asked for.
	var settingsSectionForTesting: String?
	/// And which one it asked to be folded away, since a triangle needs a click.
	var settingsFoldForTesting: String?

	/// What each project had open, so going back to one looks as it was left.
	private(set) var sessions = ProjectSessions()
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

	/// Takes a tab dragged out of another window.
	func adopt(_ tab: EditorViewController.Tab) {
		editor.adopt(tab)
	}
	var onClose: (() -> Void)?

	let navigator = ProjectNavigatorViewController()
	/// The editor area, which may hold several split groups.
	let editor = EditorAreaController()
	let bottomPanel = BottomPanel()

	/// The left rail and the tools it opens.
	///
	/// Not an `NSViewController`: the rail is a subview of the window's root and
	/// the tool it opens lives inside `navigatorContainer`, so there is no one
	/// view for it to control. The window builds the hierarchy and hands it the
	/// two pieces; it owns which tool is showing and every pane behind that.
	private(set) lazy var sidebar: SidebarController = {
		let bar = SidebarController(editor: editor, navigator: navigator)
		bar.project = { [weak self] in self?.project }
		bar.hostWindow = { [weak self] in self?.window }
		bar.gitCommandRoot = { [weak self] in self?.gitCommandRoot }
		bar.relativePathOfActiveFile = { [weak self] in self?.relativePathOfActiveFile() }
		bar.symbols = { [weak self] query, scope in
			await self?.serverActions.symbols(matching: query, scope: scope) ?? []
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

	var debugSession: DebugSession? { bottomPanel.activeDebugSession }

	/// Running a program, wherever it runs.
	private(set) lazy var run: RunCoordinator = {
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

	/// What a language server offers to change, and taking it.
	private(set) lazy var serverActions: ServerActions = {
		let actions = ServerActions(
			editor: editor, navigator: navigator, panel: bottomPanel, toasts: toasts
		)
		actions.currentProject = { [weak self] in self?.project }
		actions.onNotify = { [weak self] title, detail, kind in
			self?.notify(title, detail: detail, kind: kind)
		}
		actions.results = { [weak self] in self?.results }
		actions.onSetPanelVisible = { [weak self] visible in self?.setPanelVisible(visible) }
		return actions
	}()

	/// Copying a place in the code, and going to one that was copied.
	private(set) lazy var codeLinks: CodeLinks = {
		let links = CodeLinks(editor: editor, toasts: toasts)
		links.currentProject = { [weak self] in self?.project }
		links.onNotify = { [weak self] title, detail, kind in
			self?.notify(title, detail: detail, kind: kind)
		}
		return links
	}()

	// Menu-bar selectors. AppKit resolves these against the responder chain and
	// finds them here; the work is the collaborator's.
	@objc func renameSymbol(_ sender: Any?) { serverActions.renameSymbol(sender) }
	@objc func completeAtCaret(_ sender: Any?) { serverActions.completeAtCaret(sender) }
	@objc func showCodeActions(_ sender: Any?) { serverActions.showCodeActions(sender) }
	@objc func showSourceActions(_ sender: Any?) { serverActions.showSourceActions(sender) }
	@objc func copyReference(_ sender: Any?) { codeLinks.copyReference(sender) }
	@objc func copyPermalink(_ sender: Any?) { codeLinks.copyPermalink(sender) }
	@objc func goToCopiedPlace(_ sender: Any?) { codeLinks.goToCopiedPlace(sender) }

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
	private(set) lazy var titlebar: TitlebarController = {
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

	/// Where an answer to a question about the code is shown, and where it moves.
	///
	/// Wired rather than owned: it is handed the two views it presents into and
	/// the handful of things only the window knows, and it holds no reference
	/// back. `dockInSidebar` and `undockFromSidebar` are lent from here because
	/// the lower half of the sidebar is the sidebar's, not a results list's.
	private(set) lazy var results: ResultsPresenter = {
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
			self?.serverActions.findUsages(in: url, line: line, character: character)
		}
		presenter.symbolsMatching = { [weak self] query, scope in
			await self?.serverActions.symbols(matching: query, scope: scope) ?? []
		}
		presenter.reasonForNoSymbols = { [weak self] query, scope in
			self?.serverActions.reasonForNoSymbols(query: query, scope: scope) ?? ""
		}
		return presenter
	}()

	private(set) var splitView: NSSplitView!
	var verticalSplitView: NSSplitView!
	/// How wide the tree is, kept as a constraint so nothing else decides.
	private(set) var navigatorWidthConstraint: NSLayoutConstraint!
	var panelHeight: CGFloat = 260
	/// True while the panel is being rounded to whole rows, so the resize that
	/// causes cannot ask for another one.
	fileprivate var isSnappingPanel = false
	private(set) var navigatorContainer: ColoredView!
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

	var navigatorWidth: CGFloat = 260

	/// Where news the user did not ask for goes.
	private(set) lazy var toasts = ToastPresenter(window: window)

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
		serverActions.takeServerEdits()

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
			self?.serverActions.findUsages(in: url, line: line, character: character)
		}
		editor.onRename = { [weak self] url, line, character in
			self?.serverActions.renameSymbol(in: url, line: line, character: character)
		}
		editor.onWatch = { [weak self] expression in
			self?.watchFromEditor(expression)
		}
		editor.onFixWithAI = { [weak self] url, line, diagnostic in
			self?.serverActions.fixWithAI(url: url, line: line, diagnostic: diagnostic)
		}
		editor.onCopyLink = { [weak self] url, form, line, endLine in
			self?.codeLinks.copyLink(to: url, form: form, line: line, endLine: endLine)
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

	/// Gives the project tree keyboard focus.
	func focusNavigator() {
		navigator.focusTree()
	}

	/// Also reachable by double-clicking the empty part of the tab strip.
	@objc func newScratchFile(_ sender: Any?) {
		editor.newScratch()
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

	var isPanelVisible: Bool { !bottomPanel.isHidden }

	/// Whether the panel has the window to itself, and what to restore.
	private(set) var isPanelMaximized = false
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
	func tellTerminalsTheySizeChanged() {
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

	func setPanelVisible(_ visible: Bool) {
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
	func say(_ outcome: LineComment.Outcome) {
		guard case let .unavailable(reason) = outcome else { return }
		notify("Nothing was commented out", detail: reason, kind: .information)
	}

	func setFindQuery(_ query: String) { editor.setFindQuery(query) }

	func setProjectSearchQuery(_ query: String) {
		results.showProjectSearch(query: query)
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
	func newTerminalMenu() -> NSMenu {
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

	/// Everything in this file, or everything in the project.
	@objc func goToSymbolInFile(_ sender: Any?) { results.goToSymbolInFile() }

	@objc func goToSymbolInProject(_ sender: Any?) { results.goToSymbolInProject() }

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

	// MARK: - Copying a place in the code

	// MARK: - What a server offers


	// MARK: - Under the project view

	// MARK: - A window of its own

	// MARK: - Launch configurations

	func reportDividerDrag(to position: CGFloat) {
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

	/// Puts the caret on a line of the file being edited, for `:` in the palette.
	func goTo(line: Int) { editor.goTo(line: line) }

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
	func sendToKeyboard(_ selector: Selector) -> String {
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
		serverActions.takeServerEdits()
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

	func showBranchMenu() {
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

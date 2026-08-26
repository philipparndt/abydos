import AppKit
import AbydosKit

/// The project window: titlebar pills, the left tool strip, the navigator, and
/// the editor area.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
	var project: Project?

	/// The part of the project being worked on, when it is not the whole of it.
	///
	/// A repository is often not one thing: `ideai-examples` holds eight
	/// projects, a work checkout holds a service and its front end. The tree
	/// stays whole, because that is how somebody navigates — but everything
	/// scoped follows this: the launch configurations, the build's working
	/// directory, the work tree git acts on, the root the language server is
	/// given, and where a terminal opens.
	var subprojectRoot: URL?

	/// Whether this window has already arranged its terminal the way the
	/// setting asks. Only the first project it opens counts.
	var hasArrangedTerminal = false
	/// Whether the editor has the window, and what to put back when it gives it
	/// up.
	///
	/// The two answers are remembered rather than assumed: somebody who was
	/// working with the sidebar already shut does not want it opened for them by
	/// un-maximising, and the panel is the same. Nil while nothing is maximised,
	/// so a stale pair cannot be restored over a window somebody has since
	/// rearranged by hand.
	var beforeEditorMaximized: (navigator: Bool, panel: Bool)?
	var heightBeforeMaximize: CGFloat?
	/// Whether the panel has the window to itself, and what to restore.
	var isPanelMaximized = false

	/// What to do once the shell being waited for has answered, so that a second
	/// container is opened after the first rather than beside it.
	var afterContainerShellForTesting: (() -> Void)?

	/// Which section a capture run asked for.
	var settingsSectionForTesting: String?
	/// And which one it asked to be folded away, since a triangle needs a click.
	var settingsFoldForTesting: String?

	/// What each project had open, so going back to one looks as it was left.
	var sessions = ProjectSessions()
	/// Whether the window follows the terminal's working directory.
	/// Whether this window follows the terminal into another project.
	///
	/// Starts from the setting and is a per-window switch afterwards: one
	/// window following a terminal about while another stays where it was put
	/// is a reasonable way to work.
	var followsTerminal = Settings.shared.followsTerminalProject

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
	private(set) lazy var sidebar: SidebarController = makeSidebar()

	private func makeSidebar() -> SidebarController {
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
		bar.giveTheEditorTheWindow = { [weak self] in self?.giveTheEditorTheWindow() }
		bar.isPanelVisible = { [weak self] in self?.isPanelVisible ?? false }
		bar.readGit = { [weak self] in self?.readGit() }
		bar.openProject = { [weak self] url in
			guard let self else { return }
			(NSApp.delegate as? AppDelegate)?.open(projectAt: url, from: self)
		}
		return bar
	}

	/// Breakpoints and the stopped line, which outlive any one session.
	lazy var debug: DebugCoordinator = makeDebug()

	private func makeDebug() -> DebugCoordinator {
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
	}

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
	var toolStrip: ToolWindowBar { sidebar.rail }

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
		bar.isEditorMaximized = { [weak self] in self?.isEditorMaximized ?? false }
		bar.onToggleEditorMaximized = { [weak self] in self?.toggleEditorMaximized(nil) }
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

	var splitView: NSSplitView!
	var verticalSplitView: NSSplitView!
	/// How wide the tree is, kept as a constraint so nothing else decides.
	var navigatorWidthConstraint: NSLayoutConstraint!
	var panelHeight: CGFloat = 260
	/// True while the panel is being rounded to whole rows, so the resize that
	/// causes cannot ask for another one.
	fileprivate var isSnappingPanel = false
	var navigatorContainer: ColoredView!
	/// Painted behind the toolbar, since the titlebar itself is transparent.
	/// Everywhere the editor has been, and where in it we are.
	var navigation = NavigationHistory()
	/// Set while going back or forward, so retracing steps is not itself a step.
	var isNavigatingHistory = false

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
	var branchRead: Task<GitRepository.Head?, Never>?
	var toolStripWidthConstraint: NSLayoutConstraint!

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
	func startWatchingRepository(at root: URL) {
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
	func updateTopInsets() {
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

	// MARK: - Debugging anything

	// MARK: - Debugging

	// MARK: - Bottom panel

	// MARK: - Following the terminal

	// MARK: - Go

	enum GoAction { case run, build, test, trace, profile, debug }

	// MARK: - Running

	// MARK: - The devcontainer in the titlebar

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

	// MARK: - Navigation history

	// MARK: - Running in a cluster


	// MARK: - The other ways to start




	// MARK: - Hot code replace


	// MARK: - Zoom

	// MARK: - Actions

	/// Opens the sidebar, whichever way it came to be shut.
	func openNavigator() {
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

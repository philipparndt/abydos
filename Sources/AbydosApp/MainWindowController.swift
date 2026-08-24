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
	/// The sidebar, split horizontally: the tool above, a results list below
	/// when one has been put there. One arranged subview and no divider until
	/// then — see where it is built.
	private var sidebarSplit: ThinDividerSplitView!
	/// The lower half, while a list is living in it.
	private var sidebarDock: ColoredView?
	/// How much of the sidebar's height the tool keeps, remembered so a list
	/// coming back finds the divider where it was left rather than halfway.
	private var sidebarToolFraction: CGFloat = 0.55
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
	private var worktreePill: WorktreePillButton!
	private var devContainerPill: DevContainerPillButton!

	/// Every checkout of this repository, most recently worked on first, as the
	/// worktree pill's menu will offer them.
	///
	/// Kept rather than asked for when the menu opens: `readWorktree` has already
	/// run git for the pill itself, so a second listing at the moment somebody
	/// clicks would be the same answer bought again with a pause in front of it.
	private var worktrees: [GitWorktree] = []
	/// Reading the repository, as a job rather than an answer.
	///
	/// The toolbar builds its items when it chooses, and in a repository small
	/// enough git answers first — so a pill that is only ever *told* the branch
	/// misses it. Anything that needs the branch awaits this instead, whenever
	/// it happens to come into existence.
	/// The whole of HEAD and not just its name: a branch with nothing committed
	/// on it is drawn differently, and the capsule cannot tell from a string.
	private var branchRead: Task<GitRepository.Head?, Never>?
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
			self?.editor.open(
				fileURL: url,
				atLine: location.range.start.line + 1,
				column: location.range.start.character + 1,
				length: location.range.widthOnOneLine
			)
		}
		return palette
	}()

	/// Where everywhere-this-is-used is listed.
	///
	/// One per window, made once and moved between its two hosts rather than
	/// rebuilt for each: the ticks somebody has put on the list are in it, and a
	/// pane rebuilt on the way to a window would arrive with the work undone.
	private lazy var usagesPane: UsagesPane = {
		let pane = UsagesPane()
		pane.onOpen = { [weak self] url, match, intent in
			self?.openFromChecklist(url, match: match, intent: intent)
		}
		pane.onPlace = { [weak self] home in self?.placeUsages(at: home) }
		return pane
	}()

	/// The window a results list has been expanded into, one per list, while
	/// there is one.
	private var usagesWindow: ResultsWindow?
	private var searchWindow: ResultsWindow?

	/// Where the next answer to each question appears.
	///
	/// **Per window, per list, in memory, and not written to disk.** Coming back
	/// docked when somebody has just asked for a window is an answer nobody
	/// believes, so the choice has to be remembered somewhere; the question is
	/// how long for. A results list is transient and so is the reason for
	/// putting it where it is — this symbol has two hundred usages and the panel
	/// is forty rows tall, or this search wants to sit under the tree while the
	/// terminal keeps the panel. That is the shape of the current job rather
	/// than a preference about the program, which is why it is not in
	/// `Settings`: one move would otherwise decide how Find Usages behaved for
	/// months. Per project was the other candidate and was ruled out for the
	/// same reason plus a worse one — it would be the only thing in
	/// `ProjectSession` that is about a list nothing restores.
	///
	/// It survives the window being closed, which is the case item 470 named:
	/// expand, read it, close it, ask again, and the answer is a window.
	///
	/// **One each rather than one between them**, which item 506 had to decide.
	/// They are the same widget and the spec says so, but they are reached by
	/// different actions with different rhythms: a search is a question being
	/// refined, so it wants to stay where it can be typed at, and a usage list
	/// is a job being walked, so it wants to be wherever there is room. Somebody
	/// who sends a two-hundred-row usage list to a window has said nothing about
	/// where ⇧⌘F should answer, and a shared placement would make them say it.
	private var usagesPlacement: ResultPlacement = .panel
	private var searchPlacement: ResultPlacement = .panel

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

	/// The editor's own text, drawn to a PNG.
	@discardableResult
	func writeEditorImageForTesting(to path: String) -> Bool {
		editor.writeEditorImageForTesting(to: path)
	}

	/// What the panel's tab strip is showing and what it is holding back.
	var panelOverflowReportForTesting: String { bottomPanel.overflowReportForTesting }

	/// Chooses one of the tabs the strip had no room for, as its menu entry
	/// would — so that the run moving to bring it into view can be looked at.
	func selectHiddenPanelTabForTesting(_ position: Int) -> String {
		bottomPanel.selectHiddenTabForTesting(position)
	}

	func addTerminalTabForTesting() {
		bottomPanel.addTabForTesting()
	}

	func closeTerminalTabsForTesting() {
		bottomPanel.closeTerminalTabsForTesting()
	}

	@discardableResult
	func closeTerminalTabsForTesting(count: Int) -> String {
		bottomPanel.closeTerminalTabsForTesting(count: count)
	}

	func clickPanelTabForTesting(_ index: Int) -> String {
		let said = bottomPanel.clickPanelTabForTesting(index)
		// Where the keyboard landed, which is the whole of what reaching for a
		// pane means: a tree nobody can walk is a tree nobody selected.
		return said + " | " + bottomPanel.variablesKeyboardReportForTesting()
	}

	/// Brings a tmux window forward, as clicking its tab would.
	/// Presses ⌃C in the debugger's console, for `--debug-interrupt`.
	func pressDebugInterruptForTesting() -> String {
		bottomPanel.activeDebugPane?.pressInterruptForTesting() ?? "no debug session"
	}

	/// What the rail is showing, for `--rail`.
	///
	/// The panel's own state leads, because the rail's rule is written in terms
	/// of it and a report that said only which buttons were lit could not tell a
	/// closed panel from a bug.
	func railReportForTesting() -> String {
		"panel=\(isPanelVisible ? "open" : "closed") " + toolStrip.reportForTesting()
	}

	/// Shuts the panel, for `--close-panel`.
	func closePanelForTesting() {
		setPanelVisible(false)
	}

	/// Tells the rail which panes are in front.
	///
	/// The same shape as the `setSidebarSelection` call beside it, which is the
	/// point: both groups of the rail now answer one question in one way.
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
		// `NSWindow Frame IdeaiMainWindow` — so the only way a driven run leaves
		// somebody's window where they left it is not to take the name. 0522
		// caught this by driving a run and diffing `defaults` either side of it:
		// nothing this program writes had moved, and the split frames had.
		if DrivenRun.isActive {
			window.setFrameUsingName("IdeaiMainWindow")
		} else {
			window.setFrameAutosaveName("IdeaiMainWindow")
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
		buildTitlebarBackdrop()
		// From the moment there is a window, not only from the moment somebody
		// clicks on one: a driven run never makes a window key, and a server
		// asking to apply an edit in that gap would be told there was nowhere to
		// apply it.
		takeServerEdits()

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
			MainActor.assumeIsolated { self?.refreshDevContainerPill() }
		}

		// And when the answer changes rather than the container: a project whose
		// servers were moved onto this machine keeps its container up, and the
		// pill has to stop claiming the project is being worked on inside it.
		NotificationCenter.default.addObserver(
			forName: .ideaiLanguageServersMoved,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.refreshDevContainerPill() }
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
			MainActor.assumeIsolated { self?.refreshDevContainerPill() }
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
		// than repeated: `sidebarSplit` holds exactly one arranged subview
		// whenever nothing is docked below, and an `NSSplitView` with one subview
		// draws no divider at all. There is nothing to reach until there is
		// something to reach for.
		let toolContainer = ColoredView(color: Theme.current.sidebarBackground)
		toolContainer.colourSource = { Theme.current.sidebarBackground }

		sidebarSplit = ThinDividerSplitView()
		sidebarSplit.isVertical = false
		sidebarSplit.dividerStyle = .thin
		sidebarSplit.addArrangedSubview(toolContainer)
		sidebarSplit.translatesAutoresizingMaskIntoConstraints = false
		navigatorContainer.addSubview(sidebarSplit)
		NSLayoutConstraint.activate([
			sidebarSplit.topAnchor.constraint(equalTo: navigatorContainer.topAnchor),
			sidebarSplit.bottomAnchor.constraint(equalTo: navigatorContainer.bottomAnchor),
			sidebarSplit.leadingAnchor.constraint(equalTo: navigatorContainer.leadingAnchor),
			sidebarSplit.trailingAnchor.constraint(equalTo: navigatorContainer.trailingAnchor),
		])

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
		// No name in a driven run, for the reason the window frame gives: an
		// autosaved split writes `UserDefaults.standard` from inside AppKit. A
		// capture that wants a particular sidebar says so with `--sidebar-width`,
		// which is what `Scripts/screenshots.sh` has always done and why.
		splitView.autosaveName = DrivenRun.isActive ? "" : "IdeaiSplit"
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
		verticalSplitView.autosaveName = DrivenRun.isActive ? "" : "IdeaiPanelSplit"
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
		bottomPanel.onRunAgain = { [weak self] in self?.runSelectedConfiguration(debug: false) }
		bottomPanel.onDebugAgain = { [weak self] in self?.runSelectedConfiguration(debug: true) }
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
			self.openFromChecklist(url, match: match, intent: intent)
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
			self?.changesPane?.refresh()
			// A new main.go or Makefile target should get its play button
			// without reopening the project — but only when what was written
			// could be one. See `refreshRunConfigurations(because:)`.
			self?.refreshRunConfigurations(because: change)
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
		// **Offered only where git can do it.** `stash push --staged` arrived
		// in 2.35; on an older one the item is absent rather than a menu entry
		// that fails when pressed. Asked once, when the window is built.
		if let root = project?.root {
			Task { @MainActor [weak self] in
				guard await GitStash.canPushStaged(in: root) else { return }
				self?.editor.onStashDiffSelection = { [weak self] change, diff, selected in
					self?.stashDiffSelection(change: change, diff: diff, lines: selected)
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
					self.capsule?.isReadingBranch = false
					self.capsule?.setBranch(head?.name, isUnborn: head?.isUnborn ?? false)
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
		worktreePill?.invalidateIntrinsicContentSize()
		devContainerPill?.invalidateIntrinsicContentSize()
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
		capsule?.isReadingBranch = true
		layoutTitlebarPills()
		let read = Task { @MainActor [weak self] () -> GitRepository.Head? in
			guard let self, let project = self.project else { return nil }
			await project.loadGit()
			return await project.git?.currentHead()
		}
		branchRead = read

		Task { @MainActor [weak self] in
			let head = await read.value
			guard let self, !Task.isCancelled else { return }
			self.capsule?.isReadingBranch = false
			self.capsule?.setBranch(head?.name, isUnborn: head?.isUnborn ?? false)
			if ProjectSwitcherPopover.reportsForTesting {
				print(String(format: "BRANCHPILL appeared after %8.2f ms  (%@)",
					Date().timeIntervalSince(askedAt) * 1000, head?.name ?? "no branch"))
				fflush(stdout)
			}
			// The capsule only gets its width once it has a name to show.
			self.layoutTitlebarPills()
			self.navigator.refreshGitStatus()

			// Changes, history and branches hold on to one repository, so a
			// *different* work tree needs them built again — which is what
			// this said and not what it did. Rebuilding whatever the answer
			// came back as threw away a pane somebody was already using:
			// reading the repository finishes a second or two after a window
			// opens, and it took with it the commit message half typed into the
			// pane and the folders unfolded in it.
			if self.currentSidebarTool == .changes || self.currentSidebarTool == .branches {
				let holding = self.currentSidebarTool == .changes
					? self.changesPane?.repositoryRoot
					: self.branchesPane?.repositoryRoot
				if holding != (self.scopeRoot ?? self.project?.root) {
					self.install(tool: self.currentSidebarTool, force: true)
				}
			}
			self.refreshRunConfigurations()
		}
		return read
	}

	/// Names the window after the repository, and fills the pill that says which
	/// of its checkouts this is.
	///
	/// A linked worktree is another checkout of the same project, so
	/// `ideai/.claude/worktrees/titlebar-capsule` is still ideai — naming it
	/// after its folder would name the checkout and lose the project. The pill
	/// beside the name says which checkout it is, and opens the list of them.
	///
	/// **The whole list is kept, and 0490 is why.** This asked git for every
	/// checkout, found the one containing this window and threw the rest away, so
	/// the titlebar could say which worktree it was on and offer no way to any
	/// other — and on the primary it said nothing at all, because "primary" was
	/// read as "nothing to say". That is the report: `~/dev/abydos` showed
	/// `abydos | main` and no sign that fifty other checkouts existed.
	///
	/// Asked of git rather than read off the path: a worktree can be created
	/// anywhere, including outside the repository it belongs to.
	private func readWorktree() {
		guard let project else { return }
		let root = project.root

		Task { @MainActor [weak self] in
			let listed = await GitWorktrees.list(in: root)
			// Another project may have been opened while git was answering.
			guard let self, self.project?.root == root else { return }

			// The window may be opened at the worktree itself or somewhere
			// inside it, so the deepest one containing this root is the one.
			//
			// Deepest matters more than it looks here: an agent harness puts its
			// checkouts under `<the primary>/.claude/worktrees/`, so the primary
			// contains them by path and a shallower match would name every one of
			// those windows after the wrong checkout.
			let containing = listed
				.filter { root.path == $0.path.path || root.path.hasPrefix($0.path.path + "/") }
				.max { $0.path.path.count < $1.path.path.count }

			// Ordered once, here, so the menu is not sorting seventy-four entries
			// in front of somebody who has just clicked. Most recently worked on
			// first, from mtimes rather than from git — the same estimate, and the
			// same reasoning, the project switcher's scan uses.
			self.worktrees = GitWorktrees.byRecentActivity(listed)

			if let primary = listed.first(where: { $0.isPrimary }), containing?.isPrimary == false {
				self.capsule?.setProject(name: primary.name)
			}

			// One checkout is not a choice, and a repository nobody has added a
			// worktree to should not carry a control explaining that it has one.
			let primaryName = listed.first { $0.isPrimary }?.name ?? root.lastPathComponent
			self.worktreePill?.setWorktree(
				listed.count > 1 ? containing.map {
					// The words are whatever the capsule beside it has not
					// already said — which on the primary, and on a worktree
					// named after the branch showing a foot to the left, is
					// nothing at all.
					WorktreePillButton.State(
						name: GitWorktrees.qualifier(for: $0, primaryName: primaryName),
						full: $0.name,
						isPrimary: $0.isPrimary
					)
				} : nil,
				count: listed.count
			)
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
		// The files already on screen belong to the new scope's servers now.
		// Without this the container's server comes up knowing about nothing,
		// and the file somebody is looking at is the one it has not been told
		// about — which is 0432 from the other end.
		editor.rescope()
		startWatchingRepository(at: scope)
		bottomPanel.setWorkingDirectory(scope)

		subprojectPill?.setSubproject(
			subprojectRoot.map { Subprojects.relativePath($0, to: project.root) }
		)
		// The devcontainer is the subproject's whenever it has one, so moving
		// between them moves which container the titlebar is talking about.
		refreshDevContainerPill()
		layoutTitlebarPills()
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
		subprojectPill?.setSubproject(nil)
		window?.title = project.name

		// No badge and no colour: which project this is gets stated once, by the
		// name, and colour is kept for the switcher — where there is more than
		// one project on screen and it has something to tell apart.
		capsule?.setProject(name: project.name)
		// Cleared rather than left standing: the pill of the project being left
		// would sit in the titlebar of the one arriving until git answered, and
		// the two repositories have nothing to do with each other.
		worktrees = []
		worktreePill?.setWorktree(nil)
		capsule?.setBranch(nil)
		// Reading, not absent: this window is about to ask git about the project
		// that has just arrived, and that is what the half should say meanwhile.
		capsule?.isReadingBranch = true
		refreshDevContainerPill()
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

	/// Puts the pointer on the ✕ of every tab of every strip in the window and
	/// says what each strip made of it, then photographs the window with the
	/// first ✕ of each hovered and again with the pointer off them all.
	///
	/// The strips are found by walking the window rather than asked of the editor
	/// and the panel in turn. What is being checked is that the two agree, and one
	/// walk both puts them in the same picture and picks up a third strip if
	/// somebody adds one — which is how this went wrong in the first place: the
	/// editor's strip grew a hover and the panel's was somewhere else.
	func tabCloseHoverForTesting(to path: String) {
		guard let window else { return }
		bottomPanel.seedUnclosableTabForTesting()
		window.contentView?.layoutSubtreeIfNeeded()
		let strips = Self.tabStrips(under: window.contentView)

		print("HOVER: \(strips.count) strips")
		// Every tab, not only the first: the one that must *not* light up is a
		// tmux window, and tmux's windows are never at the front of a strip.
		for strip in strips {
			for index in 0..<max(strip.tabCountForTesting, 1) {
				print("  on  \(strip.hoverCloseForTesting(index))")
			}
			strip.hoverCloseForTesting(0)
		}
		WindowCapture.write(window: window, to: path)

		for strip in strips { print("  off \(strip.hoverCloseForTesting(nil))") }
		WindowCapture.write(
			window: window, to: (path as NSString).deletingPathExtension + "-left.png"
		)
		fflush(stdout)
	}

	private static func tabStrips(under view: NSView?) -> [any TabCloseHovering] {
		guard let view else { return [] }
		let here = view as? (any TabCloseHovering)
		return (here.map { [$0] } ?? []) + view.subviews.flatMap { tabStrips(under: $0) }
	}

	/// Draws the sidebar's pane into a file, whatever the window is doing.
	///
	/// The window capture goes through the compositor and a pane that has just
	/// been built is not always in it yet; this asks the view itself.
	/// Says whether it wrote one, so a run that could not can exit non-zero
	/// rather than leaving a stale file and a zero status behind it.
	@discardableResult
	func snapshotSidebarForTesting(to path: String) -> Bool {
		guard let view = primaryToolView, view.bounds.width > 1 else { return false }
		guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
		view.cacheDisplay(in: view.bounds, to: rep)
		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		return (try? data.write(to: URL(fileURLWithPath: path))) != nil
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
			fflush(stdout)
		}
	}

	/// Looks at where the debugger stopped, without moving it.
	func inspectDebugStateForTesting() {
		let stoppedAt = executionMarker.map { "\(($0.file as NSString).lastPathComponent):\($0.line)" }
			?? "not stopped"
		print("INSPECT: stopped at \(stoppedAt)")
		// What the editor is drawing beside the code, which is the half of a
		// stop that used to be readable only in the panel.
		print("VALUES:\n\(editor.inlineValueReportForTesting())")
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
		// What is beside the code at this step, which is the claim that the
		// values follow execution rather than being drawn once and left.
		print("VALUES:\n\(editor.inlineValueReportForTesting())")

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
			fflush(stdout)
			}
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

	/// Find, in every tab, and then the gesture the report is about.
	///
	/// Search in the file in front, switch to the next tab, and step — which is
	/// where one file's offsets used to reach another file's view.
	func exerciseFindAcrossTabsForTesting() {
		print("FIND before:\n\(editor.activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		editor.activeGroup?.selectNextTab(offset: 1)
		print("FIND after switch:\n\(editor.activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		// The step. Before this change it used the group's matches, which were
		// the *other* file's.
		editor.activeGroup?.findNext()
		print("FIND after step:\n\(editor.activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		// And back, to show the first tab kept what it was doing.
		editor.activeGroup?.selectNextTab(offset: -1)
		print("FIND back:\n\(editor.activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		// Closing the searched tab takes its find state with it, because the
		// state lives on the tab. Asserted rather than assumed: state that
		// outlived its tab is what this change is about.
		if let url = editor.activeGroup?.activeTabURL {
			_ = editor.activeGroup?.closeTab(showing: url)
		}
		print("FIND after close:\n\(editor.activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)
		exit(0)
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

	/// Drags a tab onto the group's right-hand zone, the way another group would.
	///
	/// **The regression check for the drop path**, which this change edited: a
	/// file drag and a tab drag now arrive at the same `performDragOperation`,
	/// and the tab must still split. Driven rather than tested because
	/// `EditorTabDrag` lives in the app target, where the suite cannot reach it.
	func dragTabForTesting() {
		guard let group = editor.activeGroup, let target = group.view as? EditorDropView else {
			print("TABDRAG: no drop view")
			fflush(stdout)
			return
		}
		print("TABDRAG before: groups=\(editor.groupCountForTesting)"
			+ " tabs=[\(editor.openTabNamesForTesting)]")

		let payload: [String: Any] = [
			"group": group.groupID.uuidString, "index": 0,
			"path": group.activeTabURL?.path ?? "",
		]
		let board = NSPasteboard(name: .init("dev.abydos.tabdrag-test"))
		board.clearContents()
		board.setData(
			try? JSONSerialization.data(withJSONObject: payload),
			forType: EditorTabDrag.pasteboardType
		)

		// Well to the right, which is the zone that splits — **in window
		// coordinates**, because `updateZone` converts `draggingLocation` from
		// nil, which is the window. Handing it view coordinates put the point in
		// the centre zone, and a centre drop onto a tab's own group is refused
		// by design: the first run of this read as a broken split and was a
		// broken harness.
		let inView = NSPoint(x: target.bounds.width * 0.9, y: target.bounds.midY)
		let drag = TestingDrag(pasteboard: board, at: target.convert(inView, to: nil))
		let offered = target.draggingEntered(drag)
		print("TABDRAG offered: \(offered.contains(.move) ? "move" : "other")")
		_ = target.performDragOperation(drag)
		fflush(stdout)

		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			guard let self else { return }
			print("TABDRAG after: groups=\(self.editor.groupCountForTesting)")
			fflush(stdout)
			exit(0)
		}
	}

	/// The geometry every board card is drawn with, for `--card-report`.
	func cardGeometryForTesting() -> String {
		bottomPanel.existingBacklogPane?.cardGeometryReportForTesting ?? "no pane"
	}

	/// Which server root the file in front is filed under, for `--lsp-root`.
	func serverRootReportForTesting() -> String {
		editor.activeGroup?.serverRootReportForTesting ?? "no group"
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
			session.selectedConfiguration = selectedConfigurationName
			session.xcodeDestinations = xcodeDestinations
			session.breakpoints = breakpointsToRemember()
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
		session.selectedConfiguration = selectedConfigurationName
		session.xcodeDestinations = xcodeDestinations
		session.breakpoints = breakpointsToRemember()
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

	/// Takes a completion and steps through its stops with Tab, saying where
	/// the caret and selection went. `--snippet 'cube(${1:size});$0|10|tab'`.
	func exerciseSnippetForTesting(_ spec: String) {
		editor.exerciseSnippetForTesting(spec)
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
				let before = editorTextForTesting()
				let handled = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
				let after = editorTextForTesting()
				print("COMMENTKEY \(name) at the real menu: answered "
					+ "\(handled ? "it" : "NOTHING") and the text "
					+ "\(before == after ? "DID NOT CHANGE" : "changed")")
			}
		}
		fflush(stdout)
	}

	func setFindQuery(_ query: String) { editor.setFindQuery(query) }

	/// `--find-next`: ⌘G with the keyboard back in the code. Says where the
	/// keyboard ended up, since that is the whole claim the picture it is taken
	/// for makes — the same reason `selectLinesForTesting` reports it.
	func findNextFromEditorForTesting(_ times: Int) {
		editor.findNextFromEditor(times)
		let responder = window?.firstResponder
		print("FIND NEXT \(times) keyboard=\(responder.map { String(describing: type(of: $0)) } ?? "nothing")")
		fflush(stdout)
	}

	func setProjectSearchQuery(_ query: String) {
		showProjectSearch(query: query)
	}

	/// ⇧⌘F, wherever the last answer to it was.
	///
	/// The placement is honoured before the query is typed, because the field
	/// has to be in a window to take the keyboard and the move is what puts it
	/// in one.
	private func showProjectSearch(query: String?) {
		guard let pane = bottomPanel.makeSearchPaneIfNeeded() else { return }
		pane.onPlace = { [weak self] home in self?.placeSearch(at: home) }
		placeSearch(at: searchPlacement, focusList: false)
		if let query { pane.setQuery(query) }
		// The field rather than the list: asking for search is asking a question,
		// and the question is typed. A *move* puts the keyboard in the rows —
		// that pane already has an answer in it.
		pane.focusField()
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
		showProjectSearch(query: editor.selectedTextForSearch())
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
		session.onHotSwap = { [weak self, weak session] event, wasStopped in
			guard let self, let session else { return }
			self.reportHotSwap(event, wasStopped: wasStopped, in: session)
		}
		session.onBreakpointsChanged = { [weak self, weak session] in
			guard let self, let session else { return }
			self.syncBreakpointsToEditor(from: session)
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
				// A value that was true at the last breakpoint is not true a
				// microsecond after `continue`, and it is drawn in the same grey
				// either way.
				self?.editor.setInlineValues(nil)
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

	/// Where each Xcode project was last sent, keyed as
	/// `XcodeDestinationMemory` says — by project, not by scheme. Kept with the
	/// project's session, so a project that went to the phone yesterday goes
	/// there again today rather than back to a simulator.
	var xcodeDestinations: [String: String] = [:]

	/// One scan at a time, with at most one more queued behind it — the shape
	/// `refreshGitStatus` has had all along.
	private var isDiscoveringRunConfigurations = false
	private var wantsAnotherRunConfigurationScan = false

	/// What the scan has been asked for and what it actually did, for
	/// `--report-open`.
	///
	/// Three numbers rather than one, because the fix has two halves and only
	/// separate counts say which half is working: `asked` is how often something
	/// wanted a scan, `skipped` is how many of those wrote nothing that could
	/// define a configuration, and `walked` is how many whole-project walks
	/// actually happened. Before 0446 the three were equal by construction.
	struct RunConfigurationTally {
		var asked = 0
		var skipped = 0
		var coalesced = 0
		var walked = 0
	}
	nonisolated(unsafe) static var runConfigurationTallyForTesting = RunConfigurationTally()

	/// Rescans, but only if this batch of writes could have changed the answer.
	///
	/// A language server importing a Tycho reactor writes `.project`,
	/// `.classpath` and `.settings` into every bundle it touches, and each of
	/// those arrives here as a filesystem event. None of them can add a `main`
	/// method or a Makefile target, so none of them is worth a walk of 45,772
	/// Java files — which is what each one used to cost.
	func refreshRunConfigurations(because change: FileSystemChange) {
		Self.runConfigurationTallyForTesting.asked += 1
		guard RunConfigurationDiscovery.deservesRescan(after: change) else {
			Self.runConfigurationTallyForTesting.skipped += 1
			return
		}
		refreshRunConfigurations()
	}

	func refreshRunConfigurations() {
		guard let project else { return }
		let root = project.root

		// Coalesced, because the filter above is not a guarantee: a `git
		// checkout` across a large repository names thousands of Java files in
		// a few batches, and every one of those batches is a legitimate reason
		// to scan. Uncoalesced, the concurrent queue answers a burst by making
		// more threads, and every walk but the last is stale before it finishes.
		guard !isDiscoveringRunConfigurations else {
			wantsAnotherRunConfigurationScan = true
			Self.runConfigurationTallyForTesting.coalesced += 1
			return
		}
		isDiscoveringRunConfigurations = true
		Self.runConfigurationTallyForTesting.walked += 1

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let found = RunConfigurationDiscovery.discover(in: root)
			DispatchQueue.main.async {
				guard let self else { return }
				self.isDiscoveringRunConfigurations = false
				self.runConfigurations = found

				// Group by file so the gutter can put a play button beside each
				// entry point and each make target.
				var byFile: [String: Set<Int>] = [:]
				for configuration in found {
					guard let file = configuration.file, let line = configuration.line else { continue }
					byFile[file, default: []].insert(line)
				}
				self.editor.setRunnableLines(byFile)

				if self.wantsAnotherRunConfigurationScan {
					self.wantsAnotherRunConfigurationScan = false
					self.refreshRunConfigurations()
				}
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

			// Listing a Debug that cannot start would be worse than leaving it
			// out. Go goes through Delve; Java goes through an adapter inside a
			// jdtls, which since 0452 is started for the debugger alone when the
			// server editing the project is not one that hosts it — so what has to
			// be asked here is whether *anything* can host it, not which server
			// happens to be answering about files.
			if configuration.isDebuggable, javaDebugSettledRefusal(configuration) == nil {
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

	/// Why Java cannot be debugged here at all, when nothing anybody does now
	/// would change it — and nil for everything else, including the reasons that
	/// are worth offering and explaining.
	///
	/// Nil for a configuration that is not Java, which is most of them: the
	/// question is about the Java debugger and asking it of a Go package would
	/// walk a project for markers that decide nothing.
	private func javaDebugSettledRefusal(_ configuration: RunConfiguration) -> String? {
		guard configuration.source == .javaMain, let project else { return nil }
		let root = project.scopeRoot
		guard let refusal = JavaDebugHost.refusal(
			project: root,
			inDevContainer: LanguageService.shared.devContainerNameHoldingServers(for: root)
		), refusal.isSettledHere else { return nil }
		return refusal.localizedDescription
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
		let remembered = xcodeDestinations[XcodeDestinationMemory.key(for: target)]

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
		xcodeDestinations[XcodeDestinationMemory.key(for: target)] = destination.id


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

	/// Starts one of the discovered configurations by name, as choosing it from
	/// the run menu does, and reads its console back a few seconds later.
	///
	/// `--run-configs` says what the list holds; this says what one of them
	/// does, which is a different question and the one that catches a
	/// configuration that looks right and does not run. Every line is flushed:
	/// a driver run ends in a kill, and a report still in stdout's buffer when
	/// the signal arrives is a run that looks like it never happened.
	func runNamedConfigurationForTesting(_ name: String) {
		func say(_ text: String) {
			print("RUNCONFIG: \(text)")
			fflush(stdout)
		}

		for configuration in runConfigurations {
			say("  \(title(for: configuration.source)) | \(configuration.name)"
				+ " | \(configuration.commandLine) | in \(configuration.workingDirectory)")
		}

		guard let configuration = runConfigurations.first(where: { $0.name == name }) else {
			say("nothing called \(name)")
			return
		}

		say("starting \(configuration.name)")
		run(configuration)

		// Twice, because how long this takes is not knowable from here: a warm
		// `swift run` is a second and a cold one compiles the world. The first
		// reading says the run started, the second says how it ended.
		for (index, delay) in [8.0, 40.0].enumerated() {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
				guard let self else { return }
				say("after \(Int(delay))s, console \(self.bottomPanel.runConsolesForTesting)")
				say("after \(Int(delay))s: "
					+ self.bottomPanel.activeTerminalTailForTesting(lines: index == 0 ? 6 : 14))
			}
		}
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
		let remembered = xcodeDestinations[XcodeDestinationMemory.key(for: target)]
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
		case .swiftPackage: return "Swift Package"
		case .bazel:     return "Bazel"
		case .conan:     return "Conan"
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

	/// Whether the board has any cards yet, for a driver waiting on it.
	func backlogHasCardsForTesting() -> Bool { bottomPanel.backlogHasCardsForTesting() }

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
		for item in choices.isEmpty ? [containerMenuItem(for: nil)] : choices.map(containerMenuItem) {
			item.target = self
			// This is what names it after the container as well as what greys it
			// out — the item says "New Terminal in <the devcontainer's own name> ⬢"
			// for a project that has one, and stays grey and generic for the rest.
			item.isEnabled = validateMenuItem(item)
			menu.addItem(item)
		}
		return menu
	}

	/// One entry offering a shell in one container, or the grey generic one.
	///
	/// The choice travels on the item, because with several of them the title is
	/// not enough to act on — what is clicked has to name the file it meant, or
	/// the second entry would open the first entry's container.
	private func containerMenuItem(for choice: DevContainerFile.Choice?) -> NSMenuItem {
		let item = NSMenuItem(
			title: Self.containerTerminalTitle,
			action: #selector(newTerminalInContainer(_:)),
			keyEquivalent: ""
		)
		item.representedObject = choice?.file
		return item
	}

	/// What the + and its chevron answer to, for the harness.
	var terminalAddControlsForTesting: String { bottomPanel.addControlsForTesting }

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

	/// The container the pill is naming, so its menu acts on exactly what the
	/// words on it say rather than on whichever container is preferred.
	private var pilledContainer: DevContainerFile.Choice?

	/// Says in the titlebar which devcontainer this project is being worked on
	/// inside — or, dimmed, which one it has and is not using.
	///
	/// **Two states rather than one, which is 0438's third fault.** 0433 made this
	/// pill say *running*, and took it away for both declines; the way back out of
	/// a decline lives in this pill's menu, so the gesture that most needed
	/// undoing was the one that removed its own undo. The strip above a file
	/// carries a button too, but only over a file whose server is missing, so
	/// somebody who declined and then worked on something else had nothing on
	/// screen at all — which is how it was reported: gone for good.
	///
	/// So the pill is now about the `devcontainer.json`, which is what
	/// `hasDevContainer` has always been about, and its two states are the
	/// difference 0433 was right to insist on. Lit with the `⬢`: this project's
	/// tools are in that container. Dimmed without it: there is one and they are
	/// not. It never claims a container is in use when it is not, which was the
	/// whole of the old rule.
	private func refreshDevContainerPill() {
		guard let pill = devContainerPill else { return }
		guard let root = devContainerRoot else {
			pilledContainer = nil
			pill.setContainer(nil)
			pill.toolTip = nil
			layoutTitlebarPills()
			return
		}
		let choices = devContainerChoices
		let consent = LanguageService.shared.devContainerConsent(for: root)
		Task { @MainActor in
			// Only a project that said yes has its tools in there. A container left
			// running with somebody's shell in it, under a project whose servers
			// were put on this machine, is a container this project is not using.
			let running = consent == .container
				? await DevContainers.shared.existingSessions(for: root)
				: []
			// Still the same project by the time the actor answered: a window that
			// switched project meanwhile must not be labelled with the old one's.
			guard self.devContainerRoot == root else { return }
			// **The one this project's tools belong in, not the first one that is
			// up.** A project may have two containers running at once — the one it
			// was switched away from is deliberately left going, because somebody's
			// shell may be in it — so "whichever sorts first" would leave the pill
			// naming the container the project moved *off*, which is what it did
			// until it was watched doing it. What the project's servers are in is
			// what was written down, and this lights only once that one is really up.
			//
			// Named from the menu's own choices, so the pill, the tab in the same
			// container and the menu item that opens one cannot come to disagree
			// about what it is called.
			let wanted = LanguageService.shared.containerChoice(for: root)
			let inUse = wanted.flatMap { choice in
				running.contains {
					FilePath.canonical($0.configuration.file) == FilePath.canonical(choice.file)
				} ? choice : nil
			}
			self.pilledContainer = inUse ?? wanted ?? choices.first
			let name = Self.containerName(for: self.pilledContainer, in: root)
			pill.setContainer(Self.containerMark, inUse: inUse != nil)
			// **The tool tip carries the name in both states now**, because the pill
			// no longer does — 0444's part 3. It said nothing at all while a
			// container was in use, which was right when the name was written across
			// the titlebar and is not right now that hovering is one of the two
			// places the name is.
			pill.toolTip = inUse != nil
				? DevContainerConsent.pillInUse(container: name)
				: self.devContainerStateSentence(for: root, container: name, consent: consent)
			self.layoutTitlebarPills()
		}
	}

	/// What state a container that is not in use is in, in one sentence.
	///
	/// **"It is starting" is only true while it is.** The answer stays on file
	/// when a start fails — somebody did say yes and has not changed their mind —
	/// so the consent alone cannot tell the gap between the answer and the
	/// container from a container that will never arrive, and the pill said
	/// "starting" for the rest of the session. Seen while watching a
	/// `postCreateCommand` fail in the pane 0444's part 4 added.
	private func devContainerStateSentence(
		for root: URL, container: String, consent: DevContainerConsent?
	) -> String {
		if consent == .container, LanguageService.shared.devContainerFailedToStart(for: root) {
			return DevContainerConsent.pillCouldNotStart(container: container)
		}
		return DevContainerConsent.pillState(consent, container: container)
	}

	@objc fileprivate func showDevContainerMenuItem(_ sender: Any?) { showDevContainerMenu() }

	/// What the pill offers: the file it came from, and the way out of it.
	///
	/// **Not a rebuild.** Throwing the image away and building it again is a real
	/// gesture and it is not here: nothing in this app removes an image yet, and
	/// a "Rebuild" that only restarted the container would be a button that looks
	/// like it did the expensive thing and did not.
	@objc func showDevContainerMenu() {
		guard devContainerPill?.hasContainer == true else { return }
		let anchor: NSView? = devContainerPill ?? capsule
		devContainerPillMenu().popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: (anchor?.bounds.maxY ?? 0) + Theme.current.scaled(4)),
			in: anchor
		)
	}

	/// The menu itself, built rather than shown, so that what it offers can be
	/// read by something other than an eye.
	private func devContainerPillMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		guard let root = devContainerRoot else { return menu }

		let inUse = devContainerPill?.isInUse == true
		let container = Self.containerName(for: pilledContainer, in: root)

		// **The state line is in both states now**, which 0444's part 3 makes
		// necessary rather than merely tidy: the pill has stopped saying the
		// container's name, so this menu and the tool tip are the two places it is
		// said, and a menu that dropped out of a pill saying nothing but `⬢` and
		// then said nothing itself would leave a project of ten subprojects unable
		// to say which container it means.
		let state = NSMenuItem(
			title: inUse
				? DevContainerConsent.pillInUse(container: container)
				: devContainerStateSentence(
					for: root,
					container: container,
					consent: LanguageService.shared.devContainerConsent(for: root)
				),
			action: nil,
			keyEquivalent: ""
		)
		state.isEnabled = false
		menu.addItem(state)
		menu.addItem(.separator())

		// **The choice of container, which is 0444's parts 1 and 2 arriving.** The
		// question that starts a container stays three answers however many there
		// are — a devcontainer's name is a sentence, and a button per container is
		// a wall in the corner of the screen — so it names the one it would use and
		// *which* is asked here, where there is room, where somebody is already
		// looking when they think about the container, and where the answer is
		// reversible without reopening the project.
		//
		// **The words differ between the two states because the gesture does.**
		// Nothing running: every entry starts something and says so, which is
		// 0438's "Use <container>" grown from one to one-per-container. One
		// running: the entries are which of them it is, with a mark on the one it
		// is, and clicking another moves the servers there.
		let choices = devContainerChoices
		if inUse {
			// A single ticked entry repeating the sentence above it is noise; the
			// list is only worth having where there is something to choose.
			if choices.count > 1 {
				for choice in choices {
					let item = NSMenuItem(
						title: choice.name,
						action: #selector(useDevContainerFromMenu(_:)),
						keyEquivalent: ""
					)
					item.representedObject = choice.file
					item.target = self
					item.isEnabled = true
					item.state = choice.file == pilledContainer?.file ? .on : .off
					item.toolTip = item.state == .on
						? nil
						: "Move \(root.lastPathComponent)'s language servers into \(choice.name). "
							+ "The ones in \(container) are stopped first."
					menu.addItem(item)
				}
				menu.addItem(.separator())
			}
		} else {
			for choice in choices {
				let use = NSMenuItem(
					title: DevContainerConsent.offerTitle(container: choice.name),
					action: #selector(useDevContainerFromMenu(_:)),
					keyEquivalent: ""
				)
				use.representedObject = choice.file
				use.target = self
				use.isEnabled = true
				use.toolTip = "Run \(root.lastPathComponent)'s language servers inside "
					+ "\(choice.name). The first start builds or downloads its image."
				menu.addItem(use)
			}
			if !choices.isEmpty { menu.addItem(.separator()) }
		}

		// **"New Terminal", not "New Terminal in <the container> ⬢".** The View
		// menu's item and the chevron's beside the panel both have to name the
		// container, because they are read a long way from anything that says
		// which one is meant. This menu drops out of a pill with the name written
		// on it, so repeating it says nothing and leaves three entries that all
		// read as the same length of noise.
		let terminal = containerMenuItem(for: pilledContainer ?? devContainerChoices.first)
		terminal.title = "New Terminal"
		terminal.target = self
		terminal.isEnabled = true
		menu.addItem(terminal)

		if let file = pilledContainer?.file {
			// The path and not the container's name, because this one is about a
			// file and the tab it opens will be called `devcontainer.json` — a
			// project with two of them has two identical tabs otherwise.
			let open = NSMenuItem(
				title: "Open \(file.deletingLastPathComponent().lastPathComponent)"
					+ "/\(file.lastPathComponent)",
				action: #selector(openDevContainerFile(_:)),
				keyEquivalent: ""
			)
			open.target = self
			open.isEnabled = true
			menu.addItem(open)
		}

		// Only while it is in use. Offering to move onto this machine a project
		// that is already on this machine is a switch with nothing on the other
		// side of it, and the state line above has already said so.
		if devContainerPill?.isInUse == true {
			menu.addItem(.separator())

			// Named as the sentence it is rather than as a switch being thrown:
			// this changes which toolchain the code on screen is checked against,
			// and "Disable" would say nothing about what happens instead.
			let here = NSMenuItem(
				title: "Work on This Machine Instead",
				action: #selector(workOnThisMachineFromMenu(_:)),
				keyEquivalent: ""
			)
			here.target = self
			here.isEnabled = true
			here.toolTip = "Run \(root.lastPathComponent)'s language servers on this machine. "
				+ "The container is left running — a terminal may be in it."
			menu.addItem(here)
		}

		return menu
	}

	@objc private func openDevContainerFile(_ sender: Any?) {
		guard let file = pilledContainer?.file else { return }
		openFile(at: file)
	}

	@objc private func workOnThisMachineFromMenu(_ sender: Any?) {
		guard let root = devContainerRoot else { return }
		LanguageService.shared.workOnThisMachine(for: root)
	}

	/// The way in, and the way from one container to another.
	///
	/// One selector for both because it is one sentence — "this project's language
	/// servers belong in that container" — and the three states it can be said
	/// from differ only in what has to be stopped first, which is
	/// `LanguageService.move`'s business and not this menu's. The container
	/// travels on the item, the way the terminal entries' does: with several of
	/// them the title is not something an action can act on.
	@objc private func useDevContainerFromMenu(_ sender: Any?) {
		guard let root = devContainerRoot else { return }
		guard let choice = choice(carriedBy: sender) else {
			LanguageService.shared.useDevContainer(for: root)
			return
		}
		LanguageService.shared.useDevContainer(choice, for: root)
	}

	/// What the pill says, for the harness — a menu cannot be photographed while
	/// it is open, and neither can the absence of a pill be told from a window
	/// that has not finished loading.
	func devContainerPillForTesting() -> String {
		// The scope beside it, because "no pill" has two causes that look
		// identical from outside — this project has no devcontainer, or the window
		// is not pointed at the part of it that has one — and telling them apart
		// is most of what a switched-back window has to be checked for.
		let where_ = " [scope=\(scopeRoot?.lastPathComponent ?? "-")"
			+ " container=\(devContainerRoot?.lastPathComponent ?? "-")]"
		guard let pill = devContainerPill, pill.hasContainer else { return "PILL: (none)\(where_)" }
		// **What it shows and what it means, separately**, since 0444 made them
		// two different things: the pill is the mark alone, and the name it stands
		// for is only in the tool tip and the menu. A dump that printed the name as
		// though it were on the pill would be recording the thing that was
		// deliberately taken off it.
		return "PILL: shows=\(pill.isInUse ? Self.containerMark : "(icon only)")"
			+ " name=\(devContainerPillTitleForTesting)"
			+ " tip=\(pill.toolTip ?? "-")"
			+ where_
	}

	private var devContainerPillTitleForTesting: String {
		Self.containerName(for: pilledContainer, in: devContainerRoot ?? URL(fileURLWithPath: "/"))
	}

	/// What the pill's menu offers, for the harness: a menu cannot be
	/// photographed while it is open, and the way back out of a decline is the
	/// whole of 0438's third fault.
	func devContainerMenuForTesting() -> String {
		guard devContainerPill?.hasContainer == true else { return "PILLMENU: (no pill)" }
		let menu = devContainerPillMenu()
		return "PILLMENU: " + menu.items.map { item in
			guard !item.isSeparatorItem else { return "—" }
			// The tick as well as the words: with several containers listed, which
			// one is marked is the whole of what the list says.
			return (item.state == .on ? "✓" : "")
				+ item.title
				+ (item.isEnabled ? "" : " (disabled)")
		}.joined(separator: " | ")
	}

	/// What the worktree pill says, for the harness.
	///
	/// Absence is the interesting reading and the one a screenshot cannot give:
	/// a repository with one checkout should have no pill at all, and an empty
	/// stretch of toolbar looks exactly like one that has not finished loading.
	/// On the primary the pill is deliberately wordless, so what it *shows* and
	/// what it *is* are printed separately — a dump that read the name off the
	/// drawing would record nothing on the very window the report was about.
	func worktreePillForTesting() -> String {
		guard let pill = worktreePill, pill.hasWorktrees else {
			return "WORKTREE: (none) [listed=\(worktrees.count)]"
		}
		let state = pill.worktree
		return "WORKTREE: shows=\(state?.name ?? "(icon only)")"
			+ " of=\(state?.full ?? "-")"
			+ " at=\(state.map { $0.isPrimary ? "primary" : "linked" } ?? "-")"
			+ " listed=\(worktrees.count)"
			+ " tip=\((pill.toolTip ?? "-").replacingOccurrences(of: "\n", with: " / "))"
	}

	/// What the worktree menu offers, for the harness — including how much of it
	/// went behind `More…`, which is the whole claim on a repository with
	/// seventy-four checkouts.
	func worktreeMenuForTesting() -> String {
		guard worktreePill?.hasWorktrees == true else { return "WORKTREEMENU: (no pill)" }
		func describe(_ items: [NSMenuItem]) -> String {
			items.map { item in
				guard !item.isSeparatorItem else { return "—" }
				let submenu = item.submenu.map { " { \(describe($0.items)) }" } ?? ""
				return (item.state == .on ? "✓" : "") + item.title + submenu
			}.joined(separator: " | ")
		}
		return "WORKTREEMENU: " + describe(worktreeMenu().items)
	}

	/// Presses the pill menu's entry whose words are these.
	@discardableResult
	func pressDevContainerMenuForTesting(_ title: String) -> Bool {
		guard let item = devContainerPillMenu().items.first(where: { $0.title == title }),
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
		let item = containerMenuItem(for: chosen)
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
	/// somebody else's install takes. The tab is there from the first moment
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

	/// Follows ⌘-click, through the same path the click takes.
	func exerciseGoToDefinitionForTesting(line: Int, character: Int) {
		let before = editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing"
		editor.goToDefinitionForTesting(line: line, character: character)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
			guard let self else { return }
			let landed = self.editor.activeGroup?.activeTabURL
			let after = landed?.lastPathComponent ?? "nothing"
			print("DEFINITION: \(before) → \(after) \(self.editor.caretReportForTesting)")
			// The whole path, and not decoration: a server running inside a
			// devcontainer answers about /workspaces/…, and what has to arrive
			// here is the same file named as this machine names it. A report
			// giving only the last component cannot tell the two apart.
			print("DEFINITION-PATH: \(landed?.path ?? "nothing")")
			// Flushed, because the run that asks this is usually killed rather
			// than allowed to exit: a `--lsp-wait` long enough for sourcekit-lsp
			// to index a package leaves the driver's `timeout` to end the app,
			// and an unflushed buffer dies with it. Two runs of this verb
			// reported nothing at all for exactly that reason.
			fflush(stdout)
		}
	}

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
		findUsages(in: url, line: line, character: character)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
			guard let self else { return }
			print("USAGES: where=\(self.usagesPlacement.rawValue) "
				+ "window=\(self.usagesInWindowForTesting) "
				+ "panel=\(self.bottomPanel.existingUsagesPane != nil) "
				+ "sidebar=\(self.sidebarDock?.subviews.first === self.usagesPane) "
				+ "columns=\(self.bottomPanel.columnCountForTesting)")
			fflush(stdout)
			self.usagesPane.stepForTesting("heading")
			self.usagesPane.stepForTesting("who")
		}
	}

	/// Works the usages list from the command line, the way `--search-steps`
	/// works the search one.
	///
	/// `settle` is handled here for the same reason it is there: the list is
	/// filled from an answer that arrives on the main queue, and a script that
	/// pressed on regardless would be asking about rows that had not been built.
	func usagesStepsForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		guard bottomPanel.existingUsagesPane != nil
			|| usagesInWindowForTesting
			|| usagesPane.superview != nil
		else {
			print("USAGES: no list")
			fflush(stdout)
			return
		}
		runUsagesSteps(script)
	}

	private func runUsagesSteps(_ script: [String]) {
		for (index, step) in script.enumerated() {
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = Double(step.dropFirst("settle:".count)) ?? 0.5
				let rest = Array(script.dropFirst(index + 1))
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.runUsagesSteps(rest)
				}
				return
			}
			// What the walk cost the language server, which is the number item 470
			// asked for: a count of notifications rather than a duration, so it
			// means the same on a machine with four builds running on it.
			// The close button on the expanded window, which is being finished with
			// the list rather than asking for it back in the panel.
			if step == "close" {
				usagesWindow?.close()
				continue
			}
			// Find Usages again, at the same place. Two claims need it: the ticks
			// come back on the same symbol, and a window that was expanded and
			// closed is what the next answer opens in.
			if step == "again" {
				if let last = lastUsagesRequest {
					findUsages(in: last.url, line: last.line, character: last.character)
				}
				continue
			}
			if step == "traffic" {
				let group = editor.activeGroup
				print("USAGES traffic: \(LanguageService.shared.documentTrafficForTesting) "
					+ "tabs=\(group?.tabCount ?? 0) "
					+ "[\(group?.tabTitlesForTesting.joined(separator: " ") ?? "")]")
				continue
			}
			usagesPane.stepForTesting(step)
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
		bottomPanel.showProfiler(address: Self.lastProfilerAddress)
	}

	/// Remembered for the session: the same program is usually profiled more
	/// than once in a sitting.
	static var lastProfilerAddress = "localhost:6060"

	/// Whether the usages list is showing in a window rather than in the panel.
	var usagesInWindowForTesting: Bool { usagesWindow != nil }


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

	/// What was last asked about, so a script can ask again — which is how the
	/// two claims about asking twice get checked: the ticks come back, and the
	/// choice of a window is remembered.
	private var lastUsagesRequest: (url: URL, line: Int, character: Int)?

	private func findUsages(in url: URL, line: Int, character: Int) {
		guard let project, let languageId = editor.activeGroup?.activeDocument?.languageId else { return }
		lastUsagesRequest = (url, line, character)

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
			showUsages(
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

	/// Puts one symbol's usages wherever the last answer to that question was.
	private func showUsages(_ locations: [LSPLocation], of symbol: String, at origin: String) {
		usagesPane.show(
			locations: locations, of: symbol, at: origin, root: project?.scopeRoot
		)
		placeUsages(at: usagesPlacement)
	}

	/// `focusList` is false for the one move nobody asked for: a list pushed out
	/// of the sidebar to make room for the other one.
	private func placeUsages(at home: ResultPlacement, focusList: Bool = true) {
		usagesPlacement = home
		place(
			usagesPane, at: home, window: &usagesWindow, focusList: focusList,
			release: { [weak self] in
				self?.bottomPanel.releaseUsages()
			}, dock: { [weak self] beside, focus in
				guard let self else { return }
				self.setPanelVisible(true)
				self.bottomPanel.dockUsages(
					self.usagesPane, title: self.usagesPane.paneTitle,
					beside: beside, focusList: focus
				)
			})
	}

	/// `focusList` is false for the ⇧⌘F that *makes* the pane: the keyboard goes
	/// to the field there, and a move that grabbed it back would put the caret
	/// in the rows of a search nobody has typed yet.
	private func placeSearch(at home: ResultPlacement, focusList: Bool = true) {
		guard let pane = bottomPanel.existingSearchPane else { return }
		searchPlacement = home
		place(pane, at: home, window: &searchWindow, focusList: focusList, release: { [weak self] in
			self?.bottomPanel.releaseSearch()
		}, dock: { [weak self] beside, focus in
			guard let self else { return }
			self.setPanelVisible(true)
			self.bottomPanel.dockSearch(pane, beside: beside, focusList: focus)
		})
	}

	/// Moves a results list to one of its four homes.
	///
	/// One route for both lists and all four destinations, because the property
	/// that has to hold is about the *move* rather than about any one home: the
	/// same view is taken out of wherever it is and put into the next one, so the
	/// rows, the ticks, the scroll position and the selection come with it. A
	/// pane rebuilt per home would arrive with the work undone, which is the
	/// mistake item 470 already avoided between two hosts and there are now four.
	///
	/// Every branch ends the same way — the keyboard, in the list. That is not
	/// tidiness: `spec/usages.md` is the reason the list exists in the shape it
	/// does, and a home that arrives without the keyboard is a home where ↓
	/// scrolls something else.
	private func place(
		_ pane: any ResultsPane,
		at home: ResultPlacement,
		window slot: inout ResultsWindow?,
		focusList: Bool = true,
		release: () -> Void,
		dock: (Bool, Bool) -> Void
	) {
		// Out of whatever it is in now, in every case. Taking it out of the panel
		// is the panel's own call because the tab has to go with it; the other
		// two are a superview and a content view.
		release()
		undockFromSidebar(pane)
		// The sidebar slot takes one guest, like the window and unlike the strip:
		// there is one lower half and splitting it again would be a sidebar of
		// three things, which is a tool window layout and not what was asked for.
		// Whoever is there goes back to the panel, and *its* placement is
		// updated, so the control on it says where it now is.
		if home == .sidebar { evictFromSidebar(unless: pane) }
		if let existing = slot, home != .window {
			existing.onClose = nil
			existing.contentView = nil
			existing.close()
			slot = nil
		}
		pane.removeFromSuperview()
		pane.setPlacement(home)

		switch home {
		case .panel: dock(false, focusList)
		case .beside: dock(true, focusList)
		case .sidebar: dockInSidebar(pane, focusList: focusList)
		case .window: expand(pane, into: &slot, focusList: focusList)
		}
	}

	// MARK: - Under the project view

	/// Sends whichever list is under the project view back to the panel, so the
	/// one arriving finds the slot empty.
	///
	/// Neither of them takes the keyboard on the way out. Every other move ends
	/// with the keyboard in the rows, and that is right for a move somebody
	/// asked for — this one is a consequence of asking for the *other* list, and
	/// the list arriving is the one being looked at. Nothing could see it go
	/// wrong today, because both moves defer the keyboard by a turn and the
	/// arriving one is queued second; saying it here is what stops that being
	/// the reason.
	private func evictFromSidebar(unless pane: any ResultsPane) {
		if usagesPlacement == .sidebar, usagesPane !== pane {
			placeUsages(at: .panel, focusList: false)
		}
		if searchPlacement == .sidebar, bottomPanel.existingSearchPane !== pane {
			placeSearch(at: .panel, focusList: false)
		}
	}

	/// Puts a list in the lower half of the sidebar, splitting it for the
	/// occasion.
	private func dockInSidebar(_ pane: any ResultsPane, focusList: Bool) {
		let dock: ColoredView
		if let existing = sidebarDock {
			dock = existing
		} else {
			dock = ColoredView(color: Theme.current.sidebarBackground)
			dock.colourSource = { Theme.current.sidebarBackground }
			sidebarDock = dock
			// `translatesAutoresizingMaskIntoConstraints` stays on for a split
			// view's own subviews: the split view sets their frames, and a
			// subview that refuses to be framed is one the divider cannot move.
			sidebarSplit.addArrangedSubview(dock)
		}
		dock.subviews.forEach { $0.removeFromSuperview() }

		pane.translatesAutoresizingMaskIntoConstraints = false
		dock.addSubview(pane)
		NSLayoutConstraint.activate([
			pane.topAnchor.constraint(equalTo: dock.topAnchor),
			pane.bottomAnchor.constraint(equalTo: dock.bottomAnchor),
			pane.leadingAnchor.constraint(equalTo: dock.leadingAnchor),
			pane.trailingAnchor.constraint(equalTo: dock.trailingAnchor),
		])

		// A list put under a sidebar that is shut is a list nobody can see, and
		// the move was somebody asking to see it. Same reason the panel route
		// calls `setPanelVisible(true)`.
		//
		// A maximised terminal is the same problem one layer out: it hides the
		// whole of `splitView`, sidebar and editor together, so the list arrives
		// in a view that is not on screen. It was arriving there in silence —
		// the first run of this said `where=sidebar` over a window with nothing
		// but a terminal in it. The window comes back, which is what asking for
		// a list beside the tree meant.
		if isPanelMaximized { togglePanelMaximized(nil) }
		if navigatorContainer.isHidden
			|| splitView.isSubviewCollapsed(navigatorContainer)
			|| navigatorContainer.frame.width < 2 {
			openNavigator()
		}

		let height = sidebarSplit.bounds.height
		if height > 80 {
			sidebarSplit.setPosition(height * sidebarToolFraction, ofDividerAt: 0)
		}
		sidebarSplit.adjustSubviews()
		if focusList { DispatchQueue.main.async { pane.focusList() } }
	}

	/// Takes a list out of the sidebar and puts the sidebar back to one view.
	private func undockFromSidebar(_ pane: any ResultsPane) {
		guard let dock = sidebarDock, pane.superview === dock else { return }
		// The fraction the divider was left at, so coming back finds it there.
		let height = sidebarSplit.bounds.height
		if height > 80 {
			sidebarToolFraction = min(0.9, max(0.1, (height - dock.frame.height) / height))
		}
		pane.removeFromSuperview()
		dock.removeFromSuperview()
		sidebarDock = nil
		sidebarSplit.adjustSubviews()
	}

	// MARK: - A window of its own

	/// The same view, in a window big enough to read two hundred rows in.
	private func expand(
		_ pane: any ResultsPane, into slot: inout ResultsWindow?, focusList: Bool
	) {
		let window = slot ?? makeResultsWindow(for: pane)
		slot = window
		window.title = pane.paneTitle
		window.contentView = pane

		if let parent = self.window {
			let frame = parent.frame
			let size = NSSize(
				width: min(760, frame.width - 80), height: min(520, frame.height - 160)
			)
			window.setFrame(NSRect(
				x: frame.midX - size.width / 2,
				y: frame.midY - size.height / 2,
				width: size.width,
				height: size.height
			), display: true)
			parent.addChildWindow(window, ordered: .above)
		}
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
		} else {
			window.orderFront(nil)
		}
		// The same call every other home needs, for the same reason: a list
		// nobody gave the keyboard to is one ↓ cannot walk.
		if focusList { DispatchQueue.main.async { pane.focusList() } }
	}

	private func makeResultsWindow(for pane: any ResultsPane) -> ResultsWindow {
		// No full-size content: the heading would be drawn under the titlebar, on
		// top of the title and the traffic lights.
		let window = ResultsWindow(
			contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: true
		)
		window.backgroundColor = Theme.current.editorBackground
		// Closing is being finished with the list, not asking for it back in the
		// panel: the choice of a window stands, so the next answer opens one.
		window.onClose = { [weak self, weak window, weak pane] in
			guard let window, let pane else { return }
			window.parent?.removeChildWindow(window)
			pane.removeFromSuperview()
			window.contentView = nil
			if self?.usagesWindow === window { self?.usagesWindow = nil }
			if self?.searchWindow === window { self?.searchWindow = nil }
			window.orderOut(nil)
		}
		return window
	}

	/// A row in a checklist pane was activated.
	///
	/// The whole of the keyboard answer is in the three branches, and the middle
	/// one is item 510's correction to item 470's pair. A preview asks for the
	/// provisional tab and does not take first responder, so the editor scrolls,
	/// shows the line and puts the caret there while the keyboard stays in the
	/// list and ↓ reaches the next row. A permanent open is a click, a double
	/// click or ⏎: this is the file, and it gets a tab of its own — and the
	/// keyboard *still* stays in the list, because the hand that did it is over
	/// the list and its next ⌫ has to tick a row rather than edit a file. Only a
	/// commit moves the keyboard, and only ⇥ is one.
	private func openFromChecklist(
		_ url: URL, match: SearchMatch, intent: ResultChecklist.Intent
	) {
		// Where the row's match becomes a place in the editor: its line, the column
		// it starts at, and how wide it is — the three the editor needs to put it
		// on screen rather than merely to scroll near it (item 533).
		let line = match.line + 1
		let column = match.column + 1
		let length = match.utf16Range.count
		switch intent {
		case .preview:
			editor.open(
				fileURL: url, atLine: line, column: column, length: length,
				focusEditor: false, preview: true
			)
		case .permanent:
			editor.open(
				fileURL: url, atLine: line, column: column, length: length,
				focusEditor: false
			)
		case .commit:
			editor.open(fileURL: url, atLine: line, column: column, length: length)
			// The one home where making the editor first responder is not enough.
			// A list expanded into a window of its own is a second window, and it
			// is the key one while somebody is working the list — so ⇥ left the
			// editor holding this window's first responder while every keystroke
			// went on reaching the panel. That is the fault this item is about,
			// one window over: the caret blinking in a view the keys are not
			// going to. `makeKey` rather than `makeKeyAndOrderFront`, because the
			// panel is a child window and floats over this one either way; the
			// list stays where it was and only the keys move.
			if window?.isKeyWindow == false { window?.makeKey() }
		}
	}

	/// Why the symbol list is empty, in a sentence somebody can act on.
	private func reasonForNoSymbols(query: String, scope: SymbolPalette.Scope) -> String {
		guard let project else { return "No project is open." }
		let status = LanguageService.shared.serverStatus(project: project.scopeRoot)

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

	/// What the menu over a commit in the log offers.
	///
	/// The same shape as `--branch-rows` and for the same reason: the claim is
	/// that a commit has verbs, and that the one which can lose work is fenced
	/// off from the ones that cannot. A list of titles diffs; a photograph of an
	/// open menu does not, and an `NSMenu` popped up for real blocks the run
	/// loop so the screenshot never fires at all.
	func commitMenuForTesting(row: Int, waiting: Int = 6) {
		if historyPane == nil { showSidebarTool(.history) }
		guard let pane = historyPane else {
			print("COMMIT-MENU: no history pane")
			return
		}

		// The log is read off the main queue and answers on it, so a pane built
		// a moment ago has no rows yet. Waited for rather than assumed: a fixed
		// delay long enough for a cold repository is a delay every run pays,
		// and one short enough not to be is a flake.
		guard pane.hasRowsForTesting else {
			guard waiting > 0 else {
				print("COMMIT-MENU: the log is still empty")
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.commitMenuForTesting(row: row, waiting: waiting - 1)
			}
			return
		}
		print("COMMIT-MENU:\n\(pane.commitMenuForTesting(row: row))")
	}

	/// Drives the refs tree from the command line: `report`, `shut:<key>`,
	/// `open:<key>`, `filter:<text>`, `stash:<n>`, `tag-sources:<tag>`,
	/// `refresh`, `settle[:seconds]`.
	///
	/// The same arrangement `--changes-tree` uses and for the same reason: the
	/// questions this pane turns on are about *this view* — did the prefix
	/// fold, did the one branch under `hotfix/` stay flat, did filtering
	/// flatten the lot — and a screenshot is one frame of that rather than the
	/// sequence.
	func branchRowsForTesting(_ steps: String) {
		if branchesPane == nil { showSidebarTool(.branches) }
		guard let pane = branchesPane else {
			print("BRANCHES: no branches pane")
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// Everything after a `settle` goes back to the run loop: git answers
			// on the main queue, so a nested wait here would never see the list
			// it is waiting for.
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.branchRowsForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report":  print("BRANCHES:\n\(pane.rowsForTesting())")
			case "stash":
				pane.openStashForTesting(Int(argument) ?? 0)
			case "tag-sources":
				print("TAG-SOURCES:\n\(pane.tagSourcesForTesting(excluding: argument))")
			case "shut":    pane.setFolderForTesting(argument, collapsed: true)
			case "open":    pane.setFolderForTesting(argument, collapsed: false)
			case "filter":  pane.filterForTesting(argument)
			case "refresh": pane.refresh()
			default:        print("BRANCHES: unknown step \(step)")
			}
		}
	}

	/// Drives the changes tree from the command line: `report`, `stage:<path>`,
	/// `unstage:<path>`, `shut:<path>`, `open:<path>`, `offer:<path>`,
	/// `offer-staged:<path>`, `discard:<path>`, `refresh`, `settle[:seconds]`.
	///
	/// The pane lives in the app target, where the suite cannot reach it, and
	/// the questions this pane turns on — does staging a folder take everything
	/// under it, does the tree stay open across a refresh, where does the
	/// selection land once what was selected has been staged away — are about
	/// *this view* rather than about the tree it is drawn from. A screenshot is
	/// one frame of that and not the sequence, so the sequence is scripted, the
	/// way `--tree` scripts the navigator.
	func changesStepsForTesting(_ steps: String) {
		if changesPane == nil { showSidebarTool(.changes) }
		guard let pane = changesPane else {
			print("CHANGES: no changes pane")
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// Everything after a `settle` goes back to the run loop: git runs
			// off the main queue and answers on it, so a nested wait here would
			// never see the tree it is waiting for.
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.changesStepsForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report":
				print("CHANGES:\n\(pane.changesTreeForTesting())")
			case "stage":
				pane.stageForTesting(paths: argument.split(separator: "+").map(String.init), staged: false)
			case "unstage":
				pane.stageForTesting(paths: argument.split(separator: "+").map(String.init), staged: true)
			case "shut":
				pane.setExpandedForTesting(path: argument, expanded: false, staged: false)
			case "open":
				pane.setExpandedForTesting(path: argument, expanded: true, staged: false)
			// What the context menu offers over a row, and what it would ask
			// before throwing the work away. `offer-staged` is how the other
			// half of that decision is checked: a staged row offers nothing.
			case "offer":
				print(pane.discardWordingForTesting(path: argument, staged: false))
			case "offer-staged":
				print(pane.discardWordingForTesting(path: argument, staged: true))
			case "discard":
				pane.discardForTesting(path: argument)
			// What a file being written does to the pane, on demand: what is
			// still open and still selected afterwards is the whole question.
			case "refresh":
				pane.refresh()
			default:
				print("CHANGES: no such step \(step)")
			}
		}
	}

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

	/// Exports the diagram in front from its own preview pane, the way the
	/// pane's menu does, and says what the menu offered on the way past.
	func exportDiagramForTesting(_ raw: String) {
		// `--export editable-png` is the second gesture in the same menu: the
		// picture that is also the document, `x.drawio.png`.
		let asked = raw.lowercased()
		let editable = asked.hasPrefix("editable-")
		guard let format = DiagramFormat(
			rawValue: editable ? String(asked.dropFirst("editable-".count)) : asked
		) else {
			print("EXPORT: no such format \(raw)")
			return
		}
		// A rendered Markdown document is a diagram pane too, in the only sense
		// that matters here: it has an `Export ▸` on it and writing the pictures
		// out is one act however many fences the document holds.
		if editor.activeGroup?.diagramPreview == nil,
		   let markdown = editor.activeGroup?.markdownPreview,
		   let url = markdown.fileURL, let source = markdown.markdownSource?()
		{
			print("EXPORT menu: \(markdown.exportMenuTitlesForTesting.joined(separator: " | "))")
			DiagramExportCommand.run(
				url: url, source: source, format: format,
				theme: Theme.current.isLight ? .light : .dark, projectRoot: nil
			) { written in
				print("EXPORT: \(written.map(\.lastPathComponent).joined(separator: ", "))")
			}
			return
		}
		guard let pane = editor.activeGroup?.diagramPreview else {
			print("EXPORT: nothing showing a diagram")
			return
		}
		print("EXPORT menu: \(pane.menuTitlesForTesting.joined(separator: " | "))")
		pane.export(format, editable: editable) { written in
			print("EXPORT: \(written.map(\.lastPathComponent).joined(separator: ", "))")
		}
	}

	/// Swaps the diagram in front between fitting the pane's width and the
	/// drawing's own size, as a double-click on it does, and says what the
	/// corner now reads.
	///
	/// The percentage is the point: a screenshot shows a diagram got larger and
	/// cannot show what it got larger *to*.
	func setDiagramFitForTesting(_ raw: String) {
		guard let pane = editor.activeGroup?.diagramPreview else {
			print("FIT: nothing showing a diagram")
			return
		}
		pane.setFit(raw.lowercased() == "actual" ? .actual : .width)
		print("FIT: \(pane.scaleReadoutForTesting)")
	}

	/// The same for the picture in front, and it prints more than a percentage.
	///
	/// What 0532 was about is a document view pinned to the pane, and no capture
	/// of a picture can show whether the thing under it is larger than the hole
	/// it is seen through. The numbers can: the report names the picture, the
	/// document it sits in and the part of it on screen, so "pannable rather
	/// than cropped" is arithmetic anybody can check.
	func setImageFitForTesting(_ raw: String) {
		guard let pane = editor.activeGroup?.imagePreview else {
			print("IMAGE: nothing showing a picture")
			return
		}
		pane.setFit(raw.lowercased() == "actual" ? .actual : .pane)
		print("IMAGE: \(pane.reportForTesting)")
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

	/// Scrolls the picture in front to a corner of itself, `x,y` as fractions.
	func panImageForTesting(_ raw: String) {
		guard let pane = editor.activeGroup?.imagePreview else {
			print("IMAGE: nothing showing a picture")
			return
		}
		let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
		guard parts.count == 2 else {
			print("IMAGE: --image-pan wants x,y as fractions, got \(raw)")
			return
		}
		pane.panForTesting(CGPoint(x: parts[0], y: parts[1]))
		print("IMAGE: \(pane.reportForTesting)")
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
		let runs = Self.runConfigurationTallyForTesting
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

	/// The panel's own layout, beside the terminal's grid.
	///
	/// Where the tab strip sits inside the panel is not visible in any of the
	/// numbers above, and it is what a band above the tabs is made of.
	func panelGeometryForTesting() -> String {
		bottomPanel.stripGeometryForTesting()
	}

	/// Whether the terminal panel is showing, what is in it, and what the pane in
	/// front last said — for 0444's part 4, whose whole claim is about a pane that
	/// appears without being asked for and must not be asked for again to be seen.
	func panelTabsForTesting(tail: Int = 0) -> String {
		var said = "PANEL: visible=\(isPanelVisible) \(bottomPanel.tabsForTesting)"
		if tail > 0 { said += "\n  last: " + bottomPanel.activeTerminalTailForTesting(lines: tail) }
		return said
	}

	/// Where the terminal in front says it is — the answer the window follows.
	func terminalDirectoryForTesting() -> URL? {
		bottomPanel.activeTerminalDirectoryForTesting()
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

	func showDebugConsoleForTesting() {
		bottomPanel.showDebugConsoleForTesting()
	}

	func echoDebugOutputForTesting() {
		bottomPanel.debugOutput = { text in
			FileHandle.standardError.write(Data("[debug] \(text)".utf8))
		}
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
			while self.runConfigurations.isEmpty, Date() < deadline {
				try? await Task.sleep(for: .milliseconds(200))
			}

			for configuration in self.runConfigurations where configuration.source == .xcodeScheme {
				guard let target = configuration.xcode else { continue }
				_ = await XcodeDestinations.shared.destinations(
					for: target,
					workingDirectory: URL(fileURLWithPath: configuration.workingDirectory)
				)
			}
			self.printConfigurationMenuForTesting(open: goal)
		}
	}

	private func printConfigurationMenuForTesting(open goal: String?) {
		let list = runList()
		print("MENU: \(list.arrangement.rowCount) rows for "
			+ "\(list.arrangement.flatCount) runnable things")
		if let control = runControl {
			showConfigurationMenu(from: control.bounds, in: control)
			for line in ProjectSwitcherPopover.rowsForTesting() { print("MENU: \(line)") }
			guard let goal else { return }
			print("MENU: --- opening \(goal) ---")
			for line in ProjectSwitcherPopover.openGoalForTesting(goal) { print("MENU: \(line)") }
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
			// The port and the class files together, from one server: whichever
			// jdtls can give them, which since 0452 may be one started for the
			// debugger alone. The class files are here, so a frame from the pod
			// lands on the source it was compiled from rather than on a
			// decompiled stub.
			let target = try await LanguageService.shared.javaLaunchTarget(
				project: root,
				anchor: JavaTooling.mainClasses(in: root).first.map { URL(fileURLWithPath: $0.file) },
				saying: { sentence in self.runControl?.setStatus(sentence, busy: true) }
			)
			request.host = "127.0.0.1"
			request.port = debugForward.localPort
			request.classPaths = target.classPaths
			request.projectName = target.projectName

			guard let session = bottomPanel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: target.port, request: request),
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
		//
		// Except a script, whatever the type says. `go` is the default type a new
		// configuration is written with, so a configuration somebody pointed at
		// `./mvnw` and did not change the type of ran as `go run ./mvnw` — which
		// fails in Go's words about a directory that is not a package, and is the
		// same fault as handing the script to LLDB: believing the type over the
		// file.
		let isScript = ScriptLaunch.kind(ofProgramAt: program) != nil
		let words = configuration.type == "go" && !isScript
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

	/// Runs a wrapper script with JDWP asked for, then attaches to the JVM.
	///
	/// The same two halves as debugging in a pod, which is the flow this follows:
	/// something elsewhere is started with its port open and suspended, and the
	/// adapter inside the language server connects to it so the sources on screen
	/// are the ones on this disk. What differs is that "elsewhere" is a child of
	/// a shell script on this machine rather than a container, so there is no
	/// port-forward and nothing to tell us when the JVM is up — the port is
	/// opened by a grandchild this app never sees, and is polled for.
	///
	/// The script runs in an ordinary run pane, not swallowed by the debugger:
	/// what Maven and Gradle print while they resolve and compile is most of what
	/// there is to read when a launch does not work, and `internalConsole` would
	/// have shown none of it.
	private func startScriptDebug(
		_ configuration: LaunchConfiguration,
		kind: ScriptLaunch.Kind,
		in root: URL,
		environment: [String: String]
	) {
		let program = configuration.expandedProgram(root: root)
		let directory = configuration.expandedWorkingDirectory(root: root)

		// Gradle's port is Gradle's, so a stale JVM holding it is a thing that
		// can happen and has to be said. For everyone else the kernel picks.
		let port: Int
		if kind == .gradle {
			port = ScriptLaunch.gradleDebugPort
			if DebugPort.isOpen(port) {
				notify(
					"Something is already on port \(port)",
					detail: "Gradle's --debug-jvm always uses \(port) and cannot be told another. "
						+ "A JVM left suspended by an earlier launch is the usual reason; stop it "
						+ "and try again."
				)
				return
			}
		} else if let free = DebugPort.free() {
			port = free
		} else {
			notify("No free port", detail: "The debugger needs a local port and the kernel had none.")
			return
		}

		let plan = ScriptLaunch.plan(
			kind: kind,
			port: port,
			environment: environment,
			arguments: configuration.expandedArguments(root: root)
		)

		setPanelVisible(true)
		runControl?.setStatus("Starting \(configuration.name)…", busy: true)

		let words = [program] + plan.arguments
		let pane = bottomPanel.runCommand(
			title: configuration.name,
			command: words.map(Self.shellQuoted).joined(separator: " "),
			directory: URL(fileURLWithPath: directory),
			environment: plan.environment,
			reusing: "run:\(configuration.id)"
		)
		followRunningPane(pane)
		// Said in the debug console rather than only in the status line: it is
		// the one record of what was actually arranged, and the command in the
		// run pane does not show it — the option went into the environment.
		bottomPanel.showDebug()?.appendOutput(plan.note + "\n")

		Task { @MainActor [weak self] in
			guard let self else { return }
			self.runControl?.setStatus("Waiting for the JVM on \(plan.port)…", busy: true)
			guard await DebugPort.waitUntilOpen(plan.port) else {
				// Deliberately specific about the two ways this ends badly,
				// because they need opposite things done about them.
				self.runControl?.setStatus("The JVM never opened \(plan.port)", failed: true)
				self.notify(
					"Nothing opened port \(plan.port)",
					detail: Self.scriptDebugAdvice(for: kind)
				)
				return
			}
			self.attachToScriptJVM(configuration, port: plan.port, root: root)
		}
	}

	/// What to try when the port never opened, which differs by wrapper.
	private static func scriptDebugAdvice(for kind: ScriptLaunch.Kind) -> String {
		switch kind {
		case .maven:
			return "Maven ran but no JVM took the debug option. A forked goal starts a second JVM "
				+ "that does not inherit MAVEN_OPTS — Surefire needs it in argLine, Spring Boot in "
				+ "jvmArguments."
		case .gradle:
			return "Gradle ran but nothing forked a JVM. --debug-jvm only opens a port for a task "
				+ "that starts one, which means a JavaExec or Test task."
		case .script:
			return "The script ran but started no JVM under JAVA_TOOL_OPTIONS. If it starts the JVM "
				+ "through something that clears the environment, the option has to go in there "
				+ "instead."
		}
	}

	/// Connects the Java debugger to a JVM that is up and waiting.
	private func attachToScriptJVM(
		_ configuration: LaunchConfiguration, port: Int, root: URL
	) {
		Task { @MainActor in
			// The class files and the server's own port together, as the pod
			// attach does: a frame from the JVM then lands on the source it was
			// compiled from rather than on a decompiled stub.
			let target: LanguageService.JavaLaunchTarget
            do {
				target = try await LanguageService.shared.javaLaunchTarget(
					project: root,
					anchor: JavaTooling.mainClasses(in: root).first.map { URL(fileURLWithPath: $0.file) },
					saying: { sentence in self.runControl?.setStatus(sentence, busy: true) }
				)
			} catch {
				runControl?.setStatus("Java cannot be debugged yet", failed: true)
				notify(
					"The Java language server is not ready",
					detail: "The debugger for Java lives inside it, and the JVM is waiting on port "
						+ "\(port) until it arrives or you stop it."
				)
				return
			}

			var request = JavaDebug.Request(kind: .attach)
			request.host = "127.0.0.1"
			request.port = port
			request.classPaths = target.classPaths
			request.projectName = target.projectName

			guard let session = bottomPanel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: target.port, request: request),
				breakpoints: pendingBreakpoints
			) else { return }
			wire(session)
		}
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
		// A script before anything else, because the thing it is *not* is what
		// the rest of this function assumes: a file a debugger can open. Handing
		// `./mvnw` to lldb-dap got "is not a valid executable" — true, and about
		// the wrong program. What a wrapper script has to be debugged through is
		// the JVM it eventually starts.
		if let kind = ScriptLaunch.kind(ofProgramAt: configuration.expandedProgram(root: root)) {
			startScriptDebug(configuration, kind: kind, in: root, environment: environment)
			return
		}

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
	/// Two things have to come from a Java language server and neither can be
	/// worked out here: the port its debug adapter is listening on, and the
	/// classpath of the module the class belongs to. A JVM started without the
	/// second one fails with `ClassNotFoundException` on the class it was asked
	/// to run, which reads like the class is missing rather than the classpath.
	///
	/// **Which server that is may not be the one editing.** Since 0452, a project
	/// that chose the fast Java server for editing gets a jdtls started here for
	/// the debugger alone — and the wait for its import is what pressing Debug
	/// costs on a large project. So the status line says what is being waited for
	/// while it happens, in the server's own words where it has any: a spinner
	/// that says nothing looks exactly like a debugger that has hung.
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
		// The scope, because the adapter lives inside the language server and
		// the server for a subproject is filed under the subproject: asking the
		// repository above it gets `noServer` in a checkout of several.
		let root = project.scopeRoot

		setPanelVisible(true)
		runControl?.setStatus("Debugging \(name)…", busy: true)

		Task { @MainActor in
			// Any file in the module will do — the question is about the project
			// the file belongs to, not the file — so the class's own source is
			// used when there is one and any main class in the project otherwise.
			let anchor = anchorFile
				?? JavaTooling.mainClasses(in: root)
					.first { $0.name == mainClass }
					.map { URL(fileURLWithPath: $0.file) }

			let target: LanguageService.JavaLaunchTarget
			do {
				target = try await LanguageService.shared.javaLaunchTarget(
					project: root,
					anchor: anchor,
					// Strongly, because the `Task` around this already holds self
					// and a weak capture inside one buys nothing.
					saying: { sentence in
						self.runControl?.setStatus(sentence, busy: true)
						self.bottomPanel.showDebug()?.appendOutput(sentence + "\n")
					}
				)
			} catch {
				runControl?.setStatus("Java cannot be debugged yet", failed: true)
				// The missing bundle gets the whole manual rather than one line:
				// it is the one failure here nobody can guess the fix for.
				var detail = error.localizedDescription
				if let failure = error as? LanguageService.JavaDebugFailure, case .noBundle = failure {
					detail = JavaTooling.debugPluginManual
				}
				if let failure = error as? JavaDebugHost.Failure, case .noBundle = failure {
					detail = JavaTooling.debugPluginManual
				}
				notify("Java cannot be debugged yet", detail: detail)
				return
			}

			runControl?.setStatus("Debugging \(name)…", busy: true)
			let request = JavaDebug.Request(
				kind: .launch,
				mainClass: mainClass,
				classPaths: target.classPaths,
				projectName: target.projectName,
				workingDirectory: workingDirectory.path,
				arguments: arguments,
				vmArguments: vmArguments,
				environment: environment
			)
			guard let session = bottomPanel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: target.port, request: request),
				breakpoints: pendingBreakpoints
			) else { return }
			wire(session)
		}
	}

	// MARK: - Hot code replace

	/// Says what a swap into the running JVM did.
	///
	/// **Most of these are refusals, and that is the JVM rather than a fault.**
	/// HotSpot replaces method bodies and nothing else, so adding a method,
	/// changing a signature, adding a field and changing what a class extends are
	/// all refused — which is most of what editing feels like. A report that said
	/// only "hot swap failed" would teach somebody to ignore it; one that carries
	/// the adapter's own sentence tells them why they are about to restart.
	private func reportHotSwap(
		_ event: JavaDebug.HotSwap.Event, wasStopped: Bool, in session: DebugSession
	) {
		// Every stage in the log as well as the console. `BUILD_COMPLETE` with no
		// `END` after it is the shape of "the adapter compiled and then found
		// nothing to redefine", and telling that from "no events at all" is the
		// whole of diagnosing a swap that does not happen.
		DiagnosticLog.write(
			"java hot code replace: \(event.stage.rawValue) \(event.message ?? "")", to: "lsp"
		)
		// **`activeDebugPane` and not `showDebug()`, which was the fault.**
		// `showDebug()` ends in `activate(session, focus: true)` — it brings the
		// pane forward *and takes the keyboard*. Called once per hot-swap event,
		// that meant every save during a debug session pulled the focus out of
		// the editor: reported as "I lose focus whenever I save, as soon as the
		// application runs", and it is also why ⌘Z looked broken afterwards —
		// the undo history was never lost, the keyboard was somewhere else.
		//
		// Reporting is not a reason to move anybody's keyboard. The pane is
		// written into where it is; somebody who wants to look at it clicks it.
		let console = bottomPanel.activeDebugPane
		switch event.stage {
		case .starting:
			// Before anything has happened. In the console, where somebody
			// looking for it finds it, and not in the corner of the window — a
			// toast per save is a toast nobody reads.
			if let message = event.message { console?.appendOutput(message + "\n") }

		case .buildComplete:
			if let message = event.message { console?.appendOutput(message + "\n") }
			// **And now ask, which is the half that was missing.** The adapter
			// says the build is done and then waits: `AUTO` is this client's
			// policy about the event, not something the adapter acts on alone.
			// Sending it here rather than on the save is what makes the timing
			// right — the adapter knows when its compile finished and nothing
			// out here does.
			Task { @MainActor in
				guard let result = await session.redefineClasses() else { return }
				if let failure = result.errorMessage, !result.didSwap {
					self.reportHotSwap(
						JavaDebug.HotSwap.Event(stage: .error, message: failure),
						wasStopped: wasStopped, in: session
					)
					return
				}
				guard result.didSwap else { return }
				self.reportHotSwap(
					JavaDebug.HotSwap.Event(
						stage: .end,
						message: "Redefined " + result.changed.joined(separator: ", ")
					),
					wasStopped: wasStopped, in: session
				)
			}

		case .end:
			console?.appendOutput((event.message ?? "Classes redefined in the running JVM") + "\n")
			// **And the stack moved, which is the most confusing thing this
			// does.** The adapter drops to an affected frame and enters it
			// again, so somebody stopped in the method they just edited is
			// suddenly somewhere else. Not this app's behaviour to decline, and
			// unexplained it reads as the debugger losing its place.
			if JavaDebug.HotSwap.movedTheStack(event, wasStopped: wasStopped) {
				console?.appendOutput(
					"The frame you were stopped in was entered again, so the new body runs "
						+ "from its start.\n"
				)
			}

		case .warning:
			if let message = event.message { console?.appendOutput(message + "\n") }

		case .error:
			let detail = event.message ?? "The JVM would not take the change."
			console?.appendOutput(detail + "\n")
			// A session that cannot swap at all says so once — `cannotHotSwap`
			// is set by the session the first time a failure is about the session
			// rather than about the change, so this is the only time it is true
			// and unsaid.
			if session.cannotHotSwap {
				guard !saidThisSessionCannotHotSwap else { return }
				saidThisSessionCannotHotSwap = true
				notify(
					"This session cannot replace code",
					detail: detail + "\nSaving will not change the running program.",
					kind: .information
				)
				return
			}
			notify(
				"The JVM would not take that change",
				detail: detail + "\nIt replaces method bodies and nothing else.",
				kind: .warning,
				actionTitle: restartTitle(for: session),
				action: { [weak self] in self?.runSelectedConfiguration(debug: true) }
			)
		}
	}

	/// Said once per session, since `cannotHotSwap` stays true afterwards.
	private var saidThisSessionCannotHotSwap = false

	/// What the restart offer is about to restart.
	///
	/// **Named for an attached session, because it is somebody's service.**
	/// Restarting a JVM this app launched costs a process nobody else is using;
	/// restarting one in a pod is a different sentence and deserves to be read
	/// before it is pressed.
	private func restartTitle(for session: DebugSession) -> String {
		session.isAttached ? "Restart the program being debugged" : "Restart the session"
	}

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
		queueHotSwapCompile(project: project.scopeRoot)
	}

	private var hotSwapCompileRunning = false
	private var hotSwapCompileQueued = false

	private func queueHotSwapCompile(project root: URL) {
		guard !hotSwapCompileRunning else {
			hotSwapCompileQueued = true
			return
		}
		hotSwapCompileRunning = true
		Task { @MainActor in
			_ = await LanguageService.shared.compileJavaForSwap(project: root)
			self.hotSwapCompileRunning = false
			if self.hotSwapCompileQueued {
				self.hotSwapCompileQueued = false
				self.queueHotSwapCompile(project: root)
			}
		}
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
	private func showConfigurationMenu(from rect: NSRect, in control: RunControl) {
		ProjectSwitcherPopover.show(
			relativeTo: control,
			anchorRect: rect,
			currentProject: project,
			owner: self,
			focus: .runs,
			runs: runList()
		)
	}

	/// Everything the run popover needs: what can be run, what is chosen, and
	/// what choosing one means.
	///
	/// The four sources are the menu's own, untouched — this is only what is
	/// done with what they found.
	func runList() -> ProjectSwitcherPopover.RunList {
		let saved = launchConfigurations
		let savedNames = Set(saved.map(\.name))

		// The saved ones as rows. Only a name and a source are read from these:
		// choosing one selects it by name, exactly as the menu item did.
		var all: [RunConfiguration] = saved.map { entry in
			RunConfiguration(
				name: entry.name,
				source: .vscode,
				executable: entry.program,
				arguments: entry.arguments,
				workingDirectory: entry.workingDirectory
			)
		}

		all += runConfigurations.filter { $0.source == .xcodeScheme }

		for goal in makeGoals() where !savedNames.contains("make \(goal.name)") {
			all.append(RunConfiguration(
				name: "make \(goal.name)",
				source: .make,
				executable: "make",
				arguments: [goal.name],
				workingDirectory: goal.makefile.path.deletingLastPathComponent().path,
				file: goal.makefile.path.path
			))
		}

		all += runConfigurations.filter {
			($0.source == .maven || $0.source == .gradle || $0.source == .javaMain)
				&& !savedNames.contains($0.name)
		}

		var actions: [(title: String, symbol: String, handler: () -> Void)] = []
		if selectedConfiguration != nil {
			actions.append(("Edit\u{2026}", "pencil", { [weak self] in
				self?.editSelectedConfiguration()
			}))
			// One local and one in the cluster differ by two fields, so the way
			// to get the second is a copy of the first.
			actions.append(("Duplicate\u{2026}", "plus.square.on.square", { [weak self] in
				self?.duplicateSelectedConfiguration()
			}))
		}
		actions.append(("New\u{2026}", "plus", { [weak self] in self?.addConfiguration() }))
		actions.append(("Open launch.json", "doc.text", { [weak self] in self?.openLaunchFile() }))

		return ProjectSwitcherPopover.RunList(
			arrangement: RunPicker.arrange(all, pinned: savedNames),
			selected: selectedConfigurationName,
			choose: { [weak self] configuration in self?.chose(configuration) },
			actions: actions
		)
	}

	/// What choosing a row means, which depends on where the row came from.
	///
	/// The same four behaviours the menu items had, in one place instead of four
	/// selectors: a saved configuration is selected, a scheme is started, a make
	/// goal goes through `MakeLaunch` because it may become a debuggable entry,
	/// and everything else is selected as the goal to run.
	private func chose(_ configuration: RunConfiguration) {
		switch configuration.source {
		case .vscode, .intelliJ:
			selectedMakeRun = nil
			selectedConfigurationName = configuration.name
			refreshRunControl()

		case .xcodeScheme:
			// A scheme has a second axis of its own — where it runs — and in the
			// menu that axis was a submenu, which is the only way a scheme could
			// be started from this control at all. A popover row has no submenu,
			// so the destination list opens as a menu from where the row was.
			// It is not folded like a reactor's modules because the destinations
			// are not known yet: asking Xcode takes about twelve seconds, and a
			// row that could not say what was behind it until then would be
			// worse than the menu it replaced.
			guard let target = configuration.xcode, let control = runControl else {
				run(configuration)
				return
			}
			let menu = destinationMenu(for: configuration, target: target)
			menu.popUp(positioning: nil, at: NSPoint(x: 0, y: control.bounds.maxY), in: control)

		case .make:
			guard let file = configuration.file, let goal = configuration.arguments.first else { return }
			chooseMakeGoal(goal, inMakefileAt: URL(fileURLWithPath: file))

		default:
			// Chosen, not started — the same bargain the build goals had: picking
			// from a list says which one, and the play button says when.
			selectedMakeRun = configuration
			selectedConfigurationName = configuration.name
			refreshRunControl()
		}
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
		guard let parts = sender.representedObject as? [String], parts.count == 2 else {
			notify("That Makefile could not be read")
			return
		}
		chooseMakeGoal(parts[1], inMakefileAt: URL(fileURLWithPath: parts[0]))
	}

	/// Picks a Makefile goal to run, from the menu or from the run popover.
	///
	/// Shared rather than duplicated: what a goal becomes is decided here, by
	/// `MakeLaunch`, and deciding it anywhere else is how a goal came to be
	/// offered as debuggable and then do nothing.
	private func chooseMakeGoal(_ goal: String, inMakefileAt path: URL) {
		guard let project, let makefile = Makefile.read(at: path) else {
			notify("That Makefile could not be read")
			return
		}

		// Chosen, not started: picking something from a list of things to run
		// says which one, and the play button says when.
		switch MakeLaunch.choice(for: goal, in: makefile, projectRoot: project.root) {
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

	/// Presses the settings sidebar's arrow keys, and says where they left it.
	///
	/// Beside `--settings-fold`, which is the triangle: the same folding, by the
	/// other way in. What comes back also carries the sidebar's sizes, so a run
	/// can tell whether the zoom reached the page as well as what the keys did.
	func pressSettingsKeysForTesting(_ keys: String) {
		guard let page = editor.activeGroup?.page(identifier: "settings") as? SettingsPage else {
			print("SETTINGS: no settings page")
			return
		}
		page.pressArrowsForTesting(
			keys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
		)
		print("SETTINGS: \(page.reportForTesting)")
	}

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

		// Something to look at while the repository is being read. The sidebar
		// used to keep the *previous* tool on screen for the whole wait, so
		// asking for the changes view on a large repository looked like the
		// click had missed — and clicking again did nothing, because the second
		// ask is the one this guard drops.
		let waiting = PaneActivityView.install(
			over: primaryContainer, message: "Reading repository…"
		)

		Task { @MainActor [weak self] in
			await self?.project?.loadGit()
			waiting.finish()
			guard let self, self.pendingSidebarTool == tool else { return }
			self.pendingSidebarTool = nil
			// It may have arrived while this was waiting: reading a repository
			// takes long enough that a window told to open on the changes pane
			// gets there first, and building it a second time on top of itself
			// threw away the one that was already on screen.
			guard self.currentSidebarTool != tool || self.primaryToolView == nil else {
				self.updateSidebarSelection()
				return
			}
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
			let pane = ChangesPane(root: gitCommandRoot ?? project.root)
			pane.onSelectChange = { [weak self] change in self?.showDiff(for: change) }
			// `…` promotes the message rather than starting a second one.
			pane.onOpenPage = { [weak self] summary in
				self?.showCommitPage(carrying: summary)
			}
			pane.onWorkingCopyChanged = { [weak self] in self?.navigator.refreshGitStatus() }
			changesPane = pane
			view = pane
		case .branches:
			// Nothing to show until the project's repository has been read,
			// which the caller waits for rather than leaving the sidebar empty.
			guard let project, project.git != nil else { return nil }
			let pane = BranchesPane(root: gitCommandRoot ?? project.root)
			// A worktree is a project in its own right, so opening one is
			// switching to it rather than checking anything out.
			//
			// Through the delegate, which this was the one caller not doing
			// (0490): a bare `switchProject` took over the window whatever the
			// setting said, and opened a second window on a checkout that
			// already had one. The backlog card, the project switcher and now
			// the titlebar all go through the same door.
			pane.onOpenCommitPage = { [weak self] in self?.showCommitPage(carrying: nil) }
			pane.onOpenFiles = { [weak self] paths in
				guard let self, let project = self.project else { return }
				for path in paths {
					self.editor.open(fileURL: project.root.appendingPathComponent(path))
				}
			}
			pane.onShowLog = { [weak self] ref in self?.showLogPage(scopedTo: ref) }
			pane.onSelectChange = { [weak self] change in self?.showDiff(for: change) }
			pane.onOpenWorktree = { [weak self] path in
				guard let self else { return }
				(NSApp.delegate as? AppDelegate)?.open(projectAt: path, from: self)
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
			let pane = HistoryPane(root: gitCommandRoot ?? project.root)
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

	/// A key that used to open something and now opens the git tool.
	///
	/// **Doing nothing would be the worse answer.** ⌘2 and ⌘6 have been Commit
	/// and History for as long as this app has had them, and fingers do not
	/// read release notes. For one release they land somewhere sensible and say
	/// where the thing they used to open has gone.
	@objc func movedShortcut(_ sender: Any?) {
		showSidebarTool(.branches)
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

	/// Opens the log as a page in the editor area.
	///
	/// **The same pane at the size it needs**, which is why this reaches for
	/// `HistoryPane(root:layout:)` rather than a class of its own: the loader,
	/// the collapse rule, the graph and the commit menu are the same questions
	/// at either size, and two classes asking them would be two answers that
	/// drift apart in colours, in what counts as unpushed, in how a merge
	/// folds.
	///
	/// A page rather than a dialog, for the reason `LaunchConfigurationsPage`
	/// gives: it can be left open, switched away from, and come back to.
	@objc func showLogPage(_ sender: Any?) { showLogPage(scopedTo: nil) }

	/// - Parameter ref: a branch or tag to show the history of, or nil for the
	///   branch that is checked out.
	func showLogPage(scopedTo ref: String?) {
		leaveTerminalFullScreen()
		guard let project, project.git != nil, let group = editor.activeGroup else { return }

		let page = (group.page(identifier: "log") as? HistoryPane)
			?? HistoryPane(root: gitCommandRoot ?? project.root, layout: .page)
		logPage = page

		// Named for what it is showing: two log tabs both called "Log" would be
		// the tab strip saying nothing, and a log scoped to a branch is a
		// different question from the one about where you are standing.
		group.openPage(
			page,
			title: ref.map { "Log · \($0)" } ?? "Log",
			identifier: "log",
			symbol: "clock.arrow.circlepath"
		)
		page.setRef(ref)
	}

	/// The log page, while one is open, for the driver to read.
	private weak var logPage: HistoryPane?
	/// The commit page, likewise.
	private weak var commitPage: ChangesPane?

	/// Opens the commit view as a page in the editor area.
	///
	/// **The same pane at the size it needs**, exactly as the log is: the tree,
	/// folder staging and the discard question are the same questions at either
	/// size, so there is one class and two arrangements rather than two classes
	/// that drift.
	///
	/// - Parameter carrying: what has been typed into the sidebar's summary, so
	///   pressing `…` is promoting a message rather than starting a second one.
	@objc func showCommitPage(_ sender: Any?) { showCommitPage(carrying: nil) }

	func showCommitPage(carrying summary: String?) {
		leaveTerminalFullScreen()
		guard let project, project.git != nil, let group = editor.activeGroup else { return }

		let page: ChangesPane
		if let existing = group.page(identifier: "commit") as? ChangesPane {
			page = existing
		} else {
			page = ChangesPane(root: gitCommandRoot ?? project.root, layout: .page)
			page.onWorkingCopyChanged = { [weak self] in
				self?.navigator.refreshGitStatus()
				self?.changesPane?.refresh()
			}
		}
		commitPage = page
		group.openPage(page, title: "Commit", identifier: "commit", symbol: "checkmark.circle")

		if let summary, !summary.isEmpty { page.carrySummaryForTesting(summary) }
		page.refresh()
	}

	/// What the commit page holds.
	func commitPageForTesting(_ steps: String, waiting: Int = 8) {
		if commitPage == nil { showCommitPage(carrying: nil) }
		guard let page = commitPage else {
			print("COMMIT-PAGE: no page")
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.commitPageForTesting(rest, waiting: waiting)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("COMMIT-PAGE:\n\(page.pageReportForTesting())")
			case "select": page.selectChangeForTesting(argument)
			case "type":   page.carrySummaryForTesting(argument)
			default:       print("COMMIT-PAGE: unknown step \(step)")
			}
		}
	}

	/// What the log page holds, and what its menu over a commit offers.
	func logPageForTesting(_ steps: String, waiting: Int = 8) {
		if logPage == nil { showLogPage(nil) }
		guard let page = logPage else {
			print("LOG-PAGE: no page")
			return
		}
		guard page.hasRowsForTesting else {
			guard waiting > 0 else {
				print("LOG-PAGE: the log is still empty")
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.logPageForTesting(steps, waiting: waiting - 1)
			}
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// The diff of a file is read off the main queue like everything
			// else here, so a report taken in the same turn as the selection
			// sees the state before it.
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.logPageForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("LOG-PAGE:\n\(page.pageReportForTesting())")
			case "menu":   print("LOG-PAGE-MENU:\n\(page.commitMenuForTesting(row: Int(argument) ?? 0))")
			case "file":
				page.selectCommitForTesting(0)
				page.selectFileForTesting(Int(argument) ?? 0)
			default:       print("LOG-PAGE: unknown step \(step)")
			}
		}
	}

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

	/// Puts just these lines aside.
	///
	/// **No new patch machinery at all.** `GitPatch.patch(selecting:)` already
	/// builds a partial patch and `GitWorkingCopy.stage(lines:ofDiff:)` already
	/// applies one to the index — so "stash these hunks" is staging them and
	/// stashing what is staged, which is what `--staged` is for.
	///
	/// The index is put back the way it was found: somebody who had staged
	/// something else and then stashed a hunk should not discover their staging
	/// had been swept up with it.
	private func stashDiffSelection(change: GitChange, diff: String, lines: Set<Int>) {
		guard let project, !lines.isEmpty else { return }
		let root = project.root

		Task { @MainActor in
			let alreadyStaged = await GitWorkingCopy.status(in: root).staged.map(\.path)
			guard alreadyStaged.isEmpty else {
				Toast.post(
					"Something is already staged",
					detail: "Stashing lines uses the index, so it needs the index empty. "
						+ "Commit or unstage what is there first."
				)
				return
			}

			let staged = await GitWorkingCopy.stage(lines: lines, ofDiff: diff, in: root)
			guard staged.exitCode == 0 else {
				finishDiffOperation(staged, change: change)
				return
			}

			let name = "\(lines.count) line\(lines.count == 1 ? "" : "s") of \(change.name)"
			let put = await GitStash.pushStaged(in: root, message: name)
			finishDiffOperation(put, change: change)
			if put.exitCode == 0 {
				Toast.post("Stashed \(name)", kind: .information)
			}
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
				in: project.root,
				isDirectory: change.isDirectory
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
	/// Selects lines in the editor without going near the first responder, and
	/// says where the keyboard actually is — which is the whole claim the
	/// picture it is taken for makes.
	func selectLinesForTesting(from: Int, to: Int) {
		let done = editor.selectLinesForTesting(fromLine: from, toLine: to)
		let responder = window?.firstResponder
		print("SELECT lines \(from)-\(to) \(done ? "selected" : "no editor") "
			+ "keyboard=\(responder.map { String(describing: type(of: $0)) } ?? "nothing")")
		fflush(stdout)
	}

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

	/// Turns the engine setting on and opens a terminal, so a pane older than
	/// the change sits beside one younger — for `--engine-switch`.
	func switchEngineForTesting() {
		Settings.shared.terminalGhosttyEngine = true
		print("ENGINE: setting on, opening a pane")
		bottomPanel.newTerminal()
		fflush(stdout)
	}

	/// Which panes say they were drawn by the other engine, for `--engines`.
	func reportEnginesForTesting() {
		print("ENGINES:\n\(bottomPanel.engineMarksForTesting())")
		fflush(stdout)
	}

	/// What the editor said about motions nothing handled, for
	/// `--unhandled-motions`.
	func reportUnhandledMotionsForTesting() {
		let named = editor.exerciseUnhandledMotionsForTesting()
		print("MOTIONS: \(named)")
		print("MOTIONS log: \(DiagnosticLog.path("editor"))")
		fflush(stdout)
	}

	/// Walks the panel's variables tree with the keyboard, and reads it twice.
	///
	/// **The second read is the point.** → on a row the adapter has not been
	/// asked about returns before its children exist; the tree is rebuilt when
	/// the answer arrives, and that rebuild is what used to leave nothing
	/// selected. A report printed on the same turn as the key press cannot see
	/// it, which is how the bug came back after being called fixed.
	private func walkThePaneForTesting() {
		print("VALUE panel: \(bottomPanel.variablesKeyboardReportForTesting())")
		print("VALUE panel clicked: \(bottomPanel.clickVariablesForTesting())")
		print("VALUE panel down: \(bottomPanel.walkVariablesForTesting(["down"]))")
		// Past the leaf and onto a row with something under it: → on a leaf
		// asks the adapter for nothing, so it cannot rebuild anything and the
		// bug cannot show. `openable=` in the report says which kind of row
		// this landed on.
		print("VALUE panel on a container: \(bottomPanel.walkVariablesForTesting(["down"]))")
		print("VALUE panel right: \(bottomPanel.walkVariablesForTesting(["right"]))")
		fflush(stdout)
		bottomPanel.walkVariablesThenSettleForTesting([]) { [weak self] after in
			print("VALUE panel right, once its children arrived: \(after)")
			print("VALUE panel after: \(self?.bottomPanel.variablesKeyboardReportForTesting() ?? "gone")")
			print("VALUE panel selection: \(self?.bottomPanel.variablesSelectionColourForTesting() ?? "gone")")
			fflush(stdout)
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
			walkThePaneForTesting()
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
			self.walkThePaneForTesting()

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

	/// What a server said about the file in front and how loudly it is drawn,
	/// for `--diagnostics`.
	func reportDiagnosticsForTesting(at seconds: Double) {
		print("DIAGNOSTICS at \(Int(seconds))s: \(editor.diagnosticReportForTesting())")
		fflush(stdout)
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
			defer { fflush(stdout) }
			print("COMPLETE: \(self.editor.completionReportForTesting)")
			// What the server said about the item that is highlighted, which is
			// the half that used to be parsed and thrown away.
			print("COMPLETE doc: \(self.editor.completionDocumentationForTesting)")

			self.editor.writeCompletionImageForTesting(to: "build/completion-list.png")

			// Down once, then take it, so what lands in the document is the
			// second suggestion rather than whatever was highlighted first.
			self.editor.moveCompletionSelectionForTesting(by: 1)
			print("COMPLETE doc after ↓: \(self.editor.completionDocumentationForTesting)")
			let committed = self.editor.commitCompletionForTesting()
			print("COMMIT: \(committed) → \(self.editor.caretReportForTesting)")

			// **The moment the change is about.** The list has gone and the
			// first stop is selected: this is where somebody asks what it takes.
			print("HINT: \(self.editor.parameterHintForTesting)")
			self.editor.simulateTab()
			print("HINT after tab: \(self.editor.parameterHintForTesting)")
			self.editor.simulateEscape()
			print("HINT after escape: \(self.editor.parameterHintForTesting)")
		}
	}

	/// Walks the caret by word and says where it landed at each step.
	///
	/// The flush at the end is not decoration: a run ends by killing the app,
	/// and six lines still in stdout's buffer when the signal lands make a
	/// driver that works look like one that prints nothing at all.
	func exerciseWordNavigationForTesting() {
		defer { fflush(stdout) }
		print("WORD: start \(editor.caretReportForTesting)")
		editor.simulateKey("right", modifiers: .option)
		print("WORD: ⌥→ \(editor.caretReportForTesting)")
		editor.simulateKey("right", modifiers: .option)
		print("WORD: ⌥→ \(editor.caretReportForTesting)")
		editor.simulateKey("right", modifiers: [.option, .shift])
		print("WORD: ⇧⌥→ \(editor.caretReportForTesting)")
		editor.simulateKey("left", modifiers: .option)
		print("WORD: ⌥← \(editor.caretReportForTesting)")
		editor.simulateKey("left", modifiers: .option)
		print("WORD: ⌥← \(editor.caretReportForTesting)")
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

extension MainWindowController: NSToolbarDelegate {
	// These identifiers keep their old spelling for the same reason the window
	// autosave names do: AppKit stores a toolbar's arrangement under them, and
	// renaming would rebuild everybody's toolbar from the default.
	private static let capsuleItem = NSToolbarItem.Identifier("ideai.capsule")
	private static let subprojectItem = NSToolbarItem.Identifier("ideai.subproject")
	private static let worktreeItem = NSToolbarItem.Identifier("ideai.worktree")
	private static let devContainerItem = NSToolbarItem.Identifier("ideai.devcontainer")
	private static let runItem = NSToolbarItem.Identifier("ideai.run")

	/// Next to the traffic lights, where a window says what it is.
	///
	/// Centred was tried and reads as decoration: the eye starts at the top left
	/// of a window, and putting the one thing that answers "where am I" anywhere
	/// else makes it something to go looking for.
	/// The devcontainer beside the subproject, in that order, because that is the
	/// order the sentence goes in: this project, this corner of it, and the
	/// machine that corner's tools are on.
	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		// The worktree pill next to the capsule and before the subproject, because
		// it qualifies the same thing the capsule's left half names — which
		// checkout — where the subproject qualifies which corner of it and the
		// devcontainer qualifies what it is built with. Reading left to right
		// then goes from the widest question to the narrowest.
		[
			Self.capsuleItem, Self.worktreeItem, Self.subprojectItem, Self.devContainerItem,
			.flexibleSpace, Self.runItem,
		]
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
				Task { @MainActor in
					let head = await read.value
					capsule.setBranch(head?.name, isUnborn: head?.isUnborn ?? false)
				}
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
			control.onChooseConfiguration = { [weak self, weak control] rect in
				guard let control else { return }
				self?.showConfigurationMenu(from: rect, in: control)
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

		case Self.worktreeItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = WorktreePillButton()
			pill.onClick = { [weak self] in self?.showWorktreeMenu() }
			pill.setWorktree(nil)
			worktreePill = pill
			item.view = pill
			item.menuFormRepresentation = menuItem("Worktree", #selector(showWorktreeMenuItem(_:)))
			item.visibilityPriority = .low
			// The toolbar builds its items when it chooses, which may be long
			// after git answered — so the reading is taken again rather than
			// waited for. Same reason the devcontainer pill does it below.
			readWorktree()
			return item

		case Self.devContainerItem:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let pill = DevContainerPillButton()
			pill.onClick = { [weak self] in self?.showDevContainerMenu() }
			pill.setContainer(nil)
			devContainerPill = pill
			item.view = pill
			item.menuFormRepresentation = menuItem(
				"Devcontainer", #selector(showDevContainerMenuItem(_:))
			)
			item.visibilityPriority = .low
			// The item is built when the toolbar chooses, which may be after the
			// project was loaded and its container asked about.
			refreshDevContainerPill()
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

	@objc fileprivate func showWorktreeMenuItem(_ sender: Any?) { showWorktreeMenu() }

	/// How many checkouts the menu shows before the rest go behind `More…`.
	///
	/// Ten is a menu somebody reads. This repository answers seventy-four —
	/// about fifty from `abydos-backlog start` and twenty an agent harness left
	/// under `.claude/worktrees/` — and a flat list of those is a wall the eye
	/// slides off, which is the same as not being there.
	private static let worktreesShown = 10

	/// The checkouts of this repository, so moving between them is a menu rather
	/// than a hunt through the file system.
	///
	/// The primary is always here and always first, because it is the way back
	/// and the pill would otherwise be a door that only opens outward. So is the
	/// one this window is on, ticked, even when the ordering would have put it
	/// past the cap — a menu whose tick is not in it reads as being nowhere.
	@objc func showWorktreeMenu() {
		let anchor: NSView? = worktreePill ?? capsule
		worktreeMenu().popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: (anchor?.bounds.maxY ?? 0) + Theme.current.scaled(4)),
			in: anchor
		)
	}

	/// Built apart from being shown, so the harness can read it: a menu cannot be
	/// photographed while it is open, and the interesting claim about this one is
	/// what it does with seventy-four entries.
	private func worktreeMenu() -> NSMenu {
		let menu = NSMenu()
		let current = project?.root.standardizedFileURL.path

		// The directory is gone, so the one thing a row here can do would fail.
		// They stay in the branches pane, where removing one is the point.
		let present = worktrees.filter { !$0.isMissing }

		var shown = Array(present.prefix(Self.worktreesShown))
		if let here = present.first(where: { $0.path.path == current }),
		   !shown.contains(where: { $0.path.path == here.path.path }) {
			shown.append(here)
		}
		let rest = present.filter { entry in !shown.contains { $0.path.path == entry.path.path } }

		// What every other row is named against, so a folder that only repeats
		// its branch can be told from one somebody chose.
		let primaryName = present.first { $0.isPrimary }?.name ?? project?.name ?? ""

		for worktree in shown {
			menu.addItem(worktreeItem(worktree, current: current, primaryName: primaryName))
		}

		if !rest.isEmpty {
			menu.addItem(.separator())
			let more = NSMenuItem(title: "More — \(rest.count) older", action: nil, keyEquivalent: "")
			let submenu = NSMenu()
			for worktree in rest {
				submenu.addItem(worktreeItem(worktree, current: current, primaryName: primaryName))
			}
			more.submenu = submenu
			menu.addItem(more)
		}

		// Adding, removing and revealing a checkout all live in the branches
		// pane already, with a filter field in front of them. The titlebar is
		// for going somewhere; this is the way through to the rest.
		menu.addItem(.separator())
		menu.addItem(menuItem("Show All Worktrees…", #selector(toggleBranchesView(_:))))
		return menu
	}

	/// The longest a row is allowed to be before the tail is dropped.
	///
	/// A branch here is named after a backlog item, and a backlog item's branch
	/// carries most of its title — `backlog/0479-toggle-comment-answers-to-a-key-
	/// nobody-asked-for-on-a`. Ten of those side by side is a menu as wide as the
	/// display, which is not a menu somebody reads either. The tail goes rather
	/// than the middle because what tells these apart is at the front: the
	/// number.
	private static let worktreeTitleLimit = 52

	/// One checkout: what is checked out there, and its folder name when that
	/// says something the branch does not.
	///
	/// The branch is on the item rather than only in the tool tip, because the
	/// folder name is a decision somebody made months ago and the branch is what
	/// they are looking for. `GitWorktree.summary` says it in all three of the
	/// states 0477 settled — a branch, one with nothing on it, and a commit
	/// checked out directly — so a detached worktree reads as `detached at
	/// abc1234` here rather than as a bare folder name.
	private func worktreeItem(
		_ worktree: GitWorktree, current: String?, primaryName: String
	) -> NSMenuItem {
		let label = GitWorktrees.label(for: worktree, primaryName: primaryName)
		let item = NSMenuItem(
			title: label.count > Self.worktreeTitleLimit
				? label.prefix(Self.worktreeTitleLimit - 1) + "…"
				: label,
			action: #selector(openWorktreeFromMenu(_:)),
			keyEquivalent: ""
		)
		item.target = self
		item.representedObject = worktree.path
		item.state = worktree.path.path == current ? .on : .off
		// The whole of it, which the title may have dropped the tail of, and the
		// directory — the one thing a row never shows and the thing somebody
		// needs when two branches read alike.
		item.toolTip = [
			label,
			worktree.path.path,
			worktree.isPrimary ? "The checkout this repository was cloned into" : nil,
		].compactMap { $0 }.joined(separator: "\n")
		return item
	}

	@objc private func openWorktreeFromMenu(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL,
		      url.standardizedFileURL.path != project?.root.standardizedFileURL.path
		else { return }
		// Through the delegate rather than `switchProject`, the way a worktree
		// opened from a backlog card or the project switcher goes: this window or
		// a new one, whichever the setting says, and a checkout already open in
		// another window is raised rather than opened twice. That last part is
		// what makes the arrangement 0454 relies on — a card's work in a worktree
		// while another window sits on the primary — survive being clicked at.
		(NSApp.delegate as? AppDelegate)?.open(projectAt: url, from: self)
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

	/// Clicks the branch pill, for measuring what opening it costs.
	func showBranchMenuForTesting() { showBranchMenu() }

	fileprivate func showBranchMenu() {
		guard let project, let capsule else { return }
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

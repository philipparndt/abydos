import AppKit
import AbydosKit

/// The left rail and what it opens: the project tree, changes, branches, the
/// outline, scratches, history — and the git log and commit pages those last two
/// open into.
///
/// **Not an `NSViewController`, which the plan assumed it would be.** The rail
/// is a subview of the window's root and the tool it opens lives inside
/// `navigatorContainer`, on the other side of a split view. There is no single
/// view for this object to be the controller of, so it owns the pieces and the
/// window keeps building the hierarchy. That also means its actions are not
/// found through the responder chain, so they stay on the window controller as
/// one-line forwards, exactly as the titlebar's do.
///
/// What it owns is the tool state: which tool is showing, the pane for each, the
/// popover a narrow window shows one in, and the sidebar's own split — including
/// the lower half a results list is docked into, which `ResultsPresenter` has
/// been reaching for through two closures since it was written.
@MainActor
final class SidebarController: NSObject {
	/// Not private: `SidebarController+Compare` opens the diff tab and the log
	/// page, and Swift's `private` is file-scoped.
	let editor: EditorAreaController
	/// A remembered compare page coming back with its project.
	var onOpenComparePage: ((CompareSource, CompareSource) -> Void)?
	let navigator: ProjectNavigatorViewController

	// What the window knows and this object asks for.
	var project: () -> Project? = { nil }
	var hostWindow: () -> NSWindow? = { nil }
	/// The message the project was left composing, asked for when a pane is
	/// built rather than pushed at whatever pane exists — the sidebar tool is
	/// rebuilt when the repository finishes reading, and a push would go with
	/// the pane it landed in.
	var rememberedMessage: () -> ProjectSession.ComposedMessage? = { nil }
	/// What each tree was folded into, asked for at the same moment and for the
	/// same reason: this tool is rebuilt when the repository finishes reading,
	/// and folds pushed at whatever pane existed a second earlier go into the
	/// bin with it. Keyed `refs`, `changes.unstaged`, `changes.staged`.
	var rememberedFolds: () -> [String: ProjectSession.TreeFolds] = { [:] }
	/// The window's draft inbox: where a finished draft is kept until the
	/// project it was asked for has a pane to put it in.
	var holdDraft: (URL, ClaudeDraft.Draft) -> Void = { _, _ in }
	var heldDraft: (URL) -> ClaudeDraft.Draft? = { _ in nil }
	var discardDraft: (URL) -> Void = { _ in }
	/// The two pages this controller does not own but a session names: the
	/// launch configurations belong to the run coordinator and the settings to
	/// the window. Closures for the reason every other cross-controller verb
	/// here is one — the sidebar knows the session, not the page.
	var openLaunchConfigurationsPage: () -> Void = {}
	var openSettingsPage: (_ asked: Bool) -> Void = { _ in }
	var gitCommandRoot: () -> URL? = { nil }
	var relativePathOfActiveFile: () -> String? = { nil }
	var symbols: (String, SymbolPalette.Scope) async -> [LSPSymbol] = { _, _ in [] }
	var notify: (String, String?) -> Void = { _, _ in }

	// The window's layout, which this object asks about but does not arrange.
	var isNavigatorVisible: () -> Bool = { false }
	var showNavigator: () -> Void = {}
	var hideNavigator: () -> Void = {}
	var isPanelMaximized: () -> Bool = { false }
	var leaveMaximised: () -> Void = {}
	var leaveTerminalFullScreen: () -> Void = {}
	var onInsetsChanged: () -> Void = {}
	/// A log or a commit page is opened to be read, and is unreadable in a
	/// third of a window. The gesture is the window's; asking is this object's.
	var giveTheEditorTheWindow: () -> Void = {}
	var isPanelVisible: () -> Bool = { false }
	/// The repository read the window runs, which several panes ask to repeat.
	var readGit: () -> Void = {}
	/// Opening a checkout is the window's, the way every other route to one is.
	var openProject: (URL) -> Void = { _ in }

	init(editor: EditorAreaController, navigator: ProjectNavigatorViewController) {
		self.editor = editor
		self.navigator = navigator
		super.init()
	}

	/// The rail itself, which the window puts down its left edge.
	var rail: ToolWindowBar { toolStrip }

	/// The sidebar's lower half, so a driven run can prove a list is in it.
	var dockHost: NSView? { sidebarDock }

	private let toolStrip = ToolWindowBar()

	var changesPane: ChangesPane?

	private(set) var branchesPane: BranchesPane?

	private var structurePane: StructurePane?

	var scratchesPane: ScratchesPane?

	private(set) var historyPane: HistoryPane?

	/// Reviewing: the list, the page it opens, and the run that drives them.
	///
	/// **A collaborator rather than more of this class**, which was already at
	/// the length where a file stops being read and starts being appended to.
	/// The window wires it — see `MainWindowController.wireReviewing` — because
	/// what it needs to be told is the editor area and the project, and both of
	/// those are the window's.
	let pullRequests = PullRequestReview()

	var primaryToolView: NSView?

	var primaryToolTop: NSLayoutConstraint?

	var primaryContainer: NSView!

	/// The sidebar, split horizontally: the tool above, a results list below
	/// when one has been put there. One arranged subview and no divider until
	/// then — see where it is built.
	var sidebarSplit: ThinDividerSplitView!

	/// The lower half, while a list is living in it.
	private var sidebarDock: ColoredView?

	/// How much of the sidebar's height the tool keeps, remembered so a list
	/// coming back finds the divider where it was left rather than halfway.
	private var sidebarToolFraction: CGFloat = 0.55

	private(set) var currentSidebarTool: SidebarToolKind = .project

	/// Height the titlebar covers, applied to sidebar panes that do not inset
	/// themselves.
	var sidebarTopInset: CGFloat = 0

	/// What the rail is showing, for `--rail`.
	///
	/// The panel's own state leads, because the rail's rule is written in terms
	/// of it and a report that said only which buttons were lit could not tell a
	/// closed panel from a bug.
	func railReportForTesting() -> String {
		// The tool in front is named too. The rail's own buttons do not cover
		// every sidebar tool — there is no branches button — so a run asking
		// "did the tool come back" could not read the answer anywhere.
		"panel=\(isPanelVisible() ? "open" : "closed") tool=\(currentSidebarTool.stored) "
			+ toolStrip.reportForTesting()
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

	/// Puts a list in the lower half of the sidebar, splitting it for the
	/// occasion.
	func dockInSidebar(_ pane: any ResultsPane, focusList: Bool) {
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
		if isPanelMaximized() { leaveMaximised() }
		if !isNavigatorVisible() { showNavigator() }

		let height = sidebarSplit.bounds.height
		if height > 80 {
			sidebarSplit.setPosition(height * sidebarToolFraction, ofDividerAt: 0)
		}
		sidebarSplit.adjustSubviews()
		if focusList { DispatchQueue.main.async { pane.focusList() } }
	}

	/// Takes a list out of the sidebar and puts the sidebar back to one view.
	func undockFromSidebar(_ pane: any ResultsPane) {
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
		if isPanelMaximized() {
			showToolPopover(tool)
			return
		}

		// Hidden, or dragged shut until there is nothing left of it — which is
		// the same thing to look at and was not the same thing to the code:
		// pressing ⌘2 on a sidebar somebody had dragged closed did nothing at
		// all, twice, because it thought it was already showing.
		let isCollapsed = !isNavigatorVisible()

		if !isCollapsed, tool == currentSidebarTool {
			hideNavigator()
			return
		}

		install(tool: tool)
		if isCollapsed { showNavigator() }
		updateSidebarSelection()
	}

	/// Brings a tool on screen, with none of the strip button's toggling.
	///
	/// `showSidebarTool` is a tab: asking for the one already showing puts the
	/// sidebar away, which is right for a button somebody is clicking and wrong
	/// for a menu command that is about to put a text field in that tool. "New
	/// File" cannot be the thing that hides the tree it is creating the file
	/// in — so this one only ever ends with the tool visible.
	func revealSidebarTool(_ tool: SidebarToolKind) {
		// A maximised terminal hides the sidebar and the editor together, so
		// the tool would arrive in a view that is not on screen — the same
		// silence `showList` describes, and the same way out of it.
		if isPanelMaximized() { leaveMaximised() }
		install(tool: tool)
		if !isNavigatorVisible() { showNavigator() }
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
			height: min(Theme.current.scaled(560), (hostWindow()?.frame.height ?? 700) - 120)
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
			// `queue: .main` is the promise this rests on. On the window
			// controller the closure inherited that class's isolation and needed
			// no saying; on a class of its own it is a `@Sendable` closure and
			// has to say what it already is.
			MainActor.assumeIsolated {
				guard let self else { return }
				self.toolPopover = nil
				self.popoverTool = nil
				self.toolStrip.setSidebarSelection(visible: false, tool: self.currentSidebarTool)
				// The popover borrowed the sidebar's own views — the tree most of
				// all — so they are put back where they belong.
				self.install(tool: self.currentSidebarTool, force: true)
				// The tree ducks under the titlebar again once it is back in the
				// sidebar.
				self.onInsetsChanged()
				if let observer = self.popoverObserver {
					NotificationCenter.default.removeObserver(observer)
					self.popoverObserver = nil
				}
			}
		}
	}

	/// The tool showing over the terminal, if one is.
	var toolPopover: NSPopover?

	private var popoverTool: SidebarToolKind?

	private var popoverObserver: NSObjectProtocol?

	func updateSidebarSelection() {
		let visible = isNavigatorVisible()
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
			over: primaryToolView ?? primaryContainer, message: "Reading repository…",
			paneIsEmpty: primaryToolView == nil
		)

		Task { @MainActor [weak self] in
			await self?.project()?.loadGit()
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

	/// Shows the tool a project was left on, if it named one.
	///
	/// **It does not open a sidebar somebody closed.** Whether the sidebar is
	/// showing is the split view's autosave, per machine: somebody who closed
	/// it closed it for the window and not for the project, and a restore that
	/// opened it would be the session arguing with the layout. This only
	/// decides *which* tool is behind that, whether or not it is on screen.
	///
	/// A name this version does not know, or a git tool in a folder that is no
	/// working copy, falls back to the project tree — which is where a window
	/// starts anyway, so the fallback is doing nothing. `install(tool:)` waits
	/// for a repository that is still being read and gives up quietly on one
	/// that never arrives, which is the whole of that.
	func showRemembered(tool stored: String?) {
		guard let tool = SidebarToolKind.named(stored), tool != currentSidebarTool else { return }
		install(tool: tool)
	}

	func install(tool: SidebarToolKind, force: Bool = false) {
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
		pullRequests.paneWentAway()

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
	func install(view: NSView, for tool: SidebarToolKind) -> NSView {
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
		onInsetsChanged()
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
			guard let project = project(), project.git != nil else { return nil }
			let pane = ChangesPane(root: gitCommandRoot() ?? project.root)
			pane.onSelectChange = { [weak self] change in self?.showDiff(for: change) }
			// `…` promotes the message rather than starting a second one.
			pane.onOpenPage = { [weak self] summary in
				self?.showCommitPage(carrying: summary)
			}
			pane.onWorkingCopyChanged = { [weak self] in self?.navigator.refreshGitStatus() }
			changesPane = pane
			// Here rather than after the switch, because this is the moment a
			// pane exists: a message put into the pane standing before the
			// repository was read went into the bin with it, which is the loss
			// the code that rebuilds this tool already records having caused.
			wireDrafts(of: pane)
			if let message = rememberedMessage() { pane.restore(message: message) }
			// And what was folded, for the same reason and at the same moment.
			pane.folds = rememberedFolds()
			// A draft may have come back while this project was away, or while
			// this pane was being rebuilt — which happens when the branch read
			// lands, seconds after a window opens.
			pane.applyHeldDraft()
			view = pane
		case .branches:
			// Nothing to show until the project's repository has been read,
			// which the caller waits for rather than leaving the sidebar empty.
			guard let project = project(), project.git != nil else { return nil }
			let pane = BranchesPane(root: gitCommandRoot() ?? project.root)
			// A worktree is a project in its own right, so opening one is
			// switching to it rather than checking anything out.
			//
			// Through the delegate, which this was the one caller not doing
			// (0490): a bare `switchProject` took over the window whatever the
			// setting said, and opened a second window on a checkout that
			// already had one. The backlog card, the project switcher and now
			// the titlebar all go through the same door.
			pane.onOpenCommitPage = { [weak self] in self?.showCommitPage(carrying: nil) }
			pane.onOpenEstate = { [weak self] in self?.showEstatePage() }
			pane.onOpenFiles = { [weak self] paths in
				guard let self, let project = self.project() else { return }
				for path in paths {
					self.editor.open(fileURL: project.root.appendingPathComponent(path))
				}
			}
			pane.onShowLog = { [weak self] ref in self?.showLogPage(scopedTo: ref) }
			pane.onReviewStash = { [weak self] entry in self?.showStashPage(entry) }
			pane.onSelectChange = { [weak self] change in self?.showDiff(for: change) }
			pane.onOpenWorktree = { [weak self] path in self?.openProject(path) }
			pane.onRepositoryChanged = { [weak self] in
				// A checkout changes the branch the titlebar shows, so the
				// repository is read again — the same read everything else
				// awaits.
				self?.readGit()
				// And the stash page, if one is open: a stash dropped from the
				// tree leaves a page describing something that is not there.
				self?.stashPage?.refresh()
			}
			branchesPane = pane
			// The working copy shut, `origin` and `Tags` opened — whatever was
			// arranged here last time, taken as the pane is built. This is the
			// row the report was about.
			if let refs = rememberedFolds()["refs"] { pane.folds = refs }
			view = pane
		case .history:
			// Nothing to show until the project's repository has been read,
			// which the caller waits for rather than leaving the sidebar empty.
			guard let project = project(), project.git != nil else { return nil }
			let pane = HistoryPane(root: gitCommandRoot() ?? project.root)
			pane.onOpenWorkingCopyDiff = { [weak self] change, root, text in
				self?.editor.openDiff(for: change, root: root, text: text)
			}
			pane.offerScope(path: relativePathOfActiveFile())
			pane.onSelectFile = { [weak self] commit, file in
				self?.showCommitDiff(commit: commit, file: file)
			}
			historyPane = pane
			view = pane
		case .pullRequests:
			// Nothing until the repository has been read: a pull request is
			// asked about by remote, and only the repository knows the remote.
			guard project()?.git != nil, let pane = pullRequests.makePane() else { return nil }
			view = pane
		case .scratches:
			let pane = ScratchesPane(projectRoot: project()?.root)
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
	/// - Parameter ref: a branch or tag to show the history of, or nil for the
	///   branch that is checked out.
	/// - Parameter asked: whether somebody asked for this page. Only then does
	///   it give the editor the window back: while the terminal panel has the
	///   whole window the editor is *hidden*, so a page opened into it could
	///   not be seen — and a page being restored with a project asked for
	///   nothing. See `reopen(page:)`, which is the other caller.
	/// - Parameter owner: the repository whose log this is, when it is not the
	///   project's own — a submodule, for the history of a file inside one.
	/// The log page, while one is open, for the driver to read.
	weak var logPage: HistoryPane?

	/// The commit page, likewise.
	weak var commitPage: ChangesPane?

	/// The estate page, while one is open, for the driver to read.
	weak var estatePage: EstateOverviewPage?
	weak var stashPage: StashPage?


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

	func openFirstScratchForTesting() {
		scratchesPane?.openFirstForTesting()
	}

	func selectFirstChangeForTesting() {
		changesPane?.selectFirstChangeForTesting()
	}

	/// Flips how the git page arranges a commit's files, and ticks itself.
}

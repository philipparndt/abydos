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
	private let editor: EditorAreaController
	private let navigator: ProjectNavigatorViewController

	// What the window knows and this object asks for.
	var project: () -> Project? = { nil }
	var hostWindow: () -> NSWindow? = { nil }
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
		"panel=\(isPanelVisible() ? "open" : "closed") " + toolStrip.reportForTesting()
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
	/// A key-down for ⎋, for a driven run that wants the key rather than the
	/// method it ends up in.
	static func escapeEvent() -> NSEvent {
		NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
			windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
			characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
			isARepeat: false, keyCode: 53
		)!
	}

	/// Whether the editor's find bar is up — the other half of "who got ⌘F".
	private var editorFindBarIsShowing: Bool { editor.findBarIsShowingForTesting }

	/// ⌘⏎, the key a row's own verb is on.
	static func commandReturnEvent() -> NSEvent {
		NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
			windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
			characters: "\r", charactersIgnoringModifiers: "\r",
			isARepeat: false, keyCode: 36
		)!
	}

	/// Walks the window's responder chain for Find and names who takes it.
	///
	/// **The chain, not the key, and the window's chain rather than the
	/// application's.** Three ways were tried before this one. A hand-made
	/// `NSEvent` through `performKeyEquivalent` is ignored; a `CGEvent` at the
	/// window server needs an Accessibility grant the built app does not have;
	/// and `NSApp.sendAction(to: nil)` goes through the *key window*, which a
	/// driven run does not have — these runs are not activated, and the report
	/// said `app active false` rather than lying about the outcome.
	///
	/// What is left is the thing actually in question. The ⌘F binding is
	/// untouched by this change — the item is `keyEquivalent: "f"` and was
	/// before — and what the change adds is a second implementor of the action
	/// further down the chain. So: start at the window's first responder, walk
	/// up, and say who answers.
	static func sendFind(in window: NSWindow?) -> String {
		let selector = #selector(MainWindowController.findInFile(_:))
		var responder = window?.firstResponder
		while let here = responder {
			if here.responds(to: selector) {
				_ = here.perform(selector, with: nil)
				return String(describing: type(of: here))
			}
			responder = here.nextResponder
		}
		return "nobody"
	}

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
			case "find":    pane.showFilter()
			// A real ⎋ through the responder chain, not a call to what ⎋ calls:
			// the question here is whether the key reaches the strip at all.
			case "escape":  pane.window?.sendEvent(SidebarController.escapeEvent())
			// ⌘F through the menu bar, which is how the press actually
			// arrives — the responder chain decides who gets it, and the
			// question in 4.4 is whether it decides the way it should.
			case "cmdf":
				print("BRANCHES find taken by: \(SidebarController.sendFind(in: pane.window))")
			case "focus-tree": pane.window?.makeFirstResponder(pane.tableViewForTesting)
			// Several branches at once, and what the menu would then offer and
			// copy. `+` between the names, as the other multi-row steps use.
			case "select":
				print("BRANCHES select: "
					+ pane.selectBranchesForTesting(argument.split(separator: "+").map(String.init)))
			case "menu":
				print("BRANCHES menu: \(pane.branchMenuTitlesForTesting().joined(separator: " | "))")
			case "copy-name":
				print("BRANCHES copy-name would copy:\n"
					+ pane.copyNameTextForTesting().split(separator: "\n")
						.map { "  " + $0 }.joined(separator: "\n"))
			case "unfind":  pane.hideFilter()
			case "menu":
				print("BRANCHES menu \(argument): "
					+ pane.menuTitlesForTesting(row: Int(argument) ?? 0))
			case "fstate":  print("BRANCHES filter: \(pane.filterStateForTesting())"
				+ " · editor find \(editorFindBarIsShowing ? "open" : "shut")"
				+ " · responder \(type(of: pane.window?.firstResponder ?? NSNull()))")
			case "refresh": pane.refresh()
			// What each row offers, and firing the selected one's verb — the
			// two halves of "a row's action can be reached from the keyboard".
			case "actions": print("BRANCHES actions:\n  "
				+ pane.rowActionsForTesting().joined(separator: "\n  "))
			case "select":  pane.selectRowForTesting(Int(argument) ?? 0)
			case "fire":    pane.fireSelectedRowActionForTesting()
			case "repo":    print("BRANCHES repo: \(pane.repositoryRowForTesting())")
			case "repo-fire": pane.fireRepositoryRowForTesting()
			// The pinned row's whole claim is that scrolling does not take it
			// away, and only a scrolled tree can say whether that is true.
			case "scroll":  pane.scrollTreeForTesting(toBottom: argument != "top")
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
		hostWindow()?.layoutIfNeeded()
		return pane.typeInCommitBodyForTesting(text)
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
			over: primaryContainer, message: "Reading repository…"
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
			pane.onOpenFiles = { [weak self] paths in
				guard let self, let project = self.project() else { return }
				for path in paths {
					self.editor.open(fileURL: project.root.appendingPathComponent(path))
				}
			}
			pane.onShowLog = { [weak self] ref in self?.showLogPage(scopedTo: ref) }
			pane.onSelectChange = { [weak self] change in self?.showDiff(for: change) }
			pane.onOpenWorktree = { [weak self] path in self?.openProject(path) }
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
			guard let project = project(), project.git != nil else { return nil }
			let pane = HistoryPane(root: gitCommandRoot() ?? project.root)
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
	func showLogPage(scopedTo ref: String?) {
		leaveTerminalFullScreen()
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return }

		let page = (group.page(identifier: "log") as? HistoryPane)
			?? HistoryPane(root: gitCommandRoot() ?? project.root, layout: .page)
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
		giveTheEditorTheWindow()
		// Opened to be read, and read with the arrows: a page whose keyboard is
		// still in whatever opened it needs a click before it can be walked.
		DispatchQueue.main.async { [weak page] in page?.focusList() }
		page.setRef(ref)
	}

	/// The log page, while one is open, for the driver to read.
	private(set) weak var logPage: HistoryPane?

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
	func showCommitPage(carrying summary: String?) {
		leaveTerminalFullScreen()
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return }

		let page: ChangesPane
		if let existing = group.page(identifier: "commit") as? ChangesPane {
			page = existing
		} else {
			page = ChangesPane(root: gitCommandRoot() ?? project.root, layout: .page)
			page.onWorkingCopyChanged = { [weak self] in
				self?.navigator.refreshGitStatus()
				self?.changesPane?.refresh()
			}
		}
		commitPage = page
		group.openPage(page, title: "Commit", identifier: "commit", symbol: "checkmark.circle")
		giveTheEditorTheWindow()
		DispatchQueue.main.async { [weak page] in page?.focusList() }

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
			case "who":    print("COMMIT-PAGE \(page.keyboardReportForTesting())")
			case "keys":   print("COMMIT-PAGE keys: " + page.keysForTesting(argument))
			case "select": page.selectChangeForTesting(argument)
			case "type":   page.carrySummaryForTesting(argument)
			default:       print("COMMIT-PAGE: unknown step \(step)")
			}
		}
	}

	/// What the pull request list says, row by row — see `PullRequestReview`.
	func pullRequestsForTesting(_ steps: String) { pullRequests.driveForTesting(steps) }

	/// What the log page holds, and what its menu over a commit offers.
	func logPageForTesting(_ steps: String, waiting: Int = 8) {
		if logPage == nil { showLogPage(scopedTo: nil) }
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
			// The changes view's own rows, which `report` does not carry: how a
			// commit's files are arranged is the question, and the flat
			// arrangement has to match what the page drew before it was an
			// outline at all.
			// The keyboard's own claims: a click gives the list focus, the
			// arrows move, and ← and → shut and open without losing the row.
			case "keys":
				print("LOG-PAGE keys: " + page.fileKeysForTesting(argument))
				fflush(stdout)
			case "files":
				print("LOG-PAGE files:\n  " + page.fileRowsForTesting().joined(separator: "\n  "))
			case "arrange": page.toggleFileArrangementForTesting()
			case "star":    page.pressStarForTesting()
			case "shut":    page.collapseEveryFolderForTesting()
			default:       print("LOG-PAGE: unknown step \(step)")
			}
		}
	}

	/// Moves the selected lines across the index, in whichever direction the
	/// diff's side implies.
	func applyDiffSelection(change: GitChange, diff: String, lines: Set<Int>) {
		guard let project = project(), !lines.isEmpty else { return }
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
	func stashDiffSelection(change: GitChange, diff: String, lines: Set<Int>) {
		guard let project = project(), !lines.isEmpty else { return }
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

	func discardDiffSelection(change: GitChange, diff: String, lines: Set<Int>) {
		guard let project = project(), !lines.isEmpty else { return }

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

		if let window = hostWindow() {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	private func finishDiffOperation(_ result: GitRepository.ProcessResult, change: GitChange) {
		if result.exitCode != 0 {
			notify(
				"git reported a problem",
				(result.stderr.isEmpty ? result.stdout : result.stderr)
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
		guard let project = project() else { return }
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
		guard let project = project() else { return }
		Task { @MainActor in
			let text = await GitHistory.diff(of: commit.hash, path: file.path, in: project.root)
			editor.openCommitDiff(commit: commit, file: file, root: project.root, text: text)
		}
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

	func openFirstScratchForTesting() {
		scratchesPane?.openFirstForTesting()
	}

	func selectFirstChangeForTesting() {
		changesPane?.selectFirstChangeForTesting()
	}

	/// Flips how the git page arranges a commit's files, and ticks itself.
}

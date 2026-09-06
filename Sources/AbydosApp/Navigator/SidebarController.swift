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
	var openSettingsPage: () -> Void = {}
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
			case "recreate": pane.recreateTagForTesting()
			// The tag delete with the sheet's answer given — `delete-tag` for
			// the local half alone, `delete-tag:remote` for both. The sheet
			// itself stays undriven: `NSAlert` wants a person, and reaching in
			// to press it would be testing `NSAlert`.
			case "delete-tag": pane.deleteTagForTesting(alsoOnRemote: argument == "remote")
			// Opening a stash as a page, and what that page then says.
			case "review-stash":
				print("BRANCHES review-stash: " + pane.reviewStashForTesting(argument))
			case "stash-page":
				print(stashPage?.reportForTesting() ?? "STASH-PAGE none")
			case "stash-page-select":
				print("STASH-PAGE select: "
					+ (stashPage?.selectForTesting(argument) ?? "no page"))
			case "stash-page-press":
				print("STASH-PAGE press: "
					+ (stashPage?.pressForTesting(argument) ?? "no page"))
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
			// Clicks and arrows, with the selection read after each — the
			// tree-behaviour claim, asked of this tree as of the other three.
			case "keys": print("BRANCHES keys: " + pane.keysForTesting(argument))
			// Several branches at once, and what the menu would then offer and
			// copy. `+` between the names, as the other multi-row steps use.
			// A row index selects that row; names select those branches. One
			// verb rather than two because they are the same step asked in two
			// ways — and because two `case "select"` in one switch is a warning
			// saying the second is dead, which it was.
			case "select":
				if let row = Int(argument) {
					pane.selectRowForTesting(row)
				} else {
					print("BRANCHES select: " + pane.selectBranchesForTesting(
						argument.split(separator: "+").map(String.init)
					))
				}
			case "menu":
				if let row = Int(argument) {
					print("BRANCHES menu \(argument): " + pane.menuTitlesForTesting(row: row))
				} else {
					print("BRANCHES menu: "
						+ pane.branchMenuTitlesForTesting().joined(separator: " | "))
				}
			// `choose:<row>:<title>` fires that row's menu item by title, the
			// way a person picking a sort order would.
			case "choose":
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				if parts.count == 2, let row = Int(parts[0]) {
					print("BRANCHES choose: "
						+ pane.chooseMenuItemForTesting(row: row, titled: parts[1]))
				} else {
					print("BRANCHES choose: wants row:title, got \(argument)")
				}
			case "delete-wording":
				Task { @MainActor in
					print("BRANCHES delete-wording: \(await pane.deleteWordingForTesting())")
					fflush(stdout)
				}
			// The delete itself, with the dialog's checkbox as the argument —
			// `delete:worktrees` ticks it, `delete` leaves it. This skips the
			// dialog; `sheet-press` below is the step that answers one.
			case "delete":
				Task { @MainActor in
					await pane.deleteForTesting(removingWorktrees: argument == "worktrees")
				}
			// The dialog itself, on screen, for a screenshot of it.
			case "ask-delete": pane.askAboutDeletingForTesting()
			case "sheet":      print(pane.deleteSheetForTesting())
			// The working copy's own verb, and answering the dialog it opens.
			// Not `stash`, which is taken above for opening a stash row — a
			// second one is dead code the compiler does not always mention.
			case "stash-changes": pane.stashWorkingCopyForTesting()
			case "stash-answer":
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				print("BRANCHES stash-answer: " + pane.answerStashForTesting(
					parts.first ?? "", untracked: (parts.count > 1 ? parts[1] : "yes") != "no"
				))
			// Publishing with no remote, which is the case that used to fail in
			// git's words instead of asking for one.
			case "publish":    pane.pushSelectedForTesting()
			case "remote":     pane.setRemoteForTesting()
			case "type-remote": pane.typeRemoteForTesting(argument)
			// Answering it — the step the two above skip between them. Not
			// `press`, which the banner below has: a second one is a dead case.
			case "sheet-press": print("BRANCHES "
				+ BranchDeletion.pressSheetButtonForTesting(argument, in: pane.window))
			case "copy-name":
				print("BRANCHES copy-name would copy:\n"
					+ pane.copyNameTextForTesting().split(separator: "\n")
						.map { "  " + $0 }.joined(separator: "\n"))
			case "unfind":  pane.hideFilter()
			case "fstate":  print("BRANCHES filter: \(pane.filterStateForTesting())"
				+ " · editor find \(editorFindBarIsShowing ? "open" : "shut")"
				+ " · responder \(type(of: pane.window?.firstResponder ?? NSNull()))")
			case "refresh": pane.refresh()
			// What each row offers, and firing the selected one's verb — the
			// two halves of "a row's action can be reached from the keyboard".
			case "actions": print("BRANCHES actions:\n  "
				+ pane.rowActionsForTesting().joined(separator: "\n  "))
			case "fire":    pane.fireSelectedRowActionForTesting()
			case "repo":    print("BRANCHES repo: \(pane.repositoryRowForTesting())")
			case "repo-fire": pane.fireRepositoryRowForTesting()
			// The pinned row's whole claim is that scrolling does not take it
			// away, and only a scrolled tree can say whether that is true.
			// The strip above the tree while git is mid-operation, and its
			// verbs: `banner`, `press:continue`, `press:skip`, `press:abort`.
			case "banner":  print(pane.operationBannerForTesting())
			case "press":   pane.pressBannerForTesting(argument)
			// What the `⋯` menu holds, and what one conflicted file's row
			// offers — neither of which a shot of a closed menu can show.
			// Every remote verb the repository row offers, and when it last
			// fetched — the row draws one verb and there are four.
			// Which refs the pane calls finished, by ref rather than by name:
			// `origin/x` and `x` are two questions.
			case "merged":
				print("BRANCHES merged: " + pane.mergedMarkForTesting())
			case "delete-remote":
				pane.deleteRemoteForTesting()
			case "remote-menu":
				print("REPOSITORY menu: " + pane.remoteMenuForTesting())
			case "fetch":
				pane.pressFetchForTesting()
			// What the editor is showing, so "a click on a row opens the file"
			// is a claim a driven run can check rather than a screenshot.
			case "tabs":
				print("TABS: " + (editor.activeGroup?.tabTitlesForTesting.joined(separator: ", ")
					?? "no group"))
			case "banner-menu":
				print("BANNER menu \(argument.isEmpty ? "more" : argument): "
					+ pane.bannerMenuForTesting(argument))
			// Resolving one file the way the row's menu does:
			// `resolve:<path>:<ours|theirs|mark|open>`.
			case "resolve":
				let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)
				print("BANNER resolve: " + pane.resolveConflictForTesting(
					parts.first ?? "", how: parts.count > 1 ? parts[1] : "mark"
				))
			case "scroll":  pane.scrollTreeForTesting(toBottom: argument != "top")
			default:        print("BRANCHES: unknown step \(step)")
			}
			// Every step, because a driven run is killed rather than ended:
			// stdout is a pipe, the buffer is never drained by the exit, and a
			// report written after the last flushing step is simply lost. It
			// cost half an hour of "the tree prints nothing" that was a report
			// sitting in a buffer.
			fflush(stdout)
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
			// Selects the row the way a first click does, deferred diff and
			// all, so the double-click shape can be driven: select, then stage.
			case "select":
				pane.selectForTesting(path: argument, staged: false)
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
			// The commit message history: `history` prints the menu's entries,
			// `use-history:<n>` fills the fields from one — both async (the
			// log is read when the menu opens), so settle before reading.
			case "history":
				pane.messageHistoryForTesting()
			// What the Draft button would ask for. `draft-ask:plain` asks with
			// the setting off, so the two shapes can be read in one run.
			case "draft-ask":
				if argument == "plain" { Settings.shared.conventionalCommitDrafts = false }
				pane.draftAskForTesting()
			// Both halves of a message, and what is left of them: the two steps
			// a switch-and-return proof needs. `compose:<summary>|<body>`.
			case "compose":
				let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)
				pane.composeForTesting(
					summary: parts.first ?? "", body: parts.count > 1 ? parts[1] : ""
				)
			case "message":
				print("CHANGES message: " + pane.messageReportForTesting())
			// Commits what is staged with this subject, through the button's
			// own door: whether the project's hooks ran is a claim that wants a
			// trace rather than an assertion.
			case "commit-now": pane.commitForTesting(subject: argument)
			case "use-history":
				pane.useHistoryEntryForTesting(Int(argument) ?? 0)
			// Ends the run, and is the one ending that flushes: a script with
			// no exit is killed by whatever waits on it, and a kill loses what
			// `print` buffered — reports were written and never seen.
			case "exit":
				fflush(stdout)
				exit(0)
			default:
				print("CHANGES: no such step \(step)")
			}
		}
		fflush(stdout)
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
	func showLogPage(scopedTo ref: String?, asked: Bool = true) {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return }

		let page = (group.page(identifier: "log") as? HistoryPane)
			?? HistoryPane(root: gitCommandRoot() ?? project.root, layout: .page)
		logPage = page
		page.onOpenWorkingCopyDiff = { [weak self] change, root, text in
			self?.editor.openDiff(for: change, root: root, text: text)
		}

		// Named for what it is showing: two log tabs both called "Log" would be
		// the tab strip saying nothing, and a log scoped to a branch is a
		// different question from the one about where you are standing.
		group.openPage(
			page,
			title: ref.map { "Log · \($0)" } ?? "Log",
			identifier: "log",
			symbol: "clock.arrow.circlepath"
		)
		// **It does not take the window.** It used to, on the argument that a
		// graph and a diff want the room — which is true and is not this page's
		// call to make. The panel's height and the tree's width are somebody's
		// own arrangement, chosen for what they were doing a minute ago, and
		// rearranging it to show them a log is the mode `giveTheEditorTheWindow`
		// already refuses to undo on the way out. The commit page stopped doing
		// this for the same reason; the log had been left behind.
		//
		// The two gestures that give it the room are the ones that always did:
		// double-click the tab, or the View menu.
		//
		// Opened to be read, and read with the arrows: a page whose keyboard is
		// still in whatever opened it needs a click before it can be walked.
		DispatchQueue.main.async { [weak page] in page?.focusList() }
		page.setRef(ref)
	}

	/// The log page, while one is open, for the driver to read.
	private(set) weak var logPage: HistoryPane?

	/// The commit page, likewise.
	private weak var commitPage: ChangesPane?

	/// The message being composed, wherever it is being composed.
	///
	/// The page first: somebody who promoted the message with `…` is typing in
	/// the page, and the sidebar's field holds what they left behind. Nil when
	/// nothing has been typed in either.
	var composedMessage: ProjectSession.ComposedMessage? {
		commitPage?.composedMessage ?? changesPane?.composedMessage
	}

	/// The pages that are open, with what each is showing.
	///
	/// Read off the editor's own tabs rather than the weak handles here: a page
	/// this controller never opened — a pull request review, the settings page —
	/// is still a page the window had.
	/// What the trees are folded into now, for the session.
	///
	/// Asked of the panes that exist: a tool nobody has opened in this sitting
	/// has no pane, and what was read out of the session for it is handed back
	/// unchanged rather than being replaced with nothing. Otherwise opening a
	/// project and never touching the git tool would erase the folds in it.
	func foldsToRemember(carrying stored: [String: ProjectSession.TreeFolds])
		-> [String: ProjectSession.TreeFolds] {
		var folds = stored
		if let branchesPane { folds["refs"] = branchesPane.foldsWorthKeeping }
		if let changesPane {
			let sides = changesPane.folds
			folds["changes.unstaged"] = sides["changes.unstaged"]
			folds["changes.staged"] = sides["changes.staged"]
		}
		folds["tree"] = navigator.folds
		return folds.compactMapValues { $0.isEmpty ? nil : $0 }
	}

	/// Which tool is in front, by the name the session keeps it under.
	var toolToRemember: String { currentSidebarTool.stored }

	func openPagesToRemember() -> [ProjectSession.OpenPage] {
		editor.openPageIdentifiers().map { identifier in
			switch identifier {
			case "log":
				return ProjectSession.OpenPage(
					identifier: identifier, showing: logPage?.scopeToRemember() ?? [:]
				)
			case "stash":
				return ProjectSession.OpenPage(
					identifier: identifier, showing: stashPage?.stashToRemember() ?? [:]
				)
			default:
				return ProjectSession.OpenPage(identifier: identifier)
			}
		}
	}

	/// Reopens the pages a session remembered, once the repository is readable.
	///
	/// **After the git read, and not before.** Every opener below refuses while
	/// `project.git` is nil, which is the state a window is in for the second or
	/// two after it opens — reopening there would drop the lot in silence. The
	/// openers are the ones a click uses and each reuses an existing tab, so a
	/// restore that races somebody opening the same page cannot make two.
	func reopen(pages: [ProjectSession.OpenPage]) {
		guard !pages.isEmpty else { return }
		Task { @MainActor [weak self] in
			await self?.project()?.loadGit()
			guard let self, let project = self.project(), project.git != nil else { return }
			for page in pages { self.reopen(page: page) }
		}
	}

	/// **Nothing here asked for anything.** These pages are coming back with a
	/// project, which happens by itself: a window following its terminal
	/// switches project when the shell walks into another one, and switching a
	/// tmux window is how a shell walks. Reported as the maximised terminal
	/// being lost on a tab switch — and only for a project that had a log or a
	/// commit page open, which is what pointed at these four calls.
	/// Restores the pages a run names, so the path can be driven at all.
	///
	/// **A driven run never reads a real session** — `SessionStore.read`
	/// refuses one, which is half of item 0522 — so the restore this is about
	/// cannot happen by itself in a run. The pages come from the run instead
	/// of from somebody's project, and everything after that is the app's own
	/// code.
	func restorePagesForTesting(_ identifiers: [String]) -> String {
		reopen(pages: identifiers.map { ProjectSession.OpenPage(identifier: $0) })
		return "restoring: " + identifiers.joined(separator: ", ")
	}

	private func reopen(page: ProjectSession.OpenPage) {
		switch page.identifier {
		case "commit":
			showCommitPage(carrying: nil, asked: false)
		case "log":
			showLogPage(scopedTo: page.showing["ref"], asked: false)
			if let path = page.showing["path"] {
				logPage?.offerScope(path: path)
				logPage?.setScope(path: path)
			}
		case "stash":
			// **By commit, not by index.** `stash@{0}` is a different commit
			// after one `git stash push`, so an index would reopen the page on
			// somebody else's work. The commit may also be gone — popped from
			// another window — and a page about a stash that no longer exists
			// has nothing to show, so it stays closed.
			guard let commit = page.showing["commit"],
			      let root = gitCommandRoot() ?? project()?.root else { return }
			Task { @MainActor [weak self] in
				let entries = await GitStash.list(in: root)
				guard let entry = entries.first(where: { $0.commit == commit }) else { return }
				self?.showStashPage(entry, asked: false)
			}
		case "estate":
			showEstatePage(asked: false)
		case "launch":
			// **Written into every session file and read by nothing.** The
			// `sessions` capability already requires "the pages whose identity
			// is their identifier alone" to come back, and these two were
			// captured, stored and dropped on the way in — a requirement that
			// existed and was unmet rather than a new one.
			openLaunchConfigurationsPage()
		case "settings":
			openSettingsPage()
		default:
			// A page this version has no opener for — one a later version wrote
			// down, or one whose owner is elsewhere in the app. Left closed
			// rather than guessed at.
			break
		}
	}

	/// Opens the commit view as a page in the editor area.
	///
	/// **The same pane at the size it needs**, exactly as the log is: the tree,
	/// folder staging and the discard question are the same questions at either
	/// size, so there is one class and two arrangements rather than two classes
	/// that drift.
	///
	/// - Parameter carrying: what has been typed into the sidebar's summary, so
	///   pressing `…` is promoting a message rather than starting a second one.
	/// - Parameter asked: whether somebody asked for this page. Only then does
	///   it give the editor the window back: while the terminal panel has the
	///   whole window the editor is *hidden*, so a page opened into it could
	///   not be seen — and a page being restored with a project asked for
	///   nothing. See `reopen(page:)`, which is the other caller.
	func showCommitPage(carrying summary: String?, asked: Bool = true) {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return }

		let page: ChangesPane
		let wanted = gitCommandRoot() ?? project.root
		if let existing = group.page(identifier: "commit") as? ChangesPane,
		   existing.repositoryRoot.standardizedFileURL == wanted.standardizedFileURL {
			// **Its root is checked, which it was not.** A page is reused by
			// identifier, so a commit page left over from another project was
			// handed this project's remembered message and this project's
			// draft — the report's fault by a second door.
			page = existing
		} else {
			page = ChangesPane(root: gitCommandRoot() ?? project.root, layout: .page)
			page.onWorkingCopyChanged = { [weak self] in
				self?.navigator.refreshGitStatus()
				self?.changesPane?.refresh()
			}
			// The verbs over the page's own diff. Without these the menu is
			// still offered — `DiffView` builds it for any diff that is not
			// read-only — and pressing it does nothing at all.
			page.onApplyDiffSelection = { [weak self] change, diff, lines, owner in
				self?.applyDiffSelection(
					change: change, diff: diff, lines: lines, in: owner, from: .page
				)
			}
			page.onDiscardDiffSelection = { [weak self] change, diff, lines, owner in
				self?.discardDiffSelection(
					change: change, diff: diff, lines: lines, in: owner, from: .page
				)
			}
			// **Offered only where git can do it**, as the editor's diff is:
			// `stash push --staged` arrived in 2.35, and on an older one the
			// item is absent rather than failing when pressed.
			// Held rather than captured weakly: the check is one command and the
			// page is the caller's. Named for what it is now that `asked` means
			// "somebody asked for this page" in this function's signature.
			let thePage = page
			Task { @MainActor [weak self] in
				guard await GitStash.canPushStaged(in: thePage.repositoryRoot) else { return }
				thePage.onStashDiffSelection = { [weak self] change, diff, lines, owner in
					self?.stashDiffSelection(
						change: change, diff: diff, lines: lines, in: owner, from: .page
					)
				}
			}
		}
		commitPage = page
		// **No longer takes the window.** It did because the page was unreadable
		// small: a fixed 224 points of message area left four lines of diff on a
		// short page. The message is two rows now and under the diff rather than
		// across the width, so the page is worth opening at whatever size it is
		// given — and taking somebody's tree and terminal away to show them a
		// commit is a thing to do only when the page cannot be read otherwise.
		group.openPage(page, title: "Commit", identifier: "commit", symbol: "checkmark.circle")
		DispatchQueue.main.async { [weak page] in page?.focusList() }

		if let summary, !summary.isEmpty { page.carrySummaryForTesting(summary) }
		wireDrafts(of: page)
		// A page reopened by a session is where the message was being written
		// if `…` had been pressed, so it is offered here too — into empty
		// fields only, so promoting a summary from the sidebar still wins.
		if let message = rememberedMessage() { page.restore(message: message) }
		page.applyHeldDraft()
		page.refresh()
	}

	/// Asks whichever panes exist to take what the inbox holds for them.
	///
	/// What a late answer does: the pane that asked applies it if it is still
	/// the pane for that project, and any other pane declines.
	func applyHeldDraftsForTesting() {
		changesPane?.applyHeldDraft()
		commitPage?.applyHeldDraft()
	}

	/// Gives a pane the inbox, both ways.
	///
	/// One function for both construction sites, because a pane that can hand a
	/// draft in and not ask for one is a pane that loses drafts silently —
	/// which is the fault this is fixing, in a new place.
	private func wireDrafts(of pane: ChangesPane) {
		pane.onDraft = { [weak self] root, draft in self?.holdDraft(root, draft) }
		pane.heldDraft = { [weak self] root in self?.heldDraft(root) }
		pane.onDraftTaken = { [weak self] root in self?.discardDraft(root) }
	}

	/// One stash, as a page — see `StashPage`.
	///
	/// **One page, re-pointed.** Reviewing a second stash re-uses the first
	/// page rather than opening a tab per stash: `openPage` already keys by
	/// identifier, and a row of near-identical tabs called `Stash` would be a
	/// tab strip nobody can read.
	func showStashPage(_ entry: GitStash.Entry, asked: Bool = true) {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else {
			return
		}
		let root = gitCommandRoot() ?? project.root
		let page: StashPage
		if let existing = group.page(identifier: "stash") as? StashPage {
			page = existing
			page.show(entry)
		} else {
			page = StashPage(root: root, entry: entry)
			// **Through the pane, because the questions live there.** Applying
			// asks whether the entry should stay, branching asks for a name,
			// and dropping says the work is on no branch — three dialogs this
			// page would otherwise own a second copy of.
			page.onApply = { [weak self] entry in self?.branchesPane?.apply(stash: entry) }
			page.onBranch = { [weak self] entry in self?.branchesPane?.branch(fromStash: entry) }
			page.onDrop = { [weak self] entry in self?.branchesPane?.drop(stashes: [entry]) }
		}
		stashPage = page
		group.openPage(page, title: "Stash", identifier: "stash", symbol: "tray.full")
	}

	/// Every submodule in the estate, as a page — see `EstateOverviewPage`.
	func showEstatePage(asked: Bool = true) {
		if asked { leaveTerminalFullScreen() }
		guard let project = project(), project.git != nil, let group = editor.activeGroup else { return }

		let page = (group.page(identifier: "estate") as? EstateOverviewPage)
			?? EstateOverviewPage(root: gitCommandRoot() ?? project.root)
		page.onOpenPullRequest = { [weak self] number, root in
			_ = self?.pullRequests.openFromEstate(number: number, in: root)
		}
		page.onOpenSubmodule = { [weak self] path in
			// The submodule's own changes, in the page that already draws them —
			// landing on that repository's row, not merely opening a page that
			// looks the same as it did before the row was pressed.
			guard let self else { return }
			showCommitPage(carrying: nil)
			// After the page has read the working copy, or the row it is being
			// asked to select does not exist yet.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
				self?.commitPage?.select(path: path)
			}
		}
		estatePage = page
		group.openPage(
			page, title: "Submodules", identifier: "estate", symbol: "square.stack.3d.up"
		)
		giveTheEditorTheWindow()
	}

	/// The estate page, while one is open, for the driver to read.
	private(set) weak var estatePage: EstateOverviewPage?
	private(set) weak var stashPage: StashPage?

	/// What the estate page says, row by row.
	func estateForTesting(_ steps: String, waiting: Int = 8) {
		if estatePage == nil { showEstatePage() }
		guard let page = estatePage else {
			print("ESTATE: no page")
			return
		}
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			if step.hasPrefix("settle") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.estateForTesting(rest, waiting: waiting)
				}
				return
			}
			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "rows":   print("ESTATE rows:\n\(page.rowsForTesting())")
			case "filter": page.filterForTesting(argument)
			case "take":
				// `svc-1:theirs`, or `svc-1:<commit>` for a third one.
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				if parts.count == 2 { page.resolveForTesting(path: parts[0], to: parts[1]) }
			default:       print("ESTATE: unknown step \(step)")
			}
		}
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
			case "rows":   print("COMMIT-PAGE rows:\n\(page.rowsForTesting())")
			case "diff":   print("COMMIT-PAGE diff: \(page.diffForTesting())")
			case "verbs":  print("COMMIT-PAGE verbs: \(page.diffVerbsForTesting())")
			case "stage-lines":
				let count = Int(argument) ?? 1
				print("COMMIT-PAGE stage-lines: \(page.stageLinesForTesting(count))")
			case "stage":  page.stageForTesting(paths: [argument], staged: false)
			case "who":    print("COMMIT-PAGE \(page.keyboardReportForTesting())")
			case "keys":   print("COMMIT-PAGE keys: " + page.keysForTesting(argument))
			case "select": page.selectChangeForTesting(argument)
			// Which way a changed picture is being looked at: 0 side by side,
			// 1 the slider, 2 the changed regions.
			case "picture-mode":
				print("COMMIT-PAGE picture: " + page.choosePictureModeForTesting(Int(argument) ?? 0))
			case "type":   page.carrySummaryForTesting(argument)
			// The draft, in the three moves a person has: press it, have an
			// answer arrive, and read what the button became.
			case "draft":  page.pressDraftForTesting()
			case "deliver":
				// `deliver:summary|description`, standing in for `claude`.
				let halves = argument.split(separator: "|", maxSplits: 1).map(String.init)
				page.deliverDraftForTesting(
					summary: halves.first ?? "feat: a drafted summary",
					description: halves.count > 1 ? halves[1] : "The why, drafted."
				)
			case "draft-report":
				print("COMMIT-PAGE draft: " + page.draftReportForTesting)
			case "chevron": page.toggleDescriptionForTesting()
			case "return":  page.pressReturnInSummaryForTesting()
			// The commit message history: `history` prints the menu's entries,
			// `use-history:<n>` fills the fields from one — both async, so
			// settle before reading.
			case "history":     page.messageHistoryForTesting()
			// Commits what is staged with this subject, through the button's
			// own door: whether the project's hooks ran is a claim that wants a
			// trace rather than an assertion.
			case "commit-now": page.commitForTesting(subject: argument)
			case "use-history": page.useHistoryEntryForTesting(Int(argument) ?? 0)
			// A script that says so ends the run. Without it the process is
			// killed by whatever is waiting on it, and a killed process never
			// flushes: the report was written and never reached the terminal.
			case "exit":   fflush(stdout); exit(0)
			default:       print("COMMIT-PAGE: unknown step \(step)")
			}
			fflush(stdout)
		}
	}

	/// What the pull request list says, row by row — see `PullRequestReview`.
	func pullRequestsForTesting(_ steps: String) { pullRequests.driveForTesting(steps) }

	/// What the log page holds, and what its menu over a commit offers.
	func logPageForTesting(_ steps: String, waiting: Int = 8) {
		if logPage == nil { showLogPage(scopedTo: nil) }
		// No page yet is the same waiting game as an empty one: the page needs
		// the project's git, which loads after the window, and a driver asking
		// at 2.5 seconds can be earlier than that. Reporting "no page" at the
		// first ask ended runs that were one loading step from working — and
		// ended them silently, because a run that then hangs is killed, and a
		// kill never flushes what `print` buffered. Hence the flushes on every
		// ending here, not only on `exit`.
		guard let page = logPage, page.hasRowsForTesting else {
			guard waiting > 0 else {
				print(logPage == nil ? "LOG-PAGE: no page" : "LOG-PAGE: the log is still empty")
				fflush(stdout)
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.logPageForTesting(steps, waiting: waiting - 1)
			}
			return
		}
		// The steps are the pane's own — see `HistoryPane.driveForTesting`,
		// which is the shape `pullRequestsForTesting` already has: this
		// controller's part is only to have the page and to wait for it.
		page.driveForTesting(steps)
	}

	/// Where the lines were selected, so what happens next is shown back in the
	/// same place. A tab wants the diff re-opened as a tab; the commit page
	/// keeps its diff and only wants re-reading.
	enum DiffOrigin {
		case tab
		case page
	}

	/// Moves the selected lines across the index, in whichever direction the
	/// diff's side implies.
	///
	/// - Parameter root: the repository the diff was read in, which is the
	///   submodule for a file inside one. Defaults to the project's own.
	func applyDiffSelection(
		change: GitChange, diff: String, lines: Set<Int>,
		in root: URL? = nil, from origin: DiffOrigin = .tab
	) {
		guard let project = project(), !lines.isEmpty else { return }
		let root = root ?? project.root
		Task { @MainActor in
			let result = change.isStaged
				? await GitWorkingCopy.unstage(lines: lines, ofDiff: diff, in: root)
				: await GitWorkingCopy.stage(lines: lines, ofDiff: diff, in: root)
			finishDiffOperation(result, change: change, from: origin)
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
	func stashDiffSelection(
		change: GitChange, diff: String, lines: Set<Int>,
		in owner: URL? = nil, from origin: DiffOrigin = .tab
	) {
		guard let project = project(), !lines.isEmpty else { return }
		let root = owner ?? project.root

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
				finishDiffOperation(staged, change: change, from: origin)
				return
			}

			let name = "\(lines.count) line\(lines.count == 1 ? "" : "s") of \(change.name)"
			let put = await GitStash.pushStaged(in: root, message: name)
			finishDiffOperation(put, change: change, from: origin)
			if put.exitCode == 0 {
				Toast.post("Stashed \(name)", kind: .information)
			}
		}
	}

	func discardDiffSelection(
		change: GitChange, diff: String, lines: Set<Int>,
		in owner: URL? = nil, from origin: DiffOrigin = .tab
	) {
		guard let project = project(), !lines.isEmpty else { return }
		let root = owner ?? project.root

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
					in: root,
					input: Data(patch.utf8)
				)
				self.finishDiffOperation(result, change: change, from: origin)
			}
		}

		if let window = hostWindow() {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	private func finishDiffOperation(
		_ result: GitRepository.ProcessResult, change: GitChange, from origin: DiffOrigin = .tab
	) {
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
		//
		// **Back where it was selected.** From the page that is the page's own
		// diff, and opening a tab as well would answer a gesture made to avoid
		// tabs with one of them.
		switch origin {
		case .tab:  showDiff(for: change)
		case .page:
			commitPage?.refresh()
			commitPage?.rereadDiff()
		}
	}

	/// Opens the diff for a change as an editor tab.
	/// Where a file stands in its repository, for the compare verbs: the git
	/// root and the path git knows the file by. Nil outside the repository,
	/// where there is nothing to compare against.
	private func repositoryPlace(of url: URL) -> (root: URL, path: String)? {
		guard let project = project() else { return nil }
		let root = (project.gitRoot ?? project.root).standardizedFileURL
		let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
		let path = url.standardizedFileURL.path
		guard path.hasPrefix(prefix) else { return nil }
		return (root, String(path.dropFirst(prefix.count)))
	}

	/// Compare ▸ Against Last Commit: the file's diff against HEAD — staged
	/// and unstaged edits in one answer, the question the gutter's change
	/// marks answer — as a diff tab.
	func compareFileAgainstHead(_ url: URL) {
		guard let place = repositoryPlace(of: url) else { return }
		Task { @MainActor in
			let text = await GitWorkingCopy.diffAgainstHead(for: place.path, in: place.root)
			guard let text, !text.isEmpty else {
				Toast.post(
					"Nothing to compare",
					detail: "\(url.lastPathComponent) matches the last commit.",
					kind: .information
				)
				return
			}
			editor.openDiff(
				for: GitChange(path: place.path, kind: .modified, isStaged: false),
				root: place.root, text: text
			)
		}
	}

	/// Compare ▸ History…: the log page the "This File" segment reaches,
	/// arrived at from the file's own row.
	func showFileHistory(of url: URL) {
		guard let place = repositoryPlace(of: url) else { return }
		showLogPage(scopedTo: nil)
		logPage?.offerScope(path: place.path)
		logPage?.setScope(path: place.path)
	}

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

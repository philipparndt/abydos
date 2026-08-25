import AppKit
import AbydosKit

/// Where an answer to a question about the code is shown, and where it moves to.
///
/// Find Usages, ⇧⌘F and Go to Symbol are three questions with one presentation
/// problem between them: the answer is a list, the list has four possible homes
/// — the panel, beside the panel, under the project tree, or a window of its own
/// — and the same view has to be carried between them so that the rows, the
/// ticks, the scroll position and the selection survive the move.
///
/// It was seven properties and four hundred lines on `MainWindowController`,
/// where the placement of a search result sat in the same scope as the debugger's
/// breakpoints and the run configuration list, reachable from all of it.
///
/// It holds no reference to the window. What it needs from one it is handed:
/// which window to parent a results window to, what the project's scope root is,
/// and the two sidebar operations, which belong to the sidebar and are lent here
/// until there is a `SidebarController` to own them.
@MainActor
final class ResultsPresenter {
	private let editor: EditorAreaController
	private let panel: BottomPanel

	/// The window a results window is parented to, when there is one.
	var hostWindow: () -> NSWindow? = { nil }
	/// What paths in a list are shown relative to.
	var scopeRoot: () -> URL? = { nil }
	/// A list docked in the panel is a list nobody can see if the panel is shut.
	var showPanel: () -> Void = {}
	/// The lower half of the sidebar, which is the sidebar's to split and not
	/// this object's to know about.
	var dockInSidebar: (any ResultsPane, Bool) -> Void = { _, _ in }
	var undockFromSidebar: (any ResultsPane) -> Void = { _ in }
	/// The sidebar's lower half, so a driven run can prove the list is in it.
	var sidebarDockHost: () -> NSView? = { nil }
	/// The same question asked again, at the place it was asked about. Driven
	/// runs use it to prove the ticks come back and that a window is remembered.
	var askUsagesAgain: (URL, Int, Int) -> Void = { _, _, _ in }
	/// What the symbol palette lists, and what it says when that is nothing.
	var symbolsMatching: (String, SymbolPalette.Scope) async -> [LSPSymbol] = { _, _ in [] }
	var reasonForNoSymbols: (String, SymbolPalette.Scope) -> String = { _, _ in "" }

	init(editor: EditorAreaController, panel: BottomPanel) {
		self.editor = editor
		self.panel = panel
	}

	/// What was last asked about, so the window's own Find Usages can record it
	/// without this object having to run the query.
	func noteUsagesRequest(url: URL, line: Int, character: Int) {
		lastUsagesRequest = (url, line, character)
	}

	/// Everything in this file, or everything in the project.
	func goToSymbolInFile() { symbolPalette.show(scope: .document, over: hostWindow()) }
	func goToSymbolInProject() { symbolPalette.show(scope: .workspace, over: hostWindow()) }

	/// Go to a symbol by name.
	private lazy var symbolPalette: SymbolPalette = {
		let palette = SymbolPalette()
		palette.provider = { [weak self] query, scope in
			await self?.symbolsMatching(query, scope) ?? []
		}
		palette.emptyReason = { [weak self] query, scope in
			self?.reasonForNoSymbols(query, scope) ?? ""
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

	/// ⇧⌘F, wherever the last answer to it was.
	///
	/// The placement is honoured before the query is typed, because the field
	/// has to be in a window to take the keyboard and the move is what puts it
	/// in one.
	func showProjectSearch(query: String?) {
		guard let pane = panel.makeSearchPaneIfNeeded() else { return }
		pane.onPlace = { [weak self] home in self?.placeSearch(at: home) }
		placeSearch(at: searchPlacement, focusList: false)
		if let query { pane.setQuery(query) }
		// The field rather than the list: asking for search is asking a question,
		// and the question is typed. A *move* puts the keyboard in the rows —
		// that pane already has an answer in it.
		pane.focusField()
	}

	/// Works the usages list from the command line, the way `--search-steps`
	/// works the search one.
	///
	/// `settle` is handled here for the same reason it is there: the list is
	/// filled from an answer that arrives on the main queue, and a script that
	/// pressed on regardless would be asking about rows that had not been built.
	func usagesStepsForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		guard panel.existingUsagesPane != nil
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
					askUsagesAgain(last.url, last.line, last.character)
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
		let scope: SymbolPalette.Scope = project ? .workspace : .document
		symbolPalette.show(scope: scope, over: hostWindow())
		symbolPalette.setQueryForTesting(query)

		// Twice: at 1 s the server is usually still starting, which is the state
		// the dialog used to sit in silently and for ever, and at 20 s it has
		// answered — without the palette having been reopened, which is the
		// whole of the fix.
		let say: (Double) -> Void = { [weak self] at in
			guard let self else { return }
			let results = self.symbolPalette.resultsForTesting
			print("SYMBOLS +\(at)s: \(results.count) for “\(query)” "
				+ "reason=“\(self.reasonForNoSymbols(query, scope))”")
			for result in results.prefix(4) { print("SYMBOL: \(result)") }
			fflush(stdout)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { say(1.0) }

		DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) { [weak self] in
			guard let self else { return }
			say(20.0)
			// The keys the list is driven by, including the four that were
			// missing: ⇟ ⇞ and the two ends.
			for key in ["down", "pageDown", "pageDown", "end", "pageUp", "start"] {
				print("SYMBOLKEY \(key): \(self.symbolPalette.pressForTesting(key))")
			}
			fflush(stdout)

			self.symbolPalette.openFirstForTesting()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				print("SYMBOLS: opened \(self.editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing")")
				fflush(stdout)
			}
		}
	}

	/// Whether the usages list is showing in a window rather than in the panel.
	var usagesInWindowForTesting: Bool { usagesWindow != nil }

	/// What was last asked about, so a script can ask again — which is how the
	/// two claims about asking twice get checked: the ticks come back, and the
	/// choice of a window is remembered.
	private var lastUsagesRequest: (url: URL, line: Int, character: Int)?

	/// Puts one symbol's usages wherever the last answer to that question was.
	func showUsages(_ locations: [LSPLocation], of symbol: String, at origin: String) {
		usagesPane.show(
			locations: locations, of: symbol, at: origin, root: scopeRoot()
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
				self?.panel.releaseUsages()
			}, dock: { [weak self] beside, focus in
				guard let self else { return }
				self.showPanel()
				self.panel.dockUsages(
					self.usagesPane, title: self.usagesPane.paneTitle,
					beside: beside, focusList: focus
				)
			})
	}

	/// `focusList` is false for the ⇧⌘F that *makes* the pane: the keyboard goes
	/// to the field there, and a move that grabbed it back would put the caret
	/// in the rows of a search nobody has typed yet.
	private func placeSearch(at home: ResultPlacement, focusList: Bool = true) {
		guard let pane = panel.existingSearchPane else { return }
		searchPlacement = home
		place(pane, at: home, window: &searchWindow, focusList: focusList, release: { [weak self] in
			self?.panel.releaseSearch()
		}, dock: { [weak self] beside, focus in
			guard let self else { return }
			self.showPanel()
			self.panel.dockSearch(pane, beside: beside, focusList: focus)
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
		case .sidebar: dockInSidebar(pane, focusList)
		case .window: expand(pane, into: &slot, focusList: focusList)
		}
	}

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
		if searchPlacement == .sidebar, panel.existingSearchPane !== pane {
			placeSearch(at: .panel, focusList: false)
		}
	}

	/// The same view, in a window big enough to read two hundred rows in.
	private func expand(
		_ pane: any ResultsPane, into slot: inout ResultsWindow?, focusList: Bool
	) {
		let window = slot ?? makeResultsWindow(for: pane)
		slot = window
		window.title = pane.paneTitle
		window.contentView = pane

		if let parent = hostWindow() {
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
	func openFromChecklist(
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
			if hostWindow()?.isKeyWindow == false { hostWindow()?.makeKey() }
		}
	}

	/// The profiler knows a name, not a place; the symbol search turns one into
	/// the other.
	func showSymbols(query: String) {
		symbolPalette.show(scope: .workspace, query: query, over: hostWindow())
	}

	/// `--find-usages`: asks, then says where the answer went and reads it back.
	func exerciseFindUsagesForTesting(line: Int, character: Int, in url: URL) {
		askUsagesAgain(url, line, character)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
			guard let self else { return }
			print("USAGES: where=\(self.usagesPlacement.rawValue) "
				+ "window=\(self.usagesInWindowForTesting) "
				+ "panel=\(self.panel.existingUsagesPane != nil) "
				+ "sidebar=\(self.sidebarDockHost()?.subviews.first === self.usagesPane) "
				+ "columns=\(self.panel.columnCountForTesting)")
			fflush(stdout)
			self.usagesPane.stepForTesting("heading")
			self.usagesPane.stepForTesting("who")
		}
	}
}

import AppKit
import AbydosKit

/// Driving the panel from a script: which tab is in front, what the strip is
/// showing, what the terminal in it last printed, and every gesture that
/// splits, tears off or renames one.
extension BottomPanel {
	/// Chooses one of the hidden tabs, the way its menu entry would.
	func selectHiddenTabForTesting(_ position: Int) -> String {
		tabStripForTesting?.selectHiddenForTesting(position) ?? "no strip"
	}

	/// What the + and the chevron beside it answer to, for the harness.
	var addControlsForTesting: String {
		tabStripForTesting?.addControlsForTesting ?? "no strip"
	}

	/// Every tab, the one in front marked, and whether it is still a report
	/// rather than a shell — for the harness, which cannot photograph a hidden
	/// panel and is the only witness to 0444's part 4 there is.
	var tabsForTesting: String {
		guard !sessions.isEmpty else { return "(no tabs)" }
		return sessions.enumerated().map { index, session in
			let active = index == activeIndex
			let preparing = active && activeTerminalShowsOutputOnly
			return (active ? "*" : "") + session.displayTitle + (preparing ? " (preparing)" : "")
		}.joined(separator: " | ")
	}

	/// Where the keyboard is in the debug pane's variables tree.
	func variablesKeyboardReportForTesting() -> String {
		activeDebugPane?.keyboardReportForTesting ?? "no debug pane"
	}

	/// Clicks the variables tree, as somebody would.
	func clickVariablesForTesting() -> String {
		activeDebugPane?.clickVariablesForTesting() ?? "no debug pane"
	}

	/// Walks the debug pane's variables tree with the arrow keys.
	func walkVariablesForTesting(_ keys: [String]) -> String {
		activeDebugPane?.walkVariablesForTesting(keys) ?? "no debug pane"
	}

	/// Whether the board has any cards yet.
	func backlogHasCardsForTesting() -> Bool {
		showBacklog()?.hasCardsForTesting ?? false
	}

	/// What colour the pane's tree draws its selected row in.
	func variablesSelectionColourForTesting() -> String {
		activeDebugPane?.selectionColourForTesting ?? "no debug pane"
	}

	/// Walks the pane's tree and reads it once the children have arrived.
	func walkVariablesThenSettleForTesting(_ keys: [String], then say: @escaping (String) -> Void) {
		guard let pane = activeDebugPane else { return say("no debug pane") }
		pane.walkVariablesThenSettleForTesting(keys, then: say)
	}

	/// Which tabs are marked as drawn by the other engine, across every strip.
	func engineMarksForTesting() -> String {
		let strips = columnViews.map { $0.strip.engineMarksForTesting }
		return strips.joined(separator: "\n")
			+ "\nfallback said: \(EngineFallback.saidForTesting)"
	}

	/// The last lines the pane in front has, so that what a build wrote into it
	/// can be read from outside.
	func activeTerminalTailForTesting(lines: Int) -> String {
		terminalTextForTesting
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
			.suffix(lines)
			.joined(separator: " ⏎ ")
	}

	/// Clicks a tab, for the capture harness.
	func selectTabForTesting(_ index: Int) {
		activate(sessions[index], focus: false)
	}

	/// Selects a tab *and* takes the keyboard, which is what a click does.
	///
	/// The commands that only work while the terminal has the keyboard cannot
	/// be exercised through `selectTabForTesting` — it deliberately leaves the
	/// focus where it was, so a harness using it measures the gate rather than
	/// the thing behind it.
	func selectAndFocusTabForTesting(_ index: Int) {
		guard sessions.indices.contains(index) else { return }
		activate(sessions[index], focus: true)
	}

	/// Puts the first tab beside whatever is showing, as the menu does.
	func splitFirstBesideForTesting() {
		handleDrop(TerminalTabDrag.Payload(panelID: panelID, column: 0, index: 0), zone: .left)
	}

	/// The case somebody actually reaches for: the tab in front, told to sit
	/// beside. Exercises the menu's own path.
	func splitActiveBesideForTesting() {
		guard let session = activeSession,
		      let index = sessions(in: session.column).firstIndex(where: { $0 === session })
		else { return }
		tabStripForTesting?.onSplit?(index, .right)
	}

	/// Shows where a dropped tab would land, as the drag does. For the harness.
	func previewDropForTesting() {
		showDropTargets()
		columnViews.first?.showPreview(.right)
	}

	/// Puts the last terminal beside the first, as dragging its tab to the edge
	/// does. For the capture harness.
	func splitForTesting() {
		guard sessions.count >= 2 else { return }
		// The one that is not on screen, which is the case dragging a tab to the
		// edge is for.
		handleDrop(
			TerminalTabDrag.Payload(panelID: panelID, column: 0, index: sessions.count - 2),
			zone: .right
		)
	}

	/// Takes the terminal in front out into a window, as dragging its tab
	/// outside does. For the capture harness.
	func tearOffForTesting(at point: NSPoint) {
		guard let session = activeSession else { return }
		tearOff(session, at: point)
	}

	/// Renames whichever tab is in front, for the capture harness.
	func renameActiveForTesting(to name: String) {
		guard let activeIndex else { return }
		rename(index: activeIndex, to: name)
	}

	/// Opens the in-place editor and leaves it open, so a capture shows it.
	func beginRenameActiveForTesting() {
		guard let session = activeSession,
		      let index = sessions(in: session.column).firstIndex(where: { $0 === session })
		else { return }
		tabStripForTesting?.beginRenaming(index)
	}

	/// The terminals that are open, to be opened again next time.
	///
	/// Only plain terminals: a debugger, a profiler or a review is attached to
	/// something that is not running any more, and reopening one would be
	/// reopening a window onto nothing.
	///
	/// And only ones with a shell in them. A pane that is a *report* — a launch
	/// log, a pod's output, an image being built — is a terminal by construction
	/// and has never run a process, so restoring it opens a shell in the
	/// project's directory called "Building rust-analyzer". That is the shape of
	/// the fault 0444 found by watching tabs accumulate to three, and 0459 would
	/// have added a second source of it: a build's pane is the one kind that
	/// never becomes a shell at all, so the tab somebody kept to read would come
	/// back every session as a prompt.
	func captureTerminals() -> [ProjectSession.OpenTerminal] {
		sessions.compactMap { session in
			guard case .terminal = session.kind, !session.hasExited else { return nil }
			guard session.terminal?.showsOutputOnly != true else { return nil }
			return ProjectSession.OpenTerminal(
				name: session.displayTitle,
				directory: session.directory?.path,
				isRenamed: session.isRenamed,
				// Which of them was showing. Four came back and the first was
				// in front, whichever had been.
				isInFront: session === activeSession
			)
		}
	}

	/// Opens the terminals a project had, with fresh shells in the same places.
	func restoreTerminals(_ terminals: [ProjectSession.OpenTerminal]) {
		// The session made for the entry that was in front, kept as it is made.
		//
		// **Not found by name afterwards, and not by index either.** Three
		// terminals are all called `Local` until somebody renames one, so a
		// name finds the first of them — driven, and it brought back the first
		// where the third had been. An index is the other trap: a terminal
		// that fails to start makes no session and shifts every one after it.
		// Holding the object as it is created is neither.
		var wasInFront: Session?
		for terminal in terminals {
			let directory = terminal.directory.map { URL(fileURLWithPath: $0) } ?? workingDirectory
			// Not focused: this happens while a project is opening, and the
			// keyboard belongs to whatever the person opened it for.
			guard let pane = newTerminal(rootedAt: directory, title: terminal.name, focus: false)
			else { continue }
			guard let session = sessions.last, session.terminal === pane else { continue }
			if terminal.isInFront { wasInFront = session }
			session.isRenamed = terminal.isRenamed
			// The one that attached to tmux keeps the name it was just given —
			// `tmux` — unless the stored name was one somebody typed. What it
			// was called last time was whatever the client happened to report.
			guard terminal.isRenamed || session !== mirroredTerminal else { continue }
			session.displayTitle = terminal.name
		}
		refreshTabs()

		// Not focused, for the reason the restore above is not: this runs while
		// a project is opening, and the keyboard belongs to whatever somebody
		// opened it for. Nothing to do where the entry that was in front made
		// no session — the panel then shows what it shows today.
		if let wasInFront { activate(wasInFront, focus: false) }
	}

	/// tmux's own id for the window being shown, when one is.
	///
	/// Worth remembering across a launch: reopening a project into a window
	/// nobody chose, when the one they were in is still sitting there, is the
	/// sort of thing that makes somebody hunt through a tab strip for the work
	/// they left ten seconds ago.
	var currentTmuxWindowID: String? {
		let active = tmuxWindows.first(where: \.isActive)?.windowID
		return (active?.isEmpty ?? true) ? nil : active
	}

	/// Goes back to the window a project was left in, if it is still there.
	///
	/// Quietly when it is not: the server may have been restarted or the window
	/// closed, and neither is something the person did wrong. tmux's own choice
	/// stands in that case, which is the same as what happened before any of
	/// this was remembered.
	func restoreTmuxWindow(_ windowID: String) {
		guard let session = mirroredSession ?? tmuxSession, !windowID.isEmpty else { return }
		Task { @MainActor in
			guard await TmuxMirror.select(windowID: windowID, inSession: session) else { return }
			self.refreshTmuxWindows()
		}
	}

	/// Whether any plain terminal is open.
	var hasTerminals: Bool {
		sessions.contains { if case .terminal = $0.kind { return true }; return false }
	}

	/// Closes every plain terminal, for a window that is changing project.
	func closeTerminals() {
		for index in sessions.indices.reversed() {
			guard case .terminal = sessions[index].kind else { continue }
			close(index: index, hidingWhenEmpty: false)
		}
	}

	/// Redraws the tab strip. Called from outside when something a tab shows —
	/// whether its program is still running — has changed without the panel
	/// being told.
	func refreshTabs() {
		onActiveTerminalChanged?()
		rebuildColumns()
	}

	// MARK: - Commands

	func focusActive() {
		guard let activeIndex, sessions.indices.contains(activeIndex) else { return }
		sessions[activeIndex].terminal?.focus()
	}

	func applySettings() {
		// The status bar follows the switches: off while these tabs show the
		// same windows, back the moment they do not. Through the same path the
		// poll uses, so a switch flicked while tmux is not listening is retried
		// rather than being the one thing that was meant to fix it.
		if let session = mirroredSession ?? tmuxSession {
			Task { await applyStatusBarWish(to: session) }
		}

		// "Tabs are tmux's windows" switched: start or stop watching the
		// session, and rebuild the strip so the change is visible now rather
		// than at the next launch.
		startMirroringTmuxIfWanted()
		if !mirrorsTmux, !tmuxWindows.isEmpty {
			tmuxWindows = []
			mirroredSession = nil
		}
		rebuildColumns()

		placeholder.font = Theme.current.uiFont(12)
		for view in columnViews { view.applyThemeChange() }
		for session in sessions {
			switch session.kind {
			case let .review(pane, _): pane.applySettings()
			case let .search(pane): pane.applySettings()
			case let .usages(pane): pane.applySettings()
			case let .backlog(pane): pane.applySettings()
			case let .debug(pane): pane.applySettings()
			case let .terminal(pane): pane.terminalView.applyThemeChange()
			case .profiler: break
			}
		}
	}
}

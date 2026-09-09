import AppKit
import AbydosKit

/// Driving the window from the command line.
///
/// These are the verbs whose subject really is the window: they read the split
/// it is arranged in, the project it has open, which pane has the keyboard.
/// Everything that only reached a sub-controller has already gone to it — this
/// is the residue, and it is here rather than on a driver object of its own
/// because a driver holding a reference back to the window would be the same
/// coupling with an extra hop.
///
/// A file of its own so that `MainWindowController.swift` is the window and not
/// the harness. The class's own state is `private` still; what these reach is
/// the collaborators and the handful of layout fields, which are internal.
extension MainWindowController {
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

	var sidebarForTesting: SidebarController { sidebar }

	var debugForTesting: DebugCoordinator { debug }

	var runForTesting: RunCoordinator { run }

	var serverActionsForTesting: ServerActions { serverActions }

	var codeLinksForTesting: CodeLinks { codeLinks }

	var titlebarForTesting: TitlebarController { titlebar }

	/// Which panes the window is giving its room to.
	///
	/// The one thing a screenshot of a maximised editor cannot settle: an editor
	/// filling the window looks the same whether the tree is hidden or merely
	/// dragged to nothing, and "the panel is down" and "the panel is up behind
	/// the editor" are the same picture.
	/// Double-clicks a tab, and says what the window looks like afterwards.
	func doubleClickTabForTesting(_ index: Int) -> String {
		let took = editor.doubleClickTabForTesting(index: index)
		return "\(took) — \(windowLayoutReportForTesting)"
	}

	var windowLayoutReportForTesting: String {
		let navigator = (navigatorContainer?.isHidden ?? true)
			|| (navigatorContainer?.frame.width ?? 0) < 2
			? "hidden" : "\(Int(navigatorContainer?.frame.width ?? 0))pt"
		return "navigator=\(navigator) "
			+ "panel=\(bottomPanel.isHidden ? "hidden" : "\(Int(bottomPanel.frame.height))pt") "
			+ "editorMaximized=\(isEditorMaximized) "
			+ "panelMaximized=\(isPanelMaximized)"
	}

	/// Shuts the panel, for `--close-panel`.
	func closePanelForTesting() {
		setPanelVisible(false)
	}

	/// What the corner is saying, for the harness.
	func toastReportForTesting() -> String { toasts.reportForTesting() }

	/// What the panel's pill counts, and what its list holds.
	func runningSessionsReportForTesting() -> String { bottomPanel.runningSessionsReportForTesting() }

	/// Clicks the pill, as a person would, and says what came up.
	func openRunningSessionsForTesting(filter: String? = nil) -> String {
		bottomPanel.openRunningSessionsForTesting(filter: filter)
	}

	/// Opens the list the way ⇧⌘A does and says what came up, plus where it
	/// sits against this window.
	func openRunningSessionsPaletteForTesting(filter: String? = nil) -> String {
		bottomPanel.openRunningSessionsPaletteForTesting(over: window, filter: filter)
	}

	/// Clicks a tmux window tab and says what the window did about it.
	///
	/// **Reported: switching tmux tabs takes the terminal out of full screen.**
	/// Two states go by that name and the report does not say which, so both
	/// are read either side of the click: the panel having the window to itself
	/// (`isPanelMaximized`, which this app's own code calls terminal full
	/// screen) and the window being in a macOS full-screen space. The project
	/// too, since following the shell is the one thing a tab switch is known to
	/// move, and the frame, which says whether anything resized at all.
	///
	/// The first of the two is reachable from here — `--panel-maximize` — and
	/// stayed put across a click, in another project, with following on. The
	/// second is not: macOS refuses `toggleFullScreen` to an app that is not
	/// the active one, and a driven run never activates. So a run reads that
	/// state and cannot yet create it.
	func clickTmuxTabAndReportForTesting(_ index: Int) -> String {
		func state(_ when: String) -> String {
			let full = window?.styleMask.contains(.fullScreen) == true
			let frame = window?.frame ?? .zero
			return String(
				format: "  %@: panelMaximized=%@ macFullScreen=%@ project=%@ frame=(%.0f×%.0f)",
				when,
				isPanelMaximized ? "yes" : "no",
				full ? "yes" : "no",
				project?.root.lastPathComponent ?? "none",
				frame.width, frame.height
			)
		}
		var said = ["TMUX TAB:", state("before")]
		said.append("  " + bottomPanel.clickTmuxTabForTesting(index))
		said.append(state("after"))
		return said.joined(separator: "\n")
	}

	/// The same reading a beat later, since following the shell is two hops
	/// through the run loop and a project switch is more.
	func tmuxTabSettledReportForTesting() -> String {
		let full = window?.styleMask.contains(.fullScreen) == true
		return String(
			format: "  settled: panelMaximized=%@ macFullScreen=%@ project=%@",
			isPanelMaximized ? "yes" : "no",
			full ? "yes" : "no",
			project?.root.lastPathComponent ?? "none"
		)
	}

	/// The identity a panel tab gave its shell, for a driven session to name.
	func terminalIdentityForTesting(_ index: Int) -> String? {
		bottomPanel.terminalIdentityForTesting(index)
	}

	/// Chooses the first row the list shows, as ⏎ in its filter does, and says
	/// which tab the panel then has in front — the claim that a row reaches a
	/// tab whatever tab was in front before.
	func chooseFirstRunningSessionForTesting() -> String {
		bottomPanel.chooseFirstRunningSessionForTesting() + " | " + panelTabsForTesting()
	}

	/// Keys in the open running-sessions list, and where they went.
	func pressInRunningSessionsForTesting(_ keys: String) -> String {
		bottomPanel.pressInRunningSessionsForTesting(keys)
	}

	/// Presses one of a question's answers by its words.
	func answerToastForTesting(_ title: String) -> Bool { toasts.answerForTesting(title) }

	/// Opens the sidebar to a width, for looking at a pane in a screenshot.
	func openSidebarForTesting(width: CGFloat) {
		navigatorWidth = width
		navigatorWidthConstraint.constant = width
		navigatorContainer.isHidden = false
		splitView.setPosition(width, ofDividerAt: 0)
		splitView.adjustSubviews()
		sidebar.updateSidebarSelection()
	}

	/// Uses the empty page's button when there is one, so the capture exercises
	/// the control rather than what it happens to call.
	func newScratchForTesting() {
		if !editor.clickScratchPlaceholderForTesting() { newScratchFile(nil) }
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
		// The pages and the message beside it: they are what a switch used to
		// take with it, so a report of a switch that did not name them could
		// not say whether they came back.
		let pages = sidebar.openPagesToRemember()
			.map { page in
				page.showing.isEmpty
					? page.identifier
					: page.identifier + "(" + page.showing.sorted { $0.key < $1.key }
						.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + ")"
			}
		let message = sidebar.composedMessage
		print("PANES \(phase): window=\(window) board=[\(board)]"
			+ " pages=[\(pages.joined(separator: " "))]"
			+ " message=[\(message?.summary ?? "")]")
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

	/// Puts the panel at a stated height, for a capture that has to look the
	/// same twice.
	///
	/// The split position is remembered per machine, so a screenshot taken
	/// where somebody had dragged the terminal to the top of the window shows
	/// the terminal and nothing else. Zero closes it, which is what a shot of
	/// the editor alone wants.
	/// Widens the window and says what the panel's height was either side.
	///
	/// **The whole claim in two numbers.** A width-only resize used to cost the
	/// terminal about a row per resize notification, and a window dragged wider
	/// posts them by the dozen — so the after-number was a floor rather than the
	/// height somebody had set. Reported rather than photographed because two
	/// screenshots of a panel are hard to measure and easy to argue with.
	func widenForTesting(by extra: Double) {
		guard let window else { return }
		func said(_ phase: String) -> String {
			"PANEL-HEIGHT \(phase): window=\(Int(window.frame.width))"
				+ " panel=\(Int(bottomPanel.frame.height))"
				+ " split=\(Int(verticalSplitView.bounds.height))"
		}
		print(said("before"))
		fflush(stdout)

		var frame = window.frame
		frame.size.width += CGFloat(extra)
		// Animated off, and in one step: this is the resize a drag performs
		// many times over, and the point is what one of them costs.
		window.setFrame(frame, display: true, animate: false)
		window.layoutIfNeeded()

		// A turn later, because the snap answers on the turn after the resize
		// it is told about — reading now would read the number before the code
		// under test had its say.
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			print(said("after"))
			fflush(stdout)
		}
	}
}

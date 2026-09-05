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
			// The divider's own point, as everywhere else: a harness that asks
			// for 300 and gets 299 makes every capture a point out.
			self.verticalSplitView.setPosition(
				total - CGFloat(height) - self.verticalSplitView.dividerThickness,
				ofDividerAt: 0
			)
			self.tellTerminalsTheySizeChanged()
		}
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
}

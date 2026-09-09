import AppKit
import AbydosKit

/// The flags a driven run applies once its window is up.
///
/// Every one of them is the same shape — a flag was given, so do the thing and
/// often print what happened — and they are in no order but the one they were
/// written in. Splitting them three ways is splitting a list, and the list is
/// what it is: `--help` is the index.
///
/// This third is the tools: language servers, the debugger, the git pages,
/// run configurations, and the size of the window they are shown in.
@MainActor
extension AppDelegate {
	func driveTheTools(_ options: LaunchOptions, in controller: MainWindowController?) {
		if options.drawReport { BacklogCardViewDrawReport.enable() }

		// The report goes on for every form of the verb, presses included: what
		// a press does is half the answer, and which layer saw it is the other.
		if let steps = options.mouseSteps {
			MouseReport.enable()
			if steps != "report" {
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					controller?.pressMouseForTesting(steps)
				}
			}
		}

		if options.cardReport {
			// After the walk that reads the folders, which happens off the main
			// thread.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("CARDS:\n\(controller?.panelForTesting.cardGeometryForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if options.lspRoot {
			// After the file is open and its language known, which is what the
			// root is worked out from. No server has to have started: the root
			// is read off the disk.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("LSPROOT: \(controller?.editorForTesting.serverRootReportForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let spec = options.definitionAt {
			let parts = spec.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				guard parts.count == 2 else { return }
				controller?.editorForTesting.exerciseGoToDefinitionForTesting(line: parts[0] - 1, character: parts[1])
			}
		}

		if let spec = options.answerAt {
			let parts = spec.split(separator: ":").compactMap { Int($0) }
			// No delay of its own: the whole point is to be asking while the
			// server is still starting, so that the first answer is timed rather
			// than waited out.
			if parts.count == 2 {
				controller?.measureFirstAnswerForTesting(
					line: parts[0] - 1, character: parts[1], deadline: options.answerDeadline)
			}
		}

		if let spec = options.usagesAt {
			let parts = spec.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				guard parts.count == 2 else { return }
				controller?.serverActionsForTesting.exerciseFindUsagesForTesting(line: parts[0] - 1, character: parts[1])
			}
			// After the list is there and has said what is in it: the report above
			// runs three seconds behind the request, and a script that pressed ↓
			// before then would be walking an empty table.
			if let steps = options.usagesSteps {
				DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12) + 4) {
					controller?.resultsForTesting.usagesStepsForTesting(steps)
				}
			}
		}

		if let spec = options.renameAt {
			let halves = spec.split(separator: "=", maxSplits: 1)
			let parts = halves.first.map { $0.split(separator: ":").compactMap { Int($0) } } ?? []
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				guard parts.count == 2, halves.count == 2 else { return }
				controller?.serverActionsForTesting.exerciseRenameForTesting(
					line: parts[0] - 1, character: parts[1], to: String(halves[1])
				)
			}
		}

		if let query = options.symbolQuery {
			// After the language server has had time to index.
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				controller?.resultsForTesting.exerciseSymbolPaletteForTesting(query, project: options.symbolProject)
			}
		}

		if options.showToast {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.notify(
					"Cannot run this Go command",
					detail: "No go.mod was found in this project or below it."
				)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.notify("Saved 3 files", kind: .information)
			}
		}

		if let path = options.projectPath {
			let cwd = URL(fileURLWithPath: path, isDirectory: true).path
			for spec in options.claudeRunning where spec.after > 0 {
				DispatchQueue.main.asyncAfter(deadline: .now() + spec.after) {
					var payload = [
						"event": "SessionStart", "session": spec.id, "status": spec.status, "cwd": cwd,
					]
					// In one of the panel's tabs, by the identity the tab gave its
					// shell — what the hook sends for a session outside tmux.
					if let tab = spec.tab, let identity = controller?.terminalIdentityForTesting(tab) {
						payload["terminal"] = identity
					}
						// The tool uses that spawn them, so the register counts them
					// the way it counts a real session's.
					defer {
						for _ in 0..<spec.subagents {
							RunningSessions.shared.note([
								"event": "PreToolUse", "session": spec.id, "status": "working",
								"cwd": cwd, "tool": ClaudeHook.subagentTool,
							])
						}
					}
					guard let moved = RunningSessions.shared.note(payload) else { return }
					if moved.sessionsChanged { controller?.claudeSessionsChanged(slug: moved.slug) }
					controller?.runningSessionsChanged()
				}
			}
		}

		if options.closePanel {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, options.screenshotDelay - 0.6)) {
				controller?.closePanelForTesting()
			}
		}

		if let at = options.debugInterruptAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("INTERRUPT: \(controller?.panelForTesting.pressDebugInterruptForTesting() ?? "no window")")
				fflush(stdout)
			}
		}

		if options.railReport {
			// After whatever else this run does and *before* the shutter, which
			// is what the first version got wrong: it read at two seconds against
			// a default delay of 1.5, so the run had already exited and the line
			// never printed.
			DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, options.screenshotDelay - 0.2)) {
				print("RAIL: \(controller?.sidebarForTesting.railReportForTesting() ?? "no window")")
			}
		}

		if options.debugConsole {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1, options.screenshotDelay - 1)) {
				controller?.panelForTesting.showDebugConsoleForTesting()
			}
		}

		if let path = options.subproject, let controller {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				guard let root = controller.project?.root,
				      let url = Subprojects.resolve(path, in: root)
				else { return }
				controller.openSubproject(at: url)
			}
		}

		if let command = options.closeTabs {
			let parts = command.split(separator: ":")
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.editorForTesting.closeTabsForTesting(
					String(parts.first ?? "close"), at: Int(parts.last ?? "0") ?? 0
				)
			}
		}

		if let name = options.launchConfiguration {
			controller?.runForTesting.selectConfigurationForTesting(named: name)
		}

		if options.launchProfile {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.profileSelectedForTesting()
			}
		}

		if options.launchRun || options.launchDebug || options.launchMenu || options.launchEditor {
			// After anything that chooses what to run, or play would press
			// before there is a selection to press it on.
			let delay = options.chooseMakeRun == nil ? 1.2 : 3.0
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				// Echoed so a capture run can be read from a terminal: what the
				// adapter says is half of what is being checked.
				controller?.panelForTesting.echoDebugOutputForTesting()
				if options.launchRun { controller?.runSelected(nil) }
				if options.launchDebug { controller?.debugSelected(nil) }
				if options.launchMenu {
					controller?.showConfigurationMenuForTesting(open: options.launchMenuGoal)
				}
				if options.launchEditor { controller?.runForTesting.editConfigurationForTesting() }
			}
		}

		if options.debugStop {
			// The console is the third of the three faults and cannot be read
			// from the session, so it is echoed as it arrives — the same way a
			// capture run reads what the adapter said.
			controller?.panelForTesting.echoDebugOutputForTesting()
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.goDebug(nil)
			}
			// Delve builds first, so the breakpoint is not reached for several
			// seconds; `--debug-steps` waits 6.0 for the same reason.
			DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
				controller?.reportDebugStopForTesting("before")
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) {
				controller?.reportDebugStopForTesting(options.debugFinish ? "finish" : "press")
			}
			// Twice afterwards. The first is what the gesture leaves at once;
			// the second is late enough for anything the adapter said on its way
			// out to have arrived, which is where Delve's exit status lives.
			DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
				controller?.reportDebugStopForTesting("after")
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 11.0) {
				controller?.reportDebugStopForTesting("settled")
			}
		}

		if options.debugInspect {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				if let binary = options.debugBinary {
					controller?.debugBinaryForTesting(binary)
				} else {
					controller?.goDebug(nil)
				}
			}
			// Once it has built and stopped, look at what is there — and do not
			// step, or the values belong to somewhere else.
			DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
				controller?.debugForTesting.inspectDebugStateForTesting()
			}
			// Then let it finish, so there is an exit code to report.
			DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
				controller?.reportExitForTesting()
			}
		}

		if options.debugSteps {
			// After the breakpoint has been set, which is scheduled at 1.0.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.goDebug(nil)
			}
			// Delve builds the program first, which takes a moment.
			for (index, delay) in [6.0, 7.5, 9.0, 10.5, 12.0].enumerated() {
				DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
					controller?.debugForTesting.reportDebugStepForTesting(step: index)
				}
			}
		}

		if options.undoTree {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.editorForTesting.exerciseUndoTreeForTesting()
			}
		}

		if let typed = options.completeText {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.editorForTesting.exerciseCompletionForTesting(typing: typed)
			}
		}

		if options.terminalTabBeside {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.exerciseTerminalTabBesideForTesting()
			}
		}

		if options.completeNow {
			// When it is pressed decides which of the two answers is under
			// test: early and the server is still preparing, late and it has a
			// list. Both are the feature working.
			DispatchQueue.main.asyncAfter(deadline: .now() + options.completeNowAt) {
				controller?.exerciseExplicitCompletionForTesting()
			}
		}

		if options.wordNavigation {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.editorForTesting.exerciseWordNavigationForTesting()
			}
		}

		if options.verticalNavigation {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.editorForTesting.exerciseVerticalNavigationForTesting()
			}
		}

		if options.emacsNavigation {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.editorForTesting.exerciseEmacsNavigationForTesting()
			}
		}

		if options.fakeDiagnostics {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.editorForTesting.injectDiagnosticsForTesting()
			}
		}

		if let wait = options.lspWait {
			DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
				controller?.editorForTesting.reportDiagnosticsForTesting()
			}
		}

		if let row = options.historyCommit {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.sidebarForTesting.showSidebarTool(.history)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.sidebarForTesting.selectHistoryForTesting(commit: row, file: 0)
			}
		}

		if let search = options.scratchSearch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.sidebarForTesting.showSidebarTool(.scratches)
				controller?.sidebarForTesting.searchScratchesForTesting(search)
				if options.openScratch { controller?.sidebarForTesting.openFirstScratchForTesting() }
			}
		}

		if let line = options.runLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.runForTesting.invokeForTesting(line: line, debug: false)
			}
		}

		if let line = options.debugLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.runForTesting.invokeForTesting(line: line, debug: true)
			}
		}

		if let tool = options.sidebarTool {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				switch tool {
				case "changes":   controller?.sidebarForTesting.showSidebarTool(.changes)
				case "branches":  controller?.sidebarForTesting.showSidebarTool(.branches)
				case "structure": controller?.sidebarForTesting.showSidebarTool(.structure)
				case "history":   controller?.sidebarForTesting.showSidebarTool(.history)
				case "scratches": controller?.sidebarForTesting.showSidebarTool(.scratches)
				case "pull-requests": controller?.sidebarForTesting.showSidebarTool(.pullRequests)
				default:          controller?.sidebarForTesting.showSidebarTool(.project)
				}
			}
		}

		if options.showChanges {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.toggleChanges(nil)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
				controller?.sidebarForTesting.selectFirstChangeForTesting()
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
				controller?.editorForTesting.selectDiffHunkForTesting(0)
			}
		}

		if options.reportChart {
			let chart = RunCoordinator.bundledChart
			print("CHART: \(chart?.path ?? "not found")")
		}

		if options.zoomWindow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				guard let window = controller?.window else { return }
				window.zoom(nil)
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
					print("ZOOM: got \(window.frame) screen \(window.screen?.visibleFrame ?? .zero)")
				}
			}
		}

		// A whole window of a stated size, centred on the screen it is on: two
		// machines taking the same documentation screenshot should produce the
		// same image, and the saved frame is per machine.
		if let widen = options.widenBy {
			DispatchQueue.main.asyncAfter(deadline: .now() + widen.at) {
				controller?.widenForTesting(by: widen.extra)
			}
		}

		if let size = options.windowSize {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				guard let window = controller?.window else { return }
				window.setContentSize(size)
				window.center()
			}
		}

		// The panel, likewise. Its height is remembered per machine, and one
		// left filling the window hides everything a screenshot is for.
		if let height = options.panelHeight {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
				controller?.setPanelHeightForTesting(height)
			}
		}

		if let width = options.windowWidth {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				guard let window = controller?.window else { return }
				var frame = window.frame
				frame.size.width = width
				window.setFrame(frame, display: true)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.titlebarForTesting.reportToolbarForTesting()
			}
		}

		if let line = options.saveGutterLine, let path = options.filePath {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.runForTesting.saveGutterConfigurationForTesting(
					file: URL(fileURLWithPath: path), line: line
				)
			}
		}

		if let name = options.runConfigNamed {
			// Later than most of these: the list is filled in by a scan on a
			// background queue, and asking for something before the scan has
			// answered reports only that it was not found.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.runForTesting.runNamedConfigurationForTesting(name)
			}
		}

		if let seconds = options.cadovaWatchSeconds {
			// A second in: a file opened with `--file` is not in a window at all for
			// the first moment, and the pane starts nothing until it has been.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.watchCadovaForTesting(seconds: seconds)
			}
		}

		if let seconds = options.diagramWatchSeconds {
			// From half a second, not one: a diagram pane says something from the
			// moment it exists — "Nothing to draw yet.", or what to install — and
			// that state is the one this watches for, so starting a whole second in
			// would miss it on a file that draws quickly.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				controller?.watchDiagramForTesting(seconds: seconds)
			}
		}

		if let goal = options.chooseMakeRun {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				controller?.runForTesting.chooseMakeRunForTesting(goal)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.runForTesting.describeRunTargetForTesting()
			}
		}

		if let goal = options.makeGoal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.runForTesting.runMakeGoalForTesting(goal, debug: options.makeDebug)
			}
		}

		if let filter = options.podFilter {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.showPodsForTesting(
					filter: filter, choose: options.podChoose, kind: options.profilerKind
				)
			}
		}

		if let address = options.profilerAddress {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.profileForTesting(
					address: address, kind: options.profilerKind ?? "heap"
				)
			}
		}

		// An unsteady click over a pane that is tracking the mouse. tmux copies
		// on selection, so a drag report from a click nobody meant is what
		// empties the clipboard.
		if let pixels = options.wobblePixels {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(2.0, options.screenshotDelay - 2)) {
				print(controller?.panelForTesting.showTerminal()?.terminalView
					.wobbleClickForTesting(pixels)
					?? "WOBBLE: no terminal")
				fflush(stdout)
			}
		}

		if options.highlightPills {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, options.screenshotDelay - 1)) {
				controller?.titlebarForTesting.highlightPillsForTesting()
			}
		}

		if let filter = options.attachFilter {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1, options.screenshotDelay - 1.5)) {
				controller?.runForTesting.showAttachPickerForTesting(filter: filter)
			}
		}

		if let spec = options.commandHoverAt {
			let parts = spec.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1, options.screenshotDelay - 1)) {
				guard parts.count == 2 else { return }
				controller?.editorForTesting.hoverWithCommandForTesting(
					line: parts[0] - 1, character: parts[1]
				)
			}
		}

		if let steps = options.navigateSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1, options.screenshotDelay - 1.5)) {
				controller?.navigateForTesting(steps)
			}
		}

		if let steps = options.treeSteps {
			// A run with a picture coming starts the script 1.5 s before the
			// shutter, as everything else here does. A run without one starts it
			// at the delay itself and ends when it ends, so a script with several
			// `settle`s in it is not cut off by an `exit` it cannot see.
			let capturing = options.writesACapture
			let at = capturing ? max(1, options.screenshotDelay - 1.5) : options.screenshotDelay
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.treeStepsForTesting(steps, thenExit: !capturing)
			}
		}

		// A fixed moment rather than one measured back from the screenshot: a
		// script that stages a folder and looks again has `settle`s in it and
		// runs for several seconds, which the shot is timed to outlast.
		if let steps = options.changesSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.sidebarForTesting.changesStepsForTesting(steps)
			}
		}

		if let later = options.changesLater {
			DispatchQueue.main.asyncAfter(deadline: .now() + later.at) {
				controller?.sidebarForTesting.changesStepsForTesting(later.steps)
			}
		}

		if options.pillState {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print(controller?.titlebarForTesting.branchPillForTesting() ?? "BRANCHPILL none")
				fflush(stdout)
			}
		}

		if let steps = options.branchRowSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.sidebarForTesting.branchRowsForTesting(steps)
			}
		}

		if let steps = options.hexSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				Task { @MainActor in
					let report = await controller?.editorForTesting.hexStepsForTesting(steps) ?? "HEX no window"
					print(report)
					fflush(stdout)
				}
			}
		}

		if let row = options.commitMenuRow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.sidebarForTesting.commitMenuForTesting(row: row)
			}
		}

		if let paths = options.comparePaths {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				Task { @MainActor in
					var report = controller?.openCompareForTesting(paths.0, paths.1) ?? "no window"
					if let steps = options.compareSteps {
						report += "\n" + (await controller?.compareStepsForTesting(steps) ?? "no window")
					}
					print("COMPARE: " + report)
					fflush(stdout)
				}
			}
		}

		if let steps = options.logPageSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.sidebarForTesting.logPageForTesting(steps)
			}
		}

		if let steps = options.commitPageSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.sidebarForTesting.commitPageForTesting(steps)
			}
		}

		// Later than the pages, because this one is a network call rather than a
		// `git` invocation: the list is not there to report on until `gh` has
		// answered, and the report waits for it besides.
		// The estate reads three answers a repository, each bounded, so it is
		// given the same head start the pages get.
		if let steps = options.estateSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.sidebarForTesting.estateForTesting(steps)
			}
		}

		if let steps = options.pullRequestSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.sidebarForTesting.pullRequestsForTesting(steps)
			}
		}

		if let steps = options.searchSteps {
			// A fixed moment rather than one measured back from the screenshot,
			// unlike the tree's: a script that ticks rows, presses ⌘Z and looks
			// again has `settle`s in it and runs for several seconds, so the
			// picture is timed to the script with `--delay` rather than the other
			// way round. 2.5 seconds is after `--search` starts the search at 0.8
			// and after the walk has put something in the list to tick.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.searchStepsForTesting(steps)
			}
		}

		if options.toggleStrictTmuxOff {
			// The checkbox's own path, so what is measured is what a click
			// does rather than what a test thinks it does.
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				TmuxSettings.setTabsAreTmuxWindows(false)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
				TmuxSettings.setTabsAreTmuxWindows(true)
			}
		}

		if let seconds = options.stopAfter {
			DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
				controller?.stopRunningForTesting()
			}
		}

		if let line = options.disabledBreakpointLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.debugForTesting.disableBreakpointForTesting(line: line)
			}
		}

		if let move = options.dragTmuxTab {
			let parts = move.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				guard parts.count == 2 else { return }
				controller?.panelForTesting.dragTmuxTabForTesting(from: parts[0], to: parts[1])
			}
		}

		if options.addTmuxWindow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				let before = controller?.panelForTesting.paneCountForTesting ?? 0
				controller?.panelForTesting.addTmuxWindowForTesting()
				// The one thing this button must never do is add a pane here.
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					let after = controller?.panelForTesting.paneCountForTesting ?? 0
					print("TMUXADD: panes \(before) -> \(after)")
				}
			}
		}

		if let goal = options.rerun {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.rerunSelectedForTesting(goal == "selected" ? nil : goal)
			}
		}

		if let action = options.serverBanner {
			// After the servers have been looked for, which is what decides
			// whether there is anything to say.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				if action == "report" {
					controller?.editorForTesting.reportServerBannerForTesting()
				} else {
					controller?.editorForTesting.pressServerBannerForTesting(action)
				}
			}
		}

		if let index = options.closeTmuxTab {
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				controller?.panelForTesting.closeTmuxTabForTesting(index)
			}
		}

		if let delay = options.addTerminalTabAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				let before = controller?.panelForTesting.paneCountForTesting ?? 0
				controller?.panelForTesting.addTerminalTabForTesting()
				// The panel's own + adds a pane: its strip holds the panel's own
				// tabs, and tmux's windows have the + on the strip below. The
				// count goes up by one here and stays put for --tmux-add.
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					print("PANELADD: panes \(before) -> \(controller?.panelForTesting.paneCountForTesting ?? 0)")
				}
			}
		}
	}
}

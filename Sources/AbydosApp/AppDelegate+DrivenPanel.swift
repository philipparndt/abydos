import AppKit
import AbydosKit

/// The flags a driven run applies once its window is up.
///
/// Every one of them is the same shape — a flag was given, so do the thing and
/// often print what happened — and they are in no order but the one they were
/// written in. Splitting them three ways is splitting a list, and the list is
/// what it is: `--help` is the index.
///
/// This third is the panel and what is below it — terminals, tmux, the
/// sidebar, the backlog — and the capture that ends the run.
@MainActor
extension AppDelegate {
	func driveThePanel(_ options: LaunchOptions, in controller: MainWindowController?) {
		// **What the run saw of the palette.** 0400's surviving candidate was a
		// torn read of `Theme.current`, and the audit that killed it is a claim
		// about 1580 reads in 99 files — so every driven run says whether
		// anything touched the palette off the main thread while it was up. A
		// line saying it did is the hypothesis coming back to life.
		if options.screenshotPath != nil {
			DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
				print("THEME: \(ThemeAccess.reportForTesting)")
				// The two numbers a crash log needs for its addresses to mean
				// anything a dSYM can answer about, printed here so that they
				// are known to be right without waiting for a crash.
				print("IMAGE: \(AppDelegate.imageLocation())")
				fflush(stdout)
			}
		}

		if let at = options.panelMaximizeAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.togglePanelMaximized(nil)
				print("PANEL: maximized=\(controller?.isPanelMaximized == true)")
				fflush(stdout)
			}
		}

		if let restoring = options.restorePages {
			DispatchQueue.main.asyncAfter(deadline: .now() + restoring.at) {
				let before = controller?.isPanelMaximized == true
				print("PAGES: " + (controller?.sidebarForTesting
					.restorePagesForTesting(restoring.identifiers) ?? "no window"))
				print("PAGES: maximized before=\(before)")
				// The pages load git first, so the answer that matters is the
				// one after that has had a moment to happen.
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					let tabs = controller?.editorForTesting.activeGroup?
						.tabTitlesForTesting.joined(separator: ", ") ?? "no group"
					print("PAGES: maximized after=\(controller?.isPanelMaximized == true) tabs=[\(tabs)]")
					fflush(stdout)
				}
			}
		}

		if let click = options.clickTmuxTab {
			DispatchQueue.main.asyncAfter(deadline: .now() + click.at) {
				print(controller?.clickTmuxTabAndReportForTesting(click.index) ?? "TMUX TAB: no window")
				fflush(stdout)
				// A beat, because following the shell is a subprocess and a
				// project switch is a load: whatever the click sets off has
				// not finished when it returns.
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					print(controller?.tmuxTabSettledReportForTesting() ?? "  settled: no window")
					fflush(stdout)
				}
			}
		}

		if let count = options.fillTmuxTabs {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				let panel = controller?.panelForTesting
				print("TMUX \(panel?.seedMirrorWindowsForTesting(count) ?? "no panel")")
				// And what choosing a hidden one does, which is the half of it
				// a picture cannot show: the run moves the least that brings
				// the window into view.
				print("TMUX CHOSE: \(panel?.selectHiddenMirrorWindowForTesting(0) ?? "no panel")")
				print("TMUX AFTER: \(panel?.mirrorOverflowReportForTesting ?? "no panel")")
				fflush(stdout)
			}
		}

		if let count = options.fillTerminalTabs {
			// Spread out rather than in a loop: each one starts a shell, and
			// twelve started in the same turn of the run loop is a burst the
			// panel never sees in use.
			for step in 0..<count {
				DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(step) * 0.25) {
					controller?.panelForTesting.addTerminalTabForTesting()
				}
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(count) * 0.25 + 1.5) {
				print("TABS: \(controller?.panelForTesting.paneCountForTesting ?? 0) panes")
				// A number rather than a picture: whether a tab can be reached
				// is a fact, and a screenshot of a full strip is a thing
				// somebody has to squint at.
				print("OVERFLOW: \(controller?.panelForTesting.panelOverflowReportForTesting ?? "none")")
				fflush(stdout)

				// And what choosing a hidden one does, which is the half of this
				// that a still picture cannot show: the run moves the least that
				// brings it into view.
				// The two are exclusive on purpose. Choosing a hidden tab pulls
				// the run back to show it, which is the very state the closing
				// case needs *not* to be in: what was reported is a strip whose
				// run is still pushed forward when tabs go away.
				if let closing = options.closeTerminalTabs {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						print("CLOSING: \(controller?.panelForTesting.closeTerminalTabsForTesting(count: closing) ?? "none")")
						DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
							print("CLOSED: \(controller?.panelForTesting.panelOverflowReportForTesting ?? "none")")
							fflush(stdout)
						}
					}
				} else {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						print("CHOSE: \(controller?.panelForTesting.selectHiddenPanelTabForTesting(0) ?? "none")")
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
							print("AFTER: \(controller?.panelForTesting.panelOverflowReportForTesting ?? "none")")
							fflush(stdout)
						}
					}
				}
			}
		}

		if let spec = options.clickPanelTab {
			let parts = spec.split(separator: "@")
			let index = Int(parts.first ?? "0") ?? 0
			let at = parts.count > 1 ? Double(parts[1]) ?? 4.0 : 4.0
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("PANEL \(controller?.panelForTesting.clickPanelTabAndReportForTesting(index) ?? "no window")")
			}
		}

		if let delay = options.closeTerminals {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				controller?.panelForTesting.closeTerminalTabsForTesting()
			}
		}

		if let milliseconds = options.stallMilliseconds {
			// A hitch on purpose, to prove the watch is awake and that the log
			// says what was going on.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				StallWatch.mark("deliberate stall") {
					Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
				}
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					for stall in StallWatch.worst(limit: 5) {
						print("STALL \(stall.line)")
					}
				}
			}
		}

		if let presses = options.typingPresses {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.panelForTesting.measureTypingForTesting(presses: presses, interval: 0.12)
			}
		}

		for (index, at) in options.openReportsAt.enumerated() {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("OPEN --- at \(at)s ---")
				// Only the last reading types. Typing changes the document and
				// the tree, so a run that measured keystrokes at five seconds
				// and again at sixty would have the second reading describe a
				// file the first one edited.
				let typing = index == options.openReportsAt.count - 1 ? options.openReportTyping : 0
				controller?.scaleReportForTesting(typing: typing)
			}
		}

		if let at = options.branchPillAt {
			ProjectSwitcherPopover.reportsForTesting = true
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.showBranchMenuForTesting()
				// Twice: once as it opens, which is what somebody clicking early
				// sees, and once after git has answered, which is the list.
				for delay in [0.05, 6.0] {
					DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
						print("BRANCHPOPOVER at +\(delay)s")
						for line in ProjectSwitcherPopover.rowsForTesting() {
							print("BRANCHPOPOVER \(line)")
						}
						fflush(stdout)
					}
				}
			}
		}

		if let branch = options.pushBranch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				controller?.sidebarForTesting.pushBranchForTesting(branch)
			}
		}

		if let row = options.branchMenuRow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.sidebarForTesting.branchMenuForTesting(row: row)
			}
		}

		if options.maximizeTerminal, options.sidebarTool != nil {
			// Maximise, borrow a tool over the terminal, then give the window
			// back — the sequence that used to come back to an empty sidebar.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.togglePanelMaximized(nil)
			}
		}

		if let hovers = options.tmuxMenuHovers {
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				controller?.panelForTesting.tmuxMenuForTesting(hovers: hovers)
			}
		}

		if let row = options.collapseRow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.sidebarForTesting.collapseHistoryRowForTesting(row)
			}
		}

		if let path = options.sidebarShot {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(2, options.screenshotDelay - 1)) {
				// **A capture that cannot be produced says so and exits
				// non-zero**, and one that can still ends the run. This wrote
				// its file and then sat there: `--sidebar-shot` on its own never
				// exited, so every driven use of it was a `timeout` away from
				// looking like a hang — and a run killed by `timeout` reports
				// 124 whether or not the picture was written.
				let ok = controller?.sidebarForTesting.snapshotSidebarForTesting(to: path) ?? false
				if !ok {
					FileHandle.standardError.write(Data("sidebar capture failed: \(path)\n".utf8))
				}
				// Only when nothing else is going to end the run: a
				// `--screenshot` in the same command owns the exit.
				if options.screenshotPath == nil { exit(ok ? 0 : 2) }
			}
		}

		if let path = options.tabCloseHover {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(3, options.screenshotDelay)) {
				controller?.panelForTesting.tabCloseHoverForTesting(to: path)
				exit(0)
			}
		}

		if let width = options.sidebarWidth {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.openSidebarForTesting(width: CGFloat(width))
			}
		}

		if let appearance = options.switchAppearance {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				Settings.shared.appearance = appearance
			}
		}

		if let width = options.resizeWidth {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				guard let window = controller?.window else { return }
				var frame = window.frame
				frame.size.width = width
				window.setFrame(frame, display: true, animate: false)
			}
		}

		if options.showsBlame {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.toggleBlame(nil)
			}
		}

		// The board's own cards and the tip's state, on a clock, so a process
		// posting pointer moves from outside can read what its moves did.
		for at in options.tipReportAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("TIP \(at)s: \(controller?.panelForTesting.tipReportForTesting() ?? "no window")")
				fflush(stdout)
			}
		}

		for at in options.backlogGeometryAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("BACKLOG-GEOM \(Int(at))s: \(controller?.panelForTesting.backlogGeometryForTesting() ?? "no window")")
				fflush(stdout)
			}
		}

		// After `--send-bytes` has put the address there, and before a screen
		// report at seven can read the row it landed on.
		if let link = options.terminalLink {
			DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
				print(controller?.panelForTesting.terminalLinkReportForTesting(
					row: link.row, column: link.column, click: link.click, bare: link.bare) ?? "LINK: no window")
				fflush(stdout)
			}
		}

		for seconds in options.terminalScreenAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
				print(controller?.panelForTesting.terminalScreenReportForTesting(label: "\(seconds)s") ?? "TERMINAL SCREEN: no window")
				fflush(stdout)
			}
		}

		if options.reportsTerminalGeometry {
			for seconds in [3.0, 5.0, 7.0, 9.0] {
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
					print("GEOM \(Int(seconds))s: \(controller?.panelForTesting.terminalGeometryForTesting() ?? "-")")
					print("PANEL \(Int(seconds))s: \(controller?.panelForTesting.panelGeometryForTesting() ?? "-")")
					fflush(stdout)
				}
			}
		}

		if options.pills.terminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				switch options.pills.which {
				case "all": controller?.exerciseEveryDevContainerTerminalForTesting()
				case let which?: controller?.exerciseDevContainerTerminalForTesting(
					which: Int(which)
				)
				case nil: controller?.exerciseDevContainerTerminalForTesting()
				}
			}
		}

		for at in options.pills.devContainerAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.titlebarForTesting.devContainerPillForTesting() ?? "PILL: no window")")
				fflush(stdout)
			}
		}

		for at in options.pills.worktreeAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.titlebarForTesting.worktreePillForTesting() ?? "WORKTREE: no window")")
				fflush(stdout)
			}
		}

		if let at = options.pills.worktreeMenuAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.titlebarForTesting.worktreeMenuForTesting() ?? "WORKTREEMENU: no window")")
				fflush(stdout)
			}
		}

		for at in options.panelTabsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s "
					+ (controller?.panelTabsForTesting(tail: options.panelTabsTail)
						?? "PANEL: no window"))
				fflush(stdout)
			}
		}

		if let at = options.pills.devContainerMenuAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print(controller?.titlebarForTesting.devContainerMenuForTesting() ?? "PILLMENU: no window")
				fflush(stdout)
			}
		}

		for spec in options.pills.pressDevContainer {
			let parts = spec.split(separator: "@")
			let title = String(parts.first ?? "")
			let at = parts.count > 1 ? Double(parts[1]) ?? 8 : 8
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				let pressed = controller?.pressDevContainerMenuForTesting(title) ?? false
				print("\(Int(at))s PILLMENU pressed \(title): "
					+ (pressed ? "yes" : "there was no such entry"))
				fflush(stdout)
			}
		}

		for at in options.toastReportsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.toastReportForTesting() ?? "TOASTS: no window")")
				fflush(stdout)
			}
		}

		// Far enough apart that the tip's own half-second wait elapses on each,
		// so a capture at the end photographs the last one resting rather than
		// catching the timer mid-flight.
		for (index, name) in options.hoverControls.enumerated() {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.5 + Double(index) * 0.8) {
				print("HOVER: " + (controller?.hoverChromeForTesting(name) ?? "no window"))
				fflush(stdout)
			}
		}

		if let count = options.seededWindows {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				print("SEEDED: \(controller?.panelForTesting.seedTmuxSessionsForTesting(count) ?? "no window")")
				fflush(stdout)
			}
		}

		for at in options.running.at {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.runningSessionsReportForTesting() ?? "SESSIONS: no window")")
				fflush(stdout)
			}
		}
		if let at = options.running.menuAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.openRunningSessionsForTesting(filter: options.running.filter) ?? "SESSIONS: no window")")
				fflush(stdout)
			}
		}
		for at in options.running.paletteAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.openRunningSessionsPaletteForTesting(filter: options.running.filter) ?? "SESSIONS: no window")")
				fflush(stdout)
			}
		}
		if let how = options.zoomGesture {
			DispatchQueue.main.asyncAfter(deadline: .now() + options.zoomGestureAt) {
				controller?.exerciseZoomForTesting(how)
			}
		}

		for at in options.presentationAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.togglePresentationMode(nil)
				print("\(Int(at))s PRESENTATION toggled: scale=\(Settings.shared.activeScale)")
				fflush(stdout)
			}
		}
		if let keys = options.running.keys {
			let opened = options.running.menuAt ?? options.running.paletteAt.first ?? 6
			DispatchQueue.main.asyncAfter(deadline: .now() + opened + 0.6) {
				print("SESSIONS keys: \(controller?.pressInRunningSessionsForTesting(keys) ?? "no window")")
				fflush(stdout)
			}
		}
		if let at = options.running.chooseAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.chooseFirstRunningSessionForTesting() ?? "SESSIONS: no window")")
				fflush(stdout)
			}
		}

		if let spec = options.answerToast {
			let parts = spec.split(separator: "@")
			let title = String(parts.first ?? "")
			let at = parts.count > 1 ? Double(parts[1]) ?? 6 : 6
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				let pressed = controller?.answerToastForTesting(title) ?? false
				print("ANSWERED \(title): \(pressed ? "yes" : "there was no such answer on screen")")
				fflush(stdout)
			}
		}

		for at in options.serverBannersAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s ", terminator: "")
				controller?.editorForTesting.reportServerBannerForTesting()
				fflush(stdout)
			}
		}

		for switching in options.switchProjects {
			DispatchQueue.main.asyncAfter(deadline: .now() + switching.at) {
				let url = URL(fileURLWithPath: (switching.path as NSString).expandingTildeInPath)
				// What the panes held before, so the after-state is a comparison
				// rather than a claim.
				controller?.reportPanesForTesting("before")
				// Captured *before* the switch, which is the whole point of it.
				// Taken after, this named the project just arrived at and the
				// watcher check touched the wrong tree — a harness reporting
				// "proj-b has no backlog" about a check meant for proj-a.
				let left = controller?.project?.root
				controller?.switchProject(to: url, followingTerminal: true)
				print("SWITCHED to \(url.lastPathComponent) at \(Int(switching.at))s")
				fflush(stdout)
				// After the walk that re-reads the folders, which happens off
				// the main thread: asked sooner, this reports a board that has
				// not finished arriving.
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					controller?.reportPanesForTesting("after")
					// And then the silent half: is the project that was left
					// still being watched?
					if let left, options.checkOldWatcher {
						controller?.checkTheOldProjectIsUnwatchedForTesting(left)
					}
				}
			}
		}

		if options.terminalAddMenu {
			// The panel first, since a strip that is not on screen has no layout
			// and so no hit areas to ask about.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.showTerminalPanelForTesting()
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					print("TABADD areas: \(controller?.panelForTesting.terminalAddControlsForTesting ?? "no window")")
					print("TABADD menu: \(controller?.newTerminalMenuForTesting() ?? "no window")")
					fflush(stdout)
					if options.writesACapture { return }
					exit(0)
				}
			}
		}

		if options.reportsTerminalDirectory {
			// From one second in, because the switch this catches happens about a
			// second after launch: a first reading at three seconds is already the
			// window on the other project, which reads as a window that opened
			// there. Flushed, because a driver run ends in a kill.
			for seconds in [1.0, 2.0, 3.0, 5.0, 7.0, 9.0] {
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
					let where_ = controller?.panelForTesting.terminalDirectoryForTesting()
					print("CWD \(Int(seconds))s: \(where_?.path ?? "unknown")"
						+ "  \(controller?.projectReportForTesting() ?? "no window")")
					fflush(stdout)
				}
			}
		}

		if options.pushChanges {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
				controller?.pushChangesForTesting()
			}
		}

		if let line = options.breakpointLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.debugForTesting.toggleBreakpointForTesting(line: line)
			}
		}

		for delay in options.breakpointReports {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				print("BREAKPOINTS at \(delay)s:")
				print(controller?.debugForTesting.breakpointReportForTesting() ?? "no window")
			}
		}

		if options.sidebarCycle {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.sidebarForTesting.showSidebarTool(.changes)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.sidebarForTesting.showSidebarTool(.project)
			}
		}

		if options.zoomCycle {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.zoomIn(nil)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.zoomOut(nil)
			}
		}

		if let second = options.tearOffFile {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.editorForTesting.openForTesting(URL(fileURLWithPath: second))
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
				controller?.editorForTesting.tearOffForTesting(index: 1, at: NSPoint(x: 300, y: 600))
				self.reportWindowsForTesting("torn off")
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
				self.dragTornOffTabBackForTesting(into: controller)
				self.reportWindowsForTesting("dragged back")
			}
		}

		if let at = options.closeLastWindowAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				guard let last = self.windowControllers.last else { return }
				let project = last.project?.root.lastPathComponent ?? "nothing"
				last.close()
				print("CLOSED a window showing \(project); "
					+ "\(self.windowControllers.count) left")
			}
		}

		if options.followTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.toggleFollowTerminal(nil)
				// **What the switch left behind, not only what it did.** It
				// used to flip the window and write nothing, so following came
				// back off at every launch — and no run could see that, because
				// a run only ever asked the window it had just told.
				print("FOLLOW: window=\(controller?.followsTerminal == true)"
					+ " stored=\(Settings.shared.followsTerminalProject)")
				fflush(stdout)
			}
		}

		if options.maximizeTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				controller?.togglePanelMaximized(nil)
			}
		}

		if let path = options.metalShot {
			// The bell is rung a moment before the frame is taken, so what is
			// captured is the effect part-way through rather than at rest.
			if let before = options.bellBefore {
				DispatchQueue.main.asyncAfter(deadline: .now() + options.screenshotDelay - before) {
					controller?.ringTerminalBellForTesting()
				}
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + options.screenshotDelay) {
				controller?.renderTerminalWithMetal(to: path)
				exit(0)
			}
		}

		if options.benchRender {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				controller?.benchmarkTerminalRendering()
				exit(0)
			}
		}

		if options.reviewUncommitted {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				controller?.reviewUncommittedChanges(nil)
			}
		}

		if options.startReview {
			controller?.reviewBranch(nil)
		}

		if let mode = options.backlogMode {
			controller?.showBacklog(nil)
			// `--backlog openspec` and `--backlog openspec-list`: which record,
			// then how it is drawn. Two questions, and neither answers the
			// other — which is the same reason the pane has two controls.
			controller?.showBacklogMode(list: mode.hasSuffix("list"))
			// `--backlog openspec-switch`: the switch is clicked *after* the
			// board is up, which is the gesture somebody makes and not the one
			// a driver usually makes — the call below happens before the walk
			// that reads the folders has come back, so it switches a board with
			// nothing on it.
			controller?.showBacklogSource(
				openSpec: !mode.hasSuffix("switch") && mode.hasPrefix("openspec"))

			// After the walk that reads both folders, which happens off the main
			// thread: a report asked for before the cards arrive is a report of
			// an empty board.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.showBacklogSource(openSpec: mode.hasPrefix("openspec"))
				print("BACKLOG project: \(controller?.project?.root.path ?? "none")")
				print(controller?.backlogBoardReportForTesting() ?? "no project")
				for column in ["ready", "in-progress"] {
					print("drag \(column): "
						+ (controller?.backlogDragReportForTesting(state: column) ?? "none"))
				}
				fflush(stdout)
			}

			// `--backlog openspec-watch`: the same report again, ten seconds
			// later, with nothing touched in between. The point of a dashboard
			// over files is that the files are the truth, and the only way to
			// show that a box ticked in a terminal moves a card is to tick one
			// while the board is up and look again.
			if mode.hasSuffix("watch") {
				DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
					print("BACKLOG again:")
					print(controller?.backlogBoardReportForTesting() ?? "no project")
					fflush(stdout)
				}
			}
		}

		// After a wait, because the board reads the folder off the main thread
		// and a menu asked for before the cards arrive is a menu for no card.
		//
		// The project is printed first, and it is not decoration: an agent
		// driving this app with `--open` once had a window come up on a project
		// from the recent list instead, and everything it then did it did to
		// somebody else's files. Whatever is printed below is only about the
		// tree named on this line.
		if options.backlogMenu != nil || options.backlogMenuChange != nil
			|| options.backlogNew != nil || options.backlogInit
			|| options.backlogTasks != nil || options.backlogTasksChange != nil
			|| options.backlogTick != nil || options.backlogUntick != nil || options.backlogTasksShot != nil {
			// **Waited for rather than slept through.** Three seconds was enough
			// for the backlog, whose state is which folder a file is in; the
			// OpenSpec record asks the CLI about every change, and a board still
			// loading answers "no change called that", which reads as a card
			// that is missing rather than as a report asked too early.
			whenTheBoardHasCards(controller, giveUpAfter: 20) {
				print("BACKLOG project: \(controller?.project?.root.path ?? "none")")
				if let number = options.backlogMenu {
					print("BACKLOG menu \(String(format: "%04d", number)): "
						+ (controller?.backlogMenuForTesting(number: number) ?? "no window"))
				}
				if let name = options.backlogMenuChange {
					print("BACKLOG menu \(name): "
						+ (controller?.backlogMenuForTesting(change: name) ?? "no window"))
				}
				if options.backlogInit {
					print("BACKLOG before: \(controller?.backlogAbsentForTesting() ?? "no window")")
					print("BACKLOG init: \(controller?.makeBacklogForTesting() ?? "no window")")
				}
				if let title = options.backlogNew {
					print("BACKLOG new: "
						+ (controller?.newBacklogItemForTesting(titled: title) ?? "no window"))
				}
				// The tick before the report, deliberately: `--backlog-tick`
				// and `--backlog-tasks` together are "tick one and show me what
				// is left", which is the pair somebody working a manual list
				// asks for.
				if let asked = options.backlogTick {
					print("BACKLOG tick \(asked.card):\(asked.index): "
						+ (controller?.backlogTickForTesting(card: asked.card, index: asked.index)
							?? "no window"))
				}
				// And back, through the row the tip keeps with *Undo* on it: the
				// pair is the round trip the change is about.
				if let card = options.backlogUntick {
					print("BACKLOG untick \(card): "
						+ (controller?.backlogUntickForTesting(card: card) ?? "no window"))
				}
				if let number = options.backlogTasks {
					print("BACKLOG tasks \(String(format: "%04d", number)):")
					print(controller?.backlogTasksForTesting(number: number) ?? "no window")
				}
				if let name = options.backlogTasksChange {
					print("BACKLOG tasks \(name):")
					print(controller?.backlogTasksForTesting(change: name) ?? "no window")
				}
				if let path = options.backlogTasksShot {
					print("BACKLOG tasks shot: "
						+ (controller?.backlogTasksShotForTesting(to: path) ?? "no window"))
				}
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if options.detailDialog {
			// The real thing a missing server offers, so what is captured is what
			// somebody pressing "How to install" would actually be shown.
			let suggestion = LanguageServers.Suggestion(
				languageId: "tsx",
				languageName: "TSX",
				command: "typescript-language-server",
				installHint: "npm install -g typescript-language-server typescript"
			)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				DetailDialog(
					title: "Installing \(suggestion.command)",
					detail: suggestion.manual,
					isError: false
				).show(over: controller?.window)
			}
		}

		if let raw = options.terminalBytes {
			// \e and \x01-style escapes, so a sequence can be given on the
			// command line.
			let decoded = raw
				.replacingOccurrences(of: "\\e", with: "\u{1B}")
				.replacingOccurrences(of: "\\x01", with: "\u{01}")
				.replacingOccurrences(of: "\\x05", with: "\u{05}")
				.replacingOccurrences(of: "\\r", with: "\r")
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.sendToTerminal(decoded)
			}
		}

		// What has the keyboard, which is the half of `abydos <file>` that no
		// picture can show: a caret between blinks looks exactly like a caret in
		// a view nobody is typing into.
		//
		// The key window when there is one, and this window's own first
		// responder when there is not — a run started without the app coming to
		// the front has no key window at all, and the first responder is still
		// what the next keystroke would reach, which is the thing being claimed.
		for at in options.focusReportsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				// Which window, as well as which view. A results list expanded into
				// a window of its own puts a second window on screen, and "the
				// first responder is a ChecklistTable" is then two different
				// answers depending on whose responder it is — the panel
				// remembering where its own focus was, or the keys actually going
				// there. Item 510 could not tell those apart without this.
				let key = NSApp.keyWindow
				let window = key ?? controller?.window
				let responder = window?.firstResponder
				let name = responder.map { String(describing: type(of: $0)) } ?? "nothing"
				let whose = window.map { String(describing: type(of: $0)) } ?? "no window"
				print("FOCUS \(String(format: "%.1f", at))s \(name) "
					+ "in \(whose)\(key == nil ? " (none key)" : "")")
			}
		}

		if options.openTerminal {
			controller?.toggleTerminal(nil)
			// One at a time, spaced out. Given all at once these arrive in the
			// pty together, and a command that reads the tty itself — `kitty
			// icat` outside tmux does, to hear what the terminal can do — reads
			// the ones after it and throws them away.
			for (index, input) in options.terminalInput.enumerated() {
				// Give the shell time to print its prompt before typing at it.
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + Double(index) * 2.0) {
					controller?.sendToTerminal(input + "\n")
				}
			}
		}

		if options.quickLook {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1.0, options.screenshotDelay - 1.2)) {
				print("QUICKLOOK: " + (controller?.editorForTesting.quickLookForTesting() ?? "no window"))
			}
		}

		if !options.tabDoubleClicks.isEmpty {
			let after = max(1.0, options.screenshotDelay - 1.2)
			for (index, tab) in options.tabDoubleClicks.enumerated() {
				DispatchQueue.main.asyncAfter(deadline: .now() + after + Double(index) * 0.3) {
					print("TAB double-click \(tab): "
						+ (controller?.doubleClickTabForTesting(tab) ?? "no window"))
				}
			}
		}

		// After whatever `--run` put on the screen, and before the shot: a
		// selection is drawn over output, so there has to be output first.
		if !options.terminalSelections.isEmpty {
			let after = max(1.0, options.screenshotDelay - 1.0)
			for (index, drag) in options.terminalSelections.enumerated() {
				DispatchQueue.main.asyncAfter(deadline: .now() + after + Double(index) * 0.2) {
					controller?.panelForTesting.selectInTerminalForTesting(drag)
				}
			}
		}

		if options.typeText != nil || options.collapseFolds || options.markdownPreview {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, options.screenshotDelay - 0.5)) {
				if let text = options.typeText { controller?.simulateTyping(text) }
				if options.collapseFolds { controller?.collapseAllFolds(nil) }
				if options.markdownPreview { controller?.toggleMarkdownPreview(nil) }
			}
		}

		if let section = options.dumpSettings {
			// Flattened, so a child page can be dumped as well as a top-level
			// one. The pages under Tools are where the tools actually are, and a
			// dump that could only reach their parent could say nothing about
			// any of them.
			let rows = SettingsSections.flattened.first { $0.section.title == section }?
				.section.rows() ?? []
			for line in SettingsPaneController.describe(rows, withHelp: options.dumpSettingsHelp) {
				print("SETTING \(line)")
			}
			exit(0)
		}

		// A preference chosen while the app is running, which is the moment 0460
		// is about. Timed, because a preference changed before anything has been
		// tried has nothing to reconsider: the case that matters is a server that
		// has already failed for this project.
		if let said = options.chooseSetting {
			DispatchQueue.main.asyncAfter(deadline: .now() + options.chooseSettingAt) {
				print("CHOSE: \(SettingsSections.choose(said))")
			}
		}

		if let delivering = options.deliverDraft {
			DispatchQueue.main.asyncAfter(deadline: .now() + delivering.at) {
				print("DRAFT: " + (controller?
					.deliverDraftForTesting(root: delivering.root) ?? "no window"))
				fflush(stdout)
			}
		}

		if let said = options.settingsSays {
			print("SAYS: \(SettingsSections.says(said))")
			fflush(stdout)
		}

		// Beside `--settings`, and for the same reason: a panel nothing can open
		// from a script is a panel no run can photograph, and what the About
		// panel says — the version, the build, the documentation link — is
		// exactly the sort of claim worth a screenshot.
		if options.openAbout {
			showAbout(nil)
		}

		if options.openSettings {
			controller?.settingsSectionForTesting = options.settingsSection
			controller?.settingsFoldForTesting = options.settingsFold
			controller?.showSettingsPage(nil)

			// After anything else the run asked for — a zoom cycle above all —
			// so the report says what the page settled at rather than what it
			// opened as.
			if let keys = options.settingsKeys {
				DispatchQueue.main.asyncAfter(
					deadline: .now() + max(0.4, options.screenshotDelay - 0.4)
				) {
					controller?.editorForTesting.pressSettingsKeysForTesting(keys)
				}
			}
			if let text = options.settingsFilter {
				// Before the capture, so the picture is of the filtered page,
				// and after the page has had a turn to build.
				DispatchQueue.main.asyncAfter(
					deadline: .now() + max(0.4, options.screenshotDelay - 0.8)
				) {
					controller?.editorForTesting.filterSettingsForTesting(text)
				}
			}
		}

		// The list of what is running, driven the way somebody would drive it:
		// open it, read it, press Stop on a row, read it again.
		//
		// It waits before it opens, and that is not politeness: a count taken
		// while a language server is still starting is a race rather than a
		// rule, which is the same lesson `--switch-to path@seconds` records one
		// section along in 0427.
		if options.runningTools {
			let window = RunningToolsWindowController.shared
			let wanted = options.stopRunning
			// Nothing to photograph means nothing to wait for afterwards, so the
			// run ends when the reading is done — this is a measurement anybody
			// can take from a script, and a window left open is a run that has
			// to be killed.
			let ends = options.screenshotPath == nil
			// Eight seconds, or longer when a run says so. With a picture to
			// take, `--delay` is when to take it and this stays at eight so the
			// sequence fits in front of it; with no picture there is nothing to
			// fit in front of, and `--delay` becomes how long to let the servers
			// settle — which is what a measurement of a server that indexes
			// wants, since the processes underneath it arrive after it does.
			let opensAt = ends ? max(8.0, options.screenshotDelay) : 8.0
			DispatchQueue.main.asyncAfter(deadline: .now() + opensAt) {
				window.show()
				window.refresh {
					print("RUNNING: before\n\(window.reportForTesting)")
					guard let wanted else {
						if ends { exit(0) }
						return
					}
					window.stopForTesting(matching: wanted) {
						print("RUNNING: after\n\(window.reportForTesting)")
						// And then something needs it again, which is the half of
						// "stopping is not for ever" that is easy to leave
						// unproven: every open file is announced afresh, exactly
						// as it is when the scope moves under one.
						print("RUNNING: rescoping \(controller?.editorForTesting.tabCountForTesting ?? -1) tab(s)")
						controller?.editorForTesting.rescope()
						DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
							window.refresh {
								// Whether the stopped process really went, asked
								// of the operating system rather than of the
								// register the list is drawn from.
								if let pid = window.stoppedPidForTesting {
									print("RUNNING: pid \(pid) still alive: "
										+ "\(ToolContainers.isAlive(pid))")
								}
								print("RUNNING: after a file needed it again\n"
									+ window.reportForTesting)
								if ends { exit(0) }
							}
						}
					}
				}
			}
		}

		if let path = options.editorShotPath {
			DispatchQueue.main.asyncAfter(deadline: .now() + options.screenshotDelay) {
				let ok = controller?.editorForTesting.writeEditorImageForTesting(to: path) ?? false
				FileHandle.standardError.write(Data("editor shot \(ok ? "written" : "failed"): \(path)\n".utf8))
				if options.screenshotPath == nil { exit(ok ? 0 : 2) }
			}
		}

		if let path = options.screenshotPath {
			scheduleScreenshot(
				path: path,
				delay: options.screenshotDelay,
				controller: controller
			) { [weak controller] in
				// The list is a window of its own, so it is nowhere in the main
				// window's frame. Photographed directly when it is the subject.
				if options.runningTools { return RunningToolsWindowController.shared.window }

				// **The About panel is AppKit's own window** — nothing here
				// holds a reference to one — so it is found as the frontmost
				// window that is not the project's. Asked at capture time
				// rather than when the run was set up, because at that point it
				// has not been opened yet. `scheduleScreenshot` prints the
				// title it photographed, which is what says it found the
				// right one.
				// **`NSApp.windows`, not `orderedWindows`.** The panel is an
				// `NSPanel` with no title, and the ordered list does not carry
				// it — asking that way found nothing and the capture silently
				// photographed the project window instead, which is the same
				// afternoon-losing failure the "captured …" line above exists
				// to catch. It caught this one.
				if options.openAbout {
					return NSApp.windows.first { $0.isVisible && $0 !== controller?.window }
				}
				return nil
			}
		}
	}
}

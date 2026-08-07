import AppKit
import AbydosKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
	/// Public so the four-line executable — and an Xcode application target
	/// built from the same sources — can make one.
	public override init() { super.init() }

	private var windowControllers: [MainWindowController] = []
	/// Claude sessions announcing themselves, from the hook this binary also is.
	private var claudeWatch: ClaudeWatch?

	@objc func showAbout(_ sender: Any?) {
		NSApp.orderFrontStandardAboutPanel(options: [
			.applicationVersion: Self.buildDescription
				.replacingOccurrences(of: "Abydos ", with: ""),
		])
		NSApp.activate(ignoringOtherApps: true)
	}

	/// Which build this is: the version, the commit count, and the commit.
	static var buildDescription: String {
		let info = Bundle.main.infoDictionary
		let version = info?["CFBundleShortVersionString"] as? String ?? "?"
		let build = info?["CFBundleVersion"] as? String ?? "?"
		let commit = info?["IdeaiCommit"] as? String ?? "unknown"
		return "Abydos \(version) (build \(build), \(commit))"
	}

	public func applicationDidFinishLaunching(_ notification: Notification) {
		// Settings from the other identifier this app has had, before anything
		// reads one: a change of identifier would otherwise look like every
		// preference being forgotten at once. The App Store rename to
		// `de.rnd7.ideai` has been reversed for now — macOS files the Local
		// Network grant under the identifier and cannot move one between names,
		// and this macOS beta cannot create a new grant at all — so settings
		// come back from where that rename left them.
		Settings.migrate(from: "de.rnd7.ideai")

		// An earlier version turned tmux's bar off for the whole server by
		// writing to ~/.tmux.conf. It is per session now, so that line goes.
		TmuxSettings.migrateAwayFromConfigEdit()

		// Where the user's tools actually are, asked of their shell before the
		// first file wants to know.
		UserShell.warmLoginPath()

		// Claude sessions in the terminal, saying when they need an answer or
		// have finished. Nothing arrives unless the hooks are installed.
		let watch = ClaudeWatch()
		watch.windows = { [weak self] in self?.windowControllers ?? [] }
		watch.start()
		claudeWatch = watch

		// Watching for the main thread going away, from the start: a hitch
		// while typing is over before it can be looked into, so the trail has
		// to be there already. One sleeping thread, written to
		// ~/Library/Logs/Abydos/stalls.log only when something takes too long.
		StallWatch.start()

		// Before the palette is chosen, since presenting picks a different one.
		// An override rather than the stored switch: this shares a preferences
		// domain with the installed app, and a screenshot must not leave it
		// presenting.
		if LaunchOptions.parse().presentation { Settings.shared.presentingOverride = true }

		// The palette, before anything is built with it.
		Theme.apply()
		DistributedNotificationCenter.default.addObserver(
			forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
			object: nil,
			queue: .main
		) { _ in
			// The system's own answer arrives a moment after the notification.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				guard Theme.apply() else { return }
				NotificationCenter.default.post(name: .abydosSettingsChanged, object: nil)
			}
		}

		// The palette decides this now — `Theme.apply()` above set it.
		// Before any view measures text.
		FontRegistry.registerBundledFonts()
		buildMenu()

		// On first launch there is no Abydos history, so seed the switcher from
		// JetBrains' own recent-projects list — the point is that the list in the
		// titlebar is already populated with the projects the user cares about.
		RecentProjects.shared.seedFromJetBrainsIfEmpty()

		// Notes written before scratches moved to ~/.config, carried over. Ahead
		// of anything that reads them, so no window ever sees the old place.
		let carried = ScratchFiles.migrateLegacyStore()
		if carried > 0 { print("Moved \(carried) scratch file(s) to \(ScratchFiles.defaultRoot.path)") }

		let options = LaunchOptions.parse()

		// "Is the thing I just installed the thing that is running?" — a
		// question that has come up once too often to keep answering by
		// guesswork.
		if options.reportVersion {
			print(Self.buildDescription)
			exit(0)
		}

		// Asked before anything else is built: the answer is about this app,
		// and touching the local network is what makes macOS offer the prompt
		// that everything it launches then inherits.
		if let target = options.probeLAN {
			guard let (host, port) = LocalNetworkProbe.parse(target) else {
				print("usage: --probe-lan host:port")
				exit(2)
			}
			// The app's own answer, and then a child's. The permission belongs
			// to the app; whether what it launches inherits it is the question,
			// and a debugger, a test run or a program under test is a child.
			LocalNetworkProbe.check(host: host, port: port) { own in
				let child = LocalNetworkProbe.checkWithSocket(host: host, port: port)
				let report = """
				local network \(host):\(port)
				  the app itself:      \(own.summary)
				  a program it starts: \(child.summary)
				"""
				print(report)
				// Written as well as printed: launched from the Dock — which is
				// the only launch whose answer is about this app rather than
				// about whatever started it — there is nowhere for stdout to go.
				DiagnosticLog.write(report, to: "network")
				// Refused counts as a pass: something answered, which is only
				// possible when the connection was allowed to be made at all.
				let allowed = { (r: LocalNetworkProbe.Result) in r == .reachable || r == .refused }
				exit(allowed(own) && allowed(child) ? 0 : 1)
			}
			return
		}

		// Before anything is drawn: a palette applied after the first window is
		// a window drawn twice, and the capture can catch the first one.
		if let theme = options.theme {
			Settings.shared.appearance = theme
			// The terminal follows, which is what it does by default now. A run
			// that wants them apart says so by setting the scheme itself.
			Settings.shared.terminalScheme = Appearance.followsEditor
			Theme.apply()
		}

		MetalProbe.start()
		if let zoom = options.zoom { Settings.shared.uiScale = zoom }

		let controller: MainWindowController?
		if let path = options.projectPath {
			controller = open(projectAt: URL(fileURLWithPath: path, isDirectory: true))
		} else if let last = RecentProjects.shared.entries.first {
			controller = open(projectAt: last.url)
		} else if options.isScreenshotRun {
			// A capture run must never block on a modal panel.
			controller = nil
		} else {
			openProjectPanel(nil)
			controller = windowControllers.first
		}

		for path in options.filePaths {
			controller?.openFile(at: URL(fileURLWithPath: path))
		}
		if let previewPath = options.previewPath {
			controller?.previewFile(at: URL(fileURLWithPath: previewPath))
		}
		if options.expandNavigator {
			controller?.expandNavigatorTree()
		}

		// A capture run never takes the keyboard.
		//
		// The screenshot is drawn straight from the view hierarchy, so it needs
		// no focus at all — and an app that steals it while somebody is typing
		// somewhere else does not merely interrupt them: their next keystrokes
		// arrive in whatever this window has open, and get saved there.
		if options.isScreenshotRun || options.metalShot != nil {
			NSApp.setActivationPolicy(.accessory)
		} else {
			NSApp.activate(ignoringOtherApps: true)
		}

		// Simulated input runs after the initial parse lands, so folds and
		// highlights exist by the time it is exercised.
		if options.splitActive {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitActiveForTesting()
			}
		}
		if options.splitThenDisturb {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitThenDisturbForTesting()
			}
		}
		if options.splitPanes {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitPanesForTesting()
			}
		}
		if options.splitTerminals {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitTerminalsForTesting()
			}
		}
		if options.previewTerminalDrop {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.previewTerminalDropForTesting()
			}
		}
		if options.tearOffTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.tearOffTerminalForTesting()
			}
			// And then the command a person reaches for out there, through the
			// responder chain the menu uses rather than by calling the method:
			// calling it proves the method exists, which was never in doubt.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				let item = NSMenuItem(
					title: "New Terminal Tab",
					action: Selector(("newTerminalTab:")),
					keyEquivalent: "t"
				)
				let window = TerminalWindowController.lastOpenedForTesting
				let before = window?.terminalCountForTesting ?? -1
				let enabled = window?.validateMenuItem(item) ?? false
				// Down that window's own responder chain rather than the
				// application's: a capture run has no key window, so an
				// app-wide send starts nowhere and proves nothing.
				window?.window?.makeKeyAndOrderFront(nil)
				let delivered = window?.window?.tryToPerform(item.action!, with: item) ?? false
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					print("TORNOFF: enabled=\(enabled) delivered=\(delivered) "
						+ "terminals \(before) -> \(window?.terminalCountForTesting ?? -1)")
				}
			}
		}

		if let name = options.renameTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.renameActiveTerminalForTesting(to: name)
			}
		}

		if let path = options.switchTo {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				self.open(projectAt: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
			}
		}

		if let filter = options.switcherFilter {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.showProjectSwitcher(nil)
				if !filter.isEmpty {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
						ProjectSwitcherPopover.applyFilterForTesting(filter)
					}
				}
			}
		}
		if let split = options.split {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				if split == "down" {
					controller?.splitEditorDown(nil)
				} else {
					controller?.splitEditorRight(nil)
				}
			}
		}
		if let name = options.dropZone {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				let zone: EditorTabDrag.Zone
				switch name {
				case "left":   zone = .left
				case "right":  zone = .right
				case "top":    zone = .top
				case "bottom": zone = .bottom
				default:       zone = .center
				}
				controller?.previewDropZone(zone)
			}
		}
		if options.wordWrap {
			// Set rather than toggled: the setting persists, so toggling made a
			// capture depend on how the previous run left it.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.setWordWrap(true)
			}
		}
		if let query = options.findQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.findInFile(nil)
				controller?.setFindQuery(query)
			}
		}
		if let query = options.searchQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.findInProject(nil)
				controller?.setProjectSearchQuery(query)
			}
		}

		if let delay = options.externalEdit, let path = options.filePath {
			// Written by another process, the way an agent would.
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				let url = URL(fileURLWithPath: path)
				guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
				text = "// added by the agent\n" + text
				try? text.write(to: url, atomically: true, encoding: .utf8)
			}
		}

		if let raw = options.previewMode, let mode = PreviewMode(rawValue: raw) {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.setPreviewMode(mode)
			}
		}

		if let name = options.newFolder {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.createFolderForTesting(named: name)
			}
		}

		if let name = options.newFile {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.createFileForTesting(named: name)
			}
		}

		if options.newScratch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.newScratchForTesting()
			}
		}

		if options.typeBlock {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseReturnIndentForTesting()
			}
		}

		if options.terminalTabKey {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseTerminalTabKeyForTesting()
			}
		}

		if options.printText {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(2.0, options.screenshotDelay - 0.2)) {
				let text = controller?.editorTextForTesting() ?? "no editor"
				print("TEXT ----------")
				for line in text.components(separatedBy: "\n") {
					print("| " + line.replacingOccurrences(of: "\t", with: "→"))
				}
				print("---------------")
			}
		}

		if let spec = options.indentBlock {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				let parts = spec.split(separator: ":").map(String.init)
				guard parts.count == 3, let from = Int(parts[0]), let to = Int(parts[1]) else { return }
				controller?.exerciseIndentForTesting(from: from, to: to, outdent: parts[2] == "out")
			}
		}

		if !options.optionKeys.isEmpty {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				for pair in options.optionKeys {
					let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
					guard parts.count == 2 else { continue }
					let sent = controller?.optionKeyForTesting(bare: parts[0], composed: parts[1])
					print("OPTIONKEY ⌥\(parts[0]) → \(sent ?? "no window") "
						+ "(bytes: \(Array((sent ?? "").utf8)))")
				}
			}
		}

		if let text = options.commitBody {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("COMMITBODY \(controller?.typeInCommitBodyForTesting(text) ?? "no window")")
				fflush(stdout)
				if options.isScreenshotRun { return }
				exit(0)
			}
		}

		if let frames = options.burstFrames {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				let sent = controller?.burstForTesting(frames: frames) ?? -1
				// A second later: long enough for the backlog to drain and for
				// the picture at the end of it to be drawn.
				DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
					print("BURST frames=\(sent) draws=\(TerminalView.drawCountForTesting)")
					fflush(stdout)
					if options.isScreenshotRun { return }
					exit(0)
				}
			}
		}

		if options.tabMenu {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				for over in [true, false] {
					let titles = controller?.tabMenuTitlesForTesting(overTab: over) ?? []
					print("TABMENU \(over ? "tab" : "empty"): \(titles.joined(separator: " | "))")
				}
				print("LAYOUT \(controller?.layoutReportForTesting() ?? "no window")")
				print("GLOBALSCRATCH \(controller?.globalScratchDirectoryForTesting() ?? "no window")")
				fflush(stdout)
				if options.isScreenshotRun { return }
				exit(0)
			}
		}

		if options.clickBelowLastLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("CLICKBELOW \(controller?.clickBelowLastLineForTesting() ?? "no window")")
				fflush(stdout)
				if options.isScreenshotRun { return }
				exit(0)
			}
		}

		if let spec = options.deadKeys {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				let presses = spec.split(separator: ",").compactMap { part -> (code: UInt16, shift: Bool)? in
					let shift = part.hasSuffix("s")
					guard let code = UInt16(shift ? part.dropLast() : part) else { return nil }
					return (code, shift)
				}
				let report = controller?.deadKeyForTesting(presses: presses)
				print("DEADKEY \(report ?? "no window")")
				// Piped output is held until the process ends, and a test that
				// is killed on a timeout takes the answer with it.
				fflush(stdout)
				// Unless a picture is being taken of what it left on screen.
				if options.isScreenshotRun { return }
				exit(0)
			}
		}

		if let path = options.toolbarImage {
			DebugToolbarPreview.write(to: path, location: options.toolbarLocation)
			print("TOOLBAR: \(path)")
			exit(0)
		}

		if let line = options.editBreakpointLine {
			// The sheet itself, for a capture run: it is drawn by hand and a
			// hand-drawn thing cannot be checked by reading it.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.editBreakpointForTesting(line: line)
			}
		}

		if let condition = options.breakpointCondition, let line = options.breakpointLine {
			// Before anything is running, which is when conditions are really
			// set: while writing the code, not while stopped in it.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
				controller?.setBreakpointConditionForTesting(line: line, condition: condition)
			}
		}

		if let spec = options.definitionAt {
			let parts = spec.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				guard parts.count == 2 else { return }
				controller?.exerciseGoToDefinitionForTesting(line: parts[0] - 1, character: parts[1])
			}
		}

		if let spec = options.usagesAt {
			let parts = spec.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				guard parts.count == 2 else { return }
				controller?.shouldDockUsagesForTesting = options.dockUsages
				controller?.exerciseFindUsagesForTesting(line: parts[0] - 1, character: parts[1])
			}
		}

		if let query = options.symbolQuery {
			// After the language server has had time to index.
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				controller?.exerciseSymbolPaletteForTesting(query, project: options.symbolProject)
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

		if options.debugConsole {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1, options.screenshotDelay - 1)) {
				controller?.showDebugConsoleForTesting()
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
				controller?.closeTabsForTesting(
					String(parts.first ?? "close"), at: Int(parts.last ?? "0") ?? 0
				)
			}
		}

		if let name = options.launchConfiguration {
			controller?.selectConfigurationForTesting(named: name)
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
				controller?.echoDebugOutputForTesting()
				if options.launchRun { controller?.runSelected(nil) }
				if options.launchDebug { controller?.debugSelected(nil) }
				if options.launchMenu { controller?.showConfigurationMenuForTesting() }
				if options.launchEditor { controller?.editConfigurationForTesting() }
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
				controller?.inspectDebugStateForTesting()
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
					controller?.reportDebugStepForTesting(step: index)
				}
			}
		}

		if options.undoTree {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseUndoTreeForTesting()
			}
		}

		if let typed = options.completeText {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseCompletionForTesting(typing: typed)
			}
		}

		if options.wordNavigation {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseWordNavigationForTesting()
			}
		}

		if options.fakeDiagnostics {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.injectDiagnosticsForTesting()
			}
		}

		if let wait = options.lspWait {
			DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
				controller?.reportDiagnosticsForTesting()
			}
		}

		if let row = options.historyCommit {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.showSidebarTool(.history)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.selectHistoryForTesting(commit: row, file: 0)
			}
		}

		if let search = options.scratchSearch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.showSidebarTool(.scratches)
				controller?.searchScratchesForTesting(search)
				if options.openScratch { controller?.openFirstScratchForTesting() }
			}
		}

		if let line = options.runLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.invokeForTesting(line: line, debug: false)
			}
		}

		if let line = options.debugLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.invokeForTesting(line: line, debug: true)
			}
		}

		if let tool = options.sidebarTool {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				switch tool {
				case "changes":   controller?.showSidebarTool(.changes)
				case "branches":  controller?.showSidebarTool(.branches)
				case "structure": controller?.showSidebarTool(.structure)
				case "history":   controller?.showSidebarTool(.history)
				case "scratches": controller?.showSidebarTool(.scratches)
				default:          controller?.showSidebarTool(.project)
				}
			}
		}

		if options.showChanges {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.toggleChanges(nil)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
				controller?.selectFirstChangeForTesting()
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
				controller?.selectDiffHunkForTesting(0)
			}
		}

		if options.reportChart {
			let chart = MainWindowController.bundledChart
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
				controller?.reportToolbarForTesting()
			}
		}

		if let line = options.saveGutterLine, let path = options.filePath {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.saveGutterConfigurationForTesting(
					file: URL(fileURLWithPath: path), line: line
				)
			}
		}

		if let goal = options.chooseMakeRun {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				controller?.chooseMakeRunForTesting(goal)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.describeRunTargetForTesting()
			}
		}

		if let goal = options.makeGoal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.runMakeGoalForTesting(goal, debug: options.makeDebug)
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

		if options.highlightPills {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, options.screenshotDelay - 1)) {
				controller?.highlightPillsForTesting()
			}
		}

		if let filter = options.attachFilter {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1, options.screenshotDelay - 1.5)) {
				controller?.showAttachPickerForTesting(filter: filter)
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
			DispatchQueue.main.asyncAfter(deadline: .now() + max(1, options.screenshotDelay - 1.5)) {
				controller?.treeStepsForTesting(steps)
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
				controller?.disableBreakpointForTesting(line: line)
			}
		}

		if let move = options.dragTmuxTab {
			let parts = move.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				guard parts.count == 2 else { return }
				controller?.dragTmuxTabForTesting(from: parts[0], to: parts[1])
			}
		}

		if options.addTmuxWindow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				let before = controller?.paneCountForTesting ?? 0
				controller?.addTmuxWindowForTesting()
				// The one thing this button must never do is add a pane here.
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					let after = controller?.paneCountForTesting ?? 0
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
					controller?.reportServerBannerForTesting()
				} else {
					controller?.pressServerBannerForTesting(action)
				}
			}
		}

		if let index = options.closeTmuxTab {
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				controller?.closeTmuxTabForTesting(index)
			}
		}

		if let delay = options.addTerminalTabAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				let before = controller?.paneCountForTesting ?? 0
				controller?.addTerminalTabForTesting()
				// The panel's own + adds a pane: its strip holds the panel's own
				// tabs, and tmux's windows have the + on the strip below. The
				// count goes up by one here and stays put for --tmux-add.
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
					print("PANELADD: panes \(before) -> \(controller?.paneCountForTesting ?? 0)")
				}
			}
		}

		if let spec = options.clickPanelTab {
			let parts = spec.split(separator: "@")
			let index = Int(parts.first ?? "0") ?? 0
			let at = parts.count > 1 ? Double(parts[1]) ?? 4.0 : 4.0
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("PANEL \(controller?.clickPanelTabForTesting(index) ?? "no window")")
			}
		}

		if let delay = options.closeTerminals {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				controller?.closeTerminalTabsForTesting()
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
				controller?.measureTypingForTesting(presses: presses, interval: 0.12)
			}
		}

		if let branch = options.pushBranch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				controller?.pushBranchForTesting(branch)
			}
		}

		if let row = options.branchMenuRow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.branchMenuForTesting(row: row)
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
				controller?.tmuxMenuForTesting(hovers: hovers)
			}
		}

		if let row = options.collapseRow {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.collapseHistoryRowForTesting(row)
			}
		}

		if let path = options.sidebarShot {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(2, options.screenshotDelay - 1)) {
				controller?.snapshotSidebarForTesting(to: path)
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

		if options.reportsTerminalGeometry {
			for seconds in [3.0, 5.0, 7.0, 9.0] {
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
					print("GEOM \(Int(seconds))s: \(controller?.terminalGeometryForTesting() ?? "-")")
				}
			}
		}

		if options.reportsTerminalDirectory {
			for seconds in [3.0, 5.0, 7.0, 9.0] {
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
					let where_ = controller?.terminalDirectoryForTesting()
					print("CWD \(Int(seconds))s: \(where_?.path ?? "unknown")")
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
				controller?.toggleBreakpointForTesting(line: line)
			}
		}

		for delay in options.breakpointReports {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				print("BREAKPOINTS at \(delay)s:")
				print(controller?.breakpointReportForTesting() ?? "no window")
			}
		}

		if options.sidebarCycle {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.showSidebarTool(.changes)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.showSidebarTool(.project)
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
				controller?.openForTesting(URL(fileURLWithPath: second))
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
				controller?.tearOffForTesting(index: 1, at: NSPoint(x: 300, y: 600))
				self.reportWindowsForTesting("torn off")
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
				self.dragTornOffTabBackForTesting(into: controller)
				self.reportWindowsForTesting("dragged back")
			}
		}

		if options.followTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.toggleFollowTerminal(nil)
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

		if options.openTerminal {
			controller?.toggleTerminal(nil)
			if let input = options.terminalInput {
				// Give the shell time to print its prompt before typing at it.
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
					controller?.sendToTerminal(input + "\n")
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
			let rows = SettingsSections.all.first { $0.title == section }?.rows() ?? []
			for line in SettingsPaneController.describe(rows) { print("SETTING \(line)") }
			exit(0)
		}

		if options.openSettings {
			controller?.settingsSectionForTesting = options.settingsSection
			controller?.showSettingsPage(nil)
		}

		if let path = options.screenshotPath {
			scheduleScreenshot(
				path: path,
				delay: options.screenshotDelay,
				controller: controller,
				window: nil
			)
		}
	}

	/// Captures the window after async work (git status, parsing, folds) settles,
	/// then exits with a status reflecting whether the file was written.
	private func scheduleScreenshot(
		path: String,
		delay: TimeInterval,
		controller: MainWindowController?,
		window explicitWindow: NSWindow? = nil
	) {
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
			guard let window = explicitWindow ?? controller?.window ?? NSApp.windows.first else {
				FileHandle.standardError.write(Data("no window to capture\n".utf8))
				exit(2)
			}
			// Which window this actually is. A capture that photographs the
			// wrong project is silent otherwise, and one did for an afternoon:
			// the window followed a restored terminal into another checkout.
			let title: String = window.title
			let project: String = controller?.project?.root.lastPathComponent ?? "none"
			let line = "captured \(title) (project \(project))\n"
			FileHandle.standardError.write(Data(line.utf8))
			let ok = WindowCapture.write(window: window, to: path)
			exit(ok ? 0 : 3)
		}
	}

	// MARK: - Testing

	private func reportWindowsForTesting(_ stage: String) {
		let described = windowControllers.map { controller in
			"\(controller.isTornOff ? "torn" : "main")"
				+ "(tabs=\(controller.tabCountForTesting)"
				+ ",frame=\(controller.window?.frame ?? .zero))"
		}
		print("TEAROFF \(stage): windows=\(windowControllers.count) \(described.joined(separator: " "))")
	}

	/// Drops the torn-off window's tab back onto the original window's strip,
	/// along the same path a drag between windows takes.
	private func dragTornOffTabBackForTesting(into target: MainWindowController?) {
		guard let target,
		      let torn = windowControllers.first(where: { $0.isTornOff }),
		      let groupID = torn.activeGroupIDForTesting
		else { return }
		target.dropForTesting(
			payload: EditorTabDrag.Payload(groupID: groupID, index: 0, path: ""),
			at: 0
		)
	}

	public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}

	/// ⌘, opens the settings in the window somebody is working in.
	@objc func showSettings(_ sender: Any?) {
		if let controller = frontmostController {
			controller.showSettingsPage(sender)
			controller.showWindow(nil)
			return
		}
		// No window to put a page in — the settings still have to be reachable.
		SettingsWindowController.shared.show()
	}

	/// Flushes pending edits when the app goes to the background, so switching to
	/// a terminal always finds the file on disk current.
	public func applicationDidResignActive(_ notification: Notification) {
		guard Settings.shared.saveOnFocusLoss else { return }
		for controller in windowControllers {
			controller.autoSaveAll()
		}
	}

	public func applicationWillTerminate(_ notification: Notification) {
		for controller in windowControllers {
			controller.autoSaveAll()
			controller.rememberOpenEditors()
		}
	}

	public func application(_ application: NSApplication, open urls: [URL]) {
		for url in urls {
			if url.hasDirectoryPath {
				open(projectAt: url)
				continue
			}
			// A file: the project is whatever encloses it, and the file itself
			// is what somebody wanted to look at.
			let controller = open(projectAt: Project.root(containing: url))
			controller.openForTesting(url)
		}
	}

	// MARK: - Opening projects

	/// Opens a project, in this window or another.
	///
	/// - `from`: the window the choice was made in. Unless the setting says
	///   otherwise, that window changes project rather than a second one
	///   appearing — the window is where you were working, and a new one for
	///   the same task is a window to close later.
	/// Another window, on whatever the front one has open.
	///
	/// The same project rather than an empty window: a second window is
	/// nearly always wanted for the work already in progress, and the project
	/// switcher is one click away for the other case.
	@objc func newWindow(_ sender: Any?) {
		let controller = makeWindow()
		if let project = frontmostController?.project {
			controller.load(project: Project(root: project.root))
		}
		controller.showWindow(nil)
	}

	/// The window a menu command belongs to.
	private var frontmostController: MainWindowController? {
		if let key = NSApp.keyWindow?.windowController as? MainWindowController { return key }
		return windowControllers.first { !$0.isTornOff }
	}

	@discardableResult
	func open(projectAt url: URL, from source: MainWindowController? = nil) -> MainWindowController {
		// Focus an existing window rather than opening the same project twice.
		// Torn-off windows are skipped: opening a project should raise the window
		// it was opened in, not one someone happened to drag a tab into.
		if let existing = windowControllers.first(where: {
			!$0.isTornOff && $0.project?.root.standardizedFileURL == url.standardizedFileURL
		}) {
			existing.showWindow(nil)
			return existing
		}

		// A torn-off window holds one file on purpose; switching a project in
		// it would take that away.
		let reusable = source ?? windowControllers.first { !$0.isTornOff }
		if !Settings.shared.opensProjectsInNewWindow,
		   let target = reusable, !target.isTornOff {
			// Through the switch rather than a bare load: the window keeps what
			// each project had open, and leaving the last project's files in
			// the tab bar is confusing — they are not this project's files.
			target.switchProject(to: url)
			target.showWindow(nil)
			RecentProjects.shared.record(url: url)
			return target
		}

		let controller = makeWindow()
		controller.switchProject(to: url)
		controller.showWindow(nil)
		RecentProjects.shared.record(url: url)
		return controller
	}

	private func makeWindow() -> MainWindowController {
		let controller = MainWindowController()
		controller.onClose = { [weak self, weak controller] in
			guard let self, let controller else { return }
			self.windowControllers.removeAll { $0 === controller }
		}
		controller.onTearOffTab = { [weak self] tab, screenPoint, source in
			self?.tearOff(tab: tab, at: screenPoint, from: source)
		}
		windowControllers.append(controller)
		return controller
	}

	/// Opens a window for a tab dragged out of `source`.
	///
	/// It lands where it was dropped, which is how it reaches a second display:
	/// the screen is the one under the pointer, not the one the tab came from.
	private func tearOff(tab: EditorViewController.Tab, at screenPoint: NSPoint, from source: MainWindowController) {
		guard let project = source.project else { return }

		let controller = makeWindow()
		controller.markAsTornOff()
		controller.load(project: project)

		let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) }
			?? source.window?.screen
			?? NSScreen.main
		if let visible = screen?.visibleFrame {
			let size = source.window?.frame.size ?? NSSize(width: 1100, height: 750)
			controller.window?.setFrame(
				TearOff.windowFrame(droppedAt: screenPoint, size: size, visibleFrame: visible),
				display: true
			)
		}

		controller.showWindow(nil)
		controller.adopt(tab)
	}

	var openProjectRoots: [URL] {
		windowControllers.compactMap { $0.project?.root }
	}

	@objc func openProjectPanel(_ sender: Any?) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Open"
		panel.message = "Choose a project directory"

		guard panel.runModal() == .OK, let url = panel.url else {
			// Nothing open and nothing chosen — there is no useful state to sit in.
			if windowControllers.isEmpty { NSApp.terminate(nil) }
			return
		}
		open(projectAt: url)
	}

	// MARK: - Menu

	private func buildMenu() {
		let mainMenu = NSMenu()

		let appMenuItem = NSMenuItem()
		let appMenu = NSMenu()
		// Ours rather than the standard panel, which shows the version but not
		// which build it came from — the one thing worth knowing when the
		// question is whether an install took.
		appMenu.addItem(
			withTitle: "About ideai",
			action: #selector(showAbout(_:)),
			keyEquivalent: ""
		)
		appMenu.addItem(.separator())
		let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
		settingsItem.target = self
		appMenu.addItem(settingsItem)
		appMenu.addItem(.separator())
		appMenu.addItem(withTitle: "Hide ideai", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		appMenu.addItem(withTitle: "Quit ideai", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		appMenuItem.submenu = appMenu
		mainMenu.addItem(appMenuItem)

		let fileMenuItem = NSMenuItem()
		let fileMenu = NSMenu(title: "File")
		// A second window on the same project: two files side by side, or a
		// terminal in one and the code in the other.
		let newWindow = NSMenuItem(
			title: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n"
		)
		newWindow.target = self
		fileMenu.addItem(newWindow)

		let openItem = NSMenuItem(title: "Open…", action: #selector(openProjectPanel(_:)), keyEquivalent: "o")
		openItem.target = self
		fileMenu.addItem(openItem)

		// The shortcut the capsule advertises. In the menu rather than on the
		// view, so it works wherever the keyboard focus happens to be and can be
		// found by somebody who never reads a titlebar.
		//
		// ⇧⌘P, where a decade of VS Code has taught everybody's hands to reach
		// for a palette. Presentation Mode had it and moved to ⌃⌘P: that is
		// wanted a few times a year and this a few times an hour.
		//
		// Not plain ⌘K, which clears the terminal as it does in Terminal and
		// every console — a menu's key equivalent is matched before any view
		// sees the key, so taking it would have quietly stopped that working.
		let switcherItem = NSMenuItem(
			title: "Go to Anything…",
			action: #selector(MainWindowController.showProjectSwitcher(_:)),
			keyEquivalent: "p"
		)
		switcherItem.keyEquivalentModifierMask = [.command, .shift]
		fileMenu.addItem(switcherItem)
		let scratchItem = NSMenuItem(
			title: "New Scratch File",
			action: #selector(MainWindowController.newScratchFile(_:)),
			keyEquivalent: "n"
		)
		scratchItem.keyEquivalentModifierMask = [.command, .shift]
		fileMenu.addItem(scratchItem)
		fileMenu.addItem(.separator())
		fileMenu.addItem(withTitle: "Save", action: #selector(MainWindowController.saveDocument(_:)), keyEquivalent: "s")
		fileMenu.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeTab(_:)), keyEquivalent: "w")
		let closeWindow = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
		closeWindow.keyEquivalentModifierMask = [.command, .shift]
		fileMenu.addItem(closeWindow)
		fileMenuItem.submenu = fileMenu
		mainMenu.addItem(fileMenuItem)

		let editMenuItem = NSMenuItem()
		let editMenu = NSMenu(title: "Edit")
		editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
		let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
		redo.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(redo)
		let localHistory = NSMenuItem(
			title: "File History…",
			action: #selector(MainWindowController.showFileHistory(_:)),
			keyEquivalent: "z"
		)
		localHistory.keyEquivalentModifierMask = [.command, .option]
		editMenu.addItem(localHistory)
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		editMenu.addItem(.separator())
		let symbolInFile = NSMenuItem(
			title: "Go to Declaration\u{2026}",
			action: #selector(MainWindowController.goToSymbolInFile(_:)),
			keyEquivalent: "o"
		)
		symbolInFile.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(symbolInFile)

		let symbolInProject = NSMenuItem(
			title: "Go to Symbol\u{2026}",
			action: #selector(MainWindowController.goToSymbolInProject(_:)),
			keyEquivalent: "o"
		)
		symbolInProject.keyEquivalentModifierMask = [.command, .option]
		editMenu.addItem(symbolInProject)

		// IDEA's shortcuts on macOS, since that is where the muscle memory
		// comes from.
		let back = NSMenuItem(
			title: "Back",
			action: #selector(MainWindowController.navigateBack(_:)),
			keyEquivalent: "["
		)
		back.keyEquivalentModifierMask = [.command]
		editMenu.addItem(back)

		let forward = NSMenuItem(
			title: "Forward",
			action: #selector(MainWindowController.navigateForward(_:)),
			keyEquivalent: "]"
		)
		forward.keyEquivalentModifierMask = [.command]
		editMenu.addItem(forward)
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "Find…", action: #selector(MainWindowController.findInFile(_:)), keyEquivalent: "f")
		let findInProject = NSMenuItem(
			title: "Find in Project…",
			action: #selector(MainWindowController.findInProject(_:)),
			keyEquivalent: "f"
		)
		findInProject.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(findInProject)
		editMenu.addItem(withTitle: "Find Next", action: #selector(MainWindowController.findNext(_:)), keyEquivalent: "g")
		let findPrevious = NSMenuItem(
			title: "Find Previous",
			action: #selector(MainWindowController.findPrevious(_:)),
			keyEquivalent: "g"
		)
		findPrevious.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(findPrevious)
		editMenuItem.submenu = editMenu
		mainMenu.addItem(editMenuItem)

		let runMenuItem = NSMenuItem()
		let runMenu = NSMenu(title: "Run")
		let goRun = NSMenuItem(title: "Go Run", action: #selector(MainWindowController.goRun(_:)), keyEquivalent: "r")
		goRun.keyEquivalentModifierMask = [.command, .control]
		runMenu.addItem(goRun)
		runMenu.addItem(withTitle: "Go Build", action: #selector(MainWindowController.goBuild(_:)), keyEquivalent: "")
		let goTest = NSMenuItem(title: "Go Test", action: #selector(MainWindowController.goTest(_:)), keyEquivalent: "t")
		goTest.keyEquivalentModifierMask = [.command, .control]
		runMenu.addItem(goTest)
		runMenu.addItem(.separator())
		let goDebug = NSMenuItem(title: "Go Debug (Delve)", action: #selector(MainWindowController.goDebug(_:)), keyEquivalent: "d")
		goDebug.keyEquivalentModifierMask = [.command, .control]
		runMenu.addItem(goDebug)
		let runItem = NSMenuItem(
			title: "Run…",
			action: #selector(MainWindowController.showRunConfigurations(_:)),
			keyEquivalent: "r"
		)
		runItem.keyEquivalentModifierMask = [.control]
		runMenu.addItem(runItem)
		let runSelected = NSMenuItem(
			title: "Run",
			action: #selector(MainWindowController.runSelected(_:)),
			keyEquivalent: "r"
		)
		runSelected.keyEquivalentModifierMask = [.control]
		runMenu.addItem(runSelected)

		let debugSelected = NSMenuItem(
			title: "Debug",
			action: #selector(MainWindowController.debugSelected(_:)),
			keyEquivalent: "d"
		)
		debugSelected.keyEquivalentModifierMask = [.control]
		runMenu.addItem(debugSelected)
		let fromMake = NSMenuItem(
			title: "New from Make goal\u{2026}",
			action: #selector(MainWindowController.newFromMakeGoal(_:)),
			keyEquivalent: ""
		)
		runMenu.addItem(fromMake)
		runMenu.addItem(.separator())

		let profiler = NSMenuItem(
			title: "Profile\u{2026}",
			action: #selector(MainWindowController.showProfiler(_:)),
			keyEquivalent: "p"
		)
		profiler.keyEquivalentModifierMask = [.control, .shift]
		runMenu.addItem(profiler)
		runMenu.addItem(.separator())

		let debugExecutable = NSMenuItem(
			title: "Debug Executable\u{2026}",
			action: #selector(MainWindowController.debugExecutable(_:)),
			keyEquivalent: ""
		)
		runMenu.addItem(debugExecutable)
		let attachItem = NSMenuItem(
			title: "Attach to Process\u{2026}",
			action: #selector(MainWindowController.attachToProcess(_:)),
			keyEquivalent: ""
		)
		runMenu.addItem(attachItem)
		runMenu.addItem(.separator())

		// The function keys IDEA and Xcode both use, so the fingers that
		// already know them do not have to learn anything.
		let resume = NSMenuItem(
			title: "Continue", action: #selector(MainWindowController.debugContinue(_:)), keyEquivalent: "\u{F70C}"
		)
		resume.keyEquivalentModifierMask = []
		runMenu.addItem(resume)

		let pause = NSMenuItem(
			title: "Pause", action: #selector(MainWindowController.debugPause(_:)), keyEquivalent: ""
		)
		runMenu.addItem(pause)

		let stepOver = NSMenuItem(
			title: "Step Over", action: #selector(MainWindowController.debugStepOver(_:)), keyEquivalent: "\u{F70B}"
		)
		stepOver.keyEquivalentModifierMask = []
		runMenu.addItem(stepOver)

		let stepInto = NSMenuItem(
			title: "Step Into", action: #selector(MainWindowController.debugStepInto(_:)), keyEquivalent: "\u{F70A}"
		)
		stepInto.keyEquivalentModifierMask = []
		runMenu.addItem(stepInto)

		let stepOut = NSMenuItem(
			title: "Step Out", action: #selector(MainWindowController.debugStepOut(_:)), keyEquivalent: "\u{F70B}"
		)
		stepOut.keyEquivalentModifierMask = [.shift]
		runMenu.addItem(stepOut)

		let stopDebugging = NSMenuItem(
			title: "Stop", action: #selector(MainWindowController.debugStop(_:)), keyEquivalent: "\u{F705}"
		)
		stopDebugging.keyEquivalentModifierMask = [.command]
		runMenu.addItem(stopDebugging)

		runMenu.addItem(.separator())
		runMenu.addItem(withTitle: "Go Trace", action: #selector(MainWindowController.goTrace(_:)), keyEquivalent: "")
		runMenu.addItem(withTitle: "Go CPU Profile", action: #selector(MainWindowController.goProfile(_:)), keyEquivalent: "")
		runMenuItem.submenu = runMenu
		mainMenu.addItem(runMenuItem)

		// Agent actions get their own menu: this is the part of the app that is
		// meant to grow.
		let agentMenuItem = NSMenuItem()
		let agentMenu = NSMenu(title: "Agent")
		let reviewItem = NSMenuItem(
			title: "Review Branch…",
			action: #selector(MainWindowController.reviewBranch(_:)),
			keyEquivalent: "r"
		)
		reviewItem.keyEquivalentModifierMask = [.command, .shift]
		agentMenu.addItem(reviewItem)

		let uncommittedItem = NSMenuItem(
			title: "Review Uncommitted Changes…",
			action: #selector(MainWindowController.reviewUncommittedChanges(_:)),
			keyEquivalent: "u"
		)
		uncommittedItem.keyEquivalentModifierMask = [.command, .shift]
		agentMenu.addItem(uncommittedItem)
		agentMenuItem.submenu = agentMenu
		mainMenu.addItem(agentMenuItem)

		let viewMenuItem = NSMenuItem()
		let viewMenu = NSMenu(title: "View")
		viewMenu.addItem(withTitle: "Project", action: #selector(MainWindowController.showProjectView(_:)), keyEquivalent: "1")
		viewMenu.addItem(withTitle: "Commit", action: #selector(MainWindowController.toggleChanges(_:)), keyEquivalent: "2")
		viewMenu.addItem(withTitle: "Branches", action: #selector(MainWindowController.toggleBranchesView(_:)), keyEquivalent: "3")
		viewMenu.addItem(withTitle: "Structure", action: #selector(MainWindowController.toggleStructureView(_:)), keyEquivalent: "4")
		viewMenu.addItem(withTitle: "Scratches", action: #selector(MainWindowController.toggleScratchesView(_:)), keyEquivalent: "5")
		viewMenu.addItem(withTitle: "History", action: #selector(MainWindowController.toggleHistoryView(_:)), keyEquivalent: "6")
		viewMenu.addItem(.separator())
		let terminalItem = NSMenuItem(title: "Toggle Terminal", action: #selector(MainWindowController.toggleTerminal(_:)), keyEquivalent: "j")
		viewMenu.addItem(terminalItem)
		let newTerminalItem = NSMenuItem(title: "New Terminal", action: #selector(MainWindowController.newTerminal(_:)), keyEquivalent: "t")
		newTerminalItem.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(newTerminalItem)

		// The same thing on ⌘T, but only while the terminal has the keyboard —
		// where that is the key everybody's fingers already reach for.
		// Not written against a class: the same command has to reach the main
		// window's panel and a terminal window torn out of it, and a selector
		// typed as `MainWindowController.newTerminalTab` reaches only the
		// first — which is why a torn-off window's menu items were greyed out.
		// Sent to nil, it goes down the responder chain to whichever window
		// controller answers.
		let terminalTabItem = NSMenuItem(
			title: "New Terminal Tab",
			action: Selector(("newTerminalTab:")),
			keyEquivalent: "t"
		)
		terminalTabItem.keyEquivalentModifierMask = [.command]
		viewMenu.addItem(terminalTabItem)
		let followTerminal = NSMenuItem(
			title: "Follow Terminal Project",
			action: #selector(MainWindowController.toggleFollowTerminal(_:)),
			keyEquivalent: "f"
		)
		followTerminal.keyEquivalentModifierMask = [.command, .control]
		viewMenu.addItem(followTerminal)
		let maximizeTerminal = NSMenuItem(
			title: "Maximize Terminal",
			action: #selector(MainWindowController.togglePanelMaximized(_:)),
			keyEquivalent: "j"
		)
		maximizeTerminal.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(maximizeTerminal)
		let foldAll = NSMenuItem(title: "Collapse All", action: #selector(MainWindowController.collapseAllFolds(_:)), keyEquivalent: "-")
		foldAll.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(foldAll)
		let unfoldAll = NSMenuItem(title: "Expand All", action: #selector(MainWindowController.expandAllFolds(_:)), keyEquivalent: "+")
		unfoldAll.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(unfoldAll)
		viewMenu.addItem(.separator())
		// ⌘+ is reported as "=" on most layouts; both are registered so the key
		// works with and without shift.
		let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
		viewMenu.addItem(zoomIn)
		let zoomInAlt = NSMenuItem(title: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "=")
		zoomInAlt.isAlternate = true
		zoomInAlt.isHidden = true
		viewMenu.addItem(zoomInAlt)
		viewMenu.addItem(withTitle: "Zoom Out", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
		viewMenu.addItem(withTitle: "Actual Size", action: #selector(MainWindowController.resetZoom(_:)), keyEquivalent: "0")

		// Its own zoom and its own palette, so a talk can be set up once and
		// left alone — and so coming back to the desk afterwards is a menu item
		// rather than finding the old size by hand.
		let presentation = NSMenuItem(
			title: "Presentation Mode",
			action: #selector(MainWindowController.togglePresentationMode(_:)),
			keyEquivalent: "p"
		)
		// Moved off ⇧⌘P, which the palette took: that is where VS Code put its
		// own, and this is wanted once a quarter.
		presentation.keyEquivalentModifierMask = [.command, .control]
		viewMenu.addItem(presentation)
		viewMenu.addItem(.separator())
		let blameItem = NSMenuItem(
			title: "Toggle Blame",
			action: #selector(MainWindowController.toggleBlame(_:)),
			keyEquivalent: "b"
		)
		blameItem.keyEquivalentModifierMask = [.command, .option]
		viewMenu.addItem(blameItem)

		let wrapItem = NSMenuItem(
			title: "Toggle Word Wrap",
			action: #selector(MainWindowController.toggleWordWrap(_:)),
			keyEquivalent: "z"
		)
		wrapItem.keyEquivalentModifierMask = [.command, .option]
		viewMenu.addItem(wrapItem)
		let preview = NSMenuItem(
			title: "Toggle Markdown Preview",
			action: #selector(MainWindowController.toggleMarkdownPreview(_:)),
			keyEquivalent: "v"
		)
		preview.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(preview)
		viewMenu.addItem(.separator())
		let splitRight = NSMenuItem(
			title: "Split Right",
			action: #selector(MainWindowController.splitEditorRight(_:)),
			keyEquivalent: "\\"
		)
		viewMenu.addItem(splitRight)
		let splitDown = NSMenuItem(
			title: "Split Down",
			action: #selector(MainWindowController.splitEditorDown(_:)),
			keyEquivalent: "\\"
		)
		splitDown.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(splitDown)
		viewMenu.addItem(.separator())
		let nextTab = NSMenuItem(title: "Next Tab", action: #selector(MainWindowController.selectNextTab(_:)), keyEquivalent: "]")
		nextTab.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(nextTab)
		let previousTab = NSMenuItem(title: "Previous Tab", action: #selector(MainWindowController.selectPreviousTab(_:)), keyEquivalent: "[")
		previousTab.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(previousTab)
		viewMenuItem.submenu = viewMenu
		mainMenu.addItem(viewMenuItem)

		NSApp.mainMenu = mainMenu
	}
}

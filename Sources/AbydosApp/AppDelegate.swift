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

	/// Writes down what an uncaught exception was, before the process goes.
	///
	/// A crash report symbolicates a release build by nearest exported symbol,
	/// which for a Swift binary is frequently a function that has nothing to do
	/// with the crash: a report of a nil in a text attribute pointed at a menu
	/// action fifty lines from any drawing. The exception itself knows better —
	/// its own stack is captured where it was raised — so it is written to a log
	/// that survives the process.
	private static func recordUncaughtExceptions() {
		NSSetUncaughtExceptionHandler { exception in
			let lines = [
				"uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason given")",
				// What was on screen a moment ago, which the stack cannot say.
				// The one crash that keeps coming back is raised inside CoreText
				// on a value nothing in this app can be seen to have produced,
				// and the row being drawn plus the font it was drawn with is
				// what nobody has been able to read off a report yet.
				"    \(LastDrawn.description)",
				// **The frames below are approximate and this line is what
				// makes them exact later.** `callStackSymbols` resolves through
				// `dladdr`, which sees exported symbols only — for an optimised
				// Swift binary that is frequently a function fifty lines from
				// the crash, which is how 0400's report came to name
				// `showConfigurationMenu` and `stopDevPodForwards`, both wrong.
				// The real site came from the breadcrumb above, not from the
				// stack.
				//
				// Every address below is `load + offset`; with the build's UUID
				// and its load address written down, a dSYM kept beside the
				// build turns them into file and line with `atos`. Without these
				// two numbers the addresses in an old log are unusable, because
				// the load address is different every run.
				"    \(AppDelegate.buildDescription)",
				"    \(AppDelegate.imageLocation())",
			] + exception.callStackSymbols.map { "    \($0)" }
			DiagnosticLog.write(lines.joined(separator: "\n"), to: "crash")
			// And take the tools with it. This is the exit that runs no
			// `deinit` and no `applicationWillTerminate`, so it is the one that
			// leaves containers running until somebody finds them by hand.
			//
			// Both, because they are two different things: the process is
			// signalled, and the container is removed by name. Killing the
			// `docker run` leaves the container up — `--rm` never fires — which
			// is why ending the processes alone was not enough.
			ToolProcesses.shared.terminateAll()
			ToolContainers.shared.removeAll()
		}
	}

	/// Where this binary was loaded and which build it is, in the form `atos`
	/// wants.
	///
	/// Both numbers are needed and neither is guessable after the fact: ASLR
	/// puts the image somewhere different every launch, so an address in
	/// yesterday's log means nothing without the load address that went with it,
	/// and the UUID is what says which dSYM answers for it.
	///
	/// Asked of dyld by image index rather than by taking the address of one of
	/// our own functions: image 0 is the main executable by definition, where a
	/// Swift function value is a pair and its first word is not reliably
	/// something `dladdr` will answer about.
	static func imageLocation() -> String {
		guard let header = _dyld_get_image_header(0) else { return "image: unknown" }
		let slide = _dyld_get_image_vmaddr_slide(0)
		let uuid = imageUUID(at: UnsafeRawPointer(header)) ?? "unknown"
		return String(
			format: "image: loaded at 0x%llx (slide 0x%llx), uuid %@",
			UInt(bitPattern: header), UInt(bitPattern: slide), uuid
		)
	}

	/// The Mach-O UUID of the loaded image, read out of its own load commands.
	private static func imageUUID(at base: UnsafeRawPointer) -> String? {
		let header = base.assumingMemoryBound(to: mach_header_64.self)
		var command = base.advanced(by: MemoryLayout<mach_header_64>.size)
		for _ in 0..<header.pointee.ncmds {
			let load = command.assumingMemoryBound(to: load_command.self)
			if load.pointee.cmd == LC_UUID {
				let entry = command.assumingMemoryBound(to: uuid_command.self)
				return UUID(uuid: entry.pointee.uuid).uuidString
			}
			command = command.advanced(by: Int(load.pointee.cmdsize))
		}
		return nil
	}

	/// Whatever ends this process on purpose takes the tools with it.
	///
	/// `applicationWillTerminate` is not every exit: the command-line modes —
	/// the screenshot capture above all — call `exit` as soon as they have what
	/// they came for, and one of those left a PlantUML server running with
	/// nothing to stop it. `atexit` runs for all of them, and runs nothing twice:
	/// by the time a normal quit gets here there is nothing left registered.
	private static func endToolsOnExit() {
		atexit {
			ToolProcesses.shared.terminateAll()
			ToolContainers.shared.removeAll()
		}
	}

	/// Removes the containers a previous run of this app left behind.
	///
	/// Only ours — everything this app starts is named `abydos-…` — and only
	/// those whose starter is no longer running, so two copies of this app open
	/// at once leave each other's alone.
	///
	/// **Every runtime installed rather than the preferred one**, and that is
	/// 0473. This asked `discover` for one runtime, which honours the preference,
	/// and on a machine with the docker CLI installed and its daemon deliberately
	/// stopped the preference names docker: `docker ps -a` then failed, a listing
	/// that did not succeed was read as "nothing to remove", and every container
	/// actually left behind was in Apple's runtime, which nobody looked at. Six of
	/// them accumulated in a day that way. A leftover is in whichever runtime
	/// started it, and nothing says that is the one anybody would choose today.
	private static func sweepContainersLeftBehind() {
		DispatchQueue.global(qos: .utility).async {
			for runtime in ContainerRuntime.installed() {
				let removed = ToolContainers.shared.sweep(using: runtime)
				guard !removed.isEmpty else { continue }
				// Which runtime is in the line because it is the next question
				// anybody reading it asks, and because a sweep that did not say
				// where it had looked is what hid the fault above for a day. What
				// one of these costs while it is up: on Apple's runtime a container
				// is a virtual machine, and `container ls` reports a gigabyte of
				// memory and four cores for each of ours.
				print("Removed \(removed.count) \(runtime.name) container(s) left by an "
					+ "earlier run: " + removed.joined(separator: ", "))
			}
		}
	}

	public func applicationDidFinishLaunching(_ notification: Notification) {
		// Before anything writes to a pipe, which is nearly the first thing
		// this app does: a shell that has just exited, or a tmux server that
		// has stopped, would otherwise take the whole app with it and leave
		// nothing behind to say why.
		BrokenPipes.ignore()
		Self.recordUncaughtExceptions()
		Self.endToolsOnExit()
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
		// And the `Claude Sessions` root, which is otherwise read once when a
		// project opens: a session that starts, works and ends while somebody
		// watches would change nothing on screen.
		watch.sessionsChanged = { [weak self] slug in
			for controller in self?.windowControllers ?? [] {
				controller.claudeSessionsChanged(slug: slug)
			}
		}
		watch.start()
		claudeWatch = watch

		// What a previous run left running. An app that was killed outright
		// removes nothing on the way out, so the next one to start does it: every
		// container of ours carries the process id that started it, and one whose
		// starter is gone is one nothing will ever come back for. Off the main
		// thread, since it asks a runtime a question and a wedged runtime is
		// precisely the situation this is clearing up after.
		Self.sweepContainersLeftBehind()

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
		// Before any window, because the first pane is built with the window and
		// a seam set after that is a seam the pane never saw.
		if options.engineRefuses { TerminalView.pretendsTheLibraryWillNotStart = true }

		if let theme = options.theme {
			Settings.shared.appearance = theme
			// The terminal follows, which is what it does by default now. A run
			// that wants them apart says so by setting the scheme itself.
			Settings.shared.terminalScheme = Appearance.followsEditor
			Theme.apply()
		}

		MetalProbe.start()
		if let zoom = options.zoom { Settings.shared.uiScale = zoom }

		// **What a driven run opens is decided here, before any of the
		// arrangements written for somebody double-clicking the app.**
		//
		// It used to be the third branch of six, which is why "it opens what it
		// was given, or it fails" could not be read anywhere: the fallbacks came
		// first in the source and the rule was an exception among them. 0522 and
		// 0534 are both what that cost.
		// **Before the window opens**, so the project's first read of its
		// sessions already has it: this stands in for a session that was already
		// running when somebody opened the project. With `@<seconds>` it happens
		// later instead, through the same call the hook's notification makes —
		// which is the only way to drive the redraw, `ClaudeWatch` never
		// subscribing on a run like this one.
		if let id = options.claudeRunning, let path = options.projectPath,
		   options.claudeRunningAfter <= 0 {
			RunningSessions.shared.note([
				"event": "SessionStart", "session": id,
				"cwd": URL(fileURLWithPath: path, isDirectory: true).path,
			])
		}

		let controller: MainWindowController?
		if DrivenRun.isActive {
			controller = openForDrivenRun(options)
		} else if let path = options.projectPath {
			controller = open(projectAt: URL(fileURLWithPath: path, isDirectory: true))
		} else if let file = options.filePaths.first {
			// Files but no project, which used to mean "the project the file is
			// in" only by accident — the fallback below opened whatever was last
			// worked in, and the file went into a window full of somebody else's
			// tabs. The file's own project is what was meant.
			let directory = URL(fileURLWithPath: file).deletingLastPathComponent()
			controller = open(projectAt: ProjectRoot.find(from: directory) ?? directory)
		} else if let last = RecentProjects.shared.entries.first {
			controller = open(projectAt: last.url)
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
		// `writesACapture` rather than the two flags that used to be named here:
		// a picture is drawn from the view hierarchy whichever flag asked for
		// it, and the pair was a list that went out of date the moment a third
		// capture flag was added.
		if options.writesACapture {
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
			DispatchQueue.main.asyncAfter(deadline: .now() + options.switchToAt) {
				let to = self.open(
					projectAt: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
				)
				print("SWITCHED to \(to.project?.root.lastPathComponent ?? "nothing"); "
					+ "\(self.windowControllers.count) window(s)")
				fflush(stdout)
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
				if let keys = options.switcherKeys {
					DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
						for key in keys.split(separator: ",") {
							print("SWITCHER \(key): \(ProjectSwitcherPopover.pressForTesting(String(key)))")
						}
						fflush(stdout)
						if options.writesACapture { return }
						exit(0)
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
		if let position = options.settingsDivider {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.dragSettingsDividerForTesting(to: position)
			}
		}
		if let position = options.editorDivider {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.dragSettingsDividerForTesting(to: position, settings: false)
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
		if let steps = options.findNextSteps {
			// After the query has been typed and the debounced search has run;
			// stepping before there are any matches is a no-op that looks like the
			// verb being broken.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.findNextFromEditorForTesting(steps)
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

		// After the preview has had a moment to draw: the pane's Export uses the
		// text it drew, which is the whole point of exporting from the preview.
		if let raw = options.exportDiagram {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.exportDiagramForTesting(raw)
			}
		}

		// Just before the capture rather than at a moment of its own: a size is
		// only interesting once there is a drawing to be that size, and how long
		// that takes is the whole reason `--delay` is a number somebody passes —
		// a diagram drawn in a container has a container to start first.
		if let raw = options.diagramFit {
			let at = options.isScreenshotRun ? max(3.0, options.screenshotDelay - 1.5) : 8.0
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.setDiagramFitForTesting(raw)
			}
		}

		// The same moment for a picture, and sooner: a picture is a file read
		// off the disk rather than a drawing something else has to make, so
		// there is nothing to wait for but the window.
		if let raw = options.imageFit {
			let at = options.isScreenshotRun ? max(1.2, options.screenshotDelay - 1.0) : 2.0
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.setImageFitForTesting(raw)
			}
		}

		// After the size and before the pan, for the same reason the pan is last:
		// each of the three depends on the one above it.
		if let raw = options.imageZoom {
			let at = options.isScreenshotRun ? max(1.3, options.screenshotDelay - 0.9) : 2.2
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.zoomImageForTesting(raw)
			}
		}

		// After the size, because where a picture can be scrolled to depends on
		// how large it is being drawn.
		if let raw = options.imagePan {
			let at = options.isScreenshotRun ? max(1.4, options.screenshotDelay - 0.8) : 2.4
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.panImageForTesting(raw)
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

		if !options.commentBlocks.isEmpty {
			// A second apart, so each press lands on the text the one before it
			// left rather than on a rope still being reparsed.
			for (step, spec) in options.commentBlocks.enumerated() {
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + Double(step)) {
					controller?.toggleCommentForTesting(spec)
				}
			}
		}

		if options.commentKey {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.commentKeyReportForTesting()
			}
		}

		if let spec = options.snippet {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.exerciseSnippetForTesting(spec)
			}
		}

		if options.menuKeys {
			// After the menu is built and the system has had its chance to move
			// anything: the relocation happens when the menu becomes the
			// application's, and reading a key equivalent before that reports the
			// literal from the source rather than the one somebody will press.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				MenuKeyReport.print()
				if !options.writesACapture { exit(0) }
			}
		}

		if let spec = options.selectLines {
			// Late, so whatever else the run asked for — a terminal, a results list
			// — has already taken the keyboard. The selection is made after it and
			// takes nothing back, which is the state being photographed.
			DispatchQueue.main.asyncAfter(deadline: .now() + max(2.5, options.screenshotDelay - 1.0)) {
				let parts = spec.split(separator: ":").compactMap { Int($0) }
				guard parts.count == 2 else { return }
				controller?.selectLinesForTesting(from: parts[0], to: parts[1])
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
				if options.writesACapture { return }
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
					if options.writesACapture { return }
					exit(0)
				}
			}
		}

		if let steps = options.copyPath {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("COPYPATH \(controller?.copyPathForTesting(steps: steps) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let steps = options.appearanceWalk {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				print("APPEARANCE \(controller?.appearanceWalkForTesting(steps) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if options.listRunConfigurations {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("RUNCONFIGS\n  \(controller?.runConfigurationsForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let query = options.paletteQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("PALETTE \(controller?.paletteCommandsForTesting(query: query) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
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
				if options.writesACapture { return }
				exit(0)
			}
		}

		if options.clickBelowLastLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("CLICKBELOW \(controller?.clickBelowLastLineForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
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
				if options.writesACapture { return }
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

		if options.findAcrossTabs {
			// After `--find` has typed its query and the debounced search has
			// run; stepping before there are matches proves nothing.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.exerciseFindAcrossTabsForTesting()
			}
		}

		if options.dragTab {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.dragTabForTesting()
			}
		}

		if !options.dropFiles.isEmpty {
			// After the window has a project and whatever `--file` asked for is
			// open, or "before" is a report of an empty editor.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.dropFilesForTesting(options.dropFiles)
			}
		}

		if let offer = options.backlogOffer {
			// Before any pane is built, which is what makes the pretence
			// possible at all: the view asks once, when it is made.
			if offer == "missing" { BacklogAbsentView.pretendsTheToolIsMissing = true }
			// After the walk that reads both folders, which happens off the main
			// thread: asked sooner, every project looks like one with nothing.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("OFFER project: \(controller?.project?.root.path ?? "none")")
				print(controller?.backlogOfferReportForTesting() ?? "no window")
				if offer == "openspec" {
					print("OFFER pressed: " + (controller?.pressOpenSpecOfferForTesting() ?? "no window"))
				}
				fflush(stdout)
			}

			// The same pane asked again, for `--backlog-offer watch`: a record
			// of work made while it was up — by the terminal it started, or by
			// somebody in another window — should have replaced the offer with
			// a board, and the pane is not reopened in between.
			if offer == "watch" {
				// Shown, and then read a moment later. Asking is what triggers
				// the re-read — the pane reloads whenever it is shown — and the
				// walk that answers it runs off the main thread, so a report
				// printed in the same breath prints the state before it. That
				// is not a delay somebody waits: it is one dispatch away, and
				// the gap here is generous so the check cannot be flaky.
				DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
					print("OFFER again: "
						+ (controller?.backlogOfferAsItStandsForTesting() ?? "no window"))
					fflush(stdout)
				}
			}
		}

		if let at = options.engineSwitchAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.switchEngineForTesting()
			}
		}

		for at in options.engineReportsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.reportEnginesForTesting()
			}
		}

		if options.unhandledMotions {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.reportUnhandledMotionsForTesting()
			}
		}

		if let branch = options.checkoutBranch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.checkoutBranchForTesting(branch, pressing: options.pressOffer)
			}
		}

		if let asked = options.copyLink {
			// After the file is open and its document is real: a reference is
			// about a tab, and there is none for the first second.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				let parts = asked.split(separator: ":").map(String.init)
				let form = parts.first ?? "reference"
				let lines = (parts.count > 1 ? parts[1] : "1")
					.split(separator: "-").compactMap { Int($0) }
				controller?.copyLinkForTesting(
					form, line: lines.first ?? 1, endLine: lines.count > 1 ? lines[1] : nil
				)
			}
		}

		if let link = options.followLink {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
				controller?.followLinkForTesting(link)
			}
		}

		if let asked = options.codeActionsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + asked.after) {
				controller?.reportCodeActionsForTesting(
					line: asked.line, character: asked.character, take: options.codeActionTake
				)
			}
		}

		if let at = options.openValueAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.openValueForTesting()
			}
		}

		for at in options.diagnosticsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.reportDiagnosticsForTesting(at: at)
			}
		}

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
				print("CARDS:\n\(controller?.cardGeometryForTesting() ?? "no window")")
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
				print("LSPROOT: \(controller?.serverRootReportForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let spec = options.definitionAt {
			let parts = spec.split(separator: ":").compactMap { Int($0) }
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				guard parts.count == 2 else { return }
				controller?.exerciseGoToDefinitionForTesting(line: parts[0] - 1, character: parts[1])
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
				controller?.exerciseFindUsagesForTesting(line: parts[0] - 1, character: parts[1])
			}
			// After the list is there and has said what is in it: the report above
			// runs three seconds behind the request, and a script that pressed ↓
			// before then would be walking an empty table.
			if let steps = options.usagesSteps {
				DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12) + 4) {
					controller?.usagesStepsForTesting(steps)
				}
			}
		}

		if let spec = options.renameAt {
			let halves = spec.split(separator: "=", maxSplits: 1)
			let parts = halves.first.map { $0.split(separator: ":").compactMap { Int($0) } } ?? []
			DispatchQueue.main.asyncAfter(deadline: .now() + (options.lspWait ?? 12)) {
				guard parts.count == 2, halves.count == 2 else { return }
				controller?.exerciseRenameForTesting(
					line: parts[0] - 1, character: parts[1], to: String(halves[1])
				)
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

		if let id = options.claudeRunning, let path = options.projectPath,
		   options.claudeRunningAfter > 0 {
			let cwd = URL(fileURLWithPath: path, isDirectory: true).path
			DispatchQueue.main.asyncAfter(deadline: .now() + options.claudeRunningAfter) {
				guard let slug = RunningSessions.shared.note([
					"event": "SessionStart", "session": id, "cwd": cwd,
				]) else { return }
				controller?.claudeSessionsChanged(slug: slug)
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

		if options.debugStop {
			// The console is the third of the three faults and cannot be read
			// from the session, so it is echoed as it arrives — the same way a
			// capture run reads what the adapter said.
			controller?.echoDebugOutputForTesting()
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

		if options.verticalNavigation {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseVerticalNavigationForTesting()
			}
		}

		if options.emacsNavigation {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseEmacsNavigationForTesting()
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

		if let name = options.runConfigNamed {
			// Later than most of these: the list is filled in by a scan on a
			// background queue, and asking for something before the scan has
			// answered reports only that it was not found.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.runNamedConfigurationForTesting(name)
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

		// A fixed moment rather than one measured back from the screenshot: a
		// script that stages a folder and looks again has `settle`s in it and
		// runs for several seconds, which the shot is timed to outlast.
		if let steps = options.changesSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.changesStepsForTesting(steps)
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

		if let count = options.fillTerminalTabs {
			// Spread out rather than in a loop: each one starts a shell, and
			// twelve started in the same turn of the run loop is a burst the
			// panel never sees in use.
			for step in 0..<count {
				DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(step) * 0.25) {
					controller?.addTerminalTabForTesting()
				}
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(count) * 0.25 + 1.5) {
				print("TABS: \(controller?.paneCountForTesting ?? 0) panes")
				// A number rather than a picture: whether a tab can be reached
				// is a fact, and a screenshot of a full strip is a thing
				// somebody has to squint at.
				print("OVERFLOW: \(controller?.panelOverflowReportForTesting ?? "none")")
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
						print("CLOSING: \(controller?.closeTerminalTabsForTesting(count: closing) ?? "none")")
						DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
							print("CLOSED: \(controller?.panelOverflowReportForTesting ?? "none")")
							fflush(stdout)
						}
					}
				} else {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						print("CHOSE: \(controller?.selectHiddenPanelTabForTesting(0) ?? "none")")
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
							print("AFTER: \(controller?.panelOverflowReportForTesting ?? "none")")
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
				// **A capture that cannot be produced says so and exits
				// non-zero**, and one that can still ends the run. This wrote
				// its file and then sat there: `--sidebar-shot` on its own never
				// exited, so every driven use of it was a `timeout` away from
				// looking like a hang — and a run killed by `timeout` reports
				// 124 whether or not the picture was written.
				let ok = controller?.snapshotSidebarForTesting(to: path) ?? false
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
				controller?.tabCloseHoverForTesting(to: path)
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

		if options.reportsTerminalGeometry {
			for seconds in [3.0, 5.0, 7.0, 9.0] {
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
					print("GEOM \(Int(seconds))s: \(controller?.terminalGeometryForTesting() ?? "-")")
					print("PANEL \(Int(seconds))s: \(controller?.panelGeometryForTesting() ?? "-")")
					fflush(stdout)
				}
			}
		}

		if options.devContainerTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				switch options.devContainerWhich {
				case "all": controller?.exerciseEveryDevContainerTerminalForTesting()
				case let which?: controller?.exerciseDevContainerTerminalForTesting(
					which: Int(which)
				)
				case nil: controller?.exerciseDevContainerTerminalForTesting()
				}
			}
		}

		for at in options.devContainerPillAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.devContainerPillForTesting() ?? "PILL: no window")")
				fflush(stdout)
			}
		}

		for at in options.worktreePillAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.worktreePillForTesting() ?? "WORKTREE: no window")")
				fflush(stdout)
			}
		}

		if let at = options.worktreeMenuAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print("\(Int(at))s \(controller?.worktreeMenuForTesting() ?? "WORKTREEMENU: no window")")
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

		if let at = options.devContainerMenuAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				print(controller?.devContainerMenuForTesting() ?? "PILLMENU: no window")
				fflush(stdout)
			}
		}

		for spec in options.pressDevContainerMenu {
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
				controller?.reportServerBannerForTesting()
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
					print("TABADD areas: \(controller?.terminalAddControlsForTesting ?? "no window")")
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
					let where_ = controller?.terminalDirectoryForTesting()
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
			|| options.backlogNew != nil || options.backlogInit {
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
					controller?.pressSettingsKeysForTesting(keys)
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
						print("RUNNING: rescoping \(controller?.tabCountForTesting ?? -1) tab(s)")
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
				let ok = controller?.writeEditorImageForTesting(to: path) ?? false
				FileHandle.standardError.write(Data("editor shot \(ok ? "written" : "failed"): \(path)\n".utf8))
				if options.screenshotPath == nil { exit(ok ? 0 : 2) }
			}
		}

		if let path = options.screenshotPath {
			scheduleScreenshot(
				path: path,
				delay: options.screenshotDelay,
				controller: controller,
				// The list is a window of its own, so it is nowhere in the main
				// window's frame. Photographed directly when it is the subject.
				window: options.runningTools ? RunningToolsWindowController.shared.window : nil
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

	/// What this app has started and has not ended, with what each is costing.
	///
	/// On the app delegate rather than on a window controller, because what it
	/// lists is the app's: one set of language servers and one set of containers
	/// however many project windows are open. It opens with no window at all,
	/// for the same reason the settings do.
	@MainActor
	@objc func showRunningTools(_ sender: Any?) {
		RunningToolsWindowController.shared.show()
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
		// Nothing this app started outlives it. A subprocess is handed to
		// launchd rather than killed when its parent goes, and a container that
		// keeps running holds whatever it was doing — enough of them and the
		// runtime's own service stops answering, which is what happened here.
		//
		// The container is removed separately and by name, because ending the
		// process that started it does nothing to it at all.
		ToolProcesses.shared.terminateAll()
		ToolContainers.shared.removeAll()
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

	/// `abydos <file>` from a terminal in a window that has no editor of its own.
	///
	/// A torn-off terminal window is a panel and nothing else. The window that
	/// asked cannot answer, so the nearest project window does — and if there is
	/// none, one is opened on whatever encloses the file.
	func openFromTerminal(_ request: TerminalOpenRequest) {
		let url = URL(fileURLWithPath: request.path)
		let controller = frontmostController ?? open(projectAt: Project.root(containing: url))
		controller.openFromTerminal(request)
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

	/// What a driven run opens: what it was given, or nothing, saying which.
	///
	/// Three sentences, in one place, and every one of them is a report that was
	/// filed:
	///
	/// - **No project named opens nothing.** This used to fall through to the
	///   most recently opened project, which is how `--type` came to put
	///   `C-ircle` into a file in `abydos-examples` that nobody was editing: a
	///   verb was run with no project, the window came up on whatever the
	///   reporter had last been working in, and the keyboard went there. Falling
	///   back is right for somebody double-clicking the app — it is where they
	///   left off — and wrong for every one of the verbs, which are about a
	///   project somebody named. 0522.
	/// - **A project that cannot be opened fails**, on standard error and with a
	///   non-zero status, rather than opening a window on a directory that is not
	///   there and driving it.
	/// - **The root it resolved is printed**, standardised, because `/tmp/x` and
	///   `/private/tmp/x` are the same directory and a run that photographed the
	///   wrong one of them was silent about it for an afternoon. On standard
	///   error, so that no driver verb's parser is fed a line it did not expect.
	///
	///   Resolved rather than standardised, and what that resolves *to* is worth
	///   knowing: `/tmp` is a link to `/private/tmp`, and Foundation's
	///   `resolvingSymlinksInPath` deliberately drops a leading `/private` where
	///   the result still exists. So both spellings converge on `/tmp/…` —
	///   checked, both ways round — which is the whole point of printing it. Two
	///   names for one directory is how a run came to photograph the wrong copy
	///   and be silent about it for an afternoon.
	private func openForDrivenRun(_ options: LaunchOptions) -> MainWindowController? {
		let wanted: URL?
		if let path = options.projectPath {
			wanted = URL(fileURLWithPath: path, isDirectory: true)
		} else if let file = options.filePaths.first {
			let directory = URL(fileURLWithPath: file).deletingLastPathComponent()
			wanted = ProjectRoot.find(from: directory) ?? directory
		} else {
			wanted = nil
		}

		guard let wanted else { return nil }

		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: wanted.path, isDirectory: &isDirectory)
		guard exists, isDirectory.boolValue else {
			FileHandle.standardError.write(Data(
				"cannot open \(wanted.resolvingSymlinksInPath().path): no such directory\n".utf8
			))
			exit(2)
		}

		let controller = open(projectAt: wanted)
		let opened = (controller.project?.root ?? wanted).resolvingSymlinksInPath().path
		FileHandle.standardError.write(Data("project \(opened)\n".utf8))
		return controller
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
		LaunchClock.mark("window ordered front")
		// And again on the next turn of the main queue, which is the first
		// moment anything can have been drawn: `applicationDidFinishLaunching`
		// carries on for a while after this — menus, drivers, the language
		// server warm-up — and none of it has yielded, so the window somebody
		// can see is not on screen at the line above. 0428 wants the number a
		// person waits through, and that is this one.
		DispatchQueue.main.async { LaunchClock.mark("window drawn") }
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

	/// What the app is called, for the three menu items that say so.
	///
	/// From the bundle rather than written out: they said "ideai" for as long
	/// as it took somebody to open the menu after the rename, and the bundle
	/// has been right the whole time.
	static var applicationName: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
			?? ProcessInfo.processInfo.processName
	}

	private func buildMenu() {
		let mainMenu = NSMenu()

		let appMenuItem = NSMenuItem()
		let appMenu = NSMenu()
		// Ours rather than the standard panel, which shows the version but not
		// which build it came from — the one thing worth knowing when the
		// question is whether an install took.
		appMenu.addItem(
			withTitle: "About \(Self.applicationName)",
			action: #selector(showAbout(_:)),
			keyEquivalent: ""
		)
		appMenu.addItem(.separator())
		let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
		settingsItem.target = self
		appMenu.addItem(settingsItem)
		appMenu.addItem(.separator())
		appMenu.addItem(withTitle: "Hide \(Self.applicationName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		appMenu.addItem(withTitle: "Quit \(Self.applicationName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

		// ⌘/, which is Xcode's, VS Code's and IDEA's alike — the one shortcut in
		// this menu nobody has to be told. `"/"` was unbound anywhere in the app,
		// so nothing had to give it up.
		let toggleComment = NSMenuItem(
			title: "Toggle Comment",
			action: #selector(MainWindowController.toggleLineComment(_:)),
			keyEquivalent: "/"
		)
		toggleComment.keyEquivalentModifierMask = [.command]
		// **The one item in this menu bar that keeps its literal key**, and 0479 is
		// the account of why. Left to itself, the system moves a key equivalent it
		// judges awkward on the current layout to one that needs no shift: `/` on a
		// German keyboard is ⇧7, so the menu read **⌘ß**, and the person who had
		// asked for ⌘/ pressed ⌘⇧7 and got nothing. Both halves of that were
		// measured — ⌘ß was the only press that reached it, and ⌘⇧7 reached nothing
		// — with `--comment-key`.
		//
		// Turning the relocation off works *here* because AppKit forgives a modifier
		// the mask does not ask for when that modifier is what types the character,
		// so ⌘⇧7 reaches this item with `/` intact. Measured, not reasoned about,
		// and it is the whole reason this is the fix rather than declaring the
		// shortcut twice.
		//
		// **It is off for this item and nothing else**, and that is a judgement the
		// same measurement supports. The other punctuation shortcuts here — `[`, `]`
		// for Back and Forward, `\` for the splits, `=` for Zoom In — all need ⌥ on
		// this keyboard, so keeping *their* literals costs a whole extra modifier
		// where the relocation gives them one key in the same place it is on a US
		// keyboard: ⌘Ö rather than ⌥⌘5. Worse, `\` is ⌥⇧7, so with the literal kept
		// the forgiven shift makes `⌘\` and `⇧⌘\` **the same press** — Split Right
		// answers and Split Down becomes unpressable. `/` has neither problem: one
		// extra shift, no collision with anything.
		//
		// So the cost of this line is that a German user presses ⌘⇧7 rather than
		// ⌘ß, for the shortcut every editor documents, spelled in the menu the way
		// somebody told "⌘/" would look for it. ⌘ß was a key nobody would ever try,
		// so what that cost was the whole feature. `--menu-keys` prints which press
		// reaches every shortcut in the menu bar, which is how all of this stopped
		// being a guess.
		toggleComment.allowsAutomaticKeyEquivalentLocalization = false
		editMenu.addItem(toggleComment)
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

		// ⇧F6, which is IDEA's, for the same reason the two below are.
		let rename = NSMenuItem(
			title: "Rename…",
			action: #selector(MainWindowController.renameSymbol(_:)),
			keyEquivalent: String(UnicodeScalar(UInt32(NSF6FunctionKey))!)
		)
		rename.keyEquivalentModifierMask = [.shift]
		editMenu.addItem(rename)

		// **⌥⏎, which is IDEA's, and the only always-on way in.** Measured in
		// 0538 against gopls and jdtls: a server answers *something* for every
		// line of a real file — organise imports, generate accessors, and in
		// gopls's case a kind of its own invention — so an indicator driven by
		// "are there actions here" would be on every row. A keystroke asks only
		// when somebody asks.
		//
		// A menu item rather than a key handled in the text view, because a menu
		// item's key equivalent is matched before the view sees the event: ⌥⏎ in
		// a text view is a newline, and catching it afterwards would be catching
		// it after something else had already done it.
		let actions = NSMenuItem(
			title: "Show Context Actions",
			action: #selector(MainWindowController.showCodeActions(_:)),
			keyEquivalent: "\r"
		)
		actions.keyEquivalentModifierMask = [.option]
		editMenu.addItem(actions)

		// **⌘⇧C for the reference, and nothing for the permalink.** The
		// question the design left open was whether a keystroke is worth
		// spending on a gesture done twice a week; the answer is that the
		// reference is not that gesture. It is the string handed to an
		// assistant, and handing one over is something somebody does several
		// times in a sitting — this session alone produced dozens of
		// `file:line` references by hand. The permalink is the twice-a-week one:
		// it goes into a message or a bookmark, deliberately, and reaching the
		// menu for it costs nothing anybody will notice.
		//
		// ⌘⇧C is free here and is what IDEA puts "copy reference" on, which is
		// where the muscle memory comes from.
		let copyReference = NSMenuItem(
			title: "Copy Reference",
			action: #selector(MainWindowController.copyReference(_:)),
			keyEquivalent: "c"
		)
		copyReference.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(copyReference)

		let copyPermalink = NSMenuItem(
			title: "Copy Permalink",
			action: #selector(MainWindowController.copyPermalink(_:)),
			keyEquivalent: ""
		)
		editMenu.addItem(copyPermalink)

		// The other end of the same road, and the only door there is: nothing
		// registers an `abydos://` scheme, so a link is followed by pasting it.
		let goToCopied = NSMenuItem(
			title: "Go to Copied Place",
			action: #selector(MainWindowController.goToCopiedPlace(_:)),
			keyEquivalent: "v"
		)
		goToCopied.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(goToCopied)

		// The file's own, which have no caret: `source.*` is about the whole
		// file — organise imports, fix everything of one kind — and a menu that
		// opens where somebody is typing is the wrong place for it.
		let sourceActions = NSMenuItem(
			title: "Source Actions…",
			action: #selector(MainWindowController.showSourceActions(_:)),
			keyEquivalent: ""
		)
		editMenu.addItem(sourceActions)

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

		agentMenu.addItem(.separator())
		let backlogItem = NSMenuItem(
			title: "Backlog",
			action: #selector(MainWindowController.showBacklog(_:)),
			keyEquivalent: "b"
		)
		backlogItem.keyEquivalentModifierMask = [.command, .shift]
		agentMenu.addItem(backlogItem)

		agentMenu.addItem(withTitle: "Start the Next Ready Item\u{2026}",
		                  action: #selector(MainWindowController.startNextBacklogItem(_:)),
		                  keyEquivalent: "")

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
		// How a file with a rendered form is shown. In a submenu of their own
		// because "Split Right" is also what a second editor pane is called:
		// two commands with one name in one menu is a coin toss in the palette.
		//
		// ⌘1…⌘6 are the sidebar's, so these take the same numbers a modifier
		// along, in the order the tab strip's own dropdown lists them.
		let previewItem = NSMenuItem()
		let previewMenu = NSMenu(title: "Preview")
		for (index, mode) in PreviewMode.allCases.enumerated() {
			let item = NSMenuItem(
				title: mode.title,
				action: #selector(MainWindowController.choosePreviewMode(_:)),
				keyEquivalent: String(index + 1)
			)
			item.keyEquivalentModifierMask = [.control, .command]
			item.representedObject = mode.rawValue
			previewMenu.addItem(item)
		}
		previewItem.submenu = previewMenu
		viewMenu.addItem(previewItem)

		viewMenu.addItem(.separator())
		let terminalItem = NSMenuItem(title: "Toggle Terminal", action: #selector(MainWindowController.toggleTerminal(_:)), keyEquivalent: "j")
		viewMenu.addItem(terminalItem)
		let newTerminalItem = NSMenuItem(title: "New Terminal", action: #selector(MainWindowController.newTerminal(_:)), keyEquivalent: "t")
		newTerminalItem.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(newTerminalItem)

		// Beside the ordinary one rather than anywhere else, because it is the
		// same gesture: a shell for this project. Which machine it is on is what
		// the title says. Greyed out for a project with no devcontainer.json,
		// which is most of them.
		//
		// This is the title it has before a window has been asked: validation
		// renames it after the container it would open, since a repository of
		// subprojects has one each.
		//
		// One item, and it opens the project's preferred devcontainer. A project
		// offering several — `.devcontainer/alpine` beside `.devcontainer/go` —
		// has all of them in the + chevron's menu in the terminal panel, which is
		// where a list belongs; this stays a single command that says which
		// container it means. `MainWindowController.devContainerMenuTitle` is
		// where the reason for not making it a submenu is written down.
		let containerTerminalItem = NSMenuItem(
			title: MainWindowController.containerTerminalTitle,
			action: #selector(MainWindowController.newTerminalInContainer(_:)),
			keyEquivalent: ""
		)
		viewMenu.addItem(containerTerminalItem)

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

		// What is running, beside the terminal items because it is the same
		// family of thing — a process this app started that is still going —
		// and with an explicit target because it is the app's list rather than
		// this window's, and has to open when no project window is up at all.
		//
		// No key equivalent. It is wanted the day the fan comes on, which is not
		// often enough to spend a chord on; the command palette is generated
		// from this menu bar, so ⇧⌘P and "running" already reaches it.
		let runningTools = NSMenuItem(
			title: "Running Servers and Containers…",
			action: #selector(showRunningTools(_:)),
			keyEquivalent: ""
		)
		runningTools.target = self
		viewMenu.addItem(runningTools)

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

/// Runs `report` once the board has cards on it, or once the wait is over.
///
/// The board loads on its own: the backlog is a folder walk and the OpenSpec
/// record is the CLI, once per change, found through the login shell. A driver
/// that asks on a timer asks either too early or later than it needs to, and
/// asking too early prints a sentence about a card that is not missing.
///
/// Gives up rather than waiting for ever, and reports anyway — an empty board is
/// an answer, and a driver that never prints is one nobody can read.
private func whenTheBoardHasCards(
	_ controller: MainWindowController?,
	giveUpAfter seconds: TimeInterval,
	then report: @escaping () -> Void
) {
	let deadline = Date().addingTimeInterval(seconds)

	func look() {
		guard let controller else { return report() }
		if controller.backlogHasCardsForTesting() || Date() >= deadline {
			report()
			return
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: look)
	}
	// The first look is still after a beat: the pane is made when the panel is
	// shown, and showing it is what the report itself does.
	DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: look)
}

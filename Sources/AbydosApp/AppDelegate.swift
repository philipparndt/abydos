import AppKit
import AbydosKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
	/// Public so the four-line executable — and an Xcode application target
	/// built from the same sources — can make one.
	public override init() { super.init() }

	var windowControllers: [MainWindowController] = []
	/// Claude sessions announcing themselves, from the hook this binary also is.
	private var claudeWatch: ClaudeWatch?

	@objc func showAbout(_ sender: Any?) {
		NSApp.orderFrontStandardAboutPanel(options: [
			.applicationVersion: Self.buildDescription
				.replacingOccurrences(of: "Abydos ", with: ""),
			.credits: Self.aboutCredits,
		])
		NSApp.activate(ignoringOtherApps: true)
	}

	/// Where the documentation is served from.
	///
	/// Its own repository and its own Pages site, for the reason the `README`
	/// gives, so it is spelled out rather than derived from anything in the
	/// bundle. **Lower case**: Pages paths are case-sensitive and the
	/// capitalised spelling answers 404.
	static let documentationURL = "https://philipparndt.github.io/abydos-docs/"

	/// The documentation, as something clickable under the version.
	///
	/// `.credits` rather than a panel of this app's own: the standard one
	/// already answers the menu item and carries the icon and the version, and
	/// it renders an attributed string — so a `.link` in it opens the browser
	/// with nothing here to handle the click. There is no `Credits.rtf` in the
	/// bundle, so this displaces nothing.
	static var aboutCredits: NSAttributedString {
		let centred = NSMutableParagraphStyle()
		centred.alignment = .center

		var attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
			.paragraphStyle: centred,
		]
		// Not force-unwrapped. `URL(string:)` is optional, and the obvious `!`
		// would turn a typo in the literal above into a crash on every ⌘? —
		// text nobody can click is the better of the two failures.
		if let url = URL(string: Self.documentationURL) { attributes[.link] = url }
		return NSAttributedString(string: "Documentation", attributes: attributes)
	}

	/// Which build this is: the version, the commit count, and the commit.
	static var buildDescription: String {
		let info = Bundle.main.infoDictionary
		let version = info?["CFBundleShortVersionString"] as? String ?? "?"
		let build = info?["CFBundleVersion"] as? String ?? "?"
		let commit = info?["AbydosCommit"] as? String ?? "unknown"
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
		// The Finder's Services menu is told who answers *New Terminal Here*.
		// Registered here rather than lazily: the menu is built from the
		// bundle, and the object has to exist by the time somebody chooses it.
		terminalService.open = { [weak self] root in self?.open(projectAt: root) }
		NSApp.servicesProvider = terminalService
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

		// And an earlier version took the default for web pages, which is how
		// macOS is told which application is the browser — so links opened in
		// an editor that dropped them. Given back where it happened.
		Task { @MainActor in await DefaultEditor.handBackWhatWasNeverOurs() }

		// And an earlier version started every pane with `PAGER=cat`, which a
		// tmux server that was up at the time is still handing out — off the
		// main thread, because it runs `tmux` twice and a launch waits for
		// nothing that a pane will ask about later.
		DispatchQueue.global(qos: .utility).async {
			TmuxConfig.forgetPagerInRunningServer()
		}

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
		// And the pill on every panel, which counts the whole machine and so
		// is the same in every window.
		watch.runningChanged = { [weak self] in
			for controller in self?.windowControllers ?? [] {
				controller.runningSessionsChanged()
			}
		}
		watch.start()
		claudeWatch = watch

		// What the app holds, over every window, for a row in one window that
		// names a tab in another: the register is the machine's, the reach is
		// the app's.
		PanelRunningSessions.app = .init(
			terminals: { [weak self] in
				Set((self?.windowControllers ?? []).flatMap(\.terminalIdentities))
			},
			reveal: { [weak self] identity in
				(self?.windowControllers ?? []).contains { $0.revealTerminalTab(identity: identity) }
			}
		)

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
		if let path = options.projectPath {
			for spec in options.claudeRunning where spec.after <= 0 {
				let cwd = URL(fileURLWithPath: path, isDirectory: true).path
				RunningSessions.shared.note([
					"event": "SessionStart", "session": spec.id, "status": spec.status, "cwd": cwd,
				])
				for _ in 0..<spec.subagents {
					RunningSessions.shared.note([
						"event": "PreToolUse", "session": spec.id, "status": "working",
						"cwd": cwd, "tool": ClaudeHook.subagentTool,
					])
				}
			}
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
		driveTheEditor(options, in: controller)
		driveTheTools(options, in: controller)
		driveThePanel(options, in: controller)
	}

	/// Captures the window after async work (git status, parsing, folds) settles,
	/// then exits with a status reflecting whether the file was written.
	/// - Parameter subject: which window to photograph, asked for at capture
	///   time rather than when the run was set up. A panel the run opens for
	///   itself does not exist yet at that point, and one AppKit owns — the
	///   About panel — is never held here at all.
	func scheduleScreenshot(
		path: String,
		delay: TimeInterval,
		controller: MainWindowController?,
		subject: @escaping () -> NSWindow? = { nil }
	) {
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
			guard let window = subject() ?? controller?.window ?? NSApp.windows.first else {
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

	func reportWindowsForTesting(_ stage: String) {
		let described = windowControllers.map { controller in
			"\(controller.isTornOff ? "torn" : "main")"
				+ "(tabs=\(controller.editorForTesting.tabCountForTesting)"
				+ ",frame=\(controller.window?.frame ?? .zero))"
		}
		print("TEAROFF \(stage): windows=\(windowControllers.count) \(described.joined(separator: " "))")
	}

	/// Drops the torn-off window's tab back onto the original window's strip,
	/// along the same path a drag between windows takes.
	func dragTornOffTabBackForTesting(into target: MainWindowController?) {
		guard let target,
		      let torn = windowControllers.first(where: { $0.isTornOff }),
		      let groupID = torn.editorForTesting.activeGroupIDForTesting
		else { return }
		target.editorForTesting.dropForTesting(
			payload: EditorTabDrag.Payload(groupID: groupID, index: 0, path: ""),
			at: 0
		)
	}

	public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}

	/// The first quit-time gate this app has: a decrypted SOPS buffer with
	/// edits lives in memory only, so quitting is the one thing that loses it,
	/// and it asks. Ordinary unsaved tabs still quit as they always did.
	public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		for controller in windowControllers {
			guard controller.settleDecryptedBuffersForQuit() else { return .terminateCancel }
		}
		return .terminateNow
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

	/// Fills File ▸ Project Trust from the window in front when it is opened.
	///
	/// Every item there is about a project — its name, its folder, the remote
	/// it says it came from, and whether any of those is trusted already — so
	/// there is nothing to build until somebody looks.
	@MainActor let trustMenuDelegate = TrustMenuDelegate()

	/// *New Terminal Here*, which the Finder shows in its Services menu.
	@MainActor let terminalService = TerminalService()

	/// Opens what the system handed over — and only what names a file.
	///
	/// **This arrives from an Apple Event, so the URL is whatever the sender
	/// wrote.** A `GURL` event carries a string, and no scheme is required of
	/// it: what reached here has been a relative path with no scheme at all.
	/// Neither test below tells one of those apart — `hasDirectoryPath` is true
	/// for anything ending in a slash, `https://host/a/` and `notes/` included,
	/// so a non-file URL became a project root and every git command run
	/// against it aborted the app on `NSTask`'s "non-file URL argument".
	///
	/// `DroppedFiles` has always filtered the same way for the same reason. A
	/// URL that names no file is dropped rather than refused out loud: there is
	/// nothing to show for it and nobody to tell, this being a message from the
	/// system rather than something somebody typed.
	public func application(_ application: NSApplication, open urls: [URL]) {
		// `abydos://compare?a=…&b=…` is `abydos-diff` typed in a terminal that
		// is not one of this app's own, where no pane can carry the request.
		for url in urls where url.scheme == "abydos" { openCompareURL(url) }
		for url in urls where url.isFileURL {
			if url.hasDirectoryPath {
				open(projectAt: url)
				continue
			}
			// A file: the project is whatever encloses it, and the file itself
			// is what somebody wanted to look at.
			let controller = open(projectAt: Project.root(containing: url))
			controller.editorForTesting.openForTesting(url)
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
	var frontmostController: MainWindowController? {
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
func whenTheBoardHasCards(
	_ controller: MainWindowController?,
	giveUpAfter seconds: TimeInterval,
	then report: @escaping () -> Void
) {
	let deadline = Date().addingTimeInterval(seconds)

	func look() {
		guard let controller else { return report() }
		if controller.panelForTesting.backlogHasCardsForTesting() || Date() >= deadline {
			report()
			return
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: look)
	}
	// The first look is still after a beat: the pane is made when the panel is
	// shown, and showing it is what the report itself does.
	DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: look)
}

/// Builds File ▸ Project Trust when it is opened — see `trustMenuDelegate`.
@MainActor
final class TrustMenuDelegate: NSObject, NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		let controller = NSApp.keyWindow?.windowController as? MainWindowController
			?? NSApp.windows.compactMap { $0.windowController as? MainWindowController }.first
		guard let controller else {
			let none = NSMenuItem(title: "No project", action: nil, keyEquivalent: "")
			none.isEnabled = false
			menu.addItem(none)
			return
		}
		// The window's own menu, moved rather than copied: an item carries its
		// target, and two menus built from two lists is how they come to say
		// different things.
		for item in controller.trustMenu().items {
			item.menu?.removeItem(item)
			menu.addItem(item)
		}
	}
}

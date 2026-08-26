import AppKit
import AbydosKit

/// Running a program: what can be run, which one is chosen, and starting it —
/// on this machine, in a container, or in a cluster — with the debugger, a
/// profiler or coverage attached.
///
/// It was five `// MARK` sections and some 2,900 lines of
/// `MainWindowController`, holding twenty-two properties that nothing else in
/// that class touched and that everything in it could reach.
///
/// One type across three files rather than three types. What makes a run
/// coordinator is one set of state — the configuration list, which one is
/// selected, what is running now — and every part of the job reads it. Three
/// types would have put that state in one of them with the other two asking,
/// which is the arrangement being taken apart rather than a smaller version of
/// it.
@MainActor
final class RunCoordinator {
	let panel: BottomPanel
	let editor: EditorAreaController

	// What the window knows and this object asks for.
	var currentProject: () -> Project? = { nil }
	var currentLaunchRoot: () -> URL = { URL(fileURLWithPath: ".") }
	var debugCoordinator: () -> DebugCoordinator? = { nil }
	/// The window a sheet or a menu is put on.
	var hostWindow: () -> NSWindow? = { nil }

	// What it asks the window to do.
	var onSetPanelVisible: (Bool) -> Void = { _ in }
	var onNotify: (String, String?, Toast.Kind, String?, (() -> Void)?) -> Void = { _, _, _, _, _ in }

	/// The window's toast, with the labels its callers already use.
	func notify(
		_ title: String,
		detail: String? = nil,
		kind: Toast.Kind = .error,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) {
		onNotify(title, detail, kind, actionTitle, action)
	}
	var onWire: (DebugSession) -> Void = { _ in }
	var onRememberOpenEditors: () -> Void = {}
	var onLeaveTerminalFullScreen: () -> Void = {}
	var onAttachToProcess: (Any?) -> Void = { _ in }
	var onMenuItem: (String, Selector) -> NSMenuItem = { t, a in NSMenuItem(title: t, action: a, keyEquivalent: "") }
	var onRunSelected: (Any?) -> Void = { _ in }
	var onDebugSelected: (Any?) -> Void = { _ in }
	var onStopSelected: (Any?) -> Void = { _ in }
	/// The run dropdown, which the window shows because the popover it uses
	/// takes a `MainWindowController` as its owner.
	var onShowConfigurationMenu: (NSRect, RunControl) -> Void = { _, _ in }

	/// A goal from a build file chosen from the menu that has no launch
	/// configuration — a make target, a Maven goal, a Gradle task. Play runs it
	/// the way its build tool would.
	///
	/// Named for make because make was the first, and the selection model calls
	/// it that too. Nothing about it is make-specific.
	var selectedMakeRun: RunConfiguration?
	/// Remembered for the session: the same program is usually profiled more
	/// than once in a sitting.
	static var lastProfilerAddress = "localhost:6060"
	/// The tunnel and the debugger's tunnel, while a dev pod session is on.
	var devPodForwards: [PortForward] = []
	/// The pod running something of ours, so stop can tell it to stop.
	var devPodClient: DevPodClient?
	/// The launch in progress, so it can be cancelled.
	var clusterTask: Task<Void, Never>?
	/// Set while a run is on its way to being profiled.
	var profileAfterRun = false

	/// What the script being debugged exited with, while its port is awaited.
	///
	/// Read when the wait ends to tell "the build is still going" from "the thing
	/// died", which from the port alone look identical.
	var scriptDebugExit: Int32?
	/// Said once per session, since `cannotHotSwap` stays true afterwards.
	var saidThisSessionCannotHotSwap = false
	var hotSwapCompileRunning = false
	var hotSwapCompileQueued = false

	init(panel: BottomPanel, editor: EditorAreaController) {
		self.panel = panel
		self.editor = editor
	}

	var runControl: RunControl?

	/// The terminal a launch configuration is running in, so the play button can
	/// become a stop button that stops the right thing.
	weak var runningPane: TerminalPane?

	/// Held while open: the panel is a child window and nothing else owns it.
	/// Held while open, for the same reason.
	var processPicker: ProcessPicker?

	/// What the run control acts on, remembered per project.
	///
	/// Written down as it changes rather than at quit. A window that never gets
	/// to say goodbye — a crash, a force quit, a capture run — should still
	/// come back pointing at whatever was last run from it.
	var selectedConfigurationName: String? {
		didSet {
			guard selectedConfigurationName != oldValue else { return }
			onRememberOpenEditors()
		}
	}

	/// The session the debug commands act on, if one is running.
	var debugSession: DebugSession? { panel.activeDebugSession }

	@objc func debugStop(_ sender: Any?) { debugSession?.stop() }

	/// What this project can run, refreshed off the main thread.
	private(set) var runConfigurations: [RunConfiguration] = []

	/// Where each Xcode project was last sent, keyed as
	/// `XcodeDestinationMemory` says — by project, not by scheme. Kept with the
	/// project's session, so a project that went to the phone yesterday goes
	/// there again today rather than back to a simulator.
	var xcodeDestinations: [String: String] = [:]

	/// One scan at a time, with at most one more queued behind it — the shape
	/// `refreshGitStatus` has had all along.
	var isDiscoveringRunConfigurations = false

	var wantsAnotherRunConfigurationScan = false

	/// Rescans, but only if this batch of writes could have changed the answer.
	///
	/// A language server importing a Tycho reactor writes `.project`,
	/// `.classpath` and `.settings` into every bundle it touches, and each of
	/// those arrives here as a filesystem event. None of them can add a `main`
	/// method or a Makefile target, so none of them is worth a walk of 45,772
	/// Java files — which is what each one used to cost.
	func refreshRunConfigurations(because change: FileSystemChange) {
		Self.runConfigurationTallyForTesting.asked += 1
		guard RunConfigurationDiscovery.deservesRescan(after: change) else {
			Self.runConfigurationTallyForTesting.skipped += 1
			return
		}
		// The cached scan describes the tree as it was, and a change that deserves
		// a rescan is by definition one it no longer describes.
		refreshRunConfigurations(forgettingCachedScan: true)
	}

	/// - Parameter forgettingCachedScan: whether the kept Java scan is known to
	///   be out of date. Set when a file-system change brought us here, and
	///   acted on *inside* the same task that then rescans: forgetting from a
	///   task of its own raced the scan it was meant to precede, and a scan whose
	///   answer is invalidated while it is running is one whose answer cannot be
	///   kept — so the next Debug press paid for the walk all over again.
	func refreshRunConfigurations(forgettingCachedScan forget: Bool = false) {
		guard let project = currentProject() else { return }
		let root = project.root

		// Coalesced, because the filter above is not a guarantee: a `git
		// checkout` across a large repository names thousands of Java files in
		// a few batches, and every one of those batches is a legitimate reason
		// to scan. Uncoalesced, the concurrent queue answers a burst by making
		// more threads, and every walk but the last is stale before it finishes.
		guard !isDiscoveringRunConfigurations else {
			wantsAnotherRunConfigurationScan = true
			Self.runConfigurationTallyForTesting.coalesced += 1
			return
		}
		isDiscoveringRunConfigurations = true
		Self.runConfigurationTallyForTesting.walked += 1

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			// The Java scan through the shared cache, and the rest of discovery
			// around it: pressing Debug wants the same answer and would otherwise
			// start a second walk of the same tree while this one is still running.
			let mains = Self.awaitingMainClasses(in: root, forgetting: forget)
			let found = RunConfigurationDiscovery.discover(in: root, javaMainClasses: mains)
			DispatchQueue.main.async {
				guard let self else { return }
				self.isDiscoveringRunConfigurations = false
				self.runConfigurations = found

				// Group by file so the gutter can put a play button beside each
				// entry point and each make target.
				var byFile: [String: Set<Int>] = [:]
				for configuration in found {
					guard let file = configuration.file, let line = configuration.line else { continue }
					byFile[file, default: []].insert(line)
				}
				self.editor.setRunnableLines(byFile)

				if self.wantsAnotherRunConfigurationScan {
					self.wantsAnotherRunConfigurationScan = false
					// Coalesced changes are still changes: this rescan exists because
					// more of them arrived while the last walk was running.
					self.refreshRunConfigurations(forgettingCachedScan: true)
				}
			}
		}
	}

	func configuration(for item: NSMenuItem) -> RunConfiguration? {
		guard let id = item.representedObject as? String else { return nil }
		return runConfigurations.first { $0.id == id }
	}

	/// Why Java cannot be debugged here at all, when nothing anybody does now
	/// would change it — and nil for everything else, including the reasons that
	/// are worth offering and explaining.
	///
	/// Nil for a configuration that is not Java, which is most of them: the
	/// question is about the Java debugger and asking it of a Go package would
	/// walk a project for markers that decide nothing.
	func javaDebugSettledRefusal(_ configuration: RunConfiguration) -> String? {
		guard configuration.source == .javaMain, let project = currentProject() else { return nil }
		let root = project.scopeRoot
		guard let refusal = JavaDebugHost.refusal(
			project: root,
			inDevContainer: LanguageService.shared.devContainerNameHoldingServers(for: root)
		), refusal.isSettledHere else { return nil }
		return refusal.localizedDescription
	}

	/// Runs a configuration in a terminal session of its own.
	///
	/// A terminal rather than a captured-output pane: the thing being run is
	/// usually interactive, or prints as it goes, and watching it in a real
	/// shell is what makes it debuggable.
	func run(_ configuration: RunConfiguration) {
		// A scheme is not a command line until somewhere to run it is known,
		// and finding that out means asking `xcodebuild`, which takes long
		// enough that it cannot happen while a list of runnable things is being
		// drawn. So it happens here, once, on the way to the first run.
		if let target = configuration.xcode {
			runScheme(configuration, target: target)
			return
		}

		onSetPanelVisible(true)
		// Through the same reporting as anything else started here: a run from
		// the gutter is a run, and it should colour the titlebar, offer a stop
		// button, and say how it went.
		runControl?.setStatus("Running \(configuration.name)…", busy: true)

		let pane = panel.runCommand(
			title: configuration.name,
			command: configuration.commandLine,
			directory: URL(fileURLWithPath: configuration.workingDirectory),
			environment: configuration.environment,
			// This configuration's console, and it keeps it. Running the same
			// thing five times left five finished consoles behind, and the one
			// being read was whichever was on top.
			reusing: "run:\(configuration.id)"
		)
		followRunningPane(pane)
	}

	/// Runs a scheme where it went last time, or where it makes sense to.
	///
	/// The destination is asked for rather than assumed even when one is
	/// remembered, because a remembered one can be a simulator that has been
	/// deleted or a phone that is in somebody's pocket, and a build aimed at a
	/// destination that is not there fails several minutes in with a message
	/// about a scheme.
	func runScheme(_ configuration: RunConfiguration, target: XcodeTarget) {
		onSetPanelVisible(true)
		let directory = URL(fileURLWithPath: configuration.workingDirectory)
		let remembered = xcodeDestinations[XcodeDestinationMemory.key(for: target)]

		// Asked once per project per session: the second run of a scheme starts
		// building immediately rather than spending twelve seconds finding out
		// what it already knows.
		let known = XcodeDestinations.shared.known(for: target)
		if let chosen = known.first(where: { $0.id == remembered })
			?? (remembered == nil ? XcodeDestinations.shared.preferred(among: known) : nil)
		{
			start(configuration, target: target, on: chosen)
			return
		}

		runControl?.setStatus("Finding where \(configuration.name) can run…", busy: true)
		Task { @MainActor in
			let found = await XcodeDestinations.shared.destinations(
				for: target, workingDirectory: directory
			)
			guard let destination = found.first(where: { $0.id == remembered })
				?? XcodeDestinations.shared.preferred(among: found)
			else {
				self.runControl?.setStatus("No destination for \(configuration.name)", failed: true)
				notify(
					"Nowhere to run \(configuration.name)",
					detail: "xcodebuild lists no destination for this scheme. "
						+ "A device has to be connected and unlocked, and a simulator has to be "
						+ "installed for the deployment target."
				)
				return
			}
			self.start(configuration, target: target, on: destination)
		}
	}

	/// Builds, installs and launches, in the terminal where the output is.
	func start(_ configuration: RunConfiguration, target: XcodeTarget, on destination: XcodeDestination) {
		xcodeDestinations[XcodeDestinationMemory.key(for: target)] = destination.id


		let directory = URL(fileURLWithPath: configuration.workingDirectory)
		let derived = XcodeRun.derivedDataPath(for: target.scheme, in: directory)
		let command = XcodeRun.command(
			project: target.project,
			scheme: target.scheme,
			destination: destination,
			derivedData: derived
		) ?? XcodeRun.build(
			project: target.project,
			scheme: target.scheme,
			destination: destination,
			derivedData: derived
		)

		runControl?.setStatus("Running \(configuration.name) on \(destination.title)…", busy: true)
		let pane = panel.runCommand(
			// The destination in the title, because "docscanner-ios" twice over
			// is two tabs nobody can tell apart, and where it went is the thing
			// that differs.
			title: "\(configuration.name) · \(destination.title)",
			command: command,
			directory: directory,
			environment: configuration.environment,
			reusing: "run:\(configuration.id)"
		)
		followRunningPane(pane)
	}

	/// Watches a pane's process, so the titlebar says what became of it.
	func followRunningPane(_ pane: TerminalPane?) {
		runningPane = pane
		// The panel sets this too — it is how a tab learns its process has
		// gone, and so how a run tab stops wearing the running green. Taking
		// the handler rather than adding to it left the tab green over
		// `[process exited]`.
		let panelHandler = pane?.terminalView.onProcessExit
		pane?.terminalView.onProcessExit = { [weak self, weak pane] code in
			panelHandler?(code)
			MainActor.assumeIsolated {
				guard let self, self.runningPane === pane else { return }
				self.runningPane = nil
				self.runControl?.setStatus(
					code == 0 ? "Finished — exit code 0" : "Failed — exit code \(code)",
					failed: code != 0
				)
			}
		}
	}

	/// What this project offers to run, as the picker would group it.
	func runConfigurationsForTesting() -> String {
		guard !runConfigurations.isEmpty else { return "nothing" }
		return runConfigurations
			.map { "\(title(for: $0.source)): \($0.name) → \($0.executable) \($0.arguments.joined(separator: " "))" }
			.joined(separator: "\n  ")
	}

	/// Starts one of the discovered configurations by name, as choosing it from
	/// the run menu does, and reads its console back a few seconds later.
	///
	/// `--run-configs` says what the list holds; this says what one of them
	/// does, which is a different question and the one that catches a
	/// configuration that looks right and does not run. Every line is flushed:
	/// a driver run ends in a kill, and a report still in stdout's buffer when
	/// the signal arrives is a run that looks like it never happened.
	func runNamedConfigurationForTesting(_ name: String) {
		func say(_ text: String) {
			print("RUNCONFIG: \(text)")
			fflush(stdout)
		}

		for configuration in runConfigurations {
			say("  \(title(for: configuration.source)) | \(configuration.name)"
				+ " | \(configuration.commandLine) | in \(configuration.workingDirectory)")
		}

		guard let configuration = runConfigurations.first(where: { $0.name == name }) else {
			say("nothing called \(name)")
			return
		}

		say("starting \(configuration.name)")
		run(configuration)

		// Twice, because how long this takes is not knowable from here: a warm
		// `swift run` is a second and a cold one compiles the world. The first
		// reading says the run started, the second says how it ended.
		for (index, delay) in [8.0, 40.0].enumerated() {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
				guard let self else { return }
				say("after \(Int(delay))s, console \(self.panel.runConsolesForTesting)")
				say("after \(Int(delay))s: "
					+ self.panel.activeTerminalTailForTesting(lines: index == 0 ? 6 : 14))
			}
		}
	}

	/// The one run mark, kept between menus and remade when the zoom changes.
	static var cachedRunMark: (scale: CGFloat, image: NSImage?) = (0, nil)

	/// The mark on a menu item that will run something, in place of a tick.
	///
	/// A ticked list is what a settings menu looks like — "Word Wrap", "Show
	/// Invisibles", things somebody turns on — and neither the schemes nor the
	/// destinations under them are that: clicking one runs the app. The glyph is
	/// the play button's own, in the play button's own green, so the menu and
	/// the button it hangs off say the same thing. It goes in the tick's column
	/// rather than beside the title, which is what keeps the titles lined up
	/// with each other and with the headings above them.
	///
	/// One image rather than one per item, which is also what lets a printed
	/// dump tell a run mark from a tick.
	static func runMark() -> NSImage? {
		let scale = Theme.current.scale
		if cachedRunMark.scale == scale { return cachedRunMark.image }
		let image = Theme.symbol("play.fill", size: 10 * scale, color: Theme.current.gitAdded)
		// Not a template: AppKit re-tints a template state image with the menu's
		// own ink, and the colour is half of what this glyph is for.
		image?.isTemplate = false
		cachedRunMark = (scale, image)
		return image
	}

	/// Marks the one item a click would actually start, the way the tick used to.
	///
	/// The tick is left alone if there is no glyph to put there: a menu item
	/// whose on-state image is nil shows nothing at all, and an unmarked list is
	/// worse than the one this was meant to fix.
	func markWillRun(_ item: NSMenuItem, _ willRun: Bool) {
		item.state = willRun ? .on : .off
		if let mark = RunCoordinator.runMark() { item.onStateImage = mark }
	}

	func title(for source: RunConfiguration.Source) -> String {
		switch source {
		case .intelliJ:  return "IntelliJ"
		case .vscode:    return "VS Code"
		case .make:      return "Make"
		case .goModule:  return "Go"
		case .maven:     return "Maven"
		case .gradle:    return "Gradle"
		case .javaMain:  return "Java"
		case .xcodeScheme: return "Schemes"
		case .swiftPackage: return "Swift Package"
		case .bazel:     return "Bazel"
		case .conan:     return "Conan"
		}
	}

	/// What the project defines, plus a suggestion when it defines nothing.
	var launchConfigurations: [LaunchConfiguration] {
		guard currentProject() != nil else { return [] }
		return LaunchStore.read(in: currentLaunchRoot())
	}

	/// What the play button is pointed at, decided in one place.
	///
	/// The strip and the button used to work this out separately, and disagreed
	/// exactly where it mattered: with a Makefile goal chosen in a project that
	/// has launch configurations of its own, the strip fell back to the first
	/// configuration while the button ran the goal.
	var runTarget: RunSelection.Target {
		RunSelection.resolve(
			configurations: launchConfigurations.map(\.name),
			makeRun: selectedMakeRun?.name,
			selected: selectedConfigurationName
		)
	}

	var selectedConfiguration: LaunchConfiguration? {
		guard case let .configuration(name) = runTarget else { return nil }
		return launchConfigurations.first { $0.name == name }
	}

	func refreshRunControl() {
		runControl?.setConfiguration(RunSelection.displayName(
			configurations: launchConfigurations.map(\.name),
			makeRun: selectedMakeRun?.name,
			selected: selectedConfigurationName
		))
		refreshLaunchNotice()
	}

	/// Says up front when the selected launch could not be debugged here.
	///
	/// Everything this asks is a `PATH` lookup or a jar on disk. Pressing Debug
	/// without it started a JVM, suspended it on a port, spent the classpath scan
	/// and *then* said that no debugger was ever going to arrive — the same
	/// information, after the wait, about a JVM now stuck waiting for it.
	func refreshLaunchNotice() {
		guard let project = currentProject(), let selection = selectedJavaDebuggableLaunch() else {
			editor.activeGroup?.setLaunchNotice(nil)
			return
		}
		_ = selection
		editor.activeGroup?.setLaunchNotice(
			LanguageService.shared.javaDebugNotice(project: project.root)
		)
	}

	/// The selected configuration, when debugging it would go through jdtls.
	///
	/// Which is any configuration whose debugger is the Java one, and any whose
	/// program is a wrapper script — `mvnw`, `gradlew`, a `#!` script — because
	/// those debug by asking the JVM the script starts to wait, and the adapter
	/// that then attaches lives inside jdtls. A configuration that is only ever
	/// run is included, and says so honestly: the strip is about what Debug
	/// would do, not about what Run is doing.
	func selectedJavaDebuggableLaunch() -> LaunchConfiguration? {
		guard let name = selectedConfigurationName,
		      let configuration = launchConfigurations.first(where: { $0.name == name })
		else { return nil }

		if configuration.adapterID == "java" { return configuration }
		guard let root = currentProject()?.root else { return nil }
		let program = configuration.expandedProgram(root: root)
		return ScriptLaunch.kind(ofProgramAt: program) != nil ? configuration : nil
	}

	/// Keeps the titlebar saying what the session is doing.
	func updateRunControl(for state: DebugSession.State, session: DebugSession?) {
		switch state {
		case .starting:
			runControl?.setStatus("Starting…", busy: true)
		case .running:
			runControl?.setStatus("Running", busy: true)
		case let .stopped(reason):
			runControl?.setStatus("Paused — \(reason)", busy: true)
		case .terminated:
			guard let code = session?.exitCode else {
				runControl?.setStatus("Finished")
				return
			}
			runControl?.setStatus(
				code == 0 ? "Finished — exit code 0" : "Failed — exit code \(code)",
				failed: code != 0
			)
		case .idle:
			runControl?.setStatus("")
		}
	}

	/// Runs or debugs what is selected.
	///
	/// A project with nothing configured gets one written for it from what is
	/// actually there, rather than a dialog asking a question nobody has the
	/// information to answer before the first run.
	/// Stops whichever of the two is running.
	func stopRunning() {
		// A launch still working its way through the cluster is the thing most
		// worth being able to stop: it is the part that waits.
		if let task = clusterTask {
			clusterTask = nil
			task.cancel()
			stopDevPodForwards()
			clusterLog("stopped")
			runControl?.setStatus("Stopped")
			return
		}
		if devPodClient != nil {
			stopDevPod()
			return
		}
		if let pane = runningPane {
			runningPane = nil
			pane.terminalView.terminateProcess()
			// The tab is showing a running program; it has just stopped being
			// one.
			panel.refreshTabs()
			runControl?.setStatus("Stopped")
			return
		}
		debugStop(nil)
	}

	/// Derives a launch configuration from the gutter's arrow and prints it.
	func saveGutterConfigurationForTesting(file: URL, line: Int) {
		let path = RunConfigurationDiscovery.canonicalPath(file)
		guard let discovered = runConfigurations.first(where: { $0.file == path && $0.line == line })
			?? runConfigurations.first
		else {
			print("GUTTER: nothing to run at \(file.lastPathComponent):\(line)")
			return
		}
		let item = NSMenuItem()
		item.representedObject = discovered.id
		saveGutterConfiguration(item)
		print("GUTTER: opened the editor for \(discovered.name)")
	}

	func showAttachPickerForTesting(filter: String) {
		onAttachToProcess(nil)
		guard !filter.isEmpty else { return }
		processPicker?.filterForTesting(filter)
		print("ATTACH: \(processPicker?.shownNamesForTesting.prefix(5).joined(separator: ", ") ?? "none")")
	}

	func runSelectedConfiguration(debug: Bool) {
		guard currentProject() != nil else { return }

		// A make goal nothing can debug runs as make runs it, in the terminal,
		// for both buttons: there is no debugger to offer and refusing to start
		// would be worse than starting without one.
		if case let .make(name) = runTarget, let goal = selectedMakeRun, goal.name == name {
			run(goal)
			return
		}

		guard let configuration = selectedConfiguration ?? createSuggestedConfiguration() else {
			notify(
				"Nothing to run",
				detail: "No launch configuration, and nothing recognisable to make one from."
			)
			return
		}
		selectedConfigurationName = configuration.name
		refreshRunControl()

		if debug {
			debugConfiguration(configuration, in: currentLaunchRoot())
		} else {
			runConfiguration(configuration, in: currentLaunchRoot())
		}
	}

	/// Runs the build and produces the environment a configuration needs, then
	/// hands both to whatever starts it.
	///
	/// Both steps are skipped by configurations that declare neither, which is
	/// every one written by hand — this is the price of a configuration
	/// derived from a Makefile, and only those pay it.
	func prepare(
		_ configuration: LaunchConfiguration,
		in root: URL,
		then start: @escaping ([String: String]) -> Void
	) {
		let evaluate = { [weak self] in
			guard let self else { return }
			let commands = configuration.environmentCommands
			guard !commands.isEmpty else {
				start(configuration.expandedEnvironment(root: root))
				return
			}

			self.runControl?.setStatus("Reading \(configuration.name)'s environment…", busy: true)
			Task { @MainActor in
				let directory = URL(
					fileURLWithPath: configuration.expandedWorkingDirectory(root: root)
				)
				let produced = await ShellEnvironment.evaluate(commands, in: directory)
				if !produced.failures.isEmpty {
					// Started anyway: the program is the one that knows whether
					// it can do without, and it says so better than a guess.
					self.notify(
						"Some environment could not be read",
						detail: produced.failures
							.map { "\($0.key): \($0.value.isEmpty ? "produced nothing" : $0.value)" }
							.sorted()
							.joined(separator: "\n")
					)
				}
				start(configuration.expandedEnvironment(root: root).merging(produced.values) { _, new in new })
			}
		}

		guard let step = configuration.makeStep else {
			evaluate()
			return
		}

		onSetPanelVisible(true)
		runControl?.setStatus("Building \(configuration.name)…", busy: true)
		let pane = panel.runCommand(
			title: "make",
			command: step.commandLine(root: root),
			directory: root,
			// The build console for this configuration, kept apart from the
			// console the program itself runs in.
			reusing: "build:\(configuration.id)"
		)
		runningPane = pane
		pane?.terminalView.onProcessExit = { [weak self, weak pane] code in
			MainActor.assumeIsolated {
				guard let self, self.runningPane === pane else { return }
				self.runningPane = nil
				guard code == 0 else {
					// Nothing starts on a failed build: what would run is the
					// last binary that built, which is the wrong one.
					self.runControl?.setStatus("Build failed — exit code \(code)", failed: true)
					return
				}
				evaluate()
			}
		}
	}

	/// Connects the debugger to the `dlv dap` the pod is now running.
	/// How a pod is named in the toolbar: the namespace and the pod, which is
	/// what `kubectl` would want to be told to find it again.
	func label(for pod: DevPodTarget) -> String {
		"\(pod.namespace)/\(pod.name)"
	}

	/// Runs, or debugs, the configuration on a line without going through the
	/// menu — which is a separate window the harness cannot reach.
	func invokeForTesting(line: Int, debug wantsDebug: Bool) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		let path = RunConfigurationDiscovery.canonicalPath(url)
		guard let configuration = runConfigurations.first(where: {
			$0.file == path && $0.line == line
		}) else { return }
		if wantsDebug { debug(configuration) } else { run(configuration) }
	}

	/// The chart that travels with the app.
	///
	/// Looked for by hand in every place it could be: inside the resource
	/// bundle a package target produces, beside the executable, inside the
	/// application bundle, and in the repository when running from a checkout.
	static var bundledChart: URL? {
		// `Bundle.module` is not used here. Its generated accessor calls
		// `fatalError` when it cannot find the resource bundle, so a build that
		// shipped without one does not fall back — it takes the app down, which
		// is what happened when somebody pressed run in a cluster.
		// SwiftPM names it `<package>_<target>.bundle`, so it followed the
		// rename: a stale name here is a run in a cluster that cannot find the
		// chart it ships with.
		let resource = "Abydos_AbydosApp.bundle"
		var candidates: [URL] = []

		if let main = Bundle.main.resourceURL {
			candidates.append(main.appendingPathComponent(resource))
			candidates.append(main)
		}
		// Beside the executable, which is where a plain `swift build` puts it.
		let beside = Bundle.main.bundleURL.deletingLastPathComponent()
		candidates.append(beside.appendingPathComponent(resource))
		candidates.append(Bundle.main.bundleURL.appendingPathComponent(resource))
		// Running from the repository, where the source is the chart.
		candidates.append(
			URL(fileURLWithPath: #filePath)
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.appendingPathComponent("DevPod")
		)

		let manager = FileManager.default
		for candidate in candidates {
			for chart in [
				candidate.appendingPathComponent("devpod-chart"),
				candidate.appendingPathComponent("Contents/Resources/devpod-chart"),
				candidate.appendingPathComponent("chart/abydos-devpod"),
			] where manager.fileExists(atPath: chart.appendingPathComponent("Chart.yaml").path) {
				return chart
			}
		}
		return nil
	}

	static func describe(devPod error: any Error) -> String {
		switch error {
		case let refusal as ContextRefusal:
			return refusal.message
		case let failure as DevPodClient.Failure:
			switch failure {
			case let .unreachable(reason): return reason
			case let .refused(code, body): return "The pod answered \(code): \(body)"
			case let .wrongArchitecture(binary, pod):
				return "Built for \(binary), but the pod runs \(pod)"
			}
		case let failure as DevPodBuild.Failure:
			switch failure {
			case .noToolchain: return "No Go toolchain was found"
			case let .failed(output): return output
			case let .unsupported(reason): return reason
			}
		case let failure as DevPodInstall.Failure:
			switch failure {
			case .noHelm:
				return "helm is not installed. The development pod is a chart, and helm is what installs it."
			case .noChart:
				return "The development pod's chart is missing from this build of Abydos."
			case let .failed(output):
				return output.isEmpty ? "helm failed and said nothing." : output
			}
		case let failure as PortForward.Failure:
			switch failure {
			case .noKubectl: return "kubectl is not installed"
			case .noFreePort: return "No local port was free"
			case .timedOut: return "kubectl did not answer"
			case let .failed(reason): return reason
			}
		default:
			return error.localizedDescription
		}
	}

	/// What a derived configuration will actually do, in a sentence or three.
	static func describe(_ configuration: LaunchConfiguration, root: URL) -> String {
		var lines: [String] = []
		if let step = configuration.makeStep {
			lines.append("Builds with make \(step.targets.joined(separator: " ")) first.")
		}
		lines.append("Debugs \(configuration.program) with the arguments the recipe passes.")
		if !configuration.environmentCommands.isEmpty {
			let names = configuration.environmentCommands.keys.sorted().joined(separator: ", ")
			lines.append("\(names) come from the shell each time it starts.")
		}
		return lines.joined(separator: "\n")
	}


	/// Starts the native debugger on a configuration's package.
	func debug(_ configuration: RunConfiguration) {
		guard configuration.isDebuggable else { return }

		// Java does not go through Delve, and it does not go through a program
		// at all: the adapter is inside the language server.
		if configuration.source == .javaMain, let mainClass = configuration.mainClass {
			startJavaDebug(
				name: configuration.name,
				mainClass: mainClass,
				anchorFile: configuration.file.map { URL(fileURLWithPath: $0) },
				workingDirectory: URL(fileURLWithPath: configuration.workingDirectory),
				arguments: [],
				environment: configuration.environment
			)
			return
		}

		guard let delve = GoTooling.findDelveExecutable() else {
			notify(
				"Delve is not installed",
				detail: "Install it with: go sidebar.install github.com/go-delve/delve/cmd/dlv@latest"
			)
			return
		}
		// Delve is told the directory, which is where the package lives.
		startNativeDebugger(delve: delve, package: configuration.workingDirectory)
	}

	/// Runs the tests with coverage, and reports what they covered.
	///
	/// The tests rather than the program: coverage is a property of a test run,
	/// and a program run by hand covers whatever the person doing it happened
	/// to touch.
	func runSelectedWithCoverage() {
		guard let root = currentProject()?.root else { return }
		guard FileManager.default.fileExists(atPath: root.appendingPathComponent("go.mod").path) else {
			notify(
				"Coverage is Go-only so far",
				detail: "This project has no go.mod. Coverage for other languages is not built yet.",
				kind: .information
			)
			return
		}

		let profile = AbydosFolder.url(in: root).appendingPathComponent("coverage.out")
		_ = try? AbydosFolder.create(in: root)
		onSetPanelVisible(true)
		panel.runCommand(
			title: "coverage",
			command: "go test ./... -coverprofile='\(profile.path)' -covermode=atomic"
				+ " && echo && go tool cover -func='\(profile.path)' | tail -30",
			directory: root,
			reusing: "coverage:\(root.path)"
		)
	}

	@objc func openLaunchFile() {
		guard currentProject() != nil else { return }
		let file = LaunchFile.url(in: currentLaunchRoot())
		guard FileManager.default.fileExists(atPath: file.path) else {
			notify("No launch.json yet", detail: "Press run once and one will be written.", kind: .information)
			return
		}
		editor.open(fileURL: file, focusEditor: true)
	}

	@objc func addConfiguration() {
		guard let project = currentProject() else { return }
		let suggestion = LaunchFile.suggestion(for: currentLaunchRoot())
			?? LaunchConfiguration(name: project.name, type: "lldb", program: "${workspaceFolder}")
		presentConfigurationEditor(suggestion, isNew: true)
	}

	/// The shared Java scan, from a thread that is not in an async context.
	///
	/// Discovery runs on a `DispatchQueue`, and the cache that keeps a second
	/// scan from starting is an actor. A semaphore is the bridge between the two,
	/// and blocking here is the intended behaviour: this queue exists to wait for
	/// exactly this. It is not a cooperative-pool thread, so nothing starves.
	/// `nonisolated` because it is called off the main queue and blocks there
	/// on purpose — which the comment above already says and the type did not.
	/// It was `private` on a `@MainActor` class before, where the same call
	/// went unremarked.
	nonisolated static func awaitingMainClasses(
		in root: URL, forgetting forget: Bool
	) -> [JavaTooling.MainClass] {
		let gate = DispatchSemaphore(value: 0)
		// A box rather than a captured `var`: the write happens on whichever
		// thread the task finishes on, and the read after `wait()` is ordered
		// after it by the semaphore.
		final class Box: @unchecked Sendable { var value: [JavaTooling.MainClass] = [] }
		let box = Box()
		Task.detached {
			if forget { await JavaTooling.forgetMainClasses(in: root) }
			box.value = await JavaTooling.mainClassesOffMain(in: root)
			gate.signal()
		}
		gate.wait()
		return box.value
	}

	nonisolated(unsafe) static var runConfigurationTallyForTesting = RunConfigurationTally()


	/// What the scan has been asked for and what it actually did, for
	/// `--report-open`.
	///
	/// Three numbers rather than one, because the fix has two halves and only
	/// separate counts say which half is working: `asked` is how often something
	/// wanted a scan, `skipped` is how many of those wrote nothing that could
	/// define a configuration, and `walked` is how many whole-project walks
	/// actually happened. Before 0446 the three were equal by construction.
	struct RunConfigurationTally {
		var asked = 0
		var skipped = 0
		var coalesced = 0
		var walked = 0
	}
}

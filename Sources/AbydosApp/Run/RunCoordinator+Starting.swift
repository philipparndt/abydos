import AppKit
import AbydosKit

/// Starting a program under a debugger, and replacing its code while it runs.
///
/// Part of `RunCoordinator`. Split off because the whole of it does not fit in
/// one file and this is where the seam is: everything here is about a session
/// that is already going or about to.
extension RunCoordinator {
	/// Starts the native debugger and wires its state to the editor.
	func startNativeDebugger(delve: String, package: String) {
		// The Go menu reaches this without passing the run control's own
		// verbs — one more door to the same place, gated here rather than at
		// the two callers, for the reason the others were moved down.
		guard mayRunProjectCode() else { return }
		onSetPanelVisible(true)
		// The titlebar follows the session from here on — `wire` reports every
		// state change to it — but the gap before the adapter answers is worth
		// filling, or pressing debug looks like it did nothing.
		runControl?.setStatus("Starting…", busy: true)
		// Breakpoints go in with the session, not after it: the adapter only
		// asks for them once, immediately after launch.
		guard let session = panel.startDebugging(
			delve: delve,
			package: package,
			breakpoints: debugCoordinator()?.pendingBreakpoints ?? [:]
		) else { return }
		onWire(session)
	}

	func startRun(
		_ configuration: LaunchConfiguration,
		in root: URL,
		environment: [String: String]
	) {
		let program = configuration.expandedProgram(root: root)
		let directory = configuration.expandedWorkingDirectory(root: root)
		let arguments = configuration.expandedArguments(root: root)

		onSetPanelVisible(true)
		runControl?.setStatus("Running \(configuration.name)…", busy: true)

		// A Go configuration names a package, which is `go run`'s argument; any
		// other names a binary, which is simply executed.
		//
		// Except a script, whatever the type says. `go` is the default type a new
		// configuration is written with, so a configuration somebody pointed at
		// `./mvnw` and did not change the type of ran as `go run ./mvnw` — which
		// fails in Go's words about a directory that is not a package, and is the
		// same fault as handing the script to LLDB: believing the type over the
		// file.
		let isScript = ScriptLaunch.kind(ofProgramAt: program) != nil
		let words = configuration.type == "go" && !isScript
			? ["go", "run", program] + arguments
			: [program] + arguments
		let pane = panel.runCommand(
			title: configuration.name,
			command: words.map(Self.shellQuoted).joined(separator: " "),
			directory: URL(fileURLWithPath: directory),
			environment: environment,
			reusing: "run:\(configuration.id)"
		)
		// The shell reports what the program exited with, which is the one thing
		// worth saying in the titlebar once it is over.
		followRunningPane(pane)
	}

	/// Runs a wrapper script with JDWP asked for, then attaches to the JVM.
	///
	/// The same two halves as debugging in a pod, which is the flow this follows:
	/// something elsewhere is started with its port open and suspended, and the
	/// adapter inside the language server connects to it so the sources on screen
	/// are the ones on this disk. What differs is that "elsewhere" is a child of
	/// a shell script on this machine rather than a container, so there is no
	/// port-forward and nothing to tell us when the JVM is up — the port is
	/// opened by a grandchild this app never sees, and is polled for.
	///
	/// The script runs in an ordinary run pane, not swallowed by the debugger:
	/// what Maven and Gradle print while they resolve and compile is most of what
	/// there is to read when a launch does not work, and `internalConsole` would
	/// have shown none of it.
	func startScriptDebug(
		_ configuration: LaunchConfiguration,
		kind: ScriptLaunch.Kind,
		in root: URL,
		environment: [String: String]
	) {
		let program = configuration.expandedProgram(root: root)
		let directory = configuration.expandedWorkingDirectory(root: root)

		// Gradle's port is Gradle's, so a stale JVM holding it is a thing that
		// can happen and has to be said. For everyone else the kernel picks.
		let port: Int
		if kind == .gradle {
			port = ScriptLaunch.gradleDebugPort
			if DebugPort.isOpen(port) {
				notify(
					"Something is already on port \(port)",
					detail: "Gradle's --debug-jvm always uses \(port) and cannot be told another. "
						+ "A JVM left suspended by an earlier launch is the usual reason; stop it "
						+ "and try again."
				)
				return
			}
		} else if let free = DebugPort.free() {
			port = free
		} else {
			notify("No free port", detail: "The debugger needs a local port and the kernel had none.")
			return
		}

		let plan = ScriptLaunch.plan(
			kind: kind,
			port: port,
			environment: environment,
			arguments: configuration.expandedArguments(root: root)
		)

		onSetPanelVisible(true)
		runControl?.setStatus("Starting \(configuration.name)…", busy: true)

		let words = [program] + plan.arguments
		let pane = panel.runCommand(
			title: configuration.name,
			command: words.map(Self.shellQuoted).joined(separator: " "),
			directory: URL(fileURLWithPath: directory),
			environment: plan.environment,
			reusing: "run:\(configuration.id)"
		)
		followRunningPane(pane)
		// Said in the debug console rather than only in the status line: it is
		// the one record of what was actually arranged, and the command in the
		// run pane does not show it — the option went into the environment.
		panel.showDebug()?.appendOutput(plan.note + "\n")

		scriptDebugExit = nil
		runControl?.setStatus(
			"Waiting for the JVM on \(plan.port)…", busy: true, preparing: true
		)

		// Detached, and that is the point rather than a detail: the poll blocks a
		// thread for up to a quarter of a second at a time and keeps it up for
		// two minutes, and a `Task { @MainActor in … }` here would inherit this
		// window's actor and make that thread the one drawing. A launch that is
		// waiting has to leave the project usable — the wait is for a grandchild
		// process, and nothing about it belongs on the main thread.
		let waitedPort = plan.port
		let waiter = Task.detached { [weak self] in
			let opened = await DebugPort.waitUntilOpen(waitedPort)
			await self?.scriptDebugFinished(
				opened: opened, configuration: configuration, kind: kind, port: waitedPort, root: root
			)
		}

		// The poll above is waiting for a JVM that this process starts. Once the
		// process itself is gone, no JVM is coming and there is nothing left to
		// wait for — so stop, rather than spending the rest of the two minutes
		// saying "Waiting for the JVM" about something that has already failed.
		//
		// That is how a duplicate JDWP option in MAVEN_OPTS presented: VM
		// initialisation refused it in the first second, and the window then sat
		// on "Waiting for the JVM on 49565…" for two minutes before offering
		// advice about forked goals, which had nothing to do with it. The
		// handler is taken and called on rather than replaced, the way
		// `followRunningPane` does it, so the run tab still learns its process
		// has gone.
		let followHandler = pane?.terminalView.onProcessExit
		pane?.terminalView.onProcessExit = { [weak self] code in
			followHandler?(code)
			MainActor.assumeIsolated {
				self?.scriptDebugExit = code
				waiter.cancel()
			}
		}
	}


	/// What to do once the wait for the script's JVM is over, however it ended.
	///
	/// A method rather than the tail of the detached task's closure: the closure
	/// runs off the main actor and everything here belongs on it, and reaching
	/// back into a weakly captured `self` from inside a nested `MainActor.run`
	/// is a captured-var reference that Swift 6 makes an error.
	@MainActor
	func scriptDebugFinished(
		opened: Bool,
		configuration: LaunchConfiguration,
		kind: ScriptLaunch.Kind,
		port: Int,
		root: URL
	) {
		guard opened else {
			// Three ways this ends badly now, and the first is the one that used
			// to be reported as one of the other two.
			if let code = scriptDebugExit {
				runControl?.setStatus(
					"Exited with code \(code) before opening \(port)", failed: true
				)
				notify(
					"\(configuration.name) exited before the JVM opened port \(port)",
					detail: "Exit code \(code). Whatever it printed is in the run pane — the "
						+ "script never got as far as a JVM, so none of the advice about which "
						+ "goal forks one applies."
				)
				return
			}
			// Deliberately specific about the two ways this ends badly, because
			// they need opposite things done about them.
			runControl?.setStatus("The JVM never opened \(port)", failed: true)
			notify("Nothing opened port \(port)", detail: Self.scriptDebugAdvice(for: kind))
			return
		}
		attachToScriptJVM(configuration, port: port, root: root)
	}

	/// Connects the Java debugger to a JVM that is up and waiting.
	func attachToScriptJVM(
		_ configuration: LaunchConfiguration, port: Int, root: URL
	) {
		Task { @MainActor in
			// The anchor decides which module's classpath jdtls answers about, so
			// it is chosen against *this configuration's* working directory rather
			// than taken from the front of the project's list — see
			// `JavaTooling.nearestFile`.
			//
			// From what discovery already found, rather than by reading every
			// source file in the project again. `refreshRunConfigurations` walks
			// the project off the main thread when it opens and again when files
			// change, and every Java entry it returns carries the file its `main`
			// is in — so the answer is already in hand and cost nothing to get.
			//
			// Pressing Debug used to spend that walk a second time: tens of
			// thousands of file reads on a large repository, in the seconds right
			// after the JVM had suspended itself waiting for us.
			let directory = configuration.expandedWorkingDirectory(root: root)
			var anchor = JavaTooling.nearestFile(
				to: directory,
				among: runConfigurations.filter { $0.source == .javaMain }.compactMap(\.file)
			).map { URL(fileURLWithPath: $0) }

			// Only if discovery has not run yet, or found none — a project opened
			// a moment ago, which is exactly when somebody presses Debug.
			//
			// **Any Java file in the module will do, and a main class is not needed
			// to find one.** The anchor names a module and nothing more: jdtls
			// answers about the project the file belongs to. Asking for a main class
			// meant reading every source file in the repository — 96–139 s on a
			// checkout of 13,754 of them, to reach the seven that had a `main` —
			// while the JVM sat suspended waiting for the debugger being arranged
			// here.
			//
			// So it is asked for in two ways, better one first. A configuration that
			// names a module is anchored by a file from that module, which is a few
			// `stat`s and is *precise*. A configuration whose directory is the
			// project root names no module and gives nothing to be precise about:
			// the cheap search would answer with whichever module the walk reached
			// first, which on the repository this was measured on was a
			// build-tooling module nobody was debugging. The main classes are the
			// better signal for that case — and now that the scan behind them is
			// seconds and shared rather than minutes and repeated, it is one worth
			// paying for.
			if anchor == nil, FilePath.canonicalEvenIfMissing(URL(fileURLWithPath: directory))
				!= FilePath.canonical(root) {
				runControl?.setStatus("Finding the module to debug…", busy: true, preparing: true)
				// Detached: bounded, but still a directory walk, and this is the main
				// actor.
				anchor = await Task.detached {
					JavaTooling.nearestJavaFile(
						to: URL(fileURLWithPath: directory), under: root
					)
				}.value.map { URL(fileURLWithPath: $0) }
			}
			if anchor == nil {
				runControl?.setStatus("Looking for the class to debug…", busy: true, preparing: true)
				let scanned = await JavaTooling.mainClassesOffMain(in: root).map(\.file)
				anchor = JavaTooling.nearestFile(to: directory, among: scanned)
					.map { URL(fileURLWithPath: $0) }
			}
			// Said in the debug console, beside the plan: which file the classpath
			// was asked about is the difference between debugging this module and
			// debugging whichever one sorted first, and it is not visible anywhere
			// else.
			if let anchor {
				panel.showDebug()?.appendOutput(
					"Classpath from \(MakeLaunch.relativeToWorkspace(anchor, root: root))\n"
				)
			}

			// The class files and the server's own port together, as the pod
			// attach does: a frame from the JVM then lands on the source it was
			// compiled from rather than on a decompiled stub.
			let target: LanguageService.JavaLaunchTarget
            do {
				target = try await LanguageService.shared.javaLaunchTarget(
					project: root,
					anchor: anchor,
					saying: { sentence in
						self.runControl?.setStatus(sentence, busy: true, preparing: true)
					}
				)
			} catch {
				runControl?.setStatus("Java cannot be debugged yet", failed: true)
				// The error already says which of the several reasons it was —
				// jdtls not installed, the java-debug bundle missing, an import
				// still running, a classpath with nothing in it — and each wants
				// something different done about it. `JavaDebugFailure` spells
				// every one of them out; reporting one sentence about readiness
				// instead threw that away and sent somebody looking at a language
				// server that was never on the machine.
				notify(
					"Java cannot be debugged here",
					detail: error.localizedDescription
						+ "\n\nThe JVM is waiting on port \(port) until a debugger arrives or you "
						+ "stop it."
				)
				return
			}

			var request = JavaDebug.Request(kind: .attach)
			request.host = "127.0.0.1"
			request.port = port
			request.classPaths = target.classPaths
			request.projectName = target.projectName

			guard let session = panel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: target.port, request: request),
				breakpoints: debugCoordinator()?.pendingBreakpoints ?? [:]
			) else { return }
			onWire(session)
		}
	}

	func debugConfiguration(_ configuration: LaunchConfiguration, in root: URL) {
		guard mayRunProjectCode() else { return }
		prepare(configuration, in: root) { [weak self] environment in
			guard let self else { return }
			if configuration.devPod != nil {
				self.runInCluster(configuration, in: root, environment: environment, debug: true)
			} else {
				self.startDebug(configuration, in: root, environment: environment)
			}
		}
	}

	func startDebug(
		_ configuration: LaunchConfiguration,
		in root: URL,
		environment: [String: String]
	) {
		// **The last door before a debugger runs the project's program**, and
		// the one that was missing: the gutter's own debug went through
		// `debug(_:)` rather than `debugConfiguration(_:in:)`, so an untrusted
		// project was photographed paused at a breakpoint. A check at the top
		// of one route is a check the other routes walk past — so it is here
		// too, where there is no route left.
		guard mayRunProjectCode() else { return }
		// A script before anything else, because the thing it is *not* is what
		// the rest of this function assumes: a file a debugger can open. Handing
		// `./mvnw` to lldb-dap got "is not a valid executable" — true, and about
		// the wrong program. What a wrapper script has to be debugged through is
		// the JVM it eventually starts.
		if let kind = ScriptLaunch.kind(ofProgramAt: configuration.expandedProgram(root: root)) {
			// The JVM option variables are resolved against the shell that will run
			// the command before the plan is made, so that the plan can both take
			// the agents out of them and add its own without losing what was
			// there. See `ShellEnvironment.values(of:in:)` for why this app's own
			// environment is the wrong thing to ask.
			Task { @MainActor in
				let directory = URL(
					fileURLWithPath: configuration.expandedWorkingDirectory(root: root)
				)
				let known = ScriptLaunch.jvmOptionVariables.filter { environment[$0] == nil }
				let fromShell = await ShellEnvironment.values(of: known, in: directory)
				self.startScriptDebug(
					configuration,
					kind: kind,
					in: root,
					environment: environment.merging(fromShell) { mine, _ in mine }
				)
			}
			return
		}

		let adapter = DebugAdapters.adapter(id: configuration.adapterID) ?? DebugAdapters.lldb

		// Nothing to find on disk for Java: the adapter is started by the
		// language server, which is either running or is the thing to fix.
		if adapter.transport == .languageServer {
			guard let mainClass = configuration.javaMainClass else {
				notify(
					"This configuration does not say what to start",
					detail: "A Java configuration needs a mainClass — the fully qualified name of "
						+ "the class with the main method."
				)
				return
			}
			startJavaDebug(
				name: configuration.name,
				mainClass: mainClass,
				anchorFile: nil,
				workingDirectory: URL(fileURLWithPath: configuration.expandedWorkingDirectory(root: root)),
				arguments: configuration.expandedArguments(root: root),
				vmArguments: configuration.javaVMArguments,
				environment: environment
			)
			return
		}

		guard let executable = DebugAdapters.executable(for: adapter) else {
			notify("\(adapter.name) is not installed", detail: adapter.installHint)
			return
		}

		onSetPanelVisible(true)
		runControl?.setStatus("Debugging \(configuration.name)…", busy: true)
		guard let session = panel.startDebugging(
			adapter: adapter,
			executable: executable,
			start: .launch(
				program: configuration.expandedProgram(root: root),
				arguments: configuration.expandedArguments(root: root),
				workingDirectory: URL(
					fileURLWithPath: configuration.expandedWorkingDirectory(root: root)
				),
				environment: environment
			),
			breakpoints: debugCoordinator()?.pendingBreakpoints ?? [:]
		) else { return }
		onWire(session)
	}

	/// Starts a Java debug session.
	///
	/// Two things have to come from a Java language server and neither can be
	/// worked out here: the port its debug adapter is listening on, and the
	/// classpath of the module the class belongs to. A JVM started without the
	/// second one fails with `ClassNotFoundException` on the class it was asked
	/// to run, which reads like the class is missing rather than the classpath.
	///
	/// **Which server that is may not be the one editing.** Since 0452, a project
	/// that chose the fast Java server for editing gets a jdtls started here for
	/// the debugger alone — and the wait for its import is what pressing Debug
	/// costs on a large project. So the status line says what is being waited for
	/// while it happens, in the server's own words where it has any: a spinner
	/// that says nothing looks exactly like a debugger that has hung.
	func startJavaDebug(
		name: String,
		mainClass: String,
		anchorFile: URL?,
		workingDirectory: URL,
		arguments: [String],
		vmArguments: [String] = [],
		environment: [String: String]
	) {
		guard let project = currentProject() else { return }
		// The scope, because the adapter lives inside the language server and
		// the server for a subproject is filed under the subproject: asking the
		// repository above it gets `noServer` in a checkout of several.
		let root = project.scopeRoot

		onSetPanelVisible(true)
		runControl?.setStatus("Debugging \(name)…", busy: true)

		Task { @MainActor in
			// Any file in the module will do — the question is about the project
			// the file belongs to, not the file — so the class's own source is
			// used when there is one and any main class in the project otherwise.
			// The scan reads every source file in the project, and this closure is
			// on the main actor: called synchronously here it was the whole-repository
			// walk on the main thread, which is a beach ball rather than a slow status
			// — 96–139 s of one on the checkout this was measured on. `mainClasses`
			// says as much in its own documentation.
			var anchor = anchorFile
			if anchor == nil {
				anchor = await JavaTooling.mainClassesOffMain(in: root)
					.first { $0.name == mainClass }
					.map { URL(fileURLWithPath: $0.file) }
			}

			let target: LanguageService.JavaLaunchTarget
			do {
				target = try await LanguageService.shared.javaLaunchTarget(
					project: root,
					anchor: anchor,
					// Strongly, because the `Task` around this already holds self
					// and a weak capture inside one buys nothing.
					saying: { sentence in
						self.runControl?.setStatus(sentence, busy: true)
						self.panel.showDebug()?.appendOutput(sentence + "\n")
					}
				)
			} catch {
				runControl?.setStatus("Java cannot be debugged yet", failed: true)
				// The missing bundle gets the whole manual rather than one line:
				// it is the one failure here nobody can guess the fix for.
				var detail = error.localizedDescription
				if let failure = error as? LanguageService.JavaDebugFailure, case .noBundle = failure {
					detail = JavaTooling.debugPluginManual
				}
				if let failure = error as? JavaDebugHost.Failure, case .noBundle = failure {
					detail = JavaTooling.debugPluginManual
				}
				notify("Java cannot be debugged yet", detail: detail)
				return
			}

			runControl?.setStatus("Debugging \(name)…", busy: true)
			let request = JavaDebug.Request(
				kind: .launch,
				mainClass: mainClass,
				classPaths: target.classPaths,
				projectName: target.projectName,
				workingDirectory: workingDirectory.path,
				arguments: arguments,
				vmArguments: vmArguments,
				environment: environment
			)
			guard let session = panel.startDebugging(
				adapter: DebugAdapters.java,
				executable: DebugAdapters.java.command,
				start: .java(host: "127.0.0.1", port: target.port, request: request),
				breakpoints: debugCoordinator()?.pendingBreakpoints ?? [:]
			) else { return }
			onWire(session)
		}
	}

	/// Says what a swap into the running JVM did.
	///
	/// **Most of these are refusals, and that is the JVM rather than a fault.**
	/// HotSpot replaces method bodies and nothing else, so adding a method,
	/// changing a signature, adding a field and changing what a class extends are
	/// all refused — which is most of what editing feels like. A report that said
	/// only "hot swap failed" would teach somebody to ignore it; one that carries
	/// the adapter's own sentence tells them why they are about to restart.
	func reportHotSwap(
		_ event: JavaDebug.HotSwap.Event, wasStopped: Bool, in session: DebugSession
	) {
		// Every stage in the log as well as the console. `BUILD_COMPLETE` with no
		// `END` after it is the shape of "the adapter compiled and then found
		// nothing to redefine", and telling that from "no events at all" is the
		// whole of diagnosing a swap that does not happen.
		DiagnosticLog.write(
			"java hot code replace: \(event.stage.rawValue) \(event.message ?? "")", to: "lsp"
		)
		// **`activeDebugPane` and not `showDebug()`, which was the fault.**
		// `showDebug()` ends in `activate(session, focus: true)` — it brings the
		// pane forward *and takes the keyboard*. Called once per hot-swap event,
		// that meant every save during a debug session pulled the focus out of
		// the editor: reported as "I lose focus whenever I save, as soon as the
		// application runs", and it is also why ⌘Z looked broken afterwards —
		// the undo history was never lost, the keyboard was somewhere else.
		//
		// Reporting is not a reason to move anybody's keyboard. The pane is
		// written into where it is; somebody who wants to look at it clicks it.
		let console = panel.activeDebugPane
		switch event.stage {
		case .starting:
			// Before anything has happened. In the console, where somebody
			// looking for it finds it, and not in the corner of the window — a
			// toast per save is a toast nobody reads.
			if let message = event.message { console?.appendOutput(message + "\n") }

		case .buildComplete:
			if let message = event.message { console?.appendOutput(message + "\n") }
			// **And now ask, which is the half that was missing.** The adapter
			// says the build is done and then waits: `AUTO` is this client's
			// policy about the event, not something the adapter acts on alone.
			// Sending it here rather than on the save is what makes the timing
			// right — the adapter knows when its compile finished and nothing
			// out here does.
			Task { @MainActor in
				guard let result = await session.redefineClasses() else { return }
				if let failure = result.errorMessage, !result.didSwap {
					self.reportHotSwap(
						JavaDebug.HotSwap.Event(stage: .error, message: failure),
						wasStopped: wasStopped, in: session
					)
					return
				}
				guard result.didSwap else { return }
				self.reportHotSwap(
					JavaDebug.HotSwap.Event(
						stage: .end,
						message: "Redefined " + result.changed.joined(separator: ", ")
					),
					wasStopped: wasStopped, in: session
				)
			}

		case .end:
			console?.appendOutput((event.message ?? "Classes redefined in the running JVM") + "\n")
			// **And the stack moved, which is the most confusing thing this
			// does.** The adapter drops to an affected frame and enters it
			// again, so somebody stopped in the method they just edited is
			// suddenly somewhere else. Not this app's behaviour to decline, and
			// unexplained it reads as the debugger losing its place.
			if JavaDebug.HotSwap.movedTheStack(event, wasStopped: wasStopped) {
				console?.appendOutput(
					"The frame you were stopped in was entered again, so the new body runs "
						+ "from its start.\n"
				)
			}

		case .warning:
			if let message = event.message { console?.appendOutput(message + "\n") }

		case .error:
			let detail = event.message ?? "The JVM would not take the change."
			console?.appendOutput(detail + "\n")
			// A session that cannot swap at all says so once — `cannotHotSwap`
			// is set by the session the first time a failure is about the session
			// rather than about the change, so this is the only time it is true
			// and unsaid.
			if session.cannotHotSwap {
				guard !saidThisSessionCannotHotSwap else { return }
				saidThisSessionCannotHotSwap = true
				notify(
					"This session cannot replace code",
					detail: detail + "\nSaving will not change the running program.",
					kind: .information
				)
				return
			}
			notify(
				"The JVM would not take that change",
				detail: detail + "\nIt replaces method bodies and nothing else.",
				kind: .warning,
				actionTitle: restartTitle(for: session),
				action: { [weak self] in self?.runSelectedConfiguration(debug: true) }
			)
		}
	}


	/// What the restart offer is about to restart.
	///
	/// **Named for an attached session, because it is somebody's service.**
	/// Restarting a JVM this app launched costs a process nobody else is using;
	/// restarting one in a pod is a different sentence and deserves to be read
	/// before it is pressed.
	func restartTitle(for session: DebugSession) -> String {
		session.isAttached ? "Restart the program being debugged" : "Restart the session"
	}



	func queueHotSwapCompile(project root: URL) {
		guard !hotSwapCompileRunning else {
			hotSwapCompileQueued = true
			return
		}
		hotSwapCompileRunning = true
		Task { @MainActor in
			_ = await LanguageService.shared.compileJavaForSwap(project: root)
			self.hotSwapCompileRunning = false
			if self.hotSwapCompileQueued {
				self.hotSwapCompileQueued = false
				self.queueHotSwapCompile(project: root)
			}
		}
	}

	/// What to try when the port never opened, which differs by wrapper.
	static func scriptDebugAdvice(for kind: ScriptLaunch.Kind) -> String {
		switch kind {
		case .maven:
			return "Maven ran but no JVM took the debug option. A forked goal starts a second JVM "
				+ "that does not inherit MAVEN_OPTS — Surefire needs it in argLine, Spring Boot in "
				+ "jvmArguments."
		case .gradle:
			return "Gradle ran but nothing forked a JVM. --debug-jvm only opens a port for a task "
				+ "that starts one, which means a JavaExec or Test task."
		case .script:
			return "The script ran but started no JVM under JAVA_TOOL_OPTIONS. If it starts the JVM "
				+ "through something that clears the environment, the option has to go in there "
				+ "instead."
		}
	}

	/// A word the shell will pass through as it was written.
	static func shellQuoted(_ word: String) -> String {
		guard word.contains(where: { !$0.isLetter && !$0.isNumber && !"-_./=:@".contains($0) })
		else { return word }
		return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}

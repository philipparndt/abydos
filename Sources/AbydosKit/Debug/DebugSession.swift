import Foundation

/// The session owns the debugger state and publishes it; views render whatever
/// it currently holds. Keeping it free of view code means the protocol
/// choreography — which requests must precede which, what has to be re-fetched
/// after a stop — is testable against a stub adapter.
public final class DebugSession {
	public enum State: Equatable, Sendable {
		case idle
		case starting
		case running
		case stopped(reason: String)
		case terminated
	}

	public private(set) var state: State = .idle {
		didSet {
			guard state != oldValue else { return }
			// **Nothing is drawn beside the code while nothing is stopped.**
			// A value that was true at the last breakpoint is not true a
			// microsecond after `continue`, and the editor draws it in the same
			// grey either way. Cleared here rather than in `resume`, `stepOver`,
			// `stepInto` and `stepOut` separately, which is four places to
			// forget.
			if case .stopped = state {} else { inlineValues = nil }
			let current = state
			onMain { [weak self] in
				guard let self else { return }
				for observer in self.stateObservers { observer(current) }
			}
		}
	}

	/// Where this is running, when that is not here.
	///
	/// A session in a pod looks exactly like one on this machine: the same
	/// toolbar, the same stack, the same variables — which is the point, and
	/// also how somebody comes to read a stack from a cluster believing it is
	/// their laptop. Nil means here, and here needs no saying.
	public var location: String?

	/// Breakpoints by file, kept across runs so they survive restarting.
	public internal(set) var breakpoints: [String: [Breakpoint]] = [:]

	public internal(set) var stackFrames: [StackFrame] = []
	public internal(set) var scopes: [Scope] = []
	/// What the editor should draw beside the code, or nil while nothing is
	/// stopped.
	///
	/// Built once per stop and per frame change rather than asked for per line:
	/// the names of a frame's variables are a dictionary, and a row's drawing is
	/// then a scan of that row's tokens against it. See `InlineValues`.
	public internal(set) var inlineValues: InlineValueSet?

	/// Frame whose variables are shown.
	public internal(set) var selectedFrameID: Int?

	/// Told whenever the state changes.
	///
	/// A list rather than one closure, because more than one thing genuinely
	/// needs to know: the pane enables its toolbar, the window clears the
	/// execution marker. With a single property the second assignment silently
	/// replaced the first, and the toolbar sat greyed out while the program was
	/// plainly stopped with a stack on screen.
	private var stateObservers: [(State) -> Void] = []
	/// Which stream the last output came from, and whether it ended a line.
	private var lastOutputCategory: String?
	private var outputAtLineStart = true

	public func observeState(_ observer: @escaping (State) -> Void) {
		stateObservers.append(observer)
	}
	public var onStackChanged: (() -> Void)?
	public var onVariablesChanged: (() -> Void)?
	public var onBreakpointsChanged: (() -> Void)?
	public var onOutput: ((String) -> Void)?
	/// Fired when execution stops somewhere with a source location.
	/// Told where execution stopped. A list, for the same reason as above.
	var stoppedObservers: [(String, Int) -> Void] = []

	public func observeStopped(_ observer: @escaping (String, Int) -> Void) {
		stoppedObservers.append(observer)
	}

	/// Told when the frame's variables have been read again. **A list, and it
	/// had to become one**: `onVariablesChanged` is a single closure and the
	/// debug pane sets it to rebuild its tree. The editor wants the same moment
	/// to draw the values beside the code, and a second `=` would have left
	/// whichever ran last as the only one told — silently, and looking exactly
	/// like a feature that does not work.
	private var variablesObservers: [() -> Void] = []

	public func observeVariables(_ observer: @escaping () -> Void) {
		variablesObservers.append(observer)
	}

	/// Everything that wants to know the variables changed, told at once.
	func sayVariablesChanged() {
		onMain { [weak self] in
			guard let self else { return }
			self.onVariablesChanged?()
			for observer in self.variablesObservers { observer() }
		}
	}

	let client: DAPClient
	private let projectRoot: URL
	var currentThreadID: Int?
	/// Which debugger is behind this session, once one has been started.
	public private(set) var adapter: DebugAdapter?

	/// What the program exited with, once it has.
	///
	/// "Finished" is the same word for a clean run and a crash, which is the
	/// one thing you want to know without reading the log.
	public private(set) var exitCode: Int?
	/// Bumped per launch so a stale watchdog cannot fire on a newer session.
	private var launchGeneration = 0

	/// How many times children have been asked for, for a driver to print.
	///
	/// **The claim this exists to check is a negative one**: scrolling a stopped
	/// file, with values beside every line that names one, asks the adapter for
	/// nothing. A request per hint per repaint is what would make a stopped
	/// editor unusable, and the only honest way to say it does not happen is to
	/// count.
	public internal(set) var childrenRequestsForTesting = 0

	/// Delivers a callback on the main thread.
	///
	/// The adapter's replies arrive on whatever executor the awaiting task
	/// resumes on — a cooperative-pool thread, not the main one — and every one
	/// of these callbacks ends up touching AppKit. Calling them from there
	/// modifies the layout engine off the main thread, which aborts the process
	/// rather than merely misbehaving.
	private func onMainLaunchStalled(_ message: String) {
		onMain { [weak self] in self?.onLaunchStalled?(message) }
	}

	func onMain(_ body: @escaping @Sendable () -> Void) {
		if Thread.isMainThread {
			body()
		} else {
			DispatchQueue.main.async(execute: body)
		}
	}

	public init(projectRoot: URL, client: DAPClient = DAPClient()) {
		self.projectRoot = projectRoot
		self.client = client
		wireEvents()
	}


	// MARK: - Session

	/// Launches `dlv dap` and runs the given package under it.
	/// Starts Delve on a Go package. Kept for the Go menu items.
	public func launch(delveExecutable: String, package: String) async throws {
		try await launch(
			adapter: DebugAdapters.delve,
			executable: delveExecutable,
			program: absolutePackagePath(package)
		)
	}

	/// Starts any adapter on any program.
	///
	/// The protocol is the same whichever debugger is behind it, so this is the
	/// same sequence for all of them: start it however it wants to be spoken
	/// to, shake hands, and send the request. What differs is a handful of
	/// strings, which the adapter itself supplies.
	public func launch(
		adapter: DebugAdapter,
		executable: String,
		program: String,
		arguments: [String] = [],
		workingDirectory directoryOverride: URL? = nil,
		environment: [String: String] = [:]
	) async throws {
		state = .starting
		launchGeneration += 1
		exitCode = nil
		saidTheSessionEnded = false
		self.adapter = adapter

		// Resolved against the project before anything is done with it. A
		// package is named relatively — "." or "cmd/server" — and resolving
		// that against the *app's* working directory pointed the debugger at
		// wherever ideai itself was started from, where the build failed with
		// nothing said about it.
		let program = absolutePackagePath(program)

		// A configuration may say where to run; otherwise the program's own
		// directory, because a build only works from inside its module or its
		// package and the project root often is neither.
		let workingDirectory = directoryOverride
			?? Self.directory(containing: program)
			?? projectRoot


		switch adapter.transport {
		case .socket:
			try await client.startListening(
				executable: executable,
				arguments: adapter.arguments,
				workingDirectory: workingDirectory
			)
		case .standardIO:
			try client.start(
				executable: executable,
				arguments: adapter.arguments,
				workingDirectory: workingDirectory
			)
		case .languageServer:
			// Nothing to spawn, and nothing this method can do about it: the
			// adapter is inside a language server that only the app layer holds.
			// `startJava` is the way in.
			state = .idle
			throw DAPClient.ClientError.adapterError(
				"\(adapter.name) is started by its language server, not from here."
			)
		}

		try await handshake(with: adapter)

		// Launch is sent before waiting for `initialized`; the adapter replies
		// to it once configuration is done, which is why it is not awaited.
		send("launch", watching: DebugAdapters.launchArguments(
			for: adapter,
			program: program,
			workingDirectory: workingDirectory.path,
			arguments: arguments,
			environment: environment
		))

		startLaunchWatchdog()
	}

	/// Debugs a native program that is stopped in a pod.
	///
	/// Delve is Go's and knows nothing about Zig, Odin, C, C++ or Rust, so what
	/// waits in the pod for those is gdbserver — and what talks to it is the
	/// LLDB on this machine, which speaks that protocol already. The binary
	/// stays here as well: it was built here, so its debug information points
	/// at the sources on this disk and every line lands where it should.
	public func attachNatively(
		adapter: DebugAdapter,
		executable: String,
		program: URL,
		host: String,
		port: Int
	) async throws {
		state = .starting
		launchGeneration += 1
		exitCode = nil
		saidTheSessionEnded = false
		self.adapter = adapter

		try client.start(
			executable: executable,
			arguments: adapter.arguments,
			workingDirectory: program.deletingLastPathComponent()
		)
		try await handshake(with: adapter)

		// `attachCommands` replaces LLDB's own idea of attaching, which is what
		// makes this a remote session: the target is the local binary and the
		// process is the one gdbserver is holding.
		send("attach", watching: [
			"request": "attach",
			"program": program.path,
			"attachCommands": [
				"target create \"\(program.path)\"",
				"gdb-remote \(host):\(port)",
			],
			"stopOnEntry": false,
		])
		startLaunchWatchdog()
	}

	/// Starts a session on a debugger that is already running somewhere else.
	///
	/// The pod's supervisor has `dlv dap` up and a forwarded port leads to it,
	/// so there is nothing to spawn: connect, shake hands, and say what to
	/// launch — which is a binary already sitting in the pod.
	public func launchRemotely(
		host: String,
		port: Int,
		program: String,
		arguments: [String] = [],
		workingDirectory: String? = nil,
		environment: [String: String] = [:]
	) async throws {
		state = .starting
		launchGeneration += 1
		exitCode = nil
		saidTheSessionEnded = false
		adapter = DebugAdapters.delve

		try await client.connect(host: host, port: port)
		try await handshake(with: DebugAdapters.delve)

		var request: [String: Any] = [
			"request": "launch",
			"mode": "exec",
			"program": program,
		]
		if !arguments.isEmpty { request["args"] = arguments }
		if let workingDirectory { request["cwd"] = workingDirectory }
		if !environment.isEmpty { request["env"] = environment }
		send("launch", watching: request)

		startLaunchWatchdog()
	}

	/// Starts a Java session on the adapter the language server put up.
	///
	/// There is nothing to spawn: jdtls has already started java-debug inside
	/// itself and answered with a port, so this dials it and says what to do.
	/// Both shapes go through here — launching a class on this machine and
	/// attaching to a JVM in a pod — because from this side they differ only in
	/// the request that follows the handshake.
	public func startJava(
		host: String = "127.0.0.1",
		port: Int,
		request: JavaDebug.Request
	) async throws {
		state = .starting
		launchGeneration += 1
		exitCode = nil
		saidTheSessionEnded = false
		adapter = DebugAdapters.java
		// What a restart would cost, recorded where the request says it: an
		// attach is a JVM somebody else started, and for this app that means one
		// in a pod.
		isAttached = request.kind == .attach

		try await client.connect(host: host, port: port)
		try await handshake(with: DebugAdapters.java)
		client.send(request.kind.rawValue, arguments: request.wireFormat)

		startLaunchWatchdog()
	}

	/// Attaches to a process that is already running.
	///
	/// The case launching cannot cover: a server that is already up, something
	/// started by a script, or a process that only misbehaves after an hour.
	public func attach(adapter: DebugAdapter, executable: String, pid: Int) async throws {
		state = .starting
		launchGeneration += 1
		exitCode = nil
		saidTheSessionEnded = false
		self.adapter = adapter

		switch adapter.transport {
		case .socket:
			try await client.startListening(
				executable: executable, arguments: adapter.arguments, workingDirectory: projectRoot
			)
		case .standardIO:
			try client.start(
				executable: executable, arguments: adapter.arguments, workingDirectory: projectRoot
			)
		case .languageServer:
			state = .idle
			throw DAPClient.ClientError.adapterError(
				"\(adapter.name) is started by its language server, not from here."
			)
		}

		try await handshake(with: adapter)
		send("attach", watching: DebugAdapters.attachArguments(for: adapter, pid: pid))
		startLaunchWatchdog()
	}

	/// The initialize request, which is the same for every adapter but for the
	/// name each one expects to be called.
	private func handshake(with adapter: DebugAdapter) async throws {
		_ = try await client.request("initialize", arguments: [
			"clientID": "ideai",
			"clientName": "ideai",
			"adapterID": adapter.adapterID,
			"pathFormat": "path",
			"linesStartAt1": true,
			"columnsStartAt1": true,
			"supportsVariableType": true,
			"supportsRunInTerminalRequest": false,
		])
	}

	/// The directory a program path names, or its parent when it is a file.
	static func directory(containing path: String) -> URL? {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
		let url = URL(fileURLWithPath: path)
		return isDirectory.boolValue ? url : url.deletingLastPathComponent()
	}

	/// Where a package sits, as a path go will accept.
	///
	/// Canonical, because go compares the directory it is asked to build
	/// against the module it resolved and refuses when they are spelled
	/// differently: a project opened as `/tmp/x` inside a module go knows as
	/// `/private/tmp/x` fails with "outside main module", which reads as a
	/// problem with the project and is not one.
	private func absolutePackagePath(_ package: String) -> String {
		if package.hasPrefix("/") { return FilePath.canonical(URL(fileURLWithPath: package)) }
		let trimmed = package.hasPrefix("./") ? String(package.dropFirst(2)) : package
		return FilePath.canonical(projectRoot.appendingPathComponent(trimmed))
	}

	public func stop() {
		// **The state changes now and the adapter is drained behind it.**
		//
		// It used to be `disconnect`, then `client.stop()` — which clears both
		// readability handlers before terminating anything, so the request just
		// sent was never read and nothing the adapter said afterwards arrived.
		// Two things arrive after `disconnect`: the adapter's last words, which
		// are what the console shows, and — for Delve — the exit status, which
		// it reports as the sentence `noteExitCode(inOutput:)` exists to parse
		// because it never sends an `exited` event. Killed first, the toolbar
		// showed a bare "Finished" where it had "Finished — exit code 0".
		//
		// Nothing waits on this thread. `DAPClient.stop` already carries a note
		// about a bounded busy-wait on the main queue being recorded as idle
		// time, and a second wait there would make that worse — so the panes
		// empty on the spot and the reply is somebody else's problem. The exit
		// code arriving a moment after the state is exactly the path
		// `noteExitCode` was written for when a program ends on its own.
		state = .terminated
		clearWhatTheProgramLeftBehind()
		client.disconnectThenStop { [weak self] answered in
			self?.sayTheSessionEnded(adapterAnswered: answered)
		}
	}

	/// How long the adapter took to answer the last `disconnect`, for the driven
	/// run that chooses the deadline.
	public var disconnectReplyTimeForTesting: TimeInterval? { client.lastDisconnectReply }

	/// The adapter's own ending, as against the user pressing Stop.
	///
	/// A named path rather than a case body, because there are exactly two ways
	/// a session ends and they must leave the same thing behind. Reachable from
	/// the tests for the same reason.
	func adapterSaidItEnded(body: [String: Any]) {
		// `exited` carries the code; `terminated` only says it is over, and the
		// two arrive in either order. Whichever came with a code is the one that
		// knows how it went.
		if let code = body["exitCode"] as? Int { exitCode = code }
		state = .terminated
		clearWhatTheProgramLeftBehind()

		// Delve sends neither `exited` nor a code, and only says how the program
		// went when asked to disconnect — which is where VS Code gets it from
		// too. Asking costs nothing: the session is over either way.
		guard exitCode == nil else {
			sayTheSessionEnded()
			return
		}

		// **And the console line waits for the answer**, rather than being
		// written now. Driven against Delve, a program that reaches its own end
		// produces this order:
		//
		//     total 6
		//     [Finished]                                ← written here, too early
		//     Process 97912 has exited with status 0
		//
		// The status lands a moment later, the toolbar picks it up — that is
		// what `noteExitCode` republishing `.terminated` is for — and the
		// console is left saying "Finished" beside a toolbar saying "Finished —
		// exit code 0". A line is appended once and cannot be taken back, so it
		// is written after the adapter has had its say.
		client.disconnectThenStop { [weak self] answered in
			self?.sayTheSessionEnded(adapterAnswered: answered)
		}
	}

	/// Ends the session without waiting for anybody, for a window that is closing.
	///
	/// **`stop()` returns before the adapter is dead**, which is right for the
	/// button — the panes answer at once and the draining happens behind them —
	/// and wrong for teardown. A window that closes takes the pane, the callback
	/// and any chance of finishing that work with it, so the adapter would be
	/// left running.
	///
	/// That is not untidiness. `DAPClient.stopNow` carries the reason at length:
	/// Foundation does not mark a pipe's descriptors close-on-exec, so an
	/// adapter that outlives its session holds open every pipe that existed when
	/// it started, and a stray one is enough to hang an unrelated `git` on a
	/// read that never reaches end of file. Two of them, left behind by a test,
	/// cost twenty minutes of a suite that should take fourteen seconds.
	///
	/// So this is the old `stop()`: ask, then kill, without waiting to be
	/// answered. Nothing is going to read the answer anyway.
	public func stopImmediately() {
		client.send("disconnect", arguments: ["terminateDebuggee": true])
		client.stop()
		state = .terminated
		clearWhatTheProgramLeftBehind()
	}

	/// Whether the console has already been told this session is over.
	///
	/// Two paths end a session — the stop button and the adapter's own
	/// `terminated`/`exited` — and both can be travelled for one session: a
	/// stopped program often produces the event as well. The line belongs on the
	/// console once.
	private var saidTheSessionEnded = false

	/// Writes the end of the session to the console, in the app's own words.
	///
	/// **Every word in that console is the adapter's**, which is why a session
	/// that ends quietly leaves a log that simply stops — and a log that stops
	/// cannot be told from one that is waiting. Delve's banner and "Building
	/// …" are already there, so a line about the session itself is in keeping.
	///
	/// The words are the toolbar's, because two sentences for one fact is how
	/// somebody comes to believe they are two facts.
	private func sayTheSessionEnded(adapterAnswered: Bool = true) {
		guard !saidTheSessionEnded else { return }
		saidTheSessionEnded = true

		let ending: String
		if !adapterAnswered {
			// Not a clean finish, and it must not be reported as one: the
			// adapter was killed, and whether the program went with it is a
			// question this cannot answer.
			ending = "Stopped \u{2014} the debug adapter did not answer, and was killed"
		} else if let exitCode {
			ending = exitCode == 0
				? "Finished \u{2014} exit code 0"
				: "Failed \u{2014} exit code \(exitCode)"
		} else {
			ending = "Finished"
		}

		// On its own line whatever the adapter left behind: Delve ends
		// "Building <path>" without a newline, which is what `outputAtLineStart`
		// is tracking.
		let text = (outputAtLineStart ? "" : "\n") + "[" + ending + "]\n"
		outputAtLineStart = true
		onMain { [weak self] in self?.onOutput?(text) }
	}

	/// Empties what the panes are showing about a program that has gone.
	///
	/// **One function because there are two paths to the same place** — the
	/// stop button, and the adapter's own `terminated`/`exited` — and they had
	/// different ideas about what is left over. Both emptied the frames and the
	/// scopes; neither touched `threads`, which is cleared by nothing anywhere
	/// in this file, so the goroutine list went on showing
	/// `* [Go 1] main.main (Thread 27093656)` for a process that had ended.
	///
	/// Emptying it is only half: `onThreadsChanged` is fired by `refreshThreads`
	/// and by nothing else, so a list emptied in silence is a table still
	/// drawing what it last had.
	private func clearWhatTheProgramLeftBehind() {
		stackFrames = []
		scopes = []
		inlineValues = nil
		threads = []
		selectedThreadID = nil
		onMain { [weak self] in
			self?.onStackChanged?()
			self?.onThreadsChanged?()
		}
		// Through the one function that tells everybody, so that a pane emptied
		// in silence cannot happen to the observers either.
		sayVariablesChanged()
	}

	// MARK: - Execution control

	public func resume() {
		guard let thread = currentThreadID else { return }
		client.send("continue", arguments: ["threadId": thread])
		state = .running
	}

	public func pause() {
		guard let thread = currentThreadID else { return }
		client.send("pause", arguments: ["threadId": thread])
	}

	public func stepOver() { step("next") }
	public func stepInto() { step("stepIn") }
	public func stepOut() { step("stepOut") }

	private func step(_ command: String) {
		guard let thread = currentThreadID else { return }
		client.send(command, arguments: ["threadId": thread])
		state = .running
	}

	// MARK: - Events

	/// Picks an exit status out of an adapter's own message.
	///
	/// Only when the events did not carry one: an adapter that reports it
	/// properly is believed over anything found in prose. Delve never sends an
	/// `exited` event and says it in a sentence instead, which is the same
	/// place VS Code reads it from.
	func noteExitCode(inOutput text: String) {
		guard exitCode == nil else { return }
		guard let range = text.range(of: "has exited with status ") else { return }

		let digits = text[range.upperBound...].prefix { $0.isNumber || $0 == "-" }
		guard let code = Int(digits) else { return }
		exitCode = code

		// The status usually arrives after the session is already over, so the
		// state that carried "no code" has to be published a second time.
		guard state == .terminated else { return }
		onMain { [weak self] in
			guard let self else { return }
			for observer in self.stateObservers { observer(.terminated) }
		}
	}

	private func wireEvents() {
		client.onOutput = { [weak self] category, text in
			guard let self else { return }
			// Delve ends "Building <path>" without a newline, so its next
			// message continued the same line and read as one word. A change of
			// category mid-line is a change of speaker, and gets a line of its
			// own.
			var text = text
			if let last = self.lastOutputCategory, last != category, !self.outputAtLineStart {
				text = "\n" + text
			}
			self.lastOutputCategory = category
			self.outputAtLineStart = text.hasSuffix("\n")

			// Delve reports the exit status as a sentence rather than in the
			// `exited` event, which it never sends — the same place VS Code
			// reads it from.
			self.noteExitCode(inOutput: text)
			// Kept for the watchdog, which otherwise has to guess why nothing
			// started when the adapter has already said why.
			self.lastAdapterOutput = LaunchStall.remember(text, after: self.lastAdapterOutput)
			self.onOutput?(text)
		}
		client.onTerminated = { [weak self] in
			self?.state = .terminated
		}
		client.onEvent = { [weak self] event, body in
			guard let self else { return }
			switch event {
			case "initialized":
				// Only now may breakpoints be sent; the adapter is ready for
				// configuration. Sending them earlier is silently dropped.
				Task { await self.configurationDone() }

			case "stopped":
				self.currentThreadID = body["threadId"] as? Int
				let reason = body["reason"] as? String ?? "pause"
				self.state = .stopped(reason: reason)
				Task { await self.refreshStack() }

			case "continued":
				self.state = .running

			case "terminated", "exited":
				self.adapterSaidItEnded(body: body)

			case JavaDebug.HotSwap.event:
				self.hotSwapSaid(body: body)

			default:
				break
			}
		}
	}

	// MARK: - Hot code replace

	/// What a swap into this session did, at every stage of one.
	///
	/// The second argument is whether the program was stopped when it landed,
	/// which is what decides whether the stack moved under somebody: the adapter
	/// drops to an affected frame and enters it again, and that is worth saying
	/// only when there was a frame to move.
	public var onHotSwap: ((JavaDebug.HotSwap.Event, _ wasStopped: Bool) -> Void)?

	/// Whether this session attached to a program somebody else started.
	///
	/// What a restart *costs* turns on it: restarting a JVM this app launched
	/// ends a process nobody else is using, and restarting one it attached to in
	/// a pod is restarting somebody's service.
	public internal(set) var isAttached = false

	/// Whether this session has been found to be unable to swap at all.
	///
	/// **Learnt rather than asked.** The adapter reports eighteen capabilities
	/// and none of them is about hot code replace, so the only evidence is a
	/// failure whose wording is about the session rather than about the change.
	/// Once true, the reporting stops repeating itself.
	public private(set) var cannotHotSwap = false

	/// Asks the adapter to redefine whatever it has seen recompiled.
	///
	/// **This is the request nothing was sending, and its absence was the whole
	/// fault.** `hotCodeReplace: AUTO` reads like a setting that makes the
	/// adapter swap by itself; it is not. The provider inside the bundle
	/// publishes `hotcodereplace` with `BUILD_COMPLETE` when the workspace it is
	/// listening to finishes compiling, and then waits — `AUTO` is the *client's*
	/// policy about what to do with that event, and the client is this. Measured
	/// on the hot-swap example: `BUILD_COMPLETE` five times over five saves, and
	/// never a `STARTING` or an `END`, because `doHotCodeReplace` is only reached
	/// through this request.
	///
	/// It takes no arguments. Which classes are redefined is the provider's own
	/// bookkeeping, from the resource deltas it accumulated.
	@discardableResult
	public func redefineClasses() async -> JavaDebug.HotSwap.Result? {
		guard let body = try? await client.request(JavaDebug.HotSwap.command) else { return nil }
		return JavaDebug.HotSwap.result(from: body)
	}

	private func hotSwapSaid(body: [String: Any]) {
		guard let event = JavaDebug.HotSwap.event(from: body) else { return }
		if event.stage == .error, let message = event.message,
		   JavaDebug.HotSwap.isAboutTheSession(message) {
			cannotHotSwap = true
		}
		let wasStopped: Bool
		if case .stopped = state { wasStopped = true } else { wasStopped = false }
		onMain { [weak self] in self?.onHotSwap?(event, wasStopped) }
	}

	/// Reports a launch that never produced an event.
	public var onLaunchStalled: ((String) -> Void)?

	/// The last thing the adapter said, which is usually why nothing started.
	private var lastAdapterOutput: String?

	/// Sends a launch or an attach, and reports a refusal the moment it arrives.
	///
	/// **The response used to be dropped.** `launch` is not awaited, and for a
	/// good reason — the adapter answers it only once configuration is done, so
	/// awaiting it would block the very events that finish the launch — but
	/// "not awaited" had been written as "not read", and an adapter that says
	/// `success: false` in the first second was answered by the watchdog
	/// twenty-five seconds later, guessing from whatever it had printed by then.
	///
	/// A completion is the whole fix: the request is still not waited on, and
	/// the answer is still read.
	private func send(_ command: String, watching arguments: [String: Any]) {
		let generation = launchGeneration
		client.send(command, arguments: arguments) { [weak self] result in
			guard case let .failure(error) = result else { return }
			self?.onMain { [weak self] in
				guard let self, self.launchGeneration == generation else { return }
				// Only while this launch is still the one being waited on. A
				// refusal that arrives after something else has happened — a
				// stop pressed, a second launch started — is not news.
				guard case .starting = self.state else { return }
				self.state = .terminated
				self.onMainLaunchStalled(LaunchStall.explainRefusal(
					command,
					message: Self.said(error),
					lastOutput: self.lastAdapterOutput
				))
			}
		}
	}

	/// The adapter's own sentence out of an error, and nothing invented.
	private static func said(_ error: Error) -> String? {
		if case let DAPClient.ClientError.adapterError(message) = error { return message }
		// Every other case is this program's own description of a transport
		// problem, which is not the adapter refusing and is worth saying as
		// itself.
		return (error as? LocalizedError)?.errorDescription
	}

	/// Gives up on a launch that has gone quiet.
	///
	/// The usual cause is macOS's developer-tools authorization: the debuggee
	/// is held until the dialog is answered, and if it is dismissed or never
	/// appears the adapter simply never reports anything. Sitting on "not
	/// running" for ever tells the user nothing about that.
	private func startLaunchWatchdog(timeout: TimeInterval = 25) {
		let generation = launchGeneration
		DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
			guard let self, self.launchGeneration == generation else { return }
			guard case .starting = self.state else { return }

			self.state = .terminated
			self.onMainLaunchStalled(LaunchStall.explain(lastOutput: self.lastAdapterOutput))
		}
	}

	private func configurationDone() async {
		for file in breakpoints.keys {
			await syncBreakpoints(for: file)
		}
		_ = try? await client.request("configurationDone")
		state = .running
	}

	// MARK: - Threads

	/// The goroutines, or threads in anything that is not Go.
	public private(set) var threads: [DebugThread] = []
	/// Which one the stack is being shown for.
	public internal(set) var selectedThreadID: Int?

	public var onThreadsChanged: (() -> Void)?

	/// The state an adapter would have left, without an adapter.
	///
	/// `threads`, `stackFrames` and `scopes` are `private(set)` and are filled
	/// from replies, so what a session *leaves behind* — the thing this is
	/// about — cannot be asserted without either a live adapter or a seam.
	/// Internal, so only the tests in this module can reach it.
	func fillForTesting(threads: [DebugThread], frames: [StackFrame], scopes: [Scope]) {
		self.threads = threads
		self.selectedThreadID = threads.first?.id
		self.stackFrames = frames
		self.scopes = scopes
		if let frame = frames.first, let file = frame.file {
			self.inlineValues = InlineValueSet(
				file: file, line: frame.line, values: InlineValues.byName(scopes)
			)
		}
	}

	/// The state an adapter would have left, without an adapter. Internal, like
	/// `fillForTesting`, and for the same reason: what a session throws away
	/// when a program starts running again cannot be asserted otherwise.
	func setStateForTesting(_ wanted: State) {
		state = wanted
	}

	/// Re-reads the list of goroutines.
	///
	/// Go programs have thousands of them and the interesting one is rarely the
	/// one that happened to hit the breakpoint — a deadlock is a question about
	/// the others.
	public func refreshThreads() async {
		let response = try? await client.request("threads", arguments: [:])
		let entries = (response?["threads"] as? [[String: Any]]) ?? []
		threads = entries.map {
			DebugThread(id: $0["id"] as? Int ?? 0, name: $0["name"] as? String ?? "?")
		}
		onMain { [weak self] in self?.onThreadsChanged?() }
	}

	/// Shows another goroutine's stack.
	public func selectThread(id: Int) async {
		guard id != selectedThreadID else { return }
		selectedThreadID = id
		await refreshStack(thread: id, reportStop: false)
	}

	// MARK: - Watches

	/// Expressions being watched, in the order they were added.
	///
	/// Behind a lock, and every change made through the helpers below, because
	/// more than one refresh can be in the air at once: adding a watch starts
	/// one, and a stop or a change of frame starts another. Two of them writing
	/// into the same array from two threads is not a wrong value — it is the
	/// array's own storage being freed twice, which crashed the test suite with
	/// a bad access inside `Array._makeMutableAndUnique` and would crash a
	/// debugging session the same way.
	public var watches: [WatchExpression] {
		watchLock.lock()
		defer { watchLock.unlock() }
		return storedWatches
	}

	var storedWatches: [WatchExpression] = []
	let watchLock = NSLock()

	/// Changes the watch with this id, if it is still there.
	///
	/// By id rather than by index: a refresh evaluates one expression at a time
	/// and waits for the debugger between them, and a watch removed while it
	/// waits leaves every index after it pointing at the wrong row — or past the
	/// end.
	func updateWatch(id: UUID, _ change: (inout WatchExpression) -> Void) {
		watchLock.lock()
		if let index = storedWatches.firstIndex(where: { $0.id == id }) {
			change(&storedWatches[index])
		}
		watchLock.unlock()
	}

	func withWatches(_ change: (inout [WatchExpression]) -> Void) {
		watchLock.lock()
		change(&storedWatches)
		watchLock.unlock()
	}

	public var onWatchesChanged: (() -> Void)?

}

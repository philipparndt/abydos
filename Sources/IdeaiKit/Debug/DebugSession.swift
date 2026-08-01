import Foundation

/// A breakpoint the user set, independent of any running session.
public struct Breakpoint: Equatable, Hashable, Sendable {
	public let file: String
	public let line: Int
	public var isEnabled: Bool
	/// Set once the adapter confirms it; an unverified breakpoint is drawn
	/// hollow, because a filled marker where execution can never stop is a lie.
	public var isVerified: Bool

	/// An expression that must be true to stop here.
	///
	/// The difference between a breakpoint you can use and one you have to sit
	/// and press Continue at four hundred times because the interesting case is
	/// the last one.
	public var condition: String?

	/// Stop only after this many hits — `> 5`, or just `5` meaning the same.
	public var hitCondition: String?

	/// Print this and carry on rather than stopping.
	///
	/// A print statement that needs no rebuild and leaves no mess behind.
	public var logMessage: String?

	/// Whether this breakpoint does anything beyond stopping every time.
	public var isConditional: Bool {
		condition?.isEmpty == false || hitCondition?.isEmpty == false || logMessage?.isEmpty == false
	}

	public init(
		file: String,
		line: Int,
		isEnabled: Bool = true,
		isVerified: Bool = false,
		condition: String? = nil,
		hitCondition: String? = nil,
		logMessage: String? = nil
	) {
		self.file = file
		self.line = line
		self.isEnabled = isEnabled
		self.isVerified = isVerified
		self.condition = condition
		self.hitCondition = hitCondition
		self.logMessage = logMessage
	}

	/// How the protocol wants it.
	public var wireFormat: [String: Any] {
		var entry: [String: Any] = ["line": line]
		if let condition, !condition.isEmpty { entry["condition"] = condition }
		if let hitCondition, !hitCondition.isEmpty { entry["hitCondition"] = hitCondition }
		if let logMessage, !logMessage.isEmpty { entry["logMessage"] = logMessage }
		return entry
	}
}

/// One goroutine, or one thread in anything that is not Go.
public struct DebugThread: Equatable, Sendable, Identifiable {
	public let id: Int
	public let name: String

	public init(id: Int, name: String) {
		self.id = id
		self.name = name
	}
}

/// An expression being watched, and what it last came to.
public struct WatchExpression: Equatable, Sendable, Identifiable {
	public let id: UUID
	public var expression: String
	/// What it evaluated to where execution is now, or the error if it could
	/// not be evaluated there.
	public var value: String?
	public var failed: Bool
	/// Set when the value can be opened up, as a struct or a slice can.
	public var variablesReference: Int

	public init(
		id: UUID = UUID(),
		expression: String,
		value: String? = nil,
		failed: Bool = false,
		variablesReference: Int = 0
	) {
		self.id = id
		self.expression = expression
		self.value = value
		self.failed = failed
		self.variablesReference = variablesReference
	}
}

public struct StackFrame: Identifiable, Equatable, Sendable {
	public let id: Int
	public let name: String
	public let file: String?
	public let line: Int

	public init(id: Int, name: String, file: String?, line: Int) {
		self.id = id
		self.name = name
		self.file = file
		self.line = line
	}
}

public struct Variable: Identifiable, Equatable, Sendable {
	public let id = UUID()
	public let name: String
	public let value: String
	public let type: String?
	/// Non-zero when the value can be expanded; the handle to ask with.
	public let variablesReference: Int
	public var children: [Variable]?
	public var isExpanded = false

	public var isExpandable: Bool { variablesReference > 0 }

	public init(name: String, value: String, type: String?, variablesReference: Int) {
		self.name = name
		self.value = value
		self.type = type
		self.variablesReference = variablesReference
	}
}

public struct Scope: Equatable, Sendable {
	public let name: String
	public let variablesReference: Int
	public var variables: [Variable] = []
	public var isExpanded = true

	public init(name: String, variablesReference: Int) {
		self.name = name
		self.variablesReference = variablesReference
	}
}

/// Drives a debug adapter: breakpoints, stepping, stack and variables.
///
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
			let current = state
			onMain { [weak self] in
				guard let self else { return }
				for observer in self.stateObservers { observer(current) }
			}
		}
	}

	/// Breakpoints by file, kept across runs so they survive restarting.
	public private(set) var breakpoints: [String: [Breakpoint]] = [:]

	public private(set) var stackFrames: [StackFrame] = []
	public private(set) var scopes: [Scope] = []
	/// Frame whose variables are shown.
	public private(set) var selectedFrameID: Int?

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
	private var stoppedObservers: [(String, Int) -> Void] = []

	public func observeStopped(_ observer: @escaping (String, Int) -> Void) {
		stoppedObservers.append(observer)
	}

	private let client: DAPClient
	private let projectRoot: URL
	private var currentThreadID: Int?
	/// Which debugger is behind this session, once one has been started.
	public private(set) var adapter: DebugAdapter?

	/// What the program exited with, once it has.
	///
	/// "Finished" is the same word for a clean run and a crash, which is the
	/// one thing you want to know without reading the log.
	public private(set) var exitCode: Int?
	/// Bumped per launch so a stale watchdog cannot fire on a newer session.
	private var launchGeneration = 0

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

	private func onMain(_ body: @escaping @Sendable () -> Void) {
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

	// MARK: - Breakpoints

	/// Toggles a breakpoint, syncing to the adapter when one is attached.
	public func toggleBreakpoint(file: String, line: Int) {
		// Keyed by the real path, which is how the adapter names files.
		let file = FilePath.canonical(file)
		var list = breakpoints[file] ?? []
		if let index = list.firstIndex(where: { $0.line == line }) {
			list.remove(at: index)
		} else {
			list.append(Breakpoint(file: file, line: line))
			list.sort { $0.line < $1.line }
		}
		breakpoints[file] = list.isEmpty ? nil : list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Gives a breakpoint a condition, a hit count, or a message to log.
	///
	/// Passing nil for everything makes it an ordinary breakpoint again.
	public func setBreakpointOptions(
		file: String,
		line: Int,
		condition: String?,
		hitCondition: String?,
		logMessage: String?
	) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file], let index = list.firstIndex(where: { $0.line == line })
		else { return }

		list[index].condition = condition?.isEmpty == true ? nil : condition
		list[index].hitCondition = hitCondition?.isEmpty == true ? nil : hitCondition
		list[index].logMessage = logMessage?.isEmpty == true ? nil : logMessage
		breakpoints[file] = list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	public func breakpoint(file: String, line: Int) -> Breakpoint? {
		breakpoints[FilePath.canonical(file)]?.first { $0.line == line }
	}

	public func breakpoints(inFile file: String) -> [Breakpoint] {
		breakpoints[file] ?? []
	}

	public func hasBreakpoint(file: String, line: Int) -> Bool {
		breakpoints[file]?.contains { $0.line == line } ?? false
	}

	public var isActive: Bool {
		switch state {
		case .idle, .terminated: return false
		default: return true
		}
	}

	/// Sends the breakpoints for one file. DAP replaces the whole set per file,
	/// so they are always sent together rather than incrementally.
	private func syncBreakpoints(for file: String) async {
		let lines = (breakpoints[file] ?? []).filter(\.isEnabled).map(\.wireFormat)
		let response = try? await client.request("setBreakpoints", arguments: [
			"source": ["path": file],
			"breakpoints": lines,
			"sourceModified": false,
		])

		// The adapter reports which it could actually bind.
		guard let verified = response?["breakpoints"] as? [[String: Any]] else { return }
		var list = breakpoints[file] ?? []
		for (index, entry) in verified.enumerated() where index < list.count {
			list[index].isVerified = entry["verified"] as? Bool ?? false
		}
		breakpoints[file] = list
		onMain { [weak self] in self?.onBreakpointsChanged?() }
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
		}

		try await handshake(with: adapter)

		// Launch is sent before waiting for `initialized`; the adapter replies
		// to it once configuration is done, which is why it is not awaited.
		client.send("launch", arguments: DebugAdapters.launchArguments(
			for: adapter,
			program: program,
			workingDirectory: workingDirectory.path,
			arguments: arguments,
			environment: environment
		))

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
		client.send("launch", arguments: request)

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
		}

		try await handshake(with: adapter)
		client.send("attach", arguments: DebugAdapters.attachArguments(for: adapter, pid: pid))
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
		client.send("disconnect", arguments: ["terminateDebuggee": true])
		client.stop()
		state = .terminated
		stackFrames = []
		scopes = []
		onMain { [weak self] in
			self?.onStackChanged?()
			self?.onVariablesChanged?()
		}
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
				// `exited` carries the code; `terminated` only says it is over,
				// and the two arrive in either order. Whichever came with a
				// code is the one that knows how it went.
				if let code = body["exitCode"] as? Int { self.exitCode = code }
				self.state = .terminated
				// Delve sends neither `exited` nor a code, and only says how the
				// program went when asked to disconnect — which is where VS Code
				// gets it from too. Asking costs nothing: the session is over
				// either way.
				if self.exitCode == nil {
					self.client.send("disconnect", arguments: ["terminateDebuggee": true])
				}
				self.stackFrames = []
				self.scopes = []
				self.onMain {
					self.onStackChanged?()
					self.onVariablesChanged?()
				}

			default:
				break
			}
		}
	}

	/// Reports a launch that never produced an event.
	public var onLaunchStalled: ((String) -> Void)?

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
			self.onMainLaunchStalled("""
			The debugger built the program but never started it.

			macOS asks for permission the first time a process is debugged, and 			holds the program until that is answered. If developer mode is off, 			it asks every time. Enabling it once removes the prompt:

			    sudo DevToolsSecurity -enable
			""")
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
	public private(set) var selectedThreadID: Int?

	public var onThreadsChanged: (() -> Void)?

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
	public private(set) var watches: [WatchExpression] = []
	public var onWatchesChanged: (() -> Void)?

	public func addWatch(_ expression: String) {
		let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		watches.append(WatchExpression(expression: trimmed))
		onMain { [weak self] in self?.onWatchesChanged?() }
		Task { await refreshWatches() }
	}

	public func removeWatch(id: UUID) {
		watches.removeAll { $0.id == id }
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	public func removeAllWatches() {
		watches.removeAll()
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	/// Re-evaluates every watch in the selected frame.
	///
	/// After every stop and every frame change, because a watch that still
	/// shows the value from two stops ago is worse than no watch at all.
	public func refreshWatches() async {
		guard !watches.isEmpty else { return }
		guard let frame = selectedFrameID else {
			for index in watches.indices {
				watches[index].value = nil
				watches[index].failed = false
			}
			onMain { [weak self] in self?.onWatchesChanged?() }
			return
		}

		for index in watches.indices {
			let response = try? await client.request("evaluate", arguments: [
				"expression": watches[index].expression,
				"frameId": frame,
				"context": "watch",
			])
			if let result = response?["result"] as? String {
				watches[index].value = result
				watches[index].failed = false
				watches[index].variablesReference = response?["variablesReference"] as? Int ?? 0
			} else {
				// An expression that does not compile here is not an error to
				// report; it is simply out of scope in this frame, which is
				// worth saying quietly rather than clearing the row.
				watches[index].failed = true
				watches[index].value = "not available here"
				watches[index].variablesReference = 0
			}
		}
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	// MARK: - Stack and variables

	/// Re-reads the stack after a stop, then the top frame's variables.
	private func refreshStack() async {
		guard let thread = currentThreadID else { return }
		selectedThreadID = thread
		await refreshThreads()
		await refreshStack(thread: thread, reportStop: true)
	}

	/// Reads one thread's stack.
	///
	/// `reportStop` is false when the user picked another goroutine: the editor
	/// should follow the stack, but nothing has stopped, so the execution
	/// marker must not move as though it had.
	private func refreshStack(thread: Int, reportStop: Bool) async {
		let response = try? await client.request("stackTrace", arguments: [
			"threadId": thread,
			"startFrame": 0,
			"levels": 50,
		])
		let frames = (response?["stackFrames"] as? [[String: Any]]) ?? []

		stackFrames = frames.map { frame in
			let source = frame["source"] as? [String: Any]
			return StackFrame(
				id: frame["id"] as? Int ?? 0,
				name: frame["name"] as? String ?? "?",
				file: source?["path"] as? String,
				line: frame["line"] as? Int ?? 0
			)
		}
		let top = stackFrames.first
		onMain { [weak self] in
			guard let self else { return }
			self.onStackChanged?()
			// Opening the file is AppKit work, so it belongs on this side of
			// the hop with everything else.
			if reportStop, let file = top?.file, let line = top?.line {
				for observer in self.stoppedObservers { observer(file, line) }
			}
		}

		if let top { await selectFrame(id: top.id) }
	}

	/// Loads the scopes and top-level variables for a frame.
	public func selectFrame(id: Int) async {
		selectedFrameID = id
		// A watch means something different in each frame, so it is re-read
		// whenever the frame changes rather than only when execution stops.
		defer { Task { await refreshWatches() } }

		let response = try? await client.request("scopes", arguments: ["frameId": id])
		let raw = (response?["scopes"] as? [[String: Any]]) ?? []

		var loaded: [Scope] = []
		for entry in raw {
			var scope = Scope(
				name: entry["name"] as? String ?? "Scope",
				variablesReference: entry["variablesReference"] as? Int ?? 0
			)
			// Registers are noise in a Go session; skip them by default.
			if scope.name.lowercased().contains("registers") { continue }
			scope.variables = await variables(reference: scope.variablesReference)
			loaded.append(scope)
		}

		scopes = loaded
		onMain { [weak self] in self?.onVariablesChanged?() }
	}

	/// Children of a variable container.
	public func variables(reference: Int) async -> [Variable] {
		guard reference > 0 else { return [] }
		let response = try? await client.request("variables", arguments: ["variablesReference": reference])
		let raw = (response?["variables"] as? [[String: Any]]) ?? []

		return raw.map { entry in
			Variable(
				name: entry["name"] as? String ?? "",
				value: entry["value"] as? String ?? "",
				type: entry["type"] as? String,
				variablesReference: entry["variablesReference"] as? Int ?? 0
			)
		}
	}

	/// Expands or collapses a variable, loading children on first expand.
	public func toggleExpansion(scopeIndex: Int, path: [Int]) async {
		guard scopes.indices.contains(scopeIndex) else { return }
		var scope = scopes[scopeIndex]
		scope.variables = await toggle(in: scope.variables, path: path)
		scopes[scopeIndex] = scope
		onMain { [weak self] in self?.onVariablesChanged?() }
	}

	private func toggle(in variables: [Variable], path: [Int]) async -> [Variable] {
		guard let index = path.first, variables.indices.contains(index) else { return variables }
		var updated = variables
		var variable = updated[index]

		if path.count == 1 {
			variable.isExpanded.toggle()
			// Children are fetched once, on first expansion.
			if variable.isExpanded, variable.children == nil {
				variable.children = await self.variables(reference: variable.variablesReference)
			}
		} else {
			variable.children = await toggle(in: variable.children ?? [], path: Array(path.dropFirst()))
		}

		updated[index] = variable
		return updated
	}

	/// Evaluates an expression in the selected frame.
	public func evaluate(_ expression: String) async -> String? {
		guard let frame = selectedFrameID else { return nil }
		let response = try? await client.request("evaluate", arguments: [
			"expression": expression,
			"frameId": frame,
			"context": "watch",
		])
		return response?["result"] as? String
	}
}

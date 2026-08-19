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

	/// Where in the code this was put, rather than at which line number.
	///
	/// A line number stops meaning anything once something rewrites the file
	/// without saying what it changed — an agent, a `git checkout`, a formatter.
	/// The anchor is what survives that: the symbol the breakpoint was inside,
	/// how far into it, and what was written on the line. Nil until the file has
	/// been parsed, and for files with no grammar to parse them.
	public var anchor: BreakpointAnchors.Anchor?

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
		logMessage: String? = nil,
		anchor: BreakpointAnchors.Anchor? = nil
	) {
		self.file = file
		self.line = line
		self.isEnabled = isEnabled
		self.isVerified = isVerified
		self.condition = condition
		self.hitCondition = hitCondition
		self.logMessage = logMessage
		self.anchor = anchor
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

	/// Where this is running, when that is not here.
	///
	/// A session in a pod looks exactly like one on this machine: the same
	/// toolbar, the same stack, the same variables — which is the point, and
	/// also how somebody comes to read a stack from a cluster believing it is
	/// their laptop. Nil means here, and here needs no saying.
	public var location: String?

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

	/// Takes over a set of breakpoints whole, before anything is running.
	///
	/// Replaying them as toggles loses everything a `Breakpoint` carries beyond
	/// its line: `toggleBreakpoint` builds a fresh one, which is enabled, so a
	/// breakpoint somebody had switched off came back on the moment a session
	/// started — and it was sent to the adapter, and it stopped there.
	///
	/// Nothing is verified here. Whether a line can be bound is a fact about a
	/// program that is not running yet; the adapter says so when the
	/// breakpoints are sent.
	public func adopt(_ incoming: [String: [Breakpoint]]) {
		var adopted: [String: [Breakpoint]] = [:]
		for (file, list) in incoming {
			let canonical = FilePath.canonical(file)
			adopted[canonical] = list
				.sorted { $0.line < $1.line }
				.map { breakpoint in
					var copy = breakpoint
					copy.isVerified = false
					return copy
				}
		}
		breakpoints = adopted
		onMain { [weak self] in self?.onBreakpointsChanged?() }
	}

	/// Turns a breakpoint off without losing it, or on again.
	///
	/// A disabled breakpoint stays where it was put, and is not sent to the
	/// adapter: it is a breakpoint somebody wants back later, not one they want
	/// now. Xcode's click on the marker means exactly this.
	public func setBreakpoint(file: String, line: Int, enabled: Bool) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file], let index = list.firstIndex(where: { $0.line == line })
		else { return }

		guard list[index].isEnabled != enabled else { return }
		list[index].isEnabled = enabled
		// Nothing is bound while it is off; saying otherwise would draw it as
		// though execution could still stop there.
		if !enabled { list[index].isVerified = false }
		breakpoints[file] = list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Records where a file's breakpoints sit in the code, keyed by line.
	///
	/// Nothing the adapter needs to hear about: the anchor is how a breakpoint
	/// finds its line again after something else rewrites the file, which is
	/// this side's problem entirely. Nothing on screen changes either, so no
	/// redraw is asked for.
	public func setBreakpointAnchors(
		inFile file: String,
		_ anchors: [Int: BreakpointAnchors.Anchor]
	) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file] else { return }
		for index in list.indices {
			guard let anchor = anchors[list[index].line] else { continue }
			list[index].anchor = anchor
		}
		breakpoints[file] = list
	}

	/// Puts a file's breakpoints where the text moved them.
	public func replaceBreakpoints(inFile file: String, with list: [Breakpoint]) {
		let file = FilePath.canonical(file)
		breakpoints[file] = list.isEmpty ? nil : list
		onMain { [weak self] in self?.onBreakpointsChanged?() }
		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Takes a breakpoint away — what dragging one out of the gutter means.
	public func removeBreakpoint(file: String, line: Int) {
		let file = FilePath.canonical(file)
		guard var list = breakpoints[file], let index = list.firstIndex(where: { $0.line == line })
		else { return }

		list.remove(at: index)
		breakpoints[file] = list.isEmpty ? nil : list
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		if isActive { Task { await syncBreakpoints(for: file) } }
	}

	/// Turns every breakpoint off except the one named, or every one back on.
	///
	/// "Disable other breakpoints" is the thing somebody reaches for when one
	/// of thirty is the interesting one and stopping at the rest is in the way.
	public func setOtherBreakpoints(file: String, line: Int, enabled: Bool) {
		let keep = FilePath.canonical(file)
		for (path, list) in breakpoints {
			var updated = list
			for index in updated.indices where !(path == keep && updated[index].line == line) {
				updated[index].isEnabled = enabled
				if !enabled { updated[index].isVerified = false }
			}
			breakpoints[path] = updated
		}
		onMain { [weak self] in self?.onBreakpointsChanged?() }

		guard isActive else { return }
		let files = Array(breakpoints.keys)
		Task { for path in files { await syncBreakpoints(for: path) } }
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

		// The adapter reports which it could actually bind — one entry per
		// breakpoint that was sent, so the answers line up with the enabled
		// ones rather than with the whole list.
		guard let verified = response?["breakpoints"] as? [[String: Any]] else { return }
		var list = breakpoints[file] ?? []
		let sent = list.indices.filter { list[$0].isEnabled }
		for (position, index) in sent.enumerated() where position < verified.count {
			list[index].isVerified = verified[position]["verified"] as? Bool ?? false
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
		client.send("launch", arguments: DebugAdapters.launchArguments(
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
		client.send("attach", arguments: [
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
		client.send("launch", arguments: request)

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
		threads = []
		selectedThreadID = nil
		onMain { [weak self] in
			self?.onStackChanged?()
			self?.onVariablesChanged?()
			self?.onThreadsChanged?()
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

			default:
				break
			}
		}
	}

	/// Reports a launch that never produced an event.
	public var onLaunchStalled: ((String) -> Void)?

	/// The last thing the adapter said, which is usually why nothing started.
	private var lastAdapterOutput: String?

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
	public private(set) var selectedThreadID: Int?

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

	private var storedWatches: [WatchExpression] = []
	private let watchLock = NSLock()

	/// Changes the watch with this id, if it is still there.
	///
	/// By id rather than by index: a refresh evaluates one expression at a time
	/// and waits for the debugger between them, and a watch removed while it
	/// waits leaves every index after it pointing at the wrong row — or past the
	/// end.
	private func updateWatch(id: UUID, _ change: (inout WatchExpression) -> Void) {
		watchLock.lock()
		if let index = storedWatches.firstIndex(where: { $0.id == id }) {
			change(&storedWatches[index])
		}
		watchLock.unlock()
	}

	private func withWatches(_ change: (inout [WatchExpression]) -> Void) {
		watchLock.lock()
		change(&storedWatches)
		watchLock.unlock()
	}

	public var onWatchesChanged: (() -> Void)?

	public func addWatch(_ expression: String) {
		let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		withWatches { $0.append(WatchExpression(expression: trimmed)) }
		onMain { [weak self] in self?.onWatchesChanged?() }
		Task { await refreshWatches() }
	}

	public func removeWatch(id: UUID) {
		withWatches { $0.removeAll { $0.id == id } }
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	public func removeAllWatches() {
		withWatches { $0.removeAll() }
		onMain { [weak self] in self?.onWatchesChanged?() }
	}

	/// Re-evaluates every watch in the selected frame.
	///
	/// After every stop and every frame change, because a watch that still
	/// shows the value from two stops ago is worse than no watch at all.
	public func refreshWatches() async {
		// A snapshot, since the list can be added to or emptied while this runs.
		// What comes back is applied to the watch it was asked about, by id, and
		// dropped if that watch has gone.
		let current = watches
		guard !current.isEmpty else { return }
		guard let frame = selectedFrameID else {
			withWatches {
				for index in $0.indices {
					$0[index].value = nil
					$0[index].failed = false
				}
			}
			onMain { [weak self] in self?.onWatchesChanged?() }
			return
		}

		for watch in current {
			let response = try? await client.request("evaluate", arguments: [
				"expression": watch.expression,
				"frameId": frame,
				"context": "watch",
			])
			if let result = response?["result"] as? String {
				updateWatch(id: watch.id) {
					$0.value = result
					$0.failed = false
					$0.variablesReference = response?["variablesReference"] as? Int ?? 0
				}
			} else {
				// An expression that does not compile here is not an error to
				// report; it is simply out of scope in this frame, which is
				// worth saying quietly rather than clearing the row.
				updateWatch(id: watch.id) {
					$0.failed = true
					$0.value = "not available here"
					$0.variablesReference = 0
				}
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

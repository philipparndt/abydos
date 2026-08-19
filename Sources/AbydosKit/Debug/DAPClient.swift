import Foundation
import Network

/// A Debug Adapter Protocol client.
///
/// DAP is the same protocol VS Code and every modern debugger front end speaks,
/// so targeting it means Delve works today and other adapters — LLDB, debugpy —
/// need no new transport later.
///
/// Messages are JSON framed with a `Content-Length` header over the adapter's
/// stdio, the same framing LSP uses.
///
/// `@unchecked Sendable` because the compiler cannot see the discipline: the
/// shared mutable state — the pending-request table and the read buffer — is
/// guarded by `lock`, and everything else is set once during start-up before
/// any callback can run. Process and socket callbacks arrive on background
/// queues and need to reach it.
public final class DAPClient: @unchecked Sendable {
	public enum ClientError: Error, LocalizedError {
		case notRunning
		case timeout
		case timedOut
		case adapterExited
		case adapterError(String)

		public var errorDescription: String? {
			switch self {
			case .notRunning:    return "The debug adapter is not running."
			case .timeout, .timedOut:
				return "The debug adapter did not connect in time."
			case .adapterExited: return "The debug adapter exited before connecting."
			case .adapterError(let message): return message
			}
		}
	}

	/// Events pushed by the adapter, rather than replies to our requests.
	public var onEvent: ((_ event: String, _ body: [String: Any]) -> Void)?
	/// Text the debuggee wrote, so it can be shown in a console.
	public var onOutput: ((_ category: String, _ text: String) -> Void)?
	public var onTerminated: (() -> Void)?

	/// Queue callbacks are delivered on. Main for the app; tests point it away.
	public var callbackQueue: DispatchQueue = .main

	private var process: Process?
	private var inputPipe: Pipe?
	private var outputPipe: Pipe?
	/// Held only so its readability handler can be taken off again. An adapter
	/// started by `startListening` has one on stderr too, and a handler nobody
	/// clears keeps a thread spinning on a closed descriptor.
	private var errorPipe: Pipe?

	/// How many times a reader callback has run.
	///
	/// For one test, and worth the two lines: a handler left on a closed
	/// descriptor shows up as CPU rather than as a wrong answer, and CPU is the
	/// one thing a test running beside a thousand others cannot measure. A
	/// count that stops growing when the adapter does is the same fact, said
	/// locally.
	private(set) var readerWakeups = 0

	private func noteReaderWakeup() {
		lock.lock()
		readerWakeups += 1
		lock.unlock()
	}

	/// Socket transport, used by adapters that speak DAP over TCP rather than
	/// stdio. `dlv dap` is one: it is a server, and writing to its stdin
	/// reaches nothing at all.
	private var connection: NWConnection?
	private var listener: NWListener?

	private var nextSequence = 1
	private var pending: [Int: (Result<[String: Any], Error>) -> Void] = [:]
	private let lock = NSLock()
	private var buffer = Data()

	public init() {}

	deinit {
		stop()
	}

	public var isRunning: Bool {
		if let process { return process.isRunning }
		return connection != nil
	}

	// MARK: - Lifecycle

	/// Launches the adapter process and starts reading its stdout.
	public func start(executable: String, arguments: [String], workingDirectory: URL?) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		process.currentDirectoryURL = workingDirectory

		let input = Pipe()
		let output = Pipe()
		process.standardInput = input
		process.standardOutput = output
		// The adapter's own diagnostics are not protocol traffic; keep them out
		// of the message stream.
		process.standardError = Pipe()

		output.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			self?.noteReaderWakeup()
			// Empty means the far end closed. A readability handler is not
			// removed by that, and one left on a closed descriptor is called
			// again immediately, for ever — a whole core per dead adapter, in a
			// process nobody is looking at any more. It has to take itself off.
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			self?.consume(data)
		}

		process.terminationHandler = { [weak self] _ in
			guard let self else { return }
			self.failAllPending(with: ClientError.notRunning)
			self.callbackQueue.async { self.onTerminated?() }
		}

		try process.run()

		self.process = process
		self.inputPipe = input
		self.outputPipe = output
	}

	/// Starts an adapter that listens on a TCP port, and connects to it.
	///
	/// `dlv dap` is a server, not a stdio adapter — writing to its stdin reaches
	/// nothing. Its `--client-addr` mode, where the adapter dials back, builds
	/// the program and then stalls, so this uses the mode VS Code uses: let it
	/// pick a port, read the port out of its first line of output, and connect.
	public func startListening(
		executable: String,
		arguments: [String],
		workingDirectory: URL?,
		environment: [String: String] = [:],
		timeout: TimeInterval = 20
	) async throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		process.currentDirectoryURL = workingDirectory

		// A GUI app's PATH does not include Homebrew or the Go toolchain, and
		// the adapter shells out to `go build`.
		var childEnvironment = ProcessInfo.processInfo.environment
		let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin",
		                  NSHomeDirectory() + "/go/bin"]
		let existing = childEnvironment["PATH"] ?? ""
		childEnvironment["PATH"] = (extraPaths + [existing]).joined(separator: ":")
		for (key, value) in environment { childEnvironment[key] = value }
		process.environment = childEnvironment

		let output = Pipe()
		let errors = Pipe()
		process.standardOutput = output
		process.standardError = errors
		process.terminationHandler = { [weak self] _ in
			guard let self else { return }
			self.failAllPending(with: ClientError.notRunning)
			self.callbackQueue.async { self.onTerminated?() }
		}
		try process.run()
		self.process = process
		self.outputPipe = output
		self.errorPipe = errors

		let endpoint = try await Self.readEndpoint(
			from: output.fileHandleForReading,
			process: process,
			timeout: timeout
		)

		// Keep draining after the port is found. The debuggee's own output comes
		// out here rather than as DAP output events, so leaving it unread both
		// hides the program's output and risks filling the pipe.
		//
		// Both streams: Go's `log` writes to stderr, and so does anything that
		// reports a problem — which made a running service look like a silent
		// one with nothing in the console but Delve's own two lines.
		output.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			self?.noteReaderWakeup()
			// See `start`: an adapter that has exited leaves this handler on a
			// closed descriptor, where it spins on empty reads until the app is
			// quit. Two ended debug sessions were two cores.
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			guard let self else { return }
			let text = String(decoding: data, as: UTF8.self)
			self.callbackQueue.async { self.onOutput?("stdout", text) }
		}
		errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			self?.noteReaderWakeup()
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			guard let self else { return }
			let text = String(decoding: data, as: UTF8.self)
			// The one line worth hiding: Delve prints its own usage banner at
			// every launch, which is not about the program being debugged.
			guard !text.hasPrefix("DAP server listening at:") else { return }
			self.callbackQueue.async { self.onOutput?("stderr", text) }
		}

		try await connect(host: endpoint.host, port: Int(endpoint.port))
	}

	/// Connects to an adapter somebody else started.
	///
	/// A debugger inside a pod is the case this exists for: it is already
	/// running, reached through a forwarded port, and nothing here starts or
	/// owns the process. Everything after the socket is identical, which is
	/// the point — a session in a cluster is a session.
	public func connect(host: String, port: Int) async throws {
		let connection = NWConnection(
			host: NWEndpoint.Host(host),
			port: NWEndpoint.Port(integerLiteral: UInt16(port)),
			using: .tcp
		)

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			let resumed = OneShot()
			connection.stateUpdateHandler = { state in
				switch state {
				case .ready:
					guard resumed.claim() else { return }
					continuation.resume()
				case .failed(let error), .waiting(let error):
					guard resumed.claim() else { return }
					continuation.resume(throwing: error)
				default:
					break
				}
			}
			connection.start(queue: .global(qos: .userInitiated))
		}

		self.connection = connection
		receive(on: connection)
	}

	/// Reads `DAP server listening at: host:port` from the adapter's output.
	private static func readEndpoint(
		from handle: FileHandle,
		process: Process,
		timeout: TimeInterval
	) async throws -> (host: String, port: UInt16) {
		let deadline = Date().addingTimeInterval(timeout)
		var text = ""

		while Date() < deadline {
			// availableData blocks until there is something, so the exit check
			// happens between reads rather than instead of them.
			let data = handle.availableData
			if data.isEmpty {
				if !process.isRunning { throw ClientError.adapterExited }
				try await Task.sleep(nanoseconds: 20_000_000)
				continue
            }
			text += String(decoding: data, as: UTF8.self)

			guard let range = text.range(of: "listening at: ") else { continue }
			let rest = text[range.upperBound...]
			let address = rest.prefix { !$0.isNewline && !$0.isWhitespace }
			guard let colon = address.lastIndex(of: ":"),
			      let port = UInt16(address[address.index(after: colon)...])
			else { continue }
			return (String(address[address.startIndex..<colon]), port)
		}
		throw ClientError.timedOut
	}

	private func adopt(_ connection: NWConnection) {
		connection.start(queue: .global(qos: .userInitiated))
		self.connection = connection
		receive(on: connection)
	}

	private func receive(on connection: NWConnection) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
			[weak self] data, _, isComplete, error in
			guard let self else { return }
			if let data, !data.isEmpty { self.consume(data) }
			if isComplete || error != nil {
				self.failAllPending(with: ClientError.notRunning)
				self.callbackQueue.async { self.onTerminated?() }
				return
			}
			self.receive(on: connection)
		}
	}

	public func stop() {
		// Marked, not moved: the half-second busy-wait below is reached from
		// menu actions and from the stop button, which are the main thread. It
		// is bounded and it is at the end of a session rather than in the middle
		// of typing, so it is last on the list — but "half a second, on the main
		// queue, sometimes" is exactly the shape of thing that was being recorded
		// as idle.
		//
		// **`disconnectThenStop` does not add a second one.** Its wait is a
		// reply handler and a timer, so nothing blocks on the adapter; what
		// eventually runs here is this same bounded terminate, once, from
		// whichever of the two arrives first.
		StallWatch.mark("debug adapter stop") { stopNow() }
	}

	/// Asks the adapter to disconnect, reads its answer, and only then tears
	/// down.
	///
	/// **The order is the whole point.** `stopNow` clears both readability
	/// handlers before it terminates anything, so from the moment it is entered
	/// nothing the adapter says is read again — and two things arrive after
	/// `disconnect`:
	///
	/// - Delve's exit status, which it reports as the sentence "has exited with
	///   status N" rather than in an `exited` event it never sends.
	///   `DebugSession.noteExitCode(inOutput:)` exists to parse it, and on a
	///   user-initiated stop it never had the chance.
	/// - The adapter's last words, which are what the console shows.
	///
	/// Nothing waits on the caller's thread. The reply comes through the same
	/// `pending` table every other request uses, and the deadline is a timer, so
	/// the stop button returns immediately and the teardown happens behind it.
	///
	/// `answered` is false where the deadline was reached instead — an adapter
	/// that did not reply is killed exactly as before, and the caller is told so
	/// it can say that rather than reporting a clean finish.
	public func disconnectThenStop(
		deadline: TimeInterval = DAPClient.disconnectDeadline,
		completion: @escaping (_ answered: Bool) -> Void
	) {
		guard isRunning else {
			callbackQueue.async { completion(true) }
			return
		}

		// One of the two paths wins and the other returns. `stopNow` fails every
		// pending request, which includes the `disconnect` sent here — so the
		// deadline firing would otherwise call back through the reply handler
		// and tear down twice.
		let finished = OneShot()
		let asked = Date()

		send("disconnect", arguments: ["terminateDebuggee": true]) { [weak self] _ in
			guard finished.claim() else { return }
			self?.lastDisconnectReply = Date().timeIntervalSince(asked)
			self?.stop()
			completion(true)
		}

		DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline) { [weak self] in
			guard finished.claim() else { return }
			guard let self else { return }
			self.callbackQueue.async {
				self.stop()
				completion(false)
			}
		}
	}

	/// How long the adapter took to answer the last `disconnect`.
	///
	/// Kept because it is the number `disconnectDeadline` is chosen against, and
	/// a deadline nobody can check is a deadline nobody can revisit. Nil until a
	/// session has been stopped, and nil where the deadline was reached instead.
	public private(set) var lastDisconnectReply: TimeInterval?

	/// How long an adapter gets to answer `disconnect`.
	///
	/// **Measured, not chosen.** Delve answers in **0.016 s** — driven against
	/// `abydos-examples/go-service` stopped at a breakpoint, and against a small
	/// Go program that exits, on this machine: 0.016 s and 0.017 s across runs.
	/// One second is sixty times that, which is the margin for a machine under
	/// load — a suite has been seen at load 65 here — while still being short
	/// enough that an adapter which has hung does not hold a session open long
	/// enough for anybody to wonder.
	///
	/// `lastDisconnectReply` is what to re-measure it against; a deadline nobody
	/// can check is a deadline nobody can revisit.
	public static let disconnectDeadline: TimeInterval = 1.0

	private func stopNow() {
		// Both of them. Clearing stdout and leaving stderr behind is a whole
		// core, quietly, for as long as the app runs — one per debug session
		// that has ended.
		outputPipe?.fileHandleForReading.readabilityHandler = nil
		errorPipe?.fileHandleForReading.readabilityHandler = nil
		connection?.cancel()
		listener?.cancel()
		// Told to go, and then made to.
		//
		// `terminate()` is a SIGTERM and an adapter is entitled to ignore one;
		// dropping the reference afterwards leaves it running with nobody left
		// to ask. That is not a tidiness problem: Foundation does not mark a
		// pipe's descriptors close-on-exec, so a process that outlives its
		// session holds open every pipe that existed when it started — and a
		// stray one is enough to hang an unrelated `git` on a read that never
		// reaches end of file. Two of them, left behind by a test, cost twenty
		// minutes of a suite that should take fourteen seconds.
		if let running = process, running.isRunning {
			running.terminate()
			// A moment to go quietly, then not a moment more.
			let deadline = Date().addingTimeInterval(0.5)
			while running.isRunning, Date() < deadline {
				usleep(20_000)
			}
			if running.isRunning {
				kill(running.processIdentifier, SIGKILL)
			}
		}
		process = nil
		inputPipe = nil
		outputPipe = nil
		errorPipe = nil
		connection = nil
		listener = nil
		failAllPending(with: ClientError.notRunning)
	}

	/// One-shot flag: the first caller to `claim` gets true and every other
	/// caller gets false.
	///
	/// Two things need it. A second connection or a duplicate state callback
	/// must not resume a continuation twice; and in `disconnectThenStop` the
	/// reply and the deadline race, with the loser having to do nothing.
	private final class OneShot: @unchecked Sendable {
		private var taken = false
		private let lock = NSLock()

		func claim() -> Bool {
			lock.lock()
			defer { lock.unlock() }
			if taken { return false }
			taken = true
			return true
		}
	}

	private func failAllPending(with error: Error) {
		lock.lock()
		let handlers = pending.values
		pending.removeAll()
		lock.unlock()
		for handler in handlers { handler(.failure(error)) }
	}

	// MARK: - Requests

	/// Sends a request and delivers the adapter's `body` on the callback queue.
	public func send(
		_ command: String,
		arguments: [String: Any]? = nil,
		completion: (((Result<[String: Any], Error>) -> Void))? = nil
	) {
		guard inputPipe != nil || connection != nil else {
			completion.map { handler in callbackQueue.async { handler(.failure(ClientError.notRunning)) } }
			return
		}

		lock.lock()
		let sequence = nextSequence
		nextSequence += 1
		if let completion { pending[sequence] = completion }
		lock.unlock()

		var message: [String: Any] = [
			"seq": sequence,
			"type": "request",
			"command": command,
		]
		if let arguments { message["arguments"] = arguments }

		guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return }
		var framed = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
		framed.append(payload)

		if let connection {
			connection.send(content: framed, completion: .contentProcessed { _ in })
		} else {
			inputPipe?.fileHandleForWriting.write(framed)
		}
	}

	/// Async convenience, since most call sites want to await a reply.
	@discardableResult
	public func request(_ command: String, arguments: [String: Any]? = nil) async throws -> [String: Any] {
		try await withCheckedThrowingContinuation { continuation in
			send(command, arguments: arguments) { result in
				continuation.resume(with: result)
			}
		}
	}

	// MARK: - Reading

	/// Accumulates bytes and dispatches every complete message in the buffer.
	private func consume(_ data: Data) {
		lock.lock()
		buffer.append(data)
		var messages: [[String: Any]] = []

		while true {
			guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { break }
			let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
			guard let headerText = String(data: headerData, encoding: .utf8) else {
				buffer.removeAll()
				break
			}

			var contentLength = 0
			for line in headerText.components(separatedBy: "\r\n") {
				let parts = line.split(separator: ":", maxSplits: 1)
				guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
				contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
			}

			let bodyStart = headerEnd.upperBound
			// Wait for the whole body before dispatching.
			guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else { break }

			let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
			let body = Data(buffer[bodyStart..<bodyEnd])
			buffer.removeSubrange(buffer.startIndex..<bodyEnd)

			if let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
				messages.append(message)
			}
		}
		lock.unlock()

		for message in messages { dispatch(message) }
	}

	private func dispatch(_ message: [String: Any]) {
		let type = message["type"] as? String ?? ""

		switch type {
		case "response":
			let requestSequence = message["request_seq"] as? Int ?? -1
			lock.lock()
			let handler = pending.removeValue(forKey: requestSequence)
			lock.unlock()
			guard let handler else { return }

			let success = message["success"] as? Bool ?? false
			let body = message["body"] as? [String: Any] ?? [:]

			callbackQueue.async {
				if success {
					handler(.success(body))
				} else {
					let text = message["message"] as? String ?? "request failed"
					handler(.failure(ClientError.adapterError(text)))
				}
			}

		case "event":
			let event = message["event"] as? String ?? ""
			let body = message["body"] as? [String: Any] ?? [:]

			// Output events are frequent and have their own callback, so they do
			// not have to be filtered out of the general event stream.
			if event == "output" {
				let category = body["category"] as? String ?? "console"
				let text = body["output"] as? String ?? ""
				callbackQueue.async { self.onOutput?(category, text) }
				return
			}

			callbackQueue.async { self.onEvent?(event, body) }

		default:
			break
		}
	}
}

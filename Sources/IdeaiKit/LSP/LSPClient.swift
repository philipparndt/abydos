import Foundation

/// One language server, spoken to over its standard input and output.
///
/// The wire format is the same `Content-Length` framing as the debug adapter
/// protocol, and the shape of this client follows `DAPClient` for that reason:
/// spawn, frame, match replies to requests by id, and hand notifications to a
/// callback. What differs is that LSP servers are long-lived and stateful —
/// they hold a copy of every open document, and every edit has to be told to
/// them in order, or their answers quietly stop matching the file.
public final class LSPClient: @unchecked Sendable {
	public enum ClientError: Error, LocalizedError {
		case notRunning
		case failed(code: Int, message: String)
		case timedOut(String)

		public var errorDescription: String? {
			switch self {
			case .notRunning:
				return "The language server is not running."
			case let .failed(code, message):
				return "The language server refused: \(message) (\(code))."
			case let .timedOut(request):
				return "The language server did not answer \(request)."
			}
		}
	}

	/// Diagnostics arrived for a document.
	public var onDiagnostics: ((_ uri: String, _ diagnostics: [LSPDiagnostic]) -> Void)?
	/// The server said something to the user — a progress note, a warning.
	public var onMessage: ((_ level: Int, _ text: String) -> Void)?
	/// What the server wrote to its standard error.
	///
	/// Not protocol traffic and not shown to anybody, but it is where a server
	/// says why it is about to be useless — a toolchain it cannot run, a
	/// configuration it will not accept. It used to be read and dropped on the
	/// floor, which is the same as not reading it except that it looked
	/// deliberate.
	public var onStandardError: ((String) -> Void)?
	public var onExit: (() -> Void)?

	public var callbackQueue: DispatchQueue = .main

	private var process: Process?
	private var inputPipe: Pipe?
	/// The two the server writes to. Held so their readability handlers can be
	/// taken off when it stops: a handler left on a closed descriptor is called
	/// straight back, and a language server that has exited then costs a core
	/// for the rest of the session.
	private var outputPipe: Pipe?
	private var errorPipe: Pipe?

	private let lock = NSLock()
	private var buffer = Data()
	private var nextID = 1
	private var pending: [Int: (Result<Any?, Error>) -> Void] = [:]

	/// How many times a reader callback has run.
	///
	/// Kept for one test, and worth the two lines: the failure it guards
	/// against — a handler left on a closed descriptor, called back for ever —
	/// shows up as CPU rather than as a wrong answer, and CPU is the one thing
	/// a test running beside a thousand others cannot measure. A count that
	/// stops growing when the server does is the same fact, stated locally.
	private(set) var readerWakeups = 0

	private func noteReaderWakeup() {
		lock.lock()
		readerWakeups += 1
		lock.unlock()
	}

	/// What the server said it can do, from the initialize reply.
	public private(set) var capabilities: [String: Any] = [:]

	/// Whether the handshake has finished.
	private var isInitialized = false
	/// Notifications sent before it did.
	///
	/// A server rejects everything that arrives before `initialize` — quietly,
	/// so what actually happens is that the document is never registered and
	/// every later question about it comes back "no language service for this
	/// file". Holding them until the handshake lands costs a few milliseconds
	/// once and removes the whole class of race.
	private var queuedNotifications: [(String, [String: Any]?)] = []

	public init() {}

	/// Runs `body` holding the lock.
	///
	/// Synchronous on purpose, and every caller keeps it that way: taking a
	/// lock in an async function and holding it across a suspension point is
	/// how a client like this deadlocks, and Swift 6 makes it an error rather
	/// than a warning. Wrapping it means the critical sections stay short
	/// enough to see, which is the actual guarantee wanted here.
	private func locked<T>(_ body: () -> T) -> T {
		lock.lock()
		defer { lock.unlock() }
		return body()
	}

	public var isRunning: Bool {
		lock.lock()
		defer { lock.unlock() }
		return process?.isRunning ?? false
	}

	// MARK: - Lifetime

	public func start(
		executable: String,
		arguments: [String] = [],
		workingDirectory: URL?,
		environment: [String: String]? = nil
	) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		process.currentDirectoryURL = workingDirectory
		if let environment { process.environment = environment }

		let input = Pipe()
		let output = Pipe()
		process.standardInput = input
		process.standardOutput = output
		// A server's own logging is not protocol traffic. Drained rather than
		// inherited: a full pipe would block the server mid-answer. Drained into
		// the log rather than into nothing, because it is the only place some
		// servers explain themselves.
		let errors = Pipe()
		process.standardError = errors
		errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			self?.noteReaderWakeup()
			// Empty means the server closed its end. Nothing removes a
			// readability handler when that happens, and one left on a closed
			// descriptor is called straight back — a core spinning on empty
			// reads for every server that ever exited, which is what a
			// long-lived editor accumulates.
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			guard let self else { return }
			guard let text = String(data: data, encoding: .utf8) else { return }
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { return }
			self.callbackQueue.async { self.onStandardError?(trimmed) }
		}

		output.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			self?.noteReaderWakeup()
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			self?.consume(data)
		}

		process.terminationHandler = { [weak self] _ in
			guard let self else { return }
			self.failAllPending(with: ClientError.notRunning)
			self.callbackQueue.async { self.onExit?() }
		}

		try process.run()

		lock.lock()
		self.process = process
		self.inputPipe = input
		self.outputPipe = output
		self.errorPipe = errors
		lock.unlock()
	}

	/// The handshake, after which the server will answer questions.
	///
	/// `options` is the server-specific half of it: jdtls is told there which
	/// JDKs exist and which bundles to load, and there is no second chance to
	/// say it. The timeout is longer than a request's default because a server
	/// that has to read a build file before answering — which every Java server
	/// does — takes seconds rather than milliseconds on a large project.
	@discardableResult
	public func initialize(
		rootURL: URL,
		options: [String: Any]? = nil,
		timeout: TimeInterval = 10
	) async throws -> [String: Any] {
		var parameters: [String: Any] = [
			"processId": Int(ProcessInfo.processInfo.processIdentifier),
			"rootUri": rootURL.absoluteString,
			"workspaceFolders": [["uri": rootURL.absoluteString, "name": rootURL.lastPathComponent]],
			"capabilities": Self.clientCapabilities,
		]
		if let options { parameters["initializationOptions"] = options }
		let result = try await request("initialize", parameters, timeout: timeout)

		let capabilities = (result as? [String: Any])?["capabilities"] as? [String: Any] ?? [:]
		locked { self.capabilities = capabilities }

		// `initialized` goes first, then whatever was waiting behind it, in the
		// order it was asked for — a `didChange` before its `didOpen` is as
		// broken as no `didOpen` at all.
		write(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
		let queued = locked { () -> [(String, [String: Any]?)] in
			isInitialized = true
			let pending = queuedNotifications
			queuedNotifications = []
			return pending
		}
		for (method, parameters) in queued { send(notification: method, parameters) }
		return capabilities
	}

	/// What this editor claims to support.
	///
	/// Deliberately modest: claiming a capability the editor does not implement
	/// makes servers send things nobody reads, and some of them are expensive
	/// to produce.
	static let clientCapabilities: [String: Any] = [
		"textDocument": [
			"synchronization": ["didSave": true, "dynamicRegistration": false],
			"publishDiagnostics": ["relatedInformation": false],
			"hover": ["contentFormat": ["plaintext", "markdown"]],
			"definition": ["linkSupport": true],
			"documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
			"completion": [
				"completionItem": ["snippetSupport": false, "documentationFormat": ["plaintext"]],
			],
		],
		"workspace": ["workspaceFolders": true, "symbol": ["dynamicRegistration": false]],
	]

	/// Asks the server to stop, and makes sure it does.
	public func shutdown() async {
		guard isRunning else { return }
		// A server that will not shut down politely is still a process holding
		// a few hundred megabytes, so the ask is given a deadline.
		_ = try? await withTimeout(seconds: 2) { try await self.request("shutdown", nil) }
		notify("exit", nil)

		try? await Task.sleep(nanoseconds: 200_000_000)
		let process = locked { self.process }
		if process?.isRunning == true { process?.terminate() }
	}

	public func stop() {
		lock.lock()
		let process = self.process
		let output = self.outputPipe
		let errors = self.errorPipe
		self.process = nil
		self.inputPipe = nil
		self.outputPipe = nil
		self.errorPipe = nil
		isInitialized = false
		queuedNotifications = []
		lock.unlock()

		// Before the process is asked to go: once it has, these fire on a
		// closed descriptor and are called back immediately, for ever.
		output?.fileHandleForReading.readabilityHandler = nil
		errors?.fileHandleForReading.readabilityHandler = nil

		process?.terminationHandler = nil
		if process?.isRunning == true { process?.terminate() }
		failAllPending(with: ClientError.notRunning)
	}

	// MARK: - Documents

	public func didOpen(uri: String, languageId: String, version: Int, text: String) {
		notify("textDocument/didOpen", [
			"textDocument": [
				"uri": uri,
				"languageId": languageId,
				"version": version,
				"text": text,
			],
		])
	}

	/// Full-text synchronisation.
	///
	/// Incremental sync would send less, but it has to be exactly right or the
	/// server's copy silently drifts from the file and every answer after that
	/// is wrong about a place that no longer exists. Whole documents are cheap
	/// enough at the sizes anyone edits by hand.
	public func didChange(uri: String, version: Int, text: String) {
		notify("textDocument/didChange", [
			"textDocument": ["uri": uri, "version": version],
			"contentChanges": [["text": text]],
		])
	}

	public func didSave(uri: String, text: String? = nil) {
		var parameters: [String: Any] = ["textDocument": ["uri": uri]]
		if let text { parameters["text"] = text }
		notify("textDocument/didSave", parameters)
	}

	public func didClose(uri: String) {
		notify("textDocument/didClose", ["textDocument": ["uri": uri]])
	}

	// MARK: - Questions

	public func definition(uri: String, position: LSPPosition) async throws -> [LSPLocation] {
		let result = try await request("textDocument/definition", [
			"textDocument": ["uri": uri],
			"position": position.json,
		])
		return LSPLocation.list(from: result)
	}

	public func hover(uri: String, position: LSPPosition) async throws -> LSPHover? {
		let result = try await request("textDocument/hover", [
			"textDocument": ["uri": uri],
			"position": position.json,
		])
		return LSPHover(json: result)
	}

	public func completion(uri: String, position: LSPPosition) async throws -> [LSPCompletion] {
		let result = try await request("textDocument/completion", [
			"textDocument": ["uri": uri],
			"position": position.json,
		])
		return LSPCompletion.list(from: result)
	}

	/// Symbols anywhere in the project, matching a query.
	public func workspaceSymbols(query: String) async throws -> [LSPSymbol] {
		let result = try await request("workspace/symbol", ["query": query])
		guard let array = result as? [Any] else { return [] }
		return array.compactMap { LSPSymbol(json: $0) }
	}

	/// What is declared in one file.
	public func documentSymbols(uri: String) async throws -> [LSPSymbol] {
		let result = try await request("textDocument/documentSymbol", [
			"textDocument": ["uri": uri],
		])
		return LSPSymbol.list(from: result, uri: uri)
	}

	/// Runs a command the server offers.
	///
	/// The escape hatch in the protocol, and the only way into some of what a
	/// server can do: jdtls's debugger, its classpaths and its list of main
	/// classes are all commands rather than requests with a method of their own.
	public func executeCommand(
		_ command: String,
		arguments: [Any] = [],
		timeout: TimeInterval = 30
	) async throws -> Any? {
		try await request(
			"workspace/executeCommand",
			["command": command, "arguments": arguments],
			timeout: timeout
		)
	}

	public func references(uri: String, position: LSPPosition) async throws -> [LSPLocation] {
		let result = try await request("textDocument/references", [
			"textDocument": ["uri": uri],
			"position": position.json,
			"context": ["includeDeclaration": true],
		])
		return LSPLocation.list(from: result)
	}

	// MARK: - Sending

	public func notify(_ method: String, _ parameters: [String: Any]?) {
		let ready = locked { () -> Bool in
			guard isInitialized else {
				queuedNotifications.append((method, parameters))
				return false
			}
			return true
		}
		guard ready else { return }
		send(notification: method, parameters)
	}

	private func send(notification method: String, _ parameters: [String: Any]?) {
		var message: [String: Any] = ["jsonrpc": "2.0", "method": method]
		if let parameters { message["params"] = parameters }
		write(message)
	}

	@discardableResult
	public func request(
		_ method: String,
		_ parameters: [String: Any]?,
		timeout: TimeInterval = 10
	) async throws -> Any? {
		guard isRunning else { throw ClientError.notRunning }

		let id = locked { () -> Int in
			let id = nextID
			nextID += 1
			return id
		}

		return try await withTimeout(seconds: timeout, describing: method) {
			try await withCheckedThrowingContinuation { continuation in
				self.lock.lock()
				self.pending[id] = { continuation.resume(with: $0) }
				self.lock.unlock()

				var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
				if let parameters { message["params"] = parameters }
				self.write(message)
			}
		}
	}

	private func write(_ message: [String: Any]) {
		guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return }
		var framed = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
		framed.append(payload)

		lock.lock()
		let pipe = inputPipe
		lock.unlock()
		// A server that has died mid-write takes the pipe with it; the write
		// raises rather than returning an error, so it is caught here.
		guard let pipe else { return }
		do {
			try pipe.fileHandleForWriting.write(contentsOf: framed)
		} catch {
			failAllPending(with: ClientError.notRunning)
		}
	}

	/// Fails a request that is taking too long rather than waiting for ever.
	///
	/// A language server indexing a large project can go quiet for a while, and
	/// a UI that awaits it with no deadline is a UI that hangs.
	private func withTimeout<T: Sendable>(
		seconds: TimeInterval,
		describing method: String = "a request",
		_ body: @escaping @Sendable () async throws -> T
	) async throws -> T {
		try await withThrowingTaskGroup(of: T.self) { group in
			group.addTask { try await body() }
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
				throw ClientError.timedOut(method)
			}
			defer { group.cancelAll() }
			guard let first = try await group.next() else { throw ClientError.timedOut(method) }
			return first
		}
	}

	private func failAllPending(with error: Error) {
		lock.lock()
		let handlers = pending
		pending.removeAll()
		lock.unlock()
		for handler in handlers.values { handler(.failure(error)) }
	}

	// MARK: - Reading

	/// Accumulates bytes and dispatches every complete message in the buffer.
	func consume(_ data: Data) {
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
		// A reply carries an id and no method; a request from the server carries
		// both; a notification carries only a method.
		if let id = message["id"] as? Int, message["method"] == nil {
			lock.lock()
			let handler = pending.removeValue(forKey: id)
			lock.unlock()

			if let error = message["error"] as? [String: Any] {
				handler?(.failure(ClientError.failed(
					code: error["code"] as? Int ?? 0,
					message: error["message"] as? String ?? "unknown"
				)))
			} else {
				handler?(.success(message["result"]))
			}
			return
		}

		guard let method = message["method"] as? String else { return }
		let parameters = message["params"] as? [String: Any] ?? [:]

		switch method {
		case "textDocument/publishDiagnostics":
			guard let uri = parameters["uri"] as? String else { return }
			let diagnostics = (parameters["diagnostics"] as? [Any] ?? [])
				.compactMap { LSPDiagnostic(json: $0) }
			callbackQueue.async { self.onDiagnostics?(uri, diagnostics) }

		case "window/showMessage", "window/logMessage":
			guard let text = parameters["message"] as? String else { return }
			let level = parameters["type"] as? Int ?? 3
			callbackQueue.async { self.onMessage?(level, text) }

		case "workspace/configuration":
			// One answer per section asked about, and the answer is "nothing
			// configured" — everything this editor has to say was said in the
			// initialize request. A reply of the wrong shape is worse than a
			// plain null: a server that expects an array and gets one value
			// stops asking, and stops working.
			guard let id = message["id"] else { return }
			let items = (parameters["items"] as? [Any])?.count ?? 0
			write(["jsonrpc": "2.0", "id": id, "result": Array(repeating: NSNull(), count: items)])

		default:
			// A request from the server that is not answered here still needs a
			// reply, or a server that waits for one stops working.
			if let id = message["id"] {
				write(["jsonrpc": "2.0", "id": id, "result": NSNull()])
			}
		}
	}
}

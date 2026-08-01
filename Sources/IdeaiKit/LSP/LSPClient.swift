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
	public var onExit: (() -> Void)?

	public var callbackQueue: DispatchQueue = .main

	private var process: Process?
	private var inputPipe: Pipe?

	private let lock = NSLock()
	private var buffer = Data()
	private var nextID = 1
	private var pending: [Int: (Result<Any?, Error>) -> Void] = [:]

	/// What the server said it can do, from the initialize reply.
	public private(set) var capabilities: [String: Any] = [:]

	public init() {}

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
		// inherited: a full pipe would block the server mid-answer.
		let errors = Pipe()
		process.standardError = errors
		errors.fileHandleForReading.readabilityHandler = { handle in
			_ = handle.availableData
		}

		output.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			guard !data.isEmpty else { return }
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
		lock.unlock()
	}

	/// The handshake, after which the server will answer questions.
	@discardableResult
	public func initialize(rootURL: URL) async throws -> [String: Any] {
		let result = try await request("initialize", [
			"processId": Int(ProcessInfo.processInfo.processIdentifier),
			"rootUri": rootURL.absoluteString,
			"workspaceFolders": [["uri": rootURL.absoluteString, "name": rootURL.lastPathComponent]],
			"capabilities": Self.clientCapabilities,
		])

		let capabilities = (result as? [String: Any])?["capabilities"] as? [String: Any] ?? [:]
		lock.lock()
		self.capabilities = capabilities
		lock.unlock()

		notify("initialized", [:])
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
			"completion": [
				"completionItem": ["snippetSupport": false, "documentationFormat": ["plaintext"]],
			],
		],
		"workspace": ["workspaceFolders": true],
	]

	/// Asks the server to stop, and makes sure it does.
	public func shutdown() async {
		guard isRunning else { return }
		// A server that will not shut down politely is still a process holding
		// a few hundred megabytes, so the ask is given a deadline.
		_ = try? await withTimeout(seconds: 2) { try await self.request("shutdown", nil) }
		notify("exit", nil)

		try? await Task.sleep(nanoseconds: 200_000_000)
		lock.lock()
		let process = self.process
		lock.unlock()
		if process?.isRunning == true { process?.terminate() }
	}

	public func stop() {
		lock.lock()
		let process = self.process
		self.process = nil
		self.inputPipe = nil
		lock.unlock()

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

		lock.lock()
		let id = nextID
		nextID += 1
		lock.unlock()

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

		default:
			// A request from the server that is not answered here still needs a
			// reply, or a server that waits for one stops working.
			if let id = message["id"] {
				write(["jsonrpc": "2.0", "id": id, "result": NSNull()])
			}
		}
	}
}

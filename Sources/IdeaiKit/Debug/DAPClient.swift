import Foundation

/// A Debug Adapter Protocol client.
///
/// DAP is the same protocol VS Code and every modern debugger front end speaks,
/// so targeting it means Delve works today and other adapters — LLDB, debugpy —
/// need no new transport later.
///
/// Messages are JSON framed with a `Content-Length` header over the adapter's
/// stdio, the same framing LSP uses.
public final class DAPClient {
	public enum ClientError: Error {
		case notRunning
		case timeout
		case adapterError(String)
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

	private var nextSequence = 1
	private var pending: [Int: (Result<[String: Any], Error>) -> Void] = [:]
	private let lock = NSLock()
	private var buffer = Data()

	public init() {}

	deinit {
		stop()
	}

	public var isRunning: Bool { process?.isRunning ?? false }

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
			guard !data.isEmpty else { return }
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

	public func stop() {
		outputPipe?.fileHandleForReading.readabilityHandler = nil
		if process?.isRunning == true {
			process?.terminate()
		}
		process = nil
		inputPipe = nil
		outputPipe = nil
		failAllPending(with: ClientError.notRunning)
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
		guard let inputPipe else {
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

		inputPipe.fileHandleForWriting.write(framed)
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

import Foundation
import Network

/// A local MCP server that agent tools call back into.
///
/// This is the structured channel that replaces scraping a TUI. Instead of
/// parsing rendered output — which breaks whenever a tool restyles itself — the
/// agent *calls* a tool here and ideai receives typed data: file, line,
/// severity, message. Results also arrive incrementally as the agent works,
/// rather than only once it finishes.
///
/// Transport is Streamable HTTP over loopback, because ideai is a running app
/// the agent must call *into*. The stdio transport inverts that: the client
/// spawns the server, which cannot reach an already-running window.
public final class MCPServer {
	/// A tool the agent may call.
	public struct Tool {
		public let name: String
		public let description: String
		/// JSON Schema for the arguments, sent verbatim in `tools/list`.
		public let inputSchema: [String: Any]
		/// Returns the text reported back to the agent.
		public let handler: ([String: Any]) -> String

		public init(
			name: String,
			description: String,
			inputSchema: [String: Any],
			handler: @escaping ([String: Any]) -> String
		) {
			self.name = name
			self.description = description
			self.inputSchema = inputSchema
			self.handler = handler
		}
	}

	public private(set) var port: UInt16 = 0
	/// Shared secret required on every request.
	///
	/// Loopback alone is not access control: any process on the machine can
	/// reach the port. The token stops anything but the session we launched from
	/// injecting findings into the UI.
	public let token: String

	/// Queue tool handlers are invoked on. Main by default, since they drive UI.
	public var callbackQueue: DispatchQueue = .main

	private var tools: [String: Tool] = [:]
	private var listener: NWListener?
	private let queue = DispatchQueue(label: "ideai.mcp", qos: .userInitiated)
	private var connections: [ObjectIdentifier: NWConnection] = [:]

	private static let protocolVersion = "2025-06-18"

	public init(token: String = UUID().uuidString) {
		self.token = token
	}

	deinit {
		stop()
	}

	public func register(_ tool: Tool) {
		tools[tool.name] = tool
	}

	// MARK: - Lifecycle

	/// Starts listening on an ephemeral loopback port.
	@discardableResult
	public func start() throws -> UInt16 {
		let parameters = NWParameters.tcp
		// Loopback only. This server must never be reachable off the machine.
		parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
		parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
		self.listener = listener

		let ready = DispatchSemaphore(value: 0)
		listener.stateUpdateHandler = { [weak self] state in
			guard case .ready = state else { return }
			self?.port = listener.port?.rawValue ?? 0
			ready.signal()
		}
		listener.newConnectionHandler = { [weak self] connection in
			self?.accept(connection)
		}
		listener.start(queue: queue)

		// The port is only knowable once the listener is ready, and callers need
		// it immediately to build the agent's config.
		guard ready.wait(timeout: .now() + 5) == .success else {
			throw MCPServerError.failedToStart
		}
		return port
	}

	public func stop() {
		for connection in connections.values { connection.cancel() }
		connections.removeAll()
		listener?.cancel()
		listener = nil
	}

	/// The `--mcp-config` payload pointing an agent at this server.
	public func configurationJSON(serverName: String = "abydos") -> String {
		let configuration: [String: Any] = [
			"mcpServers": [
				serverName: [
					"type": "http",
					"url": "http://127.0.0.1:\(port)/mcp",
					"headers": ["Authorization": "Bearer \(token)"],
				],
			],
		]
		let data = try? JSONSerialization.data(withJSONObject: configuration)
		return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
	}

	/// Fully-qualified tool names, for the agent's allow-list.
	public func qualifiedToolNames(serverName: String = "abydos") -> [String] {
		tools.keys.map { "mcp__\(serverName)__\($0)" }.sorted()
	}

	// MARK: - Connections

	private func accept(_ connection: NWConnection) {
		let key = ObjectIdentifier(connection)
		connections[key] = connection

		connection.stateUpdateHandler = { [weak self] state in
			switch state {
			case .cancelled, .failed:
				self?.queue.async { self?.connections[key] = nil }
			default:
				break
			}
		}
		connection.start(queue: queue)
		receive(on: connection, buffer: Data())
	}

	/// Reads until a complete HTTP request is buffered, then serves it.
	///
	/// A request can arrive split across reads, and a keep-alive connection can
	/// deliver several back to back, so the buffer is carried between reads and
	/// drained a request at a time.
	private func receive(on connection: NWConnection, buffer: Data) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
			guard let self else { return }
			var buffer = buffer

			if let data, !data.isEmpty {
				buffer.append(data)
				while let (request, consumed) = HTTPRequest.parse(buffer) {
					buffer.removeFirst(consumed)
					self.serve(request, on: connection)
				}
			}

			if isComplete || error != nil {
				connection.cancel()
				return
			}
			self.receive(on: connection, buffer: buffer)
		}
	}

	private func serve(_ request: HTTPRequest, on connection: NWConnection) {
		guard request.method == "POST" else {
			send(status: "405 Method Not Allowed", body: Data(), on: connection)
			return
		}

		let authorization = request.header("authorization") ?? ""
		guard authorization == "Bearer \(token)" else {
			send(status: "401 Unauthorized", body: Data(), on: connection)
			return
		}

		guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
			send(jsonRPCError: -32700, message: "Parse error", id: nil, on: connection)
			return
		}

		// Notifications carry no id and expect no response body.
		guard let id = message["id"] else {
			send(status: "202 Accepted", body: Data(), on: connection)
			return
		}

		let method = message["method"] as? String ?? ""
		let parameters = message["params"] as? [String: Any] ?? [:]

		switch method {
		case "initialize":
			// Echo the client's protocol version when we recognise it; otherwise
			// state ours and let it decide.
			let requested = parameters["protocolVersion"] as? String
			let version = requested ?? Self.protocolVersion
			respond(result: [
				"protocolVersion": version,
				"capabilities": ["tools": ["listChanged": false]],
				"serverInfo": ["name": "abydos", "version": "0.1.0"],
			], id: id, on: connection)

		case "ping":
			respond(result: [:], id: id, on: connection)

		case "tools/list":
			let listed = tools.values
				.sorted { $0.name < $1.name }
				.map { tool -> [String: Any] in
					["name": tool.name, "description": tool.description, "inputSchema": tool.inputSchema]
				}
			respond(result: ["tools": listed], id: id, on: connection)

		case "tools/call":
			let name = parameters["name"] as? String ?? ""
			let arguments = parameters["arguments"] as? [String: Any] ?? [:]

			guard let tool = tools[name] else {
				send(jsonRPCError: -32602, message: "Unknown tool: \(name)", id: id, on: connection)
				return
			}

			// Handlers touch the UI, so they run on the callback queue while the
			// network queue waits for the text to send back.
			let semaphore = DispatchSemaphore(value: 0)
			var output = ""
			callbackQueue.async {
				output = tool.handler(arguments)
				semaphore.signal()
			}
			_ = semaphore.wait(timeout: .now() + 10)

			respond(result: [
				"content": [["type": "text", "text": output]],
				"isError": false,
			], id: id, on: connection)

		default:
			send(jsonRPCError: -32601, message: "Method not found: \(method)", id: id, on: connection)
		}
	}

	// MARK: - Responses

	private func respond(result: [String: Any], id: Any, on connection: NWConnection) {
		let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
		guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
		send(status: "200 OK", body: data, contentType: "application/json", on: connection)
	}

	private func send(jsonRPCError code: Int, message: String, id: Any?, on connection: NWConnection) {
		var payload: [String: Any] = [
			"jsonrpc": "2.0",
			"error": ["code": code, "message": message],
		]
		payload["id"] = id ?? NSNull()
		guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
		send(status: "200 OK", body: data, contentType: "application/json", on: connection)
	}

	private func send(
		status: String,
		body: Data,
		contentType: String = "text/plain",
		on connection: NWConnection
	) {
		var head = "HTTP/1.1 \(status)\r\n"
		head += "Content-Type: \(contentType)\r\n"
		head += "Content-Length: \(body.count)\r\n"
		head += "Connection: keep-alive\r\n\r\n"

		var response = Data(head.utf8)
		response.append(body)
		connection.send(content: response, completion: .contentProcessed { _ in })
	}
}

public enum MCPServerError: Error {
	case failedToStart
}

/// Just enough HTTP to serve JSON-RPC over loopback.
struct HTTPRequest {
	let method: String
	let path: String
	let headers: [String: String]
	let body: Data

	func header(_ name: String) -> String? {
		headers[name.lowercased()]
	}

	/// Parses one request from the buffer, returning it and the bytes consumed,
	/// or nil when more data is needed.
	static func parse(_ buffer: Data) -> (HTTPRequest, Int)? {
		let separator = Data("\r\n\r\n".utf8)
		guard let headerEnd = buffer.range(of: separator) else { return nil }

		let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
		guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

		var lines = headerText.components(separatedBy: "\r\n")
		guard !lines.isEmpty else { return nil }

		let requestLine = lines.removeFirst().split(separator: " ")
		guard requestLine.count >= 2 else { return nil }

		var headers: [String: String] = [:]
		for line in lines {
			guard let colon = line.firstIndex(of: ":") else { continue }
			let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
			let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			headers[name] = value
		}

		let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
		let bodyStart = headerEnd.upperBound
		let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
		// Wait for the whole body before dispatching.
		guard available >= contentLength else { return nil }

		let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
		let body = Data(buffer[bodyStart..<bodyEnd])
		let consumed = buffer.distance(from: buffer.startIndex, to: bodyEnd)

		let request = HTTPRequest(
			method: String(requestLine[0]),
			path: String(requestLine[1]),
			headers: headers,
			body: body
		)
		return (request, consumed)
	}
}

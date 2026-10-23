import Foundation
import Network
import Security

/// A loopback proxy that shows a vboard server at http://127.0.0.1:<port> to one web view, signing every request with a token.
///
/// The hosted vboard signs in through Entra ID, whose Conditional Access wants a
/// compliant device — which an embedded `WKWebView` can never prove, so the
/// page's own sign-in cannot work there. Abydos gets a personal access token
/// through the system's sign-in sheet instead, but a web view cannot add a
/// header to the requests its page makes, nor to the page's WebSocket. So the
/// page is shown from here, and every request it makes leaves here with
/// `Authorization: Bearer` added. vboard's own iPad app does the same.
///
/// Ordinary requests go upstream through one `URLSession`, which keeps its
/// connections and speaks HTTP/2 where the server does. The first version opened
/// a connection per request, and on the hosted server behind the corporate
/// network the ~560 requests of one board, each with its own TCP and TLS
/// handshake, took 13 seconds. A WebSocket is relayed as bytes over a connection
/// of its own, since a socket is one long exchange that pooling cannot help.
///
/// Anything on this machine can connect to a loopback port, and every request
/// through here would carry the person's token. So nothing is forwarded without
/// the secret cookie only the web view was given.
public final class VboardProxy: @unchecked Sendable {
	/// The cookie the web view must carry on every request; the proxy refuses anything without it (403) and never forwards it.
	public static let cookieName = "abydos_vboard"
	public let upstream: URL
	public let secret: String

	/// Sent upstream as `Authorization: Bearer <token>` on every request from
	/// the next one on (nil = none). Settable at any time, so that signing in
	/// again keeps the proxy — and with it the page's origin.
	public var token: String? {
		get { tokenLock.withLock { currentToken } }
		set { tokenLock.withLock { currentToken = newValue } }
	}

	private var currentToken: String?
	private let tokenLock = NSLock()
	private let target: Target
	private let queue = DispatchQueue(label: "de.rnd7.abydos.vboard-proxy")
	private var listener: NWListener?
	private var port: UInt16?
	private var waiting: [CheckedContinuation<URL, Error>] = []
	private var clients: [ObjectIdentifier: Client] = [:]
	private var session: URLSession?
	private let tasks = Tasks()

	/// - token: sent upstream as `Authorization: Bearer <token>` on every request (nil = none, e.g. a server without a login)
	public init(upstream: URL, token: String?) {
		self.upstream = upstream
		currentToken = token
		var bytes = [UInt8](repeating: 0, count: 32)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		precondition(status == errSecSuccess, "the system's random source refused: \(status)")
		secret = Data(bytes).base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
		target = Target(upstream)
	}

	deinit {
		listener?.cancel()
		session?.invalidateAndCancel()
		for client in clients.values { client.end() }
	}

	/// Starts listening on 127.0.0.1 and returns the base URL, e.g. http://127.0.0.1:53124.
	///
	/// On `preferredPort` when it is free, so that the page's origin — and with
	/// it its HTTP cache, its storage and its service worker — is the same from
	/// one board to the next; on a port the system chooses when it is taken.
	/// Where a line about each request goes, when somebody wants to know where
	/// the time goes: method and path (never the query, which can carry a
	/// share key), status, milliseconds and bytes. Nil, and silent, unless set.
	public static var trace: ((String) -> Void)?

	public func start(preferredPort: UInt16? = nil) async throws -> URL {
		try await withCheckedThrowingContinuation { continuation in
			queue.async { self.listen(continuation, preferredPort: preferredPort) }
		}
	}

	public var base: URL? { queue.sync { port.map(Self.base) } }

	public func stop() {
		queue.sync {
			listener?.cancel()
			listener = nil
			port = nil
			session?.invalidateAndCancel()
			session = nil
			fail(CancellationError())
			for client in clients.values { client.end() }
			clients = [:]
		}
	}

	/// The cookie to put into the web view's cookie store before loading.
	///
	/// Strict and HTTP-only, so that neither another site nor a script in the
	/// page can hand it on; not Secure, because the page is plain http.
	public func cookie() -> HTTPCookie? {
		guard base != nil else { return nil }
		return HTTPCookie(properties: [
			.domain: "127.0.0.1",
			.path: "/",
			.name: Self.cookieName,
			.value: secret,
			.sameSitePolicy: HTTPCookieStringPolicy.sameSiteStrict,
			HTTPCookiePropertyKey("HttpOnly"): "TRUE",
		])
	}

	/// For a page or API URL on the upstream, the same URL through the proxy
	/// (path, query and fragment kept). Nil before start, and for a URL on
	/// another server — which this proxy would sign with the wrong server's token.
	public func local(_ upstreamURL: URL) -> URL? {
		guard let base, var components = URLComponents(url: upstreamURL, resolvingAgainstBaseURL: false),
		      Target(upstreamURL).origin.lowercased() == target.origin.lowercased()
		else { return nil }
		components.scheme = "http"
		components.host = "127.0.0.1"
		components.port = base.port
		return components.url
	}

	private static func base(_ port: UInt16) -> URL { URL(string: "http://127.0.0.1:\(port)")! }

	// MARK: Listening

	private func listen(_ continuation: CheckedContinuation<URL, Error>, preferredPort: UInt16?) {
		if let port { return continuation.resume(returning: Self.base(port)) }
		waiting.append(continuation)
		guard listener == nil else { return }
		if session == nil {
			let operations = OperationQueue()
			operations.underlyingQueue = queue
			operations.maxConcurrentOperationCount = 1
			session = URLSession(configuration: Self.configuration, delegate: tasks, delegateQueue: operations)
		}
		listen(on: preferredPort.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any, triesLeft: Self.preferredTries)
	}

	/// How often a preferred port is asked for, a tenth of a second apart,
	/// before any port will do. A proxy that has just been stopped still holds
	/// its port for a moment — its listener lets go after `cancel` returns — and
	/// a board opened again right after closing would otherwise get a new port,
	/// which is a new origin with an empty cache.
	private static let preferredTries = 5

	/// A preferred port somebody else holds fails with "address in use" — a
	/// second proxy, or anything else — and is then given up for any port.
	/// Reuse is off so that two proxies can never share one.
	private func listen(on port: NWEndpoint.Port, triesLeft: Int = 0) {
		let giveUp = { [weak self] (error: Error) in
			guard let self else { return }
			if port == .any { return self.fail(error) }
			if triesLeft > 1 {
				self.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
					guard let self, self.listener == nil, self.port == nil, !self.waiting.isEmpty else { return }
					self.listen(on: port, triesLeft: triesLeft - 1)
				}
			} else {
				self.listen(on: .any)
			}
		}
		do {
			let parameters = NWParameters.tcp
			parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
			parameters.allowLocalEndpointReuse = false
			let listener = try NWListener(using: parameters)
			listener.stateUpdateHandler = { [weak self, weak listener] state in
				guard let self, let listener, self.listener === listener else { return }
				switch state {
				case .ready:
					guard let port = listener.port?.rawValue else { return }
					self.port = port
					let waiting = self.waiting
					self.waiting = []
					for continuation in waiting { continuation.resume(returning: Self.base(port)) }
				case .failed(let error), .waiting(let error):
					listener.cancel()
					self.listener = nil
					self.port = nil
					giveUp(error)
				default:
					break
				}
			}
			listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
			self.listener = listener
			listener.start(queue: queue)
		} catch {
			giveUp(error)
		}
	}

	private func fail(_ error: Error) {
		let waiting = self.waiting
		self.waiting = []
		for continuation in waiting { continuation.resume(throwing: error) }
	}

	private func accept(_ connection: NWConnection) {
		guard let port, let session else { return connection.cancel() }
		let context = Context(
			target: target, local: Self.base(port).absoluteString, secret: Array(secret.utf8),
			token: { [weak self] in self?.token }, session: session, tasks: tasks, queue: queue
		)
		let client = Client(connection, context)
		let id = ObjectIdentifier(client)
		clients[id] = client
		client.onEnd = { [weak self] in self?.clients[id] = nil }
		client.begin()
	}

	/// Nothing kept between requests that the page did not keep itself: no
	/// cache (the page's own HTTP cache is the one that knows the board), no
	/// cookies (the token is the sign-in). Generous on the whole exchange,
	/// because a 500 MB video upload must finish.
	private static var configuration: URLSessionConfiguration {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.urlCache = nil
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.urlCredentialStorage = nil
		configuration.httpMaximumConnectionsPerHost = 6
		configuration.timeoutIntervalForRequest = 60
		configuration.timeoutIntervalForResource = 24 * 60 * 60
		return configuration
	}
}

extension VboardProxy: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
	/// Names the server and nothing that opens it: a proxy interpolated into a
	/// log line must not carry the token or the secret along.
	public var description: String { "VboardProxy(\(target.origin) at \(base?.absoluteString ?? "not started"))" }
	public var debugDescription: String { description }
	public var customMirror: Mirror { Mirror(self, children: ["upstream": target.origin, "base": base as Any]) }
}

// MARK: - Where requests go

private struct Target {
	let host: String
	let port: UInt16
	let tls: Bool
	/// `host[:port]`, the port only when it is not the scheme's own.
	let authority: String
	let origin: String

	init(_ url: URL) {
		tls = url.scheme?.lowercased() == "https"
		host = url.host ?? ""
		let standard = tls ? 443 : 80
		port = UInt16(clamping: url.port ?? standard)
		let named = host.contains(":") ? "[\(host)]" : host
		authority = Int(port) == standard ? named : "\(named):\(port)"
		origin = (tls ? "https" : "http") + "://" + authority
	}
}

/// What every connection from the web view shares.
private struct Context {
	let target: Target
	let local: String
	let secret: [UInt8]
	let token: () -> String?
	let session: URLSession
	let tasks: Tasks
	let queue: DispatchQueue
}

// MARK: - Heads

/// The start line and fields of an HTTP message, in order, as Latin-1 so that
/// whatever bytes arrived go out again unchanged.
private struct Head {
	var start: String
	var fields: [(name: String, value: String)]

	init(start: String, fields: [(name: String, value: String)]) {
		self.start = start
		self.fields = fields
	}

	init?(_ data: Data) {
		guard let text = String(data: data, encoding: .isoLatin1) else { return nil }
		var lines = text.components(separatedBy: "\r\n")
		guard !lines.isEmpty, !lines[0].isEmpty else { return nil }
		start = lines.removeFirst()
		fields = []
		for line in lines where !line.isEmpty {
			guard let colon = line.firstIndex(of: ":") else { return nil }
			fields.append((String(line[..<colon]), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
		}
	}

	var status: Int? {
		let parts = start.split(separator: " ")
		return parts.count > 1 ? Int(parts[1]) : nil
	}

	func values(_ name: String) -> [String] {
		fields.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
	}

	func has(_ name: String, token: String) -> Bool {
		values(name).contains { $0.lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == token } }
	}

	mutating func remove(_ name: String) {
		fields.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
	}

	/// In place of the first field of that name, the others removed; at the end when there was none.
	mutating func set(_ name: String, _ value: String) {
		guard let first = fields.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
			return fields.append((name, value))
		}
		fields[first].value = value
		fields = fields.enumerated()
			.filter { $0.offset == first || $0.element.name.caseInsensitiveCompare(name) != .orderedSame }
			.map(\.element)
	}

	mutating func map(_ name: String, _ transform: (String) -> String) {
		for index in fields.indices where fields[index].name.caseInsensitiveCompare(name) == .orderedSame {
			fields[index].value = transform(fields[index].value)
		}
	}

	var data: Data {
		let text = ([start] + fields.map { "\($0.name): \($0.value)" }).joined(separator: "\r\n") + "\r\n\r\n"
		return text.data(using: .isoLatin1) ?? Data(text.utf8)
	}
}

/// `origin` replaced by `replacement` when `value` starts with it as a whole origin.
private func reorigin(_ value: String, from origin: String, to replacement: String) -> String {
	guard value.lowercased().hasPrefix(origin.lowercased()) else { return value }
	let rest = value.dropFirst(origin.count)
	guard rest.isEmpty || "/?#".contains(rest.first!) else { return value }
	return replacement + rest
}

/// The body of an HTTP/1.1 message cut out of the bytes that carry it: by
/// `Content-Length`, or chunk by chunk. Knowing where a request ends is what
/// lets the next one come over the same loopback connection.
struct HTTPBodyFramer {
	struct Malformed: Error {}
	private enum State { case length(Int), size, data(Int), dataEnd, trailer, done }
	private var state: State
	private var pending = Data()

	init(length: Int) { state = length > 0 ? .length(length) : .done }
	static var chunked: HTTPBodyFramer { var framer = HTTPBodyFramer(length: 0); framer.state = .size; return framer }

	var isDone: Bool { if case .done = state { return true } else { return false } }

	/// The body bytes in `data`, and once the body is complete whatever followed it.
	mutating func feed(_ data: Data) throws -> (body: Data, rest: Data) {
		let input = pending.isEmpty ? data : pending + data
		pending = Data()
		var body = Data()
		var at = input.startIndex
		while true {
			switch state {
			case .done:
				return (body, Data(input[at...]))
			case .length(let left), .data(let left):
				let take = min(left, input.endIndex - at)
				body.append(input[at..<(at + take)])
				at += take
				let chunk: Bool = { if case .data = state { return true } else { return false } }()
				if left > take {
					state = chunk ? .data(left - take) : .length(left - take)
					return (body, Data())
				}
				state = chunk ? .dataEnd : .done
			case .dataEnd:
				guard input.endIndex - at >= 2 else { pending = Data(input[at...]); return (body, Data()) }
				guard input[at] == 13, input[at + 1] == 10 else { throw Malformed() }
				at += 2
				state = .size
			case .size, .trailer:
				guard let crlf = input[at...].range(of: Data("\r\n".utf8)) else {
					guard input.endIndex - at < 4096 else { throw Malformed() }
					pending = Data(input[at...])
					return (body, Data())
				}
				let line = String(decoding: input[at..<crlf.lowerBound], as: UTF8.self)
				at = crlf.upperBound
				if case .size = state {
					let digits = line.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
					guard let size = Int(digits, radix: 16), size >= 0 else { throw Malformed() }
					state = size == 0 ? .trailer : .data(size)
				} else if line.isEmpty {
					state = .done
				}
			}
		}
	}
}

// MARK: - The session's delegate

/// Hands each task's events to the connection it answers. On the proxy's
/// queue, which is the session's delegate queue.
private final class Tasks: NSObject, URLSessionDataDelegate {
	var clients: [Int: Client] = [:]

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
	                completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		if let response = response as? HTTPURLResponse { clients[dataTask.taskIdentifier]?.respond(response) }
		completionHandler(.allow)
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		clients[dataTask.taskIdentifier]?.receive(data, from: dataTask)
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		clients.removeValue(forKey: task.taskIdentifier)?.complete(error)
	}

	/// Not followed: the page is the one to see a redirect, with its Location rewritten.
	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
	                newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		completionHandler(nil)
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
		completionHandler(clients[task.taskIdentifier]?.bodyStream())
	}
}

/// A request body too large to hold, passed to URLSession as it arrives. The
/// writes block while URLSession has not read what came before, on a queue of
/// their own, which is the back-pressure that keeps a 500 MB upload from
/// landing in memory.
private final class BodyStream {
	private let output: OutputStream
	private var input: InputStream?
	private let queue = DispatchQueue(label: "de.rnd7.abydos.vboard-proxy.body")

	init() {
		var input: InputStream?
		var output: OutputStream?
		Stream.getBoundStreams(withBufferSize: 256 * 1024, inputStream: &input, outputStream: &output)
		self.input = input
		self.output = output!
		queue.async { [output = self.output] in output.open() }
	}

	/// Once: URLSession asks again only to retry, and a body read from the page cannot be read twice.
	func take() -> InputStream? {
		defer { input = nil }
		return input
	}

	func write(_ data: Data, then: @escaping (Bool) -> Void) {
		queue.async { [output] in
			then(data.withUnsafeBytes { raw in
				guard var pointer = raw.bindMemory(to: UInt8.self).baseAddress else { return true }
				var left = raw.count
				while left > 0 {
					let written = output.write(pointer, maxLength: left)
					if written <= 0 { return false }
					pointer += written
					left -= written
				}
				return true
			})
		}
	}

	func close() { queue.async { [output] in output.close() } }
}

// MARK: - One connection from the web view

/// One loopback connection: a run of requests answered through the session,
/// kept alive between them, or a WebSocket relayed as bytes.
private final class Client {
	private static let blank = Data("\r\n\r\n".utf8)
	/// The most a head may take, either way: enough for any cookie jar, and a
	/// bound on what a peer can make the relay hold.
	private static let cap = 64 * 1024
	/// Bodies up to this are read whole and sent as one; larger ones are streamed.
	private static let held = 16 << 20
	/// Bytes of an answer handed to the loopback connection and not yet sent,
	/// past which the session is paused.
	private static let backlog = 4 << 20
	private static let hopByHop: Set<String> = [
		"connection", "keep-alive", "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade",
	]

	let client: NWConnection
	var onEnd: (() -> Void)?
	private let context: Context
	private var ended = false
	private var traced: (line: String, started: Date, status: Int, bytes: Int)?

	private var task: URLSessionTask?
	private var body: BodyStream?
	private var keepAlive = true
	private var answered = false
	private var hasBody = true
	private var requestDone = false
	private var responseDone = false
	private var leftover = Data()
	private var unsent = 0
	private var paused = false

	private var upstream: NWConnection?

	init(_ client: NWConnection, _ context: Context) {
		self.client = client
		self.context = context
	}

	private var target: Target { context.target }
	private var local: String { context.local.hasSuffix("/") ? String(context.local.dropLast()) : context.local }

	func begin() {
		client.stateUpdateHandler = { [weak self] state in
			switch state {
			case .failed, .cancelled: self?.end()
			default: break
			}
		}
		client.start(queue: context.queue)
		scanRequest(Data())
	}

	func end() {
		guard !ended else { return }
		ended = true
		task?.cancel()
		body?.close()
		client.cancel()
		upstream?.cancel()
		onEnd?()
		onEnd = nil
	}

	// MARK: The request

	private func scanRequest(_ buffer: Data) {
		if let blank = buffer.range(of: Self.blank) {
			guard blank.lowerBound - buffer.startIndex <= Self.cap else { return refuse(431, "Request Header Fields Too Large") }
			return request(head: buffer[..<blank.lowerBound], rest: Data(buffer[blank.upperBound...]))
		}
		guard buffer.count <= Self.cap else { return refuse(431, "Request Header Fields Too Large") }
		client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
			guard let self, !self.ended else { return }
			if let data, !data.isEmpty { return self.scanRequest(buffer + data) }
			if complete || error != nil { return self.end() }
			self.scanRequest(buffer)
		}
	}

	private func request(head bytes: Data, rest: Data) {
		guard var head = Head(bytes) else { return refuse(400, "Bad Request") }
		guard authorised(head) else { return refuse(403, "Forbidden") }
		head.map("Origin") { reorigin($0, from: local, to: target.origin) }
		head.map("Referer") { reorigin($0, from: local, to: target.origin) }
		let cookies = head.values("Cookie")
			.flatMap { $0.split(separator: ";") }
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty && name(of: $0) != VboardProxy.cookieName }
		head.remove("Cookie")
		if !cookies.isEmpty { head.fields.append(("Cookie", cookies.joined(separator: "; "))) }
		head.remove("Authorization")
		if let token = context.token() { head.fields.append(("Authorization", "Bearer \(token)")) }
		if VboardProxy.trace != nil {
			let target = head.start.split(separator: " ").dropFirst().first.map(String.init) ?? ""
			let path = target.split(separator: "?").first.map(String.init) ?? target
			traced = ("\(head.start.split(separator: " ").first ?? "") \(path)", Date(), 0, 0)
		}
		if head.values("Upgrade").contains(where: { $0.lowercased().contains("websocket") }) {
			head.set("Host", target.authority)
			return connect(sending: head.data + rest)
		}
		forward(head, rest: rest)
	}

	/// Whether the request carries the secret, compared in constant time so that
	/// how long a refusal takes says nothing about how much of a guess was right.
	private func authorised(_ head: Head) -> Bool {
		var found = false
		for pair in head.values("Cookie").flatMap({ $0.split(separator: ";") }) {
			let pair = pair.trimmingCharacters(in: .whitespaces)
			guard name(of: pair) == VboardProxy.cookieName else { continue }
			let value = Array(pair.drop { $0 != "=" }.dropFirst().utf8)
			guard value.count == secret.count else { continue }
			var difference: UInt8 = 0
			for (a, b) in zip(value, secret) { difference |= a ^ b }
			found = found || difference == 0
		}
		return found
	}

	private var secret: [UInt8] { context.secret }

	private func name(of pair: String) -> String {
		String(pair.prefix { $0 != "=" }).trimmingCharacters(in: .whitespaces)
	}

	/// An answer of the proxy's own, after which the connection closes.
	private func refuse(_ status: Int, _ reason: String, _ body: String? = nil) {
		answered = true
		task?.cancel()
		let text = Data((body ?? reason).utf8) + Data("\n".utf8)
		let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\n"
			+ "Content-Length: \(text.count)\r\nConnection: close\r\n\r\n"
		client.send(content: Data(head.utf8) + text, contentContext: .finalMessage, isComplete: true,
		            completion: .contentProcessed { [weak self] _ in self?.end() })
	}

	private func badGateway(_ why: String) {
		refuse(502, "Bad Gateway", "vboard server \(target.authority) not reachable: \(why)")
	}

	// MARK: Through the session

	/// `Accept-Encoding` is left to URLSession too: it decodes only what it
	/// asked for, and the page then gets the decoded body.
	private func forward(_ head: Head, rest: Data) {
		let parts = head.start.split(separator: " ", omittingEmptySubsequences: false)
		guard parts.count == 3, let url = upstreamURL(String(parts[1])) else { return refuse(400, "Bad Request") }
		keepAlive = parts[2] != "HTTP/1.0" && !head.has("Connection", token: "close")
		answered = false
		hasBody = parts[0] != "HEAD"
		requestDone = false
		responseDone = false
		var request = URLRequest(url: url)
		request.httpMethod = String(parts[0])
		var combined: [(String, [String])] = []
		for (field, value) in head.fields {
			let lower = field.lowercased()
			guard !Self.hopByHop.contains(lower), !["host", "content-length", "accept-encoding", "expect"].contains(lower)
			else { continue }
			if let index = combined.firstIndex(where: { $0.0.lowercased() == lower }) {
				combined[index].1.append(value)
			} else {
				combined.append((field, [value]))
			}
		}
		for (field, values) in combined { request.setValue(values.joined(separator: ", "), forHTTPHeaderField: field) }

		let framer: HTTPBodyFramer
		if head.has("Transfer-Encoding", token: "chunked") {
			framer = .chunked
		} else if let length = head.values("Content-Length").first {
			guard let length = Int(length), length >= 0 else { return refuse(400, "Bad Request") }
			if length > Self.held { request.setValue(String(length), forHTTPHeaderField: "Content-Length") }
			framer = HTTPBodyFramer(length: length)
		} else {
			framer = HTTPBodyFramer(length: 0)
		}
		if framer.isDone {
			start(context.session.dataTask(with: request))
			return bodyDone(rest)
		}
		if head.values("Content-Length").first.flatMap(Int.init).map({ $0 <= Self.held }) ?? false {
			return hold(framer, rest, Data(), request)
		}
		body = BodyStream()
		start(context.session.uploadTask(withStreamedRequest: request))
		stream(framer, rest)
	}

	private func upstreamURL(_ requestTarget: String) -> URL? {
		var path = requestTarget
		if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
			guard let components = URLComponents(string: path) else { return nil }
			path = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
		}
		guard path.hasPrefix("/") else { return nil }
		let allowed = CharacterSet.urlPathAllowed.union(.urlQueryAllowed).union(["%"])
		return URL(string: target.origin + path)
			?? path.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: target.origin + $0) }
	}

	private func start(_ task: URLSessionTask) {
		self.task = task
		context.tasks.clients[task.taskIdentifier] = self
		task.resume()
	}

	/// Reads a body small enough to send whole.
	private func hold(_ framer: HTTPBodyFramer, _ data: Data, _ held: Data, _ request: URLRequest) {
		var framer = framer
		guard let fed = try? framer.feed(data) else { return refuse(400, "Bad Request") }
		let held = held + fed.body
		let rest = fed.rest
		if framer.isDone {
			var request = request
			request.httpBody = held
			start(context.session.dataTask(with: request))
			return bodyDone(rest)
		}
		client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
			guard let self, !self.ended else { return }
			guard let data, !data.isEmpty else { return complete || error != nil ? self.end() : self.hold(framer, Data(), held, request) }
			self.hold(framer, data, held, request)
		}
	}

	/// Passes a body on as it arrives, the next read waiting for the last write.
	private func stream(_ framer: HTTPBodyFramer, _ data: Data) {
		var framer = framer
		guard let body, let fed = try? framer.feed(data) else { return refuse(400, "Bad Request") }
		let (bytes, rest) = fed
		let next = { [weak self] in
			guard let self, !self.ended else { return }
			if framer.isDone {
				body.close()
				return self.bodyDone(rest)
			}
			self.client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
				guard let self, !self.ended else { return }
				guard let data, !data.isEmpty else { return complete || error != nil ? self.end() : self.stream(framer, Data()) }
				self.stream(framer, data)
			}
		}
		guard !bytes.isEmpty else { return next() }
		body.write(bytes) { [weak self] written in
			self?.context.queue.async {
				guard let self, !self.ended else { return }
				// A write the session no longer reads: it has answered, or given up.
				written ? next() : (self.keepAlive = false)
			}
		}
	}

	func bodyStream() -> InputStream? { body?.take() }

	private func bodyDone(_ rest: Data) {
		requestDone = true
		leftover = rest
		next()
	}

	// MARK: The session's answer

	func respond(_ response: HTTPURLResponse) {
		guard !ended else { return }
		let status = response.statusCode
		hasBody = hasBody && status != 204 && status != 304 && !(100..<200).contains(status)
		var head = Head(start: "HTTP/1.1 \(status) \(Self.reason(status))", fields: [])
		let dropped: Set<String> = Self.hopByHop.union(["content-encoding", "content-length", "set-cookie", "strict-transport-security"])
		for case let (field as String, value as String) in response.allHeaderFields where !dropped.contains(field.lowercased()) {
			head.fields.append((field, value))
		}
		head.map("Location") { reorigin($0, from: target.origin, to: local) }
		traced?.status = status
		if hasBody { head.fields.append(("Transfer-Encoding", "chunked")) }
		if !keepAlive { head.fields.append(("Connection", "close")) }
		answered = true
		send(head.data)
	}

	func receive(_ data: Data, from task: URLSessionDataTask) {
		guard !ended, hasBody, !data.isEmpty else { return }
		traced?.bytes += data.count
		send(Data((String(data.count, radix: 16) + "\r\n").utf8) + data + Data("\r\n".utf8))
		if unsent > Self.backlog, !paused {
			paused = true
			task.suspend()
		}
	}

	func complete(_ error: Error?) {
		guard !ended else { return }
		task = nil
		if let traced, let trace = VboardProxy.trace {
			let ms = Int(Date().timeIntervalSince(traced.started) * 1000)
			trace("\(traced.line) → \(error == nil ? String(traced.status) : "failed: \(error!.localizedDescription)") \(ms) ms \(traced.bytes) B")
			self.traced = nil
		}
		if let error {
			return answered ? end() : badGateway(error.localizedDescription)
		}
		if hasBody { send(Data("0\r\n\r\n".utf8)) }
		responseDone = true
		// An answer before the whole body arrived ends the connection, which
		// is then out of step with the requests on it.
		if !requestDone { keepAlive = false }
		next()
	}

	private func send(_ data: Data) {
		unsent += data.count
		client.send(content: data, completion: .contentProcessed { [weak self] error in
			guard let self, !self.ended else { return }
			if error != nil { return self.end() }
			self.unsent -= data.count
			if self.paused, self.unsent < Self.backlog / 4 {
				self.paused = false
				self.task?.resume()
			}
		})
	}

	private func next() {
		guard responseDone, requestDone || !keepAlive else { return }
		guard keepAlive else { return finish() }
		body = nil
		let rest = leftover
		leftover = Data()
		scanRequest(rest)
	}

	private func finish() {
		client.send(content: nil, contentContext: .finalMessage, isComplete: true,
		            completion: .contentProcessed { [weak self] _ in self?.end() })
	}

	private static func reason(_ status: Int) -> String {
		[200: "OK", 201: "Created", 202: "Accepted", 204: "No Content", 206: "Partial Content",
		 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified",
		 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized",
		 403: "Forbidden", 404: "Not Found", 409: "Conflict", 413: "Content Too Large", 429: "Too Many Requests",
		 500: "Internal Server Error", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout"][status]
			?? "Status \(status)"
	}

	// MARK: A WebSocket, as bytes

	/// System trust and nothing weaker: a corporate root in the system keychain
	/// is trusted the way Safari trusts it. HTTP/1.1 only, because the relay
	/// reads HTTP/1 heads. A connect timeout, so that a server dropping packets —
	/// off the VPN, say — is a 502 in seconds rather than a socket that never opens.
	private func connect(sending first: Data) {
		let tcp = NWProtocolTCP.Options()
		tcp.connectionTimeout = 15
		let tls = NWProtocolTLS.Options()
		sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
		let parameters = NWParameters(tls: target.tls ? tls : nil, tcp: tcp)
		guard let port = NWEndpoint.Port(rawValue: target.port), !target.host.isEmpty else {
			return refuse(502, "Bad Gateway", "vboard server \(target.authority) is not an address")
		}
		let upstream = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: parameters)
		self.upstream = upstream
		upstream.stateUpdateHandler = { [weak self] state in
			guard let self, !self.ended else { return }
			switch state {
			case .ready:
				upstream.send(content: first, completion: .contentProcessed { [weak self] error in
					if error != nil { self?.end() }
				})
				self.relayClient(to: upstream)
				self.scanResponse(Data(), from: upstream)
			// Waiting is how a refused connection or a failed lookup shows: it
			// would retry for ever while the page waits for an answer.
			case .waiting(let error), .failed(let error):
				if let traced = self.traced, let trace = VboardProxy.trace {
					trace("\(traced.line) [socket] → failed: \(error) \(Int(Date().timeIntervalSince(traced.started) * 1000)) ms")
				}
				self.answered ? self.end() : self.badGateway("\(error)")
			case .cancelled:
				self.end()
			default:
				break
			}
		}
		upstream.start(queue: context.queue)
	}

	private func relayClient(to upstream: NWConnection) {
		client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
			guard let self, !self.ended else { return }
			let next = { complete || error != nil ? self.end() : self.relayClient(to: upstream) }
			guard let data, !data.isEmpty else { return next() }
			upstream.send(content: data, completion: .contentProcessed { error in
				error == nil ? next() : self.end()
			})
		}
	}

	private func scanResponse(_ buffer: Data, from upstream: NWConnection) {
		if let blank = buffer.range(of: Self.blank), blank.lowerBound - buffer.startIndex <= Self.cap {
			return response(head: buffer[..<blank.lowerBound], rest: buffer[blank.upperBound...], from: upstream)
		}
		guard buffer.count <= Self.cap else { return answered ? end() : badGateway("its answer's head is too long") }
		upstream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
			guard let self, !self.ended else { return }
			if let data, !data.isEmpty { return self.scanResponse(buffer + data, from: upstream) }
			if complete || error != nil {
				return self.answered ? self.end() : self.badGateway(error.map { "\($0)" } ?? "it closed without an answer")
			}
			self.scanResponse(buffer, from: upstream)
		}
	}

	/// Upstream cookies would be scoped to the wrong host and are not needed
	/// (the token is the sign-in); HSTS would be remembered against 127.0.0.1.
	private func response(head bytes: Data, rest: Data, from upstream: NWConnection) {
		guard var head = Head(bytes), let status = head.status else {
			return answered ? end() : badGateway("its answer is not HTTP")
		}
		if let traced, let trace = VboardProxy.trace {
			trace("\(traced.line) [socket] → \(status) \(Int(Date().timeIntervalSince(traced.started) * 1000)) ms")
		}
		head.remove("Set-Cookie")
		head.remove("Strict-Transport-Security")
		head.map("Location") { reorigin($0, from: target.origin, to: local) }
		answered = true
		let interim = (100..<200).contains(status) && status != 101
		client.send(content: head.data + (interim ? Data() : rest), completion: .contentProcessed { [weak self] error in
			guard let self, !self.ended else { return }
			if error != nil { return self.end() }
			interim ? self.scanResponse(Data(rest), from: upstream) : self.relayUpstream(upstream)
		})
	}

	/// For the socket's lifetime; the client side ending ends it too.
	private func relayUpstream(_ upstream: NWConnection) {
		upstream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
			guard let self, !self.ended else { return }
			let next = { complete || error != nil ? self.finish() : self.relayUpstream(upstream) }
			guard let data, !data.isEmpty else { return next() }
			self.client.send(content: data, completion: .contentProcessed { error in
				error == nil ? next() : self.end()
			})
		}
	}
}

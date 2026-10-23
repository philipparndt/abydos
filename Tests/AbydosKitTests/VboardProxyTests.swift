import Darwin
import Foundation
import Network
import Testing
import WebKit
@testable import AbydosKit

/// The loopback proxy a board tab shows a hosted vboard through, signing every
/// request with the person's token.
///
/// What is claimed: nothing reaches the server without the secret cookie only
/// the web view holds; what does reach it looks to the server like the page
/// talking to it directly, with the token of the moment added and the secret
/// taken out; many requests share a few connections to the server, which is
/// what took a board from 13 seconds to load to a fraction of that; what comes
/// back points at the proxy, is decoded, is never a redirect followed behind
/// the page's back, and leaves no cookie or HSTS behind; bodies either way
/// arrive byte for byte, held or streamed; a server out of reach is a 502; a
/// preferred port is taken when free and given up when not; and neither the
/// token nor the secret can leave through a description.
///
/// Against a stub upstream on loopback that records what it was sent, and —
/// where `vboard-local` is installed — against the real server and its real
/// page, WebSocket included. A skipped live test is not a pass.
struct VboardProxyTests {
	// MARK: A stub upstream

	/// One request as the upstream received it.
	private struct Received {
		let head: String
		let body: Data

		func values(_ name: String) -> [String] {
			head.components(separatedBy: "\r\n").dropFirst().compactMap { line in
				guard let colon = line.firstIndex(of: ":"),
				      line[..<colon].caseInsensitiveCompare(name) == .orderedSame else { return nil }
				return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			}
		}
	}

	/// An HTTP/1.1 server on loopback that keeps its connections, writes down
	/// every request and every connection, and answers what it was told to.
	private final class Stub: @unchecked Sendable {
		private let queue = DispatchQueue(label: "vboard-proxy-tests.stub")
		private let listener: NWListener
		private let answer: (UInt16) -> Data
		private var received: [Received] = []
		private var accepted = 0
		private(set) var port: UInt16 = 0
		/// Only on `queue`, once the listener is started.
		private var starting: CheckedContinuation<UInt16, Error>?

		/// - answer: what to answer, given the port the stub listens on.
		init(answer: @escaping (UInt16) -> Data) throws {
			self.answer = answer
			let parameters = NWParameters.tcp
			parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
			listener = try NWListener(using: parameters)
		}

		var requests: [Received] { queue.sync { received } }
		var connections: Int { queue.sync { accepted } }
		var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

		func start() async throws {
			let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
				starting = continuation
				listener.stateUpdateHandler = { [self] state in
					guard let starting else { return }
					switch state {
					case .ready: self.starting = nil; starting.resume(returning: listener.port!.rawValue)
					case .failed(let error): self.starting = nil; starting.resume(throwing: error)
					default: break
					}
				}
				listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
				listener.start(queue: queue)
			}
			self.port = port
		}

		func stop() { listener.cancel() }

		private func serve(_ connection: NWConnection) {
			accepted += 1
			connection.start(queue: queue)
			head(connection, Data())
		}

		private func head(_ connection: NWConnection, _ buffer: Data) {
			if let blank = buffer.range(of: Data("\r\n\r\n".utf8)) {
				let head = String(decoding: buffer[..<blank.lowerBound], as: UTF8.self)
				let request = Received(head: head, body: Data())
				let chunked = request.values("Transfer-Encoding").contains { $0.lowercased().contains("chunked") }
				let framer = chunked ? HTTPBodyFramer.chunked
					: HTTPBodyFramer(length: request.values("Content-Length").first.flatMap(Int.init) ?? 0)
				return body(connection, head, framer, Data(buffer[blank.upperBound...]), Data())
			}
			receive(connection) { self.head(connection, buffer + $0) }
		}

		private func body(_ connection: NWConnection, _ head: String, _ framer: HTTPBodyFramer, _ data: Data, _ held: Data) {
			var framer = framer
			guard let fed = try? framer.feed(data) else { return connection.cancel() }
			let held = held + fed.body
			guard framer.isDone else {
				return receive(connection) { self.body(connection, head, framer, $0, held) }
			}
			received.append(Received(head: head, body: held))
			connection.send(content: answer(port), completion: .contentProcessed { [weak self] _ in
				self?.head(connection, fed.rest)
			})
		}

		private func receive(_ connection: NWConnection, _ then: @escaping (Data) -> Void) {
			connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
				if let data, !data.isEmpty { return then(data) }
				if complete || error != nil { return connection.cancel() }
				then(Data())
			}
		}
	}

	private static func answer(_ status: String = "200 OK", headers: [String] = [], body: Data = Data()) -> Data {
		let head = (["HTTP/1.1 \(status)", "Content-Length: \(body.count)"] + headers)
			.joined(separator: "\r\n") + "\r\n\r\n"
		return Data(head.utf8) + body
	}

	private static func bytes(_ count: Int) -> Data {
		var generator = SystemRandomNumberGenerator()
		var data = Data(count: count)
		data.withUnsafeMutableBytes { raw in
			let words = raw.bindMemory(to: UInt64.self)
			for index in words.indices { words[index] = generator.next() }
		}
		return data
	}

	/// The same bytes as `gzip -n` makes them.
	private static func gzip(_ data: Data) throws -> Data {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("vboard-proxy-gzip-\(UUID().uuidString)")
		try data.write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
		process.arguments = ["-c", "-n", file.path]
		let output = Pipe()
		process.standardOutput = output
		try process.run()
		let compressed = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return compressed
	}

	/// Refuses to follow a redirect, so the test sees the one the proxy sent.
	private final class Unfollowed: NSObject, URLSessionTaskDelegate {
		func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
		                newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
			completionHandler(nil)
		}
	}

	/// A client that sends only the cookies it is told to.
	private static func client() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.urlCache = nil
		return URLSession(configuration: configuration)
	}

	private func send(_ request: URLRequest, on session: URLSession? = nil) async throws -> (HTTPURLResponse, Data) {
		let own = session == nil ? Self.client() : nil
		defer { own?.invalidateAndCancel() }
		let (data, response) = try await (session ?? own!).data(for: request, delegate: Unfollowed())
		return (try #require(response as? HTTPURLResponse), data)
	}

	private func request(_ proxy: VboardProxy, _ path: String, cookie: String?) throws -> URLRequest {
		var request = URLRequest(url: try #require(proxy.base).appendingPathComponent(path))
		request.timeoutInterval = 60
		if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
		return request
	}

	private func signed(_ proxy: VboardProxy, _ path: String) throws -> URLRequest {
		try request(proxy, path, cookie: "\(VboardProxy.cookieName)=\(proxy.secret)")
	}

	// MARK: Refusing

	@Test func aRequestWithoutTheSecretCookieIsRefusedAndNeverReachesTheServer() async throws {
		let stub = try Stub(answer: { _ in Self.answer(body: Data("hello".utf8)) })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		_ = try await proxy.start()
		defer { proxy.stop() }

		let (none, _) = try await send(try request(proxy, "api/v1/boards", cookie: nil))
		#expect(none.statusCode == 403)
		let (wrong, _) = try await send(try request(proxy, "api/v1/boards", cookie: "\(VboardProxy.cookieName)=\(String(proxy.secret.reversed()))"))
		#expect(wrong.statusCode == 403)
		#expect(stub.requests.isEmpty)
		#expect(stub.connections == 0)
	}

	// MARK: Forwarding

	@Test func theServerSeesItselfAsHostTheTokenAndEveryCookieButTheSecret() async throws {
		let stub = try Stub(answer: { _ in Self.answer() })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		let base = try await proxy.start()
		defer { proxy.stop() }

		var request = try request(proxy, "api/v1/boards", cookie: "theme=dark; \(VboardProxy.cookieName)=\(proxy.secret); lang=en")
		request.url = URL(string: base.absoluteString + "/api/v1/boards?folder=a%20b")
		request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
		request.setValue(base.absoluteString + "/b/b_0123456789abcdef", forHTTPHeaderField: "Referer")
		request.setValue("Bearer somebody-else", forHTTPHeaderField: "Authorization")
		let (response, _) = try await send(request)
		#expect(response.statusCode == 200)

		let received = try #require(stub.requests.first)
		#expect(received.head.hasPrefix("GET /api/v1/boards?folder=a%20b HTTP/1.1\r\n"))
		#expect(received.values("Host") == ["127.0.0.1:\(stub.port)"])
		#expect(received.values("Authorization") == ["Bearer the-token"])
		#expect(received.values("Cookie") == ["theme=dark; lang=en"])
		#expect(!received.head.contains(proxy.secret))
		#expect(received.values("Origin") == [stub.url.absoluteString])
		#expect(received.values("Referer") == [stub.url.absoluteString + "/b/b_0123456789abcdef"])
	}

	@Test func aRequestCarryingOnlyTheSecretReachesTheServerWithNoCookieAndWithoutATokenNoAuthorization() async throws {
		let stub = try Stub(answer: { _ in Self.answer() })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: nil)
		_ = try await proxy.start()
		defer { proxy.stop() }

		let (response, _) = try await send(try signed(proxy, "healthz"))
		#expect(response.statusCode == 200)
		let received = try #require(stub.requests.first)
		#expect(received.values("Cookie").isEmpty)
		#expect(received.values("Authorization").isEmpty)
	}

	@Test func aNewTokenIsWhatTheNextRequestCarries() async throws {
		let stub = try Stub(answer: { _ in Self.answer() })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "first")
		_ = try await proxy.start()
		defer { proxy.stop() }

		_ = try await send(try signed(proxy, "api/v1/me"))
		proxy.token = "second"
		_ = try await send(try signed(proxy, "api/v1/me"))
		proxy.token = nil
		_ = try await send(try signed(proxy, "api/v1/me"))
		#expect(stub.requests.map { $0.values("Authorization") } == [["Bearer first"], ["Bearer second"], []])
	}

	/// The claim that matters: a page's few hundred requests cost the server a
	/// handful of handshakes, not one each.
	@Test func manyRequestsReachTheServerOverAFewConnections() async throws {
		let stub = try Stub(answer: { _ in Self.answer(body: Data("{}".utf8)) })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		_ = try await proxy.start()
		defer { proxy.stop() }

		let session = Self.client()
		defer { session.invalidateAndCancel() }
		for index in 0..<40 {
			let (response, _) = try await send(try signed(proxy, "api/v1/items/\(index)"), on: session)
			#expect(response.statusCode == 200)
		}
		#expect(stub.requests.count == 40)
		#expect(stub.connections <= 6, "40 requests took \(stub.connections) connections to the server")
	}

	@Test func aRequestBodyArrivesByteForByte() async throws {
		let stub = try Stub(answer: { _ in Self.answer("201 Created") })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		_ = try await proxy.start()
		defer { proxy.stop() }

		let body = Self.bytes(1 << 20)
		var request = try signed(proxy, "api/v1/import")
		request.httpMethod = "POST"
		request.httpBody = body
		let (response, _) = try await send(request)
		#expect(response.statusCode == 201)
		let received = try #require(stub.requests.first)
		#expect(received.body.count == body.count)
		#expect(received.body == body, "the body was changed on the way")
	}

	/// Over what the proxy holds in memory, so it is passed on as it arrives.
	@Test func aBodyTooLargeToHoldIsStreamedAndArrivesByteForByte() async throws {
		let stub = try Stub(answer: { _ in Self.answer("201 Created") })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		_ = try await proxy.start()
		defer { proxy.stop() }

		let body = Self.bytes(40 << 20)
		var request = try signed(proxy, "api/v1/upload")
		request.httpMethod = "PUT"
		request.httpBody = body
		let started = Date()
		let (response, _) = try await send(request)
		#expect(response.statusCode == 201)
		let received = try #require(stub.requests.first)
		#expect(received.body.count == body.count, "after \(Date().timeIntervalSince(started)) s — \(MachineLoad.said)")
		#expect(received.body == body, "the body was changed on the way")
	}

	/// A body of unknown length — a stream — comes chunked.
	@Test func aChunkedRequestBodyArrivesByteForByte() async throws {
		let stub = try Stub(answer: { _ in Self.answer("201 Created") })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		_ = try await proxy.start()
		defer { proxy.stop() }

		let body = Self.bytes(3 << 20)
		var request = try signed(proxy, "api/v1/upload")
		request.httpMethod = "POST"
		request.httpBodyStream = InputStream(data: body)
		let (response, _) = try await send(request)
		#expect(response.statusCode == 201)
		let received = try #require(stub.requests.first)
		#expect(received.body == body, "\(received.body.count) of \(body.count) bytes, or different ones")
	}

	// MARK: Answering

	@Test func anAnswerPointsAtTheProxyKeepsNoCookieOrHSTSAndItsBodyArrivesByteForByte() async throws {
		let body = Self.bytes(2 << 20)
		// The answer names the stub's own origin, as a server's redirect would.
		let stub = try Stub(answer: { port in Self.answer("201 Created", headers: [
			"Location: http://127.0.0.1:\(port)/x?y=1",
			"Set-Cookie: session=abc; Path=/; HttpOnly",
			"Strict-Transport-Security: max-age=31536000",
			"Content-Security-Policy: default-src 'self'",
		], body: body) })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		let base = try await proxy.start()
		defer { proxy.stop() }

		let (response, data) = try await send(try signed(proxy, "file"))
		#expect(response.statusCode == 201)
		#expect(response.value(forHTTPHeaderField: "Location") == base.absoluteString + "/x?y=1")
		#expect(response.value(forHTTPHeaderField: "Set-Cookie") == nil)
		#expect(response.value(forHTTPHeaderField: "Strict-Transport-Security") == nil)
		#expect(response.value(forHTTPHeaderField: "Content-Security-Policy") == "default-src 'self'")
		#expect(data.count == body.count)
		#expect(data == body, "the body was changed on the way")
	}

	@Test func aCompressedAnswerArrivesDecoded() async throws {
		let original = Data(String(repeating: "a sticky on a board, ", count: 40_000).utf8) + Self.bytes(64 << 10)
		let compressed = try Self.gzip(original)
		#expect(compressed.count < original.count)
		let stub = try Stub(answer: { _ in Self.answer(headers: ["Content-Encoding: gzip", "Content-Type: text/plain"], body: compressed) })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		_ = try await proxy.start()
		defer { proxy.stop() }

		let (response, data) = try await send(try signed(proxy, "big.txt"))
		#expect(response.statusCode == 200)
		#expect(response.value(forHTTPHeaderField: "Content-Encoding") == nil)
		#expect(data == original, "\(data.count) bytes instead of \(original.count)")
	}

	@Test func aRedirectIsNotFollowedAndPointsAtTheProxy() async throws {
		let stub = try Stub(answer: { port in Self.answer("302 Found", headers: ["Location: http://127.0.0.1:\(port)/elsewhere"]) })
		try await stub.start()
		defer { stub.stop() }
		let proxy = VboardProxy(upstream: stub.url, token: "the-token")
		let base = try await proxy.start()
		defer { proxy.stop() }

		let (response, _) = try await send(try signed(proxy, "auth/login"))
		#expect(response.statusCode == 302)
		#expect(response.value(forHTTPHeaderField: "Location") == base.absoluteString + "/elsewhere")
		#expect(stub.requests.count == 1, "the proxy followed the redirect itself")
	}

	@Test func aServerNobodyListensOnIsABadGateway() async throws {
		let port = try #require(Self.freePort())
		let proxy = VboardProxy(upstream: URL(string: "http://127.0.0.1:\(port)")!, token: "the-token")
		_ = try await proxy.start()
		defer { proxy.stop() }

		let (response, data) = try await send(try signed(proxy, "healthz"))
		#expect(response.statusCode == 502)
		#expect(String(decoding: data, as: UTF8.self).contains("127.0.0.1:\(port)"))
	}

	// MARK: The preferred port

	@Test func aPreferredPortIsTakenWhenFreeAndGivenUpWhenNot() async throws {
		let stub = try Stub(answer: { _ in Self.answer() })
		try await stub.start()
		defer { stub.stop() }
		// The port comes from a proxy of the test's own and is never let go in
		// between: a port found free and then closed was taken by something else
		// in a full parallel run before the proxy could ask for it.
		let holder = VboardProxy(upstream: stub.url, token: nil)
		let preferred = try #require(try await holder.start().port)
		let second = VboardProxy(upstream: stub.url, token: nil)
		let fallback = try await second.start(preferredPort: UInt16(preferred))
		defer { second.stop() }
		#expect(fallback.port != preferred, "a port in use is given up")
		let (response, _) = try await send(try signed(second, "healthz"))
		#expect(response.statusCode == 200)

		holder.stop()
		let third = VboardProxy(upstream: stub.url, token: nil)
		defer { third.stop() }
		#expect(try await third.start(preferredPort: UInt16(preferred)).port == preferred, "a free port is taken")
	}

	// MARK: Saying nothing

	@Test func neitherTheTokenNorTheSecretAppearsInADescription() async throws {
		let proxy = VboardProxy(upstream: URL(string: "https://boards.example.org")!, token: "the-token-0123")
		_ = try await proxy.start()
		defer { proxy.stop() }
		var dumped = ""
		dump(proxy, to: &dumped)
		for said in ["\(proxy)", String(reflecting: proxy), dumped] {
			#expect(!said.contains("the-token-0123"))
			#expect(!said.contains(proxy.secret))
			#expect(said.contains("boards.example.org"))
		}
	}

	// MARK: Addresses

	@Test func anUpstreamURLIsTheSameURLThroughTheProxyAndTheCookieIsForItAlone() async throws {
		let proxy = VboardProxy(upstream: URL(string: "https://boards.example.org")!, token: nil)
		#expect(proxy.local(URL(string: "https://boards.example.org/b/x")!) == nil)
		#expect(proxy.cookie() == nil)
		let base = try await proxy.start()
		defer { proxy.stop() }

		#expect(proxy.local(URL(string: "https://boards.example.org/b/b_0123456789abcdef?x=1#k=abc")!)
			== URL(string: base.absoluteString + "/b/b_0123456789abcdef?x=1#k=abc"))
		#expect(proxy.local(URL(string: "https://elsewhere.example.org/b/x")!) == nil)
		let cookie = try #require(proxy.cookie())
		#expect(cookie.name == VboardProxy.cookieName)
		#expect(cookie.value == proxy.secret)
		#expect(cookie.domain == "127.0.0.1")
		#expect(cookie.path == "/")
		#expect(!cookie.isSecure)
		#expect(cookie.isHTTPOnly)
		#expect(cookie.sameSitePolicy == .sameSiteStrict)
		#expect(proxy.secret.count == 43)
	}

	// MARK: Free ports

	/// A port nobody is listening on, from the system: bind to port 0 and read
	/// back what it gave.
	private static func freePort() -> UInt16? {
		let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
		guard socket >= 0 else { return nil }
		defer { close(socket) }
		var address = sockaddr_in()
		address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		address.sin_family = sa_family_t(AF_INET)
		address.sin_port = 0
		address.sin_addr.s_addr = inet_addr("127.0.0.1")
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		let bound = withUnsafeMutablePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(socket, $0, length) == 0 && getsockname(socket, $0, &length) == 0
			}
		}
		guard bound else { return nil }
		return UInt16(bigEndian: address.sin_port)
	}
}

// MARK: - Live

/// The real server and its real page through the proxy: what the stub cannot
/// say is whether vboard's page, its API and its WebSocket still work when
/// they are not talking to the server directly.
///
/// `vboard-local` has no login, so these run without a token; the token's
/// way upstream is the stub's claim.
extension VboardProxyTests {
	/// A `vboard-local` this test started, and everything it owns.
	private final class Server {
		let process: Process
		let data: URL
		let base: URL

		init(process: Process, data: URL, base: URL) {
			self.process = process
			self.data = data
			self.base = base
		}

		/// Stops the process this test started — never one found by name —
		/// and removes its data.
		func stop() {
			if process.isRunning {
				process.terminate()
				process.waitUntilExit()
			}
			try? FileManager.default.removeItem(at: data)
		}
	}

	/// A server, or nil and one line saying why the test has nothing to do.
	private func startServer() async throws -> Server? {
		guard let program = Executables.locate("vboard-local") else {
			print("VBOARD: no vboard-local on the PATH — skipped")
			return nil
		}
		let data = FileManager.default.temporaryDirectory.appendingPathComponent("vboard-proxy-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
		// A port taken between asking and binding is tried again with another.
		for _ in 0..<3 {
			let port = try #require(Self.freePort())
			let process = Process()
			process.executableURL = URL(fileURLWithPath: program)
			process.arguments = ["--data", data.path, "--port", String(port), "--host", "127.0.0.1", "--no-browser"]
			var environment = ProcessInfo.processInfo.environment
			environment["VBOARD_NO_BROWSER"] = "1"
			process.environment = environment
			process.standardOutput = FileHandle.nullDevice
			process.standardError = FileHandle.nullDevice
			try process.run()
			let server = Server(process: process, data: data, base: URL(string: "http://127.0.0.1:\(port)")!)
			if await answers(server) { return server }
			if process.isRunning {
				process.terminate()
				process.waitUntilExit()
			}
		}
		try? FileManager.default.removeItem(at: data)
		Issue.record("vboard-local never answered /healthz — \(MachineLoad.said)")
		return nil
	}

	private func answers(_ server: Server) async -> Bool {
		let deadline = Date().addingTimeInterval(15)
		let client = VboardClient(server: server.base)
		while Date() < deadline, server.process.isRunning {
			if await client.health() == .done { return true }
			try? await Task.sleep(nanoseconds: 100_000_000)
		}
		return false
	}

	/// A board made from a copy of the retro fixture, in a scratch directory.
	private func board(on server: Server) async throws -> (VboardDocument, URL)? {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vboard-proxy-file-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let source = try #require(Bundle.module.url(forResource: "retro", withExtension: "vboard", subdirectory: "Fixtures"))
		let url = directory.appendingPathComponent("retro.vboard")
		try FileManager.default.copyItem(at: source, to: url)
		let document = VboardDocument(url: url, client: VboardClient(server: server.base))
		guard await document.open() == .onBoard else {
			Issue.record("the board did not open on vboard-local")
			try? FileManager.default.removeItem(at: directory)
			return nil
		}
		return (document, directory)
	}

	@Test func theBoardsWebSocketWorksThroughTheProxy() async throws {
		guard let server = try await startServer() else { return }
		defer { server.stop() }
		guard let (document, directory) = try await board(on: server) else { return }
		defer { try? FileManager.default.removeItem(at: directory) }
		let proxy = VboardProxy(upstream: server.base, token: nil)
		let base = try await proxy.start()
		defer { proxy.stop() }

		let port = try #require(base.port)
		let socketURL = try #require(URL(string: "ws://127.0.0.1:\(port)/api/v1/boards/\(document.boardID)/ws?pid=p_test&name=Test"))
		var request = URLRequest(url: socketURL)
		request.setValue("\(VboardProxy.cookieName)=\(proxy.secret)", forHTTPHeaderField: "Cookie")
		request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		let session = URLSession(configuration: configuration)
		defer { session.invalidateAndCancel() }
		let socket = session.webSocketTask(with: request)
		socket.resume()
		defer { socket.cancel(with: .normalClosure, reason: nil) }
		if let key = document.key {
			try await socket.send(.string(#"{"type":"auth","key":"\#(key.encoded)"}"#))
		}

		var types: [String] = []
		let started = Date()
		while Date().timeIntervalSince(started) < 30, !types.contains("snapshot") {
			guard case .string(let text) = try await socket.receive(),
			      let message = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
			      let type = message["type"] as? String else { continue }
			types.append(type)
		}
		#expect(types.contains("snapshot"), "no snapshot through the proxy, only \(types) — \(MachineLoad.said)")
		#expect(await document.end() == .done)
	}

	@MainActor
	private final class Listener: NSObject, WKScriptMessageHandler {
		var messages: [VboardPage.Message] = []
		let board: String
		init(board: String) { self.board = board }
		func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
			if let decoded = VboardPage.Message(message.body, board: board) { messages.append(decoded) }
		}
	}

	@MainActor
	@Test func theRealPageLoadsItsBoardThroughTheProxy() async throws {
		guard let server = try await startServer() else { return }
		defer { server.stop() }
		guard let (document, directory) = try await board(on: server) else { return }
		defer { try? FileManager.default.removeItem(at: directory) }
		let proxy = VboardProxy(upstream: server.base, token: nil)
		_ = try await proxy.start()
		defer { proxy.stop() }

		let listener = Listener(board: document.boardID)
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		await configuration.websiteDataStore.httpCookieStore.setCookie(try #require(proxy.cookie()))
		configuration.userContentController.addUserScript(WKUserScript(
			source: VboardPage.socketWatcher, injectionTime: .atDocumentStart, forMainFrameOnly: true
		))
		configuration.userContentController.addUserScript(WKUserScript(
			source: VboardPage.linkRewrite(proxy: try #require(proxy.base), server: URL(string: "https://boards.example.org")!),
			injectionTime: .atDocumentStart, forMainFrameOnly: true
		))
		configuration.userContentController.addUserScript(WKUserScript(
			source: VboardPage.noServiceWorker, injectionTime: .atDocumentStart, forMainFrameOnly: true
		))
		configuration.userContentController.add(listener, name: VboardPage.handlerName)
		defer { configuration.userContentController.removeScriptMessageHandler(forName: VboardPage.handlerName) }
		let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: configuration)
		web.load(URLRequest(url: try #require(proxy.local(document.link))))

		let deadline = Date().addingTimeInterval(30)
		let loaded = { listener.messages.contains { if case .snapshot = $0 { return true } else { return false } } }
		while !loaded(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
		#expect(loaded(), "the page never said its board loaded through the proxy: \(listener.messages) — \(MachineLoad.said)")
		#expect(web.url?.host == "127.0.0.1", "the page left the proxy for \(web.url?.absoluteString ?? "nothing")")

		// A link the page shows or copies names the server, not the proxy; the
		// page's own address, which it follows, is still the proxy's.
		let shown = try await web.callAsyncJavaScript("""
			const link = location.origin + "/b/x#k=y";
			const field = document.createElement("input");
			field.value = link;
			const words = document.createElement("p");
			document.body.appendChild(words);
			words.textContent = "Open " + link;
			await new Promise((done) => setTimeout(done, 50));
			const copied = new DataTransfer();
			copied.setData("text/plain", link);
			return [field.value, words.textContent, copied.getData("text/plain"), location.origin].join("|");
			""", arguments: [:], contentWorld: .page) as? String
		let parts = (shown ?? "").split(separator: "|").map(String.init)
		#expect(parts.count == 4)
		if parts.count == 4 {
			#expect(parts[0] == "https://boards.example.org/b/x#k=y")
			#expect(parts[1] == "Open https://boards.example.org/b/x#k=y")
			#expect(parts[2] == "https://boards.example.org/b/x#k=y")
			#expect(parts[3].hasPrefix("http://127.0.0.1:"))
		}
		// The page keeps no offline copy: its service worker never installs.
		try? await Task.sleep(nanoseconds: 500_000_000)
		let workers = try await web.callAsyncJavaScript(
			"return (await navigator.serviceWorker.getRegistrations()).length", arguments: [:], contentWorld: .page
		) as? Int
		#expect(workers == 0)
		#expect(await document.end() == .done)
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// The calls a board tab makes to a vboard server, against a stub that
/// answers the way `vboard-local` 0.67.0 answered when it was tried.
///
/// No network: the stub is a `URLProtocol` the client's session is given, and
/// every client has a host of its own so tests running side by side never read
/// each other's requests. The fixtures are files that server exported, with
/// the version in their own `app` field.
struct VboardClientTests {
	private func fixture(_ name: String) throws -> URL {
		try #require(Bundle.module.url(forResource: name, withExtension: "vboard", subdirectory: "Fixtures"))
	}

	private func scratch() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("vboard-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private func client(_ answer: @escaping (StubServer.Request) -> (Int, String)) -> (VboardClient, StubServer) {
		let stub = StubServer(plain: answer)
		let client = VboardClient(server: stub.base, protocolClasses: [StubProtocol.self])
		return (client, stub)
	}

	// MARK: The key and the link

	@Test func aKeyIsFortyThreeCharactersOfBase64URL() {
		let key = VboardKey.make()
		#expect(key.encoded.count == 43)
		#expect(key.encoded.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
		#expect(VboardKey.make() != key)
	}

	@Test func aKeyDoesNotPrintItself() {
		let key = VboardKey.make()
		#expect(!"\(key)".contains(key.encoded))
		#expect(!String(reflecting: key).contains(key.encoded))
	}

	@Test func aBoardIDIsTheShapeVboardAccepts() {
		let id = VboardBoardID.make()
		#expect(VboardBoardID.isValid(id))
		#expect(!VboardBoardID.isValid("b_ABCDEF0123456789"))
		#expect(!VboardBoardID.isValid("b_123"))
	}

	@Test func theLinkCarriesTheKeyInItsFragmentAndNowhereElse() throws {
		let key = VboardKey.make()
		let link = VboardLink.board(server: URL(string: "https://boards.example.org/")!, id: "b_0123456789abcdef", key: key)
		#expect(link.absoluteString == "https://boards.example.org/b/b_0123456789abcdef#k=\(key.encoded)")
		#expect(link.query == nil)
	}

	@Test func aServerUnderAPathKeepsItsPath() {
		let key = VboardKey.make()
		let link = VboardLink.board(server: URL(string: "https://example.org/vboard")!, id: "b_0123456789abcdef", key: key)
		#expect(link.path == "/vboard/b/b_0123456789abcdef")
	}

	// MARK: What a file is

	@Test func anExportedBoardIsABoard() throws {
		#expect(VboardFile.inspect(try fixture("retro")) == .board)
		#expect(VboardFile.inspect(try fixture("with-image")) == .board)
	}

	@Test func aKeptEncryptedExportIsRefused() throws {
		#expect(VboardFile.inspect(try fixture("encrypted")) == .encrypted)
	}

	@Test func anEmptyFileAndOneWithANewlineAreBothANewBoard() throws {
		let directory = try scratch()
		let empty = directory.appendingPathComponent("my.vboard")
		try Data().write(to: empty)
		#expect(VboardFile.inspect(empty) == .empty)
		let newline = directory.appendingPathComponent("other.vboard")
		try Data("\n".utf8).write(to: newline)
		#expect(VboardFile.inspect(newline) == .empty)
	}

	@Test func otherJSONIsNotABoard() {
		#expect(VboardFile.inspect(head: Data(#"{"name":"package.json"}"#.utf8), isWhole: true) == .notABoard)
		#expect(VboardFile.inspect(head: Data("not json at all".utf8), isWhole: true) == .notABoard)
	}

	@Test func aStickyThatSaysFormatVboardDoesNotMakeAFileABoard() {
		let head = #"{"items":[{"data":{"text":"\"format\":\"vboard\""}}]}"#
		#expect(VboardFile.inspect(head: Data(head.utf8), isWhole: true) == .notABoard)
	}

	@Test func aReindentedBoardWithSortedKeysIsStillABoard() {
		let head = "{\n  \"app\" : \"0.67.0\",\n  \"format\" : \"vboard\",\n  \"version\" : 1\n}"
		#expect(VboardFile.inspect(head: Data(head.utf8), isWhole: true) == .board)
	}

	// MARK: The calls

	@Test func anImportCarriesTheKeyInAHeaderAndTheIdInTheQuery() async throws {
		let (client, stub) = client { _ in (201, #"{"id":"b_0123456789abcdef","private":true}"#) }
		let key = VboardKey.make()
		let outcome = await client.importBoard(file: try fixture("retro"), id: "b_0123456789abcdef", key: key)
		#expect(outcome == .created)
		let request = try #require(stub.requests.first)
		#expect(request.method == "POST")
		#expect(request.url.path == "/api/v1/boards/import")
		#expect(request.url.query?.contains("temporary=true") == true)
		#expect(request.url.query?.contains("id=b_0123456789abcdef") == true)
		#expect(request.headers["X-Board-Key"] == key.encoded)
		#expect(!request.url.absoluteString.contains(key.encoded))
		#expect(request.body == (try Data(contentsOf: try fixture("retro"))))
	}

	@Test func whetherSomebodyIsSignedInIsAskedWithoutSendingAFile() async throws {
		let (client, stub) = client { _ in (401, #"{"error":"Please log in","code":"auth.loginRequired"}"#) }
		#expect(await client.signedIn() == .signedOut)
		#expect(stub.requests.first?.url.path == "/api/v1/me/usage")
		#expect(stub.requests.first?.body.isEmpty == true)
		let (open, _) = self.client { _ in (200, #"{"usage":{"boards":1}}"#) }
		#expect(await open.signedIn() == .done)
	}

	@Test func aTokenFromTheSignInSheetGoesOnEveryCall() async throws {
		let stub = StubServer(plain: { _ in (201, "{}") })
		let client = VboardClient(server: stub.base, token: "vbp_secret", protocolClasses: [StubProtocol.self])
		_ = await client.importBoard(file: try fixture("retro"), id: VboardBoardID.make(), key: .make())
		_ = await client.signedIn()
		#expect(stub.requests.count == 2)
		#expect(stub.requests.allSatisfy { $0.headers["Authorization"] == "Bearer vbp_secret" })
		#expect(stub.requests.allSatisfy { !$0.url.absoluteString.contains("vbp_secret") })
	}

	@Test func aTokenIsRevokedByItsId() async throws {
		let (client, stub) = client { _ in (204, "") }
		#expect(await client.revoke(tokenID: "t_123") == .done)
		#expect(stub.requests.first?.method == "DELETE")
		#expect(stub.requests.first?.url.path == "/api/v1/me/tokens/t_123")
	}

	@Test func aTakenIdIsRefusedRatherThanFailed() async throws {
		let (client, _) = client { _ in (409, #"{"error":"exists","code":"board.idTaken"}"#) }
		#expect(await client.importBoard(file: try fixture("retro"), id: VboardBoardID.make(), key: .make()) == .refused)
	}

	@Test func aReplacementVboardAcceptedIsReplaced() async throws {
		let (client, _) = client { _ in (200, #"{"id":"b_0123456789abcdef","replaced":true}"#) }
		#expect(await client.replace(file: try fixture("retro"), id: "b_0123456789abcdef", key: .make()) == .replaced)
	}

	@Test func aLoginPageInPlaceOfAnAnswerIsSignedOut() async throws {
		let (client, _) = client { _ in (200, "<!doctype html><title>Sign in</title>") }
		#expect(await client.importBoard(file: try fixture("retro"), id: VboardBoardID.make(), key: .make()) == .signedOut)
	}

	@Test func anUnauthorisedAnswerIsSignedOut() async throws {
		let (client, _) = client { _ in (401, #"{"error":"login required"}"#) }
		#expect(await client.delete(id: VboardBoardID.make(), key: .make()) == .signedOut)
	}

	@Test func whatTheServerSaysAboutAFailureIsKept() async throws {
		let (client, _) = client { _ in (413, #"{"error":"Die Datei ist zu groß"}"#) }
		let outcome = await client.importBoard(file: try fixture("retro"), id: VboardBoardID.make(), key: .make())
		#expect(outcome == .failed(status: 413, message: "Die Datei ist zu groß"))
	}

	@Test func theBoardListAsksTheServersPickerLookup() async throws {
		let (client, stub) = client { _ in (200, #"{"boards":[]}"#) }
		_ = await client.boards(matching: "retro", limit: 50)
		let request = try #require(stub.requests.first)
		#expect(request.method == "GET")
		#expect(request.url.path == "/api/v1/boards")
		#expect(request.url.query?.contains("q=retro") == true)
		#expect(request.url.query?.contains("limit=50") == true)
	}

	@Test func theBoardListLeavesOutPrivateBoardsAndReadsTheUpdate() async throws {
		let (client, _) = client { _ in
			(200, #"""
			{"boards":[
			  {"id":"b_1111111111111111","name":"Sprint 42 retro","updatedAt":"2026-10-24T09:34:59.579Z"},
			  {"id":"b_2222222222222222","name":"","private":true,"updatedAt":"2026-10-24T09:00:00Z"},
			  {"id":"b_3333333333333333","name":"","updatedAt":"2026-10-23T08:00:00Z"}
			]}
			"""#)
		}
		let boards = try await client.boards(matching: "").get()
		#expect(boards.map(\.id) == ["b_1111111111111111", "b_3333333333333333"])
		#expect(boards.map(\.name) == ["Sprint 42 retro", "b_3333333333333333"])
		#expect(boards.first?.updated == Date(timeIntervalSince1970: 1_792_834_499.579))
	}

	@Test func aBoardListWhileSignedOutSaysSo() async throws {
		let (client, _) = client { _ in (401, #"{"error":"Please log in"}"#) }
		#expect(await client.boards(matching: "") == .failure(VboardClient.ListFailure(outcome: .signedOut)))
	}

	@Test func anEmptyFileIsCreatedWithTheKeyInTheBodyNotTheURL() async throws {
		let (client, stub) = client { _ in (201, #"{"id":"b_0123456789abcdef"}"#) }
		let key = VboardKey.make()
		#expect(await client.create(id: "b_0123456789abcdef", name: "my", key: key) == .created)
		let request = try #require(stub.requests.first)
		#expect(request.url.path == "/api/v1/boards")
		#expect(!request.url.absoluteString.contains(key.encoded))
		let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
		#expect(body["name"] as? String == "my")
		#expect(body["private"] as? Bool == true)
		#expect(body["temporary"] as? Bool == true)
		#expect(body["key"] as? String == key.encoded)
		#expect(body["id"] as? String == "b_0123456789abcdef")
	}

	@Test func anExportLandsInTheDirectoryAskedForWithItsMarker() async throws {
		let board = try Data(contentsOf: try fixture("retro"))
		let stub = StubServer { _ in (200, String(decoding: board, as: UTF8.self), ["X-Vboard-Content-Rev": "17"]) }
		let client = VboardClient(server: stub.base, protocolClasses: [StubProtocol.self])
		let directory = try scratch()
		let key = VboardKey.make()
		let export = try await client.export(id: "b_0123456789abcdef", key: key, into: directory).get()
		#expect(export.file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
		#expect(try Data(contentsOf: export.file) == board)
		#expect(export.contentRev == 17)
		#expect(stub.requests.first?.headers["X-Board-Key"] == key.encoded)
	}

	@Test func anExportThatIsNotABoardIsNeverHandedOver() async throws {
		let (client, _) = client { _ in (200, "<!doctype html><title>Sign in</title>") }
		let directory = try scratch()
		let result = await client.export(id: "b_0123456789abcdef", key: .make(), into: directory)
		guard case .failure(let failure) = result else {
			Issue.record("a login page was handed over as a board")
			return
		}
		#expect(failure.outcome == VboardClient.Outcome.signedOut)
		#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
	}

	@Test func theWebSessionsCookiesAreSent() async throws {
		let stub = StubServer(plain: { _ in (204, "") })
		let cookie = try #require(HTTPCookie(properties: [
			.name: "vboard_session", .value: "s3ss10n", .domain: stub.base.host!, .path: "/",
		]))
		let client = VboardClient(server: stub.base, cookies: { [cookie] }, protocolClasses: [StubProtocol.self])
		_ = await client.delete(id: VboardBoardID.make(), key: .make())
		#expect(stub.requests.first?.headers["Cookie"]?.contains("vboard_session=s3ss10n") == true)
	}
}

extension VboardClientTests {
	private func cookie(_ name: String, domain: String, path: String = "/", secure: Bool = false, expires: Date? = nil) -> HTTPCookie {
		var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "v", .domain: domain, .path: path]
		if secure { properties[.secure] = "TRUE" }
		if let expires { properties[.expires] = expires }
		return HTTPCookie(properties: properties)!
	}

	@Test func onlyTheCookiesABrowserWouldSendAreSent() {
		let url = URL(string: "https://boards.example.org/api/v1/boards")!
		let sent = VboardClient.cookies([
			cookie("host", domain: "boards.example.org"),
			cookie("parent", domain: ".example.org"),
			cookie("elsewhere", domain: "example.com"),
			cookie("lookalike", domain: "ample.org"),
			cookie("api", domain: "boards.example.org", path: "/api"),
			cookie("apiary", domain: "boards.example.org", path: "/apiary"),
			cookie("expired", domain: "boards.example.org", expires: Date(timeIntervalSinceNow: -60)),
		], for: url).map(\.name)
		#expect(Set(sent) == ["host", "parent", "api"])
	}

	@Test func aSecureCookieIsNeverSentOverPlainHTTP() {
		let secure = cookie("session", domain: "localhost", secure: true)
		#expect(VboardClient.cookies([secure], for: URL(string: "http://localhost:7480/")!).isEmpty)
		#expect(VboardClient.cookies([secure], for: URL(string: "https://localhost:7480/")!).count == 1)
	}
}

// MARK: - The stub

/// A server that answers from a closure, one per test, found by its host.
final class StubServer: @unchecked Sendable {
	typealias Answer = (StubServer.Request) -> (Int, String, [String: String])

	struct Request {
		let method: String
		let url: URL
		let headers: [String: String]
		let body: Data
	}

	let base: URL
	let answer: Answer
	private let lock = NSLock()
	private var received: [Request] = []
	var requests: [Request] { lock.withLock { received } }

	init(answer: @escaping Answer) {
		self.answer = answer
		base = URL(string: "https://stub-\(UUID().uuidString.lowercased()).test")!
		StubServer.register(self)
	}

	convenience init(plain answer: @escaping (StubServer.Request) -> (Int, String)) {
		self.init(answer: { request -> (Int, String, [String: String]) in
			let (status, body) = answer(request)
			return (status, body, [:])
		})
	}

	func record(_ request: Request) { lock.withLock { received.append(request) } }

	private static let registryLock = NSLock()
	nonisolated(unsafe) private static var registry: [String: StubServer] = [:]
	static func register(_ server: StubServer) { registryLock.withLock { registry[server.base.host!] = server } }
	static func server(for host: String?) -> StubServer? { registryLock.withLock { host.flatMap { registry[$0] } } }
}

final class StubProtocol: URLProtocol {
	override class func canInit(with request: URLRequest) -> Bool { StubServer.server(for: request.url?.host) != nil }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		guard let url = request.url, let server = StubServer.server(for: url.host) else { return }
		let incoming = StubServer.Request(
			method: request.httpMethod ?? "GET",
			url: url,
			headers: request.allHTTPHeaderFields ?? [:],
			body: request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
		)
		server.record(incoming)
		let (status, body, answerHeaders) = server.answer(incoming)
		var fields = answerHeaders
		if fields["Content-Type"] == nil {
			fields["Content-Type"] = body.hasPrefix("{") || body.hasPrefix("[") ? "application/json" : "text/html"
		}
		let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: Data(body.utf8))
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}

	private static func read(_ stream: InputStream) -> Data {
		stream.open()
		defer { stream.close() }
		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 64 * 1024)
		while stream.hasBytesAvailable {
			let count = stream.read(&buffer, maxLength: buffer.count)
			if count <= 0 { break }
			data.append(buffer, count: count)
		}
		return data
	}
}

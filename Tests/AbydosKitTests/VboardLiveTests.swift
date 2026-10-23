import Darwin
import Foundation
import Testing
import WebKit
@testable import AbydosKit

/// A `.vboard` file on a real `vboard-local`: put there as a private board,
/// changed there, saved back, put back in place, and ended.
///
/// What the stub in `VboardDocumentTests` cannot say: that the server this
/// app is written against still answers the way the stub claims. The ids in
/// the file survive the import, the board is closed to anybody without its
/// key, a change made on the board is in the file after a save, and an ended
/// board is gone.
///
/// Every test starts a server of its own, on a free port and a scratch data
/// directory, and stops it by the process it started. Skipped where
/// `vboard-local` is not installed. A skipped live test is not a pass.
struct VboardLiveTests {
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
	private func start() async throws -> Server? {
		guard let program = Executables.locate("vboard-local") else {
			print("VBOARD: no vboard-local on the PATH — skipped")
			return nil
		}
		let data = FileManager.default.temporaryDirectory.appendingPathComponent("vboard-live-\(UUID().uuidString)")
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
		Issue.record("vboard-local never answered /healthz")
		return nil
	}

	/// Whether the server answers its health check within fifteen seconds, and
	/// is still the process this test started.
	private func answers(_ server: Server) async -> Bool {
		let deadline = Date().addingTimeInterval(15)
		let client = VboardClient(server: server.base)
		while Date() < deadline, server.process.isRunning {
			if await client.health() == .done { return true }
			try? await Task.sleep(nanoseconds: 100_000_000)
		}
		return false
	}

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

	// MARK: Files

	private func scratch() throws -> URL {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vboard-live-file-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private func copy(_ fixture: String, into directory: URL) throws -> URL {
		let source = try #require(Bundle.module.url(forResource: fixture, withExtension: "vboard", subdirectory: "Fixtures"))
		let url = directory.appendingPathComponent("\(fixture).vboard")
		try FileManager.default.copyItem(at: source, to: url)
		return url
	}

	private func json(_ url: URL) throws -> [String: Any] {
		try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
	}

	private func itemIDs(_ file: [String: Any]) -> Set<String> {
		Set((file["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
	}

	// MARK: Requests the app does not make

	/// A request made the way a colleague's page would, past the client under
	/// test, so that what it claims is checked by something other than itself.
	private func raw(
		_ server: Server,
		_ path: String,
		method: String = "GET",
		key: String?,
		body: [String: Any]? = nil
	) async throws -> (status: Int, body: Data) {
		var request = URLRequest(url: server.base.appendingPathComponent(path))
		request.httpMethod = method
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		if let key { request.setValue(key, forHTTPHeaderField: "X-Board-Key") }
		if let body {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
		}
		let session = URLSession(configuration: .ephemeral)
		defer { session.invalidateAndCancel() }
		let (data, response) = try await session.data(for: request)
		return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
	}

	// MARK: Opening

	@Test func aBoardFileOpenedPrivatelyKeepsItsItemIdsAndCannotBeReadWithoutItsKey() async throws {
		guard let server = try await start() else { return }
		defer { server.stop() }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = try copy("retro", into: directory)
		let document = VboardDocument(url: url, client: VboardClient(server: server.base))

		#expect(await document.open() == .onBoard)
		let board = "api/v1/boards/\(document.boardID)"
		#expect(try await raw(server, board, key: nil).status == 404)
		#expect(try await raw(server, board, key: VboardKey.make().encoded).status == 404)
		#expect(try await raw(server, board, key: document.key.encoded).status == 200)

		let items = try await raw(server, board + "/items", key: document.key.encoded)
		#expect(items.status == 200)
		let said = String(decoding: items.body, as: UTF8.self)
		for id in itemIDs(try json(url)) {
			#expect(said.contains(id), "\(id) was renamed by the import")
		}
		await document.end()
	}

	@Test func anEmptyFileBecomesABlankBoardNamedAfterItself() async throws {
		guard let server = try await start() else { return }
		defer { server.stop() }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("my.vboard")
		try Data().write(to: url)
		let document = VboardDocument(url: url, client: VboardClient(server: server.base))

		#expect(await document.open() == .onBoard)
		try await document.save()
		let file = try json(url)
		#expect(file["format"] as? String == "vboard")
		#expect((file["board"] as? [String: Any])?["name"] as? String == "my")
		await document.end()
	}

	// MARK: Saving

	@Test func aChangeMadeOnTheBoardReachesTheFileOnSave() async throws {
		guard let server = try await start() else { return }
		defer { server.stop() }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = try copy("retro", into: directory)
		let original = itemIDs(try json(url))
		let document = VboardDocument(url: url, client: VboardClient(server: server.base))
		#expect(await document.open() == .onBoard)

		let added = try await raw(
			server, "api/v1/boards/\(document.boardID)/items", method: "POST", key: document.key.encoded,
			body: ["items": [["type": "sticky", "x": 10, "y": 10, "data": ["text": "added live"]]]]
		)
		#expect((200..<300).contains(added.status))
		document.noteChange()
		#expect(document.isDirty)

		try await document.save()
		#expect(!document.isDirty)
		#expect(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("added live"))
		let saved = try json(url)
		#expect(saved["format"] as? String == "vboard")
		#expect(original.isSubset(of: itemIDs(saved)))
		#expect(!document.hasChangedOnDisk, "the document's own save is not somebody else's write")
		// Nothing of the save's temporary is left beside the file.
		#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["retro.vboard"])
		await document.end()
	}

	// MARK: Putting the file back

	@Test func aFileUnderANewerMarkerIsReplacedInPlace() async throws {
		guard let server = try await start() else { return }
		defer { server.stop() }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = try copy("retro", into: directory)
		let document = VboardDocument(url: url, client: VboardClient(server: server.base))
		#expect(await document.open() == .onBoard)
		let board = document.boardID
		let key = document.key

		// Somebody else writes the file: a newer marker and a sticky of their own.
		var file = try json(url)
		var meta = try #require(file["board"] as? [String: Any])
		meta["contentRev"] = (meta["contentRev"] as? Int ?? 1) + 10
		meta["lastChangeAt"] = "2099-01-01T00:00:00.000Z"
		file["board"] = meta
		var items = try #require(file["items"] as? [[String: Any]])
		var first = items[1]
		var data = first["data"] as? [String: Any] ?? [:]
		data["text"] = "written beside the board"
		first["data"] = data
		items[1] = first
		file["items"] = items
		try JSONSerialization.data(withJSONObject: file).write(to: url)

		#expect(await document.reload() == .replaced)
		#expect(document.boardID == board)
		#expect(document.key == key)
		let shown = try await raw(server, "api/v1/boards/\(board)/items", key: key.encoded)
		#expect(String(decoding: shown.body, as: UTF8.self).contains("written beside the board"))
		await document.end()
	}

	@Test func aFileThatIsNotNewerIsOpenedAgainOnANewBoard() async throws {
		guard let server = try await start() else { return }
		defer { server.stop() }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = try copy("retro", into: directory)
		let document = VboardDocument(url: url, client: VboardClient(server: server.base))
		#expect(await document.open() == .onBoard)
		let oldBoard = document.boardID
		let oldKey = document.key.encoded

		// The board moves on past the file, which then comes back unchanged:
		// a checkout of the version that was opened.
		let added = try await raw(
			server, "api/v1/boards/\(oldBoard)/items", method: "POST", key: oldKey,
			body: ["items": [["type": "sticky", "x": 10, "y": 10, "data": ["text": "newer on the board"]]]]
		)
		#expect((200..<300).contains(added.status))

		#expect(await document.reload() == .reopened)
		#expect(document.boardID != oldBoard)
		#expect(try await raw(server, "api/v1/boards/\(oldBoard)", key: oldKey).status == 404)
		#expect(try await raw(server, "api/v1/boards/\(document.boardID)", key: document.key.encoded).status == 200)
		await document.end()
	}

	// MARK: Ending

	@Test func endingTheSessionRemovesTheBoard() async throws {
		guard let server = try await start() else { return }
		defer { server.stop() }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = try copy("retro", into: directory)
		let document = VboardDocument(url: url, client: VboardClient(server: server.base))
		#expect(await document.open() == .onBoard)

		#expect(await document.end() == .done)
		#expect(try await raw(server, "api/v1/boards/\(document.boardID)", key: document.key.encoded).status == 404)
		#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["retro.vboard"])
	}
}

// MARK: - The page

/// The script the board tab puts into vboard's page, in vboard's real page.
///
/// The one claim nothing else can check: that wrapping the page's socket sees
/// what the tab needs — the board loading with its people, and a change made
/// by somebody else — without the tab being a participant. The page is the
/// web app `vboard-local` serves, in a `WKWebView` with the same script and
/// handler name the tab uses.
extension VboardLiveTests {
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
	private func waitFor(_ seconds: TimeInterval, _ condition: () -> Bool) async -> Bool {
		let deadline = Date().addingTimeInterval(seconds)
		while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
		return condition()
	}

	@MainActor
	@Test func thePagesOwnSocketSaysTheBoardLoadedAndThatSomebodyElseChangedIt() async throws {
		guard let server = try await start() else { return }
		defer { server.stop() }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let document = VboardDocument(url: try copy("retro", into: directory), client: VboardClient(server: server.base))
		#expect(await document.open() == .onBoard)
		defer { Task { await document.end() } }

		let listener = Listener(board: document.boardID)
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		configuration.userContentController.addUserScript(WKUserScript(
			source: VboardPage.socketWatcher, injectionTime: .atDocumentStart, forMainFrameOnly: true
		))
		configuration.userContentController.addUserScript(WKUserScript(
			source: VboardPage.slotRefusal, injectionTime: .atDocumentStart, forMainFrameOnly: true
		))
		configuration.userContentController.add(listener, name: VboardPage.handlerName)
		let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: configuration)
		defer { configuration.userContentController.removeScriptMessageHandler(forName: VboardPage.handlerName) }
		web.load(URLRequest(url: document.link))

		let loaded = await waitFor(30) {
			listener.messages.contains { if case .snapshot = $0 { return true } else { return false } }
		}
		#expect(loaded, "the page never said its board loaded: \(listener.messages)")
		guard loaded else { return }
		if case .snapshot(let people) = listener.messages.first(where: { if case .snapshot = $0 { return true } else { return false } }) {
			#expect(people == 1, "the page's own person, and nobody else")
		}

		// The page cannot keep the board in an account: its own call to do so is
		// refused in the page, and nothing else it asks for is.
		let slot = try await web.callAsyncJavaScript(
			"const r = await fetch('/api/v1/boards/' + board + '/my-slot', { method: 'POST', body: '{}' }); return r.status",
			arguments: ["board": document.boardID], contentWorld: .page
		) as? Int
		#expect(slot == 403)
		let other = try await web.callAsyncJavaScript(
			"const r = await fetch('/healthz'); return r.status", arguments: [:], contentWorld: .page
		) as? Int
		#expect(other == 200)

		// A colleague adds a sticky, over the API the board's page uses.
		let added = try await raw(
			server, "api/v1/boards/\(document.boardID)/items", method: "POST", key: document.key.encoded,
			body: ["items": [["type": "sticky", "x": 40, "y": 40, "data": ["text": "from a colleague"]]]]
		)
		#expect((200..<300).contains(added.status))
		#expect(await waitFor(10) { listener.messages.contains(.changed) }, "no change heard: \(listener.messages)")

		// And the end of the session reaches the page as a deletion — usually.
		// vboard tells only the sockets open at that moment, and a page starved
		// of time can be between two connections: in a full suite at load 40
		// this test took 84 s, heard the board load and the change, and not the
		// deletion. The tab treats hearing it as best effort for the same reason
		// (it waits two seconds and goes on), so a miss here is known rather
		// than a failure; a board still there afterwards is not.
		#expect(await document.end() == .done)
		let heard = await waitFor(10) { listener.messages.contains(.deleted(reason: "deleted")) }
		withKnownIssue("the page was between two connections when the board was deleted", isIntermittent: true) {
			#expect(heard, "no deletion heard: \(listener.messages) — \(MachineLoad.said)")
		}
		#expect(try await raw(server, "api/v1/boards/\(document.boardID)", key: document.key.encoded).status == 404)
	}
}

import Foundation
import Testing
@testable import IdeaiKit

/// Parsing what a language server says.
struct LSPMessageTests {
	@Test func readsAPosition() {
		let position = LSPPosition(json: ["line": 4, "character": 12])
		#expect(position == LSPPosition(line: 4, character: 12))
		#expect(LSPPosition(json: ["line": 1]) == nil)
		#expect(LSPPosition(json: "nonsense") == nil)
	}

	@Test func readsADiagnostic() {
		let diagnostic = LSPDiagnostic(json: [
			"range": ["start": ["line": 2, "character": 0], "end": ["line": 2, "character": 5]],
			"severity": 2,
			"message": "unused variable",
			"source": "swiftc",
			"code": 42,
		])

		#expect(diagnostic?.severity == .warning)
		#expect(diagnostic?.message == "unused variable")
		#expect(diagnostic?.source == "swiftc")
		// A code can be a number or a string, and is wanted as text either way.
		#expect(diagnostic?.code == "42")
	}

	/// A server that does not say how bad it is means an error, since that is
	/// the assumption somebody looks at rather than ignores.
	@Test func assumesAnErrorWhenSeverityIsMissing() {
		let diagnostic = LSPDiagnostic(json: [
			"range": ["start": ["line": 0, "character": 0], "end": ["line": 0, "character": 1]],
			"message": "something",
		])
		#expect(diagnostic?.severity == .error)
	}

	@Test func ordersSeverities() {
		#expect(LSPDiagnostic.Severity.error < .warning)
		#expect(LSPDiagnostic.Severity.warning < .hint)
	}

	/// Three shapes mean the same thing, and all three are sent in practice.
	@Test func readsEveryShapeOfLocation() {
		let range: [String: Any] = ["start": ["line": 1, "character": 2], "end": ["line": 1, "character": 8]]

		let plain = LSPLocation(json: ["uri": "file:///a.swift", "range": range])
		#expect(plain?.uri == "file:///a.swift")

		let link = LSPLocation(json: ["targetUri": "file:///b.swift", "targetSelectionRange": range])
		#expect(link?.uri == "file:///b.swift")

		// A link with only the wider range still says where to go.
		let wide = LSPLocation(json: ["targetUri": "file:///c.swift", "targetRange": range])
		#expect(wide?.uri == "file:///c.swift")
	}

	@Test func readsOneOrManyLocations() {
		let range: [String: Any] = ["start": ["line": 0, "character": 0], "end": ["line": 0, "character": 1]]
		let single: [String: Any] = ["uri": "file:///a.swift", "range": range]

		#expect(LSPLocation.list(from: single).count == 1)
		#expect(LSPLocation.list(from: [single, single]).count == 2)
		#expect(LSPLocation.list(from: NSNull()).isEmpty)
		#expect(LSPLocation.list(from: nil).isEmpty)
	}

	@Test func namesTheFileALocationPointsAt() {
		let range: [String: Any] = ["start": ["line": 0, "character": 0], "end": ["line": 0, "character": 1]]
		let location = LSPLocation(json: ["uri": "file:///tmp/a%20b.swift", "range": range])
		#expect(location?.url?.path == "/tmp/a b.swift")
	}

	/// Servers send hover text in four different shapes.
	@Test func flattensEveryShapeOfHover() {
		#expect(LSPHover(json: ["contents": "plain text"])?.contents == "plain text")

		#expect(LSPHover(json: [
			"contents": ["kind": "markdown", "value": "**bold**"],
		])?.contents == "**bold**")

		// The deprecated MarkedString, which is still what some servers send.
		#expect(LSPHover(json: [
			"contents": ["language": "swift", "value": "func f()"],
		])?.contents == "func f()")

		#expect(LSPHover(json: [
			"contents": ["one", ["kind": "plaintext", "value": "two"]],
		])?.contents == "one\n\ntwo")
	}

	@Test func saysNothingRatherThanAnEmptyHover() {
		#expect(LSPHover(json: ["contents": ""]) == nil)
		#expect(LSPHover(json: ["contents": []]) == nil)
		#expect(LSPHover(json: NSNull()) == nil)
	}

	@Test func readsCompletions() {
		let items: [String: Any] = [
			"isIncomplete": true,
			"items": [
				["label": "count", "kind": 5, "detail": "Int", "sortText": "0001"],
				["label": "map(_:)", "insertText": "map(", "documentation": "Transforms."],
			],
		]
		let completions = LSPCompletion.list(from: items)

		#expect(completions.count == 2)
		#expect(completions[0].insertText == "count")
		#expect(completions[0].detail == "Int")
		#expect(completions[1].insertText == "map(")
		#expect(completions[1].documentation == "Transforms.")
	}

	/// A textEdit says exactly what to insert and beats insertText.
	@Test func prefersTheEditOverTheHint() {
		let completion = LSPCompletion(json: [
			"label": "description",
			"insertText": "desc",
			"textEdit": ["newText": "description", "range": [
				"start": ["line": 0, "character": 0], "end": ["line": 0, "character": 4],
			]],
		])
		#expect(completion?.insertText == "description")
	}

	@Test func readsABareListOfCompletions() {
		#expect(LSPCompletion.list(from: [["label": "a"], ["label": "b"]]).count == 2)
		#expect(LSPCompletion.list(from: NSNull()).isEmpty)
	}
}

/// The framing, which is where a protocol client usually goes wrong.
struct LSPFramingTests {
	private func framed(_ object: [String: Any]) -> Data {
		let payload = try! JSONSerialization.data(withJSONObject: object)
		var data = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
		data.append(payload)
		return data
	}

	@Test func readsAMessageArrivingInPieces() async {
		let client = LSPClient()
		client.callbackQueue = .main

		let received = Received()
		client.onDiagnostics = { uri, diagnostics in
			received.record(uri: uri, count: diagnostics.count)
		}

		let message = framed([
			"jsonrpc": "2.0",
			"method": "textDocument/publishDiagnostics",
			"params": [
				"uri": "file:///a.swift",
				"diagnostics": [[
					"range": ["start": ["line": 0, "character": 0], "end": ["line": 0, "character": 3]],
					"message": "bad",
				]],
			],
		])

		// Split anywhere, including through the header: a pipe delivers what it
		// feels like, not what was written.
		for index in stride(from: 0, to: message.count, by: 7) {
			let end = min(index + 7, message.count)
			client.consume(message.subdata(in: index..<end))
		}

		try? await Task.sleep(nanoseconds: 200_000_000)
		#expect(received.uri == "file:///a.swift")
		#expect(received.count == 1)
	}

	@Test func readsTwoMessagesFromOneRead() async {
		let client = LSPClient()
		let received = Received()
		client.onMessage = { _, text in received.record(uri: text, count: received.count + 1) }

		var data = framed(["jsonrpc": "2.0", "method": "window/logMessage", "params": ["message": "one", "type": 3]])
		data.append(framed(["jsonrpc": "2.0", "method": "window/logMessage", "params": ["message": "two", "type": 3]]))
		client.consume(data)

		try? await Task.sleep(nanoseconds: 200_000_000)
		#expect(received.count == 2)
		#expect(received.uri == "two")
	}

	/// Rubbish in the stream must not wedge the reader for ever.
	@Test func survivesAMessageItCannotParse() async {
		let client = LSPClient()
		let received = Received()
		client.onMessage = { _, text in received.record(uri: text, count: 1) }

		var data = Data("Content-Length: 5\r\n\r\nnot{}".utf8)
		data.append(framed(["jsonrpc": "2.0", "method": "window/logMessage", "params": ["message": "after", "type": 3]]))
		client.consume(data)

		try? await Task.sleep(nanoseconds: 200_000_000)
		#expect(received.uri == "after")
	}

	@Test func refusesToTalkToAServerThatIsNotRunning() async {
		let client = LSPClient()
		await #expect(throws: LSPClient.ClientError.self) {
			try await client.request("textDocument/hover", nil)
		}
	}

	/// Collects callbacks from whichever queue they arrive on.
	private final class Received: @unchecked Sendable {
		private let lock = NSLock()
		private var _uri = ""
		private var _count = 0

		var uri: String { lock.lock(); defer { lock.unlock() }; return _uri }
		var count: Int { lock.lock(); defer { lock.unlock() }; return _count }

		func record(uri: String, count: Int) {
			lock.lock()
			_uri = uri
			_count = count
			lock.unlock()
		}
	}
}

/// Which server answers for which language.
struct LanguageServerRegistryTests {
	@Test func knowsAServerForTheUsualLanguages() {
		#expect(LanguageServers.definition(forLanguage: "swift")?.command == "sourcekit-lsp")
		#expect(LanguageServers.definition(forLanguage: "go")?.command == "gopls")
		#expect(LanguageServers.definition(forLanguage: "typescript")?.arguments == ["--stdio"])
		#expect(LanguageServers.definition(forLanguage: "cobol") == nil)
	}

	/// A stray file of some language does not mean the project is in it.
	@Test func wantsToSeeAProjectItUnderstands() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("servers-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let go = try #require(LanguageServers.definition(forLanguage: "go"))
		#expect(!LanguageServers.suits(go, root: root))

		try "module x\n".write(to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
		#expect(LanguageServers.suits(go, root: root))
	}

	/// Swift projects are recognised by an extension as well as a file name.
	@Test func matchesAMarkerByExtension() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("servers-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcodeproj"),
			withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let swift = try #require(LanguageServers.definition(forLanguage: "swift"))
		#expect(LanguageServers.suits(swift, root: root))
	}

	/// A server with nothing to look for is happy anywhere.
	@Test func startsAnywhereWhenItHasNoMarkers() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
		let json = try #require(LanguageServers.definition(forLanguage: "json"))
		#expect(LanguageServers.suits(json, root: root))
	}

	/// A GUI app inherits almost nothing of a shell's PATH, so the usual homes
	/// of these tools are searched whether or not it is set.
	@Test func looksWhereToolsActuallyLive() {
		let paths = LanguageServers.searchPaths
		#expect(paths.contains("/opt/homebrew/bin"))
		#expect(paths.contains("/usr/local/bin"))
		#expect(paths.contains { $0.hasSuffix("/go/bin") })
		// And never the same directory twice.
		#expect(Set(paths).count == paths.count)
	}

	@Test func saysNothingAboutAServerThatIsNotInstalled() {
		let missing = LanguageServerDefinition(
			languageIds: ["x"], command: "definitely-not-installed-\(UUID().uuidString)",
			installHint: "nowhere"
		)
		#expect(LanguageServers.executable(for: missing) == nil)
	}
}

/// Symbols, in both shapes servers send them.
struct LSPSymbolTests {
	private let range: [String: Any] = [
		"start": ["line": 4, "character": 2],
		"end": ["line": 4, "character": 12],
	]

	/// `workspace/symbol` answers with SymbolInformation, which has a location.
	@Test func readsAFlatSymbol() {
		let symbol = LSPSymbol(json: [
			"name": "WordMotion",
			"kind": 10,
			"location": ["uri": "file:///a.swift", "range": range],
			"containerName": "IdeaiKit",
		])
		#expect(symbol?.name == "WordMotion")
		#expect(symbol?.kind == .enum)
		#expect(symbol?.container == "IdeaiKit")
		#expect(symbol?.location.range.start.line == 4)
	}

	/// `textDocument/documentSymbol` answers with a tree, and a "go to" wants
	/// every one of them rather than the outline.
	@Test func flattensTheNestedShape() {
		let symbols = LSPSymbol.list(from: [[
			"name": "WordMotion",
			"kind": 10,
			"range": range,
			"selectionRange": range,
			"children": [
				["name": "Class", "kind": 10, "range": range, "selectionRange": range, "children": []],
				["name": "classify(_:)", "kind": 6, "range": range, "selectionRange": range,
				 "children": [
					["name": "inner", "kind": 13, "range": range, "selectionRange": range, "children": []],
				 ]],
			],
		]], uri: "file:///a.swift")

		#expect(symbols.map(\.name) == ["WordMotion", "Class", "classify(_:)", "inner"])
		#expect(symbols.allSatisfy { $0.location.uri == "file:///a.swift" })
	}

	/// The selection range is the name itself; the range covers the whole
	/// declaration. Jumping to the name is what somebody wants.
	@Test func prefersTheNameOverTheWholeDeclaration() {
		let symbols = LSPSymbol.list(from: [[
			"name": "run",
			"kind": 6,
			"range": ["start": ["line": 10, "character": 0], "end": ["line": 20, "character": 1]],
			"selectionRange": ["start": ["line": 10, "character": 9], "end": ["line": 10, "character": 12]],
			"children": [],
		]], uri: "file:///a.swift")

		#expect(symbols.first?.location.range.start.line == 10)
		#expect(symbols.first?.location.range.start.character == 9)
	}

	@Test func namesEachKindInAWordSomebodyWouldUse() {
		#expect(LSPSymbol.Kind.function.label == "func")
		#expect(LSPSymbol.Kind.struct.label == "struct")
		#expect(LSPSymbol.Kind.enumMember.label == "case")
		#expect(LSPSymbol.Kind.file.label == "")
	}

	@Test func survivesRepliesItCannotRead() {
		#expect(LSPSymbol.list(from: NSNull(), uri: "file:///a").isEmpty)
		#expect(LSPSymbol.list(from: ["nonsense"], uri: "file:///a").isEmpty)
		#expect(LSPSymbol(json: ["kind": 6]) == nil)
	}
}

/// Nothing may be sent before the handshake lands.
struct LSPHandshakeOrderTests {
	/// A server rejects everything that arrives before `initialize`, quietly:
	/// the document is never registered, and every later question about it
	/// comes back "no language service for this file".
	@Test func holdsNotificationsUntilInitialized() async throws {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		guard let server = LanguageServers.resolve(languageId: "swift", root: root) else { return }

		let client = LSPClient()
		defer { client.stop() }
		try client.start(
			executable: server.executable,
			arguments: server.definition.arguments,
			workingDirectory: root
		)

		// Sent immediately, before the handshake is even asked for — which is
		// exactly what the editor does when a file is already open at launch.
		let file = root.appendingPathComponent("Sources/IdeaiKit/Text/WordMotion.swift")
		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: file.absoluteString, languageId: "swift", version: 1, text: text)

		_ = try await client.initialize(rootURL: root)
		try? await Task.sleep(nanoseconds: 3_000_000_000)

		// The server knows the document, so it can answer about it.
		let symbols = try await client.documentSymbols(uri: file.absoluteString)
		#expect(!symbols.isEmpty)
		#expect(symbols.contains { $0.name == "WordMotion" })

		await client.shutdown()
	}
}

/// Finding the directory a server should be rooted at.
struct LanguageServerRootTests {
	private func makeTree(_ paths: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("roots-\(UUID().uuidString)")
		for path in paths {
			let url = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try "x".write(to: url, atomically: true, encoding: .utf8)
		}
		return root
	}

	@Test func findsAManifestAtTheRoot() throws {
		let root = try makeTree(["go.mod", "main.go"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go"))
		#expect(LanguageServers.markerDirectory(for: go, in: root) == root)
	}

	/// A repository commonly keeps its manifest a level down — `app/go.mod` —
	/// and a server rooted at the directory above it answers nothing at all.
	@Test func findsAManifestBelowTheRoot() throws {
		let root = try makeTree(["README.md", "app/go.mod", "app/main.go"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go"))

		let found = LanguageServers.markerDirectory(for: go, in: root)
		#expect(found?.lastPathComponent == "app")
		#expect(LanguageServers.suits(go, root: root))
	}

	@Test func findsOneTwoLevelsDown() throws {
		let root = try makeTree(["services/api/go.mod"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go"))
		#expect(LanguageServers.markerDirectory(for: go, in: root)?.lastPathComponent == "api")
	}

	/// Vendored copies are not the project.
	@Test func ignoresVendoredManifests() throws {
		let root = try makeTree(["vendor/other/go.mod", "node_modules/thing/package.json"])
		defer { try? FileManager.default.removeItem(at: root) }

		let go = try #require(LanguageServers.definition(forLanguage: "go"))
		#expect(LanguageServers.markerDirectory(for: go, in: root) == nil)

		let ts = try #require(LanguageServers.definition(forLanguage: "typescript"))
		#expect(LanguageServers.markerDirectory(for: ts, in: root) == nil)
	}

	@Test func saysNoWhenThereIsNoManifestAnywhere() throws {
		let root = try makeTree(["notes.txt", "docs/readme.md"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go"))
		#expect(LanguageServers.markerDirectory(for: go, in: root) == nil)
		#expect(!LanguageServers.suits(go, root: root))
	}

	/// The resolved root is what the server is started in, and it is the
	/// manifest's directory rather than the project's.
	@Test func resolvesToTheManifestDirectory() throws {
		let root = try makeTree(["app/go.mod"])
		defer { try? FileManager.default.removeItem(at: root) }
		guard let resolved = LanguageServers.resolve(languageId: "go", root: root) else { return }
		#expect(resolved.root.lastPathComponent == "app")
	}
}

/// Offering a server that is not installed.
///
/// The bar above the editor is the only place that says why a file has no
/// completion, no problems and no go-to-declaration — so what it decides to
/// say, and when it decides to say nothing, is the whole feature.
struct LanguageServerSuggestionTests {
	/// Certainly not installed, on this machine or anyone's.
	private let absent = LanguageServerDefinition(
		languageIds: ["go"],
		command: "no-such-language-server-38f1c2",
		installHint: "go install example.com/no-such-server@latest",
		rootMarkers: ["go.mod"]
	)

	private func makeTree(_ paths: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("suggest-\(UUID().uuidString)")
		for path in paths {
			let url = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try "x".write(to: url, atomically: true, encoding: .utf8)
		}
		return root
	}

	@Test func offersAServerThatIsNotInstalled() throws {
		let root = try makeTree(["go.mod", "main.go"])
		defer { try? FileManager.default.removeItem(at: root) }

		let suggestion = LanguageServers.suggestion(
			absent, forLanguage: "go", root: root, ignoring: []
		)
		#expect(suggestion?.command == "no-such-language-server-38f1c2")
		// Named the way somebody would say it, for a sentence they read once.
		#expect(suggestion?.languageName == "Go")
	}

	/// A stray `.go` file in a repository of something else is not a Go project,
	/// and offering to install a Go server for it is noise about somebody else's
	/// language.
	@Test func saysNothingWhereTheProjectIsNotOne() throws {
		let root = try makeTree(["notes.txt"])
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(LanguageServers.suggestion(absent, forLanguage: "go", root: root, ignoring: []) == nil)
	}

	/// The Ignore button's whole job.
	@Test func saysNothingAboutAnIgnoredLanguage() throws {
		let root = try makeTree(["go.mod"])
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(
			LanguageServers.suggestion(absent, forLanguage: "go", root: root, ignoring: ["go"]) == nil
		)
	}

	/// An editor that offers to install what you already have is one people
	/// learn to ignore, so an installed server says nothing at all.
	@Test func saysNothingWhenTheServerIsInstalled() throws {
		let root = try makeTree(["go.mod"])
		defer { try? FileManager.default.removeItem(at: root) }

		let present = LanguageServerDefinition(
			languageIds: ["go"], command: "sh", installHint: "already here", rootMarkers: ["go.mod"]
		)
		#expect(LanguageServers.suggestion(present, forLanguage: "go", root: root, ignoring: []) == nil)
	}

	/// A language with no server anybody knows about has nothing to offer.
	@Test func saysNothingAboutALanguageWithNoServer() throws {
		let root = try makeTree(["notes.txt"])
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(LanguageServers.suggestion(forLanguage: "markdown", root: root) == nil)
	}

	/// What the details panel says has to be actionable on its own: the command
	/// to run, where the result has to land, and how to check.
	@Test func theManualSaysWhatToDoAndWhereItGoes() throws {
		let root = try makeTree(["go.mod"])
		defer { try? FileManager.default.removeItem(at: root) }
		let suggestion = try #require(
			LanguageServers.suggestion(absent, forLanguage: "go", root: root, ignoring: [])
		)

		let manual = suggestion.manual
		#expect(manual.contains("go install example.com/no-such-server@latest"))
		#expect(manual.contains("which no-such-language-server-38f1c2"))
		// The directories this app searches, which are not the ones a login
		// shell would — the difference that costs the hours.
		#expect(manual.contains("/opt/homebrew/bin"))
		#expect(manual.contains(NSHomeDirectory() + "/go/bin"))
	}
}

/// The environment a server is started in.
///
/// The failure this exists for: `gopls` was found, started, and answered the
/// handshake — and then could not run `go`, because an app launched from the
/// Dock has `/usr/bin:/bin` and the two sbins. What it says then is "No active
/// builds contain main.go", which reads as a fact about the project. Nothing
/// about the editor said otherwise: diagnostics appeared, and every question
/// about a symbol came back empty.
struct LanguageServerEnvironmentTests {
	@Test func putsTheToolchainOnThePath() {
		let path = LanguageServers.serverEnvironment["PATH"] ?? ""
		let directories = path.split(separator: ":").map(String.init)

		// Where a compiler actually lives, whichever of these this machine
		// uses.
		#expect(directories.contains("/opt/homebrew/bin"))
		#expect(directories.contains("/usr/local/bin"))
		#expect(directories.contains("/usr/local/go/bin"))
		#expect(directories.contains(NSHomeDirectory() + "/go/bin"))
	}

	/// A `PATH` somebody set deliberately still chooses the toolchain: the
	/// directories added here go after it, not in front of it.
	@Test func keepsTheInheritedPathFirst() {
		let inherited = ProcessInfo.processInfo.environment["PATH"]?
			.split(separator: ":").map(String.init) ?? []
		let resolved = (LanguageServers.serverEnvironment["PATH"] ?? "")
			.split(separator: ":").map(String.init)

		guard let first = inherited.first else { return }
		#expect(resolved.first == first)
	}

	/// Everything else the process has — `HOME`, the Go module cache, whatever
	/// a toolchain manager set — is carried across untouched. A server started
	/// with only a `PATH` is a server with no `HOME`, and Go puts its cache in
	/// one.
	@Test func carriesTheRestOfTheEnvironment() {
		let environment = LanguageServers.serverEnvironment
		#expect(environment["HOME"] == ProcessInfo.processInfo.environment["HOME"])
	}

	/// A server explains itself on standard error, and that used to be read and
	/// dropped — the one place some of them say why they are about to be
	/// useless.
	@Test func handsOnWhatTheServerWroteToStandardError() async throws {
		let client = LSPClient()
		defer { client.stop() }

		let said = Mailbox()
		client.callbackQueue = .main
		client.onStandardError = { text in Task { await said.put(text) } }

		try client.start(
			executable: "/bin/sh",
			arguments: ["-c", "echo 'cannot find the toolchain' >&2; sleep 2"],
			workingDirectory: nil
		)

		#expect(await said.wait(seconds: 3)?.contains("cannot find the toolchain") == true)
	}
}

/// One value, awaited until it arrives.
private actor Mailbox {
	private var value: String?

	func put(_ text: String) { value = value ?? text }

	func wait(seconds: Double) async -> String? {
		let deadline = Date().addingTimeInterval(seconds)
		while Date() < deadline {
			if let value { return value }
			try? await Task.sleep(nanoseconds: 50_000_000)
		}
		return value
	}
}

/// The log that makes a failure on somebody else's machine reportable.
struct DiagnosticLogTests {
	@Test func writesALineAndStartsAgainWhenItGrows() throws {
		let name = "test-\(UUID().uuidString)"
		let file = DiagnosticLog.url(name)
		defer {
			try? FileManager.default.removeItem(at: file)
			try? FileManager.default.removeItem(at: file.appendingPathExtension("1"))
		}

		DiagnosticLog.write("gopls started", to: name)
		let written = try String(contentsOf: file, encoding: .utf8)
		#expect(written.contains("gopls started"))
		// Stamped, so two runs of the same failure can be told apart.
		#expect(written.hasPrefix("20"))

		// Past the limit the log starts again, with the old one beside it.
		try String(repeating: "x", count: DiagnosticLog.sizeLimit + 1)
			.write(to: file, atomically: true, encoding: .utf8)
		DiagnosticLog.write("gopls exited", to: name)

		let fresh = try String(contentsOf: file, encoding: .utf8)
		#expect(fresh.contains("gopls exited"))
		#expect(!fresh.contains("xxxx"))
		#expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("1").path))
	}
}

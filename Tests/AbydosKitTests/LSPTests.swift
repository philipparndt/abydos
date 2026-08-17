import Foundation
import Testing
@testable import AbydosKit

/// Parsing what a language server says.
struct LSPMessageTests {
	@Test func readsAPosition() {
		let position = LSPPosition(json: ["line": 4, "character": 12])
		#expect(position == LSPPosition(line: 4, character: 12))
		#expect(LSPPosition(json: ["line": 1]) == nil)
		#expect(LSPPosition(json: "nonsense") == nil)
	}

	/// How wide a place is, for *showing* it rather than only scrolling to it: a
	/// symbol's name where the range stays on one line, and nothing at all where
	/// the server pointed at more than one (item 533).
	@Test func measuresARangeOnOneLine() {
		#expect(LSPRange(
			start: LSPPosition(line: 12, character: 8),
			end: LSPPosition(line: 12, character: 20)
		).widthOnOneLine == 12)
		#expect(LSPRange(
			start: LSPPosition(line: 12, character: 8),
			end: LSPPosition(line: 19, character: 3)
		).widthOnOneLine == 0)
		// A server that hands its ends back the wrong way round says nothing
		// rather than a negative width.
		#expect(LSPRange(
			start: LSPPosition(line: 4, character: 9),
			end: LSPPosition(line: 4, character: 2)
		).widthOnOneLine == 0)
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
		#expect(LanguageServers.definition(forLanguage: "swift", choosing: .none)?.command == "sourcekit-lsp")
		#expect(LanguageServers.definition(forLanguage: "go", choosing: .none)?.command == "gopls")
		#expect(LanguageServers.definition(forLanguage: "typescript", choosing: .none)?.arguments == ["--stdio"])
		#expect(LanguageServers.definition(forLanguage: "cobol", choosing: .none) == nil)
	}

	/// A stray file of some language does not mean the project is in it.
	@Test func wantsToSeeAProjectItUnderstands() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("servers-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let go = try #require(LanguageServers.definition(forLanguage: "go", choosing: .none))
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

		let swift = try #require(LanguageServers.definition(forLanguage: "swift", choosing: .none))
		#expect(LanguageServers.suits(swift, root: root))
	}

	/// A server with nothing to look for is happy anywhere.
	@Test func startsAnywhereWhenItHasNoMarkers() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
		let json = try #require(LanguageServers.definition(forLanguage: "json", choosing: .none))
		#expect(LanguageServers.suits(json, root: root))
	}

	/// A GUI app inherits almost nothing of a shell's PATH, so the usual homes
	/// of these tools are searched whether or not it is set.
	@Test func looksWhereToolsActuallyLive() {
		let paths = Executables.searchPaths
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

/// Which Swift the editor means, which has to be the one the build used.
///
/// Measured before this existed: the servers answering were
/// `~/.swiftly/bin/sourcekit-lsp`, running out of a 6.1.2 toolchain, while
/// `xcrun` had Xcode's all along — so the red squiggles on screen came from a
/// compiler the build never ran.
struct XcodeToolchainTests {
	/// Only the three a toolchain manager also ships. Asking `xcrun` for `gopls`
	/// would find nothing and be a slower way of finding nothing.
	@Test func claimsOnlyWhatXcodeActuallyOwns() {
		#expect(XcodeToolchain.owns("sourcekit-lsp"))
		#expect(XcodeToolchain.owns("clangd"))
		#expect(XcodeToolchain.owns("lldb-dap"))
		#expect(!XcodeToolchain.owns("gopls"))
		#expect(!XcodeToolchain.owns("rust-analyzer"))
	}

	@Test func hasNoAnswerForAToolXcodeDoesNotShip() {
		#expect(XcodeToolchain.path(for: "definitely-not-a-tool-\(UUID().uuidString)") == nil)
	}

	/// The resolution itself: where Xcode has the tool, that is the one, whatever
	/// the `PATH` says first.
	///
	/// Conditional on Xcode being installed rather than skipped outright: on a
	/// machine with only the command-line tools there is nothing to prefer, and
	/// the fallback to the `PATH` is then the right answer rather than a failure.
	@Test func prefersXcodesCopyOverWhateverIsFirstOnThePath() throws {
		let swift = try #require(LanguageServers.definition(forLanguage: "swift", choosing: .none))
		guard let fromXcode = XcodeToolchain.path(for: "sourcekit-lsp") else { return }

		#expect(LanguageServers.executable(for: swift) == fromXcode)
		// And it is Xcode's, not a toolchain a version manager dropped in front
		// of it — the exact shape of the fault this was written for.
		#expect(!fromXcode.contains("/.swiftly/"))
		#expect(!fromXcode.contains("/Library/Developer/Toolchains/swift-"))
	}

	/// The debugger has the same two copies and the same reason to prefer one:
	/// a frame read by one toolchain's `lldb-dap` out of a binary the other
	/// compiled is a frame nobody can trust.
	@Test func theDebuggerComesFromTheSamePlaceAsTheCompiler() throws {
		guard let fromXcode = XcodeToolchain.path(for: "lldb-dap") else { return }
		#expect(DebugAdapters.executable(for: DebugAdapters.lldb) == fromXcode)
	}
}

/// One server per language per project — where "language" means the server, not
/// the file extension.
struct LanguageServerKeyTests {
	private let project = URL(fileURLWithPath: "/tmp/project")

	/// The fault, measured: opening `main.c` and `thing.cpp` in one project
	/// started two `clangd`, because the table was keyed by the language asked
	/// about and one server answers for three of them.
	@Test func oneServerAnswersForAllTheLanguagesItKnows() {
		let c = LanguageServers.serverKey(project: project, languageId: "c", choosing: .none)
		#expect(LanguageServers.serverKey(project: project, languageId: "cpp", choosing: .none) == c)
		#expect(LanguageServers.serverKey(project: project, languageId: "objc", choosing: .none) == c)

		let typescript = LanguageServers.serverKey(project: project, languageId: "typescript", choosing: .none)
		#expect(LanguageServers.serverKey(project: project, languageId: "javascript", choosing: .none) == typescript)
		#expect(LanguageServers.serverKey(project: project, languageId: "tsx", choosing: .none) == typescript)
	}

	@Test func differentServersAreStillDifferentKeys() {
		#expect(LanguageServers.serverKey(project: project, languageId: "swift", choosing: .none)
			!= LanguageServers.serverKey(project: project, languageId: "go", choosing: .none))
	}

	@Test func twoProjectsDoNotShareAServer() {
		#expect(LanguageServers.serverKey(project: project, languageId: "swift", choosing: .none)
			!= LanguageServers.serverKey(project: URL(fileURLWithPath: "/tmp/other"), languageId: "swift", choosing: .none))
	}

	/// A language nothing answers for still gets a key of its own, so the
	/// bookkeeping around it — what was looked for and not found — keeps working.
	@Test func aLanguageWithNoServerKeepsItsOwnName() {
		#expect(LanguageServers.serverKey(project: project, languageId: "cobol", choosing: .none)
			== "/tmp/project#cobol")
	}
}

/// Which root a server is filed under when the part being worked on is not the
/// whole checkout.
///
/// 0432, and the reason it is a test rather than a comment: `abydos-examples`
/// is a repository of ten projects, and a server started for one of them was
/// looked for under the repository — which answered nothing and said so only in
/// the log. The two roots are one property apart, so the only thing that keeps
/// them from drifting again is asserting that everything asks the same one.
struct LanguageServerScopeTests {
	private let checkout = URL(fileURLWithPath: "/tmp/examples")
	private let part = URL(fileURLWithPath: "/tmp/examples/devcontainers/python-language-server")

	/// The property everything scoped reads.
	@Test func theScopeIsTheSubprojectWhenThereIsOne() {
		let project = Project(root: checkout)
		#expect(project.scopeRoot == checkout)

		project.scope = part
		#expect(project.scopeRoot == part)

		// And back out of it, which is the gesture that must put every table
		// back where it was rather than leaving half of them scoped.
		project.scope = nil
		#expect(project.scopeRoot == checkout)
	}

	/// The fault itself: filed under one root, looked for under the other.
	@Test func aSubprojectsServerIsNotTheCheckoutsServer() {
		let project = Project(root: checkout)
		project.scope = part

		let scoped = LanguageServers.serverKey(project: project.scopeRoot, languageId: "python", choosing: .none)
		let whole = LanguageServers.serverKey(project: project.root, languageId: "python", choosing: .none)
		#expect(scoped != whole)
		#expect(scoped == "\(part.path)#pyright")

		// And it is not found by the scan that stops every server a project has,
		// which walks the keys by prefix: a subproject sits *inside* the
		// checkout's path, so "starts with the checkout" is true of the path and
		// must not be true of the key.
		#expect(!scoped.hasPrefix(project.root.path + "#"))
	}

	/// An unscoped project asks for exactly what it asked for before, which is
	/// what makes this change nothing for the projects that are one thing.
	@Test func aWholeProjectIsFiledWhereItAlwaysWas() {
		let project = Project(root: checkout)
		#expect(LanguageServers.serverKey(project: project.scopeRoot, languageId: "python", choosing: .none)
			== LanguageServers.serverKey(project: checkout, languageId: "python", choosing: .none))
	}
}

/// How long a language server lives: until the app does, and no sooner.
///
/// These were the reaping tests, and they asked the opposite question — which
/// window was still showing a project, and whether its servers could go. 0427
/// decided that none of that is asked any more: switching a project away and
/// closing its window both leave the servers running, because coming back has
/// to be instant and stopping one costs a re-index. What is left to hold is the
/// two things that decision rests on.
struct LanguageServerLifetimeTests {
	private let project = URL(fileURLWithPath: "/tmp/project")

	/// The torn-off window, which used to be the case that made "this window has
	/// closed" too blunt a reason to stop a server. It is settled by the key
	/// instead: a window torn off shares its project with the one it came from,
	/// two windows can be opened on one checkout, and both find the same server
	/// however the path is spelled. So closing either takes nothing away, and
	/// nothing has to ask what the other windows are showing.
	@Test func twoWindowsOnOneProjectHoldTheSameServer() {
		#expect(LanguageServers.serverKey(project: project, languageId: "swift", choosing: .none)
			== LanguageServers.serverKey(project: URL(fileURLWithPath: "/tmp/project/"), languageId: "swift", choosing: .none))
	}

	/// The count that must still be zero after the app has gone, asserted where
	/// it is decided: starting a server hands the process to `ToolProcesses`,
	/// which `applicationWillTerminate`, the `atexit` handler and the
	/// uncaught-exception handler each empty. That a process which will not go
	/// on its own is ended anyway is `ToolProcessTests`; that a server is in the
	/// set to begin with is this.
	@Test func aServerIsHandedToTheThingThatEndsItWithTheApp() throws {
		let client = LSPClient()
		defer { client.stop() }

		try client.start(
			executable: "/bin/sh",
			arguments: ["-c", "sleep 120"],
			workingDirectory: nil
		)
		let pid = try #require(client.processIdentifier)
		#expect(ToolProcesses.shared.isTracking(pid: pid))
	}
}

/// Stopping a server, which is what closing a project comes down to.
struct LSPShutdownTests {
	/// A server that answers nothing — no handshake, no `shutdown` reply — and
	/// will not end on its own. Which is the case that matters: a well-behaved
	/// server exits on `exit`, and the ones left running for a day did not.
	@Test func aServerThatWillNotGoPolitelyIsEndedAnyway() async throws {
		let client = LSPClient()
		defer { client.stop() }

		try client.start(
			executable: "/bin/sh",
			arguments: ["-c", "sleep 120"],
			workingDirectory: nil
		)
		let pid = try #require(client.processIdentifier)
		#expect(client.isRunning)

		await client.shutdown()

		// Asked of the operating system rather than of the client: what closing
		// a project has to achieve is a process that is gone.
		var alive = true
		for _ in 0..<200 where alive {
			if kill(pid, 0) != 0 { alive = false; break }
			try? await Task.sleep(nanoseconds: 50_000_000)
		}
		#expect(!alive, "the server was still running after its project closed")
		#expect(!client.isRunning)
	}

	/// The deadline underneath that, on its own.
	///
	/// It was a task group racing a sleep, and a group waits for every task in it
	/// — including the one parked on a reply that never came. So the timeout
	/// expired and the caller went on waiting anyway: the whole of `shutdown` took
	/// two minutes against a server that answers nothing, because two minutes was
	/// how long that server had been told to sleep for.
	@Test func aRequestAgainstASilentServerGivesUpOnTime() async throws {
		let client = LSPClient()
		defer { client.stop() }

		// Two minutes of silence, and one second of patience. The gap between
		// them is what is being measured: anything under half a minute means the
		// deadline ended the wait, and nothing else could have. A tighter bound
		// than that measures the machine's load rather than this client — the
		// first spelling of it wanted five seconds and failed at nine on a
		// machine running four builds.
		try client.start(
			executable: "/bin/sh",
			arguments: ["-c", "sleep 120"],
			workingDirectory: nil
		)

		let began = Date()
		await #expect(throws: LSPClient.ClientError.self) {
			_ = try await client.request("textDocument/hover", nil, timeout: 1)
		}
		#expect(Date().timeIntervalSince(began) < 30, "the deadline, not the server, ended the wait")
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
			"containerName": "AbydosKit",
		])
		#expect(symbol?.name == "WordMotion")
		#expect(symbol?.kind == .enum)
		#expect(symbol?.container == "AbydosKit")
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

/// A server that has stopped reading is the server's problem, not the app's.
struct LSPSendingTests {
	/// A pipe write blocks when nobody is draining the other end, and the other
	/// end here is somebody else's process. `/bin/sleep` never reads its
	/// standard input, so it stands in for the language server that is busy
	/// re-indexing, or wedged, or stopped: the 64 KB the kernel holds fills, and
	/// before this was queued the writing thread — the main one, on the
	/// `didChange` 0.4 s after a keypress — parked there until the server felt
	/// like reading.
	///
	/// **Not a benchmark, and the margin says so.** It is a hang detector: the
	/// same call took the whole thirty seconds before, and there is no arrangement
	/// of a busy machine that turns microseconds into five seconds.
	@MainActor @Test func aServerThatIsNotReadingDoesNotHoldUpTheSender() throws {
		let client = LSPClient()
		defer { client.stop() }
		try client.start(executable: "/bin/sleep", arguments: ["30"], workingDirectory: nil)

		// A megabyte: a large source file, and more than a pipe holds.
		let message: [String: Any] = [
			"jsonrpc": "2.0",
			"method": "textDocument/didChange",
			"params": ["contentChanges": [["text": String(repeating: "x", count: 1_000_000)]]],
		]
		let started = Date()
		client.sendForTesting(message)
		#expect(
			Date().timeIntervalSince(started) < 5,
			"the sender waited on a server that is not draining its standard input"
		)
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
		guard let server = LanguageServers.resolve(languageId: "swift", root: root, choosing: .none) else { return }

		let client = LSPClient()
		defer { client.stop() }
		try client.start(
			executable: server.executable,
			arguments: server.definition.arguments,
			workingDirectory: root
		)

		// Sent immediately, before the handshake is even asked for — which is
		// exactly what the editor does when a file is already open at launch.
		let file = root.appendingPathComponent("Sources/AbydosKit/Text/WordMotion.swift")
		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: file.absoluteString, languageId: "swift", version: 1, text: text)

		_ = try await client.initialize(rootURL: root)

		// Waited for rather than slept through. Three seconds was enough for
		// sourcekit-lsp to take the document in on a quiet machine and not on a
		// busy one, and the difference arrived as "the server does not know this
		// file" — which is the sentence this test would print if the code under
		// it were genuinely broken. Asking until it answers says the same thing
		// where it is true, is faster where it was already true, and takes the
		// machine out of it. `Patience.seconds` is the hang detector; see 0435.
		var symbols: [LSPSymbol] = []
		let deadline = Date().addingTimeInterval(Patience.seconds)
		while Date() < deadline {
			symbols = (try? await client.documentSymbols(uri: file.absoluteString)) ?? []
			if !symbols.isEmpty { break }
			try? await Task.sleep(nanoseconds: 200_000_000)
		}

		// The server knows the document, so it can answer about it.
		#expect(!symbols.isEmpty, "no symbols within \(Patience.seconds)s — \(MachineLoad.said)")
		#expect(symbols.contains { $0.name == "WordMotion" })

		await client.shutdown()
	}
}

/// What deciding which servers a project wants actually costs in directory
/// listings.
///
/// Counted rather than timed, because the machine this was written on is never
/// quiet enough for a stopwatch to mean anything — and because the claim being
/// made is about the *shape* of the work, which a count states exactly and a
/// duration only suggests.
struct LanguageServerScanCostTests {
	private func makeTree(_ paths: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("scan-\(UUID().uuidString)")
		for path in paths {
			let url = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try "x".write(to: url, atomically: true, encoding: .utf8)
		}
		return root
	}

	/// A project with no manifest anywhere is the worst case: every definition
	/// walks the whole of it to depth 2 before giving up, and `warmUp` and
	/// `serverStatus` each do that once per definition.
	///
	/// Counted from the index rather than from a process-wide total, which
	/// another suite asking about a project at the same moment would add to.
	@Test func onePassOverTheProjectRatherThanOnePerDefinition() throws {
		let root = try makeTree([
			"README.md", "docs/one.md", "docs/two.md",
			"src/a/one.txt", "src/b/two.txt", "tools/three.txt",
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let marked = LanguageServers.known.filter { !$0.rootMarkers.isEmpty }

		// An index each, which is what asking `suits` about them one at a time
		// comes to.
		var separately = 0
		for definition in marked {
			let index = LanguageServers.DirectoryIndex()
			_ = LanguageServers.markerDirectory(for: definition, in: root, maxDepth: 2, index: index)
			separately += index.listingCount
		}

		// One index between them, which is what `suitedDefinitions` does.
		let shared = LanguageServers.DirectoryIndex()
		for definition in marked {
			_ = LanguageServers.markerDirectory(for: definition, in: root, maxDepth: 2, index: shared)
		}

		#expect(shared.listingCount * marked.count == separately)
		print("LSPSCAN \(marked.count) definitions: \(separately) listings one at a time, "
			+ "\(shared.listingCount) together")
	}

	/// And the same answers, which is the part a count says nothing about.
	@Test func togetherAndSeparatelyAgree() throws {
		let root = try makeTree(["app/go.mod", "web/package.json", "notes.txt"])
		defer { try? FileManager.default.removeItem(at: root) }

		let separately = LanguageServers.known
			.filter { !$0.rootMarkers.isEmpty && LanguageServers.suits($0, root: root) }
			.map(\.command)
		let together = LanguageServers.suitedDefinitions(in: root, choosing: .none).map(\.command)
		#expect(together == separately)
		#expect(together.contains("gopls"))
		#expect(together.contains("typescript-language-server"))
		#expect(!together.contains("rust-analyzer"))
	}

	/// A marker that is a hidden file is still a marker. The walk skips hidden
	/// *directories*, and the listing the markers are read from has to keep
	/// hidden entries even so — `.classpath` is one of jdtls's, and the obvious
	/// way to write this index would have lost it.
	@Test func aHiddenMarkerIsStillFound() throws {
		let root = try makeTree([".classpath", "src/Main.java"])
		defer { try? FileManager.default.removeItem(at: root) }
		let java = try #require(LanguageServers.definition(forLanguage: "java", choosing: .none))
		#expect(LanguageServers.suits(java, root: root))
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
		let go = try #require(LanguageServers.definition(forLanguage: "go", choosing: .none))
		#expect(LanguageServers.markerDirectory(for: go, in: root) == root)
	}

	/// A repository commonly keeps its manifest a level down — `app/go.mod` —
	/// and a server rooted at the directory above it answers nothing at all.
	@Test func findsAManifestBelowTheRoot() throws {
		let root = try makeTree(["README.md", "app/go.mod", "app/main.go"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go", choosing: .none))

		let found = LanguageServers.markerDirectory(for: go, in: root)
		#expect(found?.lastPathComponent == "app")
		#expect(LanguageServers.suits(go, root: root))
	}

	/// The root moves and the key does not, which is what makes one lookup right
	/// for everybody.
	///
	/// 0467 was reported against exactly this shape — `mqtt-lamarzocco` with its
	/// `go.mod` in `app/`, so gopls is *started* at a directory that is not the
	/// project — and the first suspicion was that the footer went blank because
	/// it rebuilt the key from the group's project while the document had been
	/// filed under the root the server was started at. It had not: the key
	/// carries the project it was asked about and never the manifest directory,
	/// so the chip, the strip, and every question a file asks all name the same
	/// entry. Asserted here so the two cannot drift apart, since the day they do
	/// the symptom is silence.
	@Test func aServerRootedBelowTheProjectIsStillFiledUnderTheProject() throws {
		let root = try makeTree(["README.md", "app/go.mod", "app/main.go"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go", choosing: .none))

		let started = LanguageServers.markerDirectory(for: go, in: root)
		#expect(started?.lastPathComponent == "app")

		let key = LanguageServers.serverKey(project: root, languageId: "go", choosing: .none)
		#expect(key == "\(root.standardizedFileURL.path)#gopls")
		#expect(key != LanguageServers.serverKey(
			project: try #require(started), languageId: "go", choosing: .none
		))
	}

	@Test func findsOneTwoLevelsDown() throws {
		let root = try makeTree(["services/api/go.mod"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go", choosing: .none))
		#expect(LanguageServers.markerDirectory(for: go, in: root)?.lastPathComponent == "api")
	}

	/// Vendored copies are not the project.
	@Test func ignoresVendoredManifests() throws {
		let root = try makeTree(["vendor/other/go.mod", "node_modules/thing/package.json"])
		defer { try? FileManager.default.removeItem(at: root) }

		let go = try #require(LanguageServers.definition(forLanguage: "go", choosing: .none))
		#expect(LanguageServers.markerDirectory(for: go, in: root) == nil)

		let ts = try #require(LanguageServers.definition(forLanguage: "typescript", choosing: .none))
		#expect(LanguageServers.markerDirectory(for: ts, in: root) == nil)
	}

	@Test func saysNoWhenThereIsNoManifestAnywhere() throws {
		let root = try makeTree(["notes.txt", "docs/readme.md"])
		defer { try? FileManager.default.removeItem(at: root) }
		let go = try #require(LanguageServers.definition(forLanguage: "go", choosing: .none))
		#expect(LanguageServers.markerDirectory(for: go, in: root) == nil)
		#expect(!LanguageServers.suits(go, root: root))
	}

	/// The resolved root is what the server is started in, and it is the
	/// manifest's directory rather than the project's.
	@Test func resolvesToTheManifestDirectory() throws {
		let root = try makeTree(["app/go.mod"])
		defer { try? FileManager.default.removeItem(at: root) }
		guard let resolved = LanguageServers.resolve(languageId: "go", root: root, choosing: .none) else { return }
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
		#expect(LanguageServers.suggestion(forLanguage: "markdown", root: root, choosing: .none) == nil)
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

/// Which shell a run console runs a command line in.
///
/// The failure this exists for: `make run` printed `pnpm: command not found`
/// for a `pnpm` that `which` finds one tab away. The console used `sh -lc`,
/// which reads `/etc/profile` and `~/.profile` — and fnm, nvm, mise, asdf and
/// pnpm all write to `~/.zshrc`, which only an interactive shell reads. fnm
/// makes it worse by putting its binaries in a directory belonging to one shell
/// session, so a PATH inherited at launch goes stale when that terminal closes:
/// the same command worked in the morning and failed in the afternoon.
struct UserShellTests {
	@Test func runsACommandInTheUsersOwnShell() {
		let zsh = UserShell.invocation(for: "make run", shell: "/bin/zsh")
		#expect(zsh.executable == "/bin/zsh")
		// Login *and* interactive: the file the tools write to is only read by
		// an interactive shell, and a run console is a real terminal.
		#expect(zsh.arguments == ["-lic", "make run"])

		let fish = UserShell.invocation(for: "make run", shell: "/opt/homebrew/bin/fish")
		#expect(fish.arguments == ["-lic", "make run"])
	}

	/// `sh` has no interactive-only startup file, so `-i` would buy nothing and
	/// turn on job-control noise.
	@Test func plainShellsAreNotAskedToBeInteractive() {
		#expect(UserShell.invocation(for: "ls", shell: "/bin/sh").arguments == ["-lc", "ls"])
		#expect(UserShell.invocation(for: "ls", shell: "/bin/dash").arguments == ["-lc", "ls"])
	}

	@Test func fallsBackToASensibleShell() {
		#expect(!UserShell.path.isEmpty)
		#expect(UserShell.path.hasPrefix("/"))
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

/// Where the Swift indexer builds.
///
/// It builds the package to index it, and by default into the package's own
/// `.build` — the directory a terminal build uses. Two builds in one directory
/// take turns holding its lock and invalidate each other's work; where the
/// toolchains differ they rebuild the world in turn. On the machine this was
/// written on, a nine-second incremental build took ten minutes while the
/// indexer had the directory.
struct IndexScratchPathTests {
	private let project = URL(fileURLWithPath: "/Users/me/dev/abydos")

	@Test func theIndexerIsToldToBuildSomewhereElse() throws {
		let definition = LanguageServers.definition(forLanguage: "swift", choosing: .none)
		#expect(definition?.setup == .swift)

		let arguments = LanguageServers.arguments(for: try #require(definition), root: project)
		#expect(arguments.contains("--scratch-path"))
		let path = arguments.last ?? ""
		#expect(!path.hasPrefix(project.path), "the indexer must not build inside the project")
	}

	/// Derived data lives with the caches, not in the checkout: it can be
	/// thrown away at any time, and a directory inside the project is one more
	/// thing to ignore and one more thing to search by accident.
	@Test func itLivesWithTheCaches() {
		let path = LanguageServers.indexScratchPath(for: project).path
		#expect(path.contains("Caches") || path.contains("/tmp") || path.contains("/var/folders"))
		#expect(path.contains("abydos/index"))
	}

	/// Two projects of the same name are two directories, or one would index
	/// the other's sources.
	@Test func twoProjectsOfTheSameNameAreKeptApart() {
		let one = LanguageServers.indexScratchPath(for: URL(fileURLWithPath: "/Users/me/a/service"))
		let other = LanguageServers.indexScratchPath(for: URL(fileURLWithPath: "/Users/me/b/service"))
		#expect(one != other)
		#expect(one.lastPathComponent.hasPrefix("service-"))
	}

	/// The same project is the same directory every time, or every launch
	/// indexes from nothing.
	@Test func theSameProjectKeepsItsIndex() {
		#expect(
			LanguageServers.indexScratchPath(for: project)
				== LanguageServers.indexScratchPath(for: project)
		)
	}

	/// And the indexer is *started* there too, which is 0518.
	///
	/// Telling it where to build is not enough: the builds it starts write some
	/// of their outputs to paths with no directory in them, and a relative path
	/// is written where the process stands. Started in the project, that is 1424
	/// files — four per source file of the package being prepared — loose in
	/// somebody's checkout, in their `git status` and in every search.
	@Test func theIndexerIsStartedWhereItBuilds() throws {
		let definition = try #require(LanguageServers.definition(forLanguage: "swift", choosing: .none))
		let scratch = LanguageServers.indexScratchPath(for: project)
		try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: scratch) }

		let directory = LanguageServers.workingDirectory(for: definition, root: project)
		#expect(directory == scratch)
		#expect(
			!directory.path.hasPrefix(project.path),
			"a relative write by the indexer must not land in the project"
		)
	}

	/// A cache that could not be made leaves the project as the answer. A
	/// `Process` whose working directory does not exist refuses to run, and a
	/// server that will not start is worse than one that litters.
	@Test func aMissingCacheDirectoryLeavesTheProject() throws {
		let definition = try #require(LanguageServers.definition(forLanguage: "swift", choosing: .none))
		let absent = URL(fileURLWithPath: "/Users/me/dev/no-such-project-0518")
		#expect(LanguageServers.workingDirectory(for: definition, root: absent) == absent)
	}

	/// Everything else is started in its project, which is what has always been
	/// right for it: nothing else here builds the package to answer a question.
	@Test func everyOtherServerIsStartedInItsProject() throws {
		for language in ["go", "python", "java"] {
			guard let definition = LanguageServers.definition(forLanguage: language, choosing: .none)
			else { continue }
			#expect(
				LanguageServers.workingDirectory(for: definition, root: project) == project,
				"\(definition.command) should start in the project"
			)
		}
	}
}

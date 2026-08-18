import Foundation
import Testing
@testable import AbydosKit

/// Against a real language server, when the machine has one.
///
/// Skipped rather than failed where it is not installed: whether somebody has
/// sourcekit-lsp is a fact about their machine, not about this code. When it is
/// there, this is the only test that proves the client actually speaks the
/// protocol rather than merely parsing what it expects to be sent.
struct LSPIntegrationTests {
	private var swiftServer: (definition: LanguageServerDefinition, executable: String, root: URL)? {
		LanguageServers.resolve(languageId: "swift", root: packageRoot, choosing: .none)
	}

	/// This package, which is a Swift project a server can make sense of.
	private var packageRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // AbydosKitTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // package root
	}

	@Test func shakesHandsAndAnswersQuestions() async throws {
		guard let server = swiftServer else { return }

		let client = LSPClient()
		defer { client.stop() }

		try client.start(
			executable: server.executable,
			arguments: server.definition.arguments,
			workingDirectory: packageRoot
		)

		let capabilities = try await client.initialize(rootURL: packageRoot)
		#expect(!capabilities.isEmpty)
		// Anything worth calling a language server offers these two.
		#expect(capabilities["hoverProvider"] != nil)
		#expect(capabilities["definitionProvider"] != nil)

		// A small file of its own, so the answers do not depend on the state of
		// the repository this is running in.
		let file = packageRoot.appendingPathComponent(".lsp-probe.swift")
		let source = """
		struct Probe {
		    let value: Int
		    func doubled() -> Int { value * 2 }
		}

		let probe = Probe(value: 21)
		let result = probe.doubled()
		"""
		try source.write(to: file, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: file) }

		client.didOpen(
			uri: file.absoluteString, languageId: "swift", version: 1, text: source
		)

		// `doubled` on the last line, which is defined on line 2.
		let hover = try? await client.hover(
			uri: file.absoluteString,
			position: LSPPosition(line: 6, character: 20)
		)
		if let hover { #expect(hover.contents.contains("doubled")) }

		client.didClose(uri: file.absoluteString)
		await client.shutdown()
	}

	/// Diagnostics, which is the whole path: notification in, parsed, delivered.
	///
	/// A syntax error rather than a type error on purpose. Semantic diagnostics
	/// need build settings the server works out in the background, and whether
	/// it has them yet is a race; a file that does not parse is wrong no matter
	/// what it would have been compiled with.
	@Test func receivesDiagnosticsForAFileThatDoesNotParse() async throws {
		guard let server = swiftServer else { return }

		let client = LSPClient()
		defer { client.stop() }

		let received = Collected()
		client.onDiagnostics = { _, diagnostics in received.append(diagnostics) }

		try client.start(
			executable: server.executable,
			arguments: server.definition.arguments,
			workingDirectory: packageRoot
		)
		_ = try await client.initialize(rootURL: packageRoot)

		let file = packageRoot.appendingPathComponent("Sources/AbydosKit/Project/ScratchFiles.swift")
		let source = (try String(contentsOf: file, encoding: .utf8)) + "\nfunc broken( {\n"
		client.didOpen(uri: file.absoluteString, languageId: "swift", version: 1, text: source)

		for _ in 0..<20 {
			try? await Task.sleep(nanoseconds: 500_000_000)
			if !received.all.isEmpty { break }
		}

		let diagnostics = received.all
		#expect(!diagnostics.isEmpty)
		#expect(diagnostics.contains { $0.severity == .error })
		// On the line that was appended, not on the file's own code.
		let lines = source.components(separatedBy: "\n").count
		#expect(diagnostics.contains { $0.range.start.line >= lines - 3 })

		client.didClose(uri: file.absoluteString)
		await client.shutdown()
	}

	private final class Collected: @unchecked Sendable {
		private let lock = NSLock()
		private var items: [LSPDiagnostic] = []
		var all: [LSPDiagnostic] { lock.lock(); defer { lock.unlock() }; return items }
		func append(_ more: [LSPDiagnostic]) {
			lock.lock()
			items += more
			lock.unlock()
		}
	}

	/// Signature help, which is where "what does this parameter take" comes from
	/// for a language whose server has it.
	///
	/// **Only against the stdlib, and deliberately.** A signature from this
	/// package's own code would need the whole package indexed first — measured
	/// against a Cadova model, that is an index build of 651 files and about two
	/// minutes before the first useful answer — and a test that waits two
	/// minutes is a test somebody turns off. `String.hasPrefix` is answered from
	/// the fallback arguments, straight away.
	@Test func saysWhichParameterIsBeingFilledIn() async throws {
		guard let server = swiftServer else { return }

		let client = LSPClient()
		defer { client.stop() }

		try client.start(
			executable: server.executable,
			arguments: server.definition.arguments,
			workingDirectory: packageRoot
		)
		_ = try await client.initialize(rootURL: packageRoot)

		// The capability decides whether the request is ever sent: openscad-lsp
		// advertises none and answers nothing at all, so a client that asks
		// anyway waits for its timeout.
		#expect(client.offersSignatureHelp)
		#expect(client.signatureHelpTriggerCharacters.contains("("))

		let file = packageRoot.appendingPathComponent(".lsp-signature-probe.swift")
		let source = """
		func probe(_ text: String) -> Bool {
		    text.hasPrefix()
		}
		"""
		try source.write(to: file, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: file) }

		client.didOpen(uri: file.absoluteString, languageId: "swift", version: 1, text: source)

		// **Between the brackets, and the difference is one character.** Asked
		// at 20 — just past the `)` — this same server answers null; asked at
		// 19, it answers. Which is also where the caret is when somebody has
		// just typed the `(` that woke the request, so the editor asks at the
		// right place by construction rather than by luck.
		let help = try await client.signatureHelp(
			uri: file.absoluteString,
			position: LSPPosition(line: 1, character: 19)
		)

		let active = try #require(help?.active)
		#expect(active.signature.label.contains("hasPrefix"))
		let range = try #require(active.parameter?.range)
		let label = Array(active.signature.label.utf16)
		#expect(range.upperBound <= label.count)
		#expect(String(decoding: label[range], as: UTF16.self) == "_ prefix: String")

		client.didClose(uri: file.absoluteString)
		await client.shutdown()
	}

	/// A request made to a server that has gone away fails rather than hanging.
	@Test func failsWhenTheServerDies() async throws {
		guard let server = swiftServer else { return }

		let client = LSPClient()
		try client.start(
			executable: server.executable,
			arguments: server.definition.arguments,
			workingDirectory: packageRoot
		)
		client.stop()

		await #expect(throws: LSPClient.ClientError.self) {
			try await client.request("textDocument/hover", nil, timeout: 2)
		}
	}
}

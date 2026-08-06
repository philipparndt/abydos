import Foundation
import Testing
@testable import AbydosKit

/// Against the real OpenSCAD language server, when the machine has one.
///
/// Skipped where `openscad-lsp` is not installed, the way the Swift and Java
/// integration tests are. When it is there, this is what proves the entry in
/// the table is right — and the part most likely to be wrong is not the
/// protocol but the command line: this server listens on a TCP port unless
/// given `--stdio`, so a definition missing that flag produces a server that
/// starts, waits on 127.0.0.1:3245 for a client that never comes, and an
/// editor that waits for a handshake that never arrives. Nothing about that
/// failure looks like a missing flag.
struct OpenSCADLiveTests {
	@Test func openscadLSPAnswersOverStandardIO() async throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		let file = root.appendingPathComponent("bracket.scad")
		try JavaTestDirectory.write("""
		thickness = 4;
		width     = 40;

		module plate(w, h, t) {
			cube([w, h, t]);
		}

		function area(w, h) = w * h;

		plate(width, thickness, 2);
		""", to: file)

		guard let server = LanguageServers.resolve(languageId: "openscad", root: root) else { return }
		// No manifest exists for OpenSCAD, so the server is rooted at the
		// project itself rather than at a directory holding a marker.
		#expect(FilePath.canonical(server.root) == FilePath.canonical(root))
		#expect(server.definition.arguments.contains("--stdio"))

		let client = LSPClient()
		defer { client.stop() }

		try client.start(
			executable: server.executable,
			arguments: LanguageServers.arguments(for: server.definition, root: root),
			workingDirectory: root,
			environment: LanguageServers.serverEnvironment
		)

		let capabilities = try await client.initialize(
			rootURL: root,
			options: LanguageServers.initializationOptions(for: server.definition, root: root),
			timeout: 30
		)
		#expect(!capabilities.isEmpty)
		#expect(capabilities["hoverProvider"] != nil)
		#expect(capabilities["definitionProvider"] != nil)
		#expect(capabilities["documentSymbolProvider"] != nil)

		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: file.absoluteString, languageId: "openscad", version: 1, text: text)

		// The outline: what ⇧⌘O will show for a model. OpenSCAD's grammar ships
		// no tags query, so before this server there was nothing to list.
		var symbols: [LSPSymbol] = []
		for _ in 0..<10 {
			symbols = (try? await client.documentSymbols(uri: file.absoluteString)) ?? []
			if !symbols.isEmpty { break }
			try? await Task.sleep(nanoseconds: 500_000_000)
		}
		let names = symbols.map(\.name)
		#expect(names.contains { $0.contains("plate") }, "no module in the outline: \(names)")
		#expect(names.contains { $0.contains("area") }, "no function in the outline: \(names)")

		// And that it knows where a module is declared, which is what
		// go-to-declaration asks. Line 9 is the call to `plate`.
		let definitions = try await client.definition(
			uri: file.absoluteString,
			position: LSPPosition(line: 9, character: 0)
		)
		#expect(!definitions.isEmpty)
	}
}

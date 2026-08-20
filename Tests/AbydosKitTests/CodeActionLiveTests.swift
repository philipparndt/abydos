import Foundation
import Testing
@testable import AbydosKit

/// What real servers actually offer, and how often.
///
/// **This is a measurement before a decision.** Where the offer lives — on the
/// diagnostic, in the gutter, or only on a keystroke — turns on how much of the
/// time there is anything to offer, and nobody had measured it. A mark on every
/// line is the outcome to avoid, and a mark on every line is exactly what a
/// gutter indicator becomes if a server answers something for most positions.
///
/// It also proves the request shape: a `codeAction` request without
/// `codeActionLiteralSupport` gets bare commands back, and one without the
/// diagnostics in its context gets refactorings but no fixes — both of which
/// look like "this server does not offer much" rather than like a bug here.
///
/// Skipped where the server is not installed. A skipped live test is not a pass.
@Suite(.serialized) struct CodeActionLiveTests {
	/// What one file's worth of asking came to.
	private struct Tally {
		var lines = 0
		var offering = 0
		/// Lines offering something that is *about that line* — everything but
		/// `source.*`, which is about the file and comes back wherever the
		/// caret is. This is the number the decision turns on.
		var offeringAtTheCaret = 0
		var kinds: [String: Int] = [:]
		var needingResolve = 0
		var commands = 0

		var share: Int { lines == 0 ? 0 : offering * 100 / lines }
		var shareAtTheCaret: Int { lines == 0 ? 0 : offeringAtTheCaret * 100 / lines }
	}

	/// Asks about every line of a file, at the first character that is not
	/// whitespace — an ordinary caret position, which is where somebody's caret
	/// is when they are not doing anything in particular.
	private func measure(
		_ client: LSPClient, uri: String, text: String, diagnostics: [LSPDiagnostic]
	) async -> Tally {
		var tally = Tally()
		for (number, line) in text.components(separatedBy: "\n").enumerated() {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty else { continue }
			let column = line.count - line.drop(while: { $0 == " " || $0 == "\t" }).count
			let position = LSPPosition(line: number, character: column)
			let range = LSPRange(start: position, end: position)
			tally.lines += 1

			// The diagnostics under this line, which is what makes a fix a fix.
			let under = diagnostics.filter { $0.range.start.line <= number && $0.range.end.line >= number }
			let actions = (try? await client.codeActions(
				uri: uri, range: range, diagnostics: under, timeout: 20
			)) ?? []
			guard !actions.isEmpty else { continue }
			tally.offering += 1
			if actions.contains(where: { !$0.isSourceAction }) { tally.offeringAtTheCaret += 1 }
			for action in actions {
				tally.kinds[action.kind ?? "(no kind)", default: 0] += 1
				if action.needsResolving { tally.needingResolve += 1 }
				if action.command != nil { tally.commands += 1 }
			}
		}
		return tally
	}

	private func say(_ server: String, _ tally: Tally) {
		let kinds = tally.kinds.sorted { $0.key < $1.key }
			.map { "\($0.key)×\($0.value)" }
			.joined(separator: ", ")
		print("  CODE ACTIONS \(server): \(tally.offering) of \(tally.lines) lines"
			+ " (\(tally.share)%) offer something, and \(tally.offeringAtTheCaret)"
			+ " (\(tally.shareAtTheCaret)%) offer something about the line itself;"
			+ " \(tally.needingResolve) need resolving, \(tally.commands) are commands")
		print("  CODE ACTIONS \(server) kinds: \(kinds.isEmpty ? "none" : kinds)")
		print("  " + MachineLoad.said)
	}

	/// Diagnostics, waited for: a fix is a fix *for* one, and asking before the
	/// server has published any measures the wrong thing.
	private final class Published: @unchecked Sendable {
		private let lock = NSLock()
		private var byURI: [String: [LSPDiagnostic]] = [:]

		func record(_ uri: String, _ diagnostics: [LSPDiagnostic]) {
			lock.lock(); byURI[uri] = diagnostics; lock.unlock()
		}

		func of(_ uri: String) -> [LSPDiagnostic] {
			lock.lock(); defer { lock.unlock() }
			return byURI[uri] ?? []
		}
	}

	@Test func goplsOffersSomethingAboutEveryLineThereIs() async throws {
		guard let definition = LanguageServers.known.first(where: { $0.name == "gopls" }),
		      let executable = LanguageServers.executable(for: definition)
		else { return }

		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)

		try JavaTestDirectory.write("module example.com/actions\n\ngo 1.24\n",
		                            to: project.appendingPathComponent("go.mod"))
		// A file with something wrong in it — an unused import, which every Go
		// server offers to remove — and ordinary lines around it.
		let source = """
		package actions

		import (
			"fmt"
			"os"
		)

		func Greeting(name string) string {
			parts := []string{"hello", name}
			return fmt.Sprint(parts)
		}

		func Count(items []string) int {
			total := 0
			for range items {
				total = total + 1
			}
			return total
		}
		"""
		let file = project.appendingPathComponent("actions.go")
		try JavaTestDirectory.write(source, to: file)

		let client = LSPClient()
		defer { client.stop() }
		client.callbackQueue = DispatchQueue(label: "code-action-live")
		let published = Published()
		client.onDiagnostics = { published.record($0, $1) }

		try client.start(
			executable: executable,
			arguments: LanguageServers.arguments(for: definition, root: project),
			workingDirectory: project,
			environment: LanguageServers.serverEnvironment
		)
		_ = try await client.initialize(rootURL: project, options: nil, timeout: 60)
		#expect(client.offersCodeActions)
		client.didOpen(uri: file.absoluteString, languageId: "go", version: 1, text: source)

		await waitUntil("gopls published its diagnostics", within: 30) {
			!published.of(file.absoluteString).isEmpty
		}

		let tally = await measure(
			client, uri: file.absoluteString, text: source,
			diagnostics: published.of(file.absoluteString)
		)
		say("gopls", tally)

		// **The finding, asserted so that it cannot quietly stop being true.**
		// gopls answers *something* for every line in the file, because
		// `source.*` actions — organise imports, add a test, show the assembly —
		// are about the file and come back wherever the caret is. A gutter mark
		// driven off "are there actions here" would therefore be on every line,
		// which is the outcome this measurement existed to avoid.
		#expect(tally.offering == tally.lines)
		// **And filtering `source.*` out does not save it.** gopls returns
		// `gopls.doc.features` — a kind of its own invention, outside the
		// protocol's hierarchy — on every line as well, so a client that hid
		// the file-wide kinds it knows about would still light up every row.
		// Whatever says "there is something here" cannot be driven by whether
		// the list is empty.
		#expect(tally.offeringAtTheCaret == tally.lines)
		#expect(tally.kinds.keys.contains("gopls.doc.features"))
	}

	/// jdtls, which is the one the item is really about: its list is long, its
	/// actions resolve lazily, and several of them are commands.
	@Test func jdtlsOffersFixesForWhatItReportedAndRefactoringsBesides() async throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)

		try JavaTestDirectory.write("""
		<?xml version="1.0" encoding="UTF-8"?>
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<modelVersion>4.0.0</modelVersion>
			<groupId>com.example</groupId>
			<artifactId>actions</artifactId>
			<version>1.0.0</version>
			<properties>
				<maven.compiler.release>21</maven.compiler.release>
			</properties>
		</project>
		""", to: project.appendingPathComponent("pom.xml"))

		// `List` with no import: the quick fix this whole item is named after.
		let source = """
		package com.example.actions;

		public class Shelf {
			private final List<String> titles = new ArrayList<>();

			public void add(String title) {
				titles.add(title);
			}

			public int size() {
				return titles.size();
			}
		}
		"""
		let file = project.appendingPathComponent("src/main/java/com/example/actions/Shelf.java")
		try JavaTestDirectory.write(source, to: file)

		guard let server = LanguageServers.resolve(languageId: "java", root: project, choosing: .none)
		else { return }

		let client = LSPClient()
		defer { client.stop() }
		client.callbackQueue = DispatchQueue(label: "code-action-live")
		let published = Published()
		client.onDiagnostics = { published.record($0, $1) }

		LanguageServers.prepare(server.definition, root: project)
		try client.start(
			executable: server.executable,
			arguments: LanguageServers.arguments(for: server.definition, root: project),
			workingDirectory: project,
			environment: LanguageServers.serverEnvironment
		)
		_ = try await client.initialize(
			rootURL: project,
			options: LanguageServers.initializationOptions(for: server.definition, root: project),
			timeout: 180
		)
		#expect(client.offersCodeActions)
		client.didOpen(uri: file.absoluteString, languageId: "java", version: 1, text: source)

		// The import takes as long as it takes; the diagnostic about `List` is
		// what says the project has been compiled.
		await waitUntil("jdtls published its diagnostics", within: 180) {
			!published.of(file.absoluteString).isEmpty
		}

		let diagnostics = published.of(file.absoluteString)
		let tally = await measure(client, uri: file.absoluteString, text: source, diagnostics: diagnostics)
		say("jdtls", tally)
		print("  CODE ACTIONS jdtls resolves: \(client.resolvesCodeActions)")

		// The same finding, from the server this item is really about.
		#expect(tally.offering == tally.lines)
		// The fix this item is named after, by name.
		let line = diagnostics.first { $0.message.contains("List") }?.range.start.line ?? 3
		let position = LSPPosition(line: line, character: 20)
		let actions = try await client.codeActions(
			uri: file.absoluteString,
			range: LSPRange(start: position, end: position),
			diagnostics: diagnostics.filter { $0.range.start.line == line },
			timeout: 30
		)
		print("  CODE ACTIONS jdtls at the missing import: "
			+ actions.prefix(6).map(\.title).joined(separator: " | "))
		// jdtls words it its own way, and its own words are what the menu shows.
		#expect(actions.contains { $0.title.contains("Import 'List' (java.util)") })
	}
}

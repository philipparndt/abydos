import Foundation
import Testing
@testable import IdeaiKit

/// Adding things to .gitignore.
struct GitIgnoreTests {
	/// The exact file first: it is what was clicked, and the only suggestion
	/// that cannot cover more than was meant.
	@Test func offersTheExactFileFirst() {
		let suggestions = GitIgnore.suggestions(for: "app/__debug_bin374976163", isDirectory: false)
		#expect(suggestions.first?.pattern == "/app/__debug_bin374976163")
	}

	@Test func offersTheNameAnywhereAndTheExtension() {
		let patterns = GitIgnore.suggestions(for: "build/output.log", isDirectory: false).map(\.pattern)
		#expect(patterns.contains("output.log"))
		#expect(patterns.contains("*.log"))
		#expect(patterns.contains("/build/"))
	}

	/// Build artefacts are named for what made them, with a number that differs
	/// every time — ignoring only this one would be useless tomorrow.
	@Test func offersAPrefixForGeneratedNames() {
		let patterns = GitIgnore.suggestions(for: "__debug_bin374976163", isDirectory: false).map(\.pattern)
		#expect(patterns.contains("__debug_bin*"))
	}

	@Test func doesNotInventAPrefixForOrdinaryNames() {
		#expect(GitIgnore.generatedStem(of: "main.go") == nil)
		#expect(GitIgnore.generatedStem(of: "12345") == nil)
		#expect(GitIgnore.generatedStem(of: "__debug_bin42") == "__debug_bin")
	}

	@Test func offersDirectoryPatternsForADirectory() {
		let patterns = GitIgnore.suggestions(for: "app/target", isDirectory: true).map(\.pattern)
		#expect(patterns == ["/app/target/", "target/"])
	}

	/// A file at the root has no separate "anywhere" form worth offering.
	@Test func doesNotRepeatItselfForARootFile() {
		let patterns = GitIgnore.suggestions(for: "notes.txt", isDirectory: false).map(\.pattern)
		#expect(patterns.filter { $0 == "notes.txt" }.count <= 1)
		#expect(patterns.first == "/notes.txt")
	}

	// MARK: - Writing

	@Test func appendsWithABlankLineBefore() {
		let updated = GitIgnore.adding("*.log", to: "build/\n")
		#expect(updated == "build/\n\n*.log\n")
	}

	@Test func writesTheFirstLineIntoAnEmptyFile() {
		#expect(GitIgnore.adding("*.log", to: "") == "*.log\n")
	}

	/// Writing a duplicate is the actual mistake to avoid.
	@Test func refusesToAddWhatIsAlreadyThere() {
		let existing = "build/\n*.log\n"
		#expect(GitIgnore.adding("*.log", to: existing) == existing)
		#expect(GitIgnore.adding("  *.log  ", to: existing) == existing)
	}

	@Test func recognisesAPatternWhateverTheSpacing() {
		#expect(GitIgnore.contains("*.log", in: "  *.log  \n"))
		#expect(!GitIgnore.contains("*.log", in: "*.logs\n"))
	}

	@Test func ignoresAnEmptyPattern() {
		#expect(GitIgnore.adding("   ", to: "build/\n") == "build/\n")
	}

	@Test func writesTheFileIntoARepository() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ignore-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		try GitIgnore.add("__debug_bin*", toRepositoryAt: root)
		let contents = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
		#expect(contents == "__debug_bin*\n")

		// A second pattern joins it; the same one again changes nothing.
		try GitIgnore.add("*.log", toRepositoryAt: root)
		try GitIgnore.add("*.log", toRepositoryAt: root)
		let updated = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
		#expect(updated == "__debug_bin*\n\n*.log\n")
	}
}

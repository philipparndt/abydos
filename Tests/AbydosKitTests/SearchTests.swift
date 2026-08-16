import Testing
import Foundation
@testable import AbydosKit

struct TextSearchTests {
	private let sample = """
	let alpha = 1
	let Alpha = 2
	// alphabet soup
	func beta() {}
	"""

	@Test func findsLiteralMatchesCaseInsensitivelyByDefault() {
		let matches = TextSearch.matches(in: sample, query: "alpha", options: SearchOptions())
		// alpha, Alpha, alphabet
		#expect(matches.count == 3)
	}

	@Test func honoursCaseSensitivity() {
		let matches = TextSearch.matches(in: sample, query: "Alpha", options: SearchOptions(caseSensitive: true))
		#expect(matches.count == 1)
		#expect(matches.first?.line == 1)
	}

	@Test func wholeWordExcludesSubstrings() {
		let matches = TextSearch.matches(in: sample, query: "alpha", options: SearchOptions(wholeWord: true))
		// "alphabet" is no longer a hit.
		#expect(matches.count == 2)
	}

	@Test func reportsLineAndText() {
		let matches = TextSearch.matches(in: sample, query: "beta", options: SearchOptions())
		#expect(matches.first?.line == 3)
		#expect(matches.first?.lineText == "func beta() {}")
	}

	@Test func rangesAreUTF16AndSelectTheMatch() {
		let text = "héllo world"
		let matches = TextSearch.matches(in: text, query: "world", options: SearchOptions())
		let range = try! #require(matches.first?.utf16Range)
        let ns = text as NSString
		#expect(ns.substring(with: NSRange(location: range.lowerBound, length: range.count)) == "world")
	}

	@Test func regexSearchWorks() {
		let matches = TextSearch.matches(in: sample, query: "let \\w+", options: SearchOptions(isRegex: true))
		#expect(matches.count == 2)
	}

	/// A half-typed regex must be reported as invalid rather than silently
	/// returning nothing, which reads as "no matches".
	@Test func invalidRegexIsReported() {
		#expect(!TextSearch.isValid(query: "func (", options: SearchOptions(isRegex: true)))
		#expect(TextSearch.isValid(query: "func (", options: SearchOptions(isRegex: false)))
		#expect(TextSearch.matches(in: sample, query: "[", options: SearchOptions(isRegex: true)).isEmpty)
	}

	@Test func literalQueryTreatsRegexCharactersLiterally() {
		let text = "cost is $5 (approx)"
		let matches = TextSearch.matches(in: text, query: "$5 (approx)", options: SearchOptions())
		#expect(matches.count == 1)
	}

	@Test func emptyQueryFindsNothing() {
		#expect(TextSearch.matches(in: sample, query: "", options: SearchOptions()).isEmpty)
	}

	@Test func matchesAreCapped() {
		let text = String(repeating: "x\n", count: TextSearch.matchLimit + 500)
		let matches = TextSearch.matches(in: text, query: "x", options: SearchOptions())
		#expect(matches.count <= TextSearch.matchLimit)
	}

	@Test func searchesARopeDirectly() {
		let rope = Rope(sample)
		#expect(TextSearch.matches(in: rope, query: "beta", options: SearchOptions()).count == 1)
	}

	@Test func lineLookupIsCorrectAcrossLines() {
		let text = "a\nbb\nccc\n"
		let starts = TextSearch.lineStartOffsets(in: text as NSString)
		#expect(TextSearch.lineIndex(for: 0, in: starts) == 0)
		#expect(TextSearch.lineIndex(for: 2, in: starts) == 1)
		#expect(TextSearch.lineIndex(for: 5, in: starts) == 2)
	}
}

@Suite(.serialized)
struct ProjectSearchTests {
	/// Builds a small tree, including a directory that must be skipped.
	private func makeProject() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("ideai-search-\(UUID().uuidString)")
		let fm = FileManager.default
		try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
		try fm.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)

		try "let needle = 1\nlet other = 2\n".write(to: root.appendingPathComponent("src/a.swift"), atomically: true, encoding: .utf8)
		try "no match here\n".write(to: root.appendingPathComponent("src/b.swift"), atomically: true, encoding: .utf8)
		try "needle needle\n".write(to: root.appendingPathComponent("src/c.swift"), atomically: true, encoding: .utf8)
		try "needle in excluded\n".write(to: root.appendingPathComponent("node_modules/pkg/d.js"), atomically: true, encoding: .utf8)

		// A binary file that must not be searched or decoded.
		try Data([0x00, 0x01, 0x02] + Array("needle".utf8)).write(to: root.appendingPathComponent("src/blob.bin"))
		return root
	}

	private func run(
		_ search: ProjectSearch,
		query: String,
		options: SearchOptions = SearchOptions()
	) async -> [FileSearchResult] {
		await withCheckedContinuation { continuation in
			var collected: [FileSearchResult] = []
			search.search(
				query: query,
				options: options,
				onResults: { collected.append(contentsOf: $0) },
				onFinished: { _ in continuation.resume(returning: collected) }
			)
		}
	}

	@Test func findsMatchesAcrossFiles() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let results = await run(ProjectSearch(root: root), query: "needle")
		let paths = Set(results.map(\.relativePath))

		#expect(paths.contains("src/a.swift"))
		#expect(paths.contains("src/c.swift"))
		#expect(!paths.contains("src/b.swift"))
	}

	/// Walking node_modules is the difference between a fast search and an
	/// unusable one, so excluded directories are pruned rather than filtered.
	@Test func skipsExcludedDirectories() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let results = await run(ProjectSearch(root: root), query: "needle")
		#expect(!results.contains { $0.relativePath.contains("node_modules") })
	}

	@Test func skipsBinaryFiles() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let results = await run(ProjectSearch(root: root), query: "needle")
		#expect(!results.contains { $0.relativePath.hasSuffix(".bin") })
	}

	@Test func reportsEveryMatchWithinAFile() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let results = await run(ProjectSearch(root: root), query: "needle")
		let c = results.first { $0.relativePath == "src/c.swift" }
		#expect(c?.matches.count == 2)
	}

	@Test func emptyQueryReturnsNothing() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(await run(ProjectSearch(root: root), query: "").isEmpty)
	}

	@Test func regexSearchWorksAcrossTheProject() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let results = await run(
			ProjectSearch(root: root),
			query: "let \\w+ = \\d",
			options: SearchOptions(isRegex: true)
		)
		#expect(results.contains { $0.relativePath == "src/a.swift" })
	}

	// MARK: - The bounds

	/// The walk is stopped by the number of *matches* and not only by the number
	/// of files.
	///
	/// Item 519: `maximumResults` bounds files and `TextSearch.matchLimit` bounds
	/// one file's hits, so between them they permitted 500 × 5 000 rows, and a
	/// one-character query over a real project measured 440 854. The bound that
	/// the row list is linear in was the one nobody had.
	@Test func theWalkStopsAtItsMatchCeiling() async throws {
		let root = try manyMatchesProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let search = ProjectSearch(root: root)
		search.maximumMatches = 25
		let outcome = await finish(search, query: "needle")

		#expect(outcome.results.reduce(0) { $0 + $1.matches.count } >= 25)
		// Stopped, rather than having read all twenty files.
		#expect(outcome.results.count < 20)
		#expect(outcome.end.capped)
	}

	/// A search that fits says nothing about caps, which is the other half of the
	/// claim: `capped` has to be false for the ordinary case or the status line
	/// would tell everybody their list was a prefix.
	@Test func aSearchThatFitsIsNotReportedAsCapped() async throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let outcome = await finish(ProjectSearch(root: root), query: "needle")
		#expect(!outcome.end.capped)
		#expect(outcome.end.completed)
	}

	/// Twenty files with five matches each.
	private func manyMatchesProject() throws -> URL {
		let fm = FileManager.default
		let root = fm.temporaryDirectory.appendingPathComponent("abydos-search-cap-\(UUID().uuidString)")
		try fm.createDirectory(at: root, withIntermediateDirectories: true)
		let body = (0..<5).map { "line \($0) needle\n" }.joined()
		for index in 0..<20 {
			try body.write(
				to: root.appendingPathComponent("file\(index).swift"), atomically: true, encoding: .utf8
			)
		}
		return root
	}

	private func finish(
		_ search: ProjectSearch, query: String
	) async -> (results: [FileSearchResult], end: SearchOutcome) {
		await withCheckedContinuation { continuation in
			var collected: [FileSearchResult] = []
			search.search(
				query: query,
				options: SearchOptions(),
				onResults: { collected.append(contentsOf: $0) },
				onFinished: { continuation.resume(returning: (collected, $0)) }
			)
		}
	}
}

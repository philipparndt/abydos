import Foundation
import Testing
@testable import AbydosKit

/// The conversion that lets the usages list be the search results list.
///
/// Everything else about the usages pane is in `AbydosApp`, which the suite
/// cannot reach — so its evidence is the `--usages-steps` transcripts in item
/// 470. This is the part that has answers which can be wrong on their own.
struct UsageResultsTests {
	/// A scratch tree, thrown away afterwards. The conversion reads the files to
	/// get the line text, so it needs real ones.
	private func withFiles(
		_ files: [String: String], _ body: (URL) throws -> Void
	) throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-usages-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		for (name, text) in files {
			let url = root.appendingPathComponent(name)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try text.write(to: url, atomically: true, encoding: .utf8)
		}
		try body(root)
	}

	private func location(_ url: URL, line: Int, from: Int, to: Int) -> LSPLocation {
		LSPLocation(
			uri: url.absoluteString,
			range: LSPRange(
				start: LSPPosition(line: line, character: from),
				end: LSPPosition(line: line, character: to)
			)
		)
	}

	@Test("usages are grouped by file and put in line order")
	func groupsByFileInLineOrder() throws {
		try withFiles([
			"b.swift": "one\ntwo\nthree\n",
			"a.swift": "alpha\nbeta\n",
		]) { root in
			let b = root.appendingPathComponent("b.swift")
			let a = root.appendingPathComponent("a.swift")
			// Out of order on purpose: a server answers in whatever order its
			// index holds, and a list somebody works down has to go down the file.
			let results = UsageResults.group([
				location(b, line: 2, from: 0, to: 5),
				location(a, line: 1, from: 0, to: 4),
				location(b, line: 0, from: 0, to: 3),
			], root: root)

			#expect(results.map(\.relativePath) == ["a.swift", "b.swift"])
			#expect(results[1].matches.map(\.line) == [0, 2])
			#expect(results[1].matches.map(\.lineText) == ["one", "three"])
			#expect(results[0].matches.map(\.lineText) == ["beta"])
		}
	}

	@Test("a usage carries the whole line, so the row can show the code")
	func carriesTheLine() throws {
		try withFiles(["x.swift": "let a = 1\n    return needle\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let results = UsageResults.group(
				[location(x, line: 1, from: 11, to: 17)], root: root
			)
			#expect(results.count == 1)
			#expect(results[0].matches.count == 1)
			// Untrimmed: the cell trims for display, and the mark is keyed on the
			// trimmed text, so what is stored has to be the line as it is.
			#expect(results[0].matches[0].lineText == "    return needle")
		}
	}

	@Test("the range is a file offset, not a column")
	func rangeIsAFileOffset() throws {
		try withFiles(["x.swift": "abc\ndefgh\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let results = UsageResults.group(
				[location(x, line: 1, from: 1, to: 3)], root: root
			)
			// "abc\n" is four UTF-16 units, so line 1 starts at 4.
			#expect(results[0].matches[0].utf16Range == 5..<7)
		}
	}

	@Test("a range that spans lines does not point past the end of its own")
	func spanningRangeStaysOnItsLine() throws {
		try withFiles(["x.swift": "abc\ndef\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let spanning = LSPLocation(
				uri: x.absoluteString,
				range: LSPRange(
					start: LSPPosition(line: 0, character: 1),
					end: LSPPosition(line: 1, character: 2)
				)
			)
			let results = UsageResults.group([spanning], root: root)
			#expect(results[0].matches[0].utf16Range == 1..<1)
		}
	}

	@Test("a character past the end of the line is clamped to it")
	func clampsToTheLine() throws {
		try withFiles(["x.swift": "ab\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let results = UsageResults.group(
				[location(x, line: 0, from: 1, to: 99)], root: root
			)
			#expect(results[0].matches[0].utf16Range == 1..<2)
		}
	}

	@Test("a file outside the project keeps its whole path")
	func outsideTheProjectKeepsItsPath() throws {
		try withFiles(["inside/x.swift": "a\n", "outside/y.swift": "b\n"]) { root in
			let inside = root.appendingPathComponent("inside/x.swift")
			let outside = root.appendingPathComponent("outside/y.swift")
			let results = UsageResults.group([
				location(inside, line: 0, from: 0, to: 1),
				location(outside, line: 0, from: 0, to: 1),
			], root: root.appendingPathComponent("inside"))

			let paths = Set(results.map(\.relativePath))
			#expect(paths.contains("x.swift"))
			#expect(paths.contains(outside.standardizedFileURL.path))
		}
	}

	@Test("a location naming no file is dropped rather than counted")
	func dropsNonFiles() throws {
		try withFiles(["x.swift": "a\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let results = UsageResults.group([
				location(x, line: 0, from: 0, to: 1),
				LSPLocation(
					uri: "",
					range: LSPRange(
						start: LSPPosition(line: 0, character: 0),
						end: LSPPosition(line: 0, character: 1)
					)
				),
			], root: root)
			#expect(results.count == 1)
		}
	}

	@Test("a line the file no longer has gives an empty row rather than a crash")
	func missingLineIsEmpty() throws {
		// A server's index can be one edit behind the file. Item 470's list is
		// built from whatever the answer said, so the answer being stale must not
		// take the list with it.
		try withFiles(["x.swift": "only one line\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let results = UsageResults.group(
				[location(x, line: 400, from: 0, to: 3)], root: root
			)
			#expect(results[0].matches.count == 1)
			#expect(results[0].matches[0].lineText.isEmpty)
			#expect(results[0].matches[0].line == 400)
		}
	}

	@Test("marks for a usage list are keyed the way search's are")
	func marksAgreeWithTheChecklist() throws {
		// The point of the conversion: what comes out of it can be handed to
		// SearchChecklist with no adapter, which is why there is one done logic
		// and not two.
		try withFiles(["x.swift": "let a = need\nlet b = need\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let results = UsageResults.group([
				location(x, line: 0, from: 8, to: 12),
				location(x, line: 1, from: 8, to: 12),
			], root: root)

			let marks = SearchChecklist.marks(for: results[0])
			#expect(marks.count == 2)
			#expect(marks[0] != marks[1])

			var checklist = SearchChecklist()
			let question = SearchChecklist.Question(query: "x.swift:0:8", options: SearchOptions())
			checklist.set([marks[0]], done: true, for: question)
			#expect(checklist.isDone(marks[0], for: question))
			#expect(!checklist.isDone(marks[1], for: question))
			#expect(checklist.doneCount(in: results, for: question) == 1)
		}
	}

	@Test("the usages of two symbols are two questions")
	func twoSymbolsAreTwoQuestions() throws {
		try withFiles(["x.swift": "let a = need\n"]) { root in
			let x = root.appendingPathComponent("x.swift")
			let results = UsageResults.group(
				[location(x, line: 0, from: 8, to: 12)], root: root
			)
			let marks = SearchChecklist.marks(for: results[0])

			var checklist = SearchChecklist()
			let first = SearchChecklist.Question(query: "x.swift:0:8", options: SearchOptions())
			let second = SearchChecklist.Question(query: "x.swift:9:4", options: SearchOptions())
			checklist.set(marks, done: true, for: first)

			#expect(checklist.doneCount(in: results, for: first) == 1)
			// Asking about another symbol arrives unticked; asking about the same
			// one again brings the ticks back.
			#expect(checklist.doneCount(in: results, for: second) == 0)
		}
	}
}

import Testing
import Foundation
@testable import AbydosKit

struct DiffSearchTests {
	@Test func aRemovedAndAnAddedLineBothMatch() {
		// What the view hands in for `-let count = 1` / `+let count = 2`: the
		// code, both sides.
		let hits = DiffSearch.matches(
			in: ["let count = 1", "let count = 2"], query: "count", options: SearchOptions()
		)
		#expect(hits == [
			DiffSearch.Hit(line: 0, utf16Range: 4..<9),
			DiffSearch.Hit(line: 1, utf16Range: 4..<9),
		])
	}

	@Test func gitsPrefixIsNotText() {
		let lines = ["value"]
		#expect(DiffSearch.matches(in: lines, query: "+value", options: SearchOptions()).isEmpty)
		#expect(DiffSearch.matches(in: lines, query: "value", options: SearchOptions()).count == 1)
	}

	@Test func matchCaseAndWholeWordMeanWhatTheyMeanInTheEditor() {
		let lines = ["let alpha = 1", "let Alpha = 2", "// alphabet soup"]
		#expect(DiffSearch.matches(in: lines, query: "alpha", options: SearchOptions()).count == 3)
		#expect(DiffSearch.matches(
			in: lines, query: "Alpha", options: SearchOptions(caseSensitive: true)
		).map(\.line) == [1])
		#expect(DiffSearch.matches(
			in: lines, query: "alpha", options: SearchOptions(wholeWord: true)
		).map(\.line) == [0, 1])
	}

	@Test func aMatchNeverSpansTwoLines() {
		let lines = ["a", "b"]
		#expect(DiffSearch.matches(in: lines, query: "a\\nb", options: SearchOptions(isRegex: true)).isEmpty)
	}

	@Test func aLoneCarriageReturnDoesNotMoveTheLinesAfterIt() {
		// A diff of a CRLF file can carry a `\r` inside a line's text.
		let lines = ["first\r", "second", "third"]
		let hits = DiffSearch.matches(in: lines, query: "third", options: SearchOptions())
		#expect(hits == [DiffSearch.Hit(line: 2, utf16Range: 0..<5)])
	}

	@Test func aMatchOfNoCharactersIsNotAMatch() {
		#expect(DiffSearch.matches(in: ["one", "two"], query: "^", options: SearchOptions(isRegex: true)).isEmpty)
	}

	@Test func aPatternThatDoesNotCompileFindsNothing() {
		#expect(DiffSearch.matches(in: ["(a"], query: "(", options: SearchOptions(isRegex: true)).isEmpty)
	}

	@Test func theMatchLimitHolds() {
		let lines = Array(repeating: "a a a a a", count: 2_000)
		let hits = DiffSearch.matches(in: lines, query: "a", options: SearchOptions())
		#expect(hits.count == TextSearch.matchLimit)
	}

	@Test func rangesAreUTF16() {
		// An emoji is two UTF-16 units, which is what the view measures in.
		let hits = DiffSearch.matches(in: ["😀 x"], query: "x", options: SearchOptions())
		#expect(hits == [DiffSearch.Hit(line: 0, utf16Range: 3..<4)])
	}

	/// A keystroke in the find bar searches the whole diff again, and a
	/// whole-file diff of a large file is twenty thousand lines of it.
	@Test func aKeystrokeOverATwentyThousandLineDiffIsCheap() {
		let lines = (0..<20_000).map { "\tlet value\($0) = compute(count: \($0), into: &buffer)" }
		var elapsed: [Double] = []
		for query in ["count", "e", "buffer)"] {
			let started = Date()
			_ = DiffSearch.matches(in: lines, query: query, options: SearchOptions())
			elapsed.append(Date().timeIntervalSince(started))
		}
		print(String(
			format: "DiffSearch over 20,000 lines: count %.1f ms, e %.1f ms, buffer) %.1f ms — %@",
			elapsed[0] * 1000, elapsed[1] * 1000, elapsed[2] * 1000, MachineLoad.said
		))
		// A frame is 16 ms and a keystroke is not a frame; a fifth of a second
		// is the point at which typing in the field is felt to lag.
		if Stopwatch.maySay("DiffSearchTests", "a keystroke over 20,000 lines") {
			#expect(elapsed.max() ?? 0 < 0.2, "\(elapsed) s — \(MachineLoad.said)")
		}
	}
}

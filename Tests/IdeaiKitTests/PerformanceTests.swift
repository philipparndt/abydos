import Testing
import Foundation
import SwiftTreeSitter
@testable import IdeaiKit

/// Guards the property the whole design exists to deliver: cost scales with the
/// viewport, not the file.
///
/// Thresholds are deliberately loose — they are regression tripwires for a
/// debug build on shared CI-style hardware, not benchmarks. Actual timings are
/// printed so a slow change is visible even when it stays under the limit.
struct PerformanceTests {
	/// ~9 MB / ~200k lines of realistic Swift.
	static func makeLargeSource(lines: Int) -> String {
		var out = String()
		out.reserveCapacity(lines * 46)
		for i in 0..<(lines / 4) {
			out += "func function\(i)(argument: Int) -> String {\n"
			out += "    let value = argument * \(i) // a trailing comment\n"
			out += "    return \"result \\(value) for \(i)\"\n"
			out += "}\n"
		}
		return out
	}

	/// Prints a derived figure alongside the timings.
	static func report(_ label: String, _ value: String) {
		print(String(format: "PERF %-38s %8s", (label as NSString).utf8String!, (value as NSString).utf8String!))
	}

	static func time(_ label: String, _ body: () -> Void) -> TimeInterval {
		let start = DispatchTime.now().uptimeNanoseconds
		body()
		let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
		print(String(format: "PERF %-38s %8.2f ms", (label as NSString).utf8String!, elapsed * 1000))
		return elapsed
	}

	// MARK: - Loading

	@Test func buildsLargeRopeQuickly() {
		let source = Self.makeLargeSource(lines: 200_000)
		print("PERF source size: \(source.utf8.count / 1_000_000) MB, \(source.utf8.count) bytes")

		var rope = Rope("")
		let elapsed = Self.time("build rope (200k lines)") {
			rope = Rope(source)
		}
		#expect(rope.lineCount == 200_001)
		#expect(elapsed < 5.0, "rope construction took \(elapsed)s")
	}

	// MARK: - Random access

	@Test func lineLookupsAreLogarithmic() {
		// Compared between two sizes rather than against a wall-clock limit.
		// The claim is that lookup cost grows with the logarithm of the file,
		// and a fixed threshold tests the machine's current load instead — this
		// one failed under a parallel test run while passing on its own.
		func lookupTime(lines: Int, label: String) -> TimeInterval {
			let rope = Rope(Self.makeLargeSource(lines: lines))
			var seed: UInt64 = 0x9E3779B97F4A7C15
			var checksum = 0
			let elapsed = Self.time(label) {
				for _ in 0..<10_000 {
					seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
					let line = Int(seed % UInt64(rope.lineCount))
					checksum &+= rope.byteOffset(ofLine: line)
				}
			}
			#expect(checksum != 0)
			return elapsed
		}

		let small = lookupTime(lines: 2_000, label: "10k lookups (2k lines)")
		let large = lookupTime(lines: 200_000, label: "10k lookups (200k lines)")

		// A hundredfold more lines. Logarithmic growth is roughly 1.7x; linear
		// would be a hundredfold. Anything under ten is comfortably not linear,
		// and leaves room for the noise a shared machine adds.
		let ratio = large / max(small, 0.000_001)
		Self.report("lookup cost ratio (100x larger file)", "\(String(format: "%.1f", ratio))x")
		#expect(ratio < 10, "lookups scaled \(ratio)x for a 100x larger file")
	}

	@Test func editsAreIndependentOfFileSize() {
		// The rope's core promise: editing a huge file costs the same as a small
		// one. Compare the two directly rather than trusting an absolute number.
		var small = Rope(Self.makeLargeSource(lines: 1_000))
		var large = Rope(Self.makeLargeSource(lines: 200_000))

		let smallTime = Self.time("1k inserts into 1k-line file") {
			for i in 0..<1_000 {
				let at = small.byteOffset(ofLine: i % small.lineCount)
				small.replace(byteRange: at..<at, with: "// x\n")
			}
		}
		let largeTime = Self.time("1k inserts into 200k-line file") {
			for i in 0..<1_000 {
				let at = large.byteOffset(ofLine: (i * 197) % large.lineCount)
				large.replace(byteRange: at..<at, with: "// x\n")
			}
		}

		// Logarithmic growth over a 200x size increase is a small constant factor.
		// Anything near 200x would mean the tree degenerated into a list.
		let ratio = largeTime / max(smallTime, 0.0001)
		print(String(format: "PERF edit cost ratio (200x larger file): %.1fx", ratio))
		#expect(ratio < 25.0, "edit cost grew \(ratio)x with a 200x larger file")
	}

	// MARK: - Syntax

	@Test func viewportHighlightingIsFastOnHugeFile() throws {
		let source = Self.makeLargeSource(lines: 100_000)
		let rope = Rope(source)
		let engine = try #require(SyntaxEngine(languageId: "swift"))

		let parseTime = Self.time("initial parse (100k lines)") {
			engine.parse(rope: rope)
		}
		#expect(engine.hasTree)
		print(String(format: "PERF parse throughput: %.1f MB/s",
		             Double(rope.byteCount) / 1_000_000 / parseTime))

		// One screenful in the middle of the file — the operation that runs on
		// every scroll frame.
		let start = rope.byteOffset(ofLine: 50_000)
		let end = rope.byteOffset(ofLine: 50_080)

		// Best of several, for the same reason the keystroke measurement is:
		// the rest of the suite runs alongside this one, and a busy machine
		// moves the number by more than any regression worth catching.
		var tokens: [HighlightToken] = []
		var elapsed = Double.greatestFiniteMagnitude
		for round in 0..<5 {
			let round = Self.time("highlight 80-line viewport, round \(round + 1)") {
				tokens = engine.highlights(rope: rope, byteRange: start..<end)
			}
			elapsed = min(elapsed, round)
		}

		#expect(!tokens.isEmpty, "viewport produced no tokens")
		// At 60fps a frame is 16ms; a viewport query must fit comfortably inside.
		#expect(elapsed < 0.05, "viewport highlight took \(elapsed)s")
	}

	/// The number that decides whether typing feels instant: what a keystroke
	/// costs on the main thread, through the real document API.
	///
	/// The reparse itself is deliberately not measured here — it runs on the
	/// syntax queue (see `reparseCostJustifiesBackgroundQueue`), and the point of
	/// this test is that the typing path does not wait for it.
	@Test func keystrokeCostOnMainThreadIsNegligible() throws {
		let source = Self.makeLargeSource(lines: 100_000)
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("ideai-perf-\(UUID().uuidString).swift")
		try source.write(to: url, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: url) }

		let document = try TextDocument(url: url)
		print("PERF document: \(document.lineCount) lines, \(document.rope.byteCount) bytes")

		var caret = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: 50_000))

		// Best of several rounds. The rest of the suite runs alongside this one,
		// and a machine doing other work moves the mean by three times or more —
		// which is far more than any change worth catching here. The least
		// interrupted round is what the typing path actually costs.
		var perKeystroke = Double.greatestFiniteMagnitude
		for round in 0..<5 {
			let elapsed = Self.time("500 keystrokes via TextDocument (100k lines), round \(round + 1)") {
				for _ in 0..<500 {
					caret = document.replace(utf16Range: caret..<caret, with: "x", caretBefore: caret)
				}
			}
			perKeystroke = min(perKeystroke, elapsed / 500)
		}
		print(String(format: "PERF per keystroke (main thread): %.4f ms", perKeystroke * 1000))
		// A 60fps frame is 16ms; typing should not consume a measurable slice of it.
		#expect(perKeystroke < 0.002, "keystroke cost \(perKeystroke * 1000)ms on the main thread")
	}

	/// Documents *why* the reparse is off the main thread.
	///
	/// tree-sitter genuinely reparses incrementally — it re-reads only a couple
	/// of KB — but still rebuilds the root's child list, which is O(siblings) and
	/// therefore grows with file size. Running it inline would drop frames, so
	/// this asserts the cost is real rather than pretending it is not.
	@Test func reparseCostJustifiesBackgroundQueue() throws {
		let source = Self.makeLargeSource(lines: 100_000)
		var rope = Rope(source)
		let engine = try #require(SyntaxEngine(languageId: "swift"))
		engine.parse(rope: rope)

		let insertLine = 50_000
		var at = rope.byteOffset(ofLine: insertLine)
		let elapsed = Self.time("20 background reparses (100k lines)") {
			for _ in 0..<20 {
				let point = Point(row: insertLine, column: at - rope.byteOffset(ofLine: insertLine))
				rope.replace(byteRange: at..<at, with: "x")
				engine.applyEdit(
					InputEdit(
						startByte: at, oldEndByte: at, newEndByte: at + 1,
						startPoint: point, oldEndPoint: point,
						newEndPoint: Point(row: insertLine, column: Int(point.column) + 1)
					),
					newRope: rope
				)
				at += 1
			}
		}
		print(String(format: "PERF per background reparse: %.2f ms", elapsed / 20 * 1000))
		// Loose: this is a background cost. It only needs to stay sane.
		#expect(elapsed / 20 < 0.2)
	}

	// MARK: - Folding

	@Test func foldComputationIsReasonableOnHugeFile() throws {
		let source = Self.makeLargeSource(lines: 100_000)
		let rope = Rope(source)
		let engine = try #require(SyntaxEngine(languageId: "swift"))
		engine.parse(rope: rope)

		var folds: [FoldRange] = []
		let elapsed = Self.time("fold ranges (100k lines)") {
			folds = engine.foldRanges(rope: rope)
		}
		#expect(!folds.isEmpty)
		print("PERF fold regions found: \(folds.count)")
		// Runs on a background queue and is debounced, so the bar is looser.
		#expect(elapsed < 10.0, "fold computation took \(elapsed)s")
	}

	@Test func foldingStateMapsLinesQuickly() {
		// Collapsing every region then scrolling must stay cheap.
		var state = FoldingState()
		let ranges = (0..<20_000).map { FoldRange(startLine: $0 * 5, endLine: $0 * 5 + 3) }
		state.setAvailable(ranges)

		let collapseTime = Self.time("collapse 20k regions") {
			state.collapseAll()
		}
		#expect(collapseTime < 2.0)

		var checksum = 0
		let mapTime = Self.time("100k visual→document line lookups") {
			for i in 0..<100_000 {
				checksum &+= state.documentLine(forVisualLine: i % 40_000)
			}
		}
		#expect(checksum != 0)
		#expect(mapTime < 2.0, "line mapping took \(mapTime)s")
	}
}

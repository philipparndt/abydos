import Testing
import Foundation
@testable import AbydosKit

/// Row mapping under soft wrap, including how it composes with folding.
struct WrapLayoutTests {
	/// Builds a layout over `lines` lines whose widths come from `widths`.
	private func makeLayout(
		lineCount: Int,
		columns: Int?,
		folding: FoldingState = FoldingState(),
		widths: [Int: Int] = [:]
	) -> WrapLayout {
		var layout = WrapLayout()
		// The fixtures describe line widths; the layout now asks for row counts,
		// so they are converted here rather than in every test.
		layout.rebuild(
			documentLineCount: lineCount, columns: columns, folding: folding, documentRevision: 0
		) { line in
			let width = widths[line] ?? 10
			guard let columns, columns > 0 else { return 1 }
			return max(1, (width + columns - 1) / columns)
		}
		return layout
	}

	@Test func withoutWrappingEachLineIsOneRow() {
		let layout = makeLayout(lineCount: 5, columns: nil)
		#expect(layout.totalRows == 5)
		#expect(layout.position(forRow: 3).line == 3)
		#expect(layout.position(forRow: 3).segment == 0)
	}

	@Test func longLinesOccupySeveralRows() {
		// Line 1 is 45 columns wide at a width of 20 → three rows.
		let layout = makeLayout(lineCount: 3, columns: 20, widths: [1: 45])
		#expect(layout.rowCount(forLine: 1) == 3)
		#expect(layout.totalRows == 5)
	}

	@Test func emptyLinesStillTakeOneRow() {
		let layout = makeLayout(lineCount: 3, columns: 20, widths: [0: 0, 1: 0, 2: 0])
		#expect(layout.totalRows == 3)
	}

	@Test func mapsRowsBackToLinesAndSegments() {
		let layout = makeLayout(lineCount: 3, columns: 10, widths: [0: 5, 1: 25, 2: 5])
		// Rows: 0 → line 0; 1,2,3 → line 1 segments 0,1,2; 4 → line 2.
		#expect(layout.position(forRow: 0).line == 0)
		#expect(layout.position(forRow: 1) == (line: 1, segment: 0))
		#expect(layout.position(forRow: 2) == (line: 1, segment: 1))
		#expect(layout.position(forRow: 3) == (line: 1, segment: 2))
		#expect(layout.position(forRow: 4).line == 2)
	}

	@Test func reportsFirstRowOfEachLine() {
		let layout = makeLayout(lineCount: 3, columns: 10, widths: [0: 5, 1: 25, 2: 5])
		#expect(layout.firstRow(forLine: 0) == 0)
		#expect(layout.firstRow(forLine: 1) == 1)
		#expect(layout.firstRow(forLine: 2) == 4)
	}

	/// Wrapping and folding must compose: a hidden line contributes no rows.
	@Test func hiddenLinesContributeNoRows() {
		var folding = FoldingState()
		folding.setAvailable([FoldRange(startLine: 0, endLine: 2)])
		folding.toggle(line: 0)

		let layout = makeLayout(lineCount: 5, columns: 10, folding: folding, widths: [:])
		// Lines 1 and 2 are hidden, so rows come from 0, 3 and 4 only.
		#expect(layout.totalRows == 3)
		#expect(layout.position(forRow: 1).line == 3)
	}

	@Test func roundTripsEveryRow() {
		let widths = [0: 5, 1: 33, 2: 0, 3: 21, 4: 9]
		let layout = makeLayout(lineCount: 5, columns: 10, widths: widths)

		// Every row maps to a line whose own first row plus the segment returns it.
		for row in 0..<layout.totalRows {
			let position = layout.position(forRow: row)
			#expect(layout.firstRow(forLine: position.line) + position.segment == row)
		}
	}

	@Test func clampsRowsOutOfRange() {
		let layout = makeLayout(lineCount: 3, columns: 10)
		#expect(layout.position(forRow: -5).line == 0)
		#expect(layout.position(forRow: 9_999).line == 2)
	}

	@Test func handlesAnEmptyDocument() {
		let layout = makeLayout(lineCount: 0, columns: 10)
		#expect(layout.totalRows == 1)
		#expect(layout.position(forRow: 0).line == 0)
	}
}

/// Cutting a wrapped line into rows. The row count is measured in display
/// columns, so the slices have to be as well — a tab is one UTF-16 unit but up
/// to four columns wide, and cutting by unit count makes a row wider than the
/// space it was measured for. The overflow is then clipped and those characters
/// appear nowhere at all.
struct WrapSegmentRangeTests {
	private func slices(_ text: String, columns: Int, tabWidth: Int = 4) -> [String] {
		let units = Array(text.utf16)
		var result: [String] = []
		var segment = 0
		while true {
			let range = WrapLayout.segmentRange(
				in: text, segment: segment, columns: columns, tabWidth: tabWidth
			)
			if range.isEmpty && segment > 0 { break }
			result.append(String(decoding: units[range], as: UTF16.self))
			if range.upperBound >= units.count { break }
			segment += 1
		}
		return result
	}

	@Test func plainTextSplitsEveryColumns() {
		#expect(slices("abcdefgh", columns: 3) == ["abc", "def", "gh"])
	}

	@Test func shortLinesAreOneSegment() {
		#expect(slices("ab", columns: 10) == ["ab"])
	}

	/// Every character has to appear in exactly one slice; anything else is a
	/// character the user cannot see anywhere.
	@Test func slicesReconstructTheLine() {
		for columns in [3, 5, 8, 20] {
			let text = "\tfunc example(argument: String) -> Int {\t// trailing"
			#expect(slices(text, columns: columns).joined() == text, "columns \(columns)")
		}
	}

	/// A leading tab eats four columns, so fewer characters fit on that row.
	@Test func aTabTakesItsDisplayWidth() {
		// Tab (4 columns) + "abcd" would be 8 columns; only 6 fit.
		#expect(slices("\tabcdef", columns: 6) == ["\tab", "cdef"])
	}

	@Test func tabsAdvanceToTheNextStop() {
		// "ab" is 2 columns, the tab then fills to column 4.
		#expect(slices("ab\tcd", columns: 4) == ["ab\t", "cd"])
	}

	/// A tab fills exactly to its stop, so one that reaches the edge still fits.
	@Test func aTabThatEndsOnTheEdgeFits() {
		#expect(slices("abc\tx", columns: 4) == ["abc\t", "x"])
	}

	/// One that would cross the edge moves whole, since it cannot be split.
	@Test func aTabNeverStraddlesTheEdge() {
		#expect(slices("abcd\tx", columns: 6) == ["abcd", "\tx"])
	}

	@Test func segmentsPastTheEndAreEmpty() {
		let range = WrapLayout.segmentRange(in: "abc", segment: 9, columns: 2, tabWidth: 4)
		#expect(range.isEmpty)
	}

	@Test func zeroColumnsIsNotADivideByZero() {
		#expect(WrapLayout.segmentRange(in: "abc", segment: 0, columns: 0, tabWidth: 4).isEmpty)
	}
}

/// Offsets have to land on the row that actually shows them, by the same rule.
struct WrapSegmentForOffsetTests {
	@Test func offsetsMapToTheirRow() {
		#expect(WrapLayout.segment(forOffset: 0, in: "abcdefgh", columns: 3, tabWidth: 4) == 0)
		#expect(WrapLayout.segment(forOffset: 2, in: "abcdefgh", columns: 3, tabWidth: 4) == 0)
		#expect(WrapLayout.segment(forOffset: 3, in: "abcdefgh", columns: 3, tabWidth: 4) == 1)
		#expect(WrapLayout.segment(forOffset: 7, in: "abcdefgh", columns: 3, tabWidth: 4) == 2)
	}

	/// The case a character count gets wrong: after one tab the caret is only
	/// three units in but already on the second row.
	@Test func tabsShiftWhichRowAnOffsetIsOn() {
		let text = "\tabcdef"
		#expect(WrapLayout.segment(forOffset: 2, in: text, columns: 6, tabWidth: 4) == 0)
		#expect(WrapLayout.segment(forOffset: 4, in: text, columns: 6, tabWidth: 4) == 1)
	}

	@Test func theSliceAndTheOffsetAgree() {
		let text = "\tlet value = compute(a, b)"
		let columns = 10
		for offset in 0...(text.utf16.count) {
			let segment = WrapLayout.segment(forOffset: offset, in: text, columns: columns, tabWidth: 4)
			let range = WrapLayout.segmentRange(in: text, segment: segment, columns: columns, tabWidth: 4)
			// The offset must fall within the slice its segment names.
			#expect(offset >= range.lowerBound, "offset \(offset)")
			#expect(offset <= range.upperBound, "offset \(offset)")
		}
	}
}

/// The row count and the slicing have to come from the same walk. Where they
/// disagree, the layout allocates a row with nothing to put in it and the
/// editor shows a blank gap between wrapped lines.
struct WrapRowCountTests {
	@Test func plainTextDividesEvenly() {
		#expect(WrapLayout.rowCount(in: "abcdef", columns: 3, tabWidth: 4) == 2)
		#expect(WrapLayout.rowCount(in: "abcdefg", columns: 3, tabWidth: 4) == 3)
	}

	@Test func aShortLineIsOneRow() {
		#expect(WrapLayout.rowCount(in: "ab", columns: 10, tabWidth: 4) == 1)
		#expect(WrapLayout.rowCount(in: "", columns: 10, tabWidth: 4) == 1)
	}

	/// The case ceil(width / columns) gets wrong: a tab that cannot fit moves to
	/// the next row whole, wasting the columns it left behind.
	@Test func aMovedTabCostsAnExtraRow() {
		// "abcd" fills 4 of 6 columns; the tab needs 4 more, so it moves.
		#expect(WrapLayout.rowCount(in: "abcd\tx", columns: 6, tabWidth: 4) == 2)
		// Display width is 4 + 4 + 1 = 9, and ceil(9 / 6) is 2 as well here —
		// but the arithmetic agrees only by luck, which the next case shows.
		#expect(WrapLayout.rowCount(in: "abcde\tx", columns: 6, tabWidth: 4) == 2)
	}

	/// Every row the layout allocates must have a slice with something in it.
	@Test func everyCountedRowHasContent() {
		for text in ["\tfunc thing() {", "abcd\tx\ty", "no tabs here at all", "\t\t\tdeep"] {
			for columns in [4, 6, 9, 15] {
				let rows = WrapLayout.rowCount(in: text, columns: columns, tabWidth: 4)
				for segment in 0..<rows {
					let range = WrapLayout.segmentRange(
						in: text, segment: segment, columns: columns, tabWidth: 4
					)
					#expect(!range.isEmpty || text.isEmpty, "\(text) @\(columns) row \(segment)")
				}
				// And nothing is left over past the last row.
				let past = WrapLayout.segmentRange(
					in: text, segment: rows, columns: columns, tabWidth: 4
				)
				#expect(past.isEmpty, "\(text) @\(columns) has an unshown row")
			}
		}
	}
}

/// Rows are cut at words, not in them.
///
/// Prose read in the editor — a README with word wrap on — was broken
/// mid-word at the column edge, which is the one thing soft wrap exists to
/// avoid. The cut goes back to just after the last whitespace that follows a
/// word; leading indentation is not such a place, and a word longer than the
/// row is cut at the edge as before.
struct WrapAtWordsTests {
	private func rows(_ text: String, columns: Int, tabWidth: Int = 4) -> [String] {
		let units = Array(text.utf16)
		return (0..<WrapLayout.rowCount(in: text, columns: columns, tabWidth: tabWidth)).map { segment in
			let range = WrapLayout.segmentRange(in: text, segment: segment, columns: columns, tabWidth: tabWidth)
			return String(utf16CodeUnits: Array(units[range]), count: range.count)
		}
	}

	@Test func aSentenceBreaksAfterAWordAndTheSpaceStaysAbove() {
		#expect(rows("the quick brown fox jumps", columns: 10) == ["the quick ", "brown fox ", "jumps"])
	}

	@Test func aWordLongerThanTheRowIsCutAtTheEdge() {
		#expect(rows("abcdefghijklmnop", columns: 6) == ["abcdef", "ghijkl", "mnop"])
		#expect(rows("ab abcdefghijkl", columns: 6) == ["ab ", "abcdef", "ghijkl"])
	}

	@Test func leadingIndentationIsNotAPlaceToCut() {
		#expect(rows("    a long indented sentence", columns: 12) == ["    a long ", "indented ", "sentence"])
		#expect(rows("\tabcdef", columns: 6) == ["\tab", "cdef"])
	}

	@Test func theCaretFollowsTheWordItIsIn() {
		let text = "the quick brown fox"
		// "the quick " is row 0; the b of brown is at 10 and on row 1.
		#expect(WrapLayout.segment(forOffset: 10, in: text, columns: 10, tabWidth: 4) == 1)
		#expect(WrapLayout.segment(forOffset: 9, in: text, columns: 10, tabWidth: 4) == 0)
		#expect(WrapLayout.rowCount(in: text, columns: 10, tabWidth: 4) == 2)
	}
}

/// One pass over the chunks says exactly what a lookup per line said.
///
/// The wrap layout swapped `lineText` per line for `forEachLine`, and the only
/// thing that makes that safe is the two agreeing on every line of every shape
/// of file — so that is what is asserted, rather than a count.
struct RopeLineWalkTests {
	private func lines(of rope: Rope) -> [String] {
		var out: [String] = []
		rope.forEachLine { out.append($0) }
		return out
	}

	private func perLine(of rope: Rope) -> [String] {
		(0..<rope.lineCount).map { rope.lineText($0) }
	}

	@Test(arguments: [
		"",
		"\n",
		"one",
		"one\n",
		"one\ntwo",
		"one\ntwo\n",
		"\n\n\n",
		"a\n\nb\n",
		"trailing spaces   \n\tand a tab\n",
	])
	func theWalkAgreesWithALookupPerLine(_ text: String) {
		let rope = Rope(text)
		#expect(lines(of: rope) == perLine(of: rope))
		#expect(lines(of: rope).count == rope.lineCount)
	}

	/// Chunks are 512–2048 bytes, so a file this size is many of them and the
	/// lines land across the seams — which is the case the carried buffer is
	/// for, and the one a single-chunk fixture would never reach.
	@Test func theWalkAgreesAcrossChunkSeams() {
		let text = (0..<4000).map { "line \($0) with enough text on it to cross a seam" }
			.joined(separator: "\n") + "\n"
		let rope = Rope(text)
		#expect(rope.byteCount > 100_000, "the fixture has to be many chunks")
		#expect(lines(of: rope) == perLine(of: rope))
	}

	/// A multi-byte character is not cut in half by a seam.
	@Test func theWalkKeepsCharactersWhole() {
		let text = (0..<2000).map { "ünïcödé line \($0) — emoji 🌍 and a tab\tin it" }
			.joined(separator: "\n") + "\n"
		let rope = Rope(text)
		#expect(lines(of: rope) == perLine(of: rope))
		#expect(!lines(of: rope).contains { $0.contains("\u{FFFD}") }, "no replacement characters")
	}
}

/// What the wrap layout will and will not rebuild for.
///
/// A scroll used to re-lay-out the whole file: `viewportChanged` is wired to
/// the clip view's bounds, which move on every scroll, and nothing asked
/// whether anything had changed. At 68,608 lines that was 100 ms a scroll.
struct WrapLayoutCurrencyTests {
	private var folding = FoldingState()

	private func built(
		lineCount: Int = 100, columns: Int? = 40, revision: Int = 1, folding: FoldingState
	) -> (WrapLayout, Int) {
		var layout = WrapLayout()
		var counted = 0
		layout.rebuild(
			documentLineCount: lineCount, columns: columns,
			folding: folding, documentRevision: revision
		) { _ in counted += 1; return 2 }
		return (layout, counted)
	}

	@Test func aFreshLayoutIsCurrentForNothing() {
		let layout = WrapLayout()
		#expect(!layout.isCurrent(
			documentLineCount: 0, columns: nil, folding: folding, documentRevision: 0
		))
	}

	@Test func aScrollChangesNothingTheLayoutIsBuiltFrom() {
		let (layout, counted) = built(folding: folding)
		#expect(counted == 100, "the first build counts every line")
		// A scroll: same document, same width, same folds.
		#expect(layout.isCurrent(
			documentLineCount: 100, columns: 40, folding: folding, documentRevision: 1
		))
	}

	@Test func aSecondBuildWithTheSameInputsCountsNothing() {
		var (layout, _) = built(folding: folding)
		var counted = 0
		layout.rebuild(
			documentLineCount: 100, columns: 40, folding: folding, documentRevision: 1
		) { _ in counted += 1; return 2 }
		#expect(counted == 0, "the rows were already counted")
		#expect(layout.totalRows == 200, "and the layout still describes them")
	}

	@Test func aNarrowerViewportIsNotCurrent() {
		let (layout, _) = built(folding: folding)
		#expect(!layout.isCurrent(
			documentLineCount: 100, columns: 30, folding: folding, documentRevision: 1
		))
	}

	/// The case a width-only guard would have got wrong: typing a long word
	/// into one line rewraps it without changing the line count.
	@Test func anEditInsideOneLineIsNotCurrent() {
		let (layout, _) = built(folding: folding)
		#expect(!layout.isCurrent(
			documentLineCount: 100, columns: 40, folding: folding, documentRevision: 2
		))
	}

	/// The other case: `collapseAllFolds` moves the folds and touches neither
	/// the width nor the line count.
	@Test func aCollapsedFoldIsNotCurrent() {
		var folding = FoldingState()
		folding.setAvailable([FoldRange(startLine: 10, endLine: 20)])
		let (layout, _) = built(folding: folding)

		var collapsed = folding
		collapsed.toggle(line: 10)
		#expect(collapsed.revision != folding.revision, "folding says it moved")
		#expect(!layout.isCurrent(
			documentLineCount: 100, columns: 40, folding: collapsed, documentRevision: 1
		))
	}

	@Test func wrapBeingTurnedOffIsNotCurrent() {
		let (layout, _) = built(folding: folding)
		#expect(!layout.isCurrent(
			documentLineCount: 100, columns: nil, folding: folding, documentRevision: 1
		))
	}
}

/// What a scroll costs when soft wrap is on, and what a rebuild costs when one
/// is really needed.
///
/// **Both were the same number, and that was the bug.** `viewportChanged` is
/// wired to `frameDidChangeNotification` *and* `boundsDidChangeNotification` on
/// the clip view, and the bounds move on every scroll — so every scroll event
/// and every frame of a live resize re-laid-out the whole document. Measured on
/// a 5.5 MB crash report of 68,608 lines: **103.7 ms**, release, on the main
/// thread. That is the "slow to settle and react" a `make run` window was
/// reported for, and in debug, where a `lineText` descent is 220 times dearer,
/// the same work is tens of seconds.
///
/// Two separate claims, because two separate fixes:
///
///   - a scroll changes nothing the layout is built from, so it counts no rows
///     at all — 103.7 ms became 0.041 ms;
///   - a rebuild that is needed walks the chunks once instead of descending the
///     tree per line — 103.7 ms became 32.5 ms.
///
/// **Bounds are on processor time**, as the rest of the performance suite is:
/// this runs beside several hundred other tests and a wall clock over it would
/// be measuring what the machine was doing instead. The absolute figures above
/// are from a release build; the assertions below are ratios, which survive
/// being run under load and under either configuration.
struct WrapLayoutCostTests {
	/// Lines shaped like the file this was found on: prose and stack frames,
	/// averaging about eighty columns, so some wrap at 120 and most do not.
	private static func makeRope(lines: Int) -> Rope {
		let text = (0..<lines).map { index in
			index % 7 == 0
				? "    \(index) at Abydos.CodeView.rebuildWrapLayout() + \(index * 37) in CodeView.swift:811"
				: "line \(index) of an ordinary width"
		}.joined(separator: "\n") + "\n"
		return Rope(text)
	}

	private static func rowCounts(of rope: Rope, columns: Int) -> [Int32] {
		var counts: [Int32] = []
		counts.reserveCapacity(rope.lineCount)
		rope.forEachLine { counts.append(Int32(WrapLayout.rowCount(in: $0, columns: columns, tabWidth: 4))) }
		return counts
	}

	/// The scroll path: the layout is asked whether it is current and says yes.
	@Test func aScrollCostsNothingAgainstARebuild() {
		let rope = Self.makeRope(lines: 20_000)
		let folding = FoldingState()
		var layout = WrapLayout()

		let counts = Self.rowCounts(of: rope, columns: 120)
		let rebuild = PerformanceTests.cpuTime("wrap rebuild, 20,000 lines") {
			layout.rebuild(
				documentLineCount: rope.lineCount, columns: 120,
				folding: folding, documentRevision: 1
			) { line in line < counts.count ? Int(counts[line]) : 1 }
		}

		// A thousand scrolls, so the figure is above the clock's noise.
		let scrolls = PerformanceTests.cpuTime("wrap isCurrent x1000") {
			for _ in 0..<1000 {
				_ = layout.isCurrent(
					documentLineCount: rope.lineCount, columns: 120,
					folding: folding, documentRevision: 1
				)
			}
		}

		print(String(format: "PERF one scroll is %.0fx cheaper than a rebuild — %@",
			scrolls > 0 ? rebuild / (scrolls / 1000) : 0, MachineLoad.said))

		guard Stopwatch.maySay("PERF", "wrap scroll") else { return }
		// A scroll must be in a different class, not merely quicker. A hundred
		// of them should still cost less than one rebuild.
		#expect(scrolls / 100 < rebuild, "a scroll costs like a rebuild — \(MachineLoad.said)")
	}

	/// The rebuild path: one walk over the chunks against a descent per line.
	@Test func oneWalkBeatsALookupPerLine() {
		let rope = Self.makeRope(lines: 20_000)
		let lines = rope.lineCount

		let perLine = PerformanceTests.cpuTime("row counts, lineText per line") {
			var total = 0
			for line in 0..<lines {
				total += WrapLayout.rowCount(in: rope.lineText(line), columns: 120, tabWidth: 4)
			}
			_ = total
		}

		let oneWalk = PerformanceTests.cpuTime("row counts, one chunk walk") {
			var total = 0
			rope.forEachLine { total += WrapLayout.rowCount(in: $0, columns: 120, tabWidth: 4) }
			_ = total
		}

		print(String(format: "PERF one walk is %.1fx the per-line lookup — %@",
			oneWalk > 0 ? perLine / oneWalk : 0, MachineLoad.said))

		guard Stopwatch.maySay("PERF", "wrap row counts") else { return }
		#expect(oneWalk < perLine, "the walk is no cheaper than the descents — \(MachineLoad.said)")
	}
}

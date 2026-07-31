import Testing
import Foundation
@testable import IdeaiKit

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
		layout.rebuild(documentLineCount: lineCount, columns: columns, folding: folding) { line in
			widths[line] ?? 10
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

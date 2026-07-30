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

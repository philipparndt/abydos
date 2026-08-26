import Testing
import Foundation
@testable import AbydosKit

/// What a selection covers, as opposed to what it copies.
///
/// The copied text has never been wrong — `TerminalLine.text(in:)` has trimmed
/// trailing blanks since it was written — which is exactly why the fault
/// survived: nothing was incorrect, only unreadable. The highlight ran to the
/// right margin whatever the row said, because `columnRange` was handed
/// `cells.count`, the width of the grid, in place of the width of the text.
struct TerminalSelectionShapeTests {
	private func makeEmulator(rows: Int = 8, columns: Int = 80) -> TerminalEmulator {
		TerminalEmulator(rows: rows, columns: columns)
	}

	// MARK: - Where a row's text ends

	@Test func aRowMeasuresToItsLastCharacter() {
		let emulator = makeEmulator()
		emulator.write("hello world")
		#expect(emulator.screen[0].usedColumns == 11, "eleven characters in an eighty-column grid")
	}

	@Test func trailingSpacesAreNotText() {
		let emulator = makeEmulator()
		emulator.write("hi        ")
		#expect(emulator.screen[0].usedColumns == 2)
	}

	@Test func aRowNothingHasBeenWrittenToMeasuresZero() {
		let emulator = makeEmulator()
		emulator.write("something")
		#expect(emulator.screen[1].usedColumns == 0)
	}

	/// A cell holding a space *with a background colour* is painted, so it is
	/// there to be selected — which is what every other terminal does with a
	/// coloured bar drawn out of spaces.
	@Test func aSpaceCarryingABackgroundColourIsText() {
		let emulator = makeEmulator()
		// Red background, four spaces, back to normal.
		emulator.write("ab\u{1B}[41m    \u{1B}[0m")
		#expect(emulator.screen[0].usedColumns == 6, "the coloured spaces count")
	}

	/// The trailing cell of a wide glyph is not blank, so a row ending in an
	/// emoji measures to the end of it rather than to its middle.
	@Test func aWideGlyphMeasuresToItsFarSide() {
		let emulator = makeEmulator()
		emulator.write("ab😀")
		#expect(emulator.screen[0].usedColumns == 4, "two cells for the emoji")
	}

	// MARK: - The highlight stops there

	@Test func aShortRowInAWideWindowHighlightsOnlyItsText() {
		let emulator = makeEmulator()
		emulator.write("twelve chars")
		let line = emulator.screen[0]
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 1, column: 0)
		)
		#expect(line.usedColumns == 12)
		#expect(
			selection.columnRange(onRow: 0, columns: line.usedColumns) == 0..<12,
			"twelve columns, not eighty"
		)
	}

	@Test func theRowsBetweenTheEndsStopAtTheirOwnText() {
		let emulator = makeEmulator()
		emulator.write("first\r\nsecond row\r\nthird\r\nlast")
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 3, column: 4)
		)
		let widths = (0...3).map { row in
			selection.columnRange(onRow: row, columns: emulator.screen[row].usedColumns)
		}
		#expect(widths == [0..<5, 0..<10, 0..<5, 0..<4], "each row to the end of what it says")
	}

	/// The half that was never broken, and that has to stay exactly as it was.
	@Test func whatASelectionCopiesIsUnchanged() {
		let emulator = makeEmulator(rows: 4, columns: 20)
		emulator.write("one\r\ntwo\r\nthree")
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 2, column: 5)
		)
		#expect(emulator.screen.text(in: selection) == "one\ntwo\nthree")
	}

	// MARK: - A blank row in the middle

	@Test func aBlankRowBetweenTheEndsKeepsAMark() {
		let emulator = makeEmulator()
		emulator.write("first\r\n\r\nthird")
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 2, column: 5)
		)
		#expect(emulator.screen[1].usedColumns == 0)
		#expect(
			selection.columnRange(onRow: 1, columns: 0) == 0..<1,
			"a paragraph break should not look like the end of the selection"
		)
	}

	/// The ends are different: a last row reached at column zero has nothing in
	/// the selection and should show nothing.
	@Test func anEndRowWithNothingInItShowsNothing() {
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 2, column: 0)
		)
		#expect(selection.columnRange(onRow: 2, columns: 0) == nil)
		#expect(selection.columnRange(onRow: 2, columns: 40) == nil)
	}

	@Test func aFirstRowAnchoredPastItsTextShowsNothing() {
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 12),
			head: TerminalPosition(row: 2, column: 4)
		)
		#expect(selection.columnRange(onRow: 0, columns: 12) == nil)
	}

	// MARK: - The rectangle

	private func columns(_ emulator: TerminalEmulator) -> TerminalEmulator {
		// Eight rows of fixed-width output, the shape a block selection is for.
		for index in 0..<8 {
			emulator.write("name\(index)    value\(index)    tail\(index)\r\n")
		}
		return emulator
	}

	@Test func aBlockTakesTheSameColumnsFromEveryRow() {
		let emulator = columns(makeEmulator(rows: 10, columns: 40))
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 9),
			head: TerminalPosition(row: 7, column: 15),
			isBlock: true
		)
		for row in 0...7 {
			#expect(
				selection.columnRange(onRow: row, columns: emulator.screen[row].usedColumns) == 9..<15,
				"row \(row)"
			)
		}
		#expect(emulator.screen.text(in: selection) == (0...7).map { "value\($0)" }.joined(separator: "\n"))
	}

	/// A rectangle drawn over ragged output gives back what is on each row and
	/// no padding — which is the whole point of taking a column out of `ls -l`.
	@Test func aRowInsideABlockThatEndsEarlyContributesOnlyWhatItHas() {
		let emulator = makeEmulator(rows: 4, columns: 40)
		emulator.write("0123456789abcdefghij\r\n0123456789abcd\r\n0123456789abcdefghij")
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 10),
			head: TerminalPosition(row: 2, column: 30),
			isBlock: true
		)
		#expect(emulator.screen[1].usedColumns == 14)
		#expect(selection.columnRange(onRow: 1, columns: 14) == 10..<14, "four characters, no padding")
		#expect(emulator.screen.text(in: selection) == "abcdefghij\nabcd\nabcdefghij")
	}

	/// Dragging a rectangle right-to-left or bottom-to-top is the same
	/// rectangle: the columns come from the two ends, not from reading order.
	@Test func aBlockDraggedBackwardsIsTheSameRectangle() {
		let emulator = columns(makeEmulator(rows: 10, columns: 40))
		let forwards = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 9),
			head: TerminalPosition(row: 7, column: 15),
			isBlock: true
		)
		let backwards = TerminalSelection(
			anchor: TerminalPosition(row: 7, column: 15),
			head: TerminalPosition(row: 0, column: 9),
			isBlock: true
		)
		#expect(emulator.screen.text(in: forwards) == emulator.screen.text(in: backwards))
	}

	/// A block gets no mark on a row with nothing in its columns: its own
	/// requirement is what is there and no padding, and a mark at column 0 would
	/// sit on its own nowhere near the rectangle.
	@Test func aBlankRowInsideABlockIsNotMarked() {
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 10),
			head: TerminalPosition(row: 4, column: 18),
			isBlock: true
		)
		#expect(selection.columnRange(onRow: 2, columns: 0) == nil)
	}

	/// The scrollback fix-up moves both end points and has never known which
	/// kind of selection it is holding — which is the point of `isBlock` being a
	/// flag on the selection rather than a second type.
	@Test func aBlockSurvivesLinesFallingOffTheTop() {
		var selection = TerminalSelection(
			anchor: TerminalPosition(row: 12, column: 10),
			head: TerminalPosition(row: 19, column: 18),
			isBlock: true
		)
		let shift = 5
		selection.anchor.row -= shift
		selection.head.row -= shift
		#expect(selection.isBlock, "the kind rides along with the rows")
		#expect(selection.anchor.row == 7 && selection.head.row == 14)
		#expect(selection.columnRange(onRow: 10, columns: 40) == 10..<18)
	}

	// MARK: - Both engines

	/// The helpers are on `TerminalGridReading`, which both engines conform to,
	/// so there is one implementation and not two. This asks the same selection
	/// of a grid built by hand — the shape libghostty-vt presents — and of our
	/// own emulator's screen.
	@Test func bothEnginesAnswerTheSameWay() {
		let emulator = makeEmulator(rows: 4, columns: 40)
		emulator.write("alpha\r\nbeta\r\ngamma")

		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 2, column: 5)
		)
		let mirror = StandInGrid(lines: (0..<emulator.screen.totalLineCount).compactMap {
			emulator.screen.line(at: $0)
		})
		#expect(mirror.text(in: selection) == emulator.screen.text(in: selection))
		for row in 0...2 {
			let mine = emulator.screen.line(at: row)?.usedColumns
			#expect(mirror.line(at: row)?.usedColumns == mine, "row \(row)")
		}
	}
}

/// A grid that is nothing but rows, standing in for the other engine.
///
/// The point is the conformance: everything selection asks for is written in
/// terms of `line(at:)` and `totalLineCount`, so anything answering those gets
/// the same selection behaviour by construction rather than by being kept in
/// step.
private struct StandInGrid: TerminalGridReading {
	let lines: [TerminalLine]

	var rows: Int { lines.count }
	var columns: Int { lines.first?.cells.count ?? 0 }
	var totalLineCount: Int { lines.count }
	var scrollbackCount: Int { 0 }
	var discardedLineCount: Int { 0 }

	func line(at index: Int) -> TerminalLine? {
		lines.indices.contains(index) ? lines[index] : nil
	}
}

/// What deciding where a row's text ends costs on the redraw path.
///
/// **Opt in, like every other benchmark here**, and for the reason this one
/// learnt the hard way: it burns a second of busy CPU across its passes, and
/// this repository's suite carries a dozen tests that go red under load. Run
/// inside an ordinary `make test` it did not fail — it made *other* things
/// fail, seven of them, none of which had anything to do with selection.
///
///     ABYDOS_BENCH=1 xcrun swift test -c release --filter TerminalSelectionCost
///
/// Release, always. A debug build reports numbers around fifty times larger and
/// in a different order, and two rounds of "optimisation" were aimed at them
/// before anybody ran it in release.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ABYDOS_BENCH"] != nil))
struct TerminalSelectionCostTests {

	/// What deciding where a row's text ends costs on the redraw path.
	///
	/// `usedColumns` is a scan, and it runs once per visible row while a
	/// selection exists — where before there was no scan at all. The argument
	/// for not caching it on the line is that it is cheap, because it goes
	/// backwards and stops on the first cell of ordinary text. That is an
	/// argument; this is the number, with the machine load beside it because a
	/// figure without one cannot be told from a regression.
	///
	/// Asserts nothing. The pair is the point — the same frame's worth of rows
	/// asked the old way and the new — and a bound on either would be a test
	/// that fails on somebody else's afternoon.
	@Test func decidingWhereARowEndsIsCheapEnoughToDoWhileDrawing() {
		let rows = 40, columns = 200
		let emulator = TerminalEmulator(rows: rows, columns: columns)
		// The worst shape for this: every row short, so every scan walks back
		// over a long tail of blanks before it finds anything.
		for index in 0..<rows { emulator.write("row \(index)\r\n") }

		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: rows - 1, column: 4)
		)
		let grid = emulator.screen

		func frame(_ width: @escaping (TerminalLine) -> Int) -> Double {
			var best = Double.greatestFiniteMagnitude
			for _ in 0..<5 {
				let start = Date()
				var frames = 0
				while -start.timeIntervalSinceNow < 0.1 {
					var sum = 0
					for row in 0..<grid.totalLineCount {
						guard let line = grid.line(at: row) else { continue }
						sum += selection.columnRange(onRow: row, columns: width(line))?.count ?? 0
					}
					frames += 1
					_ = sum
				}
				best = min(best, -start.timeIntervalSinceNow / Double(frames))
			}
			return best
		}

		let before = frame { $0.cells.count }
		let after = frame { $0.usedColumns }
		print("BENCH selection geometry, \(rows) rows × \(columns) columns: "
			+ "\(String(format: "%.1f", before * 1_000_000)) µs/frame as it was, "
			+ "\(String(format: "%.1f", after * 1_000_000)) µs/frame stopping at the text  "
			+ "[\(MachineLoad.said)]")
	}
}

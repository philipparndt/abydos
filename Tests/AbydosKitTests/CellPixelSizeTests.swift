import Foundation
import Testing
@testable import AbydosKit

/// What a pane tells its program a cell is, in pixels.
///
/// The number `icat` sizes a whole picture from, and since 0397 it reaches the
/// program the moment it is worked out rather than waiting for the grid to
/// change — so an answer that is wrong for a moment is now an answer the
/// program acts on.
struct CellPixelSizeTests {
	@Test func theFirstScaleThatIsThereIsTheOneUsed() {
		let size = CellPixelSize.pixels(cellWidth: 8, cellHeight: 19, scales: [2, 1])
		#expect(size?.width == 16)
		#expect(size?.height == 38)
	}

	@Test func aScaleNobodyCanGiveIsSteppedPast() {
		let size = CellPixelSize.pixels(cellWidth: 8, cellHeight: 19, scales: [nil, 1])
		#expect(size?.width == 8)
		#expect(size?.height == 19)
	}

	/// A window that is not on a screen answers zero rather than nothing —
	/// which is what a display being woken, unplugged or moved between looks
	/// like from a view sitting on it. Falling through `??` that answer made a
	/// cell 0×0, and a cell of no pixels is a terminal saying it cannot show
	/// pictures at all: `icat` prints nothing and reserves nothing.
	@Test func aScaleOfZeroIsNotAScale() {
		let size = CellPixelSize.pixels(cellWidth: 8, cellHeight: 19, scales: [0, 2])
		#expect(size?.width == 16, "zero is skipped, not used")
		#expect(size?.height == 38)
	}

	@Test func aCellIsNeverReportedAsNoPixelsAtAll() {
		#expect(CellPixelSize.pixels(cellWidth: 8, cellHeight: 19, scales: [0]) == nil)
		#expect(CellPixelSize.pixels(cellWidth: 8, cellHeight: 19, scales: [nil]) == nil)
		#expect(CellPixelSize.pixels(cellWidth: 8, cellHeight: 19, scales: []) == nil)
		#expect(CellPixelSize.pixels(cellWidth: 0, cellHeight: 19, scales: [2]) == nil)
	}

	/// Nothing back means "leave what the program was told alone". The last
	/// answer was worked out on a screen that existed, and a pane that keeps it
	/// goes on drawing pictures at the size it drew them before.
	@Test func nothingBackLeavesTheProgramOnTheSizeItHad() {
		let terminal = PseudoTerminal()
		terminal.cellPixelSize = (width: 16, height: 38)
		if let size = CellPixelSize.pixels(cellWidth: 8, cellHeight: 19, scales: [0, nil]) {
			terminal.cellPixelSize = size
		}
		#expect(terminal.cellPixelSize == (width: 16, height: 38))
	}
}

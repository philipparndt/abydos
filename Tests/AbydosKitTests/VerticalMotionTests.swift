import Foundation
import Testing
@testable import AbydosKit

/// What ↑, ↓ and the page keys do to the caret's row, and what they do when
/// there is no row left to go to.
struct VerticalMotionTests {
	/// The ordinary case: one row nearer the top or the bottom.
	@Test func movesOneRowAtATime() {
		#expect(VerticalMotion.outcome(from: 5, by: -1, rows: 10) == .row(4))
		#expect(VerticalMotion.outcome(from: 5, by: 1, rows: 10) == .row(6))
	}

	/// The bug this was written for. Clamping the row put the caret back where
	/// it already was and the guard against a move of nothing then swallowed the
	/// keystroke, so ↑ on the first line and ↓ on the last did nothing at all.
	@Test func runsOffTheTopAndBottomToTheEdgesOfTheFile() {
		#expect(VerticalMotion.outcome(from: 0, by: -1, rows: 10) == .startOfDocument)
		#expect(VerticalMotion.outcome(from: 9, by: 1, rows: 10) == .endOfDocument)
	}

	/// A row inside the file is still a row, however close to the edge it is.
	@Test func staysOnTheRowsThatExist() {
		#expect(VerticalMotion.outcome(from: 1, by: -1, rows: 10) == .row(0))
		#expect(VerticalMotion.outcome(from: 8, by: 1, rows: 10) == .row(9))
	}

	/// Page Up and Page Down come through the same arithmetic with a screenful
	/// as the delta, so a page that overshoots lands on the edge of the file
	/// rather than on the first or last row — which is what Cocoa does.
	@Test func aPageThatOvershootsLandsOnTheEdge() {
		#expect(VerticalMotion.outcome(from: 2, by: -40, rows: 10) == .startOfDocument)
		#expect(VerticalMotion.outcome(from: 7, by: 40, rows: 10) == .endOfDocument)
		// A page that fits is still a page, not a jump to the edge.
		#expect(VerticalMotion.outcome(from: 50, by: -40, rows: 100) == .row(10))
		#expect(VerticalMotion.outcome(from: 50, by: 40, rows: 100) == .row(90))
	}

	/// A file of one row has both edges on it: ↑ goes to offset zero and ↓ to
	/// the end, and neither is a move to another row.
	@Test func aSingleRowHasBothEdgesOnIt() {
		#expect(VerticalMotion.outcome(from: 0, by: -1, rows: 1) == .startOfDocument)
		#expect(VerticalMotion.outcome(from: 0, by: 1, rows: 1) == .endOfDocument)
	}

	/// A layout that has not been built yet reports no rows at all. Running off
	/// it beats asking the view for row -1.
	@Test func anEmptyLayoutStillAnswers() {
		#expect(VerticalMotion.outcome(from: 0, by: 1, rows: 0) == .endOfDocument)
		#expect(VerticalMotion.outcome(from: 0, by: -1, rows: 0) == .startOfDocument)
	}

	/// Nothing asked for is nothing done, and that is the only way to get it.
	@Test func aDeltaOfNothingStays() {
		#expect(VerticalMotion.outcome(from: 4, by: 0, rows: 10) == .stay)
	}
}

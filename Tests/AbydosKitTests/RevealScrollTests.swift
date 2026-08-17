import CoreGraphics
import XCTest
@testable import AbydosKit

/// Putting a revealed place on screen: the pane that cannot be measured, the
/// place that is already showing, and the one off the side of a long line.
///
/// Item 533 is a search result that was "sometimes out of the screen", and the
/// reason it was *sometimes* is that the view asked this question of a pane that
/// had not been laid out yet — which no amount of waiting turns into a fact. The
/// arithmetic is here so that all three answers can be asked for without a
/// window, a main loop, or a turn count.
final class RevealScrollTests: XCTestCase {
	/// A pane 40 rows tall and 100 columns wide, scrolled to the top.
	private func pane(
		size: CGSize = CGSize(width: 1000, height: 800),
		offset: CGPoint = .zero,
		documentSize: CGSize = CGSize(width: 4000, height: 40_000),
		gutterWidth: CGFloat = 60,
		lineHeight: CGFloat = 20,
		characterWidth: CGFloat = 10,
		wraps: Bool = false
	) -> RevealScroll.Pane {
		RevealScroll.Pane(
			size: size,
			offset: offset,
			documentSize: documentSize,
			gutterWidth: gutterWidth,
			lineHeight: lineHeight,
			characterWidth: characterWidth,
			wraps: wraps
		)
	}

	// MARK: - Nothing to measure against

	/// The fault itself. A freshly opened document has not been given its size,
	/// and the view used to scroll anyway, to a number worked out from a height
	/// of zero: `max(0, y - 0 / 2)` is the line's own offset, which puts it at
	/// the very top of a pane that is about to become 800 points tall.
	func testSaysSoWhenThePaneHasNoHeight() {
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 70, y: 12_000),
				onScreenIn: pane(size: CGSize(width: 1000, height: 0), documentSize: .zero)
			),
			.notLaidOut
		)
	}

	func testSaysSoWhenThePaneIsNarrowerThanItsGutter() {
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 70, y: 12_000),
				onScreenIn: pane(size: CGSize(width: 40, height: 800))
			),
			.notLaidOut
		)
	}

	func testSaysSoBeforeTheFontHasBeenMeasured() {
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 70, y: 0),
				onScreenIn: pane(lineHeight: 0)
			),
			.notLaidOut
		)
	}

	/// The second half of the same state, and the one a height alone misses: the
	/// clip view has been given its size and the document view has not caught up,
	/// so the rows are still laid out for the pane's old width and centring on one
	/// of them centres on the wrong line. A document is never shorter than its
	/// viewport once it has been laid out for it.
	func testSaysSoWhileTheDocumentIsStillShorterThanThePane() {
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 70, y: 300),
				onScreenIn: pane(documentSize: CGSize(width: 1000, height: 400))
			),
			.notLaidOut
		)
	}

	// MARK: - Already on screen

	/// With item 529 the walk down a result list runs this on every ↓, so a match
	/// three lines below the last one must not move the view at all.
	func testLeavesAMatchAlreadyShowingWhereItIs() {
		XCTAssertEqual(
			RevealScroll.answer(bringing: CGPoint(x: 300, y: 400), onScreenIn: pane()),
			.stay
		)
	}

	func testCountsTheHalfLineAtEachEdgeAsOffScreen() {
		// Two rows from the bottom edge: the line under it is where the next ↓
		// goes, and a line drawn half off the edge is not one somebody can read.
		XCTAssertEqual(
			RevealScroll.answer(bringing: CGPoint(x: 300, y: 770), onScreenIn: pane()),
			.scroll(CGPoint(x: 0, y: 370))
		)
		// And the top edge, one row.
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 300, y: 1005),
				onScreenIn: pane(offset: CGPoint(x: 0, y: 1000))
			),
			.scroll(CGPoint(x: 0, y: 605))
		)
	}

	// MARK: - Vertical

	func testCentresALineFurtherDownTheFile() {
		XCTAssertEqual(
			RevealScroll.answer(bringing: CGPoint(x: 70, y: 12_000), onScreenIn: pane()),
			.scroll(CGPoint(x: 0, y: 11_600))
		)
	}

	func testDoesNotScrollAboveTheTopOfTheDocument() {
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 70, y: 40),
				onScreenIn: pane(offset: CGPoint(x: 0, y: 4000))
			),
			.scroll(CGPoint(x: 0, y: 0))
		)
	}

	func testDoesNotScrollPastTheEndOfTheDocument() {
		// The last line of a document 1000 points longer than the pane: centring
		// would ask for 39_600 and the furthest the pane can go is 39_200.
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 70, y: 40_000),
				onScreenIn: pane(documentSize: CGSize(width: 4000, height: 40_000))
			),
			.scroll(CGPoint(x: 0, y: 39_200))
		)
	}

	// MARK: - Horizontal

	/// The second fault of item 533, which was not a race: the offset was forced
	/// to zero on every reveal, so a match past the pane's width was scrolled off
	/// the side and stayed there.
	func testBringsInAMatchFarAlongALongLine() {
		// Column 300 of a pane 100 columns wide, at the top of the file.
		switch RevealScroll.answer(bringing: CGPoint(x: 3060, y: 200), onScreenIn: pane()) {
		case let .scroll(to):
			// Sixteen columns of context past the match, and the vertical offset
			// untouched because the line was already on screen.
			XCTAssertEqual(to.x, 2230)
			XCTAssertEqual(to.y, 0)
			// And it really is inside the text column afterwards.
			XCTAssertGreaterThan(3060, to.x + 60)
			XCTAssertLessThan(3060, to.x + 1000)
		default:
			XCTFail("a match 300 columns along a line is not visible in a pane 100 wide")
		}
	}

	/// Not "scroll to the column". A match inside the pane's width leaves the
	/// offset alone, so the start of its line stays where it is.
	func testLeavesTheOffsetAloneForAMatchTheEyeCanAlreadySee() {
		XCTAssertEqual(
			RevealScroll.answer(bringing: CGPoint(x: 860, y: 200), onScreenIn: pane()),
			.stay
		)
	}

	/// Scrolled right, then sent to a match at the start of a line: the offset
	/// has to come back or the match is off the left edge — and under the gutter
	/// counts as off it, because the gutter is drawn over the viewport's left
	/// edge rather than over the text.
	func testBringsBackALineStartHiddenUnderTheGutter() {
		switch RevealScroll.answer(
			bringing: CGPoint(x: 2100, y: 200),
			onScreenIn: pane(offset: CGPoint(x: 2060, y: 0))
		) {
		case let .scroll(to):
			XCTAssertEqual(to.x, 1880)
			XCTAssertGreaterThan(2100, to.x + 60)
		default:
			XCTFail("a point under the gutter is not on screen")
		}
	}

	func testDoesNotScrollPastTheLeftEdge() {
		switch RevealScroll.answer(
			bringing: CGPoint(x: 70, y: 200),
			onScreenIn: pane(offset: CGPoint(x: 400, y: 0))
		) {
		case let .scroll(to):
			XCTAssertEqual(to.x, 0)
		default:
			XCTFail("column one is not visible when the pane is scrolled right")
		}
	}

	func testDoesNotScrollPastTheRightEdgeOfTheDocument() {
		// The context past the match would ask for 2130 and the document only has
		// 2000 to give.
		switch RevealScroll.answer(
			bringing: CGPoint(x: 2960, y: 200),
			onScreenIn: pane(documentSize: CGSize(width: 3000, height: 40_000))
		) {
		case let .scroll(to):
			XCTAssertEqual(to.x, 2000)
		default:
			XCTFail("a match near the end of the longest line is not visible")
		}
	}

	// MARK: - Wrapped text

	/// Wrapped text is exactly as wide as the viewport: there is nowhere to
	/// scroll sideways, and an offset left over from before wrap was turned on
	/// belongs back at zero.
	func testKeepsWrappedTextAgainstTheLeftEdge() {
		switch RevealScroll.answer(
			bringing: CGPoint(x: 900, y: 200),
			onScreenIn: pane(
				offset: CGPoint(x: 300, y: 0),
				documentSize: CGSize(width: 1000, height: 40_000),
				wraps: true
			)
		) {
		case let .scroll(to):
			XCTAssertEqual(to, CGPoint(x: 0, y: 0))
		default:
			XCTFail("wrapped text scrolled sideways has somewhere to go back to")
		}
	}

	func testAsksForNothingWhenWrappedTextIsAlreadyShowing() {
		XCTAssertEqual(
			RevealScroll.answer(
				bringing: CGPoint(x: 900, y: 200),
				onScreenIn: pane(documentSize: CGSize(width: 1000, height: 40_000), wraps: true)
			),
			.stay
		)
	}
}

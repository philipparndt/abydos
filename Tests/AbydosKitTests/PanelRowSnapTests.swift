import CoreGraphics
import XCTest
@testable import AbydosKit

/// Rounding the terminal panel down to whole rows, and the states where it
/// must not.
///
/// The question is asked twice — once when the split reports a resize, and
/// again on the turn that would act on it — because between those two moments
/// the panel can become something this has no business moving.
final class PanelRowSnapTests: XCTestCase {
	private func state(
		isVisible: Bool = true,
		isMaximized: Bool = false,
		total: CGFloat = 1000,
		panelHeight: CGFloat = 260,
		remainder: CGFloat? = 3,
		dividerThickness: CGFloat = 1
	) -> PanelRowSnap.State {
		PanelRowSnap.State(
			isVisible: isVisible,
			isMaximized: isMaximized,
			total: total,
			panelHeight: panelHeight,
			remainder: remainder,
			dividerThickness: dividerThickness
		)
	}

	func testGivesTheRemainderBack() {
		// 260 tall with 3 points that are not a row: the panel is to keep 257,
		// and a divider one point thick means the position is 742 — a split
		// gives its second subview `total - position - thickness`, so 743 would
		// leave the panel 256.
		XCTAssertEqual(PanelRowSnap.dividerPosition(for: state()), 742)
	}

	/// **The bug the report was about.** Widening a window posts one resize
	/// notification after another, and each one asked this question again.
	/// Answering `total - wanted` left the panel a point short of whole rows,
	/// so the next remainder was nearly a whole row and the next pass took that
	/// off too: the terminal shed a row per notification down to its floor.
	/// Applying the answer has to end the matter.
	func testRoundingSettlesInOneStep() {
		let first = state()
		let position = try? XCTUnwrap(PanelRowSnap.dividerPosition(for: first))
		guard let position else { return }

		// What the split view does with that position, which is the step the
		// arithmetic used to leave out.
		let panel = first.total - position - first.dividerThickness
		XCTAssertEqual(panel, 257)

		// The terminal's usable height is now a whole number of rows, so there
		// is nothing left over and nothing more to do.
		let settled = state(panelHeight: panel, remainder: 0)
		XCTAssertNil(PanelRowSnap.dividerPosition(for: settled))
	}

	/// And the same claim without assuming the remainder went to zero: whatever
	/// is left over after one snap must be under the half point this ignores.
	func testWhatIsLeftOverAfterASnapIsNothingWorthMoving() {
		let rowHeight: CGFloat = 17
		for leftover in stride(from: 1.0, through: 16.0, by: 1.0) {
			let first = state(panelHeight: 300, remainder: CGFloat(leftover))
			guard let position = PanelRowSnap.dividerPosition(for: first) else { continue }
			let panel = first.total - position - first.dividerThickness
			XCTAssertEqual(panel, 300 - CGFloat(leftover), accuracy: 0.001)
			// A panel that is exactly `wanted` tall leaves a remainder of zero,
			// whatever the row height: the usable height was a multiple of it
			// before the point was lost, and now the point is not lost.
			let after = (panel - (300 - CGFloat(leftover))).truncatingRemainder(
				dividingBy: rowHeight
			)
			XCTAssertLessThan(abs(after), PanelRowSnap.smallestRemainder)
		}
	}

	/// The regression: a snap decided while the panel was at the bottom of the
	/// window, applied a turn later once the panel had been given the whole of
	/// it, put the editor back on screen while the window still thought the
	/// panel was maximised — and the panel kept the titlebar inset it wears up
	/// there, which is an empty band above the tabs.
	func testDecidesNothingOnceThePanelHasTheWholeWindow() {
		XCTAssertNil(PanelRowSnap.dividerPosition(for: state(isMaximized: true)))
		// Even with the whole window's height to divide, which is the shape the
		// stale answer had.
		XCTAssertNil(
			PanelRowSnap.dividerPosition(for: state(isMaximized: true, panelHeight: 996))
		)
	}

	func testDecidesNothingWhenThePanelIsPutAway() {
		XCTAssertNil(PanelRowSnap.dividerPosition(for: state(isVisible: false)))
	}

	/// A debugger or a profiler in the panel has no grid and no opinion about
	/// its height.
	func testDecidesNothingWithoutATerminal() {
		XCTAssertNil(PanelRowSnap.dividerPosition(for: state(remainder: nil)))
	}

	func testIgnoresRoundingNoise() {
		XCTAssertNil(PanelRowSnap.dividerPosition(for: state(remainder: 0.25)))
	}

	/// The window has not been laid out yet, so there is nothing to divide.
	func testWaitsForASplitWorthDividing() {
		XCTAssertNil(PanelRowSnap.dividerPosition(for: state(total: 180, panelHeight: 170)))
	}

	/// Shaving a row off to make the arithmetic tidy would be tidying the wrong
	/// thing: the panel has a floor.
	func testKeepsThePanelAboveItsFloor() {
		XCTAssertNil(PanelRowSnap.dividerPosition(for: state(panelHeight: 162, remainder: 3)))
		// 163 less its 3 leftover points is 160, the floor exactly, and the
		// divider goes one point higher than the height to leave room for
		// itself: 1000 - 160 - 1.
		XCTAssertEqual(PanelRowSnap.dividerPosition(for: state(panelHeight: 163, remainder: 3)), 839)
	}
}

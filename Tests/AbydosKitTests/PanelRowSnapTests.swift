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
		remainder: CGFloat? = 3
	) -> PanelRowSnap.State {
		PanelRowSnap.State(
			isVisible: isVisible,
			isMaximized: isMaximized,
			total: total,
			panelHeight: panelHeight,
			remainder: remainder
		)
	}

	func testGivesTheRemainderBack() {
		// 260 tall with 3 points that are not a row: the panel keeps 257, and
		// the divider is that far up from the bottom.
		XCTAssertEqual(PanelRowSnap.dividerPosition(for: state()), 743)
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
		XCTAssertEqual(PanelRowSnap.dividerPosition(for: state(panelHeight: 163, remainder: 3)), 840)
	}
}

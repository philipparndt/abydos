import Foundation
import Testing
@testable import AbydosKit

/// Which tabs a strip can actually offer, and how far it moves to show one.
///
/// The reported case is the panel's strip with sixteen terminals in it, all
/// called `Local`, six of them past the trailing edge with no way to reach them:
/// neither strip bounds its layout, neither takes a scroll wheel, and ⌘] and ⌘[
/// are the editor's.
struct TabOverflowTests {
	/// Ten tabs a hundred points wide, which is about what a panel tab is.
	private let widths: [CGFloat] = Array(repeating: 100, count: 10)

	@Test func nothingIsHiddenWhenTheyAllFit() {
		let overflow = TabOverflow.measure(widths: widths, available: 1000)
		#expect(overflow.visible == 0..<10)
		#expect(overflow.isOverflowing == false)
		#expect(overflow.hiddenCount == 0)
	}

	@Test func aTabThatFitsExactlyIsVisible() {
		let overflow = TabOverflow.measure(widths: widths, available: 500)
		#expect(overflow.visible == 0..<5)
		#expect(overflow.hiddenAfter == [5, 6, 7, 8, 9])
	}

	/// Half a tab under the session tag is not a target — it is a tab somebody
	/// clicks and misses.
	@Test func aTabUnderTheTrailingControlsIsHidden() {
		let overflow = TabOverflow.measure(widths: widths, available: 550)
		#expect(overflow.visible == 0..<5)
		#expect(overflow.hiddenCount == 5)
	}

	/// The available width is measured to where the controls' ground begins,
	/// not to the edge of the strip, which is the whole point of the previous
	/// claim.
	@Test func theControlsTakeTheirRoomOffTheAvailableWidth() {
		let toTheEdge = TabOverflow.measure(widths: widths, available: 800)
		let toTheControls = TabOverflow.measure(widths: widths, available: 800 - 220)
		#expect(toTheEdge.visible.count == 8)
		#expect(toTheControls.visible.count == 5)
	}

	@Test func tabsBeforeTheRunAreCountedToo() {
		let overflow = TabOverflow.measure(widths: widths, start: 4, available: 300)
		#expect(overflow.visible == 4..<7)
		#expect(overflow.hiddenBefore == [0, 1, 2, 3])
		#expect(overflow.hiddenAfter == [7, 8, 9])
		#expect(overflow.hiddenCount == 7)
	}

	/// A menu shows tabs in the order somebody knows them by, not in the order
	/// the strip's bookkeeping puts them.
	@Test func theHiddenAreListedInTabOrder() {
		let overflow = TabOverflow.measure(widths: widths, start: 4, available: 300)
		#expect(overflow.hidden == [0, 1, 2, 3, 7, 8, 9])
	}

	/// A window too narrow for even one tab still shows one. Reporting
	/// everything hidden would make the menu the only way to use the app.
	@Test func aStripTooNarrowForOneTabStillShowsIt() {
		let overflow = TabOverflow.measure(widths: widths, available: 20)
		#expect(overflow.visible == 0..<1)
		#expect(overflow.hiddenAfter.count == 9)
	}

	@Test func anEmptyStripHasNothingHidden() {
		let overflow = TabOverflow.measure(widths: [], available: 500)
		#expect(overflow.visible.isEmpty)
		#expect(overflow.isOverflowing == false)
	}

	@Test func spacingBetweenTabsCounts() {
		let tight = TabOverflow.measure(widths: widths, available: 500, spacing: 0)
		let spaced = TabOverflow.measure(widths: widths, available: 500, spacing: 10)
		#expect(tight.visible.count == 5)
		#expect(spaced.visible.count == 4)
	}

	// MARK: - Moving the run

	/// A strip that re-lays itself out on every selection is one whose tabs move
	/// under the pointer for no reason.
	@Test func aVisibleTabDoesNotMoveTheRun() {
		#expect(TabOverflow.start(showing: 2, widths: widths, from: 0, available: 500) == 0)
	}

	@Test func showingOneAheadMovesTheRunTheLeastThatFits() {
		// Five fit. Showing the sixth needs the run to start at one, and no
		// further: starting at two would hide a tab that was visible.
		#expect(TabOverflow.start(showing: 5, widths: widths, from: 0, available: 500) == 1)
		#expect(TabOverflow.start(showing: 9, widths: widths, from: 0, available: 500) == 5)
	}

	@Test func showingOneBehindStartsAtIt() {
		#expect(TabOverflow.start(showing: 1, widths: widths, from: 4, available: 300) == 1)
	}

	/// The move is the least one: what it chooses shows the tab, and one step
	/// less does not.
	@Test func theMoveIsTheLeastThatWorks() {
		let chosen = TabOverflow.start(showing: 7, widths: widths, from: 0, available: 500)
		let after = TabOverflow.measure(widths: widths, start: chosen, available: 500)
		#expect(after.visible.contains(7))

		let oneLess = TabOverflow.measure(widths: widths, start: chosen - 1, available: 500)
		#expect(!oneLess.visible.contains(7))
	}

	/// A strip too narrow for two tabs still gets to the one asked for.
	@Test func aVeryNarrowStripStillReachesTheTabAskedFor() {
		let chosen = TabOverflow.start(showing: 6, widths: widths, from: 0, available: 20)
		#expect(chosen == 6)
		#expect(TabOverflow.measure(widths: widths, start: chosen, available: 20).visible.contains(6))
	}

	@Test func askingForATabThatIsNotThereChangesNothing() {
		#expect(TabOverflow.start(showing: 99, widths: widths, from: 3, available: 500) == 3)
	}

	/// Tabs are not all the same width — a shell in a deep directory takes a
	/// third of the strip on its own, since a panel tab has no ceiling.
	@Test func tabsOfDifferentWidths() {
		let mixed: [CGFloat] = [96, 400, 96, 96, 300, 96]
		let overflow = TabOverflow.measure(widths: mixed, available: 600)
		#expect(overflow.visible == 0..<3)
		#expect(overflow.hiddenAfter == [3, 4, 5])

		let chosen = TabOverflow.start(showing: 4, widths: mixed, from: 0, available: 600)
		#expect(TabOverflow.measure(widths: mixed, start: chosen, available: 600).visible.contains(4))
	}
}

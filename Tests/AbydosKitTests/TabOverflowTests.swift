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

	// MARK: - Room that appears again

	/// **Reported: tabs close and the strip does not lay out again.** Eight tabs
	/// left, room for all of them, an empty half of the strip — and the chevron
	/// still offering five. The run moves forward when the active tab does not
	/// fit and nothing ever moved it back, so the space that appeared when tabs
	/// closed stayed unused and the tabs before the run stayed hidden.
	@Test func closingTabsBringsTheHiddenOnesBack() {
		// Thirteen tabs with room for eight: the run has been pushed forward.
		let many: [CGFloat] = Array(repeating: 100, count: 13)
		let pushed = TabOverflow.start(showing: 12, widths: many, from: 0, available: 800)
		#expect(TabOverflow.measure(widths: many, start: pushed, available: 800).hiddenBefore.count == 5)

		// Five of them close. Everything left fits, so nothing should be hidden.
		let fewer: [CGFloat] = Array(repeating: 100, count: 8)
		let settled = TabOverflow.settled(start: pushed, widths: fewer, available: 800)
		let after = TabOverflow.measure(widths: fewer, start: settled, available: 800)
		#expect(settled == 0)
		#expect(after.isOverflowing == false, "\(after.hiddenCount) still hidden with room for all of them")
	}

	/// The window gets wider, which is the same thing happening for a different
	/// reason.
	@Test func aWiderStripBringsThemBackToo() {
		let widths: [CGFloat] = Array(repeating: 100, count: 13)
		let pushed = TabOverflow.start(showing: 12, widths: widths, from: 0, available: 800)
		#expect(pushed > 0)

		let settled = TabOverflow.settled(start: pushed, widths: widths, available: 1400)
		#expect(TabOverflow.measure(widths: widths, start: settled, available: 1400).hiddenBefore.isEmpty)
	}

	/// **It only ever fills trailing space**, so it cannot move tabs under the
	/// pointer while somebody is using them: a run with tabs hidden after it has
	/// no space to fill, and settling leaves it exactly where it was.
	@Test func aRunWithMoreToComeIsLeftAlone() {
		let widths: [CGFloat] = Array(repeating: 100, count: 20)
		#expect(TabOverflow.settled(start: 5, widths: widths, available: 800) == 5)
		#expect(TabOverflow.settled(start: 0, widths: widths, available: 800) == 0)
	}

	/// And it pulls back only as far as the last tab allows, rather than all the
	/// way to the start — otherwise the tab somebody is on would go off the end.
	@Test func settlingStopsWhereTheLastTabWouldFallOff() {
		let widths: [CGFloat] = Array(repeating: 100, count: 13)
		let settled = TabOverflow.settled(start: 12, widths: widths, available: 800)
		let after = TabOverflow.measure(widths: widths, start: settled, available: 800)
		#expect(after.hiddenAfter.isEmpty, "the last tab must stay visible")
		#expect(settled == 5, "eight fit, so the run ends at the last tab")
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

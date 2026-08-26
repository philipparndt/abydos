import Foundation
import Testing

@testable import AbydosKit

/// The rule that stops an unsteady click emptying the clipboard.
///
/// The bug it is written against: tmux copies on selection, this app forwards
/// the window-activating click straight through to tmux, and a hand that moved
/// two pixels between press and release made tmux select nothing and copy that
/// nothing over the system clipboard. The next paste was empty.
@Suite struct ClickSlackTests {
	/// A cell as the terminal actually measures one: about twice as tall as wide.
	private let cellWidth: CGFloat = 7
	private let cellHeight: CGFloat = 16

	private func travelled(_ slack: inout ClickSlack, to point: CGPoint) -> Bool {
		slack.hasLeftTheSlack(at: point, cellWidth: cellWidth, cellHeight: cellHeight)
	}

	@Test func aClickThatDoesNotMoveIsNotADrag() {
		var slack = ClickSlack()
		slack.pressed(at: CGPoint(x: 100, y: 100))
		#expect(travelled(&slack, to: CGPoint(x: 100, y: 100)) == false)
	}

	@Test func aHandThatWobblesAFewPixelsIsStillClicking() {
		var slack = ClickSlack()
		slack.pressed(at: CGPoint(x: 100, y: 100))
		for wobble in [CGPoint(x: 102, y: 101), CGPoint(x: 98, y: 103), CGPoint(x: 103, y: 97)] {
			#expect(travelled(&slack, to: wobble) == false, "\(wobble) is inside one cell")
		}
	}

	@Test func acrossOneCellSidewaysIsADrag() {
		var slack = ClickSlack()
		slack.pressed(at: CGPoint(x: 100, y: 100))
		#expect(travelled(&slack, to: CGPoint(x: 107, y: 100)))
	}

	@Test func acrossOneCellDownwardsIsADrag() {
		var slack = ClickSlack()
		slack.pressed(at: CGPoint(x: 100, y: 100))
		#expect(travelled(&slack, to: CGPoint(x: 100, y: 84)))
	}

	/// The half that makes a selection usable rather than merely safe: a drag
	/// that has travelled goes on reporting when it comes back, so dragging out
	/// and back again does not stop dead half way.
	@Test func onceItHasTravelledItKeepsReporting() {
		var slack = ClickSlack()
		slack.pressed(at: CGPoint(x: 100, y: 100))
		#expect(travelled(&slack, to: CGPoint(x: 140, y: 100)))
		#expect(travelled(&slack, to: CGPoint(x: 101, y: 100)), "back near the press, still a drag")
		#expect(slack.isTravelling)
	}

	/// Each gesture is judged on its own. Without this, one real drag would
	/// leave every later click reporting immediately — which is the bug again.
	@Test func thenTheNextPressStartsWithItsSlackBack() {
		var slack = ClickSlack()
		slack.pressed(at: CGPoint(x: 100, y: 100))
		#expect(travelled(&slack, to: CGPoint(x: 140, y: 100)))
		slack.released()

		slack.pressed(at: CGPoint(x: 200, y: 200))
		#expect(travelled(&slack, to: CGPoint(x: 202, y: 201)) == false)
		#expect(slack.isTravelling == false)
	}

	/// A drag with no press behind it is reported rather than swallowed. The
	/// cost of being wrong the other way is a selection that never starts, and
	/// this object is not certain enough about a gesture it never saw begin.
	@Test func aDragWithNoPressIsLetThrough() {
		var slack = ClickSlack()
		#expect(travelled(&slack, to: CGPoint(x: 100, y: 100)))
	}

	/// A cell size of zero arrives while a view is being laid out, and would
	/// otherwise make every pixel a drag — the bug, exactly.
	@Test func aCellOfNoSizeStillGivesAPixelOfSlack() {
		var slack = ClickSlack()
		slack.pressed(at: CGPoint(x: 100, y: 100))
		#expect(
			slack.hasLeftTheSlack(
				at: CGPoint(x: 100.5, y: 100), cellWidth: 0, cellHeight: 0
			) == false
		)
	}
}

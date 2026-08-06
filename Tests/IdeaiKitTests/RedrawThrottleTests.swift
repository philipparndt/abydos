import Foundation
import Testing
@testable import IdeaiKit

/// The rule that decides whether a terminal which is behind should draw what it
/// has so far. What it exists to prevent is a screen flickering through its own
/// history: a locked screen stops the drawing and not the program, so a spinner
/// arrives as minutes of frames at once, and drawing each of them is over a
/// hundred pictures a second that were each replaced before anybody saw them.
struct RedrawThrottleTests {
	/// Caught up is always drawn, however recently the last one was: this is
	/// the final picture, and skipping it leaves the screen showing a step on
	/// the way to it.
	@Test func caughtUpAlwaysDraws() {
		#expect(RedrawThrottle.shouldDraw(isBehind: false, sinceLastDraw: 0))
		#expect(RedrawThrottle.shouldDraw(isBehind: false, sinceLastDraw: 0.001))
		#expect(RedrawThrottle.shouldDraw(isBehind: false, sinceLastDraw: 10))
	}

	/// Behind and drawn a moment ago: skip. Parsing carries on either way, so
	/// what is skipped is a picture and never any output.
	@Test func behindAndJustDrawnSkips() {
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0))
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0.008))
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0.049))
	}

	/// Behind for long enough still draws. A program producing output faster
	/// than it can be parsed would otherwise show nothing at all, and a build
	/// that appears frozen is worse than one that scrolls coarsely.
	@Test func behindForLongEnoughStillDraws() {
		#expect(RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0.05))
		#expect(RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 1))
	}

	/// Fast enough to follow, slow enough to see. The parse budget is 6 ms, so
	/// a backlog produced a picture about every eight — this is the number that
	/// turns that into something the eye can read.
	@Test func drawsAtAPaceAPersonCanSee() {
		#expect(RedrawThrottle.catchUpInterval >= 0.02)
		#expect(RedrawThrottle.catchUpInterval <= 0.1)

		// A minute of buffered spinner frames, drawn at this pace, is a couple
		// of dozen pictures rather than several thousand.
		let batchesPerSecond = 1.0 / 0.008
		let drawnPerSecond = 1.0 / RedrawThrottle.catchUpInterval
		#expect(drawnPerSecond < batchesPerSecond / 5)
	}
}

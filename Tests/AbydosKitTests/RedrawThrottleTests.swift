import Foundation
import Testing
@testable import AbydosKit

/// The rule that decides whether a terminal which is behind should draw what it
/// has so far. What it exists to prevent is a screen flickering through its own
/// history: a locked screen stops the drawing and not the program, so an agent's
/// spinner and clock arrive as minutes of frames at once, and drawing them is a
/// screen replaying time that has already passed.
struct RedrawThrottleTests {
	/// Caught up is always drawn, however recently the last one was: this is
	/// the final picture, and skipping it leaves the screen showing a step on
	/// the way to it.
	@Test func caughtUpAlwaysDraws() {
		#expect(RedrawThrottle.shouldDraw(isBehind: false, sinceLastDraw: 0, behindFor: 0))
		#expect(RedrawThrottle.shouldDraw(isBehind: false, sinceLastDraw: 0.001, behindFor: 5))
		#expect(RedrawThrottle.shouldDraw(isBehind: false, sinceLastDraw: 10, behindFor: 0))
	}

	/// A burst is not drawn at all while it drains, however long ago the last
	/// picture was. Every frame in it is one the program has already replaced —
	/// which is what made the clock in an agent's window race through the
	/// minutes it spent while the screen was locked.
	@Test func aBurstIsHeldUntilItDrains() {
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0, behindFor: 0))
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 1, behindFor: 0.05))
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 10, behindFor: 0.24))
	}

	/// Behind for longer than a burst lasts still gets a heartbeat: a build
	/// showing nothing at all looks frozen, and looking frozen is worse than a
	/// picture that only changes once a second.
	@Test func stillBehindGetsAHeartbeat() {
		#expect(RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 1, behindFor: 0.25))
		#expect(RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 2, behindFor: 3))
	}

	/// One a second and no more. Twenty was what made a backlog replay: each
	/// picture had already been replaced by the time it was drawn, so what
	/// somebody saw was an agent's clock racing through minutes it had spent
	/// while the screen was locked.
	@Test func theHeartbeatIsSlowEnoughNotToReplayAnything() {
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0.05, behindFor: 3))
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0.5, behindFor: 3))
		#expect(!RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 0.99, behindFor: 3))
		#expect(RedrawThrottle.shouldDraw(isBehind: true, sinceLastDraw: 1, behindFor: 3))
	}

	/// The numbers themselves, because both are chosen rather than derived and
	/// changing either changes what somebody sees.
	@Test func holdsABurstForAQuarterOfASecondAndThenBeatsOnceASecond() {
		#expect(RedrawThrottle.burstHoldOff == 0.25)
		#expect(RedrawThrottle.catchUpInterval == 1.0)
	}
}

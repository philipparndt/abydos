import Foundation
import Testing
@testable import AbydosKit

/// The rule that decides whether a terminal which is behind should draw what it
/// has so far. What it exists to prevent is a screen flickering through its own
/// history: a locked screen stops the drawing and not the program, so an agent's
/// spinner and clock arrive as minutes of frames at once, and drawing them is a
/// screen replaying time that has already passed.
///
/// What it must *not* do is stop drawing a program that is keeping up. Item 0491:
/// the rule used to be asked "is the queue empty", which against a program
/// writing as fast as it is read is permanently no — so the screen was held to
/// one frame a second while every frame it declined to draw was current. It is
/// asked how many seconds out of date the picture is instead.
struct RedrawThrottleTests {
	/// Current is always drawn, however recently the last one was: this is the
	/// final picture, and skipping it leaves the screen showing a step on the way
	/// to it.
	@Test func aCurrentPictureAlwaysDraws() {
		#expect(RedrawThrottle.shouldDraw(staleBy: 0, sinceLastDraw: 0, behindFor: 0))
		#expect(RedrawThrottle.shouldDraw(staleBy: 0, sinceLastDraw: 0.001, behindFor: 5))
		#expect(RedrawThrottle.shouldDraw(staleBy: 0, sinceLastDraw: 10, behindFor: 0))
	}

	/// The case this item is about, and the one the old rule got wrong. A program
	/// writing as fast as it is read leaves output queued at every instant — but
	/// the picture is milliseconds old, not seconds, so every frame of it is the
	/// program's own and gets drawn.
	@Test func aProgramKeepingUpDrawsEveryFrame() {
		// The queue is never empty and the last draw was one frame ago. Under the
		// old rule this was "behind", and the answer was no for a whole second.
		#expect(RedrawThrottle.shouldDraw(staleBy: 0.002, sinceLastDraw: 1.0 / 60, behindFor: 0))
		#expect(RedrawThrottle.shouldDraw(staleBy: 0.05, sinceLastDraw: 1.0 / 120, behindFor: 0))
		// Right up to the edge, including a queue that has been non-empty for
		// minutes: a build pouring output for five minutes is five minutes of
		// current pictures, not a backlog.
		#expect(RedrawThrottle.shouldDraw(staleBy: 0.24, sinceLastDraw: 0.001, behindFor: 300))
	}

	/// A burst is not drawn at all while it drains, however long ago the last
	/// picture was. Every frame in it is one the program has already replaced —
	/// which is what made the clock in an agent's window race through the
	/// minutes it spent while the screen was locked.
	@Test func aBurstIsHeldUntilItDrains() {
		#expect(!RedrawThrottle.shouldDraw(staleBy: 0.25, sinceLastDraw: 0, behindFor: 0))
		#expect(!RedrawThrottle.shouldDraw(staleBy: 12, sinceLastDraw: 1, behindFor: 0.05))
		#expect(!RedrawThrottle.shouldDraw(staleBy: 60, sinceLastDraw: 10, behindFor: 0.24))
	}

	/// Behind for longer than a burst lasts still gets a heartbeat: a build
	/// showing nothing at all looks frozen, and looking frozen is worse than a
	/// picture that only changes once a second.
	@Test func stillBehindGetsAHeartbeat() {
		#expect(RedrawThrottle.shouldDraw(staleBy: 0.3, sinceLastDraw: 1, behindFor: 0.25))
		#expect(RedrawThrottle.shouldDraw(staleBy: 40, sinceLastDraw: 2, behindFor: 3))
	}

	/// One a second and no more. Twenty was what made a backlog replay: each
	/// picture had already been replaced by the time it was drawn, so what
	/// somebody saw was an agent's clock racing through minutes it had spent
	/// while the screen was locked.
	@Test func theHeartbeatIsSlowEnoughNotToReplayAnything() {
		#expect(!RedrawThrottle.shouldDraw(staleBy: 30, sinceLastDraw: 0.05, behindFor: 3))
		#expect(!RedrawThrottle.shouldDraw(staleBy: 30, sinceLastDraw: 0.5, behindFor: 3))
		#expect(!RedrawThrottle.shouldDraw(staleBy: 30, sinceLastDraw: 0.99, behindFor: 3))
		#expect(RedrawThrottle.shouldDraw(staleBy: 30, sinceLastDraw: 1, behindFor: 3))
	}

	/// The numbers themselves, because all three are chosen rather than derived
	/// and changing any of them changes what somebody sees.
	@Test func aQuarterOfASecondIsCurrentAndABurstBeatsOnceASecond() {
		#expect(RedrawThrottle.liveWindow == 0.25)
		#expect(RedrawThrottle.burstHoldOff == 0.25)
		#expect(RedrawThrottle.catchUpInterval == 1.0)
	}
}

import Foundation

/// Whether a terminal that is behind should draw what it has so far.
///
/// Output is parsed in batches with a budget, so the screen can be drawn
/// between them rather than after all of it. That is right when the output is
/// arriving as it is produced, and wrong when there is a backlog: every batch
/// then paints a picture the program has already replaced, and what somebody
/// sees is not a program working but a screen flickering through its own
/// history — an agent's elapsed time sprinting through minutes it already
/// spent, a spinner spinning at a speed nothing ever spun at.
///
/// A backlog is not exotic. A locked screen stops the drawing and not the
/// program, so anything animating — a spinner, a progress bar, a log — arrives
/// as minutes of frames the moment the screen comes back.
///
/// So there are two ways to be behind, and they want opposite things:
///
/// A **burst** is a backlog with an end: whatever arrived while nobody was
/// looking. Every frame in it is stale, including the ones drawn twenty times a
/// second, and the only picture worth showing is the last one. Nothing is drawn
/// until it has drained.
///
/// A **flood** is a program producing output faster than it can be parsed, and
/// it has no end to wait for. Drawing nothing at all would leave a build
/// looking frozen, so once being behind has lasted longer than a burst would,
/// there is a heartbeat: one picture a second, which is enough to see that
/// something is happening and far too slow to replay anybody's afternoon.
///
/// The two cannot be told apart while they are happening — a minute of buffered
/// frames arrives from the kernel exactly as fast as a program that never stops
/// writing — so both are treated the same way, and the rate is chosen for what
/// it costs to be wrong. Being slow to show a flood costs a coarser picture of
/// a build; being fast to show a burst costs the flicker this exists to stop.
public enum RedrawThrottle {
	/// How often to draw while still behind.
	///
	/// Once a second, not twenty times: every one of those pictures has already
	/// been replaced by the time it is drawn, and drawing them in order is a
	/// screen replaying time that has already passed. One a second says the
	/// terminal is alive and working through a backlog without pretending the
	/// backlog is happening now.
	public static let catchUpInterval: TimeInterval = 1.0

	/// How long being behind is treated as a burst worth waiting out.
	///
	/// A quarter of a second: long enough to swallow the catch-up after a
	/// locked screen, an app switch or a scrolled-back pane, and short enough
	/// that a program which really is outrunning the parser starts showing
	/// progress before anybody wonders whether it has died.
	public static let burstHoldOff: TimeInterval = 0.25

	/// - Parameters:
	///   - isBehind: whether output is still waiting to be parsed.
	///   - sinceLastDraw: how long ago the screen was last drawn.
	///   - behindFor: how long there has been a backlog without a break.
	public static func shouldDraw(
		isBehind: Bool,
		sinceLastDraw: TimeInterval,
		behindFor: TimeInterval
	) -> Bool {
		// Caught up: this is the picture the program means.
		guard isBehind else { return true }

		// Still inside a burst: the frame being offered is one the program has
		// already replaced, and the one worth drawing comes when it drains.
		guard behindFor >= burstHoldOff else { return false }

		return sinceLastDraw >= catchUpInterval
	}
}

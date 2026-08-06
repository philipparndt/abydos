import Foundation

/// Whether a terminal that is behind should draw what it has so far.
///
/// Output is parsed in batches with a budget, so the screen can be drawn
/// between them rather than after all of it. That is right when the output is
/// arriving as it is produced, and wrong when there is a backlog: every batch
/// then paints a picture the program has already replaced, at whatever rate the
/// batches complete — well over a hundred a second — and what somebody sees is
/// not a program working but a screen flickering through its own history.
///
/// A backlog is not exotic. A locked screen stops the drawing and not the
/// program, so anything animating — a spinner, a progress bar, a log — arrives
/// as minutes of frames the moment the screen comes back.
///
/// The rule is: draw when caught up, and while behind draw no more often than a
/// person can see. Not "never while behind", because a program producing output
/// faster than it can be parsed would then never show anything at all, and a
/// build that appears frozen is worse than one that scrolls a little coarsely.
public enum RedrawThrottle {
	/// How often to draw while catching up. Twenty a second reads as motion
	/// rather than as flicker, and collapses a minute of buffered frames into
	/// something the eye can follow.
	public static let catchUpInterval: TimeInterval = 0.05

	/// - Parameters:
	///   - isBehind: whether output is still waiting to be parsed.
	///   - sinceLastDraw: how long ago the screen was last drawn.
	public static func shouldDraw(isBehind: Bool, sinceLastDraw: TimeInterval) -> Bool {
		guard isBehind else { return true }
		return sinceLastDraw >= catchUpInterval
	}
}

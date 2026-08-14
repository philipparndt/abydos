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
///
/// ## What "behind" means, and what it used to mean (item 0491)
///
/// It means **how many seconds out of date the picture is**: how long ago the
/// oldest delivery nobody has parsed yet came off the pty. It used to mean "the
/// queue is not empty", and that was wrong in a way that got worse the faster
/// the terminal became.
///
/// A program writing as fast as it is read leaves the queue non-empty for ever,
/// so the old question was permanently answered yes and the screen was
/// permanently held to one frame a second — while every frame it declined to
/// draw was current. What had been hiding it was slowness: before the parser was
/// fixed, the backlog reached its high-water mark, the reader was suspended, the
/// queue emptied, and the screen drew forty-three times a second *because the
/// parser could not keep up*. Making the parser four and a half times faster
/// took that away and the screen stopped. Two measured improvements were
/// reverted before the rule underneath them was read.
///
/// Seconds have no such coupling. A tenth of a second behind is a tenth of a
/// second behind whatever the parser costs, whichever pattern the program is
/// writing, and on whichever engine — which is the whole point of measuring the
/// thing somebody is complaining about rather than a proxy for it.
///
/// Two candidates lost, and both for the same reason:
///
/// - **Bytes behind.** Bytes are only staleness after dividing by a parse rate,
///   and that rate moves by a factor of ten between patterns and by four and a
///   half between releases of the parser. A byte threshold therefore means a
///   different number of seconds for every pattern and every build — which is
///   exactly the coupling that produced this fault.
/// - **Whether the queue is growing or shrinking.** It sounds like the right
///   question and it does not separate the two cases. A burst drains — its queue
///   *shrinks*, monotonically, and it is the case the hold-off exists for. A
///   program keeping up holds a queue that is flat or shrinking too. The sign of
///   the derivative puts both on the same side of the line, and it needs a
///   window to measure over while the decision has to be made every frame.
public enum RedrawThrottle {
	/// How far behind the picture may be and still count as the program's
	/// current picture.
	///
	/// A quarter of a second — the same number as `burstHoldOff` and for the same
	/// reason, so there is one figure to argue with rather than two. Under it,
	/// what is on the grid is what the program is saying now, give or take a few
	/// frames nobody can perceive, and it is drawn at whatever rate the display
	/// refreshes. Over it, the terminal is working through something that has
	/// already happened.
	///
	/// Not zero, and not one frame. The queue is normally non-empty — output
	/// arrives while the last of it is still being parsed — and a threshold
	/// tighter than the time it takes to read and parse one delivery would put
	/// a healthy terminal permanently on the wrong side of the line, which is the
	/// fault this replaces.
	public static let liveWindow: TimeInterval = 0.25

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
	///   - staleBy: how long ago the oldest delivery nobody has parsed yet came
	///     off the pty, in seconds. Zero when everything that arrived is parsed.
	///   - sinceLastDraw: how long ago the screen was last drawn.
	///   - behindFor: how long `staleBy` has been over `liveWindow` without a
	///     break.
	public static func shouldDraw(
		staleBy: TimeInterval,
		sinceLastDraw: TimeInterval,
		behindFor: TimeInterval
	) -> Bool {
		// Current: this is the picture the program means, whether or not more of
		// it is already on the way.
		guard staleBy >= liveWindow else { return true }

		// Still inside a burst: the frame being offered is one the program has
		// already replaced, and the one worth drawing comes when it drains.
		guard behindFor >= burstHoldOff else { return false }

		return sinceLastDraw >= catchUpInterval
	}
}

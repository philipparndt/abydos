import AppKit

/// An arc chasing its own tail: what a working Claude session looks like.
///
/// **Shared because it is the same fact drawn twice.** The tmux tab strip has
/// turned this for a working window since the badges were added — a still `⋯`
/// says "something is happening here" no more convincingly than a full stop
/// does, and a turning one says it across a room. The running-sessions list
/// drew the still `⋯` for the same state, one panel up, and was reported for
/// it: the pill counts a session as working, the row beside it looked asleep.
///
/// The phase is the caller's, because the two turn on their own timers over
/// their own rows: a strip redraws three badges, a list redraws the rows it is
/// showing, and neither wants the other's.
enum Spinner {
	/// Turned a twelfth of a turn at a time, which is fast enough to read as
	/// motion and slow enough that a screen full of them costs nothing.
	static let interval = 1.0 / 12

	/// How far round a phase is, in degrees. Thirty a step: twelve steps to the
	/// full turn, so the arc comes back to where it started every second.
	static func angle(phase: CGFloat) -> CGFloat { phase * 30 }

	/// An arc of 280 degrees — most of a circle, with the gap that makes the
	/// turning visible at all. A full circle turning looks like a full circle.
	static func draw(in rect: NSRect, phase: CGFloat, colour: NSColor) {
		let radius = rect.width / 2 - Theme.current.scaled(1.5)
		guard radius > 0 else { return }
		let start = angle(phase: phase)
		let arc = NSBezierPath()
		arc.appendArc(
			withCenter: NSPoint(x: rect.midX, y: rect.midY),
			radius: radius,
			startAngle: start,
			endAngle: start + 280
		)
		arc.lineWidth = Theme.current.scaled(1.6)
		arc.lineCapStyle = .round
		colour.setStroke()
		arc.stroke()
	}
}

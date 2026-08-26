import Foundation

/// How far a pointer may wander between press and release and still be a click.
///
/// **This exists because an unsteady click was emptying the clipboard.** tmux
/// with the mouse on copies whatever a drag selected, the moment the button
/// comes up. This app forwards the first click into an inactive window straight
/// through to the program — `acceptsFirstMouse` — so that clicking from
/// somewhere else onto a tmux pane selects that pane in one gesture rather than
/// two. Put those together and a hand that moves two pixels between pressing and
/// releasing sends tmux a drag: tmux enters copy mode, selects nothing, and on
/// release copies that nothing over the system clipboard. The next paste is
/// empty, and nothing on screen ever said why.
///
/// The fix is to say what everything with a pointer says: a press and a release
/// near the same place is a click, and a drag has to travel before it is one.
/// A terminal has an obvious unit to measure that in — a cell — so the pointer
/// is allowed a whole one in each direction before the program hears about a
/// drag at all.
///
/// **Waiting costs the selection nothing**, which is what makes a whole cell
/// safe rather than merely generous. The program was already told where the
/// button went down; it anchors the selection there. Suppressing the reports
/// that arrive before the pointer has gone anywhere only decides *when* the
/// selection starts, never where — so a drag that does travel still selects
/// from the character it was pressed on.
///
/// Held per gesture rather than per event: once a drag has travelled it stays a
/// drag, so bringing the pointer back towards where it started goes on
/// reporting. Deciding afresh on each event would make a selection dragged out
/// and back again stop dead half way.
public struct ClickSlack: Sendable {
	/// Where the button went down, in whatever coordinates the caller measures
	/// in. Only differences are taken, so which corner they are from does not
	/// matter — it only has to be the same corner both times.
	private var press: CGPoint?
	/// Set once the pointer has left the slack, and not unset until the next
	/// press.
	private var hasTravelled = false

	public init() {}

	/// A button went down. Anything before the next `hasLeftTheSlack` is a click.
	public mutating func pressed(at point: CGPoint) {
		press = point
		hasTravelled = false
	}

	/// The button came up, or the gesture was abandoned.
	public mutating func released() {
		press = nil
		hasTravelled = false
	}

	/// Whether the program should hear about this drag.
	///
	/// A cell in each direction, measured from the press. Not a radius: cells
	/// are about twice as tall as they are wide, and a circle would be stricter
	/// sideways than up, which is the opposite of what a wobbling hand does.
	public mutating func hasLeftTheSlack(
		at point: CGPoint, cellWidth: CGFloat, cellHeight: CGFloat
	) -> Bool {
		if hasTravelled { return true }
		guard let press else {
			// No press recorded — a drag this object never saw begin. Reporting
			// it is the old behaviour and the safe one: the alternative is
			// swallowing a real drag because of a press that went missing.
			return true
		}
		let travelled = abs(point.x - press.x) >= max(1, cellWidth)
			|| abs(point.y - press.y) >= max(1, cellHeight)
		if travelled { hasTravelled = true }
		return travelled
	}

	/// Whether this gesture has already been let through, without deciding
	/// anything. For reports that want to say what happened.
	public var isTravelling: Bool { hasTravelled }
}

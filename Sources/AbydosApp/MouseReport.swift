import AppKit
import AbydosKit

/// What each `otherMouse` event was, as it passes each view that could claim it.
///
/// **Written because "the side buttons do nothing" has two different causes and
/// a photograph cannot tell them apart.** A mouse whose driver maps its side
/// buttons to keystrokes sends no mouse event at all; a mouse that sends button
/// 3 which is then swallowed by the terminal sends one that nobody hears. The
/// first is not this program's to fix and the second is, and the difference is a
/// line saying whether anything arrived.
///
/// Off unless `--mouse` asked for it, and a `print` when it is on: this sits in
/// three mouse handlers, and a report that costs anything is a report that
/// changes what it is reporting on.
enum MouseReport {
	private(set) static var isOn = false

	static func enable() { isOn = true }

	/// One line per event, saying which button and what the layer could do with
	/// it. `tracking` is the terminal's question — whether the program has asked
	/// for mouse events — and is left out where it is not the question.
	static func say(_ where_: String, _ event: NSEvent, tracking: Bool? = nil) {
		guard isOn else { return }
		let purpose = MouseButtons.purpose(of: event.buttonNumber)
		print("MOUSE \(where_): button=\(event.buttonNumber) is=\(purpose)"
			+ (tracking.map { " tracking=\($0)" } ?? ""))
		fflush(stdout)
	}

	/// One line per wheel event, saying what arrived and what the terminal made
	/// of it. A trackpad and a wheel raise events of different shapes — a
	/// hundred small precise ones a second against one a notch — and which
	/// shape a run received is the first question when it scrolled too far, or
	/// not at all.
	static func wheel(_ event: NSEvent, steps: Int, forTheProgram: Bool) {
		guard isOn else { return }
		print(String(
			format: "WHEEL dy=%.2f precise=%@ phase=%d momentum=%d steps=%d program=%@",
			event.scrollingDeltaY, event.hasPreciseScrollingDeltas ? "yes" : "no",
			event.phase.rawValue, event.momentumPhase.rawValue, steps,
			forTheProgram ? "yes" : "no"))
		fflush(stdout)
	}
}

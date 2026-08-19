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
}

import AppKit
import AbydosKit

/// Says, once, that the engine somebody asked for could not start.
///
/// **A moment, not a state.** "You asked for libghostty-vt and it would not
/// start" is true at a point in time; "this pane is drawn by our own emulator"
/// is true afterwards and for as long as the pane lives. Conflating them makes
/// one of the two noisy or the other silent, so the tab carries the state and
/// this carries the moment.
///
/// Once per process, because the library either loads or does not: a sentence
/// per pane opened would be the same fact repeated by something that cannot
/// have changed.
enum EngineFallback {
	private static var said = false

	static func sayOnce() {
		guard !said else { return }
		said = true
		Toast.post(
			"libghostty-vt would not start",
			detail: "The panes you open are drawn by this app's own emulator instead. "
				+ "The setting is still on, and each pane says which engine drew it.",
			kind: .warning
		)
		DiagnosticLog.write("terminal: libghostty-vt asked for and not usable", to: "tmux")
	}

	/// Whether it has been said, for a driver to print.
	static var saidForTesting: Bool { said }
}

import AppKit
import AbydosKit

/// Names a motion the editor was asked for and does not have — once, and only
/// in a debug build.
///
/// **A key that moves the caret without Shift and does nothing with it has been
/// the same bug three times**: 0494 twice and 0495 once, each diagnosed by
/// somebody reading `doCommand`'s switch and noticing which name was absent.
/// The editor can say it instead.
///
/// **Only `move…` and `select…`, and that restriction is the whole design.**
/// `default:` as a whole has no bound worth quoting — `noop:` alone would drown
/// it — while these two families are fixed at compile time by AppKit, so the
/// noise has a ceiling that can be counted rather than hoped about. Against the
/// macOS 27.0 SDK on 2026-08-20: 43 declared, 39 handled, so **four** possible
/// lines for the life of a build, and only for a key somebody pressed.
///
/// The item that asked for this counted fourteen on 2026-08-16. Ten of them
/// have been taken since — the emacs motions and the paragraph ones among them
/// — which is the shape of thing this exists to keep visible.
///
/// Nothing prints until a key is pressed, so this finds no bug nobody triggers.
/// What it does is turn "this key does nothing, why?" into "this key does
/// nothing, and here is the selector nobody handled" — and **the drivers press
/// keys**: `--vertical-nav` and `--word-nav` sweep a corner of the keyboard, so
/// a debug run of either says what it swept up beside its own report.
enum UnhandledMotions {
	/// Said once each, for the life of the process. A held key repeats, and a
	/// line per repeat is the noise this is trying not to be.
	private static var said: Set<String> = []

	static func note(_ selector: Selector) {
		#if DEBUG
		let name = NSStringFromSelector(selector)
		guard name.hasPrefix("move") || name.hasPrefix("select") else { return }
		guard !said.contains(name) else { return }
		said.insert(name)
		DiagnosticLog.write("editor: nothing handles \(name)", to: "editor")
		#endif
	}

	/// What has been said so far, for a driver to print.
	static var reportForTesting: String {
		said.isEmpty ? "nothing unhandled has been pressed" : said.sorted().joined(separator: ", ")
	}
}

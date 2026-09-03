import AppKit

/// The window a palette lives in: a panel with no title, put away by Escape or
/// by losing the keyboard.
///
/// Shared rather than one per palette. The symbol palette had this class to
/// itself until the running-sessions list wanted the same window, and the two
/// things a palette's window has to do — answer Escape from inside a text
/// field, and go away when somebody clicks past it — are the same two things
/// in both. `cancelOperation` is the reason a subclass is needed at all: a
/// search field swallows Escape as "stop editing" and never passes it on, so
/// the window has to be asked instead of the field.
final class PalettePanel: NSPanel {
	/// A key the palette wants before the responder chain sees it. True when
	/// it took it.
	var onKey: ((NSEvent) -> Bool)?
	/// Escape, or the keyboard going elsewhere.
	var onResignKey: (() -> Void)?

	override var canBecomeKey: Bool { true }

	/// The app's theme rather than the machine's own appearance, applied every
	/// time the window is shown.
	///
	/// **A window's appearance and the app's theme are two different things.**
	/// Everything a palette draws comes from `Theme.current`, but the band
	/// across the top is the title bar's own material and a search field's
	/// bezel is a system control — both of which follow the *window's*
	/// appearance. Left unset it is whatever the Mac is in, so a light theme on
	/// a dark Mac came up with a dark strip over a light list, which is how this
	/// was reported. The popover next door had taken its appearance from the
	/// theme since the day it was written; these windows had not.
	///
	/// Here rather than in each palette, and on every showing rather than at
	/// construction: a palette keeps its window between openings and the theme
	/// can be changed while it is put away.
	override func orderFront(_ sender: Any?) {
		wearTheTheme()
		super.orderFront(sender)
	}

	override func makeKeyAndOrderFront(_ sender: Any?) {
		wearTheTheme()
		super.makeKeyAndOrderFront(sender)
	}

	private func wearTheTheme() {
		appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)
		backgroundColor = Theme.current.sidebarBackground
	}

	override func keyDown(with event: NSEvent) {
		guard onKey?(event) != true else { return }
		super.keyDown(with: event)
	}

	override func cancelOperation(_ sender: Any?) {
		onResignKey?()
	}

	override func resignKey() {
		super.resignKey()
		onResignKey?()
	}
}

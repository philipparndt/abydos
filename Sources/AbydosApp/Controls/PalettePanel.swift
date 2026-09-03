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

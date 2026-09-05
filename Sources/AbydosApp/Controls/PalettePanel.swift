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

	// MARK: - Where a palette stands

	/// How far below the parent's top edge a palette hangs.
	private static let drop: CGFloat = 120

	/// Centred horizontally on the window that opened it, near that window's
	/// top, and kept inside it — a window narrower than the list would
	/// otherwise be given a list hanging off both its edges.
	///
	/// **On the window, not the screen.** The running-sessions list was asked
	/// for "like Spotlight search", which is screen-centred; this app has more
	/// than one window and often more than one display, and a palette is opened
	/// *by* a window, from a key that window's menu answered. Screen-centred it
	/// would appear away from the window that asked for it whenever that window
	/// is not on the main display.
	///
	/// Here rather than in each palette because two of them now want exactly
	/// this — the running-sessions list and the switcher — and a second copy of
	/// the arithmetic is where the two start to differ. The symbol palette
	/// keeps its own: it is a wider window at a deeper drop, sized from the
	/// parent rather than from its rows, and folding that in would be changing
	/// where it stands rather than sharing where it stands.
	static func place(_ window: NSWindow, over parent: NSWindow, size: NSSize) {
		window.setContentSize(size)
		let frame = parent.frame
		let x = min(
			max(frame.minX, frame.midX - window.frame.width / 2),
			max(frame.minX, frame.maxX - window.frame.width)
		)
		window.setFrameOrigin(
			NSPoint(x: x, y: frame.maxY - window.frame.height - Theme.current.scaled(drop))
		)
	}

	/// A list that grew or shrank while somebody is reading it: the top edge
	/// stays where it is, so the rows under their eyes do not move.
	static func resize(_ window: NSWindow, to size: NSSize) {
		let top = window.frame.maxY
		window.setContentSize(size)
		window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
	}

	/// Where it sits against the window it was opened over, for a driven run to
	/// check that "centred, near the top" is what happened — one report for
	/// every palette, since they now share the placement it describes.
	static func placementForTesting(_ window: NSWindow?, over parent: NSWindow?) -> String {
		guard let window, window.isVisible else { return "not open" }
		guard let parent else { return "no window" }
		let mine = window.frame, theirs = parent.frame
		// `inside` as well as `centred`, because on a window narrower than the
		// list the two answers differ and the one that matters is the second.
		// It means what the placement promises: the palette's leading edge is
		// not outside the window's, and its trailing edge is not either unless
		// the palette is simply wider than the window — which is one edge
		// overhanging rather than the two a centred placement would give.
		return String(
			format: "%.0f×%.0f centred=%@ inside=%@ offTop=%.0f",
			mine.width, mine.height,
			abs(mine.midX - theirs.midX) < 2 ? "yes" : "no",
			mine.minX >= theirs.minX - 1 && (mine.maxX <= theirs.maxX + 1 || mine.width > theirs.width)
				? "yes" : "no",
			theirs.maxY - mine.maxY
		)
	}
}

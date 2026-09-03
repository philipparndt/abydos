import AppKit
import AbydosKit

/// The two ways the running-sessions list is put on screen, from the outside.
///
/// One list, two hosts: the popover the pill hangs it from, and the palette a
/// key opens. Everything above them — the register, the reach, what a row does
/// — is written once against this.
@MainActor
protocol RunningSessionsHost: AnyObject {
	var isShown: Bool { get }
	/// Reads the register again. Called once a second while anything works, so
	/// a row cannot go stale under the pointer.
	func reload()
	func close()

	func typeFilterForTesting(_ text: String)
	func visibleRowsForTesting() -> String
	func chooseFirstForTesting() -> String
	func pressForTesting(_ key: String) -> String
}

/// The running-sessions list in a window of its own, centred over the window
/// that opened it — what ⇧⌘A puts up.
///
/// **Centred on the window, not the screen.** It was asked for "like Spotlight
/// search", which is screen-centred; this app has more than one window and
/// often more than one display, and the list is opened *by a window*, from a
/// key that window's menu answered. Screen-centred, it would appear away from
/// the window that asked for it whenever that window is not on the main
/// display. `SymbolPalette` settled this the same way, and this follows it
/// rather than inventing a second geometry.
///
/// The controller inside is the popover's, unchanged: the filter, the rows, the
/// arrows, ⏎ and Escape are one implementation with two windows around it.
@MainActor
final class RunningSessionsPalette: RunningSessionsHost {
	private let controller: RunningSessionsController
	private var window: PalettePanel?

	init(
		firstSlugs: @escaping () -> [String],
		reach: @escaping (RunningSessions.Session) -> SessionReach,
		onChoose: @escaping (RunningSessions.Session) -> Void
	) {
		// No shortcut in the corner: whoever is looking at this pressed it.
		controller = RunningSessionsController(firstSlugs: firstSlugs, reach: reach)
		controller.onChoose = { [weak self] session in
			self?.close()
			onChoose(session)
		}
		controller.onResize = { [weak self] size in self?.resize(to: size) }
		controller.onEscape = { [weak self] in self?.close() }
	}

	var isShown: Bool { window?.isVisible == true }

	func reload() { controller.reload() }

	/// Puts it up over the given window, or brings it back to the front if it
	/// is already up — pressing the key twice is not two lists.
	func show(over parent: NSWindow?) {
		guard let parent else { return }
		let window = self.window ?? makeWindow()
		self.window = window
		// The window wears the theme itself, on every showing — see
		// `PalettePanel`. What is left here is the ground the list is drawn on,
		// which is set when the view is made and the view is made once.
		controller.applyTheme()
		// A fresh opening is where a fresh order is free; while it is open the
		// order is held — see `RunningSessionsListView.placeOfSession`.
		controller.freezeOrderAgain()
		controller.reload()
		place(window, over: parent)
		parent.addChildWindow(window, ordered: .above)
		// The keyboard only if the app already has it: opening this is an
		// answer to a keystroke, so it always does in use, and never does in a
		// capture run — where taking it would take it from somebody's terminal.
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
			// The window is kept between openings, so nothing about its
			// appearing puts the caret back in the filter on the second one.
			controller.focusFilter()
		} else {
			window.orderFront(nil)
		}
	}

	func close() {
		guard let window, window.isVisible else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
	}

	private func makeWindow() -> PalettePanel {
		let window = PalettePanel(
			contentRect: NSRect(origin: .zero, size: controller.wantedSize),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: true
		)
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.isMovableByWindowBackground = true
		window.contentViewController = controller
		window.onResignKey = { [weak self] in self?.close() }
		// The key that opened it, pressed again, puts it away — which the menu
		// item cannot do from here. A child window's responder chain does not
		// run through its parent, so while this panel has the keyboard nothing
		// in it answers `showRunningSessions(_:)`, the item is disabled, and
		// the menu lets the keystroke through to this window instead. That is
		// where it is caught.
		window.onKey = { [weak self] event in
			guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
			      event.charactersIgnoringModifiers?.lowercased() == "a"
			else { return false }
			self?.close()
			return true
		}
		return window
	}

	/// Centred horizontally on the parent, near its top, and kept inside it:
	/// a window narrower than the list would otherwise be given a list hanging
	/// off both its edges.
	private func place(_ window: NSWindow, over parent: NSWindow) {
		let size = controller.wantedSize
		window.setContentSize(size)
		let frame = parent.frame
		let x = min(
			max(frame.minX, frame.midX - window.frame.width / 2),
			max(frame.minX, frame.maxX - window.frame.width)
		)
		window.setFrameOrigin(NSPoint(x: x, y: frame.maxY - window.frame.height - Theme.current.scaled(120)))
	}

	/// A session appearing or ending changes how tall the list wants to be.
	/// The top edge stays where it is, so the rows somebody is reading do not
	/// move under them.
	private func resize(to size: NSSize) {
		guard let window, window.isVisible else { return }
		let top = window.frame.maxY
		window.setContentSize(size)
		window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
	}

	// MARK: - For the harness

	func typeFilterForTesting(_ text: String) { controller.typeFilterForTesting(text) }
	func visibleRowsForTesting() -> String { controller.visibleRowsForTesting() }
	func chooseFirstForTesting() -> String { controller.chooseFirstForTesting() }
	func pressForTesting(_ key: String) -> String { controller.pressForTesting(key) }

	/// Where it sits against the window it was opened over, for a run to check
	/// that "centred, near the top" is what happened.
	func placementForTesting(over parent: NSWindow?) -> String {
		guard let window, window.isVisible else { return "not open" }
		guard let parent else { return "no window" }
		let mine = window.frame, theirs = parent.frame
		return String(
			format: "%.0f×%.0f centred=%@ offTop=%.0f",
			mine.width, mine.height,
			abs(mine.midX - theirs.midX) < 2 ? "yes" : "no",
			theirs.maxY - mine.maxY
		)
	}
}

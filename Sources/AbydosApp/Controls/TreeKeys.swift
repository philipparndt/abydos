import AppKit

/// Clicking and keying a tree the way a person does, for a driven run.
///
/// **The one runner four trees share**, so the claim "click a row, then press
/// ↓, and the selection moves" is asked of each of them the same way. The log
/// page's file list wrote this for itself when its list did not take the
/// keyboard on a click, and found two instruments broken before the fault: a
/// synthesised `mouseDown` handed to the view selects nothing, because a
/// table's `mouseDown` runs a tracking loop waiting for the release that never
/// comes; and an arrow event with no characters moves nothing, because a table
/// maps arrows through the key-binding manager by what the key *produced*.
/// Both lessons are in here once.
enum TreeKeys {
	/// Clicks the middle of a row, through our own window's event dispatch.
	///
	/// **Never through the system event tap.** The first instrument posted a
	/// press and a release at screen coordinates with `CGEvent`, and they went
	/// to whichever window was frontmost — which in a driven run is the
	/// terminal the run was started from, not the window being driven. Three
	/// trees reported the keyboard in a `TerminalView` and nothing selected,
	/// and a click had landed in somebody's shell. The house rule about
	/// guarding every launch is about exactly this.
	///
	/// A table's `mouseDown` runs a tracking loop that asks the window for the
	/// release, so the release is queued *first*, on the app's own event queue,
	/// and the press is then handed to the window: the loop finds its release
	/// waiting and the row is selected, with the keyboard wherever a real click
	/// would have put it.
	static func click(row: Int, in outline: NSOutlineView) -> String {
		guard row < outline.numberOfRows else { return "click\(row) no such row" }
		guard let window = outline.window else { return "click\(row) no window" }
		let rect = outline.rect(ofRow: row)
		let inWindow = outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
		func event(_ type: NSEvent.EventType) -> NSEvent? {
			NSEvent.mouseEvent(
				with: type, location: inWindow, modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber, context: nil,
				eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
			)
		}
		guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else {
			return "click\(row) no event"
		}
		// Ours to activate: a press on a window that is not key is an
		// activating click, which AppKit swallows unless the view under it
		// accepts first mouse — and a table does not. The driven window is the
		// app's own, so bringing it forward is not the fault the house rule
		// about launches guards against.
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		// What is actually under the point, said in the report: a click that
		// lands on another view is the instrument missing, not the tree
		// failing, and the two read the same without this.
		let under = window.contentView?.hitTest(inWindow).map { String(describing: type(of: $0)) } ?? "nothing"
		NSApp.postEvent(up, atStart: false)
		window.sendEvent(down)
		// The release is taken by the tracking loop; anything it queued for
		// afterwards — the selection change notification — wants a turn.
		RunLoop.current.run(until: Date().addingTimeInterval(0.2))
		return "click\(row) on \(under) at (\(Int(inWindow.x)),\(Int(inWindow.y)))"
	}

	/// The four arrows by name, with the characters a table's key bindings read.
	static func arrow(_ name: String) -> (code: UInt16, scalar: UnicodeScalar)? {
		switch name {
		case "up": return (126, UnicodeScalar(0xF700)!)
		case "down": return (125, UnicodeScalar(0xF701)!)
		case "left": return (123, UnicodeScalar(0xF702)!)
		case "right": return (124, UnicodeScalar(0xF703)!)
		default: return nil
		}
	}

	/// Presses one key on the view that has the keyboard — not on the tree,
	/// which is the whole question a click-then-arrow step asks.
	static func press(_ code: UInt16, _ scalar: UnicodeScalar, in window: NSWindow?) {
		let characters = String(Character(scalar))
		guard let window, let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: .function,
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window.windowNumber, context: nil,
			characters: characters, charactersIgnoringModifiers: characters,
			isARepeat: false, keyCode: code
		) else { return }
		(window.firstResponder ?? window).keyDown(with: event)
	}

	/// Who has the keyboard, by type, so a report can say "the tree" or "the
	/// window" rather than an address.
	static func keyboardHolder(in window: NSWindow?) -> String {
		window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nobody"
	}
}

import AppKit
import AbydosKit

/// The settings sidebar's table, so the arrow keys fold as well as move.
///
/// An `NSOutlineView` has this behaviour for nothing, and this list is
/// deliberately not one (0421): two levels over a flat array is a list somebody
/// can see all of, and the depth is drawn by the row. What an outline view has
/// that is worth keeping is what hands already expect from one — right opens,
/// left closes, and the row you land on is the one you would have clicked. So
/// that is the part written out, and only that part: up and down go to
/// `super`, where the table walks the rows that are showing.
final class SettingsSidebarTable: NSTableView {
	/// Asked what a sideways arrow should do; answers whether it did anything,
	/// so a key that means nothing here is still the table's to refuse.
	var onFold: ((SettingsOutline.Fold) -> Bool)?

	override func keyDown(with event: NSEvent) {
		let pressed = event.charactersIgnoringModifiers?.unicodeScalars.first.map { Int($0.value) }
		let key: SettingsOutline.Fold? = switch pressed {
		case NSRightArrowFunctionKey: .open
		case NSLeftArrowFunctionKey: .close
		default: nil
		}
		guard let key, onFold?(key) == true else {
			super.keyDown(with: event)
			return
		}
	}
}

/// Top-down coordinates, so a stack in a scroll view starts at the top. Beside
/// the sidebar table because both are the settings page's small furniture, moved
/// out when the page reached the length aim.
final class FlippedContainer: NSView {
	override var isFlipped: Bool { true }
}

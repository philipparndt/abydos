import AppKit
import AbydosKit

/// Tree that reports Return and double-click, for stage/unstage.
///
/// Left and right arrows are left to `NSOutlineView`, which already folds and
/// unfolds with them — the keyboard expansion the navigator has, for nothing.
final class ChangesOutlineView: NSOutlineView {
	/// The row under the pointer for a click, and -1 from the keyboard, where
	/// the selection is what counts rather than any one row.
	var onActivate: ((Int) -> Void)?

	/// A click from an inactive window lands on the row rather than being spent
	/// activating the app, as the branches tree and the project tree do.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	/// The editor's tab strip draws which tab holds the keyboard, and AppKit
	/// posts nothing when the first responder changes.
	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		// 36 is Return, 76 the numeric keypad's.
		if event.keyCode == 36 || event.keyCode == 76 {
			onActivate?(-1)
			return
		}
		super.keyDown(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?(clickedRow) }
	}
}

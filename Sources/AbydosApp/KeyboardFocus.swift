import AppKit

extension Notification.Name {
	/// The keyboard moved from one view to another.
	///
	/// AppKit posts nothing when the first responder changes, and two things on
	/// screen need to know: the tab strips, which mark the tab the cursor is in
	/// with a coloured line and the rest with a plain one. Without a signal they
	/// would keep whatever they last drew, and both strips would claim the
	/// keyboard at once.
	static let keyboardFocusChanged = Notification.Name("AbydosKeyboardFocusChanged")
}

/// Says the keyboard has moved, for anything that draws which pane holds it.
@MainActor func announceKeyboardFocusChange() {
	// After the change, not during it: `becomeFirstResponder` is called before
	// the window's `firstResponder` is the new view, so a strip asking now
	// would be told about the view that is on its way out.
	DispatchQueue.main.async {
		NotificationCenter.default.post(name: .keyboardFocusChanged, object: nil)
	}
}

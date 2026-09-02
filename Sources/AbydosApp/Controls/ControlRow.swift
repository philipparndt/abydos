import AppKit

/// A row of drawn controls beside a field, at the field's height.
enum ControlRow {
	/// Ties every control's height to the field's.
	///
	/// Left to themselves the controls measure themselves — a glyph button
	/// at its square, a text button at its line plus padding, a checkbox at
	/// its box — and the commit page's message area came out at four heights
	/// in two rows, which is what "chaotic" meant when it was reported. The
	/// field is the one with a designed height and the one that follows the
	/// zoom, so the rest take theirs from it. A glyph button stays square,
	/// since a 20-by-26 chevron is a tab.
	static func matchHeights(to field: NSView, of controls: [NSView]) {
		for control in controls {
			control.translatesAutoresizingMaskIntoConstraints = false
			control.heightAnchor.constraint(equalTo: field.heightAnchor).isActive = true
			if let button = control as? DrawnButton, button.image != nil {
				button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true
			}
		}
	}
}

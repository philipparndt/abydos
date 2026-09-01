import AppKit
import AbydosKit

/// A search field that follows the zoom.
///
/// **The library's one *measured* member, and the distinction is deliberate.**
/// Everything else here draws itself, because a bezel has a largest size and
/// the words inside it do not. A search field is the case where that trade goes
/// the other way: `NSSearchField` carries the field editor, the cancel button,
/// the recents menu, the ⌘F responder behaviour and a decade of text-editing
/// keys, and none of that is worth reimplementing to fix a font size.
///
/// So the field is kept and *given* its metrics: the theme's font, and a height
/// from the same arithmetic the drawn controls use. Its rounded bezel is one of
/// the few AppKit draws to the bounds it is given rather than to `controlSize`,
/// which is why this works here and would not work for a push button.
///
/// A new member of this library is one or the other, and which it is belongs
/// where it is defined — the two camps are only useful while they are stated.
final class ScaledSearchField: NSSearchField, ScaleFollowing {
	/// The design-time size of what is typed into it.
	private let fontSize: CGFloat

	private var heightConstraint: NSLayoutConstraint?

	init(placeholder: String, fontSize: CGFloat = 12) {
		self.fontSize = fontSize
		super.init(frame: .zero)
		placeholderString = placeholder
		focusRingType = .none
		translatesAutoresizingMaskIntoConstraints = false
		let height = heightAnchor.constraint(equalToConstant: 0)
		height.isActive = true
		heightConstraint = height
		applyTheme()
		ScaledControls.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func applyTheme() {
		let font = Theme.current.uiFont(fontSize)
		self.font = font
		// The height from the measured line, not from a constant: the point of
		// the library is that one place decides how tall a control holding one
		// line of text is, and a search field is one.
		heightConstraint?.constant = ControlMetrics.height(
			lineHeight: ceil(NSAttributedString(
				string: "Hg", attributes: [.font: font]
			).size().height),
			scale: Theme.current.scale
		)
		// The placeholder takes the cell's font at the moment it is set, so a
		// field whose font has changed keeps the old placeholder size until it
		// is set again — which reads as the one bit of the field that did not
		// follow.
		let placeholder = placeholderString
		placeholderString = nil
		placeholderString = placeholder
		needsDisplay = true
	}
}

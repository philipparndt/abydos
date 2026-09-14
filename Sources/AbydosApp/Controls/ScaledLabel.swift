import AppKit
import AbydosKit

/// A label whose type follows the zoom.
///
/// **The same fault as the buttons, one row along.** A label is built with
/// `Theme.current.uiFont(11)`, which is right at the zoom in force when the
/// pane was made and wrong at every other one. It is invisible until it sits
/// beside a control that *does* follow — and fixing the buttons without fixing
/// the words beside them would have made these panes look worse than they did,
/// which is the sort of half-sweep that gets a change reverted.
///
/// A *measured* member, like the search field: `NSTextField` carries selection,
/// accessibility and the whole of text layout, and none of that is worth
/// redrawing for a font size.
final class ScaledLabel: NSTextField, ScaleFollowing {
	private let fontSize: CGFloat
	private let weight: NSFont.Weight
	private let colour: () -> NSColor
	private let fixedDigits: Bool

	/// - Parameter fixedDigits: every digit the same width, for a label that
	///   counts — a clock redrawn thirty times a second in proportional
	///   figures changes width with every tick and shoves whatever sits beside
	///   it back and forth.
	init(
		_ text: String = "",
		size: CGFloat = 11,
		weight: NSFont.Weight = .regular,
		fixedDigits: Bool = false,
		colour: @escaping () -> NSColor = { Theme.current.sidebarText }
	) {
		fontSize = size
		self.weight = weight
		self.fixedDigits = fixedDigits
		self.colour = colour
		super.init(frame: .zero)
		stringValue = text
		isEditable = false
		isBordered = false
		isSelectable = false
		drawsBackground = false
		applyTheme()
		ScaledControls.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// The colour is taken from a closure rather than stored, for the reason
	/// everything else here is: a stored colour is a palette change that did
	/// not arrive.
	func applyTheme() {
		let base = Theme.current.uiFont(fontSize, weight: weight)
		if fixedDigits {
			// The app's own face with tabular figures, rather than the system's
			// monospaced-digit face: the label keeps the type everything around
			// it has.
			let descriptor = base.fontDescriptor.addingAttributes([
				.featureSettings: [[
					NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
					NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
				]],
			])
			font = NSFont(descriptor: descriptor, size: base.pointSize) ?? base
		} else {
			font = base
		}
		textColor = colour()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}
}

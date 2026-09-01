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

	init(
		_ text: String = "",
		size: CGFloat = 11,
		weight: NSFont.Weight = .regular,
		colour: @escaping () -> NSColor = { Theme.current.sidebarText }
	) {
		fontSize = size
		self.weight = weight
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
		font = Theme.current.uiFont(fontSize, weight: weight)
		textColor = colour()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}
}

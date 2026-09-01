import AppKit
import AbydosKit

/// A checkbox in the app's own type, drawn rather than bezelled.
///
/// A system checkbox has the same wall every other bezel has: its box is
/// artwork at one of four sizes, so at a large zoom `Hide read` and `Whole
/// file` sat as 14-point squares beside 24-point words. That is the pull-request
/// header in the report of 2026-09-01.
///
/// **The shape is copied, not invented.** People know what a checkbox looks
/// like, and a drawn one that reads as something else is worse than a small one
/// that reads as a checkbox: a rounded square with a hairline, filled and
/// carrying a tick when on. The proportions are the system's at 1× — a box
/// roughly the height of a capital letter, sitting on the text's centre line —
/// so nothing visibly moves at the zoom almost everybody is at, which is the
/// same promise `DrawnButton` made.
final class DrawnCheckbox: NSButton, ScaleFollowing {
	private let label: String

	init(title: String, action: @escaping () -> Void) {
		label = title
		super.init(frame: .zero)
		isBordered = false
		wantsLayer = true
		setButtonType(.switch)
		// The cell draws nothing: the box and the words are both this view's,
		// because a half-drawn control is one that disagrees with itself about
		// where its centre line is.
		imagePosition = .imageOnly
		image = nil
		alternateImage = nil
		self.title = ""
		setAccessibilityLabel(label)
		onAction = action
		applyTheme()
		ScaledControls.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var state: NSControl.StateValue {
		didSet { needsDisplay = true }
	}

	func applyTheme() {
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override var isFlipped: Bool { true }

	/// The side of the box, and the gap between it and the words.
	private var boxSide: CGFloat { Theme.current.scaled(13) }
	private var gap: CGFloat { Theme.current.scaled(6) }

	private var words: NSAttributedString {
		NSAttributedString(string: label, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: isEnabled
				? Theme.current.sidebarText
				: Theme.current.sidebarText.withAlphaComponent(0.45),
		])
	}

	override var intrinsicContentSize: NSSize {
		let text = words.size()
		return NSSize(
			width: (boxSide + gap + ceil(text.width)).rounded(),
			height: max(boxSide, ceil(text.height)).rounded()
		)
	}

	override func draw(_ dirtyRect: NSRect) {
		let side = boxSide
		let box = NSRect(
			x: 0, y: ((bounds.height - side) / 2).rounded(),
			width: side, height: side
		)
		let radius = ControlMetrics.radius(scale: Theme.current.scale) * 0.6
		let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

		if state == .on {
			(isEnabled ? Theme.current.caret : Theme.current.caret.withAlphaComponent(0.45)).setFill()
			path.fill()
			// The tick is a symbol rather than two strokes: it is the same
			// glyph the rest of the app ticks things off with, and drawing it
			// by hand would be a second checkmark to keep in step.
			if let tick = Theme.symbol(
				"checkmark", size: 9 * Theme.current.scale,
				color: Theme.current.editorBackground, weight: .bold
			) {
				tick.drawFitted(in: box.insetBy(dx: side * 0.2, dy: side * 0.2))
			}
		} else {
			Theme.current.editorBackground.setFill()
			path.fill()
			Theme.current.separator.setStroke()
			path.lineWidth = 1
			path.stroke()
		}

		let text = words
		let size = text.size()
		text.draw(at: NSPoint(x: side + gap, y: ((bounds.height - size.height) / 2).rounded()))
	}
}

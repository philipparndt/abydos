import AppKit

/// The ✕ on a tab, and the plate that appears behind it under the pointer.
///
/// Two strips draw it — the editor's and the panel's — and the plate is the part
/// that has to agree. A hover highlight only reads as an affordance if it is the
/// same affordance wherever it appears, and one rounded rect and one alpha
/// copied into two files drift the first time somebody adjusts the colour. The
/// panel's strip went a year without a highlight at all for the neighbouring
/// reason: the code that would have drawn one was in the other file.
///
/// The other answer would be a tab bar the two strips share. That is a much
/// larger change than one highlight is worth — the two differ in almost
/// everything else they draw, from tmux's green to the preview control — so a
/// function taking a rect and a flag is the middle: the plate, the shape and the
/// ink live once, and each strip keeps its own layout.
///
/// The arm inset and the line width stay with the caller. The two size their
/// close boxes differently — 14 points against 12 — and the crosses come out the
/// same size only because the insets differ to match, so settling either number
/// here would mean choosing one strip's look for both.
enum TabCloseButton {
	@MainActor static func draw(
		in rect: NSRect,
		hovered: Bool,
		inset: CGFloat,
		lineWidth: CGFloat
	) {
		// Grown by a point rather than fitted to the box, so the cross sits
		// inside the plate instead of touching its corners.
		if hovered {
			let plate = NSBezierPath(
				roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4
			)
			NSColor.white.withAlphaComponent(0.12).setFill()
			plate.fill()
		}

		let cross = NSBezierPath()
		cross.move(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
		cross.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
		cross.move(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
		cross.line(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
		cross.lineWidth = lineWidth
		cross.lineCapStyle = .round
		Theme.current.sidebarText.setStroke()
		cross.stroke()
	}
}

/// A strip of tabs whose ✕ can be put under the pointer without a pointer.
///
/// A screenshot run has no mouse, and the half of a hover that goes wrong is the
/// half a screenshot cannot show anyway: the plate still sitting there after the
/// pointer has left. Both strips answer with what they think is under the
/// pointer, so the leaving is a line of text rather than a squint.
@MainActor protocol TabCloseHovering: NSView {
	/// How many tabs there are to try, so a run can walk all of them rather than
	/// trusting that the first one is representative — the tab that must *not*
	/// light up is never the first.
	var tabCountForTesting: Int { get }

	/// Hovers the ✕ of a tab, or — with `nil` — takes the pointer off the strip
	/// entirely, and says what the strip now believes.
	@discardableResult
	func hoverCloseForTesting(_ index: Int?) -> String
}

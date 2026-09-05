import AppKit

/// The plumbing a view needs to answer the pointer: which of its controls is
/// under it, the ground drawn there, and the app's own tooltip shown from it.
///
/// **Because the fourth copy is where they start to differ.** The terminal
/// strip grew this by hand — a hovered-control state, a hit test, a show on
/// change, a hide on exit, a rectangle handed to `StyledTip` — and the left
/// rail, the navigator's header and the run control each want the same thing.
/// Written once, the four cannot drift into four delays, four ways of dropping
/// the tip on a click, and four answers to a driven run.
///
/// The view keeps what only it knows: where its controls are, what they say,
/// and how it draws. Both arrive as closures rather than a table to keep
/// up to date — a control's words change with what it is showing (a count, an
/// on-or-off state), and a table would be one more thing to refresh at exactly
/// the right moment.
@MainActor
final class TipHost<Control: Equatable> {
	/// The controls and where they are, in the order they are asked: a chevron
	/// on a button's edge is asked before the button under it. A zero-width
	/// rectangle is a control that is not on this view at the moment, and
	/// contains nothing.
	private let controls: () -> [(Control, NSRect)]
	/// What each says when the pointer rests on it.
	private let words: (Control) -> StyledTip.Tip

	/// Which control the pointer is on, for the view to draw.
	private(set) var hovered: Control?

	init(controls: @escaping () -> [(Control, NSRect)], words: @escaping (Control) -> StyledTip.Tip) {
		self.controls = controls
		self.words = words
	}

	func control(at point: NSPoint) -> Control? {
		controls().first { $0.1.width > 0 && $0.1.contains(point) }?.0
	}

	func rect(of control: Control) -> NSRect {
		controls().first { $0.0 == control }?.1 ?? .zero
	}

	/// The pointer at a point: the hover state moved, the tip shown from
	/// whichever control it landed on, and `true` when the view has something
	/// new to draw.
	@discardableResult
	func update(at point: NSPoint, in view: NSView) -> Bool {
		let control = control(at: point)
		let changed = control != hovered
		hovered = control
		// The tip follows the hover rather than a tooltip rectangle, so it is
		// asked on every move and drops itself the moment the pointer is on
		// something else or on nothing.
		if let control {
			StyledTip.shared.show(words(control), from: rect(of: control), of: view)
		} else {
			StyledTip.shared.hide()
		}
		return changed
	}

	/// The pointer gone, or a click: a tip explains a control somebody has
	/// stopped reading about and started using.
	@discardableResult
	func clear() -> Bool {
		let changed = hovered != nil
		hovered = nil
		StyledTip.shared.hide()
		return changed
	}

	/// Puts the pointer on a named control and says what it is and what it
	/// would tell somebody — the hover and the tooltip in one answer, since
	/// they are the same question asked with the pointer.
	///
	/// Through `update` rather than by setting the state, because what is being
	/// checked is what the pointer does: a harness that assigned the hover
	/// would pass with the hit test wired to nothing.
	func hoverForTesting(_ name: String, _ named: [String: Control], in view: NSView) -> String {
		guard let control = named[name] else { return "no control called \(name)" }
		let rect = rect(of: control)
		guard rect.width > 0 else { return "\(name): not here" }
		update(at: NSPoint(x: rect.midX, y: rect.midY), in: view)
		let lit = hovered == control ? "lit" : "NOT LIT"
		return "\(name): \(lit) " + words(control).reportForTesting
	}
}

/// The ground drawn under whichever control the pointer is on.
///
/// One shape for the whole window's chrome: the strip drew it first — a
/// rounded band in the faintest ink the theme has, short enough to read as a
/// button rather than as a block — and the rail, the header and the run
/// control draw the same one, so that one window does not have three hovers.
enum HoverGround {
	/// The band a control of this height gets: inset either side, and no taller
	/// than a button, whatever the strip or bar around it is.
	static func band(around rect: NSRect) -> NSRect {
		let inset = Theme.current.scaled(3)
		return NSRect(
			x: rect.minX - inset,
			y: rect.midY - Theme.current.scaled(10),
			width: rect.width + inset * 2,
			height: Theme.current.scaled(20)
		)
	}

	/// - Parameter overTint: whether the control draws a ground of its own. A
	///   faint band that reads clearly behind a bare glyph disappears behind a
	///   pill that is already on a tint, so that one gets a stronger halo,
	///   capsule-shaped like the thing it is behind.
	static func draw(around rect: NSRect, ink: NSColor, overTint: Bool = false) {
		guard rect.width > 0 else { return }
		let band = band(around: rect)
		ink.withAlphaComponent(overTint ? 0.26 : 0.12).setFill()
		let radius = overTint ? band.height / 2 : Theme.current.scaled(5)
		NSBezierPath(roundedRect: band, xRadius: radius, yRadius: radius).fill()
	}
}

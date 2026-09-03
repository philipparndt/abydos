import AppKit
import AbydosKit

/// The pill on the terminal's title bar: two dots and two figures, how many
/// Claude sessions on the machine are working and how many are waiting for
/// somebody.
///
/// In the tab badges' own colours, because it is the same fact one level up:
/// the badge says what the session in *this* window is doing, and the pill says
/// how many are doing each, including the ones in tmux sessions and projects the
/// strip cannot show. Amber is the only state that earns colour on the ground: a
/// working session wants nothing, and a finished one is in the list and in
/// neither number.
///
/// Measured and drawn here, placed by `PanelTabStrip`: the strip owns where its
/// controls go and this owns what one of them looks like, which keeps the pill
/// out of a file that is already over five thousand lines and forbidden to grow.
/// Every dimension is read from `Theme.current` where it is used, so the pill
/// scales with the zoom for the reason the drawn-control library's members do.
enum SessionsPill {
	static var height: CGFloat { Theme.current.scaled(16) }
	private static var dot: CGFloat { Theme.current.scaled(6) }

	/// Whether the pill carries its digits, or only its two dots.
	///
	/// The same width at which the tmux tag drops the session's name: a strip
	/// that narrow has room for the fact and not the figure.
	static func showsDigits(inStripOfWidth width: CGFloat) -> Bool {
		width > Theme.current.scaled(420)
	}

	static func width(for counts: RunningSessions.Counts, showsDigits: Bool) -> CGFloat {
		let padding = Theme.current.scaled(14)
		guard showsDigits else { return dot * 2 + Theme.current.scaled(8) + padding }
		let working = digits(counts.working, ink: .black).size().width
		let needs = digits(counts.needsInput, ink: .black).size().width
		return dot + Theme.current.scaled(4) + working
			+ Theme.current.scaled(8)
			+ dot + Theme.current.scaled(4) + needs
			+ padding
	}

	static func draw(_ counts: RunningSessions.Counts, in frame: NSRect, showsDigits: Bool) {
		let pill = NSBezierPath(
			roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2
		)
		(counts.needsInput > 0
			? PanelTabStrip.colour(for: .needsInput).withAlphaComponent(0.18)
			: Theme.current.sidebarText.withAlphaComponent(0.10)
		).setFill()
		pill.fill()

		var x = frame.minX + Theme.current.scaled(7)
		x = drawHalf(
			at: x, in: frame, count: counts.working, showsDigits: showsDigits,
			dot: PanelTabStrip.colour(for: .working), ink: Theme.current.sidebarText
		)
		x += Theme.current.scaled(8)
		drawHalf(
			at: x, in: frame, count: counts.needsInput, showsDigits: showsDigits,
			dot: PanelTabStrip.colour(for: .needsInput), ink: PanelTabStrip.colour(for: .needsInput)
		)
	}

	private static func digits(_ count: Int, ink: NSColor) -> NSAttributedString {
		NSAttributedString(string: String(count), attributes: [
			.font: Theme.current.uiFont(10, weight: .semibold),
			.foregroundColor: ink,
		])
	}

	/// One dot and, where there is room, its figure. Returns where the next
	/// thing goes.
	@discardableResult
	private static func drawHalf(
		at x: CGFloat, in frame: NSRect, count: Int, showsDigits: Bool, dot colour: NSColor, ink: NSColor
	) -> CGFloat {
		colour.setFill()
		NSBezierPath(ovalIn: NSRect(x: x, y: frame.midY - dot / 2, width: dot, height: dot)).fill()
		var next = x + dot
		if showsDigits {
			let figure = digits(count, ink: ink)
			let size = figure.size()
			next += Theme.current.scaled(4)
			figure.draw(at: NSPoint(x: next, y: frame.midY - size.height / 2))
			next += size.width
		}
		return next
	}
}

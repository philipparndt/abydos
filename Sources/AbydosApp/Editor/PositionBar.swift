import AppKit
import AbydosKit

/// The bar along the bottom of a zoomed timeline: where the window is in the
/// whole, and a handle to move it by.
///
/// Reported 2026-09-16: "it is currently not possible to scroll with the
/// scrollbar at the bottom". It was drawn and nothing else — four points tall,
/// with no hand on it — so a press there went through to the timeline and
/// moved the playhead instead. Both the sound tab's canvas and the song pane's
/// had it the same way, so it is here once for both.
///
/// A press on the thumb takes it where it was pressed; a press on the track
/// either side brings the thumb's middle there and takes it from its middle.
/// The target is taller than what is drawn, since a strip a few points tall is
/// one a pointer misses.
struct PositionBar {
	/// Where in the thumb it was taken, while it is being dragged.
	private(set) var grab: CGFloat?

	var isDragging: Bool { grab != nil }

	static var height: CGFloat { max(4, Theme.current.scaled(6)) }
	/// The height a press counts in, above the bottom edge.
	static var reach: CGFloat { Theme.current.scaled(12) }

	/// The thumb, in a flipped view: the window's share of the whole, at the
	/// window's place in it, along the bottom.
	static func thumb(in bounds: NSRect, start: Double, span: Double, duration: Double) -> NSRect {
		guard duration > 0 else { return .zero }
		let width = max(Theme.current.scaled(24), CGFloat(span / duration) * bounds.width)
		let room = max(0, bounds.width - width)
		// The inverse of `start(forThumbAt:)`, so a thumb put down is a thumb
		// that stays where it was put.
		let along = CGFloat(min(1, max(0, start / max(1e-9, duration - span))))
		return NSRect(x: along * room, y: bounds.height - height, width: width, height: height)
	}

	/// A press: the window's new start when it is on the bar, nil when it is
	/// somewhere else and belongs to the timeline.
	mutating func press(
		at point: NSPoint, in bounds: NSRect, start: Double, span: Double, duration: Double
	) -> Double? {
		guard duration > 0, span < duration, point.y >= bounds.height - Self.reach else { return nil }
		let thumb = Self.thumb(in: bounds, start: start, span: span, duration: duration)
		if point.x >= thumb.minX, point.x <= thumb.maxX {
			grab = point.x - thumb.minX
			return start
		}
		grab = thumb.width / 2
		return Self.start(forThumbAt: point.x - thumb.width / 2, in: bounds, span: span, duration: duration)
	}

	/// A drag with the bar in hand: the window's new start.
	func drag(to point: NSPoint, in bounds: NSRect, span: Double, duration: Double) -> Double? {
		guard let grab else { return nil }
		return Self.start(forThumbAt: point.x - grab, in: bounds, span: span, duration: duration)
	}

	mutating func release() { grab = nil }

	/// The window's start for a thumb whose left edge is at `left`.
	///
	/// Measured against the room the thumb has to move in, not the whole
	/// width: a thumb drawn wider than its share — the shortest is still a
	/// handle — would otherwise reach the end before the window does.
	private static func start(forThumbAt left: CGFloat, in bounds: NSRect, span: Double, duration: Double) -> Double {
		let share = CGFloat(span / duration) * bounds.width
		let width = max(Theme.current.scaled(24), share)
		let room = max(1, bounds.width - width)
		let fraction = Double(min(max(0, left), room) / room)
		return fraction * max(0, duration - span)
	}

	/// The track and the thumb, drawn.
	static func draw(in bounds: NSRect, start: Double, span: Double, duration: Double, active: Bool) {
		let track = NSRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
		Theme.current.separator.withAlphaComponent(0.5).setFill()
		track.fill()
		let thumb = self.thumb(in: bounds, start: start, span: span, duration: duration)
		Theme.current.gitModified.withAlphaComponent(active ? 1 : 0.8).setFill()
		NSBezierPath(roundedRect: thumb, xRadius: height / 2, yRadius: height / 2).fill()
	}
}

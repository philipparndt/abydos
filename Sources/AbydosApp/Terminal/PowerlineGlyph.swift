import AppKit

/// Draws powerline separators as geometry rather than as font glyphs.
///
/// A font glyph is sized to the font's own metrics, so it never quite fills the
/// terminal cell: the result is a visible seam where one prompt segment meets
/// the next, and a slight height mismatch against the segment background.
/// Drawing the shape to the cell rectangle removes both, and makes the prompt
/// look identical regardless of which font is in use. Ghostty, Kitty and WezTerm
/// all special-case these glyphs for the same reason.
enum PowerlineGlyph {
	/// The separators worth drawing ourselves. Other Nerd Font glyphs are icons,
	/// which the font renders perfectly well.
	static func isSeparator(_ scalar: UInt32) -> Bool {
		switch scalar {
		case 0xE0B0, 0xE0B1, 0xE0B2, 0xE0B3: return true
		// Rounded and flame variants of the same idea.
		case 0xE0B4, 0xE0B5, 0xE0B6, 0xE0B7: return true
		case 0xE0C0, 0xE0C1, 0xE0C2, 0xE0C3: return true
		default: return false
		}
	}

	static func draw(scalar: UInt32, in rect: NSRect, color: NSColor) {
		color.setFill()
		color.setStroke()

		switch scalar {
		case 0xE0B0:
			filledTriangle(pointingRight: true, in: rect).fill()
		case 0xE0B2:
			filledTriangle(pointingRight: false, in: rect).fill()

		case 0xE0B1:
			chevron(pointingRight: true, in: rect).stroke()
		case 0xE0B3:
			chevron(pointingRight: false, in: rect).stroke()

		case 0xE0B4, 0xE0C0:
			filledHalfCircle(onRight: true, in: rect).fill()
		case 0xE0B6, 0xE0C2:
			filledHalfCircle(onRight: false, in: rect).fill()

		case 0xE0B5, 0xE0C1:
			halfCircleOutline(onRight: true, in: rect).stroke()
		case 0xE0B7, 0xE0C3:
			halfCircleOutline(onRight: false, in: rect).stroke()

		default:
			break
		}
	}

	/// A solid triangle spanning the whole cell, so it meets its neighbours with
	/// no gap on either side.
	private static func filledTriangle(pointingRight: Bool, in rect: NSRect) -> NSBezierPath {
		let path = NSBezierPath()
		if pointingRight {
			path.move(to: NSPoint(x: rect.minX, y: rect.minY))
			path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
			path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
		} else {
			path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
			path.line(to: NSPoint(x: rect.minX, y: rect.midY))
			path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
		}
		path.close()
		return path
	}

	private static func chevron(pointingRight: Bool, in rect: NSRect) -> NSBezierPath {
		let path = NSBezierPath()
		// Inset slightly so the stroke sits inside the cell rather than clipping.
		let inset = rect.width * 0.2
		if pointingRight {
			path.move(to: NSPoint(x: rect.minX + inset, y: rect.minY))
			path.line(to: NSPoint(x: rect.maxX - inset, y: rect.midY))
			path.line(to: NSPoint(x: rect.minX + inset, y: rect.maxY))
		} else {
			path.move(to: NSPoint(x: rect.maxX - inset, y: rect.minY))
			path.line(to: NSPoint(x: rect.minX + inset, y: rect.midY))
			path.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY))
		}
		path.lineWidth = max(1, rect.width * 0.12)
		path.lineJoinStyle = .miter
		return path
	}

	private static func filledHalfCircle(onRight: Bool, in rect: NSRect) -> NSBezierPath {
		let path = NSBezierPath()
		let radius = rect.height / 2
		let centre = NSPoint(x: onRight ? rect.minX : rect.maxX, y: rect.midY)

		path.appendArc(
			withCenter: centre,
			radius: radius,
			startAngle: onRight ? -90 : 90,
			endAngle: onRight ? 90 : 270
		)
		path.close()
		return path
	}

	private static func halfCircleOutline(onRight: Bool, in rect: NSRect) -> NSBezierPath {
		let path = filledHalfCircle(onRight: onRight, in: rect)
		path.lineWidth = max(1, rect.width * 0.12)
		return path
	}
}

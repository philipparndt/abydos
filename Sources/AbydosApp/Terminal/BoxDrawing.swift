import AppKit

/// Draws box-drawing characters as geometry rather than as font glyphs.
///
/// They exist to join their neighbours — a rule across a screen, the border of
/// a tmux pane — and a font cannot be relied on for that. A glyph is sized to
/// the font's metrics, a cell to a whole number of points, and the difference
/// shows as a dashed line where a solid one was meant. Stretching the glyph to
/// the cell fixes the joins in one direction and breaks the alignment of
/// corners against rules in the other, because the two are drawn to different
/// extents inside their em box.
///
/// Drawn to the cell rectangle, every join meets exactly and every arm lands on
/// the same centre line. Ghostty, Kitty and WezTerm all draw these themselves,
/// for the same reason.
enum BoxDrawing {
	/// How thick an arm is.
	enum Weight {
		case none, light, heavy, double
	}

	/// Which way the arms of a character point, and how thick each one is.
	struct Arms {
		var left: Weight = .none
		var right: Weight = .none
		var up: Weight = .none
		var down: Weight = .none
	}

	/// Whether this is one we draw. Anything else is left to the font, which
	/// handles the shaded blocks and the odd corners perfectly well.
	static func arms(for scalar: UInt32) -> Arms? {
		switch scalar {
		// Straight lines.
		case 0x2500: return Arms(left: .light, right: .light)
		case 0x2501: return Arms(left: .heavy, right: .heavy)
		case 0x2502: return Arms(up: .light, down: .light)
		case 0x2503: return Arms(up: .heavy, down: .heavy)
		case 0x2550: return Arms(left: .double, right: .double)
		case 0x2551: return Arms(up: .double, down: .double)

		// Corners, light then heavy then double.
		case 0x250C: return Arms(right: .light, down: .light)
		case 0x2510: return Arms(left: .light, down: .light)
		case 0x2514: return Arms(right: .light, up: .light)
		case 0x2518: return Arms(left: .light, up: .light)
		case 0x250F: return Arms(right: .heavy, down: .heavy)
		case 0x2513: return Arms(left: .heavy, down: .heavy)
		case 0x2517: return Arms(right: .heavy, up: .heavy)
		case 0x251B: return Arms(left: .heavy, up: .heavy)
		case 0x2554: return Arms(right: .double, down: .double)
		case 0x2557: return Arms(left: .double, down: .double)
		case 0x255A: return Arms(right: .double, up: .double)
		case 0x255D: return Arms(left: .double, up: .double)
		// Rounded corners are drawn square: at a cell's size the difference is
		// a pixel, and a join that meets exactly matters more.
		case 0x256D: return Arms(right: .light, down: .light)
		case 0x256E: return Arms(left: .light, down: .light)
		case 0x256F: return Arms(left: .light, up: .light)
		case 0x2570: return Arms(right: .light, up: .light)

		// Tees.
		case 0x251C: return Arms(right: .light, up: .light, down: .light)
		case 0x2524: return Arms(left: .light, up: .light, down: .light)
		case 0x252C: return Arms(left: .light, right: .light, down: .light)
		case 0x2534: return Arms(left: .light, right: .light, up: .light)
		case 0x2523: return Arms(right: .heavy, up: .heavy, down: .heavy)
		case 0x252B: return Arms(left: .heavy, up: .heavy, down: .heavy)
		case 0x2533: return Arms(left: .heavy, right: .heavy, down: .heavy)
		case 0x253B: return Arms(left: .heavy, right: .heavy, up: .heavy)
		case 0x2560: return Arms(right: .double, up: .double, down: .double)
		case 0x2563: return Arms(left: .double, up: .double, down: .double)
		case 0x2566: return Arms(left: .double, right: .double, down: .double)
		case 0x2569: return Arms(left: .double, right: .double, up: .double)

		// Crosses.
		case 0x253C: return Arms(left: .light, right: .light, up: .light, down: .light)
		case 0x254B: return Arms(left: .heavy, right: .heavy, up: .heavy, down: .heavy)
		case 0x256C: return Arms(left: .double, right: .double, up: .double, down: .double)

		default: return nil
		}
	}

	static func draws(_ scalar: UInt32) -> Bool { arms(for: scalar) != nil }

	/// Fills the arms of a character into a cell.
	static func draw(scalar: UInt32, in rect: NSRect, color: NSColor) {
		guard let arms = arms(for: scalar) else { return }
		color.setFill()

		// Odd, so a line has a middle pixel and meets its neighbours squarely.
		let light = max(1, (rect.height / 14).rounded())
		let heavy = max(2, (light * 2).rounded())
		// Far enough apart to read as two lines at any size worth using.
		let gap = max(1, light)

		func thickness(_ weight: Weight) -> CGFloat {
			switch weight {
			case .none: return 0
			case .light: return light
			case .heavy: return heavy
			case .double: return light
			}
		}

		let midX = (rect.midX).rounded()
		let midY = (rect.midY).rounded()

		/// One arm, from an edge to the centre — a little past it, so opposite
		/// arms overlap rather than meeting on a seam.
		func horizontal(_ weight: Weight, towardsLeft: Bool, offset: CGFloat = 0) {
			let t = thickness(weight)
			guard t > 0 else { return }
			let y = (midY + offset - t / 2).rounded()
			let x = towardsLeft ? rect.minX : midX - t / 2
			let width = towardsLeft ? midX - rect.minX + t / 2 : rect.maxX - midX + t / 2
			NSRect(x: x, y: y, width: width, height: t).fill()
		}

		// Drawn with y running up, so the top of the cell is maxY. An arm
		// pointing up therefore runs from the middle to the top edge.
		func vertical(_ weight: Weight, towardsTop: Bool, offset: CGFloat = 0) {
			let t = thickness(weight)
			guard t > 0 else { return }
			let x = (midX + offset - t / 2).rounded()
			let y = towardsTop ? midY - t / 2 : rect.minY
			let height = towardsTop ? rect.maxY - midY + t / 2 : midY - rect.minY + t / 2
			NSRect(x: x, y: y, width: t, height: height).fill()
		}

		// A double arm is two lines either side of where a single one would go.
		func arm(_ weight: Weight, horizontalTowardsLeft: Bool? = nil, verticalTowardsTop: Bool? = nil) {
			let offsets: [CGFloat] = weight == .double ? [-(gap + light) / 2, (gap + light) / 2] : [0]
			for offset in offsets {
				if let towardsLeft = horizontalTowardsLeft {
					horizontal(weight, towardsLeft: towardsLeft, offset: offset)
				}
				if let towardsTop = verticalTowardsTop {
					vertical(weight, towardsTop: towardsTop, offset: offset)
				}
			}
		}

		arm(arms.left, horizontalTowardsLeft: true)
		arm(arms.right, horizontalTowardsLeft: false)
		arm(arms.up, verticalTowardsTop: true)
		arm(arms.down, verticalTowardsTop: false)
	}
}

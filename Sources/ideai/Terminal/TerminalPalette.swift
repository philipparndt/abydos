import AppKit
import IdeaiKit

/// Maps terminal colours to concrete `NSColor`s.
///
/// The 16 named colours are the theme's, not the xterm defaults, so a shell
/// prompt sits in the same palette as the editor's syntax highlighting instead
/// of clashing with it. The 240 extended slots follow the standard xterm cube,
/// which programs assume exactly.
enum TerminalPalette {
	/// ANSI 0–15, tuned to match the editor theme.
	static let named: [NSColor] = [
		.hex(0x2B2D30), // 0 black
		.hex(0xC7756B), // 1 red
		.hex(0x6AAB73), // 2 green
		.hex(0xB58A2B), // 3 yellow
		.hex(0x3592C4), // 4 blue
		.hex(0xC77DBB), // 5 magenta
		.hex(0x2AACB8), // 6 cyan
		.hex(0xBCBEC4), // 7 white
		.hex(0x5A5D63), // 8 bright black
		.hex(0xE06C60), // 9 bright red
		.hex(0x7FCC89), // 10 bright green
		.hex(0xE8BF6A), // 11 bright yellow
		.hex(0x56A8F5), // 12 bright blue
		.hex(0xE18FD8), // 13 bright magenta
		.hex(0x4BD4E0), // 14 bright cyan
		.hex(0xDFE1E5), // 15 bright white
	]

	/// Full 256-entry table, built once.
	private static let extended: [NSColor] = {
		var colors = named

		// 16–231: a 6×6×6 cube. The level table is the xterm standard; an even
		// linear ramp would visibly mismatch what programs expect.
		let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
		for red in 0..<6 {
			for green in 0..<6 {
				for blue in 0..<6 {
					colors.append(NSColor(
						srgbRed: levels[red] / 255,
						green: levels[green] / 255,
						blue: levels[blue] / 255,
						alpha: 1
					))
				}
			}
		}

		// 232–255: 24 steps of grey.
		for step in 0..<24 {
			let value = CGFloat(8 + step * 10) / 255
			colors.append(NSColor(srgbRed: value, green: value, blue: value, alpha: 1))
		}
		return colors
	}()

	/// The 256 palette entries as the shaders want them, worked out once.
	///
	/// Going through NSColor for this meant a colour-space conversion for every
	/// cell of every frame — two, counting the background — which on a screen
	/// of ten thousand cells is more work than drawing them.
	private static let components: [SIMD4<Float>] = extended.map { color in
		let srgb = color.usingColorSpace(.sRGB) ?? color
		return SIMD4(
			Float(srgb.redComponent), Float(srgb.greenComponent),
			Float(srgb.blueComponent), Float(srgb.alphaComponent)
		)
	}

	/// A cell's colour, without building an NSColor for it.
	static func components(
		for terminalColor: TerminalColor,
		isForeground: Bool,
		bold: Bool,
		defaultForeground: SIMD4<Float>,
		defaultBackground: SIMD4<Float>
	) -> SIMD4<Float> {
		switch terminalColor {
		case .default:
			return isForeground ? defaultForeground : defaultBackground
		case let .indexed(index):
			let resolved = (bold && index < 8) ? Int(index) + 8 : Int(index)
			return components[min(resolved, components.count - 1)]
		case let .rgb(red, green, blue):
			return SIMD4(Float(red) / 255, Float(green) / 255, Float(blue) / 255, 1)
		}
	}

	static func color(
		for terminalColor: TerminalColor,
		isForeground: Bool,
		bold: Bool
	) -> NSColor {
		switch terminalColor {
		case .default:
			return isForeground ? Theme.current.editorText : Theme.current.editorBackground
		case let .indexed(index):
			// Bold has historically brightened the first eight colours, and
			// prompts still rely on that for their highlight colour.
			let resolved = (bold && index < 8) ? Int(index) + 8 : Int(index)
			return extended[min(resolved, extended.count - 1)]
		case let .rgb(red, green, blue):
			return NSColor(
				srgbRed: CGFloat(red) / 255,
				green: CGFloat(green) / 255,
				blue: CGFloat(blue) / 255,
				alpha: 1
			)
		}
	}
}

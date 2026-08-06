import AppKit
import AbydosKit

/// Maps terminal colours to concrete `NSColor`s.
///
/// The 16 named colours are the theme's, not the xterm defaults, so a shell
/// prompt sits in the same palette as the editor's syntax highlighting instead
/// of clashing with it. The 240 extended slots follow the standard xterm cube,
/// which programs assume exactly.
enum TerminalPalette {
	/// The scheme the tables below were built for.
	///
	/// Rebuilt when it changes rather than looked up per cell: a screen repaint
	/// asks for two colours for every cell on it.
	@MainActor private static var builtFor: TerminalScheme?

	/// ANSI 0–15, from the chosen scheme.
	@MainActor static var named: [NSColor] {
		rebuildIfNeeded()
		return namedStorage
	}

	@MainActor private static var namedStorage: [NSColor] = TerminalScheme.default.named
	@MainActor private static var extendedStorage: [NSColor] = []

	/// How much of a colour is left when a cell asks to be faint.
	///
	/// Blended towards what is behind it rather than towards black, so faint
	/// text stays faint against any background. Ghostty takes a colour down by
	/// about half and this matches it: at 0.6 the dimmed status line a
	/// full-screen tool draws was barely distinguishable from ordinary text.
	static let dimAmount: CGFloat = 0.45

	/// What a cell with no colour of its own sits on, and is written in.
	@MainActor static var background: NSColor { TerminalScheme.current.background }
	@MainActor static var foreground: NSColor { TerminalScheme.current.foreground }
	@MainActor static var cursor: NSColor { TerminalScheme.current.cursor }

	/// Throws the table away, so the next draw builds it again.
	///
	/// The scheme has not changed, but what it resolves to has: the one that
	/// follows the editor is a different set of colours in daylight.
	@MainActor static func invalidate() {
		builtFor = nil
	}

	@MainActor private static func rebuildIfNeeded() {
		let scheme = TerminalScheme.current
		guard builtFor != scheme else { return }
		builtFor = scheme
		namedStorage = scheme.named
		extendedStorage = Self.buildExtended(from: namedStorage)
		componentsStorage = extendedStorage.map { color in
			let srgb = color.usingColorSpace(.sRGB) ?? color
			return SIMD4(
				Float(srgb.redComponent), Float(srgb.greenComponent),
				Float(srgb.blueComponent), Float(srgb.alphaComponent)
			)
		}
	}

	/// Full 256-entry table.
	@MainActor private static var extended: [NSColor] {
		rebuildIfNeeded()
		return extendedStorage
	}

	private static func buildExtended(from named: [NSColor]) -> [NSColor] {
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
	}

	/// The 256 palette entries as the shaders want them, worked out once.
	///
	/// Going through NSColor for this meant a colour-space conversion for every
	/// cell of every frame — two, counting the background — which on a screen
	/// of ten thousand cells is more work than drawing them.
	@MainActor private static var componentsStorage: [SIMD4<Float>] = []

	/// A cell's colour, without building an NSColor for it.
	@MainActor
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
			rebuildIfNeeded()
			let resolved = (bold && index < 8) ? Int(index) + 8 : Int(index)
			return componentsStorage[min(resolved, componentsStorage.count - 1)]
		case let .rgb(red, green, blue):
			return SIMD4(Float(red) / 255, Float(green) / 255, Float(blue) / 255, 1)
		}
	}

	@MainActor
	static func color(
		for terminalColor: TerminalColor,
		isForeground: Bool,
		bold: Bool
	) -> NSColor {
		switch terminalColor {
		case .default:
			return isForeground ? foreground : background
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

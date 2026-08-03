import AppKit
import IdeaiKit

/// A set of colours for the terminal.
///
/// Kept apart from the editor's theme. A terminal's palette is a language of
/// its own — prompts, diffs and full-screen tools all mean something by it —
/// and people arrive with one they already know.
enum TerminalScheme: String, CaseIterable {
	/// Ghostty's palette on a deep blue. What most people coming from Ghostty
	/// will recognise, and the default.
	case blue
	/// The editor's own colours, so the terminal sits in the same palette as
	/// the syntax highlighting beside it — including in daylight, where a
	/// terminal that stayed black would be the one dark rectangle on screen.
	case dark

	static let `default` = TerminalScheme.blue

	var title: String {
		switch self {
		case .blue: return "Blue"
		case .dark: return "Dark"
		}
	}

	/// ANSI 0–15.
	var named: [NSColor] {
		switch self {
		case .blue where Theme.current.isLight:
			// The same palette in daylight: the hues kept, the values pushed
			// down so they can be read on paper-white rather than on navy.
			return [
				.hex(0x3B3E45), // 0 black
				.hex(0xB03A2E), // 1 red
				.hex(0x4E7A1E), // 2 green
				.hex(0x8A6100), // 3 yellow
				.hex(0x2C5F8A), // 4 blue
				.hex(0xA4318B), // 5 magenta
				.hex(0x2A7D74), // 6 cyan
				.hex(0x60656E), // 7 white
				.hex(0x767B85), // 8 bright black
				.hex(0xC0392B), // 9 bright red
				.hex(0x5E8C22), // 10 bright green
				.hex(0xA97400), // 11 bright yellow
				.hex(0x2E6DA4), // 12 bright blue
				.hex(0x8E44AD), // 13 bright magenta
				.hex(0x2E8B84), // 14 bright cyan
				.hex(0x2B2D30), // 15 bright white
			]
		case .blue:
			return [
				.hex(0x1D1F21), // 0 black
				.hex(0xCC6666), // 1 red
				.hex(0xB5BD68), // 2 green
				.hex(0xF0C674), // 3 yellow
				.hex(0x81A2BE), // 4 blue
				.hex(0xED73BD), // 5 magenta
				.hex(0x8ABEB7), // 6 cyan
				.hex(0x999999), // 7 white
				.hex(0x666666), // 8 bright black
				.hex(0xD54E53), // 9 bright red
				.hex(0xB9CA4A), // 10 bright green
				.hex(0xE7C547), // 11 bright yellow
				.hex(0x7AA6DA), // 12 bright blue
				.hex(0xC397D8), // 13 bright magenta
				.hex(0x70C0B1), // 14 bright cyan
				.hex(0xEAEAEA), // 15 bright white
			]
		case .dark where Theme.current.isLight:
			// The same hues, darkened to be read against white. A palette made
			// for a black background disappears on a light one — yellow most
			// of all.
			return [
				.hex(0x3B3E45), // 0 black
				.hex(0xB03A2E), // 1 red
				.hex(0x2E7D32), // 2 green
				.hex(0x8A6100), // 3 yellow
				.hex(0x1565C0), // 4 blue
				.hex(0x9C27B0), // 5 magenta
				.hex(0x00796B), // 6 cyan
				.hex(0x5A5D66), // 7 white
				.hex(0x6B6F78), // 8 bright black
				.hex(0xD32F2F), // 9 bright red
				.hex(0x388E3C), // 10 bright green
				.hex(0xA97400), // 11 bright yellow
				.hex(0x1976D2), // 12 bright blue
				.hex(0xAB47BC), // 13 bright magenta
				.hex(0x00897B), // 14 bright cyan
				.hex(0x2B2D30), // 15 bright white
			]
		case .dark:
			return [
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
		}
	}

	/// What a cell with no colour of its own sits on.
	var background: NSColor {
		switch self {
		// Not white: a terminal that is exactly the colour of the editor beside
		// it stops reading as a terminal. A hint of the same blue does it.
		case .blue: return Theme.current.isLight ? .hex(0xF4F6FB) : .hex(0x282935)
		case .dark: return Theme.current.editorBackground
		}
	}

	/// What a cell with no colour of its own is written in.
	var foreground: NSColor {
		switch self {
		case .blue: return Theme.current.isLight ? .hex(0x24262B) : .hex(0xFFFFFF)
		case .dark: return Theme.current.editorText
		}
	}

	/// The block cursor.
	var cursor: NSColor {
		switch self {
		case .blue: return Theme.current.isLight ? .hex(0x3B3E45) : .hex(0xC5C8C6)
		case .dark: return Theme.current.caret
		}
	}

	/// The one in use.
	static var current: TerminalScheme {
		TerminalScheme(rawValue: Settings.shared.terminalScheme) ?? .default
	}
}

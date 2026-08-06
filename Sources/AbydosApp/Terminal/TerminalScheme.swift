import AppKit
import AbydosKit

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
	/// The app's own: amber on a warm near-black, to sit beside the Abydos
	/// editor palette. ANSI still means what ANSI means — red is red, and a
	/// failing test has to look like one — but the hues lean towards the
	/// desert and the greys are warm rather than blue.
	case abydos

	static let `default` = TerminalScheme.blue

	var title: String {
		switch self {
		case .blue: return "Blue"
		case .dark: return "Dark"
		case .abydos: return "Abydos"
		}
	}

	/// ANSI 0–15.
	var named: [NSColor] {
		switch self {
		case .blue where Theme.current.isLight:
			// The hues kept, at a lightness that works both ways round. A
			// terminal colour is as often a background as a foreground — a
			// powerline prompt is nothing but coloured backgrounds — so these
			// sit in the middle: dark enough to read on paper-white, light
			// enough that black text on them is not a smudge.
			return [
				.hex(0x2B2D30), // 0 black — properly black, since a prompt
				               //   writes it on top of its own colours
				.hex(0xCB4B3C), // 1 red
				.hex(0x74A62F), // 2 green
				.hex(0xC08A00), // 3 yellow
				.hex(0x3E86C4), // 4 blue
				.hex(0xB65AAE), // 5 magenta
				.hex(0x3AA79E), // 6 cyan
				.hex(0x8B919B), // 7 white
				.hex(0x6B7078), // 8 bright black
				.hex(0xE0685A), // 9 bright red
				.hex(0x8CBF45), // 10 bright green
				.hex(0xDBA318), // 11 bright yellow
				.hex(0x5B9FD8), // 12 bright blue
				.hex(0xC97BC2), // 13 bright magenta
				.hex(0x54BDB4), // 14 bright cyan
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
		case .abydos:
			return [
				.hex(0x1C1712), // 0 black — the ground, warmed
				.hex(0xD6706E), // 1 red — a failure is red anywhere
				.hex(0x9FB37A), // 2 green
				.hex(0xF7B44E), // 3 yellow — the amber itself
				.hex(0xC9944A), // 4 blue → sand: the one hue that cannot stay,
				               //   since blue on this ground is the pairing
				               //   that looks like a mistake
				.hex(0xC98A9E), // 5 magenta
				.hex(0x8FB3A6), // 6 cyan
				.hex(0xCDBFA9), // 7 white
				.hex(0x7A6A55), // 8 bright black
				.hex(0xE58B87), // 9 bright red
				.hex(0xB4C78D), // 10 bright green
				.hex(0xFFE0AC), // 11 bright yellow — the core light
				.hex(0xE0A85E), // 12 bright blue → bright sand
				.hex(0xDFA0B2), // 13 bright magenta
				.hex(0xA6C7B8), // 14 bright cyan
				.hex(0xF3E7D3), // 15 bright white
			]
		case .dark where Theme.current.isLight:
			// As above: a middle lightness, so the same colour serves as text
			// on white and as something to write black on.
			return [
				.hex(0x2B2D30), // 0 black — properly black, since a prompt
				               //   writes it on top of its own colours
				.hex(0xC8503F), // 1 red
				.hex(0x5FA03A), // 2 green
				.hex(0xB8860B), // 3 yellow
				.hex(0x3B82C4), // 4 blue
				.hex(0xB158AE), // 5 magenta
				.hex(0x2FA39A), // 6 cyan
				.hex(0x8B919B), // 7 white
				.hex(0x6B7078), // 8 bright black
				.hex(0xDD6A58), // 9 bright red
				.hex(0x7FBE55), // 10 bright green
				.hex(0xD3A017), // 11 bright yellow
				.hex(0x589CD6), // 12 bright blue
				.hex(0xC77BC0), // 13 bright magenta
				.hex(0x4FBAB1), // 14 bright cyan
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
		// A shade off the editor's, for the same reason the blue one is: a
		// terminal exactly the colour of the editor beside it stops reading as
		// a terminal.
		case .abydos: return .hex(0x1A1512)
		}
	}

	/// What a cell with no colour of its own is written in.
	var foreground: NSColor {
		switch self {
		case .blue: return Theme.current.isLight ? .hex(0x24262B) : .hex(0xFFFFFF)
		case .dark: return Theme.current.editorText
		case .abydos: return .hex(0xE8D9C0)
		}
	}

	/// The block cursor.
	var cursor: NSColor {
		switch self {
		case .blue: return Theme.current.isLight ? .hex(0x3B3E45) : .hex(0xC5C8C6)
		case .dark: return Theme.current.caret
		case .abydos: return .hex(0xF7B44E)
		}
	}

	/// The one in use.
	static var current: TerminalScheme {
		TerminalScheme(rawValue: Settings.shared.terminalScheme) ?? .default
	}
}

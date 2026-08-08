import AppKit
import AbydosKit

/// A set of colours for the terminal.
///
/// Kept apart from the editor's theme. A terminal's palette is a language of
/// its own — prompts, diffs and full-screen tools all mean something by it —
/// and people arrive with one they already know.
///
/// The colours are the `terminal` section of a scheme file; this is what turns
/// one into `NSColor`s and what decides which file is in force. A scheme may
/// have that section and no `app` one — "Editor colours" is exactly that, a
/// terminal palette whose ground, text and cursor follow whatever the editor is
/// wearing.
struct TerminalScheme: Equatable {
	let id: String
	let title: String
	private let colours: SchemeTerminal

	init(scheme: Scheme) {
		id = scheme.id
		title = scheme.title
		colours = scheme.terminal ?? Scheme.fallback.terminal!
	}

	/// Compared by name: two values for the same scheme are the same palette,
	/// and the light/dark half of it is settled by the theme in force, which
	/// tells `TerminalPalette` to build its tables again when it changes.
	static func == (left: TerminalScheme, right: TerminalScheme) -> Bool {
		left.id == right.id
	}

	static var all: [TerminalScheme] {
		SchemeLibrary.shared.terminalSchemes.map(TerminalScheme.init)
	}

	static var `default`: TerminalScheme {
		TerminalScheme(scheme: SchemeLibrary.shared.defaultTerminalScheme)
	}

	/// ANSI 0–15.
	var named: [NSColor] {
		colours.named(isLight: Theme.current.isLight).map { NSColor.hex($0) }
	}

	/// What a cell with no colour of its own sits on.
	///
	/// Not the editor's own, for most schemes: a terminal that is exactly the
	/// colour of the editor beside it stops reading as a terminal, so each
	/// palette states a ground a shade off it. The one that says it follows the
	/// editor means the opposite on purpose — one surface rather than two.
	var background: NSColor {
		colour(colours.background) ?? Theme.current.editorBackground
	}

	/// What a cell with no colour of its own is written in.
	var foreground: NSColor {
		colour(colours.foreground) ?? Theme.current.editorText
	}

	/// The block cursor.
	var cursor: NSColor {
		colour(colours.cursor) ?? Theme.current.caret
	}

	private func colour(_ pair: SchemePair?) -> NSColor? {
		pair.map { NSColor.hex($0.value(isLight: Theme.current.isLight)) }
	}

	/// The one in use.
	///
	/// The setting may say "follow the editor", which is what a new
	/// installation gets: one decision about what the app looks like, rather
	/// than a warm amber editor beside a deep blue terminal that nobody chose.
	static var current: TerminalScheme {
		let resolved = Appearance.resolvedTerminalScheme(
			setting: Settings.shared.terminalScheme, stored: Settings.shared.activeAppearance
		)
		let wanted = Appearance.terminalSchemeIdentifier(for: resolved)
		guard let scheme = SchemeLibrary.shared.scheme(id: wanted), scheme.terminal != nil else {
			return .default
		}
		return TerminalScheme(scheme: scheme)
	}
}

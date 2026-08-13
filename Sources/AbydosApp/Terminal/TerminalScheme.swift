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
	/// Which palette is in force, remembered until something changes it.
	///
	/// **This used to be worked out on every access, and a terminal drawing at a
	/// hundred and sixty frames a second asks constantly.** In a CPU profile of a
	/// fire benchmark it was 5,374 of 96,415 samples — reading
	/// `Settings.terminalScheme` and `Settings.activeAppearance` from
	/// `UserDefaults` twice per call, resolving them, and looking the answer up in
	/// `SchemeLibrary` — with `_CFPreferencesCopyAppValueWithContainerAndConfiguration`
	/// alone at 4,803. A preference read is a search list, a lock and a generation
	/// check; it is not free and it is certainly not free per frame.
	///
	/// `TerminalPalette` already cached the colour *table*, which hid this: the
	/// table was rebuilt only when the scheme changed, but working out *whether*
	/// it had changed did all of the above every time, and
	/// `background`/`foreground`/`cursor` went straight here with no cache at all.
	/// So the cheap thing was cached and the expensive thing was not.
	///
	/// Invalidated by `TerminalPalette.invalidate()`, which is what the appearance
	/// change already calls and which is the one place that knows the answer may
	/// have moved — a settings write, a light/dark flip, or schemes reloaded from
	/// disk. Anything that adds a fourth reason belongs there too.
	@MainActor static var current: TerminalScheme {
		if let cached { return cached }
		let resolved = Appearance.resolvedTerminalScheme(
			setting: Settings.shared.terminalScheme, stored: Settings.shared.activeAppearance
		)
		let wanted = Appearance.terminalSchemeIdentifier(for: resolved)
		guard let scheme = SchemeLibrary.shared.scheme(id: wanted), scheme.terminal != nil else {
			cached = .default
			return .default
		}
		let answer = TerminalScheme(scheme: scheme)
		cached = answer
		return answer
	}

	@MainActor private static var cached: TerminalScheme?

	/// Forgets which palette is in force, so the next ask works it out again.
	@MainActor static func forget() { cached = nil }
}

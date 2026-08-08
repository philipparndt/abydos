import Foundation

/// What the app looks like: the editor's palette, and the terminal's.
///
/// Two questions, not one list. *Which* palette — the app's own warm one, or
/// the blue-grey it started with — and *how light* it should be. Asked
/// separately because they are separate: somebody who wants Abydos wants it in
/// the morning as well, and somebody who follows the system wants whichever
/// palette they chose to follow along rather than to be swapped for another.
///
/// The two used to be a single list with "Abydos" and "Abydos Light" in it,
/// which is five entries to say four things and no way at all to say "Abydos,
/// and follow the system".
///
/// Which palettes there are is no longer written here. A palette is a file —
/// see `Scheme` and `SchemeLibrary` — and this is only the arithmetic on the
/// one string everything downstream is given.
public enum Appearance {
	/// How light.
	public enum Mode: String, CaseIterable, Sendable {
		case system
		case light
		case dark

		public var title: String {
			switch self {
			case .system: return "System"
			case .light:  return "Light"
			case .dark:   return "Dark"
			}
		}
	}

	/// What an unrecognised stored value means, and what a fresh installation
	/// gets: the blue-grey the app shipped with before it had a second palette.
	///
	/// A constant here rather than a flag in a file, because it is a fact about
	/// this app's history — which stored values existed before schemes were
	/// files — and not something a scheme somebody writes gets to claim.
	public static let defaultFamily = "blue"

	private static var library: SchemeLibrary { .shared }

	/// Which palettes there are, in the order the settings window lists them.
	public static var families: [(id: String, title: String)] {
		library.appSchemes.map { ($0.id, $0.title) }
	}

	/// The stored value, which is one string because everything downstream —
	/// presentation mode, the `--theme` flag, the palette lookup — has always
	/// been given one.
	public static func name(family: String, mode: Mode) -> String {
		let scheme = library.appScheme(id: family) ?? library.defaultAppScheme
		return (scheme.app?.stored ?? SchemeApp.Stored(id: scheme.id)).name(for: mode)
	}

	/// Which palette a stored value names.
	///
	/// This is also the whole of the migration from when the two questions were
	/// one list: every value that could have been stored then decomposes into
	/// the pair that means the same thing now — `abydos-light` because the
	/// Abydos scheme says so by default, `light` because the blue one still
	/// names its three the way it always did.
	public static func family(of stored: String) -> String {
		decompose(stored)?.family ?? defaultFamily
	}

	/// How light a stored value asks for.
	public static func mode(of stored: String) -> Mode {
		decompose(stored)?.mode ?? .system
	}

	private static func decompose(_ stored: String) -> (family: String, mode: Mode)? {
		for scheme in library.appSchemes {
			guard let names = scheme.app?.stored else { continue }
			for mode in Mode.allCases where names.name(for: mode) == stored {
				return (scheme.id, mode)
			}
		}
		return nil
	}

	/// Whether a stored value is a light one, given what the system says for
	/// the pair that defers to it.
	public static func isLight(_ stored: String, systemIsDark: Bool) -> Bool {
		switch mode(of: stored) {
		case .light:  return true
		case .dark:   return false
		case .system: return !systemIsDark
		}
	}

	/// The value that means "whatever the editor is using".
	///
	/// A value rather than a separate switch: one control that lists the
	/// palettes and has "Same as the theme" at the top of them says both what
	/// is being used and that it follows, where a toggle beside a list leaves
	/// somebody wondering which of the two is in charge.
	public static let followsEditor = "follow"

	/// The terminal palette that goes with a family: the one from the same
	/// file, since a scheme dresses both halves of the window.
	///
	/// A family whose file has no terminal section falls back to the default
	/// one, which is how somebody ends up with a Dracula editor beside a
	/// terminal nobody chose — so the suite checks that the shipped ones all
	/// have one.
	public static func terminalScheme(following stored: String) -> String {
		let family = family(of: stored)
		if library.scheme(id: family)?.terminal != nil { return family }
		return library.defaultTerminalScheme.id
	}

	/// The scheme a stored terminal setting names.
	///
	/// "dark" is what "Editor colours" was called while the terminal palettes
	/// were an enum, and somebody who chose it two months ago still has that
	/// word in their preferences. Translated rather than migrated: rewriting
	/// what somebody chose is a worse habit than answering to both names.
	public static func terminalSchemeIdentifier(for setting: String) -> String {
		setting == "dark" ? "editor" : setting
	}

	/// Which terminal palette to actually use.
	///
	/// - Parameter setting: what is stored, which may be `followsEditor`.
	public static func resolvedTerminalScheme(setting: String, stored: String) -> String {
		guard setting == followsEditor || setting.isEmpty else { return setting }
		return terminalScheme(following: stored)
	}

	/// What a fresh installation gets: the terminal following the theme,
	/// because that is the answer somebody who has not thought about it wants.
	public static let defaultTerminalSetting = followsEditor

	/// Whether an existing terminal choice should be left alone.
	///
	/// Making "follow the theme" the default is right for a new installation
	/// and wrong for somebody who picked Blue two months ago: an upgrade that
	/// quietly repaints their terminal is a bug with a nice explanation.
	public static func migratedTerminalSetting(stored: String?) -> String {
		guard let stored, !stored.isEmpty else { return followsEditor }
		return stored
	}
}

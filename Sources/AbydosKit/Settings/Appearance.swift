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
public enum Appearance {
	/// Which palette.
	public enum Family: String, CaseIterable, Sendable {
		/// The app's own: amber, warm greys, ink on unbleached paper by day.
		case abydos
		/// The blue-grey one the app started with, and the palette most
		/// editors' dark themes are a version of.
		case blue
		/// Dracula, which people arrive with rather than discover here — and
		/// its daylight half, which upstream calls Alucard.
		case dracula

		public var title: String {
			switch self {
			case .abydos:  return "Abydos"
			case .blue:    return "Blue"
			case .dracula: return "Dracula"
			}
		}
	}

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

	/// The stored value, which is one string because everything downstream —
	/// presentation mode, the `--theme` flag, the palette lookup — has always
	/// been given one.
	public static func name(family: Family, mode: Mode) -> String {
		switch (family, mode) {
		case (.blue, .system):   return "system"
		case (.blue, .light):    return "light"
		case (.blue, .dark):     return "dark"
		case (.abydos, .system): return "abydos-system"
		case (.abydos, .light):  return "abydos-light"
		case (.abydos, .dark):   return "abydos"
		case (.dracula, .system): return "dracula-system"
		case (.dracula, .light):  return "dracula-light"
		case (.dracula, .dark):   return "dracula"
		}
	}

	/// Which palette a stored value names.
	///
	/// This is also the whole of the migration from when the two questions were
	/// one list: every value that could have been stored then decomposes into
	/// the pair that means the same thing now.
	public static func family(of stored: String) -> Family {
		if stored.hasPrefix("abydos") { return .abydos }
		if stored.hasPrefix("dracula") { return .dracula }
		return .blue
	}

	/// How light a stored value asks for.
	public static func mode(of stored: String) -> Mode {
		switch stored {
		case "light", "abydos-light", "dracula-light":   return .light
		case "dark", "abydos", "dracula":               return .dark
		case "system", "abydos-system", "dracula-system": return .system
		default:                                        return .system
		}
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

	/// The terminal palette that goes with a family. Each has one of its own,
	/// and each of those knows what to do in daylight.
	public static func terminalScheme(following stored: String) -> String {
		switch family(of: stored) {
		case .abydos:  return "abydos"
		case .dracula: return "dracula"
		case .blue:    return "blue"
		}
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

import Foundation

/// What the app looks like: the editor's palette, and the terminal's.
///
/// The two used to be set in two places, which is how somebody ended up with a
/// warm amber editor beside a deep blue terminal without ever choosing that.
/// They are one decision now, made once, with the terminal free to differ where
/// somebody wants it to — a palette is a language people arrive already knowing,
/// and a green-on-black terminal beside a light editor is a real preference and
/// not a mistake.
public enum Appearance {
	/// The palettes the editor offers.
	public enum Theme: String, CaseIterable, Sendable {
		/// Whatever the system is set to, in the plain dark and light palettes.
		case system
		case dark
		case light
		/// The app's own, warm: amber on near-black.
		case abydos
		/// The same warmth in daylight: ink on paper, still amber.
		case abydosLight = "abydos-light"

		public var title: String {
			switch self {
			case .system:      return "System"
			case .dark:        return "Dark"
			case .light:       return "Light"
			case .abydos:      return "Abydos"
			case .abydosLight: return "Abydos Light"
			}
		}

		/// Whether this palette is a light one, given what the system says for
		/// the one that defers to it.
		public func isLight(systemIsDark: Bool) -> Bool {
			switch self {
			case .system:      return !systemIsDark
			case .dark:        return false
			case .light:       return true
			case .abydos:      return false
			case .abydosLight: return true
			}
		}
	}

	/// The value that means "whatever the editor is using".
	///
	/// A value rather than a separate switch: one control that lists the
	/// palettes and has "Same as the editor" at the top of them says both what
	/// is being used and that it follows, where a toggle beside a list leaves
	/// somebody wondering which of the two is in charge.
	public static let followsEditor = "follow"

	/// The terminal palette that goes with an editor palette.
	///
	/// The plain themes pair with the terminal scheme that takes the editor's
	/// own colours, so light and dark follow along by themselves. Abydos pairs
	/// with Abydos, whose own light and dark variants do the same.
	public static func terminalScheme(following theme: Theme) -> String {
		switch theme {
		case .abydos, .abydosLight: return "abydos"
		case .system, .dark, .light: return "dark"
		}
	}

	/// Which terminal palette to actually use.
	///
	/// - Parameter setting: what is stored, which may be `followsEditor`.
	public static func resolvedTerminalScheme(setting: String, theme: Theme) -> String {
		guard setting == followsEditor || setting.isEmpty else { return setting }
		return terminalScheme(following: theme)
	}

	/// What a project opened for the first time should get.
	///
	/// Following the editor, because that is the answer somebody who has not
	/// thought about it wants. Somebody who has thought about it says so, and
	/// then it is never taken away from them again — see `migrate`.
	public static let defaultTerminalSetting = followsEditor

	/// Whether an existing terminal choice should be left alone.
	///
	/// Making "follow the editor" the default is right for a new installation
	/// and wrong for somebody who picked Blue two months ago: an upgrade that
	/// quietly repaints their terminal is a bug with a nice explanation. A
	/// choice that was stored stays stored.
	public static func migratedTerminalSetting(stored: String?) -> String {
		guard let stored, !stored.isEmpty else { return followsEditor }
		return stored
	}
}

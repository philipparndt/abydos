import Foundation

/// One thing the app can be asked to do.
///
/// Named, findable, and carrying whatever key it already answers to. What
/// performs it is not described here: the palette holds the doing and this
/// holds the finding, so the rules for both can be checked without a menu bar.
public struct CommandDescriptor: Equatable, Sendable {
	/// What the action is called, without the menu it sits in.
	public let title: String
	/// The menus it was found under, outermost first — "View", "Appearance".
	/// Shown so two commands with the same name can be told apart, and searched
	/// so "terminal" finds everything under the Terminal menu.
	public let path: [String]
	/// The key it already answers to, as somebody would write it: ⇧⌘P.
	public let shortcut: String?

	public init(title: String, path: [String] = [], shortcut: String? = nil) {
		self.title = title
		self.path = path
		self.shortcut = shortcut
	}

	/// Title with its menu in front, for a row that has to say where it lives.
	public var qualifiedTitle: String {
		path.isEmpty ? title : path.joined(separator: " › ") + " › " + title
	}
}

/// Finding a command by what somebody types.
public enum CommandSearch {
	/// The commands that match, best first.
	///
	/// Ranked rather than filtered, because the list is everything the app can
	/// do: an exact name has to come above a command that merely contains the
	/// letters somewhere, or "open" buries "Open…" under everything with the
	/// word in it.
	public static func match(_ commands: [CommandDescriptor], query: String) -> [CommandDescriptor] {
		let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
		guard !needle.isEmpty else { return commands }

		return commands
			.compactMap { command -> (CommandDescriptor, Int)? in
				guard let score = score(command, needle: needle) else { return nil }
				return (command, score)
			}
			// Stable within a rank: the menu's own order is meaningful, and
			// resorting equal matches alphabetically would scatter the items of
			// a menu somebody is looking down.
			.enumerated()
			.sorted { left, right in
				left.element.1 == right.element.1
					? left.offset < right.offset
					: left.element.1 > right.element.1
			}
			.map(\.element.0)
	}

	/// How well a command answers to what was typed, or nil for not at all.
	static func score(_ command: CommandDescriptor, needle: String) -> Int? {
		let title = command.title.lowercased()

		if title == needle { return 100 }
		if title.hasPrefix(needle) { return 80 }

		// A word in the middle: "split" should find "Split Right" and also
		// "Editor › Split Right", which is the same command said longer.
		if title.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 60 }
		if title.contains(needle) { return 40 }

		// The menu it lives under, so "terminal" lists what the Terminal menu
		// holds even where the items themselves never say the word.
		if command.path.contains(where: { $0.lowercased().contains(needle) }) { return 20 }

		// Letters in order — "sr" for "Split Right" — which is how anybody who
		// knows what they want types it.
		return isSubsequence(needle, of: title) ? 10 : nil
	}

	/// Whether every character of `needle` appears in order in `text`.
	static func isSubsequence(_ needle: String, of text: String) -> Bool {
		var remaining = Substring(needle)
		for character in text where character == remaining.first {
			remaining = remaining.dropFirst()
			if remaining.isEmpty { return true }
		}
		return remaining.isEmpty
	}
}

/// Writing a key equivalent the way a menu does.
///
/// Kept apart from AppKit so the spelling can be checked exhaustively: the
/// order of the symbols is fixed by convention (⌃⌥⇧⌘) and getting it wrong
/// looks like a typo in somebody's muscle memory.
public enum ShortcutText {
	/// - Parameters:
	///   - key: the key equivalent, as a menu stores it — lowercase for a plain
	///     letter, since the shift is carried by the modifiers.
	///   - control/option/shift/command: which modifiers are held.
	public static func describe(
		key: String,
		control: Bool = false,
		option: Bool = false,
		shift: Bool = false,
		command: Bool = false
	) -> String? {
		guard !key.isEmpty else { return nil }

		var text = ""
		if control { text += "⌃" }
		if option { text += "⌥" }
		if shift { text += "⇧" }
		if command { text += "⌘" }
		return text + name(of: key)
	}

	/// What a key is called on a keyboard, for the ones that are not a letter.
	static func name(of key: String) -> String {
		switch key {
		case "\u{8}", "\u{7F}": return "⌫"
		case "\r", "\u{3}":     return "↩"
		case "\t":              return "⇥"
		case "\u{1B}":          return "⎋"
		case " ":               return "Space"
		case "\u{F700}":        return "↑"
		case "\u{F701}":        return "↓"
		case "\u{F702}":        return "←"
		case "\u{F703}":        return "→"
		case "\u{F72C}":        return "⇞"
		case "\u{F72D}":        return "⇟"
		case "\u{F729}":        return "↖"
		case "\u{F72B}":        return "↘"
		default:
			// A letter is written the way it is printed on the key, which is
			// upper case; the shift, where there is one, is already a symbol.
			//
			// Only where the upper case is still *one* character, because for some
			// it is not: `ß` upper-cases to `SS`, and a key equivalent of ß —
			// which is exactly what the system moved ⌘/ to on a German keyboard,
			// see 0479 — was written down as **⌘SS**, a shortcut for a key nobody
			// has. A capital that changes the length of the key is not a capital,
			// it is a spelling rule for words.
			guard key.count == 1 else { return key }
			let capital = key.uppercased()
			return capital.count == 1 ? capital : key
		}
	}
}

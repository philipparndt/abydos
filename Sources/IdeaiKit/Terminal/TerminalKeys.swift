import Foundation

/// Byte sequences for keys that do not simply produce a character.
///
/// Kept out of the view so the table — and the rules for the modifiers applied
/// to it — can be checked without a window and without a running shell.
public enum TerminalKeys {
	/// macOS virtual key codes for the keys with a fixed sequence.
	public enum Key: UInt16 {
		case upArrow = 126
		case downArrow = 125
		case rightArrow = 124
		case leftArrow = 123
		case home = 115
		case end = 119
		case pageUp = 116
		case pageDown = 121
		case forwardDelete = 117
		case backspace = 51
		case Return = 36
		case tab = 48
		case escape = 53
	}

	/// Whether Option should send ESC before this key's own sequence.
	///
	/// Only the keys that stand for a character. Option on an arrow or a
	/// navigation key is spelled inside its CSI sequence instead — `ESC ESC [ D`
	/// is not something any reader understands, and prefixing one would break
	/// word-wise cursor movement rather than enable it.
	///
	/// Return is the one people notice: a program that treats plain Return as
	/// "submit" — a shell, or an agent's prompt — uses ESC Return for "newline
	/// without submitting", so sending a bare carriage return submits the text
	/// the user was trying to break in half.
	public static func takesMetaPrefix(_ key: Key) -> Bool {
		switch key {
		case .Return, .backspace, .tab, .escape, .forwardDelete:
			return true
		case .upArrow, .downArrow, .leftArrow, .rightArrow,
		     .home, .end, .pageUp, .pageDown:
			return false
		}
	}

	/// The sequence for a key that is not an arrow, or nil when it has none.
	///
	/// Arrows are excluded because their encoding depends on the cursor-key
	/// mode the program has selected, which only the emulator knows.
	public static func sequence(for key: Key) -> String? {
		switch key {
		case .home:          return "\u{1B}[H"
		case .end:           return "\u{1B}[F"
		case .pageUp:        return "\u{1B}[5~"
		case .pageDown:      return "\u{1B}[6~"
		case .forwardDelete: return "\u{1B}[3~"
		// DEL rather than BS: what every Unix terminal has sent since the VT220,
		// and what readline expects for "delete backwards".
		case .backspace:     return "\u{7F}"
		case .Return:        return "\r"
		case .tab:           return "\t"
		case .escape:        return "\u{1B}"
		case .upArrow, .downArrow, .leftArrow, .rightArrow: return nil
		}
	}

	/// What a modified navigation key sends, or nil when the key has no special
	/// meaning with that modifier.
	///
	/// These are the readline movements, which is what a shell and a terminal
	/// UI both understand — not the CSI forms with a modifier parameter. A
	/// program has to opt into parsing `ESC [ 1 ; 3 D`, while `ESC b` has meant
	/// "back one word" since long before any of them, and every line editor
	/// handles it.
	///
	/// The mapping is the one macOS users already have: ⌥ moves by word, ⌘ goes
	/// to the ends of the line, matching every native text field.
	public static func editingSequence(for key: Key, option: Bool, command: Bool) -> String? {
		switch key {
		case .leftArrow:
			if command { return "\u{01}" }        // Ctrl-A, start of line
			if option { return "\u{1B}b" }        // Meta-B, back one word
			return nil
		case .rightArrow:
			if command { return "\u{05}" }        // Ctrl-E, end of line
			if option { return "\u{1B}f" }        // Meta-F, forward one word
			return nil
		case .backspace:
			// Ctrl-U, which clears to the start of the line. ⌥⌫ is left to the
			// meta rule, where it becomes ESC DEL — delete one word.
			return command ? "\u{15}" : nil
		default:
			return nil
		}
	}

	/// Applies Option-as-Meta, which sends ESC before the sequence.
	public static func applyingMeta(_ sequence: String, key: Key, optionHeld: Bool) -> String {
		guard optionHeld, takesMetaPrefix(key) else { return sequence }
		return "\u{1B}" + sequence
	}
}

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
		/// The Enter at the bottom right of a numeric keypad.
		///
		/// Needs naming because macOS hands it over as U+0003 — End of Text,
		/// which is to say Ctrl-C. Passed through as the character it claims to
		/// be, it interrupts: in a shell it kills the line being typed, and in
		/// an agent's prompt it throws away the message instead of sending it.
		/// It is a Return, and every other terminal sends one.
		case keypadEnter = 76
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
		case .Return, .keypadEnter, .backspace, .tab, .escape, .forwardDelete:
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
		// The same carriage return as the big one. Programs that want to tell
		// the two apart ask for the keyboard protocol, which reports the key
		// rather than the byte and is handled before this table.
		case .Return, .keypadEnter: return "\r"
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

	/// What Option and a key should send.
	///
	/// Two things want the same modifier and only one of them can have it.
	/// Shells use Option as Meta — ⌥B and ⌥F move by words — and keyboard
	/// layouts outside the US put characters there: on a German layout `{` is
	/// ⌥8, `[` is ⌥5, `}` is ⌥9, `]` is ⌥6, `|` is ⌥7 and `@` is ⌥L.
	///
	/// Meta won unconditionally here, which meant a German keyboard could not
	/// type a brace into a terminal at all — ⌥8 sent `ESC 8`, and the only way
	/// to get a `{` into a shell was to paste it. That is the wrong way round:
	/// a character somebody's keyboard is telling us they typed is not a
	/// modifier gesture, and word-motion is the thing to make optional.
	///
	/// - Parameters:
	///   - composed: what the layout produced with Option held — `event.characters`.
	///   - bare: the same key without modifiers — `event.charactersIgnoringModifiers`.
	///   - asMeta: whether somebody has asked for Option to mean Meta anyway.
	public static func optionOutput(composed: String?, bare: String, asMeta: Bool) -> String {
		guard !asMeta else { return "\u{1B}" + bare }

		// A layout composed something of its own: send that, and nothing else.
		if let composed, composed != bare, isTypable(composed) { return composed }

		// Option added nothing — ⌥B on a US layout gives "∫", but ⌥Left gives
		// no character at all — so it can only have meant Meta.
		return "\u{1B}" + bare
	}

	/// Whether a key event has to be handed to the input manager instead of
	/// being turned into bytes here.
	///
	/// A dead key produces no character of its own: pressing `^` on a German
	/// layout, or ⌥e on a US one, holds the accent back until the next key says
	/// whether it becomes `ê` or `^e`. The layout makes that decision, and only
	/// when the event reaches the input manager. Encoding events ourselves is
	/// why `^` and `` ` `` typed nothing at all — there was no character in the
	/// event to send, so there was nothing to send.
	///
	/// The same door is what a Japanese or Chinese input method comes through,
	/// which is the other thing that could not be typed here.
	public static func needsComposition(
		characters: String?,
		keyCode: UInt16,
		control: Bool,
		command: Bool,
		option: Bool,
		optionAsMeta: Bool,
		composing: Bool
	) -> Bool {
		// A control or command combination is a command, not text.
		if control || command { return false }

		// Option is Meta when it has been asked to be, and Meta never composes.
		if option, optionAsMeta { return false }

		// Once something is being composed every key belongs to it — including
		// the space that turns a pending `^` into a bare circumflex, and the
		// escape that abandons it.
		if composing { return true }

		// A key with a sequence of its own stands for itself. Return carries no
		// character either, and it is not waiting for a second key.
		if Key(rawValue: keyCode) != nil { return false }

		return (characters ?? "").isEmpty
	}

	/// Whether a string is something a program would want as input rather than
	/// as a control code.
	static func isTypable(_ text: String) -> Bool {
		guard !text.isEmpty else { return false }
		return text.unicodeScalars.allSatisfy { scalar in
			scalar.value >= 0x20 && scalar.value != 0x7F
		}
	}
}

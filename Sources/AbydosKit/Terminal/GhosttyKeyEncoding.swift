import Foundation
import GhosttyVt

/// libghostty-vt's own key encoder, driven from our call sites (item 0485).
///
/// Arrow keys and "the unambiguous form of an ambiguous key" both come from
/// here rather than from arithmetic of ours, and there is one reason that is
/// worth more than the tidiness: **xterm's `modifyOtherKeys` is not readable.**
/// libghostty-vt honours `CSI > 4 ; 2 m` and
/// `ghostty_key_encoder_setopt_from_terminal` passes it to the encoder, but no
/// `GHOSTTY_TERMINAL_DATA_*` kind reports it. So an engine that did its own
/// arithmetic from the readable state would see only the kitty flags, and a
/// program using the older protocol — which is most of the ones that use either
/// — would silently get plain bytes. Asking the encoder asks the terminal's real
/// state, both protocols included.
///
/// It also means DECCKM (application cursor keys) is read from the terminal
/// rather than tracked here, and the kitty protocol's full escape-code
/// disambiguation is ghostty's rather than a reimplementation of it.
///
/// The encoder is owned for the life of the engine; `setopt_from_terminal` is
/// called before every encode, because a program changes these modes while it
/// runs and the answer must be the one that is true now.
final class GhosttyKeyEncoding {
	private var encoder: GhosttyKeyEncoder?
	private var event: GhosttyKeyEvent?

	init() {
		var encoder: GhosttyKeyEncoder?
		guard ghostty_key_encoder_new(nil, &encoder) == GHOSTTY_SUCCESS else { return }
		self.encoder = encoder
		var event: GhosttyKeyEvent?
		guard ghostty_key_event_new(nil, &event) == GHOSTTY_SUCCESS else { return }
		self.event = event
	}

	deinit {
		if let event { ghostty_key_event_free(event) }
		if let encoder { ghostty_key_encoder_free(encoder) }
	}

	/// An arrow key, honouring application cursor key mode.
	func arrow(_ direction: TerminalArrowKey, terminal: GhosttyTerminal) -> String? {
		let key: GhosttyKey
		switch direction {
		case .up: key = GHOSTTY_KEY_ARROW_UP
		case .down: key = GHOSTTY_KEY_ARROW_DOWN
		case .right: key = GHOSTTY_KEY_ARROW_RIGHT
		case .left: key = GHOSTTY_KEY_ARROW_LEFT
		}
		return encode(key: key, mods: 0, utf8: nil, terminal: terminal)
	}

	/// The kitty or xterm form of a key, or nil when the program has not asked
	/// for one and the ordinary bytes should be sent.
	///
	/// "Has not asked" is decided by comparing against the same key with no
	/// modifiers: if holding Shift changes nothing about what the terminal would
	/// send, then this terminal is not in a protocol that can say Shift was held,
	/// and the caller's own key handling should have the keystroke back. That is
	/// the same contract `TerminalEmulator.encodeModifiedKey` has, arrived at from
	/// the other direction.
	func modifiedKey(
		code: Int, shift: Bool, option: Bool, control: Bool, command: Bool,
		terminal: GhosttyTerminal
	) -> String? {
		guard let key = Self.key(forCode: code) else { return nil }

		var mods: GhosttyMods = 0
		if shift { mods |= GhosttyMods(GHOSTTY_MODS_SHIFT) }
		if option { mods |= GhosttyMods(GHOSTTY_MODS_ALT) }
		if control { mods |= GhosttyMods(GHOSTTY_MODS_CTRL) }
		if command { mods |= GhosttyMods(GHOSTTY_MODS_SUPER) }
		// Nothing held is what it always was. A protocol that changed those would
		// break every program that only asked about the modified ones.
		guard mods != 0 else { return nil }

		// The text a bare keypress would carry. Without it ghostty's encoder has
		// no way to know what an unmodified `A` means, and the legacy encodings
		// are built out of exactly that.
		let text = Self.text(forCode: code)
		guard let modified = encode(key: key, mods: mods, utf8: text, terminal: terminal),
		      !modified.isEmpty
		else { return nil }
		let plain = encode(key: key, mods: 0, utf8: text, terminal: terminal)
		guard modified != plain else { return nil }
		return modified
	}

	/// Whether the terminal is in a protocol that can report a modifier at all.
	///
	/// Asked of the encoder rather than of the terminal's readable state, which
	/// is the whole reason this type exists: Shift+Enter encoding as something
	/// other than a bare CR is exactly the condition the caller wants, and it is
	/// true for the kitty protocol and for `modifyOtherKeys` alike.
	func reportsModifiedKeys(terminal: GhosttyTerminal) -> Bool {
		modifiedKey(
			code: 13, shift: true, option: false, control: false, command: false,
			terminal: terminal) != nil
	}

	// MARK: - Plumbing

	private func encode(
		key: GhosttyKey, mods: GhosttyMods, utf8: String?, terminal: GhosttyTerminal
	) -> String? {
		guard let encoder, let event else { return nil }
		// Before every encode: a program turns these modes on and off while it
		// runs, so an encoder configured once would answer for the wrong moment.
		ghostty_key_encoder_setopt_from_terminal(encoder, terminal)
		ghostty_key_event_set_action(event, GHOSTTY_KEY_ACTION_PRESS)
		ghostty_key_event_set_key(event, key)
		ghostty_key_event_set_mods(event, mods)
		ghostty_key_event_set_consumed_mods(event, 0)
		if let utf8 {
			let bytes = Array(utf8.utf8)
			bytes.withUnsafeBufferPointer { buffer in
				ghostty_key_event_set_utf8(
					event, buffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
					buffer.count)
			}
			ghostty_key_event_set_unshifted_codepoint(
				event, utf8.unicodeScalars.first?.value ?? 0)
		} else {
			ghostty_key_event_set_utf8(event, nil, 0)
			ghostty_key_event_set_unshifted_codepoint(event, 0)
		}

		var buffer = [CChar](repeating: 0, count: 64)
		var written = 0
		let result = buffer.withUnsafeMutableBufferPointer { out in
			ghostty_key_encoder_encode(encoder, event, out.baseAddress, out.count, &written)
		}
		guard result == GHOSTTY_SUCCESS, written > 0 else { return result == GHOSTTY_SUCCESS ? "" : nil }
		return String(decoding: buffer.prefix(written).map { UInt8(bitPattern: $0) }, as: UTF8.self)
	}

	/// Our callers speak in codepoints — 13 for Return, 9 for Tab, 127 for
	/// Backspace, 27 for Escape, and an ASCII letter otherwise — because that is
	/// what the kitty protocol puts on the wire. ghostty's encoder speaks in
	/// *physical* keys, so this is the one translation between the two models.
	private static func key(forCode code: Int) -> GhosttyKey? {
		switch code {
		case 13: return GHOSTTY_KEY_ENTER
		case 9: return GHOSTTY_KEY_TAB
		case 27: return GHOSTTY_KEY_ESCAPE
		case 127, 8: return GHOSTTY_KEY_BACKSPACE
		case 0x20: return GHOSTTY_KEY_SPACE
		default: break
		}
		// Letters and digits are contiguous in ghostty's enum, so the offset from
		// `A` and `DIGIT_0` is the letter and the digit. Anything else has no
		// physical key we can name, and gets its ordinary bytes.
		if let scalar = UnicodeScalar(UInt32(code)), scalar.isASCII {
			let character = Character(scalar)
			if let letter = character.lowercased().unicodeScalars.first,
			   letter.value >= 0x61, letter.value <= 0x7A {
				return GhosttyKey(
					rawValue: GHOSTTY_KEY_A.rawValue + UInt32(letter.value - 0x61))
			}
			if scalar.value >= 0x30, scalar.value <= 0x39 {
				return GhosttyKey(
					rawValue: GHOSTTY_KEY_DIGIT_0.rawValue + UInt32(scalar.value - 0x30))
			}
		}
		return nil
	}

	/// What the key would type with nothing held.
	private static func text(forCode code: Int) -> String? {
		switch code {
		case 13, 9, 27, 127, 8: return nil
		default:
			guard let scalar = UnicodeScalar(UInt32(code)), scalar.isASCII else { return nil }
			return String(Character(scalar))
		}
	}
}

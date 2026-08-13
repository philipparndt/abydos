import Foundation
import GhosttyVt

/// Key encoding for the libghostty-vt engine (item 0485).
///
/// **libghostty-vt has a key encoder of its own — `ghostty/vt/key/encoder.h` —
/// and it is deliberately not used.** That was not the first plan; it is what
/// measuring it said. Configured from a terminal that has been asked for nothing
/// at all, and again with `MODIFY_OTHER_KEYS_STATE_2` explicitly false and the
/// kitty flags explicitly zero, `ghostty_key_encoder_encode` answers:
///
///     Shift+Enter  ->  ESC [ 27;2;13 ~
///     Enter        ->  CR
///     Ctrl+A       ->  ESC [ 0;5 u
///
/// The first is xterm's `modifyOtherKeys` form sent to a program that never asked
/// for it, and the third is a kitty-protocol sequence with a codepoint of zero.
/// Both are reasonable for ghostty, whose own app always reports modified keys —
/// and both are wrong *here*, because the whole point of the engine setting is
/// that a pane behaves the same either way. A program that gets `ESC [ 27;2;13 ~`
/// under one engine and `CR` under the other is precisely the silent divergence
/// item 0485 exists to prevent.
///
/// So the arithmetic is the same arithmetic `TerminalEmulator` uses, and what
/// comes from libghostty-vt is the *state* that decides it: DECCKM for the arrow
/// keys and the kitty keyboard flags for the modified form. Both are readable, and
/// `GhosttyEngineTests` asserts the two engines produce identical bytes.
///
/// The one thing that is *not* readable, and is therefore named in the engine's
/// `unimplemented`: **xterm's `modifyOtherKeys`**. libghostty-vt honours
/// `CSI > 4 ; 2 m` and hands its state to its own encoder, but no
/// `GHOSTTY_TERMINAL_DATA_*` kind reports it and no probe of the encoder
/// distinguishes it, because the encoder emits that form whether or not it was
/// asked for. Under this engine a program using the older protocol gets ordinary
/// bytes — which is the conservative direction, and what every terminal without
/// the feature does — rather than a sequence it did not ask for.
enum GhosttyKeyEncoding {
	/// The kitty keyboard protocol's flags, as the terminal holds them.
	static func kittyFlags(terminal: GhosttyTerminal) -> UInt8 {
		var flags: UInt8 = 0
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS, &flags)
			== GHOSTTY_SUCCESS
		else { return 0 }
		return flags
	}
}

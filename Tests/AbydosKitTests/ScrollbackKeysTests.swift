import Foundation
import Testing
@testable import AbydosKit

/// Which keys the pane keeps for its own history, and which reach the program.
///
/// There were none: Page Up, Home and the rest all went to the program, so the
/// only way to read a long build log was the wheel — and on a trackpad the
/// wheel was the complaint. Shift plus the four navigation keys is the
/// convention of kitty, Alacritty, GNOME Terminal and iTerm2.
struct ScrollbackKeysTests {
	private func motion(_ key: TerminalKeys.Key, shift: Bool = true, control: Bool = false,
	                    option: Bool = false, command: Bool = false) -> TerminalKeys.ScrollbackMotion? {
		TerminalKeys.scrollbackMotion(
			keyCode: key.rawValue, shift: shift, control: control, option: option, command: command)
	}

	@Test func shiftAndANavigationKeyMovesTheView() {
		#expect(motion(.pageUp) == .pageUp)
		#expect(motion(.pageDown) == .pageDown)
		#expect(motion(.home) == .top)
		#expect(motion(.end) == .bottom)
	}

	/// The unshifted key is the program's: `less` pages on it, and so does an
	/// agent's own history.
	@Test func withoutShiftTheKeyIsTheProgramsAsBefore() {
		#expect(motion(.pageUp, shift: false) == nil)
		#expect(motion(.home, shift: false) == nil)
	}

	/// ⌃⇧⇞ and its neighbours are somebody else's chords, and a pane that
	/// swallowed them would take them away.
	@Test func anotherModifierBesideShiftDisqualifies() {
		#expect(motion(.pageUp, control: true) == nil)
		#expect(motion(.pageUp, option: true) == nil)
		#expect(motion(.end, command: true) == nil)
	}

	@Test func aKeyThatIsNotNavigationIsNotAMotion() {
		#expect(motion(.upArrow) == nil)
		#expect(motion(.tab) == nil)
		#expect(TerminalKeys.scrollbackMotion(keyCode: 0, shift: true, control: false, option: false, command: false) == nil)
	}
}

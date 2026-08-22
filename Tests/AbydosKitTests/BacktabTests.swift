import Foundation
import Testing
@testable import AbydosKit

/// Shift+Tab, which has to be a different three bytes from Tab's one.
///
/// Filed because it was not: the key sent a bare tab, which is the *same* byte
/// Tab sends, so nothing downstream could tell the two apart and every
/// backwards-cycling shortcut silently went forwards or did nothing.
struct BacktabTests {
	private let tab = TerminalKeys.Key.tab.rawValue

	@Test func shiftTabSendsBacktab() {
		#expect(TerminalKeys.backtabSequence(
			keyCode: tab, shift: true, control: false, option: false, command: false
		) == "\u{1B}[Z")
	}

	/// The whole point, stated as the thing that was wrong. A test that only
	/// checked the sequence would have passed against the old code the moment
	/// somebody made Tab send `CSI Z` too.
	@Test func tabAndShiftTabAreNotTheSameBytes() {
		let plain = TerminalKeys.sequence(for: .tab)
		let shifted = TerminalKeys.backtabSequence(
			keyCode: tab, shift: true, control: false, option: false, command: false
		)
		#expect(plain == "\t")
		#expect(shifted != nil)
		#expect(shifted != plain)
	}

	@Test func plainTabIsNotBacktab() {
		#expect(TerminalKeys.backtabSequence(
			keyCode: tab, shift: false, control: false, option: false, command: false
		) == nil)
	}

	/// ⌃⇥ and ⌥⇥ switch panes and windows. A terminal that answered them would
	/// take that away, and neither is a backtab.
	@Test func onlyShiftMakesABacktab() {
		#expect(TerminalKeys.backtabSequence(
			keyCode: tab, shift: true, control: true, option: false, command: false
		) == nil)
		#expect(TerminalKeys.backtabSequence(
			keyCode: tab, shift: true, control: false, option: true, command: false
		) == nil)
		#expect(TerminalKeys.backtabSequence(
			keyCode: tab, shift: true, control: false, option: false, command: true
		) == nil)
	}

	@Test func noOtherKeyIsABacktab() {
		for key in [TerminalKeys.Key.Return, .escape, .backspace, .leftArrow] {
			#expect(TerminalKeys.backtabSequence(
				keyCode: key.rawValue, shift: true, control: false, option: false, command: false
			) == nil)
		}
	}

	/// What the promise actually is: `xterm-256color` is what `PseudoTerminal`
	/// advertises, and its terminfo says `kcbt=\E[Z`. This is the sequence, spelt
	/// the way `infocmp` prints it, so the two cannot drift apart unnoticed.
	@Test func theSequenceIsWhatTheAdvertisedTerminfoPromises() {
		let kcbt = "\u{1B}[Z"
		#expect(kcbt.unicodeScalars.map(\.value) == [0x1B, 0x5B, 0x5A])
		#expect(TerminalKeys.backtabSequence(
			keyCode: tab, shift: true, control: false, option: false, command: false
		) == kcbt)
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// Shift+Return, which has to be a newline and not a submit.
///
/// Reported 2026-09-10: "Standard Zeilenumbruch mit Shift-Return" — the usual
/// line break is Shift+Return, and this terminal wanted Option. It sent a bare
/// carriage return for Shift+Return, the same byte Return sends, so an agent's
/// prompt submitted the half-written message. Most terminals answer both keys.
struct ShiftReturnTests {
	private func sequence(_ key: TerminalKeys.Key, shift: Bool = true, control: Bool = false,
	                      option: Bool = false, command: Bool = false) -> String? {
		TerminalKeys.shiftReturnSequence(
			keyCode: key.rawValue, shift: shift, control: control, option: option, command: command)
	}

	@Test func shiftReturnSendsEscapeThenReturn() {
		#expect(sequence(.Return) == "\u{1B}\r")
		#expect(sequence(.keypadEnter) == "\u{1B}\r")
	}

	/// The same bytes Option+Return sends, on purpose: one meaning, two keys.
	@Test func shiftReturnAndOptionReturnAreTheSameBytes() {
		let option = TerminalKeys.applyingMeta(
			TerminalKeys.sequence(for: .Return)!, key: .Return, optionHeld: true)
		#expect(sequence(.Return) == option)
	}

	/// The point, as the thing that was wrong: a plain Return and a shifted one
	/// must not be the same byte.
	@Test func returnAndShiftReturnAreNotTheSameBytes() {
		#expect(TerminalKeys.sequence(for: .Return) == "\r")
		#expect(sequence(.Return) != TerminalKeys.sequence(for: .Return))
	}

	@Test func plainReturnIsNotANewline() {
		#expect(sequence(.Return, shift: false) == nil)
	}

	/// ⌃⏎ is somebody else's chord and ⌥⏎ has its own rule; neither is this.
	@Test func onlyShiftMakesTheNewline() {
		#expect(sequence(.Return, control: true) == nil)
		#expect(sequence(.Return, option: true) == nil)
		#expect(sequence(.Return, command: true) == nil)
	}

	@Test func aShiftedLetterIsNotANewline() {
		#expect(sequence(.tab) == nil)
		#expect(TerminalKeys.shiftReturnSequence(
			keyCode: 0, shift: true, control: false, option: false, command: false) == nil)
	}
}

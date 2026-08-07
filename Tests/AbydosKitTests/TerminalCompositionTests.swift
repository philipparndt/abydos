import Foundation
import Testing
@testable import AbydosKit

/// Which keys the layout has to be asked about.
///
/// `^` and `` ` `` could not be typed in the terminal at all. Both are dead keys
/// on a German layout: they carry no character until a second key arrives, and
/// every event was being turned into bytes here — where there was no character
/// to turn into anything. The fix is not a table of those two keys but the door
/// they come through, which is the same door every layout and every input method
/// in the world uses.
struct TerminalCompositionTests {
	/// A dead key: no character, nothing pending yet, nothing special about the
	/// key code.
	@Test func asksTheLayoutAboutAKeyThatTypedNothing() {
		#expect(TerminalKeys.needsComposition(
			characters: "", keyCode: 10,
			control: false, command: false, option: false, optionAsMeta: false, composing: false
		))
		#expect(TerminalKeys.needsComposition(
			characters: nil, keyCode: 10,
			control: false, command: false, option: false, optionAsMeta: false, composing: false
		))
	}

	/// An ordinary letter is bytes, and going the long way round would put the
	/// whole keyboard through an input method that has nothing to add.
	@Test func encodesAnOrdinaryKeyDirectly() {
		#expect(!TerminalKeys.needsComposition(
			characters: "a", keyCode: 0,
			control: false, command: false, option: false, optionAsMeta: false, composing: false
		))
	}

	/// The second press belongs to the composition, whatever it is: `e` makes
	/// `ê`, and space makes a bare `^`.
	@Test func givesEveryKeyToAPendingComposition() {
		for character in ["e", " ", "^"] {
			#expect(TerminalKeys.needsComposition(
				characters: character, keyCode: 14,
				control: false, command: false, option: false, optionAsMeta: false, composing: true
			))
		}
	}

	/// ⌃C is a signal, not a letter — and it reaches a program that may well be
	/// what is hanging.
	@Test func neverComposesAControlCombination() {
		#expect(!TerminalKeys.needsComposition(
			characters: "\u{3}", keyCode: 8,
			control: true, command: false, option: false, optionAsMeta: false, composing: true
		))
		#expect(!TerminalKeys.needsComposition(
			characters: "", keyCode: 8,
			control: false, command: true, option: false, optionAsMeta: false, composing: false
		))
	}

	/// Option means Meta when it has been set to, and ⌥F is then a word forward
	/// rather than the start of an accent — which is what ⌥e is on a US layout.
	@Test func leavesOptionAloneWhenItIsMeta() {
		#expect(!TerminalKeys.needsComposition(
			characters: "", keyCode: 14,
			control: false, command: false, option: true, optionAsMeta: true, composing: false
		))
		// With Option as Option, the layout gets to compose.
		#expect(TerminalKeys.needsComposition(
			characters: "", keyCode: 14,
			control: false, command: false, option: true, optionAsMeta: false, composing: false
		))
	}

	/// Return and the arrows carry no character either, and they are not waiting
	/// for a second key. Sending them through composition is how Return would
	/// stop working.
	@Test func keepsTheKeysThatHaveTheirOwnSequence() {
		for key in [TerminalKeys.Key.Return, .escape, .leftArrow, .backspace, .tab] {
			#expect(!TerminalKeys.needsComposition(
				characters: "", keyCode: key.rawValue,
				control: false, command: false, option: false, optionAsMeta: false, composing: false
			))
		}
	}

	/// Once something is pending, even those keys go to the layout: it commits
	/// the accent and hands the key back, which is what `doCommandBySelector`
	/// is there to catch.
	@Test func stillAsksAboutReturnWhileSomethingIsPending() {
		#expect(TerminalKeys.needsComposition(
			characters: "", keyCode: TerminalKeys.Key.Return.rawValue,
			control: false, command: false, option: false, optionAsMeta: false, composing: true
		))
	}
}

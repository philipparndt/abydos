import Foundation
import Testing
@testable import AbydosKit

/// What Option and a key send to a shell.
///
/// Two things want that modifier. Shells use it as Meta — ⌥B and ⌥F move by
/// words — and every keyboard layout outside the US puts characters there. Meta
/// won unconditionally, which meant a German keyboard could not type a brace
/// into a terminal at all: ⌥8 sent `ESC 8`, and the only way to get a `{` into
/// a shell was to paste one.
struct OptionKeyTests {
	/// A German layout, where the characters a programmer needs most all live
	/// behind Option.
	@Test func sendsWhatAGermanLayoutComposes() {
		let cases: [(bare: String, composed: String)] = [
			("8", "{"), ("9", "}"), ("5", "["), ("6", "]"), ("7", "|"), ("l", "@"),
		]
		for (bare, composed) in cases {
			#expect(
				TerminalKeys.optionOutput(composed: composed, bare: bare, asMeta: false) == composed,
				"⌥\(bare) should type \(composed)"
			)
		}
	}

	/// A key that composes nothing can only have meant Meta — ⌥Left, or a
	/// layout where Option does not reach that key.
	@Test func fallsBackToMetaWhenNothingIsComposed() {
		#expect(TerminalKeys.optionOutput(composed: nil, bare: "b", asMeta: false) == "\u{1B}b")
		#expect(TerminalKeys.optionOutput(composed: "b", bare: "b", asMeta: false) == "\u{1B}b")
		#expect(TerminalKeys.optionOutput(composed: "", bare: "f", asMeta: false) == "\u{1B}f")
	}

	/// Control codes are not typing. A layout that answers Option with one has
	/// not composed a character, whatever it returned.
	@Test func ignoresSomethingThatIsNotACharacter() {
		#expect(TerminalKeys.optionOutput(composed: "\u{1B}", bare: "[", asMeta: false) == "\u{1B}[")
		#expect(TerminalKeys.optionOutput(composed: "\u{7F}", bare: "d", asMeta: false) == "\u{1B}d")
	}

	/// And for anybody who wants word-motion back — a US layout, where ⌥B
	/// composing "∫" is less useful than moving back a word.
	@Test func obeysSomebodyWhoAsksForMeta() {
		#expect(TerminalKeys.optionOutput(composed: "∫", bare: "b", asMeta: true) == "\u{1B}b")
		#expect(TerminalKeys.optionOutput(composed: "{", bare: "8", asMeta: true) == "\u{1B}8")
	}

	/// What a US layout does without the setting: Option composes there too,
	/// which is what every other Mac terminal does by default.
	@Test func composesOnAUSLayoutAsWell() {
		#expect(TerminalKeys.optionOutput(composed: "∫", bare: "b", asMeta: false) == "∫")
	}
}

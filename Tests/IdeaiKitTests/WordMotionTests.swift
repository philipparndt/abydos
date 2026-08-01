import Foundation
import Testing
@testable import IdeaiKit

/// Where the next word begins and the previous one ends.
struct WordMotionTests {
	private func units(_ text: String) -> [UInt16] { Array(text.utf16) }

	/// ⌥→ goes to the end of the word ahead, which is what a Mac does.
	@Test func movesToTheEndOfTheWordAhead() {
		let text = units("let value = 42")
		#expect(WordMotion.endOfWord(after: 0, in: text) == 3)   // "let"
		#expect(WordMotion.endOfWord(after: 3, in: text) == 9)   // "value"
		#expect(WordMotion.endOfWord(after: 9, in: text) == 11)  // "="
		#expect(WordMotion.endOfWord(after: 11, in: text) == 14) // "42"
		#expect(WordMotion.endOfWord(after: 14, in: text) == 14) // and stops
	}

	/// ⌥← goes to the start of the word behind. Deliberately not the mirror of
	/// the above: holding one then the other does not return you where you were,
	/// and that is how every Mac text field behaves.
	@Test func movesToTheStartOfTheWordBehind() {
		let text = units("let value = 42")
		#expect(WordMotion.startOfWord(before: 14, in: text) == 12)
		#expect(WordMotion.startOfWord(before: 12, in: text) == 10)
		#expect(WordMotion.startOfWord(before: 10, in: text) == 4)
		#expect(WordMotion.startOfWord(before: 4, in: text) == 0)
		#expect(WordMotion.startOfWord(before: 0, in: text) == 0)
	}

	/// An underscore is part of the identifier, not a break in it.
	@Test func treatsUnderscoreAsPartOfTheWord() {
		let text = units("some_long_name here")
		#expect(WordMotion.endOfWord(after: 0, in: text) == 14)
		#expect(WordMotion.startOfWord(before: 14, in: text) == 0)
	}

	/// A run of punctuation is crossed in one go, not one character at a time.
	@Test func crossesPunctuationInOneStep() {
		let text = units("a ==> b")
		#expect(WordMotion.endOfWord(after: 1, in: text) == 5)
		#expect(WordMotion.startOfWord(before: 5, in: text) == 2)
	}

	@Test func crossesLineBreaks() {
		let text = units("first\nsecond")
		#expect(WordMotion.endOfWord(after: 5, in: text) == 12)
		#expect(WordMotion.startOfWord(before: 6, in: text) == 0)
	}

	@Test func staysInsideTheTextWhereverItIsAsked() {
		let text = units("word")
		#expect(WordMotion.endOfWord(after: 999, in: text) == 4)
		#expect(WordMotion.startOfWord(before: -5, in: text) == 0)
		#expect(WordMotion.endOfWord(after: 0, in: []) == 0)
		#expect(WordMotion.startOfWord(before: 0, in: []) == 0)
	}

	@Test func findsTheWordAroundAPosition() {
		let text = units("let value = 42")
		#expect(WordMotion.wordRange(at: 6, in: text) == 4..<9)
		// A caret just past a word still belongs to it.
		#expect(WordMotion.wordRange(at: 9, in: text) == 4..<9)
		#expect(WordMotion.wordRange(at: 10, in: text) == nil)
	}

	/// What a completion list is filtered by.
	@Test func readsThePrefixBeingTyped() {
		#expect(WordMotion.prefix(before: 8, in: units("let valu")) == "valu")
		#expect(WordMotion.prefix(before: 4, in: units("let ")) == "")
		// Just after the paren there is no word being typed; just before it,
		// the identifier is what a completion list would be filtered by.
		#expect(WordMotion.prefix(before: 11, in: units("foo.barBaz(")) == "")
		#expect(WordMotion.prefix(before: 10, in: units("foo.barBaz(")) == "barBaz")
	}

	/// Text outside the basic plane counts in UTF-16 units, like everything else.
	@Test func countsInUTF16Units() {
		let text = units("emoji 🎈 tail")
		// The balloon is two units, so the word after it starts at 9.
		#expect(WordMotion.endOfWord(after: 5, in: text) == 8)
		#expect(WordMotion.endOfWord(after: 8, in: text) == 13)
	}
}

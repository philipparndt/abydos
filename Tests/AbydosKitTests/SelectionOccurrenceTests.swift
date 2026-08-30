import Foundation
import Testing
@testable import AbydosKit

/// Where else the selected text is.
///
/// The rule is about characters and not about symbols, which is the decision
/// worth having tests around: `count` finds the `count` inside `accountId`, and
/// that is chosen rather than tolerated.
struct SelectionOccurrenceTests {
	@Test func aSelectionFindsItsOtherPlaces() {
		let text = "let count = 0\nif count > 0 { print(count) }\n"
		let selected = ((text as NSString).range(of: "count")).location
		let ranges = SelectionOccurrences.ranges(
			of: "count", in: text, excluding: selected..<(selected + 5)
		)
		#expect(ranges.count == 2)
		// In file order, and past the selection's own place, which is not one of
		// the *other* places.
		#expect(ranges.map(\.lowerBound) == ranges.map(\.lowerBound).sorted())
		#expect(ranges.allSatisfy { $0.lowerBound > selected })
		#expect(ranges.allSatisfy { $0.count == 5 })
	}

	/// A selection is a run of characters, not a symbol. Selecting `count`
	/// lighting the `count` inside `accountId` is the chosen behaviour: a rule
	/// that lit only whole words would light nothing at all for `x + y`.
	@Test func aMatchInsideALongerWordIsAMatch() {
		let ranges = SelectionOccurrences.ranges(of: "count", in: "let accountId = 7")
		#expect(ranges.count == 1)
		#expect(ranges.first?.lowerBound == 6)
	}

	@Test func aDifferentCaseIsADifferentString() {
		#expect(SelectionOccurrences.ranges(of: "Count", in: "count Count count").count == 1)
	}

	@Test func theSelectionsOwnPlaceIsNotOneOfTheOthers() {
		let text = "name name"
		#expect(SelectionOccurrences.ranges(of: "name", in: text, excluding: 0..<4) == [5..<9])
		#expect(SelectionOccurrences.ranges(of: "name", in: text, excluding: 5..<9) == [0..<4])
		// With nothing excluded, both places are answered: the caller that has no
		// selection to leave out is asking a different question.
		#expect(SelectionOccurrences.ranges(of: "name", in: text) == [0..<4, 5..<9])
	}

	/// `aa` is in `aaaa` three times. A scan that stepped over each hit would say
	/// two, which is a wrong answer rather than a conservative one.
	@Test func overlappingOccurrencesAreOccurrences() {
		#expect(SelectionOccurrences.ranges(of: "aa", in: "aaaa") == [0..<2, 1..<3, 2..<4])
	}

	@Test func oneCharacterIsWorthNothing() {
		#expect(SelectionOccurrences.isWorthHighlighting("e") == false)
		#expect(SelectionOccurrences.ranges(of: "e", in: "every letter here").isEmpty)
	}

	@Test func aSelectionAcrossLinesIsWorthNothing() {
		#expect(SelectionOccurrences.isWorthHighlighting("one\ntwo") == false)
		#expect(SelectionOccurrences.ranges(of: "one\ntwo", in: "one\ntwo one\ntwo").isEmpty)
	}

	/// An indent selected would otherwise band every indent in the file.
	@Test func whitespaceAloneIsWorthNothing() {
		#expect(SelectionOccurrences.isWorthHighlighting("    ") == false)
		#expect(SelectionOccurrences.isWorthHighlighting("\t\t") == false)
		// Whitespace *around* something is not whitespace alone.
		#expect(SelectionOccurrences.isWorthHighlighting(" x "))
	}

	@Test func nothingElseIsNoRanges() {
		#expect(SelectionOccurrences.ranges(of: "absent", in: "nothing of the sort here").isEmpty)
	}

	@Test func anEmptySelectionIsWorthNothing() {
		#expect(SelectionOccurrences.isWorthHighlighting("") == false)
		#expect(SelectionOccurrences.ranges(of: "", in: "anything").isEmpty)
	}

	/// The cap is what keeps a common two-character selection in a large file
	/// from building a list nothing will draw.
	@Test func theScanStopsAtTheCap() {
		let text = String(repeating: "ab", count: 100)
		#expect(SelectionOccurrences.ranges(of: "ab", in: text, limit: 10).count == 10)
		#expect(SelectionOccurrences.ranges(of: "ab", in: text).count == 100)
	}

	/// Two characters is about what somebody dragged over, not about how it is
	/// stored: an emoji is one character and four UTF-16 units.
	@Test func twoIsCountedInCharacters() {
		#expect(SelectionOccurrences.isWorthHighlighting("🐞") == false)
		#expect(SelectionOccurrences.isWorthHighlighting("🐞🐞"))
	}
}

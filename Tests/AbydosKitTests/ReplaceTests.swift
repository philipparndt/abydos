import Foundation
import Testing
@testable import AbydosKit

/// Replacing what find found.
///
/// The find bar found and could not replace, so the parts with an answer worth
/// checking — what a replacement means with the `.*` switch on and off, and what
/// a Replace All does to the text between the matches — live here rather than in
/// a view nothing can open.
struct ReplaceTests {
	static let literal = SearchOptions()
	static let regex = SearchOptions(isRegex: true)

	@Test func aLiteralReplacementGoesInAsItself() throws {
		let text = "one two one"
		let edit = try #require(
			TextSearch.replaceAll(in: text, query: "one", options: Self.literal, template: "$1")
		)
		#expect(edit.count == 2)
		// Not a capture: the `.*` switch is off, so a dollar is a dollar and the
		// only way to type one would otherwise be gone.
		#expect(apply(edit, to: text) == "$1 two $1")
	}

	@Test func aCaptureIsPutBackWhereTheTemplateAsksForIt() {
		let text = "user_id and order_id"
		let edit = TextSearch.replaceAll(
			in: text, query: "(\\w+)_id", options: Self.regex, template: "$1Id"
		)
		#expect(edit?.count == 2)
		#expect(apply(edit, to: text) == "userId and orderId")
	}

	@Test func theWholeMatchIsDollarZero() {
		let text = "answer"
		let edit = TextSearch.replaceAll(in: text, query: "a\\w+", options: Self.regex, template: "[$0]")
		#expect(apply(edit, to: text) == "[answer]")
	}

	/// **Foundation substitutes the empty string for a group that does not
	/// exist**, so a mistyped number is a silent deletion of every match. It is
	/// refused instead, and nothing reaches the file.
	@Test func aTemplateNamingAGroupThePatternHasNotIsRefused() {
		let text = "user_id"
		#expect(TextSearch.isValid(template: "$7", query: "(\\w+)_(id)", options: Self.regex) == false)
		#expect(TextSearch.replaceAll(
			in: text, query: "(\\w+)_(id)", options: Self.regex, template: "$7"
		) == nil)
	}

	/// The digits are read the way the engine reads them: as many as still name a
	/// group. `$12` against one group is group 1 and then a `2`, which is what
	/// `replacementString` produces — refusing it would refuse a template that
	/// works.
	@Test func digitsAfterAGroupNumberAreNotPartOfIt() {
		let text = "user_id"
		#expect(TextSearch.isValid(template: "$12", query: "(\\w+)_id", options: Self.regex))
		#expect(apply(
			TextSearch.replaceAll(in: text, query: "(\\w+)_id", options: Self.regex, template: "$12"),
			to: text
		) == "user2")
	}

	@Test func anEscapedDollarIsADollar() {
		let text = "cost"
		#expect(TextSearch.isValid(template: "\\$1", query: "cost", options: Self.regex))
		#expect(apply(
			TextSearch.replaceAll(in: text, query: "cost", options: Self.regex, template: "\\$1"),
			to: text
		) == "$1")
	}

	/// The edit is the smallest span that covers the matches, so what is between
	/// them and what is outside them is not rewritten at all.
	@Test func theTextBetweenTheMatchesIsCarriedThroughUntouched() throws {
		let text = "keep\nfind me\nleave this alone\nfind me\nkeep"
		let span = try #require(TextSearch.replaceAll(
			in: text, query: "find", options: Self.literal, template: "found"
		))
		// Starts at the first match and ends at the last, not at the ends of the
		// file: the two `keep` lines are outside the edit entirely.
		#expect(span.utf16Range.lowerBound == (text as NSString).range(of: "find").location)
		#expect(span.text.contains("leave this alone"))
		#expect(apply(span, to: text) == "keep\nfound me\nleave this alone\nfound me\nkeep")
	}

	@Test func aQueryThatMatchesNothingIsNoEdit() {
		#expect(TextSearch.replaceAll(
			in: "nothing here", query: "absent", options: Self.literal, template: "x"
		) == nil)
	}

	@Test func anEmptyQueryIsNoEdit() {
		#expect(TextSearch.replaceAll(
			in: "anything", query: "", options: Self.literal, template: "x"
		) == nil)
		#expect(TextSearch.replacement(
			forMatchAt: 0..<3, in: "anything", query: "", options: Self.literal, template: "x"
		) == nil)
	}

	@Test func aPatternThatWillNotCompileIsNoEdit() {
		#expect(TextSearch.replaceAll(
			in: "anything", query: "(unclosed", options: Self.regex, template: "x"
		) == nil)
	}

	/// The one match under the caret, which is what the Replace button replaces.
	@Test func oneMatchBecomesItsReplacement() throws {
		let text = "user_id and order_id"
		let matches = TextSearch.matches(in: text, query: "(\\w+)_id", options: Self.regex)
		#expect(matches.count == 2)
		let second = try #require(matches.last)
		#expect(TextSearch.replacement(
			forMatchAt: second.utf16Range,
			in: text, query: "(\\w+)_id", options: Self.regex, template: "$1Id"
		) == "orderId")
	}

	/// A range that was a match when it was found and is not one now — the text
	/// moved underneath it. Nothing is written rather than something wrong.
	@Test func aRangeThatIsNoLongerAMatchReplacesNothing() {
		#expect(TextSearch.replacement(
			forMatchAt: 0..<4, in: "keep this", query: "find", options: Self.literal, template: "x"
		) == "x")
		#expect(TextSearch.replacement(
			forMatchAt: 0..<4, in: "keep this", query: "find", options: Self.regex, template: "x"
		) == nil)
	}

	@Test func aRangeOutsideTheTextReplacesNothing() {
		#expect(TextSearch.replacement(
			forMatchAt: 40..<44, in: "short", query: "s\\w+", options: Self.regex, template: "x"
		) == nil)
	}

	/// What the editor does with the edit, so a test can say what the file
	/// becomes rather than what the span holds.
	private func apply(_ edit: TextSearch.ReplaceAll?, to text: String) -> String? {
		guard let edit else { return nil }
		let ns = text as NSString
		return ns.replacingCharacters(
			in: NSRange(
				location: edit.utf16Range.lowerBound,
				length: edit.utf16Range.count
			),
			with: edit.text
		)
	}
}

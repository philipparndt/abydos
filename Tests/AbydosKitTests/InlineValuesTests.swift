import Foundation
import Testing
@testable import AbydosKit

/// What a stopped frame shows at the end of a line.
///
/// This is the half of the feature with edge cases in it — a name inside a
/// longer one, a name twice, a value the size of a page — and it is here rather
/// than in a screenshot because a hint that names the wrong variable is read as
/// fact. The drawing is placement and is checked by driving.
struct InlineValuesTests {
	private let frame = [
		"count": "12",
		"total": "480",
		"name": "\"holder\"",
	]

	@Test func aLineNamingAVariableShowsItsValue() {
		let hints = InlineValues.hints(in: "count += 1", from: frame)
		#expect(hints.map(\.text) == ["count = 12"])
	}

	/// **The bug this rule exists for.** `count` inside `counter` is a different
	/// variable, and a value pinned to it is a lie in the same grey as the truth.
	@Test func aNameIsNotFoundInsideALongerName() {
		for line in ["counter += 1", "account.total", "discount = 5", "recounted()"] {
			#expect(
				InlineValues.hints(in: line, from: ["count": "12"]).isEmpty,
				"\(line) should name nothing"
			)
		}
	}

	/// A member of something else is not the local of the same name.
	@Test func aNameAfterADotIsSomebodyElsesMember() {
		#expect(InlineValues.hints(in: "self.count", from: frame).isEmpty)
		#expect(InlineValues.hints(in: "shape.total", from: frame).isEmpty)
		// The receiver is still matched: it is a name on its own.
		let hints = InlineValues.hints(in: "count.description", from: frame)
		#expect(hints.map(\.name) == ["count"])
	}

	@Test func aNameTwiceOnALineIsOneHint() {
		let hints = InlineValues.hints(in: "count = count + 1", from: frame)
		#expect(hints.map(\.text) == ["count = 12"])
	}

	/// Reading order is the only order that means anything at the end of a line.
	@Test func namesComeInTheOrderTheyOccurOnTheLine() {
		let hints = InlineValues.hints(in: "total = count * 40", from: frame)
		#expect(hints.map(\.name) == ["total", "count"])
	}

	/// A struct's value is a page and a `[]byte` is four kilobytes; neither is a
	/// hint. The whole value is still in the variables tree.
	@Test func aValueTooLargeForALineIsCut() {
		let long = String(repeating: "x", count: 200)
		let hints = InlineValues.hints(in: "count", from: ["count": long], budget: 10)
		#expect(hints.first?.value == "xxxxxxxxxx\u{2026}")
	}

	/// Nothing can push the drawing onto a second line, because there is no
	/// second line to push it onto.
	@Test func aValueWithNewlinesBecomesOneLine() {
		let value = "Point {\n  x: 1\n  y: 2\n}"
		let summary = InlineValues.summary(of: value, budget: 100)
		#expect(!summary.contains("\n"))
		#expect(summary == "Point { x: 1 y: 2 }")
	}

	/// This runs per visible row while somebody scrolls, so the common answer —
	/// a line that names nothing — is the cheap one.
	@Test func aLineThatNamesNothingIsAnsweredAsNothing() {
		#expect(InlineValues.hints(in: "// a comment about nothing", from: frame).isEmpty)
		#expect(InlineValues.hints(in: "", from: frame).isEmpty)
		#expect(InlineValues.hints(in: "count", from: [:]).isEmpty)
	}

	/// An adapter answers `scopes` from the inside out, so a name in two of them
	/// is the nearer one.
	@Test func theInnermostScopeWins() {
		var locals = Scope(name: "Locals", variablesReference: 1)
		locals.variables = [Variable(name: "n", value: "inner", type: nil, variablesReference: 0)]
		var globals = Scope(name: "Globals", variablesReference: 2)
		globals.variables = [Variable(name: "n", value: "outer", type: nil, variablesReference: 0)]

		#expect(InlineValues.byName([locals, globals])["n"] == "inner")
	}
}

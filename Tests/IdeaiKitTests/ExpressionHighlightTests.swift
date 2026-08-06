import Foundation
import Testing
@testable import IdeaiKit

/// Colouring a breakpoint's condition, which is code typed without an editor.
struct ExpressionHighlightTests {
	@Test func coloursAGoCondition() {
		let tokens = ExpressionHighlight.tokens(in: "id == \"lamarzocco\"", languageId: "go")
		#expect(!tokens.isEmpty)

		// The string is found, and its range is within what was typed rather
		// than shifted by the wrapper that made it parse.
		let text = "id == \"lamarzocco\""
		let string = tokens.first { $0.kind == .string }
		let range = try? #require(string?.range)
		#expect(range != nil)
		if let range {
			#expect(range.lowerBound >= 0)
			#expect(range.upperBound <= text.utf16.count)
		}
	}

	/// The wrapper exists so a fragment parses at all; anything it contributes
	/// belongs to it and not to what somebody typed.
	@Test func rangesBelongToTheFragment() {
		let text = "len(os.Args) > 2"
		for token in ExpressionHighlight.tokens(in: text, languageId: "go") {
			#expect(token.range.lowerBound >= 0)
			#expect(token.range.upperBound <= text.utf16.count)
		}
	}

	@Test func saysNothingAboutAnEmptyOrUnknownFragment() {
		#expect(ExpressionHighlight.tokens(in: "", languageId: "go").isEmpty)
		#expect(ExpressionHighlight.tokens(in: "i > 5", languageId: "no-such-language").isEmpty)
	}

	/// A log message is not code, but the part in braces is: `i is {i}` prints
	/// a sentence with a value in it, and the braces say which part is which.
	@Test func findsWhatALogMessageInterpolates() {
		#expect(ExpressionHighlight.interpolations(in: "i is {i}") == [5..<8])
		#expect(ExpressionHighlight.interpolations(in: "args is {len(os.Args)}") == [8..<22])
		#expect(ExpressionHighlight.interpolations(in: "nothing here").isEmpty)
	}

	/// Nested braces close once, at the outer one — `{f({x})}` is one
	/// expression, not two — and an unclosed brace colours nothing rather than
	/// colouring the rest of the line.
	@Test func handlesNestingAndTheUnfinished() {
		#expect(ExpressionHighlight.interpolations(in: "{f({x})}") == [0..<8])
		#expect(ExpressionHighlight.interpolations(in: "half {open").isEmpty)
		#expect(ExpressionHighlight.interpolations(in: "stray } brace").isEmpty)
	}

	@Test func findsSeveralInOneMessage() {
		#expect(ExpressionHighlight.interpolations(in: "{a} and {b}") == [0..<3, 8..<11])
	}
}

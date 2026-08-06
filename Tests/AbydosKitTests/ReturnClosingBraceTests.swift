import Foundation
import Testing
@testable import AbydosKit

/// Return after an opening brace that nothing closes.
///
/// Typing `{` and pressing return is how a block gets opened, and finishing it
/// by hand — down a line, out a level, type the brace — is a chore an editor
/// should have saved.
struct ReturnClosingBraceTests {
	@Test func writesTheClosingBrace() {
		let result = ReturnIndent.result(
			before: "func main() {", after: "", usesTabs: true, indentWidth: 4, unclosed: true
		)
		#expect(result.text == "\n\t\n}")
		// The caret waits on the blank line between the halves.
		#expect(result.caretOffset == 2)
	}

	/// The indent of the line that opened it, not of the caret: a block opened
	/// two levels in closes two levels in.
	@Test func closesAtTheOpeningLinesIndent() {
		let result = ReturnIndent.result(
			before: "\t\tif x {", after: "", usesTabs: true, indentWidth: 4, unclosed: true
		)
		#expect(result.text == "\n\t\t\t\n\t\t}")
	}

	/// Brackets and parentheses too, since they open blocks the same way.
	@Test func closesWhateverWasOpened() {
		#expect(ReturnIndent.result(
			before: "let values = [", after: "", usesTabs: true, indentWidth: 4, unclosed: true
		).text == "\n\t\n]")
		#expect(ReturnIndent.result(
			before: "call(", after: "", usesTabs: true, indentWidth: 4, unclosed: true
		).text == "\n\t\n)")
	}

	/// A colon opens a block in Python and closes with nothing, so return
	/// indents and writes no closing anything.
	@Test func writesNothingForAColon() {
		let result = ReturnIndent.result(
			before: "def thing():", after: "", usesTabs: false, indentWidth: 4, unclosed: true
		)
		#expect(result.text == "\n    ")
	}

	/// The old behaviour where the file is already balanced: indent, and leave
	/// the braces alone. An editor that adds one nobody asked for is worse than
	/// one that adds none.
	@Test func addsNothingWhenTheFileIsBalanced() {
		let result = ReturnIndent.result(
			before: "func main() {", after: "", usesTabs: true, indentWidth: 4, unclosed: false
		)
		#expect(result.text == "\n\t")
	}

	/// And the case that already worked: the caret between a pair splits them,
	/// whatever the rest of the file says.
	@Test func stillSplitsAPairTheCaretSitsIn() {
		let result = ReturnIndent.result(
			before: "if x {", after: "}", usesTabs: true, indentWidth: 4, unclosed: false
		)
		#expect(result.text == "\n\t\n")
		#expect(result.caretOffset == 2)
	}

	/// Counting is what decides it: more opens than closes means the block the
	/// caret is in has no end yet.
	@Test func countsWhatTheFileHasOpen() {
		#expect(ReturnIndent.isUnclosed("func a() {", opening: "{", closing: "}"))
		#expect(!ReturnIndent.isUnclosed("func a() {\n}", opening: "{", closing: "}"))
		#expect(ReturnIndent.isUnclosed("{ { }", opening: "{", closing: "}"))
		#expect(!ReturnIndent.isUnclosed("", opening: "{", closing: "}"))
	}
}

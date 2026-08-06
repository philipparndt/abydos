import Foundation
import Testing
@testable import AbydosKit

/// What pressing return should actually insert.
struct ReturnIndentTests {
	private func press(_ before: String, _ after: String = "", tabs: Bool = false, width: Int = 4)
		-> ReturnIndent.Result {
		ReturnIndent.result(before: before, after: after, usesTabs: tabs, indentWidth: width)
	}

	/// The common case: stay where the line started.
	@Test func keepsTheCurrentIndent() {
		let result = press("        let value = 1")
		#expect(result.text == "\n        ")
		#expect(result.caretOffset == result.text.utf16.count)
	}

	@Test func indentsAfterAnOpeningBrace() {
		#expect(press("func run() {").text == "\n    ")
		#expect(press("    if x {").text == "\n        ")
		#expect(press("\tif x {", tabs: true).text == "\n\t\t")
	}

	/// Brackets and parentheses open a block too, as does a trailing colon —
	/// which is the whole of Python's block syntax.
	@Test func indentsAfterAnythingThatOpens() {
		#expect(press("let items = [").text == "\n    ")
		#expect(press("call(").text == "\n    ")
		#expect(press("def run():").text == "\n    ")
	}

	/// Trailing spaces after the brace must not stop it being an opening.
	@Test func looksPastTrailingSpaces() {
		#expect(press("func run() {   ").text == "\n    ")
	}

	/// Return between a pair puts the closing half on its own line and leaves
	/// the caret on a blank line between them.
	@Test func splitsAPairOntoThreeLines() {
		let result = press("func run() {", "}")
		#expect(result.text == "\n    \n")
		#expect(result.caretOffset == 5)

		// What the document ends up looking like.
		let before = "func run() {"
		let after = "}"
		let whole = before + result.text + after
		#expect(whole == "func run() {\n    \n}")

		// And the caret is on the blank middle line, indented.
		let uptoCaret = before + String(result.text.prefix(result.caretOffset))
		#expect(uptoCaret == "func run() {\n    ")
	}

	@Test func splitsAPairInsideAnIndentedBlock() {
		let result = press("        if x {", "}")
		#expect(result.text == "\n            \n        ")
		#expect(result.caretOffset == 13)
	}

	/// A closing brace ahead of the caret only splits when something opened
	/// just behind it.
	@Test func doesNotSplitWhenNothingWasOpened() {
		let result = press("    let x = y", "}")
		#expect(result.text == "\n    ")
	}

	@Test func handlesAnEmptyLine() {
		#expect(press("").text == "\n")
		#expect(press("    ").text == "\n    ")
	}

	// MARK: - Dedenting a closing brace

	@Test func dedentsAClosingBraceOnItsOwnLine() {
		#expect(ReturnIndent.shouldDedent(afterTyping: "}", lineBefore: "        "))
		#expect(ReturnIndent.shouldDedent(afterTyping: ")", lineBefore: "\t\t"))
		#expect(ReturnIndent.shouldDedent(afterTyping: "]", lineBefore: ""))
	}

	/// Typing a bracket in the middle of a line must not move the line.
	@Test func leavesBracketsInTheMiddleOfALineAlone() {
		#expect(!ReturnIndent.shouldDedent(afterTyping: "}", lineBefore: "    let x = y["))
		#expect(!ReturnIndent.shouldDedent(afterTyping: "]", lineBefore: "    items[0"))
		#expect(!ReturnIndent.shouldDedent(afterTyping: "x", lineBefore: "    "))
	}

	@Test func takesOffExactlyOneLevel() {
		#expect(ReturnIndent.dedented("        ", usesTabs: false, indentWidth: 4) == "    ")
		#expect(ReturnIndent.dedented("\t\t", usesTabs: true, indentWidth: 4) == "\t")
		#expect(ReturnIndent.dedented("", usesTabs: false, indentWidth: 4) == "")
	}

	/// Indentation that is not a whole number of levels loses what is there
	/// rather than more than there is.
	@Test func survivesPartialIndentation() {
		#expect(ReturnIndent.dedented("  ", usesTabs: false, indentWidth: 4) == "")
	}

	// MARK: - Which convention the file uses

	/// The file's own habit beats the setting.
	@Test func followsWhateverTheFileAlreadyDoes() {
		let tabbed = "func a() {\n\tlet x = 1\n\tlet y = 2\n}\n"
		#expect(ReturnIndent.usesTabs(in: tabbed, default: false))

		let spaced = "func a() {\n    let x = 1\n    let y = 2\n}\n"
		#expect(!ReturnIndent.usesTabs(in: spaced, default: true))
	}

	@Test func fallsBackToTheSettingForAFileWithNoIndentation() {
		#expect(ReturnIndent.usesTabs(in: "one\ntwo\n", default: true))
		#expect(!ReturnIndent.usesTabs(in: "one\ntwo\n", default: false))
		#expect(ReturnIndent.usesTabs(in: "", default: true))
	}

	@Test func readsTheLeadingWhitespace() {
		#expect(ReturnIndent.leadingWhitespace(of: "    let x") == "    ")
		#expect(ReturnIndent.leadingWhitespace(of: "\t\tlet x") == "\t\t")
		#expect(ReturnIndent.leadingWhitespace(of: "let x") == "")
		#expect(ReturnIndent.leadingWhitespace(of: "   ") == "   ")
	}
}

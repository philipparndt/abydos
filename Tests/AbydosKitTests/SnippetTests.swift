import Foundation
import Testing
@testable import AbydosKit

/// Completions written in the snippet syntax.
///
/// The case that started this is verbatim from openscad-lsp: typing `unio` and
/// pressing Tab put `union() $0` into the file — a syntax error, and one
/// somebody has to notice and delete.
struct SnippetTests {
	@Test func putsTheCaretWhereTheServerAsked() {
		let snippet = Snippet.expand("union() $0")
		#expect(snippet.text == "union() ")
		#expect(snippet.caret == 8)
	}

	/// A placeholder leaves its default behind, which is text to type over
	/// rather than text to delete.
	@Test func leavesTheDefaultText() {
		let snippet = Snippet.expand("translate(${1:[0, 0, 0]}) $0")
		#expect(snippet.text == "translate([0, 0, 0]) ")
		#expect(snippet.caret == 21)
	}

	/// With no `$0`, the caret goes to the first thing worth typing over.
	@Test func fallsBackToTheFirstStop() {
		let snippet = Snippet.expand("cube(${1:size})")
		#expect(snippet.text == "cube(size)")
		#expect(snippet.caret == 5)
	}

	/// A choice offers several; the first is what goes in.
	@Test func takesTheFirstChoice() {
		let snippet = Snippet.expand("rotate(${1|x,y,z|})$0")
		#expect(snippet.text == "rotate(x)")
		#expect(snippet.caret == 9)
	}

	/// An escaped dollar is a dollar. Shell completions are full of them, and
	/// eating one would rewrite somebody's command.
	@Test func respectsEscapes() {
		#expect(Snippet.expand("echo \\$PATH").text == "echo $PATH")
		#expect(Snippet.expand("\\${not a stop}").text == "${not a stop}")
		#expect(Snippet.expand("back\\\\slash").text == "back\\slash")
	}

	/// A dollar that begins nothing is a dollar.
	@Test func leavesALoneDollarAlone() {
		#expect(Snippet.expand("costs $").text == "costs $")
		#expect(Snippet.expand("$ echo").text == "$ echo")
	}

	/// Something that is not a snippet comes back as it was, with the caret at
	/// the end — which is what inserting a plain completion does.
	@Test func leavesPlainTextAlone() {
		let snippet = Snippet.expand("difference")
		#expect(snippet.text == "difference")
		#expect(snippet.caret == 10)
	}

	/// Defaults can hold placeholders of their own.
	@Test func expandsANestedPlaceholder() {
		let snippet = Snippet.expand("for (${1:${2:i}} = [0:1]) {$0}")
		#expect(snippet.text == "for (i = [0:1]) {}")
		#expect(snippet.caret == 17)
	}

	/// Several stops: the numbered ones leave their text, `$0` decides where
	/// the caret lands, wherever it appears.
	@Test func handlesSeveralStops() {
		let snippet = Snippet.expand("module ${1:name}(${2:args}) {\n\t$0\n}")
		#expect(snippet.text == "module name(args) {\n\t\n}")
		// After the tab on the empty line, which is index 21.
		#expect(snippet.caret == 21)
	}

	@Test func survivesTheMalformed() {
		// An unclosed brace is text, not a crash.
		#expect(Snippet.expand("${1:unclosed").text == "${1:unclosed")
		#expect(Snippet.expand("").text.isEmpty)
		#expect(Snippet.expand("$").text == "$")
	}
}

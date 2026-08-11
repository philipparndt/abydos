import Foundation
import Testing
@testable import AbydosKit

/// ⌘/ over a caret and over a selection.
///
/// Every test here is one of the six ways this goes subtly wrong, which is why
/// the toggle is a value in the engine rather than a method on a view: none of
/// these could be checked by pressing the key and looking.
struct LineCommentTests {
	/// Reaches for the block out of a toggle, or fails the test saying which
	/// outcome came back instead.
	private func toggled(
		_ block: String, _ syntax: CommentSyntax = .line("//")
	) -> LineComment.Toggle? {
		guard case let .toggled(toggle) = LineComment.toggle(block, syntax: syntax) else {
			Issue.record("expected a toggle for “\(block)”")
			return nil
		}
		return toggle
	}

	// MARK: - One direction for the whole block

	@Test func commentsEveryLineTheSelectionTouches() throws {
		let toggle = try #require(toggled("one\ntwo\nthree"))
		#expect(toggle.text == "// one\n// two\n// three")
		#expect(toggle.commenting)
	}

	@Test func takesTheCommentOffAgain() throws {
		let toggle = try #require(toggled("// one\n// two"))
		#expect(toggle.text == "one\ntwo")
		#expect(!toggle.commenting)
	}

	/// The whole block goes one way. Toggling each line independently would turn
	/// a half-commented block into its inverse, so the second press would not
	/// give back what the first one found — which is the one property a toggle
	/// has to have.
	@Test func aHalfCommentedBlockIsCommentedRatherThanInverted() throws {
		let first = try #require(toggled("// one\ntwo\nthree"))
		#expect(first.text == "// // one\n// two\n// three")

		let second = try #require(toggled(first.text))
		#expect(second.text == "// one\ntwo\nthree")
	}

	@Test func pressingItTwiceLeavesAnIndentedBlockExactlyAsItWas() throws {
		let block = "\tif condition {\n\t\tdoSomething()\n\t}"
		let commented = try #require(toggled(block))
		#expect(try #require(toggled(commented.text)).text == block)
	}

	// MARK: - Which column

	/// At the shallowest indent the range shares. Column zero would flatten the
	/// shape of the code somebody is reading it by, which is most of what makes
	/// a commented-out block still readable.
	@Test func insertsAtTheShallowestSharedIndent() throws {
		let toggle = try #require(toggled("\tlet a = 1\n\t\tlet b = 2"))
		#expect(toggle.text == "\t// let a = 1\n\t// \tlet b = 2")
	}

	/// A Makefile: the target is at column zero and its recipe begins with a
	/// tab, so the shared indent is nothing and `#` goes at the front of both.
	@Test func aMakefileRecipeIsCommentedAtColumnZero() throws {
		let toggle = try #require(toggled("build:\n\tswift build", .line("#")))
		#expect(toggle.text == "# build:\n# \tswift build")
	}

	/// The longest common *prefix* and not the smallest visual width, and this is
	/// the case that tells them apart: a width of one would name a column that is
	/// inside the tab on the first line and between two spaces on the second, and
	/// inserting there splits the indentation it was meant to keep.
	@Test func mixedTabsAndSpacesFallBackToColumnZeroRatherThanSplittingAnIndent() throws {
		let toggle = try #require(toggled("\tone\n    two"))
		#expect(toggle.text == "// \tone\n//     two")
	}

	/// Uncommenting works off each line's own indent, not the range's shared
	/// one: a file commented by another editor has its tokens at column zero and
	/// those have to come off too.
	@Test func takesTheTokenOffWhereverItIs() throws {
		let toggle = try #require(toggled("// let a = 1\n\t\t// let b = 2"))
		#expect(toggle.text == "let a = 1\n\t\tlet b = 2")
	}

	// MARK: - Blank lines

	@Test func leavesBlankLinesBlank() throws {
		let toggle = try #require(toggled("one\n\ntwo"))
		#expect(toggle.text == "// one\n\n// two")
	}

	/// The trap this is here for: an empty line has no comment on it and never
	/// will have, so counting it as *uncommented* would make one blank line in
	/// the middle of a commented block flip the press back to “comment again”.
	@Test func oneBlankLineInACommentedBlockDoesNotFlipTheToggle() throws {
		let toggle = try #require(toggled("// one\n\n// two"))
		#expect(toggle.text == "one\n\ntwo")
		#expect(!toggle.commenting)
	}

	/// Whitespace-only counts as blank, or a line with a stray tab on it would
	/// be the one thing keeping a block from uncommenting.
	@Test func aLineOfNothingButWhitespaceIsBlankToo() throws {
		let toggle = try #require(toggled("// one\n \t\n// two"))
		#expect(toggle.text == "one\n \t\ntwo")
	}

	@Test func aRangeOfNothingButBlankLinesIsLeftAlone() {
		#expect(LineComment.toggle("\n  \n", syntax: .line("//")) == .nothing)
		#expect(LineComment.toggle("", syntax: .line("//")) == .nothing)
	}

	/// The edits come back one per line including the untouched ones, so a
	/// caret's line finds its edit by index rather than by searching.
	@Test func theEditsAreOnePerLineIncludingTheBlankOnes() throws {
		let toggle = try #require(toggled("one\n\ntwo"))
		#expect(toggle.edits.count == 3)
		#expect(!toggle.edits[0].isEmpty)
		#expect(toggle.edits[1].isEmpty)
		#expect(!toggle.edits[2].isEmpty)
	}

	// MARK: - What uncommenting removes

	/// Exactly what commenting inserts: the token, and the one space after it
	/// only if it is there. A file whose author wrote `//code` must not come
	/// back as ` code`, which would reindent it one column per press.
	@Test func removesTheSpaceOnlyWhenThereIsOne() throws {
		let toggle = try #require(toggled("//code\n// spaced"))
		#expect(toggle.text == "code\nspaced")
	}

	/// A tab after the token is not the space commenting inserts, so it stays.
	@Test func doesNotTakeATabForTheInsertedSpace() throws {
		let toggle = try #require(toggled("//\tcode"))
		#expect(toggle.text == "\tcode")
	}

	@Test func aCommentWithNothingAfterItComesBackEmpty() throws {
		let toggle = try #require(toggled("//"))
		#expect(toggle.text == "")
	}

	/// The cost of `//code` counting as commented, written down because it is a
	/// real consequence rather than an oversight: Swift's `/// doc` counts too,
	/// and uncommenting it gives `/ doc`. Xcode and VS Code both do this, and the
	/// alternative is the comment table knowing every language's doc-comment
	/// forms.
	@Test func aDocCommentIsTreatedAsACommentTheWayEveryEditorDoes() throws {
		let toggle = try #require(toggled("/// doc"))
		#expect(toggle.text == "/ doc")
	}

	// MARK: - Languages with no line comment

	/// Not silence. A keystroke that does nothing at all is the worst of the
	/// three answers, so the refusal carries the sentence that gets said.
	@Test func aLanguageWithNoLineCommentRefusesAndSaysWhy() {
		let outcome = LineComment.toggle("a { color: red }", syntax: .forLanguage("css"))
		guard case let .unavailable(reason) = outcome else {
			Issue.record("CSS should refuse rather than mangle")
			return
		}
		#expect(reason.contains("/*"))
	}

	@Test func aFileOfNoKnownLanguageRefusesToo() {
		guard case .unavailable = LineComment.toggle("some text", syntax: .forLanguage(nil)) else {
			Issue.record("an unknown language should refuse rather than guess a token")
			return
		}
	}

	// MARK: - Where the selection ends up

	/// A caret keeps its place in the text: it was in front of `a` and it is in
	/// front of `a` afterwards, three columns further along because that is where
	/// `a` now is.
	@Test func aCaretStaysWithTheCharacterItWasInFrontOf() throws {
		let toggle = try #require(toggled("let a = 1"))
		#expect(toggle.text == "// let a = 1")
		#expect(toggle.offset(4) == 7)
		#expect(toggle.offset(0) == 3)
	}

	@Test func aSelectionEndsUpOverTheSameCharacters() throws {
		let toggle = try #require(toggled("let a = 1"))
		// “a = 1”, which is 4..<9 before and has to be 7..<12 after.
		#expect(toggle.offset(4) == 7)
		#expect(toggle.offset(9) == 12)
	}

	@Test func uncommentingBringsTheCaretBackWithIt() throws {
		let toggle = try #require(toggled("// let a = 1"))
		#expect(toggle.offset(7) == 4)
	}

	/// A caret sitting in the middle of the token being taken away has nowhere
	/// else to be than where the token started.
	@Test func aCaretInsideTheTokenLandsWhereTheTokenWas() throws {
		let toggle = try #require(toggled("\t// x"))
		#expect(toggle.offset(2) == 1)
		#expect(toggle.offset(1) == 1)
	}

	/// Across lines, which is where the arithmetic could quietly be one line's
	/// worth of insertion out.
	@Test func anOffsetOnALaterLineIsCarriedByEveryInsertionBeforeIt() throws {
		let toggle = try #require(toggled("one\ntwo"))
		#expect(toggle.text == "// one\n// two")
		// The `t` of `two` is at 4 before and 10 after.
		#expect(toggle.offset(4) == 10)
		#expect(toggle.offset(7) == 13)
	}

	/// An untouched blank line in the middle must not shift what follows it.
	@Test func aBlankLineContributesNothingToTheArithmetic() throws {
		let toggle = try #require(toggled("one\n\ntwo"))
		#expect(toggle.text == "// one\n\n// two")
		// The `t` of `two`: 5 before (3 + 1 + 0 + 1), 11 after.
		#expect(toggle.offset(5) == 11)
	}

	// MARK: - Real files of each shape

	/// Indented Swift, the shape most of this repository is, with a blank line in
	/// the middle of it.
	@Test func indentedSwiftKeepsItsShape() throws {
		let block = "\tprivate func reload() {\n\t\tguard let document else { return }\n\n"
			+ "\t\tdocument.refresh()\n\t}"
		let commented = try #require(toggled(block, .forLanguage("swift")))
		#expect(commented.text == "\t// private func reload() {\n\t// \tguard let document else { return }\n\n"
			+ "\t// \tdocument.refresh()\n\t// }")
		#expect(try #require(toggled(commented.text, .forLanguage("swift"))).text == block)
	}

	@Test func aMakefileUsesHashAndSurvivesTheRoundTrip() throws {
		let block = "test:\n\tswift test\n\n\techo done"
		let commented = try #require(toggled(block, .forLanguage("make")))
		#expect(commented.text == "# test:\n# \tswift test\n\n# \techo done")
		#expect(try #require(toggled(commented.text, .forLanguage("make"))).text == block)
	}

	@Test func yamlUsesHashAtTheDepthItIsNestedAt() throws {
		let block = "  image: alpine\n  ports:\n    - 8080:8080"
		let commented = try #require(toggled(block, .forLanguage("yaml")))
		#expect(commented.text == "  # image: alpine\n  # ports:\n  #   - 8080:8080")
		#expect(try #require(toggled(commented.text, .forLanguage("yaml"))).text == block)
	}

	@Test func plantUMLUsesAnApostrophe() throws {
		let commented = try #require(toggled("Alice -> Bob", .forLanguage("plantuml")))
		#expect(commented.text == "' Alice -> Bob")
	}
}

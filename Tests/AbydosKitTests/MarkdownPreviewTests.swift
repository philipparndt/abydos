import Foundation
import Testing
@testable import AbydosKit

/// What the markdown preview's parser is given, and what comes back out of it.
///
/// The three faults these cover were found in a real shopping list, kept as
/// `Fixtures/shopping-list.md`: emphasis inside a link was dropped, a bold cell
/// beginning with `~` rendered with its asterisks showing, and `---:` did
/// nothing. Two of them are Foundation's parser being wrong rather than being
/// used wrongly, so the assertions run the repaired source back through it —
/// asserting the repair's *output text* would only say that this file agrees
/// with itself.
struct MarkdownPreviewTests {
	/// One run of the parsed result: what it says and what it is wearing.
	private struct Piece {
		var text: String
		var bold = false
		var italic = false
		var code = false
		var struck = false
		var link: String?
	}

	private func parse(_ markdown: String) -> [Piece] {
		var options = AttributedString.MarkdownParsingOptions()
		options.interpretedSyntax = .full
		options.failurePolicy = .returnPartiallyParsedIfPossible
		options.allowsExtendedAttributes = true
		let source = MarkdownSource.repaired(markdown)
		guard let parsed = try? AttributedString(markdown: source, options: options) else { return [] }
		return parsed.runs.map { run in
			let intent = run.inlinePresentationIntent ?? []
			return Piece(
				text: String(parsed[run.range].characters),
				bold: intent.contains(.stronglyEmphasized),
				italic: intent.contains(.emphasized),
				code: intent.contains(.code),
				struck: intent.contains(.strikethrough),
				link: run.link?.absoluteString
			)
		}
	}

	private func text(_ pieces: [Piece]) -> String { pieces.map(\.text).joined() }

	private func fixture() throws -> String {
		let url = try #require(Bundle.module.url(
			forResource: "shopping-list", withExtension: "md", subdirectory: "Fixtures"
		))
		return try String(contentsOf: url, encoding: .utf8)
	}

	// MARK: - Emphasis inside a link

	@Test func emphasisInsideALinkIsApplied() {
		let pieces = parse("[Multiplex Birke **15 mm**, 250 × 125 cm](https://example.com/x)")
		#expect(text(pieces) == "Multiplex Birke 15 mm, 250 × 125 cm")
		#expect(pieces.allSatisfy { $0.link == "https://example.com/x" })
		let bold = pieces.filter(\.bold)
		#expect(bold.map(\.text) == ["15 mm"])
	}

	@Test func aLinkThatIsEntirelyEmphasisedIsStillOneLink() {
		let pieces = parse("[**everything**](https://example.com/x)")
		#expect(text(pieces) == "everything")
		#expect(pieces.allSatisfy { $0.bold && $0.link == "https://example.com/x" })
	}

	@Test func italicAndStrikethroughComeOutOfALabelToo() {
		#expect(parse("[a *b* c](https://x.com)").filter(\.italic).map(\.text) == ["b"])
		#expect(parse("[a ~~b~~ c](https://x.com)").filter(\.struck).map(\.text) == ["b"])
	}

	/// A label with nothing to move is left exactly as written, so the common
	/// case never goes near the rewrite.
	@Test func aPlainLabelIsNotRewritten() {
		#expect(MarkdownSource.liftedLinkEmphasis("[plain](https://x.com)") == "[plain](https://x.com)")
		#expect(MarkdownSource.repaired("see [the docs](./a_b.md)") == "see [the docs](./a_b.md)")
	}

	/// A code span stays inside the link rather than being lifted out of it: a
	/// label that *is* a code span would otherwise stop being a link at all.
	@Test func aCodeSpanInALabelKeepsTheLink() {
		let pieces = parse("[run `make build` first](https://x.com)")
		#expect(text(pieces) == "run make build first")
		#expect(pieces.allSatisfy { $0.link == "https://x.com" })
	}

	/// An image is not a link, and its label must not be taken apart.
	@Test func anImageIsLeftAlone() {
		#expect(MarkdownSource.repaired("![alt **b**](x.png)") == "![alt **b**](x.png)")
	}

	// MARK: - A stray tilde

	@Test func aBoldRunBeginningWithATildeIsBold() {
		let pieces = parse("**~ 211 €**")
		#expect(pieces.map(\.text) == ["~ 211 €"])
		#expect(pieces.allSatisfy { $0.bold })
	}

	@Test func theTildeHasNothingToDoWithBeingTheLastCell() {
		// The report blamed the row splitter. It is the same in the first cell,
		// with no table anywhere near it.
		#expect(parse("**~ 211 €** and **Summe**").filter(\.bold).map(\.text) == ["~ 211 €", "Summe"])
		#expect(parse("*~ 2 €*").filter(\.italic).map(\.text) == ["~ 2 €"])
	}

	@Test func realStrikethroughIsNotTouched() {
		#expect(MarkdownSource.escapedStrayTildes("Leim ~~D3~~ D4") == "Leim ~~D3~~ D4")
		#expect(parse("Leim ~~D3~~ D4").filter(\.struck).map(\.text) == ["D3"])
		#expect(parse("~a~").filter(\.struck).map(\.text) == ["a"])
		#expect(parse("**~~struck~~ and bold**").filter(\.bold).map(\.text) == ["struck", " and bold"])
	}

	@Test func aTildeInCodeIsLeftAsItIs() {
		#expect(MarkdownSource.repaired("`rm -rf ~ x`") == "`rm -rf ~ x`")
		let fenced = "```sh\nrm -rf ~ x\n[a **b**](u)\n```"
		#expect(MarkdownSource.repaired(fenced) == fenced)
		let tildeFence = "~~~sh\ncd ~ && ls\n~~~"
		#expect(MarkdownSource.repaired(tildeFence) == tildeFence)
	}

	/// An indented block is a quotation, and this repository's backlog is full
	/// of them quoting exactly the bug above.
	@Test func anIndentedBlockIsQuotedRatherThanRepaired() {
		let quoted = "What fails:\n\n    \"**~ 211**\"  ->  literal\n    [a **b**](u)\n"
		#expect(MarkdownSource.repaired(quoted) == quoted)
		// A list item's own indented continuation is prose, not a quotation.
		let item = "- an item\n\n    with **~ 211 €** under it\n"
		#expect(MarkdownSource.repaired(item).contains("**\\~ 211 €**"))
	}

	// MARK: - The neighbours: emphasis inside other containers

	@Test func emphasisSurvivesInsideAHeadingAListAndAQuote() {
		#expect(parse("## Der Preis ist **~ 211 €**").filter(\.bold).map(\.text) == ["~ 211 €"])
		#expect(parse("- Die **15 mm** Platte").filter(\.bold).map(\.text) == ["15 mm"])
		#expect(parse("> Zuschnitt kostet **extra**, ~ 2 €").filter(\.bold).map(\.text) == ["extra"])
	}

	@Test func aLinkWithEmphasisWorksInsideAHeadingAListAndAQuote() {
		for container in ["## ", "- ", "> "] {
			let pieces = parse(container + "[a **b** c](https://x.com)")
			#expect(pieces.filter(\.bold).map(\.text) == ["b"], "in \(container.debugDescription)")
			#expect(pieces.filter { $0.link != nil }.map(\.text).joined() == "a b c")
		}
	}

	// MARK: - Rows and columns

	@Test func alignmentsAreReadOffTheDelimiterRow() {
		#expect(MarkdownTable.alignments(inDelimiterRow: "|---|---|---|---:|")
			== [.leading, .leading, .leading, .trailing])
		#expect(MarkdownTable.alignments(inDelimiterRow: "| :--- | :---: | ---: |")
			== [.leading, .center, .trailing])
	}

	@Test func aDelimiterRowIsToldFromAParagraphThatStartsWithABar() {
		#expect(MarkdownTable.isDelimiterRow("|---|---:|"))
		#expect(MarkdownTable.isDelimiterRow("| --- | --- |"))
		#expect(!MarkdownTable.isDelimiterRow("| | |"))
		#expect(!MarkdownTable.isDelimiterRow("| a | b |"))
		#expect(!MarkdownTable.isDelimiterRow("nothing"))
	}

	@Test func anEscapedBarIsContentRatherThanAColumn() {
		#expect(MarkdownTable.cells(in: "| Kantenband \\| gerollt | Baumarkt | 2 |")
			== ["Kantenband \\| gerollt", "Baumarkt", "2"])
		// And the backslash survives to the inline parser, which is what turns
		// it back into a bar on screen.
		#expect(text(parse("Kantenband \\| gerollt")) == "Kantenband | gerollt")
	}

	@Test func emptyCellsAreKeptWhereverTheyAre() {
		#expect(MarkdownTable.cells(in: "| | | **Summe** | **~ 211 €** |")
			== ["", "", "**Summe**", "**~ 211 €**"])
		#expect(MarkdownTable.cells(in: "| a | b") == ["a", "b"])
	}

	// MARK: - The document this came from

	@Test func theShoppingListRendersTheWayItReads() throws {
		let document = try fixture()
		let lines = document.components(separatedBy: "\n").filter { $0.hasPrefix("|") }
		let rows = lines.map { MarkdownTable.cells(in: $0) }

		// Every row is four columns wide, including the one with a bar in it.
		#expect(rows.allSatisfy { $0.count == 4 }, "widths: \(rows.map(\.count))")
		let delimiter = try #require(lines.first { MarkdownTable.isDelimiterRow($0) })
		#expect(MarkdownTable.alignments(inDelimiterRow: delimiter)
			== [.leading, .leading, .leading, .trailing])

		// The first cell of the first body row, and the last cell of the last.
		let link = parse(rows[2][0])
		#expect(link.filter(\.bold).map(\.text) == ["15 mm"])
		#expect(link.allSatisfy { $0.link == "https://example.com/multiplex-birke" })

		let total = parse(rows[rows.count - 1][3])
		#expect(total.map(\.text) == ["~ 211 €"])
		#expect(total.allSatisfy { $0.bold })
	}
}

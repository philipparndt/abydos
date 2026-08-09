import Foundation
import Testing
@testable import AbydosKit

/// Cutting drawable fences out of a Markdown document.
///
/// The preview draws a ```` ```mermaid ```` block as the diagram it describes,
/// and everything that decides *which* text that is happens here, before a web
/// view is involved at all. The cases below are the ones that would put the
/// wrong string into a renderer or take a bite out of the prose around it.
struct MarkdownFenceTests {
	private func fixture(_ name: String) throws -> String {
		let url = try #require(Bundle.module.url(
			forResource: name, withExtension: "md", subdirectory: "Fixtures"
		))
		return try String(contentsOf: url, encoding: .utf8)
	}

	private func diagrams(_ markdown: String) -> [MarkdownFence.Drawn] {
		MarkdownFence.split(markdown).compactMap {
			if case let .drawn(block) = $0 { return block }
			return nil
		}
	}

	private func prose(_ markdown: String) -> String {
		MarkdownFence.split(markdown).compactMap {
			if case let .prose(text) = $0 { return text }
			return nil
		}.joined(separator: "\n")
	}

	// MARK: - What is a diagram

	@Test func aMermaidFenceComesOutAsADiagram() {
		let pieces = MarkdownFence.split("""
			Before.

			```mermaid
			flowchart TD
			    A --> B
			```

			After.
			""")
		#expect(pieces.count == 3)
		guard case let .drawn(block) = pieces[1] else {
			Issue.record("the fence did not come out as a diagram")
			return
		}
		#expect(block.language == "mermaid")
		#expect(block.source == "flowchart TD\n    A --> B")
		#expect(block.openingLine == 3)
	}

	@Test func aFenceOfAnyOtherLanguageIsLeftAsProse() {
		let markdown = "```swift\nlet a = 1\n```\n"
		#expect(diagrams(markdown).isEmpty)
		#expect(prose(markdown) == markdown)
	}

	@Test func aFenceWithNoLanguageIsLeftAsProse() {
		#expect(diagrams("```\nplain\n```\n").isEmpty)
	}

	@Test func theLanguageIsReadWhateverItsCase() {
		#expect(diagrams("```Mermaid\ngraph TD\n```").count == 1)
	}

	@Test func aLanguageWithSomethingAfterItIsStillMermaid() {
		// GitHub's own fences carry attributes after the language, and a block
		// that stopped being a diagram because somebody wrote a title on it would
		// be a mystery rather than a rule.
		#expect(diagrams("```mermaid title=\"one\"\ngraph TD\n```").count == 1)
	}

	// MARK: - Where a fence ends

	@Test func aTildeFenceIsAFenceToo() {
		let found = diagrams("~~~mermaid\ngraph TD\n~~~\n")
		#expect(found.count == 1)
		#expect(found.first?.source == "graph TD")
	}

	@Test func aBacktickInsideATildeFenceDoesNotEndIt() {
		let found = diagrams("~~~mermaid\ngraph TD\n```\nA --> B\n~~~\n")
		#expect(found.first?.source == "graph TD\n```\nA --> B")
	}

	@Test func aLongerFenceIsClosedOnlyByOneAsLong() {
		let found = diagrams("````mermaid\ngraph TD\n```\nstill inside\n````\n")
		#expect(found.first?.source == "graph TD\n```\nstill inside")
	}

	@Test func aFenceThatIsNeverClosedIsLeftAsProse() {
		// CommonMark runs it to the end of the file, and a diagram from a block
		// somebody is still opening is a diagram of half a sentence. It reads as
		// the code block it was before this existed.
		let markdown = "```mermaid\nflowchart TD\n    A --> B\n"
		#expect(diagrams(markdown).isEmpty)
		#expect(prose(markdown) == markdown)
	}

	@Test func theClosingFenceMayNotCarryAnythingElse() {
		let found = diagrams("```mermaid\ngraph TD\n``` not a close\n```\n")
		#expect(found.first?.source == "graph TD\n``` not a close")
	}

	// MARK: - Indenting

	@Test func anIndentedFenceLosesItsOwnIndentAndNoMore() {
		// The fence's indent is the block's margin; anything deeper is the
		// diagram's own shape, which in Mermaid is how a subgraph is written.
		let found = diagrams("""
			  ```mermaid
			  flowchart TD
			      subgraph one
			      end
			  ```
			""")
		#expect(found.first?.source == "flowchart TD\n    subgraph one\n    end")
	}

	@Test func fourSpacesIsAnIndentedCodeBlockRatherThanAFence() {
		#expect(diagrams("    ```mermaid\n    graph TD\n    ```\n").isEmpty)
	}

	// MARK: - The neighbours

	@Test func proseKeepsEveryCharacterAroundADiagram() {
		let markdown = "# Title\n\n```mermaid\ngraph TD\n```\n\nAfter **it**.\n"
		#expect(prose(markdown) == "# Title\n\n\nAfter **it**.\n")
	}

	@Test func aTableInsideADiagramIsNotATable() {
		// A sequence diagram's own lines look like other things, which is why the
		// fences come out before anything else is looked for.
		let found = diagrams("```mermaid\nflowchart LR\n    A[\"| a | b |\"]\n```\n")
		#expect(found.first?.source.contains("| a | b |") == true)
	}

	@Test func severalFencesEachComeOutWithTheirOwnLine() throws {
		let found = diagrams(try fixture("diagrams"))
		#expect(found.count == 3)
		#expect(found.map { $0.source.split(separator: "\n").first ?? "" }
			== ["flowchart TD", "sequenceDiagram", "stateDiagram-v2"])
		// Counted from 1, so a complaint about line 2 of the second block is
		// line 27 of the file.
		#expect(found.map(\.openingLine) == [8, 25, 45])
	}

	@Test func aDocumentWithNoFenceIsOnePieceOfProse() throws {
		let pieces = MarkdownFence.split(try fixture("shopping-list"))
		#expect(pieces.count == 1)
	}
}

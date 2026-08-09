import Foundation
import Testing
@testable import AbydosKit

/// What the pictures out of a Markdown document are called, and which of them
/// are written.
///
/// The two questions 0425 left open, answered without drawing anything. A `.mmd`
/// file is one diagram and its picture is named after it; a README is four
/// diagrams and neither the gesture nor the name fell out of drawing them. The
/// gesture is settled by there being no gesture — `Export ▸` over the document
/// writes every block — so everything left to decide is here, in the naming.
struct MarkdownDiagramExportTests {
	private func fixture(_ name: String) throws -> String {
		let url = try #require(Bundle.module.url(
			forResource: name, withExtension: "md", subdirectory: "Fixtures"
		))
		return try String(contentsOf: url, encoding: .utf8)
	}

	private let readme = URL(fileURLWithPath: "/w/docs/README.md")

	private func names(
		_ markdown: String, format: DiagramFormat = .png, theme: DiagramTheme? = .light
	) -> [String] {
		DiagramExport.fenced(in: markdown, of: readme, format: format, theme: theme)
			.map(\.destination.lastPathComponent)
	}

	// MARK: - Which blocks there are

	/// Three fences of three different kinds, and nothing else in the document
	/// mistaken for one — the pipe table and the Swift block are prose.
	@Test func everyDrawableFenceIsAPictureAndNothingElseIs() throws {
		let document = try fixture("diagrams")
		let found = DiagramExport.fences(in: document)
		#expect(found.count == 3)
		#expect(found.allSatisfy { $0.language == "mermaid" })
		#expect(found[0].source.hasPrefix("flowchart TD"))
		#expect(found[1].source.hasPrefix("sequenceDiagram"))
		#expect(found[2].source.hasPrefix("stateDiagram-v2"))
	}

	/// A block somebody has opened and not written in yet is not a diagram, for
	/// the same reason the preview shows it as code: there is nothing to draw,
	/// and asking Mermaid would stop the export of every other block in the file.
	@Test func aFenceWithNothingInItIsNotExported() {
		let document = """
		```mermaid
		```

		```mermaid
		%% still thinking
		```

		```mermaid
		flowchart TD
		    A --> B
		```
		"""
		#expect(DiagramExport.fences(in: document).count == 1)
		#expect(names(document) == ["README-1.png"])
	}

	@Test func aDocumentWithNoFenceInItHasNothingToExport() {
		#expect(DiagramExport.fences(in: "# Notes\n\nNo diagram here.\n").isEmpty)
	}

	// MARK: - What the pictures are called

	/// Never a bare `README.png`: a Markdown document is not a diagram, so a
	/// picture named after the whole file would claim to be a picture of the
	/// document — and `README.md` and `README.puml` sit in one folder quite
	/// happily, where they would otherwise both write `README.png`.
	@Test func anUntitledBlockIsNamedAfterItsPlaceAndNeverAfterTheWholeFile() throws {
		#expect(try names(fixture("diagrams"))
			== ["README-1.png", "README-2.png", "README-3.png"])
		// Including the only one in a document with one, so that adding a second
		// fence does not rename the first.
		#expect(names("```mermaid\nflowchart TD\n A --> B\n```") == ["README-1.png"])
	}

	/// A fence's front matter `title:` is the one thing in a Markdown block that
	/// *is* a name — it belongs to the diagram rather than to the prose around
	/// it, Mermaid draws it into the picture, and `README-checkout.png` says what
	/// it is a picture of where a number does not.
	@Test func aBlockThatNamesItselfIsNamedAfterItself() {
		let document = """
		```mermaid
		---
		title: Checkout
		---
		flowchart TD
		    A --> B
		```
		"""
		#expect(names(document) == ["README-checkout.png"])
	}

	/// The position counts *every* drawable block rather than only the anonymous
	/// ones, so giving one diagram a title does not renumber the pictures beside
	/// it.
	@Test func namingOneBlockDoesNotRenumberTheOthers() {
		let document = """
		```mermaid
		flowchart TD
		    A --> B
		```

		```mermaid
		---
		title: Checkout
		---
		flowchart TD
		    C --> D
		```

		```mermaid
		flowchart TD
		    E --> F
		```
		"""
		#expect(names(document) == ["README-1.png", "README-checkout.png", "README-3.png"])
	}

	/// The first block to claim a name keeps it, so a title typed today never
	/// renames a picture written last week.
	@Test func aSecondBlockWithTheSameTitleFallsBackToItsPlace() {
		let document = """
		```mermaid
		---
		title: Checkout
		---
		flowchart TD
		    A --> B
		```

		```mermaid
		---
		title: Checkout!
		---
		flowchart TD
		    C --> D
		```
		"""
		#expect(names(document) == ["README-checkout.png", "README-2.png"])
	}

	/// The numbers belong to the positions. A title that came out as `3` would be
	/// a name saying "the third block" about a block that is not it — and
	/// `3 dark` would collide with the third block's dark picture.
	@Test func aTitleThatWouldReadAsAPositionIsNotUsed() {
		#expect(DiagramExport.slug("2") == nil)
		#expect(DiagramExport.slug("2 dark") == nil)
		#expect(DiagramExport.slug("!!!") == nil)
		#expect(DiagramExport.slug("Step 2") == "step-2")
	}

	/// Letters and digits kept, everything else collapsed to one `-` — including
	/// the `/` and `:` a file name may not hold at all — and a sentence used as a
	/// title capped rather than becoming a name nobody can read.
	@Test func aTitleBecomesSomethingAFolderCanHold() {
		#expect(DiagramExport.slug("Ordering a Shelf") == "ordering-a-shelf")
		#expect(DiagramExport.slug("  What / when: how?  ") == "what-when-how")
		#expect(DiagramExport.slug("build → deploy") == "build-deploy")
		let long = DiagramExport.slug(String(repeating: "ab ", count: 40))
		#expect((long?.count ?? 0) <= 40)
		#expect(long?.hasSuffix("-") == false)
	}

	// MARK: - How it composes with the theme

	/// `-dark` goes on the end of whichever name the block got, so the two rules
	/// compose rather than fight.
	@Test func darkGoesOnTheEndOfEveryKindOfName() {
		let document = """
		```mermaid
		---
		title: Checkout
		---
		flowchart TD
		    A --> B
		```

		```mermaid
		flowchart TD
		    C --> D
		```
		"""
		#expect(names(document, theme: .dark)
			== ["README-checkout-dark.png", "README-2-dark.png"])
		#expect(names(document, format: .svg, theme: .light)
			== ["README-checkout.svg", "README-2.svg"])
	}

	/// 0429's rule applied a block at a time, because a look is stated a block at
	/// a time: the fence that chose is drawn its own way and keeps the plain
	/// name, while the one beside it follows what was asked for.
	@Test func aBlockThatChoseItsOwnLookKeepsThePlainName() {
		let document = """
		```mermaid
		%%{init: {'theme': 'forest'}}%%
		flowchart TD
		    A --> B
		```

		```mermaid
		flowchart TD
		    C --> D
		```
		"""
		let blocks = DiagramExport.fenced(in: document, of: readme, format: .png, theme: .dark)
		#expect(blocks.map(\.theme) == [nil, .dark])
		#expect(blocks.map(\.destination.lastPathComponent)
			== ["README-1.png", "README-2-dark.png"])
	}

	/// A document does not have a look; each fence does. So it states one only
	/// when every fence has — which is the only case where offering `PNG (Dark)`
	/// would offer a difference that does not exist.
	@Test func aDocumentStatesALookOnlyWhenEveryBlockDoes() throws {
		let chosen = """
		```mermaid
		%%{init: {'theme': 'forest'}}%%
		flowchart TD
		    A --> B
		```
		"""
		let mixed = chosen + "\n\n```mermaid\nflowchart TD\n    C --> D\n```\n"
		#expect(DiagramExport.statedLook(inMarkdown: chosen) != nil)
		#expect(DiagramExport.statedLook(inMarkdown: mixed) == nil)
		#expect(try DiagramExport.statedLook(inMarkdown: fixture("diagrams")) == nil)
		#expect(DiagramExport.statedLook(inMarkdown: "# Nothing here\n") == nil)
		// And the one question the menus ask reaches it for a `.md`.
		#expect(DiagramExport.statedLook(of: readme, source: chosen) != nil)
	}

	// MARK: - Whether there is anything to export at all

	/// `isDiagram` is a question about the name and this is a question about the
	/// contents. An `Export ▸` over every `.md` in a repository would be wrong far
	/// more often than right.
	@Test func aMarkdownFileIsExportableOnlyWhenSomethingIsWrittenInIt() throws {
		#expect(DiagramExport.holdsADiagram(readme, source: try fixture("diagrams")))
		#expect(!DiagramExport.holdsADiagram(readme, source: "# Notes\n\nNothing.\n"))
		// Everything else is still decided by its name alone.
		#expect(DiagramExport.holdsADiagram(URL(fileURLWithPath: "/w/a.puml")))
		#expect(DiagramExport.holdsADiagram(URL(fileURLWithPath: "/w/a.mmd")))
		#expect(!DiagramExport.holdsADiagram(URL(fileURLWithPath: "/w/a.swift")))
	}

	// MARK: - What may be written over

	/// **A new name is not a new stamp.** The refusal reads the bytes of whatever
	/// is already at these paths and never the name, so every picture out of a
	/// Markdown document is protected and replaceable by exactly the rules
	/// `diagram.png` is — with nothing new to recognise.
	@Test func theseNamesAreProtectedByTheSameStampAsEveryOtherPicture() {
		let ours = DiagramStamp.sign(svg: "<svg/>", tool: .mermaid)
		let strangers = "<svg><text>a screenshot with an unlucky name</text></svg>"
		var files: [String: Data] = [
			"/w/docs/README-1.svg": Data(ours.utf8),
			"/w/docs/README-checkout-dark.svg": Data(ours.utf8),
		]
		func reading(_ url: URL) -> Data? { files[url.path] }

		let both = [
			URL(fileURLWithPath: "/w/docs/README-1.svg"),
			URL(fileURLWithPath: "/w/docs/README-checkout-dark.svg"),
		]
		#expect(DiagramExport.refusal(toWrite: both, reading: reading) == nil)

		files["/w/docs/README-checkout-dark.svg"] = Data(strangers.utf8)
		let refused = DiagramExport.refusal(toWrite: both, reading: reading)
		#expect(refused?.contains("README-checkout-dark.svg") == true)
	}
}

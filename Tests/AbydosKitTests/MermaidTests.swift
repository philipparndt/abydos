import Foundation
import Testing
@testable import AbydosKit

/// What a Mermaid file is, and the two pieces of tidying that have to happen to
/// what `mermaid.render` gives back before it is worth showing or writing.
///
/// None of this draws anything. The drawing is a live test, and these are the
/// rules that decide whether what it drew is usable.
struct MermaidTests {
	// MARK: - Which files

	@Test func theExtensionsMermaidsOwnToolingUses() {
		#expect(Mermaid.isDiagram(URL(fileURLWithPath: "/p/flow.mmd")))
		#expect(Mermaid.isDiagram(URL(fileURLWithPath: "/p/Sequence.MERMAID")))
		#expect(!Mermaid.isDiagram(URL(fileURLWithPath: "/p/notes.md")))
		#expect(!Mermaid.isDiagram(URL(fileURLWithPath: "/p/design.puml")))
	}

	/// Both tools' files, because the tree's Export item and the preview pane
	/// both ask this one question rather than one each.
	@Test func bothKindsOfDiagramAreDiagrams() {
		#expect(DiagramExport.isDiagram(URL(fileURLWithPath: "/p/flow.mmd")))
		#expect(DiagramExport.isDiagram(URL(fileURLWithPath: "/p/design.puml")))
		#expect(!DiagramExport.isDiagram(URL(fileURLWithPath: "/p/main.swift")))
	}

	@Test func aMermaidFileOpensAsTextAndDiagramTogether() {
		let url = URL(fileURLWithPath: "/p/flow.mmd")
		#expect(FilePreview.kind(for: url) == .mermaid)
		#expect(FilePreview.kind(for: url)?.isDiagram == true)
		#expect(FilePreview.defaultMode(for: url) == .splitRight)
		#expect(FilePreview.availableModes(for: url) == PreviewMode.allCases)
	}

	// MARK: - Whether there is anything to draw

	/// A file somebody has just made, or one that is nothing but a heading of
	/// `%%` comments, is the ordinary state of a new document rather than an
	/// error to draw at them.
	@Test func nothingYetIsNotADiagram() {
		#expect(!Mermaid.hasDiagram(""))
		#expect(!Mermaid.hasDiagram("\n   \n\t\n"))
		#expect(!Mermaid.hasDiagram("%% the deployment\n%% written 2026-08-09\n"))
		#expect(Mermaid.hasDiagram("%% the deployment\nflowchart TD\n  A --> B\n"))
		#expect(Mermaid.hasDiagram("sequenceDiagram\n  A->>B: hi\n"))
	}

	// MARK: - A drawing with a size of its own

	/// `mermaid.render` returns `width="100%"` with the real width hidden in a
	/// `max-width`, which is right for a page and wrong for a file: an SVG with
	/// no intrinsic size rasterises into a browser's default 300×150 box.
	@Test func aDrawingIsGivenTheSizeItsViewBoxDeclares() {
		let drawn = """
		<svg id="d" width="100%" xmlns="http://www.w3.org/2000/svg" class="flowchart" \
		style="max-width: 281.96875px;" viewBox="0 0 281.96875 491.375"><g/></svg>
		"""
		let sized = Mermaid.sized(drawn)
		#expect(sized.contains("width=\"281.969\""))
		#expect(sized.contains("height=\"491.375\""))
		#expect(!sized.contains("100%"))
		#expect(!sized.contains("max-width"))
		// Everything else is left exactly as it was.
		#expect(sized.contains("viewBox=\"0 0 281.96875 491.375\""))
		#expect(sized.contains("class=\"flowchart\""))
		#expect(sized.contains("<g/>"))
	}

	/// A whole number is written as one. `width="650.0"` is legal and looks like
	/// a bug in a file somebody opens.
	@Test func aWholeNumberOfPixelsHasNoDecimalPoint() {
		let drawn = "<svg width=\"100%\" style=\"max-width: 650px;\" viewBox=\"-50 -10 650 363\"/>"
		let sized = Mermaid.sized(drawn)
		#expect(sized.contains("width=\"650\""))
		#expect(sized.contains("height=\"363\""))
	}

	/// The attribute is matched with the space in front of it, or `width` finds
	/// `stroke-width` and takes a slice out of the middle of the tag.
	@Test func aStrokeWidthIsNotTheDrawingsWidth() {
		let drawn = "<svg stroke-width=\"2\" width=\"100%\" viewBox=\"0 0 10 20\"/>"
		let sized = Mermaid.sized(drawn)
		#expect(sized.contains("stroke-width=\"2\""))
		#expect(sized.contains("width=\"10\""))
		#expect(sized.contains("height=\"20\""))
	}

	/// Nothing to go on is nothing to change. A drawing this cannot read is
	/// still a drawing, and cutting it about would be worse than leaving it.
	@Test func aDrawingWithNoViewBoxIsLeftAlone() {
		let drawn = "<svg width=\"12\" height=\"9\"><g/></svg>"
		#expect(Mermaid.sized(drawn) == drawn)
		#expect(Mermaid.sized("not a drawing at all") == "not a drawing at all")
	}

	// MARK: - What Mermaid says is wrong

	/// The real thing, copied from what `mermaid.render` threw: four lines, of
	/// which the first three are the line number and a copy of the source with a
	/// caret under it, and neither survives being put in a one-line notice.
	@Test func aParseErrorBecomesOneSentenceWithTheLineInIt() {
		let thrown = """
		Parse error on line 3:
		...otavalidline ??? %%%
		-----------------------^
		Expecting '()', 'SOLID_OPEN_ARROW', 'DOTTED_OPEN_ARROW', 'SOLID_ARROW', \
		'SOLID_ARROW_TOP', got 'NEWLINE'
		"""
		let fault = Mermaid.fault(message: thrown, line: 3)
		#expect(fault.line == 3)
		#expect(fault.message.hasPrefix("Expecting '()', 'SOLID_OPEN_ARROW', 'DOTTED_OPEN_ARROW'"))
		#expect(fault.message.contains("2 others"))
		#expect(fault.message.hasSuffix("got 'NEWLINE'"))
		#expect(!fault.message.contains("\n"))
		#expect(fault.sentence(for: "flow.mmd").hasPrefix("flow.mmd line 3: Expecting"))
	}

	/// When the thrown object carried no `hash` to read the line from, the
	/// message names it and that is where it comes from.
	@Test func theLineIsReadOffTheMessageWhenNothingElseCarriesIt() {
		let fault = Mermaid.fault(
			message: "Parse error on line 12:\n...\n---^\nExpecting 'A', got 'B'", line: nil
		)
		#expect(fault.line == 12)
	}

	/// A short list is left as it is. Cutting three tokens down to two and "1
	/// other" would be longer than saying them.
	@Test func aShortListOfExpectationsIsNotShortened() {
		let fault = Mermaid.fault(message: "Expecting 'A', 'B', got 'C'", line: 1)
		#expect(fault.message == "Expecting 'A', 'B', got 'C'")
	}

	/// "No diagram type detected matching given configuration for text: …"
	/// carries the whole document after the colon, and a notice is not the place
	/// for somebody's own file read back at them.
	@Test func anUnknownDiagramTypeDoesNotQuoteTheWholeFile() {
		let fault = Mermaid.fault(
			message: "No diagram type detected matching given configuration for text: "
				+ "notadiagramtype\n  A --> B\n",
			line: nil
		)
		#expect(fault.line == nil)
		#expect(fault.message == "No diagram type detected matching given configuration "
			+ "for this text.")
		#expect(fault.sentence(for: "flow.mmd")
			== "flow.mmd could not be drawn: No diagram type detected matching given "
			+ "configuration for this text.")
	}

	// MARK: - The page

	/// The bundle has to be in the build, or every Mermaid file is a blank pane
	/// and nothing says why.
	@Test func theVendoredBundleIsInThisBuild() throws {
		let url = try #require(Mermaid.bundleURL)
		let bundle = try String(contentsOf: url, encoding: .utf8)
		#expect(bundle.utf8.count > 1_000_000)
		// The page finds Mermaid at `globalThis.mermaid`, which the UMD build
		// publishes on its very last line. A build that stopped doing that would
		// load without complaint and then draw nothing.
		#expect(bundle.hasSuffix("globalThis[\"mermaid\"] = globalThis.__esbuild_esm_mermaid_nm[\"mermaid\"].default;\n"))
		#expect(Mermaid.version != nil)
	}

	/// The three settings that are decisions rather than defaults, and the
	/// reason each is set is written where it is set.
	@Test func thePageTurnsOffTheThingsThatWouldSpoilAnExport() {
		let page = Mermaid.page(bundle: "/* bundle */")
		#expect(page.contains("/* bundle */"))
		// Labels in a `foreignObject` are HTML, which nothing outside a browser
		// draws — so an exported SVG would be empty boxes and a PNG impossible.
		#expect(page.contains("htmlLabels: false"))
		#expect(page.contains("securityLevel: 'strict'"))
		#expect(page.contains("suppressErrorRendering: true"))
		#expect(page.contains("async function abydosDraw"))
		#expect(page.contains("async function abydosRaster"))
		// And the drawing is flattened, or every edge in it is a black wedge
		// everywhere except a browser.
		#expect(page.contains("function abydosInline"))
		#expect(page.contains("abydosInline(drawn.svg)"))
	}
}

/// Signing a picture so it can be told from somebody's own file with an unlucky
/// name.
struct DiagramStampTests {
	@Test func aDrawingIsSignedOnceAndNoMoreThanOnce() {
		let signed = DiagramStamp.sign(svg: "<svg viewBox=\"0 0 1 1\"/>", tool: .mermaid)
		#expect(signed.hasPrefix("<?abydos-mermaid?>\n<svg"))
		#expect(DiagramStamp.sign(svg: signed, tool: .mermaid) == signed)
		#expect(DiagramExport.isDrawnHere(Data(signed.utf8)))
		#expect(DiagramExport.isOurs(Data(signed.utf8)))
	}

	/// The refusal has to let this app's own previous export through, or
	/// exporting the same diagram twice — which is the ordinary way of working —
	/// would fail the second time.
	@Test func aPreviousExportMayBeWrittenOverAndAStrangersFileMayNot() {
		let ours = Data(DiagramStamp.sign(svg: "<svg/>", tool: .mermaid).utf8)
		let theirs = Data("<svg>somebody's own drawing</svg>".utf8)
		let destination = URL(fileURLWithPath: "/p/flow.svg")
		#expect(DiagramExport.refusal(toWrite: [destination], reading: { _ in ours }) == nil)
		let refused = DiagramExport.refusal(toWrite: [destination], reading: { _ in theirs })
		#expect(refused?.contains("flow.svg") == true)
		#expect(refused?.contains("was not drawn from a diagram") == true)
	}

	/// PNG's own CRC-32, against the value the specification's own test vector
	/// gives for "IEND".
	@Test func theChunkChecksumIsPNGs() {
		#expect(DiagramStamp.crc32(Data("IEND".utf8)) == 0xAE42_6082)
	}

	/// A `tEXt` chunk, correctly framed, going in straight after `IHDR` — which
	/// is where the format says an ancillary chunk may go.
	@Test func aPictureIsSignedInsideItsOwnBytes() throws {
		let png = try #require(madeUpPNG())
		let signed = DiagramStamp.sign(png: png, tool: .mermaid)
		#expect(signed.count > png.count)
		#expect(DiagramExport.isDrawnHere(signed))

		let bytes = [UInt8](signed)
		#expect(Array(bytes.prefix(8)) == DiagramStamp.pngSignature)
		// IHDR is untouched, and what follows it is the new chunk.
		#expect(Array(bytes[12..<16]) == Array("IHDR".utf8))
		#expect(Array(bytes[37..<41]) == Array("tEXt".utf8))
		// Everything after the signature reads back as whole chunks that end at
		// exactly the end of the file — the check a decoder makes.
		var at = 8
		var types: [String] = []
		while at + 8 <= bytes.count {
			let length = (Int(bytes[at]) << 24) | (Int(bytes[at + 1]) << 16)
				| (Int(bytes[at + 2]) << 8) | Int(bytes[at + 3])
			let type = String(decoding: bytes[(at + 4)..<(at + 8)], as: UTF8.self)
			let body = Data(bytes[(at + 4)..<(at + 8 + length)])
			let stated = (UInt32(bytes[at + 8 + length]) << 24)
				| (UInt32(bytes[at + 9 + length]) << 16)
				| (UInt32(bytes[at + 10 + length]) << 8) | UInt32(bytes[at + 11 + length])
			#expect(DiagramStamp.crc32(body) == stated)
			types.append(type)
			at += 12 + length
		}
		#expect(at == bytes.count)
		#expect(types == ["IHDR", "tEXt", "IDAT", "IEND"])
	}

	/// Anything that is not a PNG comes back untouched rather than half-written.
	/// What happens next is that this is written to somebody's repository.
	@Test func somethingThatIsNotAPictureIsNotCutAbout() {
		let plain = Data("not a picture".utf8)
		#expect(DiagramStamp.sign(png: plain, tool: .mermaid) == plain)
		#expect(DiagramStamp.sign(png: Data(), tool: .mermaid) == Data())
	}

	/// The smallest PNG-shaped thing with the chunks a real one has.
	private func madeUpPNG() -> Data? {
		var data = Data(DiagramStamp.pngSignature)
		var header = Data()
		header.append(contentsOf: [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0])
		data.append(DiagramStamp.chunk(type: "IHDR", payload: header))
		data.append(DiagramStamp.chunk(type: "IDAT", payload: Data([0x78, 0x9C, 0x01])))
		data.append(DiagramStamp.chunk(type: "IEND", payload: Data()))
		return data
	}
}

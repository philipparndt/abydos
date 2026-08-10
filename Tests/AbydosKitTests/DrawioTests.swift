import Foundation
import Testing
@testable import AbydosKit

/// What a `.drawio` file is, read without a web view.
///
/// The format rules rather than the drawing: every one of these is something
/// that can be wrong in a way nothing complains about, which is why they are
/// written down as tests rather than as comments.
struct DrawioTests {
	static func fixture(_ name: String) throws -> Data {
		let url = try #require(
			Bundle.module.url(forResource: name, withExtension: "drawio", subdirectory: "Fixtures")
				?? Bundle.module.url(forResource: name, withExtension: "drawio")
		)
		return try Data(contentsOf: url)
	}

	// MARK: - draw.io's own compression

	/// The trap, and the reason this is the first test in the file: inflating
	/// and stopping there gives XML that parses perfectly and has `%20` wherever
	/// a label had a space.
	@Test func aPayloadIsUnescapedAsWellAsInflated() throws {
		let xml = "<mxGraphModel><root><mxCell value=\"Read the file\"/></root></mxGraphModel>"
		let packed = try #require(Drawio.compress(xml))
		#expect(!packed.contains("<"), "a compressed payload is base64")
		let back = try #require(Drawio.decompress(packed))
		#expect(back == xml)
		#expect(!back.contains("%20"))
	}

	/// Every character `encodeURIComponent` leaves alone, and no others. A
	/// wider set produces a payload draw.io reads back with the wrong
	/// characters in it.
	@Test func compressionRoundTripsEverythingAwkward() throws {
		let xml = "<a b=\"ä & 'quoted' ~!*()-_. 100% #tag\">line\nbreak</a>"
		let packed = try #require(Drawio.compress(xml))
		let back = try #require(Drawio.decompress(packed))
		#expect(back == xml)
	}

	/// Read out of a payload this app did not write. draw.io's own files are
	/// raw-deflate rather than zlib, and the two differ by six bytes that turn
	/// the whole thing into nothing if they are guessed wrong.
	@Test func aPayloadDrawioItselfWroteIsRead() throws {
		let document = try #require(Drawio.read(try Self.fixture("pages")))
		#expect(document.pages.count == 3)
		let everyPageCompressed = document.pages.allSatisfy(\.wasCompressed)
		#expect(everyPageCompressed)
		#expect(document.pages[0].model.contains("<mxGraphModel"))
		#expect(document.pages[0].model.contains("Overview box"))
		#expect(!document.pages[0].model.contains("%20"))
	}

	// MARK: - Pages

	@Test func aPlainFileIsOnePageAndSaysItWasNotCompressed() throws {
		let document = try #require(Drawio.read(try Self.fixture("plain")))
		#expect(document.pages.count == 1)
		#expect(document.pages[0].name == "One")
		#expect(document.pages[0].id == "page-one")
		#expect(document.pages[0].wasCompressed == false)
		#expect(document.isCompressed == false)
	}

	@Test func pagesKeepTheirNamesAndOrder() throws {
		let document = try #require(Drawio.read(try Self.fixture("pages")))
		#expect(document.pages.map(\.name) == ["Overview", "Detail", "Deployment"])
		#expect(document.isCompressed)
	}

	/// A page with no name is still a page, and the control has to call it
	/// something.
	@Test func anUnnamedPageIsNumbered() {
		let pages = Drawio.pages(in: "<mxfile><diagram id=\"a\"><x/></diagram></mxfile>")
		#expect(pages.count == 1)
		#expect(pages[0].title(number: 1) == "Page 1")
	}

	@Test func aPageWithNothingOnItDoesNotStopTheRest() {
		let pages = Drawio.pages(
			in: "<mxfile><diagram name=\"Empty\" id=\"a\"/><diagram name=\"Full\" id=\"b\">"
				+ "<mxGraphModel/></diagram></mxfile>"
		)
		#expect(pages.map(\.name) == ["Empty", "Full"])
	}

	// MARK: - The same drawing in another hand

	/// The one that keeps a `.drawio` from being edited by being opened.
	///
	/// draw.io re-serialises a document as it loads it: its own indentation, and
	/// `dx`/`dy` set to the size of the window it is being looked at in. Compared
	/// as text that is a change, and every file would grow the tab's dot, ask on
	/// close and be rewritten by auto-save without anybody touching it.
	@Test func theSameDrawingWrittenOutAgainIsNotAnEdit() {
		let one = """
			<mxfile><diagram name="One" id="a"><mxGraphModel dx="1102" dy="768" grid="1">
			  <root>
			    <mxCell id="0" />
			    <mxCell id="v1" value="a box" style="rounded=0;" vertex="1" parent="1">
			      <mxGeometry x="120" y="80" width="200" height="60" as="geometry" />
			    </mxCell>
			  </root>
			</mxGraphModel>
			</diagram></mxfile>
			"""
		// The same drawing, in draw.io's hand: a window of another size, and its
		// own indentation.
		let other = "<mxfile><diagram name=\"One\" id=\"a\"><mxGraphModel dx=\"2786\" dy=\"460\" "
			+ "grid=\"1\"><root><mxCell id=\"0\" /><mxCell id=\"v1\" value=\"a box\" "
			+ "style=\"rounded=0;\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"120\" y=\"80\" "
			+ "width=\"200\" height=\"60\" as=\"geometry\" /></mxCell></root></mxGraphModel>"
			+ "</diagram></mxfile>"
		#expect(one != other)
		#expect(Drawio.isSameDrawing(one, as: other))
	}

	/// And everything anybody actually does is still an edit.
	@Test func movingALabelOrABoxIsAnEdit() {
		func file(_ cell: String) -> String {
			"<mxfile><diagram name=\"One\" id=\"a\"><mxGraphModel dx=\"10\" dy=\"10\"><root>"
				+ cell + "</root></mxGraphModel></diagram></mxfile>"
		}
		let box = "<mxCell id=\"v1\" value=\"a box\"><mxGeometry x=\"120\" y=\"80\"/></mxCell>"
		let moved = "<mxCell id=\"v1\" value=\"a box\"><mxGeometry x=\"200\" y=\"80\"/></mxCell>"
		let renamed = "<mxCell id=\"v1\" value=\"a crate\"><mxGeometry x=\"120\" y=\"80\"/></mxCell>"
		#expect(!Drawio.isSameDrawing(file(box), as: file(moved)))
		#expect(!Drawio.isSameDrawing(file(box), as: file(renamed)))
		#expect(!Drawio.isSameDrawing(file(box), as: file(box + box)))
		// A page renamed, a page added, and a page whose id changed are all edits.
		#expect(!Drawio.isSameDrawing(
			file(box), as: file(box).replacingOccurrences(of: "name=\"One\"", with: "name=\"Two\"")
		))
	}

	// MARK: - The two picture forms

	/// A `.drawio.svg` is a real SVG with the document in a `content`
	/// attribute, and draw.io tries three encodings for it in order.
	@Test func aDrawingCarryingItsOwnDocumentIsRead() throws {
		let mxfile = "<mxfile><diagram name=\"In a picture\" id=\"p\"><mxGraphModel/></diagram></mxfile>"
		let svg = DiagramStamp.embed(mxfile: mxfile, in: "<svg width=\"10\" height=\"10\"></svg>")
		#expect(svg.contains("content=\""))
		let read = try #require(Drawio.read(Data(svg.utf8)))
		#expect(read.pages.map(\.name) == ["In a picture"])
	}

	@Test func aBase64ContentAttributeIsReadToo() throws {
		let mxfile = "<mxfile><diagram name=\"Packed\" id=\"p\"><mxGraphModel/></diagram></mxfile>"
		let svg = "<svg content=\"\(Data(mxfile.utf8).base64EncodedString())\"></svg>"
		#expect(Drawio.read(Data(svg.utf8))?.pages.first?.name == "Packed")
	}

	/// And a PNG with an `mxfile` chunk, which is what makes
	/// `architecture.drawio.png` a picture GitHub renders and draw.io reopens.
	@Test func aPictureCarryingItsOwnDocumentIsRead() throws {
		let mxfile = "<mxfile><diagram name=\"In a PNG\" id=\"p\"><mxGraphModel/></diagram></mxfile>"
		let png = DiagramStamp.embed(mxfile: mxfile, in: Self.smallestPNG)
		let read = try #require(Drawio.read(png))
		#expect(read.pages.map(\.name) == ["In a PNG"])
		// And it is still a PNG afterwards, which is the whole point of putting
		// the chunk after IHDR rather than anywhere convenient.
		#expect(Array(png.prefix(8)) == DiagramStamp.pngSignature)
	}

	@Test func aPictureNobodyDrewFromADiagramIsNotOne() {
		#expect(Drawio.read(Self.smallestPNG) == nil)
		#expect(Drawio.read(Data("<svg><rect/></svg>".utf8)) == nil)
		#expect(DiagramExport.isDrawnFromADiagram(Self.smallestPNG) == false)
	}

	// MARK: - What this build does not carry

	@Test func aDiagramUsingClipartSaysSoRatherThanDrawingAGap() throws {
		let model = "<mxGraphModel><root><mxCell style=\"shape=image;"
			+ "image=img/lib/clip_art/computers/Laptop_128x128.png;\"/>"
			+ "<mxCell style=\"shape=image;image=img/lib/azure2/ai/Bot_Services.svg;\"/>"
			+ "</root></mxGraphModel>"
		let document = try #require(Drawio.read(Data(
			"<mxfile><diagram id=\"a\">\(model)</diagram></mxfile>".utf8
		)))
		#expect(Drawio.missingClipart(in: document) == 2)
		let said = try #require(Drawio.clipartNotice(for: document))
		#expect(said.contains("2 shapes"))
	}

	@Test func anOrdinaryDiagramSaysNothingAboutClipart() throws {
		let document = try #require(Drawio.read(try Self.fixture("stencils")))
		#expect(Drawio.clipartNotice(for: document) == nil)
	}

	// MARK: - Which files these are

	@Test func onlyThePlainDocumentIsOpenedInTheEditor() {
		#expect(Drawio.isDiagram(URL(fileURLWithPath: "/a/architecture.drawio")))
		#expect(Drawio.isDiagram(URL(fileURLWithPath: "/a/architecture.dio")))
		// The two picture forms stay pictures, deliberately: `pathExtension`
		// says `svg`, they render on GitHub, and the editor is a `.drawio` away.
		#expect(!Drawio.isDiagram(URL(fileURLWithPath: "/a/architecture.drawio.svg")))
		#expect(!Drawio.isDiagram(URL(fileURLWithPath: "/a/architecture.drawio.png")))
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/a/architecture.drawio.svg")) == .image)
	}

	/// A `.drawio` opens in the editor and offers no source half at all — which
	/// is not a nicety. A text editor and draw.io over the same file, neither
	/// aware of the other's edits, is the one way this could lose work.
	@Test func aDrawioOpensRenderedAndHasNoSourceHalf() {
		let url = URL(fileURLWithPath: "/a/architecture.drawio")
		#expect(FilePreview.kind(for: url) == .drawio)
		#expect(FilePreview.defaultMode(for: url) == .preview)
		#expect(FilePreview.hasReadableSource(url) == false)
		#expect(FilePreview.availableModes(for: url) == [.preview])
		#expect(FilePreview.kind(for: url)?.isDiagram == true)
		#expect(DiagramExport.isDiagram(url))
	}

	// MARK: - The stamp, now that there are three drawers

	@Test func eachDrawerSignsWithItsOwnName() {
		#expect(DiagramStamp.marker(.mermaid) == "abydos-mermaid")
		#expect(DiagramStamp.marker(.drawio) == "abydos-drawio")
		for tool in DiagramStamp.Tool.allCases {
			let svg = DiagramStamp.sign(svg: "<svg></svg>", tool: tool)
			#expect(DiagramExport.isDrawnHere(Data(svg.utf8)))
			#expect(DiagramExport.isDrawnHere(DiagramStamp.sign(png: Self.smallestPNG, tool: tool)))
		}
		// And nothing that merely mentions the prefix is mistaken for one.
		#expect(!DiagramExport.isDrawnHere(Data("<svg>abydos-something-else</svg>".utf8)))
	}

	@Test func signingTwiceDoesNotSignTwice() {
		let once = DiagramStamp.sign(svg: "<svg></svg>", tool: .drawio)
		#expect(DiagramStamp.sign(svg: once, tool: .drawio) == once)
	}

	/// The smallest legal PNG: signature, IHDR, IEND. Enough for every reader
	/// here, and nothing is drawn from it.
	static let smallestPNG: Data = {
		var data = Data(DiagramStamp.pngSignature)
		var header = Data()
		header.append(contentsOf: [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0])
		data.append(DiagramStamp.chunk(type: "IHDR", payload: header))
		data.append(DiagramStamp.chunk(type: "IEND", payload: Data()))
		return data
	}()
}

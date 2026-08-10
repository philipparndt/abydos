import AppKit
import Foundation
import Testing
@testable import AbydosKit

/// Diagrams drawn by the real draw.io, written to a real folder, and read back.
///
/// The one thing no rule test can say: that what lands on disk is a picture of
/// the diagram. A PNG of nought bytes and an SVG whose labels are all in
/// `foreignObject` both look like success from everywhere except here.
///
/// Nothing is skipped and nothing has to be installed. What can still be
/// missing is a `WKWebView` that will load at all, which under some test
/// runners it will not; that case reports itself rather than failing, because
/// it is a fact about the runner rather than about the code.
@MainActor
struct DrawioLiveTests {
	private func canDraw() async -> Bool {
		let file = try? DrawioTests.fixture("plain")
		guard let file, let document = Drawio.read(file) else { return false }
		let drawn = await DrawioRenderer.shared.draw(document.mxfile, format: .svg)
		if case .failure(.trouble(let said)) = drawn, said == Drawio.missingBundleHint {
			print("DRAWIO: no web view here — \(said)")
			return false
		}
		return true
	}

	private func madeFolder() throws -> URL {
		let folder = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-drawio-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}

	// MARK: - Drawing

	/// A plain one-page file, drawn, and every property of the drawing that
	/// makes it a picture outside a browser as well as in one.
	@Test func aPlainFileIsARealDrawing() async throws {
		guard await canDraw() else { return }
		let document = try #require(Drawio.read(try DrawioTests.fixture("plain")))
		let drawn = await DrawioRenderer.shared.draw(document.mxfile, format: .svg)
		guard case let .success(data) = drawn else {
			Issue.record("nothing drawn: \(drawn)")
			return
		}
		let svg = String(decoding: data, as: UTF8.self)
		#expect(svg.contains("<svg"))
		#expect(svg.contains("</svg>"))
		#expect(DiagramExport.isDrawnHere(data))
		// The labels are text, not HTML in a `foreignObject`. With
		// `foEnabled` left on, this file is a picture of two empty boxes
		// everywhere that is not a browser — the same fault Mermaid's
		// `htmlLabels` had, in a different tool.
		#expect(!svg.contains("foreignObject"))
		#expect(svg.contains("Read the file"))
		#expect(svg.contains("Draw the picture"))
		// A size of its own, so no viewer has to guess one.
		#expect(svg.contains("width=") && svg.contains("height="))
		#expect(svg.contains("viewBox="))
	}

	/// The one that proves the offline asset set is complete.
	///
	/// draw.io loads shape libraries lazily, by style prefix, at draw time, from
	/// `https://viewer.diagrams.net/stencils/…`. Under `WebRenderer` those
	/// fetches are cancelled and **they fail silently** — the diagram draws
	/// short of its icons and looks like a diagram. So this draws a file of AWS
	/// shapes and then asks draw.io's own registry whether every one of them
	/// resolved, which is the only place that answer exists.
	@Test func aStencilFileDrawsItsIconsWithNothingFetched() async throws {
		guard await canDraw() else { return }
		let document = try #require(Drawio.read(try DrawioTests.fixture("stencils")))
		let drawn = await DrawioRenderer.shared.draw(document.mxfile, format: .svg)
		guard case let .success(data) = drawn else {
			Issue.record("nothing drawn: \(drawn)")
			return
		}
		let svg = String(decoding: data, as: UTF8.self)
		#expect(svg.contains("EC2"))
		#expect(svg.contains("S3 Bucket"))

		// Asked of draw.io's own registry rather than counted off the picture:
		// an unresolved shape is drawn as a plain rectangle, and a diagram
		// missing every icon still looks like a diagram. This is the one
		// question the picture cannot answer.
		let missing = await DrawioRenderer.shared.missingShapes(in: document)
		#expect(missing == [], "these shapes did not resolve: \(missing ?? [])")

		// One of the icons is a stencil out of `stencils.min.js`
		// (`mxgraph.aws.compute.ec2_instance`) and two are drawn by a
		// JavaScript shape out of `shapes-14-6-5.min.js`
		// (`mxgraph.aws4.resourceIcon`). Both bundles are needed and this file
		// is here because it uses both.
		let names = Drawio.shapeNames(in: document.pages[0].model)
		#expect(names.contains("mxgraph.aws4.resourceIcon"))
		#expect(names.contains("mxgraph.aws.compute.ec2_instance"))
	}

	/// The picture must be the same picture outside a browser.
	///
	/// draw.io writes every colour twice: the plain value as an attribute and
	/// `light-dark(…)` in a `style` beside it, so one file follows the reader's
	/// theme. WebKit understands it; CoreSVG — which is what NSImage,
	/// Preview.app and this app's own preview all draw an SVG with — does not,
	/// and paints the element **black** rather than falling back. The exported
	/// AWS diagram opened in Preview.app as five solid black boxes with its
	/// labels gone, while the pane and the PNG were both correct.
	@Test func nothingInADrawingNeedsABrowserToBeRead() async throws {
		guard await canDraw() else { return }
		for name in ["plain", "pages", "stencils"] {
			let document = try #require(Drawio.read(try DrawioTests.fixture(name)))
			let drawn = await DrawioRenderer.shared.draw(document.mxfile, format: .svg)
			guard case let .success(data) = drawn else {
				Issue.record("\(name) did not draw: \(drawn)")
				continue
			}
			let svg = String(decoding: data, as: UTF8.self)
			#expect(!svg.contains("light-dark("), "\(name) is drawn in colours only a browser reads")
			#expect(!svg.contains("foreignObject"), "\(name) has labels only a browser draws")
			// And it is a real picture to AppKit, which is the renderer behind
			// the preview pane and behind Preview.app.
			#expect(NSImage(data: data)?.size.width ?? 0 > 0)
		}
	}

	/// A file draw.io itself wrote: three pages, every one compressed.
	@Test func everyPageOfACompressedFileDrawsSomethingDifferent() async throws {
		guard await canDraw() else { return }
		let document = try #require(Drawio.read(try DrawioTests.fixture("pages")))
		#expect(await DrawioRenderer.shared.pageCount(document.mxfile) == 3)

		var drawings: [String] = []
		for page in 0..<document.pages.count {
			let drawn = await DrawioRenderer.shared.draw(document.mxfile, page: page, format: .svg)
			guard case let .success(data) = drawn else {
				Issue.record("page \(page) did not draw: \(drawn)")
				continue
			}
			drawings.append(String(decoding: data, as: UTF8.self))
		}
		#expect(drawings.count == 3)
		// Each page is its own picture, which is the whole reason the export
		// writes three files rather than one.
		#expect(drawings[0].contains("Overview box"))
		#expect(drawings[1].contains("Detail box"))
		#expect(drawings[2].contains("Deployment box"))
	}

	/// The pane draws SVG for sharpness, and asking for a PNG has to give a PNG.
	@Test func aPNGIsAPNGAndIsNotBlank() async throws {
		guard await canDraw() else { return }
		let document = try #require(Drawio.read(try DrawioTests.fixture("plain")))
		let drawn = await DrawioRenderer.shared.draw(document.mxfile, format: .png)
		guard case let .success(data) = drawn else {
			Issue.record("no picture: \(drawn)")
			return
		}
		#expect(Array(data.prefix(8)) == DiagramStamp.pngSignature)
		let bytes = [UInt8](data)
		let width = (Int(bytes[16]) << 24) | (Int(bytes[17]) << 16)
			| (Int(bytes[18]) << 8) | Int(bytes[19])
		let height = (Int(bytes[20]) << 24) | (Int(bytes[21]) << 16)
			| (Int(bytes[22]) << 8) | Int(bytes[23])
		// Rasterised at 2×, and the fixture's own bounds are about 210×220.
		#expect(width > 300, "a 2× drawing should be wider than 300px, was \(width)")
		#expect(height > 300, "a 2× drawing should be taller than 300px, was \(height)")
		// A PNG of a blank canvas compresses to almost nothing. This one has a
		// diagram on it.
		#expect(data.count > 3000, "the picture is \(data.count) bytes, which is a blank page")
	}

	// MARK: - Exporting

	/// Every page, named the way PlantUML's own file output names them — which
	/// is the decision 0426 left open and the reason the notice says how many.
	@Test func everyPageIsWrittenBesideTheFile() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("architecture.drawio")
		let bytes = try DrawioTests.fixture("pages")
		try bytes.write(to: source)

		let written = await DiagramExport.export(drawio: bytes, of: source, format: .png)
		guard case let .success(files) = written else {
			Issue.record("nothing exported: \(written)")
			return
		}
		#expect(files.map(\.lastPathComponent)
			== ["architecture.png", "architecture_001.png", "architecture_002.png"])
		for file in files {
			let onDisk = try Data(contentsOf: file)
			#expect(Array(onDisk.prefix(8)) == DiagramStamp.pngSignature)
			#expect(DiagramExport.isDrawnHere(onDisk))
			// And every picture is also the document: `architecture.png` opens
			// again in draw.io with all three of its pages.
			let inside = try #require(Drawio.read(onDisk))
			#expect(inside.pages.map(\.name) == ["Overview", "Detail", "Deployment"])
		}

		// Again, over what was written: exporting twice is the ordinary way of
		// working rather than a mistake to catch.
		let again = await DiagramExport.export(drawio: bytes, of: source, format: .png)
		guard case .success = again else {
			Issue.record("a second export refused its own pictures: \(again)")
			return
		}
	}

	@Test func anSVGExportIsADrawingAndCarriesTheDocument() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("one.drawio")
		let bytes = try DrawioTests.fixture("plain")
		try bytes.write(to: source)

		let written = await DiagramExport.export(drawio: bytes, of: source, format: .svg)
		guard case let .success(files) = written, let file = files.first else {
			Issue.record("nothing exported: \(written)")
			return
		}
		#expect(file.lastPathComponent == "one.svg")
		let onDisk = try Data(contentsOf: file)
		let svg = String(decoding: onDisk, as: UTF8.self)
		#expect(svg.contains("<svg"))
		#expect(!svg.contains("foreignObject"))
		#expect(Drawio.read(onDisk)?.pages.first?.name == "One")
	}

	/// Somebody's own picture with an unlucky name stops the export rather than
	/// being destroyed.
	@Test func somebodyElsesPictureIsNotOverwritten() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("one.drawio")
		let bytes = try DrawioTests.fixture("plain")
		try bytes.write(to: source)
		let theirs = folder.appendingPathComponent("one.svg")
		try "<svg>a drawing somebody made by hand</svg>".write(
			to: theirs, atomically: true, encoding: .utf8
		)

		let written = await DiagramExport.export(drawio: bytes, of: source, format: .svg)
		guard case let .failure(failure) = written else {
			Issue.record("somebody's own drawing was overwritten")
			return
		}
		#expect(failure.message.contains("one.svg"))
		#expect(try String(contentsOf: theirs, encoding: .utf8).contains("by hand"))
	}

	// MARK: - The picture that is also the document

	/// The round trip that is the whole claim: a `.drawio.png` this app writes
	/// opens again *as the document*, with every page and every label.
	///
	/// Not "a file appeared". The picture is read back the way draw.io's own
	/// reader would — the `mxfile` chunk, `+` for space, un-escaped — the model is
	/// parsed, and every page is compared to the page it came from. A picture
	/// under a name promising a document, that is only a picture, is worse than
	/// no gesture at all.
	@Test func anEditablePNGReopensAsTheWholeDocument() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("architecture.drawio")
		let bytes = try DrawioTests.fixture("pages")
		try bytes.write(to: source)
		let before = try #require(Drawio.read(bytes))

		let written = await DiagramExport.export(editable: bytes, of: source, format: .png)
		guard case let .success(file) = written else {
			Issue.record("nothing saved: \(written)")
			return
		}
		// One file for a three-page document, which is the difference from the
		// export: the whole `<mxfile>` is inside it.
		#expect(file.lastPathComponent == "architecture.drawio.png")

		let onDisk = try Data(contentsOf: file)
		#expect(Array(onDisk.prefix(8)) == DiagramStamp.pngSignature)
		// A real picture as well as a real document: this is the half GitHub
		// renders, and CoreSVG is what draws it here and in Preview.app.
		#expect(NSImage(data: onDisk)?.size.width ?? 0 > 0)
		#expect(onDisk.count > 3000, "\(onDisk.count) bytes is a blank page")

		// And the half draw.io reopens.
		let after = try #require(Drawio.read(onDisk))
		#expect(after.pages.count == before.pages.count)
		#expect(after.pages.map(\.name) == ["Overview", "Detail", "Deployment"])
		#expect(after.pages.map(\.id) == before.pages.map(\.id))
		// The models themselves, not merely the page names — a chunk that lost a
		// `%20` or a `+` would still count three pages and be wrong everywhere a
		// label had a space in it.
		#expect(after.pages.map(\.model) == before.pages.map(\.model))
		#expect(after.mxfile == before.mxfile)
		#expect(!after.pages[0].model.contains("%20"))
		#expect(after.pages[0].model.contains("Overview box"))

		// Saving it again replaces its own file rather than refusing it: the
		// `mxfile` chunk is what proves the picture came from a diagram.
		let again = await DiagramExport.export(editable: bytes, of: source, format: .png)
		guard case .success = again else {
			Issue.record("a second save refused its own picture: \(again)")
			return
		}
	}

	/// The same for the SVG, where the document rides in a `content` attribute
	/// rather than a chunk — and where the picture has to stay a picture
	/// anything, not only a browser, can draw.
	@Test func anEditableSVGReopensAsTheWholeDocument() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("architecture.drawio")
		let bytes = try DrawioTests.fixture("pages")
		try bytes.write(to: source)
		let before = try #require(Drawio.read(bytes))

		let written = await DiagramExport.export(editable: bytes, of: source, format: .svg)
		guard case let .success(file) = written else {
			Issue.record("nothing saved: \(written)")
			return
		}
		#expect(file.lastPathComponent == "architecture.drawio.svg")

		let onDisk = try Data(contentsOf: file)
		let svg = String(decoding: onDisk, as: UTF8.self)
		#expect(svg.contains("content=\""))
		#expect(!svg.contains("foreignObject"))
		#expect(!svg.contains("light-dark("))
		#expect(NSImage(data: onDisk)?.size.width ?? 0 > 0)

		let after = try #require(Drawio.read(onDisk))
		#expect(after.pages.map(\.name) == before.pages.map(\.name))
		#expect(after.pages.map(\.model) == before.pages.map(\.model))
	}

	/// A one-page file gets one picture under the same rule, and the plain
	/// export's name is left alone — the two gestures write two different files
	/// and neither stands on the other.
	@Test func theEditablePictureDoesNotTakeThePlainExportsName() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("one.drawio")
		let bytes = try DrawioTests.fixture("plain")
		try bytes.write(to: source)

		_ = await DiagramExport.export(drawio: bytes, of: source, format: .png)
		let saved = await DiagramExport.export(editable: bytes, of: source, format: .png)
		guard case let .success(file) = saved else {
			Issue.record("nothing saved: \(saved)")
			return
		}
		#expect(file.lastPathComponent == "one.drawio.png")
		#expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("one.png").path))
		#expect(Drawio.read(try Data(contentsOf: file))?.pages.first?.name == "One")
	}

	/// Somebody's own picture called `architecture.drawio.png` is not destroyed
	/// by this gesture any more than by the other one.
	@Test func anEditableSaveWillNotOverwriteSomebodyElsesPicture() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("one.drawio")
		try (try DrawioTests.fixture("plain")).write(to: source)
		let theirs = folder.appendingPathComponent("one.drawio.svg")
		try "<svg>a drawing somebody made by hand</svg>".write(
			to: theirs, atomically: true, encoding: .utf8
		)

		let saved = await DiagramExport.export(
			editable: try DrawioTests.fixture("plain"), of: source, format: .svg
		)
		guard case let .failure(failure) = saved else {
			Issue.record("somebody's own drawing was overwritten")
			return
		}
		#expect(failure.message.contains("one.drawio.svg"))
		#expect(try String(contentsOf: theirs, encoding: .utf8).contains("by hand"))
	}

	/// The measurement the pane rests on: the first draw pays for an 11.7 MB
	/// page load and every one after it is cheap.
	@Test func drawingIsFastOnceThePageIsLoaded() async throws {
		guard await canDraw() else { return }
		let document = try #require(Drawio.read(try DrawioTests.fixture("stencils")))
		_ = await DrawioRenderer.shared.draw(document.mxfile, format: .svg)
		let began = Date()
		for _ in 0..<5 {
			_ = await DrawioRenderer.shared.draw(document.mxfile, format: .svg)
		}
		let each = Date().timeIntervalSince(began) / 5
		print("DRAWIO: \(String(format: "%.4f", each))s a warm render, \(MachineLoad.said)")
		// Only where a stopwatch means anything — the same reasoning as Mermaid's
		// twin of this test, written out under `MachineLoad.canBeTimed`.
		guard MachineLoad.canBeTimed else {
			print("DRAWIO: not timing the warm render — \(MachineLoad.said)")
			return
		}
		#expect(each < 1.0, "a warm render took \(each)s")
	}
}

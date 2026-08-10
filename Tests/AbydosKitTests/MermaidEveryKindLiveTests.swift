import AppKit
import Foundation
import Testing
@testable import AbydosKit

/// One of every kind of diagram Mermaid draws, drawn twice: once by CoreSVG,
/// which is `NSImage` and therefore the preview pane and Preview.app, and once
/// by WebKit, which is the exported PNG. The two have to be the same picture.
///
/// That agreement is the property the whole flattening in `Mermaid.page` exists
/// for, and it was being claimed rather than checked: the six examples in
/// `ExampleMermaidTests` are a flowchart, a sequence, a state, a class, an
/// entity-relationship and a git graph, and every other kind of diagram is laid
/// out by different code inside Mermaid. Asking the rest of them the same
/// question found three faults in one afternoon, every one of them this app's
/// own doing rather than a limit of CoreSVG:
///
///  * A **Sankey**'s flows are gradient strokes, and the reference to a gradient
///    was written back as `url("#linearGradient-5")` with the quotes the browser
///    puts in a computed value. CoreSVG finds no such gradient and paints
///    nothing: **77% of the page** differed, and the pane showed four bars on
///    blank paper.
///  * A **journey**'s labels are drawn twice by Mermaid, as HTML in a
///    `foreignObject` and as a `<text>` beside it in a `<switch>`, for the
///    renderer to choose. The browser takes the first and never lays the second
///    out, so the empty-label sweep removed it and the file went out with only
///    the branch CoreSVG cannot draw. Every label was missing from the pane and
///    from the exported SVG while the PNG was perfect.
///  * A **treemap**'s labels carry `dominant-baseline: middle` in a `style` of
///    Mermaid's own, which beat the attributes the bake writes to neutralise
///    it — so the browser centred a label that was already centred and drew it
///    half a line low. That one had the *export* wrong and the pane right.
///
/// The claims below are in two kinds on purpose. The pixel comparison is a net
/// for a catastrophe: it caught the Sankey at 77% and would catch anything that
/// large again, but the journey's missing labels were only 0.8% of a mostly
/// empty page and it would have let those through. So what each of those three
/// faults *was* is also asserted directly, as a property of the file.
///
/// Skipped when the runner will not host a `WKWebView`, which is a fact about
/// where this is running rather than about the code.
@MainActor
struct MermaidEveryKindLiveTests {
	/// One diagram of every kind this Mermaid knows, kept as small as each kind
	/// can be while still drawing the parts that go wrong — a label, an edge, a
	/// fill. The names are the `PROBE` lines the faults above were found in.
	static let kinds: [(name: String, source: String)] = [
		("flowchart", """
		flowchart TD
		    A[Start] --> B{Is it a diagram?}
		    B -- yes --> C[Draw it]
		    B -- no --> D[Say so]
		"""),
		("sequence", """
		sequenceDiagram
		    autonumber
		    participant Editor
		    participant Preview
		    Editor->>Preview: text changed
		    Preview-->>Editor: the picture
		    Note over Editor,Preview: a note across both
		"""),
		("state", """
		stateDiagram-v2
		    [*] --> Clean
		    Clean --> Edited: typing
		    Edited --> Clean: saved
		"""),
		("class", """
		classDiagram
		    class WebRenderer {
		        +call(script) Any
		        -stop()
		    }
		    class MermaidRenderer
		    WebRenderer <|-- MermaidRenderer : draws with
		"""),
		("er", """
		erDiagram
		    PROJECT ||--o{ RUN_CONFIGURATION : keeps
		    RUN_CONFIGURATION {
		        string name
		    }
		"""),
		("git", """
		gitGraph
		    commit
		    branch feature
		    commit
		    checkout main
		    merge feature
		"""),
		("pie", """
		pie title What the bundle is
		    "mermaid" : 3.57
		    "everything else" : 1.2
		"""),
		("gantt", """
		gantt
		    title A schedule
		    dateFormat YYYY-MM-DD
		    section Drawing
		    the pane      :a1, 2026-01-01, 30d
		    the export    :after a1, 20d
		"""),
		("journey", """
		journey
		    title A day of drawing
		    section Morning
		      Open a file: 5: Me
		      Draw it: 3: Me, App
		"""),
		("mindmap", """
		mindmap
		  root((preview))
		    Mermaid
		      web view
		    PlantUML
		      container
		"""),
		("timeline", """
		timeline
		    title The queue
		    2025 : PlantUML
		    2026 : Mermaid : draw.io
		"""),
		("quadrant", """
		quadrantChart
		    title Cost against value
		    x-axis Low --> High
		    y-axis Cheap --> Dear
		    Mermaid: [0.3, 0.8]
		    Container: [0.8, 0.2]
		"""),
		("xychart", """
		xychart-beta
		    title "Renders"
		    x-axis [one, two, three]
		    y-axis "Seconds" 0 --> 1
		    bar [0.9, 0.02, 0.01]
		"""),
		("sankey", """
		sankey-beta

		Editor,Preview,10
		Preview,Mermaid,10
		Mermaid,Picture,10
		"""),
		("block", """
		block-beta
		    columns 3
		    a["Editor"] b["Renderer"] c["Picture"]
		    a --> b
		    b --> c
		"""),
		("c4", """
		C4Context
		    title A context
		    Person(user, "Somebody", "types")
		    System(app, "Abydos", "draws")
		    Rel(user, app, "uses")
		"""),
		("requirement", """
		requirementDiagram
		    requirement draws {
		        id: 1
		        text: a diagram is drawn
		        risk: low
		        verifymethod: test
		    }
		    element pane {
		        type: view
		    }
		    pane - satisfies -> draws
		"""),
		("packet", """
		packet-beta
		    0-15: "Source"
		    16-31: "Destination"
		"""),
		("architecture", """
		architecture-beta
		    group app(cloud)[App]
		    service web(server)[Web view] in app
		    service disk(disk)[Picture] in app
		    web:R --> L:disk
		"""),
		("kanban", """
		kanban
		    Todo
		        [ELK layout]
		    Doing
		        [A screenshot]
		"""),
		("radar", """
		radar-beta
		    title Coverage
		    axis a["Speed"], b["Size"], c["Fidelity"]
		    curve mermaid{80, 95, 90}
		"""),
		("treemap", """
		treemap-beta
		"Preview"
		    "Mermaid": 40
		    "PlantUML": 30
		"""),
	]

	/// The kinds the pixel comparison is run over: the three that were wrong,
	/// and three ordinary ones to say what "the same picture" costs when nothing
	/// is wrong. Not all twenty-two, because comparing two two-megapixel
	/// rasterisations is the expensive part and the properties below are what
	/// actually name a fault.
	static let compared = ["sankey", "journey", "treemap", "flowchart", "sequence", "pie"]

	private func canDraw() async -> Bool {
		let drawn = await MermaidRenderer.shared.draw("flowchart TD\n A --> B", format: .svg)
		if case .failure(.trouble(let said)) = drawn, said == Mermaid.missingBundleHint {
			print("MERMAID: no web view here — \(said)")
			return false
		}
		return true
	}

	// MARK: - What the file may not contain

	/// Every kind of diagram, and the three things that made one of them draw
	/// differently outside a browser.
	@Test(arguments: kinds)
	func everyKindOfDiagramIsAPictureAndNotAProgram(name: String, source: String) async throws {
		guard await canDraw() else { return }
		let drawn = await MermaidRenderer.shared.draw(source, format: .svg, theme: .light)
		guard case let .success(data) = drawn else {
			Issue.record("\(name) did not draw: \(drawn)")
			return
		}
		let svg = String(decoding: data, as: UTF8.self)

		// A reference nothing outside a browser can follow. `url("#id")` is what
		// `getComputedStyle` hands back and what the serialiser writes out as
		// `url(&quot;#id&quot;)`; CoreSVG looks for a gradient of that name,
		// finds none, and paints nothing at all.
		#expect(!svg.contains("&quot;"), "\(name) points at something with quotes in the name")
		// A `<switch>` is Mermaid asking the renderer to choose between HTML and
		// text. The choice is made here now, so there is nothing left to choose.
		#expect(!svg.contains("<switch"), "\(name) leaves the renderer to choose")
		#expect(!svg.contains("foreignObject"), "\(name) draws labels only a browser draws")
		// Nothing inherited written onto something that draws nothing itself:
		// every shape carries its own resolved copy, and CoreSVG applies a
		// `stroke-opacity` on a `<g>` a second time as if it were a group opacity.
		for piece in svg.components(separatedBy: "<g").dropFirst() {
			let tag = piece.prefix(while: { $0 != ">" })
			#expect(!tag.contains("stroke-opacity"), "\(name) paints a group")
			#expect(!tag.contains("font-size"), "\(name) paints a group")
		}
		// And no run of text left saying where it goes or how it is anchored —
		// in an attribute *or* in a style, since a style beats the attribute and
		// that is how a treemap's labels came out half a line low.
		for piece in svg.components(separatedBy: "<text").dropFirst() {
			let tag = piece.prefix(while: { $0 != ">" })
			#expect(!tag.contains("dominant-baseline: middle"), "\(name) centres a label twice")
			#expect(!tag.contains("text-anchor: middle"), "\(name) anchors a label twice")
		}
		#expect(DiagramExport.isDrawnHere(data), "\(name) is not stamped")
	}

	// MARK: - And the two renderers agree about it

	/// The same diagram rasterised by CoreSVG and by WebKit, compared pixel for
	/// pixel.
	///
	/// A pixel or two of slack in each direction, because the two round a
	/// drawing's size differently — 564 against 562 for the same flowchart — so
	/// the same picture is still shifted under itself. What is left after that is
	/// the edges of glyphs: measured at **0.01% to 0.76% of the page** over the
	/// six below. A tenth of the page is what a missing gradient, a missing
	/// label or a missing arrowhead costs — the Sankey was at 77% — so that is
	/// where the line is, far above the noise and far below a fault.
	@Test(arguments: compared)
	func thePaneAndTheExportedPictureAreTheSamePicture(name: String) async throws {
		guard await canDraw() else { return }
		let source = try #require(Self.kinds.first(where: { $0.name == name })?.source)
		let drawnSVG = await MermaidRenderer.shared.draw(source, format: .svg, theme: .light)
		let drawnPNG = await MermaidRenderer.shared.draw(source, format: .png, theme: .light)
		guard case let .success(svg) = drawnSVG, case let .success(png) = drawnPNG else {
			Issue.record("\(name) did not draw both ways: \(drawnSVG) \(drawnPNG)")
			return
		}
		let web = try #require(NSBitmapImageRep(data: png), "\(name)'s PNG is not a picture")
		let core = try #require(
			rasterised(svg, into: CGSize(width: web.pixelsWide, height: web.pixelsHigh)),
			"CoreSVG would not read \(name) at all"
		)
		let apart = Self.howFarApart(core, web)
		print(String(format: "MERMAID %@: the two renderers differ over %.2f%% of the page",
		             name, apart * 100))
		#expect(apart < 0.10, "\(name) draws differently in the two: \(apart * 100)% of the page")
	}

	/// The drawing through CoreSVG, which is what `NSImage` is, at exactly the
	/// size WebKit rasterised it to.
	private func rasterised(_ svg: Data, into size: CGSize) -> NSBitmapImageRep? {
		guard let image = NSImage(data: svg), image.size.width > 0 else { return nil }
		let box = NSRect(x: 0, y: 0, width: size.width, height: size.height)
		guard let rep = NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		) else { return nil }
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
		// The same paper the PNG is rasterised onto, since a drawing has no
		// background of its own and a comparison against transparency compares
		// whatever was behind it.
		NSColor.white.setFill()
		box.fill()
		image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
		NSGraphicsContext.restoreGraphicsState()
		return rep
	}

	/// What fraction of the page the two disagree about, allowing each pixel to
	/// have moved by two.
	private static func howFarApart(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
		guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
		      let left = a.bitmapData, let right = b.bitmapData
		else { return 1 }
		let width = a.pixelsWide, height = a.pixelsHigh
		let strideL = a.bytesPerRow, strideR = b.bytesPerRow
		let sampleL = a.samplesPerPixel, sampleR = b.samplesPerPixel
		func same(_ i: Int, _ j: Int) -> Bool {
			max(
				abs(Int(left[i]) - Int(right[j])),
				max(
					abs(Int(left[i + 1]) - Int(right[j + 1])),
					abs(Int(left[i + 2]) - Int(right[j + 2]))
				)
			) <= 24
		}
		var differing = 0
		for y in 0..<height {
			for x in 0..<width {
				let here = y * strideL + x * sampleL
				let there = y * strideR + x * sampleR
				if same(here, there) { continue }
				// Both ways round: something drawn a pixel to the left is the same
				// picture, and something drawn *nowhere* is not.
				var near = false
				for dy in -2...2 where !near {
					for dx in -2...2 where !near {
						let ny = y + dy, nx = x + dx
						guard ny >= 0, ny < height, nx >= 0, nx < width else { continue }
						near = same(here, ny * strideR + nx * sampleR)
							&& same(ny * strideL + nx * sampleL, there)
					}
				}
				if !near { differing += 1 }
			}
		}
		return Double(differing) / Double(width * height)
	}
}

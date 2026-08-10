import Foundation
import Testing
@testable import AbydosKit

/// Diagrams drawn by the real Mermaid, written to a real folder, and read back.
///
/// This is the one thing no rule test can say: that what lands on disk is a
/// picture of the diagram. A PNG of nought bytes and an SVG holding an error
/// message both look like success from everywhere except here.
///
/// Nothing is skipped and nothing has to be installed — which is the whole
/// point of drawing Mermaid this way. What can still be missing is a
/// `WKWebView` that will load at all, which under some test runners it will
/// not; that case reports itself rather than failing, because it is a fact
/// about the runner rather than about the code.
@MainActor
struct MermaidLiveTests {
	static let flowchart = """
	flowchart TD
	    A[Start] --> B{Is it a diagram?}
	    B -- yes --> C[Draw it]
	    B -- no --> D[Say so]
	    C --> E[Export beside the file]
	    D --> E
	"""

	static let sequence = """
	sequenceDiagram
	    participant Editor
	    participant Preview
	    participant Mermaid
	    Editor->>Preview: text changed
	    Preview->>Mermaid: render(source)
	    Mermaid-->>Preview: an SVG
	    Preview-->>Editor: the picture
	"""

	private func madeFolder() throws -> URL {
		let folder = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-mermaid-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}

	/// Whether a web view loaded here at all, so a runner that cannot host one
	/// says so instead of failing every test below it.
	private func canDraw() async -> Bool {
		let drawn = await MermaidRenderer.shared.draw("flowchart TD\n A --> B", format: .svg)
		if case .failure(.trouble(let said)) = drawn, said == Mermaid.missingBundleHint {
			print("MERMAID: no web view here — \(said)")
			return false
		}
		return true
	}

	// MARK: - Drawing

	/// Both shapes of diagram the pane will meet first, drawn and looked at.
	@Test func aFlowchartAndASequenceAreBothRealDrawings() async throws {
		guard await canDraw() else { return }
		for (name, source) in [("flowchart", Self.flowchart), ("sequence", Self.sequence)] {
			let drawn = await MermaidRenderer.shared.draw(source, format: .svg)
			guard case let .success(data) = drawn else {
				Issue.record("\(name) did not draw: \(drawn)")
				continue
			}
			let svg = String(decoding: data, as: UTF8.self)
			#expect(svg.contains("<svg"))
			#expect(svg.contains("</svg>"))
			// A size of its own, which is what stops every viewer guessing a
			// different one — and what made the first PNG 172×300.
			#expect(!svg.contains("width=\"100%\""))
			#expect(svg.contains("viewBox="))
			#expect(DiagramExport.isDrawnHere(data))
			// No `foreignObject`: the labels are `<text>`, so the file is a
			// picture outside a browser as well as in one.
			#expect(!svg.contains("foreignObject"))
			// And nothing is left depending on a CSS engine. An edge whose
			// `fill:none` lived in a stylesheet is drawn as a solid black wedge
			// by everything that is not a browser — which is what the pane
			// showed before this was inlined.
			#expect(!svg.contains("<style"))
			#expect(svg.contains("fill=\"none\""))
			#expect(svg.contains("stroke-width="))
			// Nothing points at a marker any more: they are geometry, so the
			// arrowheads are on the page in renderers that draw no markers.
			#expect(!svg.contains("marker-end="))
			#expect(!svg.contains("<marker"))
			// And no run inside a row re-anchors the row. A `text-anchor` on the
			// element a text chunk starts at is honoured by a browser and
			// ignored by CoreSVG, which is two different pictures from one file
			// — seen, with "Tell the customer" hanging off the left edge of the
			// exported PNG while the pane had it centred.
			for piece in svg.components(separatedBy: "<tspan").dropFirst() {
				let tag = piece.prefix(while: { $0 != ">" })
				#expect(!tag.contains("text-anchor"))
			}
			#expect(data.count > 2000, "\(name) came back suspiciously small")
		}
	}

	/// `autonumber`, whose badge is a marker on a line with no length.
	///
	/// The fifth thing that had to be baked, found by drawing the examples
	/// repository's sequence diagram and looking at it. Mermaid numbers a
	/// message by drawing a line from a point to *itself*, hanging the badge off
	/// its `marker-start` and writing the number in white on top of it. A
	/// zero-length line was skipped as nothing to place a marker on, so the
	/// reference was left standing on a marker that is removed a moment later —
	/// and white numerals on white paper are the same as no numbers at all.
	@Test func anAutonumberedSequenceKeepsItsBadges() async throws {
		guard await canDraw() else { return }
		let numbered = "sequenceDiagram\n    autonumber\n" + Self.sequence
			.split(separator: "\n").dropFirst().joined(separator: "\n")
		let drawn = await MermaidRenderer.shared.draw(numbered, format: .svg)
		guard case let .success(data) = drawn else {
			Issue.record("an autonumbered sequence did not draw: \(drawn)")
			return
		}
		let svg = String(decoding: data, as: UTF8.self)
		#expect(!svg.contains("marker-start="), "a badge is still a marker reference")
		#expect(svg.contains("sequenceNumber"), "the numbers themselves are missing")
		// Four messages, so four badges — and the circle each is drawn on is the
		// part that went missing while the numbers stayed.
		let circles = svg.components(separatedBy: "<circle").count - 1
		#expect(circles >= 4, "only \(circles) circles, so the badges are not drawn")
	}

	/// The one thing a preview and an export must not agree about: the pane
	/// draws SVG for sharpness, and asking for a PNG has to give a PNG.
	@Test func aPNGIsAPNGAndNotWhateverWasOnScreen() async throws {
		guard await canDraw() else { return }
		let drawn = await MermaidRenderer.shared.draw(Self.flowchart, format: .png)
		guard case let .success(data) = drawn else {
			Issue.record("no picture: \(drawn)")
			return
		}
		#expect(Array(data.prefix(8)) == DiagramStamp.pngSignature)
		#expect(DiagramExport.isDrawnHere(data))
		// Rasterised at 2×, so the picture is the size of the drawing doubled
		// rather than a browser's default 300×150 box.
		let bytes = [UInt8](data)
		let width = (Int(bytes[16]) << 24) | (Int(bytes[17]) << 16)
			| (Int(bytes[18]) << 8) | Int(bytes[19])
		let height = (Int(bytes[20]) << 24) | (Int(bytes[21]) << 16)
			| (Int(bytes[22]) << 8) | Int(bytes[23])
		#expect(width > 400, "a 2× flowchart should be wider than 400px, was \(width)")
		#expect(height > 800, "a 2× flowchart should be taller than 800px, was \(height)")
	}

	// MARK: - Exporting

	@Test func aDiagramIsWrittenBesideItselfInBothFormats() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("flow.mmd")
		try Self.flowchart.write(to: source, atomically: true, encoding: .utf8)

		for format in DiagramFormat.allCases {
			let written = await DiagramExport.export(
				mermaid: Self.flowchart, of: source, format: format
			)
			guard case let .success(files) = written else {
				Issue.record("\(format) did not export: \(written)")
				continue
			}
			#expect(files.count == 1)
			let picture = try #require(files.first)
			#expect(picture.lastPathComponent == "flow.\(format.rawValue)")
			let onDisk = try Data(contentsOf: picture)
			#expect(!onDisk.isEmpty)
			#expect(DiagramExport.isDrawnHere(onDisk))
			if format == .png {
				#expect(Array(onDisk.prefix(8)) == DiagramStamp.pngSignature)
			} else {
				#expect(String(decoding: onDisk, as: UTF8.self).contains("<svg"))
			}
		}

		// And again, over what was written the first time: exporting twice is
		// the ordinary way of working, not a mistake to catch.
		let again = await DiagramExport.export(mermaid: Self.sequence, of: source, format: .svg)
		guard case .success = again else {
			Issue.record("a second export refused its own picture: \(again)")
			return
		}
	}

	/// Nothing is written for a diagram that does not parse, and what is said is
	/// one sentence with the line in it. The picture of the error PlantUML draws
	/// has no equivalent here — Mermaid throws — and the rule is the same.
	@Test func aDiagramThatDoesNotParseWritesNothingAndNamesTheLine() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("broken.mmd")
		let broken = "sequenceDiagram\n    Alice->>Bob: hi\n    thisisnotavalidline ??? %%%\n"
		try broken.write(to: source, atomically: true, encoding: .utf8)

		let written = await DiagramExport.export(mermaid: broken, of: source, format: .png)
		guard case let .failure(failure) = written else {
			Issue.record("a diagram that does not parse was exported anyway")
			return
		}
		#expect(failure.message.hasPrefix("broken.mmd line 3:"))
		#expect(!failure.message.contains("\n"))
		#expect(!FileManager.default.fileExists(atPath: folder
			.appendingPathComponent("broken.png").path))
	}

	/// A file with the name an export wants, which this app did not draw, stops
	/// the export instead of being destroyed.
	@Test func somebodyElsesPictureIsNotOverwritten() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("flow.mmd")
		try Self.flowchart.write(to: source, atomically: true, encoding: .utf8)
		let theirs = folder.appendingPathComponent("flow.svg")
		try "<svg>a drawing somebody made by hand</svg>".write(
			to: theirs, atomically: true, encoding: .utf8
		)

		let written = await DiagramExport.export(mermaid: Self.flowchart, of: source, format: .svg)
		guard case let .failure(failure) = written else {
			Issue.record("somebody's own drawing was overwritten")
			return
		}
		#expect(failure.message.contains("flow.svg"))
		#expect(try String(contentsOf: theirs, encoding: .utf8).contains("by hand"))
	}

	// MARK: - Exporting a document full of fences

	/// `Tests/AbydosKitTests/Fixtures/diagrams.md`, read from where it is written
	/// rather than from a copy in here — the preview is looked at in that file,
	/// and the export has to agree with it.
	private func fixture(_ name: String) throws -> String {
		let url = try #require(Bundle.module.url(
			forResource: name, withExtension: "md", subdirectory: "Fixtures"
		))
		return try String(contentsOf: url, encoding: .utf8)
	}

	/// Three fences of three kinds in one document, written out and read back.
	///
	/// The thing no rule test can say: that what lands beside a README is three
	/// pictures rather than three files. A PNG of nought bytes and an SVG holding
	/// an error message both look like success from everywhere except here.
	@Test func everyFenceInADocumentIsWrittenAndEveryFileIsAPicture() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let document = try fixture("diagrams")
		let source = folder.appendingPathComponent("README.md")
		try document.write(to: source, atomically: true, encoding: .utf8)

		for format in DiagramFormat.allCases {
			let written = await DiagramExport.export(
				markdown: document, of: source, format: format, theme: .light
			)
			guard case let .success(files) = written else {
				Issue.record("\(format) did not export: \(written)")
				continue
			}
			#expect(files.map(\.lastPathComponent) == [
				"README-1.\(format.rawValue)",
				"README-2.\(format.rawValue)",
				"README-3.\(format.rawValue)",
			])
			// Every one opened and looked at, which is the whole point of this
			// test: the file is a picture, it is signed, and it is not tiny.
			for file in files {
				let onDisk = try Data(contentsOf: file)
				#expect(onDisk.count > 500, "\(file.lastPathComponent) is \(onDisk.count) bytes")
				#expect(DiagramExport.isDrawnHere(onDisk))
				if format == .png {
					#expect(Array(onDisk.prefix(8)) == DiagramStamp.pngSignature)
				} else {
					let svg = String(decoding: onDisk, as: UTF8.self)
					#expect(svg.contains("<svg"))
					#expect(svg.contains("</svg>"))
					// The flattening, which a fence goes through exactly as a `.mmd`
					// does: no stylesheet left to apply and no HTML labels in it.
					#expect(!svg.contains("<style"))
					#expect(!svg.contains("foreignObject"))
					#expect(!svg.lowercased().contains("syntax error"))
				}
			}
			// Each of the three is its own diagram rather than three copies of the
			// first, which is what a wrong offset into the document would produce.
			let sizes = try files.map { try Data(contentsOf: $0).count }
			#expect(Set(sizes).count == 3, "three fences came out as \(sizes)")
		}

		// A dark export writes the pair beside them rather than over them, and the
		// light pictures are still there afterwards.
		let dark = await DiagramExport.export(
			markdown: document, of: source, format: .svg, theme: .dark
		)
		guard case let .success(files) = dark else {
			Issue.record("the dark export did not happen: \(dark)")
			return
		}
		#expect(files.map(\.lastPathComponent)
			== ["README-1-dark.svg", "README-2-dark.svg", "README-3-dark.svg"])
		#expect(FileManager.default.fileExists(
			atPath: folder.appendingPathComponent("README-1.svg").path
		))
	}

	/// One fence that does not parse, and the whole document is refused.
	///
	/// The complaint names the line of the *file* rather than of the block, which
	/// is the number in the editor beside it — and not one of the three good
	/// diagrams above it is written, because everything is drawn before anything
	/// is written.
	@Test func oneBrokenFenceWritesNothingAtAllAndNamesTheLineOfTheFile() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let document = try fixture("diagrams") + """

		## And one that does not parse

		```mermaid
		sequenceDiagram
		    Customer->>Shop: Order a shelf
		    Shop ??? Workshop
		```
		"""
		let source = folder.appendingPathComponent("README.md")
		try document.write(to: source, atomically: true, encoding: .utf8)

		let written = await DiagramExport.export(markdown: document, of: source, format: .png)
		guard case let .failure(failure) = written else {
			Issue.record("a document with a broken fence in it was exported anyway")
			return
		}
		// Printed rather than only asserted: the sentence is the whole of what
		// somebody gets, and a test that only checks its prefix cannot show that
		// it reads as one.
		print("MERMAID: \(failure.message)")
		#expect(!failure.message.contains("\n"))
		// The line is the one in the editor, which is inside the fourth block
		// rather than inside a diagram counted from its own first line.
		let offending = try #require(document.components(separatedBy: "\n")
			.firstIndex(where: { $0.contains("Shop ??? Workshop") })) + 1
		#expect(failure.message.hasPrefix("README.md line \(offending):"),
		        "\(failure.message)")

		// Nothing written, not even the three that drew perfectly well.
		let leftBehind = try FileManager.default
			.contentsOfDirectory(atPath: folder.path)
			.filter { $0 != "README.md" }
		#expect(leftBehind.isEmpty, "these were written anyway: \(leftBehind)")
	}

	/// A picture nobody here drew stops the whole document, by the same rule and
	/// the same reading of the bytes that protects `diagram.png`.
	@Test func aStrangersPictureStopsAWholeDocument() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let document = try fixture("diagrams")
		let source = folder.appendingPathComponent("README.md")
		try document.write(to: source, atomically: true, encoding: .utf8)
		let theirs = folder.appendingPathComponent("README-2.svg")
		try "<svg>a drawing somebody made by hand</svg>".write(
			to: theirs, atomically: true, encoding: .utf8
		)

		let written = await DiagramExport.export(markdown: document, of: source, format: .svg)
		guard case let .failure(failure) = written else {
			Issue.record("somebody's own drawing was overwritten")
			return
		}
		#expect(failure.message.contains("README-2.svg"))
		#expect(try String(contentsOf: theirs, encoding: .utf8).contains("by hand"))
		#expect(!FileManager.default.fileExists(
			atPath: folder.appendingPathComponent("README-1.svg").path
		))
	}

	/// A fence that named itself is named after itself on disk, and the fence
	/// beside it that chose its own look keeps the plain name while the other
	/// gains `-dark`.
	@Test func aNamedFenceAndAFenceThatChoseAreBothWrittenAsTheyAsked() async throws {
		guard await canDraw() else { return }
		let folder = try madeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let document = """
		# Two diagrams

		```mermaid
		---
		title: Ordering a shelf
		---
		flowchart TD
		    A[Order placed] --> B[Pack it]
		```

		```mermaid
		%%{init: {'theme': 'forest'}}%%
		flowchart TD
		    C[Cut] --> D[Post]
		```
		"""
		let source = folder.appendingPathComponent("README.md")
		try document.write(to: source, atomically: true, encoding: .utf8)

		let written = await DiagramExport.export(
			markdown: document, of: source, format: .svg, theme: .dark
		)
		guard case let .success(files) = written else {
			Issue.record("the export did not happen: \(written)")
			return
		}
		#expect(files.map(\.lastPathComponent)
			== ["README-ordering-a-shelf-dark.svg", "README-2.svg"])
		for file in files {
			let svg = try String(contentsOf: file, encoding: .utf8)
			#expect(svg.contains("<svg"))
			#expect(!svg.lowercased().contains("syntax error"))
		}
		// The one that chose is drawn in its own colours, so it has no paper of
		// this app's painted under it; the one that did not is on dark paper.
		#expect(try String(contentsOf: files[0], encoding: .utf8)
			.contains(DiagramTheme.dark.paper))
		#expect(try !String(contentsOf: files[1], encoding: .utf8)
			.contains(DiagramTheme.dark.paper))
	}

	/// The measurement the whole decision rests on: the second diagram and every
	/// one after it costs hundredths of a second, against a second a piece from
	/// a container that has no server mode to keep warm.
	@Test func drawingIsFastEnoughToDoWhileSomebodyTypes() async throws {
		guard await canDraw() else { return }
		_ = await MermaidRenderer.shared.draw(Self.flowchart, format: .svg)
		let began = Date()
		for _ in 0..<5 {
			_ = await MermaidRenderer.shared.draw(Self.sequence, format: .svg)
		}
		let each = Date().timeIntervalSince(began) / 5
		print("MERMAID: \(String(format: "%.4f", each))s a warm render, \(MachineLoad.said)")
		// Only where a stopwatch means anything. This bound is about the renderer
		// keeping its page loaded; on a machine with nothing left to give it is
		// about the scheduler instead, and a red from it says nothing anybody can
		// act on. See `MachineLoad.canBeTimed`, and 0435 for what it cost.
		guard MachineLoad.canBeTimed else {
			print("MERMAID: not timing the warm render — \(MachineLoad.said)")
			return
		}
		#expect(each < 0.5, "a warm render took \(each)s, which is not a preview that follows typing")
	}
}

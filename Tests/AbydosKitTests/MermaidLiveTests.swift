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
			#expect(data.count > 2000, "\(name) came back suspiciously small")
		}
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
		print("MERMAID: \(String(format: "%.4f", each))s a warm render")
		#expect(each < 0.5, "a warm render took \(each)s, which is not a preview that follows typing")
	}
}

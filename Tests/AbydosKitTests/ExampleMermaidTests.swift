import Foundation
import Testing
@testable import AbydosKit

/// The Mermaid diagrams in the examples repository, drawn by the renderer they
/// were written against.
///
/// The same argument as `ExampleDevContainerTests`: 0425 asks for examples to
/// work against, and an example nothing asserts about drifts. This one has more
/// to say than a reader test can, because the four faults that had to be fixed
/// before a Mermaid drawing was a *picture* — edges filled solid, arrowheads
/// missing, labels above their boxes, a row re-anchored by its first word —
/// were every one of them found by looking at what landed on screen rather than
/// by a diagram failing to parse. All four were found in a flowchart and a
/// sequence diagram; the class, state, entity-relationship and git diagrams
/// here are laid out by different code inside Mermaid, and this is what asks
/// them the same questions.
///
/// Skipped when the examples repository is not beside this one, and when the
/// runner will not host a `WKWebView` — both are facts about where this is
/// running rather than about the code.
@MainActor
struct ExampleMermaidTests {
	/// Every diagram in `mermaid/`, and the kind of drawing each one is there to
	/// exercise. The list is the promise: a file added to that folder and not to
	/// this list fails the last test below.
	///
	/// `nonisolated` because `@Test(arguments:)` reads it from outside the actor
	/// this suite is pinned to — a warning today and an error in the Swift 6
	/// language mode. See `MermaidEveryKindLiveTests.kinds`.
	nonisolated static let examples: [(file: String, kind: String)] = [
		("render.mmd", "flowchart"),
		("export.mermaid", "sequenceDiagram"),
		("document.mmd", "stateDiagram-v2"),
		("preview.mmd", "classDiagram"),
		("project.mmd", "erDiagram"),
		("branches.mmd", "gitGraph"),
	]

	/// `../abydos-examples/mermaid`, found from this file rather than from the
	/// working directory — and from three levels further up as well, since a
	/// worktree sits under `.claude/worktrees/<name>`.
	private static var folder: URL? {
		let repository = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent() // AbydosKitTests
			.deletingLastPathComponent() // Tests
			.deletingLastPathComponent() // the checkout
		let candidates = [
			repository.deletingLastPathComponent(),
			repository
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent(),
		]
		for beside in candidates {
			let url = beside.appendingPathComponent("abydos-examples/mermaid")
			var isDirectory: ObjCBool = false
			if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
			   isDirectory.boolValue
			{
				return url
			}
		}
		return nil
	}

	/// Whether a web view loaded here at all, so a runner that cannot host one
	/// says so rather than failing every diagram below it.
	private func canDraw() async -> Bool {
		let drawn = await MermaidRenderer.shared.draw("flowchart TD\n A --> B", format: .svg)
		if case .failure(.trouble(let said)) = drawn, said == Mermaid.missingBundleHint {
			print("MERMAID: no web view here — \(said)")
			return false
		}
		return true
	}

	private func read(_ file: String) throws -> String? {
		guard let folder = Self.folder else { return nil }
		return try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
	}

	// MARK: - Every one of them is a picture

	/// Each example drawn, and asked the four questions the flattening exists to
	/// answer. A diagram type that answers one of them wrongly is a bug in the
	/// app and not a bad example, which is why this names the file and the fault
	/// rather than skipping anything.
	@Test(arguments: examples)
	func eachExampleDrawsAsAPictureRatherThanAProgram(file: String, kind: String) async throws {
		guard let source = try read(file) else { return }
		guard await canDraw() else { return }
		#expect(source.contains(kind), "\(file) no longer holds a \(kind)")

		let drawn = await MermaidRenderer.shared.draw(source, format: .svg)
		guard case let .success(data) = drawn else {
			Issue.record("\(file) did not draw: \(drawn)")
			return
		}
		let svg = String(decoding: data, as: UTF8.self)

		// A size of its own, so every viewer draws it the same size.
		#expect(!svg.contains("width=\"100%\""), "\(file) has no size of its own")
		#expect(svg.contains("viewBox="), "\(file) has no viewBox")
		// Labels as text, not as a browser's HTML in a foreignObject.
		#expect(!svg.contains("foreignObject"), "\(file) draws labels in a foreignObject")
		// Nothing left depending on a CSS engine: an edge whose `fill:none` lived
		// in a stylesheet is a solid black wedge everywhere that is not a browser.
		#expect(!svg.contains("<style"), "\(file) still carries a stylesheet")
		// Arrowheads as geometry rather than as a reference CoreSVG draws nothing
		// for — and the same for `marker-start`, which is how a sequence
		// diagram's `autonumber` badge is drawn: a line from a point to itself
		// with the badge hanging off its start.
		#expect(!svg.contains("marker-end="), "\(file) still points at a marker")
		#expect(!svg.contains("marker-start="), "\(file) still points at a marker")
		#expect(!svg.contains("<marker"), "\(file) still defines a marker")
		// And no run inside a row re-anchoring the row, which drew one picture in
		// the pane and a different one in the exported PNG.
		for piece in svg.components(separatedBy: "<tspan").dropFirst() {
			let tag = piece.prefix(while: { $0 != ">" })
			#expect(!tag.contains("text-anchor"), "\(file) anchors a run inside a row")
		}
		#expect(DiagramExport.isDrawnHere(data), "\(file) is not stamped")
		#expect(data.count > 1500, "\(file) came back suspiciously small: \(data.count) bytes")
	}

	/// Every label in the file is somewhere in the drawing.
	///
	/// The cheapest possible answer to "is it the right picture?", and it is
	/// worth having because the ways a Mermaid drawing goes wrong are quiet: a
	/// row of text dropped, a label drawn empty, a shape whose contents never
	/// arrived. None of those fail a render.
	@Test func theWordsInTheDiagramsReachTheDrawing() async throws {
		guard await canDraw() else { return }
		let wanted: [String: [String]] = [
			"render.mmd": ["Somebody types in the editor", "Rasterise", "white paper"],
			"export.mermaid": ["Preview pane", "the file selected in the tree"],
			"document.mmd": ["Changed underneath", "git checkout", "keep mine"],
			"preview.mmd": ["MermaidPreviewView", "WebRenderer", "draws with"],
			"project.mmd": ["RUN_CONFIGURATION", "allowedContexts", "keeps in .abydos/run"],
			"branches.mmd": ["conflict", "resolved", "feature"],
		]
		for (file, words) in wanted.sorted(by: { $0.key < $1.key }) {
			guard let source = try read(file) else { return }
			let drawn = await MermaidRenderer.shared.draw(source, format: .svg)
			guard case let .success(data) = drawn else {
				Issue.record("\(file) did not draw: \(drawn)")
				continue
			}
			// Compared with the tags out and the spaces out. Mermaid wraps a long
			// label onto rows, and every row becomes a `<text>` of its own — so
			// "Somebody types in the editor" is drawn as "Somebody types in the"
			// and "editor", and looking for the sentence would fail on a picture
			// that is perfectly correct.
			let flat = String(decoding: data, as: UTF8.self)
				.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
				.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
			for word in words {
				let wanted = word.replacingOccurrences(
					of: "\\s+", with: "", options: .regularExpression
				)
				#expect(flat.contains(wanted), "\(file) drew nothing saying “\(word)”")
			}
		}
	}

	// MARK: - And each one exports

	/// Both formats, written beside a copy of the file rather than beside the
	/// example itself: the examples repository keeps its sources and not its
	/// pictures, the way `plantuml/` draws into `build/`.
	@Test func eachExampleExportsInBothFormats() async throws {
		guard let folder = Self.folder else { return }
		guard await canDraw() else { return }
		let work = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-examples-mermaid-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: work) }

		for (file, _) in Self.examples {
			let source = try String(
				contentsOf: folder.appendingPathComponent(file), encoding: .utf8
			)
			let copy = work.appendingPathComponent(file)
			try source.write(to: copy, atomically: true, encoding: .utf8)

			for format in DiagramFormat.allCases {
				let written = await DiagramExport.export(mermaid: source, of: copy, format: format)
				guard case let .success(files) = written, let picture = files.first else {
					Issue.record("\(file) did not export as \(format): \(written)")
					continue
				}
				let onDisk = try Data(contentsOf: picture)
				#expect(!onDisk.isEmpty, "\(file) exported nought bytes of \(format)")
				#expect(DiagramExport.isDrawnHere(onDisk), "\(file)'s \(format) is not stamped")
				if format == .png {
					#expect(Array(onDisk.prefix(8)) == DiagramStamp.pngSignature)
					// A PNG of an empty page is a few hundred bytes and looks like
					// success everywhere except here.
					#expect(onDisk.count > 8000, "\(file).png is \(onDisk.count) bytes")
				} else {
					#expect(String(decoding: onDisk, as: UTF8.self).contains("</svg>"))
				}
			}
		}
	}

	// MARK: - The list and the folder agree

	/// A diagram added to the folder and not to the list above is a diagram
	/// nothing here looks at, which is exactly the drift these tests exist to
	/// stop.
	@Test func everyFileInTheFolderIsOneOfTheseAndTheOtherWayAround() throws {
		guard let folder = Self.folder else { return }
		let found = try FileManager.default
			.contentsOfDirectory(atPath: folder.path)
			.filter { Mermaid.isDiagram(URL(fileURLWithPath: $0)) }
			.sorted()
		#expect(found == Self.examples.map(\.file).sorted())
		// Both extensions, exercised by the examples rather than only by a unit
		// test: they are two rows in `FilePreview` and one of them is easy to
		// forget.
		#expect(found.contains { $0.hasSuffix(".mmd") })
		#expect(found.contains { $0.hasSuffix(".mermaid") })
	}
}

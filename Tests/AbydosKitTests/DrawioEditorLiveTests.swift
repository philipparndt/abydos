import AppKit
import Foundation
import Testing
@testable import AbydosKit

/// The real draw.io editor, loaded, given a document, drawn in, and read back.
///
/// This is the half of 0426 that could go wrong quietly. Every test here is
/// about the document rather than about the picture: whether what comes back
/// out of the editor is what went in, whether a change is heard about at all,
/// and whether a file draw.io itself wrote is written back in the form it
/// arrived in rather than as a diff nobody asked for.
///
/// What can still be missing is a `WKWebView` that will host draw.io at all,
/// which under some runners it will not; that reports itself rather than
/// failing, because it is a fact about the runner.
@MainActor
struct DrawioEditorLiveTests {
	/// One editor, loaded and ready, or nil if a web view will not host one.
	private func opened() async -> DrawioEditor? {
		guard let editor = DrawioEditor.make() else { return nil }
		editor.webView.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
		var ready = false
		editor.onReady = { ready = true }
		editor.start()
		for _ in 0..<60 where !ready {
			try? await Task.sleep(nanoseconds: 250_000_000)
		}
		guard ready else {
			print("DRAWIO: no editor here — the web view did not load draw.io")
			return nil
		}
		return editor
	}

	private func settle(_ times: Int = 8) async {
		for _ in 0..<times { try? await Task.sleep(nanoseconds: 250_000_000) }
	}

	// MARK: - The document, both ways

	/// A file goes in and the same diagram comes back out. Not the same bytes —
	/// draw.io rewrites its own header — but the same pages with the same
	/// contents, which is what a document is.
	@Test func aDocumentSurvivesGoingThroughTheEditor() async throws {
		guard let editor = await opened() else { return }
		defer { editor.webView.navigationDelegate = nil }
		let document = try #require(Drawio.read(try DrawioTests.fixture("pages")))
		editor.load(document.mxfile, compressed: document.isCompressed)
		await settle()

		let back = try #require(await editor.currentDocument())
		let read = try #require(Drawio.read(Data(back.utf8)))
		#expect(read.pages.map(\.name) == ["Overview", "Detail", "Deployment"])
		#expect(read.pages[0].model.contains("Overview box"))
		// And the labels are not full of `%20`, which is what skipping
		// `decodeURIComponent` looks like and what parses perfectly.
		#expect(!read.pages[0].model.contains("%20"))
	}

	/// A file that arrived compressed is written back compressed, and a plain
	/// one plain.
	///
	/// draw.io's own default is *uncompressed*, so without this every file
	/// draw.io wrote — which is every file, all 155 of its own templates
	/// included — would turn into a diff thousands of lines long the first time
	/// somebody moved a box. That is how people stop trusting an editor.
	@Test func aFileIsWrittenBackInTheFormItArrivedIn() async throws {
		guard let editor = await opened() else { return }
		defer { editor.webView.navigationDelegate = nil }

		for (name, wasCompressed) in [("pages", true), ("plain", false)] {
			let document = try #require(Drawio.read(try DrawioTests.fixture(name)))
			#expect(document.isCompressed == wasCompressed)
			editor.load(document.mxfile, compressed: document.isCompressed)
			await settle()
			let back = try #require(await editor.currentDocument())
			let read = try #require(Drawio.read(Data(back.utf8)))
			#expect(
				read.isCompressed == wasCompressed,
				"\(name) went in \(wasCompressed ? "compressed" : "plain") and came back the other way"
			)
		}
	}

	/// Drawing in the editor is an edit to the file, heard about at once.
	///
	/// Not on draw.io's own autosave timer, which is a second and a half. The
	/// tab's edited dot has to appear when the shape is dropped, and ⌘S a
	/// moment later has to write what is on screen.
	@Test func aChangeInTheEditorIsAChangeToTheFile() async throws {
		guard let editor = await opened() else { return }
		defer { editor.webView.navigationDelegate = nil }
		let document = try #require(Drawio.read(try DrawioTests.fixture("plain")))

		var reported: [String] = []
		editor.onChanged = { reported.append($0) }
		editor.load(document.mxfile, compressed: false)
		await settle()
		reported.removeAll()

		// A shape dropped on the canvas, through draw.io's own model rather
		// than through anything of this app's.
		_ = try? await editor.webView.callAsyncJavaScript("""
			const graph = abydosUi.editor.graph;
			graph.getModel().beginUpdate();
			try {
				graph.insertVertex(graph.getDefaultParent(), null, 'Drawn by a test',
					40, 400, 200, 60, 'rounded=1;whiteSpace=wrap;html=1;');
			} finally { graph.getModel().endUpdate(); }
			return true;
			""", arguments: [:], in: nil, contentWorld: .page)
		await settle(4)

		#expect(!reported.isEmpty, "drawing in the editor said nothing to the app")
		let last = try #require(reported.last)
		let read = try #require(Drawio.read(Data(last.utf8)))
		#expect(read.pages[0].model.contains("Drawn by a test"))
	}

	// MARK: - What it draws

	/// The editor can export what is on screen, and the picture is a picture
	/// outside a browser — no `foreignObject`, no `light-dark()`.
	@Test func theEditorExportsAPictureAnythingCanRead() async throws {
		guard let editor = await opened() else { return }
		defer { editor.webView.navigationDelegate = nil }
		let document = try #require(Drawio.read(try DrawioTests.fixture("stencils")))
		editor.load(document.mxfile, compressed: document.isCompressed)
		await settle()

		let drawing = try #require(await editor.export(.svg))
		let svg = String(decoding: drawing, as: UTF8.self)
		#expect(svg.contains("<svg"))
		#expect(!svg.contains("foreignObject"))
		#expect(!svg.contains("light-dark("))
		#expect(svg.contains("EC2"))
		#expect(NSImage(data: drawing)?.size.width ?? 0 > 0)

		let picture = try #require(await editor.export(.png))
		#expect(Array(picture.prefix(8)) == DiagramStamp.pngSignature)
		#expect(picture.count > 3000, "the picture is \(picture.count) bytes, which is a blank page")
	}

	/// Nothing the editor asks for leaves this machine, and what it asks for
	/// and does not get is written down rather than drawn as a gap.
	@Test func everythingTheEditorNeedsIsInThisBuild() async throws {
		guard let editor = await opened() else { return }
		defer { editor.webView.navigationDelegate = nil }
		let document = try #require(Drawio.read(try DrawioTests.fixture("stencils")))
		editor.load(document.mxfile, compressed: document.isCompressed)
		await settle()

		// Two things are deliberately left out and are named in one place.
		// Anything *else* missing is a vendoring mistake, and the scheme
		// handler is the only place that would ever know — a draw.io asking for
		// a file it does not get carries on drawing and says nothing.
		let unexpected = editor.missingAssets.filter { path in
			// A request for the literal string "null", which draw.io makes once
			// on load from a URL it builds out of a setting nobody set. It is
			// answered 404 and nothing looks for the answer.
			path != "null" && !Drawio.notCarried.contains { path.hasPrefix($0) }
		}
		#expect(unexpected.isEmpty, "the editor asked for files this build does not have: \(unexpected)")
	}
}

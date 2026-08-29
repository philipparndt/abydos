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

	/// Elapsed time with nothing to wait for.
	///
	/// The editor is a web view running somebody else's JavaScript, and what is
	/// being given time to happen is a render this side has no signal for — the
	/// `onReady` above is the last thing it says. Every wait in this file that
	/// *can* watch for something does; this is what is left.
	private func settle(_ times: Int = 8) async {
		for _ in 0..<times { try? await Task.sleep(nanoseconds: 250_000_000) }
	}

	/// Waits for something to become true, for the waits that have something to
	/// watch.
	///
	/// A hang detector rather than a bound, so the ceiling is `Patience`'s and
	/// not a number chosen from what somebody watched fail — which is what the
	/// four-second sleep this replaces was.
	private func waitUntil(
		_ seconds: TimeInterval = Patience.seconds, _ done: () -> Bool
	) async {
		let deadline = Date().addingTimeInterval(seconds)
		while Date() < deadline {
			if done() { return }
			try? await Task.sleep(nanoseconds: 100_000_000)
		}
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

	/// Opening a file is not editing it, and this is the test that says so.
	///
	/// draw.io re-serialises the document as it loads it, and the text it hands
	/// back is never the text that went in: its own indentation, and
	/// `<mxGraphModel dx dy>` set to the size of the window it is being looked at
	/// in. Compared as text that is a change — so the tab grew its edited dot,
	/// closing asked whether to save, and auto-save would have rewritten a file
	/// nobody touched. Seen, on three fixtures, none of them touched.
	///
	/// The text really does come back different, and that is asserted rather than
	/// assumed: without it this test would pass just as well over a comparison
	/// that did nothing, and the sentence above would be a story.
	@Test func openingAFileIsNotEditingIt() async throws {
		guard let editor = await opened() else { return }
		defer { editor.webView.navigationDelegate = nil }

		var rewritten = 0
		for name in ["plain", "pages", "stencils"] {
			let bytes = try DrawioTests.fixture(name)
			let document = try #require(Drawio.read(bytes))
			editor.load(document.mxfile, compressed: document.isCompressed)
			await settle()
			let back = try #require(await editor.currentDocument())
			if back != document.mxfile { rewritten += 1 }
			#expect(
				Drawio.isSameDrawing(back, as: document.mxfile),
				"opening \(name).drawio counted as an edit to it"
			)
		}
		#expect(
			rewritten == 3,
			"\(3 - rewritten) file(s) came back byte-identical, so this test no longer measures what it claims to"
		)
	}

	/// The claim the editable picture is named for, checked against draw.io
	/// itself rather than against this app's reader.
	///
	/// `architecture.drawio.png` is offered as *the document*, so a test that
	/// only reads it back with `Drawio.read` is checking this app against itself:
	/// the same code wrote the chunk and the same code took it out again, and
	/// both could be wrong together. So the picture is written by the export,
	/// opened, and the document inside it handed to the real editor — which
	/// draws it, counts its pages and hands it back. The picture, having been
	/// through draw.io, is still the three-page diagram it was made from.
	@Test func aPictureThisAppWroteOpensAgainInTheRealEditor() async throws {
		guard let editor = await opened() else { return }
		defer { editor.webView.navigationDelegate = nil }
		let folder = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-drawio-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }

		let bytes = try DrawioTests.fixture("pages")
		let before = try #require(Drawio.read(bytes))
		let source = folder.appendingPathComponent("architecture.drawio")
		try bytes.write(to: source)
		let written = await DiagramExport.export(editable: bytes, of: source, format: .png)
		guard case let .success(file) = written else {
			Issue.record("nothing saved: \(written)")
			return
		}

		// Opened the way somebody opening the picture would have it opened, and
		// then it is draw.io's turn.
		let inside = try #require(Drawio.read(try Data(contentsOf: file)))
		editor.load(inside.mxfile, compressed: inside.isCompressed)
		await settle()
		let back = try #require(await editor.currentDocument())
		let read = try #require(Drawio.read(Data(back.utf8)))
		#expect(read.pages.map(\.name) == before.pages.map(\.name))
		#expect(read.pages[0].model.contains("Overview box"))
		#expect(!read.pages[0].model.contains("%20"))
		// And it is the same drawing, not merely a document with the right
		// number of pages in it.
		#expect(Drawio.isSameDrawing(back, as: before.mxfile))
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
		// **Watched, not slept through.** This file's `settle` is for waits with
		// nothing to watch, and its own comment says so; this one has something
		// — `reported` filling — so it waits for that instead of for four
		// seconds. Four was enough on a quiet machine and not on a loaded one,
		// which is the whole of why this test was intermittently red.
		await waitUntil { !reported.isEmpty }

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

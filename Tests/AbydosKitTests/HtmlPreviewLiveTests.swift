import AppKit
import Foundation
import Testing
import WebKit
@testable import AbydosKit

/// A real web view, served by `HtmlScheme`, asked what it ended up with.
///
/// The half of this feature that could go wrong quietly. Everything here is
/// about what the page *got*: whether the document it rendered was the buffer
/// or the file on disk, whether a stylesheet beside it arrived, and whether a
/// reference that climbs out of the directory was refused. None of it can be
/// answered without loading something.
///
/// What can still be missing is a `WKWebView` that will run at all, which under
/// some runners it will not; that reports itself rather than failing, because it
/// is a fact about the runner. `DrawioEditorLiveTests` makes the same trade.
@MainActor
struct HtmlPreviewLiveTests {
	private func scratch() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("html-live-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	/// A web view wired the way the pane wires one, with the rule list in it.
	private func page(
		file: URL, document: String
	) async -> (web: WKWebView, scheme: HtmlScheme)? {
		guard let list = await HtmlBlocking.list() else {
			print("HTML: no content rule list here — the store would not compile one")
			return nil
		}
		let scheme = HtmlScheme(file: file, document: document)
		let configuration = WKWebViewConfiguration()
		configuration.setURLSchemeHandler(scheme, forURLScheme: HtmlPage.scheme)
		configuration.websiteDataStore = .nonPersistent()
		configuration.userContentController.add(list)
		let web = WKWebView(
			frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration
		)
		guard let address = HtmlPage.address(of: file) else { return nil }
		web.load(URLRequest(url: address))
		guard await settled(web) else {
			print("HTML: no web view here — the page never finished loading")
			return nil
		}
		return (web, scheme)
	}

	/// Waits for the page to be one this side can ask questions of.
	///
	/// A hang detector rather than a bound, in `Patience`'s terms: a load that
	/// has not happened in this long is a load that is not going to.
	private func settled(_ web: WKWebView) async -> Bool {
		let deadline = Date().addingTimeInterval(Patience.seconds)
		while Date() < deadline {
			if !web.isLoading, let ready = try? await web.evaluateJavaScript(
				"document.readyState"
			) as? String, ready == "complete" {
				return true
			}
			try? await Task.sleep(nanoseconds: 100_000_000)
		}
		return false
	}

	private func asked(_ web: WKWebView, _ script: String) async -> String {
		let answer = try? await web.evaluateJavaScript(script)
		return (answer as? String) ?? String(describing: answer ?? "nil")
	}

	/// The whole reason for the scheme handler: the pane shows what is in the
	/// editor, so an unsaved edit is on screen.
	@Test func theBufferIsWhatRendersRatherThanTheFile() async throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("index.html")
		try "<html><body><p id=p>on disk</p></body></html>"
			.write(to: file, atomically: true, encoding: .utf8)

		guard let page = await page(
			file: file, document: "<html><body><p id=p>unsaved</p></body></html>"
		) else { return }
		#expect(await asked(page.web, "document.getElementById('p').textContent") == "unsaved")
	}

	/// A page looks the way it looks in a browser, which means the files beside
	/// it arrive.
	@Test func aStylesheetBesideTheFileIsApplied() async throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("index.html")
		try "p { color: rgb(1, 2, 3); }"
			.write(to: directory.appendingPathComponent("style.css"),
			       atomically: true, encoding: .utf8)

		guard let page = await page(file: file, document: """
			<html><head><link rel="stylesheet" href="style.css"></head>
			<body><p id=p>styled</p></body></html>
			""") else { return }
		let colour = await asked(
			page.web, "getComputedStyle(document.getElementById('p')).color"
		)
		#expect(colour == "rgb(1, 2, 3)")
		#expect(page.scheme.refused.isEmpty)
	}

	/// A picture in a subdirectory resolves the way it does on disk.
	@Test func aSubdirectoryIsReachedAndAMissingFileIsNot() async throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("index.html")
		try FileManager.default.createDirectory(
			at: directory.appendingPathComponent("css"), withIntermediateDirectories: true
		)
		try "body { margin: 7px; }".write(
			to: directory.appendingPathComponent("css/site.css"), atomically: true, encoding: .utf8
		)

		guard let page = await page(file: file, document: """
			<html><head>
			<link rel="stylesheet" href="css/site.css">
			<link rel="stylesheet" href="css/missing.css">
			</head><body>here</body></html>
			""") else { return }
		#expect(await asked(page.web, "getComputedStyle(document.body).marginTop") == "7px")
		// The one that is not there was refused and recorded, and the page still
		// rendered — a 404 a page expects must not look like a broken load.
		#expect(page.scheme.refused.contains("/css/missing.css"))
	}

	/// No page is a way to read the rest of the disk. The file exists and is
	/// still not served, which is the only version of this test worth having.
	@Test func aReferenceThatClimbsOutOfTheDirectoryIsRefused() async throws {
		let directory = try scratch()
		let above = directory.deletingLastPathComponent()
		defer { try? FileManager.default.removeItem(at: directory) }
		let secret = above.appendingPathComponent("html-live-secret-\(UUID().uuidString).css")
		try "body { margin: 99px; }".write(to: secret, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: secret) }

		let file = directory.appendingPathComponent("index.html")
		guard let page = await page(file: file, document: """
			<html><head>
			<link rel="stylesheet" href="../\(secret.lastPathComponent)">
			</head><body>here</body></html>
			""") else { return }
		#expect(await asked(page.web, "getComputedStyle(document.body).marginTop") != "99px")
		#expect(page.scheme.refused.contains("/\(secret.lastPathComponent)"))
	}

	/// The rule that keeps an absolute `https://` reference from being fetched
	/// at all. It compiles, and the page it is in still renders — a list that
	/// blocked this app's own scheme too would leave every pane blank, which is
	/// the way this goes wrong.
	@Test func theBlockingListCompilesAndStillServesThisAppsOwnScheme() async throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("index.html")
		#expect(await HtmlBlocking.list() != nil)

		guard let page = await page(file: file, document: """
			<html><head>
			<link rel="stylesheet" href="https://cdn.example.invalid/water.css">
			<script src="https://cdn.example.invalid/chart.js"></script>
			</head><body><p id=p>rendered anyway</p></body></html>
			""") else { return }
		#expect(await asked(page.web, "document.getElementById('p').textContent")
			== "rendered anyway")
		// Nothing of the remote pair reached the handler: they are not this app's
		// scheme, so they were never ours to refuse — the rule list dropped them.
		#expect(page.scheme.refused.isEmpty)
		#expect(await asked(page.web, "String(document.styleSheets.length)") == "0")
	}
}

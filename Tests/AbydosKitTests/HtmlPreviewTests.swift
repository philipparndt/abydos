import Foundation
import Testing
@testable import AbydosKit

/// Which files are pages, what a page may reach, and what it asks for that this
/// pane will not fetch.
struct HtmlPreviewTests {
	private func url(_ name: String) -> URL {
		URL(fileURLWithPath: "/project/\(name)")
	}

	private func scratch() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("html-preview-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	// MARK: - The kind

	@Test func theThreePageExtensionsArePages() {
		#expect(FilePreview.kind(for: url("index.html")) == .html)
		#expect(FilePreview.kind(for: url("index.htm")) == .html)
		#expect(FilePreview.kind(for: url("page.xhtml")) == .html)
		#expect(FilePreview.kind(for: url("INDEX.HTML")) == .html)
	}

	/// The HTML grammar colours all of these, and none of them is a document a
	/// browser lays out. A grammar is about syntax; a preview is about what the
	/// file is.
	@Test func whatTheHtmlGrammarColoursIsNotAllAPage() {
		#expect(FilePreview.kind(for: url("App.vue")) == nil)
		#expect(FilePreview.kind(for: url("pom.xml")) == nil)
		#expect(FilePreview.kind(for: url("schema.xsd")) == nil)
		#expect(FilePreview.kind(for: url("report.xsl")) == nil)
		#expect(FilePreview.hasPreview(url("App.vue")) == false)
	}

	/// An `.svg` stays a picture: the picture pane is the right pane for a
	/// drawing, and its text is offered there already.
	@Test func anSvgIsStillAPicture() {
		#expect(FilePreview.kind(for: url("architecture.svg")) == .image)
		#expect(FilePreview.kind(for: url("architecture.drawio.svg")) == .image)
	}

	/// Markdown's answer, for markdown's reason: read as well as rendered, and
	/// a generated report of several megabytes must not render because a tab
	/// was opened on it.
	@Test func aPageOpensAsItsSource() {
		#expect(FilePreview.defaultMode(for: url("index.html")) == .source)
		#expect(FilePreview.defaultMode(for: url("coverage/index.html")) == .source)
	}

	@Test func aPageOffersAllFourModes() {
		#expect(FilePreview.hasPreview(url("index.html")))
		#expect(FilePreview.hasReadableSource(url("index.html")))
		#expect(FilePreview.availableModes(for: url("index.html")) == PreviewMode.allCases)
	}

	/// The tab that was remembered comes back, which is what makes asking for
	/// the preview once enough.
	@Test func aRememberedModeComesBack() {
		#expect(FilePreview.restoredMode(.splitRight, for: url("index.html")) == .splitRight)
		#expect(FilePreview.restoredMode(nil, for: url("index.html")) == .source)
	}

	/// A page is shown in a pane of its own, so Quick Look would be a second
	/// window saying the same thing — and it does not play.
	@Test func aPageIsNeitherAViewerNorAPlayer() {
		#expect(FilePreview.hasDedicatedViewer(url("index.html")) == false)
		#expect(FilePreview.isPlayable(url("index.html")) == false)
		#expect(FilePreview.kind(for: url("index.html"))?.isDiagram == false)
	}

	// MARK: - What the page may reach

	@Test func aNeighbourIsServed() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let found = HtmlPage.file(at: "/style.css", under: directory)
		#expect(found?.lastPathComponent == "style.css")
	}

	@Test func aSubdirectoryIsServed() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let found = HtmlPage.file(at: "/img/logo.png", under: directory)
		#expect(found?.path.hasSuffix("/img/logo.png") == true)
	}

	/// The whole point of the directory being the document's own: a page must
	/// not be a way to read the rest of somebody's disk by writing `../` into an
	/// `img` tag.
	@Test func aReferenceThatClimbsOutIsRefused() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(HtmlPage.file(at: "/../../.ssh/id_rsa", under: directory) == nil)
		#expect(HtmlPage.file(at: "/docs/../../secrets.env", under: directory) == nil)
	}

	/// A link planted in the directory points out of it, and resolving both
	/// sides is what notices.
	@Test func aSymlinkOutOfTheDirectoryIsRefused() throws {
		let directory = try scratch()
		let outside = try scratch()
		defer {
			try? FileManager.default.removeItem(at: directory)
			try? FileManager.default.removeItem(at: outside)
		}
		let secret = outside.appendingPathComponent("secret.txt")
		try "no".write(to: secret, atomically: true, encoding: .utf8)
		try FileManager.default.createSymbolicLink(
			at: directory.appendingPathComponent("escape"), withDestinationURL: outside
		)
		#expect(HtmlPage.file(at: "/escape/secret.txt", under: directory) == nil)
	}

	/// `/tmp` is a symlink to `/private/tmp` on this system, so a directory that
	/// resolved and a file that did not would refuse every neighbour a document
	/// under it has.
	@Test func aDirectoryBehindASymlinkStillServesItsOwn() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let unresolved = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent(directory.lastPathComponent)
		#expect(HtmlPage.file(at: "/style.css", under: unresolved) != nil)
	}

	@Test func theDocumentIsServedAtItsOwnName() {
		let file = url("docs/index.html")
		#expect(HtmlPage.isDocument(path: "/index.html", of: file))
		#expect(HtmlPage.isDocument(path: "/", of: file))
		#expect(HtmlPage.isDocument(path: "/style.css", of: file) == false)
		#expect(HtmlPage.address(of: file)?.absoluteString
			== "\(HtmlPage.scheme)://\(HtmlPage.host)/index.html")
	}

	// MARK: - What points off this machine

	@Test func aPageBuiltOnACdnSaysWhatItWanted() {
		let source = """
			<html><head>
			<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/water.css">
			<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
			<script src="//unpkg.com/htmx.org"></script>
			</head><body><p>Hello</p></body></html>
			"""
		let found = HtmlPage.remoteReferences(in: source)
		#expect(found.count == 3)
		#expect(found.first == "https://cdn.jsdelivr.net/npm/water.css")
		#expect(found.said?.hasPrefix("3 remote references were not loaded") == true)
	}

	/// A tracking pixel is one `img` tag and the reason this pane refuses the
	/// network at all.
	@Test func aTrackingPixelCounts() {
		let found = HtmlPage.remoteReferences(
			in: #"<body><img src="https://example.com/pixel.gif" width="1"></body>"#
		)
		#expect(found.count == 1)
		#expect(found.said == "1 remote reference was not loaded — https://example.com/pixel.gif")
	}

	/// Nearly every page links somewhere. Counting a link as something that
	/// failed to load would put a number on the pane for a page where nothing
	/// was refused at all.
	@Test func aLinkSomebodyCouldClickIsNotAFetch() {
		let source = """
			<p><a href="https://example.com/docs">the documentation</a></p>
			<form action="https://example.com/search"></form>
			"""
		#expect(HtmlPage.remoteReferences(in: source) == .none)
	}

	@Test func whatIsAlreadyHereIsNotRemote() {
		let source = """
			<link rel="stylesheet" href="style.css">
			<img src="img/logo.png">
			<img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
			<script src="/js/app.js"></script>
			"""
		#expect(HtmlPage.remoteReferences(in: source) == .none)
	}

	/// A CDN tag somebody commented out is the likeliest thing in a page to be
	/// sitting behind `<!--`, and a pane that named it would be describing a
	/// document that does not ask for it.
	@Test func aCommentedOutReferenceIsNotCounted() {
		let source = """
			<!-- <script src="https://cdn.example.com/old.js"></script> -->
			<script src="app.js"></script>
			"""
		#expect(HtmlPage.remoteReferences(in: source) == .none)
	}

	/// The address is named in the file's own hand: a host is case-insensitive
	/// and everything after it is not.
	@Test func theAddressIsNamedAsTheFileWroteIt() {
		let found = HtmlPage.remoteReferences(in: #"<img SRC="https://example.com/Logo.PNG">"#)
		#expect(found.first == "https://example.com/Logo.PNG")
	}

	/// `data-src` is a different attribute, and `xlink:href` is the one an SVG
	/// `use` writes. Neither is `src` or `href`.
	@Test func anAttributeIsNotTheTailOfALongerOne() {
		let found = HtmlPage.remoteReferences(
			in: #"<img data-src="https://example.com/lazy.png" src="local.png">"#
		)
		#expect(found == .none)
	}

	@Test func nothingToSayWhenNothingWasRefused() {
		#expect(HtmlPage.RemoteReferences.none.said == nil)
		#expect(HtmlPage.remoteReferences(in: "<p>plain</p>") == .none)
	}

	// MARK: - What a file is served as

	/// A page loads fonts and modules that came along after draw.io's list was
	/// written, and a type served as bytes is a stylesheet a browser ignores.
	@Test func whatAPageLoadsIsNamed() {
		#expect(HtmlPage.mediaType(for: "css") == "text/css")
		#expect(HtmlPage.mediaType(for: "mjs") == "application/javascript")
		#expect(HtmlPage.mediaType(for: "woff2") == "font/woff2")
		#expect(HtmlPage.mediaType(for: "webp") == "image/webp")
		#expect(HtmlPage.mediaType(for: "HTML") == "text/html")
		#expect(HtmlPage.mediaType(for: "sqlite") == "application/octet-stream")
	}
}

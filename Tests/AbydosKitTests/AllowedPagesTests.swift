import Foundation
import Testing
@testable import AbydosKit

/// Which pages may reach the network, where that is kept, and what forgets it.
@MainActor
struct AllowedPagesTests {
	private func scratch() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("allowed-pages-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	/// A store of its own, never the shared one: a suite that wrote into
	/// somebody's real list would be a suite that grants permissions.
	private func store(in directory: URL, driven: Bool = false) -> AllowedPages {
		AllowedPages(storeURL: directory.appendingPathComponent("allowed.json"), driven: driven)
	}

	@Test func aPageIsRefusedUntilItIsAllowed() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let page = directory.appendingPathComponent("index.html")
		let pages = store(in: directory)

		#expect(pages.isAllowed(page) == false)
		pages.allow(page)
		#expect(pages.isAllowed(page))
	}

	/// The whole point of keeping it: a page somebody reads often stays as they
	/// left it.
	@Test func anAllowSurvivesTheApplication() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let page = directory.appendingPathComponent("index.html")
		store(in: directory).allow(page)

		#expect(store(in: directory).isAllowed(page))
	}

	@Test func forgettingTakesItBack() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let page = directory.appendingPathComponent("index.html")
		let pages = store(in: directory)
		pages.allow(page)

		pages.forget(page)
		#expect(pages.isAllowed(page) == false)
		#expect(store(in: directory).isAllowed(page) == false)
	}

	/// One file, not a directory and not its neighbours.
	@Test func anAllowIsAboutOneDocument() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let pages = store(in: directory)
		pages.allow(directory.appendingPathComponent("index.html"))

		#expect(pages.isAllowed(directory.appendingPathComponent("guide.html")) == false)
		#expect(pages.isAllowed(directory) == false)
	}

	/// The safe direction to fail in, and the reason a path is an acceptable
	/// key: a file that moves is asked about again.
	@Test func aFileThatMovesLosesIt() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let pages = store(in: directory)
		pages.allow(directory.appendingPathComponent("index.html"))

		#expect(pages.isAllowed(directory.appendingPathComponent("docs/index.html")) == false)
	}

	/// `/tmp` is a symlink to `/private/tmp` here, so an allow granted under one
	/// spelling has to be read under the other.
	///
	/// **The file has to exist for that to be true.** `resolvingSymlinksInPath`
	/// stats the path, so for a name that is not there the two spellings stay
	/// two strings — measured, after this test was first written against a file
	/// it never created. It costs nothing in the pane, which only ever asks
	/// about a document it is showing.
	@Test func theSpellingOfThePathDoesNotDecideIt() throws {
		let name = "allowed-\(UUID().uuidString).html"
		let resolved = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(name)
		let unresolved = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
		try "<html></html>".write(to: resolved, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: resolved) }
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }

		let pages = store(in: directory)
		pages.allow(unresolved)
		#expect(pages.isAllowed(resolved))
	}

	/// A capture must not reach anybody's server, and must not leave a decision
	/// behind that no person made.
	@Test func aDrivenRunNeitherFetchesNorRemembers() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let page = directory.appendingPathComponent("index.html")

		let driven = store(in: directory, driven: true)
		driven.allow(page)
		#expect(driven.isAllowed(page) == false)
		#expect(driven.isHeldBackByDrivenRun)
		// Pressed, and said so in the line — the button is not dead, it is the
		// fetching that a capture does not do.
		#expect(driven.isRemembered(page))
		// Nothing was written, so a real run afterwards knows nothing about it.
		#expect(store(in: directory).isAllowed(page) == false)
	}

	/// A page allowed by somebody at a screen is still not fetched by a capture,
	/// and the capture can still say that it was allowed.
	@Test func aDrivenRunIgnoresWhatWasRemembered() throws {
		let directory = try scratch()
		defer { try? FileManager.default.removeItem(at: directory) }
		let page = directory.appendingPathComponent("index.html")
		store(in: directory).allow(page)

		let driven = store(in: directory, driven: true)
		#expect(driven.isAllowed(page) == false)
		#expect(driven.isRemembered(page))
	}
}

/// The line at the foot of the pane, in each of the states it has.
struct HtmlPaneLineTests {
	private func references(_ count: Int) -> HtmlPage.RemoteReferences {
		HtmlPage.RemoteReferences(count: count, first: count > 0 ? "https://example.com/a.css" : nil)
	}

	@Test func aRefusedPageSaysWhatAndOffersToLoadIt() {
		let line = HtmlPage.line(references: references(1), allowed: false, driven: false)
		#expect(line.said == "1 remote reference was not loaded — https://example.com/a.css")
		#expect(line.offer == .load)
		#expect(line.offer?.title == "Load")
	}

	/// A page that asks for nothing remote has nothing to say and nothing to
	/// offer — a button on it would be an offer to do nothing.
	@Test func aPageThatAsksForNothingSaysNothing() {
		let line = HtmlPage.line(references: .none, allowed: false, driven: false)
		#expect(line.said == nil)
		#expect(line.offer == nil)
	}

	@Test func anAllowedPageSaysSoAndOffersToBlockItAgain() {
		let line = HtmlPage.line(references: references(3), allowed: true, driven: false)
		#expect(line.said == "This page is being fetched from the network.")
		#expect(line.offer == .block)
		#expect(line.offer?.title == "Block")
	}

	/// Said rather than hidden: a pane that quietly refused a page somebody had
	/// allowed would be a pane whose screenshot argues against the feature.
	@Test func aDrivenRunSaysWhyAnAllowedPageIsStillEmpty() {
		let line = HtmlPage.line(references: references(3), allowed: true, driven: true)
		#expect(line.said == "This page is allowed the network — a driven run fetches nothing.")
		#expect(line.offer == .block)
	}
}

import AppKit
import Foundation
import PDFKit
import Testing
@testable import AbydosKit

/// PDFs in the editor.
///
/// A repository keeps the paper beside the code, and clicking the paper used to
/// say "This looks like a binary file" and offer a hex dump.
struct PdfPreviewTests {
	// MARK: - Which files are PDFs

	@Test func knowsAPdfWhenItSeesOne() {
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/spec.pdf")) == .pdf)
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/DATASHEET.PDF")) == .pdf)
		// Not everything with paper in the name.
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/spec.pdf.md")) == .markdown)
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/spec.ps")) == nil)
	}

	/// A PDF opens as the document, and offers nothing else: there is no source
	/// half, so the mode control has one entry.
	@Test func opensRenderedAndOffersNothingElse() {
		let url = URL(fileURLWithPath: "/tmp/spec.pdf")
		#expect(FilePreview.defaultMode(for: url) == .preview)
		#expect(!FilePreview.hasReadableSource(url))
		#expect(FilePreview.availableModes(for: url) == [.preview])
		#expect(FilePreview.hasPreview(url))
	}

	/// It is not a diagram, so it gets no Export beside it — there is nothing to
	/// export a PDF *to* that it is not already.
	@Test func isNotADiagram() {
		#expect(FilePreview.Kind.pdf.isDiagram == false)
	}

	// MARK: - How large a page is drawn

	/// Wider than the pane: shrunk to fit it. Narrower: left at its own size,
	/// which for a PDF is what 100% means.
	@Test func fitsTheWidthAndNeverBlowsAPageUp() {
		// US Letter, 612 points wide.
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 306, zoom: 1) == 0.5)
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 1200, zoom: 1) == 1)
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 612, zoom: 1) == 1)
	}

	/// ⌘+ enlarges the document, and past the width of the pane — which is the
	/// one place this parts company with the picture pane, because a PDF scrolls
	/// and a picture does not.
	@Test func followsTheWindowsZoom() {
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 1200, zoom: 1.5) == 1.5)
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 612, zoom: 2) == 2)
		// Already shrunk to fit, then zoomed: half of the page's own size, twice
		// over, is the page's own size again.
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 306, zoom: 2) == 1)
	}

	/// Bounded at both ends: below a tenth the page is a dot, and above eight the
	/// renderer is being asked for a bitmap it should not be.
	@Test func staysWithinReason() {
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 612, zoom: 100) == 8)
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 612, zoom: 0) == 0.1)
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 612, zoom: -3) == 0.1)
	}

	@Test func survivesAPaneWithNoRoomInIt() {
		#expect(PdfPreview.scale(pageWidth: 0, paneWidth: 500, zoom: 1) == 1)
		#expect(PdfPreview.scale(pageWidth: 612, paneWidth: 0, zoom: 1) == 1)
	}

	// MARK: - What is fitted to

	/// The widest page, not the first one. A scanned appendix or a wide table is
	/// landscape in an otherwise portrait document, and fitting to page one puts
	/// it halfway off the side.
	@Test func fitsToTheWidestPageThereIs() throws {
		let document = PDFDocument()
		document.insert(page(width: 612, height: 792), at: 0)
		document.insert(page(width: 1008, height: 612), at: 1)
		document.insert(page(width: 612, height: 792), at: 2)
		#expect(PdfPreview.widestPage(in: document) == 1008)

		// Only the first few are measured: a thousand-page document should not be
		// walked to lay out its first screen.
		#expect(PdfPreview.widestPage(in: document, sampling: 1) == 612)
	}

	// MARK: - What it says underneath

	@Test func saysHowManyPagesAndHowLarge() {
		#expect(PdfPreview.caption(pages: 1, scale: 1) == "1 page")
		#expect(PdfPreview.caption(pages: 12, scale: 1) == "12 pages")
		#expect(PdfPreview.caption(pages: 12, scale: 1.5) == "12 pages · 150%")
	}

	// MARK: - Files that are not documents

	/// `PDFDocument(url:)` answers nil for all of these, and an empty grey pane
	/// is not an answer to any of them.
	@Test func saysWhyAFileWillNotOpen() throws {
		let folder = try scratch()
		defer { try? FileManager.default.removeItem(at: folder) }

		let missing = folder.appendingPathComponent("gone.pdf")
		#expect(trouble(PdfPreview.open(missing))?.contains("no file") == true)

		let empty = folder.appendingPathComponent("empty.pdf")
		try Data().write(to: empty)
		#expect(trouble(PdfPreview.open(empty))?.contains("empty") == true)

		// A JPEG that somebody renamed, or a truncated download.
		let damaged = folder.appendingPathComponent("damaged.pdf")
		try Data(repeating: 0x7F, count: 4000).write(to: damaged)
		let said = try #require(trouble(PdfPreview.open(damaged)))
		#expect(said.contains("could not be read as a PDF"))
		#expect(said.contains("damaged"))
	}

	/// A real one opens, and is handed back with its pages on it.
	@Test func opensARealDocument() throws {
		let folder = try scratch()
		defer { try? FileManager.default.removeItem(at: folder) }

		let url = folder.appendingPathComponent("real.pdf")
		let written = PDFDocument()
		for index in 0 ..< 3 { written.insert(page(width: 612, height: 792), at: index) }
		#expect(written.write(to: url))

		guard case .document(let opened) = PdfPreview.open(url) else {
			Issue.record("a document written by PDFKit did not open")
			return
		}
		#expect(opened.pageCount == 3)
	}

	/// A password on it opens and then refuses every page, which shows as a pane
	/// full of nothing. Said rather than shown.
	@Test func saysWhenADocumentIsLocked() throws {
		let folder = try scratch()
		defer { try? FileManager.default.removeItem(at: folder) }

		let url = folder.appendingPathComponent("locked.pdf")
		let written = PDFDocument()
		written.insert(page(width: 612, height: 792), at: 0)
		#expect(written.write(to: url, withOptions: [
			.userPasswordOption: "secret", .ownerPasswordOption: "secret",
		]))

		let said = try #require(trouble(PdfPreview.open(url)))
		#expect(said.contains("locked"))
	}

	// MARK: - Helpers

	private func trouble(_ opened: PdfPreview.Opened) -> String? {
		guard case .trouble(let said) = opened else { return nil }
		return said
	}

	/// A blank page of a given size, which is all these tests need one to be.
	private func page(width: CGFloat, height: CGFloat) -> PDFPage {
		let image = NSImage(size: NSSize(width: width, height: height))
		image.lockFocus()
		NSColor.white.setFill()
		NSRect(x: 0, y: 0, width: width, height: height).fill()
		image.unlockFocus()
		return PDFPage(image: image) ?? PDFPage()
	}

	private func scratch() throws -> URL {
		let folder = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-pdf-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}
}

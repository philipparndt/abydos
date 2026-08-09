import Foundation
import PDFKit

/// Reading a PDF, and how large to draw it.
///
/// Kept out of the view so both halves can be checked without a window: what
/// happens to a file that is not a PDF, and what ⌘+ does to a page.
public enum PdfPreview {
	/// What came of opening a file.
	public enum Opened {
		case document(PDFDocument)
		/// One sentence saying why there is nothing to show.
		case trouble(String)
	}

	/// Opens a PDF, or says in one sentence why it will not open.
	///
	/// `PDFDocument(url:)` answers nil for everything — a JPEG named `.pdf`, a
	/// truncated download, a file that is not there — and an empty grey pane is
	/// not an answer to any of them. So the cases are told apart here and each
	/// gets a sentence somebody can act on, the way `ContainerImages.explain`
	/// does for a pull that failed.
	///
	/// Slow: it parses the file. Call it off the main thread.
	public static func open(_ url: URL) -> Opened {
		guard FileManager.default.fileExists(atPath: url.path) else {
			return .trouble("There is no file at \(url.path) any more.")
		}
		let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		if bytes == 0 {
			return .trouble("This file is empty, so there is no document in it.")
		}

		guard let document = PDFDocument(url: url) else {
			return .trouble(
				"This file could not be read as a PDF. It is either damaged or "
					+ "named .pdf without being one."
			)
		}
		// A locked document opens and then refuses every page, which shows as a
		// pane full of nothing. Said rather than shown.
		if document.isLocked {
			return .trouble(
				"This PDF is locked with a password, so none of it can be shown here."
			)
		}
		if document.pageCount == 0 {
			return .trouble("This PDF has no pages in it.")
		}
		return .document(document)
	}

	/// How large a page is drawn, as `PDFView.scaleFactor`.
	///
	/// The same promise the picture pane makes in `ImageFit`: a page wider than
	/// the pane shrinks to fit it, and one that already fits is left at its own
	/// size rather than blown up — a PDF states its own page size in points and
	/// 100% is what that size means. On top of that goes the app's own zoom, so
	/// ⌘+ enlarges a document exactly as it enlarges everything else in the
	/// window and ⌘0 puts it back.
	///
	/// The one place this parts company with `ImageFit.fitScale(image:in:zoom:)`
	/// is the ceiling. That one caps the zoom at what the pane can hold, because
	/// a picture that outgrows its pane is a picture with its edges cut off. A
	/// PDF scrolls — that is the whole of what `PDFView` is — so capping it there
	/// would make ⌘+ stop having any effect the moment the page filled the width,
	/// which is precisely when somebody presses it.
	///
	/// The arithmetic itself now lives in `ImageFit.widthScale`, because the
	/// diagram pane learned to scroll and wanted exactly this rule. A page and a
	/// drawing are not the same thing, so the name stays here; the numbers are
	/// shared, so ⌘+ cannot come to mean two different things in one window.
	public static func scale(pageWidth: CGFloat, paneWidth: CGFloat, zoom: CGFloat) -> CGFloat {
		ImageFit.widthScale(width: pageWidth, paneWidth: paneWidth, zoom: zoom)
	}

	/// The width to fit to: the widest page there is.
	///
	/// Fitting to the first page alone puts a landscape page halfway off the
	/// side of a portrait document — which is what a scanned appendix or a wide
	/// table usually is. Only the first few are measured, because the answer
	/// almost never changes after them and a thousand-page document should not
	/// be walked to lay out its first screen.
	public static func widestPage(in document: PDFDocument, sampling limit: Int = 16) -> CGFloat {
		var widest: CGFloat = 0
		for index in 0 ..< min(document.pageCount, max(limit, 1)) {
			guard let page = document.page(at: index) else { continue }
			widest = max(widest, page.bounds(for: .cropBox).width)
		}
		return widest
	}

	/// What to say a document is, under the pages.
	public static func caption(pages: Int, scale: CGFloat) -> String {
		let count = "\(pages) page\(pages == 1 ? "" : "s")"
		guard scale > 0, abs(scale - 1) > 0.005 else { return count }
		return "\(count) · \(Int((scale * 100).rounded()))%"
	}
}

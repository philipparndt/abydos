import Foundation
import Testing
@testable import AbydosKit

/// Pictures in the editor.
///
/// Clicking a screenshot in a documentation folder used to say "This looks like
/// a binary file" and offer a hex dump, which is an answer to a question nobody
/// asked.
struct ImagePreviewTests {
	@Test func knowsAPictureWhenItSeesOne() {
		for name in ["diagram.png", "shot.JPG", "icon.heic", "loop.gif", "photo.tiff", "logo.webp"] {
			#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/\(name)")) == .image)
		}
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/notes.md")) == .markdown)
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/part.stl")) == .model)
		#expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/main.swift")) == nil)
	}

	/// A picture opens as the picture.
	@Test func opensRendered() {
		#expect(FilePreview.defaultMode(for: URL(fileURLWithPath: "/tmp/diagram.png")) == .preview)
		#expect(FilePreview.defaultMode(for: URL(fileURLWithPath: "/tmp/notes.md")) == .source)
	}

	/// An SVG is a drawing written down: it shows the drawing, and the text is
	/// still there to read. A PNG has no text, so it is offered none.
	@Test func offersSourceOnlyWhereThereIsSome() {
		let svg = URL(fileURLWithPath: "/tmp/flow.svg")
		#expect(FilePreview.hasReadableSource(svg))
		#expect(FilePreview.availableModes(for: svg) == PreviewMode.allCases)

		let png = URL(fileURLWithPath: "/tmp/flow.png")
		#expect(!FilePreview.hasReadableSource(png))
		#expect(FilePreview.availableModes(for: png) == [.preview])
	}

	/// Bigger than the pane: shrunk to fit, proportions kept.
	@Test func shrinksWhatDoesNotFit() {
		let scale = ImageFit.fitScale(image: CGSize(width: 2000, height: 1000), in: CGSize(width: 500, height: 500))
		#expect(scale == 0.25)

		let box = ImageFit.rect(image: CGSize(width: 2000, height: 1000), in: CGSize(width: 500, height: 500))
		#expect(box.width == 500)
		#expect(box.height == 250)
		// Centred in what is left over.
		#expect(box.origin.y == 125)
		#expect(box.origin.x == 0)
	}

	/// Smaller than the pane: left alone. A sixteen-pixel icon blown up to fill
	/// a window is a blurry lie about what is in the file.
	@Test func neverBlowsAPictureUp() {
		let box = ImageFit.rect(image: CGSize(width: 16, height: 16), in: CGSize(width: 800, height: 600))
		#expect(box.size == CGSize(width: 16, height: 16))
		#expect(ImageFit.fitScale(image: CGSize(width: 16, height: 16), in: CGSize(width: 800, height: 600)) == 1)
	}

	/// Asked for a particular factor — somebody wanting to see it at its own
	/// size — that is what it is drawn at, fit or no fit.
	@Test func honoursAChosenScale() {
		let box = ImageFit.rect(
			image: CGSize(width: 2000, height: 1000), in: CGSize(width: 500, height: 500), scale: 1
		)
		#expect(box.size == CGSize(width: 2000, height: 1000))
	}

	/// A picture follows the window's zoom, past the pane and without a ceiling.
	///
	/// At 1× the answer is the fit exactly, so a window nobody has zoomed looks
	/// the way it always did. Above 1× it is what item 0532 asked for: the rule
	/// this replaced took `min(zoom, room)` and so stopped having any effect the
	/// moment the picture filled the pane, which is precisely when somebody
	/// presses ⌘+.
	@Test func followsTheZoomPastThePane() {
		let small = CGSize(width: 200, height: 100)
		let pane = CGSize(width: 800, height: 600)
		#expect(ImageFit.paneScale(image: small, in: pane, zoom: 1) == 1)
		#expect(ImageFit.paneScale(image: small, in: pane, zoom: 2) == 2)
		// Four times over is exactly the width of the pane, and going past it is
		// the whole point — there is somewhere to scroll now.
		#expect(ImageFit.paneScale(image: small, in: pane, zoom: 4) == 4)
		#expect(ImageFit.paneScale(image: small, in: pane, zoom: 8) == 8)

		// Larger than the pane already: fitted at 1×, and the zoom multiplies that
		// fit rather than being stopped by it.
		let large = CGSize(width: 2000, height: 1000)
		#expect(ImageFit.paneScale(image: large, in: CGSize(width: 500, height: 500), zoom: 1) == 0.25)
		#expect(ImageFit.paneScale(image: large, in: CGSize(width: 500, height: 500), zoom: 3) == 0.75)

		// The height counts as well as the width, which is the one thing a picture
		// wants differently from a PDF and a diagram: a picture is looked at whole.
		#expect(ImageFit.paneScale(image: CGSize(width: 100, height: 1000), in: pane, zoom: 1) == 0.6)

		// Only the bounds that stop the arithmetic being silly.
		#expect(ImageFit.paneScale(image: small, in: pane, zoom: 100) == 8)
		#expect(ImageFit.paneScale(image: small, in: pane, zoom: -3) == 0.1)

		#expect(ImageFit.paneScale(image: .zero, in: pane, zoom: 2) == 1)
		#expect(ImageFit.paneScale(image: small, in: .zero, zoom: 2) == 1)
	}

	/// A pane that scrolls fits the *width* and has no ceiling but the silly one.
	///
	/// The rule above consults the height as well, because a picture is looked at
	/// whole; a PDF and a diagram are read downwards, so fitting their height is
	/// how a page ends up a stamp in the middle of a window. Both are the same
	/// arithmetic after the basis — see `theThreePanesAgreeAboutTheZoom`.
	@Test func fitsTheWidthWhereThereIsSomewhereToScroll() {
		// Twice as wide as the pane: half size, and the height is not consulted.
		#expect(ImageFit.widthScale(width: 1000, paneWidth: 500, zoom: 1) == 0.5)
		// Narrower than the pane: left at its own size rather than blown up.
		#expect(ImageFit.widthScale(width: 400, paneWidth: 1000, zoom: 1) == 1)

		// The zoom multiplies it, and going past the pane is the point.
		#expect(ImageFit.widthScale(width: 1000, paneWidth: 500, zoom: 2) == 1)
		#expect(ImageFit.widthScale(width: 400, paneWidth: 1000, zoom: 2) == 2)

		// Only the bounds that stop the arithmetic being silly.
		#expect(ImageFit.widthScale(width: 400, paneWidth: 1000, zoom: 100) == 8)
		#expect(ImageFit.widthScale(width: 400, paneWidth: 1000, zoom: 0) == 0.1)
		#expect(ImageFit.widthScale(width: 400, paneWidth: 1000, zoom: -3) == 0.1)

		// Nothing to fit yet — a pane with no picture in it, or none laid out.
		#expect(ImageFit.widthScale(width: 0, paneWidth: 1000, zoom: 1) == 1)
		#expect(ImageFit.widthScale(width: 400, paneWidth: 0, zoom: 1) == 1)
	}

	/// The drawing's own size follows the zoom too, so ⌘+ from 100% is 110%
	/// rather than nothing.
	@Test func clampsAScaleArrivedAtAnotherWay() {
		#expect(ImageFit.clamp(1) == 1)
		#expect(ImageFit.clamp(1.1) == 1.1)
		#expect(ImageFit.clamp(0) == 0.1)
		#expect(ImageFit.clamp(40) == 8)
	}

	/// One rule, two callers. A second copy of it is how ⌘+ comes to mean two
	/// things in one window.
	@Test func thePdfPaneAsksTheSameQuestion() {
		for (width, pane, zoom) in [(612.0, 306.0, 1.0), (612, 1200, 1.5), (612, 612, 100), (0, 500, 1)] {
			#expect(
				PdfPreview.scale(pageWidth: width, paneWidth: pane, zoom: zoom)
					== ImageFit.widthScale(width: width, paneWidth: pane, zoom: zoom)
			)
		}
	}

	/// One rule after the basis, three callers. A picture, a page and a drawing
	/// disagree about what to fit to and must not disagree about what ⌘+ does.
	@Test func theThreePanesAgreeAboutTheZoom() {
		for zoom in [0.5, 1.0, 1.1, 2.0, 4.0, 40.0, -1.0] {
			// A picture already at its fit, a page already at its fit: the same
			// zoom on the same basis is the same number, and both are bounded the
			// same way.
			#expect(
				ImageFit.paneScale(image: CGSize(width: 500, height: 500),
				                   in: CGSize(width: 500, height: 500), zoom: zoom)
					== ImageFit.widthScale(width: 500, paneWidth: 500, zoom: zoom)
			)
			#expect(ImageFit.zoomed(1, by: zoom) == ImageFit.clamp(max(zoom, 0)))
		}
	}

	/// The document a scrolling pane scrolls is as large as the picture in it.
	///
	/// This is the whole of item 0532: the picture pane resized its document to
	/// the *content* size on every frame change, so a screenshot at its own size
	/// was cropped by a document that could never be larger than the hole it was
	/// seen through.
	@Test func theDocumentIsAsLargeAsThePicture() {
		let visible = CGSize(width: 500, height: 400)

		// Larger than the pane in both directions: the document is the picture and
		// its margins, so both scrollers have somewhere to go.
		#expect(
			ImageFit.documentSize(picture: CGSize(width: 2560, height: 1600),
			                      visible: visible, margin: 16)
				== CGSize(width: 2592, height: 1632)
		)

		// Larger in one direction only: pannable in exactly that one.
		#expect(
			ImageFit.documentSize(picture: CGSize(width: 2000, height: 100),
			                      visible: visible, margin: 16)
				== CGSize(width: 2032, height: 400)
		)

		// Smaller than the pane: the document is the pane, and the picture is
		// centred in it with nothing to scroll.
		#expect(
			ImageFit.documentSize(picture: CGSize(width: 16, height: 16),
			                      visible: visible, margin: 16)
				== visible
		)

		// And where the picture goes in it, which is what `rect` already answered.
		let document = ImageFit.documentSize(
			picture: CGSize(width: 2560, height: 1600), visible: visible, margin: 16
		)
		let box = ImageFit.rect(image: CGSize(width: 2560, height: 1600), in: document, scale: 1)
		#expect(box == CGRect(x: 16, y: 16, width: 2560, height: 1600))
	}

	/// The caption says what the file holds, how large it is being drawn, and
	/// which of the two ways it arrived at that size.
	@Test func saysWhatItIsShowing() {
		#expect(ImageFit.caption(image: CGSize(width: 1000, height: 560), scale: 1) == "1000 × 560")
		#expect(ImageFit.caption(image: CGSize(width: 1000, height: 560), scale: 0.25) == "1000 × 560 · 25%")

		// Fitted says so, and says so at 100% as well: fitted and 100% is the same
		// number as chosen and 100%, and only one of the two stays 100% when the
		// window is made narrower.
		#expect(
			ImageFit.caption(image: CGSize(width: 1000, height: 560), scale: 0.25, fitted: true)
				== "1000 × 560 · Fit · 25%"
		)
		#expect(
			ImageFit.caption(image: CGSize(width: 16, height: 16), scale: 1, fitted: true)
				== "16 × 16 · Fit · 100%"
		)
	}

	/// Nothing to draw is not a crash.
	@Test func survivesAnEmptyPane() {
		#expect(ImageFit.rect(image: .zero, in: CGSize(width: 100, height: 100)) == .zero)
		#expect(ImageFit.rect(image: CGSize(width: 10, height: 10), in: .zero) == .zero)
	}
}

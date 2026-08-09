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

	/// A drawing follows the window's zoom, as far as the pane allows.
	///
	/// At 1× the answer is the old one exactly, so a window nobody has zoomed
	/// looks the way it always did.
	@Test func followsTheZoomWhileThereIsRoom() {
		let small = CGSize(width: 200, height: 100)
		let pane = CGSize(width: 800, height: 600)
		#expect(ImageFit.fitScale(image: small, in: pane, zoom: 1) == 1)
		#expect(ImageFit.fitScale(image: small, in: pane, zoom: 2) == 2)
		// Four times over is exactly the width of the pane; past that it is as
		// large as the pane can hold and no larger.
		#expect(ImageFit.fitScale(image: small, in: pane, zoom: 4) == 4)
		#expect(ImageFit.fitScale(image: small, in: pane, zoom: 8) == 4)

		// Larger than the pane already: zooming cannot make it larger than the
		// room there is, which is what the un-zoomed rule said too.
		let large = CGSize(width: 2000, height: 1000)
		#expect(ImageFit.fitScale(image: large, in: CGSize(width: 500, height: 500), zoom: 1) == 0.25)
		#expect(ImageFit.fitScale(image: large, in: CGSize(width: 500, height: 500), zoom: 3) == 0.25)

		#expect(ImageFit.fitScale(image: .zero, in: pane, zoom: 2) == 1)
	}

	/// A pane that scrolls fits the *width* and has no ceiling but the silly one.
	///
	/// The rule above caps at what the pane can hold, which is right where the
	/// picture cannot be scrolled and exactly wrong where it can: ⌘+ would stop
	/// doing anything the moment the drawing filled the pane. The diagram pane and
	/// the PDF pane both scroll and both ask this.
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

	/// The caption says what the file holds, and how much of it is showing when
	/// that is not all of it.
	@Test func saysWhatItIsShowing() {
		#expect(ImageFit.caption(image: CGSize(width: 1000, height: 560), scale: 1) == "1000 × 560")
		#expect(ImageFit.caption(image: CGSize(width: 1000, height: 560), scale: 0.25) == "1000 × 560 · 25%")
	}

	/// Nothing to draw is not a crash.
	@Test func survivesAnEmptyPane() {
		#expect(ImageFit.rect(image: .zero, in: CGSize(width: 100, height: 100)) == .zero)
		#expect(ImageFit.rect(image: CGSize(width: 10, height: 10), in: .zero) == .zero)
	}
}

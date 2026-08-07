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

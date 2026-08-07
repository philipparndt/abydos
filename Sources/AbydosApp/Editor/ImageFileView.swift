import AbydosKit
import AppKit

/// A picture, shown in a tab.
///
/// Documentation lives next to the diagrams and screenshots it talks about, and
/// clicking one used to say "This looks like a binary file" and offer a hex
/// dump. It is shown fitted to the pane and never blown up past its own size,
/// on a checkerboard so a transparent background reads as transparent rather
/// than as whatever colour happens to be behind it — which is exactly the
/// question anybody opening an icon has.
final class ImageFileView: NSView {
	private let url: URL
	private var image: NSImage?
	/// The size in pixels, which is what the file is: `NSImage.size` is in
	/// points, so a picture from a Retina screenshot claims to be half of what
	/// it holds.
	private var pixelSize: CGSize = .zero
	/// Nil while fitted, and a fixed factor once somebody has asked for one.
	private var chosenScale: CGFloat?

	private let caption = NSTextField(labelWithString: "")

	init(url: URL) {
		self.url = url
		super.init(frame: .zero)
		load()

		caption.font = Theme.current.uiFont(11)
		caption.textColor = Theme.current.sidebarText.withAlphaComponent(0.75)
		caption.stringValue = ImageFit.caption(image: pixelSize, scale: shownScale(in: bounds.size))
		caption.translatesAutoresizingMaskIntoConstraints = false
		addSubview(caption)
		NSLayoutConstraint.activate([
			caption.centerXAnchor.constraint(equalTo: centerXAnchor),
			caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func load() {
		guard let loaded = NSImage(contentsOf: url) else { return }
		image = loaded

		// A bitmap knows how many pixels it has; anything drawn from
		// instructions — an SVG — has no pixel count of its own, so its size in
		// points is the honest answer.
		if let bitmap = loaded.representations.first(where: { $0.pixelsWide > 0 }) {
			pixelSize = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
		} else {
			pixelSize = loaded.size
		}
	}

	/// The factor the picture is being drawn at.
	private func shownScale(in pane: CGSize) -> CGFloat {
		chosenScale ?? ImageFit.fitScale(image: pixelSize, in: inset(pane))
	}

	/// The area the picture may use, leaving room for the caption under it.
	private func inset(_ pane: CGSize) -> CGSize {
		CGSize(width: max(0, pane.width - 32), height: max(0, pane.height - 48))
	}

	/// Double-click swaps between fitting the pane and the picture's own size,
	/// which is the question a scaled-down screenshot always raises.
	override func mouseDown(with event: NSEvent) {
		guard event.clickCount == 2 else { return super.mouseDown(with: event) }
		chosenScale = chosenScale == nil ? 1 : nil
		needsDisplay = true
		updateCaption()
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		updateCaption()
		needsDisplay = true
	}

	private func updateCaption() {
		caption.stringValue = ImageFit.caption(image: pixelSize, scale: shownScale(in: bounds.size))
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		guard let image else {
			let message = NSAttributedString(string: "This picture cannot be read.", attributes: [
				.font: Theme.current.uiFont(12),
				.foregroundColor: Theme.current.sidebarText,
			])
			let size = message.size()
			message.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.midY))
			return
		}

		var box = ImageFit.rect(image: pixelSize, in: inset(bounds.size), scale: chosenScale ?? 0)
		box.origin.x += 16
		box.origin.y += 24
		guard box.width > 0, box.height > 0 else { return }

		drawCheckerboard(in: box)
		image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
	}

	/// The grey squares under the picture, so a transparent background is
	/// visibly transparent rather than looking like part of the picture.
	private func drawCheckerboard(in box: NSRect) {
		let square: CGFloat = 8
		let dark = Theme.current.editorBackground.blended(withFraction: 0.06, of: .white)
			?? Theme.current.editorBackground
		let light = Theme.current.editorBackground.blended(withFraction: 0.12, of: .white)
			?? Theme.current.editorBackground

		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: box).addClip()
		dark.setFill()
		box.fill()
		light.setFill()
		var row = 0
		var y = box.minY
		while y < box.maxY {
			var x = box.minX + (row.isMultiple(of: 2) ? 0 : square)
			while x < box.maxX {
				NSRect(x: x, y: y, width: square, height: square).fill()
				x += square * 2
			}
			y += square
			row += 1
		}
		NSGraphicsContext.restoreGraphicsState()
	}
}

/// The scrolling container a tab installs.
///
/// The picture goes in a scroll view like every other kind of tab's content,
/// which is also what makes a picture shown at its own size pannable rather
/// than cropped.
final class ImageFileViewer {
	let scrollView: NSScrollView
	private let imageView: ImageFileView

	init(url: URL) {
		imageView = ImageFileView(url: url)

		scrollView = NSScrollView()
		scrollView.documentView = imageView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay

		// The picture fits the pane it is given, so the document is the pane
		// until somebody asks for the picture's own size.
		scrollView.contentView.postsFrameChangedNotifications = true
		NotificationCenter.default.addObserver(
			forName: NSView.frameDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak scrollView, weak imageView] _ in
			MainActor.assumeIsolated {
				guard let scrollView, let imageView else { return }
				imageView.setFrameSize(scrollView.contentSize)
			}
		}
	}
}

import AppKit
import Metal
import QuartzCore

/// The layer the terminal grid is drawn into.
///
/// Sized to what is on screen rather than to the whole document. The terminal's
/// view spans all of its history — thousands of lines — and no drawable is that
/// large, so this rides along on top of the visible part and is told where that
/// is as the view scrolls.
final class TerminalMetalView: NSView {
	private let metalLayer = CAMetalLayer()

	init(device: MTLDevice) {
		super.init(frame: .zero)
		wantsLayer = true
		layer = metalLayer

		metalLayer.device = device
		metalLayer.pixelFormat = .bgra8Unorm
		metalLayer.framebufferOnly = false
		metalLayer.isOpaque = true
		// Drawn on demand, as output arrives, rather than on a clock.
		metalLayer.presentsWithTransaction = false
		metalLayer.autoresizingMask = []
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Never takes the mouse: everything that responds to a click — selection,
	/// the cursor, dropping files — belongs to the view underneath.
	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	override var isFlipped: Bool { true }

	var scale: CGFloat = 2 {
		didSet { updateDrawableSize() }
	}

	/// The drawable changed size and holds nothing that fits it any more.
	///
	/// Waiting for the next tick of the display link would show whatever the
	/// layer had — stretched, or nothing at all — which is what makes a resize
	/// flicker.
	var onResize: (() -> Void)?

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		updateDrawableSize()
	}

	private func updateDrawableSize() {
		metalLayer.contentsScale = scale
		let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
		guard size.width >= 1, size.height >= 1, size != metalLayer.drawableSize else { return }
		metalLayer.drawableSize = size
		onResize?()
	}

	/// The next surface to draw into, or nil when there is nothing to draw on.
	func nextDrawable() -> CAMetalDrawable? {
		guard bounds.width >= 1, bounds.height >= 1 else { return nil }
		return metalLayer.nextDrawable()
	}
}

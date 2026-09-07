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
		// The frame is handed over as part of the same layout change that
		// resized the layer, rather than whenever the GPU gets round to it.
		// Otherwise a resize shows the old contents stretched to the new size
		// until the next frame arrives, which is what flickers.
		metalLayer.presentsWithTransaction = true
		metalLayer.autoresizingMask = []
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Never takes the mouse: everything that responds to a click — selection,
	/// the cursor, dropping files — belongs to the view underneath.
	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	/// The same I-beam the view underneath asks for.
	///
	/// **Said twice on purpose.** Cursor rects are not hit-testing: they are a
	/// list the window keeps, and `hitTest` returning nil above does not put
	/// this view's area back to whatever is beneath it. A subview that
	/// registers no rect ought to let the one underneath show through, and if
	/// that is so this override changes nothing — but GPU rendering is *on by
	/// default*, so being wrong about it means the pointer is an arrow over the
	/// terminal for nearly everybody, which is the fault this was written to
	/// fix. Four lines against that trade is worth it.
	override func resetCursorRects() {
		super.resetCursorRects()
		addCursorRect(bounds, cursor: .iBeam)
	}

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

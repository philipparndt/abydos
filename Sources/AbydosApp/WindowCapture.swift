import AppKit
import AbydosKit

/// A view holding something AppKit's own capture cannot see.
///
/// `cacheDisplay(in:to:)` walks the view tree and draws what is in it. A
/// `CAMetalLayer`'s contents are not, so a pane rendering through Metal comes
/// out empty — and nothing anywhere says why. A view that knows it has such
/// content answers with a picture of it instead.
protocol SnapshotDrawable: NSView {
	func snapshotImage(size: CGSize) -> CGImage?
}

enum WindowCapture {
	/// Renders a window to a PNG.
	///
	/// Draws the theme frame when reachable so the capture includes the titlebar
	/// and its pills; otherwise falls back to the content view.
	@discardableResult
	static func write(window: NSWindow, to path: String) -> Bool {
		// A child window is a window of its own, so it is nowhere in the frame
		// drawn below it. Each is written beside the capture instead.
		for (index, child) in window.childWindows?.enumerated() ?? [NSWindow]().enumerated() {
			let beside = (path as NSString).deletingPathExtension + "-child\(index).png"
			write(window: child, to: beside)
		}

		// A sheet is a window of its own, so it is nowhere in the frame that
		// gets drawn below it. It is written beside the capture instead.
		if let sheet = window.attachedSheet {
			let beside = (path as NSString).deletingPathExtension + "-sheet.png"
			write(window: sheet, to: beside)
		}

		guard let contentView = window.contentView else { return false }
		let target = contentView.superview ?? contentView

		target.layoutSubtreeIfNeeded()
		guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return false }
		target.cacheDisplay(in: target.bounds, to: rep)
		drawSnapshots(under: target, into: rep, of: target)

		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		do {
			try data.write(to: URL(fileURLWithPath: path))
			return true
		} catch {
			FileHandle.standardError.write(Data("screenshot write failed: \(error)\n".utf8))
			return false
		}
	}

	/// Paints in what the view tree could not draw.
	///
	/// After the ordinary capture, because these go *over* the empty rectangles
	/// it left behind: every view that says it holds Metal content is asked for
	/// a picture, and it is drawn where that view is.
	private static func drawSnapshots(under view: NSView, into rep: NSBitmapImageRep, of target: NSView) {
		var pending: [SnapshotDrawable] = []
		func collect(_ view: NSView) {
			if let drawable = view as? SnapshotDrawable { pending.append(drawable) }
			for subview in view.subviews { collect(subview) }
		}
		collect(view)
		guard !pending.isEmpty, let context = NSGraphicsContext(bitmapImageRep: rep) else { return }

		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = context
		for drawable in pending {
			let rect = drawable.convert(drawable.bounds, to: target)
			guard rect.width > 1, rect.height > 1,
			      let image = drawable.snapshotImage(size: rect.size)
			else { continue }
			NSImage(cgImage: image, size: rect.size).draw(in: rect)
		}
		NSGraphicsContext.restoreGraphicsState()
	}
}

import AppKit

/// An editor group's root view, which accepts dropped tabs.
///
/// The whole group is the drop target, not just its tab strip, so a tab can be
/// dropped over the text — which is where you look when deciding to split, and
/// what every editor with split panes accepts.
final class EditorDropView: ColoredView {
	weak var owner: EditorViewController?

	private var activeZone: EditorTabDrag.Zone?
	private let overlay = DropHighlightOverlay()

	/// How much of the top of this view lies under the window's titlebar.
	///
	/// The window draws its content full height, so this view starts behind the
	/// titlebar. Anything painted at y = 0 — the top edge of the drop outline —
	/// is therefore covered by it, which is what made the frame look open at
	/// the top.
	var topInset: CGFloat = 0 {
		didSet {
			guard topInset != oldValue else { return }
			needsLayout = true
		}
	}

	/// The part of this view somebody can actually see.
	private var visibleRegion: NSRect {
		NSRect(x: 0, y: topInset, width: bounds.width, height: max(0, bounds.height - topInset))
	}

	override init(color: NSColor) {
		super.init(color: color)
		// The preview must sit above the tab bar and the text, so it lives in its
		// own overlay rather than in this view's own drawing — anything drawn
		// here would be painted behind the subviews and never seen.
		overlay.autoresizingMask = [.width, .height]
		overlay.isHidden = true
		addSubview(overlay, positioned: .above, relativeTo: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// `EditorTabDrag` describes zones with a top-left origin — `.top` is the
	/// rect at y = 0 — so the view that hit-tests and draws them must agree.
	/// Unflipped, "drag to the top" would resolve to `.bottom`.
	override var isFlipped: Bool { true }

	override func layout() {
		super.layout()
		overlay.frame = visibleRegion
		// Subviews added later would otherwise cover it.
		if subviews.last !== overlay {
			overlay.removeFromSuperview()
			addSubview(overlay, positioned: .above, relativeTo: nil)
		}
	}

	// MARK: - Dragging

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		updateZone(sender)
		return .move
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		updateZone(sender)
		return .move
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		clearZone()
	}

	override func draggingEnded(_ sender: NSDraggingInfo) {
		clearZone()
	}

	private func updateZone(_ sender: NSDraggingInfo) {
		// Zones are worked out in the same region they are drawn in, so what is
		// highlighted is what the pointer is actually over.
		let point = convert(sender.draggingLocation, from: nil)
		let region = visibleRegion
		let local = NSPoint(x: point.x - region.minX, y: point.y - region.minY)
		let zone = EditorTabDrag.zone(for: local, in: NSRect(origin: .zero, size: region.size))
		guard zone != activeZone else { return }

		activeZone = zone
		overlay.frame = region
		overlay.zone = zone
		overlay.isHidden = false
		if subviews.last !== overlay {
			overlay.removeFromSuperview()
			addSubview(overlay, positioned: .above, relativeTo: nil)
		}
	}

	/// Shows a drop preview without a drag, so the screenshot harness can verify
	/// that the overlay actually paints above the tab bar and the text.
	func previewZoneForTesting(_ zone: EditorTabDrag.Zone) {
		activeZone = nil
		overlay.frame = visibleRegion
		overlay.zone = zone
		overlay.isHidden = false
		overlay.removeFromSuperview()
		addSubview(overlay, positioned: .above, relativeTo: nil)
		activeZone = zone
	}

	private func clearZone() {
		guard activeZone != nil else { return }
		activeZone = nil
		overlay.isHidden = true
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let zone = activeZone
		clearZone()

		guard let owner,
		      let payload = EditorTabDrag.payload(from: sender.draggingPasteboard),
		      let zone
		else { return false }

		owner.onTabDropped?(payload, zone, owner)
		return true
	}
}

/// Draws the region a drop would occupy, above everything else in the group.
private final class DropHighlightOverlay: NSView {
	var zone: EditorTabDrag.Zone? {
		didSet { needsDisplay = true }
	}

	/// Matches `EditorDropView`, and `EditorTabDrag`'s top-left origin.
	override var isFlipped: Bool { true }

	/// Never intercepts clicks; it exists only to be looked at.
	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	override func draw(_ dirtyRect: NSRect) {
		guard let zone else { return }
		let rect = EditorTabDrag.highlightRect(for: zone, in: bounds)
		let accent = Theme.current.gitModified

		accent.withAlphaComponent(0.18).setFill()
		rect.fill()

		// Outlining the whole target region rather than marking one edge: the
		// region is the answer to "where does this land", and an outline reads the
		// same whichever side the new pane takes.
		//
		// Inset by the full thickness rather than half of it, so the stroke
		// lands entirely inside the region: half of it would fall outside the
		// view at the edges and be clipped away, leaving a frame that looks
		// open on whichever sides touch them.
		let thickness = Theme.current.scaled(2.5)
		let outline = NSBezierPath(rect: rect.insetBy(dx: thickness, dy: thickness))
		outline.lineWidth = thickness
		accent.setStroke()
		outline.stroke()
	}
}

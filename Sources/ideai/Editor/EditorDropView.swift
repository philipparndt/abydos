import AppKit

/// An editor group's root view, which accepts dropped tabs.
///
/// The whole group is the drop target, not just its tab strip, so a tab can be
/// dropped over the text — which is where you look when you are deciding to
/// split, and what every editor with split panes accepts.
final class EditorDropView: ColoredView {
	weak var owner: EditorViewController?

	private var activeZone: EditorTabDrag.Zone?

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
		let point = convert(sender.draggingLocation, from: nil)
		let zone = EditorTabDrag.zone(for: point, in: bounds)
		guard zone != activeZone else { return }
		activeZone = zone
		needsDisplay = true
	}

	private func clearZone() {
		guard activeZone != nil else { return }
		activeZone = nil
		needsDisplay = true
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		defer { clearZone() }
		guard let owner,
		      let payload = EditorTabDrag.payload(from: sender.draggingPasteboard),
		      let zone = activeZone
		else { return false }

		owner.onTabDropped?(payload, zone, owner)
		return true
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		guard let activeZone else { return }

		// Preview exactly the region the drop would occupy, so the split that is
		// about to happen is obvious before releasing.
		let rect = EditorTabDrag.highlightRect(for: activeZone, in: bounds)
		Theme.current.gitModified.withAlphaComponent(0.20).setFill()
		rect.fill()

		Theme.current.gitModified.withAlphaComponent(0.8).setStroke()
		let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
		outline.lineWidth = 2
		outline.stroke()
	}
}

import AppKit
import AbydosKit

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
		operation(for: sender)
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		operation(for: sender)
	}

	/// What this drag would do, and what to show while it is overhead.
	///
	/// **`.move` used to be the answer to everything**, which is right for a tab
	/// being dragged between groups and is exactly what the Finder does not
	/// offer for a file. The project tree already carries the lesson: an
	/// operation the source never permitted is a drop that quietly does nothing,
	/// which is indistinguishable from not accepting the drag at all.
	///
	/// The zone overlay is a tab's business. It answers "where does this pane
	/// go", and a file is not a pane — it is a tab. So a file over the group
	/// highlights nothing, and what is shown is what will happen.
	private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
		if EditorTabDrag.payload(from: sender.draggingPasteboard) != nil {
			updateZone(sender)
			return .move
		}
		clearZone()
		guard !EditorDrop.urls(from: sender.draggingPasteboard).isEmpty else { return [] }
		// What the source is willing to do. A Finder drag offers copy; asking
		// for move would be refused and look like nothing happening.
		return sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
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
		guard let owner else { return false }

		if let payload = EditorTabDrag.payload(from: sender.draggingPasteboard), let zone {
			owner.onTabDropped?(payload, zone, owner)
			return true
		}

		// Files. Anything that is neither a tab nor a file is declined, so the
		// drag springs back rather than opening a tab named after a web address.
		let dropped = EditorDrop.urls(from: sender.draggingPasteboard)
		guard !dropped.isEmpty else { return false }
		owner.onFilesDropped?(dropped)
		return true
	}
}

/// Reading a drag that carries files.
///
/// Its own type because the decisions in it are decidable without a window —
/// which URLs are files, and which of them are folders — and a drop is otherwise
/// only checkable by driving.
enum EditorDrop {
	/// The file URLs a drag carries, in the order it carries them.
	///
	/// **File URLs only.** A browser will happily put an `https:` URL on the
	/// board, and `NSURL` reads it perfectly well; opening a tab for it would
	/// name a file that does not exist.
	static func urls(from pasteboard: NSPasteboard) -> [URL] {
		let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
		let read = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
		// Asked for twice: the option is a request AppKit honours for what it
		// can identify, and the filter is what makes it true.
		return DroppedFiles.filesOnly(read ?? [])
	}

	/// Which of them are folders, and which are files. See `DroppedFiles`.
	static func separate(_ urls: [URL]) -> (folders: [URL], files: [URL]) {
		DroppedFiles.separate(urls)
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

/// A drag the harness can make, since a real one cannot be scripted.
///
/// Only the parts `EditorDropView` reads are answered; the rest of
/// `NSDraggingInfo` is a large protocol whose other members it never touches.
/// Offering `.copy` is what a Finder drag offers, which is the case being
/// checked — and answering `.move` here would hide the very trap this change is
/// about.
final class TestingDrag: NSObject, NSDraggingInfo {
	private let board: NSPasteboard
	private let point: NSPoint

	init(pasteboard: NSPasteboard, at point: NSPoint) {
		self.board = pasteboard
		self.point = point
	}

	var draggingDestinationWindow: NSWindow? { nil }
	var draggingSourceOperationMask: NSDragOperation { [.copy] }
	var draggingLocation: NSPoint { point }
	var draggedImageLocation: NSPoint { point }
	var draggedImage: NSImage? { nil }
	var draggingPasteboard: NSPasteboard { board }
	var draggingSource: Any? { nil }
	var draggingSequenceNumber: Int { 1 }
	var draggingFormation: NSDraggingFormation {
		get { .default }
		set { _ = newValue }
	}
	var animatesToDestination: Bool {
		get { false }
		set { _ = newValue }
	}
	var numberOfValidItemsForDrop: Int {
		get { 1 }
		set { _ = newValue }
	}
	var springLoadingHighlight: NSSpringLoadingHighlight { .none }

	func slideDraggedImage(to screenPoint: NSPoint) {}
	func enumerateDraggingItems(
		options: NSDraggingItemEnumerationOptions,
		for view: NSView?,
		classes: [AnyClass],
		searchOptions: [NSPasteboard.ReadingOptionKey: Any],
		using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
	) {}
	func resetSpringLoading() {}
}

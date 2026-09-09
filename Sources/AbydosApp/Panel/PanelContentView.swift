import AppKit
import AbydosKit

// MARK: - Tab strip

struct PanelTabItem {
	let title: String
	let hasExited: Bool
	/// A terminal: the only kind somebody names, and the only kind that can go
	/// off into a window of its own.
	var isTerminal = false
	/// What it holds, drawn on the tab the way a file's icon is.
	var symbol = "terminal"
	/// On screen — which, when the pane is split, is more than one of them.
	var isShowing = false
	/// Whether the ✕ belongs on it.
	///
	/// A tmux window is closed by killing it, which can take a build or an ssh
	/// session with it; everything the panel owns itself closes with a click,
	/// as it always did.
	var isClosable = true
	/// What the Claude session in this tmux window is doing.
	var aiStatus: TmuxMirror.AIStatus?
	/// tmux's own number for the window, drawn where the icon would be: it is
	/// what `C-b 2` selects, and it is the name everybody using tmux already
	/// has for that window.
	var tmuxIndex: Int?
	/// Whether this tab is the terminal tmux is attached to — the one whose
	/// windows are the strip below.
	var isTmuxAttached = false
	/// A program somebody started, and whether it is still going.
	///
	/// Running, the tab wears the same green the titlebar does — the two are
	/// saying the same thing, and the one in the corner of the eye is the tab.
	var isRun = false
	var isRunning = false
	/// What to say about the engine that drew this pane, or nil where the usual
	/// one did.
	///
	/// **Only the other engine.** A mark on every pane in the ordinary case is a
	/// mark nobody reads — 0463's settled argument, which showed the container
	/// and not the local copy — and this strip is already carrying a name, a
	/// running wash, a Claude badge and a close cross.
	var engineNote: String?

	/// What this tab is called by something more durable than its position.
	///
	/// The strip remembers which tab its run of drawn tabs starts at, and an
	/// index is worthless for that: the list is rebuilt whenever tmux's windows
	/// are re-read, and a window closed in another client shifts every number
	/// after it. Empty where nothing has said — a strip that cannot name its
	/// tabs simply starts at the first, which is what it did before.
	var identity: String = ""
}

extension PanelTabStrip: NSViewToolTipOwner {
	/// What the tab under the pointer says about its engine.
	///
	/// Answered from the point rather than from a table built when the tooltip
	/// was registered: this strip is rebuilt whenever tmux's windows are
	/// re-read, and anything remembered by index would name the wrong tab a
	/// moment later.
	func view(
		_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
		point: NSPoint, userData: UnsafeMutableRawPointer?
	) -> String {
		for (index, item) in items.enumerated() where framesForToolTips.indices.contains(index) {
			if framesForToolTips[index].contains(point), let note = item.engineNote { return note }
		}
		return ""
	}
}

/// The panel's content area, which a dragged terminal tab can be dropped on.
final class PanelContentView: NSView {
	var onDrop: ((TerminalTabDrag.Payload, TerminalTabDrag.Zone) -> Void)?
	/// Whether this panel wants a given tab at all.
	var acceptsDrag: ((TerminalTabDrag.Payload) -> Bool)?

	private var zone: TerminalTabDrag.Zone?

	/// Shows the preview without a drag, for the capture harness.
	func previewForTesting(_ zone: TerminalTabDrag.Zone) {
		previewZone(zone)
	}

	/// Draws the half a drop would land in, or nothing.
	func previewZone(_ zone: TerminalTabDrag.Zone?) {
		guard zone != self.zone else { return }
		self.zone = zone
		needsDisplay = true
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		registerForDraggedTypes([TerminalTabDrag.pasteboardType])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		update(with: sender)
	}

	override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
		update(with: sender)
	}

	private func update(with sender: any NSDraggingInfo) -> NSDragOperation {
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard),
		      acceptsDrag?(payload) ?? false
		else { return [] }

		let point = convert(sender.draggingLocation, from: nil)
		let zone = TerminalTabDrag.zone(for: point, in: bounds)
		if zone != self.zone {
			self.zone = zone
			needsDisplay = true
		}
		return .move
	}

	override func draggingExited(_ sender: (any NSDraggingInfo)?) {
		zone = nil
		needsDisplay = true
	}

	override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		defer {
			zone = nil
			needsDisplay = true
		}
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard),
		      acceptsDrag?(payload) ?? false, let zone
		else { return false }
		onDrop?(payload, zone)
		return true
	}

	/// The half it would land in, so a split is something you see before you
	/// commit to it.
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		guard let zone else { return }

		let rect = TerminalTabDrag.highlightRect(for: zone, in: bounds)
		Theme.current.gitModified.withAlphaComponent(0.12).setFill()
		rect.fill()
		Theme.current.gitModified.withAlphaComponent(0.7).setStroke()
		let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
		outline.lineWidth = 2
		outline.stroke()
	}
}

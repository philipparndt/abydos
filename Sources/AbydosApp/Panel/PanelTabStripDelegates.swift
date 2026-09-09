import AppKit
import AbydosKit

/// Committing a rename: return keeps it, escape drops it, and clicking away
/// keeps it too — the same as renaming a file in the Finder.
extension PanelTabStrip: NSTextFieldDelegate {
	func controlTextDidEndEditing(_ notification: Notification) {
		endRenaming(commit: true)
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
		switch command {
		case #selector(NSResponder.cancelOperation(_:)):
			endRenaming(commit: false)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			endRenaming(commit: true)
			return true
		default:
			return false
		}
	}
}


/// Dragging a terminal tab within its own strip, and out of it.
extension PanelTabStrip: NSDraggingSource {
	func draggingSession(
		_ session: NSDraggingSession,
		sourceOperationMaskFor context: NSDraggingContext
	) -> NSDragOperation {
		context == .withinApplication ? .move : []
	}

	/// Let go where nothing wanted it: outside the window, that means a window
	/// of its own.
	func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
		onDragMoved?(screenPoint)
	}

	/// Where the drag ended, when nothing took it.
	///
	/// The panel decides rather than a drop target: a terminal fills the pane
	/// it is in, and relying on a view under it to be offered the drop is
	/// relying on a hit test through whatever the program happens to be
	/// drawing. The pointer's position is not in doubt.
	func draggingSession(
		_ session: NSDraggingSession,
		endedAt screenPoint: NSPoint,
		operation: NSDragOperation
	) {
		let index = draggedIndex
		draggedIndex = nil
		dropCaret = nil
		needsDisplay = true
		onDragEnded?()

		guard operation == [], let index else { return }
		onDragEndedAt?(index, screenPoint)
	}
}

extension PanelTabStrip {
	func setUpTabDropping() {
		registerForDraggedTypes([TerminalTabDrag.pasteboardType])
	}

	override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		draggingUpdated(sender)
	}

	override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard),
		      payload.panelID == panelID || acceptsForeign?(payload) == true
		else { return [] }

		let point = convert(sender.draggingLocation, from: nil)
		let caret = insertionIndex(at: point)
		if caret != dropCaret {
			dropCaret = caret
			needsDisplay = true
		}
		return .move
	}

	override func draggingExited(_ sender: (any NSDraggingInfo)?) {
		dropCaret = nil
		needsDisplay = true
	}

	override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		defer {
			dropCaret = nil
			needsDisplay = true
		}
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard) else { return false }
		let point = convert(sender.draggingLocation, from: nil)
		onDropTab?(payload, insertionIndex(at: point))
		return true
	}
}


/// A text field whose text sits in the middle of it.
///
/// A tab is taller than a line, and a field left to itself puts its text at
/// the top of the box — which beside the tabs either side of it reads as

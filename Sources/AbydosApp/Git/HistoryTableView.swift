import AppKit
import AbydosKit

/// A table that says when its selection changed and when it ran out of rows.
final class HistoryTableView: NSTableView {
	/// A click from an inactive window lands on the row, rather than being
	/// spent activating the app.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.resignFirstResponder()
	}

	var onSelectionChange: (() -> Void)?
	var onScrolledToEnd: (() -> Void)?
	var rowHeightOverride: CGFloat?
	/// A click in the graph column, which the pane may take for a fold.
	var onGraphClick: ((NSPoint, Int) -> Bool)?
	/// Left and right on a commit: fold the branch it brought in, or show it.
	var onFold: ((_ expanding: Bool, _ row: Int) -> Void)?

	override func keyDown(with event: NSEvent) {
		// A merge folds with ← and opens with →, as a tree does everywhere
		// else. It could only ever be done by hitting a nine-point box.
		if event.keyCode == 123 || event.keyCode == 124, selectedRow >= 0 {
			onFold?(event.keyCode == 124, selectedRow)
			return
		}
		super.keyDown(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		// The table's own x is the row's x — rows start at its leading edge —
		// so converting through a row view that may not exist yet only ever
		// moved the point into the wrong space.
		let row = self.row(at: point)
		if row >= 0, onGraphClick?(point, row) == true { return }
		super.mouseDown(with: event)
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)

		// Asking for more when the last row has been drawn: a log is read by
		// scrolling, and the page after the one you are on is the one you are
		// about to want.
		guard numberOfRows > 0, let last = rowView(atRow: numberOfRows - 1, makeIfNecessary: false)
		else { return }
		if dirtyRect.intersects(last.frame) { onScrolledToEnd?() }
	}
}

import AppKit
import AbydosKit

// MARK: - Table subclass

final class SwitcherTableView: NSTableView {
	var onKeyDown: ((NSEvent) -> Bool)?

	/// Row under the pointer, so rows light up on hover the way a menu does.
	var hoveredRow: Int = -1
	var trackingArea: NSTrackingArea?

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	// The popover's table should take focus so arrow keys work on open.
	override var acceptsFirstResponder: Bool { true }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		setHovered(row(at: point))
	}

	override func mouseExited(with event: NSEvent) {
		setHovered(-1)
	}

	func setHovered(_ newRow: Int) {
		guard newRow != hoveredRow else { return }
		let previous = hoveredRow
		hoveredRow = newRow

		// Repaint only the two rows involved rather than the whole table.
		for candidate in [previous, newRow] where candidate >= 0 {
			(rowView(atRow: candidate, makeIfNecessary: false) as? SwitcherRowView)?
				.setHovered(candidate == newRow)
		}
	}
}

/// Draws the blue selection band, and a lighter band on hover.
final class SwitcherRowView: NSTableRowView {
	var isHovered = false

	func setHovered(_ hovered: Bool) {
		guard hovered != isHovered else { return }
		isHovered = hovered
		needsDisplay = true
	}

	override func drawBackground(in dirtyRect: NSRect) {
		super.drawBackground(in: dirtyRect)
		// Only when not selected, so hover never competes with the selection.
		guard isHovered, !isSelected else { return }
		NSColor.white.withAlphaComponent(0.07).setFill()
		bounds.fill()
	}

	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selectionActive.setFill()
		bounds.fill()
	}

	override var isEmphasized: Bool {
		get { true }
		set {}
	}
}

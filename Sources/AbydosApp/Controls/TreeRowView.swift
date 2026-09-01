import AppKit
import AbydosKit

/// The row behind a selected row, in every tree in this app.
///
/// **What it replaces is AppKit's own selection band.** An outline view that is
/// not given a row view of its own draws the system's full-bleed blue, and the
/// commit page's changes tree was never given one — so a selected file sat in a
/// system band inside a window that draws its selection as a rounded, inset
/// pill everywhere else. Reported on 2026-09-01 as "that tree's selection is
/// not themed", which is exactly what it is: not the app's colour, not the
/// app's shape, and not quiet when the keyboard is elsewhere.
///
/// The shape and the rule are the project tree's, which had them first and
/// worked them out: a rounded pill inset from the edges, in the palette's
/// selection colour, strong while the tree has the keyboard and quiet while it
/// does not — *this is where you were, and it is not where your keys are
/// going*.
class TreeRowView: NSTableRowView {
	/// A wash behind the row that is not a selection — the project tree tints
	/// excluded output directories this way.
	var tint: NSColor?

	/// Cells draw their label colour from the selection state, so they have to
	/// repaint when it changes — `NSTableRowView` only invalidates itself.
	override var isSelected: Bool {
		didSet {
			guard isSelected != oldValue else { return }
			for subview in subviews { subview.needsDisplay = true }
		}
	}

	override func drawBackground(in dirtyRect: NSRect) {
		super.drawBackground(in: dirtyRect)
		if let tint, !isSelected {
			tint.setFill()
			bounds.fill()
		}
	}

	override func drawSelection(in dirtyRect: NSRect) {
		let colour = Theme.current.selection(.row, hasKeyboard: isTreeFocused)
		let rect = bounds.insetBy(dx: Theme.current.scaled(5), dy: 1)
		let radius = Theme.current.scaled(6)
		colour.setFill()
		NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
	}

	/// True when the tree holding this row has the keyboard.
	var isTreeFocused: Bool {
		guard let window, let responder = window.firstResponder as? NSView else { return false }
		return responder === superview || responder.isDescendant(of: superview ?? self)
	}
}

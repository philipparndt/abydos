import AppKit
import AbydosKit

/// A verb drawn at the trailing edge of a row in the git tree.
///
/// **A verb hangs off the row that draws its object.** That is what
/// `git-refs-tree` already says about a folder of branches, and it is the reason
/// the traffic button existed: the repository had no row, so its verb needed a
/// button above the tree. Everything in that header was a verb belonging to a
/// row — making a branch to `Local`, committing to the working copy — put in a
/// box at the top because nothing offered to carry it.
///
/// Drawn rather than made a subview. Every row in this pane is custom drawn
/// through `RowMetrics`, and an `NSButton` here would be the one control in the
/// tree that did not match the rest of it. (The first version of this said row
/// views are recycled and buttons would have to be attached and detached — they
/// are not: `outlineView(_:viewFor:item:)` builds a fresh view per row and never
/// calls `makeView(withIdentifier:)`. The reason is house style, not recycling,
/// and saying the wrong one would have misled whoever reads this next.)
struct RowAction {
	/// The words, for an action that has room for them.
	var title: String?
	/// The glyph, for one that does not. One of the two is set.
	var symbol: String?
	/// What it is, for a tooltip and for a driven run to report.
	var help: String
	/// Whether it is drawn even when the pointer is elsewhere.
	///
	/// True for the things that are *state* or are done constantly — the
	/// repository's traffic, the working copy's commit. False for the
	/// occasional ones, which appear when the row is pointed at or selected and
	/// stay quiet otherwise.
	var isAlwaysShown: Bool = false
}

/// A row that can carry one.
///
/// The action is hit-tested before the row's own gesture, the way the editor's
/// tab strip checks its trailing controls before its tabs: the control sits over
/// the row and a press there means the control.
///
/// **Selection counts as being pointed at**, which is what makes the keyboard
/// work: a row arrowed to shows what it offers, so `⌘⏎` is never a guess about
/// an invisible verb.
class ActionableRowView: NSView {
	override var isFlipped: Bool { true }

	var action: RowAction? {
		didSet { needsDisplay = true }
	}
	var onAction: (() -> Void)?

	private var isPointedAt = false
	private var actionFrame: NSRect = .zero

	/// Whether the row this is in is selected, which the row view above knows.
	var isRowSelected: Bool { (superview as? NSTableRowView)?.isSelected ?? false }

	private var showsAction: Bool {
		guard let action else { return false }
		return action.isAlwaysShown || isPointedAt || isRowSelected
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach(removeTrackingArea)
		addTrackingArea(NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		))
	}

	override func mouseEntered(with event: NSEvent) {
		isPointedAt = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent) {
		isPointedAt = false
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		if showsAction, actionFrame.contains(point) {
			fireAction()
			return
		}
		// Anything else is the row's, and the outline view is the row.
		super.mouseDown(with: event)
	}

	/// Pressed, from the pointer or from `⌘⏎`.
	func fireAction() {
		guard action != nil else { return }
		onAction?()
	}

	/// Draws the action and answers how much room it took, so a row can lay its
	/// own text out inside what is left.
	@discardableResult
	func drawAction() -> CGFloat {
		actionFrame = .zero
		guard let action, showsAction else { return 0 }

		let font = Theme.current.uiFont(11, weight: .medium)
		let colour = Theme.current.gitIgnored
		let padding = Theme.current.scaled(7)
		let height = Theme.current.scaled(17)

		var width = Theme.current.scaled(20)
		var label: NSAttributedString?
		if let title = action.title {
			let text = NSAttributedString(string: title, attributes: [
				.font: font,
				.foregroundColor: Theme.current.sidebarHeaderText,
			])
			label = text
			width = ceil(text.size().width) + padding * 2
		}

		let frame = NSRect(
			x: bounds.maxX - RowMetrics.trailingInset - width,
			y: bounds.midY - height / 2,
			width: width,
			height: height
		)
		guard frame.minX > RowMetrics.textInset else { return 0 }
		actionFrame = frame

		let path = NSBezierPath(
			roundedRect: frame,
			xRadius: Theme.current.scaled(4),
			yRadius: Theme.current.scaled(4)
		)
		Theme.current.sidebarHeaderText.withAlphaComponent(isPointedAt ? 0.20 : 0.10).setFill()
		path.fill()

		if let label {
			label.draw(at: NSPoint(
				x: frame.minX + padding,
				y: frame.midY - label.size().height / 2
			))
		} else if let symbol = action.symbol,
		          let icon = Theme.symbol(
		          	symbol, size: 11 * Theme.current.scale, color: colour, weight: .medium
		          ) {
			icon.draw(in: NSRect(
				x: frame.midX - icon.size.width / 2,
				y: frame.midY - icon.size.height / 2,
				width: icon.size.width,
				height: icon.size.height
			))
		}

		toolTip = action.help
		return width + RowMetrics.trailingInset
	}

	/// What a driven run reads: whether this row offers anything, and what.
	var actionReportForTesting: String {
		guard let action else { return "-" }
		let name = action.title ?? action.symbol ?? "?"
		return "\(name)\(action.isAlwaysShown ? "" : " (on hover)")"
	}
}

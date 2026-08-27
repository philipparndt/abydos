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
	/// The words for a row too narrow to hold the first set.
	///
	/// A verb that takes half a 300-point pane leaves `Working copy` reading
	/// `Wor…`, which is the row saying less than it did before it had a verb.
	var shortTitle: String?
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

	/// A second verb, to the left of the first, drawn as a glyph and never as
	/// words.
	///
	/// **Glyph-only on purpose.** The width arithmetic below exists because a
	/// row whose name was truncated to make space for a button has been made
	/// worse by the button, and two sets of spellings competing for the same
	/// trailing edge is that problem twice. A symbol is a fixed twenty points,
	/// so what the row has left is still one subtraction.
	///
	/// One user so far: re-reading the repository, which is a verb on the
	/// repository and had nowhere to live — this pane deliberately has no header
	/// to put a button in, and its own comment says why.
	var secondaryAction: RowAction? {
		didSet { needsDisplay = true }
	}
	var onSecondaryAction: (() -> Void)?

	private var isPointedAt = false
	private var actionFrame: NSRect = .zero
	private var secondaryFrame: NSRect = .zero

	/// Whether the row this is in is selected, which the row view above knows.
	var isRowSelected: Bool { (superview as? NSTableRowView)?.isSelected ?? false }

	private var showsAction: Bool {
		guard let action else { return false }
		return action.isAlwaysShown || isPointedAt || isRowSelected
	}

	private var showsSecondary: Bool {
		guard let secondaryAction else { return false }
		return secondaryAction.isAlwaysShown || isPointedAt || isRowSelected
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
		// The second verb first: it sits inside the space the first one measured
		// from, so asking in the other order would give every press to the first.
		if showsSecondary, secondaryFrame.contains(point) {
			firesSecondaryForTesting += 1
			onSecondaryAction?()
			return
		}
		if showsAction, actionFrame.contains(point) {
			fireAction()
			return
		}
		// Anything else is the row's, and the outline view is the row.
		super.mouseDown(with: event)
	}

	/// Pressed, from the pointer or from `⌘⏎`.
	/// How many times this row's verb has been pressed or keyed.
	///
	/// Counted because the verbs worth checking do not all leave a mark a
	/// driven run can read: `Pull` opens a dialog, and a driven run that opens
	/// a dialog stops. The question the count answers is the one in doubt —
	/// did the key reach the row — rather than what the row then did.
	private(set) var firesForTesting = 0
	private(set) var firesSecondaryForTesting = 0

	func fireAction() {
		guard action != nil else { return }
		firesForTesting += 1
		onAction?()
	}

	private var padding: CGFloat { Theme.current.scaled(7) }

	private func text(_ title: String) -> NSAttributedString {
		NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(11, weight: .medium),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
	}

	/// The longest of the action's spellings that leaves the row's own text a
	/// readable amount of room.
	///
	/// **The row comes first.** A row whose name has been truncated to make
	/// space for a button has been made worse by the button.
	private func label(for action: RowAction) -> NSAttributedString? {
		let spellings = [action.title, action.shortTitle].compactMap { $0 }
		guard !spellings.isEmpty else { return nil }
		let forTheRow = Theme.current.scaled(96)
		for spelling in spellings {
			let drawn = text(spelling)
			let width = ceil(drawn.size().width) + padding * 2 + RowMetrics.trailingInset
			if bounds.width - width >= forTheRow { return drawn }
		}
		return text(spellings[spellings.count - 1])
	}

	/// How much of the trailing edge the action will take, **measured before
	/// anything is drawn**.
	///
	/// A row draws its own text first, so it has to know what is left before it
	/// starts. The first version of this returned the width from the drawing
	/// call and the rows asked afterwards, which is too late: `Working copy` was
	/// drawn to the full width and `Review 2 changes…` was then drawn on top of
	/// it, and in a narrow pane the two were one unreadable row.
	var actionWidth: CGFloat {
		let first: CGFloat = {
			guard let action, showsAction else { return 0 }
			return label(for: action).map { ceil($0.size().width) + padding * 2 }
				?? Theme.current.scaled(20)
		}()
		// The gap only where there is something on both sides of it: a row with
		// only the glyph must not be inset by the space a missing button would
		// have needed.
		let second = showsSecondary
			? secondaryWidth + (first > 0 ? secondaryGap : 0)
			: 0
		guard first > 0 || second > 0 else { return 0 }
		return first + second + RowMetrics.trailingInset
	}

	/// The box a second verb's glyph is drawn in.
	private var secondaryWidth: CGFloat { Theme.current.scaled(24) }

	/// **Between the two of them, and it was missing.** The glyph fills its box,
	/// so `Fetch` and the refresh arrow were drawn edge to edge and read as one
	/// wide control with a line down it.
	private var secondaryGap: CGFloat { Theme.current.scaled(6) }

	/// Draws the action, at the width `actionWidth` promised.
	func drawAction() {
		actionFrame = .zero
		secondaryFrame = .zero
		drawSecondaryAction()
		guard let action, showsAction else { return }

		let colour = Theme.current.gitIgnored
		let height = Theme.current.scaled(17)
		let label = label(for: action)
		let aside = showsSecondary ? secondaryWidth + secondaryGap : 0
		let width = actionWidth - RowMetrics.trailingInset - aside

		// To the left of the second verb when there is one, which is the whole
		// reason `actionWidth` counts both: the first version put them at the
		// same trailing edge and drew the glyph on top of `Push`.
		let frame = NSRect(
			x: bounds.maxX - RowMetrics.trailingInset - width - aside,
			y: bounds.midY - height / 2,
			width: width,
			height: height
		)
		guard frame.minX > RowMetrics.textInset else { return }
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
	}

	/// The second verb, at the trailing edge, with the first one to its left.
	private func drawSecondaryAction() {
		guard let secondary = secondaryAction, showsSecondary else { return }
		let height = Theme.current.scaled(17)
		let frame = NSRect(
			x: bounds.maxX - RowMetrics.trailingInset - secondaryWidth,
			y: bounds.midY - height / 2,
			width: secondaryWidth,
			height: height
		)
		guard frame.minX > RowMetrics.textInset else { return }
		secondaryFrame = frame

		let path = NSBezierPath(
			roundedRect: frame,
			xRadius: Theme.current.scaled(4),
			yRadius: Theme.current.scaled(4)
		)
		Theme.current.sidebarHeaderText.withAlphaComponent(isPointedAt ? 0.20 : 0.10).setFill()
		path.fill()

		guard let symbol = secondary.symbol,
		      let icon = Theme.symbol(
		      	symbol, size: 11 * Theme.current.scale,
		      	color: Theme.current.gitIgnored, weight: .medium
		      )
		else { return }
		icon.draw(in: NSRect(
			x: frame.midX - icon.size.width / 2,
			y: frame.midY - icon.size.height / 2,
			width: icon.size.width,
			height: icon.size.height
		))
	}

	/// What a driven run reads: whether this row offers anything, and what.
	var actionReportForTesting: String {
		guard let action else { return "-" }
		let name = action.title ?? action.symbol ?? "?"
		return "\(name)\(action.isAlwaysShown ? "" : " (on hover)")"
	}
}

import AppKit
import AbydosKit

/// The split between two editor groups, holding the divider where it was put.
///
/// `NSSplitView` lays arranged subviews out through Auto Layout, and this split
/// used to say nothing at all about where its divider goes: no width
/// constraint, no holding priority, no delegate. Nothing stating the position
/// means the position is whatever the solver makes of what is *in* the panes,
/// so every layout pass re-divided the split from the panes' fitting widths.
/// A pane holding a file has a small one and nothing moved; the settings page
/// has a real one — its sidebar and the widest card, 620 points of it — and
/// that pane was pinned to exactly that number. Dragging the divider set the
/// frames, the next layout pass threw them away, and the page sprang back.
///
/// So the divider's position is said here as a constraint, the way the window
/// says the tree's width for the same reason. A share of the split rather than
/// a number of points, so a window that changes size keeps the proportion
/// instead of giving every new pixel to one side; `.defaultHigh`, so a pane
/// that genuinely cannot be that narrow still wins.
final class EditorGroupSplitView: NSSplitView {
	override var dividerColor: NSColor { Theme.current.separator }
	override var dividerThickness: CGFloat { 1 }

	/// How hard the divider holds its place.
	///
	/// Above what a pane's contents prefer, so a page with a wide natural width
	/// cannot re-divide the split; below the window's own width, which AppKit
	/// states at 500. Higher than that and a pane too narrow for what is in it
	/// widens the *window* to make room, so dragging the divider across resized
	/// the window instead of moving the divider.
	private static let sharePriority = NSLayoutConstraint.Priority(490)

	/// The first pane's share of the split.
	private var fraction: CGFloat = 0.5
	/// The constraint saying that share, remade whenever it changes: a
	/// multiplier cannot be edited.
	private var share: NSLayoutConstraint?

	init(vertical: Bool) {
		super.init(frame: .zero)
		isVertical = vertical
		dividerStyle = .thin
		delegate = self
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Halves the split, which is what a split gesture means.
	///
	/// Said as a share, so it needs no width to divide: the old version waited
	/// for a layout pass to halve a number, because halving nothing gives the
	/// new pane nothing.
	func divideEvenly() {
		fraction = 0.5
		applyShare()
	}

	override func layout() {
		// The panes change: a group is removed and its split collapses into the
		// one above, which replaces the view this constraint was made against.
		if share == nil || share?.firstItem !== arrangedSubviews.first { applyShare() }
		super.layout()
	}

	private func applyShare() {
		guard arrangedSubviews.count == 2 else { return }
		share?.isActive = false
		let first = arrangedSubviews[0]
		let constraint = isVertical
			? first.widthAnchor.constraint(equalTo: widthAnchor, multiplier: fraction)
			: first.heightAnchor.constraint(equalTo: heightAnchor, multiplier: fraction)
		constraint.priority = Self.sharePriority
		constraint.isActive = true
		share = constraint
	}

	/// Moves the divider as a drag does, for a run with no hand on the mouse:
	/// the position the drag proposes, and then the position itself.
	func dragDividerForTesting(to position: CGFloat) {
		_ = splitView(self, constrainSplitPosition: position, ofSubviewAt: 0)
		setPosition(position, ofDividerAt: 0)
	}
}

extension EditorGroupSplitView: NSSplitViewDelegate {
	/// Takes the drag down as it happens, rather than after.
	///
	/// This is asked where the divider is being dragged to before anything
	/// moves, which is the moment to change what the constraint says. Written
	/// afterwards instead, the constraint and the frames would disagree for a
	/// pass and the divider would only travel part of the way with the mouse.
	func splitView(
		_ splitView: NSSplitView,
		constrainSplitPosition proposedPosition: CGFloat,
		ofSubviewAt dividerIndex: Int
	) -> CGFloat {
		let total = isVertical ? bounds.width : bounds.height
		guard total > 1 else { return proposedPosition }
		fraction = min(1, max(0, proposedPosition / total))
		applyShare()
		return proposedPosition
	}
}

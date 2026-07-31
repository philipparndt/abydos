import AppKit
import IdeaiKit

/// A split whose divider goes almost the whole way across.
///
/// `NSSplitView` otherwise honours the panes' own minimum widths, and a code
/// view with a gutter and a rendered document each claim a fair share — so the
/// divider stops well short of either edge. Here the point is to glance at one
/// while working in the other, which means being able to give a pane nearly
/// everything.
final class PreviewSplitView: NSSplitView, NSSplitViewDelegate {
	override var dividerColor: NSColor { Theme.current.separator }
	override var dividerThickness: CGFloat { 1 }

	/// Enough to keep a sliver showing, so a pane pushed aside can be dragged
	/// back rather than lost.
	private static var minimumPane: CGFloat { Theme.current.scaled(48) }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		delegate = self
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func splitView(
		_ splitView: NSSplitView,
		constrainMinCoordinate proposedMinimumPosition: CGFloat,
		ofSubviewAt dividerIndex: Int
	) -> CGFloat {
		Self.minimumPane
	}

	func splitView(
		_ splitView: NSSplitView,
		constrainMaxCoordinate proposedMaximumPosition: CGFloat,
		ofSubviewAt dividerIndex: Int
	) -> CGFloat {
		let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
		return max(Self.minimumPane, total - Self.minimumPane)
	}

	/// Neither pane collapses. A collapsed pane leaves no divider to grab, and
	/// getting it back means going through the menu.
	func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
		false
	}

	/// Keeps the proportions when the window resizes, rather than giving every
	/// new pixel to one side.
	func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
		let isVertical = splitView.isVertical
		let old = isVertical ? oldSize.width : oldSize.height
		let new = isVertical ? splitView.bounds.width : splitView.bounds.height

		guard old > 0, new > 0, splitView.arrangedSubviews.count == 2 else {
			splitView.adjustSubviews()
			return
		}

		let first = splitView.arrangedSubviews[0]
		let fraction = (isVertical ? first.frame.width : first.frame.height) / old
		splitView.adjustSubviews()
		splitView.setPosition((new * fraction).rounded(), ofDividerAt: 0)
	}
}

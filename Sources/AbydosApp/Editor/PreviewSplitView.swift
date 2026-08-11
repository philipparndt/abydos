import AppKit
import AbydosKit

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

	/// Where the divider is wanted, as a fraction of the whole, until the split
	/// is big enough to be told.
	///
	/// A split is built while its tab is being opened, and at that moment it has
	/// no size — a restored tab that is not the one in front is never laid out at
	/// all until somebody clicks it. So the fraction is kept here and spent at
	/// the first layout with room in it, which is also the only honest answer to
	/// "where is your divider" for a split that has never had one.
	///
	/// Set before the split is in a window, which is where it is built, so there
	/// is no layout to ask for: the first one comes with being installed.
	var wantedFraction: CGFloat?

	/// Where the divider is now, as a fraction of the whole, or nil for a split
	/// that has not been laid out and was not told where to put it.
	var currentFraction: CGFloat? {
		if let wantedFraction { return wantedFraction }
		guard arrangedSubviews.count == 2 else { return nil }
		let total = isVertical ? bounds.width : bounds.height
		guard total > 0 else { return nil }
		let first = arrangedSubviews[0]
		return (isVertical ? first.frame.width : first.frame.height) / total
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		delegate = self
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func layout() {
		super.layout()
		guard let fraction = wantedFraction else { return }
		// Not until both halves fit. A split laid out at a few points once — a
		// window being restored, a pane mid-animation — would spend the fraction
		// against that, have it clamped to the minimum by the delegate below, and
		// then keep *those* proportions for ever, since a resize preserves
		// whatever it finds.
		let total = isVertical ? bounds.width : bounds.height
		guard total > 2 * Self.minimumPane else { return }

		// Cleared before the move and not after, because `setPosition` lays the
		// split out again from inside this call. 5edc084 is the same shape — a
		// divider answering a resize by resizing — and it died of a stack
		// overflow before anybody saw the divider.
		wantedFraction = nil
		setPosition((total * fraction).rounded(), ofDividerAt: 0)
	}

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

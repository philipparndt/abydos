import CoreGraphics
import Foundation

/// Pulling an editor tab out into a window of its own.
///
/// The geometry lives here so the rule for when a drag becomes a window, and
/// where that window lands, can be checked without dragging anything.
public enum TearOff {
	/// How far below the new window's top edge the pointer sits.
	///
	/// Roughly a title bar, so the window looks as though it was pulled out
	/// from under the cursor and could go on being dragged by it.
	public static let grabInset: CGFloat = 24

	/// Whether releasing here should make a window.
	///
	/// Only outside the window the tab came from. Anywhere inside it the drop
	/// either landed on something that wanted it — another group, the tab strip,
	/// an edge to split against — or on chrome that did not, and turning "I let
	/// go over the file tree" into a new window would be a surprise.
	public static func tearsOff(dropPoint: CGPoint, sourceWindowFrame: CGRect) -> Bool {
		!sourceWindowFrame.contains(dropPoint)
	}

	/// Where a window torn off at `dropPoint` should sit.
	///
	/// `visibleFrame` is that of the screen the drop landed on, so a tab dragged
	/// to a second display opens there rather than back on the first.
	public static func windowFrame(
		droppedAt dropPoint: CGPoint,
		size: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		// A window larger than the screen it was dropped on is no use.
		let width = min(size.width, visibleFrame.width)
		let height = min(size.height, visibleFrame.height)

		// Centred under the pointer horizontally, hanging below it vertically.
		var origin = CGPoint(
			x: dropPoint.x - width / 2,
			y: dropPoint.y + grabInset - height
		)

		// Wholly on screen, whatever corner it was dropped near.
		origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - width)
		origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - height)

		return CGRect(origin: origin, size: CGSize(width: width, height: height))
	}
}

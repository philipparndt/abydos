import AppKit
import IdeaiKit

/// How much of a row is inside the selection.
///
/// The pill AppKit draws is inset from the row it belongs to, so text laid out
/// to the row's own edge runs past the highlight and out of the sidebar. Every
/// row here stops here instead.
enum RowMetrics {
	static var trailingInset: CGFloat { Theme.current.scaled(12) }

	/// Draws one line, cut short with an ellipsis rather than run past, and
	/// says where it ended.
	@discardableResult
	static func draw(
		_ text: String,
		font: NSFont,
		colour: NSColor,
		at x: CGFloat,
		in bounds: NSRect,
		limit: CGFloat
	) -> CGFloat {
		guard limit > x else { return x }

		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let string = NSAttributedString(string: text, attributes: [
			.font: font,
			.foregroundColor: colour,
			.paragraphStyle: paragraph,
		])

		let height = string.size().height
		let width = min(string.size().width, limit - x)
		string.draw(in: NSRect(x: x, y: bounds.midY - height / 2, width: width, height: height))
		return x + width
	}
}


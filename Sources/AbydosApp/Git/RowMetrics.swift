import AppKit
import AbydosKit

/// How much of a row is inside the selection.
///
/// The pill AppKit draws is inset from the row it belongs to, so text laid out
/// to the row's own edge runs past the highlight and out of the sidebar. Every
/// row here stops here instead.
enum RowMetrics {
	static var trailingInset: CGFloat { Theme.current.scaled(12) }

	/// Where a row's leading glyph goes: the tick on the current branch, the
	/// status letter on a change, the tray on a stash.
	///
	/// **One column for all of them, and one for the text beside it.** These
	/// were five different numbers in five row views, and an outline view that
	/// indents by depth turned that into a tree whose names did not line up
	/// with each other at any level.
	static var glyphInset: CGFloat { Theme.current.scaled(2) }

	/// How big the glyph is drawn.
	///
	/// **The project tree's numbers, because it is the tree beside this one.**
	/// A thirteen-point symbol in a sixteen-point box, six points of air, and
	/// the text after that — `FileIcon` and the navigator's row have drawn it
	/// that way for as long as there has been one, and a git tree whose icons
	/// were three points smaller read as a different application.
	static var glyphSize: CGFloat { Theme.current.scaled(16) }

	/// Where a row's text goes, leaving the glyph column to its left.
	static var textInset: CGFloat { glyphInset + glyphSize + Theme.current.scaled(6) }

	/// Draws a row's leading glyph in its column.
	static func glyph(_ name: String, colour: NSColor, in bounds: NSRect) {
		guard let image = Theme.symbol(name, size: 13 * Theme.current.scale, color: colour) else {
			return
		}
		image.drawFitted(in: NSRect(
			x: glyphInset, y: bounds.midY - glyphSize / 2,
			width: glyphSize, height: glyphSize
		))
	}

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


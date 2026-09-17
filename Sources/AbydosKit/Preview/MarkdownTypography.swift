import Foundation

/// The proportions a rendered markdown page is set in, from one body size.
///
/// Every number here is a multiple of the body, and the body is the one thing
/// the app decides — so the preview follows the interface's zoom the way every
/// control does, and a heading is twice the body at every zoom rather than 24
/// points at all of them, which is what it was. The proportions are GitHub's
/// stylesheet's, read as ratios: 16 px at a line height of 1.5, headings at
/// 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85, code at 85 % on a panel padded by one
/// body height. Only the ratios were taken; the palette is the theme's — the
/// panel is the theme's own `currentLineBackground`, the one surface every
/// theme already made for coloured code to sit on. A blend of the page toward
/// the text was tried first and put forty syntax kinds of the shipped themes
/// under their contrast floor, because the themes are calibrated to the page.
public struct MarkdownTypography: Equatable, Sendable {
	/// The size prose is set at, in points, already scaled by the zoom.
	public let body: Double

	public init(body: Double) {
		self.body = body
	}

	/// A heading's size, for levels one to six; anything past six is six.
	public func heading(_ level: Int) -> Double {
		let ratios: [Double] = [2, 1.5, 1.25, 1, 0.875, 0.85]
		return body * ratios[max(0, min(level - 1, ratios.count - 1))]
	}

	/// Code, fenced or inline, is set smaller than prose: a monospace face at
	/// the body size looks larger than the body, and every rendered page
	/// corrects for it.
	public var code: Double { body * 0.85 }

	/// The line a body paragraph is set on, top to top.
	public var lineHeight: Double { body * 1.5 }
	/// Code is set tighter, so a block reads as a block.
	public var codeLineHeight: Double { code * 1.45 }

	/// Between two paragraphs: a body height, which is a line's worth of air.
	public var paragraphSpacing: Double { body }
	/// A heading has more above it than below, so it belongs to what follows.
	public var headingSpaceAbove: Double { body * 1.5 }
	public var headingSpaceBelow: Double { body }
	/// Between a level one or two heading and the rule drawn under it.
	public var headingRulePadding: Double { body * 0.3 }

	/// Inside a code panel, on every edge.
	public var panelPadding: Double { body }
	/// Around inline code, beside and above the letters.
	public var pillPaddingX: Double { code * 0.25 }
	public var pillPaddingY: Double { code * 0.15 }
	/// A panel's and a pill's corners; six on a sixteen body.
	public var cornerRadius: Double { body * 0.375 }

	/// One level of list, and the width a marker hangs in.
	public var listIndent: Double { body * 2 }
	/// Between the items of a list, which sit closer than paragraphs do.
	public var listItemSpacing: Double { body * 0.25 }
	/// A block quote's bar down its left edge, and the room beside it.
	public var quoteBar: Double { body * 0.25 }
	public var quotePadding: Double { body }
	/// A thematic break's thickness and the air either side of it.
	public var ruleHeight: Double { body * 0.25 }
	public var ruleSpace: Double { body * 1.5 }

	/// The page's own margins: the side is wider than the top, as on paper.
	public var insetX: Double { body * 2 }
	public var insetY: Double { body * 1.5 }
}

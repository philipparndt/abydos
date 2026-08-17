import CoreGraphics

/// Where a pane has to scroll to put a place in a document on screen, whether it
/// has to at all, and whether it is in a state to be asked.
///
/// The three answers are the three faults of item 533, and they are separated
/// here because none of them is about a view:
///
/// - **`notLaidOut`.** Every number below is measured against the viewport, and a
///   pane that has not been given its size measures to nonsense: centring on a
///   height of zero puts the line at the very top, and a wrap layout built for a
///   width of zero puts it on the wrong row entirely. A caller that gets this
///   answer must not scroll — it has nothing to scroll *to* — and must ask again
///   once the pane has a size. Asking one turn of the main loop later is not the
///   same thing as asking a pane that has been laid out, which is the bug this
///   answer exists to make impossible to write.
/// - **`stay`.** Somewhere already on screen is shown by leaving the view alone.
///   Walking a file's search results re-centred on every step, which moves the
///   text under the eyes of whoever is reading it for no gain.
/// - **`scroll`.** Both axes, together. The horizontal offset used to be forced
///   to zero on every reveal, so a match far along a long line was scrolled off
///   the side by construction, however long layout had had.
///
/// Not "scroll to the column": a match eighty characters in should not push the
/// start of its line off the left edge for no reason. The rule is the one every
/// editor has — bring it inside the pane with a little context, and leave the
/// offset where it is when it is already inside.
public enum RevealScroll {
	/// The pane as it is at the moment the question is asked.
	///
	/// All in the document view's coordinates, which are flipped: `y` grows
	/// downwards and a point is the *top* of its line.
	public struct Pane: Equatable, Sendable {
		/// What the clip view shows of the document.
		public var size: CGSize
		/// What it is scrolled to now. The answer is built from this rather than
		/// from nothing, which is what makes leaving an axis alone expressible.
		public var offset: CGPoint
		/// The document view's whole size, so no answer asks for an offset past
		/// the end of it.
		public var documentSize: CGSize
		/// The band down the left that the gutter draws over.
		///
		/// It is pinned to the viewport rather than to the text, so it covers the
		/// leftmost `gutterWidth` of whatever is scrolled under it: a point is
		/// only really visible when it is to the right of `offset.x +
		/// gutterWidth`, which is why this is part of the question.
		public var gutterWidth: CGFloat
		public var lineHeight: CGFloat
		public var characterWidth: CGFloat
		/// Whether soft wrap is on. Wrapped text is exactly as wide as the
		/// viewport, so there is no sideways answer to give and the offset
		/// belongs at zero.
		public var wraps: Bool

		public init(
			size: CGSize,
			offset: CGPoint,
			documentSize: CGSize,
			gutterWidth: CGFloat,
			lineHeight: CGFloat,
			characterWidth: CGFloat,
			wraps: Bool
		) {
			self.size = size
			self.offset = offset
			self.documentSize = documentSize
			self.gutterWidth = gutterWidth
			self.lineHeight = lineHeight
			self.characterWidth = characterWidth
			self.wraps = wraps
		}
	}

	/// What to do about a point that should be on screen.
	public enum Answer: Equatable, Sendable {
		/// There is nothing to measure against yet. Remember the request and ask
		/// again when the pane has been given a size.
		case notLaidOut
		/// It is on screen. Moving the view would be the fault, not the fix.
		case stay
		/// Scroll the clip view here.
		case scroll(CGPoint)
	}

	/// Rows of the pane a point may not be within and still count as visible.
	///
	/// One at the top and two at the bottom, and the asymmetry is because a point
	/// is the top of its line: a line whose top is one row above the bottom edge
	/// is half cut off, and the row under it is where the next ↓ goes.
	public static let rowsAboveTheBand: CGFloat = 1
	public static let rowsBelowTheBand: CGFloat = 2
	/// Columns of context left beside a point that has to be brought in
	/// sideways, so a match does not land against the edge it came from.
	///
	/// Sixteen rather than a handful because the point is the *start* of what
	/// somebody wants to read: eight columns left `public` itself on screen with
	/// two columns to spare and the word after it cut in half, which is visible
	/// and still not readable.
	public static let columnsOfContext: CGFloat = 16

	/// Where the clip view belongs so `point` is on screen.
	public static func answer(bringing point: CGPoint, onScreenIn pane: Pane) -> Answer {
		// A row height of zero is a view that has not measured its font, and a
		// pane narrower than its own gutter has no text column at all. Both are
		// states a fresh pane passes through.
		guard pane.lineHeight > 0, pane.characterWidth > 0 else { return .notLaidOut }
		guard pane.size.height >= pane.lineHeight, pane.size.width > pane.gutterWidth else {
			return .notLaidOut
		}
		// The document view is never shorter than the viewport — a short file
		// fills the pane so a click under the last line lands in the text — so a
		// document that *is* shorter is one whose frame has not caught up with
		// the size the pane has just been given. Its rows are in the wrong place
		// and centring on one of them is centring on the wrong line.
		guard pane.documentSize.height + 0.5 >= pane.size.height else { return .notLaidOut }

		var wanted = pane.offset

		let top = pane.offset.y
		let bottom = top + pane.size.height
		if point.y < top + pane.lineHeight * rowsAboveTheBand
			|| point.y > bottom - pane.lineHeight * rowsBelowTheBand {
			// Centred rather than merely brought in, so there is context around
			// what was jumped to — but only when it has to move at all.
			wanted.y = point.y - pane.size.height / 2
		}

		if pane.wraps {
			wanted.x = 0
		} else {
			let context = pane.characterWidth * columnsOfContext
			// The gutter's edge, not the pane's: text under the gutter is text
			// nobody can read.
			let left = pane.offset.x + pane.gutterWidth
			let right = pane.offset.x + pane.size.width
			if point.x < left {
				wanted.x = point.x - pane.gutterWidth - context
			} else if point.x > right - pane.characterWidth {
				wanted.x = point.x + context + pane.characterWidth - pane.size.width
			}
		}

		wanted.x = min(max(0, wanted.x), max(0, pane.documentSize.width - pane.size.width))
		wanted.y = min(max(0, wanted.y), max(0, pane.documentSize.height - pane.size.height))

		guard abs(wanted.x - pane.offset.x) > 0.5 || abs(wanted.y - pane.offset.y) > 0.5 else {
			return .stay
		}
		return .scroll(wanted)
	}
}

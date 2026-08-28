import Foundation

/// The other places a selection's own text appears.
///
/// "Where else is this" is asked constantly while reading code, and until this
/// existed the two answers both cost more than the question: ⌘F takes the
/// keyboard, needs the query seeded and throws its answer away on ⎋, and Find in
/// Project answers a broader question as a list of rows at the bottom of the
/// window. Neither is worth it for "twice more, both on screen".
///
/// Deliberately about characters and not about symbols. Selecting `count` lights
/// the `count` inside `accountId`, which is the chosen behaviour: a rule that lit
/// only whole words would highlight nothing at all for `x + y` or `unt`, and a
/// feature that does nothing for half the selections somebody makes is one nobody
/// relies on. What a *symbol's* uses are is the language server's answer and has
/// a verb of its own.
public enum SelectionOccurrences {
	/// Whether a selection is one worth answering at all.
	///
	/// Three refusals, each with a screen of noise behind it. One character would
	/// band every `e` on the page — and the answer to "where else is `e`" is
	/// "everywhere", which is not information. A selection crossing lines is a
	/// block being moved rather than a thing being looked up. A run of spaces is
	/// an indent, and every indent in the file lighting up is the same noise as
	/// `e` with more of it.
	///
	/// Counted in characters rather than UTF-16 units, because two is a number
	/// about what somebody dragged over and not about how it is stored.
	public static func isWorthHighlighting(_ selection: String) -> Bool {
		guard selection.count >= 2 else { return false }
		guard !selection.contains(where: \.isNewline) else { return false }
		return !selection.allSatisfy(\.isWhitespace)
	}

	/// Where the selection's text appears, in file order, as UTF-16 ranges.
	///
	/// Ranges rather than `SearchMatch`: what the bands need is offsets, and
	/// building a line's text for each of five thousand hits is work nothing
	/// reads.
	///
	/// Literal and case-sensitive — `Count` selected does not answer with
	/// `count`. A selection is exactly the characters somebody dragged over, and
	/// a highlight that quietly matched more than that would be claiming an
	/// identity the text does not have. `.literal` is also the fast comparison:
	/// no canonical decomposition, which is both what a code editor means by
	/// "the same characters" and what makes this cheap enough to run on every
	/// selection.
	///
	/// - Parameter selected: the selection's own range, which is not one of the
	///   *other* places. What is selected is already said by the selection, and a
	///   band over it would be a second claim covering a louder one.
	public static func ranges(
		of selection: String,
		in text: String,
		excluding selected: Range<Int>? = nil,
		limit: Int = TextSearch.matchLimit
	) -> [Range<Int>] {
		guard isWorthHighlighting(selection) else { return [] }

		let haystack = text as NSString
		let needle = selection as NSString
		guard needle.length > 0, haystack.length >= needle.length else { return [] }

		var found: [Range<Int>] = []
		var from = 0
		while from <= haystack.length - needle.length, found.count < limit {
			let searched = NSRange(location: from, length: haystack.length - from)
			let hit = haystack.range(of: selection, options: [.literal], range: searched)
			guard hit.location != NSNotFound else { break }

			let range = hit.location..<(hit.location + hit.length)
			if range != selected { found.append(range) }
			// Past the start of this one rather than past its end: overlapping
			// occurrences are occurrences. `aa` appears three times in `aaaa`,
			// and a scan that stepped over each hit would report two.
			from = hit.location + 1
		}
		return found
	}
}

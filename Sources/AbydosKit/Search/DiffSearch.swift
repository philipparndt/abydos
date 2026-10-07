import Foundation

/// Finds a query in the lines of a diff, one line at a time.
///
/// **The lines a caller hands in are the whole of what a diff search means**:
/// the code of each line without git's `+`, `-` or space in front of it, and
/// none of the furniture around it — hunk headers, the scope git guesses, the
/// preamble, the remarks drawn under lines. Which rows those are is the view's
/// business; what counts as a match in them is decided here, where it can be
/// tested without a window.
///
/// **One pattern, matched line by line**, rather than `TextSearch` over the
/// lines joined with newlines. The joined text would hand back a line number to
/// map back to a row, through `TextSearch`'s own idea of where lines break — and
/// a code line holding a lone `\r`, which a diff of a CRLF file does, would
/// shift every row after it. Per line, a match cannot span two rows whatever
/// the pattern says, which is the rule a file searched line by line keeps. The
/// pattern itself is `TextSearch`'s, so case, whole word and regular expression
/// mean exactly what they mean in the editor.
public enum DiffSearch {
	/// One match: which of the given lines, and where in it.
	public struct Hit: Equatable, Sendable {
		/// Index into the lines handed to `matches`.
		public var line: Int
		/// UTF-16 range within that line, which is what the view selects with.
		public var utf16Range: Range<Int>

		public init(line: Int, utf16Range: Range<Int>) {
			self.line = line
			self.utf16Range = utf16Range
		}
	}

	/// Every match of `query` in `lines`, in order, at most
	/// `TextSearch.matchLimit` of them.
	///
	/// A match of no characters is dropped even for a regular expression: it
	/// can be neither marked nor selected, and `^` finding every line is a count
	/// nobody asked for.
	public static func matches(in lines: [String], query: String, options: SearchOptions) -> [Hit] {
		guard !query.isEmpty, let regex = TextSearch.makeRegex(query: query, options: options) else {
			return []
		}
		var hits: [Hit] = []
		for (index, line) in lines.enumerated() where !line.isEmpty {
			let length = (line as NSString).length
			var full = false
			regex.enumerateMatches(in: line, range: NSRange(location: 0, length: length)) { match, _, stop in
				guard let match, match.range.length > 0 else { return }
				hits.append(Hit(
					line: index,
					utf16Range: match.range.location..<(match.range.location + match.range.length)
				))
				if hits.count >= TextSearch.matchLimit {
					full = true
					stop.pointee = true
				}
			}
			if full { break }
		}
		return hits
	}
}

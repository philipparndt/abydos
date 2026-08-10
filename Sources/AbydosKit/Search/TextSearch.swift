import Foundation

/// Hashable rather than only equatable because `SearchChecklist` keys the marks
/// somebody has ticked off by the whole question, and the options are half of
/// what a question is.
public struct SearchOptions: Hashable, Sendable {
	public var caseSensitive: Bool
	public var wholeWord: Bool
	public var isRegex: Bool

	public init(caseSensitive: Bool = false, wholeWord: Bool = false, isRegex: Bool = false) {
		self.caseSensitive = caseSensitive
		self.wholeWord = wholeWord
		self.isRegex = isRegex
	}
}

/// One hit, in the units the editor needs.
public struct SearchMatch: Equatable, Sendable {
	/// UTF-16 range, which is what the view selects with.
	public var utf16Range: Range<Int>
	/// 0-based line the match starts on.
	public var line: Int
	/// The whole line, for previewing results.
	public var lineText: String

	public init(utf16Range: Range<Int>, line: Int, lineText: String) {
		self.utf16Range = utf16Range
		self.line = line
		self.lineText = lineText
	}
}

/// Finds matches in text.
///
/// Searching is inherently a linear scan, so the work is in doing it once per
/// query rather than once per keystroke — callers debounce — and in returning
/// UTF-16 ranges directly, so the editor never has to re-map offsets.
public enum TextSearch {
	/// Upper bound on results, so a query like `.` on a large file cannot lock
	/// the UI building millions of matches nobody will scroll through.
	public static let matchLimit = 5_000

	public static func matches(in text: String, query: String, options: SearchOptions) -> [SearchMatch] {
		guard !query.isEmpty else { return [] }

		let ns = text as NSString
		guard let regex = makeRegex(query: query, options: options) else { return [] }

		var results: [SearchMatch] = []
		// Line starts are computed once and binary-searched, rather than counting
		// newlines again for every match.
		let lineStarts = lineStartOffsets(in: ns)

		regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, stop in
			guard let match, match.range.length > 0 || options.isRegex else { return }
			let line = lineIndex(for: match.range.location, in: lineStarts)
			let lineStart = lineStarts[line]
			let lineEnd = line + 1 < lineStarts.count ? lineStarts[line + 1] : ns.length
			let lineText = ns.substring(with: NSRange(location: lineStart, length: max(0, lineEnd - lineStart)))

			results.append(SearchMatch(
				utf16Range: match.range.location..<(match.range.location + match.range.length),
				line: line,
				lineText: lineText.trimmingCharacters(in: .newlines)
			))
			if results.count >= matchLimit { stop.pointee = true }
		}
		return results
	}

	public static func matches(in rope: Rope, query: String, options: SearchOptions) -> [SearchMatch] {
		matches(in: rope.string, query: query, options: options)
	}

	/// Builds the regex a query implies.
	///
	/// A literal query is escaped rather than special-cased, so whole-word and
	/// case handling work identically for literal and regex searches.
	static func makeRegex(query: String, options: SearchOptions) -> NSRegularExpression? {
		var pattern = options.isRegex ? query : NSRegularExpression.escapedPattern(for: query)
		if options.wholeWord {
			pattern = "\\b(?:\(pattern))\\b"
		}
		var regexOptions: NSRegularExpression.Options = []
		if !options.caseSensitive { regexOptions.insert(.caseInsensitive) }
		return try? NSRegularExpression(pattern: pattern, options: regexOptions)
	}

	/// True when a regex query compiles — used to mark the field invalid rather
	/// than silently returning nothing.
	public static func isValid(query: String, options: SearchOptions) -> Bool {
		guard !query.isEmpty else { return true }
		return makeRegex(query: query, options: options) != nil
	}

	// MARK: - Line lookup

	static func lineStartOffsets(in text: NSString) -> [Int] {
		var starts = [0]
		text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
			let next = enclosing.location + enclosing.length
			if next < text.length { starts.append(next) }
		}
		return starts
	}

	static func lineIndex(for offset: Int, in lineStarts: [Int]) -> Int {
		var low = 0
		var high = lineStarts.count - 1
		while low < high {
			let mid = (low + high + 1) / 2
			if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
		}
		return low
	}
}

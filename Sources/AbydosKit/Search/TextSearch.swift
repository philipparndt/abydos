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
	/// 0-based UTF-16 column the match starts at on its line.
	///
	/// Carried because a line is not a place. A match two hundred characters along
	/// a long line is off the side of the editor's pane, and something handed only
	/// the line has no way to know it — which is half of item 533. Worked out
	/// where the line's own start offset is already in hand, rather than by going
	/// looking for it again later.
	public var column: Int

	public init(utf16Range: Range<Int>, line: Int, lineText: String, column: Int = 0) {
		self.utf16Range = utf16Range
		self.line = line
		self.lineText = lineText
		self.column = column
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
				lineText: lineText.trimmingCharacters(in: .newlines),
				column: match.range.location - lineStart
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

	// MARK: - Replacing

	/// One edit that puts a whole Replace All into the file.
	///
	/// A span and the text it becomes, rather than a list of replacements: the
	/// editor makes one edit of it, so two hundred matches are one entry in the
	/// undo history and one reparse, instead of two hundred of each.
	public struct ReplaceAll: Equatable, Sendable {
		/// From the first match's start to the last match's end. What lies
		/// between them that did not match is carried through untouched — the
		/// span is the smallest one edit can cover, not a rewrite of the file.
		public var utf16Range: Range<Int>
		public var text: String
		/// How many matches were replaced, for saying so.
		public var count: Int

		public init(utf16Range: Range<Int>, text: String, count: Int) {
			self.utf16Range = utf16Range
			self.text = text
			self.count = count
		}
	}

	/// What one match becomes, or nil when it cannot become anything.
	///
	/// Nil for a pattern that will not compile, a range that is not a match of it
	/// after all — the text has moved since the match was found — or a template
	/// that names a capture the pattern does not have. Every one of those is a
	/// case where writing *something* would be worse than writing nothing.
	public static func replacement(
		forMatchAt utf16Range: Range<Int>,
		in text: String,
		query: String,
		options: SearchOptions,
		template: String
	) -> String? {
		guard !query.isEmpty, let regex = makeRegex(query: query, options: options) else { return nil }
		// A literal search takes a literal replacement: what somebody typed goes
		// into the file as itself, `$1` included. Templates are the regex
		// engine's language, and offering them for a search that is not one would
		// mean a dollar could not be typed.
		guard options.isRegex else { return template }
		guard isUsable(template: template, with: regex) else { return nil }

		let ns = text as NSString
		guard utf16Range.lowerBound >= 0, utf16Range.upperBound <= ns.length else { return nil }
		let range = NSRange(location: utf16Range.lowerBound, length: utf16Range.count)
		// Anchored, and the whole range or nothing: this is being asked about a
		// match somebody is looking at, and a pattern that now matches something
		// shorter is not that match.
		guard let match = regex.firstMatch(in: text, options: [.anchored], range: range),
		      match.range == range
		else { return nil }
		return regex.replacementString(for: match, in: text, offset: 0, template: template)
	}

	/// The single edit that replaces every match, or nil when there are none.
	///
	/// **Every match, and not the first `matchLimit` of them.** The cap exists so
	/// that a query like `.` cannot build millions of `SearchMatch` values for a
	/// list nobody will scroll; a Replace All builds none of them, and one that
	/// quietly stopped five thousand in would leave a file half-changed with
	/// nothing said about the other half.
	public static func replaceAll(
		in text: String,
		query: String,
		options: SearchOptions,
		template: String
	) -> ReplaceAll? {
		guard !query.isEmpty, let regex = makeRegex(query: query, options: options) else { return nil }
		guard !options.isRegex || isUsable(template: template, with: regex) else { return nil }

		let ns = text as NSString
		var replaced = ""
		var start: Int?
		var cursor = 0
		var count = 0

		regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
			// The same guard the search keeps, so what is replaced is what was
			// counted: a zero-length match is a thing only a regex can find.
			guard let match, match.range.length > 0 || options.isRegex else { return }
			if start == nil {
				start = match.range.location
				cursor = match.range.location
			}
			replaced += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
			replaced += options.isRegex
				? regex.replacementString(for: match, in: text, offset: 0, template: template)
				: template
			cursor = NSMaxRange(match.range)
			count += 1
		}

		guard let first = start, count > 0 else { return nil }
		return ReplaceAll(utf16Range: first..<cursor, text: replaced, count: count)
	}

	/// Whether a replacement can be used with a query, the way `isValid` asks
	/// whether the query itself can be.
	///
	/// A query that will not compile answers true here: its own error is already
	/// being reported, and two complaints about one broken thing send somebody
	/// looking for a second problem.
	public static func isValid(template: String, query: String, options: SearchOptions) -> Bool {
		guard options.isRegex, !query.isEmpty else { return true }
		guard let regex = makeRegex(query: query, options: options) else { return true }
		return isUsable(template: template, with: regex)
	}

	/// Whether every `$n` in a template names a group the pattern has.
	///
	/// **Foundation does not check this and does not complain.** Measured:
	/// `$7` against a pattern with two capture groups returns the empty string,
	/// so a Replace All with a mistyped number silently deletes every match
	/// rather than refusing.
	///
	/// The digits are read the way ICU reads them — greedily, while the number
	/// still names a group — so `$12` against two groups is group 1 followed by
	/// a literal `2`, which is what `replacementString` does with it. A first
	/// digit that already names no group is the mistake worth catching.
	static func isUsable(template: String, with regex: NSRegularExpression) -> Bool {
		let groups = regex.numberOfCaptureGroups
		let characters = Array(template)
		var index = 0

		while index < characters.count {
			// A backslash makes the next character literal, `\$` included.
			guard characters[index] != "\\" else {
				index += 2
				continue
			}
			guard characters[index] == "$" else {
				index += 1
				continue
			}
			index += 1
			// A dollar with no digit after it is a dollar.
			guard index < characters.count, let first = digit(characters[index]) else { continue }
			guard first <= groups else { return false }

			var number = first
			index += 1
			while index < characters.count, let next = digit(characters[index]) {
				let extended = number * 10 + next
				guard extended <= groups else { break }
				number = extended
				index += 1
			}
		}
		return true
	}

	/// An ASCII digit's value, and nothing else's: `٣` is a number to
	/// `wholeNumberValue` and is not a group reference.
	private static func digit(_ character: Character) -> Int? {
		guard character.isASCII, character.isNumber else { return nil }
		return character.wholeNumberValue
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

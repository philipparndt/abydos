import Foundation

/// Replacing what the project search found, one file at a time.
///
/// The find bar replaces in a buffer it can see; the search pane cannot see
/// the files its rows point into, and that is the whole difficulty. A row is a
/// UTF-16 range into the file *as it was read*: a tab typed in since, a
/// formatter, a file saved by another program — every one of them moves the
/// offsets, and an edit at a stale offset replaces the wrong text with no way
/// of knowing it did.
///
/// So nothing here replaces at the range a row holds. The file's current text
/// is searched again, and the rows chosen are found in it by their
/// `SearchChecklist.Mark` — the path, the matched line's trimmed text, and
/// which of the identical lines it is — which is the key the ticks already use
/// because it survives the file being edited around it. A match that has moved
/// is still replaced; a match that is gone is reported as not found and nothing
/// is written in its place.
///
/// One edit per file, from the first replaced match to the last, with the text
/// between them and any match that was not chosen carried through byte for
/// byte. That is `TextSearch.replaceAll` with a filter, and it is what makes
/// two hundred replacements one entry in a tab's undo history rather than two
/// hundred.
public enum ProjectReplace {
	/// What one file's replacement comes to.
	public struct Outcome: Equatable, Sendable {
		/// The one edit, or `nil` when nothing in the file was chosen and found.
		public let edit: TextSearch.ReplaceAll?
		/// How many matches the edit replaces.
		public var replaced: Int { edit?.count ?? 0 }
		/// The chosen marks that were not in the file's current text.
		public let notFound: [SearchChecklist.Mark]

		public init(edit: TextSearch.ReplaceAll?, notFound: [SearchChecklist.Mark]) {
			self.edit = edit
			self.notFound = notFound
		}
	}

	/// The edit that replaces the chosen rows in a file as it is now.
	///
	/// - Parameters:
	///   - text: the file's current text — a document's rope where the file is
	///     open, the bytes on disk where it is not.
	///   - path: the file's path relative to the search root, which is what a
	///     mark names.
	///   - choosing: the marks to replace, or `nil` for every match in the
	///     file. Marks naming other files are ignored rather than reported.
	public static func edit(
		in text: String,
		path: String,
		question: SearchChecklist.Question,
		template: String,
		choosing chosen: Set<SearchChecklist.Mark>?
	) -> Outcome {
		let query = question.query
		let options = question.options
		guard let chosen else {
			let edit = TextSearch.replaceAll(in: text, query: query, options: options, template: template)
			return Outcome(edit: edit, notFound: [])
		}

		let wanted = chosen.filter { $0.path == path }
		guard !wanted.isEmpty else { return Outcome(edit: nil, notFound: []) }

		// The marks of the text as it is now, in the order the matches come, so
		// an index into one is an index into the other — and into the regex
		// enumeration `replaceAll` runs, which keeps the same order and the same
		// zero-length guard.
		let matches = TextSearch.matches(in: text, query: query, options: options)
		let result = FileSearchResult(url: URL(fileURLWithPath: path), relativePath: path, matches: matches)
		let marks = SearchChecklist.marks(for: result)

		var kept: Set<Int> = []
		var found: Set<SearchChecklist.Mark> = []
		for (index, mark) in marks.enumerated() where wanted.contains(mark) {
			kept.insert(index)
			found.insert(mark)
		}
		let notFound = wanted.subtracting(found).sorted { ($0.text, $0.occurrence) < ($1.text, $1.occurrence) }
		guard !kept.isEmpty else { return Outcome(edit: nil, notFound: notFound) }

		let edit = TextSearch.replaceAll(
			in: text, query: query, options: options, template: template,
			keeping: { kept.contains($0) }
		)
		return Outcome(edit: edit, notFound: notFound)
	}

	// MARK: - Taking it back

	/// What one replacement did, so that one ⌘Z can take all of it back.
	///
	/// Per file the span's range and its text before and after, rather than a
	/// copy of the file: five hundred files at four megabytes is the worst case
	/// the search permits, and a span is a few hundred bytes. Whether the file
	/// was open is kept because undoing goes back the way the edit came — through
	/// the document if it was open, to disk if it was not.
	public struct Record: Equatable, Sendable {
		public struct File: Equatable, Sendable {
			public let url: URL
			public let relativePath: String
			/// Where the span started, which an undo and a redo share.
			public let start: Int
			public let before: String
			public let after: String
			public let wasOpen: Bool

			public init(url: URL, relativePath: String, start: Int, before: String, after: String, wasOpen: Bool) {
				self.url = url
				self.relativePath = relativePath
				self.start = start
				self.before = before
				self.after = after
				self.wasOpen = wasOpen
			}
		}

		public var files: [File]
		public var replaced: Int
		public var notFound: Int

		public init(files: [File] = [], replaced: Int = 0, notFound: Int = 0) {
			self.files = files
			self.replaced = replaced
			self.notFound = notFound
		}

		public var fileCount: Int { files.count }
	}

	/// The edit that puts one file's span back, or `nil` when the span no longer
	/// reads what the replacement left there — the file has been changed since,
	/// and a blind write would take somebody's edit with it.
	///
	/// `forward` false is an undo: the span now reads `after` and becomes
	/// `before`. True is a redo, the other way round.
	public static func reversal(
		of file: Record.File, in text: String, forward: Bool
	) -> TextSearch.ReplaceAll? {
		let expected = forward ? file.before : file.after
		let becoming = forward ? file.after : file.before
		let ns = text as NSString
		let length = (expected as NSString).length
		guard file.start >= 0, file.start + length <= ns.length else { return nil }
		let range = NSRange(location: file.start, length: length)
		guard ns.substring(with: range) == expected else { return nil }
		return TextSearch.ReplaceAll(utf16Range: file.start..<(file.start + length), text: becoming, count: 1)
	}

	// MARK: - Files that are not open

	/// A file's text, by the tests the search itself applies: a NUL in the
	/// first eight kilobytes is binary, and anything that is not UTF-8 is not
	/// searched and so is not replaced in.
	public static func readText(at url: URL) -> String? {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
		if data.prefix(8_000).contains(0) { return nil }
		return String(data: data, encoding: .utf8)
	}

	/// The text with one edit applied, which is what goes back to disk.
	public static func applying(_ edit: TextSearch.ReplaceAll, to text: String) -> String {
		let ns = text as NSString
		let range = NSRange(location: edit.utf16Range.lowerBound, length: edit.utf16Range.count)
		return ns.replacingCharacters(in: range, with: edit.text)
	}

	/// Written atomically, as a document's save is: a temporary file and a
	/// rename, so a crash mid-write leaves the old file rather than half of the
	/// new one.
	public static func write(_ text: String, to url: URL) throws {
		try Data(text.utf8).write(to: url, options: .atomic)
	}
}

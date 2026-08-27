import Foundation

/// Which search results somebody has already looked at.
///
/// A project-wide search answers with more than fits on a screen, and going
/// through it is a job: open one, decide, move on. Nothing held *which ones had
/// been dealt with*, so the list looked the same after an hour as it did at the
/// start and the only record of the progress was in somebody's head.
///
/// Kept out of the view, like `FileUndo`, because the interesting part is not
/// the drawing: it is what a mark is keyed on, and that is a decision with
/// several wrong answers that a window cannot be asked about.
///
/// ## What a mark is keyed on, and why not the line number
///
/// The feature is only worth having if a mark survives the search being run
/// again. Working through two hundred matches takes long enough that it will
/// be: a file gets edited, the tree reloads, ⇧⌘F is pressed a second time with
/// the same term. If the marks are forgotten each time then the list only helps
/// within one uninterrupted sitting, which is not the job.
///
/// So they are remembered — against the file, the text of the matched line, and
/// which of the identical lines in that file it is. Not against the line
/// number, which goes stale the moment anything is inserted above it, and
/// inserting things above matches is exactly what somebody working through a
/// result list does. The matched *text* moves with the line.
///
/// The occurrence count is what stops `return nil` — twenty of them in one file
/// — from ticking all twenty when one is ticked. It counts only among lines
/// whose text is identical, so it is unmoved by every edit that does not add
/// another copy of that same line above the marked one. That last case does get
/// it wrong: the tick lands on the first of two identical lines rather than the
/// second. Two lines that are character-for-character the same under the same
/// query are as near indistinguishable as the list can make them, and the
/// alternative — a line number — is wrong far more often.
///
/// Leading and trailing whitespace is off the key, so re-indenting a file (a
/// formatter run, a block wrapped in an `if`) does not lose every mark in it.
///
/// ## Why the marks are per question and not per project
///
/// Two searches for different things over the same file are different
/// questions, and having answered one is not having answered the other. A line
/// holding both `TODO` and `FIXME` would otherwise arrive already ticked under
/// the second search, and a row that says "looked at" when nobody looked at it
/// is the one failure this must not have.
///
/// The options are part of the question for the same reason: turning `.*` on
/// changes what the term means. Nothing is thrown away when they change, so
/// turning an option back off brings the marks back with it — an accidental
/// click on `Aa` costs nothing.
///
/// ## What a tick is, and where it lives now
///
/// The ticking itself is `Checklist`, which is shared with the pull request
/// page's list of files. What is here is the *question* a set of ticks belongs
/// to; what is there is a tick and the token it may one day be cleared by. A
/// search passes no token and so nothing it ticks is ever invalidated, which is
/// exactly how this behaved before tokens existed.
public struct SearchChecklist: Equatable, Sendable {
	/// The search a set of marks belongs to.
	public struct Question: Hashable, Sendable {
		public let query: String
		public let options: SearchOptions

		public init(query: String, options: SearchOptions) {
			self.query = query
			self.options = options
		}
	}

	/// One match, named in a way that survives the file being edited around it.
	public struct Mark: Hashable, Sendable {
		/// Path relative to the search root — the same string the row shows, so
		/// a mark can be read in a debugger without a lookup.
		public let path: String
		/// The matched line, trimmed at both ends.
		public let text: String
		/// Which of the lines in this file with exactly this text it is,
		/// counting from zero in file order.
		public let occurrence: Int

		public init(path: String, text: String, occurrence: Int) {
			self.path = path
			self.text = text
			self.occurrence = occurrence
		}
	}

	/// One checklist per question. `Checklist` is where a tick lives and where
	/// the token that may one day clear it lives; this type is what says a tick
	/// belongs to *this* search rather than to another.
	private var lists: [Question: Checklist<Mark>] = [:]

	public init() {}

	/// The marks for one file's matches, in the same order as `result.matches`,
	/// so a row can be paired with its mark by index.
	///
	/// One pass and one dictionary per file rather than a scan per match: a
	/// large search rebuilds these for every batch that streams in, and a
	/// quadratic count over a file with five thousand hits in it would be felt.
	public static func marks(for result: FileSearchResult) -> [Mark] {
		var seen: [String: Int] = [:]
		var marks: [Mark] = []
		marks.reserveCapacity(result.matches.count)
		for match in result.matches {
			let text = match.lineText.trimmingCharacters(in: .whitespaces)
			let occurrence = seen[text, default: 0]
			seen[text] = occurrence + 1
			marks.append(Mark(path: result.relativePath, text: text, occurrence: occurrence))
		}
		return marks
	}

	public func isDone(_ mark: Mark, for question: Question) -> Bool {
		lists[question]?.isDone(mark) ?? false
	}

	/// Every mark held for one question, which is what an undo puts back.
	public func marks(for question: Question) -> Set<Mark> {
		lists[question]?.subjects ?? []
	}

	/// Marks or unmarks a batch, and answers with the set as it was before.
	///
	/// The whole previous set rather than a diff, because that is what ⌘Z needs
	/// and it is small: a set of marks is a few dozen short strings even after a
	/// long session, and there is nothing here worth being clever about.
	/// - Parameter tokens: what each tick is about, for a list that can say —
	///   see `Checklist`. A search gives none, and nothing it ticks is ever
	///   invalidated, which is exactly how it behaved before tokens existed.
	@discardableResult
	public mutating func set(
		_ marks: [Mark],
		done isDone: Bool,
		for question: Question,
		tokens: [Mark: String] = [:]
	) -> Set<Mark> {
		var list = lists[question] ?? Checklist<Mark>()
		let previous = list.set(marks, done: isDone, tokens: tokens)
		// An empty list is dropped rather than kept, so a question somebody
		// unticked entirely does not sit in here for the life of the window.
		lists[question] = list.isEmpty ? nil : list
		return previous
	}

	/// Puts a whole question's marks back as they were, for ⌘Z.
	public mutating func restore(_ marks: Set<Mark>, for question: Question) {
		guard !marks.isEmpty else {
			lists[question] = nil
			return
		}
		var list = lists[question] ?? Checklist<Mark>()
		list.restore(marks)
		lists[question] = list
	}

	/// Clears the ticks of one question whose subject has since changed.
	///
	/// - Returns: the marks whose ticks were cleared. Empty for a list that
	///   passed no tokens, which is every list this type has today — the
	///   capability is here because `Checklist` is shared with a list that does.
	@discardableResult
	public mutating func revalidate(
		_ current: [Mark: String], for question: Question
	) -> Set<Mark> {
		guard var list = lists[question] else { return [] }
		let cleared = list.revalidate(against: current)
		guard !cleared.isEmpty else { return [] }
		lists[question] = list.isEmpty ? nil : list
		return cleared
	}

	/// How many of the matches now showing are marked done.
	///
	/// Counted against the results rather than read off the stored set, because
	/// the stored set can hold marks for lines that no longer match — the file
	/// was edited, the term was narrowed — and "12 of 9 done" is worse than no
	/// number at all.
	public func doneCount(in results: [FileSearchResult], for question: Question) -> Int {
		guard let held = lists[question], !held.isEmpty else { return 0 }
		var count = 0
		for result in results {
			for mark in Self.marks(for: result) where held.isDone(mark) { count += 1 }
		}
		return count
	}
}

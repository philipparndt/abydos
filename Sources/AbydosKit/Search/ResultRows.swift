import Foundation

/// The flattened rows of a results checklist — a file heading, then the matches
/// under it — together with the counts a status line reads.
///
/// This is the half of the search and usages panes that a window is not needed
/// for, and it is here rather than in the view because item 519 is the item
/// about it: the pane rebuilt every row it already had on every batch that
/// streamed in, and 440 000 matches over a one-character query left the main
/// thread dead for seven seconds at a stretch. What was wrong is not a drawing
/// decision — `sample` put the table's `reloadData` at 7 samples in 6866 — it is
/// *what the rebuild costs and how often it is asked for*, which is arithmetic
/// over arrays, which is a thing with a test.
///
/// ## Appending is not rebuilding
///
/// `append` is O(what arrived). Marks are computed once per file, when the file
/// first comes in, and kept beside the results — so a rebuild for a reason that
/// has nothing to do with new results (a row ticked, ⌘Z, a file folded shut,
/// the hide-done toggle) is a set lookup per match rather than a
/// `trimmingCharacters` and a dictionary of `String` keys per match.
///
/// That is also the answer to whether the marks want caching: they do not need
/// a cache, they need to be computed once, and holding them beside the results
/// they were computed from is that.
///
/// ## The list is bounded, and says so
///
/// `maximumMatches` is a ceiling on what the list will hold. A one-character
/// query is a request for a row per line of the project, and no number of
/// microseconds per row makes that a list somebody works through. `isCapped`
/// travels with the rows so the pane above can *say* the list is a prefix — a
/// truncated list that looks complete is the failure this program refuses
/// everywhere else.
///
/// The cap is taken at file granularity: the last file to arrive comes in whole
/// or not at all, because a file heading that reads `12` over eight rows is a
/// worse lie than a list that stops one file early.
public struct ResultRows {
	/// A file heading, or one match under one.
	///
	/// The mark and the done state ride on the row rather than being looked up
	/// while drawing: a cell is made per visible row on every reload, and asking
	/// the checklist from inside `viewFor` would recompute a file's marks once
	/// per row of it.
	public enum Row {
		/// The heading, with the marks of everything under it — which is what a
		/// selection on the heading ticks off, folded open or not.
		case file(FileSearchResult, marks: [SearchChecklist.Mark], done: Int, isDone: Bool)
		case match(FileSearchResult, SearchMatch, SearchChecklist.Mark, isDone: Bool)
	}

	/// The search the ticks belong to. Two searches over the same file are two
	/// different questions, and having answered one is not having answered the
	/// other.
	public var question = SearchChecklist.Question(query: "", options: SearchOptions())

	/// How many matches the list will hold before it stops taking them.
	///
	/// 20 000 is far past what anybody works through and far short of what a
	/// one-character query offers: the same query that measured 440 854 matches
	/// stops here at a twentieth of that, and the difference is the whole of the
	/// freeze. It is deliberately not a *display* limit — see `ProjectSearch`,
	/// which stops walking at the same number, so the files past it are not read
	/// either.
	public var maximumMatches = 20_000

	public private(set) var results: [FileSearchResult] = []
	public private(set) var rows: [Row] = []
	/// The marks of each file's matches, in the same order as `results` and as
	/// each result's own `matches`. Computed once, when the file arrives.
	private var marksByFile: [[SearchChecklist.Mark]] = []

	public private(set) var matchCount = 0
	/// How many of the matches in the list are ticked off — counted over
	/// everything held, including rows the hide-done toggle is not showing.
	public private(set) var doneCount = 0
	/// True when something was left out because the list was full.
	public private(set) var isCapped = false

	public private(set) var hidesDone = false
	public private(set) var collapsedFiles: Set<String> = []

	public init() {}

	// MARK: - What is in it

	/// Replaces everything. What the usages list does, which is handed its whole
	/// answer at once.
	public mutating func setResults(
		_ results: [FileSearchResult], marking checklist: SearchChecklist
	) {
		self.results = []
		self.marksByFile = []
		self.matchCount = 0
		self.doneCount = 0
		self.isCapped = false
		self.rows = []
		append(results, marking: checklist)
	}

	/// Takes in what has just arrived, and nothing else.
	///
	/// The one call item 519 exists for. Batch *n* used to cost the whole of
	/// batches 1…*n*; it now costs batch *n*.
	public mutating func append(
		_ batch: [FileSearchResult], marking checklist: SearchChecklist
	) {
		for result in batch {
			guard matchCount < maximumMatches else {
				isCapped = true
				return
			}
			let marks = SearchChecklist.marks(for: result)
			results.append(result)
			marksByFile.append(marks)
			matchCount += result.matches.count

			let flags = marks.map { checklist.isDone($0, for: question) }
			doneCount += flags.lazy.filter { $0 }.count
			appendRows(for: result, marks: marks, done: flags)
		}
	}

	/// Everything again, from the results already held.
	///
	/// For the reasons the rows change that are not new results: a row ticked, a
	/// ⌘Z, a file folded shut, the hide-done toggle. The marks are not recomputed
	/// — they are keyed on the question and the matched text, neither of which a
	/// tick moves.
	public mutating func rebuild(marking checklist: SearchChecklist) {
		rows = []
		doneCount = 0
		for (index, result) in results.enumerated() {
			let marks = marksByFile[index]
			let flags = marks.map { checklist.isDone($0, for: question) }
			doneCount += flags.lazy.filter { $0 }.count
			appendRows(for: result, marks: marks, done: flags)
		}
	}

	public mutating func setHidesDone(_ hiding: Bool, marking checklist: SearchChecklist) {
		guard hidesDone != hiding else { return }
		hidesDone = hiding
		rebuild(marking: checklist)
	}

	/// Folds one file open or shut, and says which it now is.
	@discardableResult
	public mutating func toggleCollapsed(
		_ relativePath: String, marking checklist: SearchChecklist
	) -> Bool {
		let collapsing = !collapsedFiles.contains(relativePath)
		if collapsing {
			collapsedFiles.insert(relativePath)
		} else {
			collapsedFiles.remove(relativePath)
		}
		rebuild(marking: checklist)
		return collapsing
	}

	public func isCollapsed(_ relativePath: String) -> Bool {
		collapsedFiles.contains(relativePath)
	}

	// MARK: - Reading rows

	public var count: Int { rows.count }

	public subscript(index: Int) -> Row? {
		rows.indices.contains(index) ? rows[index] : nil
	}

	/// The marks under a set of rows, in order and without repeats.
	///
	/// A file heading brings every match in the file with it, collapsed or not:
	/// the heading *is* the file, and a selection that took only the rows on
	/// screen would quietly leave a folded file half-ticked.
	public func marks(under indexes: some Sequence<Int>) -> [SearchChecklist.Mark] {
		var seen: Set<SearchChecklist.Mark> = []
		var collected: [SearchChecklist.Mark] = []
		for index in indexes where rows.indices.contains(index) {
			switch rows[index] {
			case let .file(_, marks, _, _):
				for mark in marks where seen.insert(mark).inserted { collected.append(mark) }
			case let .match(_, _, mark, _):
				if seen.insert(mark).inserted { collected.append(mark) }
			}
		}
		return collected
	}

	// MARK: - Flattening one file

	/// One file's heading and its matches, appended.
	///
	/// The done flags are computed by the caller and handed in, rather than being
	/// asked of the checklist twice — once to count them for the heading and once
	/// per row. That is not micro-optimising: the count and the rows are the same
	/// question, and asking it twice is how the two come to disagree.
	private mutating func appendRows(
		for result: FileSearchResult, marks: [SearchChecklist.Mark], done flags: [Bool]
	) {
		let done = flags.lazy.filter { $0 }.count
		// A heading is done when everything under it is, rather than being marked
		// in its own right: a re-run that turns up one new match in a finished
		// file must bring that file back with the new match under it, and a file
		// marked as a whole could not do that.
		let allDone = done == marks.count && !marks.isEmpty
		if hidesDone && allDone { return }

		rows.append(.file(result, marks: marks, done: done, isDone: allDone))
		guard !collapsedFiles.contains(result.relativePath) else { return }
		for (index, match) in result.matches.enumerated() {
			if hidesDone && flags[index] { continue }
			rows.append(.match(result, match, marks[index], isDone: flags[index]))
		}
	}
}

import Testing
import Foundation
@testable import AbydosKit

/// What the results list *is*, without the table that draws it.
///
/// The claims here are the ones item 519 needed and could not make from
/// anywhere: the pane that streams results into this list is in the app target
/// where the suite cannot reach it, and "appending does not rebuild" is
/// arithmetic over arrays rather than anything about a window.
struct ResultRowsTests {
	private let question = SearchChecklist.Question(query: "needle", options: SearchOptions())

	/// A file's matches, as a search would answer with them.
	private func result(_ path: String, _ lines: [(Int, String)]) -> FileSearchResult {
		FileSearchResult(
			url: URL(fileURLWithPath: "/tmp/\(path)"),
			relativePath: path,
			matches: lines.map { line, text in
				SearchMatch(utf16Range: 0..<1, line: line, lineText: text)
			}
		)
	}

	/// `count` files with `matches` matches each, named apart.
	private func manyResults(files: Int, matches: Int, from: Int = 0) -> [FileSearchResult] {
		(from..<(from + files)).map { index in
			result("src/file\(index).swift", (0..<matches).map { ($0, "line \($0) needle") })
		}
	}

	private func rows(_ model: ResultRows) -> [String] {
		model.rows.map { row in
			switch row {
			case let .file(result, _, done, isDone):
				return "file \(result.relativePath) \(done)/\(result.matches.count)\(isDone ? " DONE" : "")"
			case let .match(_, match, _, isDone):
				return "match \(match.line)\(isDone ? " DONE" : "")"
			}
		}
	}

	private func made(_ results: [FileSearchResult], _ checklist: SearchChecklist = SearchChecklist())
		-> ResultRows {
		var model = ResultRows()
		model.question = question
		model.setResults(results, marking: checklist)
		return model
	}

	// MARK: - The rows

	@Test func aFileHeadingIsFollowedByItsMatches() {
		let model = made([result("a.swift", [(3, "one needle"), (9, "two needle")])])
		#expect(rows(model) == ["file a.swift 0/2", "match 3", "match 9"])
		#expect(model.matchCount == 2)
	}

	/// The one call the whole item is about. A batch that arrives must not
	/// disturb — or re-derive — a single row that was already there.
	@Test func appendingLeavesWhatWasAlreadyBuiltAlone() {
		var model = ResultRows()
		model.question = question
		let checklist = SearchChecklist()

		model.append([result("a.swift", [(1, "one needle")])], marking: checklist)
		let first = rows(model)
		model.append([result("b.swift", [(2, "two needle"), (5, "three needle")])], marking: checklist)

		#expect(Array(rows(model).prefix(first.count)) == first)
		#expect(rows(model) == ["file a.swift 0/1", "match 1", "file b.swift 0/2", "match 2", "match 5"])
		#expect(model.matchCount == 3)
		#expect(model.results.count == 2)
	}

	/// Streaming a search in batches must land where handing it over in one go
	/// lands. The two paths are what the search pane and the usages pane use.
	@Test func streamingInBatchesEndsWhereOneBatchWouldHave() {
		let all = manyResults(files: 9, matches: 4)
		var streamed = ResultRows()
		streamed.question = question
		for start in stride(from: 0, to: all.count, by: 2) {
			streamed.append(Array(all[start..<min(start + 2, all.count)]), marking: SearchChecklist())
		}
		#expect(rows(streamed) == rows(made(all)))
		#expect(streamed.matchCount == made(all).matchCount)
	}

	/// The other half of item 529's live-append question, and the half that is
	/// about the rows rather than about the rule.
	///
	/// Search now shows the row the selection lands on, and search is the list
	/// whose rows arrive while somebody is walking it. The selection is an index
	/// into these rows, so "a row appeared under the selection" would be a batch
	/// changing what an index names — and it cannot, because every batch is
	/// appended past the end. The row at index *n* before a batch is the same row
	/// at the same index after it, whichever end of the list *n* is at.
	@Test func abatchDoesNotMoveTheRowUnderAnIndex() {
		var model = ResultRows()
		model.question = question
		let checklist = SearchChecklist()
		model.append(manyResults(files: 3, matches: 3), marking: checklist)

		let before = rows(model)
		for index in before.indices {
			model.append(manyResults(files: 1, matches: 2, from: 90 + index), marking: checklist)
			#expect(rows(model)[index] == before[index])
		}
		#expect(Array(rows(model).prefix(before.count)) == before)
	}

	// MARK: - The bound

	@Test func theListStopsAtItsCeilingAndSaysSo() {
		var model = ResultRows()
		model.question = question
		model.maximumMatches = 50
		model.setResults(manyResults(files: 40, matches: 10), marking: SearchChecklist())

		#expect(model.isCapped)
		#expect(model.matchCount == 50)
		#expect(model.results.count == 5)
	}

	/// A file arrives whole or not at all: a heading that reads `12` over eight
	/// rows is a worse answer than a list that stops one file early.
	@Test func theCeilingIsTakenAtAWholeFile() {
		var model = ResultRows()
		model.question = question
		model.maximumMatches = 25
		model.setResults(manyResults(files: 40, matches: 10), marking: SearchChecklist())

		#expect(model.isCapped)
		// Three whole files, the third of which carried it past 25.
		#expect(model.matchCount == 30)
		for row in model.rows {
			guard case let .file(result, _, _, _) = row else { continue }
			#expect(result.matches.count == 10)
		}
	}

	@Test func aListThatFitsIsNotCapped() {
		var model = ResultRows()
		model.question = question
		model.maximumMatches = 50
		model.setResults(manyResults(files: 4, matches: 10), marking: SearchChecklist())
		#expect(!model.isCapped)
		#expect(model.matchCount == 40)
	}

	/// Batch by batch, which is how a search fills it.
	@Test func theCeilingHoldsAcrossBatches() {
		var model = ResultRows()
		model.question = question
		model.maximumMatches = 50
		for batch in 0..<10 {
			model.append(manyResults(files: 2, matches: 10, from: batch * 2), marking: SearchChecklist())
		}
		#expect(model.isCapped)
		#expect(model.matchCount == 50)
	}

	// MARK: - The ticks

	@Test func theDoneCountIsKeptAsBatchesArrive() {
		let first = result("a.swift", [(1, "one needle"), (2, "two needle")])
		let second = result("b.swift", [(3, "three needle")])
		var checklist = SearchChecklist()
		checklist.set([SearchChecklist.marks(for: first)[0]], done: true, for: question)
		checklist.set(SearchChecklist.marks(for: second), done: true, for: question)

		var model = ResultRows()
		model.question = question
		model.append([first], marking: checklist)
		#expect(model.doneCount == 1)
		model.append([second], marking: checklist)
		#expect(model.doneCount == 2)
		#expect(rows(model) == [
			"file a.swift 1/2", "match 1 DONE", "match 2", "file b.swift 1/1 DONE", "match 3 DONE",
		])
	}

	/// The running count and the count taken from scratch agree.
	///
	/// `doneCount` used to be `SearchChecklist.doneCount(in:for:)`, a walk over
	/// every result asking for every mark again — which is a large part of what
	/// froze the window, because the status line was redrawn on every batch. It
	/// is kept as batches arrive now, and a number maintained incrementally is a
	/// number that can drift. So it is checked against the one that cannot.
	@Test func theRunningDoneCountAgreesWithCountingFromScratch() {
		let files = manyResults(files: 6, matches: 4)
		var checklist = SearchChecklist()
		for file in files.prefix(3) {
			checklist.set(Array(SearchChecklist.marks(for: file).prefix(2)), done: true, for: question)
		}

		var model = ResultRows()
		model.question = question
		for file in files { model.append([file], marking: checklist) }
		#expect(model.doneCount == checklist.doneCount(in: files, for: question))
		#expect(model.doneCount == 6)

		// And again after a rebuild, which is the other way the number is made.
		model.setHidesDone(true, marking: checklist)
		#expect(model.doneCount == checklist.doneCount(in: files, for: question))
	}

	/// The count is over everything held, not over what is on screen: the status
	/// line says how much of the work is done, and hiding the finished rows is
	/// not finishing them.
	@Test func hidingDoneRowsDoesNotChangeWhatIsCounted() {
		let first = result("a.swift", [(1, "one needle"), (2, "two needle")])
		let second = result("b.swift", [(3, "three needle")])
		var checklist = SearchChecklist()
		checklist.set(SearchChecklist.marks(for: second), done: true, for: question)

		var model = made([first, second], checklist)
		model.setHidesDone(true, marking: checklist)

		#expect(rows(model) == ["file a.swift 0/2", "match 1", "match 2"])
		#expect(model.doneCount == 1)
		#expect(model.matchCount == 3)
	}

	@Test func foldingAFileShutLeavesItsHeading() {
		let file = result("a.swift", [(1, "one needle"), (2, "two needle")])
		var model = made([file])
		model.toggleCollapsed("a.swift", marking: SearchChecklist())
		#expect(rows(model) == ["file a.swift 0/2"])
		model.toggleCollapsed("a.swift", marking: SearchChecklist())
		#expect(rows(model) == ["file a.swift 0/2", "match 1", "match 2"])
	}

	/// A heading is the file, folded open or shut. A selection that took only
	/// the rows on screen would quietly leave a folded file half-ticked.
	@Test func aHeadingCarriesEveryMatchInItsFileEvenFolded() {
		let file = result("a.swift", [(1, "one needle"), (2, "two needle")])
		var model = made([file])
		model.toggleCollapsed("a.swift", marking: SearchChecklist())
		#expect(model.marks(under: [0]).count == 2)
	}

	@Test func aMatchRowCarriesOnlyItsOwnMark() {
		let model = made([result("a.swift", [(1, "one needle"), (2, "two needle")])])
		#expect(model.marks(under: [1]) == [SearchChecklist.Mark(
			path: "a.swift", text: "one needle", occurrence: 0
		)])
	}
}

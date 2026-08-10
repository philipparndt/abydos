import Testing
import Foundation
@testable import AbydosKit

/// The part of "the results are a checklist" that can be checked without a
/// window: what a tick is remembered against, and what still counts as the same
/// match after the file has been edited under it.
struct SearchChecklistTests {
	private let question = SearchChecklist.Question(query: "needle", options: SearchOptions())

	/// A file's matches, as a search would answer with them.
	private func result(
		_ path: String, _ lines: [(Int, String)]
	) -> FileSearchResult {
		FileSearchResult(
			url: URL(fileURLWithPath: "/tmp/\(path)"),
			relativePath: path,
			matches: lines.map { line, text in
				SearchMatch(utf16Range: 0..<1, line: line, lineText: text)
			}
		)
	}

	@Test func aMarkSurvivesLinesBeingAddedAboveIt() {
		let before = result("src/a.swift", [(10, "let needle = 1"), (40, "use(needle)")])
		var checklist = SearchChecklist()
		checklist.set([SearchChecklist.marks(for: before)[1]], done: true, for: question)

		// The same file after twelve lines went in at the top, which is what
		// somebody working through a result list does to it.
		let after = result("src/a.swift", [(22, "let needle = 1"), (52, "use(needle)")])
		let marks = SearchChecklist.marks(for: after)
		#expect(!checklist.isDone(marks[0], for: question))
		#expect(checklist.isDone(marks[1], for: question))
	}

	@Test func aMarkSurvivesTheLineBeingIndented() {
		let before = result("src/a.swift", [(3, "use(needle)")])
		var checklist = SearchChecklist()
		checklist.set(SearchChecklist.marks(for: before), done: true, for: question)

		let after = result("src/a.swift", [(4, "\t\tuse(needle)")])
		#expect(checklist.isDone(SearchChecklist.marks(for: after)[0], for: question))
	}

	/// The reason a mark is not the matched text on its own: a file with twenty
	/// `return needle` in it would otherwise tick all twenty at once.
	@Test func twoIdenticalLinesDoNotTickEachOther() {
		let file = result("src/a.swift", [
			(4, "return needle"), (9, "return needle"), (14, "return needle"),
		])
		let marks = SearchChecklist.marks(for: file)
		var checklist = SearchChecklist()
		checklist.set([marks[1]], done: true, for: question)

		#expect(!checklist.isDone(marks[0], for: question))
		#expect(checklist.isDone(marks[1], for: question))
		#expect(!checklist.isDone(marks[2], for: question))
	}

	@Test func anotherQuestionHasItsOwnMarks() {
		let file = result("src/a.swift", [(4, "// TODO: needle, and FIXME")])
		let marks = SearchChecklist.marks(for: file)
		var checklist = SearchChecklist()
		checklist.set(marks, done: true, for: question)

		let other = SearchChecklist.Question(query: "FIXME", options: SearchOptions())
		#expect(checklist.isDone(marks[0], for: question))
		#expect(!checklist.isDone(marks[0], for: other))
	}

	/// Nothing is thrown away when the options change, so an accidental click on
	/// `Aa` is a click on `Aa` again rather than an afternoon lost.
	@Test func changingAnOptionAndChangingItBackKeepsTheMarks() {
		let file = result("src/a.swift", [(4, "let needle = 1")])
		let marks = SearchChecklist.marks(for: file)
		var checklist = SearchChecklist()
		checklist.set(marks, done: true, for: question)

		let sensitive = SearchChecklist.Question(
			query: "needle", options: SearchOptions(caseSensitive: true)
		)
		#expect(!checklist.isDone(marks[0], for: sensitive))
		#expect(checklist.isDone(marks[0], for: question))
	}

	@Test func unmarkingTakesTheTickOffAgain() {
		let file = result("src/a.swift", [(4, "let needle = 1"), (7, "use(needle)")])
		let marks = SearchChecklist.marks(for: file)
		var checklist = SearchChecklist()
		checklist.set(marks, done: true, for: question)
		checklist.set([marks[0]], done: false, for: question)

		#expect(!checklist.isDone(marks[0], for: question))
		#expect(checklist.isDone(marks[1], for: question))
	}

	/// What ⌘Z is given: the set as it stood before the gesture, put back whole.
	@Test func theSetBeforeAGestureIsWhatPutsItBack() {
		let file = result("src/a.swift", [(4, "one needle"), (7, "two needle"), (9, "three needle")])
		let marks = SearchChecklist.marks(for: file)
		var checklist = SearchChecklist()
		checklist.set([marks[0]], done: true, for: question)

		let before = checklist.set([marks[1], marks[2]], done: true, for: question)
		#expect(checklist.doneCount(in: [file], for: question) == 3)

		checklist.restore(before, for: question)
		#expect(checklist.doneCount(in: [file], for: question) == 1)
		#expect(checklist.isDone(marks[0], for: question))
	}

	/// Counted against what is showing, not off the stored set: a mark whose
	/// line no longer matches must not be counted, or the status line says
	/// "12 done" over nine rows.
	@Test func theCountIgnoresMarksForLinesThatNoLongerMatch() {
		let before = result("src/a.swift", [(4, "let needle = 1"), (7, "use(needle)")])
		var checklist = SearchChecklist()
		checklist.set(SearchChecklist.marks(for: before), done: true, for: question)

		let after = result("src/a.swift", [(7, "use(needle)")])
		#expect(checklist.doneCount(in: [after], for: question) == 1)
	}

	@Test func aFileIsDoneWhenEveryMatchUnderItIs() {
		let file = result("src/a.swift", [(4, "one needle"), (7, "two needle")])
		let marks = SearchChecklist.marks(for: file)
		var checklist = SearchChecklist()

		checklist.set([marks[0]], done: true, for: question)
		#expect(checklist.doneCount(in: [file], for: question) == 1)
		checklist.set([marks[1]], done: true, for: question)
		#expect(checklist.doneCount(in: [file], for: question) == file.matches.count)
	}
}

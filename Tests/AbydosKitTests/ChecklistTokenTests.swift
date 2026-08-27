import Foundation
import Testing
@testable import AbydosKit

/// A tick that can be cleared when the thing it was about changes.
///
/// **A tick against a diff that has since been rewritten is a false record**,
/// and the only value a checklist has is that it can be trusted. Keeping it
/// tells a reviewer they have read something nobody has read; clearing all of
/// them on every push is as bad the other way, because a pull request pushed to
/// five times during a review could then never be finished.
struct ChecklistTokenTests {
	/// The case the usages list and the search results are in, and the one this
	/// must not change: no token, nothing ever invalidated.
	@Test func aListThatGivesNoTokenKeepsEveryTick() {
		var list = Checklist<String>()
		list.set(["a", "b", "c"], done: true)

		#expect(list.revalidate(against: ["a": "x", "b": "y"]).isEmpty)
		#expect(list.count == 3)
		#expect(list.isDone("a"))
	}

	@Test func someRowsChangedUnderneathTheList() {
		var list = Checklist<String>()
		list.set(
			["one", "two", "three", "four"],
			done: true,
			tokens: ["one": "1", "two": "2", "three": "3", "four": "4"]
		)

		let cleared = list.revalidate(against: ["one": "1", "two": "CHANGED", "three": "3", "four": "4"])

		#expect(cleared == ["two"])
		#expect(!list.isDone("two"))
		#expect(list.count == 3)
		#expect(list.isDone("one") && list.isDone("three") && list.isDone("four"))
	}

	/// What the count says afterwards, which is the third scenario in the spec:
	/// three of four, and the cleared row is showing again.
	@Test func theCountSaysThreeOfFour() {
		var list = Checklist<String>()
		let rows = ["one", "two", "three", "four"]
		list.set(rows, done: true, tokens: Dictionary(uniqueKeysWithValues: rows.map { ($0, $0) }))

		list.revalidate(against: ["two": "moved"])

		#expect(list.count == 3)
		#expect(rows.filter { !list.isDone($0) } == ["two"])
	}

	/// **A row the list no longer has keeps its tick.** It is not a row that
	/// changed, and confusing the two would mean a file that leaves a pull
	/// request and comes back unchanged comes back unticked.
	@Test func aRowNotInTheNewListIsNotACleared0ne() {
		var list = Checklist<String>()
		list.set(["a", "b"], done: true, tokens: ["a": "1", "b": "2"])

		#expect(list.revalidate(against: ["a": "1"]).isEmpty)
		#expect(list.isDone("b"))
	}

	/// A row added after the ticks were made arrives unticked, and takes none of
	/// the others with it — the spec's third scenario about pushes.
	@Test func aRowAddedByAPushLeavesTheOthersAlone() {
		var list = Checklist<String>()
		list.set(["a", "b"], done: true, tokens: ["a": "1", "b": "2"])

		#expect(list.revalidate(against: ["a": "1", "b": "2", "c": "3"]).isEmpty)
		#expect(list.count == 2)
		#expect(!list.isDone("c"))
	}

	@Test func untickingForgetsWhatTheTickWasAbout() {
		var list = Checklist<String>()
		list.set(["a"], done: true, tokens: ["a": "1"])
		list.set(["a"], done: false)

		#expect(list.token(of: "a") == nil)
		// Ticked again with no token, it is a tick nothing can clear.
		list.set(["a"], done: true)
		#expect(list.revalidate(against: ["a": "different"]).isEmpty)
	}

	/// ⌘Z puts back what was ticked, and a tick that comes back with no record
	/// of what it was about is one `revalidate` can never clear — which is the
	/// safe direction: it shows rather than hides.
	@Test func undoPutsTheTicksBack() {
		var list = Checklist<String>()
		let before = list.set(["a", "b"], done: true, tokens: ["a": "1", "b": "2"])
		list.set(["a", "b"], done: false)
		#expect(list.isEmpty)

		list.restore(before)
		#expect(list.isEmpty)

		list.set(["a"], done: true, tokens: ["a": "1"])
		let held = list.set(["b"], done: true, tokens: ["b": "2"])
		list.restore(held)
		#expect(list.subjects == ["a"])
	}
}

/// The same capability seen through the search's own checklist, which is the
/// one the spec's first scenario is about.
struct SearchChecklistTokenTests {
	private let question = SearchChecklist.Question(query: "TODO", options: SearchOptions())

	private func mark(_ path: String) -> SearchChecklist.Mark {
		SearchChecklist.Mark(path: path, text: "TODO", occurrence: 0)
	}

	@Test func aUsagesListRevalidatesToNothing() {
		var checklist = SearchChecklist()
		checklist.set([mark("a.swift"), mark("b.swift")], done: true, for: question)

		#expect(checklist.revalidate([mark("a.swift"): "anything"], for: question).isEmpty)
		#expect(checklist.isDone(mark("a.swift"), for: question))
		#expect(checklist.marks(for: question).count == 2)
	}

	/// And with tokens it behaves as `Checklist` does, because it is one.
	@Test func aQuestionWhoseRowsCarryTokens() {
		var checklist = SearchChecklist()
		checklist.set(
			[mark("a.swift"), mark("b.swift")],
			done: true,
			for: question,
			tokens: [mark("a.swift"): "1", mark("b.swift"): "2"]
		)

		let cleared = checklist.revalidate(
			[mark("a.swift"): "1", mark("b.swift"): "moved"], for: question
		)

		#expect(cleared == [mark("b.swift")])
		#expect(checklist.isDone(mark("a.swift"), for: question))
		#expect(!checklist.isDone(mark("b.swift"), for: question))
	}

	/// Ticks belong to the question they were made under, and revalidating one
	/// says nothing about another.
	@Test func anotherQuestionIsUntouched() {
		let other = SearchChecklist.Question(query: "FIXME", options: SearchOptions())
		var checklist = SearchChecklist()
		checklist.set([mark("a.swift")], done: true, for: question, tokens: [mark("a.swift"): "1"])
		checklist.set([mark("a.swift")], done: true, for: other, tokens: [mark("a.swift"): "1"])

		checklist.revalidate([mark("a.swift"): "moved"], for: question)

		#expect(!checklist.isDone(mark("a.swift"), for: question))
		#expect(checklist.isDone(mark("a.swift"), for: other))
	}
}

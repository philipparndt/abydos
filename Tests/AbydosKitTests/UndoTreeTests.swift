import Foundation
import Testing
@testable import AbydosKit

/// Every state a document has been in, and how to get between them.
struct UndoTreeTests {
	private func edit(_ range: Range<Int>, removed: String = "", inserted: String) -> UndoTree.Edit {
		UndoTree.Edit(
			byteRange: range,
			removed: Array(removed.utf8),
			inserted: Array(inserted.utf8),
			caretBefore: range.lowerBound
		)
	}

	/// A text the tree's edits are played against, so a route can be checked by
	/// what it produces rather than by its shape.
	private func apply(_ route: (undo: [UndoTree.Edit], apply: [UndoTree.Edit], caret: Int?), to text: String) -> String {
		var bytes = Array(text.utf8)
		for edit in route.undo {
			let range = edit.appliedRange
			bytes.replaceSubrange(range, with: edit.removed)
		}
		for edit in route.apply {
			bytes.replaceSubrange(edit.byteRange, with: edit.inserted)
		}
		return String(decoding: bytes, as: UTF8.self)
	}

	@Test func startsAtTheRootWithNowhereToGo() {
		let tree = UndoTree()
		#expect(tree.count == 1)
		#expect(!tree.canUndo)
		#expect(!tree.canRedo)
		#expect(tree.current == UndoTree.rootID)
	}

	@Test func recordsAChainOfEdits() {
		var tree = UndoTree()
		tree.record(edit(0..<0, inserted: "a"), summary: "type a")
		tree.record(edit(1..<1, inserted: "b"), summary: "type b")

		#expect(tree.count == 3)
		#expect(tree.canUndo)
		#expect(!tree.canRedo)
	}

	@Test func undoesAndRedoesAlongAChain() {
		var tree = UndoTree()
		tree.record(edit(0..<0, inserted: "hello"), summary: "type")

		let back = tree.route(to: try! #require(tree.undoTarget))
		#expect(apply(back, to: "hello") == "")

		tree.moveTo(tree.undoTarget!)
		#expect(!tree.canUndo)
		#expect(tree.canRedo)

		let forward = tree.route(to: try! #require(tree.redoTarget))
		#expect(apply(forward, to: "") == "hello")
	}

	/// The reason this exists: typing after an undo must not destroy what was
	/// undone. A stack loses it; a tree keeps both futures.
	@Test func keepsBothFuturesWhenTypingAfterAnUndo() {
		var tree = UndoTree()
		let first = tree.record(edit(0..<0, inserted: "first attempt"), summary: "first")

		tree.moveTo(tree.undoTarget!)
		let second = tree.record(edit(0..<0, inserted: "second attempt"), summary: "second")

		#expect(tree.count == 3)
		#expect(tree.nodes[UndoTree.rootID].children == [first, second])

		// Back to the root, then forward down the *other* branch.
		tree.moveTo(UndoTree.rootID)
		#expect(tree.hasAlternativeFutures)

		let toFirst = tree.route(to: first)
		#expect(apply(toFirst, to: "") == "first attempt")
	}

	/// Crossing from one branch to another: up to the shared ancestor undoing,
	/// then down applying.
	@Test func crossesBetweenBranches() {
		var tree = UndoTree()
		tree.record(edit(0..<0, inserted: "shared "), summary: "shared")
		let stem = tree.current
		let left = tree.record(edit(7..<7, inserted: "left"), summary: "left")

		tree.moveTo(stem)
		let right = tree.record(edit(7..<7, inserted: "right"), summary: "right")
		#expect(tree.current == right)

		// From "shared right" straight to "shared left".
		let across = tree.route(to: left)
		#expect(across.undo.count == 1)
		#expect(across.apply.count == 1)
		#expect(apply(across, to: "shared right") == "shared left")
	}

	/// A jump from deep in one branch to deep in another undoes and applies
	/// however many steps it takes.
	@Test func crossesSeveralStepsAtOnce() {
		var tree = UndoTree()
		tree.record(edit(0..<0, inserted: "a"), summary: "a")
		let stem = tree.current
		tree.record(edit(1..<1, inserted: "b"), summary: "b")
		tree.record(edit(2..<2, inserted: "c"), summary: "c")
		let deepLeft = tree.current

		tree.moveTo(stem)
		tree.record(edit(1..<1, inserted: "x"), summary: "x")
		tree.record(edit(2..<2, inserted: "y"), summary: "y")

		let across = tree.route(to: deepLeft)
		#expect(across.undo.count == 2)
		#expect(across.apply.count == 2)
		#expect(apply(across, to: "axy") == "abc")
	}

	@Test func goingNowhereIsNoWork() {
		var tree = UndoTree()
		tree.record(edit(0..<0, inserted: "a"), summary: "a")
		let route = tree.route(to: tree.current)
		#expect(route.undo.isEmpty)
		#expect(route.apply.isEmpty)
	}

	/// Redo without being asked which takes the newest branch: it is the one
	/// somebody was working on.
	@Test func redoTakesTheMostRecentFuture() {
		var tree = UndoTree()
		let old = tree.record(edit(0..<0, inserted: "old"), summary: "old")
		tree.moveTo(UndoTree.rootID)
		let new = tree.record(edit(0..<0, inserted: "new"), summary: "new")
		tree.moveTo(UndoTree.rootID)

		#expect(tree.redoTarget == new)
		#expect(tree.futures.map(\.id) == [new, old])
	}

	/// Typing a word is one thing that happened, not seven.
	@Test func extendsTheEditItJustMade() {
		var tree = UndoTree()
		tree.record(edit(0..<0, inserted: "h"), summary: "type")
		tree.extendCurrent(inserted: Array("ello".utf8), summary: "type", time: Date())

		#expect(tree.count == 2)
		let back = tree.route(to: tree.undoTarget!)
		#expect(apply(back, to: "hello") == "")
	}

	/// Extending must never rewrite a state something has branched from.
	@Test func refusesToExtendTheRoot() {
		var tree = UndoTree()
		tree.extendCurrent(inserted: Array("x".utf8), summary: "nope", time: Date())
		#expect(tree.count == 1)
		#expect(tree.root.edit == nil)
	}

	@Test func putsTheCaretWhereTheLastChangeLeftIt() {
		var tree = UndoTree()
		tree.record(edit(0..<0, inserted: "hello"), summary: "type")

		// Undoing puts it where the edit began.
		let back = tree.route(to: UndoTree.rootID)
		#expect(back.caret == 0)

		tree.moveTo(UndoTree.rootID)
		// Applying puts it after what was applied.
		let forward = tree.route(to: tree.redoTarget!)
		#expect(forward.caret == 5)
	}

	@Test func listsEveryStateOldestFirst() {
		var tree = UndoTree(time: Date(timeIntervalSince1970: 0))
		tree.record(edit(0..<0, inserted: "a"), summary: "a", time: Date(timeIntervalSince1970: 10))
		tree.moveTo(UndoTree.rootID)
		tree.record(edit(0..<0, inserted: "b"), summary: "b", time: Date(timeIntervalSince1970: 20))

		#expect(tree.timeline.map(\.summary) == ["Opened", "a", "b"])
	}

	@Test func saysWhichStatesAreOnTheWayHere() {
		var tree = UndoTree()
		let first = tree.record(edit(0..<0, inserted: "a"), summary: "a")
		tree.moveTo(UndoTree.rootID)
		let other = tree.record(edit(0..<0, inserted: "b"), summary: "b")

		#expect(tree.isOnCurrentPath(other))
		#expect(!tree.isOnCurrentPath(first))
		#expect(tree.isOnCurrentPath(UndoTree.rootID))
	}
}

/// The tree through the real document, which is where it has to hold up.
struct DocumentHistoryTests {
	private func makeDocument(_ text: String = "") throws -> TextDocument {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("history-\(UUID().uuidString).txt")
		try text.write(to: url, atomically: true, encoding: .utf8)
		let document = try TextDocument(url: url)
		document.settings = Settings(defaults: TestDefaults.make())
		return document
	}

	private func text(of document: TextDocument) -> String {
		document.rope.string(in: 0..<document.rope.byteCount)
	}

	@Test func undoesAndRedoesOrdinaryTyping() throws {
		let document = try makeDocument()
		_ = document.replace(utf16Range: 0..<0, with: "hello", caretBefore: 0)
		#expect(text(of: document) == "hello")

		document.undo()
		#expect(text(of: document) == "")
		document.redo()
		#expect(text(of: document) == "hello")
	}

	/// The whole point: what was undone survives typing something else.
	///
	/// With two stacks this text is destroyed the moment the second edit lands,
	/// and no sequence of keys brings it back.
	@Test func keepsWhatWasUndoneAfterTypingSomethingElse() throws {
		let document = try makeDocument()
		_ = document.replace(utf16Range: 0..<0, with: "first attempt", caretBefore: 0)
		let firstAttempt = document.history.current

		document.undo()
		_ = document.replace(utf16Range: 0..<0, with: "second attempt", caretBefore: 0)
		#expect(text(of: document) == "second attempt")

		// The abandoned text is still a state, and can be gone back to.
		document.travel(to: firstAttempt)
		#expect(text(of: document) == "first attempt")

		// And so is the one that replaced it.
		#expect(document.history.root.children.count == 2)
	}

	@Test func walksBackThroughSeveralEdits() throws {
		let document = try makeDocument("start\n")
		_ = document.replace(utf16Range: 6..<6, with: "one\n", caretBefore: 6)
		_ = document.replace(utf16Range: 10..<10, with: "two\n", caretBefore: 10)

		document.undo()
		#expect(text(of: document) == "start\none\n")
		document.undo()
		#expect(text(of: document) == "start\n")
		#expect(!document.canUndo)
	}

	@Test func saysWhatEachStateDid() throws {
		let document = try makeDocument("delete me")
		_ = document.replace(utf16Range: 0..<9, with: "", caretBefore: 0)
		#expect(document.history.currentNode.summary == "Deleted “delete me”")

		_ = document.replace(utf16Range: 0..<0, with: "new text", caretBefore: 0)
		#expect(document.history.currentNode.summary.hasPrefix("Typed"))
	}

	/// A run of typing is one state, so undo takes back the word.
	@Test func coalescesARunOfTyping() throws {
		let document = try makeDocument()
		var caret = 0
		for character in "hello" {
			caret = document.replace(utf16Range: caret..<caret, with: String(character), caretBefore: caret)
		}

		// One state for the run, plus the root.
		#expect(document.history.count == 2)
		document.undo()
		#expect(text(of: document) == "")
	}

	/// Landing on a state must not let the next keystroke merge into it.
	@Test func startsAFreshStateAfterTravelling() throws {
		let document = try makeDocument()
		_ = document.replace(utf16Range: 0..<0, with: "abc", caretBefore: 0)
		document.undo()
		_ = document.replace(utf16Range: 0..<0, with: "x", caretBefore: 0)

		#expect(document.history.root.children.count == 2)
		document.undo()
		#expect(text(of: document) == "")
	}

	@Test func putsTheCaretBackWhereTheEditWas() throws {
		let document = try makeDocument("one two")
		_ = document.replace(utf16Range: 4..<7, with: "three", caretBefore: 4)
		#expect(text(of: document) == "one three")

		let caret = document.undo()
		#expect(text(of: document) == "one two")
		#expect(caret == 4)
	}

	@Test func doesNothingWhenThereIsNothingToUndo() throws {
		let document = try makeDocument("fixed")
		#expect(document.undo() == nil)
		#expect(document.redo() == nil)
		#expect(text(of: document) == "fixed")
	}
}

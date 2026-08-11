import Foundation
import Testing
@testable import AbydosKit

/// Reading what a server says it wants done.
struct WorkspaceEditParsingTests {
	private func range(_ line: Int, _ from: Int, _ to: Int) -> [String: Any] {
		[
			"start": ["line": line, "character": from],
			"end": ["line": line, "character": to],
		]
	}

	@Test func readsTheOlderChangesMap() {
		let edit = WorkspaceEdit(json: [
			"changes": [
				"file:///b.swift": [["range": range(0, 4, 7), "newText": "bar"]],
				"file:///a.swift": [["range": range(1, 0, 3), "newText": "bar"]],
			],
		])

		// Sorted, because a map has no order and a plan that comes out
		// differently on two runs is one nobody can write a test about.
		#expect(edit?.changes.count == 2)
		#expect(edit?.changes.first?.uri == "file:///a.swift")
	}

	@Test func readsDocumentChangesInTheOrderTheyAreSent() {
		let edit = WorkspaceEdit(json: [
			"documentChanges": [
				[
					"textDocument": ["uri": "file:///Foo.java", "version": 3],
					"edits": [["range": range(0, 13, 16), "newText": "Bar"]],
				],
				[
					"kind": "rename",
					"oldUri": "file:///Foo.java",
					"newUri": "file:///Bar.java",
				],
			],
		])

		#expect(edit?.changes.count == 2)
		guard case let .edits(uri, edits) = edit?.changes.first else {
			Issue.record("the first change is not a text edit")
			return
		}
		#expect(uri == "file:///Foo.java")
		#expect(edits.first?.newText == "Bar")
		#expect(edit?.changes.last == .rename(
			from: "file:///Foo.java", to: "file:///Bar.java",
			overwrite: false, ignoreIfExists: false
		))
	}

	/// A server that sends both means the same edit twice, for clients that
	/// understand only the older shape. Applying both would apply it twice.
	@Test func prefersDocumentChangesWhenBothAreSent() {
		let edit = WorkspaceEdit(json: [
			"changes": ["file:///old.swift": [["range": range(0, 0, 1), "newText": "x"]]],
			"documentChanges": [[
				"textDocument": ["uri": "file:///new.swift"],
				"edits": [["range": range(0, 0, 1), "newText": "x"]],
			]],
		])
		#expect(edit?.changes.count == 1)
		#expect(edit?.changes.first?.uri == "file:///new.swift")
	}

	@Test func readsTheThreeFileOperations() {
		let edit = WorkspaceEdit(json: [
			"documentChanges": [
				["kind": "create", "uri": "file:///new.java", "options": ["ignoreIfExists": true]],
				[
					"kind": "rename", "oldUri": "file:///a.java", "newUri": "file:///b.java",
					"options": ["overwrite": true],
				],
				["kind": "delete", "uri": "file:///gone.java", "options": ["recursive": true]],
			],
		])

		#expect(edit?.changes == [
			.create(uri: "file:///new.java", overwrite: false, ignoreIfExists: true),
			.rename(
				from: "file:///a.java", to: "file:///b.java",
				overwrite: true, ignoreIfExists: false
			),
			.delete(uri: "file:///gone.java", recursive: true, ignoreIfNotExists: false),
		])
	}

	/// All of it or none of it: half a refactoring is worse than none.
	@Test func refusesTheWholeEditWhenOnePartIsUnreadable() {
		#expect(WorkspaceEdit(json: [
			"documentChanges": [
				["textDocument": ["uri": "file:///a.java"], "edits": []],
				["kind": "somethingNobodyHasHeardOf", "uri": "file:///b.java"],
			],
		]) == nil)
	}

	@Test func aNullAnswerIsNoEdit() {
		#expect(WorkspaceEdit(json: NSNull()) == nil)
		#expect(WorkspaceEdit(json: nil) == nil)
	}

	/// An `AnnotatedTextEdit` is a `TextEdit` with a label on it for a client
	/// that offers half an edit. This one does not, so the label is dropped and
	/// the edit still applies.
	@Test func readsAnAnnotatedEditAsAnOrdinaryOne() {
		let edits = LSPTextEdit.list(from: [
			["range": range(0, 0, 3), "newText": "bar", "annotationId": "rename-imports"],
		])
		#expect(edits.count == 1)
		#expect(edits.first?.newText == "bar")
	}

	@Test func namesEveryFileItTouchesIncludingWhereARenameGoes() {
		let edit = WorkspaceEdit(changes: [
			.edits(uri: "file:///Foo.java", []),
			.rename(from: "file:///Foo.java", to: "file:///Bar.java", overwrite: false, ignoreIfExists: false),
		])
		#expect(edit.files == ["file:///Foo.java", "file:///Bar.java"])
	}
}

/// What `prepareRename` says, in the three shapes servers send.
struct RenameTargetTests {
	@Test func readsARangeAndAPlaceholder() {
		let target = LSPRenameTarget(json: [
			"range": [
				"start": ["line": 2, "character": 8],
				"end": ["line": 2, "character": 14],
			],
			"placeholder": "oldName",
		])
		#expect(target?.range?.start.character == 8)
		#expect(target?.placeholder == "oldName")
	}

	@Test func readsABareRange() {
		let target = LSPRenameTarget(json: [
			"start": ["line": 1, "character": 0],
			"end": ["line": 1, "character": 4],
		])
		#expect(target?.range?.end.character == 4)
		#expect(target?.placeholder == nil)
	}

	/// "Yes, and work the extent out yourself."
	@Test func readsDefaultBehaviour() {
		let target = LSPRenameTarget(json: ["defaultBehavior": true])
		#expect(target != nil)
		#expect(target?.range == nil)
	}

	/// Null is the server saying there is nothing here to rename, which is an
	/// answer rather than a failure.
	@Test func nothingHereIsNotAnError() {
		#expect(LSPRenameTarget(json: NSNull()) == nil)
		#expect(LSPRenameTarget(json: ["defaultBehavior": false]) == nil)
	}
}

/// Putting a server's edits into text.
struct TextEditApplicationTests {
	private func edit(_ line: Int, _ from: Int, _ to: Int, _ text: String) -> LSPTextEdit {
		LSPTextEdit(
			range: LSPRange(
				start: LSPPosition(line: line, character: from),
				end: LSPPosition(line: line, character: to)
			),
			newText: text
		)
	}

	/// Every edit in a set is against the same original text, so two of them on
	/// one line must not shift each other.
	@Test func appliesSeveralEditsToOneLineWithoutShiftingThem() {
		let text = "let foo = foo + foo\n"
		let applied = LSPTextEdit.applied(
			[edit(0, 4, 7, "bar"), edit(0, 10, 13, "bar"), edit(0, 16, 19, "bar")],
			to: text
		)
		#expect(applied == "let bar = bar + bar\n")
	}

	/// The new name being longer than the old is the case that catches a
	/// front-to-back application.
	@Test func aLongerNameDoesNotEatTheTextAfterIt() {
		let applied = LSPTextEdit.applied(
			[edit(0, 0, 1, "alpha"), edit(0, 2, 3, "omega")],
			to: "a b c"
		)
		#expect(applied == "alpha omega c")
	}

	@Test func appliesEditsAcrossLines() {
		let text = "one foo\ntwo\nthree foo\n"
		let applied = LSPTextEdit.applied([edit(0, 4, 7, "bar"), edit(2, 6, 9, "bar")], to: text)
		#expect(applied == "one bar\ntwo\nthree bar\n")
	}

	/// A range that spans lines, which is what a rename of a multi-line
	/// construct looks like.
	@Test func appliesAnEditSpanningTwoLines() {
		let across = LSPTextEdit(
			range: LSPRange(
				start: LSPPosition(line: 0, character: 4),
				end: LSPPosition(line: 1, character: 3)
			),
			newText: "X"
		)
		// From the `t` of `two` to just before the `ee` of `three`, which takes
		// the line break with it.
		#expect(LSPTextEdit.applied([across], to: "one two\nthree four\n") == "one Xee four\n")
	}

	/// Windows line endings are one character longer, and getting that wrong
	/// puts every edit in the file one early.
	@Test func countsWindowsLineEndings() {
		let text = "one foo\r\ntwo foo\r\n"
		#expect(LSPTextEdit.applied([edit(1, 4, 7, "bar")], to: text) == "one foo\r\ntwo bar\r\n")
	}

	@Test func countsBareCarriageReturns() {
		#expect(LSPTextEdit.applied([edit(1, 0, 3, "bar")], to: "one\rfoo\r") == "one\rbar\r")
	}

	/// Servers name the end of a line as a very large character number. Clamped
	/// to the text of the line and **not past its newline**: one character more
	/// and a rename joins two lines of somebody's file together.
	@Test func clampsPastTheEndOfALineWithoutSwallowingItsNewline() {
		let far = LSPTextEdit(
			range: LSPRange(
				start: LSPPosition(line: 0, character: 3),
				end: LSPPosition(line: 0, character: 9999)
			),
			newText: "!"
		)
		#expect(LSPTextEdit.applied([far], to: "one\ntwo\n") == "one!\ntwo\n")
	}

	@Test func appendsAtTheVeryEnd() {
		let append = LSPTextEdit(
			range: LSPRange(
				start: LSPPosition(line: 2, character: 0),
				end: LSPPosition(line: 2, character: 0)
			),
			newText: "three\n"
		)
		#expect(LSPTextEdit.applied([append], to: "one\ntwo\n") == "one\ntwo\nthree\n")
	}

	/// The protocol forbids overlapping edits, and picking a winner would write
	/// something neither the server nor the person asked for.
	@Test func refusesOverlappingEdits() {
		#expect(LSPTextEdit.applied([edit(0, 0, 5, "x"), edit(0, 3, 8, "y")], to: "abcdefghij") == nil)
	}

	/// Two insertions at one place are not an overlap — servers do it for
	/// imports.
	@Test func allowsTwoInsertionsAtOnePlace() {
		let applied = LSPTextEdit.applied([edit(0, 0, 0, "a"), edit(0, 0, 0, "b")], to: "c")
		#expect(applied == "abc" || applied == "bac")
	}

	/// A server talking about a document it no longer has.
	@Test func refusesAPlaceTheFileDoesNotHave() {
		#expect(LSPTextEdit.applied([edit(9, 0, 1, "x")], to: "one\n") == nil)
	}

	/// Characters are UTF-16 units in this protocol, which is what the editor
	/// counts too — so an emoji before the symbol must not shift it.
	@Test func countsCharactersAsTheProtocolDoes() {
		// "🎉" is two UTF-16 units, so `foo` starts at character 3.
		#expect(LSPTextEdit.applied([edit(0, 3, 6, "bar")], to: "🎉 foo") == "🎉 bar")
	}

	@Test func noEditsIsTheTextUnchanged() {
		#expect(LSPTextEdit.applied([], to: "unchanged") == "unchanged")
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// A project that lives in memory, so that a plan, a rollback and a write that
/// refuses can all be arranged exactly.
///
/// A real disk cannot be made to refuse the twenty-first write without making
/// the machine strange, and the twenty-first write refusing is the case this
/// whole item is built around. So the files are a dictionary and the refusal is
/// a set of paths.
final class FakeFiles: @unchecked Sendable {
	private let lock = NSLock()
	private var text: [String: String]
	/// Paths that refuse to be written, moved or trashed.
	var refusing: Set<String> = []
	/// Paths whose *undo* refuses, for the case where putting back fails too.
	var refusingToBePutBack: Set<String> = []
	private(set) var writes = 0

	struct Refused: Error, LocalizedError {
		let path: String
		var errorDescription: String? { "the file is read-only" }
	}

	init(_ text: [String: String]) { self.text = text }

	var contents: [String: String] { lock.lock(); defer { lock.unlock() }; return text }

	func has(_ path: String) -> Bool { contents[path] != nil }

	var files: WorkspaceEditFiles {
		WorkspaceEditFiles(
			contents: { [self] url in
				lock.lock(); defer { lock.unlock() }
				return text[url.path]
			},
			exists: { [self] url in
				lock.lock(); defer { lock.unlock() }
				return text[url.path] != nil
			},
			write: { [self] url, contents in
				try refuse(url.path)
				lock.lock(); defer { lock.unlock() }
				text[url.path] = contents
				writes += 1
			},
			move: { [self] from, to in
				try refuse(from.path)
				lock.lock(); defer { lock.unlock() }
				guard let held = text.removeValue(forKey: from.path) else {
					throw Refused(path: from.path)
				}
				text[to.path] = held
			},
			trash: { [self] url in
				try refuse(url.path)
				lock.lock(); defer { lock.unlock() }
				text[url.path] = nil
			}
		)
	}

	/// Which paths have been touched once already, so that "refuses to be put
	/// back" can mean the second time and not the first.
	private var touched: Set<String> = []

	/// Two different refusals, because the two cases they arrange are different
	/// sentences: a path in `refusing` never accepts anything, which is the
	/// ordinary rollback; a path in `refusingToBePutBack` accepts the write and
	/// then refuses to give it up, which is the floor.
	private func refuse(_ path: String) throws {
		lock.lock()
		defer { lock.unlock() }
		if refusing.contains(path) { throw Refused(path: path) }
		guard refusingToBePutBack.contains(path) else { return }
		guard touched.insert(path).inserted else { throw Refused(path: path) }
	}
}

private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }
private func uri(_ path: String) -> String { url(path).absoluteString }

private func replacing(_ line: Int, _ from: Int, _ to: Int, with text: String) -> LSPTextEdit {
	LSPTextEdit(
		range: LSPRange(
			start: LSPPosition(line: line, character: from),
			end: LSPPosition(line: line, character: to)
		),
		newText: text
	)
}

/// Working out what an edit comes to, without touching anything.
struct WorkspaceEditPlanTests {
	private func plan(_ edit: WorkspaceEdit, in files: FakeFiles) -> WorkspaceEditPlan {
		WorkspaceEditPlan.make(edit, contents: files.files.contents, exists: files.files.exists)
	}

	@Test func planningTouchesNothing() {
		let files = FakeFiles(["/p/a.swift": "let foo = 1\n"])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/a.swift"), [replacing(0, 4, 7, with: "bar")]),
		])

		let made = plan(edit, in: files)
		#expect(made.writes.count == 1)
		#expect(made.writes.first?.after == "let bar = 1\n")
		// The whole point: the file still says what it said.
		#expect(files.contents["/p/a.swift"] == "let foo = 1\n")
	}

	@Test func editsSeveralFilesAtOnce() {
		let files = FakeFiles([
			"/p/a.swift": "foo()\n",
			"/p/b.swift": "foo()\n",
			"/p/c.swift": "foo()\n",
		])
		let edit = WorkspaceEdit(changes: ["/p/a.swift", "/p/b.swift", "/p/c.swift"].map {
			.edits(uri: uri($0), [replacing(0, 0, 3, with: "bar")])
		})

		let made = plan(edit, in: files)
		#expect(made.refusals.isEmpty)
		#expect(made.writes.count == 3)
		#expect(made.writes.allSatisfy { $0.after == "bar()\n" })
	}

	/// A file nothing changed is not written. A write that puts back exactly
	/// what was there still moves the modification date, which is what a build
	/// watcher reads.
	@Test func aFileThatDoesNotChangeIsNotWritten() {
		let files = FakeFiles(["/p/a.swift": "let foo = 1\n"])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/a.swift"), [replacing(0, 4, 7, with: "foo")]),
		])
		#expect(plan(edit, in: files).writes.isEmpty)
	}

	// MARK: - A file that moves

	/// The Java case: the class is renamed and the file has to follow.
	@Test func editsThenMovesTheFile() {
		let files = FakeFiles(["/p/Foo.java": "class Foo {}\n"])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/Foo.java"), [replacing(0, 6, 9, with: "Bar")]),
			.rename(
				from: uri("/p/Foo.java"), to: uri("/p/Bar.java"),
				overwrite: false, ignoreIfExists: false
			),
		])

		let made = plan(edit, in: files)
		#expect(made.refusals.isEmpty)
		#expect(made.moves == [.init(from: url("/p/Foo.java"), to: url("/p/Bar.java"))])
		// Recorded at the name the file will have, so a write lands after the
		// move rather than at a path the move has emptied.
		#expect(made.writes.count == 1)
		#expect(made.writes.first?.url == url("/p/Bar.java"))
		#expect(made.writes.first?.before == "class Foo {}\n")
		#expect(made.writes.first?.after == "class Bar {}\n")
	}

	/// The same edit with the move sent first, which servers also do. Both mean
	/// the same thing, and only simulating the order gets both right.
	@Test func movesThenEditsUnderTheNewName() {
		let files = FakeFiles(["/p/Foo.java": "class Foo {}\n"])
		let edit = WorkspaceEdit(changes: [
			.rename(
				from: uri("/p/Foo.java"), to: uri("/p/Bar.java"),
				overwrite: false, ignoreIfExists: false
			),
			.edits(uri: uri("/p/Bar.java"), [replacing(0, 6, 9, with: "Bar")]),
		])

		let made = plan(edit, in: files)
		#expect(made.refusals.isEmpty)
		#expect(made.moves == [.init(from: url("/p/Foo.java"), to: url("/p/Bar.java"))])
		#expect(made.writes.first?.url == url("/p/Bar.java"))
		#expect(made.writes.first?.after == "class Bar {}\n")
	}

	@Test func aFileRenamedTwiceIsOneMove() {
		let files = FakeFiles(["/p/A.java": "x\n"])
		let edit = WorkspaceEdit(changes: [
			.rename(from: uri("/p/A.java"), to: uri("/p/B.java"), overwrite: false, ignoreIfExists: false),
			.rename(from: uri("/p/B.java"), to: uri("/p/C.java"), overwrite: false, ignoreIfExists: false),
		])
		#expect(plan(edit, in: files).moves == [.init(from: url("/p/A.java"), to: url("/p/C.java"))])
	}

	@Test func aFileRenamedBackIsNoMoveAtAll() {
		let files = FakeFiles(["/p/A.java": "x\n"])
		let edit = WorkspaceEdit(changes: [
			.rename(from: uri("/p/A.java"), to: uri("/p/B.java"), overwrite: false, ignoreIfExists: false),
			.rename(from: uri("/p/B.java"), to: uri("/p/A.java"), overwrite: false, ignoreIfExists: false),
		])
		let made = plan(edit, in: files)
		#expect(made.moves.isEmpty)
		#expect(made.writes.isEmpty)
	}

	@Test func createsAndDeletes() {
		let files = FakeFiles(["/p/gone.java": "old\n"])
		let edit = WorkspaceEdit(changes: [
			.create(uri: uri("/p/new.java"), overwrite: false, ignoreIfExists: false),
			.edits(uri: uri("/p/new.java"), [replacing(0, 0, 0, with: "class New {}\n")]),
			.delete(uri: uri("/p/gone.java"), recursive: false, ignoreIfNotExists: false),
		])

		let made = plan(edit, in: files)
		#expect(made.refusals.isEmpty)
		#expect(made.writes.count == 1)
		#expect(made.writes.first?.before == nil)
		#expect(made.writes.first?.after == "class New {}\n")
		// Held, so an undo can put it back rather than fish it out of the trash.
		#expect(made.deletions == [.init(url: url("/p/gone.java"), contents: "old\n")])
	}

	// MARK: - Refusals, all of which happen before anything is written

	@Test func refusesAFileItCannotRead() {
		let files = FakeFiles([:])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/missing.swift"), [replacing(0, 0, 1, with: "x")]),
		])
		#expect(plan(edit, in: files).refusals == ["“missing.swift” could not be read."])
	}

	/// The one refusal that is not about the file system: the server is
	/// describing a document that is not the one on disk.
	@Test func refusesEditsThatDoNotFitTheFile() {
		let files = FakeFiles(["/p/a.swift": "one line\n"])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/a.swift"), [replacing(40, 0, 1, with: "x")]),
		])
		let made = plan(edit, in: files)
		#expect(made.refusals.count == 1)
		#expect(made.refusals.first?.contains("no longer agree") == true)
		#expect(made.writes.isEmpty)
	}

	@Test func refusesARenameOntoSomethingThatIsThere() {
		let files = FakeFiles(["/p/A.java": "a\n", "/p/B.java": "b\n"])
		let edit = WorkspaceEdit(changes: [
			.rename(from: uri("/p/A.java"), to: uri("/p/B.java"), overwrite: false, ignoreIfExists: false),
		])
		let made = plan(edit, in: files)
		#expect(made.refusals == ["“A.java” cannot become “B.java”: something is already there."])
		#expect(made.moves.isEmpty)
	}

	@Test func overwriteSaysItIsAllowed() {
		let files = FakeFiles(["/p/A.java": "a\n", "/p/B.java": "b\n"])
		let edit = WorkspaceEdit(changes: [
			.rename(from: uri("/p/A.java"), to: uri("/p/B.java"), overwrite: true, ignoreIfExists: false),
		])
		#expect(plan(edit, in: files).refusals.isEmpty)
	}

	@Test func ignoreIfExistsSkipsRatherThanRefuses() {
		let files = FakeFiles(["/p/A.java": "a\n"])
		let edit = WorkspaceEdit(changes: [
			.create(uri: uri("/p/A.java"), overwrite: false, ignoreIfExists: true),
		])
		let made = plan(edit, in: files)
		#expect(made.refusals.isEmpty)
		#expect(made.isEmpty)
	}

	@Test func refusesAURIThatNamesNoFile() {
		let files = FakeFiles([:])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: "jdt://contents/rt.jar/java.lang/String.class", [replacing(0, 0, 1, with: "x")]),
		])
		#expect(plan(edit, in: files).refusals.first?.contains("not a file this editor can change") == true)
	}

	/// One refusal among many good changes still means nothing is written —
	/// which is the whole partial-failure answer, stated where it is decided.
	@Test func oneRefusalIsCarriedBesideEverythingThatWouldHaveWorked() {
		let files = FakeFiles(["/p/a.swift": "foo\n", "/p/b.swift": "foo\n"])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/a.swift"), [replacing(0, 0, 3, with: "bar")]),
			.edits(uri: uri("/p/nowhere.swift"), [replacing(0, 0, 3, with: "bar")]),
			.edits(uri: uri("/p/b.swift"), [replacing(0, 0, 3, with: "bar")]),
		])
		let made = plan(edit, in: files)
		#expect(made.writes.count == 2)
		#expect(made.refusals.count == 1)
		// And the applier turns that into nothing happening at all.
		#expect(WorkspaceEditApplier.apply(made, to: files.files).isUntouched)
		#expect(files.contents["/p/a.swift"] == "foo\n")
	}
}

/// Carrying a plan out, and putting it back.
struct WorkspaceEditApplierTests {
	private func plan(_ edit: WorkspaceEdit, in files: FakeFiles) -> WorkspaceEditPlan {
		WorkspaceEditPlan.make(edit, contents: files.files.contents, exists: files.files.exists)
	}

	private func renameAcross(_ paths: [String]) -> WorkspaceEdit {
		WorkspaceEdit(changes: paths.map {
			.edits(uri: uri($0), [replacing(0, 0, 3, with: "bar")])
		})
	}

	@Test func writesEveryFile() {
		let paths = (1...5).map { "/p/f\($0).swift" }
		let files = FakeFiles(Dictionary(uniqueKeysWithValues: paths.map { ($0, "foo()\n") }))

		let outcome = WorkspaceEditApplier.apply(plan(renameAcross(paths), in: files), to: files.files)
		guard case .applied = outcome else {
			Issue.record("the edit did not apply: \(outcome)")
			return
		}
		#expect(paths.allSatisfy { files.contents[$0] == "bar()\n" })
	}

	@Test func movesTheFileAndWritesItAtItsNewName() {
		let files = FakeFiles(["/p/Foo.java": "class Foo {}\n"])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/Foo.java"), [replacing(0, 6, 9, with: "Bar")]),
			.rename(from: uri("/p/Foo.java"), to: uri("/p/Bar.java"), overwrite: false, ignoreIfExists: false),
		])

		_ = WorkspaceEditApplier.apply(plan(edit, in: files), to: files.files)
		#expect(files.contents["/p/Foo.java"] == nil)
		#expect(files.contents["/p/Bar.java"] == "class Bar {}\n")
	}

	// MARK: - The twenty-first file

	/// The failure the whole item is built around: the writes have started and
	/// one of them refuses. Everything already written goes back, and the
	/// project is as it was.
	@Test func aWriteThatRefusesPutsBackEverythingBeforeIt() {
		let paths = (1...20).map { "/p/f\(String(format: "%02d", $0)).swift" }
		let files = FakeFiles(Dictionary(uniqueKeysWithValues: paths.map { ($0, "foo()\n") }))
		files.refusing = ["/p/f15.swift"]

		let outcome = WorkspaceEditApplier.apply(plan(renameAcross(paths), in: files), to: files.files)

		guard case let .putBack(failure) = outcome else {
			Issue.record("expected a rollback, got \(outcome)")
			return
		}
		#expect(failure.contains("f15.swift"))
		#expect(failure.contains("read-only"))
		#expect(outcome.isUntouched)
		// Every one of the twenty says what it said before.
		#expect(paths.allSatisfy { files.contents[$0] == "foo()\n" })
	}

	/// A move that refuses is the same story, and the file has to be where it
	/// was rather than at either name.
	@Test func aMoveThatRefusesPutsTheFileBack() {
		let files = FakeFiles(["/p/A.java": "a\n", "/p/other.java": "b\n"])
		files.refusing = ["/p/A.java"]
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/other.java"), [replacing(0, 0, 1, with: "c")]),
			.rename(from: uri("/p/A.java"), to: uri("/p/B.java"), overwrite: false, ignoreIfExists: false),
		])

		let outcome = WorkspaceEditApplier.apply(plan(edit, in: files), to: files.files)
		#expect(outcome.isUntouched)
		#expect(files.contents["/p/A.java"] == "a\n")
		#expect(files.contents["/p/B.java"] == nil)
		#expect(files.contents["/p/other.java"] == "b\n")
	}

	/// A file this edit created is trashed rather than left empty when the
	/// rollback runs.
	@Test func rollingBackACreationTakesTheFileAway() {
		let files = FakeFiles(["/p/a.swift": "foo\n"])
		files.refusing = ["/p/a.swift"]
		let edit = WorkspaceEdit(changes: [
			.create(uri: uri("/p/new.swift"), overwrite: false, ignoreIfExists: false),
			.edits(uri: uri("/p/new.swift"), [replacing(0, 0, 0, with: "new\n")]),
			.edits(uri: uri("/p/a.swift"), [replacing(0, 0, 3, with: "bar")]),
		])

		#expect(WorkspaceEditApplier.apply(plan(edit, in: files), to: files.files).isUntouched)
		#expect(files.contents["/p/new.swift"] == nil)
		#expect(files.contents["/p/a.swift"] == "foo\n")
	}

	/// The floor: the write refused **and** the putting back refused. All that
	/// is left is being exact, by name, on both sides.
	@Test func aRollbackThatCannotFinishSaysExactlyWhatIsWhere() {
		let files = FakeFiles([
			"/p/a.swift": "foo\n", "/p/b.swift": "foo\n", "/p/c.swift": "foo\n",
		])
		// `b` refuses to be written; `a` takes its write and then refuses to give
		// it up again.
		files.refusing = ["/p/b.swift"]
		files.refusingToBePutBack = ["/p/a.swift"]

		let outcome = WorkspaceEditApplier.apply(
			plan(renameAcross(["/p/a.swift", "/p/b.swift", "/p/c.swift"]), in: files),
			to: files.files
		)

		guard case let .halfDone(failure, changed, unchanged) = outcome else {
			Issue.record("expected the floor, got \(outcome)")
			return
		}
		#expect(failure.contains("b.swift"))
		#expect(changed == [url("/p/a.swift")])
		#expect(unchanged.isEmpty)
		#expect(!outcome.isUntouched)

		// And the sentence names both sides rather than counting them.
		#expect(outcome.summary?.detail.contains("“a.swift”") == true)
		#expect(outcome.summary?.title == "The rename did not finish")
	}

	// MARK: - One undo

	/// Forty files and one ⌘Z. The plan is run backwards, which is the same
	/// walk the rollback does — one mechanism rather than two that can disagree.
	@Test func oneUndoTakesTheWholeEditBack() {
		let paths = (1...40).map { "/p/f\(String(format: "%02d", $0)).swift" }
		let files = FakeFiles(Dictionary(uniqueKeysWithValues: paths.map { ($0, "foo()\n") }))

		let made = plan(renameAcross(paths), in: files)
		guard case let .applied(applied) = WorkspaceEditApplier.apply(made, to: files.files) else {
			Issue.record("the edit did not apply")
			return
		}
		#expect(paths.allSatisfy { files.contents[$0] == "bar()\n" })

		let back = WorkspaceEditApplier.reverse(applied, in: files.files)
		#expect(back.isUntouched)
		#expect(paths.allSatisfy { files.contents[$0] == "foo()\n" })
	}

	@Test func undoingPutsAMovedFileBackUnderItsOldName() {
		let files = FakeFiles(["/p/Foo.java": "class Foo {}\n"])
		let edit = WorkspaceEdit(changes: [
			.edits(uri: uri("/p/Foo.java"), [replacing(0, 6, 9, with: "Bar")]),
			.rename(from: uri("/p/Foo.java"), to: uri("/p/Bar.java"), overwrite: false, ignoreIfExists: false),
		])

		guard case let .applied(applied) = WorkspaceEditApplier.apply(plan(edit, in: files), to: files.files) else {
			Issue.record("the edit did not apply")
			return
		}
		_ = WorkspaceEditApplier.reverse(applied, in: files.files)
		#expect(files.contents["/p/Bar.java"] == nil)
		#expect(files.contents["/p/Foo.java"] == "class Foo {}\n")
	}

	@Test func undoingPutsADeletedFileBack() {
		let files = FakeFiles(["/p/gone.java": "old\n"])
		let edit = WorkspaceEdit(changes: [
			.delete(uri: uri("/p/gone.java"), recursive: false, ignoreIfNotExists: false),
		])
		guard case let .applied(applied) = WorkspaceEditApplier.apply(plan(edit, in: files), to: files.files) else {
			Issue.record("the edit did not apply")
			return
		}
		#expect(files.contents["/p/gone.java"] == nil)
		_ = WorkspaceEditApplier.reverse(applied, in: files.files)
		#expect(files.contents["/p/gone.java"] == "old\n")
	}

	/// Success says nothing. The files have changed on screen, which is the
	/// whole of what was asked for, and an app congratulating itself is the
	/// rule `FileUndo` already settled.
	@Test func nothingIsSaidWhenItAllWorked() {
		let files = FakeFiles(["/p/a.swift": "foo\n"])
		let outcome = WorkspaceEditApplier.apply(plan(renameAcross(["/p/a.swift"]), in: files), to: files.files)
		#expect(outcome.summary == nil)
	}
}

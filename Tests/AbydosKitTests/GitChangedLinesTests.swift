import Foundation
import Testing
@testable import AbydosKit

/// Which lines the editor gutter marks, read off literal diffs — the parse is
/// `GitPatch`'s and already proven; these claims are about the classification.
struct GitChangedLinesTests {
	private func lines(of diff: String) -> GitChangedLines {
		GitChangedLines.read(GitPatch.parse(diff))
	}

	@Test func aReplacedLineIsAModification() {
		let changed = lines(of: """
		diff --git a/f.txt b/f.txt
		--- a/f.txt
		+++ b/f.txt
		@@ -1,3 +1,3 @@
		 one
		-two
		+TWO
		 three
		""")
		#expect(changed.marks == [2: .modified])
		#expect(changed.deletedAfter.isEmpty)
	}

	/// What every other editor calls "changed": the whole replacement run is
	/// a modification, and nothing was deleted.
	@Test func oneLineReplacedByThreeIsThreeModifications() {
		let changed = lines(of: """
		diff --git a/f.txt b/f.txt
		--- a/f.txt
		+++ b/f.txt
		@@ -1,3 +1,5 @@
		 one
		-two
		+first
		+second
		+third
		 three
		""")
		#expect(changed.marks == [2: .modified, 3: .modified, 4: .modified])
		#expect(changed.deletedAfter.isEmpty)
	}

	@Test func aPureAdditionIsAdded() {
		let changed = lines(of: """
		diff --git a/f.txt b/f.txt
		--- a/f.txt
		+++ b/f.txt
		@@ -1,2 +1,4 @@
		 one
		+new one
		+new two
		 two
		""")
		#expect(changed.marks == [2: .added, 3: .added])
		#expect(changed.deletedAfter.isEmpty)
	}

	@Test func aPureRemovalMarksAfterThePrecedingLine() {
		let changed = lines(of: """
		diff --git a/f.txt b/f.txt
		--- a/f.txt
		+++ b/f.txt
		@@ -1,4 +1,2 @@
		 one
		-two
		-three
		 four
		""")
		#expect(changed.marks.isEmpty)
		#expect(changed.deletedAfter == [1])
	}

	/// 0 is "above the first line", which is the only place this deletion can
	/// be drawn.
	@Test func aDeletionAtTheTopMarksAboveLineOne() {
		let changed = lines(of: """
		diff --git a/f.txt b/f.txt
		--- a/f.txt
		+++ b/f.txt
		@@ -1,3 +1,2 @@
		-gone
		 one
		 two
		""")
		#expect(changed.deletedAfter == [0])
	}

	@Test func anEmptyDiffMarksNothing() {
		#expect(lines(of: "").isEmpty)
	}
}

/// The diff behind the marks, against a real repository.
struct GitDiffAgainstHeadTests {
	private func makeRepository() async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("changed-lines-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = await GitRepository.run(["init", "-q", "-b", "main"], in: root)
		_ = await GitRepository.run(["config", "user.email", "t@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "T"], in: root)
		try "ignored.log\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		try "one\ntwo\nthree\nfour\n".write(
			to: root.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "first"], in: root)
		return root
	}

	/// The marks answer "what have I changed since the last commit", so a
	/// staged edit and an unstaged one mark exactly alike.
	@Test func stagedAndUnstagedEditsMarkAlike() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		try "ONE\ntwo\nthree\nfour\n".write(
			to: root.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "f.txt"], in: root)
		try "ONE\ntwo\nTHREE\nfour\n".write(
			to: root.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8
		)

		let diff = try #require(await GitWorkingCopy.diffAgainstHead(for: "f.txt", in: root))
		let changed = GitChangedLines.read(GitPatch.parse(diff))
		#expect(changed.marks == [1: .modified, 3: .modified])
	}

	@Test func anUntrackedFileHasNoMarks() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try "new\n".write(
			to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8
		)
		#expect(await GitWorkingCopy.diffAgainstHead(for: "new.txt", in: root) == nil)
	}

	@Test func anIgnoredFileHasNoMarks() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try "noise\n".write(
			to: root.appendingPathComponent("ignored.log"), atomically: true, encoding: .utf8
		)
		#expect(await GitWorkingCopy.diffAgainstHead(for: "ignored.log", in: root) == nil)
	}

	@Test func aCleanFileHasAnEmptyDiff() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let diff = try #require(await GitWorkingCopy.diffAgainstHead(for: "f.txt", in: root))
		#expect(GitChangedLines.read(GitPatch.parse(diff)).isEmpty)
	}
}

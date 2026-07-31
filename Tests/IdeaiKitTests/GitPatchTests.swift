import Testing
import Foundation
@testable import IdeaiKit

/// Parsing a unified diff into something parts can be taken out of.
struct GitPatchParseTests {
	private let sample = """
	diff --git a/file.txt b/file.txt
	index 1234567..89abcde 100644
	--- a/file.txt
	+++ b/file.txt
	@@ -1,4 +1,5 @@ func header()
	 one
	-two
	+TWO
	+two point five
	 three
	"""

	@Test func headerIsKeptSeparateFromHunks() {
		let patch = GitPatch.parse(sample)
		#expect(patch.header.count == 4)
		#expect(patch.header.first == "diff --git a/file.txt b/file.txt")
		#expect(patch.hunks.count == 1)
	}

	@Test func hunkStartsAndHeadingAreRead() {
		let hunk = GitPatch.parse(sample).hunks[0]
		#expect(hunk.oldStart == 1)
		#expect(hunk.newStart == 1)
		#expect(hunk.heading == "func header()")
	}

	@Test func linesAreTaggedAndStripped() {
		let lines = GitPatch.parse(sample).hunks[0].lines
		#expect(lines.map(\.kind) == [.context, .removed, .added, .added, .context])
		#expect(lines[1].text == "two")
		#expect(lines[2].text == "TWO")
	}

	/// Only changed lines can be staged; context is carried, not chosen.
	@Test func onlyChangedLinesAreSelectable() {
		#expect(GitPatch.parse(sample).selectableIndices() == [1, 2, 3])
	}

	@Test func indicesAreNumberedAcrossHunks() {
		let patch = GitPatch.parse("""
		--- a/f
		+++ b/f
		@@ -1,2 +1,2 @@
		 a
		-b
		@@ -10,2 +10,2 @@
		 c
		+d
		""")
		#expect(patch.hunks.count == 2)
		#expect(patch.selectableIndices() == [1, 3])
		#expect(patch.indices(inHunk: 1) == [3])
	}

	/// A blank line inside a hunk is context whose marker git dropped; treating
	/// it as a terminator would shift every index after it.
	@Test func blankLinesInsideAHunkStayInside() {
		let patch = GitPatch.parse("""
		--- a/f
		+++ b/f
		@@ -1,3 +1,3 @@
		 a

		-b
		""")
		#expect(patch.hunks[0].lines.count == 3)
		#expect(patch.selectableIndices() == [2])
	}

	@Test func noNewlineMarkersAreCarriedNotSelectable() {
		let patch = GitPatch.parse("""
		--- a/f
		+++ b/f
		@@ -1 +1 @@
		-a
		\\ No newline at end of file
		+b
		""")
		#expect(patch.hunks[0].lines.map(\.kind) == [.removed, .noNewline, .added])
		#expect(patch.selectableIndices() == [0, 2])
	}
}

/// Building the patch that actually gets applied. This is where being wrong
/// stages something the user did not choose.
struct GitPatchBuildTests {
	private let sample = """
	--- a/file.txt
	+++ b/file.txt
	@@ -1,4 +1,5 @@
	 one
	-two
	+TWO
	+extra
	 three
	"""

	@Test func nothingSelectedProducesNoPatch() {
		#expect(GitPatch.parse(sample).patch(selecting: []) == nil)
	}

	/// The case that matters most: an unselected deletion means the line stays,
	/// so it becomes context. Dropping it would stage a deletion nobody chose.
	@Test func anUnselectedDeletionBecomesContext() {
		// Select only the "+TWO" addition, at index 2.
		let output = GitPatch.parse(sample).patch(selecting: [2])
		#expect(output?.contains("\n two\n") == true)
		#expect(output?.contains("\n-two\n") == false)
		#expect(output?.contains("+TWO") == true)
	}

	@Test func anUnselectedAdditionIsDropped() {
		// Select only the deletion at index 1.
		let output = GitPatch.parse(sample).patch(selecting: [1])
		#expect(output?.contains("-two") == true)
		#expect(output?.contains("+TWO") == false)
		#expect(output?.contains("+extra") == false)
	}

	/// Counts have to describe the patch that is being emitted, not the one it
	/// came from, or git apply rejects it.
	@Test func hunkCountsAreRecomputed() {
		let output = GitPatch.parse(sample).patch(selecting: [2])
		// one, two-as-context, +TWO, three: 3 old lines, 4 new.
		#expect(output?.contains("@@ -1,3 +1,4 @@") == true)
	}

	@Test func hunksWithNothingSelectedAreOmitted() {
		let patch = GitPatch.parse("""
		--- a/f
		+++ b/f
		@@ -1,2 +1,2 @@
		 a
		+b
		@@ -10,2 +10,2 @@
		 c
		+d
		""")
		let output = patch.patch(selecting: [1])
		#expect(output?.contains("@@ -1,") == true)
		#expect(output?.contains("@@ -10,") == false)
	}

	@Test func theHeaderIsCarriedThrough() {
		let output = GitPatch.parse(sample).patch(selecting: [2])
		#expect(output?.hasPrefix("--- a/file.txt\n+++ b/file.txt\n") == true)
	}

	@Test func theHeadingIsPreserved() {
		let patch = GitPatch.parse("""
		--- a/f
		+++ b/f
		@@ -1,2 +1,2 @@ inside func()
		 a
		+b
		""")
		#expect(patch.patch(selecting: [1])?.contains("@@ inside func()") == true)
	}

	/// Reversing flips which unselected lines are carried. An unselected
	/// addition is already in the index, so it has to appear on both sides or
	/// the reverse apply finds content it does not expect.
	@Test func reversingCarriesUnselectedAdditionsAsContext() {
		let patch = GitPatch.parse("""
		--- a/f
		+++ b/f
		@@ -1,1 +1,3 @@
		 a
		+one
		+two
		""")
		let output = patch.patch(selecting: [1], reverse: true)
		#expect(output?.contains("+one") == true)
		#expect(output?.contains(" two") == true)
		#expect(output?.contains("+two") == false)
	}

	/// And an unselected deletion is not in the index at all, so it appears on
	/// neither side — carrying it as context would not match.
	@Test func reversingDropsUnselectedDeletions() {
		let patch = GitPatch.parse("""
		--- a/f
		+++ b/f
		@@ -1,3 +1,1 @@
		 a
		-one
		-two
		""")
		let output = patch.patch(selecting: [1], reverse: true)
		#expect(output?.contains("-one") == true)
		#expect(output?.contains("two") == false)
	}

	@Test func theResultEndsWithANewline() {
		#expect(GitPatch.parse(sample).patch(selecting: [2])?.hasSuffix("\n") == true)
	}
}

/// Applied against a real repository, because a patch git rejects is worthless
/// however well-formed it looks.
struct GitPartialStagingTests {
	private func makeRepository(contents: String) async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-partial-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		_ = await GitRepository.run(["init", "-q"], in: root)
		_ = await GitRepository.run(["config", "user.email", "t@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "T"], in: root)
		try contents.write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "initial"], in: root)
		return root
	}

	private func write(_ contents: String, to root: URL) throws {
		try contents.write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
	}

	/// One of two additions goes to the index; the other stays in the work tree.
	@Test func stagingOneLineLeavesTheOtherUnstaged() async throws {
		let root = try await makeRepository(contents: "a\nb\nc\n")
		try write("a\nFIRST\nb\nSECOND\nc\n", to: root)

		let diff = await GitWorkingCopy.diff(for: "file.txt", staged: false, in: root)
		let patch = GitPatch.parse(diff)
		let selectable = patch.selectableIndices()
		#expect(selectable.count == 2)

		let result = await GitWorkingCopy.stage(
			lines: [selectable[0]],
			ofDiff: diff,
			in: root
		)
		#expect(result.exitCode == 0, "\(result.stderr)")

		let staged = await GitWorkingCopy.diff(for: "file.txt", staged: true, in: root)
		#expect(staged.contains("+FIRST"))
		#expect(!staged.contains("+SECOND"))

		// And the rest is still there to stage later.
		let remaining = await GitWorkingCopy.diff(for: "file.txt", staged: false, in: root)
		#expect(remaining.contains("+SECOND"))
	}

	/// The dangerous direction: staging an addition must not also stage a
	/// deletion that happens to sit in the same hunk.
	@Test func stagingAnAdditionLeavesAnUnselectedDeletionAlone() async throws {
		let root = try await makeRepository(contents: "keep\nremove\n")
		try write("keep\nADDED\n", to: root)

		let diff = await GitWorkingCopy.diff(for: "file.txt", staged: false, in: root)
		let patch = GitPatch.parse(diff)
		guard let addition = patch.hunks[0].lines.firstIndex(where: { $0.kind == .added }) else {
			Issue.record("no addition in diff")
			return
		}
		var index = 0
		var flat = 0
		for line in patch.hunks[0].lines {
			if index == addition { break }
			index += 1
			flat += 1
		}

		let result = await GitWorkingCopy.stage(lines: [flat], ofDiff: diff, in: root)
		#expect(result.exitCode == 0, "\(result.stderr)")

		let staged = await GitWorkingCopy.diff(for: "file.txt", staged: true, in: root)
		#expect(staged.contains("+ADDED"))
		// "remove" is still in the index: its deletion was not selected.
		#expect(!staged.contains("-remove"))
	}

	@Test func stagingAWholeHunkWorks() async throws {
		let root = try await makeRepository(contents: "a\nb\nc\n")
		try write("a\nX\nY\nc\n", to: root)

		let diff = await GitWorkingCopy.diff(for: "file.txt", staged: false, in: root)
		let patch = GitPatch.parse(diff)
		let result = await GitWorkingCopy.stage(
			lines: Set(patch.indices(inHunk: 0)),
			ofDiff: diff,
			in: root
		)
		#expect(result.exitCode == 0, "\(result.stderr)")

		let status = await GitWorkingCopy.status(in: root)
		#expect(status.staged.map(\.path) == ["file.txt"])
		#expect(status.unstaged.isEmpty)
	}

	@Test func unstagingOneLineReversesOnlyThatLine() async throws {
		let root = try await makeRepository(contents: "a\nb\nc\n")
		try write("a\nFIRST\nb\nSECOND\nc\n", to: root)
		await GitWorkingCopy.stage(paths: ["file.txt"], in: root)

		let staged = await GitWorkingCopy.diff(for: "file.txt", staged: true, in: root)
		let selectable = GitPatch.parse(staged).selectableIndices()
		#expect(selectable.count == 2)

		let result = await GitWorkingCopy.unstage(
			lines: [selectable[0]],
			ofDiff: staged,
			in: root
		)
		#expect(result.exitCode == 0, "\(result.stderr)")

		let remaining = await GitWorkingCopy.diff(for: "file.txt", staged: true, in: root)
		#expect(!remaining.contains("+FIRST"))
		#expect(remaining.contains("+SECOND"))
	}

	/// Several hunks, staging from only the later one — the case where reusing
	/// the original post-image line numbers produces a patch git rejects.
	@Test func stagingFromALaterHunkApplies() async throws {
		let lines = (1...40).map(String.init).joined(separator: "\n") + "\n"
		let root = try await makeRepository(contents: lines)

		var edited = (1...40).map(String.init)
		edited[2] = "EARLY"
		edited[35] = "LATE"
		try write(edited.joined(separator: "\n") + "\n", to: root)

		let diff = await GitWorkingCopy.diff(for: "file.txt", staged: false, in: root)
		let patch = GitPatch.parse(diff)
		#expect(patch.hunks.count == 2)

		let result = await GitWorkingCopy.stage(
			lines: Set(patch.indices(inHunk: 1)),
			ofDiff: diff,
			in: root
		)
		#expect(result.exitCode == 0, "\(result.stderr)")

		let staged = await GitWorkingCopy.diff(for: "file.txt", staged: true, in: root)
		#expect(staged.contains("+LATE"))
		#expect(!staged.contains("+EARLY"))
	}

	/// Non-ASCII paths are what broke plain file staging: git escapes them in
	/// its default output and the escaped form matches nothing.
	@Test func pathsWithNonASCIICharactersCanBeStaged() async throws {
		let root = try await makeRepository(contents: "x\n")
		let name = "kühlschrank-türe/abdeckung.3mf"
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("kühlschrank-türe"),
			withIntermediateDirectories: true
		)
		try "content\n".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)

		let before = await GitWorkingCopy.status(in: root)
		#expect(before.unstaged.map(\.path) == [name])

		let result = await GitWorkingCopy.stage(paths: [name], in: root)
		#expect(result.exitCode == 0, "\(result.stderr)")

		let after = await GitWorkingCopy.status(in: root)
		#expect(after.staged.map(\.path) == [name])
	}
}

/// The decoder used when git was not asked for -z output.
struct GitPathUnquoteTests {
	@Test func octalEscapesDecodeAsUTF8() {
		#expect(GitWorkingCopy.unquote(#""k\303\274hlschrank""#) == "kühlschrank")
	}

	@Test func multiByteSequencesAreDecodedTogether() {
		// Decoding each octal triple on its own would give two Latin-1
		// characters rather than the one they encode.
		#expect(GitWorkingCopy.unquote(#""\342\234\223""#) == "✓")
	}

	@Test func namedEscapesAreHandled() {
		#expect(GitWorkingCopy.unquote(#""a\tb""#) == "a\tb")
		#expect(GitWorkingCopy.unquote(#""a\"b""#) == "a\"b")
		#expect(GitWorkingCopy.unquote(##""a\\b""##) == #"a\b"#)
	}

	@Test func unquotedPathsPassThrough() {
		#expect(GitWorkingCopy.unquote("plain/path.txt") == "plain/path.txt")
	}
}

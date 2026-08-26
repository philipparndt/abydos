import Foundation
import Testing
@testable import AbydosKit

/// Widening a diff until it is the whole file.
///
/// **The advantage a review in an editor has.** A browser shows three lines
/// either side of a change; here the file is on disk with a language server
/// pointed at it, and the question a reviewer actually has is usually about the
/// code around the change rather than the change.
struct WholeFileDiffTests {
	private let file = """
	one
	two
	three
	four
	five
	"""

	/// git's own output for changing line three of that file.
	private let diff = """
	diff --git a/count.txt b/count.txt
	index 111..222 100644
	--- a/count.txt
	+++ b/count.txt
	@@ -2,3 +2,3 @@
	 two
	-drei
	+three
	 four
	"""

	@Test func theFileIsThereWithTheChangeInIt() throws {
		let wide = try #require(WholeFileDiff.expand(diff: diff, contents: file))
		let lines = wide.split(separator: "\n").map(String.init)

		// One hunk, covering the file from its first line.
		#expect(lines.filter { $0.hasPrefix("@@") } == ["@@ -1,5 +1,5 @@"])
		// The lines the narrow diff never showed.
		#expect(lines.contains(" one"))
		#expect(lines.contains(" five"))
		// And the change itself, exactly as git wrote it.
		#expect(lines.contains("-drei"))
		#expect(lines.contains("+three"))
	}

	/// The header travels, so the widened diff still says which file it is.
	@Test func theHeaderIsKept() throws {
		let wide = try #require(WholeFileDiff.expand(diff: diff, contents: file))
		#expect(wide.hasPrefix("diff --git a/count.txt b/count.txt"))
	}

	/// The counts have to add up or nothing downstream can number the lines: the
	/// old side is the file with the deletion in it and the addition out.
	@Test func theCountsAreOfWhatIsActuallyThere() throws {
		let wide = try #require(WholeFileDiff.expand(diff: diff, contents: file))
		let patch = GitPatch.parse(wide)
		let hunk = try #require(patch.hunks.first)

		#expect(hunk.oldStart == 1)
		#expect(hunk.newStart == 1)
		#expect(hunk.lines.filter { $0.kind == .context }.count == 4)
		#expect(hunk.lines.filter { $0.kind == .added }.count == 1)
		#expect(hunk.lines.filter { $0.kind == .removed }.count == 1)
	}

	/// Two changes in one file, with untouched code between and around them.
	@Test func severalHunksAreSplicedInOrder() throws {
		let contents = (1...10).map { "line \($0)" }.joined(separator: "\n")
		let diff = """
		diff --git a/x b/x
		--- a/x
		+++ b/x
		@@ -2,1 +2,1 @@
		-was two
		+line 2
		@@ -8,1 +8,1 @@
		-was eight
		+line 8
		"""
		let wide = try #require(WholeFileDiff.expand(diff: diff, contents: contents))
		let patch = GitPatch.parse(wide)
		let hunk = try #require(patch.hunks.first)

		#expect(patch.hunks.count == 1)
		#expect(hunk.lines.filter { $0.kind == .added }.map(\.text) == ["line 2", "line 8"])
		// Everything else is context, including the six lines between them.
		#expect(hunk.lines.filter { $0.kind == .context }.count == 8)
	}

	/// A file that ends in a newline splits with a trailing empty piece, which
	/// is not a line of the file — counting it would put a phantom line on the
	/// end of every whole-file view.
	@Test func aTrailingNewlineIsNotALine() throws {
		let wide = try #require(WholeFileDiff.expand(diff: diff, contents: file + "\n"))
		#expect(wide.contains("@@ -1,5 +1,5 @@"))
	}

	/// **Nil rather than a guess.** A patch whose line numbers do not fit the
	/// text handed in is a mismatch — a stale head, a file fetched at the wrong
	/// ref — and the ordinary diff, which is never wrong, is what the page then
	/// draws.
	@Test func aPatchThatDoesNotFitIsRefused() {
		#expect(WholeFileDiff.expand(diff: diff, contents: "one\ntwo") == nil)
		// A deletion has no new side at all.
		#expect(WholeFileDiff.expand(diff: diff, contents: "") == nil)
		// Nothing to widen.
		#expect(WholeFileDiff.expand(diff: "", contents: file) == nil)
	}

	/// An addition at the very end of a file, which is the off-by-one every
	/// splice of this shape gets wrong first.
	@Test func aLineAddedAtTheEnd() throws {
		let contents = "one\ntwo\nthree"
		let diff = """
		diff --git a/x b/x
		--- a/x
		+++ b/x
		@@ -2,1 +2,2 @@
		 two
		+three
		"""
		let wide = try #require(WholeFileDiff.expand(diff: diff, contents: contents))
		let patch = GitPatch.parse(wide)
		let hunk = try #require(patch.hunks.first)
		#expect(hunk.lines.map(\.rendered) == [" one", " two", "+three"])
	}
}

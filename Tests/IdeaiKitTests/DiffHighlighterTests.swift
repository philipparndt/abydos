import Foundation
import Testing
@testable import IdeaiKit

/// Syntax highlighting for a diff, which is two programs interleaved.
struct DiffHighlighterTests {
	private func patch(_ text: String) -> GitPatch {
		GitPatch.parse(text)
	}

	private let sample = """
	diff --git a/main.swift b/main.swift
	--- a/main.swift
	+++ b/main.swift
	@@ -1,4 +1,4 @@
	 func greet() {
	-    let name = "old"
	+    let name = "new"
	     print(name)
	 }
	"""

	@Test func colourersBothSidesOfAChange() {
		let tokens = DiffHighlighter.highlight(patch(sample), languageId: "swift")

		// The removed line is only in the old reconstruction, the added one only
		// in the new; both must come back with something.
		let removed = tokens[1] ?? []
		let added = tokens[2] ?? []
		#expect(!removed.isEmpty)
		#expect(!added.isEmpty)
		#expect(added.contains { $0.kind == .keyword })
		#expect(added.contains { $0.kind == .string })
	}

	/// Offsets are within the line, not within the reconstruction: a view draws
	/// one line at a time and knows nothing of where it sat.
	@Test func rangesAreRelativeToTheirLine() {
		let tokens = DiffHighlighter.highlight(patch(sample), languageId: "swift")
		let added = tokens[2] ?? []
		let line = "    let name = \"new\""

		for token in added {
			#expect(token.range.lowerBound >= 0)
			#expect(token.range.upperBound <= line.utf8.count)
		}

		// `let` sits at offset 4 on that line.
		let keyword = added.first { $0.kind == .keyword }
		#expect(keyword?.range == 4..<7)
	}

	@Test func leavesUnknownLanguagesAlone() {
		#expect(DiffHighlighter.highlight(patch(sample), languageId: "not-a-language").isEmpty)
	}

	@Test func survivesAnEmptyPatch() {
		#expect(DiffHighlighter.highlight(GitPatch(), languageId: "swift").isEmpty)
	}

	/// Context lines belong to both sides and are coloured once.
	@Test func coloursContextLines() {
		let tokens = DiffHighlighter.highlight(patch(sample), languageId: "swift")
		#expect(tokens[0]?.contains { $0.kind == .keyword } == true)
	}

	/// A string that runs over a line break colours every line it covers.
	@Test func spansTokensAcrossLines() {
		let multiline = """
		diff --git a/a.swift b/a.swift
		--- a/a.swift
		+++ b/a.swift
		@@ -1,3 +1,3 @@
		+let text = \"\"\"
		+    hello
		+    \"\"\"
		"""
		let tokens = DiffHighlighter.highlight(patch(multiline), languageId: "swift")
		// The middle line is nothing but string, and must not come back bare.
		#expect(tokens[1]?.isEmpty == false)
	}
}

/// Offsets survive characters that are more than one byte.
struct DiffHighlighterUnicodeTests {
	@Test func countsInUTF16LikeTheEngineDoes() {
		let patch = GitPatch.parse("""
		diff --git a/a.swift b/a.swift
		--- a/a.swift
		+++ b/a.swift
		@@ -1,2 +1,2 @@
		+let café = "über"
		+let plain = 1
		""")
		let tokens = DiffHighlighter.highlight(patch, languageId: "swift")

		// `let` opens both lines, and on the second it must still be at 0 —
		// the accented line before it must not have shifted anything.
		#expect(tokens[0]?.first { $0.kind == .keyword }?.range == 0..<3)
		#expect(tokens[1]?.first { $0.kind == .keyword }?.range == 0..<3)

		// Every range has to land inside the line it belongs to.
		let lines = ["let café = \"über\"", "let plain = 1"]
		for (index, line) in lines.enumerated() {
			for token in tokens[index] ?? [] {
				#expect(token.range.upperBound <= line.utf16.count)
			}
		}
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// A selection of several rows surviving the tree being rebuilt underneath it.
///
/// The navigator reloads on every filesystem event, so a build writing files
/// rebuilds it dozens of times a minute. Everything here is about the reload
/// giving back what was selected rather than the first of it.
struct TreeSelectionTests {
	/// A tree, as rows: the path at each index. A reload is a different one.
	private struct Tree {
		let rows: [String]

		func path(at row: Int) -> String? {
			rows.indices.contains(row) ? rows[row] : nil
		}

		func row(of path: String) -> Int {
			rows.firstIndex(of: path) ?? -1
		}
	}

	private let before = Tree(rows: [
		"/p", "/p/Sources", "/p/Sources/a.swift", "/p/Sources/b.swift", "/p/README.md",
	])

	/// The one that bites: three rows selected, a file written, and all three
	/// still selected afterwards even though every index moved.
	@Test func severalRowsSurviveAReloadThatRenumbersThem() {
		let selected = TreeSelection.paths(rows: [2, 3, 4]) { before.path(at: $0) }
		#expect(selected == ["/p/Sources/a.swift", "/p/Sources/b.swift", "/p/README.md"])

		// A build drops a file in at the top, so every row after it shifts.
		let after = Tree(rows: [
			"/p", "/p/build.log", "/p/Sources", "/p/Sources/a.swift", "/p/Sources/b.swift",
			"/p/README.md",
		])
		let restored = TreeSelection.rows(for: selected) { after.row(of: $0) }
		#expect(restored == [3, 4, 5])
		#expect(restored.count == selected.count, "the selection must not shrink")
	}

	/// One of them is trashed while the others are still selected: the rest come
	/// back, and the missing one does not take them with it.
	@Test func aPathThatWentAwayDoesNotTakeTheOthersWithIt() {
		let selected = ["/p/Sources/a.swift", "/p/gone.swift", "/p/README.md"]
		let restored = TreeSelection.rows(for: selected) { before.row(of: $0) }
		#expect(restored == [2, 4])
	}

	/// Tree order, not the order they were clicked — which is what "copy these
	/// paths" means and what a reload gives back regardless.
	@Test func theOrderIsTheTreeSRatherThanTheClicks() {
		let selected = TreeSelection.paths(rows: [4, 2, 3]) { before.path(at: $0) }
		#expect(selected == ["/p/Sources/a.swift", "/p/Sources/b.swift", "/p/README.md"])
	}

	/// The single-row case is the same code, so arrowing through the tree keeps
	/// working exactly as it did.
	@Test func oneRowIsStillOneRow() {
		let selected = TreeSelection.paths(rows: [3]) { before.path(at: $0) }
		#expect(selected == ["/p/Sources/b.swift"])
		#expect(TreeSelection.rows(for: selected) { before.row(of: $0) } == [3])
	}

	/// Nothing selected stays nothing, rather than becoming the root.
	@Test func nothingSelectedStaysNothing() {
		#expect(TreeSelection.paths(rows: []) { before.path(at: $0) }.isEmpty)
		#expect(TreeSelection.rows(for: []) { before.row(of: $0) }.isEmpty)
	}

	/// Two paths that have collapsed onto the same row — a folder closed over
	/// both of them — select that row once rather than twice.
	@Test func twoPathsLandingOnOneRowSelectItOnce() {
		let restored = TreeSelection.rows(for: ["/p/Sources", "/p/Sources"]) { before.row(of: $0) }
		#expect(restored == [1])
	}
}

/// Where the selection goes when rows are deleted.
///
/// It used to go to the top of the tree, which is a long way from where somebody
/// was working — and the next keystroke then acts on something they cannot see.
struct TreeSelectionAfterDeleteTests {
	/// A folder at row 1 with three children under it, the way the rows read.
	private let rows = [
		"/p",              // 0  the project root
		"/p/Sources",      // 1
		"/p/Sources/a.swift", // 2
		"/p/Sources/b.swift", // 3
		"/p/Sources/c.swift", // 4
		"/p/README.md",    // 5
	]

	private func path(_ row: Int) -> String? {
		rows.indices.contains(row) ? rows[row] : nil
	}

	@Test func theSiblingAboveTakesTheSelection() {
		#expect(TreeSelection.surviving(above: [3], path: path) == "/p/Sources/a.swift")
	}

	/// No sibling above, so the folder holding it — which is the row above, so
	/// the same movement finds it.
	@Test func theFirstChildHandsBackToItsParent() {
		#expect(TreeSelection.surviving(above: [2], path: path) == "/p/Sources")
	}

	/// Three deleted at once lands above all of them, not between them.
	@Test func aRunOfRowsStepsOverItself() {
		#expect(TreeSelection.surviving(above: [2, 3, 4], path: path) == "/p/Sources")
	}

	/// A selection with a gap anchors above the *topmost* row going, not on the
	/// survivor between them.
	///
	/// Rows 3 and 5 go and row 4 stays, so "nearest survivor" and "above them
	/// all" disagree — and above is the one that is predictable. Where the
	/// selection lands should depend on where the deletion started, not on which
	/// rows happened to be skipped in the middle of it.
	@Test func aSelectionWithAGapAnchorsAboveTheTopmost() {
		#expect(TreeSelection.surviving(above: [3, 5], path: path) == "/p/Sources/a.swift")
	}

	/// Nothing above the first row, and the top is then the right answer.
	@Test func deletingTheFirstRowHasNowhereToGo() {
		#expect(TreeSelection.surviving(above: [0], path: path) == nil)
	}

	@Test func deletingNothingMovesNothing() {
		#expect(TreeSelection.surviving(above: [], path: path) == nil)
	}

	// MARK: - Staging, which empties rows exactly as deleting does

	/// **Staging is a deletion from the list it was in**, so where the
	/// selection lands is the same question and gets the same answer. Written
	/// from the two cases as they were put:
	///
	///     a
	///      - b
	///      - c  ← selected, and staged
	///      - d
	///
	/// The row above `c` is `b`, and that is where the selection goes — not
	/// `d`, and not the top of the list.
	@Test func stagingAMiddleChildSelectsTheOneAboveIt() {
		let rows = ["a", "a/b", "a/c", "a/d"]
		#expect(
			TreeSelection.surviving(above: [2], path: { rows.indices.contains($0) ? rows[$0] : nil })
				== "a/b"
		)
	}

	/// The second case, and the one that says why "the row above" is the whole
	/// rule rather than "the sibling above":
	///
	///     a
	///      - b  ← selected, and staged
	///      - c
	///
	/// `b` has no sibling above it, and the row above it is its parent. One
	/// walk up the visible rows gives both without knowing which it is.
	@Test func stagingTheFirstChildSelectsItsParent() {
		let rows = ["a", "a/b", "a/c"]
		#expect(
			TreeSelection.surviving(above: [1], path: { rows.indices.contains($0) ? rows[$0] : nil })
				== "a"
		)
	}

	/// A folder staged as one gesture takes its children with it, and the
	/// selection still lands on the row above the folder rather than inside
	/// what has gone.
	@Test func stagingAFolderLandsAboveTheFolder() {
		let rows = ["a", "a/b", "a/c", "a/c/one", "a/c/two", "a/d"]
		#expect(
			TreeSelection.surviving(above: [2, 3, 4], path: { rows.indices.contains($0) ? rows[$0] : nil })
				== "a/b"
		)
	}

	/// **The case where above is not enough**, as it was reported:
	///
	///     .vscode
	///       launch.json  ← selected, and staged
	///     CLAUDE.md      ← expected afterwards
	///
	/// Staging the only file in a folder empties the folder, so the row above
	/// the selection goes as well. Nothing survives upwards and the answer is
	/// the row below.
	@Test func theOnlyFileInAFolderFallsToTheRowBelow() {
		let rows = [".vscode", ".vscode/launch.json", "CLAUDE.md"]
		let at: (Int) -> String? = { rows.indices.contains($0) ? rows[$0] : nil }
		// Above answers the folder, which is about to stop existing too — the
		// caller finds that out when it looks the path up and cannot.
		#expect(TreeSelection.surviving(above: [1], path: at) == ".vscode")
		#expect(TreeSelection.surviving(below: [1], rowCount: rows.count, path: at) == "CLAUDE.md")
	}

	/// The last row in the list has nothing below it, and above is then the
	/// answer — which is what it was for.
	@Test func theLastRowHasNothingBelowIt() {
		let rows = ["a", "a/b", "a/c"]
		let at: (Int) -> String? = { rows.indices.contains($0) ? rows[$0] : nil }
		#expect(TreeSelection.surviving(below: [2], rowCount: rows.count, path: at) == nil)
		#expect(TreeSelection.surviving(above: [2], path: at) == "a/b")
	}

	/// A run going out of the middle skips over itself downwards too.
	@Test func aRunFallsPastAllOfItself() {
		let rows = ["a", "b", "c", "d", "e"]
		let at: (Int) -> String? = { rows.indices.contains($0) ? rows[$0] : nil }
		#expect(TreeSelection.surviving(below: [1, 2, 3], rowCount: rows.count, path: at) == "e")
	}
}


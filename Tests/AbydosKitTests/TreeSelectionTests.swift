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

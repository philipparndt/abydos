import Foundation
import Testing
@testable import AbydosKit

/// Slash-separated names as the tree they describe.
///
/// The claims that matter are about folding, because the two callers want
/// opposite things from it and the parameter exists to keep them from being two
/// implementations that drift.
struct PathTreeTests {
	private func items(_ paths: [String]) -> [(path: String, payload: String)] {
		paths.map { (path: $0, payload: $0) }
	}

	private func shape(_ nodes: [PathNode<String>], indent: Int = 0) -> String {
		nodes.map { node in
			String(repeating: "  ", count: indent)
				+ node.name
				+ (node.isFolder ? "/ (\(node.count))" : "")
				+ (node.children.isEmpty ? "" : "\n" + shape(node.children, indent: indent + 1))
		}.joined(separator: "\n")
	}

	@Test func namesWithNoSlashInThemAreRootsOfTheirOwn() {
		let tree = PathTree.build(items(["main", "develop"]))
		#expect(shape(tree) == "develop\nmain")
	}

	@Test func twoBranchesUnderOnePrefixFold() {
		let tree = PathTree.build(items(["feature/tags", "feature/stash-preview"]), folding: true)
		#expect(shape(tree) == """
		feature/ (2)
		  stash-preview
		  tags
		""")
	}

	/// A folder that exists to hold one row has turned one row into two and
	/// said nothing: there is no such thing as checking out a folder.
	@Test func aPrefixWithOneBranchUnderItStaysFlat() {
		let tree = PathTree.build(items(["hotfix/0472", "main"]), folding: true)
		// Folded, it is a leaf and not a folder, so it takes its place among
		// the leaves in name order rather than above them.
		#expect(shape(tree) == "hotfix/0472\nmain")
	}

	/// And all the way down, in one pass rather than a half-folded chain.
	@Test func aChainOfSingleChildrenBecomesOneRow() {
		let tree = PathTree.build(items(["a/b/c/thing"]), folding: true)
		#expect(shape(tree) == "a/b/c/thing")
		#expect(tree.first?.path == "a/b/c/thing", "the path is what git is given, and is untouched")
	}

	/// The changes tree wants the opposite, and says why: folding would make a
	/// row that is not a folder, and take away the row that stages the outer
	/// folder on its own.
	@Test func withoutFoldingAChainStaysAChain() {
		let tree = PathTree.build(items(["Sources/AbydosKit/Git/GitBlame.swift"]))
		#expect(shape(tree) == """
		Sources/ (1)
		  AbydosKit/ (1)
		    Git/ (1)
		      GitBlame.swift
		""")
	}

	@Test func aFolderSaysHowManyAreUnderIt() {
		let tree = PathTree.build(
			items(["feature/a", "feature/b", "feature/deep/c", "main"]), folding: true
		)
		guard let feature = tree.first(where: { $0.name == "feature" }) else {
			Issue.record("expected a feature folder, got \(shape(tree))")
			return
		}
		#expect(feature.count == 3, "leaves beneath, at any depth")
	}

	/// The branch you are on is the one you look for, and it should not be four
	/// rows down its own list.
	@Test func aPromotedLeafComesFirst() {
		let tree = PathTree.build(
			items(["zebra", "main", "feature/x", "feature/y"]),
			folding: true,
			promoting: { $0 == "main" ? 0 : nil }
		)
		#expect(tree.first?.name == "main")
	}

	/// Two branches are looked for and they have an order between them: the one
	/// you are on, then the one everything merges into. A flag could say *both
	/// of these go first* and not *this one of them goes first*, which is why
	/// the rank replaced it.
	@Test func promotedLeavesKeepTheirOwnOrder() {
		let tree = PathTree.build(
			items(["zebra", "main", "alpha", "feature/x", "feature/y"]),
			folding: true,
			promoting: { name in
				if name == "zebra" { return 0 }
				if name == "main" { return 1 }
				return nil
			}
		)
		#expect(tree.map(\.name).prefix(2) == ["zebra", "main"])
		// And everything else keeps the arrangement it had: folders, then names.
		#expect(Array(tree.map(\.name).dropFirst(2)) == ["feature", "alpha"])
	}

	/// The refs tree's tags want newest first, and the order is a parameter of
	/// this one builder precisely so it cannot become a second builder.
	@Test func leavesTakeTheOrderTheyAreGiven() {
		let dates = ["old": 1, "newer": 2, "newest": 3]
		let tree = PathTree.build(
			items(["old", "newest", "newer"]),
			ordering: { (dates[$0] ?? 0) > (dates[$1] ?? 0) }
		)
		#expect(tree.map(\.name) == ["newest", "newer", "old"])
	}

	/// A folder has no date: it keeps its place before the leaves and its name
	/// order among its fellow folders, and only what is under it takes the
	/// given order.
	@Test func foldersKeepTheirPlaceUnderALeafOrder() {
		let dates = ["release/one": 1, "release/two": 5, "zz-old": 0, "aa-new": 9]
		let tree = PathTree.build(
			items(["zz-old", "aa-new", "release/one", "release/two"]),
			ordering: { (dates[$0] ?? 0) > (dates[$1] ?? 0) }
		)
		#expect(tree.map(\.name) == ["release", "aa-new", "zz-old"])
		#expect(tree.first?.children.map(\.name) == ["two", "one"], "the order holds inside a folder")
	}

	@Test func promotionStillBeatsTheGivenOrder() {
		let tree = PathTree.build(
			items(["b", "a", "current"]),
			promoting: { $0 == "current" ? 0 : nil },
			ordering: { $0 > $1 }
		)
		#expect(tree.map(\.name) == ["current", "b", "a"])
	}

	/// **A folder that is an object cannot be flattened, because its verbs go
	/// with it.** `backup/` is made by this program and the refs tree gives it
	/// a verb of its own — deleting the entries older than a given age. Folded
	/// away, one backup ref meant no backup folder and no way to sweep it.
	@Test func aFolderNamedInItsOwnRightKeepsItsRowWithOneChild() {
		let tree = PathTree.build(
			items(["backup/2026-08-25-1607-main", "main"]),
			folding: true,
			keeping: ["backup"]
		)
		#expect(shape(tree) == """
			backup/ (1)
			  2026-08-25-1607-main
			main
			""")
	}

	/// The rule it is an exception to, unchanged: a prefix that merely happened
	/// to be shared turns one row into two and says nothing.
	@Test func aPrefixThatIsOnlyAPrefixStillFolds() {
		let tree = PathTree.build(
			items(["hotfix/0472", "main"]),
			folding: true,
			keeping: ["backup"]
		)
		#expect(shape(tree) == "hotfix/0472\nmain")
	}

	/// Kept folders are matched by name, not by path, so one nested under
	/// something else is still the folder the tree names.
	@Test func aKeptFolderIsFoundWhereverItSits() {
		let tree = PathTree.build(
			items(["refs/backup/only"]),
			folding: true,
			keeping: ["backup"]
		)
		#expect(shape(tree) == """
			refs/backup/ (1)
			  only
			""")
	}

	@Test func foldersComeBeforeLeavesAndThenNameOrder() {
		let tree = PathTree.build(items(["b/one", "b/two", "a/one", "a/two", "zzz", "aaa"]))
		#expect(tree.map(\.name) == ["a", "b", "aaa", "zzz"])
	}

	@Test func everyNodeCanBeFoundByItsPathAgain() {
		let tree = PathTree.build(items(["feature/a", "feature/b", "main"]), folding: true)
		let found = PathTree.index(tree)
		#expect(found["feature"]?.isFolder == true)
		#expect(found["feature/a"]?.payload == "feature/a")
		#expect(found["main"]?.payload == "main")
	}

	/// Nothing to draw is not a crash, and is not one empty folder either.
	@Test func nothingAtAllIsNoRows() {
		#expect(PathTree.build(items([]), folding: true).isEmpty)
	}
}

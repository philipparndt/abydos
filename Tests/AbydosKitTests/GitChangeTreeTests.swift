import Foundation
import Testing
@testable import AbydosKit

/// The changes pane's tree: which folders exist, what a folder says about
/// itself, and what staging one hands to git.
///
/// The view is in the app target and the suite cannot reach it, so everything
/// here is the part that can be claimed without a window — which is why the
/// tree is built in the kit rather than inside the pane.
struct GitChangeTreeTests {
	private func change(_ path: String, _ kind: GitChange.Kind = .modified, staged: Bool = false) -> GitChange {
		GitChange(path: path, kind: kind, isStaged: staged)
	}

	/// The rows the tree would draw, top to bottom, as `path` for a file and
	/// `path/` for a folder.
	private func rows(_ nodes: [GitChangeNode]) -> [String] {
		nodes.flatMap { node -> [String] in
			node.isFolder ? ["\(node.path)/"] + rows(node.children) : [node.path]
		}
	}

	// MARK: - Which folders exist

	@Test func onlyFoldersWithAChangeUnderThemAreRows() {
		let tree = GitChangeTree.build([
			change("Sources/AbydosKit/Git/GitBlame.swift"),
			change("Makefile"),
		])

		// No `Sources/AbydosApp`, no `Tests`: nothing has changed in them, and
		// the point of the tree is to be shorter than the flat list, not longer.
		#expect(rows(tree) == [
			"Sources/",
			"Sources/AbydosKit/",
			"Sources/AbydosKit/Git/",
			"Sources/AbydosKit/Git/GitBlame.swift",
			"Makefile",
		])
	}

	/// Folders before files, then name order — `FileNode.order`, so the two
	/// trees in the window agree about what comes first.
	@Test func foldersComeBeforeFilesAndThenNameOrder() {
		let tree = GitChangeTree.build([
			change("README.md"),
			change("Makefile"),
			change("Tests/a.swift"),
			change("Sources/b.swift"),
		])
		#expect(rows(tree) == [
			"Sources/", "Sources/b.swift",
			"Tests/", "Tests/a.swift",
			"Makefile", "README.md",
		])
	}

	/// A chain of single-child folders stays a chain. Deliberate: see the
	/// comment on `GitChangeTree`.
	@Test func aChainOfSingleChildFoldersIsNotCollapsed() {
		let tree = GitChangeTree.build([change("a/b/c/d.swift")])
		#expect(rows(tree) == ["a/", "a/b/", "a/b/c/", "a/b/c/d.swift"])
	}

	// MARK: - What a folder says

	@Test func aFolderCountsTheChangesUnderIt() {
		let tree = GitChangeTree.build([
			change("Sources/Git/a.swift"),
			change("Sources/Git/b.swift"),
			change("Sources/c.swift"),
		])
		let sources = tree[0]
		#expect(sources.path == "Sources")
		#expect(sources.count == 3)
		#expect(!sources.isPartial)
	}

	/// The one a folder row exists to say: some of what changed under here is
	/// not on this side of the index. Two lists make a folder in "Staged" look
	/// finished, and somebody who reads it that way commits half of it.
	@Test func aFolderWithChangesOnTheOtherSideIsPartial() {
		let staged = GitChangeTree.build(
			[change("Sources/a.swift", staged: true)],
			against: [change("Sources/b.swift"), change("Sources/c.swift")]
		)
		#expect(staged[0].count == 1)
		#expect(staged[0].total == 3)
		#expect(staged[0].isPartial)

		// And the same folder in the other list says the mirror of it.
		let unstaged = GitChangeTree.build(
			[change("Sources/b.swift"), change("Sources/c.swift")],
			against: [change("Sources/a.swift", staged: true)]
		)
		#expect(unstaged[0].count == 2)
		#expect(unstaged[0].total == 3)
		#expect(unstaged[0].isPartial)
	}

	/// A file staged and then edited again is one path in both lists. Counting
	/// distinct paths would call its folder whole, and a commit would leave the
	/// second edit behind — so entries are counted, not paths.
	@Test func aFileStagedAndEditedAgainLeavesItsFolderPartial() {
		let staged = GitChangeTree.build(
			[change("Sources/a.swift", staged: true)],
			against: [change("Sources/a.swift")]
		)
		#expect(staged[0].count == 1)
		#expect(staged[0].total == 2)
		#expect(staged[0].isPartial)
	}

	/// The other side is counted once, at the deepest folder this tree has —
	/// not at every level above it, which would have said a folder three deep
	/// held three changes it does not have.
	@Test func aDeepChangeOnTheOtherSideIsCountedOnceNotOncePerLevel() {
		let tree = GitChangeTree.build(
			[change("a/b/c/one.swift")],
			against: [change("a/b/c/two.swift")]
		)
		let a = tree[0]
		#expect(a.count == 1)
		#expect(a.total == 2)
		#expect(a.children[0].total == 2)          // a/b
		#expect(a.children[0].children[0].total == 2)  // a/b/c
	}

	/// A change on the other side under a folder this tree has never heard of
	/// is counted against the nearest folder it does have, rather than
	/// inventing an empty row that would stage nothing.
	@Test func theOtherSideUnderAnUnknownFolderCountsAgainstTheNearestKnownOne() {
		let tree = GitChangeTree.build(
			[change("Sources/a.swift")],
			against: [change("Sources/Deep/b.swift")]
		)
		#expect(rows(tree) == ["Sources/", "Sources/a.swift"])
		#expect(tree[0].total == 2)
		#expect(tree[0].isPartial)
	}

	/// A file row is never partial. It is the same file in both lists, which is
	/// what two lists are for; saying it twice on the row as well is noise.
	@Test func aFileRowIsNeverPartial() {
		let tree = GitChangeTree.build(
			[change("a.swift", staged: true)],
			against: [change("a.swift")]
		)
		#expect(!tree[0].isPartial)
	}

	// MARK: - What is handed to git

	/// A folder and the files under it is one argument, because the folder
	/// already covers them.
	@Test func aSelectedFolderSwallowsTheFilesSelectedUnderIt() {
		let reduced = GitChangeTree.reduce([
			"Sources",
			"Sources/Git/a.swift",
			"Sources/Git",
			"Makefile",
		])
		#expect(reduced == ["Sources", "Makefile"])
	}

	@Test func unrelatedFoldersAreAllKept() {
		let reduced = GitChangeTree.reduce(["Sources/Git", "Sources/Project", "Tests"])
		#expect(reduced == ["Sources/Git", "Sources/Project", "Tests"])
	}

	/// A folder whose *name* is a prefix of another's is not its parent.
	/// `Sources` swallowing `SourcesExtra` would stage a folder nobody chose.
	@Test func aNamePrefixIsNotAParent() {
		let reduced = GitChangeTree.reduce(["Sources", "SourcesExtra/a.swift"])
		#expect(reduced == ["Sources", "SourcesExtra/a.swift"])
	}

	@Test func theSamePathTwiceIsHandedOverOnce() {
		#expect(GitChangeTree.reduce(["a.swift", "a.swift"]) == ["a.swift"])
	}

	// MARK: - Putting the view back together

	@Test func everyNodeCanBeFoundAgainByItsPath() {
		let tree = GitChangeTree.build([
			change("Sources/Git/a.swift"),
			change("Makefile"),
		])
		let index = GitChangeTree.index(tree)
		#expect(index["Sources"]?.isFolder == true)
		#expect(index["Sources/Git"]?.isFolder == true)
		#expect(index["Sources/Git/a.swift"]?.change?.path == "Sources/Git/a.swift")
		#expect(index["Makefile"]?.isFolder == false)
		#expect(index["Tests"] == nil)
	}

	/// Nothing changed is no rows at all, rather than a root that draws as an
	/// empty folder.
	@Test func nothingChangedIsNoRows() {
		#expect(GitChangeTree.build([]).isEmpty)
	}
}

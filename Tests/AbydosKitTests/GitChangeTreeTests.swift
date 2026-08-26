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

	private func directory(_ path: String, staged: Bool = false) -> GitChange {
		// What `-unormal` hands back for a wholly untracked folder: one entry,
		// its path, and the flag that says it is a directory.
		GitChange(path: path, kind: .untracked, isStaged: staged, isDirectory: true)
	}

	// MARK: - What a row is

	/// The reported fault, at the level it is decided: an untracked directory
	/// was drawn as a file because `isFolder` asks whether the row was invented,
	/// and this one was not.
	@Test func anUntrackedDirectoryHoldsFilesWithoutBeingAnInventedFolder() throws {
		let tree = GitChangeTree.build([directory("PI-12")])
		let row = try #require(tree.first)

		#expect(row.holdsFiles == true, "it is a directory and must draw as one")
		#expect(row.isFolder == false, "git reported it; this tree did not invent it")
	}

	@Test func anUntrackedFileHoldsNothing() {
		let tree = GitChangeTree.build([change("notes.md", .untracked)])
		#expect(tree.first?.holdsFiles == false)
		#expect(tree.first?.isFolder == false)
	}

	@Test func anInventedFolderBothHoldsFilesAndIsOne() {
		let tree = GitChangeTree.build([change("Sources/AbydosKit/Git/GitBlame.swift")])
		#expect(tree.first?.holdsFiles == true)
		#expect(tree.first?.isFolder == true)
	}

	/// The reason `isFolder` was left alone. Git reports the whole directory as
	/// one entry, so it counts as one change and is never partly staged — and
	/// widening `isFolder` would have said "1 of 12" about a row that is wholly
	/// unstaged.
	@Test func anUntrackedDirectoryIsOneChangeAndNeverPartial() throws {
		let tree = GitChangeTree.build([directory("PI-12")], against: [])
		let row = try #require(tree.first)
		#expect(row.count == 1)
		#expect(row.total == 1)
		#expect(row.isPartial == false)
	}

	/// Drawn as a folder, so it sorts with them.
	@Test func anUntrackedDirectorySortsWithTheFolders() {
		let tree = GitChangeTree.build([
			change("apple.txt"),
			directory("zebra"),
		])
		#expect(tree.map(\.name) == ["zebra", "apple.txt"])
	}

	// MARK: - How much changed

	@Test func aFolderSumsTheLinesUnderIt() {
		let tree = GitChangeTree.build([
			change("Sources/A.swift"),
			change("Sources/B.swift"),
		])
		tree.first?.applyLineCounts([
			"Sources/A.swift": GitLineCount(added: 12, removed: 3),
			"Sources/B.swift": GitLineCount(added: 4, removed: 1),
		])
		#expect(tree.first?.lines == GitLineCount(added: 16, removed: 4))
		#expect(tree.first?.children.first?.lines == GitLineCount(added: 12, removed: 3))
	}

	/// Git gives no count for a binary file, and zero would be a claim that
	/// nothing changed.
	@Test func aRowGitWillNotCountSaysNothing() {
		let tree = GitChangeTree.build([change("blob.bin")])
		tree.first?.applyLineCounts([:])
		#expect(tree.first?.lines == nil)
	}

	/// A folder holding one counted file and one uncounted one says what it
	/// knows, rather than nothing or a zero for the binary.
	@Test func aFolderSumsOnlyWhatItHasCountsFor() {
		let tree = GitChangeTree.build([
			change("Sources/A.swift"),
			change("Sources/blob.bin"),
		])
		tree.first?.applyLineCounts(["Sources/A.swift": GitLineCount(added: 2, removed: 2)])
		#expect(tree.first?.lines == GitLineCount(added: 2, removed: 2))
		#expect(tree.first?.children.first { $0.name == "blob.bin" }?.lines == nil)
	}

	/// The walk being avoided: a directory nobody has opened cannot say how much
	/// changed inside it, and working it out is exactly the cost `-unormal`
	/// exists to refuse.
	@Test func anUnopenedUntrackedDirectorySaysNothingAboutLines() {
		let tree = GitChangeTree.build([directory("PI-12")])
		tree.first?.applyLineCounts(["PI-12/notes.md": GitLineCount(added: 9, removed: 0)])
		#expect(tree.first?.lines == nil, "it has not been opened, so it does not know")
	}

	@Test func anOpenedUntrackedDirectorySumsWhatTurnedUp() {
		let tree = GitChangeTree.build([directory("PI-12")])
		let row = tree.first!
		row.fill(with: GitChangeTree.contents(
			ofUntrackedDirectory: "PI-12",
			files: ["PI-12/notes.md", "PI-12/src/main.swift"],
			staged: false
		))
		row.applyLineCounts([
			"PI-12/notes.md": GitLineCount(added: 9, removed: 0),
			"PI-12/src/main.swift": GitLineCount(added: 4, removed: 0),
		])
		#expect(row.lines == GitLineCount(added: 13, removed: 0))
	}

	// MARK: - What is inside an untracked directory

	@Test func openingAnUntrackedDirectoryGivesItsContentsAsATree() {
		let rows = GitChangeTree.contents(
			ofUntrackedDirectory: "PI-12",
			files: ["PI-12/notes.md", "PI-12/src/main.swift", "PI-12/src/util.swift"],
			staged: false
		)
		#expect(self.rows(rows) == [
			"PI-12/src/",
			"PI-12/src/main.swift",
			"PI-12/src/util.swift",
			"PI-12/notes.md",
		], "the folders between are invented, as they are everywhere else")
	}

	@Test func everythingInsideAnUntrackedDirectoryIsUntracked() {
		let rows = GitChangeTree.contents(
			ofUntrackedDirectory: "PI-12", files: ["PI-12/a.txt"], staged: false
		)
		#expect(rows.first?.change?.kind == .untracked)
		#expect(rows.first?.change?.isStaged == false)
	}

	/// The trap this was written around: filling the row must not change what
	/// the row says about itself, or a wholly unstaged folder starts claiming to
	/// be partly staged.
	@Test func fillingAnUntrackedDirectoryLeavesItsOwnCountAlone() {
		let tree = GitChangeTree.build([directory("PI-12")])
		let row = tree.first!
		#expect(row.isFilled == false)

		row.fill(with: GitChangeTree.contents(
			ofUntrackedDirectory: "PI-12",
			files: (0..<12).map { "PI-12/file\($0).txt" },
			staged: false
		))

		#expect(row.isFilled)
		#expect(row.children.count == 12)
		#expect(row.count == 1, "git reports the directory as one entry")
		#expect(row.total == 1)
		#expect(row.isPartial == false, "it is not 1 of 12")
	}

	/// Asking again replaces rather than appends: the tree is rebuilt on every
	/// refresh and an open row is re-filled.
	@Test func fillingTwiceDoesNotDoubleTheRows() {
		let tree = GitChangeTree.build([directory("PI-12")])
		let row = tree.first!
		for _ in 0..<3 {
			row.fill(with: GitChangeTree.contents(
				ofUntrackedDirectory: "PI-12", files: ["PI-12/a.txt"], staged: false
			))
		}
		#expect(row.children.count == 1)
	}

	/// An empty answer is an answer — `mkdir` and nothing else.
	@Test func anEmptyUntrackedDirectoryIsFilledWithNothing() {
		let tree = GitChangeTree.build([directory("PI-12")])
		let row = tree.first!
		row.fill(with: GitChangeTree.contents(
			ofUntrackedDirectory: "PI-12", files: [], staged: false
		))
		#expect(row.isFilled, "asked and answered, so it is not asked again")
		#expect(row.children.isEmpty)
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

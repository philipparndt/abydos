import Foundation
import Testing
@testable import AbydosKit

/// Which chains of directories are one row, and what that row is called.
///
/// `src/main/java/com/example/myapp` is five rows before any code and four of
/// them say only "there is one more folder inside me"; a reactor of fifty
/// modules pays that fifty times. The walk that folds them lives in `FileNode`
/// so that the outline and the four hand-written tree walks ask the same
/// question — and so that it can be asked here, without a window.
///
/// Serialised for the two tests that count directory listings: that count is
/// one number for the whole process, and two of these running at once would be
/// counting each other's reads.
@Suite(.serialized)
struct CompactPackagesTests {
	/// A tree from a list of paths. A path ending in `/` is a directory; the
	/// rest are files with a byte in them.
	private func makeTree(_ paths: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-compact-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for path in paths {
			let url = root.appendingPathComponent(path)
			if path.hasSuffix("/") {
				try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			} else {
				try FileManager.default.createDirectory(
					at: url.deletingLastPathComponent(), withIntermediateDirectories: true
				)
				try "x".write(to: url, atomically: true, encoding: .utf8)
			}
		}
		return root
	}

	private func tree(_ paths: [String]) throws -> (FileNode, URL) {
		let root = try makeTree(paths)
		return (FileNode(url: root, isDirectory: true), root)
	}

	// MARK: - What folds

	@Test func aChainOfSingleDirectoriesIsOneRow() throws {
		let (tree, root) = try tree(["com/example/myapp/App.java", "com/example/myapp/Other.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		let rows = tree.compactedChildren
		#expect(rows.count == 1)
		let row = try #require(rows.first)
		#expect(row.name == "myapp", "the row is the last directory in the chain, not the first")
		#expect(row.compactedName == "com/example/myapp")
		#expect(row.children.map(\.name) == ["App.java", "Other.java"])
	}

	@Test func aDirectoryWithMoreThanOneEntryEndsTheChain() throws {
		let (tree, root) = try tree(["com/example/", "com/other/"])
		defer { try? FileManager.default.removeItem(at: root) }

		let row = try #require(tree.compactedChildren.first)
		#expect(row.name == "com")
		#expect(row.compactedName == "com")
		#expect(!row.isCompactedAway, "`com` holds two entries, so it is a row of its own")
		#expect(row.compactedChildren.map(\.name) == ["example", "other"])
	}

	/// The file is the row somebody clicks, so the directory holding it keeps
	/// its own row rather than folding into a name that is not a package.
	@Test func aDirectoryHoldingOneFileDoesNotFold() throws {
		let (tree, root) = try tree(["resources/logback.xml"])
		defer { try? FileManager.default.removeItem(at: root) }

		let row = try #require(tree.compactedChildren.first)
		#expect(row.name == "resources")
		#expect(row.children.map(\.name) == ["logback.xml"])
	}

	@Test func anExcludedDirectoryIsNotFoldedAway() throws {
		let (tree, root) = try tree(["target/classes/com/"])
		defer { try? FileManager.default.removeItem(at: root) }

		let row = try #require(tree.compactedChildren.first)
		try #require(row.isExcluded, "`target` is excluded by default, which is what this is about")
		#expect(row.name == "target", "what it is is the thing worth seeing")
		#expect(row.compactedName == "target")
	}

	/// Not merely "not folded": not *listed*. Deciding what folds is a listing
	/// per visible directory where there was none, and a `node_modules` of
	/// thousands of entries is exactly what must not be paid for.
	@Test func nothingInsideAnExcludedDirectoryIsListedToDecideWhetherItFolds() throws {
		let (tree, root) = try tree(["node_modules/a/", "node_modules/b/", "node_modules/c/"])
		defer { try? FileManager.default.removeItem(at: root) }

		let excluded = try #require(tree.children.first)
		try #require(excluded.isExcluded)

		FileNode.directoryReadsForTesting = 0
		_ = tree.compactedChildren
		#expect(!excluded.hasLoadedChildren, "nothing inside it should have been listed")
		#expect(
			FileNode.directoryReadsForTesting == 0,
			"\(FileNode.directoryReadsForTesting) directories were listed to fold an excluded one"
		)
	}

	/// The root is the project, and its name is the one thing on screen that
	/// says which project this is.
	@Test func theProjectRootIsNeverFoldedAway() throws {
		let (tree, root) = try tree(["only/deeper/file.txt"])
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(tree.compactedRow === tree)
		#expect(!tree.isCompactedAway)
		let row = try #require(tree.compactedChildren.first)
		#expect(row.name == "deeper")
		#expect(row.compactedName == "only/deeper", "the root's own name is not part of it")
	}

	/// A directory holding one link back to itself is a chain with no end.
	/// Without the guard this does not fail — it never returns.
	@Test func aSymbolicLinkEndsTheChain() throws {
		let (tree, root) = try tree(["loop/"])
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createSymbolicLink(
			at: root.appendingPathComponent("loop/link"),
			withDestinationURL: root.appendingPathComponent("loop")
		)

		let row = try #require(tree.compactedChildren.first)
		#expect(row.name == "loop")
	}

	// MARK: - What the row is called

	@Test func aPackageUnderASourceRootJoinsWithDots() throws {
		let (tree, root) = try tree([
			"src/main/java/com/example/myapp/App.java",
			"src/main/java/com/example/myapp/Other.java",
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let sourceRoot = try #require(tree.compactedChildren.first)
		#expect(sourceRoot.name == "java", "the chain ends at the source root")
		#expect(sourceRoot.compactedName == "src/main/java", "not `src.main.java`, which nobody calls it")

		let package = try #require(sourceRoot.compactedChildren.first)
		#expect(package.name == "myapp")
		#expect(package.compactedName == "com.example.myapp")
	}

	/// Two rows and not one: folding the source root into the package below it
	/// would give `src/main/java/com/example/myapp`, which is neither.
	@Test func theSourceRootAndItsPackageAreSeparateRows() throws {
		let (tree, root) = try tree(["src/main/java/com/example/myapp/App.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		let sourceRoot = try #require(tree.compactedChildren.first)
		#expect(sourceRoot.isCompactedAway == false)
		#expect(sourceRoot.compactedChildren.count == 1)
	}

	@Test func aChainThatIsNotAPackageJoinsWithSlashes() throws {
		let (tree, root) = try tree(["internal/platform/store/store.go"])
		defer { try? FileManager.default.removeItem(at: root) }

		let row = try #require(tree.compactedChildren.first)
		#expect(row.compactedName == "internal/platform/store")
	}

	/// The name is recovered by walking up, and a file has nothing to recover:
	/// the directory above it holds one entry, but that entry is not a package.
	@Test func aFileIsCalledWhatItIsCalled() throws {
		let (tree, root) = try tree(["resources/logback.xml"])
		defer { try? FileManager.default.removeItem(at: root) }

		let file = try #require(tree.compactedChildren.first?.children.first)
		#expect(file.compactedName == "logback.xml")
	}

	// MARK: - The four walks that are written by hand

	/// The reveal's rule, which the navigator applies to the ancestors it has
	/// collected: open the ones that are rows, skip the ones that are not.
	private func rowsToOpen(from node: FileNode, under root: FileNode) -> [String] {
		var ancestors: [FileNode] = []
		var current: FileNode? = node
		while let parent = current?.parent, current !== root {
			ancestors.append(parent)
			current = parent
		}
		return ancestors.reversed().filter { !$0.isCompactedAway }.map(\.name)
	}

	/// The navigator's expansion restore, which descends through the rows that
	/// exist rather than through every directory.
	private func restore(
		from node: FileNode, matching paths: Set<String>, compacting: Bool, into opened: inout [String]
	) {
		let children = compacting ? node.compactedChildren : node.children
		for child in children where child.isDirectory && paths.contains(child.url.path) {
			opened.append(child.name)
			restore(from: child, matching: paths, compacting: compacting, into: &opened)
		}
	}

	/// Reveal. Every folder between the file and the root is opened on the way
	/// down, and with compaction on most of them have no row to open — the row
	/// that stands for them is further down and is opened in its turn.
	@Test func revealingAFileOpensOnlyTheRowsTheOutlineHas() throws {
		let (tree, root) = try tree([
			"src/main/java/com/example/myapp/App.java",
			"src/main/java/com/example/myapp/Other.java",
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let file = try #require(tree.node(for: root.appendingPathComponent(
			"src/main/java/com/example/myapp/App.java"
		)))
		#expect(
			rowsToOpen(from: file, under: tree) == [root.lastPathComponent, "java", "myapp"],
			"`src`, `main`, `com` and `example` are folded into the two rows below them"
		)
	}

	/// And the file itself is its own row either way, so the selection at the
	/// end of the reveal lands on something.
	@Test func aFileInsideAChainIsItsOwnRow() throws {
		let (tree, root) = try tree(["src/main/java/com/example/myapp/App.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		let url = root.appendingPathComponent("src/main/java/com/example/myapp/App.java")
		let file = try #require(tree.node(for: url))
		#expect(file.compactedRow === file)
		#expect(!file.isCompactedAway)
	}

	/// Expansion is saved by path, and a folded row has the path of the last
	/// directory in its chain — which is a real directory with a real path,
	/// under either setting.
	@Test func aFoldedRowIsSavedAndRestoredByTheSamePathAsAnyOtherRow() throws {
		let (tree, root) = try tree(["com/example/myapp/App.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		let row = try #require(tree.compactedChildren.first)
		#expect(row.url.path == root.appendingPathComponent("com/example/myapp").path)

		var opened: [String] = []
		restore(from: tree, matching: [row.url.path], compacting: true, into: &opened)
		#expect(opened == ["myapp"], "the one row there is, opened by the path that was saved")
	}

	/// The watcher stops at the first closed door on purpose. A folded chain is
	/// several closed doors drawn as one row — but deciding to fold them listed
	/// every one, so the door at the end is open and a write behind it arrives.
	@Test func aWriteInsideAFoldedChainReachesTheRowThatShowsIt() throws {
		let (tree, root) = try tree(["com/example/myapp/App.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		let row = try #require(tree.compactedChildren.first)
		let directory = root.appendingPathComponent("com/example/myapp")
		try "x".write(
			to: directory.appendingPathComponent("New.java"), atomically: true, encoding: .utf8
		)

		let loaded = try #require(
			tree.loadedNode(for: directory), "the fold listed the chain, so it is open"
		)
		#expect(loaded === row, "and the node the watcher finds is the row that is drawn")
		#expect(loaded.hasLoadedChildren)
		loaded.reloadPreservingIdentity()
		#expect(loaded.children.map(\.name) == ["App.java", "New.java"])
	}

	// MARK: - The toggle

	/// Turning it off gives every directory in the chain a row again, and what
	/// was open has to still be open — including the four that had no row to be
	/// open on.
	@Test func whatWasOpenIsStillOpenWhenCompactionIsTurnedOff() throws {
		let (tree, root) = try tree(["src/main/java/com/example/myapp/App.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		// What the outline would have saved: the two rows compaction leaves.
		let sourceRoot = try #require(tree.compactedChildren.first)
		let package = try #require(sourceRoot.compactedChildren.first)
		let saved: Set<String> = [sourceRoot.url.path, package.url.path]

		var opened: [String] = []
		restore(
			from: tree, matching: FilePath.withAncestors(of: saved),
			compacting: false, into: &opened
		)
		#expect(
			opened == ["src", "main", "java", "com", "example", "myapp"],
			"the row that was open, and every directory above it"
		)
	}

	/// And the other way, which is the easy direction: every path that was saved
	/// is still a path, and the deepest of them is the row.
	@Test func whatWasOpenIsStillOpenWhenCompactionIsTurnedOn() throws {
		let (tree, root) = try tree(["src/main/java/com/example/myapp/App.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		func everyDirectory(_ node: FileNode) -> [String] {
			node.children.filter(\.isDirectory).flatMap { [$0.url.path] + everyDirectory($0) }
		}
		let saved = Set(everyDirectory(tree))

		var opened: [String] = []
		restore(
			from: tree, matching: FilePath.withAncestors(of: saved),
			compacting: true, into: &opened
		)
		#expect(opened == ["java", "myapp"], "the rows that are still rows")
	}

	/// The selection is kept by path, and the file has the same path and the
	/// same node under either setting — which is the whole reason a folded row
	/// is the last node in the chain rather than a stand-in for several.
	@Test func aFileSelectedInsideAChainIsTheSameFileAfterTheToggle() throws {
		let (tree, root) = try tree(["src/main/java/com/example/myapp/App.java"])
		defer { try? FileManager.default.removeItem(at: root) }

		let url = root.appendingPathComponent("src/main/java/com/example/myapp/App.java")
		let before = try #require(tree.node(for: url))
		let package = try #require(tree.compactedChildren.first?.compactedChildren.first)
		let after = try #require(package.children.first { $0.url.path == url.path })
		#expect(before === after)
	}

	/// A folded row that is not on any of the paths that were open must not come
	/// out of the toggle open — the ancestors are put back, not the descendants.
	@Test func nothingElseIsOpenedByPuttingTheAncestorsBack() throws {
		let (tree, root) = try tree([
			"src/main/java/com/example/myapp/App.java",
			"docs/one/two/three/note.md",
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let sourceRoot = try #require(tree.compactedChildren.first { $0.name == "java" })
		var opened: [String] = []
		restore(
			from: tree, matching: FilePath.withAncestors(of: [sourceRoot.url.path]),
			compacting: false, into: &opened
		)
		#expect(opened == ["src", "main", "java"], "`docs` was closed and stays closed")
	}

	// MARK: - What it costs

	/// The listing is cached against the directory's modification time, so
	/// deciding what folds is paid once and not once per refresh.
	@Test func anUnchangedTreeIsNotListedAgainToDecideWhatFolds() throws {
		let (tree, root) = try tree([
			"src/main/java/com/example/myapp/App.java",
			"docs/guide.md",
			"two/a/", "two/b/",
		])
		defer { try? FileManager.default.removeItem(at: root) }

		func walk(_ node: FileNode) {
			for child in node.compactedChildren where child.isDirectory { walk(child) }
		}
		walk(tree)

		FileNode.directoryReadsForTesting = 0
		tree.reloadPreservingIdentity()
		walk(tree)
		let listed = FileNode.directoryReadsForTesting
		#expect(listed == 0, "nothing moved, so nothing should have been listed again — \(listed) were")
	}
}

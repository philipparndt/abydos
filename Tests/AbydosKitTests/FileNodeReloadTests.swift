import Foundation
import Testing
@testable import AbydosKit

/// Re-reading the project tree, and not re-reading the parts of it that cannot
/// have changed.
///
/// The navigator re-reads every directory it has open whenever the window comes
/// forward, and `~/Library/Logs/Abydos/stalls.log` on the machine this was
/// written on says what that cost: 646 stalls named "navigator reload", median
/// 557 ms, worst 45 s, all of them on the main thread and all of them in front
/// of whatever somebody was typing. The project is a repository with a dozen
/// worktrees inside it — 265,485 entries under 47,594 directories — and almost
/// none of it changes between one reload and the next.
///
/// Serialised, because the count of directories listed is one number for the
/// whole process and two of these running at once would be counting each
/// other's reads.
@Suite(.serialized)
struct FileNodeReloadTests {
	private func makeTree(directories: Int, filesEach: Int) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-filenode-\(UUID().uuidString)")
		for index in 0..<directories {
			let folder = root.appendingPathComponent("folder-\(index)")
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			for file in 0..<filesEach {
				try "x".write(
					to: folder.appendingPathComponent("file-\(file).txt"),
					atomically: true, encoding: .utf8
				)
			}
		}
		return root
	}

	/// Loads a whole tree, so every directory in it counts as open.
	private func loadEverything(_ node: FileNode) {
		for child in node.children where child.isDirectory { loadEverything(child) }
	}

	@Test func anUnchangedTreeIsNotReadAgain() throws {
		let root = try makeTree(directories: 12, filesEach: 8)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		loadEverything(tree)

		FileNode.directoryReadsForTesting = 0
		tree.reloadPreservingIdentity()
		#expect(
			FileNode.directoryReadsForTesting == 0,
			"nothing moved, so nothing should have been listed again — \(FileNode.directoryReadsForTesting) were"
		)
	}

	/// The point of the skip is that it is a skip and not a blindfold.
	@Test func aDirectorySomethingWasAddedToIsReadAgainAndShowsIt() throws {
		let root = try makeTree(directories: 4, filesEach: 3)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		loadEverything(tree)
		let folder = tree.children.first { $0.name == "folder-2" }
		#expect(folder != nil)

		try "new".write(
			to: root.appendingPathComponent("folder-2/arrived.txt"),
			atomically: true, encoding: .utf8
		)

		tree.reloadPreservingIdentity()
		let names = (tree.children.first { $0.name == "folder-2" })?.children.map(\.name) ?? []
		#expect(names.contains("arrived.txt"), "the new file never appeared: \(names)")
	}

	/// A file removed from an open directory goes from the tree too.
	@Test func aDirectorySomethingWasRemovedFromIsReadAgain() throws {
		let root = try makeTree(directories: 3, filesEach: 4)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		loadEverything(tree)
		try FileManager.default.removeItem(at: root.appendingPathComponent("folder-1/file-0.txt"))

		tree.reloadPreservingIdentity()
		let names = (tree.children.first { $0.name == "folder-1" })?.children.map(\.name) ?? []
		#expect(!names.contains("file-0.txt"), "the removed file is still there: \(names)")
	}

	/// A change deep in the tree is found even though everything above it is
	/// unchanged — the skip stops at the directory, not at the branch.
	@Test func aChangeBelowAnUnchangedDirectoryIsStillFound() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-filenode-\(UUID().uuidString)")
		let deep = root.appendingPathComponent("one/two/three")
		try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		loadEverything(tree)

		try "deep".write(to: deep.appendingPathComponent("found.txt"), atomically: true, encoding: .utf8)
		tree.reloadPreservingIdentity()

		let found = tree.node(for: deep.appendingPathComponent("found.txt"))
		#expect(found != nil, "a file three directories down was not noticed")
	}

	/// A file whose *contents* change does not change the tree, and re-reading
	/// the directory it sits in would find exactly the same names.
	@Test func rewritingAFileDoesNotMakeItsDirectoryWorthReading() throws {
		let root = try makeTree(directories: 2, filesEach: 2)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		loadEverything(tree)

		let file = root.appendingPathComponent("folder-0/file-0.txt")
		let handle = try FileHandle(forWritingTo: file)
		try handle.write(contentsOf: Data("changed in place".utf8))
		try handle.close()

		FileNode.directoryReadsForTesting = 0
		tree.reloadPreservingIdentity()
		#expect(FileNode.directoryReadsForTesting == 0)
	}

	/// What the skip is worth, said in numbers rather than claimed.
	///
	/// Not an assertion about time — a test that fails on a busy machine is
	/// worse than no test — but the ratio is printed, and the reload of an
	/// unchanged tree must at least not read anything.
	@Test func theCostOfReloadingAnUnchangedTreeIsPrinted() throws {
		let root = try makeTree(directories: 60, filesEach: 40)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		loadEverything(tree)

		FileNode.directoryReadsForTesting = 0
		let start = Date()
		for _ in 0..<10 { tree.reloadPreservingIdentity() }
		let skipped = -start.timeIntervalSinceNow
		let readsWhileNothingChanged = FileNode.directoryReadsForTesting

		// The same ten reloads with nothing remembered, which is what this used
		// to do every time.
		let fresh = FileNode(url: root, isDirectory: true)
		loadEverything(fresh)
		let listedStart = Date()
		for _ in 0..<10 {
			forceReread(fresh)
			fresh.reloadPreservingIdentity()
		}
		let listed = -listedStart.timeIntervalSinceNow

		print(String(
			format: "FILENODE 61 directories x 40 files, 10 reloads: unchanged %.1f ms, listing %.1f ms (%.1fx)",
			skipped * 1000, listed * 1000, listed / max(skipped, 0.000_001)
		))
		#expect(readsWhileNothingChanged == 0)
	}

	/// What a filesystem event about a closed part of the tree costs.
	///
	/// This is the shape of every event a build produces: something is written
	/// several directories down inside `build`, nobody has expanded any of it,
	/// and the navigator has to decide whether it has anything to re-read. The
	/// deciding must not itself be a read, and must not leave the tree holding
	/// what it read.
	@Test func anEventDeepInsideAClosedDirectoryListsNothing() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-filenode-\(UUID().uuidString)")
		let deep = root.appendingPathComponent("build/debug/Modules")
		try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
		try "x".write(to: deep.appendingPathComponent("Foo.swiftmodule"), atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		// Only the root is open, which is what a project just opened looks like.
		_ = tree.children
		let build = tree.children.first { $0.name == "build" }
		#expect(build != nil)

		FileNode.directoryReadsForTesting = 0
		#expect(tree.loadedNode(for: deep) == nil)
		#expect(
			FileNode.directoryReadsForTesting == 0,
			"deciding that a closed directory is closed listed \(FileNode.directoryReadsForTesting) of them"
		)
		#expect(build?.hasLoadedChildren == false, "the closed directory was opened anyway")

		// And what the same question used to cost: two listings for one file the
		// tree does not show — and both of them stay, which is why the price
		// went up with every event rather than staying where it was.
		FileNode.directoryReadsForTesting = 0
		#expect(tree.node(for: deep) != nil)
		#expect(FileNode.directoryReadsForTesting == 2)
		#expect(build?.hasLoadedChildren == true)
	}

	/// The stop is at the closed door, not at the branch: a directory somebody
	/// has opened is still found and still re-read.
	@Test func anEventInsideAnOpenDirectoryIsStillFound() throws {
		let root = try makeTree(directories: 3, filesEach: 2)
		defer { try? FileManager.default.removeItem(at: root) }

		let tree = FileNode(url: root, isDirectory: true)
		loadEverything(tree)

		let folder = root.appendingPathComponent("folder-1")
		let found = tree.loadedNode(for: folder)
		#expect(found?.url.path == folder.standardizedFileURL.path)

		try "new".write(
			to: folder.appendingPathComponent("arrived.txt"), atomically: true, encoding: .utf8
		)
		found?.reloadPreservingIdentity()
		#expect(found?.children.map(\.name).contains("arrived.txt") == true)
	}

	/// Makes every open directory look changed, so the comparison above is
	/// against the work this used to do rather than against nothing.
	private func forceReread(_ node: FileNode) {
		guard node.hasLoadedChildren else { return }
		node.forgetLastReadingForTesting()
		for child in node.children where child.isDirectory { forceReread(child) }
	}
}

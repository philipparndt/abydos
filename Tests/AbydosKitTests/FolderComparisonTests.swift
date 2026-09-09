import Testing
import Foundation
@testable import AbydosKit

/// Two folders aligned by path: what a listing decides, what a read decides,
/// and what applying the marks does to the disk.
@MainActor
struct FolderComparisonTests {
	/// Two folders under a scratch directory of this test's own, never a real
	/// one (item 0522).
	private func scratch() throws -> (root: URL, a: URL, b: URL) {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-compare-\(UUID().uuidString)")
		let a = root.appendingPathComponent("A", isDirectory: true)
		let b = root.appendingPathComponent("B", isDirectory: true)
		try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
		return (root, a, b)
	}

	private func write(_ text: String, to url: URL) throws {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try text.write(to: url, atomically: true, encoding: .utf8)
	}

	private func compared(_ a: URL, _ b: URL, excluded: Set<String> = ["node_modules"]) async -> FolderComparison {
		let comparison = FolderComparison(left: .folder(a), right: .folder(b), excludedDirectoryNames: excluded)
		comparison.start()
		await comparison.settled()
		return comparison
	}

	@Test func twoFilesOfDifferentSizesAreDifferentWithoutBeingRead() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("aaa", to: a.appendingPathComponent("a.txt"))
		try write("aaaa", to: b.appendingPathComponent("a.txt"))

		let comparison = await compared(a, b)
		#expect(comparison.node(at: "a.txt")?.state == .different)
		#expect(comparison.reads == 0)
		#expect(comparison.counts.different == 1)
	}

	@Test func twoFilesOfEqualSizeAreUnknownUntilCompared() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("abc", to: a.appendingPathComponent("a.txt"))
		try write("abd", to: b.appendingPathComponent("a.txt"))

		let comparison = FolderComparison(left: .folder(a), right: .folder(b))
		var seen: [FolderComparison.State] = []
		comparison.onChange = {
			if let state = comparison.node(at: "a.txt")?.state, seen.last != state { seen.append(state) }
		}
		comparison.start()
		await comparison.settled()
		#expect(seen.first == .unknown)
		#expect(seen.last == .different)
		#expect(comparison.reads == 1)
	}

	@Test func aFolderIsDifferentIfAnyChildIs() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("1", to: a.appendingPathComponent("sub/x"))
		try write("2", to: b.appendingPathComponent("sub/x"))
		try write("same", to: a.appendingPathComponent("same/y"))
		try write("same", to: b.appendingPathComponent("same/y"))

		let comparison = await compared(a, b)
		#expect(comparison.node(at: "sub")?.state == .different)
		#expect(comparison.node(at: "same")?.state == .equal)
		#expect(comparison.root.state == .different)
	}

	@Test func aFileOnOneSideOnlyIsUnmatched() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("only", to: a.appendingPathComponent("Package.resolved"))
		try write("x", to: a.appendingPathComponent("x"))
		try write("x", to: b.appendingPathComponent("x"))

		let comparison = await compared(a, b)
		let node = try #require(comparison.node(at: "Package.resolved"))
		#expect(node.state == .unmatched)
		#expect(node.right == nil)
		#expect(comparison.counts.unmatched == 1)
		#expect(comparison.counts.equal == 1)
	}

	@Test func anIgnoredRowSaysWhichRuleIgnoredIt() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("m", to: a.appendingPathComponent("node_modules/m/index.js"))
		try write("m", to: b.appendingPathComponent("node_modules/m/index.js"))
		try write("keep", to: a.appendingPathComponent("keep"))
		try write("keep", to: b.appendingPathComponent("keep"))

		let comparison = await compared(a, b)
		let node = try #require(comparison.node(at: "node_modules"))
		guard case .ignored(let rule) = node.state else {
			Issue.record("node_modules was \(node.state)")
			return
		}
		#expect(rule.contains("build output"))
		// Never entered: nothing under it is a row.
		#expect(comparison.node(at: "node_modules/m") == nil)
		#expect(comparison.counts.ignored == 1)
	}

	@Test func aGitIgnoreRuleOnOneSideGreysTheRowAndNamesTheSide() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		_ = await GitRepository.run(["init", "-q"], in: a)
		try write("*.log\n", to: a.appendingPathComponent(".gitignore"))
		try write("log", to: a.appendingPathComponent("x.log"))
		try write("log", to: b.appendingPathComponent("x.log"))

		let comparison = await compared(a, b)
		let node = try #require(comparison.node(at: "x.log"))
		guard case .ignored(let rule) = node.state else {
			Issue.record("x.log was \(node.state)")
			return
		}
		#expect(rule.hasPrefix("A: "))
		#expect(rule.contains(".gitignore:1 *.log"))
	}

	@Test func equalRowsAreHiddenAndCounted() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		for name in ["one", "two", "three"] {
			try write(name, to: a.appendingPathComponent(name))
			try write(name, to: b.appendingPathComponent(name))
		}
		try write("differs", to: a.appendingPathComponent("d"))
		try write("DIFFERS", to: b.appendingPathComponent("d"))

		let comparison = await compared(a, b)
		#expect(comparison.counts.equal == 3)
		#expect(comparison.children(of: comparison.root, showingEqual: false).map(\.name) == ["d"])
		#expect(comparison.children(of: comparison.root, showingEqual: true).count == 4)
		#expect(comparison.counts.said == "1 Different, 3 Equal (not shown), 0 Unmatched, 0 Ignored")
	}

	@Test func aFilterKeepsTheFoldersThatLeadToAMatch() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("1", to: a.appendingPathComponent("Sources/Terminal/Keys.swift"))
		try write("2", to: b.appendingPathComponent("Sources/Terminal/Keys.swift"))
		try write("1", to: a.appendingPathComponent("Sources/Editor/Caret.swift"))
		try write("2", to: b.appendingPathComponent("Sources/Editor/Caret.swift"))

		let comparison = await compared(a, b)
		let sources = try #require(comparison.node(at: "Sources"))
		#expect(comparison.children(of: comparison.root, showingEqual: false, filter: "Terminal").map(\.name) == ["Sources"])
		#expect(comparison.children(of: sources, showingEqual: false, filter: "Terminal").map(\.name) == ["Terminal"])
		#expect(comparison.children(of: comparison.root, showingEqual: false, filter: "nothing").isEmpty)
	}

	@Test func anApplyTrashesBeforeItOverwrites() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("new", to: a.appendingPathComponent("Package.swift"))
		try write("old", to: b.appendingPathComponent("Package.swift"))
		try write("gone", to: a.appendingPathComponent("Package.resolved"))

		let comparison = await compared(a, b)
		#expect(comparison.setMark(.copyToRight, at: "Package.swift"))
		#expect(comparison.setMark(.delete, at: "Package.resolved"))
		#expect(comparison.operations.map(\.said) == [
			"Package.resolved  delete on A",
			"Package.swift  A → B",
		])

		var trashed: [(path: String, contentsThen: String?)] = []
		let results = await comparison.apply { url in
			trashed.append((url.lastPathComponent, try? String(contentsOf: url, encoding: .utf8)))
			try FileManager.default.removeItem(at: url)
		}
		#expect(results.allSatisfy { $0.error == nil })
		// The old file was in the Trash before the new one landed, and the
		// deletion went the same way.
		#expect(trashed.map(\.path) == ["Package.resolved", "Package.swift"])
		#expect(trashed[1].contentsThen == "old")
		#expect(try String(contentsOf: b.appendingPathComponent("Package.swift"), encoding: .utf8) == "new")
		#expect(!FileManager.default.fileExists(atPath: a.appendingPathComponent("Package.resolved").path))
		#expect(comparison.marks.isEmpty)

		await comparison.settled()
		#expect(comparison.node(at: "Package.swift")?.state == .equal)
		#expect(comparison.node(at: "Package.resolved") == nil)
	}

	@Test func aReadOnlySideIsNeverWrittenTo() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("committed", to: b.appendingPathComponent("file.txt"))
		try write("committed", to: b.appendingPathComponent("dir/inner.txt"))
		_ = await GitRepository.run(["init", "-q"], in: b)
		_ = await GitRepository.run(["add", "."], in: b)
		_ = await GitRepository.run(
			["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "one"], in: b
		)
		try write("committed", to: a.appendingPathComponent("file.txt"))
		try write("mine", to: a.appendingPathComponent("only-here.txt"))

		let comparison = FolderComparison(left: .folder(a), right: .tree(repository: b, commit: "HEAD", path: ""))
		comparison.start()
		await comparison.settled()

		let file = try #require(comparison.node(at: "file.txt"))
		#expect(file.state == .equal)
		#expect(file.right?.blob != nil)
		let mine = try #require(comparison.node(at: "only-here.txt"))
		// Nothing is offered towards the commit: not a copy into it, and a
		// delete only on the side that holds it and takes writes.
		#expect(comparison.offeredMarks(for: mine) == [.delete])
		#expect(!comparison.setMark(.copyToRight, at: "only-here.txt"))
		let dir = try #require(comparison.node(at: "dir"))
		#expect(dir.state == .unmatched)
		#expect(comparison.offeredMarks(for: dir) == [.copyToLeft])

		// A whole directory out of the commit lands on disk, blob by blob.
		#expect(comparison.setMark(.copyToLeft, at: "dir"))
		let results = await comparison.apply { _ in Issue.record("nothing should have been trashed") }
		#expect(results.map(\.error) == [nil])
		#expect(try String(contentsOf: a.appendingPathComponent("dir/inner.txt"), encoding: .utf8) == "committed")
	}

	@Test func theCacheSkipsWhatDidNotChange() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		for name in ["one", "two"] {
			try write(name, to: a.appendingPathComponent(name))
			try write(name, to: b.appendingPathComponent(name))
		}
		let comparison = await compared(a, b)
		#expect(comparison.reads == 2)
		comparison.refresh(directories: [""])
		await comparison.settled()
		#expect(comparison.reads == 2)
		#expect(comparison.node(at: "one")?.state == .equal)
	}

	@Test func aSavedFileMovesItsRowAndReadsNothingElse() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		for name in ["one", "two", "three"] {
			try write(name, to: a.appendingPathComponent(name))
			try write(name, to: b.appendingPathComponent(name))
		}
		let comparison = await compared(a, b)
		let before = comparison.reads

		// The same size, later: what a save of one changed character is.
		let saved = a.appendingPathComponent("one")
		try write("ONE", to: saved)
		try FileManager.default.setAttributes(
			[.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: saved.path
		)
		comparison.refresh(directories: [""])
		await comparison.settled()
		#expect(comparison.node(at: "one")?.state == .different)
		#expect(comparison.node(at: "two")?.state == .equal)
		#expect(comparison.reads == before + 1)
	}

	@Test func aBatchOverOneDirectoryListsItOnce() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("x", to: a.appendingPathComponent("sub/x"))
		try write("x", to: b.appendingPathComponent("sub/x"))
		let comparison = await compared(a, b)
		let before = comparison.listings

		comparison.refresh(directories: ["sub", "sub/", "sub"])
		await comparison.settled()
		#expect(comparison.listings == before + 1)
		// A directory nothing has listed yet is not the watcher's to list.
		comparison.refresh(directories: ["nowhere"])
		await comparison.settled()
		#expect(comparison.listings == before + 1)
	}

	@Test func swappingSidesKeepsTheRowsAndTurnsTheMarksRound() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("only", to: a.appendingPathComponent("only-in-a"))
		try write("same", to: a.appendingPathComponent("same"))
		try write("same", to: b.appendingPathComponent("same"))
		try write("x", to: a.appendingPathComponent("d"))
		try write("y", to: b.appendingPathComponent("d"))

		let comparison = await compared(a, b)
		let only = try #require(comparison.node(at: "only-in-a"))
		#expect(comparison.setMark(.copyToRight, at: "only-in-a"))
		let reads = comparison.reads
		comparison.swapSides()

		#expect(comparison.left == .folder(b) && comparison.right == .folder(a))
		#expect(comparison.node(at: "only-in-a") === only, "the same node")
		#expect(only.left == nil && only.right != nil)
		#expect(only.state == .unmatched)
		#expect(comparison.mark(at: "only-in-a") == .copyToLeft)
		#expect(comparison.node(at: "same")?.state == .equal)
		#expect(comparison.node(at: "d")?.state == .different)
		// And nothing was read again for it.
		comparison.refresh(directories: [""])
		await comparison.settled()
		#expect(comparison.reads == reads)
	}

	@Test func aNameThatIsAFileOnOneSideAndAFolderOnTheOtherIsUnmatched() async throws {
		let (root, a, b) = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("file", to: a.appendingPathComponent("thing"))
		try write("inner", to: b.appendingPathComponent("thing/inner"))
		let comparison = await compared(a, b)
		#expect(comparison.node(at: "thing")?.state == .unmatched)
		#expect(comparison.reads == 0)
	}
}

/// The four kinds of side, and what each can do.
struct CompareSourceTests {
	@Test func aBlobSourceCannotBeWrittenTo() {
		let repository = URL(fileURLWithPath: "/tmp/repo")
		let blob = CompareSource.blob(repository: repository, commit: "380fe8c2abcdef", path: "src/mod.rs")
		#expect(!blob.isWritable)
		#expect(!blob.isFolder)
		#expect(blob.name == "mod.rs")
		#expect(blob.origin == "src/mod.rs at 380fe8c2")
		#expect(blob.diskURL == nil)
		let tree = CompareSource.tree(repository: repository, commit: "380fe8c2", path: "")
		#expect(!tree.isWritable)
		#expect(tree.isFolder)
		#expect(tree.name == "repo")
		#expect(tree.descending(to: "src/mod.rs", isDirectory: false)
			== .blob(repository: repository, commit: "380fe8c2", path: "src/mod.rs"))
	}

	@Test func aFileIsComparedWithAFileAndAFolderWithAFolder() {
		let file = CompareSource.file(URL(fileURLWithPath: "/tmp/a.txt"))
		let folder = CompareSource.folder(URL(fileURLWithPath: "/tmp/dir"))
		#expect(file.canBeComparedWith(.file(URL(fileURLWithPath: "/tmp/b.txt"))))
		#expect(!file.canBeComparedWith(folder))
		#expect(folder.isWritable)
		#expect(folder.descending(to: "x/y.txt", isDirectory: false) == .file(URL(fileURLWithPath: "/tmp/dir/x/y.txt")))
	}

	@Test func aDiskSideSaysWhereItIsWithATilde() {
		let home = FileManager.default.homeDirectoryForCurrentUser
		let source = CompareSource.folder(home.appendingPathComponent("dev/abydos"))
		#expect(source.origin == "~/dev/abydos")
	}
}

/// Reading what `git check-ignore -v -z --non-matching` says.
struct FolderIgnoreTests {
	@Test func aMatchedPathCarriesItsRuleAndAnUnmatchedOneIsDropped() {
		let output = ".gitignore\0" + "1\0" + "*.log\0" + "x.log\0" + "\0\0\0" + "keep\0"
		let parsed = FolderIgnore.parse(output)
		#expect(parsed.count == 1)
		#expect(parsed[0].0 == "x.log")
		#expect(parsed[0].1 == ".gitignore:1 *.log")
	}
}

/// The shelf: what a page holds, and which two of them it compares.
struct CompareShelfTests {
	private let one = CompareSource.file(URL(fileURLWithPath: "/tmp/draft-1.txt"))
	private let two = CompareSource.file(URL(fileURLWithPath: "/tmp/draft-2.txt"))
	private let three = CompareSource.file(URL(fileURLWithPath: "/tmp/draft-3.txt"))
	private let folder = CompareSource.folder(URL(fileURLWithPath: "/tmp/dir"))

	@Test func aThirdDocumentJoinsTheShelfWithoutChangingTheDiff() {
		var shelf = CompareShelf(a: one, b: two)
		shelf.add(three)
		#expect(shelf.sources.count == 3)
		#expect(shelf.left == one && shelf.right == two)
		#expect(shelf.title == "draft-1.txt | draft-2.txt")
	}

	@Test func choosingBOnTheThirdMovesTheChip() {
		var shelf = CompareShelf(a: one, b: two)
		let index = shelf.add(three)
		#expect(shelf.choose(index, sideA: false) == nil)
		#expect(shelf.right == three)
		#expect(shelf.left == one)
	}

	@Test func aChipOnTheOtherSidesCardSwapsTheSides() {
		var shelf = CompareShelf(a: one, b: two)
		#expect(shelf.choose(1, sideA: true) == nil)
		#expect(shelf.left == two)
		#expect(shelf.right == one, "B moved to what was A, so no card holds both chips")
		#expect(shelf.choose(1, sideA: false) == nil)
		#expect(shelf.left == one && shelf.right == two, "and back again")
	}

	@Test func swapTurnsTheSidesRound() {
		var shelf = CompareShelf(a: one, b: two)
		shelf.swap()
		#expect(shelf.left == two && shelf.right == one)
	}

	@Test func aChipACardAlreadyHoldsChangesNothing() {
		var shelf = CompareShelf(a: one, b: two)
		#expect(shelf.choose(0, sideA: true) == nil)
		#expect(shelf.left == one && shelf.right == two)
	}

	@Test func aFolderIsRefusedBesideAFileWithTheReason() {
		var shelf = CompareShelf(a: one, b: two)
		let refusal = shelf.take(folder, sideA: false)
		#expect(refusal == "A folder is compared with a folder; the other side is a file.")
		#expect(shelf.right == two)
		#expect(shelf.sources.count == 3, "it is on the shelf all the same")
	}

	@Test func anIdentifierBringsBothSidesBack() {
		let blob = CompareSource.blob(repository: URL(fileURLWithPath: "/tmp/repo", isDirectory: true), commit: "abc123", path: "src/a.swift")
		let identifier = ComparePageIdentity.identifier(left: one, right: blob)
		#expect(identifier.hasPrefix("compare:"))
		#expect(!identifier.contains("/"))
		let sides = ComparePageIdentity.sides(of: identifier)
		#expect(sides?.left == one)
		#expect(sides?.right == blob)
		#expect(ComparePageIdentity.sides(of: "log") == nil)
	}
}

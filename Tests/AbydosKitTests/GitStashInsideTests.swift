import Foundation
import Testing
@testable import AbydosKit

/// Looking inside a stash, and asking whether it would still go back.
///
/// Restoring one blind is what this replaces: three entries called "wip" are a
/// guessing game, and applying one into a mess that then has to be untangled is
/// the failure worth engineering away.
struct GitStashInsideTests {
	/// git without the app's plumbing, as `GitStashLiveTests` does it — its own
	/// copy because that one is fileprivate to its file.
	@discardableResult
	private func git(_ arguments: [String], in directory: URL) -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git"] + arguments
		process.currentDirectoryURL = directory
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try? process.run()
		process.waitUntilExit()
		return process.terminationStatus
	}

	private func repository() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("inside-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			#expect(git(command, in: root) == 0, "git \(command.joined(separator: " "))")
		}
		try write("one\n", "a.txt", in: root)
		try write("one\n", "b.txt", in: root)
		#expect(git(["add", "."], in: root) == 0)
		#expect(git(["commit", "-qm", "first"], in: root) == 0)
		return root
	}

	private func write(_ text: String, _ name: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	private func onlyStash(in root: URL) async -> GitStash.Entry? {
		await GitStash.list(in: root).first
	}

	@Test func aStashSaysWhichFilesItHolds() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed\n", "a.txt", in: root)
		#expect(await GitStash.push(in: root, message: "work").exitCode == 0)

		guard let entry = await onlyStash(in: root) else {
			Issue.record("nothing was stashed")
			return
		}
		let files = await GitStash.files(entry, in: root)
		#expect(files.map(\.path) == ["a.txt"])
		#expect(files.first?.kind == .modified)
	}

	/// The one that would have been missed: git keeps what `--include-untracked`
	/// picked up in a third parent rather than in the diff, so a stash read only
	/// as `^1..stash` leaves out exactly the files somebody has forgotten they
	/// had.
	@Test func aStashSaysWhichFilesGitHadNeverSeen() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed\n", "a.txt", in: root)
		try write("brand new\n", "new.txt", in: root)
		#expect(await GitStash.push(in: root, message: "work").exitCode == 0)

		guard let entry = await onlyStash(in: root) else {
			Issue.record("nothing was stashed")
			return
		}
		let files = await GitStash.files(entry, in: root)
		#expect(files.map(\.path) == ["a.txt", "new.txt"])
		#expect(files.first(where: { $0.path == "new.txt" })?.kind == .added)
	}

	@Test func theDiffOfOneOfItsFilesCanBeRead() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed\n", "a.txt", in: root)
		#expect(await GitStash.push(in: root, message: "work").exitCode == 0)

		guard let entry = await onlyStash(in: root) else {
			Issue.record("nothing was stashed")
			return
		}
		let diff = await GitStash.diff(entry, path: "a.txt", in: root)
		#expect(diff.contains("-one"))
		#expect(diff.contains("+changed"))
	}

	@Test func theDiffOfAnUntrackedFileCanBeReadToo() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("brand new\n", "new.txt", in: root)
		#expect(await GitStash.push(in: root, message: "work").exitCode == 0)

		guard let entry = await onlyStash(in: root) else {
			Issue.record("nothing was stashed")
			return
		}
		let diff = await GitStash.diff(entry, path: "new.txt", in: root)
		#expect(diff.contains("+brand new"))
	}

	@Test func aStashThatDoesNotOverlapAppliesCleanly() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed\n", "a.txt", in: root)
		#expect(await GitStash.push(in: root, message: "work").exitCode == 0)

		// Something else is in the working copy now, in a file the stash does
		// not touch.
		try write("meanwhile\n", "b.txt", in: root)

		guard let entry = await onlyStash(in: root) else {
			Issue.record("nothing was stashed")
			return
		}
		#expect(await GitStash.wouldApply(entry, in: root) == .clean)

		// Asked and not applied: the check must touch nothing.
		#expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "one\n")
		#expect(await GitStash.list(in: root).count == 1)
	}

	@Test func aStashOverTheSameFileNamesWhereItWouldStop() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("the stash says this\n", "a.txt", in: root)
		#expect(await GitStash.push(in: root, message: "work").exitCode == 0)

		// The same file has moved on since, in a way that cannot be reconciled.
		try write("the working copy says something else\n", "a.txt", in: root)

		guard let entry = await onlyStash(in: root) else {
			Issue.record("nothing was stashed")
			return
		}
		#expect(await GitStash.wouldApply(entry, in: root) == .conflicts(["a.txt"]))

		// And still nothing has happened to the file it named.
		let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
		#expect(onDisk == "the working copy says something else\n")
	}

	/// The answer to offer when the check says it would conflict: applied on
	/// the commit it came from, it cannot.
	@Test func branchingFromAStashPutsItSomewhereItFits() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("the stash says this\n", "a.txt", in: root)
		#expect(await GitStash.push(in: root, message: "work").exitCode == 0)
		try write("main moved on\n", "a.txt", in: root)
		#expect(git(["commit", "-qam", "second"], in: root) == 0)

		guard let entry = await onlyStash(in: root) else {
			Issue.record("nothing was stashed")
			return
		}
		#expect(await GitStash.branch(entry, named: "rescued", in: root).exitCode == 0)

		// On the new branch, with the work back and the entry gone.
		let head = await GitRepository.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
		#expect(head.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "rescued")
		let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
		#expect(onDisk == "the stash says this\n")
		#expect(await GitStash.list(in: root).isEmpty, "a stash branch drops the entry when it worked")
	}

	@Test func mergeTreeConflictLinesBecomePathsInOrderAndOnlyOnce() {
		// Its conflicted-file section repeats a path once per stage, and the
		// informational messages beneath it are not to be mistaken for more.
		let output = """
		4b825dc642cb6eb9a060e54bf8d69288fbee4904
		100644 aaaa 1\ta.txt
		100644 bbbb 2\ta.txt
		100644 cccc 3\ta.txt
		100644 dddd 1\tdeep/b.txt
		100644 eeee 2\tdeep/b.txt

		Auto-merging a.txt
		"""
		#expect(GitStash.conflictedPaths(in: output) == ["a.txt", "deep/b.txt"])
	}
}

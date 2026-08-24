import Foundation
import Testing
@testable import AbydosKit

/// The stash against a real repository.
///
/// Parsing can be tested against fixtures, but everything else here is a claim
/// about what git does — that `store` puts an entry on top, that dropping
/// renumbers what is left — and the only way to know is to run it.
struct GitStashLiveTests {
	private func repository() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("stash-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			let result = Process.git(command, in: root)
			#expect(result == 0, "git \(command.joined(separator: " "))")
		}
		try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		#expect(Process.git(["add", "."], in: root) == 0)
		#expect(Process.git(["commit", "-qm", "first"], in: root) == 0)
		return root
	}

	private func write(_ text: String, _ name: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	@Test func stashingPutsTheWorkAsideAndTakesItBack() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed\n", "a.txt", in: root)
		#expect(await GitStash.push(in: root, message: "my work").exitCode == 0)

		// Put aside: the file is as it was committed.
		let after = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
		#expect(after == "one\n")

		let entries = await GitStash.list(in: root)
		#expect(entries.count == 1)
		#expect(entries.first?.message == "my work")
		#expect(entries.first?.branch == "main")
		#expect(entries.first?.reference == "stash@{0}")

		// And back, keeping the entry.
		guard let entry = entries.first else { return }
		#expect(await GitStash.apply(entry, in: root, keeping: true).exitCode == 0)
		#expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "changed\n")
		#expect(await GitStash.list(in: root).count == 1, "applying keeps the entry")
	}

	/// The other answer to the same question: take it back and be rid of it.
	@Test func applyingWithoutKeepingRemovesTheEntry() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed\n", "a.txt", in: root)
		_ = await GitStash.push(in: root, message: "my work")
		guard let entry = await GitStash.list(in: root).first else {
			Issue.record("nothing was stashed")
			return
		}

		#expect(await GitStash.apply(entry, in: root, keeping: false).exitCode == 0)
		#expect(await GitStash.list(in: root).isEmpty)
		#expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "changed\n")
	}

	/// Only what was chosen: the rest of the working copy stays where it is.
	@Test func stashingSelectedPathsLeavesTheOthersAlone() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed-a\n", "a.txt", in: root)
		try write("new file\n", "b.txt", in: root)

		#expect(await GitStash.push(in: root, message: "just a", paths: ["a.txt"]).exitCode == 0)
		#expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "one\n")
		#expect(
			FileManager.default.fileExists(atPath: root.appendingPathComponent("b.txt").path),
			"b.txt was not chosen and must still be here"
		)
	}

	/// A file git has never seen is part of the work, and a working copy with
	/// one still in it is not clean.
	@Test func untrackedFilesGoTooUnlessSaidOtherwise() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("new\n", "untracked.txt", in: root)
		#expect(await GitStash.push(in: root, message: "with the new file").exitCode == 0)
		#expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("untracked.txt").path))
	}

	/// Dropping several at once: git renumbers after every drop, so the wrong
	/// entries would go if this worked upwards.
	@Test func droppingSeveralTakesTheOnesThatWereChosen() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		for name in ["first", "second", "third"] {
			try write("\(name)\n", "a.txt", in: root)
			_ = await GitStash.push(in: root, message: name)
		}
		// Newest first, so: third, second, first.
		let entries = await GitStash.list(in: root)
		#expect(entries.map(\.message) == ["third", "second", "first"])

		// Drop the newest and the oldest, which are not adjacent.
		#expect(await GitStash.drop([entries[0], entries[2]], in: root).exitCode == 0)
		#expect(await GitStash.list(in: root).map(\.message) == ["second"])
	}

	/// git cannot rename an entry, so this stores the same commit again and
	/// drops the old one — the work must come through untouched.
	@Test func renamingKeepsTheWork() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("the work\n", "a.txt", in: root)
		_ = await GitStash.push(in: root, message: "old name")
		guard let entry = await GitStash.list(in: root).first else {
			Issue.record("nothing was stashed")
			return
		}

		#expect(await GitStash.rename(entry, to: "a better name", in: root).exitCode == 0)

		let after = await GitStash.list(in: root)
		#expect(after.count == 1, "renaming must not leave the old entry behind")
		#expect(after.first?.message == "a better name")
		#expect(after.first?.commit == entry.commit, "the same commit, under another name")

		// And it still holds what it held.
		guard let renamed = after.first else { return }
		#expect(await GitStash.apply(renamed, in: root, keeping: false).exitCode == 0)
		#expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "the work\n")
	}

	/// Renaming the one in the middle: the entry that is dropped is the old one
	/// and not whatever has moved into its place.
	@Test func renamingOneOfSeveralDropsTheRightEntry() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		for name in ["oldest", "middle", "newest"] {
			try write("\(name)\n", "a.txt", in: root)
			_ = await GitStash.push(in: root, message: name)
		}
		let entries = await GitStash.list(in: root)
		guard entries.count == 3 else {
			Issue.record("expected three entries")
			return
		}

		#expect(await GitStash.rename(entries[1], to: "renamed", in: root).exitCode == 0)
		let after = await GitStash.list(in: root)
		#expect(after.map(\.message) == ["renamed", "newest", "oldest"])
	}
}

private extension Process {
	/// git, without the app's own plumbing: these tests are about what git
	/// does, so the arrangement should be as plain as possible.
	static func git(_ arguments: [String], in directory: URL) -> Int32 {
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
}

/// Moving a tag, which is what a GitHub Action's `v1` is for.
struct GitTagsLiveTests {
	private func repository() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("tags-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			#expect(Process.git(command, in: root) == 0)
		}
		return root
	}

	private func commit(_ text: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		#expect(Process.git(["add", "."], in: root) == 0)
		#expect(Process.git(["commit", "-qm", text], in: root) == 0)
	}

	private func commit(at reference: String, in root: URL) -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "rev-parse", reference]
		process.currentDirectoryURL = root
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		try? process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	@Test func aTagIsMovedToWhereItIsTold() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		#expect(Process.git(["tag", "v1"], in: root) == 0)
		#expect(Process.git(["tag", "v1.0.0"], in: root) == 0)
		try commit("two", in: root)
		#expect(Process.git(["tag", "v1.1.0"], in: root) == 0)

		#expect(await GitTags.recreate("v1", at: "v1.1.0", in: root).exitCode == 0)
		#expect(commit(at: "v1", in: root) == commit(at: "v1.1.0", in: root))
	}

	/// What the dialog should offer: the newest `v1.x`, by version and not by
	/// text — otherwise v1.9 beats v1.10, which is how a release goes backwards.
	@Test func theNewestVersionUnderTheTagIsSuggested() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		for name in ["v1", "v1.9.0", "v1.10.0", "v2.0.0"] {
			#expect(Process.git(["tag", name], in: root) == 0)
		}
		#expect(await GitTags.likelySource(for: "v1", in: root) == "v1.10.0")
	}

	/// Nothing to move it to: better to offer HEAD than nothing at all.
	@Test func withNoVersionsUnderItTheSuggestionIsHead() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		#expect(Process.git(["tag", "stable"], in: root) == 0)
		#expect(await GitTags.likelySource(for: "stable", in: root) == "HEAD")
	}

	/// The half that was missing: a tag that does not exist yet.
	///
	/// The app could always *move* one, because a tag it could move had a row
	/// to open a menu on. A tag that did not exist had no row, so there was
	/// nowhere for the verb to live and the feature was simply absent.
	@Test func aTagCanBeMadeAtACommit() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		#expect(await GitTags.create("v0.1.0", in: root).exitCode == 0)
		#expect(commit(at: "v0.1.0", in: root) == commit(at: "HEAD", in: root))
	}

	/// A release tag people read carries a message, and git makes that a tag
	/// object rather than a name pointing straight at the commit.
	@Test func aTagWithAMessageIsAnnotated() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		#expect(await GitTags.create("v0.1.0", message: "the first one", in: root).exitCode == 0)

		let kind = await GitRepository.run(["cat-file", "-t", "v0.1.0"], in: root)
		#expect(kind.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "tag")
	}

	/// And a marker somebody drops for their own use does not, because forcing
	/// a message on them would put an editor in the way of a one-second job.
	@Test func aTagWithNoMessageIsLightweight() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		#expect(await GitTags.create("v0.1.0", in: root).exitCode == 0)

		let kind = await GitRepository.run(["cat-file", "-t", "v0.1.0"], in: root)
		#expect(kind.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "commit")
	}

	/// What the picker in front of `recreate` depends on: a branch is a source
	/// like any other, and always was.
	@Test func aMovingTagCanBePointedAtABranch() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		#expect(await GitTags.create("v1", in: root).exitCode == 0)

		#expect(Process.git(["checkout", "-q", "-b", "release"], in: root) == 0)
		try commit("two", in: root)

		#expect(await GitTags.recreate("v1", at: "release", in: root).exitCode == 0)
		#expect(commit(at: "v1", in: root) == commit(at: "release", in: root))
	}

	@Test func aTagCanBeTakenAwayAgain() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one", in: root)
		#expect(await GitTags.create("v0.1.0", in: root).exitCode == 0)
		#expect(await GitTags.delete("v0.1.0", in: root).exitCode == 0)
		#expect(await GitTags.describe("v0.1.0", in: root) == nil)
	}

	/// And the half that actually matters to a workflow: the remote moves too.
	@Test func theTagIsForcedOntoTheRemote() async throws {
		let origin = try repository()
		defer { try? FileManager.default.removeItem(at: origin) }
		let bare = FileManager.default.temporaryDirectory
			.appendingPathComponent("origin-\(UUID().uuidString).git")
		defer { try? FileManager.default.removeItem(at: bare) }

		try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
		#expect(Process.git(["init", "-q", "--bare", "."], in: bare) == 0)

		try commit("one", in: origin)
		#expect(Process.git(["remote", "add", "origin", bare.path], in: origin) == 0)
		#expect(Process.git(["tag", "v1"], in: origin) == 0)
		#expect(await GitTags.push("v1", in: origin).exitCode == 0)

		// Moved here, and then over the one the remote already has — which is
		// what git refuses without force.
		try commit("two", in: origin)
		#expect(await GitTags.recreate("v1", at: "HEAD", in: origin).exitCode == 0)
		#expect(await GitTags.push("v1", in: origin).exitCode == 0)

		#expect(commit(at: "v1", in: origin) == commit(at: "v1", in: bare))
	}
}

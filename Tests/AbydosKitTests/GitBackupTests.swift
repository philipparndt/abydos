import Foundation
import Testing
@testable import AbydosKit

/// The way back from anything that could lose work.
///
/// Every claim here is about what git actually does with a throwaway index and
/// a ref, so all of it runs against a real repository. The one that matters
/// most is `capturesAFileGitHasNeverSeen`: `git stash create` was the obvious
/// way to write `captureWorkingCopy` and silently omits untracked files, which
/// would have made a discard of a new file "insured" by a commit not containing
/// it.
struct GitBackupTests {
	/// git without the app's plumbing, as `GitStashLiveTests` does it — these
	/// are claims about what git does, so the arrangement stays plain. Its own
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
			.appendingPathComponent("backup-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			#expect(git(command, in: root) == 0, "git \(command.joined(separator: " "))")
		}
		try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		#expect(git(["add", "."], in: root) == 0)
		#expect(git(["commit", "-qm", "first"], in: root) == 0)
		return root
	}

	private func write(_ text: String, _ name: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	@Test func aCleanWorkingCopyHasNothingToKeep() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await GitBackup.captureWorkingCopy(in: root) == nil)
	}

	@Test func capturingLeavesTheWorkingCopyAndTheStashAlone() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("changed\n", "a.txt", in: root)
		let commit = await GitBackup.captureWorkingCopy(in: root)
		#expect(commit != nil, "a changed file is something to keep")

		// The whole point: insurance that moved what it was insuring would be a
		// second surprise on top of the first.
		let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
		#expect(onDisk == "changed\n")
		#expect(await GitStash.list(in: root).isEmpty, "the stash list is not touched")
	}

	@Test func capturesAFileGitHasNeverSeen() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("brand new\n", "new.txt", in: root)
		guard let commit = await GitBackup.captureWorkingCopy(in: root) else {
			Issue.record("an untracked file is something to keep")
			return
		}

		let listed = await GitRepository.run(
			["ls-tree", "--name-only", commit], in: root
		)
		#expect(listed.stdout.contains("new.txt"), "stash create would have left it out")
	}

	@Test func whatIsIgnoredIsNotKept() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("build\n", ".gitignore", in: root)
		try write("object code\n", "build", in: root)
		guard let commit = await GitBackup.captureWorkingCopy(in: root) else {
			Issue.record("the .gitignore itself is a change")
			return
		}

		let listed = await GitRepository.run(["ls-tree", "--name-only", commit], in: root)
		#expect(!listed.stdout.contains("\nbuild\n"), "a backup is insurance, not a copy of build output")
	}

	@Test func aKeptRefIsAnOrdinaryBranch() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		let moment = Date(timeIntervalSince1970: 1_700_000_000)
		#expect(await GitBackup.keep(ref: "main", subject: "main", at: moment, in: root).exitCode == 0)

		// Listed by git itself, which is the argument for a branch over a
		// private namespace: recoverable by somebody who has never heard of
		// this program.
		let branches = await GitRepository.run(["branch", "--list", "backup/*"], in: root)
		#expect(branches.stdout.contains("backup/"))

		let kept = await GitBackup.list(in: root)
		#expect(kept.count == 1)
		#expect(kept.first?.name.hasPrefix("backup/") == true)
		#expect(kept.first?.name.hasSuffix("-main") == true)
	}

	@Test func aSweepTakesOnlyWhatIsOlderThanItWasAsked() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		let head = await GitRepository.run(["rev-parse", "HEAD"], in: root)
		let commit = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		#expect(await GitBackup.keep(commit, as: "backup/old-one", in: root).exitCode == 0)

		// The commit under both refs is the same and was made now, so nothing
		// is older than a day and nothing may be taken.
		let untouched = await GitBackup.sweep(olderThan: 86_400, now: Date(), in: root)
		#expect(untouched.isEmpty)
		#expect(await GitBackup.list(in: root).count == 1)

		// Asked from far enough in the future, the same ref is stale.
		let later = Date().addingTimeInterval(90 * 86_400)
		let taken = await GitBackup.sweep(olderThan: 86_400, now: later, in: root)
		#expect(taken.count == 1)
		#expect(await GitBackup.list(in: root).isEmpty)
	}

	@Test func aNameGitWouldRefuseIsMadeIntoOneItAccepts() {
		#expect(GitBackup.slug("feature/some thing~here") == "feature-some-thing-here")
		#expect(GitBackup.slug("...") == "work")
		#expect(GitBackup.slug("main") == "main")
	}

	@Test func aBackupIsNamedForWhenItWasMade() {
		let moment = Date(timeIntervalSince1970: 1_700_000_000)
		let name = GitBackup.name(for: "main", at: moment)
		#expect(name.hasPrefix("backup/"))
		#expect(name.hasSuffix("-main"))
	}
}

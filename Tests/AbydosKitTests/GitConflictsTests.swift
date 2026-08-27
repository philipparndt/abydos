import Foundation
import Testing
@testable import AbydosKit

/// A merge that stopped, and what is said about it.
///
/// Nothing on screen said a merge was half-done, which is the worst moment for
/// an editor to be quiet. These are the claims the banner rests on.
struct GitConflictsTests {
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

	private func write(_ text: String, _ name: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	/// A repository stopped in a real conflict.
	private func conflicted() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("conflict-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			#expect(git(command, in: root) == 0)
		}
		try write("one\n", "a.txt", in: root)
		#expect(git(["add", "."], in: root) == 0)
		#expect(git(["commit", "-qm", "first"], in: root) == 0)

		#expect(git(["checkout", "-q", "-b", "side"], in: root) == 0)
		try write("the side says this\n", "a.txt", in: root)
		#expect(git(["commit", "-qam", "side work"], in: root) == 0)

		#expect(git(["checkout", "-q", "main"], in: root) == 0)
		try write("main says something else\n", "a.txt", in: root)
		#expect(git(["commit", "-qam", "main work"], in: root) == 0)

		// Expected to fail: that is the state under test.
		_ = git(["merge", "side"], in: root)
		return root
	}

	@Test func aStoppedMergeNamesItsFiles() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await GitConflicts.paths(in: root) == ["a.txt"])
	}

	/// "Ours" and "theirs" swap meaning between merge and rebase, so what the
	/// banner says is read from what git left behind rather than guessed.
	@Test func itSaysWhatKindOfStopItWas() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }

		let said = await GitConflicts.describe(in: root)
		#expect(said?.hasPrefix("Merging") == true, "\(said ?? "nothing")")
		#expect(said?.contains("side work") == true, "and which commit is coming in")
	}

	/// The verb on its own, which is what the titlebar pill has room for.
	@Test func theOperationIsNamedWithoutAskingGitForTheCommit() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await GitConflicts.operation(in: root) == .merge)
		#expect(GitConflicts.Operation.merge.said == "merging")
		#expect(GitConflicts.Operation.cherryPick.titled == "Cherry-picking")
	}

	/// **A rebase that stops without a conflict.** `--exec false` halts the
	/// rebase with a clean work tree, so nothing is conflicted and the banner —
	/// which is driven by conflicted paths — says nothing. The pill still has
	/// to: this is the state where somebody most needs telling that the
	/// repository is not where they left it.
	@Test func aRebaseStoppedWithNoConflictIsStillAnOperation() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(git(["merge", "--abort"], in: root) == 0)

		// Replays main's own last commit onto its parent — nothing to conflict
		// with — and `false` fails, which is what stops the rebase.
		_ = git(["rebase", "--exec", "false", "HEAD~1"], in: root)

		#expect(await GitConflicts.paths(in: root).isEmpty, "nothing is conflicted")
		#expect(await GitConflicts.operation(in: root) == .rebase, "and yet a rebase is open")
		#expect(await GitConflicts.describe(in: root) == "Rebasing")
	}

	/// A rebase detaches the head, and the pill used to draw nothing at all for
	/// one: `Head.name` is nil, and that was the whole of what it asked.
	@Test func aDetachedHeadSaysWhereItIs() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(git(["merge", "--abort"], in: root) == 0)
		#expect(git(["checkout", "-q", "--detach", "main"], in: root) == 0)

		let repository = GitRepository(root: root)
		await repository.refresh()
		let state = await repository.currentHeadState()

		#expect(state.name == nil, "there is no branch, and nothing may pretend there is")
		#expect(state.isDetached)
		#expect(state.display?.hasPrefix("detached at ") == true, "\(state.display ?? "nothing")")
		#expect(state.operation == nil)
	}

	@Test func aCleanRepositoryHasNothingToSay() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(git(["merge", "--abort"], in: root) == 0)

		#expect(await GitConflicts.paths(in: root).isEmpty)
		#expect(await GitConflicts.describe(in: root) == nil)
		#expect(await GitConflicts.operation(in: root) == nil)
		#expect(await GitConflicts.prompt(in: root) == nil)
	}

	@Test func thePromptCarriesTheMarkersAndSaysWhatToDo() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }

		guard let prompt = await GitConflicts.prompt(in: root) else {
			Issue.record("something is conflicted")
			return
		}
		#expect(prompt.contains("a.txt"))
		#expect(prompt.contains("<<<<<<<"), "the markers are the conflict")
		#expect(prompt.contains("main says something else"))
		#expect(prompt.contains("the side says this"))
		#expect(prompt.contains("Do not commit"), "it resolves; it does not decide")
	}

	/// A resolution written against half a file is worse than none, and only
	/// the prompt can say which half it saw.
	@Test func aFileTooLargeToSendIsNamedRatherThanDropped() async throws {
		let root = try conflicted()
		defer { try? FileManager.default.removeItem(at: root) }

		guard let prompt = await GitConflicts.prompt(in: root, limit: 10) else {
			Issue.record("something is conflicted")
			return
		}
		#expect(prompt.contains("too large to include"))
		#expect(prompt.contains("- a.txt"))
	}

	@Test func gitsVersionIsReadFromWhatItSays() {
		#expect(GitStash.version(from: "git version 2.54.0 (Apple Git-157)")! == (2, 54))
		#expect(GitStash.version(from: "git version 2.35.1")! == (2, 35))
		#expect(GitStash.version(from: "not a version") == nil)
	}
}

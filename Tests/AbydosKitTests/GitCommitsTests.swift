import Foundation
import Testing
@testable import AbydosKit

/// Revert, cherry-pick and reset, and the difference between a conflict and a
/// failure.
///
/// A revert that hits a conflict exits non-zero having already written markers
/// into the work tree. Calling that a failure would say "it did not happen"
/// about something that half happened, which is why `Outcome` has three cases
/// and not two.
struct GitCommitsTests {
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
			.appendingPathComponent("commits-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			#expect(git(command, in: root) == 0, "git \(command.joined(separator: " "))")
		}
		return root
	}

	private func commit(_ text: String, _ subject: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		#expect(git(["add", "."], in: root) == 0)
		#expect(git(["commit", "-qm", subject], in: root) == 0)
	}

	private func head(of root: URL) async -> String {
		let result = await GitRepository.run(["rev-parse", "HEAD"], in: root)
		return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func contents(of root: URL) throws -> String {
		try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
	}

	@Test func revertingUndoesACommitWithAnotherOne() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one\n", "first", in: root)
		try commit("two\n", "second", in: root)

		#expect(await GitCommits.revert(await head(of: root), in: root) == .done)
		#expect(try contents(of: root) == "one\n")

		// Undone by adding, not by removing: the commit reverted is still there.
		let count = await GitRepository.run(["rev-list", "--count", "HEAD"], in: root)
		#expect(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "3")
	}

	@Test func cherryPickingBringsOneCommitAcross() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one\n", "first", in: root)
		#expect(git(["checkout", "-q", "-b", "side"], in: root) == 0)
		try commit("from the side\n", "side work", in: root)
		let picked = await head(of: root)

		#expect(git(["checkout", "-q", "main"], in: root) == 0)
		#expect(await GitCommits.cherryPick(picked, in: root) == .done)
		#expect(try contents(of: root) == "from the side\n")
	}

	@Test func aCherryPickThatCollidesSaysWhichFileItStoppedIn() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one\n", "first", in: root)
		#expect(git(["checkout", "-q", "-b", "side"], in: root) == 0)
		try commit("side says this\n", "side work", in: root)
		let picked = await head(of: root)

		#expect(git(["checkout", "-q", "main"], in: root) == 0)
		try commit("main says something else\n", "main work", in: root)

		let outcome = await GitCommits.cherryPick(picked, in: root)
		#expect(outcome == .conflicted(["a.txt"]), "a conflict is not a failure")

		// And there is a way back out of it, which is the other half of
		// reporting it as a conflict rather than as a failure.
		#expect(await GitCommits.abort(in: root) == .done)
		#expect(try contents(of: root) == "main says something else\n")
		#expect(await GitCommits.conflictedPaths(in: root).isEmpty)
	}

	@Test func resettingMovesTheBranchAndSaysHowFar() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one\n", "first", in: root)
		let target = await head(of: root)
		try commit("two\n", "second", in: root)
		try commit("three\n", "third", in: root)

		// The number a dialog leads with, before anything has happened.
		#expect(await GitCommits.count(of: "HEAD", notIn: target, in: root) == 2)

		#expect(await GitCommits.reset(to: target, mode: .hard, in: root) == .done)
		#expect(try contents(of: root) == "one\n")
		#expect(await head(of: root) == target)
	}

	@Test func aSoftResetKeepsTheWorkItMovedPast() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one\n", "first", in: root)
		let target = await head(of: root)
		try commit("two\n", "second", in: root)

		#expect(await GitCommits.reset(to: target, mode: .soft, in: root) == .done)
		#expect(await head(of: root) == target)
		// The branch moved; the file did not.
		#expect(try contents(of: root) == "two\n")
	}

	@Test func aCommitThatIsNotThereIsAFailureAndNotAConflict() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try commit("one\n", "first", in: root)

		let outcome = await GitCommits.revert("0123456789abcdef0123456789abcdef01234567", in: root)
		guard case .failed(let said) = outcome else {
			Issue.record("expected a failure, got \(outcome)")
			return
		}
		#expect(!said.isEmpty, "git's own words, so they are not invented here")
	}
}

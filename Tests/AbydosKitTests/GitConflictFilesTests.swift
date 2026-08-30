import Foundation
import Testing
@testable import AbydosKit

/// A repository stopped in the middle of a merge, and one stopped in the middle
/// of a rebase, so the two can be asked the same questions and disagree.
private struct Stopped {
	let root: URL

	static func make() async throws -> Stopped {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("conflict-files-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for arguments in [
			["init", "-q", "-b", "main"],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
			["config", "commit.gpgsign", "false"],
		] {
			_ = await GitRepository.run(arguments, in: root)
		}
		return Stopped(root: root)
	}

	func write(_ contents: String, to name: String) throws {
		try contents.write(
			to: root.appendingPathComponent(name), atomically: true, encoding: .utf8
		)
	}

	func read(_ name: String) -> String {
		(try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? ""
	}

	@discardableResult
	func git(_ arguments: String...) async -> GitRepository.ProcessResult {
		await GitRepository.run(arguments, in: root)
	}

	func commit(_ message: String) async {
		await git("add", "-A")
		await git("commit", "-qm", message)
	}

	/// Two branches that both changed the same two lines of the same two files.
	func divergeOnTwoFiles() async throws {
		try write("one\n", to: "a.txt")
		try write("one\n", to: "b.txt")
		try write("untouched\n", to: "c.txt")
		await commit("initial")

		await git("checkout", "-q", "-b", "side")
		try write("side\n", to: "a.txt")
		try write("side\n", to: "b.txt")
		await commit("side changes both")

		await git("checkout", "-q", "main")
		try write("main\n", to: "a.txt")
		try write("main\n", to: "b.txt")
		await commit("main changes both")
	}
}

@Suite(.serialized)
struct GitConflictWaitingTests {
	@Test func aStoppedMergeListsTheFilesItIsWaitingOn() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")

		let waiting = await GitConflicts.waiting(in: repository.root)
		#expect(waiting.map(\.path) == ["a.txt", "b.txt"])
		#expect(waiting.allSatisfy { !$0.isResolved })
		// One conflict region written into each.
		#expect(waiting.allSatisfy { $0.markers == 1 })
	}

	/// The list ticks rather than shrinking: git stops calling a path unmerged
	/// the moment it is staged, so without the remembered set the row would
	/// disappear and `1 of 2 resolved` could not be said.
	@Test func aResolvedFileKeepsItsPlaceAndTicks() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")

		let before = Set(await GitConflicts.paths(in: repository.root))
		#expect(await GitConflicts.take(.ours, of: "a.txt", in: repository.root) == nil)

		let waiting = await GitConflicts.waiting(in: repository.root, alsoShowing: before)
		#expect(waiting.map(\.path) == ["a.txt", "b.txt"], "the order holds")
		#expect(waiting.first?.isResolved == true)
		#expect(waiting.last?.isResolved == false)

		// Without the memory it is one row, which is the bug this parameter is
		// here to avoid.
		let forgotten = await GitConflicts.waiting(in: repository.root)
		#expect(forgotten.map(\.path) == ["b.txt"])
	}

	@Test func takingOursKeepsTheBranchYouAreOn() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")

		#expect(await GitConflicts.take(.ours, of: "a.txt", in: repository.root) == nil)
		#expect(repository.read("a.txt") == "main\n")
		#expect(await GitConflicts.take(.theirs, of: "b.txt", in: repository.root) == nil)
		#expect(repository.read("b.txt") == "side\n")

		// Both staged, so the merge can be finished.
		let unmerged = await GitConflicts.paths(in: repository.root)
		#expect(unmerged.isEmpty)
	}

	@Test func aFileEditedByHandIsStagedAsItStands() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")

		try repository.write("main and side\n", to: "a.txt")
		#expect(GitConflicts.markersLeft(in: "a.txt", under: repository.root) == 0)
		#expect(await GitConflicts.markResolved("a.txt", in: repository.root) == nil)

		let waiting = await GitConflicts.waiting(
			in: repository.root, alsoShowing: ["a.txt", "b.txt"]
		)
		#expect(waiting.first(where: { $0.path == "a.txt" })?.isResolved == true)
		// And what was written is what is staged.
		let staged = await GitRepository.run(["show", ":a.txt"], in: repository.root)
		#expect(staged.stdout == "main and side\n")
	}

	/// Markers are counted so the row can say a file has been opened and not
	/// finished — resolved by hand is the case with no other signal.
	@Test func markersAreCountedOffTheDisk() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")

		#expect(GitConflicts.markersLeft(in: "a.txt", under: repository.root) == 1)
		#expect(GitConflicts.markersLeft(in: "c.txt", under: repository.root) == 0)
		#expect(GitConflicts.markersLeft(in: "nothing.txt", under: repository.root) == 0)
	}
}

@Suite(.serialized)
struct GitConflictSidesTests {
	/// The headline the whole strip hangs off: which branch is coming in.
	@Test func aMergeNamesTheBranchComingIn() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")

		#expect(await GitConflicts.incoming(in: repository.root) == "side")
		let sides = await GitConflicts.sides(of: .merge, in: repository.root)
		#expect(sides.ours == "main")
		#expect(sides.theirs == "side")
	}

	/// **The half that is worth a test on its own.** `--ours` is stage 2 in
	/// both operations and means opposite things: rebasing replays your work
	/// onto somebody else's, so the branch you are on arrives as `--theirs`.
	@Test func aRebaseSwapsWhatOursMeans() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()

		await repository.git("checkout", "-q", "side")
		await repository.git("rebase", "main")
		#expect(await GitConflicts.operation(in: repository.root) == .rebase)

		let sides = await GitConflicts.sides(of: .rebase, in: repository.root)
		#expect(sides.ours == "main", "\(sides.ours) — what the commits are going onto")
		#expect(sides.theirs == "side", "\(sides.theirs) — the commits being replayed")

		// And the plumbing agrees: --ours is main's line here, not side's.
		#expect(await GitConflicts.take(.ours, of: "a.txt", in: repository.root) == nil)
		#expect(repository.read("a.txt") == "main\n")
	}

	/// The set survives a restart, because git wrote it down before it stopped.
	@Test func theMergeMessageRecordsWhatWasConflicted() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")

		#expect(await GitConflicts.recorded(in: repository.root) == ["a.txt", "b.txt"])

		// Resolved, and still remembered — which is the whole point of asking.
		#expect(await GitConflicts.take(.ours, of: "a.txt", in: repository.root) == nil)
		#expect(await GitConflicts.recorded(in: repository.root) == ["a.txt", "b.txt"])

		let waiting = await GitConflicts.waiting(
			in: repository.root, alsoShowing: await GitConflicts.recorded(in: repository.root)
		)
		#expect(waiting.map(\.path) == ["a.txt", "b.txt"])
		#expect(waiting.first?.isResolved == true)
	}

	/// **A rebase writes one too**, for the commit in hand — and git removes the
	/// file when that commit is done with, so the answer is never a previous
	/// stop's set. That is what makes it safe to ask on every refresh.
	@Test func aRebaseRecordsTheCommitInHandAndForgetsIt() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("checkout", "-q", "side")
		await repository.git("rebase", "main")

		#expect(await GitConflicts.recorded(in: repository.root) == ["a.txt", "b.txt"])

		await repository.git("checkout", "--ours", "--", "a.txt")
		await repository.git("checkout", "--ours", "--", "b.txt")
		await repository.git("add", "-A")
		_ = await GitConflicts.run(.carryOn, on: .rebase, in: repository.root)

		#expect(await GitConflicts.operation(in: repository.root) == nil, "the rebase is over")
		#expect(await GitConflicts.recorded(in: repository.root).isEmpty, "and so is the record")
	}

	/// A branch deleted after the merge started still has a name, because git
	/// wrote one into `.git/MERGE_MSG` before it stopped.
	@Test func theMergeMessageNamesABranchThatHasGone() async throws {
		let repository = try await Stopped.make()
		try await repository.divergeOnTwoFiles()
		await repository.git("merge", "side")
		await repository.git("branch", "-D", "side")

		#expect(await GitConflicts.incoming(in: repository.root) == "side")
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// Picking an item up, against real repositories.
struct BacklogRunnerTests {
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("runner-\(UUID().uuidString)")
			.appendingPathComponent("project")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		func git(_ arguments: [String]) { _ = GitRepository.runSync(arguments, in: root) }
		git(["init", "-q", "-b", "main", "."])
		git(["config", "user.email", "tester@example.com"])
		git(["config", "user.name", "A Tester"])
		try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		git(["add", "-A"])
		git(["commit", "-qm", "first"])
		return root
	}

	private func commit(_ root: URL) {
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "backlog"], in: root)
	}

	private func cleanUp(_ root: URL) {
		try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
	}

	@Test func onlyAReadyItemIsPickedUp() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.create(title: "Not agreed yet")
		commit(root)

		await #expect(throws: BacklogRunner.Problem.self) {
			_ = try await BacklogRunner.start(item, in: backlog, assistant: nil)
		}
	}

	@Test func anUncommittedItemIsRefusedRatherThanSentToAnEmptyWorktree() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.move(try backlog.create(title: "Written just now"), to: .ready)

		// The worktree is a checkout of HEAD. An item that is only on disk
		// would not be in it, and the agent would arrive with nothing to read.
		await #expect(throws: BacklogRunner.Problem.self) {
			_ = try await BacklogRunner.start(item, in: backlog, assistant: nil)
		}
		#expect(backlog.item(number: item.number)?.state == .ready)
	}

	@Test func startingMakesAWorktreeAndMovesTheItemOnBothSides() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.move(try backlog.create(title: "Scale images in tmux"), to: .ready)
		commit(root)

		let start = try await BacklogRunner.start(item, in: backlog, assistant: nil)
		defer { _ = GitRepository.runSync(["worktree", "remove", "--force", start.directory.path], in: root) }

		#expect(start.branch == "backlog/0001-scale-images-in-tmux")
		#expect(FileManager.default.fileExists(atPath: start.directory.path))

		// The project's copy, which is what the dashboard shows.
		#expect(backlog.items(in: .ready).isEmpty)
		#expect(backlog.items(in: .inProgress).map(\.number) == [1])

		// And the branch's copy, so the move lands with the work.
		let there = Backlog(projectRoot: start.directory)
		#expect(there.items(in: .inProgress).map(\.number) == [1])
		#expect(there.items(in: .ready).isEmpty)

		let run = BacklogRuns(projectRoot: root).run(for: 1)
		#expect(run?.branch == start.branch)
		#expect(run?.isPresent == true)
	}

	/// The fault 0458 was written for, as a test: an agent ticks in its own
	/// checkout, and until the branch lands the project's copy still says what it
	/// said when the item was picked up.
	@Test func theProgressIsTheWorktreesAndTheStateIsTheProjects() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.move(try backlog.create(title: "Ticked on the branch"), to: .ready)
		commit(root)

		let start = try await BacklogRunner.start(item, in: backlog, assistant: nil)
		defer { _ = GitRepository.runSync(["worktree", "remove", "--force", start.directory.path], in: root) }

		// The agent works: it ticks two steps and moves its copy to `completed/`,
		// which is what `done` does on the branch. None of it reaches the project
		// until somebody merges.
		let there = Backlog(projectRoot: start.directory)
		let onBranch = try #require(there.item(number: 1))
		var ticked = 0
		let text = onBranch.text().components(separatedBy: "\n").map { line -> String in
			guard line.contains("- [ ]"), ticked < 2 else { return line }
			ticked += 1
			return line.replacingOccurrences(of: "- [ ]", with: "- [x]")
		}.joined(separator: "\n")
		try text.write(to: onBranch.file, atomically: true, encoding: .utf8)
		_ = try there.move(onBranch, to: .completed)

		let run = try #require(BacklogRuns(projectRoot: root).run(for: 1))
		let copy = try #require(run.itemInWorktree)

		// Found by number, because the two copies are no longer at the same path.
		#expect(copy.state == .completed)
		#expect(backlog.item(number: 1)?.state == .inProgress)

		// And the fraction a card should show is the branch's, not the one the
		// project's copy has been holding since the item was picked up.
		#expect(copy.progress()?.done == 2)
		#expect(backlog.item(number: 1)?.progress()?.done == 0)
	}

	@Test func aWorktreeThatIsGoneHasNoCopyToRead() throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		let run = BacklogRun(
			number: 1,
			branch: "backlog/0001-a",
			worktree: root.appendingPathComponent("../never-made"),
			assistant: "claude"
		)
		// The project's copy is then all there is, and a caller that gets nothing
		// back knows to say so rather than pass an old number off as the branch's.
		#expect(run.isPresent == false)
		#expect(run.itemInWorktree == nil)
	}

	@Test func aWorktreeCanFindTheCheckoutItWasMadeFrom() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.move(try backlog.create(title: "Something"), to: .ready)
		commit(root)

		let start = try await BacklogRunner.start(item, in: backlog, assistant: nil)
		defer { _ = GitRepository.runSync(["worktree", "remove", "--force", start.directory.path], in: root) }

		// This is how `done`, run by an agent standing in the worktree, knows
		// where the machine's record of what is running lives.
		// Compared as paths, with symlinks resolved on both sides. Two URLs for
		// the same directory are unequal for two reasons at once here: a
		// temporary directory is `/var/folders/…` where git answers
		// `/private/var/folders/…`, and one of them ends in a slash.
		let primary = await BacklogRunner.primaryCheckout(from: start.directory)
		#expect(primary?.path == root.resolvingSymlinksInPath().path)
	}

	@Test func withoutAWorktreeTheWorkHappensInTheProject() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [], worktrees: false)
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.move(try backlog.create(title: "Small project"), to: .ready)

		// No commit needed: nothing is being checked out.
		let start = try await BacklogRunner.start(item, in: backlog, assistant: nil, useWorktree: false)
		#expect(start.branch == nil)
		#expect(start.directory == root)
		#expect(backlog.items(in: .inProgress).map(\.number) == [1])
	}

	@Test func theSameItemIsNotStartedTwice() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.move(try backlog.create(title: "Only once"), to: .ready)
		commit(root)

		let start = try await BacklogRunner.start(item, in: backlog, assistant: nil)
		defer { _ = GitRepository.runSync(["worktree", "remove", "--force", start.directory.path], in: root) }

		// Put back in `ready` by hand, which is the way somebody would blunder
		// into starting a second agent on a checkout that already has one.
		let existing = try #require(backlog.item(number: 1), "the item was not on disk to move back")
		let again = try backlog.move(existing, to: .ready)
		await #expect(throws: BacklogRunner.Problem.self) {
			_ = try await BacklogRunner.start(again, in: backlog, assistant: nil)
		}
	}

	@Test func aWorktreeDeletedByHandCanBeStartedAgain() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let item = try backlog.move(try backlog.create(title: "Resumed"), to: .ready)
		commit(root)

		let first = try await BacklogRunner.start(item, in: backlog, assistant: nil)
		// `rm -rf`, which is what people actually do. The branch survives it.
		try FileManager.default.removeItem(at: first.directory)

		let existing = try #require(backlog.item(number: 1), "the item was not on disk to move back")
		let again = try backlog.move(existing, to: .ready)
		let second = try await BacklogRunner.start(again, in: backlog, assistant: nil)
		defer { _ = GitRepository.runSync(["worktree", "remove", "--force", second.directory.path], in: root) }

		// The same branch checked out again, rather than a refusal that the
		// branch already exists — whatever was committed before is still there.
		#expect(second.branch == first.branch)
		#expect(FileManager.default.fileExists(atPath: second.directory.path))
	}

	@Test func nextIsTheLowestNumberedReadyItem() throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)

		#expect(BacklogRunner.next(in: backlog) == nil)
		_ = try backlog.move(try backlog.create(title: "First"), to: .ready)
		_ = try backlog.create(title: "Second, and still open")
		_ = try backlog.move(try backlog.create(title: "Third"), to: .ready)

		#expect(BacklogRunner.next(in: backlog)?.number == 1)
	}

	@Test func thePromptSaysWhereToWorkAndWhatToReadFirst() {
		let prompt = BacklogRunner.prompt(
			number: 443,
			title: "The capsule is clipped",
			path: ".abydos/backlog/in-progress/0443-the-capsule-is-clipped",
			branch: "backlog/0443-the-capsule-is-clipped"
		)
		#expect(prompt.contains("0443"))
		#expect(prompt.contains(".abydos/backlog/AGENTS.md"))
		#expect(prompt.contains("backlog/0443-the-capsule-is-clipped"))
		#expect(prompt.contains("abydos-backlog done 443"))
		// No absolute path into the project: that is the one checkout the agent
		// must not be working in.
		#expect(!prompt.contains("/Users/"))
	}

	@Test func runsAreForgottenWhenTheirWorktreeIsGone() throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		let runs = BacklogRuns(projectRoot: root)
		try runs.record(BacklogRun(
			number: 1,
			branch: "backlog/0001-a",
			worktree: root.appendingPathComponent("../gone"),
			assistant: "claude"
		))
		try runs.record(BacklogRun(number: 2, branch: "backlog/0002-b", worktree: root, assistant: "claude"))

		#expect(runs.all().count == 2)
		let pruned = try runs.prune()
		#expect(pruned.map(\.number) == [1])
		#expect(runs.all().map(\.number) == [2])
	}

	@Test func aRunSurvivesBeingWrittenAndReadBack() throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		let runs = BacklogRuns(projectRoot: root)
		let started = Date(timeIntervalSince1970: 1_700_000_000)
		try runs.record(BacklogRun(
			number: 7, branch: "backlog/0007-x", worktree: root, assistant: "claude", startedAt: started
		))

		// The date strategies have to match on both sides: mismatched, the
		// decode of the whole array fails and every run silently disappears.
		#expect(runs.run(for: 7)?.startedAt == started)
	}
}

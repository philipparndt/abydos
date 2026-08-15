import Foundation
import Testing
@testable import AbydosKit

/// Listing, adding and removing worktrees, against real repositories.
struct GitWorktreesTests {
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("worktree-\(UUID().uuidString)")
			.appendingPathComponent("main")
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

	private func cleanUp(_ root: URL) {
		try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
	}

	@Test func listsTheRepositoryItself() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }

		let worktrees = await GitWorktrees.list(in: root)
		#expect(worktrees.count == 1)
		#expect(worktrees.first?.isPrimary == true)
		#expect(worktrees.first?.branch == "main")
		#expect(worktrees.first?.head.count == 40)
	}

	@Test func addsOneOnANewBranch() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }

		let path = GitWorktrees.suggestedPath(for: "feature/login", root: root)
		let result = await GitWorktrees.add(
			at: path, branch: "feature/login", createBranch: true, in: root
		)
		#expect(result.exitCode == 0)

		let worktrees = await GitWorktrees.list(in: root)
		#expect(worktrees.count == 2)

		let added = try #require(worktrees.first { !$0.isPrimary })
		#expect(added.branch == "feature/login")
		#expect(added.path.lastPathComponent == "main-feature-login")
		#expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("a.txt").path))
	}

	/// Checking out a branch that already exists, rather than making one.
	@Test func addsOneOnAnExistingBranch() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }
		_ = GitRepository.runSync(["branch", "existing"], in: root)

		let path = GitWorktrees.suggestedPath(for: "existing", root: root)
		#expect(await GitWorktrees.add(
			at: path, branch: "existing", createBranch: false, in: root
		).exitCode == 0)

		let worktrees = await GitWorktrees.list(in: root)
		#expect(worktrees.contains { $0.branch == "existing" })
	}

	@Test func removesOne() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }

		let path = GitWorktrees.suggestedPath(for: "temp", root: root)
		_ = await GitWorktrees.add(at: path, branch: "temp", createBranch: true, in: root)
		let added = try #require(await GitWorktrees.list(in: root).first { !$0.isPrimary })

		#expect(await GitWorktrees.remove(added, in: root).exitCode == 0)
		#expect(await GitWorktrees.list(in: root).count == 1)
		#expect(!FileManager.default.fileExists(atPath: path.path))
	}

	/// One with uncommitted work is not removed by accident.
	@Test func refusesToRemoveOneWithChanges() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }

		let path = GitWorktrees.suggestedPath(for: "busy", root: root)
		_ = await GitWorktrees.add(at: path, branch: "busy", createBranch: true, in: root)
		try "changed\n".write(to: path.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

		let added = try #require(await GitWorktrees.list(in: root).first { !$0.isPrimary })
		#expect(await GitWorktrees.remove(added, in: root).exitCode != 0)
		#expect(await GitWorktrees.list(in: root).count == 2)

		// And is removed when somebody says so anyway.
		#expect(await GitWorktrees.remove(added, force: true, in: root).exitCode == 0)
		#expect(await GitWorktrees.list(in: root).count == 1)
	}

	/// The usual state after somebody deletes a worktree with rm -rf.
	@Test func noticesOneWhoseDirectoryIsGone() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }

		let path = GitWorktrees.suggestedPath(for: "gone", root: root)
		_ = await GitWorktrees.add(at: path, branch: "gone", createBranch: true, in: root)
		try FileManager.default.removeItem(at: path)

		let missing = try #require(await GitWorktrees.list(in: root).first { !$0.isPrimary })
		#expect(missing.isMissing)

		_ = await GitWorktrees.prune(in: root)
		#expect(await GitWorktrees.list(in: root).count == 1)
	}

	/// A worktree inside the work tree would show up as untracked in its own
	/// status, so the suggestion puts it beside the repository.
	@Test func suggestsAPathBesideTheRepository() {
		let root = URL(fileURLWithPath: "/dev/project")
		let path = GitWorktrees.suggestedPath(for: "feature/x", root: root)
		#expect(path.path == "/dev/project-feature-x")
		#expect(!path.path.hasPrefix(root.path + "/"))
	}

	// MARK: - Parsing

	@Test func readsTheDetachedAndLockedFlags() {
		let output = """
		worktree /dev/project
		HEAD abc123
		branch refs/heads/main

		worktree /dev/project-detached
		HEAD def456
		detached

		worktree /dev/project-locked
		HEAD 789abc
		branch refs/heads/wip
		locked

		"""
		let worktrees = GitWorktrees.parse(output)
		#expect(worktrees.count == 3)
		#expect(worktrees[0].isPrimary)
		#expect(worktrees[0].branch == "main")
		#expect(worktrees[1].branch == nil)
		#expect(worktrees[2].isLocked)
		#expect(worktrees[2].branch == "wip")
	}

	/// 0477's three states, from the one listing and without running anything
	/// else: a branch, a branch with nothing on it, and a commit checked out
	/// directly.
	@Test func namesTheThreeStatesABranchCanBeIn() {
		let worktrees = GitWorktrees.parse("""
		worktree /dev/project
		HEAD abc1234def5678
		branch refs/heads/main

		worktree /dev/project-fresh
		HEAD 0000000000000000000000000000000000000000
		branch refs/heads/main

		worktree /dev/project-detached
		HEAD def4567abc1234
		detached

		""")
		#expect(worktrees.count == 3)

		#expect(!worktrees[0].isUnborn)
		#expect(worktrees[0].summary == "main")

		#expect(worktrees[1].isUnborn)
		#expect(worktrees[1].summary == "main — no commits yet")

		#expect(!worktrees[2].isUnborn)
		#expect(worktrees[2].summary == "detached at def4567")
	}

	/// The one in the listing this repository actually produces, rather than one
	/// written out by hand: `git init` and nothing committed.
	@Test func aCheckoutWithNothingCommittedSaysSo() async throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("worktree-unborn-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)

		let worktree = try #require(await GitWorktrees.list(in: root).first)
		#expect(worktree.branch == "main")
		#expect(worktree.isUnborn)
		#expect(worktree.summary == "main — no commits yet")
	}

	// MARK: - Ordering

	/// The primary is the way back, so it is first whether or not anybody has
	/// touched it lately — which on a repository with fifty branch worktrees is
	/// exactly the case that would have buried it.
	@Test func theOneTheRepositoryWasClonedIntoComesFirstEvenWhenItIsTheStalest() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }

		for name in ["alpha", "beta"] {
			_ = await GitWorktrees.add(
				at: GitWorktrees.suggestedPath(for: name, root: root),
				branch: name, createBranch: true, in: root
			)
		}

		// The primary made first and untouched since; the others after it.
		let ordered = GitWorktrees.byRecentActivity(await GitWorktrees.list(in: root))
		#expect(ordered.count == 3)
		#expect(ordered.first?.isPrimary == true)
	}

	/// What makes a menu of seventy-four usable: the one being worked in is near
	/// the top rather than wherever git happened to create it.
	///
	/// **The times are set rather than produced.** Three worktrees made in a row
	/// are made within the same second, and a filesystem mtime has one second to
	/// tell them apart with — so a test that worked in one of them and hoped
	/// proved nothing about the ordering and everything about how fast the
	/// machine is. Stating the input says the claim exactly: given these times,
	/// this order.
	@Test func theMostRecentlyWorkedInComesBeforeTheOthers() async throws {
		let root = try makeRepository()
		defer { cleanUp(root) }

		for name in ["first", "second", "third"] {
			_ = await GitWorktrees.add(
				at: GitWorktrees.suggestedPath(for: name, root: root),
				branch: name, createBranch: true, in: root
			)
		}

		// A linked worktree's own `.git` is a pointer written once, so the index
		// this touches is the one at the far end of it — which is the whole of
		// what `lastActivity` had to learn to follow for this ordering to mean
		// anything.
		let metadata = root.appendingPathComponent(".git/worktrees")
		for (name, minutes) in [("main-first", 5), ("main-second", 90), ("main-third", 30)] {
			// Both, because both are read: `index` moves on status, add and
			// commit, `HEAD` on a checkout, and a worktree is as recent as the
			// later of them.
			for file in ["index", "HEAD"] {
				try FileManager.default.setAttributes(
					[.modificationDate: Date().addingTimeInterval(-60 * Double(minutes))],
					ofItemAtPath: metadata.appendingPathComponent("\(name)/\(file)").path
				)
			}
		}

		let ordered = GitWorktrees.byRecentActivity(await GitWorktrees.list(in: root))
		#expect(ordered.map(\.name) == ["main", "main-first", "main-third", "main-second"])
	}

	/// Two readings of an untouched repository must not shuffle the menu under
	/// somebody who is looking at it.
	@Test func anOrderWithNothingToTellApartIsStillTheSameOrderTwice() {
		let worktrees = ["/dev/p-c", "/dev/p-a", "/dev/p-b"].enumerated().map {
			GitWorktree(
				path: URL(fileURLWithPath: $0.element), branch: "x", head: "abc",
				isPrimary: $0.offset == 0
			)
		}
		// None of these exists, so every mtime is distantPast and only the tie
		// break is left to decide.
		let once = GitWorktrees.byRecentActivity(worktrees).map(\.name)
		let twice = GitWorktrees.byRecentActivity(worktrees.reversed()).map(\.name)
		#expect(once == ["p-c", "p-a", "p-b"])
		#expect(twice == ["p-c", "p-a", "p-b"])
	}

	@Test func survivesOutputWithoutATrailingBlankLine() {
		let worktrees = GitWorktrees.parse("worktree /dev/a\nHEAD abc\nbranch refs/heads/main")
		#expect(worktrees.count == 1)
		#expect(worktrees.first?.branch == "main")
	}

	@Test func saysNothingAboutSomewhereThatIsNotARepository() async {
		let empty = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("no-repo-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: empty) }
		#expect(await GitWorktrees.list(in: empty).isEmpty)
	}
}

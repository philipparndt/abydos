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

	// MARK: - Naming one in a list

	/// Every worktree this app makes is named out of its branch, so a row that
	/// showed both said the same thing twice — at a hundred and thirty
	/// characters, on this repository.
	@Test func aFolderNamedAfterItsBranchIsNotSaidTwice() {
		let derived = GitWorktree(
			path: URL(fileURLWithPath: "/dev/abydos-backlog-0479-toggle-comment"),
			branch: "backlog/0479-toggle-comment", head: "abc1234", isPrimary: false
		)
		#expect(GitWorktrees.label(for: derived, primaryName: "abydos")
			== "backlog/0479-toggle-comment")
	}

	/// A directory somebody named themselves is worth reading, because it is the
	/// only thing saying why that checkout exists — and the repository's own name
	/// comes off the front of it, since every row in the list is a checkout of
	/// that repository.
	@Test func aFolderNamedBySomebodyKeepsItsNameWithoutTheRepositorySPrefix() {
		let chosen = GitWorktree(
			path: URL(fileURLWithPath: "/dev/abydos-ghostty-write"),
			branch: "backlog/0492-libghostty-vt-costs-half-a-millisecond",
			head: "abc1234", isPrimary: false
		)
		#expect(GitWorktrees.label(for: chosen, primaryName: "abydos")
			== "ghostty-write — backlog/0492-libghostty-vt-costs-half-a-millisecond")
	}

	/// The rule the other way about: an agent harness names the directory and
	/// then the branch after it, so the folder is the shorter of two names for
	/// the same thing.
	@Test func aBranchNamedAfterItsFolderLosesToTheFolder() {
		let agent = GitWorktree(
			path: URL(fileURLWithPath: "/dev/x/.claude/worktrees/agent-a0644a283cb87a9eb"),
			branch: "worktree-agent-a0644a283cb87a9eb", head: "abc1234", isPrimary: false
		)
		#expect(GitWorktrees.label(for: agent, primaryName: "abydos")
			== "agent-a0644a283cb87a9eb")
	}

	/// The primary is the repository itself and the way back, so it says which
	/// repository even when its branch would have stood alone.
	@Test func theOneTheRepositoryWasClonedIntoAlwaysSaysItsName() {
		let primary = GitWorktree(
			path: URL(fileURLWithPath: "/dev/abydos"),
			branch: "main", head: "abc1234", isPrimary: true
		)
		#expect(GitWorktrees.label(for: primary, primaryName: "abydos") == "abydos — main")
	}

	/// The two states with no branch to fall back on keep their folder name,
	/// because otherwise the row would be `detached at abc1234` and nothing else.
	@Test func aCheckoutWithNoBranchStillSaysWhereItIs() {
		let detached = GitWorktree(
			path: URL(fileURLWithPath: "/dev/abydos-spike"),
			branch: nil, head: "abc1234def", isPrimary: false
		)
		#expect(GitWorktrees.label(for: detached, primaryName: "abydos")
			== "spike — detached at abc1234")

		let unborn = GitWorktree(
			path: URL(fileURLWithPath: "/dev/abydos-fresh"),
			branch: "main", head: String(repeating: "0", count: 40), isPrimary: false
		)
		#expect(GitWorktrees.label(for: unborn, primaryName: "abydos")
			== "fresh — main — no commits yet")
	}

	/// What the titlebar adds beside a branch it is already showing, which is
	/// less than a menu row adds because the branch is on screen there.
	@Test func aTitlebarSaysOnlyWhatTheBranchBesideItHasNot() {
		func qualifier(folder: String, branch: String?, isPrimary: Bool = false) -> String? {
			GitWorktrees.qualifier(
				for: GitWorktree(
					path: URL(fileURLWithPath: "/dev/\(folder)"),
					branch: branch, head: "abc1234def", isPrimary: isPrimary
				),
				primaryName: "abydos"
			)
		}

		// The capsule has said the repository's name.
		#expect(qualifier(folder: "abydos", branch: "main", isPrimary: true) == nil)
		// …and here it has said the branch, which the folder was made out of.
		#expect(qualifier(
			folder: "abydos-backlog-0490-worktrees",
			branch: "backlog/0490-worktrees-chosen-from-the-titlebar"
		) == nil)
		// The other containment: a menu row would show the folder as the shorter
		// of the two, but the longer one is already up there.
		#expect(qualifier(
			folder: "agent-a0644a283cb87a9eb", branch: "worktree-agent-a0644a283cb87a9eb"
		) == nil)
		// A directory somebody chose, which nothing else on the titlebar says.
		#expect(qualifier(folder: "abydos-hotfix", branch: "release/2.1") == "hotfix")
		// No branch on the capsule to have said anything.
		#expect(qualifier(folder: "abydos-spike", branch: nil) == "spike")
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

/// Which checkout holds a branch — the fact behind git's refusal.
///
/// `git checkout ui` where another worktree has `ui` exits non-zero with
/// `fatal: 'ui' is already used by worktree at '/…/agent-a9b2'`. Every word is
/// true and none of it is actionable, and the path is in a sentence rather than
/// in an answer. This is the answer.
struct BranchHolderTests {
	private func worktree(
		_ path: String, branch: String?, isPrimary: Bool = false, isMissing: Bool = false
	) -> GitWorktree {
		GitWorktree(
			path: URL(fileURLWithPath: path),
			branch: branch,
			head: "abc123",
			isPrimary: isPrimary,
			isMissing: isMissing,
			isLocked: false
		)
	}

	private var repository: [GitWorktree] {
		[
			worktree("/Users/me/dev/cuttr", branch: "main", isPrimary: true),
			worktree("/Users/me/dev/cuttr/.claude/worktrees/agent-a9b2", branch: "ui"),
			worktree("/Users/me/dev/cuttr/.claude/worktrees/agent-b1c3", branch: nil),
			worktree("/Users/me/dev/cuttr/.claude/worktrees/gone", branch: "stale", isMissing: true),
		]
	}

	@Test func theWorktreeThatHasIt() {
		let found = GitWorktrees.holder(of: "ui", in: repository)
		#expect(found?.path.lastPathComponent == "agent-a9b2")
		#expect(found?.isPrimary == false)
	}

	/// The original clone is a checkout like any other, and reads differently in
	/// a sentence — which is why the row it comes back on says so.
	@Test func thePrimaryCheckoutCanHoldItToo() {
		#expect(GitWorktrees.holder(of: "main", in: repository)?.isPrimary == true)
	}

	@Test func aBranchNobodyHasIsNobodys() {
		#expect(GitWorktrees.holder(of: "feature/other", in: repository) == nil)
		#expect(GitWorktrees.holder(of: "", in: repository) == nil)
	}

	/// **A detached worktree holds no branch**, and `nil == nil` would have made
	/// every one of them a match for a branch nobody named.
	@Test func aDetachedWorktreeHoldsNothing() {
		let detached = [worktree("/Users/me/dev/x/w", branch: nil)]
		#expect(GitWorktrees.holder(of: "ui", in: detached) == nil)
	}

	/// A name that begins another name is a different branch. `ui` is not
	/// `ui-rework`, and a prefix test would have said it was.
	@Test func aNameThatStartsAnotherNameIsNotIt() {
		let trees = [worktree("/Users/me/dev/x/w", branch: "ui-rework")]
		#expect(GitWorktrees.holder(of: "ui", in: trees) == nil)
		#expect(GitWorktrees.holder(of: "ui-rework", in: trees)?.branch == "ui-rework")
	}

	/// **The checkout doing the asking is not an answer.** A branch held by the
	/// worktree somebody is already in cannot be why a checkout failed — git
	/// would have succeeded — and offering to open the window's own project is an
	/// offer to do nothing.
	@Test func theCheckoutAskingIsNotOfferedToItself() {
		let asking = URL(fileURLWithPath: "/Users/me/dev/cuttr/.claude/worktrees/agent-a9b2")
		#expect(GitWorktrees.holder(of: "ui", in: repository, excluding: asking) == nil)
		// And a different checkout still answers.
		#expect(GitWorktrees.holder(of: "main", in: repository, excluding: asking)?.isPrimary == true)
	}

	/// A registration whose directory is gone still holds the branch as far as
	/// git is concerned, which is exactly why it has to come back — with the fact
	/// that it is missing, so the offer can be a prune rather than an open.
	@Test func aMissingWorktreeStillHoldsItsBranch() {
		let found = GitWorktrees.holder(of: "stale", in: repository)
		#expect(found?.isMissing == true)
	}
}

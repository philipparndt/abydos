import Foundation
import Testing
@testable import AbydosKit

/// What the commit view needs to know before offering a push.
struct GitPushStateTests {
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("push-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)
		_ = GitRepository.runSync(["config", "user.email", "t@example.com"], in: root)
		_ = GitRepository.runSync(["config", "user.name", "A Tester"], in: root)
		try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "first"], in: root)
		return root
	}

	@Test func saysThereIsNothingToPushToWithoutARemote() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let state = try #require(await GitPush.state(in: root))
		#expect(state.branch == "main")
		#expect(state.upstream == nil)
		#expect(!state.hasRemote)
		#expect(!state.canPush)
	}

	/// A branch that has never been pushed offers to publish itself, and counts
	/// everything on it: there are no tracking counts to read yet.
	@Test func offersToPublishAnUnpushedBranch() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let remote = root.appendingPathExtension("remote.git")
		defer { try? FileManager.default.removeItem(at: remote) }
		_ = GitRepository.runSync(["init", "-q", "--bare", remote.path], in: root)
		_ = GitRepository.runSync(["remote", "add", "origin", remote.path], in: root)

		let state = try #require(await GitPush.state(in: root))
		#expect(state.hasRemote)
		#expect(state.upstream == nil)
		#expect(state.ahead == 1)
		#expect(state.canPush)
		#expect(state.buttonTitle == "Publish Branch")
	}

	@Test func countsWhatTheRemoteHasNotSeen() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let remote = root.appendingPathExtension("remote.git")
		defer { try? FileManager.default.removeItem(at: remote) }
		_ = GitRepository.runSync(["init", "-q", "--bare", remote.path], in: root)
		_ = GitRepository.runSync(["remote", "add", "origin", remote.path], in: root)

		let pushed = await GitPush.push(in: root, setUpstream: true)
		#expect(pushed.exitCode == 0)

		let afterPush = try #require(await GitPush.state(in: root))
		#expect(afterPush.upstream == "origin/main")
		#expect(afterPush.ahead == 0)
		#expect(!afterPush.canPush)
		#expect(afterPush.buttonTitle == "Push")

		try "two\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "second"], in: root)

		let ahead = try #require(await GitPush.state(in: root))
		#expect(ahead.ahead == 1)
		#expect(ahead.canPush)
		#expect(ahead.buttonTitle == "Push 1")
	}

	/// A repository with nothing committed still knows which branch it is on,
	/// and still cannot push it. What changed with item 0477 is that it can now
	/// say which branch that is instead of coming back as nothing at all.
	@Test func namesTheBranchItCannotPushYet() async throws {
		let root = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("push-empty-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)
		let remote = root.appendingPathExtension("remote.git")
		defer { try? FileManager.default.removeItem(at: remote) }
		_ = GitRepository.runSync(["init", "-q", "--bare", remote.path], in: root)
		_ = GitRepository.runSync(["remote", "add", "origin", remote.path], in: root)

		let state = try #require(await GitPush.state(in: root))
		#expect(state.branch == "main")
		#expect(!state.hasCommits)
		#expect(state.hasRemote)
		// There is no ref to send, so the offer is not made — and the button no
		// longer reads "Publish Branch" for a branch that cannot be published.
		#expect(!state.canPush)
		#expect(state.buttonTitle == "Push")
		#expect(state.explanation == "“main” has no commits yet")
	}

	/// A detached HEAD has no branch to push and no name to offer, which is a
	/// different answer from the one above and has to stay one.
	@Test func offersNothingForADetachedHead() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(GitRepository.runSync(["checkout", "-q", "--detach"], in: root).exitCode == 0)

		#expect(await GitPush.state(in: root) == nil)
	}

	/// Pushing what the remote already moved past fails rather than forcing.
	@Test func reportsARejectedPush() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let remote = root.appendingPathExtension("remote.git")
		defer { try? FileManager.default.removeItem(at: remote) }
		_ = GitRepository.runSync(["init", "-q", "--bare", remote.path], in: root)
		_ = GitRepository.runSync(["remote", "add", "origin", remote.path], in: root)
		_ = await GitPush.push(in: root, setUpstream: true)

		// Somebody else pushes, through a second clone of the same remote.
		let other = root.appendingPathExtension("clone")
		defer { try? FileManager.default.removeItem(at: other) }
		_ = GitRepository.runSync(["clone", "-q", remote.path, other.path], in: root)
		_ = GitRepository.runSync(["config", "user.email", "o@example.com"], in: other)
		_ = GitRepository.runSync(["config", "user.name", "Other"], in: other)
		try "theirs\n".write(to: other.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
		_ = GitRepository.runSync(["add", "-A"], in: other)
		_ = GitRepository.runSync(["commit", "-qm", "theirs"], in: other)
		_ = GitRepository.runSync(["push", "-q", "origin", "HEAD"], in: other)

		try "mine\n".write(to: root.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "mine"], in: root)

		let result = await GitPush.push(in: root, setUpstream: false)
		#expect(result.exitCode != 0)
		#expect(result.stderr.contains("rejected") || result.stdout.contains("rejected"))
	}
}

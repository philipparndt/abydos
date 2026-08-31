import Foundation
import Testing
@testable import AbydosKit

/// Reading the log.
struct GitHistoryTests {
	/// A repository with a handful of commits, built by actually running git.
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("history-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		func git(_ arguments: [String], input: Data? = nil) {
			_ = GitRepository.runSync(arguments, in: root, input: input)
		}
		git(["init", "-q", "."])
		git(["config", "user.email", "tester@example.com"])
		git(["config", "user.name", "A Tester"])

		try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		git(["add", "-A"])
		git(["commit", "-qm", "first commit"])

		try "one\ntwo\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		try "hello\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
		git(["add", "-A"])
		git(["commit", "-qm", "second commit\n\nWith a body that explains it."])

		git(["mv", "b.txt", "c.txt"])
		git(["commit", "-qm", "rename b to c"])

		return root
	}

	@Test func listsCommitsNewestFirst() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let commits = await GitHistory.log(in: root)
		#expect(commits.count == 3)
		#expect(commits.first?.subject == "rename b to c")
		#expect(commits.last?.subject == "first commit")
	}

	/// A message can contain anything, including whatever might be used as a
	/// separator, so the fields must survive it.
	@Test func survivesAwkwardMessages() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = GitRepository.runSync(["commit", "--allow-empty", "-qm", "a | b\ttab, and \"quotes\""], in: root)
		let commits = await GitHistory.log(in: root)
		#expect(commits.first?.subject == "a | b\ttab, and \"quotes\"")
	}

	@Test func readsAuthorDateAndBody() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let commits = await GitHistory.log(in: root)
		let second = try #require(commits.first { $0.subject == "second commit" })
		#expect(second.authorName == "A Tester")
		#expect(second.authorEmail == "tester@example.com")
		#expect(second.body == "With a body that explains it.")
		#expect(second.date.timeIntervalSince1970 > 0)
		#expect(!second.isMerge)
		#expect(second.shortHash.count == 7)
	}

	@Test func namesTheBranchAtTheTip() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let commits = await GitHistory.log(in: root)
		#expect(commits.first?.refs.contains { $0 == "main" || $0 == "master" } == true)
	}

	@Test func takesAWindowOfTheLog() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let page = await GitHistory.log(in: root, skip: 1, limit: 1)
		#expect(page.count == 1)
		#expect(page.first?.subject == "second commit")
		#expect(await GitHistory.count(in: root) == 3)
	}

	@Test func searchesMessages() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let found = await GitHistory.log(in: root, search: "RENAME")
		#expect(found.count == 1)
		#expect(found.first?.subject == "rename b to c")
	}

	/// The history of one file, across the rename that would otherwise end it.
	@Test func followsAFileThroughARename() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let history = await GitHistory.log(in: root, path: "c.txt")
		#expect(history.count == 2)
		#expect(history.map(\.subject) == ["rename b to c", "second commit"])
	}

	@Test func listsWhatACommitTouched() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let commits = await GitHistory.log(in: root)
		let second = try #require(commits.first { $0.subject == "second commit" })
		let files = await GitHistory.files(of: second.hash, in: root)

		#expect(files.count == 2)
		#expect(files.contains { $0.path == "a.txt" && $0.kind == .modified })
		#expect(files.contains { $0.path == "b.txt" && $0.kind == .added })
	}

	@Test func reportsARenameWithWhereItCameFrom() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let commits = await GitHistory.log(in: root)
		let files = await GitHistory.files(of: try #require(commits.first).hash, in: root)
		let renamed = try #require(files.first)
		#expect(renamed.kind == .renamed)
		#expect(renamed.path == "c.txt")
		#expect(renamed.originalPath == "b.txt")
	}

	@Test func showsTheDiffACommitMade() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let commits = await GitHistory.log(in: root)
		let second = try #require(commits.first { $0.subject == "second commit" })
		let diff = await GitHistory.diff(of: second.hash, path: "a.txt", in: root)

		#expect(diff.contains("+two"))
		#expect(!diff.contains("hello"))
	}

	@Test func readsAFileAsItWas() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let commits = await GitHistory.log(in: root)
		let first = try #require(commits.last)
		#expect(await GitHistory.contents(of: "a.txt", at: first.hash, in: root) == "one\n")
	}

	@Test func saysNothingAboutSomewhereThatIsNotARepository() async {
		let empty = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("not-a-repo-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: empty) }

		#expect(await GitHistory.log(in: empty).isEmpty)
		#expect(await GitHistory.count(in: empty) == 0)
	}
}

/// Which commits have not left the machine.
struct GitUnpushedTests {
	/// Builds a repository with two commits and returns it.
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("unpushed-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		func git(_ arguments: [String]) {
			_ = GitRepository.runSync(arguments, in: root)
		}
		git(["init", "-q", "-b", "main", "."])
		git(["config", "user.email", "tester@example.com"])
		git(["config", "user.name", "A Tester"])

		try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		git(["add", "-A"])
		git(["commit", "-qm", "first"])
		return root
	}

	private func head(of root: URL) -> String {
		GitRepository.runSync(["rev-parse", "HEAD"], in: root).stdout
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// A repository with no remote at all has everything unpushed: there is
	/// nowhere it could have gone.
	@Test func reportsEverythingWhenThereIsNoRemote() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let unpushed = await GitHistory.unpushed(in: root)
		#expect(unpushed == [head(of: root)])
	}

	/// What a remote already has is not unpushed, whatever the local branch's
	/// upstream happens to be set to.
	@Test func excludesWhatARemoteAlreadyHas() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let remote = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("remote-\(UUID().uuidString).git")
		defer { try? FileManager.default.removeItem(at: remote) }
		_ = GitRepository.runSync(["init", "-q", "--bare", remote.path], in: root)
		_ = GitRepository.runSync(["remote", "add", "origin", remote.path], in: root)
		_ = GitRepository.runSync(["push", "-q", "origin", "main"], in: root)

		let pushed = head(of: root)
		try "two\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "second"], in: root)
		let local = head(of: root)

		let unpushed = await GitHistory.unpushed(in: root)
		#expect(unpushed == [local])
		#expect(!unpushed.contains(pushed))
	}
}

/// Which commits the upstream has that the branch does not — what a pull
/// would bring, and what the scoped log must therefore show.
struct GitRemoteOnlyTests {
	/// A working copy publishing `main` to a bare "remote" in temp, and a
	/// second clone to put the remote ahead with. Returned as (work, remote,
	/// other); the caller removes all three.
	private func makePublishedRepository() throws -> (work: URL, remote: URL, other: URL) {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
		let work = base.appendingPathComponent("remote-only-\(UUID().uuidString)")
		let remote = base.appendingPathComponent("remote-only-\(UUID().uuidString).git")
		let other = base.appendingPathComponent("remote-only-\(UUID().uuidString)-other")
		try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

		func git(_ arguments: [String], in root: URL = work) {
			_ = GitRepository.runSync(arguments, in: root)
		}
		func commit(_ name: String, message: String, in root: URL) throws {
			try "\(name)\n".write(
				to: root.appendingPathComponent(name), atomically: true, encoding: .utf8
			)
			git(["add", "-A"], in: root)
			git(["commit", "-qm", message], in: root)
		}

		git(["init", "-q", "-b", "main", "."])
		git(["config", "user.email", "tester@example.com"])
		git(["config", "user.name", "A Tester"])
		try commit("a.txt", message: "first", in: work)
		git(["init", "-q", "--bare", remote.path])
		git(["remote", "add", "origin", remote.path])
		git(["push", "-qu", "origin", "main"])

		git(["clone", "-q", remote.path, other.path])
		git(["config", "user.email", "other@example.com"], in: other)
		git(["config", "user.name", "An Other"], in: other)

		return (work, remote, other)
	}

	private func removeAll(_ roots: URL...) {
		for root in roots { try? FileManager.default.removeItem(at: root) }
	}

	private func head(of root: URL) -> String {
		GitRepository.runSync(["rev-parse", "HEAD"], in: root).stdout
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Puts one commit on the remote that `work` does not have, and fetches so
	/// `origin/main` knows about it. Returns that commit's hash.
	private func putRemoteAhead(work: URL, other: URL, message: String = "from elsewhere") throws -> String {
		try "elsewhere\n".write(
			to: other.appendingPathComponent("elsewhere-\(UUID().uuidString).txt"),
			atomically: true, encoding: .utf8
		)
		_ = GitRepository.runSync(["add", "-A"], in: other)
		_ = GitRepository.runSync(["commit", "-qm", message], in: other)
		_ = GitRepository.runSync(["push", "-q", "origin", "main"], in: other)
		_ = GitRepository.runSync(["fetch", "-q", "origin"], in: work)
		return head(of: other)
	}

	@Test func aBehindBranchsScopedLogContainsTheUnpulledCommit() async throws {
		let (work, remote, other) = try makePublishedRepository()
		defer { removeAll(work, remote, other) }
		let unpulled = try putRemoteAhead(work: work, other: other)

		let remoteOnly = await GitHistory.remoteOnly(of: "main", in: work)
		#expect(remoteOnly.upstream == "origin/main")
		#expect(remoteOnly.hashes == [unpulled])

		let union = await GitHistory.log(
			in: work, revision: "main", upstream: remoteOnly.upstream
		)
		#expect(union.map(\.subject) == ["from elsewhere", "first"])
	}

	@Test func aBranchWithNoUpstreamListsOnlyItsOwnAncestry() async throws {
		let (work, remote, other) = try makePublishedRepository()
		defer { removeAll(work, remote, other) }
		_ = try putRemoteAhead(work: work, other: other)
		_ = GitRepository.runSync(["checkout", "-qb", "private"], in: work)

		let remoteOnly = await GitHistory.remoteOnly(of: "private", in: work)
		#expect(remoteOnly == .none)

		let log = await GitHistory.log(
			in: work, revision: "private", upstream: remoteOnly.upstream
		)
		#expect(log.map(\.subject) == ["first"])
	}

	@Test func aDivergedPairReportsExactlyTheUpstreamOnlyHashes() async throws {
		let (work, remote, other) = try makePublishedRepository()
		defer { removeAll(work, remote, other) }
		let unpulled = try putRemoteAhead(work: work, other: other)

		try "mine\n".write(
			to: work.appendingPathComponent("mine.txt"), atomically: true, encoding: .utf8
		)
		_ = GitRepository.runSync(["add", "-A"], in: work)
		_ = GitRepository.runSync(["commit", "-qm", "mine"], in: work)

		let remoteOnly = await GitHistory.remoteOnly(of: "main", in: work)
		#expect(remoteOnly.hashes == [unpulled])
		#expect(!remoteOnly.hashes.contains(head(of: work)))

		let union = await GitHistory.log(
			in: work, revision: "main", upstream: remoteOnly.upstream
		)
		#expect(Set(union.map(\.subject)) == ["mine", "from elsewhere", "first"])
	}

	@Test func theUnionWindowStillPagesWithSkipAndLimit() async throws {
		let (work, remote, other) = try makePublishedRepository()
		defer { removeAll(work, remote, other) }
		_ = try putRemoteAhead(work: work, other: other)

		let firstPage = await GitHistory.log(
			in: work, revision: "main", upstream: "origin/main", skip: 0, limit: 1
		)
		let secondPage = await GitHistory.log(
			in: work, revision: "main", upstream: "origin/main", skip: 1, limit: 1
		)
		#expect(firstPage.map(\.subject) == ["from elsewhere"])
		#expect(secondPage.map(\.subject) == ["first"])
	}

	/// `%(upstream:short)` still names an upstream whose ref was deleted, and
	/// passing that name on to `git log` would fail the whole command and
	/// blank the page — so a gone upstream must come back as no upstream.
	@Test func aGoneUpstreamIsTreatedAsNoUpstream() async throws {
		let (work, remote, other) = try makePublishedRepository()
		defer { removeAll(work, remote, other) }
		_ = GitRepository.runSync(["config", "branch.main.merge", "refs/heads/gone"], in: work)

		let remoteOnly = await GitHistory.remoteOnly(of: "main", in: work)
		#expect(remoteOnly == .none)
	}
}

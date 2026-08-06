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

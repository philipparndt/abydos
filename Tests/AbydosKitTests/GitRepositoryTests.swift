import Foundation
import Testing
@testable import AbydosKit

/// Where the repository thinks it is.
struct GitRepositoryRootTests {
	/// A repository under a symlinked directory — which `/tmp` and the
	/// system's temporary directory both are — must report the path the rest
	/// of the app spells it with, or nothing in it matches its own status.
	@Test func reportsTheSameRootTheProjectDoes() async throws {
		let root = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("repo-root-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		_ = GitRepository.runSync(["init", "-q", "."], in: root)

		let repository = await GitRepository.discover(from: root)
		let discovered = repository?.root
		#expect(discovered?.path == root.standardizedFileURL.path)
	}
}

/// Which branch the work tree is on, in each of the three states HEAD has.
struct GitHeadTests {
	/// `git init` and nothing else: `main` is what HEAD points at and there is
	/// no commit for it to point to.
	private func makeEmptyRepository() throws -> URL {
		let root = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("head-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = GitRepository.runSync(["init", "-q", "-b", "main", "."], in: root)
		_ = GitRepository.runSync(["config", "user.email", "t@example.com"], in: root)
		_ = GitRepository.runSync(["config", "user.name", "A Tester"], in: root)
		return root
	}

	private func commit(in root: URL) throws {
		try "one\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		_ = GitRepository.runSync(["add", "-A"], in: root)
		_ = GitRepository.runSync(["commit", "-qm", "first"], in: root)
	}

	/// The report of item 0477: a repository nothing has been committed to
	/// showed no branch at all in the titlebar.
	@Test func namesABranchWithNothingCommittedOnIt() async throws {
		let root = try makeEmptyRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let head = await GitRepository.head(in: root)
		#expect(head == .unborn("main"))
		#expect(head.name == "main")
		#expect(head.isUnborn)
	}

	/// Why the question had to change, kept as a fact rather than as a comment:
	/// `rev-parse --abbrev-ref HEAD` resolves the commit and only then names it,
	/// so in this repository it fails outright — and it is the obvious thing for
	/// somebody to put back.
	@Test func revParseStillCannotAnswerInAnEmptyRepository() throws {
		let root = try makeEmptyRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let result = GitRepository.runSync(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
		#expect(result.exitCode != 0)
	}

	@Test func namesAnOrdinaryBranch() async throws {
		let root = try makeEmptyRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try commit(in: root)

		let head = await GitRepository.head(in: root)
		#expect(head == .branch("main"))
		#expect(!head.isUnborn)
	}

	/// The state the old question answered with the literal string `HEAD`, which
	/// every caller separately turned into nil. `symbolic-ref` fails here
	/// instead, so a naive swap would have changed how this reads.
	@Test func aDetachedHeadIsNotABranch() async throws {
		let root = try makeEmptyRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try commit(in: root)
		#expect(GitRepository.runSync(["checkout", "-q", "--detach"], in: root).exitCode == 0)

		let head = await GitRepository.head(in: root)
		#expect(head.isDetached)
		#expect(head.name == nil)
		#expect(!head.isUnborn)
		// It carries the commit it is on, and `display` is what the titlebar
		// draws: a pill that says nothing is the bug this answers.
		#expect(head.display?.hasPrefix("detached at ") == true, "\(head.display ?? "nothing")")
	}

	/// A directory that is not a work tree reads as no branch, which is the same
	/// nothing the titlebar showed for it before.
	@Test func aDirectoryOutsideAnyRepositoryHasNoBranch() async throws {
		let root = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("not-a-repo-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await GitRepository.head(in: root).name == nil)
	}

	/// The cache the titlebar actually reads, filled by the same refresh that
	/// reads the working copy.
	@Test func aRefreshFillsTheBranchInAnEmptyRepository() async throws {
		let root = try makeEmptyRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try "untracked\n".write(
			to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8
		)

		let repository = GitRepository(root: root)
		await repository.refresh()
		#expect(await repository.currentBranch() == "main")
		#expect(await repository.currentHead() == .unborn("main"))
		// The status half worked all along, and still does.
		#expect(await repository.status(forRelativePath: "new.txt", isDirectory: false) == .unversioned)
	}
}

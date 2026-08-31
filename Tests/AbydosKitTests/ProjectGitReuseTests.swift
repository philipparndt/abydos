import Testing
import Foundation
@testable import AbydosKit

/// Whether a project keeps its repository across the reloads the watcher makes.
///
/// It did not: every `.git` event handed back a brand-new `GitRepository`, and
/// the ignore-rules fingerprint went with it — so the walk the fingerprint
/// exists to prevent (`git status --ignored`, the one the code itself calls
/// expensive) ran after every stage, paid for an index write of this app's own
/// making. 0.8–1.6 s per stage in the repository that reported it.
@MainActor
struct ProjectGitReuseTests {
	private func makeRepository() async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-git-reuse-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = await GitRepository.run(["init", "-q", "-b", "main"], in: root)
		_ = await GitRepository.run(["config", "user.email", "t@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "T"], in: root)
		try "build/\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		try "one\n".write(
			to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "first"], in: root)
		return root
	}

	/// A stage-like write to the index, which is what the watcher reports and
	/// what must not cost a rediscovery.
	private func writeToIndex(in root: URL) async throws {
		try "two\n".write(
			to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: root)
	}

	@Test func aReloadOverTheSameCheckoutKeepsTheRepository() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let project = Project(root: root)
		await project.loadGit()
		let first = try #require(project.git)

		try await writeToIndex(in: root)
		await project.loadGit()
		#expect(project.git === first)
	}

	@Test func theIgnoreFingerprintSurvivesTheReload() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let project = Project(root: root)
		await project.loadGit()
		let repo = try #require(project.git)
		await repo.refreshIgnored()
		#expect(await repo.needsIgnoredRefresh() == false)

		try await writeToIndex(in: root)
		await project.loadGit()
		#expect(project.git === repo)
		#expect(await repo.needsIgnoredRefresh() == false,
			"an index write is not an ignore-rules change")
	}

	@Test func anEditedIgnoreFileStillAsksForTheWalk() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let project = Project(root: root)
		await project.loadGit()
		let repo = try #require(project.git)
		await repo.refreshIgnored()
		#expect(await repo.needsIgnoredRefresh() == false)

		try "build/\n*.log\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		await project.loadGit()
		#expect(await repo.needsIgnoredRefresh() == true,
			"a changed rule is exactly what the walk is for")
	}

	/// The one case rediscovery is for: the checkout is not there any more.
	@Test func aCheckoutThatVanishedIsNotKept() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }

		let project = Project(root: root)
		await project.loadGit()
		#expect(project.git != nil)

		try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
		await project.loadGit()
		#expect(project.git == nil)
	}
}

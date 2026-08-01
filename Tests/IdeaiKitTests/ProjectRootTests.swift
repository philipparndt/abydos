import Foundation
import Testing
@testable import IdeaiKit

/// Deciding which project a directory belongs to.
struct ProjectRootTests {
	private func makeTree() -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("roots-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	private func directory(_ url: URL) {
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	}

	private func gitDirectory(at url: URL) {
		directory(url.appendingPathComponent(".git"))
	}

	private func gitFile(at url: URL, pointingTo target: String) {
		directory(url)
		try? "gitdir: \(target)\n".write(
			to: url.appendingPathComponent(".git"), atomically: true, encoding: .utf8
		)
	}

	@Test func aRepositoryIsItsOwnProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		directory(repo.appendingPathComponent("src/deep"))
		gitDirectory(at: repo)

		#expect(ProjectRoot.find(from: repo)?.path == repo.path)
		#expect(ProjectRoot.find(from: repo.appendingPathComponent("src/deep"))?.path == repo.path)
	}

	@Test func aDirectoryOutsideAnyRepositoryHasNoProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let loose = base.appendingPathComponent("loose/deeper")
		directory(loose)
		#expect(ProjectRoot.find(from: loose) == nil)
	}

	/// The point of the rule: you step into a submodule to change something
	/// about the project you were already in.
	@Test func aSubmoduleBelongsToTheRepositoryAroundIt() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let sub = repo.appendingPathComponent("vendor/thing")
		gitFile(at: sub, pointingTo: "../../.git/modules/vendor/thing")
		directory(sub.appendingPathComponent("src"))

		#expect(ProjectRoot.find(from: sub)?.path == repo.path)
		#expect(ProjectRoot.find(from: sub.appendingPathComponent("src"))?.path == repo.path)
	}

	@Test func aSubmoduleInsideASubmoduleStillBelongsToTheOutermost() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let outer = repo.appendingPathComponent("a")
		gitFile(at: outer, pointingTo: "../.git/modules/a")
		let inner = outer.appendingPathComponent("b")
		gitFile(at: inner, pointingTo: "../../.git/modules/a/modules/b")

		#expect(ProjectRoot.find(from: inner)?.path == repo.path)
	}

	/// A linked worktree is somewhere you work, not part of what contains it.
	@Test func aWorktreeIsItsOwnProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let worktree = base.appendingPathComponent("feature-branch")
		gitFile(at: worktree, pointingTo: "/somewhere/main/.git/worktrees/feature-branch")
		directory(worktree.appendingPathComponent("src"))

		#expect(ProjectRoot.find(from: worktree)?.path == worktree.path)
		#expect(ProjectRoot.find(from: worktree.appendingPathComponent("src"))?.path == worktree.path)
	}

	/// A repository checked out inside another is not a submodule of it.
	@Test func aNestedRepositoryIsTheNearestOne() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let outer = base.appendingPathComponent("outer")
		gitDirectory(at: outer)
		let inner = outer.appendingPathComponent("vendor/other")
		directory(inner)
		gitDirectory(at: inner)

		#expect(ProjectRoot.find(from: inner)?.path == inner.path)
	}

	/// An unreadable or unfamiliar pointer stops where it is rather than
	/// climbing out of the project the user meant.
	@Test func anUnrecognisedPointerStandsAlone() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let odd = repo.appendingPathComponent("odd")
		gitFile(at: odd, pointingTo: "/somewhere/else/entirely")

		#expect(ProjectRoot.find(from: odd)?.path == odd.path)
	}

	@Test func theRootDirectoryDoesNotLoop() {
		#expect(ProjectRoot.find(from: URL(fileURLWithPath: "/")) == nil)
	}
}

import Testing
import Foundation
@testable import AbydosKit

/// Staging while a subproject is open.
///
/// The two halves of git's path handling do not agree, and everything here comes
/// from that one fact:
///
///  - `git status --porcelain` reports paths **from the work tree root**,
///    whatever directory it was run in.
///  - `git add`, `restore`, `reset`, `clean` and `ls-files` resolve a pathspec
///    against the **current directory**.
///
/// So a pane that runs git inside a subproject and hands it the paths status
/// just gave it composes the two, and git looks for `sub/sub/…`:
///
///     warning: could not open directory 'sub/sub/'
///     fatal: pathspec 'sub/' did not match any files
///
/// Staging simply did not work while a subproject was open. `Project.gitRoot` is
/// the answer: the directory git commands belong in is the work tree root, not
/// the scope.
struct SubprojectStagingTests {
	// MARK: - The fact the fix rests on

	/// Worth pinning rather than remembering, because the whole bug is that
	/// these two differ and it is not obvious that they do.
	@Test func statusReportsFromTheRootAndPathspecsResolveFromTheCurrentDirectory() async throws {
		let repository = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: repository) }
		let inside = repository.appendingPathComponent("sub")

		// Asked from the subdirectory, and still answered from the root.
		let status = await GitWorkingCopy.status(in: inside)
		#expect(status.unstaged.map(\.path).contains("sub/deep/tracked.txt"))

		// The same path handed back to `add` from that same subdirectory is the
		// failure this file is about.
		let doubled = await GitRepository.run(
			["add", "-A", "--", "sub/deep/tracked.txt"], in: inside
		)
		#expect(doubled.exitCode != 0)
		#expect(doubled.stderr.contains("did not match any files"))
	}

	// MARK: - What the fix makes work

	/// Run at the work tree root, the path status gave is the path add takes.
	@Test func stagingWorksWhenGitRunsAtTheWorkTreeRoot() async throws {
		let repository = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: repository) }

		let status = await GitWorkingCopy.status(in: repository)
		let path = try #require(status.unstaged.map(\.path).first { $0.hasSuffix("tracked.txt") })

		let staged = await GitWorkingCopy.stage(paths: [path], in: repository)
		#expect(staged.exitCode == 0, "\(staged.stderr)")

		let after = await GitWorkingCopy.status(in: repository)
		#expect(after.staged.map(\.path).contains(path))
	}

	/// And unstaging comes back the same way, which uses `restore --staged` and
	/// `reset` — both pathspec-resolving commands, so both were broken too.
	@Test func unstagingWorksTheSameWay() async throws {
		let repository = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: repository) }

		let path = "sub/deep/tracked.txt"
		#expect(await GitWorkingCopy.stage(paths: [path], in: repository).exitCode == 0)
		#expect(await GitWorkingCopy.status(in: repository).staged.map(\.path).contains(path))

		let unstaged = await GitWorkingCopy.unstage(paths: [path], in: repository)
		#expect(unstaged.exitCode == 0, "\(unstaged.stderr)")
		#expect(!(await GitWorkingCopy.status(in: repository).staged.map(\.path).contains(path)))
	}

	// MARK: - Where the root comes from

	/// A project opened on a subdirectory reports the *repository's* root, not
	/// its own — which is what the panes are handed now.
	@Test func aProjectOpenedOnASubdirectoryKnowsTheRepositoryRoot() async throws {
		let repository = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: repository) }

		let project = Project(root: repository.appendingPathComponent("sub"))
		await project.loadGit()

		let gitRoot = try #require(project.gitRoot)
		#expect(
			FilePath.canonical(gitRoot) == FilePath.canonical(repository),
			"the work tree root, not the directory the project was opened on"
		)
	}

	/// A subproject moves the scope and must not move the git root: it is the
	/// same checkout, and a path from `git status` still starts at its root.
	@Test func openingASubprojectDoesNotMoveTheGitRoot() async throws {
		let repository = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: repository) }

		let project = Project(root: repository)
		project.scope = repository.appendingPathComponent("sub")
		await project.loadGit()

		#expect(project.scopeRoot.lastPathComponent == "sub", "the scope did move")
		#expect(
			FilePath.canonical(try #require(project.gitRoot)) == FilePath.canonical(repository),
			"the git root did not"
		)
	}

	/// Before the repository has been found there is nothing better to fall back
	/// to than the scope, and the property says so by being nil rather than by
	/// guessing.
	@Test func theGitRootIsNilUntilTheRepositoryHasBeenFound() {
		#expect(Project(root: URL(fileURLWithPath: "/nowhere-at-all")).gitRoot == nil)
	}

	// MARK: - Helpers

	/// A repository with one tracked file two directories down, modified, plus an
	/// untracked one beside it — the shape a subproject is opened on.
	private func makeRepository() async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-subproject-\(UUID().uuidString)")
		let deep = root.appendingPathComponent("sub/deep")
		try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

		_ = await GitRepository.run(["init", "-q"], in: root)
		_ = await GitRepository.run(["config", "user.email", "test@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "Test"], in: root)
		try "base\n".write(
			to: deep.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "initial"], in: root)

		// Modified, so it is a change with a path that has to survive the trip.
		try "changed\n".write(
			to: deep.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8
		)
		return root
	}
}

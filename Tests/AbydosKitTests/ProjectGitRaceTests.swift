import Testing
import Foundation
@testable import AbydosKit

/// Loading a project's repository from more than one place at once.
///
/// `loadGit` was `nonisolated async`, so its body ran on the cooperative pool
/// even though every caller was on the main actor — and the repository watcher
/// calls it on *every* change inside `.git`, which during a build or a fetch is
/// many a second. Two of them in it at once wrote `git` and `gitRoot` on the
/// same plain class from two threads, and the second release of the same `URL?`
/// was a segmentation fault:
///
///     EXC_BAD_ACCESS (SIGSEGV)  KERN_INVALID_ADDRESS
///       objc_destructInstance
///       _SwiftURL.__deallocating_deinit
///       outlined assign with take of URL?
///       Project.loadGit()                      Project.swift:56
///
/// It is also what made the branch pill flicker: two loads racing, and the pill
/// drawn from whichever landed last.
///
/// **A test cannot prove a race is gone.** What it can do is run the shape that
/// produced it, many times over, and fail if the answer ever comes out
/// inconsistent — which is what these do. Under the old code this file is a
/// crash; under the new one it is a second of work.
/// **Serialised, and deliberately modest about how many it starts.** Each load
/// spawns git subprocesses, and the first version of this file asked for
/// thirty-two at once — enough, running beside three thousand other tests, to
/// starve *their* `git init` and turn thirty-odd unrelated git tests red. The
/// race needs two concurrent callers to exist; six is already generous.
@Suite(.serialized)
@MainActor
struct ProjectGitRaceTests {
	private func makeRepository() async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-git-race-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = await GitRepository.run(["init", "-q"], in: root)
		_ = await GitRepository.run(["config", "user.email", "test@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "Test"], in: root)
		try "one\n".write(
			to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8
		)
        _ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "initial"], in: root)
		return root
	}

	/// The shape the watcher produces: several loads asked for at once.
	@Test func manyLoadsAtOnceAgreeAndDoNotTearTheProject() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = Project(root: root)

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<6 {
				group.addTask { @MainActor in await project.loadGit() }
			}
			for await _ in group {}
		}

		// `require` rather than `expect` and a force-unwrap three lines down:
		// `#expect` carries on, so "no repository was found at all" would be
		// recorded and then immediately trapped on, ending the whole bundle
		// instead of this test.
		let git = try #require(project.git, "no repository was found at all")
		let gitRoot = try #require(project.gitRoot)
		#expect(FilePath.canonical(gitRoot) == FilePath.canonical(root))
		// The two are written together and must never disagree — a torn write
		// is exactly what the crash was.
		#expect(FilePath.canonical(gitRoot) == FilePath.canonical(git.root))
	}

	/// Repeated rounds, because a race that survives one round may only show on
	/// the third.
	@Test func repeatedRoundsStayConsistent() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = Project(root: root)

		for round in 0..<3 {
			await withTaskGroup(of: Void.self) { group in
				for _ in 0..<4 {
					group.addTask { @MainActor in await project.loadGit() }
				}
				for await _ in group {}
			}
			let gitRoot = try #require(project.gitRoot, "round \(round) lost the root")
			#expect(FilePath.canonical(gitRoot) == FilePath.canonical(root), "round \(round)")
		}
	}

	/// A second caller arriving while the first is out joins it rather than
	/// starting another.
	///
	/// Which is not only about the race. The watcher fires on every filesystem
	/// event inside `.git`, and each load runs `git status` over the whole work
	/// tree — so without this, a build produces one full status per event, for
	/// an answer already on its way.
	@Test func concurrentLoadsAreJoinedRatherThanRepeated() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = Project(root: root)

		// Wall clock only as a ratio, never as a bound: six loads that each did
		// their own work would take about six times one, and joined they take
		// about one. The assertion is the ratio, which is what coalescing means.
		let oneStarted = Date()
		await project.loadGit()
		let one = Date().timeIntervalSince(oneStarted)

		let manyStarted = Date()
		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<6 {
				group.addTask { @MainActor in await project.loadGit() }
			}
			for await _ in group {}
		}
		let many = Date().timeIntervalSince(manyStarted)

		print(String(format: "PERF one load %.1f ms, 6 at once %.1f ms — %@",
			one * 1000, many * 1000, MachineLoad.said))

		guard Stopwatch.maySay("PERF", "joined project loads") else { return }
		#expect(many < one * 4,
		        "6 loads cost \(many)s against \(one)s for one — \(MachineLoad.said)")
	}

	/// A directory that is not a work tree answers, rather than leaving the last
	/// project's repository standing.
	@Test func aDirectoryWithNoRepositoryClearsWhatWasThere() async throws {
		let root = try await makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = Project(root: root)
		await project.loadGit()
		#expect(project.gitRoot != nil)

		let bare = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-no-repo-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: bare) }

		let plain = Project(root: bare)
		await plain.loadGit()
		#expect(plain.git == nil)
		#expect(plain.gitRoot == nil)
	}
}

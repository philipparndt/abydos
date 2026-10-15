import Foundation
import Testing
@testable import AbydosKit

/// Which changes inside `.git` are worth reacting to.
struct RepositoryWatcherTests {
	/// Refs, HEAD and the index are what the views are showing.
	@Test func reactsToRefsAndHead() {
		#expect(RepositoryWatcher.matters(directory: URL(fileURLWithPath: "/p/.git")))
		#expect(RepositoryWatcher.matters(directory: URL(fileURLWithPath: "/p/.git/refs/heads")))
		#expect(RepositoryWatcher.matters(directory: URL(fileURLWithPath: "/p/.git/refs/remotes/origin")))
	}

	/// A fetch writes thousands of loose objects and none of them says what any
	/// branch points at.
	@Test func ignoresObjectStorage() {
		#expect(!RepositoryWatcher.matters(directory: URL(fileURLWithPath: "/p/.git/objects/ab")))
		#expect(!RepositoryWatcher.matters(directory: URL(fileURLWithPath: "/p/.git/objects/pack")))
		#expect(!RepositoryWatcher.matters(directory: URL(fileURLWithPath: "/p/.git/lfs/objects")))
	}

	/// The git directory of a plain work tree is the `.git` beside it, which is
	/// what there is to watch.
	@Test func findsTheGitDirectory() async throws {
		let root = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("watch-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		_ = GitRepository.runSync(["init", "-q", "."], in: root)

		let directory = await RepositoryWatcher.directory(forRepositoryAt: root)
		#expect(directory?.path == root.standardizedFileURL.appendingPathComponent(".git").path)
	}

	@Test func hasNoGitDirectoryOutsideARepository() async throws {
		let root = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("nowatch-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await RepositoryWatcher.directory(forRepositoryAt: root) == nil)
	}

	/// A burst waits for quiet, but a burst that never goes quiet still
	/// delivers: a worktree added and removed in a loop held every refresh
	/// back for as long as the loop ran.
	@Test func waitsForQuietButNotPastTheCap() {
		let start = Date(timeIntervalSinceReferenceDate: 0)
		func delay(at seconds: TimeInterval) -> TimeInterval {
			RepositoryWatcher.delay(
				now: start.addingTimeInterval(seconds), firstWaiting: start, settle: 0.4, cap: 3
			)
		}
		#expect(delay(at: 0) == 0.4)
		#expect(delay(at: 2) == 0.4)
		#expect(abs(delay(at: 2.8) - 0.2) < 0.0001)
		#expect(delay(at: 5) == 0)
	}
}

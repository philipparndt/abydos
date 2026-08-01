import Foundation
import Testing
@testable import IdeaiKit

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
		let discovered = await repository?.root
		#expect(discovered?.path == root.standardizedFileURL.path)
	}
}

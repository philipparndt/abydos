import Foundation

/// Where the examples repository is, when it is beside this one.
///
/// 0424 makes the examples the fixtures for anything that cannot be tested by
/// reasoning — a devcontainer either comes up with the toolchain its file asked
/// for or it does not — and a test that wants one has to find the repository
/// first. It is a separate checkout, so every test using it skips cleanly when
/// it is not there.
enum ExampleProjects {
	/// `../abydos-examples`, found from this file rather than from the working
	/// directory, which a test runner is entitled to choose for itself.
	static let root: URL? = {
		let source = URL(fileURLWithPath: #filePath)
		let repository = source
			.deletingLastPathComponent() // AbydosKitTests
			.deletingLastPathComponent() // Tests
			.deletingLastPathComponent() // the checkout
		// A worktree lives under .claude/worktrees/<name>, so the sibling is
		// three more levels up. Whichever of the two exists is the answer.
		let candidates = [
			repository.deletingLastPathComponent(),
			repository
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent(),
		]
		for beside in candidates {
			let url = beside.appendingPathComponent("abydos-examples")
			var isDirectory: ObjCBool = false
			if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
			   isDirectory.boolValue,
			   FileManager.default.fileExists(atPath: url.appendingPathComponent("devcontainers").path)
			{
				return URL(fileURLWithPath: url.resolvingSymlinksInPath().path, isDirectory: true)
			}
		}
		return nil
	}()
}

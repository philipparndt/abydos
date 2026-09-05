import Foundation
import Testing
@testable import AbydosKit

/// What git can see of a file whose values the editor covers.
///
/// Against a real repository per claim rather than a stub: the whole subject is
/// what `git check-ignore` and `git ls-files` say about a path, and a fake that
/// agreed with an assumption about their exit codes would prove the assumption.
struct SecretExposureTests {
	private func repository(_ build: (URL, (_ arguments: [String]) -> Void) throws -> Void) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("exposure-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		func git(_ arguments: [String]) { _ = GitRepository.runSync(arguments, in: root) }
		git(["init", "-q", "-b", "main", "."])
		git(["config", "user.email", "test@example.com"])
		git(["config", "user.name", "Test"])
		try build(root, git)
		return root
	}

	private func write(_ text: String, to url: URL) throws {
		try text.write(to: url, atomically: true, encoding: .utf8)
	}

	@Test func anIgnoredDotenvHasNothingToSay() async throws {
		var file = URL(fileURLWithPath: "/")
		let root = try repository { root, _ in
			file = root.appendingPathComponent(".env")
			try write("API_KEY=sk-abc123\n", to: file)
			try write(".env\n", to: root.appendingPathComponent(".gitignore"))
		}
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await SecretExposure.state(of: file, in: root, conceals: true) == .fine)
	}

	@Test func anUnignoredDotenvSaysGitCanSeeIt() async throws {
		var file = URL(fileURLWithPath: "/")
		let root = try repository { root, _ in
			file = root.appendingPathComponent(".env")
			try write("API_KEY=sk-abc123\n", to: file)
		}
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await SecretExposure.state(of: file, in: root, conceals: true) == .notIgnored)
		#expect(SecretExposure.words(for: .notIgnored) == "Not in .gitignore")
	}

	/// **Tracked beats ignored, because git does.** A `.gitignore` line added
	/// after the commit changes nothing: git goes on tracking what it tracks,
	/// and telling somebody the file is merely "not ignored" would point them
	/// at a fix that does not fix it.
	@Test func aCommittedDotenvIsTrackedEvenOnceItIsIgnored() async throws {
		var file = URL(fileURLWithPath: "/")
		let root = try repository { root, git in
			file = root.appendingPathComponent(".env")
			try write("API_KEY=sk-abc123\n", to: file)
			git(["add", "-A"])
			git(["commit", "-qm", "the mistake"])
			try write(".env\n", to: root.appendingPathComponent(".gitignore"))
		}
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await SecretExposure.state(of: file, in: root, conceals: true) == .tracked)
		#expect(SecretExposure.words(for: .tracked) == "Committed to git")
		#expect(SecretExposure.consequence(for: .tracked)?.contains("history") == true)
	}

	@Test func aFileThatConcealsNothingIsNotAskedAbout() async throws {
		var file = URL(fileURLWithPath: "/")
		let root = try repository { root, _ in
			file = root.appendingPathComponent("README.md")
			try write("# notes\n", to: file)
		}
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(await SecretExposure.state(of: file, in: root, conceals: false) == .fine)
		#expect(SecretExposure.words(for: .fine) == nil)
	}

	/// A folder that is not a repository answers 128, and the bar says nothing:
	/// a notice nobody can act on is worse than no notice.
	@Test func outsideARepositoryNothingIsSaid() async throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("exposure-plain-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent(".env")
		try write("API_KEY=sk-abc123\n", to: file)

		#expect(await SecretExposure.state(of: file, in: root, conceals: true) == .fine)
	}
}

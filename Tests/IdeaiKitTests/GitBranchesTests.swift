import Testing
import Foundation
@testable import IdeaiKit

/// Ref names have more shapes than they look: remotes nest, branch names
/// contain slashes, and origin/HEAD is a symbolic ref rather than a branch.
struct GitRefClassificationTests {
	@Test func localBranchesLoseTheirPrefix() {
		let result = GitBranches.classify(refname: "refs/heads/main")
		#expect(result?.name == "main")
		#expect(result?.kind == .local)
	}

	@Test func branchNamesMayContainSlashes() {
		#expect(GitBranches.classify(refname: "refs/heads/feature/add-thing")?.name == "feature/add-thing")
		let remote = GitBranches.classify(refname: "refs/remotes/origin/feature/add-thing")
		#expect(remote?.name == "feature/add-thing")
		#expect(remote?.kind == .remote("origin"))
	}

	@Test func tagsAreRecognised() {
		#expect(GitBranches.classify(refname: "refs/tags/v1.2.3")?.kind == .tag)
	}

	/// origin/HEAD points at the default branch; listing it would offer a
	/// checkout that duplicates another row.
	@Test func remoteHEADIsNotABranch() {
		#expect(GitBranches.classify(refname: "refs/remotes/origin/HEAD") == nil)
	}

	@Test func unknownRefNamespacesAreIgnored() {
		#expect(GitBranches.classify(refname: "refs/stash") == nil)
		#expect(GitBranches.classify(refname: "refs/notes/commits") == nil)
	}

	@Test func checkoutNameKeepsTheRemotePrefix() {
		let branch = GitBranch(name: "topic", kind: .remote("upstream"))
		#expect(branch.checkoutName == "upstream/topic")
		#expect(GitBranch(name: "topic", kind: .local).checkoutName == "topic")
	}
}

struct GitTrackingParseTests {
	@Test func readsAheadAndBehind() {
		#expect(GitBranches.parseTracking("[ahead 2, behind 1]").ahead == 2)
		#expect(GitBranches.parseTracking("[ahead 2, behind 1]").behind == 1)
	}

	@Test func readsOneSidedTracking() {
		#expect(GitBranches.parseTracking("[ahead 3]") == (3, 0))
		#expect(GitBranches.parseTracking("[behind 4]") == (0, 4))
	}

	@Test func noUpstreamIsZero() {
		#expect(GitBranches.parseTracking("") == (0, 0))
		#expect(GitBranches.parseTracking("[gone]") == (0, 0))
	}
}

struct GitBranchNameValidationTests {
    /// Checked before running git so the failure is a sentence rather than
    /// git's message about ref formats.
	@Test func acceptsOrdinaryNames() {
		#expect(GitBranches.validationError(forName: "feature/add-thing") == nil)
		#expect(GitBranches.validationError(forName: "fix-123") == nil)
	}

	@Test func rejectsWhatGitWouldReject() {
		#expect(GitBranches.validationError(forName: "") != nil)
		#expect(GitBranches.validationError(forName: "  ") != nil)
		#expect(GitBranches.validationError(forName: "-dash") != nil)
		#expect(GitBranches.validationError(forName: "/leading") != nil)
		#expect(GitBranches.validationError(forName: "trailing/") != nil)
		#expect(GitBranches.validationError(forName: "two..dots") != nil)
		#expect(GitBranches.validationError(forName: "two//slashes") != nil)
		#expect(GitBranches.validationError(forName: "ends.lock") != nil)
		#expect(GitBranches.validationError(forName: "has space") != nil)
		#expect(GitBranches.validationError(forName: "has:colon") != nil)
		#expect(GitBranches.validationError(forName: "star*") != nil)
	}
}

/// Against a real repository, since listing and checkout are what the view does.
struct GitBranchIntegrationTests {
	private func makeRepository() async throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-branches-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		_ = await GitRepository.run(["init", "-q", "-b", "main"], in: root)
		_ = await GitRepository.run(["config", "user.email", "t@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "T"], in: root)
		try "one\n".write(to: root.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "first commit"], in: root)
		return root
	}

	@Test func listsLocalBranchesAndMarksTheCurrentOne() async throws {
		let root = try await makeRepository()
		await GitBranches.create("side", from: nil, checkout: false, in: root)

		let branches = await GitBranches.list(in: root)
		let locals = branches.filter { $0.kind == .local }
		#expect(Set(locals.map(\.name)) == ["main", "side"])
		#expect(locals.first { $0.isCurrent }?.name == "main")
	}

	@Test func carriesTheCommitSubject() async throws {
		let root = try await makeRepository()
		let branches = await GitBranches.list(in: root)
		#expect(branches.first { $0.name == "main" }?.subject == "first commit")
	}

	@Test func checkoutSwitchesTheCurrentBranch() async throws {
		let root = try await makeRepository()
		await GitBranches.create("side", from: nil, checkout: false, in: root)

		let side = await GitBranches.list(in: root).first { $0.name == "side" }
		let result = await GitBranches.checkout(side!, in: root)
		#expect(result.exitCode == 0, "\(result.stderr)")

		let after = await GitBranches.list(in: root)
		#expect(after.first { $0.isCurrent }?.name == "side")
	}

	@Test func createCanBranchAndSwitchInOneStep() async throws {
		let root = try await makeRepository()
		let result = await GitBranches.create("fresh", from: nil, checkout: true, in: root)
		#expect(result.exitCode == 0, "\(result.stderr)")
		#expect(await GitBranches.list(in: root).first { $0.isCurrent }?.name == "fresh")
	}

	@Test func deleteRemovesABranch() async throws {
		let root = try await makeRepository()
		await GitBranches.create("temp", from: nil, checkout: false, in: root)
		await GitBranches.delete("temp", force: false, in: root)
		#expect(!(await GitBranches.list(in: root).contains { $0.name == "temp" }))
	}

	@Test func tagsAreListed() async throws {
		let root = try await makeRepository()
		_ = await GitRepository.run(["tag", "v0.1.0"], in: root)
		#expect(await GitBranches.list(in: root).contains { $0.kind == .tag && $0.name == "v0.1.0" })
	}
}

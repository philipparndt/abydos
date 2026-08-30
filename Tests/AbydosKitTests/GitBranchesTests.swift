import Testing
import Foundation
@testable import AbydosKit

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

		// **`require`, not `!`.** A `git` that failed to spawn under load makes
		// `list` answer with nothing, `first` answer nil, and the force-unwrap
		// end the *process* — which is the whole bundle, not this test, so one
		// flake is reported as every suite still running failing at once.
		let side = try #require(
			await GitBranches.list(in: root).first { $0.name == "side" },
			"git listed no branch called side"
		)
		let result = await GitBranches.checkout(side, in: root)
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

	/// Which branches are finished: everything on them is somewhere else.
	@Test func mergedAnswersWhichBranchesAreFinished() async throws {
		let root = try await makeRepository()
		let main = await GitBranches.list(in: root).first { $0.isCurrent }?.name ?? "main"

		await GitBranches.create("done-work", from: nil, checkout: true, in: root)
		try "b\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "two"], in: root)
		_ = await GitRepository.run(["checkout", "-q", main], in: root)
		_ = await GitRepository.run(["merge", "-q", "done-work"], in: root)

		await GitBranches.create("still-going", from: nil, checkout: true, in: root)
		try "c\n".write(to: root.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "three"], in: root)
		_ = await GitRepository.run(["checkout", "-q", main], in: root)

		let merged = await GitBranches.merged(into: main, in: root)
		#expect(merged.contains("done-work"))
		#expect(!merged.contains("still-going"))
		// **The branch itself is not in the answer**, though git puts it there:
		// it is trivially merged into itself, and *finished, nothing on it that
		// is not somewhere else* is not a thing to say about the default branch.
		#expect(!merged.contains(main))
	}

	/// A repository with no such branch costs appearance, not correctness.
	@Test func mergedAnswersNothingWhenTheBranchIsNotThere() async throws {
		let root = try await makeRepository()
		#expect(await GitBranches.merged(into: "no-such-branch", in: root).isEmpty)
	}

}

/// The remote half of "is this branch finished", and the one push this app
/// makes that is not somebody publishing their own work.
@Suite(.serialized)
struct GitRemoteBranchTests {
	/// A bare repository with a clone beside it, holding one branch that has
	/// been merged into the remote's default and one that has not.
	private func fixture() async throws -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("remote-branches-\(UUID().uuidString)")
		let origin = base.appendingPathComponent("origin.git")
		let work = base.appendingPathComponent("work")
		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		_ = await GitRepository.run(["init", "-q", "--bare", "-b", "main", origin.path], in: base)
		_ = await GitRepository.run(["clone", "-q", origin.path, work.path], in: base)
		for arguments in [
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			_ = await GitRepository.run(arguments, in: work)
		}
		func write(_ text: String, _ name: String) throws {
			try text.write(to: work.appendingPathComponent(name), atomically: true, encoding: .utf8)
		}
		func commit(_ message: String) async {
			_ = await GitRepository.run(["add", "-A"], in: work)
			_ = await GitRepository.run(["commit", "-qm", message], in: work)
		}

		try write("one\n", "a.txt")
		await commit("first")
		_ = await GitRepository.run(["push", "-q", "origin", "main"], in: work)

		_ = await GitRepository.run(["checkout", "-q", "-b", "finished"], in: work)
		try write("done\n", "b.txt")
		await commit("finished work")
		_ = await GitRepository.run(["push", "-q", "-u", "origin", "finished"], in: work)

		_ = await GitRepository.run(["checkout", "-q", "main"], in: work)
		_ = await GitRepository.run(["merge", "-q", "finished"], in: work)
		_ = await GitRepository.run(["push", "-q", "origin", "main"], in: work)

		_ = await GitRepository.run(["checkout", "-q", "-b", "unfinished"], in: work)
		try write("wip\n", "c.txt")
		await commit("still going")
		_ = await GitRepository.run(["push", "-q", "-u", "origin", "unfinished"], in: work)
		_ = await GitRepository.run(["checkout", "-q", "main"], in: work)
		return work
	}

	/// **`git branch --merged` lists local branches only**, which is why the
	/// pane could mark a finished local branch and say nothing about the remote
	/// copy of the same work.
	@Test func theRemoteBranchesSayWhichAreFinished() async throws {
		let work = try await fixture()
		let finished = await GitBranches.mergedRemotes(into: "origin/main", in: work)
		#expect(finished == ["origin/finished"])

		// The local answer is a different set, about different refs.
		let locally = await GitBranches.merged(into: "main", in: work)
		#expect(locally == ["finished"])
	}

	/// The target it is measured against is the remote's default, not this
	/// machine's: a commit made locally and not pushed moves one and not the
	/// other, and a branch inside the local `main` is not yet inside the one
	/// deleting it would matter to.
	@Test func aLocalMainThatHasMovedOnDoesNotCountAsTheRemotes() async throws {
		let work = try await fixture()
		_ = await GitRepository.run(["checkout", "-q", "-b", "later"], in: work)
		try "later\n".write(
			to: work.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: work)
		_ = await GitRepository.run(["commit", "-qm", "later work"], in: work)
		_ = await GitRepository.run(["push", "-q", "-u", "origin", "later"], in: work)
		// Merged locally and never pushed, so origin/main has not moved.
		_ = await GitRepository.run(["checkout", "-q", "main"], in: work)
		_ = await GitRepository.run(["merge", "-q", "later"], in: work)

		#expect(await GitBranches.merged(into: "main", in: work).contains("later"))
		#expect(!(await GitBranches.mergedRemotes(into: "origin/main", in: work))
			.contains("origin/later"))
	}

	/// `origin/HEAD` is a symbolic ref at the remote's default. It is trivially
	/// inside it and it is not a branch anybody deletes.
	@Test func theRemotesHeadIsNotOfferedAsAFinishedBranch() async throws {
		let work = try await fixture()
		_ = await GitRepository.run(
			["remote", "set-head", "origin", "main"], in: work
		)
		let finished = await GitBranches.mergedRemotes(into: "origin/main", in: work)
		#expect(!finished.contains { $0.hasSuffix("/HEAD") })
	}

	@Test func deletingOnTheRemoteTakesItOffTheRemote() async throws {
		let work = try await fixture()
		let result = await GitBranches.deleteOnRemote("finished", on: "origin", in: work)
		#expect(result.exitCode == 0, "\(result.stderr)")

		// Gone from the remote, and the local branch left alone: they are two
		// refs and the dialog says so.
		_ = await GitRepository.run(["fetch", "--prune", "-q"], in: work)
		let remaining = await GitBranches.mergedRemotes(into: "origin/main", in: work)
		#expect(!remaining.contains("origin/finished"))
		let locally = await GitRepository.run(
			["rev-parse", "--verify", "--quiet", "refs/heads/finished"], in: work
		)
		#expect(locally.exitCode == 0, "the local branch is untouched")
	}

	/// A branch already gone answers in git's words rather than silently.
	@Test func deletingSomethingThatIsNotThereIsRefused() async throws {
		let work = try await fixture()
		let result = await GitBranches.deleteOnRemote("neverExisted", on: "origin", in: work)
		#expect(result.exitCode != 0)
	}

	@Test func theRemotesAreAskedForRatherThanAssumed() async throws {
		let work = try await fixture()
		#expect(await GitBranches.remotes(in: work) == ["origin"])
	}
}

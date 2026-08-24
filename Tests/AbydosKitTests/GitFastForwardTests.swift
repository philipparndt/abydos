import Testing
import Foundation
@testable import AbydosKit

/// Bringing a branch up to its upstream without checking it out.
///
/// The branch somebody wants to advance is usually not the one they are standing
/// on — `main ↓4` while the work happens on a feature branch — and the only way
/// to move it was checkout, pull, checkout back: three operations and a working
/// copy touched twice.
struct GitFastForwardTests {
	/// A clone whose `main` is behind, with `feature` checked out — the shape in
	/// the report.
	private func makeClone(
		aheadOnRemote: Int = 2
	) async throws -> (work: URL, upstream: URL) {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-ff-\(UUID().uuidString)")
		let upstream = base.appendingPathComponent("upstream")
		let work = base.appendingPathComponent("work")
		try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)

		_ = await GitRepository.run(["init", "-q", "-b", "main"], in: upstream)
		try await identify(upstream)
		try "1\n".write(
			to: upstream.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: upstream)
		_ = await GitRepository.run(["commit", "-qm", "one"], in: upstream)

		_ = await GitRepository.run(["clone", "-q", upstream.path, work.path], in: base)
		try await identify(work)
		_ = await GitRepository.run(["checkout", "-q", "-b", "feature"], in: work)

		for step in 0..<aheadOnRemote {
			try "\(step)\n".write(
				to: upstream.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8
			)
			_ = await GitRepository.run(["commit", "-qam", "remote \(step)"], in: upstream)
		}
		_ = await GitRepository.run(["fetch", "-q", "origin"], in: work)
		return (work, upstream)
	}

	private func identify(_ root: URL) async throws {
		_ = await GitRepository.run(["config", "user.email", "test@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "Test"], in: root)
	}

	private func head(of branch: String, in root: URL) async -> String {
		await GitRepository.run(["rev-parse", branch], in: root)
			.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - The case it is for

	@Test func aBranchThatIsNotCheckedOutMovesToItsUpstream() async throws {
		let (work, upstream) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		_ = upstream

		let outcome = await GitFastForward.advance(branch: "main", in: work)

		#expect(outcome == .moved(commits: 2))
		#expect(await head(of: "main", in: work) == (await head(of: "origin/main", in: work)))
	}

	/// The whole point: the working copy and the branch somebody is standing on
	/// are untouched.
	@Test func theCheckedOutBranchAndTheWorkingCopyAreLeftAlone() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		try "mine\n".write(
			to: work.appendingPathComponent("scratch.txt"), atomically: true, encoding: .utf8
		)
		let featureBefore = await head(of: "feature", in: work)

		_ = await GitFastForward.advance(branch: "main", in: work)

		#expect(await GitRepository.head(in: work).name == "feature")
		#expect(await head(of: "feature", in: work) == featureBefore)
		let uncommitted = await GitWorkingCopy.status(in: work)
		#expect(uncommitted.unstaged.contains { $0.path == "scratch.txt" },
		        "the uncommitted file was disturbed")
	}

	// MARK: - When it must refuse

	/// A branch with commits of its own is not a fast-forward, and moving the ref
	/// would leave them reachable from nothing.
	@Test func aDivergedBranchIsRefusedAndKeepsItsCommits() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		// A commit on main that the upstream has never seen.
		_ = await GitRepository.run(["checkout", "-q", "main"], in: work)
		try "local\n".write(
			to: work.appendingPathComponent("local.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: work)
		_ = await GitRepository.run(["commit", "-qm", "local only"], in: work)
		_ = await GitRepository.run(["checkout", "-q", "feature"], in: work)
		let before = await head(of: "main", in: work)

		let outcome = await GitFastForward.advance(branch: "main", in: work)

		#expect(outcome == .diverged(ahead: 1))
		#expect(await head(of: "main", in: work) == before, "the branch moved anyway")
	}

	/// What git actually does when it rejects a ref update, pinned because the
	/// guard above was written from a wrong reading of it.
	///
	/// It exits non-zero and says so in prose:
	///
	///     ! [rejected] origin/main -> main  (non-fast-forward)
	///
	/// The exit code is therefore usable, and the ancestry check above is not
	/// there because it lies — it is there because a rejection leaves nothing
	/// but that sentence, and `.diverged(ahead: 1)` is an answer a caller can
	/// use without parsing anybody's wording.
	@Test func gitFetchRefusesANonFastForwardAndSaysSoInItsExitCode() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		_ = await GitRepository.run(["checkout", "-q", "main"], in: work)
		try "local\n".write(
			to: work.appendingPathComponent("local.txt"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: work)
		_ = await GitRepository.run(["commit", "-qm", "local only"], in: work)
		_ = await GitRepository.run(["checkout", "-q", "feature"], in: work)

		let result = await GitRepository.run(
			["fetch", ".", "origin/main:refs/heads/main"], in: work
		)

		#expect(result.exitCode != 0)
		#expect(result.stderr.contains("rejected"))
		// And the branch is where it was — the refusal is real, not cosmetic.
		#expect(await head(of: "main", in: work) != (await head(of: "origin/main", in: work)))
	}

	@Test func theBranchThatIsCheckedOutIsAPullInstead() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		_ = await GitRepository.run(["checkout", "-q", "main"], in: work)

		#expect(await GitFastForward.advance(branch: "main", in: work) == .checkedOut)
	}

	@Test func aBranchWithNoUpstreamSaysSo() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		_ = await GitRepository.run(["branch", "orphan"], in: work)

		#expect(await GitFastForward.advance(branch: "orphan", in: work) == .noUpstream)
	}

	@Test func aBranchAlreadyAtItsUpstreamSaysSo() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		_ = await GitFastForward.advance(branch: "main", in: work)

		#expect(await GitFastForward.advance(branch: "main", in: work) == .alreadyThere)
	}

	@Test func aBranchThatDoesNotExistIsRefusedRatherThanCreated() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }

		let outcome = await GitFastForward.advance(
			branch: "no-such-branch", to: "origin/main", in: work
		)

		guard case .refused = outcome else {
			Issue.record("expected a refusal, got \(outcome)")
			return
		}
		let exists = await GitRepository.run(
			["rev-parse", "--verify", "--quiet", "refs/heads/no-such-branch"], in: work
		)
		#expect(exists.exitCode != 0, "a branch was created by a fast-forward")
	}

	/// A branch tracking something other than `origin/<same name>` is found
	/// through `@{upstream}` rather than by guessing the name.
	@Test func theUpstreamIsWhicheverOneTheBranchTracks() async throws {
		let (work, _) = try await makeClone()
		defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
		// A second local branch pointed at the same place, tracking origin/main.
		_ = await GitRepository.run(["branch", "release", "main"], in: work)
		_ = await GitRepository.run(
			["branch", "--set-upstream-to=origin/main", "release"], in: work
		)

		#expect(await GitFastForward.advance(branch: "release", in: work) == .moved(commits: 2))
		#expect(await head(of: "release", in: work) == (await head(of: "origin/main", in: work)))
	}
}

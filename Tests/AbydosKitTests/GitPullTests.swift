import Foundation
import Testing
@testable import AbydosKit

/// Bringing work down, and the reading behind the dialog in front of it.
///
/// Against two real repositories, because every claim here is about what git
/// does: that `--rebase` replays rather than merges, that `--autostash` gets a
/// dirty tree out of the way and puts it back, and that the repository's own
/// `pull.rebase` outranks anything this app would prefer.
struct GitPullTests {
	@discardableResult
	private func git(_ arguments: [String], in directory: URL) -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git"] + arguments
		process.currentDirectoryURL = directory
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try? process.run()
		process.waitUntilExit()
		return process.terminationStatus
	}

	private func write(_ text: String, _ name: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	/// A bare repository, a clone of it, and a second clone that pushes into it
	/// — so the first clone has something real to pull.
	private func pair() throws -> (mine: URL, theirs: URL, bare: URL) {
		let base = FileManager.default.temporaryDirectory
			.appendingPathComponent("pull-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

		let bare = base.appendingPathComponent("origin.git")
		try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
		#expect(git(["init", "-q", "--bare", "-b", "main", "."], in: bare) == 0)

		func clone(_ name: String) throws -> URL {
			let at = base.appendingPathComponent(name)
			#expect(git(["clone", "-q", bare.path, at.path], in: base) == 0)
			#expect(git(["config", "user.email", "t@example.com"], in: at) == 0)
			#expect(git(["config", "user.name", "T"], in: at) == 0)
			return at
		}

		let seed = try clone("seed")
		try write("one\n", "a.txt", in: seed)
		#expect(git(["add", "."], in: seed) == 0)
		#expect(git(["commit", "-qm", "first"], in: seed) == 0)
		#expect(git(["push", "-q", "origin", "main"], in: seed) == 0)

		let mine = try clone("mine")
		let theirs = try clone("theirs")
		return (mine, theirs, bare)
	}

	private func remove(_ url: URL) {
		try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
	}

	private func subjects(in root: URL) async -> [String] {
		let result = await GitRepository.run(["log", "--format=%s"], in: root)
		return result.stdout.split(separator: "\n").map(String.init)
	}

	@Test func fetchingBringsTheRefsDownAndLeavesTheTreeAlone() async throws {
		let (mine, theirs, _) = try pair()
		defer { remove(mine) }

		try write("two\n", "b.txt", in: theirs)
		#expect(git(["add", "."], in: theirs) == 0)
		#expect(git(["commit", "-qm", "second"], in: theirs) == 0)
		#expect(git(["push", "-q", "origin", "main"], in: theirs) == 0)

		#expect(await GitPull.fetch(in: mine).exitCode == 0)

		// The ref moved; the working copy did not.
		let remote = await GitRepository.run(["log", "--format=%s", "origin/main"], in: mine)
		#expect(remote.stdout.contains("second"))
		#expect(!FileManager.default.fileExists(atPath: mine.appendingPathComponent("b.txt").path))
	}

	@Test func pullingWithRebaseReplaysYourCommitOnTop() async throws {
		let (mine, theirs, _) = try pair()
		defer { remove(mine) }

		try write("theirs\n", "b.txt", in: theirs)
		#expect(git(["add", "."], in: theirs) == 0)
		#expect(git(["commit", "-qm", "theirs"], in: theirs) == 0)
		#expect(git(["push", "-q", "origin", "main"], in: theirs) == 0)

		try write("mine\n", "c.txt", in: mine)
		#expect(git(["add", "."], in: mine) == 0)
		#expect(git(["commit", "-qm", "mine"], in: mine) == 0)

		#expect(await GitPull.pull(in: mine, rebasing: true, stashing: false).exitCode == 0)

		// A straight line: mine on top of theirs, and no merge commit at all.
		#expect(await subjects(in: mine) == ["mine", "theirs", "first"])
	}

	@Test func pullingWithoutRebaseMakesAMergeCommit() async throws {
		let (mine, theirs, _) = try pair()
		defer { remove(mine) }

		try write("theirs\n", "b.txt", in: theirs)
		#expect(git(["add", "."], in: theirs) == 0)
		#expect(git(["commit", "-qm", "theirs"], in: theirs) == 0)
		#expect(git(["push", "-q", "origin", "main"], in: theirs) == 0)

		try write("mine\n", "c.txt", in: mine)
		#expect(git(["add", "."], in: mine) == 0)
		#expect(git(["commit", "-qm", "mine"], in: mine) == 0)

		#expect(await GitPull.pull(in: mine, rebasing: false, stashing: false).exitCode == 0)

		let parents = await GitRepository.run(["log", "-1", "--format=%p"], in: mine)
		let count = parents.stdout.split(separator: " ").count
		#expect(count == 2, "a merge commit has two parents")
	}

	/// The checkbox somebody ticks because otherwise the pull stops and tells
	/// them to deal with their working copy first.
	@Test func stashingGetsADirtyTreeOutOfTheWayAndPutsItBack() async throws {
		let (mine, theirs, _) = try pair()
		defer { remove(mine) }

		try write("theirs\n", "b.txt", in: theirs)
		#expect(git(["add", "."], in: theirs) == 0)
		#expect(git(["commit", "-qm", "theirs"], in: theirs) == 0)
		#expect(git(["push", "-q", "origin", "main"], in: theirs) == 0)

		try write("still working on this\n", "a.txt", in: mine)

		#expect(await GitPull.pull(in: mine, rebasing: true, stashing: true).exitCode == 0)

		// Brought down, and the work in hand is where it was left.
		#expect(await subjects(in: mine).contains("theirs"))
		let onDisk = try String(contentsOf: mine.appendingPathComponent("a.txt"), encoding: .utf8)
		#expect(onDisk == "still working on this\n")
		#expect(await GitStash.list(in: mine).isEmpty, "autostash puts its own entry back")
	}

	/// And what happens without it, which is the sentence the checkbox is
	/// there to save somebody from reading.
	@Test func aDirtyTreeWithoutStashingIsReportedAsBeingInTheWay() async throws {
		let (mine, theirs, _) = try pair()
		defer { remove(mine) }

		try write("theirs\n", "a.txt", in: theirs)
		#expect(git(["commit", "-qam", "theirs"], in: theirs) == 0)
		#expect(git(["push", "-q", "origin", "main"], in: theirs) == 0)

		try write("mine, uncommitted\n", "a.txt", in: mine)

		let result = await GitPull.pull(in: mine, rebasing: true, stashing: false)
		#expect(result.exitCode != 0)
		#expect(GitPull.refusal(from: result) == .workingCopyInTheWay)
	}

	@Test func theRepositorySettingOutranksTheApp() async throws {
		let (mine, _, _) = try pair()
		defer { remove(mine) }

		#expect(git(["config", "pull.rebase", "false"], in: mine) == 0)

		let preference = await GitPull.preference(in: mine, appDefault: .rebase)
		#expect(preference.reconciliation == .merge)
		#expect(preference.authority == .repository)
		#expect(preference.attribution != nil, "and it says where that came from")
	}

	@Test func withTheRepositorySilentTheAppDefaultFillsTheGap() async throws {
		let (mine, _, _) = try pair()
		defer { remove(mine) }

		let preference = await GitPull.preference(in: mine, appDefault: .rebase)
		#expect(preference.reconciliation == .rebase)
		#expect(preference.authority == .app)
		#expect(preference.attribution == nil)
	}

	/// A credential failure is otherwise an exit code with nothing beside it,
	/// and a pull that says nothing looks broken rather than unauthenticated.
	@Test func aCredentialFailureIsRecognisedInSeveralSpellings() {
		let spellings = [
			"fatal: could not read Username for 'https://github.com': terminal prompts disabled",
			"git@github.com: Permission denied (publickey).",
			"remote: Authentication failed for 'https://example.com/x.git/'",
		]
		for said in spellings {
			let result = GitRepository.ProcessResult(stdout: "", stderr: said, exitCode: 128)
			#expect(GitPull.refusal(from: result) == .needsCredential, "\(said)")
		}
	}

	@Test func somethingThatWorkedIsNoRefusalAtAll() {
		let result = GitRepository.ProcessResult(stdout: "Already up to date.", stderr: "", exitCode: 0)
		#expect(GitPull.refusal(from: result) == nil)
	}
}

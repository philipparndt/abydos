import Foundation
import Testing
@testable import AbydosKit

/// The conflict a superproject can have and a file cannot.
struct GitGitlinkConflictTests {
	@Test func theThreeStagesOfAConflictedGitlinkAreRead() {
		let output = [
			"160000 e28ed081f908236ad4149bf57576d1003604ea7f 1\tsvc",
			"160000 b2206a7177c1b77643ec0dc6cc60dacde339c37b 2\tsvc",
			"160000 6bef0dbac0958c46a73263081c60b7482f6b6ab7 3\tsvc",
		].joined(separator: "\0") + "\0"

		let conflicts = GitGitlinkConflicts.parse(output)
		#expect(conflicts.count == 1)
		#expect(conflicts[0].path == "svc")
		#expect(conflicts[0].base == "e28ed081f908236ad4149bf57576d1003604ea7f")
		#expect(conflicts[0].ours == "b2206a7177c1b77643ec0dc6cc60dacde339c37b")
		#expect(conflicts[0].theirs == "6bef0dbac0958c46a73263081c60b7482f6b6ab7")
		#expect(conflicts[0].sides.map(\.name) == ["ours", "theirs"])
	}

	/// A text conflict is somebody else's problem and must not be read as this
	/// one: the mode is the whole of the difference.
	@Test func aConflictedFileIsNotAGitlinkConflict() {
		let output = [
			"100644 aaaa 1\tsrc/Main.java",
			"100644 bbbb 2\tsrc/Main.java",
			"100644 cccc 3\tsrc/Main.java",
		].joined(separator: "\0") + "\0"
		#expect(GitGitlinkConflicts.parse(output).isEmpty)
	}

	/// Added on both sides independently: there is no ancestor to point at, and
	/// the two sides are still a choice.
	@Test func aSubmoduleAddedOnBothSidesHasNoBase() {
		let output = [
			"160000 bbbb 2\tsvc",
			"160000 cccc 3\tsvc",
		].joined(separator: "\0") + "\0"
		let conflicts = GitGitlinkConflicts.parse(output)
		#expect(conflicts[0].base == nil)
		#expect(conflicts[0].sides.count == 2)
	}

	@Test func severalConflictedSubmodulesComeBackInTheOrderGitGaveThem() {
		let output = [
			"160000 aaaa 2\tsvc-b", "160000 bbbb 3\tsvc-b",
			"160000 cccc 2\tsvc-a", "160000 dddd 3\tsvc-a",
		].joined(separator: "\0") + "\0"
		#expect(GitGitlinkConflicts.parse(output).map(\.path) == ["svc-b", "svc-a"])
	}

	@Test func nothingUnmergedIsNoConflicts() {
		#expect(GitGitlinkConflicts.parse("").isEmpty)
	}

	// MARK: - Against a real merge

	/// Builds a superproject whose two branches moved one submodule to different
	/// commits, and merges them.
	private func conflicted() throws -> SyntheticEstate {
		let estate = try SyntheticEstate.make(count: 1, named: "gitlinkconflict")
		SyntheticEstate.run(["checkout", "-qb", "theirs"], in: estate.root)
		// Distinct messages, or the two sides make byte-identical empty commits
		// and the merge fast-forwards instead of conflicting. See
		// `SyntheticEstate.advance`.
		estate.advance("svc-1", by: 2, saying: "theirs")
		SyntheticEstate.run(["add", "svc-1"], in: estate.root)
		SyntheticEstate.run(["commit", "-qm", "bump for theirs"], in: estate.root)

		SyntheticEstate.run(["checkout", "-q", "main"], in: estate.root)
		SyntheticEstate.run(["submodule", "update", "-q", "--checkout", "svc-1"], in: estate.root)
		estate.advance("svc-1", by: 1, saying: "ours")
		SyntheticEstate.run(["add", "svc-1"], in: estate.root)
		SyntheticEstate.run(["commit", "-qm", "bump for ours"], in: estate.root)

		_ = SyntheticEstate.run(["merge", "theirs"], in: estate.root)
		return estate
	}

	@Test func aRealMergeLeavesAGitlinkConflictThisCanRead() async throws {
		let estate = try conflicted()
		defer { estate.remove() }

		let conflicts = await GitGitlinkConflicts.conflicts(in: estate.root)
		#expect(conflicts.count == 1)
		#expect(conflicts.first?.path == "svc-1")
		#expect(conflicts.first?.ours != conflicts.first?.theirs)
		#expect(conflicts.first?.base != nil)
	}

	/// A row that said only "conflicted" would leave somebody to run this by
	/// hand before they could choose.
	@Test func theDistanceBetweenTheTwoSidesIsSaidInCommits() async throws {
		let estate = try conflicted()
		defer { estate.remove() }

		guard let conflict = await GitGitlinkConflicts.conflicts(in: estate.root).first else {
			Issue.record("no conflict")
			return
		}
		// Ours advanced by one and theirs by two, from the same ancestor.
		#expect(await GitGitlinkConflicts.distance(of: conflict, in: estate.root)
			== .diverged(ahead: 2, behind: 1))
	}

	@Test func takingASideResolvesTheConflictAndMovesTheSubmodule() async throws {
		let estate = try conflicted()
		defer { estate.remove() }

		guard let conflict = await GitGitlinkConflicts.conflicts(in: estate.root).first,
		      let theirs = conflict.theirs
		else {
			Issue.record("no conflict")
			return
		}

		#expect(await GitGitlinkConflicts.resolve(conflict, to: theirs, in: estate.root)
			.exitCode == 0)

		// Out of the unmerged state...
		#expect(await GitGitlinkConflicts.conflicts(in: estate.root).isEmpty)
		// ...pointing where it was told...
		let staged = await GitSubmodules.gitlinks(in: estate.root)
		#expect(staged.first(where: { $0.path == "svc-1" })?.commit == theirs)
		// ...and the submodule is actually there, rather than left dirty.
		let head = await GitRepository.run(
			["rev-parse", "HEAD"], in: estate.root.appendingPathComponent("svc-1")
		).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		#expect(head == theirs)
	}

	/// Git's own hint says to go into the submodule and merge, then come back.
	/// A commit that is neither side is what that leaves, and it is a resolution.
	@Test func aThirdCommitNeitherSideRecordedIsAlsoAResolution() async throws {
		let estate = try conflicted()
		defer { estate.remove() }

		guard let conflict = await GitGitlinkConflicts.conflicts(in: estate.root).first else {
			Issue.record("no conflict")
			return
		}
		// A merge inside the submodule, which is what git's hint describes.
		let submodule = estate.root.appendingPathComponent("svc-1")
		guard let theirs = conflict.theirs else { return }
		_ = await GitRepository.run(["merge", "-q", "--no-edit", theirs], in: submodule)
		let merged = await GitRepository.run(["rev-parse", "HEAD"], in: submodule)
			.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

		#expect(merged != conflict.ours && merged != conflict.theirs, "a new commit")
		#expect(await GitGitlinkConflicts.resolve(conflict, to: merged, in: estate.root)
			.exitCode == 0)
		#expect(await GitGitlinkConflicts.conflicts(in: estate.root).isEmpty)
	}
}

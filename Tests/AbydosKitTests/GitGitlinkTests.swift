import Foundation
import Testing
@testable import AbydosKit

/// How far a submodule has moved from where the superproject records it.
struct GitGitlinkTests {
	private func submodule(_ path: String = "svc-1") -> GitSubmodule {
		GitSubmodule(path: path, recordedCommit: "aaaaaaa")
	}

	// MARK: - Reading git's answer

	@Test func aheadCountsTheSubmodulesOwnSideAndNamesItsTip() {
		let output = [
			">\u{1f}bbbbbbb\u{1f}the newest",
			">\u{1f}ccccccc\u{1f}the one before",
		].joined(separator: "\n")
		let movement = GitGitlink.parse(output, for: submodule())
		#expect(movement.relation == .ahead(2))
		#expect(movement.subject == "the newest", "git logs newest first, so the tip is first")
		#expect(movement.current == "bbbbbbb", "the tip's hash, not the marker")
		#expect(movement.hasMoved)
	}

	@Test func behindCountsTheSuperprojectsSide() {
		let output = "<\u{1f}bbbbbbb\u{1f}what was recorded"
		#expect(GitGitlink.parse(output, for: submodule()).relation == .behind(1))
	}

	@Test func bothSidesMovingIsDivergence() {
		let output = [
			">\u{1f}bbbbbbb\u{1f}mine",
			"<\u{1f}ccccccc\u{1f}theirs",
			"<\u{1f}ddddddd\u{1f}theirs again",
		].joined(separator: "\n")
		let movement = GitGitlink.parse(output, for: submodule())
		#expect(movement.relation == .diverged(ahead: 1, behind: 2))
	}

	@Test func noCommitsEitherSideIsLevel() {
		let movement = GitGitlink.parse("", for: submodule())
		#expect(movement.relation == .level)
		#expect(!movement.hasMoved)
		#expect(movement.subject == nil)
	}

	/// A subject may contain anything a line can, tabs included, which is why
	/// the fields are separated by the unit separator and not by a tab.
	@Test func aSubjectHoldingTabsIsOneSubject() {
		let output = ">\u{1f}bbbbbbb\u{1f}fix:\tthe thing\twith tabs"
		#expect(GitGitlink.parse(output, for: submodule()).subject
			== "fix:\tthe thing\twith tabs")
	}

	@Test func theCommandIsOnePerRepositoryAndAsksTheRangeBothWays() {
		let arguments = GitGitlink.arguments(recorded: "abc123")
		#expect(arguments.contains("--left-right"))
		#expect(arguments.contains("abc123...HEAD"))
	}

	// MARK: - Against real repositories

	@Test func aSubmoduleAdvancedByTwelveCommitsReadsAsTwelveAhead() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "ahead")
		defer { estate.remove() }
		estate.advance("svc-1", by: 12)

		let read = await GitEstate.read(from: estate.root)
		guard let svc = read.submodule(at: "svc-1") else { Issue.record("no svc-1"); return }
		let movement = await GitGitlink.movement(of: svc, in: estate.root)

		#expect(movement.relation == .ahead(12))
		#expect(movement.subject == "moved 11", "the tip, not the first of the twelve")
		#expect(movement.current?.count == 40)
	}

	@Test func aSubmoduleWhereItIsRecordedIsLevel() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "level")
		defer { estate.remove() }

		let read = await GitEstate.read(from: estate.root)
		guard let svc = read.submodule(at: "svc-1") else { Issue.record("no svc-1"); return }
		#expect(await GitGitlink.movement(of: svc, in: estate.root).relation == .level)
	}

	/// What an estate looks like before somebody fetches. Git refuses the
	/// question rather than answering nought, and the row has to say so: a
	/// `level` about a commit nobody has is the sentence this exists to avoid.
	@Test func aRecordedCommitTheSubmoduleHasNeverFetchedIsSaidToBeMissing() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "notheré")
		defer { estate.remove() }

		let invented = GitSubmodule(
			path: "svc-1",
			recordedCommit: "70e7a598b14c5bcca5cfa1b4a66e2c4004e2b17e"
		)
		let movement = await GitGitlink.movement(of: invented, in: estate.root)
		#expect(movement.relation == .notHere)
		#expect(movement.current == nil)
	}

	/// The clean ones cost nothing: this is asked only of what the superproject
	/// has already said moved.
	@Test func onlyTheSubmodulesAskedAboutAreAsked() async throws {
		let estate = try SyntheticEstate.make(count: 4, named: "onlyasked")
		defer { estate.remove() }
		estate.advance("svc-2", by: 3)

		let read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)
		let moved = status.movedGitlinks(in: read)
		#expect(moved.map(\.path) == ["svc-2"])

		let movements = await GitGitlink.movements(of: moved, in: estate.root)
		#expect(movements.keys.sorted() == ["svc-2"], "the three clean ones are never asked")
		#expect(movements["svc-2"]?.relation == .ahead(3))
	}

	@Test func anAbsentSubmoduleIsNotAsked() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "gitlinkabsent")
		defer { estate.remove() }
		try FileManager.default.removeItem(at: estate.root.appendingPathComponent("svc-2"))

		let read = await GitEstate.read(from: estate.root)
		#expect(await GitGitlink.movements(of: read.submodules, in: estate.root).keys.sorted()
			== ["svc-1"])
	}
}

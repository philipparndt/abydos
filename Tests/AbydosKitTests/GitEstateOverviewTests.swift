import Foundation
import Testing
@testable import AbydosKit

/// The estate as a list somebody can read.
struct GitEstateOverviewTests {
	private let root = URL(fileURLWithPath: "/tmp/super", isDirectory: true)

	private func estate(_ paths: [String], absent: Set<String> = []) -> GitEstate {
		GitEstate(
			root: root,
			submodules: paths.map {
				GitSubmodule(path: $0, recordedCommit: "aaaa", isCheckedOut: !absent.contains($0))
			}
		)
	}

	private func changed(_ count: Int) -> GitWorkingCopyStatus {
		GitWorkingCopyStatus(
			unstaged: (0..<count).map { GitChange(path: "f\($0)", kind: .modified, isStaged: false) }
		)
	}

	// MARK: - The branch header

	@Test func aBranchWithNoUpstream() {
		let branch = GitEstateBranches.parse("## main\0")
		#expect(branch?.branch == "main")
		#expect(branch?.hasUpstream == false)
	}

	@Test func aBranchLevelWithItsUpstream() {
		let branch = GitEstateBranches.parse("## main...origin/main\0")
		#expect(branch?.branch == "main")
		#expect(branch?.upstream == "origin/main")
		#expect(branch?.isLevel == true)
	}

	@Test func aheadAndBehindAreRead() {
		#expect(GitEstateBranches.parse("## main...origin/main [ahead 2]\0")?.ahead == 2)
		let both = GitEstateBranches.parse("## main...origin/main [ahead 1, behind 3]\0")
		#expect(both?.ahead == 1)
		#expect(both?.behind == 3)
	}

	@Test func aDetachedHeadIsNotABranchName() {
		let branch = GitEstateBranches.parse("## HEAD (no branch)\0")
		#expect(branch?.isDetached == true)
		#expect(branch?.branch == nil)
	}

	@Test func aRepositoryWithNothingCommittedIsStillOnABranch() {
		#expect(GitEstateBranches.parse("## No commits yet on main\0")?.branch == "main")
	}

	/// A branch name may hold dots, so the split is on the three-dot run.
	@Test func aBranchNameHoldingDots() {
		let branch = GitEstateBranches.parse("## release/1.2.3...origin/release/1.2.3 [behind 4]\0")
		#expect(branch?.branch == "release/1.2.3")
		#expect(branch?.upstream == "origin/release/1.2.3")
		#expect(branch?.behind == 4)
	}

	/// `-z` terminates records with NUL but git ends the header with a newline,
	/// so a parser trusting one separator reads the header and the first changed
	/// path as one string.
	@Test func theHeaderIsFoundWhicheverSeparatorFollowsIt() {
		let branch = GitEstateBranches.parse("## main...origin/main\nM  src/Main.java\0")
		#expect(branch?.branch == "main")
		#expect(branch?.upstream == "origin/main")
	}

	@Test func outputWithNoHeaderIsNoAnswer() {
		#expect(GitEstateBranches.parse("M  src/Main.java\0") == nil)
	}

	@Test func theBranchCallDoesNotWalkTheWorkTreeOrRecurse() {
		#expect(GitEstateBranches.arguments.contains("-uno"))
		#expect(GitEstateBranches.arguments.contains("--ignore-submodules=all"))
		#expect(GitEstateBranches.arguments.contains("-b"))
	}

	// MARK: - The rows

	@Test func rowsComeInTheOrderTheWorkIsIn() {
		let estate = estate(["a-clean", "b-changed", "c-conflicted", "d-ahead"])
		let status = GitEstateStatus(
			submodules: [
				"a-clean": GitWorkingCopyStatus(),
				"b-changed": changed(3),
				"c-conflicted": GitWorkingCopyStatus(
					unstaged: [GitChange(path: "x", kind: .conflicted, isStaged: false)]
				),
				"d-ahead": GitWorkingCopyStatus(),
			]
		)
		let rows = GitEstateOverview.rows(
			in: estate, status: status,
			branches: ["d-ahead": GitSubmoduleBranch(branch: "main", upstream: "origin/main", ahead: 2)]
		)

		#expect(rows.map(\.path) == ["c-conflicted", "b-changed", "d-ahead", "a-clean"])
		#expect(rows[0].state == .conflicted)
		#expect(rows[1].state == .changed(3))
		#expect(rows[2].state == .ahead(2))
		#expect(rows[3].state == .clean)
	}

	/// Drawn before the statuses land, a row must not say clean.
	@Test func aRowWithNoStatusYetSaysSoAndIsNotClean() {
		let rows = GitEstateOverview.rows(in: estate(["svc-1"]), status: GitEstateStatus())
		#expect(rows[0].state == .unread)
		#expect(rows[0].state != .clean)
	}

	@Test func aSubmoduleTheIndexNamesAndDiskLacksReadsAsAbsent() {
		let rows = GitEstateOverview.rows(
			in: estate(["svc-1"], absent: ["svc-1"]), status: GitEstateStatus()
		)
		#expect(rows[0].state == .absent)
	}

	/// Dirty beats moved: a submodule with uncommitted work and a moved gitlink
	/// is chiefly a submodule with uncommitted work, and the movement is still
	/// carried on the row.
	@Test func aSubmoduleBothMovedAndDirtyLeadsWithWhatIsUncommitted() {
		let estate = estate(["svc-1"])
		let status = GitEstateStatus(
			superproject: GitWorkingCopyStatus(
				unstaged: [GitChange(path: "svc-1", kind: .modified, isStaged: false)]
			),
			submodules: ["svc-1": changed(2)]
		)
		let rows = GitEstateOverview.rows(in: estate, status: status)
		#expect(rows[0].state == .changed(2))
		#expect(rows[0].changeCount == 2)
	}

	@Test func aSubmoduleThatOnlyMovedSaysSo() {
		let estate = estate(["svc-1"])
		let status = GitEstateStatus(
			superproject: GitWorkingCopyStatus(
				unstaged: [GitChange(path: "svc-1", kind: .modified, isStaged: false)]
			),
			submodules: ["svc-1": GitWorkingCopyStatus()]
		)
		#expect(GitEstateOverview.rows(in: estate, status: status)[0].state == .moved)
	}

	@Test func theOrderIsTheSameOrderTwice() {
		let estate = estate((1...20).map { "svc-\($0)" })
		let status = GitEstateStatus(
			submodules: Dictionary(uniqueKeysWithValues: (1...20).map { ("svc-\($0)", changed(1)) })
		)
		let once = GitEstateOverview.rows(in: estate, status: status)
		let twice = GitEstateOverview.rows(in: estate, status: status)
		#expect(once.map(\.path) == twice.map(\.path))
	}

	// MARK: - The sentence at the top

	@Test func theSummaryCountsWhatIsLeft() {
		let estate = estate(["a", "b", "c", "d"])
		let status = GitEstateStatus(
			submodules: [
				"a": changed(1), "b": changed(2),
				"c": GitWorkingCopyStatus(), "d": GitWorkingCopyStatus(),
			]
		)
		let rows = GitEstateOverview.rows(in: estate, status: status)
		#expect(GitEstateOverview.summary(of: rows) == "2 changed · 2 clean")
	}

	@Test func anEstateWithNothingToReportSaysSoInWords() {
		let estate = estate(["a", "b"])
		let status = GitEstateStatus(
			submodules: ["a": GitWorkingCopyStatus(), "b": GitWorkingCopyStatus()]
		)
		#expect(GitEstateOverview.summary(of: GitEstateOverview.rows(in: estate, status: status))
			== "all 2 clean")
	}

	/// A page still reading must not read as a page with nothing to report.
	@Test func aSummaryBeforeAnythingLandsSaysItIsStillReading() {
		let rows = GitEstateOverview.rows(in: estate(["a", "b"]), status: GitEstateStatus())
		#expect(GitEstateOverview.summary(of: rows) == "2 still reading")
	}

	@Test func noSubmodulesIsSaidRatherThanShownAsEmptiness() {
		#expect(GitEstateOverview.summary(of: []) == "no submodules")
	}

	// MARK: - Against a real estate

	@Test func theBranchOfEverySubmoduleIsReadInOneCallEach() async throws {
		let built = try SyntheticEstate.make(count: 3, named: "branches")
		defer { built.remove() }

		let estate = await GitEstate.read(from: built.root)
		let branches = await GitEstateBranches.branches(of: estate.submodules, in: built.root)
		#expect(branches.count == 3)
		#expect(branches["svc-1"]?.branch == "main")
		// `git submodule add` clones, so a submodule has an `origin` and a
		// branch tracking it from the moment it exists. There is no such thing
		// here as a submodule with no upstream unless somebody removed it.
		#expect(branches["svc-1"]?.upstream == "origin/main")
		#expect(branches["svc-1"]?.isLevel == true)
	}

	@Test func anEstateReadsIntoRowsEndToEnd() async throws {
		let built = try SyntheticEstate.make(count: 4, named: "overviewlive")
		defer { built.remove() }
		try built.dirty("svc-2")
		built.advance("svc-4", by: 2)

		let estate = await GitEstate.read(from: built.root)
		let status = await GitEstateReader.status(of: estate)
		let branches = await GitEstateBranches.branches(of: estate.submodules, in: built.root)
		let movements = await GitGitlink.movements(
			of: status.movedGitlinks(in: estate), in: built.root
		)
		let rows = GitEstateOverview.rows(
			in: estate, status: status, branches: branches, movements: movements
		)

		#expect(rows.map(\.path) == ["svc-2", "svc-4", "svc-1", "svc-3"])
		#expect(rows[0].state == .changed(1))

		// Committing inside a submodule makes it two things at once: ahead of
		// its own remote, and somewhere the superproject does not record. The
		// row leads with the first — pushing is the next thing to do — and
		// carries the second, which is the fact the superproject needs.
		#expect(rows[1].state == .ahead(2))
		#expect(rows[1].movement?.relation == .ahead(2))
		#expect(rows[2].state == .clean)
		#expect(GitEstateOverview.summary(of: rows) == "1 changed · 1 ahead · 2 clean")
	}
}

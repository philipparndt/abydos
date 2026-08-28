import Foundation
import Testing
@testable import AbydosKit

/// A set of pull requests raised from one description, and tracked to merge.
struct GitEstatePullRequestTests {
	private func entry(
		_ name: String,
		checks: ChecksState = .none,
		review: ReviewDecision = .undecided,
		merged: Bool = false,
		draft: Bool = false,
		raised: Bool = true,
		absence: ForgeAbsence? = nil
	) -> PullRequestSetEntry {
		PullRequestSetEntry(
			submodule: nil, name: name,
			request: raised ? PullRequest(
				number: 1, title: "t", author: "a",
				headRefName: "refactor/logging", baseRefName: "main",
				isDraft: draft, checks: checks
			) : nil,
			review: review, isMerged: merged, absence: absence
		)
	}

	// MARK: - What a row is chiefly saying

	/// Red first, and before draft: a draft whose build is broken is still a
	/// broken build, and what is stopping the set is the question it answers.
	@Test func aFailingBuildLeadsEvenOnADraft() {
		#expect(entry("a", checks: .failing).state == .failing)
		#expect(entry("a", checks: .failing, draft: true).state == .failing)
	}

	@Test func eachStateIsWhatTheRowIsChieflySaying() {
		#expect(entry("a", review: .changesRequested).state == .changesRequested)
		#expect(entry("a", review: .approved).state == .approved)
		#expect(entry("a", review: .reviewRequired).state == .awaitingReview)
		#expect(entry("a", draft: true).state == .draft)
		#expect(entry("a", merged: true).state == .merged)
		#expect(entry("a", raised: false).state == .none)
		#expect(entry("a", absence: .cliNotInstalled).state == .unavailable)
	}

	/// A merged pull request is finished whatever its checks said on the way.
	@Test func mergedOutranksEverythingElse() {
		#expect(entry("a", checks: .failing, merged: true).state == .merged)
	}

	/// `gh` gives an empty string on a repository with no review rules, which is
	/// not the same as approved.
	@Test func noReviewDecisionIsNotApproval() {
		#expect(ReviewDecision(rawValue: "") == .undecided)
		#expect(entry("a").state == .awaitingReview)
	}

	// MARK: - Reading one repository's answer

	@Test func aRepositoryWithAPullRequestOnTheBranch() {
		let json = """
		[{"number": 42, "title": "Logging", "author": {"login": "pat"},
		  "headRefName": "refactor/logging", "baseRefName": "main",
		  "isDraft": false, "state": "OPEN", "reviewDecision": "APPROVED"}]
		"""
		let read = GitEstatePullRequests.decode(json, submodule: nil, name: "svc-1")
		#expect(read.request?.number == 42)
		#expect(read.review == .approved)
		#expect(!read.isMerged)
		#expect(read.state == .approved)
	}

	@Test func aMergedPullRequestIsReadAsMerged() {
		let json = """
		[{"number": 7, "title": "t", "author": {"login": "pat"},
		  "headRefName": "refactor/logging", "baseRefName": "main",
		  "isDraft": false, "state": "MERGED", "reviewDecision": "APPROVED"}]
		"""
		let read = GitEstatePullRequests.decode(json, submodule: nil, name: "svc-1")
		#expect(read.isMerged)
		#expect(read.state == .merged)
	}

	@Test func aRepositoryWithNothingOnTheBranchHasNoRequest() {
		let read = GitEstatePullRequests.decode("[]", submodule: nil, name: "svc-1")
		#expect(read.request == nil)
		#expect(read.state == .none)
	}

	/// A branch reused after a merge has two, and the one somebody means is the
	/// one they have just raised.
	@Test func theNewestIsTakenWhenABranchHasBeenUsedTwice() {
		let json = """
		[{"number": 3, "title": "old", "author": {"login": "pat"},
		  "headRefName": "refactor/logging", "baseRefName": "main",
		  "isDraft": false, "state": "MERGED", "reviewDecision": "APPROVED"},
		 {"number": 9, "title": "new", "author": {"login": "pat"},
		  "headRefName": "refactor/logging", "baseRefName": "main",
		  "isDraft": false, "state": "OPEN", "reviewDecision": ""}]
		"""
		let read = GitEstatePullRequests.decode(json, submodule: nil, name: "svc-1")
		#expect(read.request?.number == 9)
		#expect(!read.isMerged)
	}

	/// The whole set must not fail because one repository answered oddly.
	@Test func aRowMissingFieldsDegradesRatherThanFailingTheSet() {
		let json = """
		[{"number": 5, "headRefName": "refactor/logging", "baseRefName": "main"}]
		"""
		let read = GitEstatePullRequests.decode(json, submodule: nil, name: "svc-1")
		#expect(read.request?.number == 5)
		#expect(read.review == .undecided)
	}

	// MARK: - What the set says about itself

	@Test func theSummaryCountsWhatIsLeftWithRedFirst() {
		let entries = [
			entry("a", checks: .failing),
			entry("b", review: .approved),
			entry("c", review: .approved),
			entry("d", merged: true),
		]
		#expect(GitEstatePullRequests.summary(of: entries)
			== "1 failing · 2 approved and unmerged · 1 merged")
	}

	@Test func aFinishedSetSaysSoRatherThanReadingAsEmpty() {
		let entries = [entry("a", merged: true), entry("b", merged: true)]
		#expect(GitEstatePullRequests.summary(of: entries) == "all 2 merged")
	}

	@Test func aSetWithNothingRaisedSaysThat() {
		let entries = [entry("a", raised: false), entry("b", raised: false)]
		#expect(GitEstatePullRequests.summary(of: entries) == "2 with none raised")
	}

	@Test func noRepositoriesIsSaidRatherThanShownAsEmptiness() {
		#expect(GitEstatePullRequests.summary(of: []) == "no repositories")
	}

	/// A repository that could not be asked is not a repository with no pull
	/// request. The one thing an empty set must never look like is a machine
	/// that could not reach the forge.
	@Test func aRepositoryThatCouldNotBeAskedIsCountedApart() {
		let entries = [entry("a", absence: .cliNotLoggedIn(host: "github.com")), entry("b")]
		#expect(GitEstatePullRequests.summary(of: entries)
			== "1 awaiting review · 1 could not be asked")
	}

	// MARK: - The fan-out

	/// Sized for a forge rather than for this machine's disk: the limit that
	/// matters is the forge's, and a rate limit is what being wrong looks like.
	@Test func theForgeFanOutIsBoundedSeparatelyFromGit() {
		#expect(GitEstatePullRequests.concurrency >= 1)
		#expect(GitEstatePullRequests.concurrency <= 8)
	}

	/// `gh search prs` would answer a set in one call and must not be used: its
	/// indexing lags, and it is GitHub.com-shaped.
	@Test func theSetIsAskedPerRepositoryAndNeverThroughSearch() {
		let source = GitEstatePullRequests.fields
		#expect(source.contains("reviewDecision"))
		#expect(source.contains("state"))
	}

	// MARK: - Raising, against real repositories

	/// A branch that matches the default has nothing to propose, and a pull
	/// request for it would be an empty one somebody has to close.
	@Test func aRepositoryWithNothingOnTheBranchIsSkipped() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "prnothing")
		defer { estate.remove() }

		#expect(await !GitEstatePullRequests.hasCommits(
			onBranch: "main", in: estate.root.appendingPathComponent("svc-1")
		))
	}

	@Test func aRepositoryWithCommitsOnTheBranchHasSomethingToPropose() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "prsomething")
		defer { estate.remove() }

		let submodule = estate.root.appendingPathComponent("svc-1")
		SyntheticEstate.run(["checkout", "-qb", "refactor/logging"], in: submodule)
		estate.advance("svc-1", by: 2, saying: "refactor")

		#expect(await GitEstatePullRequests.hasCommits(
			onBranch: "refactor/logging", in: submodule
		))
	}

	/// Every repository gets an outcome, including the ones the refactoring
	/// never touched — a set that named only what it raised could not be told
	/// from one that raised everything.
	@Test func everyRepositoryGetsAnOutcome() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "praise")
		defer { estate.remove() }

		let read = await GitEstate.read(from: estate.root)
		let outcomes = await GitEstatePullRequests.raise(
			onBranch: "refactor/logging", title: "Logging", body: "", in: read
		)
		#expect(outcomes.map(\.name) == ["svc-1", "svc-2", "svc-3", "."])
		// No GitHub remote here, so every one is skipped and says why — which is
		// a sentence about the repository and not an error.
		#expect(outcomes.filter(\.didFail).isEmpty)
	}
}

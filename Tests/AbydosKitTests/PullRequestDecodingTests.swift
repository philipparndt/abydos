import Foundation
import Testing
@testable import AbydosKit

/// Reading what `gh` says, over output `gh` actually said.
///
/// **The payloads are recorded, not written.** `gh`'s JSON is a contract this
/// program does not own, and a fixture somebody typed out is a fixture of what
/// they believed the shape to be — which is exactly the belief a decoder test is
/// supposed to check. `Fixtures/gh-pr-list.json`, `gh-pr-files.json` and
/// `gh-pr-comments.json` came off `gh` and the GitHub API against the public
/// `cli/cli` repository, trimmed of the prose and the patch text that no decoder
/// reads.
///
/// Two payloads are written rather than recorded, and each says why: one with
/// fields missing, because a repository whose rows are all complete cannot show
/// that an incomplete one degrades rather than fails; and one from an Enterprise
/// host, because there is no public one to record and the claim being made is
/// that the host is not special-cased anywhere.
struct PullRequestDecodingTests {
	private func fixture(_ name: String) throws -> String {
		let url = try #require(Bundle.module.url(
			forResource: name, withExtension: "json", subdirectory: "Fixtures"
		))
		return try String(contentsOf: url, encoding: .utf8)
	}

	// MARK: - `gh pr list --json`

	@Test func theListSaysWhatEachRowIs() throws {
		let requests = GitHubPullRequests.pullRequests(fromJSON: try fixture("gh-pr-list"))

		#expect(requests.count == 3)
		let first = try #require(requests.first)
		#expect(first.number == 14267)
		#expect(first.author == "app/dependabot")
		#expect(first.baseRefName == "trunk")
		#expect(first.headRefName.hasPrefix("dependabot/go_modules/"))
		#expect(first.isDraft == false)
		#expect(first.url?.absoluteString == "https://github.com/cli/cli/pull/14267")
		#expect(first.title.hasPrefix("chore(deps): bump"))
	}

	/// Every row arrives unmarked. Which ones are waiting on the reader is a
	/// second call — a search — and the list itself cannot know.
	@Test func nothingIsWaitingOnAnybodyUntilTheSearchSaysSo() throws {
		let requests = GitHubPullRequests.pullRequests(fromJSON: try fixture("gh-pr-list"))
		#expect(requests.allSatisfy { !$0.isWaitingOnMe })
	}

	@Test func theTimestampIsRead() throws {
		let requests = GitHubPullRequests.pullRequests(fromJSON: try fixture("gh-pr-list"))
		let updated = try #require(requests.first?.updatedAt)
		// 2026-08-26T15:02:44Z
		#expect(abs(updated.timeIntervalSince1970 - 1_787_756_564) < 1)
	}

	/// The marker search asks for `--json number` and nothing else.
	@Test func theWaitingSearchIsJustNumbers() {
		let numbers = GitHubPullRequests.numbers(fromJSON: #"[{"number":7},{"number":9}]"#)
		#expect(numbers == [7, 9])
	}

	// MARK: - A row that is missing things

	/// **A missing field costs its row a word, not the list its rows.** A
	/// `Decodable` struct would fail the whole array over the deleted account in
	/// the first row here, and a review list that says nothing because one
	/// author closed their account is worse than one that says "(unknown)".
	@Test func aRowMissingFieldsDegradesRatherThanFailingTheList() throws {
		let requests = GitHubPullRequests.pullRequests(fromJSON: try fixture("gh-pr-list-sparse"))

		// Three rows in, two out: the third has no number, and a number is the
		// one thing nothing else can be asked by.
		#expect(requests.count == 2)

		let deleted = try #require(requests.first)
		#expect(deleted.number == 41)
		#expect(deleted.author == "(unknown)")
		#expect(deleted.checks == .none)

		let bare = try #require(requests.last)
		#expect(bare.number == 42)
		#expect(bare.title == "(untitled)")
		#expect(bare.headRefName.isEmpty)
		#expect(bare.baseRefName.isEmpty)
		#expect(bare.isDraft == false)
		#expect(bare.updatedAt == nil)
		// No `url` field at all, and no URL — rather than a row lost.
		#expect(bare.url == nil)
		// A check that has started and not finished is running, whatever its
		// empty conclusion says.
		#expect(bare.checks == .pending)
	}

	// MARK: - An Enterprise host

	/// The host is not special-cased anywhere, which is the whole claim: an
	/// installation sharing GitHub's layout is another hostname and nothing
	/// else. `GitForge` already draws that line and this follows it.
	@Test func anEnterprisePayloadReadsLikeAnyOther() throws {
		let requests = GitHubPullRequests.pullRequests(fromJSON: try fixture("gh-pr-list-enterprise"))

		#expect(requests.count == 2)
		let draft = try #require(requests.first)
		#expect(draft.number == 1188)
		#expect(draft.author == "j.doe")
		#expect(draft.isDraft)
		// The row says both, which is the spec's second scenario: a draft whose
		// checks have failed.
		#expect(draft.checks == .failing)
		#expect(draft.url?.host == "ghe.example.com")

		let green = try #require(requests.last)
		#expect(green.isDraft == false)
		#expect(green.checks == .passing)
	}

	// MARK: - What it changes

	@Test func theFilesAreReadWithTheirCounts() throws {
		let files = GitHubPullRequests.files(fromJSON: try fixture("gh-pr-files"))

		#expect(files.count == 3)
		let verify = try #require(files.first { $0.path.hasSuffix("verify/verify.go") })
		#expect(verify.additions == 3)
		#expect(verify.deletions == 2)
		#expect(verify.kind == .modified)
		#expect(verify.lineCount == GitLineCount(added: 3, removed: 2))
		// The row a `ChangedFileList` draws is the same row a commit's is.
		#expect(verify.asCommitFile.path == verify.path)
	}

	/// GitHub's word for what happened, in this repository's own — and an
	/// unknown word is a modification rather than a row lost, because a file in
	/// the list changed somehow.
	@Test func everyStatusHasAKind() {
		#expect(GitHubPullRequests.kind(from: "added") == .added)
		#expect(GitHubPullRequests.kind(from: "removed") == .deleted)
		#expect(GitHubPullRequests.kind(from: "renamed") == .renamed)
		#expect(GitHubPullRequests.kind(from: "copied") == .copied)
		#expect(GitHubPullRequests.kind(from: "changed") == .modified)
		#expect(GitHubPullRequests.kind(from: "something new") == .modified)
		#expect(GitHubPullRequests.kind(from: nil) == .modified)
	}

	/// A file with no name is no file. Everything else about a row can be
	/// missing and leave something worth drawing.
	@Test func aFileWithNoNameIsDropped() {
		let files = GitHubPullRequests.files(
			fromJSON: #"[{"additions":4},{"filename":"a.txt"},{"filename":""}]"#
		)
		#expect(files.map(\.path) == ["a.txt"])
		#expect(files.first?.additions == 0)
	}

	/// **`--paginate` concatenates documents.** Two pages arrive as `[…][…]`,
	/// which is not a JSON document and which `JSONSerialization` refuses whole.
	/// A pull request with thirty-one changed files is two pages, so this is the
	/// ordinary case rather than an exotic one.
	@Test func pagesAreConcatenatedRatherThanNested() {
		let two = #"[{"filename":"a.txt","additions":1,"deletions":0,"status":"added"}]"#
			+ "\n"
			+ #"[{"filename":"b.txt","additions":0,"deletions":2,"status":"removed"}]"#
		let files = GitHubPullRequests.files(fromJSON: two)
		#expect(files.map(\.path) == ["a.txt", "b.txt"])
		#expect(files.last?.kind == .deleted)
	}

	/// A `]` inside a string is not the end of a page.
	@Test func aBracketInsideAStringIsNotAPageBoundary() {
		let text = #"[{"filename":"we][rd.txt","status":"added"}][{"filename":"b.txt"}]"#
		let files = GitHubPullRequests.files(fromJSON: text)
		#expect(files.map(\.path) == ["we][rd.txt", "b.txt"])
	}

	// MARK: - The conversation

	@Test func theCommentsAreReadAtTheirLines() throws {
		let comments = GitHubPullRequests.comments(fromJSON: try fixture("gh-pr-comments"))

		#expect(comments.count == 4)
		let first = try #require(comments.first)
		#expect(first.id == 332_430_752)
		#expect(first.author == "mislav")
		#expect(first.path == "command/pr.go")
		#expect(first.line == 297)
		#expect(first.isOutdated == false)
		#expect(first.commit == "996619ea3cf9d0534e98e6a65c64688efd629d1d")
		#expect(first.createdAt != nil)
	}

	/// **A comment whose line has gone is kept.** GitHub answers `"line": null`
	/// for one the author has since written over, and dropping those would leave
	/// a reviewer saying a second time what somebody has already said. Two of
	/// the four recorded here are in that state, which is how common it is.
	@Test func aCommentAboutAnEarlierVersionIsKeptAndMarked() throws {
		let comments = GitHubPullRequests.comments(fromJSON: try fixture("gh-pr-comments"))
		let outdated = comments.filter(\.isOutdated)

		#expect(outdated.count == 2)
		#expect(outdated.allSatisfy { $0.line == nil })
		// Still findable: it says which file it was about.
		#expect(outdated.allSatisfy { !$0.path.isEmpty })
	}

	@Test func aCommentWithNoIdIsDropped() {
		let comments = GitHubPullRequests.comments(
			fromJSON: #"[{"body":"hi","path":"a.txt"},{"id":3,"path":"a.txt","line":2}]"#
		)
		#expect(comments.map(\.id) == [3])
		#expect(comments.first?.author == "(unknown)")
		#expect(comments.first?.body == "")
	}

	// MARK: - Checks

	/// The worst state wins: one red check makes the pull request red however
	/// many green ones are beside it, because that is what somebody deciding
	/// whether to read it wants to know.
	@Test func theWorstCheckDecides() {
		let mixed = """
		[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"},{"status":"IN_PROGRESS"}]
		"""
		#expect(checks(mixed) == .failing)
		#expect(checks(#"[{"conclusion":"SUCCESS"},{"status":"QUEUED"}]"#) == .pending)
		#expect(checks(#"[{"conclusion":"SUCCESS"},{"conclusion":"SKIPPED"}]"#) == .passing)
	}

	/// A commit status is the other shape, and Jenkins is why it is read.
	@Test func aCommitStatusIsReadToo() {
		#expect(checks(#"[{"state":"FAILURE","context":"ci/jenkins"}]"#) == .failing)
		#expect(checks(#"[{"state":"PENDING","context":"ci/jenkins"}]"#) == .pending)
		#expect(checks(#"[{"state":"SUCCESS","context":"ci/jenkins"}]"#) == .passing)
	}

	/// No checks and no news are the same thing to a row, and neither is bad
	/// news: a shape this does not recognise is ignored rather than counted as a
	/// failure.
	@Test func nothingToSayIsNotAFailure() {
		#expect(checks("[]") == .none)
		#expect(checks(#"[{"__typename":"SomethingNew"}]"#) == .none)
		#expect(GitHubPullRequests.checksState(from: nil) == .none)
	}

	private func checks(_ json: String) -> ChecksState {
		let value = try? JSONSerialization.jsonObject(with: Data(json.utf8))
		return GitHubPullRequests.checksState(from: value)
	}

	// MARK: - What `gh` said when it refused

	@Test func aRefusalIsReportedAsWhatItSaid() {
		#expect(GitHubPullRequests.complaint(
			.init(stdout: "", stderr: "  could not resolve to a Repository\n", exitCode: 1)
		) == "could not resolve to a Repository")

		// Some of `gh`'s complaints come out on stdout.
		#expect(GitHubPullRequests.complaint(
			.init(stdout: "no pull requests found", stderr: "", exitCode: 1)
		) == "no pull requests found")

		// A killed process says nothing at all, and that is worth saying.
		#expect(GitHubPullRequests.complaint(
			.init(stdout: "", stderr: "", exitCode: -9)
		).contains("-9"))
	}
}

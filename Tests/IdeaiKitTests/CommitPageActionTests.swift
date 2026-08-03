import Testing
@testable import IdeaiKit

/// Which of the commit page's buttons is the accented one.
struct CommitPageActionTests {
	@Test func stagedFilesMakeCommitTheOneToPress() {
		#expect(CommitPageAction.primary(staged: 3, isAmending: false, canPush: true) == .commit)
	}

	/// The whole point: a clean index with commits waiting is a page you came
	/// to in order to push.
	@Test func nothingStagedHandsTheAccentToPush() {
		#expect(CommitPageAction.primary(staged: 0, isAmending: false, canPush: true) == .push)
	}

	/// Not "the commit button happens to be disabled": a staged file with no
	/// message yet is still something to commit, and the accent should not
	/// jump to push and back while somebody types a summary.
	@Test func aStagedFileKeepsTheAccentWhileTheMessageIsStillEmpty() {
		#expect(CommitPageAction.primary(staged: 1, isAmending: false, canPush: true) == .commit)
	}

	/// Rewording the last commit is a normal thing to be here for, and it
	/// stages nothing.
	@Test func amendingIsSomethingToCommit() {
		#expect(CommitPageAction.primary(staged: 0, isAmending: true, canPush: true) == .commit)
	}

	@Test func nothingToDoAccentsNeither() {
		#expect(CommitPageAction.primary(staged: 0, isAmending: false, canPush: false) == .none)
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// What is said before something that can lose work.
///
/// The sentences are the part most likely to go wrong and the part hardest to
/// check by opening the app twenty times, which is why they are in the kit and
/// tested here.
struct GitDestructiveTests {
	private let moment = Date(timeIntervalSince1970: 1_700_000_000)

	private func ask(_ operation: GitDestructive.Operation) -> GitDestructive.Ask {
		GitDestructive.ask(before: operation, at: moment)
	}

	/// The whole reason the wording is here: a number is read where "this
	/// cannot be undone" is not.
	@Test func everyDialogLeadsWithACount() {
		#expect(ask(.reset(to: "50e77df9", commits: 4, mode: .hard)).title
			== "4 commits leave this branch")
		#expect(ask(.switchBranch(to: "main", changedFiles: 3)).title
			== "3 changed files would be overwritten by “main”")
		#expect(ask(.deleteBranch("feature/x", ahead: 3)).title
			== "“feature/x” is 3 commits ahead")
		#expect(ask(.rebase(branch: "main", commits: 1)).title
			== "1 commit will be replayed")
	}

	@Test func oneOfSomethingIsNotOnes() {
		#expect(ask(.switchBranch(to: "main", changedFiles: 1)).title
			== "1 changed file would be overwritten by “main”")
		#expect(ask(.reset(to: "abc", commits: 1, mode: .mixed)).title
			== "1 commit leaves this branch")
	}

	@Test func everythingRecoverableNamesTheBranchItLeaves() {
		for operation: GitDestructive.Operation in [
			.switchBranch(to: "main", changedFiles: 2),
			.discard(files: 2, untracked: 0),
			.reset(to: "abc", commits: 1, mode: .hard),
			.rebase(branch: "main", commits: 1),
			.amend,
			.deleteBranch("feature/x", ahead: 2),
			.moveTag("v1", from: "50e77df9"),
		] {
			#expect(ask(operation).backup?.hasPrefix("backup/") == true, "\(operation)")
		}
	}

	/// No ref on this machine can bring back somebody else's commits from a
	/// remote, and claiming a backup here would be the worst untruth in the
	/// feature.
	@Test func forcePushingClaimsNoBackup() {
		let asked = ask(.forcePush(branch: "main", overwriting: 2))
		#expect(asked.backup == nil)
		#expect(asked.title == "2 commits on the remote would be overwritten")
		#expect(asked.detail.contains("Nothing here can bring them back"))
	}

	/// `Always stash and switch` may be ticked; `Always discard` may not be,
	/// ever.
	@Test func onlyTheChoiceThatLosesNothingMayBeRemembered() {
		let switching = ask(.switchBranch(to: "main", changedFiles: 3))
		#expect(switching.choices.count == 2)
		#expect(switching.choices[0].title == "Stash and Switch")
		#expect(switching.choices[0].mayBeRemembered)
		#expect(!switching.choices[1].mayBeRemembered, "leaving work behind may never be remembered")

		for operation: GitDestructive.Operation in [
			.discard(files: 1, untracked: 0),
			.reset(to: "abc", commits: 1, mode: .hard),
			.rebase(branch: "main", commits: 1),
			.moveTag("v1", from: "abc"),
			.forcePush(branch: "main", overwriting: 1),
		] {
			let remembered = ask(operation).choices.filter(\.mayBeRemembered)
			#expect(remembered.isEmpty, "\(operation) has no safe answer to remember")
		}
	}

	@Test func theSafestChoiceComesFirst() {
		let choices = ask(.switchBranch(to: "main", changedFiles: 3)).choices
		#expect(choices.first?.losesNothing == true)
	}

	/// Restoring a tracked file and deleting one git has never seen are
	/// different acts, and only one of them is what "discard" sounds like.
	@Test func discardSaysSeparatelyWhatItWillDelete() {
		#expect(ask(.discard(files: 4, untracked: 2)).detail
			.contains("2 changed files git has never seen will be deleted"))
		#expect(!ask(.discard(files: 4, untracked: 0)).detail.contains("never seen"))
	}

	/// A branch level with everything else is a name, and deleting it takes
	/// nothing — so it is not the same question.
	@Test func deletingABranchThatIsNotAheadIsNotDestructive() {
		let asked = ask(.deleteBranch("merged", ahead: 0))
		#expect(asked.backup == nil)
		let lossy = asked.choices.filter { !$0.losesNothing }
		#expect(lossy.isEmpty)
		#expect(asked.detail == "Everything on it is on another branch too.")
	}

	@Test func aHardResetSaysTheWorkingCopyGoesWithIt() {
		#expect(ask(.reset(to: "abc", commits: 2, mode: .hard)).detail
			.contains("The working copy goes back with it"))
		#expect(ask(.reset(to: "abc", commits: 2, mode: .soft)).detail
			.contains("The working copy keeps what it has"))
	}
}

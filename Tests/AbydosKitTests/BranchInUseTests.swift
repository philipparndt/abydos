import Foundation
import Testing
@testable import AbydosKit

/// What is said about a branch another checkout holds.
///
/// The refusal it replaces is git's, and it is true and useless:
/// `fatal: 'ui' is already used by worktree at '/…/agent-a9b2'`. The branch is
/// checked out somewhere this program can open, and what somebody wanted is one
/// press away.
///
/// Here rather than in a view, so the sentences can be read without a window.
struct BranchInUseTests {
	private func worktree(
		_ path: String, branch: String?, isPrimary: Bool = false, isMissing: Bool = false
	) -> GitWorktree {
		GitWorktree(
			path: URL(fileURLWithPath: path), branch: branch, head: "abc123",
			isPrimary: isPrimary, isMissing: isMissing, isLocked: false
		)
	}

	@Test func aLiveCheckoutIsOfferedToBeOpened() {
		let held = worktree("/Users/me/dev/cuttr/.claude/worktrees/agent-a9b2", branch: "ui")
		let offer = BranchInUse.offer(for: held)
		#expect(offer == .open(held))

		#expect(BranchInUse.title("ui") == "ui is checked out elsewhere")
		let detail = BranchInUse.detail("ui", offer: offer, primaryName: "cuttr")
		#expect(detail.contains("agent-a9b2"))
		#expect(detail.contains("git will not have it in two places at once"))
		#expect(BranchInUse.action(for: offer, primaryName: "cuttr").hasPrefix("Open "))
	}

	/// **The main checkout is named as itself.** "The main checkout has it" reads
	/// differently from a path under `.claude/worktrees`, and the list already
	/// tells them apart.
	@Test func theMainCheckoutIsNamedAsItself() {
		let primary = worktree("/Users/me/dev/cuttr", branch: "main", isPrimary: true)
		let offer = BranchInUse.offer(for: primary)
		#expect(BranchInUse.detail("main", offer: offer, primaryName: "cuttr")
			.contains("the main checkout"))
		#expect(BranchInUse.action(for: offer, primaryName: "cuttr") == "Open the main checkout")
		// And not as a path, which is what a worktree gets.
		#expect(!BranchInUse.detail("main", offer: offer, primaryName: "cuttr")
			.contains("/Users/me/dev/cuttr,"))
	}

	/// A worktree deleted with `rm -rf` stays registered and git goes on refusing
	/// the branch on its behalf. **Offering to open it would fail**, and the
	/// sentence would be the second useless thing somebody was told in a row.
	@Test func aRegistrationWithNothingBehindItIsOfferedAPrune() {
		let gone = worktree("/Users/me/dev/cuttr/.claude/worktrees/gone", branch: "stale", isMissing: true)
		let offer = BranchInUse.offer(for: gone)
		#expect(offer == .prune(gone))

		let detail = BranchInUse.detail("stale", offer: offer, primaryName: "cuttr")
		#expect(detail.contains("no longer there"))
		#expect(detail.contains("Removing the registration frees the branch"))
		#expect(BranchInUse.action(for: offer, primaryName: "cuttr") == "Remove the registration")
		// It does not offer to open something that is not there.
		#expect(!BranchInUse.action(for: offer, primaryName: "cuttr").hasPrefix("Open"))
	}

	/// The two offers are told apart by a fact on the worktree, not by a wording.
	@Test func whichOfferIsMadeIsAFact() {
		#expect(BranchInUse.offer(for: worktree("/w", branch: "a")) == .open(worktree("/w", branch: "a")))
		#expect(BranchInUse.offer(for: worktree("/w", branch: "a", isMissing: true))
			== .prune(worktree("/w", branch: "a", isMissing: true)))
	}

	/// Every sentence names the branch that was asked for, because a toast is
	/// read out of the corner of an eye and "it is checked out elsewhere" about
	/// nothing in particular is not information.
	@Test func everySentenceNamesTheBranch() {
		for held in [
			worktree("/w/a", branch: "feature/thing"),
			worktree("/w/b", branch: "feature/thing", isPrimary: true),
			worktree("/w/c", branch: "feature/thing", isMissing: true),
		] {
			let offer = BranchInUse.offer(for: held)
			#expect(BranchInUse.title("feature/thing").contains("feature/thing"))
			#expect(BranchInUse.detail("feature/thing", offer: offer, primaryName: "p")
				.contains("feature/thing"))
		}
	}
}

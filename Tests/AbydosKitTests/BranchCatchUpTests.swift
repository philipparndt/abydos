import Foundation
import Testing
@testable import AbydosKit

/// Which catch-up verb a branch row offers.
///
/// The case that made this worth having its own type is the current branch:
/// fast-forward is right to refuse it, and the menu then offered nothing at
/// all to a branch whose own row was saying `↓3`.
struct BranchCatchUpTests {
	private func local(
		_ name: String = "main",
		current: Bool = false,
		upstream: String? = "origin/main",
		ahead: Int = 0,
		behind: Int = 0,
		gone: Bool = false
	) -> GitBranch {
		GitBranch(
			name: name,
			kind: .local,
			isCurrent: current,
			ahead: ahead,
			behind: behind,
			upstream: upstream,
			upstreamIsGone: gone
		)
	}

	/// The row somebody is standing on, which is what was missing.
	@Test func theCheckedOutBranchIsPulled() {
		#expect(BranchCatchUp.offer(for: local(current: true, behind: 3)) == .pull)
	}

	/// Offered level as well, because the counts are as old as the last fetch
	/// and a pull is how somebody finds out otherwise.
	@Test func pullIsOfferedBeforeAnybodyKnowsTheyAreBehind() {
		#expect(BranchCatchUp.offer(for: local(current: true)) == .pull)
	}

	/// A branch that is not checked out moves by its ref, and the item names
	/// where to.
	@Test func aBranchNobodyIsOnFastForwards() {
		#expect(
			BranchCatchUp.offer(for: local(behind: 4))
				== .fastForward(upstream: "origin/main")
		)
	}

	/// The upstream is used as it is written, not guessed at from the name: a
	/// branch may track something that is not `origin/<itself>`.
	@Test func theUpstreamIsTheOneTheBranchTracks() {
		let branch = local("topic", upstream: "upstream/trunk", behind: 1)
		#expect(BranchCatchUp.offer(for: branch) == .fastForward(upstream: "upstream/trunk"))
	}

	/// Commits of its own make it a merge, and moving the ref would lose them.
	@Test func aDivergedBranchIsOfferedNeither() {
		#expect(BranchCatchUp.offer(for: local(ahead: 2, behind: 3)) == nil)
	}

	/// Nothing to move towards, so nothing to offer.
	@Test func aBranchLevelWithItsUpstreamIsOfferedNothing() {
		#expect(BranchCatchUp.offer(for: local()) == nil)
	}

	/// Never pushed: no upstream, whichever branch it is.
	@Test func anUnpublishedBranchIsOfferedNothing() {
		#expect(BranchCatchUp.offer(for: local(upstream: nil, behind: 0)) == nil)
		#expect(BranchCatchUp.offer(for: local(current: true, upstream: nil)) == nil)
	}

	/// **Gone parses as level**, so it has to be asked about by name.
	///
	/// `%(upstream:track)` says `[gone]` where it would otherwise say the
	/// counts, which is nought behind and nought ahead — the shape of a branch
	/// in step. The branch left behind by a merged pull request would otherwise
	/// be offered a pull from a ref that is not there.
	@Test func anUpstreamThatIsGoneIsNotSomewhereToCatchUpTo() {
		#expect(BranchCatchUp.offer(for: local(current: true, gone: true)) == nil)
		#expect(BranchCatchUp.offer(for: local(behind: 2, gone: true)) == nil)
	}

	/// A remote-tracking row is the upstream, and a tag does not move.
	@Test func onlyLocalBranchesCatchUp() {
		let remote = GitBranch(
			name: "main", kind: .remote("origin"), behind: 3, upstream: "origin/main"
		)
		#expect(BranchCatchUp.offer(for: remote) == nil)
		#expect(BranchCatchUp.offer(for: GitBranch(name: "v1.0", kind: .tag)) == nil)
	}
}

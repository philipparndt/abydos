import Foundation

/// What to say when a branch cannot be switched to because a checkout has it.
///
/// **git's refusal is true and useless**, and this is the one refusal the app can
/// act on:
///
///     fatal: 'ui' is already used by worktree at '/…/agent-a9b22c96f3f4d82eb'
///
/// The branch *is* checked out, somewhere this program can open, and what
/// somebody wanted is one press away. Everything else git refuses for — a dirty
/// work tree, a branch that does not exist, a hook that said no — keeps git's own
/// message, which is the clearest thing available.
///
/// In `AbydosKit` and over a `GitWorktree` rather than in a view, so what is
/// said can be read without a window — the rule `RenameOffer` and `CodeLink`
/// already keep.
public enum BranchInUse {
	/// What is offered about a branch another checkout holds.
	public enum Offer: Equatable, Sendable {
		/// A checkout that is there: open it.
		case open(GitWorktree)
		/// A registration whose directory is gone. `rm -rf` on a worktree leaves
		/// it registered and git goes on refusing the branch on its behalf, so
		/// "open it" would fail and be the second useless thing somebody was told
		/// in a row.
		case prune(GitWorktree)

		public var worktree: GitWorktree {
			switch self {
			case let .open(worktree), let .prune(worktree): return worktree
			}
		}
	}

	/// What there is to offer, given the checkout that holds the branch.
	public static func offer(for worktree: GitWorktree) -> Offer {
		worktree.isMissing ? .prune(worktree) : .open(worktree)
	}

	/// The title of the notification.
	public static func title(_ branch: String) -> String {
		"\(branch) is checked out elsewhere"
	}

	/// What it says, which is what it means for *this* switch rather than a fact
	/// about the repository.
	///
	/// The primary checkout is named as itself: "the main checkout has it" reads
	/// differently from a path under `.claude/worktrees`, and the list already
	/// tells them apart.
	public static func detail(_ branch: String, offer: Offer, primaryName: String) -> String {
		let worktree = offer.worktree
		let where_ = worktree.isPrimary
			? "the main checkout"
			: "the checkout at \(worktree.path.path)"

		switch offer {
		case .open:
			return "\(branch) is checked out in \(where_), and git will not have it "
				+ "in two places at once."
		case .prune:
			return "\(branch) is held by \(where_), which is registered and no longer "
				+ "there — the usual state after a worktree is deleted by hand. "
				+ "Removing the registration frees the branch."
		}
	}

	/// What the button says.
	public static func action(for offer: Offer, primaryName: String) -> String {
		switch offer {
		case let .open(worktree):
			return worktree.isPrimary
				? "Open the main checkout"
				: "Open \(GitWorktrees.shortName(of: worktree, primaryName: primaryName))"
		case .prune:
			return "Remove the registration"
		}
	}
}

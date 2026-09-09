import Foundation

/// Which verb a branch row offers for *bring this one up to date*.
///
/// Two verbs answering one question, and which of them applies is decided by
/// whether the branch is the one being stood on. Moving a ref without touching
/// the working copy is a fast-forward, which is what `GitFastForward` does and
/// what git will not do to `HEAD`; moving the working copy with it is a pull.
///
/// **The menu used to offer the first and not the second.** Fast-forward was
/// written for the branch nobody is on — `main ↓4` while the work happens
/// elsewhere — and gated on exactly that, correctly. Nothing then put the other
/// verb back for the current branch, so right-clicking `main ↓3` while standing
/// on `main` offered Checkout, Merge, Rebase and Delete, every one of them grey
/// against itself, and no way to catch up at all. Pull was on the repository
/// row above and nowhere else. Deciding both here is what keeps the pair
/// complete: a branch that is behind has a verb, whichever branch it is.
public enum BranchCatchUp: Sendable, Equatable {
	/// Move the ref up to its upstream, leaving the working copy alone.
	case fastForward(upstream: String)
	/// The branch is checked out, so catching up moves the working copy too.
	case pull

	/// What to offer on this branch's row, or nil where nothing applies.
	///
	/// Pull is offered on the current branch whether or not the counts say it
	/// is behind, and fast-forward only where the counts say it is. That is not
	/// an inconsistency: the counts are as old as the last fetch, and a pull
	/// fetches — it is how somebody finds out they were behind. A fast-forward
	/// does not, having nothing to move towards but the ref already here, so
	/// offering it on a branch that reads level would be offering to do
	/// nothing. The same argument the repository row makes for always saying
	/// Fetch in the word.
	public static func offer(for branch: GitBranch) -> BranchCatchUp? {
		guard case .local = branch.kind, branch.upstream != nil else { return nil }
		// An upstream that was deleted is not somewhere to catch up to, and it
		// parses as level rather than as missing — so it has to be asked about
		// by name or a merged-and-deleted branch offers a pull that can only
		// fail.
		guard !branch.upstreamIsGone else { return nil }

		if branch.isCurrent { return .pull }

		// Behind with nothing of its own on it: exactly when moving the ref
		// loses nothing. `GitFastForward` asks git the same question again with
		// `merge-base --is-ancestor` before it moves anything — these counts
		// decide what to *offer*, not what is safe.
		guard branch.behind > 0, branch.ahead == 0, let upstream = branch.upstream else {
			return nil
		}
		return .fastForward(upstream: upstream)
	}
}

import Foundation

/// What can lose work, what it costs, and what to say before doing it.
///
/// **One place, and a closed one.** The rule is only worth having if the list
/// cannot drift, and the way to stop it drifting is that there is nothing here
/// to add a safe operation to: staging, unstaging, stashing, fetching, creating
/// a branch or a tag, and applying a stash while keeping it are all recoverable,
/// and none of them has a case below. A dialog in front of a safe operation is
/// what teaches somebody to dismiss the one in front of an unsafe one.
///
/// **In the kit and not in a view**, so what is said can be read without a
/// window — the rule `BranchInUse` and `GitDiscard.menuTitle` already keep. The
/// sentences are the thing most likely to go wrong and the thing hardest to
/// check by opening the app twenty times.
public enum GitDestructive {
	/// Everything that can leave work unrecoverable. There is nothing else.
	public enum Operation: Sendable, Equatable {
		/// A checkout git refuses because the working copy is in the way.
		case switchBranch(to: String, changedFiles: Int)
		/// Throwing away what is in the working copy.
		case discard(files: Int, untracked: Int)
		/// Moving the branch to another commit.
		case reset(to: String, commits: Int, mode: GitCommits.ResetMode)
		/// Replaying commits, which rewrites them.
		case rebase(branch: String, commits: Int)
		/// Replacing the commit at the tip.
		case amend
		/// Removing a branch that holds commits nothing else does.
		case deleteBranch(String, ahead: Int)
		/// Pointing a tag somewhere else.
		case moveTag(String, from: String)
		/// Writing over commits on a remote.
		case forcePush(branch: String, overwriting: Int)
	}

	/// One of the ways out of a dialog.
	public struct Choice: Sendable, Equatable {
		public let title: String
		public let detail: String
		/// Whether taking this leaves everything recoverable.
		public let losesNothing: Bool

		/// **Only the safe choice may be remembered.** `Always stash and
		/// switch` can be ticked because what it remembers loses nothing;
		/// `Always discard` cannot be, ever. That line is the whole of what
		/// keeps the checkbox honest — a remembered destructive answer is this
		/// feature with the dialog taken out.
		public var mayBeRemembered: Bool { losesNothing }

		public init(title: String, detail: String, losesNothing: Bool) {
			self.title = title
			self.detail = detail
			self.losesNothing = losesNothing
		}
	}

	/// What goes on screen before an operation runs.
	public struct Ask: Sendable, Equatable {
		/// Leads with a number. "4 commits leave main" is read; "this cannot be
		/// undone" is not.
		public let title: String
		public let detail: String
		/// In order, safest first, so the default is the one that loses least.
		public let choices: [Choice]
		/// The branch this will leave behind, or nil when nothing here can
		/// insure it.
		public let backup: String?

		public init(title: String, detail: String, choices: [Choice], backup: String?) {
			self.title = title
			self.detail = detail
			self.choices = choices
			self.backup = backup
		}
	}

	/// What to say, and what to keep, before doing this.
	public static func ask(before operation: Operation, at moment: Date) -> Ask {
		switch operation {
		case let .switchBranch(branch, changed):
			return Ask(
				title: "\(files(changed)) would be overwritten by “\(branch)”",
				detail: "git will not switch over them.",
				choices: [
					Choice(
						title: "Stash and Switch",
						detail: "Put them aside and back again when you come back to this branch.",
						losesNothing: true
					),
					Choice(
						title: "Switch and Leave Them Behind",
						detail: "Kept on a backup branch, and gone from the working copy.",
						losesNothing: false
					),
				],
				backup: GitBackup.name(for: "wip", at: moment)
			)

		case let .discard(files: count, untracked: untracked):
			// The untracked half said separately, because restoring a tracked
			// file and deleting one git has never seen are different acts and
			// only one of them is what "discard" sounds like.
			let deleted = untracked > 0
				? " \(files(untracked)) git has never seen will be deleted."
				: ""
			return Ask(
				title: "Throw away \(files(count))?",
				detail: "They go back to what the index holds.\(deleted)",
				choices: [
					Choice(
						title: "Discard",
						detail: "Kept on a backup branch first.",
						losesNothing: false
					),
				],
				backup: GitBackup.name(for: "wip", at: moment)
			)

		case let .reset(target, commits, mode):
			let keeps = mode == .hard
				? "The working copy goes back with it."
				: "The working copy keeps what it has."
			return Ask(
				title: "\(count(commits, "commit")) \(commits == 1 ? "leaves" : "leave") this branch",
				detail: "It moves to \(target). \(keeps)",
				choices: [
					Choice(
						title: "Reset",
						detail: "The commits stay on a backup branch.",
						losesNothing: false
					),
				],
				backup: GitBackup.name(for: "reset", at: moment)
			)

		case let .rebase(branch, commits):
			return Ask(
				title: "\(count(commits, "commit")) will be replayed",
				detail: "Rebasing rewrites them, so “\(branch)” will not hold the same commits "
					+ "afterwards.",
				choices: [
					Choice(
						title: "Rebase",
						detail: "The originals stay on a backup branch.",
						losesNothing: false
					),
				],
				backup: GitBackup.name(for: branch, at: moment)
			)

		case .amend:
			// No dialog worth the interruption: amending is a deliberate act
			// somebody has just chosen, and the branch behind it is silent
			// insurance rather than a question.
			return Ask(
				title: "Amend the last commit",
				detail: "The commit being replaced is kept on a backup branch.",
				choices: [
					Choice(title: "Amend", detail: "", losesNothing: false),
				],
				backup: GitBackup.name(for: "amend", at: moment)
			)

		case let .deleteBranch(name, ahead):
			// Level with everything else, a branch is a name and deleting it
			// takes nothing — so this is not the same question at all.
			guard ahead > 0 else {
				return Ask(
					title: "Delete “\(name)”?",
					detail: "Everything on it is on another branch too.",
					choices: [Choice(title: "Delete", detail: "", losesNothing: true)],
					backup: nil
				)
			}
			return Ask(
				title: "“\(name)” is \(count(ahead, "commit")) ahead",
				detail: "Nothing else holds them.",
				choices: [
					Choice(
						title: "Delete",
						detail: "The commits stay on a backup branch.",
						losesNothing: false
					),
				],
				backup: GitBackup.name(for: name, at: moment)
			)

		case let .moveTag(name, from):
			return Ask(
				title: "“\(name)” leaves \(from)",
				detail: "A moving tag is force-pushed, so whatever reads it will follow.",
				choices: [
					Choice(
						title: "Move",
						detail: "Where it points now is kept on a backup branch.",
						losesNothing: false
					),
				],
				backup: GitBackup.name(for: "tag-\(name)", at: moment)
			)

		case let .forcePush(branch, overwriting):
			// **The one that is not insured, and must not pretend to be.** No
			// ref on this machine can bring back somebody else's commits from a
			// remote, and claiming a backup here would be the worst untruth
			// this whole feature could tell.
			return Ask(
				title: "\(count(overwriting, "commit")) on the remote would be overwritten",
				detail: "“\(branch)” has diverged from it. Nothing here can bring them back.",
				choices: [
					Choice(
						title: "Force-push",
						detail: "There is no backup for what is on the remote.",
						losesNothing: false
					),
				],
				backup: nil
			)
		}
	}

	// MARK: - Words

	/// A count and its noun, agreeing. The verb beside it has to agree too, and
	/// does not come free: "1 commit leave this branch" is the shape of mistake
	/// that survives review and reads as carelessness in a dialog somebody is
	/// being asked to trust.
	private static func count(_ n: Int, _ noun: String) -> String {
		"\(n) \(noun)\(n == 1 ? "" : "s")"
	}

	private static func files(_ n: Int) -> String {
		count(n, "changed file")
	}
}

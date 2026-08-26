import Foundation

/// Checking a pull request's branch out beside the project, and finishing with
/// it again.
///
/// **This is most of why a review belongs in an editor.** The language server,
/// go-to-definition, the outline and the tests all need the code on disk. A
/// worktree rather than a checkout in place because a review arrives while
/// something else is half-done — the branch must not move under it — and
/// because two pull requests open at once is what a blocked morning looks like.
public enum PullRequestCheckout {
	/// The local branch a pull request is fetched onto.
	///
	/// Named for the number and not for `headRefName`. A pull request from a
	/// fork has a head branch called `patch-1` — as do the other four open
	/// against the same repository — and two of those cannot both be `patch-1`
	/// here. The number is the one name that is unambiguous.
	public static func branchName(for number: Int) -> String { "pr-\(number)" }

	/// Where the checkout goes: beside the repository, as every other worktree
	/// this program makes does.
	public static func path(for number: Int, in root: URL) -> URL {
		GitWorktrees.suggestedPath(for: branchName(for: number), root: root)
	}

	/// Checks the pull request out as a worktree, and answers with where it is.
	///
	/// **Through `refs/pull/N/head` and not through the branch name.** The
	/// branch of a pull request from a fork is not in this repository at all, so
	/// fetching `headRefName` finds nothing — or worse, finds a *different*
	/// branch of the same name that somebody here happens to have. GitHub serves
	/// every pull request's head under `refs/pull/<number>/head`, fork or not,
	/// which is one path that always works.
	public static func checkOut(
		_ number: Int, in root: URL
	) async -> ForgeReply<URL> {
		guard await GitForge.repository(in: root) != nil else {
			return .unavailable(.noGitHubRemote)
		}
		let directory = path(for: number, in: root)
		let branch = branchName(for: number)

		// Already there: opening it again is what somebody means by asking
		// twice, and re-fetching onto a checked-out branch would fail anyway.
		if let existing = await GitWorktrees.list(in: root).first(where: {
			$0.path.standardizedFileURL == directory.standardizedFileURL
		}) {
			return .answered(existing.path)
		}

		// `+` so a force-push on the pull request updates the branch here rather
		// than failing on a non-fast-forward. It is a branch this program made
		// to read somebody else's work, and the author's history is the truth
		// about it.
		let fetched = await GitRepository.run(
			["fetch", "origin", "+refs/pull/\(number)/head:refs/heads/\(branch)"], in: root
		)
		guard fetched.exitCode == 0 else {
			return .failed(said(fetched, instead: "The pull request's head could not be fetched."))
		}

		let added = await GitWorktrees.add(
			at: directory, branch: branch, createBranch: false, in: root
		)
		guard added.exitCode == 0 else {
			return .failed(said(added, instead: "The checkout could not be made."))
		}
		return .answered(directory)
	}

	/// Removes a checkout made for a pull request.
	///
	/// **A checkout holding changes refuses rather than discarding them**, which
	/// is the rule the branches pane already keeps, whoever made the checkout.
	/// What is in it is said, because "it refused" without a reason is a wall.
	public static func finish(
		with number: Int, in root: URL
	) async -> ForgeReply<Void> {
		let directory = path(for: number, in: root)
		guard let worktree = await GitWorktrees.list(in: root).first(where: {
			$0.path.standardizedFileURL == directory.standardizedFileURL
		}) else {
			return .failed("There is no checkout of #\(number) to finish with.")
		}

		let removed = await GitWorktrees.remove(worktree, in: root)
		guard removed.exitCode != 0 else { return .answered(()) }

		// git refuses a worktree with changes in it and says so in its own
		// words. What is actually in there is a better sentence, and it is one
		// question away.
		let status = await GitRepository.run(
			["status", "--porcelain"], in: worktree.path
		)
		let changed = status.stdout
			.split(separator: "\n")
			.map { $0.dropFirst(3) }
			.prefix(4)
			.joined(separator: ", ")
		guard !changed.isEmpty else {
			return .failed(said(removed, instead: "The checkout could not be removed."))
		}
		return .failed("The checkout of #\(number) has changes in it: \(changed).")
	}

	private static func said(
		_ result: GitRepository.ProcessResult, instead: String
	) -> String {
		let complaint = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
		return complaint.isEmpty ? instead : complaint
	}
}

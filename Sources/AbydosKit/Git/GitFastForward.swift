import Foundation

/// Moving a branch up to its upstream without checking it out.
///
/// The branch somebody wants to bring up to date is very often not the one they
/// are standing on: `main` sits four behind while the work happens on a feature
/// branch, and the only way to advance it was to check it out, pull, and check
/// the feature branch back out again — three operations, a working copy touched
/// twice, and a stash in the middle if anything was uncommitted.
///
/// `git fetch . <upstream>:<branch>` does it in one, without touching the
/// working copy or the branch that is checked out. The local repository is used
/// as the remote, so nothing goes over the network: the commits are already
/// here, in a remote-tracking ref that a fetch brought down earlier.
public enum GitFastForward {
	/// What happened, or why nothing did.
	public enum Outcome: Sendable, Equatable {
		/// The branch moved, and by how many commits.
		case moved(commits: Int)
		/// It was already at its upstream.
		case alreadyThere
		/// There is no upstream to move towards.
		case noUpstream
		/// Local commits are not on the upstream, so moving the branch would
		/// lose them. This is the case the whole thing has to get right.
		case diverged(ahead: Int)
		/// The branch is checked out here, where fast-forwarding is a pull.
		case checkedOut
		/// git refused, and this is what it said.
		case refused(String)
	}

	/// Brings a branch up to its upstream, without checking it out.
	///
    /// **The refusal is decided before the fetch, and not from its exit code.**
	/// git does refuse a non-fast-forward and does exit non-zero for it — that
	/// was checked rather than assumed — but all it leaves behind is a line of
	/// prose:
	///
	///     ! [rejected] origin/main -> main  (non-fast-forward)
	///
	/// Asking `merge-base --is-ancestor` first turns that into an answer with a
	/// number in it: `.diverged(ahead: 1)`, which a caller can put in a sentence
	/// without parsing anybody's wording. A wording is one version of one
	/// program's phrasing — the rule `DiagnosticWeight` states about
	/// `No such module` — and this one is worth not depending on.
	///
	/// Where the ref ends up is checked afterwards as well. That is belt and
	/// braces rather than distrust: it costs one `rev-parse`, and it is the
	/// difference between reporting that a branch advanced and knowing it.
	public static func advance(
		branch: String, to upstream: String, in root: URL
	) async -> Outcome {
		guard !branch.isEmpty, !upstream.isEmpty else { return .noUpstream }

		// Refusing to move the checked-out branch rather than letting git refuse
		// it: `fetch` into the current branch fails with a message about the
		// index, which is true and unhelpful. Bringing the branch you are
		// standing on up to date is a pull, and there is one.
		if await currentBranch(in: root) == branch { return .checkedOut }

		guard let before = await commit(of: "refs/heads/\(branch)", in: root) else {
			return .refused("There is no branch called \(branch).")
		}
		guard await commit(of: upstream, in: root) != nil else { return .noUpstream }

		if before == (await commit(of: upstream, in: root)) { return .alreadyThere }

		// The one question that decides whether this is safe: is everything on
		// the branch already on the upstream? If not, moving the ref would leave
		// commits reachable from nothing.
		let contained = await GitRepository.run(
			["merge-base", "--is-ancestor", branch, upstream], in: root
		)
		guard contained.exitCode == 0 else {
			let ahead = await count(of: "\(upstream)..\(branch)", in: root)
			return .diverged(ahead: ahead)
		}

		let distance = await count(of: "\(branch)..\(upstream)", in: root)

		// `.` as the remote: the commits are already in this repository, in the
		// remote-tracking ref. Nothing goes over the network, and no credential
		// is wanted.
		let result = await GitRepository.run(
			["fetch", ".", "\(upstream):refs/heads/\(branch)"], in: root
		)

		// Asked of the ref as well as the exit code: the outcome says how far it
		// moved, and the only thing that really knows that is the ref.
		guard let after = await commit(of: "refs/heads/\(branch)", in: root), after != before else {
			let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
			return .refused(said.isEmpty ? "The branch did not move." : said)
		}
		return .moved(commits: distance)
	}

	/// The same, working out the upstream from the branch.
	///
    /// `@{upstream}` is git's own name for it, so a branch tracking something
	/// other than `origin/<same name>` is handled without this having to guess.
	public static func advance(branch: String, in root: URL) async -> Outcome {
		let named = await GitRepository.run(
			["rev-parse", "--abbrev-ref", "--verify", "--quiet", "\(branch)@{upstream}"], in: root
		)
		let upstream = named.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard named.exitCode == 0, !upstream.isEmpty else { return .noUpstream }
		return await advance(branch: branch, to: upstream, in: root)
	}

	// MARK: - Asking git small questions

	private static func commit(of reference: String, in root: URL) async -> String? {
		let result = await GitRepository.run(
			["rev-parse", "--verify", "--quiet", reference], in: root
		)
		let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return result.exitCode == 0 && !hash.isEmpty ? hash : nil
	}

	private static func count(of range: String, in root: URL) async -> Int {
		let result = await GitRepository.run(["rev-list", "--count", range], in: root)
		return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
	}

	private static func currentBranch(in root: URL) async -> String? {
		await GitRepository.head(in: root).name
	}
}

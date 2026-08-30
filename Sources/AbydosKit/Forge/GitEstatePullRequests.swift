import Foundation

/// What a review has decided about a pull request, as `gh` reports it.
public enum ReviewDecision: String, Sendable, Equatable {
	case approved = "APPROVED"
	case changesRequested = "CHANGES_REQUESTED"
	case reviewRequired = "REVIEW_REQUIRED"
	/// Nothing has been asked or said. `gh` gives an empty string for this on a
	/// repository with no review rules, which is not the same as "approved".
	case undecided = ""
}

/// One repository's part in a set of pull requests raised together.
public struct PullRequestSetEntry: Sendable, Equatable, Identifiable {
	/// The submodule, or nil for the superproject.
	public let submodule: GitSubmodule?
	/// What to call this repository in a report.
	public let name: String
	/// The pull request on the set's branch, or nil where there is none.
	public let request: PullRequest?
	public let review: ReviewDecision
	public let isMerged: Bool
	/// Why this repository could not be asked, when it could not be.
	public let absence: ForgeAbsence?

	public var id: String { name }

	public init(
		submodule: GitSubmodule?,
		name: String,
		request: PullRequest? = nil,
		review: ReviewDecision = .undecided,
		isMerged: Bool = false,
		absence: ForgeAbsence? = nil
	) {
		self.submodule = submodule
		self.name = name
		self.request = request
		self.review = review
		self.isMerged = isMerged
		self.absence = absence
	}

	/// What this row is chiefly saying, which is also what orders the set.
	public enum State: Sendable, Equatable {
		case failing
		case changesRequested
		case awaitingReview
		case approved
		case merged
		case draft
		case none
		case unavailable

		var rank: Int {
			switch self {
			case .failing:          return 0
			case .changesRequested: return 1
			case .awaitingReview:   return 2
			case .approved:         return 3
			case .draft:            return 4
			case .unavailable:      return 5
			case .none:             return 6
			case .merged:           return 7
			}
		}
	}

	public var state: State {
		if absence != nil { return .unavailable }
		guard let request else { return .none }
		if isMerged { return .merged }
		// Red first, and before draft: a draft whose build is broken is still a
		// broken build, and the question the set is opened to answer is what is
		// stopping it.
		if request.checks == .failing { return .failing }
		if review == .changesRequested { return .changesRequested }
		if request.isDraft { return .draft }
		if review == .approved { return .approved }
		return .awaitingReview
	}
}

/// A set of pull requests raised from one description across many repositories.
///
/// **Keyed by its branch, and its state is never stored.** A local record of
/// pull request numbers goes stale the moment somebody merges from the web, it
/// knows nothing on a second machine, and it becomes a file to reconcile after
/// every refactoring. The forge is the record; this reads it.
///
/// `gh search prs` would answer a whole set in one call and is not used: its
/// indexing lags by minutes, it is GitHub.com-shaped, and Enterprise hosts
/// differ. Asking each repository is slower and true.
public enum GitEstatePullRequests {
	/// How many `gh` calls may be in flight at once.
	///
	/// Sized separately from `GitEstateReader.concurrency`, which is a ceiling
	/// for `git` processes against one disk. These are network calls against,
	/// very likely, one forge — the limit that matters is the forge's, not this
	/// machine's, and a rate limit is what being wrong here looks like.
	public static let concurrency = 6

	/// The fields the set needs, which is more than the list page asks for:
	/// whether it merged, and what a review decided.
	static let fields = [
		"number", "title", "author", "headRefName", "baseRefName",
		"isDraft", "statusCheckRollup", "updatedAt", "url",
		"state", "reviewDecision",
	].joined(separator: ",")

	// MARK: - Reading a set

	/// Whether `gh` itself can be used at all, asked once for the whole estate.
	///
	/// **`GitHubCLI.availability` runs `gh auth status`, and that is a process.**
	/// Asked per repository it is two hundred `gh` invocations to answer a
	/// question with one answer: the CLI is installed or it is not, and it is
	/// logged in to the host or it is not, and neither is a fact about a
	/// submodule. Only "this repository has no GitHub remote" is per repository,
	/// and that is `git config remote.origin.url` — a git call, cheap, and
	/// already what `GitForge.repository(in:)` asks.
	///
	/// The same mistake the recursive `git status` was, in a more expensive
	/// currency: `gh` is a Go binary and starting one is not free.
	static func sharedAbsence(in estate: GitEstate) async -> ForgeAbsence? {
		guard GitHubCLI.locate() != nil else { return .cliNotInstalled }
		guard let repository = await GitForge.repository(in: estate.root) else {
			// The superproject has no GitHub remote, but its submodules may
			// have; that is the per-repository check's to answer.
			return nil
		}
		let status = await GitHubCLI.run(
			["auth", "status", "--hostname", repository.host], in: estate.root
		)
		return status.exitCode == 0 ? nil : .cliNotLoggedIn(host: repository.host)
	}

	/// Every repository in the estate, and its pull request on this branch.
	public static func set(
		onBranch branch: String, in estate: GitEstate
	) async -> [PullRequestSetEntry] {
		let shared = await sharedAbsence(in: estate)

		let repositories: [(submodule: GitSubmodule?, name: String, root: URL)] =
			[(nil, ".", estate.root)]
			+ estate.submodules.filter(\.isCheckedOut).map {
				($0, $0.path, estate.root.appendingPathComponent($0.path))
			}

		var entries = await withTaskGroup(
			of: PullRequestSetEntry.self
		) { group -> [PullRequestSetEntry] in
			var next = 0
			var collected: [PullRequestSetEntry] = []

			func addWork() -> Bool {
				guard next < repositories.count, !Task.isCancelled else { return false }
				let repository = repositories[next]
				next += 1
				group.addTask {
					await entry(
						onBranch: branch,
						submodule: repository.submodule,
						name: repository.name,
						in: repository.root,
						shared: shared
					)
				}
				return true
			}

			for _ in 0..<min(concurrency, repositories.count) { _ = addWork() }
			while let made = await group.next() {
				collected.append(made)
				_ = addWork()
			}
			return collected
		}

		entries.sort {
			$0.state.rank != $1.state.rank
				? $0.state.rank < $1.state.rank
				: $0.name < $1.name
		}
		return entries
	}

	static func entry(
		onBranch branch: String,
		submodule: GitSubmodule?,
		name: String,
		in root: URL,
		shared: ForgeAbsence? = nil
	) async -> PullRequestSetEntry {
		// Installed and logged in are facts about the machine, answered once for
		// the estate. Only the remote is a fact about this repository, and
		// asking it is a git call rather than a `gh` one.
		if let shared {
			return PullRequestSetEntry(submodule: submodule, name: name, absence: shared)
		}
		guard await GitForge.repository(in: root) != nil else {
			return PullRequestSetEntry(
				submodule: submodule, name: name, absence: .noGitHubRemote
			)
		}

		// `--state all`, because a set is read to find out what is *finished*
		// as much as what is outstanding, and a merged one disappears from the
		// open list. `--head` is what makes the branch the key.
		let listed = await GitHubCLI.run(
			["pr", "list", "--head", branch, "--state", "all", "--limit", "5", "--json", fields],
			in: root
		)
		guard listed.exitCode == 0 else {
			return PullRequestSetEntry(submodule: submodule, name: name)
		}
		return decode(listed.stdout, submodule: submodule, name: name)
	}

	/// Reads one repository's answer.
	///
	/// The newest is taken when there is more than one — a branch reused after a
	/// merge has two, and the one somebody means is the one they just raised.
	static func decode(
		_ json: String, submodule: GitSubmodule?, name: String
	) -> PullRequestSetEntry {
		let requests = GitHubPullRequests.pullRequests(fromJSON: json)
		guard let request = requests.max(by: { $0.number < $1.number }) else {
			return PullRequestSetEntry(submodule: submodule, name: name)
		}

		let rows = GitHubPullRequests.arrays(from: json).flatMap { $0 }
		let row = rows.first { ($0["number"] as? Int) == request.number }
		let review = ReviewDecision(rawValue: row?["reviewDecision"] as? String ?? "") ?? .undecided
		let isMerged = (row?["state"] as? String)?.uppercased() == "MERGED"

		return PullRequestSetEntry(
			submodule: submodule, name: name,
			request: request, review: review, isMerged: isMerged
		)
	}

	// MARK: - Raising a set

	/// Opens a pull request in every repository that has commits on `branch`.
	///
	/// One title and one body for the lot: a refactoring across forty services
	/// is forty pull requests that say the same thing, and typing that
	/// description forty times is what this replaces.
	///
	/// **Skipped and already-open are outcomes, not failures.** A repository the
	/// refactoring did not touch has nothing on the branch and is said to be
	/// skipped; one that was raised yesterday is said to be already open, with
	/// its number. Reporting either as an error would make a normal set read as
	/// a broken one.
	///
	/// Serial rather than fanned out, unlike reading: these write, and a burst
	/// of forty creations is how a set gets rate limited half way through.
	@discardableResult
	public static func raise(
		onBranch branch: String,
		title: String,
		body: String,
		in estate: GitEstate,
		draft: Bool = false
	) async -> [GitEstateOutcome] {
		let shared = await sharedAbsence(in: estate)
		var outcomes: [GitEstateOutcome] = []

		// Deepest first, for the reason committing and pushing are: a review of
		// a repository that points at another is worth opening once the thing
		// it points at is there to be read.
		for submodule in estate.deepestFirst {
			let root = estate.root.appendingPathComponent(submodule.path)
			guard submodule.isCheckedOut else {
				outcomes.append(GitEstateOutcome(
					submodule: submodule, root: root, result: .skipped("not checked out")
				))
				continue
			}
			outcomes.append(await raise(
				onBranch: branch, title: title, body: body,
				submodule: submodule, in: root, draft: draft, shared: shared
			))
		}

		outcomes.sort { ($0.submodule?.path ?? "") < ($1.submodule?.path ?? "") }

		// The superproject last, because its pull request is the one that
		// records where the submodules got to, and that is only true once
		// theirs exist.
		outcomes.append(await raise(
			onBranch: branch, title: title, body: body,
			submodule: nil, in: estate.root, draft: draft, shared: shared
		))
		return outcomes
	}

	static func raise(
		onBranch branch: String,
		title: String,
		body: String,
		submodule: GitSubmodule?,
		in root: URL,
		draft: Bool,
		shared: ForgeAbsence? = nil
	) async -> GitEstateOutcome {
		let name = submodule?.path ?? "."

		// Written out rather than `??`, because the right-hand side is an
		// `await` and `??` takes an autoclosure that cannot hold one.
		var absence = shared
		if absence == nil, await GitForge.repository(in: root) == nil {
			absence = .noGitHubRemote
		}
		if let absence {
			return GitEstateOutcome(
				submodule: submodule, root: root,
				result: .skipped(absence.summary)
			)
		}

		// Nothing on the branch is the ordinary case for most of an estate: a
		// refactoring touches forty services out of two hundred.
		guard await hasCommits(onBranch: branch, in: root) else {
			return GitEstateOutcome(
				submodule: submodule, root: root,
				result: .skipped("nothing on \(branch)")
			)
		}

		// Asked before creating rather than after failing, so "already open" is
		// a sentence about the set and not `gh`'s error text.
		let existing = await entry(onBranch: branch, submodule: submodule, name: name, in: root)
		if let already = existing.request {
			return GitEstateOutcome(
				submodule: submodule, root: root,
				result: .skipped("already open #\(already.number)")
			)
		}

		var arguments = ["pr", "create", "--head", branch, "--title", title, "--body", body]
		if draft { arguments.append("--draft") }
		let created = await GitHubCLI.run(arguments, in: root)
		guard created.exitCode == 0 else {
			return GitEstateOutcome(
				submodule: submodule, root: root,
				result: .failed(GitEstateOperation.complaint(created))
			)
		}
		return GitEstateOutcome(
			submodule: submodule, root: root,
			result: .done(created.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
		)
	}

	/// Whether this repository has anything on the branch that its default
	/// branch does not.
	///
	/// A branch that exists and matches the default has nothing to propose, and
	/// a pull request for it would be an empty one somebody has to close.
	static func hasCommits(onBranch branch: String, in root: URL) async -> Bool {
		let base = await BranchGrouping.defaultBranch(in: root) ?? "main"
		guard branch != base else { return false }
		let counted = await GitRepository.run(
			["rev-list", "--count", "\(base)..\(branch)"], in: root
		)
		guard counted.exitCode == 0 else { return false }
		let text = counted.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return (Int(text) ?? 0) > 0
	}

	// MARK: - What the set says about itself

	/// How far along the set is, in one sentence somebody can act on.
	///
	/// The question a set is opened to answer is what is left, and counting
	/// forty rows by hand is what a spreadsheet is doing today.
	public static func summary(of entries: [PullRequestSetEntry]) -> String {
		guard !entries.isEmpty else { return "no repositories" }
		var parts: [String] = []
		func say(_ state: PullRequestSetEntry.State, _ what: String) {
			let count = entries.filter { $0.state == state }.count
			guard count > 0 else { return }
			parts.append("\(count) \(what)")
		}
		say(.failing, "failing")
		say(.changesRequested, "changes requested")
		say(.awaitingReview, "awaiting review")
		say(.approved, "approved and unmerged")
		say(.draft, "draft")
		say(.merged, "merged")
		say(.unavailable, "could not be asked")

		let none = entries.filter { $0.state == .none }.count
		if none > 0 { parts.append("\(none) with none raised") }

		guard !parts.isEmpty else { return "nothing raised yet" }
		// A set whose every pull request has merged is finished, and says so
		// rather than reading as an empty list.
		if entries.allSatisfy({ $0.state == .merged }) {
			return "all \(entries.count) merged"
		}
		return parts.joined(separator: " · ")
	}
}

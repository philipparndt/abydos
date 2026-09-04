import Foundation

/// One ref the branches view can list.
public struct GitBranch: Equatable, Sendable, Identifiable {
	public enum Kind: Sendable, Equatable {
		case local
		/// Remote-tracking, carrying the remote's name.
		case remote(String)
		case tag
	}

	/// Short name: `main`, or `feature/x` — without the remote prefix.
	public let name: String
	public let kind: Kind
	public let isCurrent: Bool
	/// Subject of the commit it points at, shown as a hint.
	public let subject: String
	/// How far ahead of and behind its upstream, when it has one.
	public let ahead: Int
	public let behind: Int
	/// The branch it tracks, or nil when it has never been pushed.
	///
	/// Not the same as being in step with it: a branch level with its upstream
	/// and a branch that has no upstream both count nothing, and only one of
	/// them has somewhere to push to.
	public let upstream: String?
	/// The branch tracks an upstream that no longer exists — the ordinary end
	/// of a branch whose pull request was merged and whose remote branch went
	/// with it.
	///
	/// **Not the same as level, and it parses as level.**
	/// `%(upstream:track)` says `[gone]` where it would otherwise say the
	/// counts, so both come back nought and a row reading only the counts calls
	/// the branch in step with a ref that is not there.
	public let upstreamIsGone: Bool

	/// How far this branch is from the repository's default branch.
	///
	/// Nil when nobody asked, or when the two share no history. Separate from
	/// `ahead` and `behind`, which are about the upstream and answer a
	/// different question: *is my copy of this branch in step with everybody
	/// else's*, rather than *how much work is on it*.
	public let aheadOfDefault: Int?
	public let behindDefault: Int?

	/// When the ref came to be: the tag object's date for an annotated tag,
	/// the pointed-at commit's for a lightweight one, the tip commit's for a
	/// branch — `creatordate`, which is the field a newest-first order reads.
	/// Nil on a git old enough to refuse the field, costing the order and not
	/// the rows.
	public let created: Date?

	/// Never pushed anywhere: a local branch with no upstream at all.
	///
	/// Told apart from level for the reason `upstream` already gives, and said
	/// out loud on the row because nothing else does. A tag has no upstream by
	/// definition and a remote-tracking branch is the upstream, so neither is
	/// ever unpublished.
	public var isUnpublished: Bool {
		guard case .local = kind else { return false }
		return upstream == nil
	}

	public var id: String {
		switch kind {
		case .local:            return "local:\(name)"
		case .remote(let remote): return "remote:\(remote)/\(name)"
		case .tag:              return "tag:\(name)"
		}
	}

	/// What `git checkout` should be given.
	public var checkoutName: String {
		switch kind {
		case .local, .tag:        return name
		case .remote(let remote): return "\(remote)/\(name)"
		}
	}

	public init(
		name: String,
		kind: Kind,
		isCurrent: Bool = false,
		subject: String = "",
		ahead: Int = 0,
		behind: Int = 0,
		upstream: String? = nil,
		upstreamIsGone: Bool = false,
		aheadOfDefault: Int? = nil,
		behindDefault: Int? = nil,
		created: Date? = nil
	) {
		self.name = name
		self.kind = kind
		self.isCurrent = isCurrent
		self.subject = subject
		self.ahead = ahead
		self.behind = behind
		self.upstream = upstream
		self.upstreamIsGone = upstreamIsGone
		self.aheadOfDefault = aheadOfDefault
		self.behindDefault = behindDefault
		self.created = created
	}
}

/// How a refs-tree section orders the refs in it.
///
/// One choice per section *kind* — local, remotes, tags — because that is
/// what the section headers offer, and a per-remote memory would multiply
/// keys for a question nobody asks per remote. The raw values are what the
/// Settings keys store.
public enum RefsSortOrder: String, CaseIterable, Sendable {
	/// `localizedStandardCompare` on the display name — the order the project
	/// tree and the changes tree use, and the branches' default.
	case name
	/// Newest `creatordate` first — the tags' default: the tag somebody just
	/// cut is the one they are looking for, and alphabetical order lies about
	/// versions besides (`v1.10` before `v1.9`).
	case newestFirst = "created"

	/// The order between two refs. Newest-first falls back to the name for an
	/// undated pair, so a git old enough to refuse `creatordate` still gets
	/// one stable answer.
	public func orderedBefore(_ a: GitBranch, _ b: GitBranch) -> Bool {
		switch self {
		case .name:
			return a.name.localizedStandardCompare(b.name) == .orderedAscending
		case .newestFirst:
			let first = a.created ?? .distantPast
			let second = b.created ?? .distantPast
			if first != second { return first > second }
			return a.name.localizedStandardCompare(b.name) == .orderedAscending
		}
	}
}

/// Listing and switching branches.
public enum GitBranches {
	/// Field separator for `--format`. Chosen because it cannot occur in a ref
	/// name or a commit subject.
	private static let separator = "\u{1F}"

	/// The local branches whose commits are all in `branch`.
	///
	/// **A set of names rather than a fact per branch**, and answered by one
	/// `git branch --merged` alongside the reads the pane already does. A
	/// branch the answer does not cover — because the read failed, or has not
	/// come back, or there is no default branch to compare against — is simply
	/// not in the set, so a slow or failed answer costs appearance rather than
	/// correctness.
	///
	/// The branch itself is always in git's answer, being trivially merged into
	/// itself, and is taken out here: *finished, nothing on it that is not
	/// somewhere else* is not a thing to say about `main`.
	public static func merged(into branch: String, in root: URL) async -> Set<String> {
		let result = await GitRepository.run(
			["branch", "--merged", branch, "--format=%(refname:short)"], in: root
		)
		guard result.exitCode == 0 else { return [] }
		return Set(
			result.stdout
				.split(separator: "\n")
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty && $0 != branch }
		)
	}

	/// The remotes this repository has, in the order git lists them.
	///
	/// One process, and usually one answer. Asked rather than assumed: `origin`
	/// is a convention, not a rule, and a repository with a fork remote beside
	/// it has two defaults to measure against.
	public static func remotes(in root: URL) async -> [String] {
		let result = await GitRepository.run(["remote"], in: root)
		guard result.exitCode == 0 else { return [] }
		return result.stdout
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}

	/// The same question, asked of the remote-tracking branches.
	///
	/// **`git branch --merged` lists local branches only**, which is why the
	/// pane could mark a finished local branch and had nothing to say about the
	/// remote copy of the same work. `-r` is the whole difference.
	///
	/// - Parameter target: a *remote* branch — `origin/main`. Measuring
	///   `origin/x` against the local `main` answers a question nobody asked:
	///   the local default can be ahead of the remote's, and a branch that is
	///   merged there is not yet merged where deleting it would matter.
	///
	/// Names come back with their remote on them, as `%(refname:short)` gives
	/// them: `origin/x`. The caller keys by that, because a remote row's own
	/// `name` has the remote stripped and `origin/x` and `upstream/x` would
	/// otherwise be the same branch.
	public static func mergedRemotes(into target: String, in root: URL) async -> Set<String> {
		let result = await GitRepository.run(
			["branch", "-r", "--merged", target, "--format=%(refname:short)"], in: root
		)
		guard result.exitCode == 0 else { return [] }
		return Set(
			result.stdout
				.split(separator: "\n")
				.map { $0.trimmingCharacters(in: .whitespaces) }
				// `origin/HEAD` is a symbolic ref at the remote's default and is
				// trivially merged into it; it is not a branch anybody deletes.
				.filter { !$0.isEmpty && $0 != target && !$0.hasSuffix("/HEAD") }
		)
	}

	/// Deletes a branch on the remote.
	///
	/// **This is a push**, and the only one in this file. `git push origin
	/// --delete x` removes the ref from somebody else's machine, which is why
	/// the pane asks first and says out loud where the branch is going from.
	///
	/// `--delete` rather than the `:x` refspec: they do the same thing and only
	/// one of them can be read by somebody who has not memorised it.
	public static func deleteOnRemote(
		_ name: String, on remote: String, in root: URL
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(
			["push", remote, "--delete", name],
			in: root,
			environment: ["GIT_TERMINAL_PROMPT": "0"]
		)
	}

	/// Every ref worth a row, and how far each is from `comparedTo`.
	///
	/// - Parameter comparedTo: a branch to measure every ref against, usually
	///   the repository's default. **This is the only thing that can say
	///   anything about a branch that has never been pushed** — its upstream
	///   counts are empty because it has no upstream, and `0 ahead, 0 behind`
	///   is what a branch in step with a remote reads. What somebody wants to
	///   know about a branch of their own is how far it has come from the
	///   branch it will go back into.
	///
	///   Asked with `%(ahead-behind:)`, in the call that was already being
	///   made rather than one `rev-list` per branch.
	public static func list(in root: URL, comparedTo: String? = nil) async -> [GitBranch] {
		await list(in: root, comparedTo: comparedTo, withDates: true)
	}

	private static func list(
		in root: URL, comparedTo: String?, withDates: Bool
	) async -> [GitBranch] {
		var fields = [
			"%(refname)",
			"%(HEAD)",
			"%(contents:subject)",
			"%(upstream:track)",
			"%(upstream:short)",
		]
		// Before the ahead-behind field, so the date keeps one index whether
		// or not there is a branch to compare against.
		if withDates { fields.append("%(creatordate:unix)") }
		if let comparedTo { fields.append("%(ahead-behind:\(comparedTo))") }
		let format = fields.joined(separator: separator)

		async let branches = GitRepository.run(
			["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"],
			in: root
		)
		async let tags = GitRepository.run(
			// Tags sorted newest first: an old tag is rarely what anyone is
			// looking for, and a repository can have thousands.
			["for-each-ref", "--format=\(format)", "--sort=-creatordate",
			 "--count=100", "refs/tags"],
			in: root
		)

		let listed = await branches
		// **`%(ahead-behind:)` arrived in git 2.41, and an older git refuses
		// the whole command over it** — not the one field, the list. A branch
		// pane that went empty on an older git would be this asking for a nicer
		// number and taking every row away to get it. The same care for
		// `%(creatordate:unix)`, which is far older but guarded the same way:
		// a git that refuses it costs the dates, never the rows.
		guard listed.exitCode == 0 else {
			if comparedTo != nil { return await list(in: root, comparedTo: nil, withDates: withDates) }
			if withDates { return await list(in: root, comparedTo: nil, withDates: false) }
			return []
		}

		var result = parse(listed.stdout, withDates: withDates)
		result += parse(await tags.stdout, withDates: withDates)
		return result
	}

	/// Parses `for-each-ref` output.
	///
	/// Internal so the ref-name rules can be tested against fixtures — there
	/// are more shapes than they look: remotes nest, branch names contain
	/// slashes, and `origin/HEAD` is a symbolic ref rather than a branch.
	static func parse(_ output: String, withDates: Bool = true) -> [GitBranch] {
		var result: [GitBranch] = []

		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			let fields = line.components(separatedBy: separator)
			guard fields.count >= 2 else { continue }

			let refname = fields[0]
			let isCurrent = fields[1] == "*"
			let subject = fields.count > 2 ? fields[2] : ""
			let track = fields.count > 3 ? fields[3] : ""
			let upstream = fields.count > 4 && !fields[4].isEmpty ? fields[4] : nil
			let created: Date? = withDates && fields.count > 5
				? TimeInterval(fields[5]).map { Date(timeIntervalSince1970: $0) }
				: nil
			// `%(ahead-behind:)` prints two numbers separated by a space, and
			// prints nothing at all for a ref that shares no history with what
			// it was compared against. Its index moves with the date field.
			let againstIndex = withDates ? 6 : 5
			let against = fields.count > againstIndex
				? fields[againstIndex].split(separator: " ").compactMap { Int($0) }
				: []

			guard let (name, kind) = classify(refname: refname) else { continue }
			let counts = parseTracking(track)
			let isGone = upstream != nil && track.contains("gone")

			result.append(GitBranch(
				name: name,
				kind: kind,
				isCurrent: isCurrent,
				subject: subject,
				ahead: counts.ahead,
				behind: counts.behind,
				upstream: upstream,
				upstreamIsGone: isGone,
				aheadOfDefault: against.count == 2 ? against[0] : nil,
				behindDefault: against.count == 2 ? against[1] : nil,
				created: created
			))
		}
		return result
	}

	static func classify(refname: String) -> (name: String, kind: GitBranch.Kind)? {
		if refname.hasPrefix("refs/heads/") {
			return (String(refname.dropFirst("refs/heads/".count)), .local)
		}
		if refname.hasPrefix("refs/tags/") {
			return (String(refname.dropFirst("refs/tags/".count)), .tag)
		}
		guard refname.hasPrefix("refs/remotes/") else { return nil }

		let rest = String(refname.dropFirst("refs/remotes/".count))
		// The first component is the remote; everything after it is the branch,
		// which may itself contain slashes.
		guard let slash = rest.firstIndex(of: "/") else { return nil }
		let remote = String(rest[rest.startIndex..<slash])
		let name = String(rest[rest.index(after: slash)...])

		// `origin/HEAD` is a symbolic ref pointing at the default branch, not a
		// branch of its own; listing it would offer a duplicate checkout.
		guard name != "HEAD" else { return nil }
		return (name, .remote(remote))
	}

	/// Reads `%(upstream:track)`, which looks like `[ahead 2, behind 1]`.
	static func parseTracking(_ track: String) -> (ahead: Int, behind: Int) {
		var ahead = 0
		var behind = 0

		let trimmed = track.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
		for part in trimmed.components(separatedBy: ",") {
			let fields = part.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
			guard fields.count == 2, let value = Int(fields[1]) else { continue }
			if fields[0] == "ahead" { ahead = value }
			if fields[0] == "behind" { behind = value }
		}
		return (ahead, behind)
	}

	// MARK: - Operations

	@discardableResult
	public static func checkout(_ branch: GitBranch, in root: URL) async -> GitRepository.ProcessResult {
		switch branch.kind {
		case .local, .tag:
			return await GitRepository.run(["checkout", branch.checkoutName], in: root)
		case .remote:
			// Checking out a remote ref directly detaches HEAD. Creating the
			// local branch that tracks it is what anyone actually means.
			let local = await GitRepository.run(["checkout", branch.name], in: root)
			if local.exitCode == 0 { return local }
			return await GitRepository.run(
				["checkout", "-b", branch.name, "--track", branch.checkoutName],
				in: root
			)
		}
	}

	@discardableResult
	public static func create(
		_ name: String,
		from start: String?,
		checkout: Bool,
		in root: URL
	) async -> GitRepository.ProcessResult {
		var arguments = checkout ? ["checkout", "-b", name] : ["branch", name]
		if let start, !start.isEmpty { arguments.append(start) }
		return await GitRepository.run(arguments, in: root)
	}

	/// Deletes a local branch. `force` discards unmerged work.
	@discardableResult
	public static func delete(
		_ name: String,
		force: Bool,
		in root: URL
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(["branch", force ? "-D" : "-d", name], in: root)
	}

	/// Whether every commit on `branch` is already on `target`.
	///
	/// **`merge-base --is-ancestor`, and not `git branch -d`'s opinion.** The
	/// house rules record why: `-d` refuses a branch that is merged into `main`
	/// while sitting ahead of its own *stale* upstream ref — it says "not fully
	/// merged" and means "your `origin/<branch>` is behind". Asking about
	/// ancestry is the question that decides whether deleting loses anything.
	public static func isMerged(_ branch: String, into target: String, in root: URL) async -> Bool {
		await GitRepository.run(
			["merge-base", "--is-ancestor", branch, target], in: root
		).exitCode == 0
	}

	@discardableResult
	public static func merge(_ name: String, in root: URL) async -> GitRepository.ProcessResult {
		await GitRepository.run(["merge", "--no-edit", name], in: root)
	}

	/// Replays the branch that is checked out onto another one.
	///
	/// **The current branch moves, and the named one does not.** `git rebase
	/// main` from `feature` takes feature's commits off and puts them back on
	/// top of main, so the row somebody right-clicks is the *destination* —
	/// which is why the menu item names it and says "on".
	///
	/// No `--autostash`: a working copy with changes in it makes git refuse,
	/// and a refusal that says so is better than this quietly stashing
	/// somebody's work and handing it back afterwards, which is a second thing
	/// to go wrong halfway through a rebase. The pane says what git said.
	///
	/// A conflict leaves the repository mid-rebase, which `GitConflicts` already
	/// recognises — `.rebase` is one of the states it reads, and the conflict
	/// list already knows that "ours" and "theirs" are the other way round
	/// there.
	public static func rebase(onto name: String, in root: URL) async -> GitRepository.ProcessResult {
		await GitRepository.run(["rebase", name], in: root)
	}

	/// A branch name git will accept, or nil with the reason it will not.
	///
	/// Checked before running anything so the failure is a sentence rather than
	/// git's own message about ref formats.
	public static func validationError(forName name: String) -> String? {
		let trimmed = name.trimmingCharacters(in: .whitespaces)
		if trimmed.isEmpty { return "A branch needs a name." }
		if trimmed.hasPrefix("-") { return "A branch name cannot start with a dash." }
		if trimmed.hasPrefix("/") || trimmed.hasSuffix("/") {
			return "A branch name cannot start or end with a slash."
		}
		if trimmed.hasSuffix(".lock") { return "A branch name cannot end with .lock." }
		if trimmed.contains("..") { return "A branch name cannot contain two dots in a row." }
		if trimmed.contains("//") { return "A branch name cannot contain two slashes in a row." }

		let forbidden = CharacterSet(charactersIn: " ~^:?*[\\\u{7F}")
		if trimmed.rangeOfCharacter(from: forbidden) != nil {
			return "A branch name cannot contain spaces or any of ~ ^ : ? * [ \\"
		}
		return nil
	}
}

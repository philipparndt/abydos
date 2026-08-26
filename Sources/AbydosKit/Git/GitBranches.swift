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
		upstreamIsGone: Bool = false
	) {
		self.name = name
		self.kind = kind
		self.isCurrent = isCurrent
		self.subject = subject
		self.ahead = ahead
		self.behind = behind
		self.upstream = upstream
		self.upstreamIsGone = upstreamIsGone
	}
}

/// Listing and switching branches.
public enum GitBranches {
	/// Field separator for `--format`. Chosen because it cannot occur in a ref
	/// name or a commit subject.
	private static let separator = "\u{1F}"

	public static func list(in root: URL) async -> [GitBranch] {
		let format = [
			"%(refname)",
			"%(HEAD)",
			"%(contents:subject)",
			"%(upstream:track)",
			"%(upstream:short)",
		].joined(separator: separator)

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

		var result = parse(await branches.stdout)
		result += parse(await tags.stdout)
		return result
	}

	/// Parses `for-each-ref` output.
	///
	/// Internal so the ref-name rules can be tested against fixtures — there
	/// are more shapes than they look: remotes nest, branch names contain
	/// slashes, and `origin/HEAD` is a symbolic ref rather than a branch.
	static func parse(_ output: String) -> [GitBranch] {
		var result: [GitBranch] = []

		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			let fields = line.components(separatedBy: separator)
			guard fields.count >= 2 else { continue }

			let refname = fields[0]
			let isCurrent = fields[1] == "*"
			let subject = fields.count > 2 ? fields[2] : ""
			let track = fields.count > 3 ? fields[3] : ""
			let upstream = fields.count > 4 && !fields[4].isEmpty ? fields[4] : nil

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
				upstreamIsGone: isGone
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

	@discardableResult
	public static func merge(_ name: String, in root: URL) async -> GitRepository.ProcessResult {
		await GitRepository.run(["merge", "--no-edit", name], in: root)
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

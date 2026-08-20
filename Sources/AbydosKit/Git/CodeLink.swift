import Foundation

/// A place in the code, said as a link somebody else can open.
///
/// Two forms, two audiences, and they fail in different ways.
///
/// A **reference** — `Sources/App/Main.swift:42` — costs nothing, needs no git
/// and no network, and is wrong the moment somebody inserts a line above 42.
/// That is acceptable for what it is used for: handed over now, acted on now.
/// `CodePlace` is that form and this type does not touch it.
///
/// A **permalink** — the forge's URL for a file at a commit — is right for ever,
/// because a commit does not change. It makes three promises this program cannot
/// keep on its own: that there is a remote, that the commit is on it, and that
/// the file on the forge is the file on screen. **All three can be checked here,
/// and the checking is most of the work** — because the two that fail are
/// invisible to whoever receives the link.
public enum CodeLink {
	/// A permalink, and whatever has to be said about it.
	public struct Permalink: Equatable, Sendable {
		public var url: URL
		/// The commit it names, short, for a sentence to quote.
		public var commit: String
		/// What the person copying this needs to know before they send it, and
		/// nil when there is nothing to say — which is the ordinary case.
		public var caveat: String?

		public init(url: URL, commit: String, caveat: String? = nil) {
			self.url = url
			self.commit = commit
			self.caveat = caveat
		}
	}

	/// What is true of the commit a permalink would name.
	///
	/// Answered from the refs in this checkout: **no fetch, no network, and
	/// never a push.** Pushing is somebody's own decision and not this app's,
	/// and a menu item that sometimes takes four seconds over the network is a
	/// menu item nobody presses twice.
	public struct State: Equatable, Sendable {
		/// The full commit id. A permalink names it in full: an abbreviation is
		/// a prefix that can stop being unique.
		public var commit: String
		/// Whether that commit can be found on any remote-tracking branch.
		public var isOnARemote: Bool
		/// Whether the file has changes that are not in that commit.
		public var isFileDirty: Bool

		public init(commit: String, isOnARemote: Bool, isFileDirty: Bool) {
			self.commit = commit
			self.isOnARemote = isOnARemote
			self.isFileDirty = isFileDirty
		}

		/// The commit as a sentence quotes it.
		public var shortCommit: String { String(commit.prefix(7)) }
	}

	/// Asks git the three questions, at once.
	///
	/// `path` is relative to the repository root, which is what git wants and
	/// what the forge serves.
	public static func state(
		of path: String, in repository: URL
	) async -> State? {
		async let head = GitRepository.run(["rev-parse", "HEAD"], in: repository)
		// **`branch --remotes --contains` and not `git fetch`.** The question is
		// whether the commit is on a remote as far as this checkout knows, which
		// is exactly the question that matters: a commit this checkout has never
		// seen pushed is one the recipient cannot open, and asking the network
		// would not change what is true right now.
		async let remotes = GitRepository.run(
			["branch", "--remotes", "--contains", "HEAD"], in: repository
		)
		// `--` so a path that looks like a revision is still a path.
		async let dirty = GitRepository.run(
			["status", "--porcelain", "--", path], in: repository
		)

		let commit = await head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard await head.exitCode == 0, !commit.isEmpty else {
			// No commits at all: an unborn branch has nothing to link to.
			_ = await remotes
			_ = await dirty
			return nil
		}
		let onARemote = await !remotes.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let changed = await !dirty.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		return State(commit: commit, isOnARemote: onARemote, isFileDirty: changed)
	}

	/// What has to be said about a link in this state, and nil when nothing has.
	///
	/// **Both sentences say what it means for *this link*, not what is true of
	/// the repository.** "Uncommitted changes" is a fact about a file and leaves
	/// the reader to work out what it does to their link; "the line on the forge
	/// is the line as of the commit, not the line on screen" is the consequence,
	/// which is the part that matters when somebody is about to paste it into a
	/// message.
	///
	/// Here rather than in a view, so that what is said can be read without a
	/// window — the rule `RenameAnswer` and `RenameSubject.caveat` already keep.
	public static func caveat(for state: State) -> String? {
		var said: [String] = []
		if !state.isOnARemote {
			said.append("Commit \(state.shortCommit) is not on the remote yet, "
				+ "so this link will not open for anybody else until it is pushed.")
		}
		if state.isFileDirty {
			said.append("This file has changes that are not in \(state.shortCommit), "
				+ "so the line the link opens is the line as of that commit, "
				+ "not the line on screen.")
		}
		return said.isEmpty ? nil : said.joined(separator: " ")
	}

	/// The permalink for a place, or nil where there is nothing to link to.
	///
	/// Nil for a repository with no remote, a host this app does not recognise,
	/// and a checkout with no commits: **an entry that hands over a URL it had
	/// to invent is worse than an entry that is not there.**
	public static func permalink(
		for place: CodePlace, repositoryPath: String, repository: URL, remote: String = "origin"
	) async -> Permalink? {
		guard let forge = await GitForge.repository(in: repository, remote: remote),
		      let state = await state(of: repositoryPath, in: repository),
		      let url = forge.url(forFile: repositoryPath, atCommit: state.commit, place: place)
		else { return nil }
		return Permalink(url: url, commit: state.shortCommit, caveat: caveat(for: state))
	}
}

// MARK: - Following one back

extension CodeLink {
	/// A permalink of this app's own, taken apart.
	public struct Followed: Equatable, Sendable {
		/// Relative to the repository root, which is how a forge serves it.
		public var path: String
		public var commit: String
		public var line: Int
		public var endLine: Int?

		public init(path: String, commit: String, line: Int, endLine: Int? = nil) {
			self.path = path
			self.commit = commit
			self.line = line
			self.endLine = endLine
		}
	}

	/// Reads a forge permalink back, or nil when it is not one.
	///
	/// **Only the shape this program writes.** A URL from somewhere else may
	/// look similar and mean something different — a `tree` URL is a directory,
	/// a `blame` URL is a different page of the same file — and following a link
	/// this app did not make is guessing. The commit is not checked here: this
	/// is arithmetic on a string, and whether the commit is in this checkout is
	/// a question for git.
	public static func follow(_ text: String) -> Followed? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return nil }

		// `/owner/name/blob/<commit>/<path…>`
		let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
		guard parts.count >= 5, parts[2] == "blob" else { return nil }
		let commit = parts[3]
		let path = parts.dropFirst(4).joined(separator: "/")
		guard !commit.isEmpty, !path.isEmpty else { return nil }
		let decoded = path.removingPercentEncoding ?? path

		// `#L12` or `#L12-L18`. A permalink with no line is a link to a file,
		// which is a thing somebody may well send; it lands at the top.
		var line = 1
		var endLine: Int?
		if let fragment = url.fragment?.removingPercentEncoding {
			let numbers = fragment.split(separator: "-").map {
				Int($0.drop(while: { !$0.isNumber }))
			}
			guard let first = numbers.first ?? nil, first > 0 else { return nil }
			line = first
			if numbers.count == 2, let second = numbers[1], second > first { endLine = second }
		}
		return Followed(path: decoded, commit: commit, line: line, endLine: endLine)
	}

	/// Where a followed line has ended up.
	public enum Landing: Equatable, Sendable {
		/// The text is still on the line the link named.
		case unchanged(line: Int)
		/// The text has moved, and the editor goes where it went.
		case moved(from: Int, to: Int)
		/// What the link pointed at is no longer in the file. The number is all
		/// there is left, and it is said rather than presented as the place.
		case gone(line: Int)
		/// Nothing to compare against — the commit is not in this checkout, or
		/// the file was not in it — so the number is taken at its word.
		case unknown(line: Int)

		/// Where to put the caret.
		public var line: Int {
			switch self {
			case let .unchanged(line), let .gone(line), let .unknown(line): return line
			case let .moved(_, to): return to
			}
		}

		/// The one sentence there is to say, and **nil for the ordinary case** —
		/// a line that has not moved needs no announcement, and a sentence that
		/// appears every time is one nobody reads.
		public func said(commit: String) -> String? {
			switch self {
			case .unchanged, .unknown:
				return nil
			case let .moved(from, to):
				return "Line \(from) at \(String(commit.prefix(7))) is line \(to) now."
			case let .gone(line):
				return "What this link pointed at is no longer in the file. "
					+ "This is line \(line), which is where the link said."
			}
		}
	}

	/// Where the line a permalink named is now.
	///
	/// **The line is re-found by what was on it**, which is the only thing that
	/// survives a file being rewritten: read the line as it was at that commit,
	/// then look for that text in the file as it is, nearest first.
	/// `BreakpointAnchors.rebound` is that search — written for a breakpoint in
	/// a file an agent rewrote while nobody was looking, which is the same
	/// problem word for word — and it is reused rather than copied.
	///
	/// The symbol half of anchoring is not used here: it needs a language
	/// server's symbols for the file as it was at a commit, which is a document
	/// nothing has ever opened. The text alone is the weaker claim of the two,
	/// and `BreakpointAnchors` already treats it as the honest fallback.
	public static func land(
		_ followed: Followed, in repository: URL
	) async -> Landing {
		let asItWas = await GitRepository.run(
			["show", "\(followed.commit):\(followed.path)"], in: repository
		)
		// A commit this checkout does not have, or a file that was not in it:
		// nothing to compare, so the number is taken at its word rather than a
		// line being invented for it.
		guard asItWas.exitCode == 0 else { return .unknown(line: followed.line) }

		let then = asItWas.stdout.components(separatedBy: "\n")
		guard followed.line >= 1, followed.line <= then.count else {
			return .unknown(line: followed.line)
		}
		let wanted = then[followed.line - 1]

		let file = repository.appendingPathComponent(followed.path)
		guard let now = try? String(contentsOf: file, encoding: .utf8) else {
			return .unknown(line: followed.line)
		}
		let lines = now.components(separatedBy: "\n")

		guard let found = BreakpointAnchors.rebound(
			line: followed.line, text: wanted, in: lines
		) else {
			return .gone(line: followed.line)
		}
		return found == followed.line ? .unchanged(line: found) : .moved(from: followed.line, to: found)
	}
}

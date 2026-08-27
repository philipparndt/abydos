import Foundation

/// A pull request, as much of one as a list of them needs to say.
///
/// The fields are the ones a review list is opened to read: which one it is,
/// what it is called, whose it is, which branch it is on, whether it is finished
/// enough to read, and whether its build is green. Everything else — the body,
/// the commits, the conversation — belongs to the page that opens it, and is
/// asked for then.
public struct PullRequest: Equatable, Sendable, Identifiable {
	public let number: Int
	public let title: String
	public let author: String
	/// The branch the work is on, which is what a checkout needs.
	public let headRefName: String
	/// What it is asking to be merged into.
	public let baseRefName: String
	public let isDraft: Bool
	public let checks: ChecksState
	/// Whether this account has been asked to review it.
	///
	/// Set by the list rather than decoded: which pull requests are waiting on
	/// the reader is a question GitHub's search answers, and it is a different
	/// call from the one that lists them.
	public var isWaitingOnMe: Bool
	public let updatedAt: Date?
	public let url: URL?

	public var id: Int { number }

	public init(
		number: Int,
		title: String,
		author: String,
		headRefName: String,
		baseRefName: String,
		isDraft: Bool = false,
		checks: ChecksState = .none,
		isWaitingOnMe: Bool = false,
		updatedAt: Date? = nil,
		url: URL? = nil
	) {
		self.number = number
		self.title = title
		self.author = author
		self.headRefName = headRefName
		self.baseRefName = baseRefName
		self.isDraft = isDraft
		self.checks = checks
		self.isWaitingOnMe = isWaitingOnMe
		self.updatedAt = updatedAt
		self.url = url
	}
}

/// How far along a pull request's checks are.
///
/// Shown in the list because a pull request whose build is red is usually not
/// worth reading line by line yet, and that is a fact about the work rather than
/// about the reviewer's taste.
///
/// `none` is a repository with no checks configured *and* a pull request whose
/// checks have not started — the two are indistinguishable from outside and
/// neither is something to draw a tick or a cross for.
public enum ChecksState: String, Equatable, Sendable {
	case passing, failing, pending, none

	/// What a row says about it.
	public var summary: String {
		switch self {
		case .passing: return "checks passed"
		case .failing: return "checks failed"
		case .pending: return "checks running"
		case .none:    return ""
		}
	}
}

/// One file a pull request changes, against the point it branched from.
public struct PullRequestFile: Equatable, Sendable, Identifiable {
	public let path: String
	public let additions: Int
	public let deletions: Int
	public let kind: GitChange.Kind

	public var id: String { path }

	public init(path: String, additions: Int, deletions: Int, kind: GitChange.Kind) {
		self.path = path
		self.additions = additions
		self.deletions = deletions
		self.kind = kind
	}

	/// The same file as the changed-file list draws, so a pull request page can
	/// hand its rows to `ChangedFileList` unchanged.
	public var asCommitFile: GitCommitFile {
		GitCommitFile(path: path, kind: kind)
	}

	public var lineCount: GitLineCount {
		GitLineCount(added: additions, removed: deletions)
	}
}

/// A remark somebody left on a line of a diff.
public struct ReviewComment: Equatable, Sendable, Identifiable {
	public let id: Int
	public let author: String
	public let body: String
	public let path: String
	/// The line in the file at the head the comment still applies to, or nil
	/// when the code it was about has gone.
	///
	/// Nil is not "dropped": a comment whose line no longer exists is still
	/// shown, against its file and marked as being about an earlier version. A
	/// reviewer needs to know a conversation happened even when the code it was
	/// about is gone, or they will have it a second time.
	public let line: Int?
	public let createdAt: Date?
	/// The commit the comment was left against, which is how GitHub decides
	/// whether it is still about anything.
	public let commit: String?

	/// Whether the line it was about has moved out from under it.
	public var isOutdated: Bool { line == nil }

	public init(
		id: Int,
		author: String,
		body: String,
		path: String,
		line: Int?,
		createdAt: Date? = nil,
		commit: String? = nil
	) {
		self.id = id
		self.author = author
		self.body = body
		self.path = path
		self.line = line
		self.createdAt = createdAt
		self.commit = commit
	}
}

/// A remark written here and not yet sent.
///
/// Two line numbers because a remark is usually about a block rather than a
/// line: pointing at the first line of a five-line mistake makes the author
/// find the other four. `startLine` is nil when it really is one line, which is
/// also what GitHub wants — it refuses a range whose start equals its end.
public struct PendingComment: Equatable, Sendable {
	public let path: String
	/// The last line of the range, which is where GitHub anchors the remark.
	public let line: Int
	/// The first line, when the remark covers more than one.
	public let startLine: Int?
	public let body: String

	public init(path: String, line: Int, startLine: Int? = nil, body: String) {
		self.path = path
		self.line = line
		// A range of one is a line, and saying it twice is how the API is made
		// to refuse a perfectly ordinary remark.
		self.startLine = startLine == line ? nil : startLine
		self.body = body
	}

	/// The two numbers as a range, whichever way round they were given.
	public init(path: String, from: Int, to: Int, body: String) {
		self.init(
			path: path,
			line: max(from, to),
			startLine: min(from, to) == max(from, to) ? nil : min(from, to),
			body: body
		)
	}

	/// How the remark reads when it has to be named: `40` or `36–40`.
	public var place: String {
		guard let startLine else { return "line \(line)" }
		return "lines \(startLine)–\(line)"
	}

	/// Whether this remark covers that line.
	public func covers(_ candidate: Int) -> Bool {
		candidate >= (startLine ?? line) && candidate <= line
	}

	/// What GitHub is sent for it.
	public var payload: [String: Any] {
		var made: [String: Any] = ["path": path, "line": line, "side": "RIGHT", "body": body]
		if let startLine {
			made["start_line"] = startLine
			made["start_side"] = "RIGHT"
		}
		return made
	}
}

/// What a submitted review says.
public enum ReviewVerdict: String, Equatable, Sendable, CaseIterable {
	case approve = "APPROVE"
	case comment = "COMMENT"
	case requestChanges = "REQUEST_CHANGES"

	public var title: String {
		switch self {
		case .approve:        return "Approve"
		case .comment:        return "Comment"
		case .requestChanges: return "Request Changes"
		}
	}
}

/// Which pull requests count as waiting on the reader.
///
/// The design left this open and the answer is a switch rather than a rule: a
/// repository whose reviews are assigned to teams and one whose reviews are
/// assigned to people want different lists, and which of the two this is cannot
/// be worked out from here.
public enum ReviewRequestScope: String, Equatable, Sendable, CaseIterable {
	/// Asked of this account by name.
	case me
	/// That, and asked of a team this account is in.
	case meOrMyTeams

	/// GitHub's own search qualifier for it.
	public var searchQualifier: String {
		switch self {
		case .me:          return "user-review-requested:@me"
		case .meOrMyTeams: return "review-requested:@me"
		}
	}

	public var title: String {
		switch self {
		case .me:          return "Only me"
		case .meOrMyTeams: return "My teams too"
		}
	}
}

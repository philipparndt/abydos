import Foundation

/// One commit, as the log shows it.
public struct GitCommit: Equatable, Sendable, Identifiable {
	public let hash: String
	/// The first seven characters, which is how a commit is spoken about.
	public let shortHash: String
	public let subject: String
	public let body: String
	public let authorName: String
	public let authorEmail: String
	public let date: Date
	/// Parents, so a merge can be told from an ordinary commit.
	public let parentHashes: [String]
	/// Branch and tag names pointing here.
	public let refs: [String]

	public var id: String { hash }
	public var isMerge: Bool { parentHashes.count > 1 }

	public init(
		hash: String,
		subject: String,
		body: String = "",
		authorName: String = "",
		authorEmail: String = "",
		date: Date = .distantPast,
		parentHashes: [String] = [],
		refs: [String] = []
	) {
		self.hash = hash
		self.shortHash = String(hash.prefix(7))
		self.subject = subject
		self.body = body
		self.authorName = authorName
		self.authorEmail = authorEmail
		self.date = date
		self.parentHashes = parentHashes
		self.refs = refs
	}
}

/// A file touched by a commit.
public struct GitCommitFile: Equatable, Sendable, Identifiable {
	public let path: String
	public let kind: GitChange.Kind
	/// Where it came from, for a rename or a copy.
	public let originalPath: String?

	public var id: String { path }
	public var name: String { (path as NSString).lastPathComponent }
	public var directory: String { (path as NSString).deletingLastPathComponent }

	public init(path: String, kind: GitChange.Kind, originalPath: String? = nil) {
		self.path = path
		self.kind = kind
		self.originalPath = originalPath
	}
}

/// Reading the log.
///
/// Everything here shells out to `git` and parses what comes back, like the
/// rest of the git layer. A commit is asked for by hash rather than held onto,
/// so a history view can list thousands of them cheaply and only pay for the
/// one somebody is looking at.
public enum GitHistory {
	/// Field separator inside a record, and record separator between commits.
	///
	/// Control characters rather than anything printable: a commit message can
	/// contain any text at all, including whatever you were going to use as a
	/// delimiter.
	private static let fieldSeparator = "\u{1F}"
	private static let recordSeparator = "\u{1E}"

	private static var format: String {
		["%H", "%P", "%an", "%ae", "%at", "%D", "%s", "%b"]
			.joined(separator: fieldSeparator) + recordSeparator
	}

	/// Commits, newest first.
	///
	/// - `path`: only commits touching it, which is the history of one file.
	/// - `revision`: only that ref's ancestry, which is the log of one branch.
	/// - `upstream`: a second tip beside the revision, so the union arrives
	///   ordered and windowed by git rather than merged here. A repository
	///   saying "1 behind" in its header used to open "Log · main" with no
	///   trace of that commit in it, because only the one revision was asked
	///   for. Meaningless without a revision, and ignored then.
	/// - `skip`/`limit`: a window, so a long history is read as it is scrolled
	///   rather than all at once.
	public static func log(
		in root: URL,
		path: String? = nil,
		revision: String? = nil,
		upstream: String? = nil,
		skip: Int = 0,
		limit: Int = 200,
		search: String? = nil
	) async -> [GitCommit] {
		var arguments = [
			"log",
			"--pretty=format:\(format)",
			"--skip=\(max(0, skip))",
			"--max-count=\(max(1, limit))",
		]

		// Messages only, and git does the matching: searching what is loaded
		// would only ever find the page you are already looking at.
		if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
			arguments.append("--regexp-ignore-case")
			arguments.append("--grep=\(search)")
		}

		if let revision {
			arguments.append(revision)
			if let upstream {
				arguments.append(upstream)
				// Two tips committed within the same second tie in the date
				// queue, and git's default order then pops whichever tip was
				// named first — a parent can arrive before its own child, which
				// no graph can lay out. `--date-order` is the same order with
				// the topology guaranteed.
				arguments.append("--date-order")
			}
		} else if path == nil, search == nil {
			// Every branch, tag and remote — and the stash, which `--all` does
			// not count as a ref. A graph of one branch is a line, and the
			// question a graph answers is what the branches are doing.
			arguments.append("--all")
			if hasStash(in: root) { arguments.append("refs/stash") }
		}
		if let path {
			// `--follow` takes exactly one path and must come after `--`, and it
			// is what keeps a file's history from stopping where somebody
			// renamed it.
			arguments.append("--follow")
			arguments.append("--")
			arguments.append(path)
		}

		let result = await GitRepository.run(arguments, in: root)
		guard result.exitCode == 0 else { return [] }
		return parseLog(result.stdout)
	}

	static func parseLog(_ text: String) -> [GitCommit] {
		text
			.components(separatedBy: recordSeparator)
			.compactMap(commit(fromRecord:))
	}

	private static func commit(fromRecord record: String) -> GitCommit? {
		// A record arrives with the newline that ended the previous one.
		let trimmed = record.trimmingCharacters(in: .newlines)
		guard !trimmed.isEmpty else { return nil }

		let fields = trimmed.components(separatedBy: fieldSeparator)
		guard fields.count >= 7, !fields[0].isEmpty else { return nil }

		let parents = fields[1].split(separator: " ").map(String.init)
		let timestamp = TimeInterval(fields[4]) ?? 0

		// `%D` gives "HEAD -> main, origin/main, tag: v1"; the arrow is noise
		// once the names are separated.
		let refs = fields[5]
			.components(separatedBy: ", ")
			.map { $0.replacingOccurrences(of: "HEAD -> ", with: "") }
			.filter { !$0.isEmpty }

		return GitCommit(
			hash: fields[0],
			subject: fields[6],
			body: fields.count > 7 ? fields[7].trimmingCharacters(in: .whitespacesAndNewlines) : "",
			authorName: fields[2],
			authorEmail: fields[3],
			date: Date(timeIntervalSince1970: timestamp),
			parentHashes: parents,
			refs: refs
		)
	}

	/// What a commit changed.
	///
	/// A merge is shown against its first parent — the difference it made to
	/// the branch it landed on, which is the question being asked when somebody
	/// clicks one.
	/// The commits that exist here and nowhere else yet.
	///
	/// Measured against every remote-tracking ref rather than the current
	/// branch's upstream: a branch may have no upstream set and still have been
	/// pushed under another name, and a commit that is on some remote is not
	/// one you can lose by dropping this machine in a river.
	/// Whether there is anything stashed, so the log can be asked for it.
	///
	/// `--all` leaves `refs/stash` out — it is a reflog rather than a branch —
	/// and asking for a ref that does not exist makes git fail the whole
	/// command rather than skip it.
	static func hasStash(in root: URL) -> Bool {
		FileManager.default.fileExists(
			atPath: root.appendingPathComponent(".git/refs/stash").path
		) || FileManager.default.fileExists(
			atPath: root.appendingPathComponent(".git/logs/refs/stash").path
		)
	}

	/// What a ref's upstream has that the ref does not.
	///
	/// The mirror of `unpushed`. The upstream's name rides along because whoever
	/// asked needs it for the log call that shows these commits, and resolving
	/// it twice would be two answers to one question.
	public struct RemoteOnly: Equatable, Sendable {
		/// Nil when the ref tracks nothing — and then there is nothing to show.
		public let upstream: String?
		public let hashes: Set<String>

		public static let none = RemoteOnly(upstream: nil, hashes: [])

		public init(upstream: String?, hashes: Set<String>) {
			self.upstream = upstream
			self.hashes = hashes
		}
	}

	/// The commits a ref's upstream has and the ref does not.
	///
	/// A ref with no upstream, a ref that is not a local branch (a remote ref
	/// has no upstream of its own), and an upstream that is gone all come back
	/// as `.none` rather than as an error: every one of them means the log
	/// should show exactly what it shows today. The gone case matters most —
	/// `%(upstream:short)` still names a deleted upstream, and passing that
	/// name to `git log` would fail the whole command and blank the page.
	public static func remoteOnly(of ref: String, in root: URL) async -> RemoteOnly {
		let details = await GitRepository.run(
			["for-each-ref", "--format=%(upstream:short)", "refs/heads/\(ref)"],
			in: root
		)
		let upstream = details.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard details.exitCode == 0, !upstream.isEmpty else { return .none }

		let listed = await GitRepository.run(["rev-list", "\(ref)..\(upstream)"], in: root)
		guard listed.exitCode == 0 else { return .none }
		let hashes = Set(
			listed.stdout
				.components(separatedBy: .newlines)
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty }
		)
		return RemoteOnly(upstream: upstream, hashes: hashes)
	}

	public static func unpushed(in root: URL, limit: Int = 500) async -> Set<String> {
		let result = await GitRepository.run(
			["rev-list", "--max-count=\(max(1, limit))", "HEAD", "--not", "--remotes"],
			in: root
		)
		guard result.exitCode == 0 else { return [] }
		return Set(
			result.stdout
				.components(separatedBy: .newlines)
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty }
		)
	}

	public static func files(of hash: String, in root: URL) async -> [GitCommitFile] {
		let result = await GitRepository.run([
			"show", "--name-status", "--find-renames", "--format=", "-m", "--first-parent", hash,
		], in: root)
		guard result.exitCode == 0 else { return [] }
		return parseNameStatus(result.stdout)
	}

	/// - Note: **Git quotes a path it cannot write plainly**, and that is what
	///   makes this line parseable at all: a name holding a tab arrives as
	///   `"a\tb"` rather than as two fields, so splitting on tab is only safe
	///   because the quoting happened. What was missing was the other half —
	///   putting the name back. A repository with `farbe-ständer` in it listed
	///   `"farbe-st\303\244nder/…"` in every file list drawn from this, and
	///   every diff asked for by that name came back empty, because no such
	///   path exists. Reported against a stash and true of a commit's files and
	///   a pull request's just as much.
	static func parseNameStatus(_ text: String) -> [GitCommitFile] {
		var files: [GitCommitFile] = []
		for line in text.split(separator: "\n") {
			let fields = line.split(separator: "\t")
				.map { GitWorkingCopy.unquote(String($0)) }
			guard fields.count >= 2, let status = fields.first?.first else { continue }

			switch status {
			case "A": files.append(GitCommitFile(path: fields[1], kind: .added))
			case "D": files.append(GitCommitFile(path: fields[1], kind: .deleted))
			case "M": files.append(GitCommitFile(path: fields[1], kind: .modified))
			case "R" where fields.count >= 3:
				files.append(GitCommitFile(path: fields[2], kind: .renamed, originalPath: fields[1]))
			case "C" where fields.count >= 3:
				files.append(GitCommitFile(path: fields[2], kind: .copied, originalPath: fields[1]))
			default:
				files.append(GitCommitFile(path: fields[1], kind: .modified))
			}
		}
		return files
	}

	/// The diff a commit made to one file.
	public static func diff(of hash: String, path: String, in root: URL) async -> String {
		let result = await GitRepository.run([
			"show", "--format=", "--find-renames", "--first-parent", "-m", hash, "--", path,
		], in: root)
		return result.exitCode == 0 ? result.stdout : ""
	}

	/// A file as it was at a commit.
	public static func contents(of path: String, at hash: String, in root: URL) async -> String? {
		let result = await GitRepository.run(["show", "\(hash):\(path)"], in: root)
		return result.exitCode == 0 ? result.stdout : nil
	}

	/// How many commits there are, for deciding whether there is more to load.
	public static func count(in root: URL, path: String? = nil) async -> Int {
		var arguments = ["rev-list", "--count", "HEAD"]
		if let path { arguments += ["--", path] }
		let result = await GitRepository.run(arguments, in: root)
		return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
	}
}

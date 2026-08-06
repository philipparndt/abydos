import Foundation

/// One changed path, on one side of the index.
public struct GitChange: Equatable, Sendable, Identifiable {
	public enum Kind: String, Sendable {
		case added, modified, deleted, renamed, copied, untracked, conflicted
	}

	/// Path relative to the work tree root.
	public let path: String
	public let kind: Kind
	/// Where the change is: staged for commit, or only in the work tree.
	public let isStaged: Bool

	public var id: String { "\(isStaged ? "s" : "u"):\(path)" }
	public var name: String { (path as NSString).lastPathComponent }
	public var directory: String { (path as NSString).deletingLastPathComponent }

	public init(path: String, kind: Kind, isStaged: Bool) {
		self.path = path
		self.kind = kind
		self.isStaged = isStaged
	}
}

/// The staged and unstaged halves of a working copy.
public struct GitWorkingCopyStatus: Equatable, Sendable {
	public var staged: [GitChange] = []
	public var unstaged: [GitChange] = []

	public var isEmpty: Bool { staged.isEmpty && unstaged.isEmpty }
	public var hasConflicts: Bool { unstaged.contains { $0.kind == .conflicted } }

	public init(staged: [GitChange] = [], unstaged: [GitChange] = []) {
		self.staged = staged
		self.unstaged = unstaged
	}
}

/// Staging and committing, on top of `git`.
///
/// Separate from `GitRepository`, which collapses a path's two porcelain codes
/// into the single status the navigator colours rows with. A staging UI needs
/// them apart: a file edited, staged, and then edited again is in both lists at
/// once, and showing it in one is a lie about what a commit would contain.
public enum GitWorkingCopy {
	// MARK: - Reading

	public static func status(in root: URL) async -> GitWorkingCopyStatus {
		// `-z` gives NUL-separated records with paths written out literally.
		// Without it git escapes anything non-ASCII — "kühlschrank" comes back
		// as "k\303\274hlschrank" inside quotes — and the escaped form is not a
		// path any later command can find.
		let result = await GitRepository.run(
			["status", "--porcelain=v1", "-uall", "--no-renames", "-z"],
			in: root
		)
		guard result.exitCode == 0 else { return GitWorkingCopyStatus() }
		return parse(porcelainZ: result.stdout)
	}

	/// Splits NUL-separated porcelain output into the two sides of the index.
	static func parse(porcelainZ output: String) -> GitWorkingCopyStatus {
		parse(records: output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init))
	}

	/// Splits newline-separated porcelain output. Paths may be quoted here.
	///
	/// Internal rather than private so the code table can be tested against
	/// fixtures without a repository on disk.
	static func parse(porcelain: String) -> GitWorkingCopyStatus {
		parse(records: porcelain.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
	}

	private static func parse(records: [String]) -> GitWorkingCopyStatus {
		var status = GitWorkingCopyStatus()

		for line in records {
			guard line.count > 3 else { continue }

			let index = line[line.startIndex]
			let worktree = line[line.index(after: line.startIndex)]
			let path = unquote(String(line.dropFirst(3)))
			guard !path.isEmpty else { continue }

			// A conflict is not a staged change with an unstaged one beside it;
			// it is one unresolved path, and offering to stage half of it would
			// be wrong. Both codes are consumed by this case.
			if isConflict(index: index, worktree: worktree) {
				status.unstaged.append(GitChange(path: path, kind: .conflicted, isStaged: false))
				continue
			}

			if index == "?" {
				status.unstaged.append(GitChange(path: path, kind: .untracked, isStaged: false))
				continue
			}

			if let kind = kind(for: index) {
				status.staged.append(GitChange(path: path, kind: kind, isStaged: true))
			}
			if let kind = kind(for: worktree) {
				status.unstaged.append(GitChange(path: path, kind: kind, isStaged: false))
			}
		}

		status.staged.sort { $0.path < $1.path }
		status.unstaged.sort { $0.path < $1.path }
		return status
	}

	/// Both sides carrying a letter means an unmerged path, except for the
	/// ordinary "staged then edited again" combinations that git spells with a
	/// space on one side.
	private static func isConflict(index: Character, worktree: Character) -> Bool {
		switch (index, worktree) {
		case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): return true
		default: return false
		}
	}

	private static func kind(for code: Character) -> GitChange.Kind? {
		switch code {
		case "A": return .added
		case "M", "T": return .modified
		case "D": return .deleted
		case "R": return .renamed
		case "C": return .copied
		default: return nil          // A space means "nothing on this side".
		}
	}

	/// Decodes a quoted, C-escaped path.
	///
	/// Only needed when git was not asked for `-z` output. Non-ASCII bytes are
	/// escaped one octal triple each, so "ü" arrives as `\303\274` — decoding
	/// those individually would produce two Latin-1 characters, not the
	/// character they encode. The bytes are collected and decoded as UTF-8 at
	/// the end instead.
	static func unquote(_ path: String) -> String {
		guard path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 else { return path }

		var bytes: [UInt8] = []
		let characters = Array(path.dropFirst().dropLast())
		var index = 0

		while index < characters.count {
			guard characters[index] == "\\", index + 1 < characters.count else {
				bytes.append(contentsOf: Array(String(characters[index]).utf8))
				index += 1
				continue
			}

			let next = characters[index + 1]
			if let digit = next.wholeNumberValue, (0...7).contains(digit) {
				let octal = String(characters[(index + 1)..<min(index + 4, characters.count)])
				if let value = UInt8(octal, radix: 8) {
					bytes.append(value)
					index += 1 + octal.count
					continue
				}
			}

			switch next {
			case "n": bytes.append(0x0A)
			case "t": bytes.append(0x09)
			case "r": bytes.append(0x0D)
			case "\"": bytes.append(0x22)
			case "\\": bytes.append(0x5C)
			default: bytes.append(contentsOf: Array(String(next).utf8))
			}
			index += 2
		}

		return String(decoding: bytes, as: UTF8.self)
	}

	// MARK: - Staging

	@discardableResult
	public static func stage(paths: [String], in root: URL) async -> GitRepository.ProcessResult {
		// `-A` rather than plain `add` so a deletion is staged as a deletion
		// instead of being silently skipped.
		await GitRepository.run(["add", "-A", "--"] + paths, in: root)
	}

	@discardableResult
	public static func unstage(paths: [String], in root: URL) async -> GitRepository.ProcessResult {
		let result = await GitRepository.run(["restore", "--staged", "--"] + paths, in: root)
		guard result.exitCode != 0 else { return result }

		// `restore` needs git 2.23, and it also fails before the first commit,
		// where there is no HEAD to restore from. `reset` handles both.
		return await GitRepository.run(["reset", "-q", "--"] + paths, in: root)
	}

	/// Throws away work-tree changes to `paths`. Untracked files are removed.
	@discardableResult
	public static func discard(paths: [String], in root: URL) async -> GitRepository.ProcessResult {
		// Untracked files are removed first; its result is not the one to
		// report, since a tree with nothing untracked makes it a no-op.
		_ = await GitRepository.run(["clean", "-fd", "--"] + paths, in: root)
		return await GitRepository.run(["checkout", "--"] + paths, in: root)
	}

	// MARK: - Committing

	/// The message a commit would carry, as git will store it.
	///
	/// Subject and body separated by a blank line, which is the convention every
	/// tool that reads git history relies on.
	public static func message(subject: String, body: String) -> String {
		let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
		let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !body.isEmpty else { return subject }
		return "\(subject)\n\n\(body)"
	}

	public static func commitArguments(subject: String, body: String, amend: Bool) -> [String] {
		var arguments = ["commit"]
		if amend { arguments.append("--amend") }
		// Two -m flags rather than one embedded newline: git joins them with a
		// blank line itself, and it keeps the body out of the subject if the
		// subject ever contains something shell-like.
		arguments += ["-m", subject.trimmingCharacters(in: .whitespacesAndNewlines)]
		let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
		if !body.isEmpty { arguments += ["-m", body] }
		return arguments
	}

	@discardableResult
	public static func commit(
		subject: String,
		body: String,
		amend: Bool,
		in root: URL
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(commitArguments(subject: subject, body: body, amend: amend), in: root)
	}

	/// The message of the last commit, for pre-filling an amend.
	public static func lastCommitMessage(in root: URL) async -> (subject: String, body: String)? {
		let result = await GitRepository.run(["log", "-1", "--pretty=%B"], in: root)
		guard result.exitCode == 0 else { return nil }

		let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return nil }

		let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
		let subject = String(parts.first ?? "")
		let body = parts.count > 1
			? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
			: ""
		return (subject, body)
	}

	// MARK: - Diffs

	/// The unified diff for one path, on one side of the index.
	public static func diff(for path: String, staged: Bool, in root: URL) async -> String {
		var arguments = ["diff", "--no-color"]
		if staged { arguments.append("--cached") }
		arguments += ["--", path]

		let result = await GitRepository.run(arguments, in: root)
		if !result.stdout.isEmpty { return result.stdout }

		// An untracked file has nothing to diff against, so git prints nothing.
		// `--no-index` against /dev/null produces the same shape of output, and
		// exits non-zero by design when the files differ.
		guard !staged else { return result.stdout }
		let untracked = await GitRepository.run(
			["diff", "--no-color", "--no-index", "--", "/dev/null", path],
			in: root
		)
		return untracked.stdout
	}
}

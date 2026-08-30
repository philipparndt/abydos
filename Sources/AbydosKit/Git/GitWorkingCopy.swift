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

	/// Whether this entry is a whole directory rather than one file.
	///
	/// Git answers `git status` with a directory when everything inside it is
	/// untracked — `build/` rather than the ten thousand files under it — and
	/// that entry is one thing to stage, which is what somebody who has just
	/// created a folder meant anyway. The flag exists so the row can say what it
	/// is: a diff of a directory is not a diff, and asking git for one gets
	/// nothing back rather than an error.
	public let isDirectory: Bool

	public var id: String { "\(isStaged ? "s" : "u"):\(path)" }
	public var name: String { (path as NSString).lastPathComponent }
	public var directory: String { (path as NSString).deletingLastPathComponent }

	public init(path: String, kind: Kind, isStaged: Bool, isDirectory: Bool = false) {
		self.path = path
		self.kind = kind
		self.isStaged = isStaged
		self.isDirectory = isDirectory
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
		// `-unormal`, so a wholly untracked directory arrives as one `dir/` entry
		// rather than as everything inside it. `-uall` was seven seconds on a
		// work tree with 69,829 untracked files — it has to stat every one of
		// them to name it — and this runs on every filesystem event, which
		// during a build is dozens a minute. The same question with `-unormal`
		// is 0.11 s and returns 425 records.
		//
		// The pane loses nothing it was using. A collapsed directory is one row
		// to stage, `git add -A -- build` is what staging it runs, and that is
		// what somebody clicking a folder of untracked build output meant. What
		// it gains is that the row exists at all: fifteen thousand folders of
		// them was a tree nobody could read and an outline view nobody could
		// scroll.
		let result = await GitRepository.run(statusArguments, in: root)
		guard result.exitCode == 0 else { return GitWorkingCopyStatus() }
		return parse(porcelainZ: result.stdout)
	}

	/// The one status command this program runs, so there is one place that
	/// carries `--ignore-submodules=dirty` and one place to check it.
	///
	/// **The flag is what stops a superproject costing seconds per event.**
	/// Without it git walks every submodule serially inside this one process:
	/// measured at 1.61 s over 200 submodules of eight files each, against
	/// 0.09 s with it — ten cores, load averages 4.9 to 21.2, git 2.54.0. The
	/// comment above about `-uall` is the same argument at a smaller scale, and
	/// this call runs on the same schedule: every filesystem event.
	///
	/// **`dirty` and not `all`, and the difference is the whole design.** `all`
	/// says nothing about submodules whatever; `dirty` still reports a gitlink
	/// whose recorded commit has moved, which is the one fact about a submodule
	/// that only the superproject knows. Verified against 200 submodules, four
	/// with modified work trees and one moved: this printed the moved one and
	/// nothing about the other four.
	///
	/// What is given up is the working-tree detail of each submodule, and that
	/// is not given up — it is asked for per submodule instead, in parallel, at
	/// 0.45 s for 200 against the 1.61 s this call used to cost on its own. See
	/// `GitEstateStatus`.
	///
	/// A repository with no submodules has nothing to ignore, so this is the
	/// same command it always was and there is no branch on "is this a
	/// superproject" to keep true.
	public static let statusArguments = [
		"status", "--porcelain=v1", "-unormal", "--no-renames", "-z",
		"--ignore-submodules=dirty",
	]

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
			var path = unquote(String(line.dropFirst(3)))
			// A directory git answered as a whole arrives with a trailing
			// slash. Kept out of the path: `name` would be empty, `directory`
			// would be the directory itself, and the tree would build a folder
			// with a nameless child in it.
			let isDirectory = path.hasSuffix("/")
			if isDirectory { path = String(path.dropLast()) }
			guard !path.isEmpty else { continue }

			// A conflict is not a staged change with an unstaged one beside it;
			// it is one unresolved path, and offering to stage half of it would
			// be wrong. Both codes are consumed by this case.
			if isConflict(index: index, worktree: worktree) {
				status.unstaged.append(GitChange(
					path: path, kind: .conflicted, isStaged: false, isDirectory: isDirectory
				))
				continue
			}

			if index == "?" {
				status.unstaged.append(GitChange(
					path: path, kind: .untracked, isStaged: false, isDirectory: isDirectory
				))
				continue
			}

			if let kind = kind(for: index) {
				status.staged.append(GitChange(
					path: path, kind: kind, isStaged: true, isDirectory: isDirectory
				))
			}
			if let kind = kind(for: worktree) {
				status.unstaged.append(GitChange(
					path: path, kind: kind, isStaged: false, isDirectory: isDirectory
				))
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
	///
	/// Ignored files are not: `clean` is given `-fd` and not `-x`, so throwing
	/// away a folder's changes does not also take the build output somebody's
	/// `.gitignore` keeps out of the way.
	@discardableResult
	public static func discard(paths: [String], in root: URL) async -> GitRepository.ProcessResult {
		// Untracked files are removed first. Its result is only the one to report
		// when there is nothing tracked to restore afterwards, which is where
		// `clean` was the whole operation; anywhere else a tree with nothing
		// untracked makes it a no-op, and a no-op's exit code says nothing.
		let cleaned = await GitRepository.run(["clean", "-fd", "--"] + paths, in: root)

		// `checkout` is only handed the paths git has something tracked under.
		// A path with nothing — an untracked file, or a folder holding only
		// untracked files — is already dealt with by `clean`, and giving it to
		// `checkout` fails the *whole* command with "pathspec did not match any
		// file(s) known to git": git validates every pathspec before it restores
		// anything, so one untracked file in a selection left the tracked ones
		// untouched and put git's error on screen after the work was gone.
		let known = await trackedFiles(under: paths, in: root)
		let restorable = GitDiscard.paths(paths, coveringAnyOf: known)
		guard !restorable.isEmpty else { return cleaned }
		return await GitRepository.run(["checkout", "--"] + restorable, in: root)
	}

	/// The tracked files under `paths`, as git lists them.
	///
	/// One question for the lot rather than one per path. It is asked for the
	/// paths given rather than for the whole work tree, and only when somebody
	/// has asked to throw something away — a gesture that happens once and is
	/// about to run two more git commands anyway.
	private static func trackedFiles(under paths: [String], in root: URL) async -> [String] {
		// `-z` for the same reason `status` asks for it: anything non-ASCII
		// comes back octal-escaped otherwise, and the escaped form matches no
		// path this is about to compare it with.
		let result = await GitRepository.run(["ls-files", "-z", "--"] + paths, in: root)
		guard result.exitCode == 0 else { return paths }
		return result.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
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
	///
	/// - `isDirectory`: whether the entry is a whole untracked directory, in
	///   which case there is no diff to show and what is wanted is the list of
	///   what staging it would add.
	public static func diff(
		for path: String, staged: Bool, in root: URL, isDirectory: Bool = false
	) async -> String {
		if isDirectory { return await contents(ofUntrackedDirectory: path, in: root) }

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

	/// The files inside a wholly untracked directory, as paths relative to the
	/// work tree root, sorted.
	///
	/// **This is the whole reason such a row can be opened at all.** The listing
	/// asks git for `-unormal`, so a wholly untracked directory arrives as one
	/// record — measured, and the measurement is in `status` above: `-uall` over
	/// the work tree was seven seconds against 0.11 s on a tree with 69,829
	/// untracked files, on a path that runs on every filesystem event. Scoped to
	/// one directory the same flag walks one subtree, so it costs what that
	/// directory holds and is asked only when somebody opens the row.
	public static func untrackedFiles(inDirectory path: String, in root: URL) async -> [String] {
		let result = await GitRepository.run(
			["status", "--porcelain=v1", "-uall", "--no-renames", "-z", "--", path],
			in: root
		)
		guard result.exitCode == 0 else { return [] }

		return result.stdout
			.split(separator: "\0", omittingEmptySubsequences: true)
			.compactMap { record -> String? in
				guard record.count > 3 else { return nil }
				let name = unquote(String(record.dropFirst(3)))
				return name.isEmpty ? nil : name
			}
			.sorted()
	}

	/// What is inside a directory git reported as a whole, as a list.
	///
	/// Not a diff, because there is no such thing for a directory — asking git
	/// for one gets an empty answer, which reads as "nothing here" rather than
	/// as "this is a folder". A list of what staging this row would add is the
	/// honest version of the same question.
	///
	/// `-uall` here where the listing does not use it, and that is the point of
	/// the split: scoped to one directory it walks one subtree, not the work
	/// tree, so it costs what that directory holds.
	private static func contents(ofUntrackedDirectory path: String, in root: URL) async -> String {
		let files = await untrackedFiles(inDirectory: path, in: root)

		guard !files.isEmpty else { return "\(path)/ — an empty folder\n" }
		let heading = files.count == 1
			? "\(path)/ — a new folder, 1 file\n"
			: "\(path)/ — a new folder, \(files.count) files\n"
		// Capped, because the reason this row is a folder at all is that there
		// can be tens of thousands under it, and a pane that tries to print them
		// is the thing being fixed. The count above is the whole truth; the list
		// is a sample of it, and says so.
		let shown = files.prefix(500)
		var text = heading + "\n" + shown.map { "+ \($0)" }.joined(separator: "\n") + "\n"
		if files.count > shown.count {
			text += "\n… and \(files.count - shown.count) more\n"
		}
		return text
	}
}

import Foundation

/// Work put aside.
///
/// A stash is a commit that is not on any branch, kept in a reflog of its own,
/// and everything awkward about it follows from that: entries are addressed by
/// position, so dropping one renumbers the rest, and git has no way to rename
/// one because a reflog message is not meant to be edited.
public enum GitStash {
	/// One entry, as it stands right now.
	public struct Entry: Equatable, Sendable, Identifiable {
		/// Its place in the list. Not an identity: dropping an entry changes
		/// every index after it, which is why anything that acts on several
		/// works from the commit instead.
		public let index: Int
		/// The commit the entry actually is.
		public let commit: String
		/// What it says on it, without the `WIP on main:` git writes itself.
		public let message: String
		/// The branch it was made on.
		public let branch: String
		/// How long ago, already in words: `2 hours ago`.
		public let age: String

		public var id: String { commit }

		/// How git wants to be given it.
		public var reference: String { "stash@{\(index)}" }

		public init(
			index: Int,
			commit: String,
			message: String,
			branch: String = "",
			age: String = ""
		) {
			self.index = index
			self.commit = commit
			self.message = message
			self.branch = branch
			self.age = age
		}
	}

	private static let separator = "\u{1F}"

	public static func list(in root: URL) async -> [Entry] {
		let format = ["%gd", "%H", "%gs", "%cr"].joined(separator: separator)
		let result = await GitRepository.run(
			["stash", "list", "--format=\(format)"], in: root
		)
		guard result.exitCode == 0 else { return [] }
		return parse(result.stdout)
	}

	/// Reads `stash list` output.
	///
	/// Internal so the shapes a reflog subject comes in can be tested against
	/// fixtures: git writes `WIP on main: 1a2b3c subject` for an entry nobody
	/// named, and `On main: what I typed` for one somebody did.
	static func parse(_ output: String) -> [Entry] {
		var result: [Entry] = []

		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			let fields = line.components(separatedBy: separator)
			guard fields.count >= 3 else { continue }

			let index = Int(
				fields[0].dropFirst("stash@{".count).prefix { $0.isNumber }
			) ?? result.count
			let (branch, message) = split(subject: fields[2])

			result.append(Entry(
				index: index,
				commit: fields[1],
				message: message,
				branch: branch,
				age: fields.count > 3 ? fields[3] : ""
			))
		}
		return result
	}

	/// `WIP on main: 1a2b3c subject` and `On main: my note` into their parts.
	private static func split(subject: String) -> (branch: String, message: String) {
		var text = subject
		if text.hasPrefix("WIP on ") { text = String(text.dropFirst("WIP on ".count)) }
		else if text.hasPrefix("On ") { text = String(text.dropFirst("On ".count)) }

		guard let colon = text.firstIndex(of: ":") else { return ("", subject) }
		let branch = String(text[text.startIndex..<colon])
		let rest = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)

		// An unnamed entry says which commit it was on top of, which is noise
		// beside the subject of that commit.
		let words = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
		if words.count == 2, words[0].count >= 7, words[0].allSatisfy(\.isHexDigit) {
			return (branch, String(words[1]))
		}
		return (branch, rest)
	}

	// MARK: - Putting work aside

	/// Stashes the working copy, or only the paths given.
	///
	/// - Parameter paths: relative to the repository, or empty for everything.
	/// - Parameter includeUntracked: files git has never seen. On by default,
	///   because the point of stashing is a clean working copy and one that
	///   still has new files in it is not clean.
	public static func push(
		in root: URL,
		message: String,
		paths: [String] = [],
		includeUntracked: Bool = true
	) async -> GitRepository.ProcessResult {
		var arguments = ["stash", "push"]
		if includeUntracked { arguments.append("--include-untracked") }
		if !message.isEmpty { arguments += ["--message", message] }
		if !paths.isEmpty { arguments += ["--"] + paths }
		return await GitRepository.run(arguments, in: root)
	}

	/// Stashes only what is in the index.
	///
	/// **The hunk-level stash, and it needs no new patch machinery.**
	/// `GitPatch.patch(selecting:)` already builds a partial patch from chosen
	/// lines and `GitWorkingCopy.applyToIndex` already applies one — so
	/// "stash these hunks" is staging them and then stashing what is staged.
	///
	/// - Parameter keepingIndex: whether what was staged stays staged
	///   afterwards. Off, because the point of stashing a hunk is to get it out
	///   of the way.
	public static func pushStaged(
		in root: URL,
		message: String,
		keepingIndex: Bool = false
	) async -> GitRepository.ProcessResult {
		var arguments = ["stash", "push", "--staged"]
		if keepingIndex { arguments.append("--keep-index") }
		if !message.isEmpty { arguments += ["--message", message] }
		return await GitRepository.run(arguments, in: root)
	}

	/// Whether this git can stash the index on its own.
	///
	/// `--staged` arrived in 2.35. Asked rather than assumed: the offer is
	/// absent on an older git rather than being a menu item that fails.
	public static func canPushStaged(in root: URL) async -> Bool {
		let read = await GitRepository.run(["--version"], in: root)
		guard read.exitCode == 0 else { return false }
		return version(from: read.stdout).map { $0 >= (2, 35) } ?? false
	}

	/// `git version 2.54.0 (Apple Git-157)` into the two numbers that matter.
	static func version(from said: String) -> (Int, Int)? {
		let numbers = said
			.split(separator: " ")
			.first { $0.first?.isNumber == true }?
			.split(separator: ".")
			.compactMap { Int($0.prefix { $0.isNumber }) }
		guard let numbers, numbers.count >= 2 else { return nil }
		return (numbers[0], numbers[1])
	}

	// MARK: - Looking inside one

	/// What a stash holds.
	///
	/// **Untracked files come from a parent of their own.** `stash push
	/// --include-untracked` is the default here, and git stores what it picked
	/// up in a third parent rather than in the diff — so a stash listed only as
	/// `^1..stash` is missing exactly the files somebody is most likely to have
	/// forgotten they had. They are listed as added, because at the moment the
	/// stash was made that is what they were.
	public static func files(_ entry: Entry, in root: URL) async -> [GitCommitFile] {
		let tracked = await GitRepository.run(
			["diff", "--name-status", "--find-renames", "\(entry.commit)^1", entry.commit],
			in: root
		)
		var found = tracked.exitCode == 0 ? GitHistory.parseNameStatus(tracked.stdout) : []

		for path in await untrackedPaths(of: entry, in: root) where !found.contains(where: { $0.path == path }) {
			found.append(GitCommitFile(path: path, kind: .added))
		}
		return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
	}

	/// The diff a stash holds for one of its files.
	public static func diff(_ entry: Entry, path: String, in root: URL) async -> String {
		// An untracked file is not in the commit's own tree, so the diff that
		// shows it is against the parent that picked it up.
		let untracked = await untrackedPaths(of: entry, in: root)
		let against = untracked.contains(path) ? "\(entry.commit)^3" : entry.commit

		let result = await GitRepository.run(
			["diff", "\(entry.commit)^1", against, "--", path], in: root
		)
		return result.exitCode == 0 ? result.stdout : ""
	}

	/// The files this stash picked up that git was not tracking.
	private static func untrackedPaths(of entry: Entry, in root: URL) async -> [String] {
		// A stash made without `--include-untracked` has two parents and no
		// third, and asking for one that is not there is an error rather than
		// an empty answer.
		let third = await GitRepository.run(
			["rev-parse", "--verify", "--quiet", "\(entry.commit)^3"], in: root
		)
		guard third.exitCode == 0 else { return [] }

		let listed = await GitRepository.run(
			["ls-tree", "-r", "--name-only", "\(entry.commit)^3"], in: root
		)
		guard listed.exitCode == 0 else { return [] }
		return listed.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
	}

	// MARK: - Whether it would still go back

	/// Whether a stash would apply over the working copy as it stands.
	public enum Applicability: Sendable, Equatable {
		/// It would go back without a fight.
		case clean
		/// It would stop in these paths.
		case conflicts([String])
		/// git here cannot say, and the caller should not pretend otherwise.
		case unknown
	}

	/// Asks whether a stash would apply, without applying it.
	///
	/// **The whole point is that it touches nothing.** Applying a stash into a
	/// mess that then has to be untangled is the failure worth engineering
	/// away, and a check that had to write to the work tree to answer would be
	/// the same failure with an extra step.
	///
	/// `merge-tree --write-tree` is what answers it: a three-way merge done
	/// entirely in the object database, against the commit the stash was made
	/// on. The side being merged into is the *working copy* and not `HEAD` —
	/// the question is whether it goes back over what is there now — which is
	/// why `GitBackup.captureWorkingCopy` is used to give the working copy a
	/// commit to stand for it. That capture already exists for the safety net,
	/// writes nothing to the index or the work tree, and is nil exactly when
	/// the tree is clean and `HEAD` is the right answer anyway.
	///
	/// Older git has no `--write-tree`, and `.unknown` is the honest answer
	/// there: a check that guessed "clean" would be worse than no check.
	public static func wouldApply(_ entry: Entry, in root: URL) async -> Applicability {
		let ours = await GitBackup.captureWorkingCopy(in: root) ?? "HEAD"
		let merged = await GitRepository.run(
			[
				"merge-tree",
				"--write-tree",
				"--merge-base=\(entry.commit)^1",
				ours,
				entry.commit,
			],
			in: root
		)

		if merged.exitCode == 0 { return .clean }
		// One means it merged with conflicts. Anything else is git refusing the
		// question — an option it does not have, a ref it cannot resolve — and
		// is not an answer about this stash.
		guard merged.exitCode == 1 else { return .unknown }

		let paths = conflictedPaths(in: merged.stdout)
		return paths.isEmpty ? .unknown : .conflicts(paths)
	}

	/// The paths out of `merge-tree`'s conflicted-file section.
	///
	/// Its lines are `<mode> <object> <stage>\t<path>`, one per stage, so the
	/// same file appears up to three times and the order has to be kept: the
	/// first mention is the one to report.
	static func conflictedPaths(in output: String) -> [String] {
		var seen = Set<String>()
		var found: [String] = []
		for line in output.split(separator: "\n") {
			let parts = line.split(separator: "\t", maxSplits: 1)
			guard parts.count == 2 else { continue }
			guard parts[0].split(separator: " ").count == 3 else { continue }
			let path = String(parts[1])
			if seen.insert(path).inserted { found.append(path) }
		}
		return found
	}

	// MARK: - Taking it back somewhere else

	/// Makes a branch at the commit the stash was made on, applies it there,
	/// and drops the entry when that works.
	///
	/// The right answer for a stash that has gone stale, and the one to offer
	/// when `wouldApply` says it would conflict: applied on the commit it came
	/// from, it cannot.
	public static func branch(
		_ entry: Entry,
		named name: String,
		in root: URL
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(["stash", "branch", name, entry.reference], in: root)
	}

	// MARK: - Taking it back

	/// Puts an entry back into the working copy.
	///
	/// - Parameter keeping: whether the entry stays in the list afterwards.
	///   `apply` keeps it, `pop` does not, and which one somebody wants is not
	///   something to guess.
	public static func apply(
		_ entry: Entry,
		in root: URL,
		keeping: Bool
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(
			["stash", keeping ? "apply" : "pop", entry.reference], in: root
		)
	}

	/// Drops entries.
	///
	/// Highest index first: git renumbers what is left after each drop, so
	/// dropping `stash@{0}` and then `stash@{1}` would take the wrong second
	/// one. Working down means nothing that is still to go has moved.
	public static func drop(
		_ entries: [Entry],
		in root: URL
	) async -> GitRepository.ProcessResult {
		var last = GitRepository.ProcessResult(stdout: "", stderr: "", exitCode: 0)
		for entry in entries.sorted(by: { $0.index > $1.index }) {
			last = await GitRepository.run(["stash", "drop", entry.reference], in: root)
			guard last.exitCode == 0 else { return last }
		}
		return last
	}

	/// Gives an entry a different message.
	///
	/// git cannot rename one, so the old entry is dropped and the same commit
	/// stored again under the new message. The work is untouched — it is the
	/// same commit, which is why the entry can be moved about at all — and it
	/// ends up at the top of the list, where a reflog puts whatever happened
	/// last.
	///
	/// In that order, and not the other way round: a reflog records changes of
	/// value, so storing a commit the stash already points at writes nothing at
	/// all and the rename silently does nothing.
	public static func rename(
		_ entry: Entry,
		to message: String,
		in root: URL
	) async -> GitRepository.ProcessResult {
		let dropped = await GitRepository.run(
			["stash", "drop", entry.reference], in: root
		)
		guard dropped.exitCode == 0 else { return dropped }

		// Written the way git writes its own, so the branch it was made on
		// survives the rename and the list stays of one kind.
		let subject = entry.branch.isEmpty ? message : "On \(entry.branch): \(message)"
		let stored = await GitRepository.run(
			["stash", "store", "--message", subject, entry.commit], in: root
		)
		guard stored.exitCode != 0 else { return stored }

		// The entry is out of the list and could not be put back. The commit
		// is still there, and saying which one is the difference between work
		// that can be recovered and work that is gone.
		return GitRepository.ProcessResult(
			stdout: stored.stdout,
			stderr: (stored.stderr.isEmpty ? stored.stdout : stored.stderr)
				+ "\n\nThe entry was removed from the list but could not be stored again. "
				+ "The work is in commit \(entry.commit) and can be recovered with:\n\n"
				+ "    git stash store -m \"\(message)\" \(entry.commit)",
			exitCode: stored.exitCode
		)
	}
}

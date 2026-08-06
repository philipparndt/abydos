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

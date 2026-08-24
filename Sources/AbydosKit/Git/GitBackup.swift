import Foundation

/// A way back from anything that could lose work.
///
/// An operation is destructive when nothing left on this machine afterwards can
/// put it back. There are not many — switching a branch over uncommitted work,
/// discarding, resetting, rebasing, amending, deleting a branch that is ahead,
/// moving a tag — and each of them leaves a ref here before it runs.
///
/// **A branch, and not the reflog.** The reflog holds most of this already and
/// is the right answer for somebody at a prompt. It is the wrong answer for a
/// promise: entries for unreachable commits expire after ninety days by default,
/// thirty for the unreachable ones, and `gc` collects what they pointed at. A
/// branch is reachable, so nothing collects it.
///
/// **And not a private namespace under `refs/abydos/`,** which was the tidier
/// idea and is the wrong one: it would be invisible to `git branch`, to
/// `git log --all`, and to anybody who has never heard of this program. Safety
/// nobody can find is not safety. The clutter that visible refs would have cost
/// is paid for by branch names folding on `/` — the whole of `backup/` is one
/// row somebody can leave shut forever.
///
/// **And not a tag**, which would be pushed. A private near-miss is not
/// something to publish.
public enum GitBackup {
	/// Where they live. One folder, so the refs tree folds them away.
	public static let prefix = "backup/"

	/// One backup ref.
	public struct Entry: Sendable, Equatable, Identifiable {
		/// Short name, `backup/…` included.
		public let name: String
		public let commit: String
		/// When the commit under it was made.
		public let made: Date

		public var id: String { name }

		public init(name: String, commit: String, made: Date) {
			self.name = name
			self.commit = commit
			self.made = made
		}
	}

	// MARK: - Keeping the working copy

	/// A commit holding the working copy exactly as it stands, having touched
	/// neither the working copy nor the stash list.
	///
	/// Nil when there is nothing to keep, so a backup ref is never made for a
	/// clean tree.
	///
	/// **Not `git stash create`,** which was the obvious answer and quietly
	/// omits untracked files: it has no `--include-untracked`, so a discard of a
	/// file git had never seen would have been "insured" by a commit that did
	/// not contain it. What happens instead is what `stash create` does one
	/// level down — a throwaway index of our own, everything added to it, a tree
	/// written from it — which reaches untracked files and still leaves the real
	/// index and the work tree alone.
	public static func captureWorkingCopy(in root: URL) async -> String? {
		let index = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-backup-\(UUID().uuidString).index")
		defer { try? FileManager.default.removeItem(at: index) }
		let scratch = ["GIT_INDEX_FILE": index.path]

		// From an empty index, `add -A` makes the tree *be* the work tree:
		// everything present is added, everything absent is simply not there,
		// so a deletion is recorded by omission rather than needing a base.
		// `.gitignore` is still honoured, which is what anybody would want of a
		// backup — it is insurance against losing work, not a copy of `build/`.
		let added = await GitRepository.run(["add", "-A"], in: root, environment: scratch)
		guard added.exitCode == 0 else { return nil }

		let written = await GitRepository.run(["write-tree"], in: root, environment: scratch)
		guard written.exitCode == 0 else { return nil }
		let tree = written.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !tree.isEmpty else { return nil }

		// Nothing to keep when the work tree is what HEAD already holds. An
		// unborn branch has no tree to compare with and always has something to
		// keep, which is right: there is no commit to recover it from.
		let head = await GitRepository.run(["rev-parse", "HEAD^{tree}"], in: root)
		let headTree = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		if head.exitCode == 0, headTree == tree { return nil }

		var arguments = ["commit-tree", tree, "-m", "Abydos backup of the working copy"]
		let parent = await GitRepository.run(["rev-parse", "HEAD"], in: root)
		if parent.exitCode == 0 {
			let commit = parent.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
			if !commit.isEmpty { arguments += ["-p", commit] }
		}

		let made = await GitRepository.run(arguments, in: root)
		guard made.exitCode == 0 else { return nil }
		let commit = made.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return commit.isEmpty ? nil : commit
	}

	// MARK: - Keeping a ref

	/// Points a branch under `backup/` at a commit.
	@discardableResult
	public static func keep(
		_ commit: String,
		as name: String,
		in root: URL
	) async -> GitRepository.ProcessResult {
		await GitRepository.run(
			["update-ref", "refs/heads/\(prefixed(name))", commit], in: root
		)
	}

	/// Keeps whatever a ref points at now, under a name of this shape.
	///
	/// The common case: back up `main` before something rewrites it.
	@discardableResult
	public static func keep(
		ref: String,
		subject: String,
		at moment: Date,
		in root: URL
	) async -> GitRepository.ProcessResult {
		let resolved = await GitRepository.run(["rev-parse", ref], in: root)
		guard resolved.exitCode == 0 else { return resolved }
		let commit = resolved.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return await keep(commit, as: name(for: subject, at: moment), in: root)
	}

	/// What a backup is called: when it was made, and what it holds.
	///
	/// The moment first, so the folder sorts into order by itself and a sweep
	/// can be read before it is run.
	public static func name(for subject: String, at moment: Date) -> String {
		let stamp = DateFormatter()
		stamp.locale = Locale(identifier: "en_US_POSIX")
		stamp.timeZone = TimeZone.current
		stamp.dateFormat = "yyyy-MM-dd-HHmm"
		return "\(prefix)\(stamp.string(from: moment))-\(slug(subject))"
	}

	// MARK: - Reading and sweeping

	/// The backups there are, newest first.
	public static func list(in root: URL) async -> [Entry] {
		let separator = "\u{1F}"
		let result = await GitRepository.run(
			[
				"for-each-ref",
				"--format=%(refname:short)\(separator)%(objectname)\(separator)%(committerdate:unix)",
				"--sort=-committerdate",
				"refs/heads/\(prefix)",
			],
			in: root
		)
		guard result.exitCode == 0 else { return [] }

		return result.stdout.split(separator: "\n").compactMap { line in
			let fields = line.components(separatedBy: separator)
			guard fields.count >= 3, let seconds = TimeInterval(fields[2]) else { return nil }
			return Entry(
				name: fields[0],
				commit: fields[1],
				made: Date(timeIntervalSince1970: seconds)
			)
		}
	}

	/// Deletes the backups older than a given age, and says what it took.
	///
	/// A ref keeps its commits from being collected, which is the point of it
	/// and also the cost in disk — so there has to be a way to let them go, and
	/// it has to report what it did rather than quietly making space.
	@discardableResult
	public static func sweep(
		olderThan age: TimeInterval,
		now: Date,
		in root: URL
	) async -> [Entry] {
		let stale = await list(in: root).filter { now.timeIntervalSince($0.made) > age }
		guard !stale.isEmpty else { return [] }

		var taken: [Entry] = []
		for entry in stale {
			let deleted = await GitRepository.run(
				["update-ref", "-d", "refs/heads/\(entry.name)"], in: root
			)
			if deleted.exitCode == 0 { taken.append(entry) }
		}
		return taken
	}

	// MARK: - Names

	private static func prefixed(_ name: String) -> String {
		name.hasPrefix(prefix) ? name : prefix + name
	}

	/// A ref name git will take, out of whatever it is being called after.
	///
	/// git refuses a great deal in a ref name — spaces, `~`, `^`, `:`, `..`, a
	/// trailing `.lock` — and a backup that fails to be made because the branch
	/// it was insuring had an awkward name would be the worst possible moment
	/// to find that out.
	static func slug(_ subject: String) -> String {
		let kept = subject.map { character -> Character in
			if character.isLetter || character.isNumber { return character }
			return "-"
		}
		var slug = String(kept)
		while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
		slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-.")).lowercased()
		return slug.isEmpty ? "work" : String(slug.prefix(40))
	}
}

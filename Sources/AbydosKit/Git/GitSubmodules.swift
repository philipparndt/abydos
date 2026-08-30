import Foundation

/// One submodule of a superproject: where it is, and which commit the
/// superproject records for it.
///
/// The commit here is the *gitlink* — what the superproject's index says the
/// submodule should be at. Where the submodule actually is, is a question for
/// that repository and not for this structure, and keeping the two apart is the
/// whole of what makes a moved gitlink legible.
public struct GitSubmodule: Equatable, Sendable, Identifiable {
	/// Path relative to the superproject's work tree root, with no trailing
	/// slash. This is the identity: `.gitmodules` names are decoration and can
	/// be absent, wrong, or duplicated across a rename.
	public let path: String

	/// The object name the superproject's index records for this submodule.
	public let recordedCommit: String

	/// The name `.gitmodules` gives it, when `.gitmodules` mentions it at all.
	public let name: String?

	/// The URL `.gitmodules` gives it, when `.gitmodules` mentions it at all.
	public let url: String?

	/// Whether there is a repository at `path` on disk.
	///
	/// A submodule the index names and disk lacks is ordinary: it is what a
	/// fresh clone without `--recurse-submodules` leaves, and what removing a
	/// service mid-refactoring leaves for everybody who has not pulled yet. It
	/// is shown as absent rather than fetched — the estate is read, not
	/// administered.
	public let isCheckedOut: Bool

	/// Where this submodule's git directory sits, relative to the *estate's*
	/// git directory.
	///
	/// **One rule covers every arrangement**, which is why this is a suffix
	/// rather than a path: a submodule's git directory is always its parent's
	/// git directory plus `modules/<name>`. Verified in all four combinations —
	///
	///     ordinary checkout   .git → .git/modules/svc
	///     nested in that      → .git/modules/svc/modules/lib/leaf
	///     linked worktree     .git/worktrees/wt → …/worktrees/wt/modules/svc
	///     nested in that      → …/worktrees/wt/modules/svc/modules/lib/leaf
	///
	/// — and it is what lets one watcher over the estate's git directory see
	/// every submodule's refs at any depth, in a worktree or not. The name and
	/// not the path is what git files it under, and a `git mv` leaves those two
	/// differing for good.
	public let gitDirectorySuffix: String

	/// How far down this submodule is: 0 for one the superproject itself holds.
	///
	/// Kept because order depends on it. A nested submodule's commit is what
	/// moves its parent's gitlink, which is what moves the superproject's, so
	/// anything that commits or pushes an estate has to work from the deepest
	/// outwards.
	public let depth: Int

	public var id: String { path }
	public var displayName: String { name ?? path }

	public init(
		path: String,
		recordedCommit: String,
		name: String? = nil,
		url: String? = nil,
		isCheckedOut: Bool = true,
		gitDirectorySuffix: String? = nil,
		depth: Int = 0
	) {
		self.path = path
		self.recordedCommit = recordedCommit
		self.name = name
		self.url = url
		self.isCheckedOut = isCheckedOut
		// Defaulted to the first-level spelling, which is what it is unless the
		// inventory says otherwise.
		self.gitDirectorySuffix = gitDirectorySuffix ?? "modules/\(name ?? path)"
		self.depth = depth
	}
}

/// Reading which submodules a repository has.
///
/// **From the index, not from `git submodule`.** `git submodule status` is a
/// shell and a process per submodule, run serially: measured at 5.37 s for 200
/// submodules, against 0.01 s for the one `ls-files` call below — ten cores,
/// load averages 4.9 to 21.2, git 2.54.0. `--cached` does not help; it was
/// 5.82 s. Nothing here may cost a process per submodule, because the estates
/// this exists for hold three hundred.
public enum GitSubmodules {
	/// The mode git gives a gitlink in a tree or an index entry.
	static let gitlinkMode = "160000"

	/// Every submodule the index names, sorted by path.
	///
	/// Two calls, neither of which grows a process per submodule. The index
	/// decides what exists; `.gitmodules` only decorates it with a name and a
	/// URL, because the two disagree routinely and only one of them is what git
	/// will act on: a submodule removed from the index but left in
	/// `.gitmodules`, and one added to the index by somebody whose `.gitmodules`
	/// you have not pulled, are both ordinary states mid-refactoring.
	public static func inventory(in root: URL) async -> [GitSubmodule] {
		await inventory(in: root, under: "", gitDirectory: "", depth: 0)
			.sorted { $0.path < $1.path }
	}

	/// How deep this will follow submodules inside submodules.
	///
	/// A bound rather than a belief. Nesting is real — a platform library held
	/// by every service, held in turn by the superproject — but a cycle, or a
	/// repository that holds itself through a chain of others, would otherwise
	/// walk until something gave out. Eight is far past any estate anybody has
	/// described and close enough to stop a mistake being expensive.
	static let maximumDepth = 8

	/// One level of the inventory, and whatever is inside it.
	///
	/// - Parameter under: the path prefix everything found here sits below,
	///   relative to the superproject.
	/// - Parameter gitDirectory: the prefix, relative to the *estate's* git
	///   directory, that this repository's own git directory sits at.
	private static func inventory(
		in root: URL, under prefix: String, gitDirectory: String, depth: Int
	) async -> [GitSubmodule] {
		let listed = await gitlinks(in: root)
		guard !listed.isEmpty else { return [] }

		let configured = await configuredSubmodules(in: root)
		let manager = FileManager.default

		var found: [GitSubmodule] = []
		var deeper: [(root: URL, prefix: String, gitDirectory: String)] = []

		for entry in listed {
			let decoration = configured[entry.path]
			let directory = root.appendingPathComponent(entry.path)
			// `.git` rather than the directory: an empty directory is what an
			// uninitialised submodule leaves behind, and it exists.
			let isCheckedOut = manager.fileExists(
				atPath: directory.appendingPathComponent(".git").path
			)
			let name = decoration?.name ?? entry.path
			let suffix = gitDirectory.isEmpty
				? "modules/\(name)"
				: "\(gitDirectory)/modules/\(name)"
			let path = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"

			found.append(GitSubmodule(
				path: path,
				recordedCommit: entry.commit,
				name: decoration?.name,
				url: decoration?.url,
				isCheckedOut: isCheckedOut,
				gitDirectorySuffix: suffix,
				depth: depth
			))

			// **The gate, and it is what keeps a flat estate free.** Recursing
			// unconditionally is one `ls-files` per submodule — two hundred
			// processes on the path whose whole point is that the rows appear in
			// ten milliseconds. A repository with no `.gitmodules` has no
			// submodules to declare, and asking the filesystem is a stat rather
			// than a process.
			//
			// What it misses: a gitlink left in an index after `.gitmodules` was
			// deleted. Git cannot clone or update that one either, so it is a
			// broken state rather than a shape this refuses to read, and paying
			// two hundred processes on every estate to notice it is not the
			// trade.
			guard depth + 1 < maximumDepth, isCheckedOut else { continue }
			guard manager.fileExists(
				atPath: directory.appendingPathComponent(".gitmodules").path
			) else { continue }
			deeper.append((root: directory, prefix: path, gitDirectory: suffix))
		}

		guard !deeper.isEmpty else { return found }

		// Fanned out, because a superproject whose every service holds the same
		// platform library is a real shape and reading it one at a time is the
		// serial walk this design exists to avoid.
		let inside = await withTaskGroup(of: [GitSubmodule].self) { group -> [GitSubmodule] in
			var next = 0
			var collected: [GitSubmodule] = []

			func addWork() -> Bool {
				guard next < deeper.count, !Task.isCancelled else { return false }
				let step = deeper[next]
				next += 1
				group.addTask {
					await inventory(
						in: step.root, under: step.prefix,
						gitDirectory: step.gitDirectory, depth: depth + 1
					)
				}
				return true
			}

			for _ in 0..<min(GitEstateReader.concurrency, deeper.count) { _ = addWork() }
			while let some = await group.next() { collected += some; _ = addWork() }
			return collected
		}
		return found + inside
	}

	/// The gitlinks in the index: one `git ls-files --stage`, filtered by mode.
	static func gitlinks(in root: URL) async -> [(path: String, commit: String)] {
		let result = await GitRepository.run(["ls-files", "--stage", "-z"], in: root)
		guard result.exitCode == 0 else { return [] }
		return parseStage(result.stdout)
	}

	/// Parses `git ls-files --stage -z`, keeping only gitlinks — one per path.
	///
	/// Records are `<mode> SP <object> SP <stage> TAB <path>`, NUL-separated.
	/// `-z` because without it git escapes any path that is not plain ASCII, and
	/// the escaped form is not a path any later command can find — the same
	/// reason `GitWorkingCopy.status` asks for it.
	///
	/// **One entry per path, and the stage is why.** An unmerged path has no
	/// stage 0: it has stage 1 for the common ancestor, 2 for ours and 3 for
	/// theirs. A parser that took every record listed a conflicted submodule
	/// three times — three rows on the overview, and a superproject with one
	/// conflicted submodule reporting "3 conflicted". Driving a real merge is
	/// what found it; nothing in an unconflicted repository can.
	///
	/// Ours wins when there is no stage 0, because ours is what the work tree is
	/// on and therefore what every other question asked about this submodule
	/// will be answered against.
	static func parseStage(_ output: String) -> [(path: String, commit: String)] {
		var byPath: [String: (stage: Int, commit: String)] = [:]
		var order: [String] = []

		for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
			guard let tab = record.firstIndex(of: "\t") else { continue }
			let fields = record[record.startIndex..<tab].split(separator: " ")
			guard fields.count >= 3, fields[0] == gitlinkMode,
			      let stage = Int(fields[2])
			else { continue }
			let path = String(record[record.index(after: tab)...])
			guard !path.isEmpty else { continue }

			if byPath[path] == nil { order.append(path) }
			// Lower rank wins: stage 0 if it is there, then ours, then theirs,
			// then the ancestor.
			let rank = [0: 0, 2: 1, 3: 2, 1: 3][stage] ?? 4
			let heldRank = byPath[path].map { [0: 0, 2: 1, 3: 2, 1: 3][$0.stage] ?? 4 } ?? Int.max
			if rank < heldRank { byPath[path] = (stage: stage, commit: String(fields[1])) }
		}

		return order.compactMap { path in
			guard let held = byPath[path] else { return nil }
			return (path: path, commit: held.commit)
		}
	}

	/// What `.gitmodules` says, keyed by the path it gives — which is the only
	/// key that can be matched against the index.
	static func configuredSubmodules(
		in root: URL
	) async -> [String: (name: String, url: String?)] {
		let result = await GitRepository.run(
			["config", "--file", ".gitmodules", "--list", "-z"], in: root
		)
		// A superproject need not have a `.gitmodules` at all, and git exits
		// non-zero when it does not. That is not a failure to report.
		guard result.exitCode == 0 else { return [:] }
		return parseGitmodules(result.stdout)
	}

	/// Parses `git config --list -z`, whose records are `key LF value`.
	///
	/// Keys are `submodule.<name>.<setting>`, and a name may itself contain
	/// dots — a submodule called `github.com/acme/svc` is legal — so the name is
	/// what is left after taking the known prefix off the front and the setting
	/// off the back, not the second component.
	static func parseGitmodules(_ output: String) -> [String: (name: String, url: String?)] {
		var paths: [String: String] = [:]  // name -> path
		var urls: [String: String] = [:]   // name -> url

		for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
			let halves = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
			guard halves.count == 2 else { continue }
			let key = String(halves[0]), value = String(halves[1])
			guard key.hasPrefix("submodule.") else { continue }
			let rest = String(key.dropFirst("submodule.".count))
			guard let lastDot = rest.lastIndex(of: ".") else { continue }
			let name = String(rest[rest.startIndex..<lastDot])
			let setting = String(rest[rest.index(after: lastDot)...])
			guard !name.isEmpty else { continue }
			if setting == "path" { paths[name] = value }
			if setting == "url" { urls[name] = value }
		}

		var byPath: [String: (name: String, url: String?)] = [:]
		for (name, path) in paths {
			byPath[path] = (name: name, url: urls[name])
		}
		return byPath
	}
}

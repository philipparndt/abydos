import Foundation

/// One changed path in an estate, and the repository it changed in.
///
/// The repository has to travel with the change, because in an estate the path
/// alone no longer identifies it: `src/main/java/Log.java` is a real path in
/// two hundred microservices at once, and a tree that keyed rows by path would
/// fold them into one row and then stage the wrong repository.
public struct GitEstateChange: Sendable, Equatable, Identifiable {
	/// The submodule it is in, or nil for the superproject's own work tree.
	public let submodule: GitSubmodule?

	/// The change, with its path relative to the repository that owns it.
	public let change: GitChange

	/// The same change's path, relative to the superproject — what a tree over
	/// the whole estate shows and what `GitEstate.grouped` takes back apart.
	public let path: String

	public var id: String { "\(submodule?.path ?? ""):\(change.id)" }
	public var isStaged: Bool { change.isStaged }

	public init(submodule: GitSubmodule?, change: GitChange) {
		self.submodule = submodule
		self.change = change
		if let submodule, change.path != "." {
			self.path = "\(submodule.path)/\(change.path)"
		} else {
			self.path = submodule?.path ?? change.path
		}
	}
}

/// What every repository in an estate has changed.
public struct GitEstateStatus: Sendable, Equatable {
	/// The superproject's own status, which includes every gitlink whose
	/// recorded commit has moved and nothing about a merely dirty submodule.
	public var superproject: GitWorkingCopyStatus

	/// Each submodule's own status, by submodule path. A submodule that has not
	/// been read yet is absent from this, which is not the same as being clean —
	/// see `hasBeenRead(_:)`.
	public var submodules: [String: GitWorkingCopyStatus]

	public init(
		superproject: GitWorkingCopyStatus = GitWorkingCopyStatus(),
		submodules: [String: GitWorkingCopyStatus] = [:]
	) {
		self.superproject = superproject
		self.submodules = submodules
	}

	/// Whether this submodule's status has landed.
	///
	/// The overview is drawn from the inventory before any status has been asked
	/// for, so "no changes recorded" and "not asked yet" are both empty and only
	/// one of them may be shown as clean. A row that says clean about a
	/// repository nobody has looked at is a sentence about this program dressed
	/// as a sentence about the code.
	public func hasBeenRead(_ submodulePath: String) -> Bool {
		submodules[submodulePath] != nil
	}

	public func status(of submodulePath: String) -> GitWorkingCopyStatus? {
		submodules[submodulePath]
	}

	/// Every change in the estate, with the repository it belongs to, ordered
	/// superproject first and then by submodule path.
	public func changes(in estate: GitEstate) -> [GitEstateChange] {
		var all: [GitEstateChange] = []
		for change in superproject.staged + superproject.unstaged {
			all.append(GitEstateChange(submodule: nil, change: change))
		}
		for submodule in estate.submodules {
			guard let status = submodules[submodule.path] else { continue }
			for change in status.staged + status.unstaged {
				all.append(GitEstateChange(submodule: submodule, change: change))
			}
		}
		return all
	}

	/// The estate's changes as one pair of lists, with every path written
	/// relative to the superproject.
	///
	/// This is what a tree over the whole estate is built from, and what
	/// `GitEstate.grouped` takes back apart when something is staged. The
	/// rewriting is the whole of it: a submodule reports `src/Main.java`,
	/// because that is the path its own repository knows, and two hundred
	/// submodules reporting the same path is two hundred rows only if each
	/// keeps the repository it came from in front of it.
	///
	/// The superproject's own entries are kept as they are, gitlinks included —
	/// `GitChangeTree.build` folds those onto the repository row rather than
	/// leaving them as rows of their own.
	public func flattened(in estate: GitEstate) -> GitWorkingCopyStatus {
		var flat = superproject
		for submodule in estate.submodules {
			guard let own = submodules[submodule.path] else { continue }
			flat.staged += own.staged.map { prefixed($0, with: submodule.path) }
			flat.unstaged += own.unstaged.map { prefixed($0, with: submodule.path) }
		}
		return flat
	}

	private func prefixed(_ change: GitChange, with submodulePath: String) -> GitChange {
		GitChange(
			path: "\(submodulePath)/\(change.path)",
			kind: change.kind,
			isStaged: change.isStaged,
			isDirectory: change.isDirectory
		)
	}

	/// The submodules with something in their work tree, in path order.
	public func changedSubmodules(in estate: GitEstate) -> [GitSubmodule] {
		estate.submodules.filter { submodules[$0.path]?.isEmpty == false }
	}

	/// The submodules whose own merge is unresolved.
	public func conflictedSubmodules(in estate: GitEstate) -> [GitSubmodule] {
		estate.submodules.filter { submodules[$0.path]?.hasConflicts == true }
	}

	/// The submodules whose gitlink the superproject reports as moved.
	///
	/// Read from the superproject's own status rather than by comparing commits:
	/// with `--ignore-submodules=dirty` that call reports exactly this and
	/// nothing else about a submodule, so the answer is already in hand and
	/// costs no further process.
	public func movedGitlinks(in estate: GitEstate) -> [GitSubmodule] {
		let moved = Set(
			(superproject.staged + superproject.unstaged).map(\.path)
		)
		return estate.submodules.filter { moved.contains($0.path) }
	}
}

/// How much changed, across an estate.
public enum GitEstateLineCounts {
	/// The line counts for the whole estate, keyed by superproject-relative
	/// path.
	///
	/// **One command per repository that has changes, and none for the rest.**
	/// `git diff --numstat` run in the superproject answers nothing about a file
	/// inside a submodule — the superproject does not track it — so the rows for
	/// two hundred services would carry no counts at all. Asking every
	/// repository instead would be two hundred processes to annotate six rows,
	/// which is the rule `Asking how much changed does not make a repository
	/// slow to read` at estate scale.
	///
	/// Which repositories have changes is already known before this runs: the
	/// superproject's status named the moved gitlinks and the fan-out named the
	/// dirty submodules. So the answer to "which shall I ask" costs nothing.
	public static func workingCopy(
		staged: Bool, in estate: GitEstate, status: GitEstateStatus
	) async -> [String: GitLineCount] {
		var counts = await GitLineCounts.workingCopy(staged: staged, in: estate.root)

		let changed = status.changedSubmodules(in: estate)
		guard !changed.isEmpty else { return counts }

		let perSubmodule = await withTaskGroup(
			of: (String, [String: GitLineCount]).self
		) { group -> [(String, [String: GitLineCount])] in
			var next = 0
			var collected: [(String, [String: GitLineCount])] = []

			func addWork() -> Bool {
				guard next < changed.count, !Task.isCancelled else { return false }
				let submodule = changed[next]
				next += 1
				let root = estate.root.appendingPathComponent(submodule.path)
				group.addTask {
					(submodule.path, await GitLineCounts.workingCopy(staged: staged, in: root))
				}
				return true
			}

			for _ in 0..<min(GitEstateReader.concurrency, changed.count) { _ = addWork() }
			while let answer = await group.next() { collected.append(answer); _ = addWork() }
			return collected
		}

		for (path, own) in perSubmodule {
			for (file, count) in own { counts["\(path)/\(file)"] = count }
		}
		return counts
	}
}

/// Reading every repository in an estate, in parallel and under a ceiling.
public enum GitEstateReader {
	/// How many `git` processes may run at once.
	///
	/// **Measured, not guessed.** Twelve concurrent read 200 submodules in
	/// 0.45 s; twenty-four read the same 200 in 0.46 s. The plateau is at
	/// roughly the core count, because past it the processes contend for the
	/// same disk and the same page cache, and there is nothing above it to win.
	///
	/// The ceiling is the point. Unbounded is three hundred `git` processes
	/// against ten cores while a build is running — which is how a feature for
	/// reading a large project makes the machine worse at the job it was opened
	/// for. Ten cores, load averages 4.9 to 21.2, git 2.54.0.
	public static var concurrency: Int {
		min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 12)
	}

	/// Reads the superproject and every checked-out submodule.
	///
	/// This is the sweep, and it runs when the project opens and when the
	/// inventory itself moves. It is not what runs on a filesystem event: that
	/// re-reads the one repository the event named, at 0.01 s. See
	/// `status(of:only:)`.
	public static func status(of estate: GitEstate) async -> GitEstateStatus {
		await status(of: estate, only: estate.submodules.filter(\.isCheckedOut).map(\.path))
	}

	/// Reads the superproject and the named submodules, and nothing else.
	///
	/// Cancellable at the grain that matters: `GitRepository.run` cannot take a
	/// process back once it has started it, so what cancellation buys is that
	/// nothing further is *started*. Closing a project part way through a sweep
	/// of three hundred repositories leaves the ones already running to finish
	/// and never asks the rest, which is the whole of what "stop" can honestly
	/// mean here.
	public static func status(
		of estate: GitEstate,
		only submodulePaths: [String]
	) async -> GitEstateStatus {
		async let superproject = GitWorkingCopy.status(in: estate.root)

		let wanted = submodulePaths.compactMap { estate.submodule(at: $0) }.filter(\.isCheckedOut)
		var read: [String: GitWorkingCopyStatus] = [:]

		if !wanted.isEmpty {
			read = await withTaskGroup(
				of: (String, GitWorkingCopyStatus).self
			) { group -> [String: GitWorkingCopyStatus] in
				var next = 0
				var collected: [String: GitWorkingCopyStatus] = [:]

				func addWork() -> Bool {
					guard next < wanted.count, !Task.isCancelled else { return false }
					let submodule = wanted[next]
					next += 1
					let root = estate.root.appendingPathComponent(submodule.path)
					group.addTask {
						(submodule.path, await GitWorkingCopy.status(in: root))
					}
					return true
				}

				for _ in 0..<min(concurrency, wanted.count) { _ = addWork() }
				while let (path, status) = await group.next() {
					collected[path] = status
					_ = addWork()
				}
				return collected
			}
		}

		return GitEstateStatus(superproject: await superproject, submodules: read)
	}
}

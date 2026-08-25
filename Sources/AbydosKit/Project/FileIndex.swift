import Foundation

/// Every file in a project, by path, so one can be found by typing part of it.
///
/// **An actor, decided rather than assumed.** The last thing in this app to hold
/// per-project state and be written from more than one place was `Project`, and
/// it was a plain class: the repository watcher and the window both called
/// `loadGit`, both ran on the cooperative pool, and two threads writing the same
/// two properties was a segmentation fault in `_SwiftURL.__deallocating_deinit`.
/// This has the same shape — built from a background task, invalidated by
/// filesystem events, read by a popover — so the isolation is settled here in
/// the type rather than left to whoever calls it.
///
/// The cost that decides everything else is in `ProjectFiles`: listing a work
/// tree of 24,691 files takes 0.03 s through git and 3.05 s through a walk. Even
/// the cheap one is far too expensive to do per keystroke, so the list is built
/// once, kept, and mended as files come and go.
public actor FileIndex {
	public let root: URL

	/// Paths relative to the root, prepared for matching, in the order they were
	/// listed. Prepared once here rather than per keystroke — see
	/// `FileMatching.Candidate` for what that was measured to cost.
	private var paths: [FileMatching.Candidate] = []
	/// The same paths, for deciding quickly whether one is already known.
	private var known: Set<String> = []
	/// The build in flight, so a second caller joins it rather than starting
	/// another — the shape `Project.loadGit` uses, and for the same reason: each
	/// build is a `git ls-files` over the whole repository.
	private var building: Task<Void, Never>?

	/// Bumped whenever the list is known to be behind.
	private var staleness = 0
	/// The `staleness` the list in hand was built at, or nil before the first
	/// build. Equal to `staleness` means nothing has happened since.
	private var builtAt: Int?

	public init(root: URL) {
		self.root = root.standardizedFileURL
	}

	/// Whether the first build has finished.
	///
	/// The palette asks so it can say "still reading" rather than showing an
	/// empty list, which reads as "there is no such file" — a different and
	/// wrong answer.
	public var isReady: Bool { builtAt != nil }

	public var count: Int { paths.count }

	/// Whether the list in hand is known to be behind the project.
	public var isStale: Bool { builtAt != staleness }

	// MARK: - Building

	/// Builds the list if it needs building, and joins a build in flight.
	///
	/// **At most one build per call, deliberately.** A build that lands after
	/// something else has moved is left stale rather than started again from
	/// here: the alternative is a loop that spins for as long as anything is
	/// writing, and what writes for minutes at a time is a compiler. The next
	/// caller — the next time the palette is opened — builds again, so it
	/// settles as soon as the writing stops and never before.
	public func prepare() async {
		if !isStale { return }
		if let building { return await building.value }

		let generation = staleness
		let task = Task { [root] in
			let listed = await ProjectFiles.list(in: root)
			self.adopt(listed, at: generation)
		}
		building = task
		await task.value
		building = nil
	}

	/// Says the list can no longer be trusted, without building anything.
	///
	/// For the case a filesystem event cannot describe: the kernel gave up on
	/// naming a burst file by file and said "scan this subtree instead", which
	/// is a checkout, a build or an install. Marking is all that happens on the
	/// event — a build produces them by the second, and each rebuild is a
	/// `git ls-files` over the whole repository. The build happens when somebody
	/// next asks, which is the moment it is worth paying for.
	public func markStale() {
		staleness += 1
	}

	/// Throws the list away and builds it again, now.
	public func rebuild() async {
		markStale()
		await prepare()
	}

	private func adopt(_ listed: [String], at generation: Int) {
		paths = listed.map(FileMatching.Candidate.init)
		known = Set(listed)
		builtAt = generation
	}

	// MARK: - Staying true

	/// Takes note of files that have appeared or gone.
	///
	/// Cheaper than rebuilding by the whole repository, and it is what makes a
	/// file saved a moment ago findable — which is exactly the file somebody is
	/// about to look for. It is also how the tracked-only list from git stays
	/// useful: a new file is untracked and git would not list it, but the
	/// filesystem names it.
	public func noticed(changed urls: [URL]) {
		guard builtAt != nil else { return }
		for url in urls {
			guard let path = ProjectFiles.relativePath(of: url, under: root) else { continue }
			let exists = FileManager.default.fileExists(atPath: url.path)
			if exists {
				guard !known.contains(path), !isExcluded(path) else { continue }
				known.insert(path)
				paths.append(FileMatching.Candidate(path))
			} else if known.remove(path) != nil {
				paths.removeAll { $0.path == path }
			}
		}
	}

	/// Whether a path is under a directory the walk would have skipped.
	///
	/// A filesystem event names files inside `node_modules` and `.git` like any
	/// other, so without this a build would put back everything the exclusions
	/// exist to keep out — and it would do it a file at a time, which is worse
	/// than a walk.
	private func isExcluded(_ path: String) -> Bool {
		let excluded = Set(Settings.shared.excludedDirectories)
		return path.split(separator: "/").dropLast().contains { component in
			component == ".git" || excluded.contains(String(component))
		}
	}

	// MARK: - Finding

	/// Paths matching what has been typed, best first.
	public func matches(_ query: String, limit: Int = 25) -> [String] {
		FileMatching.matches(for: query, in: paths, limit: limit)
	}
}







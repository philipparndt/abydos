import Foundation

/// Notices when the repository changes underneath the app.
///
/// Committing, pushing, rebasing and switching branches happen in terminals
/// as often as they happen here, and a history view showing what the
/// repository looked like ten minutes ago is worse than no history view: it
/// looks current.
public final class RepositoryWatcher {
	private var watcher: FileSystemWatcher?
	private let gitDirectory: URL
	private let onChange: ([URL]) -> Void
	private var pending: DispatchWorkItem?
	/// The directories that mattered since the last delivery.
	private var waiting: Set<URL> = []
	private var firstWaiting: Date?

	/// A single git command writes several files; this waits for the burst to
	/// finish rather than reloading once per file.
	private let settle: TimeInterval = 0.4
	/// But not for ever. Waiting only for quiet, a worktree added and removed
	/// in a loop — or a long rebase — never delivered until it stopped.
	private let cap: TimeInterval = 3

	/// - Parameter onChange: told which directories under the git directory
	///   changed, folded over the burst, so a listener can say which
	///   repositories that makes stale — see `GitEstateRefresh`.
	public init(gitDirectory: URL, onChange: @escaping ([URL]) -> Void) {
		self.gitDirectory = gitDirectory.standardizedFileURL
		self.onChange = onChange
	}

	deinit { stop() }

	/// The git directory for a work tree, which for a linked worktree is not
	/// the `.git` beside it.
	public static func directory(forRepositoryAt root: URL) async -> URL? {
		let result = await GitRepository.run(["rev-parse", "--absolute-git-dir"], in: root)
		let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard result.exitCode == 0, !path.isEmpty else { return nil }
		return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
	}

	public func start() {
		guard watcher == nil else { return }
		let created = FileSystemWatcher(root: gitDirectory, includesGitDirectory: true) {
			[weak self] change in
			// Which files git rewrote inside `.git` does not matter here; the
			// directories are what say whether a ref or the index moved.
			self?.handle(change.directories)
		}
		created.start()
		watcher = created
	}

	public func stop() {
		pending?.cancel()
		pending = nil
		waiting = []
		firstWaiting = nil
		watcher?.stop()
		watcher = nil
	}

	private func handle(_ directories: [URL]) {
		let mattering = directories.filter(Self.matters(directory:))
		guard !mattering.isEmpty else { return }

		let now = Date()
		let first = firstWaiting ?? now
		firstWaiting = first
		waiting.formUnion(mattering)

		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.deliver() }
		pending = work
		let delay = Self.delay(now: now, firstWaiting: first, settle: settle, cap: cap)
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
	}

	private func deliver() {
		let directories = Array(waiting)
		waiting = []
		firstWaiting = nil
		pending = nil
		onChange(directories)
	}

	/// How long until a delivery: `settle` after the latest change, but never
	/// later than `cap` after the first one still waiting.
	static func delay(now: Date, firstWaiting: Date, settle: TimeInterval, cap: TimeInterval) -> TimeInterval {
		max(0, min(settle, firstWaiting.addingTimeInterval(cap).timeIntervalSince(now)))
	}

	/// Whether a change in this directory could have changed what is shown.
	///
	/// Loose objects arrive by the thousand during a fetch and say nothing
	/// about what any branch points at; refs, HEAD and the index say
	/// everything.
	static func matters(directory: URL) -> Bool {
		let path = directory.path
		if path.contains("/objects") || path.contains("/lfs") { return false }
		return true
	}
}

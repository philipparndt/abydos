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
	private let onChange: () -> Void
	private var pending: DispatchWorkItem?

	/// A single git command writes several files; this waits for the burst to
	/// finish rather than reloading once per file.
	private let settle: TimeInterval = 0.4

	public init(gitDirectory: URL, onChange: @escaping () -> Void) {
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
			[weak self] directories in
			self?.handle(directories)
		}
		created.start()
		watcher = created
	}

	public func stop() {
		pending?.cancel()
		pending = nil
		watcher?.stop()
		watcher = nil
	}

	private func handle(_ directories: [URL]) {
		guard directories.contains(where: Self.matters(directory:)) else { return }

		pending?.cancel()
		let work = DispatchWorkItem { [onChange] in onChange() }
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: work)
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

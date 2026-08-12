import Foundation

/// Version-control state of a single path, as the navigator colours it.
public enum GitFileStatus: Sendable, Equatable {
	case unmodified
	case added
	case modified
	case deleted
	case unversioned
	case ignored
	case conflicted

	/// Which state wins when a directory aggregates its children.
	/// A directory should look "modified" if anything inside it changed.
	var severity: Int {
		switch self {
		case .unmodified:  return 0
		case .ignored:     return 1
		case .unversioned: return 2
		case .deleted:     return 3
		case .added:       return 4
		case .modified:    return 5
		case .conflicted:  return 6
		}
	}
}

/// Reads version-control state by shelling out to `git`.
///
/// Shelling out rather than linking libgit2 is a deliberate trade: one
/// `git status` invocation costs a few milliseconds even on a large repo, it is
/// always consistent with what the user sees on the command line, and it brings
/// no native dependency. Results are cached and refreshed on filesystem events.
public actor GitRepository {
	public let root: URL

	private var statusCache: [String: GitFileStatus] = [:]
	private var directoryCache: [String: GitFileStatus] = [:]
	private var headState: Head = .detached

	public init(root: URL) {
		self.root = root
	}

	/// Where `HEAD` points.
	///
	/// Three states and not two, because there are three. A repository made by
	/// `git init` and not yet committed to is *on* a branch — `.git/HEAD` says
	/// `ref: refs/heads/main` from the first moment — and what does not exist is
	/// a commit for that name to point at. Calling it "no branch" put it in with
	/// a detached checkout and with a directory that is not a work tree at all,
	/// which is how the titlebar came to show nothing for a repository whose
	/// branch name was sitting in a file (item 0477).
	public enum Head: Sendable, Equatable {
		/// A branch with at least one commit on it.
		case branch(String)
		/// A branch that exists as a name only: nothing has been committed yet.
		case unborn(String)
		/// No branch — a commit, tag or remote ref checked out directly. Also
		/// what a directory that is not a work tree answers, which every caller
		/// wants to read the same way: there is no branch name to show.
		case detached

		/// The branch's name, or nil when there is not one.
		public var name: String? {
			switch self {
			case .branch(let name), .unborn(let name): return name
			case .detached: return nil
			}
		}

		/// A branch with nothing on it yet.
		public var isUnborn: Bool {
			if case .unborn = self { return true }
			return false
		}
	}

	/// Which branch the work tree is on, and whether anything is on it.
	///
	/// The one place that asks. It used to be asked in four, all of them with
	/// `rev-parse --abbrev-ref HEAD`, which **resolves the commit and then names
	/// it** — so in a repository where nothing has been committed it fails
	/// outright rather than answering, and the branch name is right there in
	/// `.git/HEAD` while rev-parse says `fatal: ambiguous argument 'HEAD'`.
	///
	/// `symbolic-ref` reads the reference itself, which is the question being
	/// asked, and it is plumbing, so its output is a promise rather than a
	/// convenience. `branch --show-current` answers the same thing, but it is
	/// porcelain, it needs git 2.22, and it prints an empty line for a detached
	/// HEAD where symbolic-ref exits non-zero — a second rule to remember for no
	/// gain.
	///
	/// A detached HEAD comes back `.detached` because symbolic-ref *fails*
	/// there. The old question answered the literal string `HEAD` for it, and
	/// every one of the four callers separately had to know to turn that into
	/// nil.
	public static func head(in root: URL) async -> Head {
		// `--quiet` so a detached HEAD is an exit code rather than a line on
		// stderr; it is an ordinary state, not an error.
		async let symbolic = run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: root)
		// Asked at the same time rather than after it, because two processes in
		// parallel cost what one does, and this is the question that separates a
		// branch from an unborn one: `--verify --quiet` is exit 0 when HEAD
		// resolves to a commit and exit 1, silently, when there is none.
		async let resolved = run(["rev-parse", "--verify", "--quiet", "HEAD"], in: root)

		let symbolicResult = await symbolic
		let name = symbolicResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard symbolicResult.exitCode == 0, !name.isEmpty else {
			// Still awaited: an `async let` dropped without being read is a
			// cancelled child task, and cancelling a subprocess we started is
			// not what "we do not need the answer" should mean.
			_ = await resolved
			return .detached
		}
		return await resolved.exitCode == 0 ? .branch(name) : .unborn(name)
	}

	/// Locates the enclosing work tree, or nil if the directory is not in one.
	public static func discover(from directory: URL) async -> GitRepository? {
		let result = await Self.run(
			["rev-parse", "--show-toplevel"],
			in: directory
		)
		guard result.exitCode == 0 else { return nil }
		let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !path.isEmpty else { return nil }
		// Standardized, as the project's own root is: git answers with the real
		// path — `/private/tmp/...` — where the tree holds `/tmp/...`, and every
		// file in the tree then failed to match its own repository and was drawn
		// as if git had never heard of it.
		return GitRepository(
			root: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
		)
	}

	public func currentBranch() -> String? { headState.name }

	/// The branch and whether it has anything on it, as of the last refresh.
	public func currentHead() -> Head { headState }

	/// How many files the working copy has that HEAD does not agree with.
	///
	/// Ignored files are not changes — a build directory is not something
	/// anybody is going to commit — and the count is what the commit button
	/// uses to say, without being opened, that there is something to do.
	public func changedFileCount() -> Int {
		statusCache.values.filter { $0 != .unmodified && $0 != .ignored }.count
	}

	/// Re-reads branch and per-file status.
	public func refresh() async {
		async let head = Self.head(in: root)
		async let status = Self.run(
			// --porcelain=v1 is a stability-guaranteed format. -uall lists files
			// inside untracked directories instead of collapsing to the directory,
			// which the tree needs in order to colour individual rows.
			// `-z` so paths arrive literally: without it anything non-ASCII comes
			// back octal-escaped inside quotes, and the tree would then key its
			// status by a name no row actually has.
			["status", "--porcelain=v1", "-uall", "--ignored=matching", "--no-renames", "-z"],
			in: root
		)

		// Assigned whatever comes back, rather than only on success as the old
		// `rev-parse` guard did. That guard kept the last known branch when git
		// failed — but the commonest failure it was covering for was a
		// repository with nothing committed, which now has an answer, and
		// keeping a stale name through a real failure is worse than saying
		// nothing.
		headState = await head

		let statusResult = await status
        guard statusResult.exitCode == 0 else { return }
		parse(porcelain: statusResult.stdout)
	}

	/// Internal rather than private so the status rules can be unit-tested
	/// against porcelain fixtures without needing a real repository.
	func parse(porcelain: String) {
		// Handles both separators: `-z` in production, newlines in the fixtures
		// the status rules are tested against.
		let separator: Character = porcelain.contains("\0") ? "\0" : "\n"
		var files: [String: GitFileStatus] = [:]
		// Built fresh beside the files, and for the same reason. What was here
		// before is what git said last time, and an ignore rule that has since
		// been changed makes that a statement about a state of the world that no
		// longer exists.
		var directories: [String: GitFileStatus] = [:]

		for line in porcelain.split(separator: separator, omittingEmptySubsequences: true) {
			guard line.count > 3 else { continue }
			let codes = line.prefix(2)
			// Quoted only when git was not asked for -z; the decoder handles the
			// octal escapes either way.
			var path = GitWorkingCopy.unquote(String(line.dropFirst(3)))
			// Directory entries (ignored dirs) arrive with a trailing slash.
			let isDirectory = path.hasSuffix("/")
			if isDirectory { path = String(path.dropLast()) }

			let status = Self.status(forCodes: String(codes))
			files[path] = status
			if isDirectory {
				directories[path] = status
			}
		}

		statusCache = files
		// Replaced, not filtered. This used to keep every ignored directory it
		// had ever seen — the filter dropped the memoised rollups and left the
		// explicit entries from earlier parses behind — so a folder that stopped
		// being ignored stayed grey however many times the status was re-read.
		// Adding `!backlog/` to an ignore file and saving it looked like nothing
		// happening at all, until the project was closed and opened again.
		directoryCache = directories
		// The rollups are derived from both, and are recomputed lazily.
		rollupCache = [:]
	}

	private static func status(forCodes codes: String) -> GitFileStatus {
		let chars = Array(codes)
		guard chars.count == 2 else { return .unmodified }
		let (index, worktree) = (chars[0], chars[1])

		// Both sides modified, or any 'U' — a merge conflict.
		if index == "U" || worktree == "U" || (index == "A" && worktree == "A") || (index == "D" && worktree == "D") {
			return .conflicted
		}
		if index == "?" && worktree == "?" { return .unversioned }
		if index == "!" && worktree == "!" { return .ignored }
		if index == "A" || worktree == "A" { return .added }
		if index == "D" || worktree == "D" { return .deleted }
		if index == "M" || worktree == "M" || index == "R" || index == "C" { return .modified }
		return .unmodified
	}

	private var rollupCache: [String: GitFileStatus] = [:]

	/// Status for a path relative to the repository root.
	///
	/// Directories aggregate the most severe status among their descendants, so a
	/// collapsed folder still signals that something inside it changed.
	public func status(forRelativePath path: String, isDirectory: Bool) -> GitFileStatus {
		if !isDirectory {
			if let direct = statusCache[path] { return direct }
			// A file inside an ignored directory has no entry of its own.
			return inheritedIgnore(for: path) ?? .unmodified
		}

		if let cached = rollupCache[path] { return cached }
		if let explicit = directoryCache[path] {
			rollupCache[path] = explicit
			return explicit
		}
		if let inherited = inheritedIgnore(for: path) {
			rollupCache[path] = inherited
			return inherited
		}

		let prefix = path.isEmpty ? "" : path + "/"
		var worst = GitFileStatus.unmodified
		for (candidate, status) in statusCache where candidate.hasPrefix(prefix) {
			// A directory is *not* ignored merely because something inside it is.
			// Almost every project has a tracked directory holding build output,
			// and dimming those would grey out most of the tree. Only an explicit
			// entry or an ignored ancestor — both handled above — make a
			// directory itself ignored.
			if status == .ignored { continue }
			if status.severity > worst.severity { worst = status }
		}
		rollupCache[path] = worst
		return worst
	}

	/// Status for many paths, answered in one visit.
	///
	/// The same answers as calling `status(forRelativePath:isDirectory:)` in a
	/// loop, and it exists because of what that loop costs the *caller*. The
	/// navigator asks for one node of the tree at a time, and every one of those
	/// is a hop onto this actor and a continuation back — thousands of them per
	/// refresh, every one of which is a block scheduled on the main queue, all of
	/// them interleaving with the terminal's own drain. The subprocess was
	/// already off the main thread; it was the *shape of the loop* that put the
	/// work back on it.
	///
	/// In the same order as it was asked, one answer each, which is what lets the
	/// caller match them up without this having to know how it keys them.
	public func statuses(for paths: [(path: String, isDirectory: Bool)]) -> [GitFileStatus] {
		paths.map { status(forRelativePath: $0.path, isDirectory: $0.isDirectory) }
	}

	/// Walks up ancestors looking for an ignored directory.
	private func inheritedIgnore(for path: String) -> GitFileStatus? {
		var components = path.split(separator: "/").map(String.init)
		while components.count > 1 {
			components.removeLast()
			if directoryCache[components.joined(separator: "/")] == .ignored { return .ignored }
		}
		return nil
	}

	// MARK: - Process helpers

	public struct ProcessResult: Sendable {
		public var stdout: String
		public var stderr: String
		public var exitCode: Int32
	}

	/// Runs a git subcommand. Exposed so UI code can drive clone and checkout
	/// without duplicating the process plumbing.
	public static func run(
		_ arguments: [String],
		in directory: URL,
		input: Data? = nil,
		environment: [String: String] = [:]
	) async -> ProcessResult {
		await withCheckedContinuation { continuation in
			// Hop off the caller so a slow `git` never blocks the UI.
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: runSync(
					arguments, in: directory, input: input, environment: environment
				))
			}
		}
	}

	static func runSync(
		_ arguments: [String],
		in directory: URL,
		input: Data? = nil,
		environment: [String: String] = [:]
	) -> ProcessResult {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = arguments
		process.currentDirectoryURL = directory

		// Keep git from consulting the terminal or a credential helper, with
		// whatever the caller asked for on top.
		//
		// This used to be assigned twice — the caller's merge first, then this
		// one — so the second assignment silently threw the caller's
		// environment away and nothing that passed one ever had it applied.
		var env = ProcessInfo.processInfo.environment
		env["GIT_TERMINAL_PROMPT"] = "0"
		env["GIT_OPTIONAL_LOCKS"] = "0"
		for (key, value) in environment { env[key] = value }
		process.environment = env

		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err

		// stdin is a pipe whether or not there is anything to send: git that
		// inherited ours would read from whatever the app was started with.
		let stdin = Pipe()
		process.standardInput = stdin

		do {
			try process.run()
		} catch {
			return ProcessResult(stdout: "", stderr: "\(error)", exitCode: -1)
		}

		// Both pipes drained at the same time, and stdin written on a thread of
		// its own. Reading stdout to the end and stderr afterwards deadlocks
		// against a program blocked writing to the pipe nobody is reading —
		// see ProcessPipes, and the several afternoons it cost.
		let captured = ProcessPipes.drainText(
			process, out: out, err: err, input: input, stdin: stdin
		)

		return ProcessResult(
			stdout: captured.stdout,
			stderr: captured.stderr,
			exitCode: process.terminationStatus
		)
	}
}

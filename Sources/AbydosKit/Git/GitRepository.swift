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
	/// Not isolated, because it never changes and because of who asks for it.
	/// The branch pill's menu wanted the repository's own path, and asking for
	/// it was a hop onto this actor — which queues behind whatever synchronous
	/// work the actor is already doing, and this actor's work is measured in
	/// tens of thousands of paths. A `let` of a `Sendable` type has nothing to
	/// serialise and no reason to make anybody wait (item 0498).
	public nonisolated let root: URL

	private var statusCache: [String: GitFileStatus] = [:]
	private var directoryCache: [String: GitFileStatus] = [:]

	/// The ignored paths, kept apart from everything else because they are read
	/// on a different schedule.
	///
	/// What is ignored changes when an ignore *rule* changes, which happens
	/// when somebody edits a `.gitignore` — not when a build writes a file.
	/// Everything else in here is re-read on every filesystem event; asking git
	/// for the ignored set that often is what made a large work tree unusable,
	/// because `--ignored` is the flag that switches the untracked cache off.
	/// So it has its own cache, its own read, and a fingerprint that says when
	/// the read is worth doing again.
	private var ignoredCache: [String: GitFileStatus] = [:]
	/// The ignored entries that are directories, for inheriting down.
	private var ignoredDirectories: Set<String> = []
	/// What the ignore rules looked like when `ignoredCache` was filled, or nil
	/// when it never has been.
	private var ignoreRulesFingerprint: String?

	private var headState: Head = .detached {
		didSet { headSnapshot.value = headState }
	}

	/// The last known head, readable without touching the actor.
	///
	/// The same value as `headState` and kept in step with it. It exists for the
	/// branch pill: opening that menu is not an expensive question — reading a
	/// string that is already in memory — and it used to sit behind a queue of
	/// rollup scans over a hundred thousand paths, which is what "clicking the
	/// branch takes ages" was.
	private nonisolated let headSnapshot = HeadSnapshot()

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

	/// The same answer, without waiting for the actor.
	///
	/// For anything that only wants to *show* the branch — the titlebar pill and
	/// the menu under it. `currentHead()` is the same value and is the one to
	/// use when the caller is already on the actor's side of the fence.
	public nonisolated var lastKnownHead: Head { headSnapshot.value }

	/// How many entries the working copy has that HEAD does not agree with.
	///
	/// Entries and not files, which is the same thing for everything git names
	/// individually and one thing for a wholly untracked directory it named as a
	/// whole. That is deliberately the same arithmetic the changes pane does, so
	/// the badge on the strip and the count in the pane agree — they used to
	/// disagree by four orders of magnitude on a work tree full of build output,
	/// because one asked for `-uall` and the other did not.
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
			// --porcelain=v1 is a stability-guaranteed format.
			//
			// **Neither `-uall` nor `--ignored`, and the reason is git's untracked
			// cache.** This used to ask for `-uall --ignored=matching`, on the
			// grounds that the tree needs a status per row and those two flags
			// give one for every file. What they also do is switch off the
			// untracked cache — git cannot reuse a cached per-directory answer
			// when it has been asked to report the files inside an ignored
			// directory — so every refresh walked the whole work tree cold, and
			// this runs on every filesystem event.
			//
			// Measured on a repository with 69,829 untracked files in 15,376
			// folders (build output, which is what any large project's work tree
			// is mostly made of): four consecutive runs of the old command took
			// 6.4 s, 16.2 s, 59.7 s and 26.8 s — it never warms up, because there
			// is no cache to warm. The same question without those two flags is a
			// steady 0.11 s, and returns 425 records instead of 108,150.
			//
			// What is given up is nothing. `-unormal` collapses a wholly
			// untracked directory to one `dir/` entry, and every file inside a
			// directory git collapsed is untracked *by definition* — that is why
			// it was collapsed — so `inherited(for:)` colours those rows from the
			// directory's own entry rather than from an entry of their own. The
			// ignored set is still read in full, by `refreshIgnored()`, on the
			// schedule the question actually has: when an ignore rule changes.
			//
			// `-z` so paths arrive literally: without it anything non-ASCII comes
			// back octal-escaped inside quotes, and the tree would then key its
			// status by a name no row actually has.
			["status", "--porcelain=v1", "-unormal", "--no-renames", "-z"],
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

	// MARK: - What is ignored

	/// Whether the ignored set is worth reading again.
	///
	/// Cheap on purpose — this is asked once per refresh, and a refresh happens
	/// on every filesystem event. It stats the ignore files rather than reading
	/// them: an edit that changes what is ignored changes a file's size or its
	/// modification date, and a build writing ten thousand class files changes
	/// neither.
	public func needsIgnoredRefresh() async -> Bool {
		await Self.ignoreRulesFingerprint(in: root) != ignoreRulesFingerprint
	}

	/// Re-reads which paths git ignores.
	///
	/// The expensive one — `--ignored` cannot use the untracked cache, so this
	/// walks the work tree cold, which on a large repository is seconds. It is
	/// called when the ignore rules have moved and not otherwise, so those
	/// seconds are paid once when a project opens and again when somebody saves
	/// a `.gitignore`, rather than dozens of times a minute during a build.
	///
	/// `-unormal` for the same reason `refresh()` uses it: an ignored directory
	/// arrives as one `dir/` entry, and the rows inside it inherit from that.
	public func refreshIgnored() async {
		// Read before the walk, not after: if somebody saves a `.gitignore`
		// while this is running, the fingerprint stored is the one this answer
		// belongs to, and the next refresh notices the difference and asks
		// again. Stored the other way round, that edit would be swallowed.
		let fingerprint = await Self.ignoreRulesFingerprint(in: root)

		let result = await Self.run(
			["status", "--porcelain=v1", "-unormal", "--ignored=traditional",
			 "--no-renames", "-z"],
			in: root
		)
		guard result.exitCode == 0 else { return }

		var ignored: [String: GitFileStatus] = [:]
		var directories: Set<String> = []
		for record in result.stdout.split(separator: "\0", omittingEmptySubsequences: true) {
			guard record.count > 3, record.hasPrefix("!!") else { continue }
			var path = GitWorkingCopy.unquote(String(record.dropFirst(3)))
			if path.hasSuffix("/") {
				path = String(path.dropLast())
				directories.insert(path)
			}
			guard !path.isEmpty else { continue }
			ignored[path] = .ignored
		}

		// Replaced wholesale, for the reason the directory cache is: what was
		// here before is what git said under the old rules, and a folder that
		// has stopped being ignored has to stop being grey.
		ignoredCache = ignored
		ignoredDirectories = directories
		ignoreRulesFingerprint = fingerprint
	}

	/// A cheap summary of every ignore rule that applies to this work tree.
	///
	/// The tracked `.gitignore` files, `.git/info/exclude` and the global
	/// excludes file, each as its size and modification date. `ls-files` reads
	/// the index and never touches the work tree, so finding them costs
	/// milliseconds even where there are more than a thousand.
	///
	/// Untracked `.gitignore` files are deliberately left out. One only affects
	/// its own directory and below, and a directory holding an untracked
	/// `.gitignore` is itself untracked — so everything under it is already
	/// coloured by inheriting from it, whatever the rules inside say.
	private static func ignoreRulesFingerprint(in root: URL) async -> String {
		let listed = await run(
			["ls-files", "-z", "--cached", "--", "*.gitignore", ".gitignore"],
			in: root
		)
		var paths = listed.exitCode == 0
			? listed.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
			: []
		paths.append(".git/info/exclude")

		var files = paths.map { root.appendingPathComponent($0) }
		let global = await run(["config", "--get", "core.excludesFile"], in: root)
		let globalPath = global.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		if !globalPath.isEmpty {
			files.append(URL(fileURLWithPath: NSString(string: globalPath).expandingTildeInPath))
		}

		// Sorted so the same set of files always produces the same string:
		// `ls-files` is ordered, but the two appended entries are not part of
		// that order and a fingerprint that depends on assembly order would
		// report a change that had not happened.
		return files
			.map { url -> String in
				let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
				let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
				let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
				return "\(url.path):\(size):\(modified)"
			}
			.sorted()
			.joined(separator: "\n")
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
		rollupCache = Self.rollups(of: files)
	}

	/// The worst status under each directory, computed once for the whole set.
	///
	/// **Once, walking ancestors — not per directory, scanning everything.** A
	/// directory's colour used to be worked out by sweeping the entire status
	/// cache and prefix-matching every key against it, memoised per directory.
	/// That is O(changes) for one row and O(rows × changes) for a refresh, it
	/// ran synchronously on the actor, and on a work tree with a hundred
	/// thousand entries it was tens of millions of string comparisons with
	/// everything else — the branch pill included — waiting behind it.
	///
	/// Walking each entry's own ancestors instead costs one pass over the
	/// entries and touches each path component once, and it answers the same
	/// question: a directory is as bad as the worst thing beneath it.
	private static func rollups(of files: [String: GitFileStatus]) -> [String: GitFileStatus] {
		var worst: [String: GitFileStatus] = [:]

		for (path, status) in files {
			// A directory is *not* ignored merely because something inside it
			// is. Almost every project has a tracked directory holding build
			// output, and dimming those would grey out most of the tree. Only an
			// explicit entry or an ignored ancestor makes a directory ignored,
			// and both are answered before the rollups are consulted.
			guard status != .ignored else { continue }

			var components = path.split(separator: "/").map(String.init)
			// The entry's own name: its status is in `statusCache` already, and
			// what is being built here is what its *parents* should look like.
			guard !components.isEmpty else { continue }
			components.removeLast()

			while true {
				let directory = components.joined(separator: "/")
				// The root is "" and is a real key: the project's own row.
				if status.severity > (worst[directory]?.severity ?? -1) {
					worst[directory] = status
				} else {
					// Every shallower ancestor has already been given something
					// at least this severe by whatever wrote this one.
					break
				}
				guard !components.isEmpty else { break }
				components.removeLast()
			}
		}
		return worst
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
			// A file inside a directory git collapsed has no entry of its own.
			if let inherited = inherited(for: path) { return inherited }
			return ignoredCache[path] ?? .unmodified
		}

		// An explicit entry first: a collapsed `dir/` is git saying the whole
		// directory is one thing, and that is more specific than a rollup.
		if let explicit = directoryCache[path] { return explicit }
		if let rolled = rollupCache[path] { return rolled }
		if let inherited = inherited(for: path) { return inherited }
		// Last, and only where nothing else had anything to say. A directory
		// with a change under it is not ignored however many ignored files sit
		// beside that change — almost every project keeps its build output
		// inside a tracked directory, and dimming those would grey out the tree.
		return ignoredCache[path] ?? .unmodified
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

	/// Walks up ancestors looking for a directory git answered as a whole.
	///
	/// Two statuses come back that way and both are inherited exactly rather
	/// than approximately. An ignored directory's contents are ignored — that is
	/// what the rule said. An untracked directory's contents are untracked *by
	/// definition*: git collapses a directory to `dir/` only when it has nothing
	/// tracked inside it, so a row under one cannot be anything else.
	///
	/// Which is why asking for `-uall` bought nothing. It made git name each of
	/// those files individually, at the price of the untracked cache and of a
	/// hundred thousand entries to carry around, to say what the directory above
	/// them already said.
	private func inherited(for path: String) -> GitFileStatus? {
		var components = path.split(separator: "/").map(String.init)
		while components.count > 1 {
			components.removeLast()
			let ancestor = components.joined(separator: "/")
			// The nearest one wins, so both maps are asked at each level before
			// moving further up. An ignored directory inside an untracked one is
			// possible, and so is the other way round.
			if ignoredDirectories.contains(ancestor) { return .ignored }
			switch directoryCache[ancestor] {
			case .ignored: return .ignored
			case .unversioned: return .unversioned
			default: continue
			}
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

/// A `Head` that can be read from anywhere, holding a lock rather than an actor.
///
/// Exists for one caller: the branch pill, which wants to show a name it already
/// knows without joining the queue for an actor that is busy with a hundred
/// thousand paths. A lock held for the length of one assignment is the whole
/// cost, against a hop and a continuation for the alternative.
final class HeadSnapshot: @unchecked Sendable {
	private let lock = NSLock()
	private var stored: GitRepository.Head = .detached

	var value: GitRepository.Head {
		get { lock.withLock { stored } }
		set { lock.withLock { stored = newValue } }
	}
}

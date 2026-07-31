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
	private var branchName: String?

	public init(root: URL) {
		self.root = root
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
		return GitRepository(root: URL(fileURLWithPath: path, isDirectory: true))
	}

	public func currentBranch() -> String? { branchName }

	/// Re-reads branch and per-file status.
	public func refresh() async {
		async let branch = Self.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
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

		let branchResult = await branch
		if branchResult.exitCode == 0 {
			let name = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
			branchName = (name.isEmpty || name == "HEAD") ? nil : name
		}

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
				directoryCache[path] = status
			}
		}

		statusCache = files
		// Directory rollups are recomputed lazily; drop the memoised values.
		directoryCache = directoryCache.filter { _, v in v == .ignored }
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
		input: Data? = nil
	) async -> ProcessResult {
		await withCheckedContinuation { continuation in
			// Hop off the caller so a slow `git` never blocks the UI.
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: runSync(arguments, in: directory, input: input))
			}
		}
	}

	static func runSync(_ arguments: [String], in directory: URL, input: Data? = nil) -> ProcessResult {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = arguments
		process.currentDirectoryURL = directory

		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err

		// A patch arrives on stdin. Without a pipe here git would inherit ours
		// and block reading from a terminal that is not there.
		let stdin = Pipe()
		if input != nil { process.standardInput = stdin }
		// Keep git from consulting the terminal or a credential helper.
		var env = ProcessInfo.processInfo.environment
		env["GIT_TERMINAL_PROMPT"] = "0"
		env["GIT_OPTIONAL_LOCKS"] = "0"
		process.environment = env

		do {
			try process.run()
		} catch {
			return ProcessResult(stdout: "", stderr: "\(error)", exitCode: -1)
		}

		if let input {
			// Written before the pipes are drained, and closed so git sees EOF.
			stdin.fileHandleForWriting.write(input)
			try? stdin.fileHandleForWriting.close()
		}

		// Read both pipes before waiting; a full pipe buffer would otherwise
		// deadlock against a process that is still writing.
		let outData = out.fileHandleForReading.readDataToEndOfFile()
		let errData = err.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()

		return ProcessResult(
			stdout: String(decoding: outData, as: UTF8.self),
			stderr: String(decoding: errData, as: UTF8.self),
			exitCode: process.terminationStatus
		)
	}
}

import Foundation

/// One checkout of a repository.
public struct GitWorktree: Equatable, Sendable, Identifiable {
	public let path: URL
	/// The branch checked out here, or nil when the head is detached.
	public let branch: String?
	/// The commit it is on.
	public let head: String
	/// The one the repository was cloned into, which cannot be removed.
	public let isPrimary: Bool
	/// A worktree whose directory is gone — the usual state after somebody
	/// deletes one with `rm -rf` instead of `git worktree remove`.
	public let isMissing: Bool
	public let isLocked: Bool

	public var id: String { path.path }
	public var name: String { path.lastPathComponent }

	/// The branch is real and named, and nothing has been committed on it yet —
	/// a checkout straight out of `git init`.
	///
	/// Read off the head rather than asked for: `git worktree list --porcelain`
	/// answers `HEAD 0000000000000000000000000000000000000000` beside a perfectly
	/// good `branch refs/heads/main`, which 0477 confirmed while walking the git
	/// surface of a repository with no commits. So the third of that item's three
	/// states is already in the output, for free, and nothing has to run.
	public var isUnborn: Bool {
		!head.isEmpty && head.allSatisfy { $0 == "0" }
	}

	/// How this checkout reads when it has to be named beside the others.
	///
	/// The three states 0477 settled for the titlebar's branch, said in one line
	/// because a menu row has one: a branch, a branch with nothing on it, or a
	/// commit checked out directly. Nothing is the one answer that is not
	/// allowed — `detached` used to arrive here as an empty string and a row that
	/// said only its folder name was the same silence 0477 was filed about.
	public var summary: String {
		if let branch {
			return isUnborn ? "\(branch) — no commits yet" : branch
		}
		// Seven characters, which is what git abbreviates to and what anybody
		// pasting it back into git will be given anyway.
		return head.isEmpty ? "detached" : "detached at \(head.prefix(7))"
	}

	public init(
		path: URL,
		branch: String?,
		head: String,
		isPrimary: Bool,
		isMissing: Bool = false,
		isLocked: Bool = false
	) {
		self.path = path
		self.branch = branch
		self.head = head
		self.isPrimary = isPrimary
		self.isMissing = isMissing
		self.isLocked = isLocked
	}
}

/// Listing, adding and removing worktrees.
///
/// A worktree is the answer to "I need to look at another branch without
/// putting this one down" — a second directory on the same repository, with
/// its own index and its own checked-out files. The alternative is stashing,
/// which is a worse version of the same thing.
public enum GitWorktrees {
	/// Every worktree of a repository, the primary one first.
	public static func list(in root: URL) async -> [GitWorktree] {
		let result = await GitRepository.run(["worktree", "list", "--porcelain"], in: root)
		guard result.exitCode == 0 else { return [] }
		return parse(result.stdout)
	}

	/// `git worktree list --porcelain` emits records separated by blank lines,
	/// each a set of `key value` lines with bare keys for the flags.
	static func parse(_ text: String) -> [GitWorktree] {
		var worktrees: [GitWorktree] = []
		var path: URL?
		var head = ""
		var branch: String?
		var isLocked = false
		var isMissing = false

		func flush() {
			guard let path else { return }
			worktrees.append(GitWorktree(
				path: path,
				branch: branch,
				head: head,
				// The first record is the repository's own checkout.
				isPrimary: worktrees.isEmpty,
				isMissing: isMissing,
				isLocked: isLocked
			))
			branch = nil
			head = ""
			isLocked = false
			isMissing = false
		}

		for line in text.components(separatedBy: "\n") {
			if line.isEmpty {
				flush()
				path = nil
				continue
			}

			let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
			switch parts.first {
			case "worktree":
				flush()
				// Standardized, as `GitRepository.discover` already does with
				// `rev-parse --show-toplevel` and for the same reason: git
				// answers with the real path — `/private/var/...` — where the
				// project holds `/var/...`, and the caller decides which
				// worktree it is in by comparing the two. Unstandardised, a
				// project under `/tmp` or `/var` matched none of its own
				// worktrees and the chip that names the branch never appeared.
				path = parts.count > 1
					? URL(fileURLWithPath: parts[1], isDirectory: true).standardizedFileURL
					: nil
			case "HEAD":
				head = parts.count > 1 ? parts[1] : ""
			case "branch":
				// Given as a full ref; the short name is what anybody calls it.
				branch = parts.count > 1
					? parts[1].replacingOccurrences(of: "refs/heads/", with: "")
					: nil
			case "detached":
				branch = nil
			case "locked":
				isLocked = true
			case "prunable":
				isMissing = true
			default:
				break
			}
		}
		flush()
		return worktrees
	}

	/// Makes a worktree at `path`.
	///
	/// - `branch`: the branch to check out there. When `createBranch` is set it
	///   is made first, from `startPoint` or the current head.
	@discardableResult
	public static func add(
		at path: URL,
		branch: String,
		createBranch: Bool,
		startPoint: String? = nil,
		in root: URL
	) async -> GitRepository.ProcessResult {
		var arguments = ["worktree", "add"]
		if createBranch {
			arguments += ["-b", branch]
		}
		arguments.append(path.path)
		if createBranch {
			if let startPoint { arguments.append(startPoint) }
		} else {
			arguments.append(branch)
		}
		return await GitRepository.run(arguments, in: root)
	}

	/// Removes a worktree, refusing while it has changes unless forced.
	@discardableResult
	public static func remove(
		_ worktree: GitWorktree,
		force: Bool = false,
		in root: URL
	) async -> GitRepository.ProcessResult {
		var arguments = ["worktree", "remove"]
		if force { arguments.append("--force") }
		arguments.append(worktree.path.path)
		return await GitRepository.run(arguments, in: root)
	}

	/// Forgets worktrees whose directories are gone.
	@discardableResult
	public static func prune(in root: URL) async -> GitRepository.ProcessResult {
		await GitRepository.run(["worktree", "prune"], in: root)
	}

	/// Where a new worktree should go by default.
	///
	/// Beside the repository rather than inside it: a worktree within the work
	/// tree would show up as an untracked directory in its own status, and the
	/// first thing anybody would do is add it to `.gitignore` — which is a
	/// worse answer than putting it somewhere else.
	public static func suggestedPath(for branch: String, root: URL) -> URL {
		let safe = branch
			.replacingOccurrences(of: "/", with: "-")
			.replacingOccurrences(of: " ", with: "-")
		let parent = root.deletingLastPathComponent()
		return parent.appendingPathComponent("\(root.lastPathComponent)-\(safe)", isDirectory: true)
	}
}

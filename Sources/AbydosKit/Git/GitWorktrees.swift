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

	/// The primary first, then most recently worked on first.
	///
	/// A list of checkouts in git's own order is a list in the order they were
	/// created, which for a repository somebody has been working in for months is
	/// close to random. Ordering by activity puts what is being worked on at the
	/// top, which is what makes a menu of it usable at all — this repository has
	/// **74**, about fifty from `abydos-backlog start` and twenty an agent
	/// harness left under `.claude/worktrees/`.
	///
	/// The primary is pinned rather than left to the ordering because it is the
	/// way back — the checkout every other one was made from — and on a
	/// repository whose main branch has been quiet for a week it would otherwise
	/// sink below fifty branches somebody is actually on.
	///
	/// Everything else is `ProjectDiscovery.lastActivity`, which stats git's
	/// metadata rather than running git; it was written for the project scan with
	/// the note that *"this list can run to hundreds"*, which turns out to be the
	/// literal case here. Seventy-four `git log`s to sort a menu would be a pause
	/// in front of a click.
	public static func byRecentActivity(_ worktrees: [GitWorktree]) -> [GitWorktree] {
		// Measured once per checkout rather than inside the comparison, which
		// would stat each of them some tens of times over.
		let activity = Dictionary(
			worktrees.map { ($0.path.path, ProjectDiscovery.lastActivity(of: $0.path)) },
			uniquingKeysWith: { first, _ in first }
		)
		return worktrees.sorted { left, right in
			if left.isPrimary != right.isPrimary { return left.isPrimary }
			let a = activity[left.path.path] ?? .distantPast
			let b = activity[right.path.path] ?? .distantPast
			// By name when the times tie, so two readings of the same repository
			// do not shuffle the menu under somebody who is looking at it. A
			// worktree whose directory is gone has no mtime at all, and there can
			// be any number of those.
			return a == b ? left.name < right.name : a > b
		}
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
		root.deletingLastPathComponent().appendingPathComponent(
			suggestedName(for: branch, repository: root.lastPathComponent),
			isDirectory: true
		)
	}

	/// The directory name `suggestedPath` would give a worktree of this branch.
	///
	/// Apart from the path so that a *name already on disk* can be tested against
	/// it, which is how a list of them tells a folder that says something from
	/// one that only repeats the branch beside it. See `label(for:primaryName:)`.
	public static func suggestedName(for branch: String, repository: String) -> String {
		let safe = branch
			.replacingOccurrences(of: "/", with: "-")
			.replacingOccurrences(of: " ", with: "-")
		return "\(repository)-\(safe)"
	}

	/// What names this checkout in a list of them.
	///
	/// **The obvious row is the same words twice.** Every worktree this app makes
	/// — from the branches pane and from `abydos-backlog start` alike — is named
	/// by `suggestedPath`, which builds the directory *out of* the branch, so
	/// folder and branch together read:
	///
	///     abydos-backlog-0479-toggle-comment-answers-to-a-key-nobody-asked-for-on-a
	///       — backlog/0479-toggle-comment-answers-to-a-key-nobody-asked-for-on-a
	///
	/// a hundred and thirty characters of menu for one fact, measured on this
	/// repository. Two rules cut it, and both are about saying nothing twice:
	///
	/// - **The repository's name comes off the front of the folder**, because
	///   every row in this list is a checkout of the same repository and the
	///   control that opened it has just said which. `abydos-backlog-0492-…`
	///   becomes `backlog-0492-…`.
	/// - **When one of the two names contains the other, the shorter one
	///   stands alone.** It identifies the checkout exactly as well and costs a
	///   line half the width. That covers the derived names above, and it covers
	///   an agent harness's `agent-a0644…` on a branch called
	///   `worktree-agent-a0644…` from the other direction.
	///
	/// Compared with the slashes flattened, because that is the one difference
	/// `suggestedName` makes and it is not a difference in what the name says.
	///
	/// The primary keeps its full name whatever its branch is: it is the
	/// repository itself and the way back, and `main` alone would not say so.
	/// The worktree's directory without the repository's name on the front of it.
	///
	/// `suggestedPath` builds `<repository>-<branch>`, so every checkout of
	/// abydos is called `abydos-something` — and in a titlebar that has just said
	/// `abydos`, or a menu of nothing but checkouts of it, those seven characters
	/// are on every line and say nothing. Only when something is left: a worktree
	/// somebody called exactly `abydos-` keeps the name it has.
	public static func shortName(of worktree: GitWorktree, primaryName: String) -> String {
		let prefix = primaryName + "-"
		guard worktree.name.hasPrefix(prefix), worktree.name.count > prefix.count
		else { return worktree.name }
		return String(worktree.name.dropFirst(prefix.count))
	}

	public static func label(for worktree: GitWorktree, primaryName: String) -> String {
		let folder = shortName(of: worktree, primaryName: primaryName)
		switch naming(of: worktree, primaryName: primaryName) {
		case .branchOnly:
			return worktree.branch ?? worktree.summary
		case .folderOnly:
			return folder
		case .both:
			return "\(folder) — \(worktree.summary)"
		}
	}

	/// What a titlebar should add beside a branch it is already showing, or nil
	/// when the branch has said it.
	///
	/// The window's own titlebar has the tightest budget of anywhere this list
	/// appears — the capsule beside it can want half the width on a branch named
	/// after a backlog item — so the rule that keeps a *menu row* from saying the
	/// same thing twice matters more here, not less. A pill reading
	/// `backlog-0490-worktrees` next to a capsule reading
	/// `backlog/0490-worktrees-chosen-from-the-titlebar` is a hundred and fifty
	/// points spent on a word already on screen, and it was enough to push the
	/// pill into the toolbar's overflow — where the one window that most needed
	/// the control was the one window without it.
	///
	/// Nil for the primary too, for the reason the pill's own comment gives: the
	/// capsule has just said the repository's name.
	public static func qualifier(for worktree: GitWorktree, primaryName: String) -> String? {
		// The primary keeps its name in a *list*, where it has to be told from
		// the others, and loses it here, where the capsule has just said it. The
		// one case where the two callers want opposite things.
		guard !worktree.isPrimary else { return nil }
		switch naming(of: worktree, primaryName: primaryName) {
		// Either containment, not just the one the menu drops. A menu row has no
		// branch beside it, so when the folder is the shorter of two names for
		// the same thing the row shows the folder; here the branch is on screen
		// three inches to the left, so the shorter name is redundant rather than
		// preferable.
		case .branchOnly, .folderOnly: return nil
		case .both: return shortName(of: worktree, primaryName: primaryName)
		}
	}

	/// Which of a checkout's two names says something the other does not.
	private enum Naming { case branchOnly, folderOnly, both }

	private static func naming(of worktree: GitWorktree, primaryName: String) -> Naming {
		// The primary is the repository itself and the way back, so its name is
		// never dropped from a list — `main` alone would not say which repository
		// it is the main of.
		guard !worktree.isPrimary else { return .both }

		// Detached, or a branch with nothing on it. Neither shortening applies:
		// there is no ordinary branch name to weigh the folder against, and the
		// state is the thing that has to be said (0477).
		guard let branch = worktree.branch, !worktree.isUnborn else { return .both }

		let folder = shortName(of: worktree, primaryName: primaryName)
		let flattened = branch.replacingOccurrences(of: "/", with: "-")
		// The folder was made out of the branch, so the branch is the whole of
		// what it said. Tested against the full name as well as the shortened
		// one, since the repository's prefix is what `suggestedName` puts there.
		if worktree.name.contains(flattened) || folder.contains(flattened) { return .branchOnly }
		// And the other way about: an agent harness's `agent-a0644…` on a branch
		// called `worktree-agent-a0644…`, where the folder is the shorter of two
		// names for the same thing.
		if flattened.contains(folder) { return .folderOnly }
		return .both
	}
}

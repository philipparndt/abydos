import Foundation

/// Handing a ready item to an agent, in a checkout of its own.
///
/// The worktree is not a nicety. Two agents in one working tree is two agents
/// editing each other's half-finished files, and the failure is not a merge
/// conflict — it is a test suite that passes for one of them and a commit that
/// contains both. A second checkout costs a directory and removes the whole
/// class of problem, so it is the default and turning it off is a line in
/// `config.json` somebody has to write on purpose.
public enum BacklogRunner {
	/// Everything a start produced, so the caller can put a terminal in the
	/// right directory and say what it did.
	public struct Start: Sendable {
		public let item: BacklogItem
		/// Where the work happens: the new worktree, or the project itself
		/// when worktrees are turned off.
		public let directory: URL
		/// Nil when the work is happening in the project's own checkout.
		public let branch: String?
		public let prompt: String
		public let assistant: BacklogAssistant?
		public let run: BacklogRun?

		/// How to start the assistant. Nil when none of the configured ones is
		/// installed — the worktree is still made, and somebody can work in it.
		///
		/// Worked out when it is asked for rather than when the worktree is made,
		/// and that ordering is the whole point. It used to be built while the
		/// `Start` was, which put every question about the assistant — where its
		/// binary is, what permissions it may have, and so what the settings say
		/// — *before* the caller had printed a word. A failure in any of them was
		/// therefore a `start` that had made a worktree, moved an item, and said
		/// nothing at all about either (0464). Now the caller has the directory
		/// and the branch in hand, and can say so, before anything is asked of
		/// the assistant.
		public var command: AgentLauncher.Command? {
			guard let assistant, let executable = assistant.locate() else { return nil }
			return AgentLauncher.Command(
				executable: executable,
				arguments: assistant.arguments(prompt: prompt) + Self.extraArguments(for: assistant)
			)
		}

		/// What an agent may do without stopping to ask.
		///
		/// Only Claude Code takes one, and it is the same setting the review uses:
		/// an agent handed one job that then asks whether it may edit the file is
		/// an agent nobody asked anything, and the question was already answered by
		/// putting the item in `ready/`.
		private static func extraArguments(for assistant: BacklogAssistant) -> [String] {
			assistant == .claude ? AgentLauncher.permissionArguments() : []
		}
	}

	public enum Problem: Error, CustomStringConvertible {
		case notReady(BacklogItem)
		case notAGitRepository(URL)
		case notCommitted(BacklogItem)
		case alreadyRunning(BacklogRun)
		case worktreeFailed(String)

		public var description: String {
			switch self {
			case let .notReady(item):
				return "\(item.number) is in \(item.state.directoryName)/, not ready/ — only ready items are picked up."
			case let .notAGitRepository(root):
				return "\(root.path) is not a git repository, so there is nowhere to put a worktree."
			case let .notCommitted(item):
				return """
				\(item.number) is not committed. A worktree is made from HEAD, so the agent \
				would arrive in a checkout that does not contain the item it was sent to do. \
				Commit it first.
				"""
			case let .alreadyRunning(run):
				return "\(run.number) is already being worked on in \(run.worktreePath)."
			case let .worktreeFailed(message):
				return "Could not make the worktree: \(message)"
			}
		}
	}

	/// The next item to pick up: the lowest number in `ready/`.
	///
	/// Lowest rather than newest, because the order within a state is what they
	/// are worth doing in and the number is the order they were written in —
	/// the two agree often enough, and "oldest ready thing first" is at least a
	/// rule somebody can predict.
	public static func next(in backlog: Backlog) -> BacklogItem? {
		backlog.items(in: .ready).first
	}

	/// The checkout the repository was cloned into, asked from inside any of
	/// its worktrees.
	///
	/// Needed because an agent finishing an item runs `done` where it is
	/// working, and the record of what is running is on the machine rather than
	/// on the branch — so it lives in the project's own `.abydos`, and the
	/// worktree has to be able to find its way back there. `--git-common-dir`
	/// is the question git answers for exactly this: every worktree shares one,
	/// and it is `<the original checkout>/.git`.
	public static func primaryCheckout(from directory: URL) async -> URL? {
		let result = await GitRepository.run(["rev-parse", "--git-common-dir"], in: directory)
		guard result.exitCode == 0 else { return nil }

		let answer = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !answer.isEmpty else { return nil }
		// Relative to the directory it was asked in, unless it is not: git
		// gives `.git` in the original checkout and an absolute path from a
		// worktree, and both have to work.
		let common = answer.hasPrefix("/")
			? URL(fileURLWithPath: answer)
			: directory.appendingPathComponent(answer)
		// Symlinks resolved, as `GitWorktrees.parse` does and for the same
		// reason: git answers with the real path — `/private/var/…` where the
		// project holds `/var/…` — and the caller's next move is to compare
		// this with a path it already had.
		let root = common.resolvingSymlinksInPath().deletingLastPathComponent()
		return AbydosFolder.exists(in: root) ? root : nil
	}

	/// Makes the worktree, moves the item, and says how to start the agent.
	///
	/// The item is moved in both checkouts, which is not a belt-and-braces
	/// duplicate — they are answering different questions. The project's own
	/// copy is what the dashboard shows, so somebody watching sees the item
	/// leave `ready/` the moment it is picked up. The worktree's copy is on the
	/// branch, so when the branch lands the move lands with the work. Git sees
	/// the same rename on both sides and merges it as one.
	public static func start(
		_ item: BacklogItem,
		in backlog: Backlog,
		assistant: BacklogAssistant?,
		useWorktree: Bool = true
	) async throws -> Start {
		guard item.state == .ready else { throw Problem.notReady(item) }

		let runs = BacklogRuns(projectRoot: backlog.projectRoot)
		if let existing = runs.run(for: item.number), existing.isPresent {
			throw Problem.alreadyRunning(existing)
		}

		guard useWorktree else {
			let moved = try backlog.move(item, to: .inProgress)
			return finish(
				item: moved,
				relativePath: moved.displayPath(from: backlog.projectRoot),
				directory: backlog.projectRoot,
				branch: nil,
				assistant: assistant,
				run: nil
			)
		}

		guard let repository = await GitRepository.discover(from: backlog.projectRoot) else {
			throw Problem.notAGitRepository(backlog.projectRoot)
		}
		let root = repository.root

		// Asked of HEAD rather than of the index: `git worktree add` checks out
		// a commit, and a file that is only staged is as absent from the new
		// directory as one that was never added.
		let inHead = await GitRepository.run(
			["cat-file", "-e", "HEAD:" + item.displayPath(from: root)],
			in: root
		)
		guard inHead.exitCode == 0 else { throw Problem.notCommitted(item) }

		let branch = item.branchName
		let path = GitWorktrees.suggestedPath(for: branch, root: root)

		// The branch may already exist: somebody started this item, deleted the
		// worktree with `rm -rf` rather than `git worktree remove`, and came
		// back to it. `-b` refuses in that case, so the second attempt checks
		// the branch out instead of making it — which is what resuming is, and
		// keeps whatever was committed before the directory went.
		let exists = await GitRepository.run(["rev-parse", "--verify", "--quiet", "refs/heads/" + branch], in: root)
		if exists.exitCode == 0 { await GitWorktrees.prune(in: root) }
		let added = await GitWorktrees.add(
			at: path,
			branch: branch,
			createBranch: exists.exitCode != 0,
			in: root
		)
		guard added.exitCode == 0 else {
			let message = added.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
			throw Problem.worktreeFailed(message.isEmpty ? added.stdout : message)
		}

		let moved = try backlog.move(item, to: .inProgress)
		// The same move on the branch. Looked up by number rather than by path:
		// the worktree is a checkout of HEAD, and where the item sits there is
		// whatever the last commit said, not what the project's copy says now.
		let inWorktree = Backlog(projectRoot: path)
		if let there = inWorktree.items(in: .ready).first(where: { $0.number == item.number }) {
			_ = try? inWorktree.move(there, to: .inProgress)
		}

		let run = BacklogRun(
			number: item.number,
			branch: branch,
			worktree: path,
			assistant: assistant?.rawValue ?? ""
		)
		try? runs.record(run)

		return finish(
			item: moved,
			// The project's copy and the worktree's are at the same place
			// within their own checkouts, and the agent is told the relative
			// one — an absolute path into the project is the one directory it
			// must not be working in.
			relativePath: moved.displayPath(from: backlog.projectRoot),
			directory: path,
			branch: branch,
			assistant: assistant,
			run: run
		)
	}

	private static func finish(
		item: BacklogItem,
		relativePath: String,
		directory: URL,
		branch: String?,
		assistant: BacklogAssistant?,
		run: BacklogRun?
	) -> Start {
		let text = prompt(number: item.number, title: item.title, path: relativePath, branch: branch)

		return Start(
			item: item,
			directory: directory,
			branch: branch,
			prompt: text,
			assistant: assistant,
			run: run
		)
	}

	/// What the agent is told, which is as little as will do.
	///
	/// The workflow is in `AGENTS.md` and the item is in the item. Repeating
	/// either here would be a second copy that drifts, and the drift would be
	/// invisible: nobody reads the prompt a button builds.
	public static func prompt(number: Int, title: String, path: String, branch: String?) -> String {
		var lines = [
			"Pick up backlog item \(String(format: "%04d", number)) — \(title).",
			"",
		]
		if let branch {
			lines += [
				"You are in a git worktree made for this one item, on branch `\(branch)`.",
				"Do all of the work here. Another agent may be in another worktree of the",
				"same repository, so do not go looking for the project elsewhere.",
				"",
			]
		}
		lines += [
			"Read `.abydos/backlog/AGENTS.md` first — it is one page and it is the whole",
			"workflow. Then `.abydos/backlog/project.md`, and the parts of",
			"`.abydos/backlog/spec/` this item touches.",
			"",
			"The item is `\(path)`. It has already been moved to `in-progress/`, so start",
			"at step 4 of \u{201C}picking up a ready item\u{201D}: do the work, write the spec delta,",
			"write down what you ruled out, then `abydos-backlog done \(number)`.",
			"",
			"Read the item in full before you change anything, including what it says has",
			"already been tried.",
		]
		return lines.joined(separator: "\n")
	}
}

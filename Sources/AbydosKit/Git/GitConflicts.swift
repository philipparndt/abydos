import Foundation

/// A merge that stopped, and the three things somebody does next.
///
/// **Nothing on screen says a merge is half-done today.** The files are there,
/// full of markers, and the app that put them there says nothing about it —
/// which is the worst moment for an editor to be quiet.
///
/// What is offered is deliberately three and not four: opening the files is the
/// work; Fork is where this app has already said a three-way merge editor
/// belongs, so the handoff has a home rather than being a dead end; and a
/// prompt on the pasteboard hands the conflict to an agent in this app's own
/// terminal, which is the thing this app is for. Aborting is not here — the
/// banner is about resolving, and abandoning belongs on the operation that
/// started the merge, where what would be lost can be counted.
public enum GitConflicts {
	/// The paths git reports as unmerged.
	public static func paths(in root: URL) async -> [String] {
		await GitCommits.conflictedPaths(in: root)
	}

	/// A git operation that has stopped part-way through.
	///
	/// Read from the marker files git leaves in `.git` and nothing else, so
	/// asking costs four `stat` calls and no subprocess. That matters because
	/// the titlebar asks on every refresh of the head, which is every
	/// filesystem event that touches the repository.
	public enum Operation: String, Sendable, CaseIterable {
		case merge
		case cherryPick
		case revert
		case rebase

		/// The one word a pill has room for, lowercase because it sits after a
		/// branch name rather than starting a sentence.
		public var said: String {
			switch self {
			case .merge: return "merging"
			case .cherryPick: return "cherry-picking"
			case .revert: return "reverting"
			case .rebase: return "rebasing"
			}
		}

		/// The same thing at the start of a sentence, which is where the
		/// banner puts it.
		public var titled: String {
			said.prefix(1).uppercased() + said.dropFirst()
		}

		/// The git subcommand that carries it on: `git rebase --continue`,
		/// `git merge --continue`, and so on. The verbs differ from the marker
		/// files they were read from, which is the whole reason this is a type
		/// rather than a string.
		public var command: String {
			switch self {
			case .merge: return "merge"
			case .cherryPick: return "cherry-pick"
			case .revert: return "revert"
			case .rebase: return "rebase"
			}
		}

		/// Whether the commit being applied can be passed over.
		///
		/// A merge cannot: there is one commit being made and skipping it is
		/// aborting it. The other three are replaying a list, and skipping the
		/// one in hand is an ordinary thing to want — it is how a commit whose
		/// change is already upstream is got past.
		public var canSkip: Bool { self != .merge }

		/// The thing itself rather than the doing of it — `a merge is in
		/// progress`, which the participle cannot say without reading as
		/// broken English.
		public var noun: String {
			switch self {
			case .merge: return "merge"
			case .cherryPick: return "cherry-pick"
			case .revert: return "revert"
			case .rebase: return "rebase"
			}
		}
	}

	/// Which operation is under way, if one is.
	///
	/// **Separate from `describe` on purpose.** `describe` names the commit
	/// coming in, which costs a `git log`; this answers only the verb, and the
	/// titlebar wants the verb. It is also true in a case `describe` is not
	/// asked in: a rebase that has stopped without a conflict — `edit`, a
	/// failed `exec`, an empty commit — leaves no conflicted path, so nothing
	/// in the window would otherwise admit the repository is mid-rebase.
	public static func operation(in root: URL) async -> Operation? {
		let directory = await gitDirectory(in: root)
		guard let directory else { return nil }
		let files = FileManager.default
		func exists(_ name: String) -> Bool {
			files.fileExists(atPath: directory.appendingPathComponent(name).path)
		}
		if exists("MERGE_HEAD") { return .merge }
		if exists("CHERRY_PICK_HEAD") { return .cherryPick }
		if exists("REVERT_HEAD") { return .revert }
		if exists("rebase-merge") || exists("rebase-apply") { return .rebase }
		return nil
	}

	/// What the merge is between, in the words the banner should use.
	///
	/// A merge names the branch coming in; a rebase names the commit being
	/// replayed; a cherry-pick names the commit. Read from the files git
	/// leaves behind rather than guessed, because "ours" and "theirs" swap
	/// meaning between merge and rebase and getting that backwards in a
	/// sentence is worse than not writing one.
	public static func describe(in root: URL) async -> String? {
		let directory = await gitDirectory(in: root)
		guard let directory else { return nil }

		func head(_ name: String) async -> String? {
			let file = directory.appendingPathComponent(name)
			guard FileManager.default.fileExists(atPath: file.path) else { return nil }
			let read = await GitRepository.run(["log", "-1", "--format=%h %s", name], in: root)
			guard read.exitCode == 0 else { return name }
			let said = read.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
			return said.isEmpty ? name : said
		}

		switch await operation(in: root) {
		case .merge:
			return Operation.merge.titled + " " + (await head("MERGE_HEAD") ?? "MERGE_HEAD")
		case .cherryPick:
			return Operation.cherryPick.titled + " "
				+ (await head("CHERRY_PICK_HEAD") ?? "CHERRY_PICK_HEAD")
		case .revert:
			return Operation.revert.titled + " " + (await head("REVERT_HEAD") ?? "REVERT_HEAD")
		case .rebase:
			// No commit named: a rebase's `.git/rebase-merge/head` is the branch
			// being replayed rather than the commit stopped on, and `git log` on
			// it says the wrong thing.
			return Operation.rebase.titled
		case nil:
			return nil
		}
	}

	/// How far through the operation is, and what it is working on.
	///
	/// **Git keeps the count itself**, which is the only reason this is
	/// affordable: `.git/rebase-merge/msgnum` and `end` are two small files
	/// written by the rebase, and reading them is not a walk of anything. A
	/// count this app arrived at by asking `git log` would cost a process on
	/// every refresh to say a thing git had already written down.
	public struct Progress: Equatable, Sendable {
		/// Which commit is in hand, counting from one.
		public let position: Int
		/// How many there are altogether. Zero when git does not say — the
		/// bar is left out rather than guessed at.
		public let total: Int
		/// The commit being applied, in its own words.
		public let subject: String?
		/// The branch being replayed, and where onto. Rebase only; a
		/// cherry-pick has no such pair.
		public let branch: String?
		public let onto: String?

		public init(
			position: Int, total: Int, subject: String? = nil,
			branch: String? = nil, onto: String? = nil
		) {
			self.position = position
			self.total = total
			self.subject = subject
			self.branch = branch
			self.onto = onto
		}
	}

	/// Reads the count out of the files git left behind.
	///
	/// A rebase writes `msgnum` of `end` (the merge backend) or `next` of
	/// `last` (the apply backend). A cherry-pick or revert of several commits
	/// leaves a sequencer, whose `todo` holds what is left — the one in hand
	/// included — and whose `done` holds what has been applied; `done` does
	/// not exist until the first one lands, which reads as zero and is right.
	/// A merge has no count: it is one commit, and a bar over it would be
	/// decoration.
	public static func progress(in root: URL) async -> Progress? {
		guard let directory = await gitDirectory(in: root) else { return nil }
		let files = FileManager.default

		func read(_ path: String) -> String? {
			let text = try? String(
				contentsOf: directory.appendingPathComponent(path), encoding: .utf8
			)
			let said = text?.trimmingCharacters(in: .whitespacesAndNewlines)
			return (said?.isEmpty ?? true) ? nil : said
		}
		func lines(_ path: String) -> Int {
			guard let text = read(path) else { return 0 }
			return text.split(separator: "\n").filter {
				let line = $0.trimmingCharacters(in: .whitespaces)
				return !line.isEmpty && !line.hasPrefix("#")
			}.count
		}

		for backend in ["rebase-merge", "rebase-apply"] {
			guard files.fileExists(atPath: directory.appendingPathComponent(backend).path) else {
				continue
			}
			let position = read("\(backend)/msgnum") ?? read("\(backend)/next")
			let total = read("\(backend)/end") ?? read("\(backend)/last")
			// `refs/heads/side` is not what to show anybody.
			let branch = read("\(backend)/head-name").map {
				$0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0
			}
			let onto = read("\(backend)/onto").map { String($0.prefix(8)) }
			return Progress(
				position: position.flatMap(Int.init) ?? 1,
				total: total.flatMap(Int.init) ?? 0,
				// The merge backend keeps the message of the commit in hand;
				// the apply backend does not, and says nothing rather than
				// the wrong thing.
				subject: read("\(backend)/message")?.split(separator: "\n").first.map(String.init),
				branch: branch,
				onto: onto
			)
		}

		if files.fileExists(atPath: directory.appendingPathComponent("sequencer").path) {
			let left = lines("sequencer/todo")
			let done = lines("sequencer/done")
			guard left > 0 || done > 0 else { return nil }
			return Progress(position: done + 1, total: done + left, subject: nil)
		}
		return nil
	}

	/// What to do with the operation that has stopped.
	public enum Step: String, Sendable {
		/// `--continue`. Not spelled `continue`, which is a keyword.
		case carryOn
		case skip
		case abort

		var flag: String {
			switch self {
			case .carryOn: return "--continue"
			case .skip: return "--skip"
			case .abort: return "--abort"
			}
		}
	}

	/// How a step ended.
	///
	/// **Three outcomes and not two, because git's exit code carries two
	/// different meanings.** `git rebase --continue` exits 1 both when it
	/// refuses to move — markers still in the files — and when it moves,
	/// applies the next commit and stops on *its* conflict. The first is a
	/// mistake to report; the second is the rebase working exactly as it
	/// should, and reporting it as a failure is what the first version of this
	/// did.
	public enum Outcome: Equatable, Sendable {
		/// Nothing is in progress any more.
		case finished
		/// It moved, and stopped again — at the next commit, or on a conflict
		/// in it. The message is whatever git said about the stop.
		case stopped(String?)
		/// It would not move. The message is git's, verbatim.
		case refused(String)
	}

	/// Carries the operation on, passes over the commit in hand, or throws the
	/// whole thing away — and says what git said when it would not.
	///
	/// **`GIT_EDITOR=true`.** `--continue` opens an editor on the message it
	/// already has, and an editor this app cannot show is a `git` that never
	/// returns: the first version of this hung, holding a process open on a
	/// commit message nobody could see. `true` exits 0 without touching the
	/// file, which is git's own way of saying "take the message as it stands".
	///
	/// Returns nil when it worked. Otherwise the message git printed, which is
	/// worth showing verbatim: `you must edit all merge conflicts and then
	/// mark them as resolved using git add` is better advice than anything
	/// this could write about it.
	public static func run(
		_ step: Step, on operation: Operation, in root: URL
	) async -> Outcome {
		// Where it was, so a non-zero exit can be told from a step that landed
		// in the next conflict.
		let before = await progress(in: root)
		let result = await GitRepository.run(
			[operation.command, step.flag],
			in: root,
			environment: ["GIT_EDITOR": "true", "GIT_TERMINAL_PROMPT": "0"]
		)
		let said = (result.stderr + "\n" + result.stdout)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		guard await Self.operation(in: root) != nil else { return .finished }
		if result.exitCode == 0 { return .stopped(said.isEmpty ? nil : said) }

		// It is still in progress and git complained. Whether it moved is the
		// question, and the count it keeps is the answer.
		let after = await progress(in: root)
		let moved = before?.position != after?.position
		if moved { return .stopped(said.isEmpty ? nil : said) }
		return .refused(said.isEmpty ? "git \(operation.command) \(step.flag) failed" : said)
	}

	/// How much of each conflicted file goes into the prompt.
	public static let defaultLimit = 40_000

	/// A prompt describing the conflict, for pasting into a session.
	///
	/// The whole of each conflicted file rather than only the marked region:
	/// resolving a conflict is a question about what the code is meant to do,
	/// and the answer is rarely inside the markers. Capped, and what did not
	/// fit is named rather than dropped — a resolution written against half a
	/// file is worse than no resolution, and only the prompt can say so.
	public static func prompt(in root: URL, limit: Int = defaultLimit) async -> String? {
		let conflicted = await paths(in: root)
		guard !conflicted.isEmpty else { return nil }

		var files: [String] = []
		var unread: [String] = []
		var spent = 0

		for path in conflicted {
			let text = (try? String(
				contentsOf: root.appendingPathComponent(path), encoding: .utf8
			)) ?? ""
			guard !text.isEmpty, spent + text.count <= limit else {
				unread.append(path)
				continue
			}
			spent += text.count
			files.append("""
			### \(path)

			```
			\(text)
			```
			""")
		}

		var said = """
		Resolve the git conflict\(conflicted.count == 1 ? "" : "s") below.
		"""
		if let what = await describe(in: root) { said += "\n\n\(what)." }

		said += """


		Each file is given whole, with git's conflict markers in it. Edit the \
		files in place: keep what both sides were trying to do, remove every \
		`<<<<<<<`, `=======` and `>>>>>>>` line, and leave the file compiling. \
		Do not commit; leave the result staged or unstaged as you find it.
		"""

		if !unread.isEmpty {
			said += """


			These files are also conflicted and were too large to include here. \
			They still need resolving:

			\(unread.map { "- \($0)" }.joined(separator: "\n"))
			"""
		}

		said += "\n\n" + files.joined(separator: "\n\n")
		return said
	}

	/// Where this work tree's git directory is.
	private static func gitDirectory(in root: URL) async -> URL? {
		let result = await GitRepository.run(["rev-parse", "--git-dir"], in: root)
		guard result.exitCode == 0 else { return nil }
		let said = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !said.isEmpty else { return nil }
		// Relative for an ordinary checkout, absolute for a worktree.
		return said.hasPrefix("/")
			? URL(fileURLWithPath: said)
			: root.appendingPathComponent(said)
	}
}

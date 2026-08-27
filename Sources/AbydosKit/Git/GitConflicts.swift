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

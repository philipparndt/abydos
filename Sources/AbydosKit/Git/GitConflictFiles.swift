import Foundation

/// The files a stopped operation is waiting on, and the verbs that clear one.
///
/// **The strip used to say a number.** `3 files conflicted`, with a `Files`
/// button that opened all of them at once and a `Continue` that was grey for a
/// reason kept in a tooltip. A number cannot be worked through: it says how
/// much is left without saying what, and nothing on screen joined it to the
/// button it was disabling. The names were there the whole time — `paths(in:)`
/// reads them and the count was `paths.count`.
public extension GitConflicts {
	/// One file this stop is waiting on.
	struct Waiting: Equatable, Sendable {
		public let path: String
		/// Staged, so git will take it. The row keeps its place and ticks
		/// rather than vanishing: a list that empties from the middle is a list
		/// somebody has to re-find their place in every time they resolve one.
		public let isResolved: Bool
		/// How many `<<<<<<<` are still in the file. Zero and unresolved is the
		/// state that matters — edited by hand, not yet staged — which is what
		/// `Mark Resolved` is for.
		public let markers: Int

		public init(path: String, isResolved: Bool, markers: Int) {
			self.path = path
			self.isResolved = isResolved
			self.markers = markers
		}

		public var name: String { (path as NSString).lastPathComponent }
		public var directory: String { (path as NSString).deletingLastPathComponent }
	}

	/// Which stage of the index to take whole.
	///
	/// **Never shown in these words.** Stage 2 is "ours" and stage 3 is
	/// "theirs" to git in both a merge and a rebase, and they are opposite
	/// things: rebasing replays your commits onto somebody else's, so the
	/// branch you are on — the one you would call *ours* — arrives as
	/// `--theirs`. A menu offering "Use Ours" during a rebase is a menu that
	/// throws away the wrong half. `sides(of:in:)` names them by branch.
	enum Side: String, Sendable {
		case ours
		case theirs
		var flag: String { "--\(rawValue)" }
	}

	/// The files this stop is waiting on, resolved ones included.
	///
	/// - Parameter alsoShowing: everything this stop was waiting on when it
	///   was first read. Git stops calling a path unmerged the moment it is
	///   staged, so without a memory of the set the list would shrink instead
	///   of ticking — and `2 of 3 resolved` could not be said at all.
	///
	/// Sorted by path across both halves, so a row keeps its place as it ticks.
	static func waiting(in root: URL, alsoShowing remembered: Set<String> = []) async -> [Waiting] {
		let unmerged = Set(await paths(in: root))
		let all = unmerged.union(remembered).sorted()
		return all.map { path in
			Waiting(
				path: path,
				isResolved: !unmerged.contains(path),
				markers: unmerged.contains(path) ? markersLeft(in: path, under: root) : 0
			)
		}
	}

	/// What to call the two sides of this conflict, in branch names.
	///
	/// A merge is *the branch you are on* against *the branch coming in*. A
	/// rebase is the other way round and reads backwards from git's flags: the
	/// commit you are replaying arrives as `--theirs`, and the thing you are
	/// replaying it onto is `--ours`.
	static func sides(
		of operation: Operation, in root: URL
	) async -> (ours: String, theirs: String) {
		let here = await GitRepository.head(in: root).name
		switch operation {
		case .merge:
			let coming = await incoming(in: root)
			return (here ?? "this branch", coming ?? "the branch coming in")
		case .rebase:
			let progress = await progress(in: root)
			// `progress.onto` is eight characters of hash, which is what the
			// headline has always shown. A menu item saying "Use 1aec9f8d"
			// asks somebody to choose between two things when only one of them
			// has a name, so the commit is named where a branch points at it.
			var onto: String?
			if let hash = progress?.onto { onto = await named(hash, in: root) ?? hash }
			return (
				onto ?? "what it is going onto",
				progress?.branch ?? here ?? "the commits being replayed"
			)
		case .cherryPick, .revert:
			return (here ?? "this branch", "the commit")
		}
	}

	/// The branch a stopped merge is bringing in.
	///
	/// Two cheap answers before the hash. `name-rev` names the commit if a
	/// branch points at it, and `.git/MERGE_MSG` holds the line git wrote
	/// before it stopped — `Merge branch 'publish-offers-a-remote'` — which
	/// still answers when the branch has since been deleted.
	static func incoming(in root: URL) async -> String? {
		if let name = await named("MERGE_HEAD", in: root) { return name }

		if let message = await mergeMessage(in: root) {
			// `Merge branch 'x'`, `Merge branch 'x' of git@…`, `Merge remote-
			// tracking branch 'origin/x'`. The quoted half is the answer.
			if let open = message.firstIndex(of: "'"),
			   let close = message[message.index(after: open)...].firstIndex(of: "'") {
				let quoted = String(message[message.index(after: open)..<close])
				if !quoted.isEmpty { return quoted }
			}
		}

		let short = await GitRepository.run(["rev-parse", "--short", "MERGE_HEAD"], in: root)
		let hash = short.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return hash.isEmpty ? nil : hash
	}

	/// The branch a commit is the tip of, where one is.
	///
	/// `name-rev` answers `main~2` for a commit a branch has moved past — true,
	/// and useless as a name for it — so a relative answer counts as no answer.
	private static func named(_ commit: String, in root: URL) async -> String? {
		let result = await GitRepository.run(
			["name-rev", "--name-only", "--refs=refs/heads/*", commit], in: root
		)
		let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard result.exitCode == 0, !name.isEmpty, name != "undefined" else { return nil }
		guard !name.contains("~"), !name.contains("^") else { return nil }
		return name
	}

	/// The files git listed as conflicted when it wrote the merge message.
	///
	/// **A memory that survives a restart.** The set a stop is waiting on only
	/// shrinks — git stops calling a path unmerged once it is staged — so a
	/// list built from what is unmerged *now* shows a merge reopened tomorrow
	/// as though the files already dealt with had never been in it, and counts
	/// what is left as the whole job. Git writes the set into `.git/MERGE_MSG`
	/// under `# Conflicts:` before it stops, and that file is still there.
	///
	/// Merge only: a rebase leaves no equivalent, so a rebase's list is only as
	/// long as the window has been open. Half a memory is better than none, and
	/// the half that exists is the one that costs nothing to read.
	static func recorded(in root: URL) async -> Set<String> {
		guard let text = await mergeMessageText(in: root) else { return [] }
		var found: Set<String> = []
		var inside = false
		for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
			if line.hasPrefix("# Conflicts:") { inside = true; continue }
			guard inside else { continue }
			// `#\tpath`. Anything else ends the block — git writes nothing
			// after it, and guessing past the shape it writes is how a comment
			// somebody typed becomes a filename.
			guard line.hasPrefix("#\t") else { break }
			let path = String(line.dropFirst(2))
			if !path.isEmpty { found.insert(path) }
		}
		return found
	}

	/// The first line of `.git/MERGE_MSG`, if there is one.
	private static func mergeMessage(in root: URL) async -> String? {
		await mergeMessageText(in: root)?.split(separator: "\n").first.map(String.init)
	}

	private static func mergeMessageText(in root: URL) async -> String? {
		let result = await GitRepository.run(["rev-parse", "--git-path", "MERGE_MSG"], in: root)
		let said = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard result.exitCode == 0, !said.isEmpty else { return nil }
		let file = said.hasPrefix("/") ? URL(fileURLWithPath: said) : root.appendingPathComponent(said)
		return try? String(contentsOf: file, encoding: .utf8)
	}

	/// Takes one whole side of a conflict and stages the result.
	///
	/// Returns nil when it worked, and git's own words when it did not — a
	/// delete/modify conflict has no version on one of the two sides, and
	/// `error: path 'x' does not have our version` says that better than
	/// anything written over the top of it.
	@discardableResult
	static func take(_ side: Side, of path: String, in root: URL) async -> String? {
		let taken = await GitRepository.run(["checkout", side.flag, "--", path], in: root)
		guard taken.exitCode == 0 else { return complaint(taken) }
		return await markResolved(path, in: root)
	}

	/// Stages a file whose markers somebody has edited away.
	///
	/// It does not check for markers first. `git add` does not either, and the
	/// caller is better placed to ask: a file can legitimately contain the
	/// characters — this repository has one that documents them — so refusing
	/// here would be a rule with a false positive and no way round it.
	/// `Waiting.markers` is the count to ask about.
	@discardableResult
	static func markResolved(_ path: String, in root: URL) async -> String? {
		let added = await GitRepository.run(["add", "--", path], in: root)
		return added.exitCode == 0 ? nil : complaint(added)
	}

	/// How many conflict regions are still written into a file.
	///
	/// The opening marker only. Counting all three kinds and dividing is one
	/// more thing to get wrong over a file somebody is halfway through editing,
	/// where the three counts do not have to agree.
	///
	/// Read straight off disk rather than through git: this is asked once per
	/// row on every refresh, and a refresh runs on every filesystem event.
	static func markersLeft(in path: String, under root: URL) -> Int {
		let file = root.appendingPathComponent(path)
		guard let text = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
		var count = 0
		for line in text.split(separator: "\n", omittingEmptySubsequences: false)
		where line.hasPrefix("<<<<<<< ") || line == "<<<<<<<" {
			count += 1
		}
		return count
	}

	private static func complaint(_ result: GitRepository.ProcessResult) -> String {
		let said = (result.stderr + "\n" + result.stdout)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return said.isEmpty ? "git exited \(result.exitCode)" : said
	}
}

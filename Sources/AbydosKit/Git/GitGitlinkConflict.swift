import Foundation

/// A submodule both sides of a merge moved, and to different commits.
///
/// **The one conflict no merge tool can open.** Everything else this program
/// reports is text, and the archived design's non-goal holds for those — "a
/// conflict is reported and named; resolving it is the editor's job or Fork's".
/// A gitlink is not text. The whole of its content is one object name, so a
/// three-way diff of it is one line against one line, and what is actually in
/// conflict is *which commit of another repository this one points at*. The
/// resolution is a commit, not a merge.
///
/// Git says so itself when it hits one:
///
///     hint: Recursive merging with submodules currently only supports trivial
///     hint: cases. Please manually handle the merging of each conflicted
///     hint: submodule.
public struct GitGitlinkConflict: Sendable, Equatable, Identifiable {
	/// The submodule's path, relative to the superproject.
	public let path: String

	/// The commit the common ancestor recorded. Absent when the submodule was
	/// added on both sides independently, which has no ancestor to point at.
	public let base: String?
	/// What this side records.
	public let ours: String?
	/// What the side being merged in records.
	public let theirs: String?

	public var id: String { path }

	public init(path: String, base: String?, ours: String?, theirs: String?) {
		self.path = path
		self.base = base
		self.ours = ours
		self.theirs = theirs
	}

	/// The commits somebody may resolve to, as (what to call it, the commit).
	///
	/// Two of them, and a third the caller supplies from the submodule's own
	/// history — which is what git's own hint tells you to go and do, and what a
	/// merge inside the submodule leaves you holding.
	public var sides: [(name: String, commit: String)] {
		var found: [(name: String, commit: String)] = []
		if let ours { found.append(("ours", ours)) }
		if let theirs { found.append(("theirs", theirs)) }
		return found
	}
}

/// Finding and resolving the conflicts a superproject has and a file does not.
public enum GitGitlinkConflicts {
	/// Every conflicted gitlink, from one `git ls-files -u`.
	///
	/// Unmerged entries arrive as up to three records a path — stage 1 the
	/// common ancestor, 2 ours, 3 theirs — and a gitlink is told from a file by
	/// its mode being `160000`, which is the same fact the inventory reads.
	public static func conflicts(in root: URL) async -> [GitGitlinkConflict] {
		let result = await GitRepository.run(["ls-files", "-u", "-z"], in: root)
		guard result.exitCode == 0 else { return [] }
		return parse(result.stdout)
	}

	static func parse(_ output: String) -> [GitGitlinkConflict] {
		var stages: [String: [Int: String]] = [:]
		var order: [String] = []

		for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
			guard let tab = record.firstIndex(of: "\t") else { continue }
			let fields = record[record.startIndex..<tab].split(separator: " ")
			guard fields.count >= 3, fields[0] == GitSubmodules.gitlinkMode,
			      let stage = Int(fields[2])
			else { continue }
			let path = String(record[record.index(after: tab)...])
			guard !path.isEmpty else { continue }
			if stages[path] == nil { order.append(path) }
			stages[path, default: [:]][stage] = String(fields[1])
		}

		return order.map { path in
			let found = stages[path] ?? [:]
			return GitGitlinkConflict(
				path: path, base: found[1], ours: found[2], theirs: found[3]
			)
		}
	}

	/// What lies between the two sides, said as commits.
	///
	/// The same `git log --left-right` the gitlink movement uses, asked inside
	/// the submodule: `<` is what one side has and the other does not, `>` the
	/// reverse. A row that said only "conflicted" would leave somebody to run
	/// this by hand before they could choose.
	public static func distance(
		of conflict: GitGitlinkConflict, in superprojectRoot: URL
	) async -> GitGitlinkMovement.Relation {
		guard let ours = conflict.ours, let theirs = conflict.theirs else { return .notHere }
		let root = superprojectRoot.appendingPathComponent(conflict.path)
		let result = await GitRepository.run(
			["log", "--left-right", "--pretty=format:%m%x1f%H%x1f%s", "\(ours)...\(theirs)"],
			in: root
		)
		// Unrelated histories, or a commit this copy has never fetched, which is
		// git refusing the question rather than answering nought.
		guard result.exitCode == 0 else { return .notHere }

		let counted = GitGitlink.parse(
			result.stdout,
			for: GitSubmodule(path: conflict.path, recordedCommit: ours)
		)
		// `<` is ours and `>` is theirs, so the movement's "ahead" is how far
		// theirs is past ours.
		return counted.relation
	}

	/// Resolves a conflicted gitlink by pointing it at one commit.
	///
	/// Two steps and both of them necessary. The submodule is moved to the
	/// chosen commit, because the index and the work tree disagreeing is what
	/// "dirty" means and resolving a conflict into a dirty state is not
	/// resolving it. Then `git add` on the gitlink, which is what takes the path
	/// out of the unmerged state — the same command that resolves a text
	/// conflict, given the same kind of path.
	///
	/// The submodule is left detached at that commit, which is what `git
	/// submodule update` leaves anyway and is therefore not a surprise this
	/// introduces.
	@discardableResult
	public static func resolve(
		_ conflict: GitGitlinkConflict, to commit: String, in superprojectRoot: URL
	) async -> GitRepository.ProcessResult {
		let submodule = superprojectRoot.appendingPathComponent(conflict.path)
		let checkout = await GitRepository.run(
			["checkout", "--detach", commit], in: submodule
		)
		guard checkout.exitCode == 0 else { return checkout }
		return await GitRepository.run(["add", "--", conflict.path], in: superprojectRoot)
	}
}

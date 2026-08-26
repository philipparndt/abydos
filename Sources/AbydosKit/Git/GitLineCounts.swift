import Foundation

/// How much of a file changed: the two numbers every other tool that lists a
/// diff puts beside the name.
///
/// Optional at every call site rather than defaulted to zero, and that is the
/// whole of what this type is careful about. Git answers `-` in both columns for
/// a binary file, a mode change and a pure rename, and `0 0` is a claim that
/// nothing changed — which is a different and untrue statement. A row with no
/// counts says nothing.
public struct GitLineCount: Equatable, Sendable {
	public let added: Int
	public let removed: Int

	public init(added: Int, removed: Int) {
		self.added = added
		self.removed = removed
	}

	public static func + (lhs: Self, rhs: Self) -> Self {
		Self(added: lhs.added + rhs.added, removed: lhs.removed + rhs.removed)
	}
}

/// Reading `--numstat`, which is the one command that answers "how much" for a
/// whole set of changes at once.
///
/// One command per set and not one per row. The pane already asks for a diff of
/// the file being looked at, which is fine for one; thirty of them to draw
/// thirty rows is thirty processes, and the row count is the size of somebody's
/// commit rather than anything this code chooses.
public enum GitLineCounts {
	/// The working copy, on one side of the index.
	public static func workingCopy(staged: Bool, in root: URL) async -> [String: GitLineCount] {
		var arguments = ["diff", "--numstat", "--no-color", "-z"]
		if staged { arguments.append("--cached") }
		let result = await GitRepository.run(arguments, in: root)
		guard result.exitCode == 0 else { return [:] }
		return parse(result.stdout)
	}

	/// One commit, against its first parent — which is what its file list is
	/// already built against.
	public static func commit(_ commit: String, in root: URL) async -> [String: GitLineCount] {
		let result = await GitRepository.run(
			["show", "--numstat", "--no-color", "--format=", "-z", commit], in: root
		)
		guard result.exitCode == 0 else { return [:] }
		return parse(result.stdout)
	}

	/// `--numstat -z`, which is three NUL-separated fields per record for a
	/// rename and one line for everything else.
	///
	/// **`-z` because paths are not otherwise trustworthy.** Without it git
	/// quotes and escapes anything non-ASCII — `kühlschrank` comes back as
	/// `k\303\274hlschrank` — and the escaped form matches no path this app
	/// holds, so the counts would silently attach to nothing for exactly the
	/// files whose names are hardest to read. The same reason `GitWorkingCopy`
	/// asks for it.
	///
	/// A rename arrives as `added \t removed \t \0 old \0 new \0`: the path
	/// field is empty and the two names follow as their own records. The count
	/// belongs to the new name, which is the row that exists.
	static func parse(_ output: String) -> [String: GitLineCount] {
		var counts: [String: GitLineCount] = [:]
		// Split on NUL, then on tab: the record separator is NUL and the field
		// separator inside a record is still a tab.
		let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
		var index = 0
		while index < fields.count {
			let record = fields[index]
			index += 1
			guard !record.isEmpty else { continue }

			let parts = record.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
			guard parts.count >= 3 else { continue }
			let added = Int(parts[0])
			let removed = Int(parts[1])
			var path = parts[2]

			if path.isEmpty {
				// A rename: the old name, then the new one, as the next two
				// records. The new one is the row.
				guard index + 1 < fields.count else { break }
				index += 1                        // the old name, which has no row
				path = fields[index]
				index += 1
			}

			guard !path.isEmpty else { continue }
			// `-` in both columns is git saying it will not count this one —
			// binary, a mode change, a rename with no edit. Left out entirely,
			// so the row says nothing rather than zero.
			guard let added, let removed else { continue }
			counts[path] = GitLineCount(added: added, removed: removed)
		}
		return counts
	}
}

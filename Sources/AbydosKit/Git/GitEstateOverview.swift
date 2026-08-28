import Foundation

/// Where a submodule's branch stands, read from one cheap `git status` header.
public struct GitSubmoduleBranch: Sendable, Equatable {
	/// The branch, or nil when the head is detached or nothing is committed yet.
	public let branch: String?
	public let upstream: String?
	public let ahead: Int
	public let behind: Int
	public let isDetached: Bool

	public var isLevel: Bool { ahead == 0 && behind == 0 }
	public var hasUpstream: Bool { upstream != nil }

	public init(
		branch: String?, upstream: String? = nil,
		ahead: Int = 0, behind: Int = 0, isDetached: Bool = false
	) {
		self.branch = branch
		self.upstream = upstream
		self.ahead = ahead
		self.behind = behind
		self.isDetached = isDetached
	}
}

/// Reading which branch each submodule is on, and how far from its remote.
public enum GitEstateBranches {
	/// One cheap call per repository.
	///
	/// `-uno` and `--ignore-submodules=all` because only the header is wanted:
	/// without them this walks the work tree to list untracked files nobody is
	/// going to read. Measured at 0.01 s a repository against a superproject
	/// that takes 1.61 s to recurse. `-b` is what puts the header there at all.
	static let arguments = [
		"status", "--porcelain=v1", "-b", "-z", "-uno", "--ignore-submodules=all",
	]

	public static func branches(
		of submodules: [GitSubmodule], in superprojectRoot: URL
	) async -> [String: GitSubmoduleBranch] {
		let wanted = submodules.filter(\.isCheckedOut)
		guard !wanted.isEmpty else { return [:] }

		return await withTaskGroup(
			of: (String, GitSubmoduleBranch?).self
		) { group -> [String: GitSubmoduleBranch] in
			var next = 0
			var collected: [String: GitSubmoduleBranch] = [:]

			func addWork() -> Bool {
				guard next < wanted.count, !Task.isCancelled else { return false }
				let submodule = wanted[next]
				next += 1
				let root = superprojectRoot.appendingPathComponent(submodule.path)
				group.addTask {
					let result = await GitRepository.run(arguments, in: root)
					guard result.exitCode == 0 else { return (submodule.path, nil) }
					return (submodule.path, parse(result.stdout))
				}
				return true
			}

			for _ in 0..<min(GitEstateReader.concurrency, wanted.count) { _ = addWork() }
			while let (path, branch) = await group.next() {
				if let branch { collected[path] = branch }
				_ = addWork()
			}
			return collected
		}
	}

	/// Parses the `## ` header `git status -b` puts first.
	///
	/// Its shapes, all of them seen rather than guessed:
	///
	///     ## main                              no upstream
	///     ## main...origin/main                level with one
	///     ## main...origin/main [ahead 2]
	///     ## main...origin/main [ahead 1, behind 3]
	///     ## HEAD (no branch)                  detached
	///     ## No commits yet on main            nothing committed
	///
	/// Split on both separators: `-z` terminates the *records* with NUL but git
	/// ends the header with a newline, so a parser that trusted one of them
	/// would read the header and the first changed path as one string.
	static func parse(_ output: String) -> GitSubmoduleBranch? {
		let records = output.split(whereSeparator: { $0 == "\0" || $0 == "\n" })
		guard let header = records.first(where: { $0.hasPrefix("## ") }) else { return nil }
		let text = String(header.dropFirst(3))

		if text.hasPrefix("HEAD (no branch)") {
			return GitSubmoduleBranch(branch: nil, isDetached: true)
		}
		if text.hasPrefix("No commits yet on ") {
			return GitSubmoduleBranch(branch: String(text.dropFirst("No commits yet on ".count)))
		}

		// The counts, when there are any, and what is left after taking them off.
		var names = text
		var ahead = 0, behind = 0
		if let open = text.lastIndex(of: "["), text.hasSuffix("]") {
			let inside = text[text.index(after: open)..<text.index(before: text.endIndex)]
			for part in inside.split(separator: ",") {
				let words = part.split(separator: " ")
				guard words.count == 2, let count = Int(words[1]) else { continue }
				if words[0] == "ahead" { ahead = count }
				if words[0] == "behind" { behind = count }
			}
			names = String(text[text.startIndex..<open]).trimmingCharacters(in: .whitespaces)
		}

		// `...` separates the branch from its upstream. A branch name may hold
		// dots — `release/1.2.3` — so this splits on the three-dot run rather
		// than on a dot.
		guard let separator = names.range(of: "...") else {
			return GitSubmoduleBranch(branch: names.isEmpty ? nil : names)
		}
		return GitSubmoduleBranch(
			branch: String(names[names.startIndex..<separator.lowerBound]),
			upstream: String(names[separator.upperBound...]),
			ahead: ahead,
			behind: behind
		)
	}
}

/// One row of the estate overview.
///
/// A value computed when a repository's answers land, never while drawing. The
/// page this feeds has three hundred rows and the house rule about anything per
/// row of a table applies literally.
public struct GitEstateRow: Sendable, Equatable, Identifiable {
	/// What the row is chiefly saying, which is also what orders the list.
	///
	/// A page opened to find the work has to put the work first; three hundred
	/// alphabetical rows of which four matter is a page nobody reads twice.
	public enum State: Sendable, Equatable {
		/// Its own merge is unresolved.
		case conflicted
		/// It has uncommitted work, and how many changes.
		case changed(Int)
		/// Committed, and not yet pushed.
		case ahead(Int)
		/// The superproject records it somewhere else.
		case moved
		/// Nothing to report.
		case clean
		/// Its status has not landed yet. **Not clean** — that would be a
		/// sentence about this program dressed as one about the code.
		case unread
		/// The index names it and disk does not have it.
		case absent

		/// Lowest first. Conflicted, changed, ahead, moved, then the quiet ones.
		var rank: Int {
			switch self {
			case .conflicted: return 0
			case .changed: return 1
			case .ahead: return 2
			case .moved: return 3
			case .unread: return 4
			case .absent: return 5
			case .clean: return 6
			}
		}
	}

	public let submodule: GitSubmodule
	public let state: State
	public let branch: GitSubmoduleBranch?
	public let movement: GitGitlinkMovement?
	/// How many changes are in its work tree, whatever the state says.
	public let changeCount: Int

	public var id: String { submodule.path }
	public var path: String { submodule.path }
	public var needsSomething: Bool { state.rank <= State.moved.rank }

	public init(
		submodule: GitSubmodule,
		state: State,
		branch: GitSubmoduleBranch?,
		movement: GitGitlinkMovement?,
		changeCount: Int
	) {
		self.submodule = submodule
		self.state = state
		self.branch = branch
		self.movement = movement
		self.changeCount = changeCount
	}
}

/// The estate as a list somebody can read.
public enum GitEstateOverview {
	/// The rows, ordered by what needs something.
	///
	/// Ties are broken by path so the list is the same list twice: a page that
	/// reordered its own rows between two refreshes would be unreadable while
	/// anything was happening, which is exactly when it is open.
	public static func rows(
		in estate: GitEstate,
		status: GitEstateStatus,
		branches: [String: GitSubmoduleBranch] = [:],
		movements: [String: GitGitlinkMovement] = [:]
	) -> [GitEstateRow] {
		let moved = Set(status.movedGitlinks(in: estate).map(\.path))

		return estate.submodules.map { submodule -> GitEstateRow in
			let own = status.status(of: submodule.path)
			let branch = branches[submodule.path]
			let count = (own?.staged.count ?? 0) + (own?.unstaged.count ?? 0)

			let state: GitEstateRow.State
			if !submodule.isCheckedOut {
				state = .absent
			} else if own == nil {
				state = .unread
			} else if own?.hasConflicts == true {
				state = .conflicted
			} else if count > 0 {
				state = .changed(count)
			} else if let branch, branch.ahead > 0 {
				state = .ahead(branch.ahead)
			} else if moved.contains(submodule.path) {
				state = .moved
			} else {
				state = .clean
			}

			return GitEstateRow(
				submodule: submodule,
				state: state,
				branch: branch,
				movement: movements[submodule.path],
				changeCount: count
			)
		}
		.sorted {
			$0.state.rank != $1.state.rank
				? $0.state.rank < $1.state.rank
				: $0.path < $1.path
		}
	}

	/// What the page says about itself, in one sentence somebody can act on.
	///
	/// The question an overview is opened to answer is what is left, and
	/// counting three hundred rows by hand is what this replaces.
	public static func summary(of rows: [GitEstateRow]) -> String {
		guard !rows.isEmpty else { return "no submodules" }
		var parts: [String] = []
		func say(_ count: Int, _ what: String) {
			guard count > 0 else { return }
			parts.append("\(count) \(what)")
		}
		say(rows.filter { $0.state == .conflicted }.count, "conflicted")
		say(rows.filter { if case .changed = $0.state { return true } else { return false } }.count,
			"changed")
		say(rows.filter { if case .ahead = $0.state { return true } else { return false } }.count,
			"ahead")
		say(rows.filter { $0.state == .moved }.count, "moved")
		say(rows.filter { $0.state == .absent }.count, "not checked out")
		say(rows.filter { $0.state == .unread }.count, "still reading")

		let clean = rows.filter { $0.state == .clean }.count
		guard !parts.isEmpty else { return "all \(rows.count) clean" }
		if clean > 0 { parts.append("\(clean) clean") }
		return parts.joined(separator: " · ")
	}
}

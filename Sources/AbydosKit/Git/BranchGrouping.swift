import Foundation

/// Branch names arranged the way somebody reads them.
///
/// A list of a hundred branches sorted by commit date is a list nobody can find
/// anything in: `backup/2026-08-24-0723-wip`, `master`, `chore/gradle`,
/// `worktree-agent-a6a6d98…`, `feat/git` — every one of them where the last
/// commit happened to put it, which from the outside is indistinguishable from
/// no order at all. That was the report, and "not sorted" is a fair description
/// of what it looks like even though `--sort=-committerdate` is a sort.
///
/// Branches are already named in folders — `feat/`, `fix/`, `chore/`,
/// `backup/` — because that is the convention people use precisely so they can
/// be found. This groups by that convention, sorts inside each group, and puts
/// the two branches nobody wants to hunt for at the top.
public enum BranchGrouping {
	/// One heading and the branches under it.
	public struct Section: Equatable, Sendable {
		/// The folder, or nil for the branches that are not in one.
		public let folder: String?
		public let branches: [String]

		public init(folder: String?, branches: [String]) {
			self.folder = folder
			self.branches = branches
		}
	}

	/// The whole list, in the order it should be shown.
	public struct Arrangement: Equatable, Sendable {
		/// The current branch and the repository's default, in that order, with
		/// duplicates and absentees removed.
		///
		/// Pinned because they are the two anybody is most likely to want and
		/// the two most annoying to hunt for — the default especially, since it
		/// is almost never the most recently committed to and so sinks to the
		/// bottom of a list ordered by date.
		public let pinned: [String]
		public let sections: [Section]

		public init(pinned: [String], sections: [Section]) {
			self.pinned = pinned
			self.sections = sections
		}

		/// Every branch shown, in order, without the headings — what arrow keys
		/// move through.
		public var flattened: [String] { pinned + sections.flatMap(\.branches) }
	}

	/// The folder a branch is in, which is everything before the first slash.
	///
    /// The *first* and not the last: `backup/feat/git-16-23-07` belongs with the
	/// other backups, which is how somebody who made it thinks of it. Grouping
	/// by the last slash would file it under `feat` beside the branch it is a
	/// backup *of*, which is the one place it will be mistaken for it.
	public static func folder(of branch: String) -> String? {
		guard let slash = branch.firstIndex(of: "/") else { return nil }
		let folder = String(branch[branch.startIndex..<slash])
		return folder.isEmpty ? nil : folder
	}

	/// Arranges branches into pinned entries and folders.
	///
	/// - `current`: the branch checked out now, pinned first when it is in the
	///   list. It is the one row that is *about* the state of the work tree
	///   rather than a place to go.
	/// - `default`: the repository's default, from `refs/remotes/origin/HEAD`
	///   where the remote has been fetched — git really does mark it — falling
	///   back to whichever of `main` or `master` exists.
	/// - `by`/`created`: the order inside each group, and the dates a date
	///   order reads. The refs tree's LOCAL section takes a chosen order now,
	///   and the spec pins this list to that one: two lists of the same
	///   branches in one window must not disagree. A name missing from
	///   `created` sorts last among the dated, by name.
	public static func arrange(
		_ branches: [String],
		current: String? = nil,
		default defaultBranch: String? = nil,
		by order: RefsSortOrder = .name,
		created: [String: Date] = [:]
	) -> Arrangement {
		// Ordered, de-duplicated, and only names that are really there: a pin
		// for a branch that does not exist is a row that checks out nothing.
		var pinned: [String] = []
		for candidate in [current, defaultBranch].compactMap({ $0 }) {
			guard branches.contains(candidate), !pinned.contains(candidate) else { continue }
			pinned.append(candidate)
		}

		let remaining = branches.filter { !pinned.contains($0) }

		// Grouped, then each group sorted by name. Sorted *within* a folder and
		// not across the whole list, because the folder is the thing being
		// looked for first — and `localizedStandardCompare` so `fix/9` comes
		// before `fix/10`, which is what anybody numbering branches means.
		var byFolder: [String: [String]] = [:]
		var loose: [String] = []
		for branch in remaining {
			if let folder = folder(of: branch) {
				byFolder[folder, default: []].append(branch)
			} else {
				loose.append(branch)
			}
		}

		let byName: ([String]) -> [String] = { names in
			names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
		}
		let sorted: ([String]) -> [String] = { names in
			switch order {
			case .name:
				return byName(names)
			case .newestFirst:
				return names.sorted {
					let first = created[$0] ?? .distantPast
					let second = created[$1] ?? .distantPast
					if first != second { return first > second }
					return $0.localizedStandardCompare($1) == .orderedAscending
				}
			}
		}

		var sections: [Section] = []
		// The branches in no folder first: they are the short names, usually the
		// long-lived ones, and putting them under the folders would bury them.
		if !loose.isEmpty {
			sections.append(Section(folder: nil, branches: sorted(loose)))
		}
		// The folders themselves stay in name order whatever the branches do:
		// a folder has no date, and the tree keeps the same rule.
		for folder in byName(Array(byFolder.keys)) {
			sections.append(Section(folder: folder, branches: sorted(byFolder[folder] ?? [])))
		}

		return Arrangement(pinned: pinned, sections: sections)
	}

	/// Which branch a repository treats as its default.
	///
    /// **git does mark it**, which is worth saying because it is easy to assume
	/// otherwise: `refs/remotes/origin/HEAD` is a symbolic ref pointing at the
	/// remote's default branch. It only exists once the remote has been fetched
	/// with it, so the usual names are the fallback — and `main` before
	/// `master`, since a repository that has both is almost always one in the
	/// middle of moving from the second to the first.
	public static func defaultBranch(in root: URL, remote: String = "origin") async -> String? {
		let named = await GitRepository.run(
			["symbolic-ref", "--quiet", "refs/remotes/\(remote)/HEAD"], in: root
		)
		if named.exitCode == 0 {
			let reference = named.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
			// `refs/remotes/origin/main` — the branch is everything after the
			// remote, which may itself contain slashes.
			let prefix = "refs/remotes/\(remote)/"
			if reference.hasPrefix(prefix) {
				let name = String(reference.dropFirst(prefix.count))
				if !name.isEmpty { return name }
			}
		}

		for candidate in ["main", "master"] {
			let exists = await GitRepository.run(
				["rev-parse", "--verify", "--quiet", "refs/heads/\(candidate)"], in: root
			)
			if exists.exitCode == 0 { return candidate }
		}
		return nil
	}
}

import Foundation

/// A superproject and the submodules it holds, as one thing to ask questions of.
///
/// A project has always been one repository here: `Project` holds one
/// `GitRepository`, `GitWorkingCopy.status(in:)` runs one `git status` in one
/// root, and every verb in this directory takes a `root: URL` meaning "the
/// repository". A checkout of two or three hundred microservices breaks that,
/// and it breaks it quietly — `GitRepository.discover(from:)` answers the
/// *superproject* for every file inside a submodule, because a submodule's
/// `.git` is a file it climbs past, so every verb built on that answer is aimed
/// at the wrong repository for any file in the estate.
///
/// The verbs are not wrong. They were being handed the wrong root. This is what
/// hands them the right one.
///
/// A repository with no submodules is an estate of one, and takes the same path
/// through everything here: there is no "is this a superproject" branch to keep
/// true.
public struct GitEstate: Sendable {
	/// The superproject's work tree root.
	public let root: URL

	/// Every submodule the index names, sorted by path.
	public let submodules: [GitSubmodule]

	/// Submodules by their path, for answering ownership in the depth of the
	/// path rather than the size of the estate. See `submodule(containing:)`.
	private let byPath: [String: GitSubmodule]

	public init(root: URL, submodules: [GitSubmodule] = []) {
		self.root = root.standardizedFileURL
		self.submodules = submodules.sorted { $0.path < $1.path }
		self.byPath = Dictionary(
			submodules.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first }
		)
	}

	/// Reads the inventory. Two git calls, neither growing with the estate.
	public static func read(from root: URL) async -> GitEstate {
		GitEstate(root: root, submodules: await GitSubmodules.inventory(in: root))
	}

	public var holdsSubmodules: Bool { !submodules.isEmpty }
	public var count: Int { submodules.count }

	public func submodule(at path: String) -> GitSubmodule? { byPath[Self.normalised(path)] }

	// MARK: - Ownership

	/// The submodule whose work tree a path lies in, or nil for the
	/// superproject's own.
	///
	/// **Costs the depth of the path, not the size of the estate.** Every
	/// ancestor of the path is looked up in turn, longest first, which is at
	/// most a dozen hash lookups whether the estate holds three submodules or
	/// three hundred. A scan over the inventory would be correct and is not
	/// affordable: this is asked per row of a table, and the tables this exists
	/// for have three hundred rows.
	///
	/// It answers for paths that do not exist on disk. A file just written
	/// inside a submodule is the common case, and one that arrives as a
	/// filesystem event before anything has stat'd it is the usual way this is
	/// reached.
	///
	/// **A submodule contains its own root.** Asking about `svc-47` answers
	/// `svc-47`, not the superproject, because the row named `svc-47` in a tree
	/// of changes is a row about that repository's changes. The superproject's
	/// *gitlink* for `svc-47` is a different object with a different owner, and
	/// callers that mean the gitlink stage `submodule.path` against `root`
	/// rather than asking this.
	public func submodule(containing path: String) -> GitSubmodule? {
		guard !byPath.isEmpty else { return nil }
		var candidate = Self.normalised(path)
		guard !candidate.isEmpty else { return nil }

		while true {
			if let found = byPath[candidate] { return found }
			guard let slash = candidate.lastIndex(of: "/") else { return nil }
			candidate = String(candidate[candidate.startIndex..<slash])
		}
	}

	/// The directory a git command about this path belongs in.
	public func repositoryRoot(containing path: String) -> URL {
		guard let submodule = submodule(containing: path) else { return root }
		return root.appendingPathComponent(submodule.path)
	}

	/// A path rewritten to be relative to the repository that owns it.
	///
	/// `git add`, `restore`, `reset`, `clean` and `ls-files` all resolve a
	/// pathspec against the repository they run in, so handing a
	/// superproject-relative path to a command run inside a submodule composes
	/// the two — the `warning: could not open directory 'sub/sub/'` failure
	/// `Project.gitRoot` already records, at estate scale.
	///
	/// A submodule's own root becomes `.`, which is that repository's whole work
	/// tree: selecting the `svc-47` row and staging it means everything in
	/// `svc-47`.
	public func relativePath(of path: String) -> String {
		let path = Self.normalised(path)
		guard let submodule = submodule(containing: path) else { return path }
		if path == submodule.path { return "." }
		return String(path.dropFirst(submodule.path.count + 1))
	}

	// MARK: - Grouping

	/// A set of paths, and the one repository they are all to be handed to.
	public struct PathGroup: Sendable, Equatable {
		/// The submodule, or nil for the superproject itself.
		public let submodule: GitSubmodule?
		/// Where the command runs.
		public let root: URL
		/// The paths, relative to that root.
		public let paths: [String]

		public init(submodule: GitSubmodule?, root: URL, paths: [String]) {
			self.submodule = submodule
			self.root = root
			self.paths = paths
		}
	}

	/// Paths grouped by the repository that owns them, one group per repository.
	///
	/// This is what makes a selection spanning three submodules three commands
	/// rather than three hundred: a hundred paths across six repositories is six
	/// processes. It is also what makes them *correct* — see `relativePath(of:)`
	/// for what one command over the lot would do instead.
	///
	/// The superproject comes first and submodules follow in path order, so a
	/// report over the groups reads the same way twice.
	public func grouped(_ paths: [String]) -> [PathGroup] {
		var superproject: [String] = []
		var bySubmodule: [String: [String]] = [:]

		for path in paths {
			let path = Self.normalised(path)
			guard !path.isEmpty else { continue }
			if let submodule = submodule(containing: path) {
				bySubmodule[submodule.path, default: []].append(relativePath(of: path))
			} else {
				superproject.append(path)
			}
		}

		var groups: [PathGroup] = []
		if !superproject.isEmpty {
			groups.append(PathGroup(submodule: nil, root: root, paths: superproject))
		}
		for submodule in submodules {
			guard let paths = bySubmodule[submodule.path] else { continue }
			groups.append(PathGroup(
				submodule: submodule,
				root: root.appendingPathComponent(submodule.path),
				paths: paths
			))
		}
		return groups
	}

	/// Every repository in the estate, superproject first.
	public var repositoryRoots: [URL] {
		[root] + submodules.filter(\.isCheckedOut).map { root.appendingPathComponent($0.path) }
	}

	/// Trims the spellings a path can arrive in without changing which path it
	/// is. Git says `svc-47/`, a tree row says `svc-47`, and a caller that has
	/// joined two components says `./svc-47`.
	static func normalised(_ path: String) -> String {
		var path = path
		while path.hasPrefix("./") { path = String(path.dropFirst(2)) }
		while path.hasSuffix("/") { path = String(path.dropLast()) }
		return path
	}
}

extension GitEstate: Equatable {
	/// `byPath` is derived from `submodules`, so comparing it would be comparing
	/// the same fact twice.
	public static func == (lhs: GitEstate, rhs: GitEstate) -> Bool {
		lhs.root == rhs.root && lhs.submodules == rhs.submodules
	}
}

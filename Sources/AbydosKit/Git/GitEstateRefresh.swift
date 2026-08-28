import Foundation

/// Which repositories a filesystem event has actually made stale.
///
/// **This is what makes an estate affordable to keep true.** Reading all of it
/// is 0.45 s over 200 submodules; reading the one repository an event named is
/// 0.01 s. On a schedule of dozens of events a minute during a build, that is
/// the difference between a program that can hold a superproject open and one
/// that cannot.
///
/// The events arrive on two watchers and not six hundred, because of how git
/// lays a superproject out: **a submodule's git directory is always its
/// parent's git directory plus `modules/<name>`**, at any depth, and every
/// submodule's work tree is a directory inside the superproject's. So one
/// `RepositoryWatcher` over the estate's git directory sees every submodule's
/// refs and index, and one `FileSystemWatcher` over the work tree sees every
/// submodule's files. What is missing is only the attribution, which is this.
///
/// **The estate's git directory is not always `root/.git`.** A linked
/// worktree's is `<main>/.git/worktrees/<name>`, which is not under the work
/// tree at all — and its submodules are under *that*, not under the main
/// `.git/modules`. A rule that looked for `.git/` inside the work tree
/// attributed nothing there, so a commit or a checkout made in a worktree
/// changed no row. All four arrangements were checked against a real
/// repository; see `GitSubmodule.gitDirectorySuffix`.
public enum GitEstateRefresh {
	/// The repositories to re-read, and whether the inventory itself moved.
	public struct Work: Sendable, Equatable {
		/// Whether the superproject's own status is stale.
		public var superproject: Bool
		/// The submodules whose status is stale, in path order.
		public var submodulePaths: [String]
		/// Whether which submodules exist may have changed.
		public var inventory: Bool

		public var isEmpty: Bool { !superproject && submodulePaths.isEmpty && !inventory }

		public init(
			superproject: Bool = false,
			submodulePaths: [String] = [],
			inventory: Bool = false
		) {
			self.superproject = superproject
			self.submodulePaths = submodulePaths
			self.inventory = inventory
		}
	}

	/// What the paths named by an event make stale.
	///
	/// Takes paths rather than repositories, because that is what a watcher has:
	/// a list of things that moved on disk, some of them files and some of them
	/// directories. Attribution is the same for both — it is a prefix question —
	/// and only the inventory needs to know a file's name.
	///
	/// **A path outside the estate makes nothing stale.** A watcher can be
	/// pointed at a directory that is no longer the project, and an event from
	/// one is a reason to do nothing rather than a reason to sweep.
	public static func work(forChangedPaths paths: [URL], in estate: GitEstate) -> Work {
		var work = Work()
		var stale = Set<String>()
		let bySuffix = gitDirectorySuffixes(in: estate)
		let gitDirectory = estate.gitDirectoryOrDefault

		for path in paths {
			// **The git directory first, and it is not always inside the work
			// tree.** A linked worktree's `.git` is a file pointing at
			// `<main>/.git/worktrees/<name>`, so a rule that only looked under
			// the work tree attributed nothing at all there — a commit or a
			// checkout made in a worktree changed no row. Asked before the work
			// tree because in an ordinary checkout the git directory *is* under
			// it, and the longer prefix is the right answer.
			if let inside = relativePath(of: path, under: gitDirectory) {
				attribute(insideGitDirectory: inside, bySuffix: bySuffix,
					work: &work, stale: &stale)
				continue
			}

			guard let relative = relativePath(of: path, under: estate.root) else { continue }

			// `.gitmodules` is decoration rather than truth, but a change to it
			// is the usual thing to happen alongside a submodule being added.
			// A nested one has its own, which is a fact about *that* repository.
			if relative == ".gitmodules" || relative.hasSuffix("/.gitmodules") {
				work.inventory = true
				if let submodule = estate.submodule(containing: relative) {
					stale.insert(submodule.path)
				} else {
					work.superproject = true
				}
				continue
			}

			if let submodule = estate.submodule(containing: relative) {
				stale.insert(submodule.path)
			} else {
				work.superproject = true
			}
		}

		work.submodulePaths = stale.sorted()
		return work
	}

	/// What a path inside the estate's git directory makes stale.
	private static func attribute(
		insideGitDirectory inside: String,
		bySuffix: [String: String],
		work: inout Work,
		stale: inout Set<String>
	) {
		if inside.hasPrefix("modules/") {
			if let owned = submodulePath(forGitDirectory: inside, in: bySuffix) {
				stale.insert(owned)
			} else {
				// A git directory this inventory does not know is a submodule
				// added or removed since it was read — at any depth.
				work.inventory = true
			}
			return
		}

		work.superproject = true
		// `index` is where the gitlinks live, so a write to it can have changed
		// which submodules exist. The bare git directory counts too: a watcher
		// that reports directories rather than files cannot tell an index write
		// from a ref write, and re-reading the inventory is 0.01 s — cheap
		// enough to be conservative about, which sweeping two hundred
		// repositories would not be.
		if inside.isEmpty || inside == "index" { work.inventory = true }
	}

	/// The same question for the directories a `RepositoryWatcher` reports.
	public static func work(forChangedDirectories directories: [URL], in estate: GitEstate) -> Work {
		work(forChangedPaths: directories, in: estate)
	}

	/// Submodule paths by where their git directory sits, relative to the
	/// estate's own.
	///
	/// Keyed by that rather than by name, because the name alone stops being
	/// enough as soon as anything nests: `modules/svc` and
	/// `modules/svc/modules/lib/leaf` are both "the git directory of a
	/// submodule", and only the whole suffix says which. The suffix is built
	/// with the inventory, where the chain of names is known.
	///
	/// A name is still what git files each level under, and a name is not a
	/// path: a submodule moved with `git mv` keeps the name it was added with,
	/// so the directory stays `modules/old-name` while the work tree is
	/// somewhere else entirely.
	static func gitDirectorySuffixes(in estate: GitEstate) -> [String: String] {
		var bySuffix: [String: String] = [:]
		for submodule in estate.submodules {
			bySuffix[submodule.gitDirectorySuffix] = submodule.path
		}
		return bySuffix
	}

	/// Which submodule a path inside the estate's git directory belongs to.
	///
	/// The remainder is a suffix followed by whatever inside that git directory
	/// changed — `modules/svc-47/refs/heads` — and both a name and a nesting
	/// chain may hold slashes, so the longest suffix that prefixes it wins.
	static func submodulePath(
		forGitDirectory remainder: String,
		in bySuffix: [String: String]
	) -> String? {
		var candidate = remainder
		while true {
			if let path = bySuffix[candidate] { return path }
			guard let slash = candidate.lastIndex(of: "/") else { return nil }
			candidate = String(candidate[candidate.startIndex..<slash])
		}
	}

	/// A path written relative to the estate's root, or nil if it is not under
	/// it at all.
	static func relativePath(of path: URL, under root: URL) -> String? {
		let path = path.standardizedFileURL.path
		let root = root.standardizedFileURL.path
		if path == root { return "" }
		guard path.hasPrefix(root + "/") else { return nil }
		return String(path.dropFirst(root.count + 1))
	}
}

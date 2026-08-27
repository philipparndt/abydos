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
/// lays a superproject out: every submodule's git directory is inside the
/// superproject's own `.git/modules`, and every submodule's work tree is a
/// directory inside the superproject's. So one `RepositoryWatcher` over `.git`
/// sees every submodule's refs and index, and one `FileSystemWatcher` over the
/// work tree sees every submodule's files. What is missing is only the
/// attribution, which is this.
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
		let namesToPaths = submoduleNames(in: estate)

		for path in paths {
			guard let relative = relativePath(of: path, under: estate.root) else { continue }

			// Inside the superproject's git directory, which is also where every
			// submodule's git directory lives.
			if relative == ".git" || relative.hasPrefix(".git/") {
				let inside = relative == ".git" ? "" : String(relative.dropFirst(".git/".count))

				if inside.hasPrefix("modules/") {
					let name = String(inside.dropFirst("modules/".count))
					if let owned = submodulePath(forGitDirectory: name, in: namesToPaths) {
						stale.insert(owned)
					} else {
						// A git directory under a name this inventory does not
						// know is a submodule that has been added or removed
						// since it was read.
						work.inventory = true
					}
					continue
				}

				work.superproject = true
				// `.git/index` is where the gitlinks live, so a write to it can
				// have changed which submodules exist. The bare `.git` counts
				// too: a watcher that reports directories rather than files
				// cannot tell an index write from a ref write, and re-reading
				// the inventory is 0.01 s — cheap enough to be conservative
				// about, which sweeping two hundred repositories would not be.
				if inside.isEmpty || inside == "index" { work.inventory = true }
				continue
			}

			// `.gitmodules` is decoration rather than truth, but a change to it
			// is the usual thing to happen alongside a submodule being added.
			if relative == ".gitmodules" {
				work.superproject = true
				work.inventory = true
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

	/// The same question for the directories a `RepositoryWatcher` reports.
	public static func work(forChangedDirectories directories: [URL], in estate: GitEstate) -> Work {
		work(forChangedPaths: directories, in: estate)
	}

	/// Submodule paths by the name their git directory is filed under.
	///
	/// `.git/modules` is keyed by a submodule's *name*, and a name is not its
	/// path: a submodule moved with `git mv` keeps the name it was added with,
	/// so the directory stays `.git/modules/old-name` while the work tree is
	/// somewhere else entirely. Matching on the path would then attribute every
	/// ref change in that submodule to nothing.
	static func submoduleNames(in estate: GitEstate) -> [String: String] {
		var byName: [String: String] = [:]
		for submodule in estate.submodules {
			// The name defaults to the path, which is what `submodule add`
			// gives it and what a `.gitmodules` this program could not read
			// leaves us assuming.
			byName[submodule.name ?? submodule.path] = submodule.path
		}
		return byName
	}

	/// Which submodule a path under `.git/modules` belongs to.
	///
	/// The remainder after `modules/` is the name followed by whatever inside
	/// that git directory changed — `svc-47/refs/heads` — and a name may itself
	/// hold slashes, so the longest name that prefixes the remainder wins.
	static func submodulePath(
		forGitDirectory remainder: String,
		in namesToPaths: [String: String]
	) -> String? {
		var candidate = remainder
		while true {
			if let path = namesToPaths[candidate] { return path }
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

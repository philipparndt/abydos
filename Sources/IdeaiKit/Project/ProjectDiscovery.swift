import Foundation

/// A repository checkout found by scanning, rather than one that has been
/// opened before.
public struct DiscoveredProject: Equatable, Sendable {
	public let url: URL
	/// When the repository was last worked on. Distant past when unreadable.
	public let lastActivity: Date

	public init(url: URL, lastActivity: Date) {
		self.url = url
		self.lastActivity = lastActivity
	}

	public var name: String { url.lastPathComponent }
}

/// Finds repository checkouts under a set of directories.
///
/// The switcher used to list only projects that had been opened in this app,
/// which makes it useless for the thing you actually want it for — opening a
/// project for the first time. This walks the directories where checkouts
/// live, the way `tmuxctl` does, and ranks them by when they were last touched.
public enum ProjectDiscovery {
	/// Directories that hold dependencies or output rather than projects.
	///
	/// Scanning these is not just slow — `node_modules` alone can hold hundreds
	/// of vendored checkouts, none of which anyone means to open.
	public static let skippedDirectories: Set<String> = [
		"node_modules", "vendor", "dist", "build", "target", "Pods", ".build",
	]

	/// Whether a directory is the root of a checkout.
	///
	/// A `.git` *file* counts as well as a directory: that is what a worktree
	/// has, and a worktree is a project you open like any other.
	public static func isProjectRoot(_ url: URL) -> Bool {
		FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
	}

	/// Estimates when a checkout was last worked on.
	///
	/// From the mtimes of the git metadata that changes on commits, checkouts,
	/// staging — and even on `git status`, which rewrites the index. A stat is
	/// cheap; running `git` once per candidate would not be, and this list can
	/// run to hundreds.
	public static func lastActivity(of url: URL) -> Date {
		let candidates = [
			".git/index",
			".git/HEAD",
			".git/FETCH_HEAD",
			".git",              // A worktree's .git is a file.
		]

		var latest = Date.distantPast
		for candidate in candidates {
			let path = url.appendingPathComponent(candidate).path
			guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
			      let modified = attributes[.modificationDate] as? Date
			else { continue }
			if modified > latest { latest = modified }
		}
		return latest
	}

	/// Walks `roots` and returns the checkouts below them, most recent first.
	///
	/// Blocking, and touches the file system for every directory it passes, so
	/// callers run it off the main thread.
	public static func scan(roots: [URL], maxDepth: Int = 3) -> [DiscoveredProject] {
		var found: [String: DiscoveredProject] = [:]

		for root in roots {
			walk(root, depth: 0, maxDepth: maxDepth) { url in
				// Keyed by path: two roots can reach the same checkout, and a
				// duplicate row in the switcher is worse than a missing one.
				let path = url.standardizedFileURL.path
				guard found[path] == nil else { return }
				found[path] = DiscoveredProject(url: url, lastActivity: lastActivity(of: url))
			}
		}

		return sorted(Array(found.values))
	}

	/// Most recently worked on first.
	///
	/// Checkouts whose metadata could not be read all report the same distant
	/// past, so the tie-breaks decide their order: shallower paths first, since
	/// a project nearer the top of a dev directory is more likely the one meant,
	/// then by path so the list does not reshuffle between scans.
	public static func sorted(_ projects: [DiscoveredProject]) -> [DiscoveredProject] {
		projects.sorted { left, right in
			if left.lastActivity != right.lastActivity {
				return left.lastActivity > right.lastActivity
			}

			let leftDepth = left.url.pathComponents.count
			let rightDepth = right.url.pathComponents.count
			if leftDepth != rightDepth { return leftDepth < rightDepth }

			return left.url.path < right.url.path
		}
	}

	/// Visits directories below `root`, reporting each checkout it finds.
	///
	/// Does not descend into a checkout: a repository's subdirectories are not
	/// themselves projects, and a monorepo would otherwise flood the list.
	private static func walk(
		_ root: URL,
		depth: Int,
		maxDepth: Int,
		found: (URL) -> Void
	) {
		guard depth < maxDepth else { return }

		let contents = try? FileManager.default.contentsOfDirectory(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)
		guard let contents else { return }

		for url in contents {
			let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
			guard values?.isDirectory == true else { continue }

			let name = url.lastPathComponent
			guard !name.hasPrefix("."), !skippedDirectories.contains(name) else { continue }

			if isProjectRoot(url) {
				found(url)
			} else {
				walk(url, depth: depth + 1, maxDepth: maxDepth, found: found)
			}
		}
	}

	/// The directories scanned by default.
	///
	/// `~/dev` is where this project's author keeps checkouts and is the same
	/// default `tmuxctl` ships; anyone else changes it in Settings.
	public static var defaultSearchPaths: [String] { ["~/dev"] }

	/// Expands `~` and drops paths that are not directories.
	public static func resolve(searchPaths: [String]) -> [URL] {
		searchPaths.compactMap { path in
			let expanded = (path as NSString).expandingTildeInPath
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
			      isDirectory.boolValue
			else { return nil }
			return URL(fileURLWithPath: expanded, isDirectory: true)
		}
	}
}

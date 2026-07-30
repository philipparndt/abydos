import Foundation

/// Filters the recent-projects list as the user types.
///
/// Lives here rather than in the popover so the ranking rules are testable
/// without a window, and so any other project picker gets the same behaviour.
public enum ProjectFilter {
	/// Projects matching `query`, best first.
	///
	/// Both name and path are searched, because "3d" is a perfectly reasonable
	/// way to look for everything under `~/dev/3d`.
	public static func match(_ entries: [RecentProject], query: String) -> [RecentProject] {
		let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }

		let matches = entries.filter {
			$0.name.lowercased().contains(needle) || $0.displayPath.lowercased().contains(needle)
		}

		return matches.sorted { a, b in
			// A name that starts with what you typed is almost always the one you
			// meant, so those come first; then a name match over a path-only
			// match; then most recent.
			let aPrefix = a.name.lowercased().hasPrefix(needle)
			let bPrefix = b.name.lowercased().hasPrefix(needle)
			if aPrefix != bPrefix { return aPrefix }

			let aName = a.name.lowercased().contains(needle)
			let bName = b.name.lowercased().contains(needle)
			if aName != bName { return aName }

			return a.lastOpened > b.lastOpened
		}
	}
}

import Foundation

/// Which project a directory belongs to.
///
/// Used to follow a terminal: a shell that changes directory has moved to
/// another project, and the question is which one.
public enum ProjectRoot {
	/// The repository a directory sits in, or nil if it sits in none.
	///
	/// A submodule is part of the project that contains it rather than a
	/// project of its own — you go into one to change something about the
	/// project you were already in, and having the window follow you there
	/// would lose the very thing you were working on. Its `.git` is a file
	/// pointing into the parent's `.git/modules`, which is how it is told apart
	/// from a linked worktree, whose `.git` file points into `worktrees` and
	/// which really is its own project.
	public static func find(from directory: URL) -> URL? {
		var current = directory.standardizedFileURL

		while true {
			let dotGit = current.appendingPathComponent(".git")
			var isDirectory: ObjCBool = false
			if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
				if isDirectory.boolValue { return current }
				if !isSubmodulePointer(dotGit) { return current }
				// A submodule: keep climbing to whatever contains it.
			}

			// At the root, deleting the last component gives the root back.
			let parent = current.deletingLastPathComponent().standardizedFileURL
			guard parent.path != current.path else { return nil }
			current = parent
		}
	}

	/// Whether a `.git` file belongs to a submodule rather than a worktree.
	///
	/// Both are files of the form `gitdir: <path>`. A submodule's points inside
	/// the containing repository's `modules` directory; a worktree's points
	/// inside `worktrees`. Anything unrecognised is treated as standing alone,
	/// which is the safer of the two: it stops where it is rather than climbing
	/// out of the project the user meant.
	private static func isSubmodulePointer(_ file: URL) -> Bool {
		guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return false }
		guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
		else { return false }

		let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
		return target.contains("/modules/") || target.hasPrefix("modules/")
	}
}

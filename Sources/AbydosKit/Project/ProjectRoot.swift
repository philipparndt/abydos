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

	/// Which project a window showing `current` should move to, for a terminal
	/// that is now in `directory` — or nil for "stay where you are".
	///
	/// `find` answers "which repository is this directory in", and the window
	/// used to take that as the answer to "where has the shell gone". They are
	/// the same question only while the project *is* its repository. A project
	/// opened at a subdirectory — `abydos-examples/cadova-models`, a package
	/// inside a checkout — has `find` answering the checkout for every directory
	/// in it, including the project's own, so the window left the project a
	/// second after opening it for a shell that had not moved at all. That is
	/// 0509, and it cost the tabs somebody had just opened.
	///
	/// So: a directory inside the project the window is already on is not a move
	/// to anywhere. That is the rule `terminalDirectoryChanged` has always
	/// claimed — "moving between directories inside one changes nothing" — said
	/// about the project rather than about the repository, which is the whole of
	/// the difference. A shell that steps *out* of the project is somewhere else
	/// and is followed exactly as before, `cd ..` into the containing repository
	/// included: that is a real move, and refusing it would make following mean
	/// nothing for a project that is not its own git root.
	public static func projectToFollow(from directory: URL, current: URL?) -> URL? {
		if let current, contains(current, directory) { return nil }
		guard let found = find(from: directory) else { return nil }
		guard found.path != current?.standardizedFileURL.path else { return nil }
		return found
	}

	/// Whether `directory` is `root` or sits under it.
	private static func contains(_ root: URL, _ directory: URL) -> Bool {
		let root = root.standardizedFileURL.path
		let directory = directory.standardizedFileURL.path
		return directory == root || directory.hasPrefix(root + "/")
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

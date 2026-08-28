import Foundation

/// Which project a directory belongs to.
///
/// Used to follow a terminal: a shell that changes directory has moved to
/// another project, and the question is which one.
public enum ProjectRoot {
	/// What a window is showing, which is what decides what a shell moving
	/// somewhere else means.
	///
	/// Three states rather than an optional root, because a folder in no working
	/// copy is shown without being a project — and the difference is exactly
	/// what `whereToFollow` has to know. A window on a *project* is not moved by
	/// a shell going deeper into it; a window on a folder is.
	public enum Showing: Equatable, Sendable {
		case nothing
		case project(URL)
		case looseFolder(URL)
	}

	/// What a window should do about a terminal that has moved.
	public enum Move: Equatable, Sendable {
		/// Nothing. The shell has not left anywhere.
		case stay
		/// Show this root, as a project, with everything a project has.
		case project(URL)
		/// Show this folder. It is in no working copy, so it is not a project:
		/// no session of its own, nothing written into it, and not a recent.
		case looseFolder(URL)
	}

	/// The working copy a directory sits in, or nil if it sits in none.
	///
	/// A submodule is part of the project that contains it rather than a
	/// project of its own — you go into one to change something about the
	/// project you were already in, and having the window follow you there
	/// would lose the very thing you were working on. Its `.git` is a file
	/// pointing into the parent's `.git/modules`, which is how it is told apart
	/// from a linked worktree, whose `.git` file points into `worktrees` and
	/// which really is its own project.
	///
	/// **Not only git.** A window that follows a shell between two checkouts and
	/// refuses to follow it into a Subversion working copy is not obeying a rule
	/// anybody would recognise: it looks broken, and nothing is said to tell the
	/// two apart. So `.svn` and `.hg` answer here too.
	///
	/// Deliberately *not* `Subprojects.markers`. Climbing finds the nearest
	/// marker, so the `go.mod` and `pom.xml` in that list would root a
	/// multi-module checkout at whichever module the shell was standing in —
	/// which is not a project switch, it is the window losing the checkout.
	/// Those names are the scope mechanism inside a project and stay that.
	public static func find(from directory: URL) -> URL? {
		var current = directory.standardizedFileURL
		// The highest directory of a run of old-layout Subversion metadata seen
		// so far. See `mark(at:)` for what makes a run, and the climb below for
		// why the answer cannot wait until the walk has finished.
		var subversionRun: URL?

		while true {
			switch mark(at: current) {
			case .root:
				return asDirectory(current)
			case .subversionInterior:
				subversionRun = current
			case .submodule, .none:
				break
			}

			// At the root, deleting the last component gives the root back.
			let parent = current.deletingLastPathComponent().standardizedFileURL
			guard parent.path != current.path else { return subversionRun.map(asDirectory) }

			// The run of old-layout metadata has ended, so what was remembered
			// is the working copy's own root. Answered here rather than after
			// the climb because a repository *above* the working copy would
			// otherwise be found first, and the working copy lost inside it.
			if let subversionRun, !exists(".svn", in: parent) { return asDirectory(subversionRun) }

			current = parent
		}
	}

	/// What a window showing `showing` should do about a terminal that is now in
	/// `directory` — `.stay` for "you are already where you should be".
	///
	/// `find` answers "which working copy is this directory in", and the window
	/// used to take that as the answer to "where has the shell gone". They are
	/// the same question only while the project *is* its working copy. A project
	/// opened at a subdirectory — `abydos-examples/cadova-models`, a package
	/// inside a checkout — has `find` answering the checkout for every directory
	/// in it, including the project's own, so the window left the project a
	/// second after opening it for a shell that had not moved at all. That is
	/// 0509, and it cost the tabs somebody had just opened.
	///
	/// So: a directory inside the project the window is already on is not a move
	/// to anywhere. That is the rule `terminalDirectoryChanged` has always
	/// claimed — "moving between directories inside one changes nothing" — said
	/// about the project rather than about the working copy, which is the whole
	/// of the difference. A shell that steps *out* of the project is somewhere
	/// else and is followed exactly as before, `cd ..` into the containing
	/// checkout included: that is a real move, and refusing it would make
	/// following mean nothing for a project that is not its own repository root.
	///
	/// **A folder is not a project, and that rule does not reach it.** A window
	/// showing a folder in no working copy is showing somewhere somebody walked
	/// to, and walking one directory further is walking somewhere else. There is
	/// nothing per-folder to put away, so following costs nothing and staying
	/// put would only mean the tree lying about where the shell is.
	public static func whereToFollow(from directory: URL, showing: Showing) -> Move {
		let directory = directory.standardizedFileURL

		// A directory that is not there is not followed. A shell can be sitting
		// in a working directory that has been deleted underneath it, and the
		// path it reports then names nothing: 0534 is a window that pointed at
		// one, discarding the tab it had been given. Asked before the climb
		// rather than after it, because climbing out of a path that is gone
		// finds the repository that used to contain it and reads like a move.
		guard isDirectory(directory) else { return .stay }

		let found = find(from: directory)

		if case let .project(root) = showing {
			let root = asDirectory(root)

			// The project's own root answers for every directory in it, so a
			// marker that *is* the project is a shell sitting where it was put.
			if let found, found.path == root.path { return .stay }

			// **A working copy inside the project is a project of its own, and
			// walking into it is a move.** This is the one place containment
			// gives way, and it is here because of what happens without it: a
			// folder opened at the home directory — which `.abydos` then marks
			// for ever — made every checkout underneath it "inside the project",
			// so no `cd` moved the window again. Stuck, with nothing said.
			if let found, found.path != root.path, contains(root, found) {
				return .project(found)
			}

			// Otherwise a directory inside the project is not a move. That is
			// 0509, and the marker above the project — the checkout a package
			// sits in — is exactly the case it names.
			if contains(root, directory) { return .stay }
		}

		if let found { return .project(found) }

		if case let .looseFolder(folder) = showing,
		   folder.standardizedFileURL.path == directory.path { return .stay }
		return .looseFolder(asDirectory(directory))
	}

	/// What the metadata in one directory says about it.
	private enum Mark {
		/// The root of a project, whatever made it one.
		case root
		/// A submodule's `.git` file: part of the project that contains it, so
		/// the climb carries on to whatever that is.
		case submodule
		/// A `.svn` that is not a working copy's root. Subversion 1.7 and later
		/// keep one at the root holding `wc.db`; before that every directory had
		/// one, so the nearest is the directory the shell is standing in and the
		/// root is the topmost of the run.
		case subversionInterior
		/// Nothing here.
		case none
	}

	private static func mark(at directory: URL) -> Mark {
		// Asked first, and before `.git`. It is not a mark version control left:
		// it is this application's own note that somebody opened this folder as
		// a project, which is a stronger statement about a directory than
		// anything else here — including inside a submodule, where somebody who
		// opened one deliberately meant it.
		if exists(AbydosFolder.name, in: directory) { return .root }
		if exists(AbydosFolder.previousName, in: directory) { return .root }

		let dotGit = directory.appendingPathComponent(".git")
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
			if isDirectory.boolValue { return .root }
			return isSubmodulePointer(dotGit) ? .submodule : .root
		}

		// One `.hg` at the root, like a repository's `.git`.
		if exists(".hg", in: directory) { return .root }

		if exists(".svn", in: directory) {
			// `wc.db` is what a 1.7-or-later working copy keeps beside the rest
			// of its metadata, and it is only ever at the root. Without it this
			// is a directory of a checkout made by an older client, which wrote
			// a `.svn` into every one of them — and answering with the nearest
			// would root the window at `wc/trunk/src` rather than at `wc`.
			return exists("wc.db", in: directory.appendingPathComponent(".svn"))
				? .root : .subversionInterior
		}

		return .none
	}

	/// A root as a directory URL, whatever shape the caller's was.
	///
	/// `URL` equality counts the trailing slash, so the same directory built by
	/// `appendingPathComponent` and by `deletingLastPathComponent` compares
	/// unequal while the two paths are identical — which makes a `Move` carrying
	/// one shape fail to match a `Move` carrying the other. It cost two of the
	/// first tests written against this, both of them passing the same directory
	/// in by two routes. A project root is a directory, so it is said once here
	/// rather than left for every caller and every test to know.
	private static func asDirectory(_ url: URL) -> URL {
		URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
	}

	private static func exists(_ name: String, in directory: URL) -> Bool {
		FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
	}

	private static func isDirectory(_ url: URL) -> Bool {
		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
		return exists && isDirectory.boolValue
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

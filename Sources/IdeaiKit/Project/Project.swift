import Foundation

/// One open project: a root directory plus its version-control state.
public final class Project {
	public let root: URL
	public private(set) var git: GitRepository?

	public init(root: URL) {
		self.root = root.standardizedFileURL
	}

	public var name: String { root.lastPathComponent }

	/// Home-relative path, matching how IDEA shows it under the project name.
	public var displayPath: String { Project.abbreviate(root) }

	public static func abbreviate(_ url: URL) -> String {
		let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		if path == home { return "~" }
		if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
		return path
	}

	/// Finds the enclosing git work tree and loads its status.
	/// The part of the project being worked on, when it is not the whole of it.
	///
	/// Held here rather than passed in, so every refresh looks in the same
	/// place: a load started for the whole project and one started for a
	/// subproject can be in flight at once, and whichever finishes last must
	/// not be the one that decides which repository this is.
	public var scope: URL?

	/// Finds the repository this project is in.
	///
	/// From the subproject when there is one, because a checkout of several
	/// repositories is the case subprojects exist for: the work tree git acts
	/// on is the one the part being worked on belongs to, which need not be the
	/// one the tree is rooted in.
	public func loadGit() async {
		let repo = await GitRepository.discover(from: scope ?? root)
		await repo?.refresh()
		git = repo
	}

	/// The project a file belongs to.
	///
	/// The repository around it, since that is what anybody means by "the
	/// project"; failing that, the directory the file sits in, which is at
	/// least something to show a tree of. What `ideai path/to/file.go` opens.
	public static func root(containing file: URL) -> URL {
		var directory = file.standardizedFileURL
		if !((try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
			directory = directory.deletingLastPathComponent()
		}
		return ProjectRoot.find(from: directory) ?? directory
	}

	/// Path relative to the git root, which is what `git status` output is keyed by.
	/// Note this is the *git* root, which may sit above the project root.
	public func gitRelativePath(for url: URL, gitRoot: URL) -> String {
		let base = gitRoot.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		guard path.hasPrefix(base + "/") else { return "" }
		return String(path.dropFirst(base.count + 1))
	}
}

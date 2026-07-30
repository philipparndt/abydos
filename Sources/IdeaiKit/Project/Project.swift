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
	public func loadGit() async {
		let repo = await GitRepository.discover(from: root)
		await repo?.refresh()
		git = repo
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

import Foundation

/// A node in the project tree.
///
/// Children are loaded on demand: opening a project reads only the root
/// directory, so a repository with a huge `node_modules` costs nothing until
/// someone actually expands it.
public final class FileNode {
	public let url: URL
	public let isDirectory: Bool
	public private(set) weak var parent: FileNode?

	private var loadedChildren: [FileNode]?

	public var gitStatus: GitFileStatus = .unmodified

	public init(url: URL, isDirectory: Bool, parent: FileNode? = nil) {
		self.url = url.standardizedFileURL
		self.isDirectory = isDirectory
		self.parent = parent
	}

	public var name: String { url.lastPathComponent }

	/// Directories that hold build output rather than source. The navigator tints
	/// these the way IDEA marks excluded roots.
	public static let excludedDirectoryNames: Set<String> = [
		"node_modules", ".build", "build", "dist", "out", "target",
		"DerivedData", ".gradle", "__pycache__", ".venv", "venv", ".next",
	]

	public var isExcluded: Bool {
		isDirectory && FileNode.excludedDirectoryNames.contains(name)
	}

	public var hasLoadedChildren: Bool { loadedChildren != nil }

	/// Children, read from disk on first access.
	public var children: [FileNode] {
		if let loadedChildren { return loadedChildren }
		let loaded = FileNode.read(directory: url, parent: self)
		loadedChildren = loaded
		return loaded
	}

	/// Drops cached children so the next access re-reads the directory.
	public func invalidate() {
		loadedChildren = nil
	}

	/// Re-reads this directory, preserving the identity of nodes that still
	/// exist so expansion state and selection survive a refresh.
	public func reloadPreservingIdentity() {
		guard isDirectory, let existing = loadedChildren else { return }
		var byPath = [String: FileNode]()
		for child in existing { byPath[child.url.path] = child }

		let fresh = FileNode.read(directory: url, parent: self)
		loadedChildren = fresh.map { node in
			guard let previous = byPath[node.url.path], previous.isDirectory == node.isDirectory else {
				return node
			}
			// Recurse only into directories the user had already opened.
			if previous.hasLoadedChildren { previous.reloadPreservingIdentity() }
			return previous
		}
	}

	private static func read(directory: URL, parent: FileNode?) -> [FileNode] {
		let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
		guard let entries = try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: keys,
			// Hidden files are included deliberately: `.idea`, `.gitignore` and
			// friends are visible in the reference screenshot.
			options: []
		) else { return [] }

		let nodes = entries.compactMap { url -> FileNode? in
			// `.git` itself is noise; its contents are never browsed.
			if url.lastPathComponent == ".git" { return nil }
			if url.lastPathComponent == ".DS_Store" { return nil }
			let values = try? url.resourceValues(forKeys: Set(keys))
			return FileNode(url: url, isDirectory: values?.isDirectory ?? false, parent: parent)
		}

		return nodes.sorted(by: FileNode.order)
	}

	/// Directories first, then case-insensitive name order — IDEA's arrangement.
	public static func order(_ a: FileNode, _ b: FileNode) -> Bool {
		if a.isDirectory != b.isDirectory { return a.isDirectory }
		return a.name.localizedStandardCompare(b.name) == .orderedAscending
	}

	/// Walks down to `target`, loading directories along the way.
	/// Used to reveal a file in the tree.
	public func node(for target: URL) -> FileNode? {
		let targetPath = target.standardizedFileURL.path
		if targetPath == url.path { return self }
		guard targetPath.hasPrefix(url.path + "/") else { return nil }

		for child in children {
			if targetPath == child.url.path { return child }
			if child.isDirectory, targetPath.hasPrefix(child.url.path + "/") {
				return child.node(for: target)
			}
		}
		return nil
	}

	/// Applies version-control state to every loaded node beneath this one.
	/// Unloaded subtrees are skipped — they will pick up status when expanded.
	public func applyGitStatus(gitRoot: URL, lookup: (String, Bool) -> GitFileStatus) {
		let base = gitRoot.path
		let path = url.path
		let relative: String
		if path == base {
			relative = ""
		} else if path.hasPrefix(base + "/") {
			relative = String(path.dropFirst(base.count + 1))
		} else {
			relative = ""
		}

		gitStatus = lookup(relative, isDirectory)
		guard let loadedChildren else { return }
		for child in loadedChildren {
			child.applyGitStatus(gitRoot: gitRoot, lookup: lookup)
		}
	}
}

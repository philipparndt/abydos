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
	/// these the way IDEA marks excluded roots. Editable in Settings.
	public static let defaultExcludedDirectoryNames: Set<String> = [
		"node_modules", ".build", "build", "dist", "out", "target",
		"DerivedData", ".gradle", "__pycache__", ".venv", "venv", ".next",
	]

	public var isExcluded: Bool {
		isDirectory && Set(Settings.shared.excludedDirectories).contains(name)
	}

	public var hasLoadedChildren: Bool { loadedChildren != nil }

	/// What the last reading of this directory was taken against.
	///
	/// A directory's modification time moves when an entry is added, removed or
	/// renamed, which is exactly when this listing would come out different. It
	/// does *not* move when a file's contents change, and it does not need to:
	/// the tree shows names, not contents. `showsHiddenFiles` rides along
	/// because it decides what the listing leaves out, so turning it on has to
	/// count as a change here even though nothing on disk moved.
	private struct Reading: Equatable {
		/// Seconds and nanoseconds, straight from `stat`, and a flag saying the
		/// directory could not be stat'd at all — which is a change worth
		/// noticing rather than a reason to keep the old listing.
		let seconds: Int
		let nanoseconds: Int
		let readable: Bool
		let showsHiddenFiles: Bool
	}

	private var lastReading: Reading?

	/// Taken *before* the directory is listed, never after.
	///
	/// A write that lands between the stamp and the listing then leaves a stamp
	/// older than what was read, so the next reload reads the directory again.
	/// Stamping afterwards would record the newer time against the older
	/// listing and the file would stay invisible until something else moved.
	///
	/// `stat` rather than `URL.resourceValues`, which was what this was first
	/// written with and which quietly never worked: `NSURL` caches the values
	/// it has been asked for, so the second reading of a directory came back
	/// with the first reading's time and every directory looked unchanged for
	/// ever. Three tests here caught it — a file added, a file removed, and a
	/// file added three directories down — and they are the reason to keep
	/// them.
	private func readingNow() -> Reading {
		var info = stat()
		let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
			guard let path else { return false }
			return stat(path, &info) == 0
		}
		return Reading(
			seconds: ok ? Int(info.st_mtimespec.tv_sec) : 0,
			nanoseconds: ok ? Int(info.st_mtimespec.tv_nsec) : 0,
			readable: ok,
			showsHiddenFiles: Settings.shared.showHiddenFiles
		)
	}

	/// How many directories have been listed, for a test to say that an
	/// unchanged one was not listed again.
	nonisolated(unsafe) public static var directoryReadsForTesting = 0

	/// Makes this directory look unread, so a test can measure what listing it
	/// again costs.
	public func forgetLastReadingForTesting() {
		lastReading = nil
	}

	/// Children, read from disk on first access.
	public var children: [FileNode] {
		if let loadedChildren { return loadedChildren }
		let reading = readingNow()
		let loaded = FileNode.read(directory: url, parent: self)
		lastReading = reading
		loadedChildren = loaded
		return loaded
	}

	/// Drops cached children so the next access re-reads the directory.
	public func invalidate() {
		loadedChildren = nil
		lastReading = nil
	}

	/// Re-reads this directory, preserving the identity of nodes that still
	/// exist so expansion state and selection survive a refresh.
	///
	/// A directory whose modification time has not moved is not listed again.
	/// That is what makes this affordable to call on a whole tree: the
	/// navigator re-reads everything it has open whenever the window comes
	/// forward, and in a project of a quarter of a million files — a repository
	/// with a dozen worktrees inside it — listing and sorting every open
	/// directory was taking the main thread for the better part of a second,
	/// several times a minute, which is what typing into a terminal was waiting
	/// behind. Sorting is most of that cost: `localizedStandardCompare` goes
	/// through ICU for every comparison, and it is paid per directory whether
	/// anything changed or not.
	public func reloadPreservingIdentity() {
		guard isDirectory, let existing = loadedChildren else { return }

		let reading = readingNow()
		if let lastReading, lastReading == reading {
			// Nothing has been added, removed or renamed here, so this listing
			// still stands. It says nothing about the directories below, which
			// have their own times and are asked separately.
			for child in existing where child.hasLoadedChildren {
				child.reloadPreservingIdentity()
			}
			return
		}

		var byPath = [String: FileNode]()
		for child in existing { byPath[child.url.path] = child }

		let fresh = FileNode.read(directory: url, parent: self)
		lastReading = reading
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
		directoryReadsForTesting += 1
		let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
		guard let entries = try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: keys,
			// Hidden files are included deliberately: `.idea`, `.gitignore` and
			// friends are visible in the reference screenshot.
			options: []
		) else { return [] }

		let showHidden = Settings.shared.showHiddenFiles
		let nodes = entries.compactMap { url -> FileNode? in
			let name = url.lastPathComponent
			// `.git` itself is noise; its contents are never browsed.
			if name == ".git" { return nil }
			if name == ".DS_Store" { return nil }
			if !showHidden && name.hasPrefix(".") { return nil }
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

	/// Walks down to `target` through directories that are already open, and
	/// gives up rather than opening one that is not.
	///
	/// `node(for:)` below lists a directory in order to look inside it, which is
	/// exactly right for revealing a file somebody asked for and exactly wrong
	/// for the filesystem watcher. The watcher re-reads the directories the user
	/// has expanded, and it asked `node(for:)` about every directory an event
	/// named — so a build writing into `.build/…/Modules` listed `.build`, then
	/// the configuration directory below it, then the one below that, on the
	/// main queue, only to establish that the directory at the end of the path
	/// was not open after all. The guard said "only re-read directories the user
	/// has actually expanded" and the lookup in front of it had already read
	/// four that nobody had.
	///
	/// Worse than the one event, because a listing stays: a directory read once
	/// is loaded for ever, so every later reload walked it, `git status`
	/// collected a path for each of its files, and `applyGitStatus` visited them
	/// all. The tree grew the whole of a build's output while nobody was looking
	/// at any of it, and each event cost more than the last.
	public func loadedNode(for target: URL) -> FileNode? {
		let targetPath = target.standardizedFileURL.path
		if targetPath == url.path { return self }
		guard targetPath.hasPrefix(url.path + "/"), let loadedChildren else { return nil }

		for child in loadedChildren {
			if targetPath == child.url.path { return child }
			if child.isDirectory, targetPath.hasPrefix(child.url.path + "/") {
				return child.loadedNode(for: target)
			}
		}
		return nil
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

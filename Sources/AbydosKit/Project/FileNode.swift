import Foundation

/// A node in the project tree.
///
/// Children are loaded on demand: opening a project reads only the root
/// directory, so a repository with a huge `node_modules` costs nothing until
/// someone actually expands it.
public final class FileNode {
	public let url: URL
	public let isDirectory: Bool
	/// Whether the entry itself is a link, which is decided when the directory
	/// is listed and asked again by nothing.
	///
	/// Only compaction reads it, and it reads it to refuse: a directory holding
	/// one link back to itself is a chain with no end, and walking it is a hang
	/// in the tree rather than a wrong row.
	public let isSymbolicLink: Bool
	public private(set) weak var parent: FileNode?

	private var loadedChildren: [FileNode]?

	public var gitStatus: GitFileStatus = .unmodified

	public init(
		url: URL,
		isDirectory: Bool,
		isSymbolicLink: Bool = false,
		parent: FileNode? = nil
	) {
		self.url = url.standardizedFileURL
		self.isDirectory = isDirectory
		self.isSymbolicLink = isSymbolicLink
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

	/// How many nodes are held in memory below this one, counting itself.
	///
	/// The tree is lazy, so this is not the size of the project: it is how much
	/// of the project has been listed and kept. That distinction is the whole
	/// subject of `loadedNode(for:)` — before it, a build pulled its output
	/// directory into the tree while nobody was looking at it, and this number
	/// grew all afternoon. It is the number to watch after a build at 0428's
	/// scale, and nothing could report it.
	public var loadedNodeCount: Int {
		guard let loadedChildren else { return 1 }
		return 1 + loadedChildren.reduce(0) { $0 + $1.loadedNodeCount }
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
			return FileNode(
				url: url,
				isDirectory: values?.isDirectory ?? false,
				isSymbolicLink: values?.isSymbolicLink ?? false,
				parent: parent
			)
		}

		return nodes.sorted(by: FileNode.order)
	}

	/// Directories first, then case-insensitive name order — IDEA's arrangement.
	public static func order(_ a: FileNode, _ b: FileNode) -> Bool {
		if a.isDirectory != b.isDirectory { return a.isDirectory }
		return a.name.localizedStandardCompare(b.name) == .orderedAscending
	}

	// MARK: - Compaction

	/// Directories whose contents are packages rather than folders.
	///
	/// Two things follow from a name being in here, and they are the same thing
	/// seen from either side: a chain **ends** at one of these, and the chain
	/// that starts below it is written with dots. So `src/main/java` is one row
	/// and the `com.example.myapp` beneath it is another, which is what IDEA
	/// shows and what was asked for — a single row reading
	/// `src/main/java/com/example/myapp` would fold a source root into a package
	/// and be neither.
	///
	/// The Maven and Gradle convention, and nothing more than that: there is no
	/// source-root model in the tree, and building one to answer this question
	/// would be the larger half of the change. Every project laid out the way
	/// those two lay one out gets the same answer from the path alone.
	private static let sourceRootNames: Set<String> = ["java", "kotlin", "scala"]

	/// The children of this directory with every chain of single-directory
	/// folders replaced by the directory the chain ends at.
	///
	/// `src/main/java/com/example/myapp` is five rows before any code and four
	/// of them say only "there is one more folder inside me". This is what makes
	/// them one row; `compactedName` is what writes that row's name.
	public var compactedChildren: [FileNode] { children.map(\.compactedRow) }

	/// The row this node is drawn as when compaction is on.
	///
	/// Itself, unless it is a directory holding exactly one directory — then the
	/// deepest directory reachable through steps that each hold exactly one
	/// entry and that entry a directory. A file, an excluded directory, or a
	/// directory holding anything but one directory is its own row.
	public var compactedRow: FileNode {
		// A root is the project, and its name is the one thing on screen that
		// says which project this is. It is never folded into anything.
		guard parent != nil else { return self }
		var node = self
		while let only = node.onlyFoldableChild { node = only }
		return node
	}

	/// Whether this directory has no row of its own with compaction on: its name
	/// is drawn as part of the row below it.
	///
	/// The question the four hand-written walks ask. Each of them descends
	/// through `children` and would otherwise try to open a row the outline
	/// does not have.
	public var isCompactedAway: Bool {
		parent != nil && onlyFoldableChild != nil
	}

	/// The single directory this directory holds, when that is all it holds.
	///
	/// Nil ends a chain, and it ends it for every reason a chain ends: two
	/// entries, one entry that is a file, an excluded directory on either side —
	/// `target` is tinted for a reason and folding it away would hide it — a
	/// symbolic link, which is where a chain can have no end at all, and a source
	/// root, below which the chain is a package and starts again.
	private var onlyFoldableChild: FileNode? {
		guard isDirectory, !isExcluded, !isSymbolicLink else { return nil }
		guard !FileNode.sourceRootNames.contains(name) else { return nil }
		let entries = children
		guard entries.count == 1, let only = entries.first else { return nil }
		guard only.isDirectory, !only.isExcluded, !only.isSymbolicLink else { return nil }
		return only
	}

	/// The name a folded row carries: every directory folded into it, and then
	/// its own.
	///
	/// Recovered by walking *up* rather than stored beside the row, and that is
	/// deliberate: it is exactly the inverse of the walk that produced the row,
	/// so the two cannot drift, and there is no state to keep in step with a
	/// tree that reloads under it.
	public var compactedName: String {
		guard isDirectory else { return name }
		var components = [name]
		var top = self
		// `onlyFoldableChild === top` is the step down, asked from above: the
		// parent is part of this row exactly when this row is what the parent
		// would have folded into.
		while let above = top.parent, above.parent != nil, above.onlyFoldableChild === top {
			components.append(above.name)
			top = above
		}
		guard components.count > 1 else { return name }
		return components.reversed().joined(separator: top.chainSeparator)
	}

	/// Dots below `java`, `kotlin` or `scala`, slashes everywhere else, asked of
	/// the node the chain begins at.
	///
	/// So `com/example/myapp` under a source root reads `com.example.myapp`,
	/// which is what it is called, and the `src/main/java` above it reads as
	/// itself rather than as `src.main.java`, which is a name for something
	/// nobody calls that.
	private var chainSeparator: String {
		guard let above = parent, FileNode.sourceRootNames.contains(above.name) else { return "/" }
		return "."
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

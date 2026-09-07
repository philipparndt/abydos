import Foundation

/// Where an entry that was opened came from, carried on its tab.
public struct ArchiveOrigin: Sendable, Equatable {
	public let archive: URL
	public let entryPath: String

	public init(archive: URL, entryPath: String) {
		self.archive = archive
		self.entryPath = entryPath
	}

	/// What the tab's grey half says.
	public var said: String { "inside \(archive.lastPathComponent)" }
}

/// An archive somebody asked to see into, and what has been read of it.
///
/// One per shown archive, held by the tree and shared by every row inside
/// it. The index arrives off the main thread; until it does the row says it
/// is reading, and if it never does the row says why.
public final class ArchiveRoot {
	public let url: URL
	public private(set) var index: ArchiveIndex?
	public private(set) var failure: String?
	public private(set) var children: [ArchiveNode] = []

	public init(url: URL) {
		self.url = url
	}

	public var isReading: Bool { index == nil && failure == nil }

	public func set(index: ArchiveIndex) {
		self.index = index
		failure = nil
		children = index.children(of: nil).map { ArchiveNode(entry: $0, root: self, parent: nil) }
		if children.isEmpty {
			children = [ArchiveNode(note: "This archive is empty.", root: self)]
		}
	}

	public func set(failure: String) {
		self.failure = failure
		index = nil
		children = [ArchiveNode(note: failure, root: self)]
	}

	/// The row for a path inside the archive, walking only what is loaded.
	public func node(forPath path: String) -> ArchiveNode? {
		var candidates = children
		var found: ArchiveNode?
		for part in path.split(separator: "/").map(String.init) {
			guard let next = candidates.first(where: { $0.entry?.name == part }) else { return nil }
			found = next
			candidates = next.children
		}
		return found
	}
}

/// A row inside a shown archive: a directory, an entry, or a note.
///
/// A class because `NSOutlineView` identifies its items by object, the same
/// reason `FileNode` and `DependencyNode` are. Not a `FileNode`: an entry is
/// not on disk, and everything a file row gets for free — `stat`, git colour,
/// rename, trash — would be wrong for it.
public final class ArchiveNode {
	public enum Row {
		case directory(ArchiveEntry)
		case entry(ArchiveEntry)
		case note(String)
	}

	public let row: Row
	public unowned let root: ArchiveRoot
	public private(set) weak var parent: ArchiveNode?
	private var loadedChildren: [ArchiveNode]?

	public init(entry: ArchiveEntry, root: ArchiveRoot, parent: ArchiveNode?) {
		row = entry.isDirectory ? .directory(entry) : .entry(entry)
		self.root = root
		self.parent = parent
	}

	public init(note: String, root: ArchiveRoot) {
		row = .note(note)
		self.root = root
	}

	public var entry: ArchiveEntry? {
		switch row {
		case .directory(let entry), .entry(let entry): return entry
		case .note: return nil
		}
	}

	public var isDirectory: Bool {
		if case .directory = row { return true }
		return false
	}

	public var isExpandable: Bool { isDirectory }

	/// Directories first, then names, from the index, read once.
	public var children: [ArchiveNode] {
		if let loadedChildren { return loadedChildren }
		guard case .directory(let entry) = row, let index = root.index else { return [] }
		let made = index.children(of: entry.path).map { ArchiveNode(entry: $0, root: root, parent: self) }
		loadedChildren = made
		return made
	}

	public var name: String {
		switch row {
		case .directory(let entry), .entry(let entry): return entry.name
		case .note(let text): return text
		}
	}

	/// The grey half: a size for a file, what it is for anything that is not
	/// bytes to show, nothing for a directory.
	public var subtitle: String? {
		switch row {
		case .directory, .note: return nil
		case .entry(let entry):
			switch entry.member {
			case .regular: return ByteSize.said(Int64(entry.size))
			case .directory: return nil
			case .symlink(let target): return target.isEmpty ? "link" : "→ \(target)"
			case .other(let what): return what
			}
		}
	}

	/// Whether choosing it opens something.
	public var isOpenable: Bool {
		if case .entry(let entry) = row, entry.member == .regular { return true }
		return false
	}

	/// Where it came from, for the tab.
	public var origin: ArchiveOrigin? {
		entry.map { ArchiveOrigin(archive: root.url, entryPath: $0.path) }
	}

	/// The key the session keeps an opened directory under, beside the
	/// archive's own: `archive:<archive>!<path inside>`.
	public func foldKey(archiveKey: String) -> String? {
		guard case .directory(let entry) = row else { return nil }
		return "\(archiveKey)!\(entry.path)"
	}
}

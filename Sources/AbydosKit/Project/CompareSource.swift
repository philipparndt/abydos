import Foundation

/// One side of a comparison: a file or a folder, on disk or at a commit.
///
/// Four cases rather than a URL, because the two questions a page asks of a
/// side — *can it be listed* and *can it be written to* — have four different
/// answers. A folder on disk lists and takes copies; a tree at a commit lists
/// and is read-only; a file does neither and is read whole. A `git archive`
/// into a temporary directory would have made every side a folder on disk and
/// every comparison of three files unpack a tree of a hundred megabytes first.
public enum CompareSource: Hashable, Sendable {
	case file(URL)
	case folder(URL)
	/// A file as git holds it at a commit, by the path that repository knows
	/// it by.
	case blob(repository: URL, commit: String, path: String)
	/// A directory of a commit's tree; the empty path is the root of it.
	case tree(repository: URL, commit: String, path: String)

	public var isFolder: Bool {
		switch self {
		case .folder, .tree: return true
		case .file, .blob: return false
		}
	}

	/// Whether a copy can land here. Only the disk takes writes; a commit is
	/// what it is.
	public var isWritable: Bool {
		switch self {
		case .file, .folder: return true
		case .blob, .tree: return false
		}
	}

	/// Where it is on disk, when it is.
	public var diskURL: URL? {
		switch self {
		case .file(let url), .folder(let url): return url
		case .blob, .tree: return nil
		}
	}

	/// The commit, when there is one, as git abbreviates it.
	public var shortCommit: String? {
		switch self {
		case .file, .folder: return nil
		case .blob(_, let commit, _), .tree(_, let commit, _): return String(commit.prefix(8))
		}
	}

	/// What the title calls it: the last component of the path, or the
	/// repository's name for a tree at its root.
	public var name: String {
		switch self {
		case .file(let url), .folder(let url):
			return url.lastPathComponent
		case .blob(_, _, let path):
			return (path as NSString).lastPathComponent
		case .tree(let repository, _, let path):
			return path.isEmpty ? repository.lastPathComponent : (path as NSString).lastPathComponent
		}
	}

	/// Where it is from, for the shelf: a path with `~` in it, or the commit.
	public var origin: String {
		switch self {
		case .file(let url), .folder(let url):
			return (url.path as NSString).abbreviatingWithTildeInPath
		case .blob(let repository, let commit, let path), .tree(let repository, let commit, let path):
			let place = path.isEmpty ? repository.lastPathComponent : path
			return "\(place) at \(String(commit.prefix(8)))"
		}
	}

	/// Whether two sides can be the two sides of one page. A file is compared
	/// with a file and a folder with a folder; the refusal is the page's to
	/// say, this only decides it.
	public func canBeComparedWith(_ other: CompareSource) -> Bool {
		isFolder == other.isFolder
	}

	/// Whether a disk side is still there. A commit does not go away.
	public var exists: Bool {
		guard let url = diskURL else { return true }
		return FileManager.default.fileExists(atPath: url.path)
	}

	/// The bytes of a file side; nil for a folder, and nil where git has no
	/// such blob or the disk no such file.
	public func readData() async -> Data? {
		switch self {
		case .file(let url):
			return try? Data(contentsOf: url)
		case .blob(let repository, let commit, let path):
			return await GitBlob.read(commit, path: path, in: repository)
		case .folder, .tree:
			return nil
		}
	}

	/// The text of a file side, decoded as the editor would decode it.
	public func readText() async -> String? {
		guard let data = await readData() else { return nil }
		return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
	}

	/// The same side, one relative path deeper: what a row of a folder diff
	/// opens as.
	public func descending(to relativePath: String, isDirectory: Bool) -> CompareSource {
		switch self {
		case .file, .blob:
			return self
		case .folder(let url):
			let child = url.appendingPathComponent(relativePath, isDirectory: isDirectory)
			return isDirectory ? .folder(child) : .file(child)
		case .tree(let repository, let commit, let path):
			let child = path.isEmpty ? relativePath : path + "/" + relativePath
			return isDirectory
				? .tree(repository: repository, commit: commit, path: child)
				: .blob(repository: repository, commit: commit, path: child)
		}
	}
}

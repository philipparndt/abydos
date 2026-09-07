import CryptoKit
import Foundation

/// Where an opened entry is written, so the editor has a file to open.
///
/// The editor, syntax, find, the structure pane and the hex editor all take a
/// URL, so an entry somebody opens is written once under the system's cache
/// directory — never inside the project, so git never sees it — in a folder
/// keyed to the archive's path, size and modification time, so a replaced
/// archive never serves a stale copy. The system clears its caches when it
/// likes; nothing here manages them beyond that.
public enum ArchiveCache {
	public static func directory(
		for index: ArchiveIndex,
		caches: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
	) -> URL {
		let seed = "\(index.url.path)\n\(index.key.size)\n\(index.key.modified.timeIntervalSince1970)"
		let digest = SHA256.hash(data: Data(seed.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
		return caches.appendingPathComponent("abydos/archives/\(digest)", isDirectory: true)
	}

	/// The entry as a file, written the first time and reused after.
	public static func file(for entry: ArchiveEntry, in index: ArchiveIndex, caches: URL? = nil) throws -> URL {
		let root = caches.map { directory(for: index, caches: $0) } ?? directory(for: index)
		let target = root.appendingPathComponent(entry.path)
		if FileManager.default.fileExists(atPath: target.path) { return target }
		let data = try index.read(entry)
		try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
		try data.write(to: target, options: .atomic)
		return target
	}

	/// Writes an entry — a directory with its subtree — into `directory`
	/// under its own name, and returns what it wrote. Refuses to overwrite
	/// unless told; the caller asks the person first.
	@discardableResult
	public static func extract(
		_ entry: ArchiveEntry, from index: ArchiveIndex, into directory: URL, overwrite: Bool
	) throws -> URL {
		let target = directory.appendingPathComponent(entry.name)
		if FileManager.default.fileExists(atPath: target.path) {
			guard overwrite else { throw ExtractFailure.exists(target) }
			try FileManager.default.removeItem(at: target)
		}
		if entry.isDirectory {
			try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
			let prefix = entry.path + "/"
			for member in index.entries where member.path.hasPrefix(prefix) {
				let relative = String(member.path.dropFirst(prefix.count))
				let destination = target.appendingPathComponent(relative)
				if member.isDirectory {
					try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
				} else if member.member == .regular {
					try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
					try index.read(member).write(to: destination, options: .atomic)
				}
			}
		} else {
			try index.read(entry).write(to: target, options: .atomic)
		}
		return target
	}

	public enum ExtractFailure: Error, Equatable {
		/// Something is already there; ask before writing over it.
		case exists(URL)
	}
}

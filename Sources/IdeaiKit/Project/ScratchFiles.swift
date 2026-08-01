import CryptoKit
import Foundation

/// Unnamed buffers belonging to a project.
///
/// Somewhere to try something out that is not worth a file in the repository —
/// a query, a snippet, a paste from somewhere else. They keep syntax
/// highlighting and they survive quitting, which is what separates them from a
/// window you have not saved yet.
///
/// Kept outside the project rather than in a dotfile inside it. A scratch is
/// nobody else's business: it should not appear in `git status`, be carried by
/// a commit, or have to be added to an ignore file before the project is
/// tidy again.
public struct ScratchFiles {
	/// Where every project's scratches live.
	public let root: URL
	/// The project these belong to.
	public let projectRoot: URL

	public init(projectRoot: URL, root: URL? = nil) {
		self.projectRoot = projectRoot.standardizedFileURL
		self.root = root ?? Self.defaultRoot
	}

	public static var defaultRoot: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSTemporaryDirectory())
		return base.appendingPathComponent("ideai/scratch", isDirectory: true)
	}

	/// The directory holding this project's scratches.
	///
	/// Named for a digest of the project's path rather than the path itself: a
	/// path can be long, contain anything, and is not a legal file name.
	public var directory: URL {
		let digest = SHA256.hash(data: Data(projectRoot.path.utf8))
		let name = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
		return root.appendingPathComponent(name, isDirectory: true)
	}

	/// The scratches of this project, oldest first.
	public func all() -> [URL] {
		let contents = try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.creationDateKey],
			options: [.skipsHiddenFiles]
		)
		return (contents ?? []).sorted { left, right in
			let leftDate = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
			let rightDate = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
			if leftDate != rightDate { return leftDate < rightDate }
			return left.lastPathComponent < right.lastPathComponent
		}
	}

	/// Makes an empty scratch and returns where it went.
	///
	/// Numbered from one and counting past whatever is already there, so the
	/// name matches what the tab says and two scratches never collide.
	@discardableResult
	public func create(extension fileExtension: String = "txt") throws -> URL {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		var number = all().count + 1
		var destination = directory.appendingPathComponent("scratch-\(number).\(fileExtension)")
		while FileManager.default.fileExists(atPath: destination.path) {
			number += 1
			destination = directory.appendingPathComponent("scratch-\(number).\(fileExtension)")
		}

		try Data().write(to: destination, options: .withoutOverwriting)
		return destination
	}

	/// Whether a file is one of these, wherever it was opened from.
	public func contains(_ url: URL) -> Bool {
		url.standardizedFileURL.deletingLastPathComponent().path == directory.path
	}

	/// Whether a file is any project's scratch.
	public static func isScratch(_ url: URL, root: URL? = nil) -> Bool {
		let root = (root ?? defaultRoot).standardizedFileURL.path
		return url.standardizedFileURL.path.hasPrefix(root + "/")
	}

	/// What a scratch is called on its tab.
	///
	/// Numbered rather than named: it has no name, and that is the point of it.
	public static func title(for url: URL) -> String {
		let stem = url.deletingPathExtension().lastPathComponent
		guard stem.hasPrefix("scratch-"), let number = Int(stem.dropFirst("scratch-".count)) else {
			return stem
		}
		return "Scratch \(number)"
	}

	public func remove(_ url: URL) throws {
		guard contains(url) else { return }
		try FileManager.default.removeItem(at: url)
	}
}

import Foundation

/// The rows that have been sent to the trash and have not yet left the disk.
///
/// **Because the trash answers too late to be what takes a row away.** ⌘⌫ hands
/// the URLs to `NSWorkspace.recycle` and returns; the row went when the file
/// system watcher noticed the file had left its directory — after a cross-process
/// round trip, and after up to a quarter-second of event coalescing if anything
/// else was writing. For a folder that had never been expanded it did not go at
/// all: the must-scan event names the folder, and the handler re-reads only
/// directories the tree has listed. Reported as "it takes long till the project
/// view refreshes and removes the file. Sometimes it takes so long that the user
/// tries again and gets an error message" — the second press being an error
/// because the dead URL was handed to the trash a second time.
///
/// So the rows are marked here the moment the key is pressed and the tree is
/// redrawn without them. `hides(_:)` is asked by the one walk every row goes
/// through, and the trash's completion clears the mark and re-reads
/// `parents(of:)`, so the tree does not wait on the watcher for either half.
///
/// **A set of URLs rather than of nodes.** A node is rebuilt by every re-read of
/// its directory, and the mark has to outlive one: the watcher can re-read a
/// parent while the trash is still working. A URL is what both ends of the
/// gesture agree on.
public struct DoomedRows: Equatable {
	private var urls: Set<String> = []

	public init() {}

	/// Whether this row should be drawn.
	///
	/// Standardised on both sides, since a URL built from a path typed into a
	/// driving flag and one a directory read produced differ by a `/private`
	/// prefix and nothing else.
	public func hides(_ url: URL) -> Bool {
		urls.contains(Self.key(url))
	}

	public var isEmpty: Bool { urls.isEmpty }

	/// Sends these rows away. A union, because two trashes can be out at once
	/// and each completion clears only its own.
	public mutating func mark(_ marked: [URL]) {
		for url in marked { urls.insert(Self.key(url)) }
	}

	/// Brings these rows back — or, having watched them leave the disk, forgets
	/// them. The same call for both, because the set says only "not drawn" and
	/// the answer to why is on the disk by then.
	public mutating func clear(_ cleared: [URL]) {
		for url in cleared { urls.remove(Self.key(url)) }
	}

	/// The folders to re-read once the trash has answered.
	///
	/// Deduplicated, since three files trashed out of one folder are one
	/// re-read, and in the order the folders were first named so that a run
	/// saying what it re-read says the same thing twice.
	public static func parents(of urls: [URL]) -> [URL] {
		var seen: Set<String> = []
		var folders: [URL] = []
		for url in urls {
			let parent = url.standardizedFileURL.deletingLastPathComponent()
			guard seen.insert(parent.standardizedFileURL.path).inserted else { continue }
			folders.append(parent)
		}
		return folders
	}

	private static func key(_ url: URL) -> String {
		url.standardizedFileURL.resolvingSymlinksInPath().path
	}
}

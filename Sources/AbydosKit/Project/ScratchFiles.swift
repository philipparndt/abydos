import CryptoKit
import Foundation

/// Unnamed buffers, belonging to a project or to nothing in particular.
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
	/// The project these belong to, or nil for the ones that belong to no
	/// project — notes about a language, a machine, a way of doing something,
	/// which outlive whichever checkout they were first written in.
	public let projectRoot: URL?

	public init(projectRoot: URL?, root: URL? = nil) {
		self.projectRoot = projectRoot.map(Self.canonical)
		self.root = root ?? Self.defaultRoot
	}

	/// One spelling of a project's path.
	///
	/// Symlinks resolved as well as standardised: `/tmp` and `/private/tmp` are
	/// the same directory, and a project reached by each spelling must not end
	/// up with two piles of notes that cannot see one another.
	public static func canonical(_ url: URL) -> URL {
		url.standardizedFileURL.resolvingSymlinksInPath()
	}

	/// The collection that belongs to no project.
	public static func global(root: URL? = nil) -> ScratchFiles {
		ScratchFiles(projectRoot: nil, root: root)
	}

	public var isGlobal: Bool { projectRoot == nil }

	/// Where scratches live: `~/.config/ideai/scratch`.
	///
	/// Not Application Support, where macOS would put them. A scratch is the
	/// only copy of what is in it, and the thing that keeps such a file alive is
	/// somebody knowing where it is — a path you already back up, already have
	/// in a dotfiles repository, and can reach with `cd`. A folder nobody visits
	/// is a folder nobody notices going missing.
	public static var defaultRoot: URL {
		configurationDirectory.appendingPathComponent("ideai/scratch", isDirectory: true)
	}

	/// `$XDG_CONFIG_HOME`, or `~/.config` when it is not set.
	public static var configurationDirectory: URL { UserConfiguration.directory }

	/// Where they used to live, before the move to `~/.config`.
	public static var legacyRoot: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSTemporaryDirectory())
		return base.appendingPathComponent("ideai/scratch", isDirectory: true)
	}

	/// Moves scratches written before the move, once.
	///
	/// Every collection is carried over; anything that would collide is left
	/// where it is rather than overwritten, and the old directory is only
	/// removed once it is empty. Nothing here deletes a note.
	@discardableResult
	public static func migrateLegacyStore(from legacy: URL? = nil, to destination: URL? = nil) -> Int {
		let legacy = legacy ?? legacyRoot
		let destination = destination ?? defaultRoot
		let manager = FileManager.default

		guard manager.fileExists(atPath: legacy.path), legacy.path != destination.path else { return 0 }
		let collections = (try? manager.contentsOfDirectory(
			at: legacy,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: []
		)) ?? []

		var moved = 0
		for collection in collections {
			guard (try? collection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
			let target = destination.appendingPathComponent(collection.lastPathComponent, isDirectory: true)
			try? manager.createDirectory(at: target, withIntermediateDirectories: true)

			let files = (try? manager.contentsOfDirectory(
				at: collection,
				includingPropertiesForKeys: nil,
				options: []
			)) ?? []
			for file in files {
				let landing = target.appendingPathComponent(file.lastPathComponent)
				guard !manager.fileExists(atPath: landing.path) else { continue }
				guard (try? manager.moveItem(at: file, to: landing)) != nil else { continue }
				// The marker travels with them but is not one of them; the count
				// is what gets reported, and it should mean notes.
				if !file.lastPathComponent.hasPrefix(".") { moved += 1 }
			}
			// Only when nothing is left in it.
			try? manager.removeItem(at: collection)
		}
		try? manager.removeItem(at: legacy)
		return moved
	}

	/// The name of the directory holding a project's scratches.
	///
	/// A digest of the project's path rather than the path itself: a path can be
	/// long, contain anything, and is not a legal file name. Sixteen hex
	/// characters, so it can never be mistaken for the global one.
	public static func directoryName(for projectRoot: URL) -> String {
		let digest = SHA256.hash(data: Data(canonical(projectRoot).path.utf8))
		return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
	}

	/// Whether two paths name the same project.
	public static func isSameProject(_ left: URL?, _ right: URL?) -> Bool {
		switch (left, right) {
		case (nil, nil): return true
		case let (left?, right?): return canonical(left).path == canonical(right).path
		default: return false
		}
	}

	/// What the global collection's directory is called.
	public static let globalDirectoryName = "global"

	/// The directory holding these scratches.
	public var directory: URL {
		let name = projectRoot.map(Self.directoryName(for:)) ?? Self.globalDirectoryName
		return root.appendingPathComponent(name, isDirectory: true)
	}

	/// Records which project a digest belongs to, since a digest cannot be read
	/// backwards and a list of anonymous folders would be no list at all.
	static let markerName = ".project"

	/// The project a scratch directory was made for, or nil if it is the global
	/// one or was never marked.
	public static func projectRoot(ofDirectory directory: URL) -> URL? {
		guard directory.lastPathComponent != globalDirectoryName else { return nil }
		guard let path = try? String(
			contentsOf: directory.appendingPathComponent(markerName),
			encoding: .utf8
		) else { return nil }
		let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
	}

	/// Makes the directory, leaving behind which project it is for.
	private func prepareDirectory() throws {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		guard let projectRoot else { return }
		let marker = directory.appendingPathComponent(Self.markerName)
		let existing = try? String(contentsOf: marker, encoding: .utf8)
		guard existing?.trimmingCharacters(in: .whitespacesAndNewlines) != projectRoot.path else { return }
		try? projectRoot.path.write(to: marker, atomically: true, encoding: .utf8)
	}

	/// These scratches, oldest first.
	///
	/// Hidden files are skipped, which is also what keeps the marker out.
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

	/// What a scratch is unless something says otherwise.
	///
	/// Markdown: a scratch is usually notes with a bit of code in it, and
	/// Markdown is the format that highlights both — fenced blocks keep their
	/// own language, and prose does not come out looking like a broken program.
	public static let defaultExtension = "md"

	/// Makes an empty scratch and returns where it went.
	///
	/// Numbered from one and counting past whatever is already there, so the
	/// name matches what the tab says and two scratches never collide.
	@discardableResult
	public func create(extension fileExtension: String = defaultExtension) throws -> URL {
		try prepareDirectory()

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

	/// Whether a file is a scratch of any project, or a global one.
	public static func isScratch(_ url: URL, root: URL? = nil) -> Bool {
		let root = (root ?? defaultRoot).standardizedFileURL.path
		return url.standardizedFileURL.path.hasPrefix(root + "/")
	}

	/// What a scratch is called on its tab.
	///
	/// Numbered until it is renamed: it has no name, and that is the point of
	/// it. Once somebody gives it one, that is what it is called.
	public static func title(for url: URL) -> String {
		let stem = url.deletingPathExtension().lastPathComponent
		guard stem.hasPrefix("scratch-"), let number = Int(stem.dropFirst("scratch-".count)) else {
			return stem
		}
		return "Scratch \(number)"
	}

	/// Puts a scratch in the Trash, rather than deleting it.
	///
	/// Whatever asks for this — a menu item, a tab closing on something that
	/// turned out not to be empty, a mistake — the answer to "where did my note
	/// go" should be somewhere it can be got back from.
	@discardableResult
	public func remove(_ url: URL) throws -> URL? {
		guard contains(url) else { return nil }
		return try Self.moveToTrash(url)
	}

	/// Puts a scratch in the Trash, and says where it landed.
	///
	/// Nil when there was no Trash to use and it had to be removed outright —
	/// which is the answer on volumes that have none, not the normal path.
	@discardableResult
	public static func moveToTrash(_ url: URL) throws -> URL? {
		var landed: NSURL?
		do {
			try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
			return landed as URL?
		} catch {
			try FileManager.default.removeItem(at: url)
			return nil
		}
	}

	/// Gives a scratch a name of its own, keeping it where it is.
	///
	/// The extension is kept unless the new name carries one, so renaming does
	/// not silently turn Markdown into plain text.
	@discardableResult
	public func rename(_ url: URL, to name: String) throws -> URL {
		guard contains(url) else { return url }
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return url }

		var destination = directory.appendingPathComponent(trimmed)
		if destination.pathExtension.isEmpty {
			destination = destination.appendingPathExtension(url.pathExtension)
		}
		guard destination.path != url.path else { return url }
		try FileManager.default.moveItem(at: url, to: destination)
		return destination
	}

	/// Moves a scratch into another collection, keeping its contents.
	///
	/// What a note is about outlives where it was written: something learned
	/// while in one checkout is often worth keeping when the checkout is gone.
	@discardableResult
	public func move(_ url: URL, to other: ScratchFiles) throws -> URL {
		guard contains(url) else { return url }
		try other.prepareDirectory()

		var destination = other.directory.appendingPathComponent(url.lastPathComponent)
		var attempt = 2
		while FileManager.default.fileExists(atPath: destination.path) {
			let stem = url.deletingPathExtension().lastPathComponent
			destination = other.directory
				.appendingPathComponent("\(stem)-\(attempt)")
				.appendingPathExtension(url.pathExtension)
			attempt += 1
		}

		try FileManager.default.moveItem(at: url, to: destination)
		return destination
	}
}

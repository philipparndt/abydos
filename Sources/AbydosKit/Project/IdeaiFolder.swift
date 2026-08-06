import Foundation

/// The `.abydos` folder a project keeps beside its code.
///
/// Two kinds of thing live in it and they are not alike. The launch
/// configurations are part of the project — the same for everybody, worth
/// reviewing, worth committing. Everything else is one person's state on one
/// machine: which files they had open, where their caret was. So the folder
/// ships with a `.gitignore` that commits the first and ignores the second,
/// rather than leaving somebody to notice later that their editor layout is in
/// the repository.
///
/// It used to be called `.ideai`. A project with one is read from it and moved
/// across the first time anything is written, because the alternative is a
/// rename that quietly throws away everybody's launch configurations — the
/// folder is data, and data outlives the name of the program that wrote it.
public enum AbydosFolder {
	public static let name = ".abydos"
	/// What this folder was called before the app was renamed.
	public static let previousName = ".ideai"

	/// The folder to read from: the current one, or the old one when a project
	/// still has it and has not been written to since.
	public static func url(in root: URL) -> URL {
		let current = root.appendingPathComponent(name, isDirectory: true)
		guard !FileManager.default.fileExists(atPath: current.path) else { return current }

		let previous = root.appendingPathComponent(previousName, isDirectory: true)
		return FileManager.default.fileExists(atPath: previous.path) ? previous : current
	}

	/// Where the launch configurations live, one to a file.
	///
	/// A file each rather than one list: two people adding a configuration on
	/// the same day should not be a merge conflict, and a configuration is
	/// then something you can point at, move, or delete with `rm`.
	public static func runDirectory(in root: URL) -> URL {
		url(in: root).appendingPathComponent("run", isDirectory: true)
	}

	/// This machine's view of the project: open files, and where in them.
	public static func sessionFile(in root: URL) -> URL {
		url(in: root).appendingPathComponent("session.json")
	}

	public static func exists(in root: URL) -> Bool {
		FileManager.default.fileExists(atPath: url(in: root).path)
	}

	/// Creates the folder, with the rule about what belongs in git.
	///
	/// Written once and then left alone: somebody who edits it has a reason,
	/// and overwriting it on every save would be the kind of tool that argues
	/// with its user.
	@discardableResult
	public static func create(in root: URL) throws -> URL {
		try migrateIfNeeded(in: root)

		let folder = root.appendingPathComponent(name, isDirectory: true)
		let manager = FileManager.default
		try manager.createDirectory(
			at: folder.appendingPathComponent("run", isDirectory: true),
			withIntermediateDirectories: true
		)

		let ignore = folder.appendingPathComponent(".gitignore")
		guard !manager.fileExists(atPath: ignore.path) else { return folder }
		try gitignore.write(to: ignore, atomically: true, encoding: .utf8)
		return folder
	}

	/// Moves a `.ideai` folder to its new name, once.
	///
	/// A move rather than a copy: two folders would both be read by something
	/// eventually, and a launch configuration edited in one while the other is
	/// still there is a bug nobody will enjoy. Left alone if both exist —
	/// somebody has been working in the new one, and the old is theirs to
	/// delete.
	@discardableResult
	public static func migrateIfNeeded(in root: URL) throws -> Bool {
		let manager = FileManager.default
		let current = root.appendingPathComponent(name, isDirectory: true)
		let previous = root.appendingPathComponent(previousName, isDirectory: true)

		guard manager.fileExists(atPath: previous.path),
		      !manager.fileExists(atPath: current.path)
		else { return false }

		try manager.moveItem(at: previous, to: current)
		return true
	}

	/// Ignore everything here except the run configurations.
	///
	/// The negations have to name the directory before the files inside it:
	/// git does not look into a directory it has already excluded, so
	/// `!run/**` alone would match nothing.
	static let gitignore = """
	# What this app keeps beside the project.
	#
	# The run configurations belong to everybody working on it, so they are
	# committed. Everything else is one machine's state — which files were
	# open, where the caret was — and is not.
	*
	!.gitignore
	!run/
	!run/**

	"""
}

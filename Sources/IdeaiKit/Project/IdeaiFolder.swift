import Foundation

/// The `.ideai` folder a project keeps beside its code.
///
/// Two kinds of thing live in it and they are not alike. The launch
/// configurations are part of the project — the same for everybody, worth
/// reviewing, worth committing. Everything else is one person's state on one
/// machine: which files they had open, where their caret was. So the folder
/// ships with a `.gitignore` that commits the first and ignores the second,
/// rather than leaving somebody to notice later that their editor layout is in
/// the repository.
public enum IdeaiFolder {
	public static let name = ".ideai"

	public static func url(in root: URL) -> URL {
		root.appendingPathComponent(name, isDirectory: true)
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
		let folder = url(in: root)
		let manager = FileManager.default
		try manager.createDirectory(at: runDirectory(in: root), withIntermediateDirectories: true)

		let ignore = folder.appendingPathComponent(".gitignore")
		guard !manager.fileExists(atPath: ignore.path) else { return folder }
		try gitignore.write(to: ignore, atomically: true, encoding: .utf8)
		return folder
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

import Foundation

/// Paths as a launch configuration should hold them.
///
/// A configuration is committed and shared, so a path in it has to mean the
/// same thing on somebody else's machine: `${workspaceFolder}/app`, not
/// `/Users/philipparndt/dev/…/app`. Remembering that is the sort of thing
/// nobody should have to do — the editor lets a file be chosen, and this is
/// what turns the answer back into something shareable.
public enum TemplatePath {
	/// The variables, with what each one stands for. Shown in the editor, so
	/// the list and the descriptions are the documentation.
	public static let variables: [(name: String, meaning: String)] = [
		("${workspaceFolder}", "the project directory"),
		("${workspaceRoot}", "the same, under its older name"),
		("${userHome}", "your home directory"),
	]

	/// Writes a chosen path the way a configuration should hold it.
	///
	/// The project first and the home directory second, because a path inside
	/// the project is the one that has to travel; `~/go/bin/something` is a
	/// tool on this machine, and saying so is still better than spelling out
	/// whose machine it is.
	public static func shareable(_ path: String, root: URL) -> String {
		let canonical = FilePath.canonical(URL(fileURLWithPath: path))
		let base = FilePath.canonical(root)

		if canonical == base { return "${workspaceFolder}" }
		if canonical.hasPrefix(base + "/") {
			return "${workspaceFolder}/" + String(canonical.dropFirst(base.count + 1))
		}

		let home = FilePath.canonical(URL(fileURLWithPath: NSHomeDirectory()))
		if canonical == home { return "${userHome}" }
		if canonical.hasPrefix(home + "/") {
			return "${userHome}/" + String(canonical.dropFirst(home.count + 1))
		}
		return canonical
	}

	/// Where a file chooser should open for a field that already has something
	/// in it: beside what is there, or at the project when it is empty or names
	/// nothing.
	public static func startingDirectory(for value: String, root: URL) -> URL {
		guard !value.isEmpty else { return root }
		let expanded = LaunchConfiguration.expand(value, root: root)
		let url = URL(fileURLWithPath: expanded.hasPrefix("/") ? expanded : FilePath.canonical(root) + "/" + expanded)

		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
			return isDirectory.boolValue ? url : url.deletingLastPathComponent()
		}
		// Half-typed paths are common, and the directory above one usually
		// exists even when the name being typed does not.
		let parent = url.deletingLastPathComponent()
		return FileManager.default.fileExists(atPath: parent.path) ? parent : root
	}
}

import Foundation

/// Folders inside a project that are projects in their own right.
///
/// A repository is often not one thing. `ideai-examples` holds eight projects;
/// a work checkout holds a service, its front end and three libraries. The tree
/// should stay whole — that is how somebody navigates — but everything scoped
/// has to follow the part being worked on: which launch configurations there
/// are, which module a build runs in, which work tree git acts on, which root
/// the language server is given.
///
/// So one folder at a time is the subproject, and this is how they are found.
public enum Subprojects {
	/// What makes a folder look like a project of its own.
	///
	/// Deliberately the marks a build system leaves rather than a guess from
	/// the contents: a folder with a `go.mod` in it is a Go module whatever
	/// else it holds, and a folder with none is a folder.
	public static let markers: [String] = [
		".ideai", ".git",
		"go.mod", "Cargo.toml", "package.json", "build.zig", "pyproject.toml",
		"CMakeLists.txt", "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts",
		"Chart.yaml", "Makefile",
	]

	/// Whether this folder is one.
	public static func isSubproject(_ url: URL) -> Bool {
		let manager = FileManager.default
		var directory: ObjCBool = false
		guard manager.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue
		else { return false }
		return markers.contains { manager.fileExists(atPath: url.appendingPathComponent($0).path) }
	}

	/// The subprojects under a root, nearest first.
	///
	/// Shallow on purpose: two levels finds `go-service` and `native/zig-hello`
	/// without walking a `node_modules`, and a project buried deeper than that
	/// is one somebody can still open by hand.
	public static func find(in root: URL, depth: Int = 2) -> [URL] {
		var found: [URL] = []
		walk(root, root: root, remaining: depth, into: &found)
		return found.sorted {
			relativePath($0, to: root).localizedStandardCompare(relativePath($1, to: root))
				== .orderedAscending
		}
	}

	private static func walk(_ directory: URL, root: URL, remaining: Int, into found: inout [URL]) {
		guard remaining > 0 else { return }
		let manager = FileManager.default
		let contents = (try? manager.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles, .skipsPackageDescendants]
		)) ?? []

		for entry in contents {
			guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
			else { continue }
			guard !skipped.contains(entry.lastPathComponent) else { continue }

			if isSubproject(entry) {
				found.append(entry)
				// And no further: what is inside a module belongs to that
				// module, not to the project above it.
				continue
			}
			walk(entry, root: root, remaining: remaining - 1, into: &found)
		}
	}

	/// Directories that never hold a project worth opening.
	private static let skipped: Set<String> = [
		"node_modules", "vendor", "target", "build", "dist", "out", ".build",
		"DerivedData", "zig-out", "__pycache__", "venv", ".venv",
	]

	/// How a subproject is written down: relative to the project, so a session
	/// written on one machine means the same thing on another.
	public static func relativePath(_ url: URL, to root: URL) -> String {
		let base = FilePath.canonical(root)
		let path = FilePath.canonical(url)
		guard path.hasPrefix(base + "/") else { return path }
		return String(path.dropFirst(base.count + 1))
	}

	/// And back again, refusing anything that is not inside the project.
	///
	/// A session file is on disk and can say anything; a subproject outside the
	/// project it belongs to would scope the window to somewhere the tree does
	/// not show.
	public static func resolve(_ relative: String, in root: URL) -> URL? {
		guard !relative.isEmpty else { return nil }
		// Appended rather than resolved against the root: `URL(fileURLWithPath:
		// relativeTo:)` treats a root without a trailing slash as a file and
		// resolves beside it, which lands one directory too high.
		let candidate = root.appendingPathComponent(relative).standardizedFileURL
		let base = FilePath.canonical(root)
		let path = FilePath.canonical(candidate)
		guard path == base || path.hasPrefix(base + "/") else { return nil }

		var directory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory),
		      directory.boolValue
		else { return nil }
		return candidate
	}
}

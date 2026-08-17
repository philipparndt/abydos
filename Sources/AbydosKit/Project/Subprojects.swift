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
	///
	/// **The bar a name has to clear is that it declares a project, not that it
	/// mentions one.** Every entry here moves the scope pill, the language
	/// server's root, the run configurations and the tree git acts on, all at
	/// once, so a name that is right nine times in ten is not good enough: the
	/// tenth is somebody's ordinary folder claiming a scope nobody asked it to
	/// have, which is a worse failure than the folder that ought to be a
	/// subproject and is not.
	///
	/// That is why `conanfile.txt` is not here and `conanfile.py` is. A recipe
	/// *is* the package — it names it, and it is what `conan create` builds, so
	/// a folder holding one is a project even with nothing else in it.
	/// `conanfile.txt` only says what a directory consumes; it is what Conan's
	/// own documentation puts in an `examples/` folder beside a recipe, and a
	/// directory that is genuinely a project as well as a consumer has the
	/// `CMakeLists.txt` or the `Makefile` that says so, and is found by that.
	/// See 0527 for the whole argument.
	public static let markers: [String] = [
		".ideai", ".git",
		"go.mod", "Cargo.toml", "package.json", "build.zig", "pyproject.toml",
		"CMakeLists.txt", "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts",
		"Chart.yaml",
		// All three names make reads, and all three are named in
		// `RunConfigurationDiscovery.definingFileNames`. Written out rather than
		// left to the file system to fold: on a case-insensitive disk `Makefile`
		// used to match `makefile` by accident, and an accident is not a rule
		// that holds on somebody's case-sensitive volume.
		"Makefile", "makefile", "GNUmakefile",
		"conanfile.py",
	] + BazelBuild.workspaceMarkers

	/// The same, as a set, because every folder walked is asked.
	private static let markerNames = Set(markers)

	/// Whether this folder is one.
	///
	/// Names compared exactly — see `FilePath.entryNames(in:)` for why asking
	/// the file system whether `WORKSPACE` exists is not the same question.
	public static func isSubproject(_ url: URL) -> Bool {
		guard let names = FilePath.entryNames(in: url) else { return false }
		return !markerNames.isDisjoint(with: names)
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
			// `.isDirectoryKey` is false for a symbolic link, whatever it points
			// at, so a link is never walked and never counted. That is what keeps
			// Bazel out of its own way: a built workspace has `bazel-out`,
			// `bazel-bin` and `bazel-<workspace>` beside its `MODULE.bazel`, and
			// the last of those is the execroot, whose top level mirrors the
			// source tree — `MODULE.bazel` included. Followed, it would be a
			// second copy of the workspace offered as a subproject of it.
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

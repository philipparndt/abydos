import Foundation

/// the cost argument above. `conan graph info` *evaluates* `conanfile.py`, which
/// is a Python program out of somebody's repository. `bazel query` starts a
/// server that takes a lock on the output base, so this section would block
/// behind somebody's build or make their next `bazel` command block behind this
/// section. Both are read from text instead, and what text cannot answer — a
/// `WORKSPACE` workspace — says so on its row.
public enum ExternalDependencies {
	/// Every root worth asking, nearest first: the project itself, then its
	/// subprojects.
	///
	/// The whole project rather than the subproject in scope, because the tree
	/// stays whole — that is `Subprojects`' own rule — and because two
	/// subprojects may resolve different versions of the same package, which is
	/// exactly what somebody needs to see when they are wondering which one they
	/// are looking at.
	public static func roots(in project: URL) -> [URL] {
		[project] + Subprojects.find(in: project)
	}

	/// The files whose writing can change the answer, by name.
	///
	/// Kept beside the readers so the two cannot drift — the same rule
	/// `RunConfigurationDiscovery.definingFileNames` follows, and for the same
	/// reason: a name added to a reader and not to this list is a section that
	/// goes stale until the project is reopened. The lock files are here as well
	/// as the manifests, because `swift package resolve` and `go get` write the
	/// lock and leave the manifest alone.
	public static let definingFileNames: Set<String> = {
		var names = Set(DependencyKind.allCases.flatMap(\.markers))
		names.formUnion([
			"Package.resolved", "go.sum", "Cargo.lock", "package-lock.json",
			// npm prefers `npm-shrinkwrap.json` to `package-lock.json` and it is
			// the same format byte for byte, so a project that publishes one
			// resolves through it — and writing one has to reload the section.
			"npm-shrinkwrap.json",
			"pnpm-lock.yaml", "yarn.lock", "MODULE.bazel.lock", "conan.lock",
			// Not a lock file: `pnpm-workspace.yaml` is how pnpm declares the
			// workspace npm declares in `package.json`, so writing one turns every
			// package below it from "run npm install" into "resolved in the
			// workspace at …". `declaresNpmWorkspaces` reads it.
			"pnpm-workspace.yaml",
		])
		// Gradle: the lock file `dependencyLocking` writes, and the version
		// catalog, which is where a modern build keeps the coordinates the build
		// file only refers to. Maven adds nothing — it has no lock file at all,
		// and its `pom.xml` is already here as a marker.
		names.formUnion(["gradle.lockfile", "libs.versions.toml"])
		return names
	}()

	/// The kinds of project a directory is, by the files in it.
	///
	/// Plural: a repository with a `Package.swift` and a `Makefile` is one
	/// thing, but a repository with a `pom.xml` and a `package.json` genuinely
	/// has two dependency graphs and hiding one of them would be a guess.
	///
	/// Names read once and compared exactly rather than asked of `fileExists`,
	/// which on a case-insensitive disk answers yes to `WORKSPACE` for any
	/// project with an ordinary `workspace/` folder in it — and every one of
	/// those was given a Bazel group saying its dependencies were Starlark.
	/// `FilePath.entryNames(in:)` has the rest of the argument.
	public static func kinds(at root: URL) -> [DependencyKind] {
		guard let names = FilePath.entryNames(in: root) else { return [] }
		return DependencyKind.allCases.filter { kind in
			kind.markers.contains { names.contains($0) }
		}
	}

	/// Everything a project depends on, grouped by the root that declares it.
	///
	/// Ordered by root and then by kind, so the section reads the same way twice
	/// running — a set that changed places between two reloads would make the
	/// tree's expansion state meaningless.
	public static func read(project: URL) -> [DependencySet] {
		roots(in: project).flatMap { root in
			kinds(at: root).map { read(root: root, kind: $0) }
		}
	}

	/// One kind, from one directory.
	///
	/// **Teaching this a new kind is five edits and they are all in this file.**
	/// 0514 (npm), 0515 (Maven and Gradle) and 0516 (Bazel and Conan) each do the
	/// same five, and doing them in this order means the section never claims
	/// something that is not there:
	///
	/// 1. A `readX(at:) -> DependencySet.Contents` under a `MARK` of its own, at
	///    the bottom, beside the two here. It reads files and nothing else — see
	///    the rule on this type — and returns `.unresolved(…)` **in the words of
	///    the tool that would fix it** when there is nothing resolved to read,
	///    because `.packages([])` renders as "no dependencies" and would be a
	///    lie. Sort what comes out with `byName`.
	/// 2. If the sources live in a cache outside the project, a locator beside
	///    the reader — `goModuleCache()` and `cargoHome()` are the two shapes:
	///    the tool's own environment variable first, then the default under the
	///    home directory, and never `go env` or `cargo --help` to ask.
	/// 3. The `case` here, moved out of the `.notRead` line.
	/// 4. `DependencyKind.pendingItem`, which must stop naming the item — the row
	///    goes on saying "not read yet" otherwise, over a list it is now reading.
	/// 5. Any lock file the kind resolves into, in `definingFileNames`, so
	///    writing it reloads the section.
	///
	/// Then `everyKindEitherIsReadOrNamesTheItemThatWillReadIt` in the tests
	/// names the kind as read, and a fixture lock file written into a temporary
	/// directory says what comes out of it.
	///
	/// 0525 is the first item to need a sixth edit, and it is a warning rather
	/// than a step: a kind whose marker belongs to **several tools** names the
	/// one that resolved it in `DependencySet.tool`, because the kind's own name
	/// is then wrong for all but one of them. Only JavaScript is like this so
	/// far; see that property for why it is a title rather than three kinds.
	public static func read(root: URL, kind: DependencyKind) -> DependencySet {
		let contents: DependencySet.Contents
		switch kind {
		case .swiftPackage: contents = readSwiftPackages(at: root)
		case .goModule: contents = readGoModules(at: root)
		case .cargo: contents = readCargoPackages(at: root)
		case .npm: contents = readNpm(at: root)
		case .bazel: contents = readBazelModules(at: root)
		case .conan: contents = readConanPackages(at: root)
		case .maven: contents = readMavenPackages(at: root)
		case .gradle: contents = readGradlePackages(at: root)
		}
		return DependencySet(
			root: root, kind: kind,
			tool: kind == .npm ? npmLockFile(at: root)?.tool : nil,
			contents: contents
		)
	}

	/// The order every kind's list comes out in: by name, case-insensitively.
	///
	/// One rule for all of them, and not a per-kind decision, because the
	/// question the section is asked is "what is beside this file" and that is
	/// only answerable by scanning. 508 wrote and then removed a direct-first
	/// ordering for Go for the same reason.
	static func byName(_ packages: [ExternalDependency]) -> DependencySet.Contents {
		.packages(packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
	}
}

import Foundation

/// One package a project depends on, named rather than pathed.
///
/// The unit of the project view's Dependencies section, and the answer to the
/// three questions item 508 was filed for: *which package is this file in*
/// (`name`), *where did it come from* (`origin`, `version`) and *what is beside
/// it* (`localPath`, which the tree lists like any other directory).
///
/// `localPath` is optional and that is not an oversight. A package can be
/// resolved and not fetched — a fresh checkout with a `Package.resolved` and no
/// `.build`, a `go.mod` naming a module that was never downloaded — and the
/// honest row for one of those names the package and offers nothing to open.
/// Pointing at a directory that is not there would make the tree show an empty
/// folder, which reads as a package with no files in it.
public struct ExternalDependency: Equatable, Sendable {
	/// What to call it: the repository's own name where there is one, so the
	/// row matches the directory the sources are in and the import somebody
	/// wrote.
	public let name: String
	/// The version or revision the resolver settled on, as it is written down.
	/// Nil when nothing names one.
	public let version: String?
	/// Where it came from, as the manifest or lock file writes it — a URL for a
	/// Swift package, a module path for a Go module.
	public let origin: String
	/// The sources on disk, when they have been fetched.
	public let localPath: URL?
	/// Other copies of the same checkout on this machine.
	///
	/// A Swift package genuinely has two: `swift build` fetches into the
	/// project's `.build/checkouts`, and sourcekit-lsp — started with a
	/// `--scratch-path` under `~/Library/Caches/abydos/index`, because its index
	/// is derived data and does not belong in the checkout — fetches its own.
	/// Same revision, same files, two paths.
	///
	/// `localPath` is the one the section *shows*; these are the ones it will
	/// still recognise. Without them a file opened from the other copy has no
	/// row in the section and falls back to the ordinary tree, which for a
	/// Swift package means opening `.build` and walking ten levels down to the
	/// same file — the duplicate the section exists to replace.
	public let otherPaths: [URL]

	public init(name: String, version: String?, origin: String, localPath: URL?, otherPaths: [URL] = []) {
		self.name = name
		self.version = version
		self.origin = origin
		self.localPath = localPath
		self.otherPaths = otherPaths
	}

	/// The origin without the noise, for a row eleven characters wide.
	///
	/// `https://github.com/tomasf/Cadova.git` is mostly scheme and mostly the
	/// same as the row above it; `github.com/tomasf` is what tells one package's
	/// provenance from another's at a glance. The whole of it stays available in
	/// the tooltip — this is what is *drawn*, not what is known.
	public var shortOrigin: String {
		var text = origin
		for prefix in ["https://", "http://", "git@", "ssh://"] where text.hasPrefix(prefix) {
			text = String(text.dropFirst(prefix.count))
		}
		if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
		// The last component is the package's own name, which the row already
		// says. What is left is who it came from.
		let parts = text.split(separator: "/")
		guard parts.count > 1 else { return text }
		return parts.dropLast().joined(separator: "/")
	}
}

/// A build system whose dependencies this section knows how to talk about.
///
/// Deliberately a list of every kind `RunConfiguration.Source` can open rather
/// than a list of the kinds that are read: a project whose dependencies nothing
/// here can read must still appear, saying so. A section that quietly omitted
/// Maven would read as "this project has no dependencies", and that is the one
/// failure item 508 named in advance.
public enum DependencyKind: String, Sendable, CaseIterable {
	case swiftPackage
	case goModule
	case cargo
	case npm
	case maven
	case gradle
	case bazel
	case conan

	/// What the section calls it.
	public var title: String {
		switch self {
		case .swiftPackage: return "Swift packages"
		case .goModule: return "Go modules"
		case .cargo: return "Cargo"
		case .npm: return "npm"
		case .maven: return "Maven"
		case .gradle: return "Gradle"
		case .bazel: return "Bazel"
		case .conan: return "Conan"
		}
	}

	/// The files whose presence says a directory is a project of this kind.
	///
	/// Names only, checked with `fileExists` — the whole scan for a project with
	/// eight subprojects is a few dozen stats, which is what makes it affordable
	/// to do on load rather than behind a button.
	public var markers: [String] {
		switch self {
		case .swiftPackage: return ["Package.swift"]
		case .goModule: return ["go.mod"]
		case .cargo: return ["Cargo.toml"]
		case .npm: return ["package.json"]
		case .maven: return ["pom.xml"]
		case .gradle: return ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
		case .bazel: return ["MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel", "WORKSPACE.bzlmod"]
		case .conan: return ["conanfile.py", "conanfile.txt"]
		}
	}

	/// The backlog item that will teach this kind, for the kinds not read yet.
	///
	/// On the row, in the app, because that is the point of the note: somebody
	/// looking at a Maven project can see both that its dependencies are not
	/// read and where that is written down, without going to look for the
	/// backlog. Nil for a kind that is read.
	public var pendingItem: Int? {
		switch self {
		case .swiftPackage, .goModule: return nil
		case .cargo: return 513
		case .npm: return 514
		case .maven, .gradle: return 515
		case .bazel, .conan: return 516
		}
	}
}

/// What one root's dependencies came out as.
///
/// Three answers and not two, because "nothing to show" has two quite different
/// causes and a row that conflated them would be the failure this whole item is
/// about: a kind nothing here can read, and a project of a kind that *is* read
/// which has resolved nothing yet.
public struct DependencySet: Equatable, Sendable {
	public enum Contents: Equatable, Sendable {
		/// Read, and this is what it says. Possibly empty — a `go.mod` with no
		/// `require` is a module with no dependencies, and saying so is right.
		case packages([ExternalDependency])
		/// The kind is recognised and nothing here reads it yet.
		case notRead
		/// The kind is read, and there is nothing resolved to read. The string
		/// says what is missing, in the words of the tool that would make it.
		case unresolved(String)
	}

	/// The directory this was read from: the project, or one of its subprojects.
	public let root: URL
	public let kind: DependencyKind
	public let contents: Contents

	public init(root: URL, kind: DependencyKind, contents: Contents) {
		self.root = root
		self.kind = kind
		self.contents = contents
	}

	public var packages: [ExternalDependency] {
		if case let .packages(packages) = contents { return packages }
		return []
	}
}

/// Finds what a project depends on, from what is already on disk.
///
/// **No subprocess, from any reader, ever.** `SwiftPackage`'s own comment has
/// the measurements: `swift package dump-package` costs the better part of a
/// second per manifest, leaves a `.build` directory behind as a side effect of
/// being *asked*, and answers with whichever toolchain is first on the PATH.
/// The same argument applies to `go list -m all`, `mvn dependency:list` and
/// `bazel query`, and it applies harder here — this runs when a project opens
/// and again whenever a lock file is written, so anything expensive is paid
/// over and over while somebody is trying to read a file.
///
/// The cost of the rule is that two kinds (0516) may turn out not to be
/// readable at all without running their tool. That is a decision for that
/// item; the note on the row is what keeps it visible until somebody makes it.
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
			"pnpm-lock.yaml", "yarn.lock", "MODULE.bazel.lock", "conan.lock",
		])
		return names
	}()

	/// The kinds of project a directory is, by the files in it.
	///
	/// Plural: a repository with a `Package.swift` and a `Makefile` is one
	/// thing, but a repository with a `pom.xml` and a `package.json` genuinely
	/// has two dependency graphs and hiding one of them would be a guess.
	public static func kinds(at root: URL) -> [DependencyKind] {
		let manager = FileManager.default
		return DependencyKind.allCases.filter { kind in
			kind.markers.contains { manager.fileExists(atPath: root.appendingPathComponent($0).path) }
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

	public static func read(root: URL, kind: DependencyKind) -> DependencySet {
		let contents: DependencySet.Contents
		switch kind {
		case .swiftPackage: contents = readSwiftPackages(at: root)
		case .goModule: contents = readGoModules(at: root)
		case .cargo, .npm, .maven, .gradle, .bazel, .conan: contents = .notRead
		}
		return DependencySet(root: root, kind: kind, contents: contents)
	}

	// MARK: - Swift packages

	/// `Package.resolved`, which is JSON and is the resolved graph.
	///
	/// Both layouts, because both are still written: version 1 keys the list
	/// `object.pins` and names a package `package` with a `repositoryURL`,
	/// versions 2 and 3 key it `pins` and name it `identity` with a `location`.
	/// A project resolved by Xcode 15 and one resolved by `swift package
	/// resolve` last week differ by exactly this, and refusing to read the older
	/// one would be a section that empties itself when somebody opens an old
	/// checkout.
	static func readSwiftPackages(at root: URL) -> DependencySet.Contents {
		let resolved = root.appendingPathComponent("Package.resolved")
		guard let data = try? Data(contentsOf: resolved) else {
			return .unresolved("no Package.resolved — run swift package resolve")
		}
		guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return .unresolved("Package.resolved could not be read")
		}
		let pins = (top["pins"] as? [[String: Any]])
			?? ((top["object"] as? [String: Any])?["pins"] as? [[String: Any]])
			?? []

		let checkouts = checkoutDirectories(for: root)
		let manager = FileManager.default
		let packages = pins.compactMap { pin -> ExternalDependency? in
			let location = (pin["location"] as? String) ?? (pin["repositoryURL"] as? String) ?? ""
			let identity = (pin["identity"] as? String) ?? (pin["package"] as? String) ?? ""
			// The repository's own name, which is what the checkout directory is
			// called and what the import says. `identity` is lowercased by SwiftPM
			// — "cadova" — so a row taken from it would match neither the folder
			// on disk nor anything somebody typed.
			let name = Self.repositoryName(from: location) ?? identity
			guard !name.isEmpty else { return nil }

			let state = pin["state"] as? [String: Any]
			let version = (state?["version"] as? String)
				?? (state?["branch"] as? String)
				?? (state?["revision"] as? String).map { String($0.prefix(7)) }

			// The checkout is named after the repository, except when SwiftPM has
			// had to disambiguate — so the identity is tried too rather than
			// assumed away.
			let names = [name, identity].filter { !$0.isEmpty }
			let found = checkouts
				.flatMap { directory in names.map(directory.appendingPathComponent) }
				.filter { manager.fileExists(atPath: $0.path) }

			return ExternalDependency(
				name: name, version: version, origin: location,
				localPath: found.first, otherPaths: Array(found.dropFirst())
			)
		}
		return .packages(packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
	}

	/// Where a Swift package's sources may have been checked out, best first.
	///
	/// **There are two copies and they are not interchangeable, which is the
	/// thing this item found out the hard way.** `swift build` in the project
	/// fetches into `.build/checkouts`. sourcekit-lsp is started with
	/// `--scratch-path` pointing at `~/Library/Caches/abydos/index/<project>-<hash>`
	/// — derived data, deliberately not in the checkout — and fetches its own
	/// copy into `checkouts` beneath *that*. So following a symbol out of
	/// somebody's model opens
	///
	///     ~/Library/Caches/abydos/index/cadova-models-mn5raibyyd7h/checkouts/
	///         Cadova/Sources/Cadova/…/Extrusion.swift
	///
	/// and not the path under `.build` that the report and this item both
	/// assumed. A section that knew only about `.build/checkouts` gave the file
	/// in the tab no home at all — the exact failure being fixed — while
	/// looking correct in every test written against a fixture.
	///
	/// The indexer's copy comes first for that reason: it is the copy *this
	/// program* opens files from, so the row somebody is revealed into is the
	/// row their tab is actually showing. A file under `.build/checkouts` is
	/// inside the project and the ordinary tree already has a row for it.
	static func checkoutDirectories(for root: URL) -> [URL] {
		[
			LanguageServers.indexScratchPath(for: root).appendingPathComponent("checkouts"),
			root.appendingPathComponent(".build/checkouts"),
		]
	}

	/// `https://github.com/tomasf/Cadova.git` → `Cadova`.
	static func repositoryName(from location: String) -> String? {
		var text = location
		if text.hasSuffix("/") { text = String(text.dropLast()) }
		if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
		let last = text.split(whereSeparator: { $0 == "/" || $0 == ":" }).last
		return last.map(String.init)
	}

	// MARK: - Go modules

	/// `go.mod`, which is both the manifest and the resolved set.
	///
	/// There is no lock file to read: since Go 1.17 `go.mod` lists the whole
	/// build list, direct and indirect, each with the version the build uses. So
	/// this reads the `require` clauses — the one-line form and the block form,
	/// which are both common in the same file — and nothing else.
	///
	/// Direct and indirect are not told apart, though `// indirect` is right
	/// there. One list sorted by name is what makes the section browsable: the
	/// question being asked of it is "what is beside this file", and an answer
	/// sorted by how the dependency was reached rather than by its name is an
	/// answer nobody can scan. See item 508 for the argument.
	static func readGoModules(at root: URL) -> DependencySet.Contents {
		let manifest = root.appendingPathComponent("go.mod")
		guard let text = try? String(contentsOf: manifest, encoding: .utf8) else {
			return .unresolved("go.mod could not be read")
		}

		var requires: [(module: String, version: String)] = []
		var inBlock = false
		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			// The comment goes first: `// indirect` sits on most of these lines
			// and would otherwise be counted as two more fields.
			var line = Substring(rawLine)
			if let comment = line.range(of: "//") { line = line[..<comment.lowerBound] }
			line = line.trimmingCharacters(in: .whitespaces)[...]
			guard !line.isEmpty else { continue }

			if inBlock {
				if line == ")" { inBlock = false; continue }
				let fields = line.split(separator: " ").filter { !$0.isEmpty }
				if fields.count >= 2 { requires.append((String(fields[0]), String(fields[1]))) }
				continue
			}
			guard line.hasPrefix("require") else { continue }
			let rest = line.dropFirst("require".count).trimmingCharacters(in: .whitespaces)
			if rest == "(" { inBlock = true; continue }
			let fields = rest.split(separator: " ").filter { !$0.isEmpty }
			if fields.count >= 2 { requires.append((String(fields[0]), String(fields[1]))) }
		}

		let cache = goModuleCache()
		let manager = FileManager.default
		let packages = requires.map { require -> ExternalDependency in
			let directory = cache?
				.appendingPathComponent(escapeGoPath(require.module) + "@" + require.version)
			let local = directory.flatMap { manager.fileExists(atPath: $0.path) ? $0 : nil }
			return ExternalDependency(
				name: require.module,
				version: require.version,
				// A module path *is* where it came from. Go has no separate URL:
				// `github.com/spf13/cobra` is fetched by being named.
				origin: require.module,
				localPath: local
			)
		}
		return .packages(packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
	}

	/// Where the module cache is, without asking `go env`.
	///
	/// `GOMODCACHE`, then `$GOPATH/pkg/mod`, then `~/go/pkg/mod`, which is the
	/// order the toolchain itself resolves them in. A subprocess would be
	/// authoritative and would cost a process launch per project on open; these
	/// three cover every machine that has not deliberately moved it, and a
	/// package whose directory is not found simply has no sources to browse,
	/// which is a state the row already knows how to show.
	static func goModuleCache() -> URL? {
		let environment = ProcessInfo.processInfo.environment
		if let path = environment["GOMODCACHE"], !path.isEmpty {
			return URL(fileURLWithPath: path)
		}
		if let path = environment["GOPATH"], !path.isEmpty {
			return URL(fileURLWithPath: path).appendingPathComponent("pkg/mod")
		}
		return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go/pkg/mod")
	}

	/// The module cache's escaping: an upper-case letter becomes `!` and its
	/// lower-case self.
	///
	/// `github.com/IBM/sarama` is on disk as `github.com/!i!b!m/sarama`. Case
	/// alone cannot name a directory on a case-insensitive file system, and two
	/// modules differing only in case would otherwise collide — so the toolchain
	/// escapes rather than lower-cases, and anything looking for the sources has
	/// to escape the same way. Found the hard way: without this, every module
	/// with a capital in its path had no sources and the rows looked like
	/// packages nobody had fetched.
	static func escapeGoPath(_ path: String) -> String {
		var escaped = ""
		for character in path {
			if character.isUppercase {
				escaped.append("!")
				escaped.append(contentsOf: character.lowercased())
			} else {
				escaped.append(character)
			}
		}
		return escaped
	}
}

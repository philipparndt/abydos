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
	/// Swift package, a module path for a Go module, the registry or the git URL
	/// for a Cargo crate.
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
	/// The one file this dependency resolved to, when it resolved to a file
	/// rather than to sources.
	///
	/// The JVM is why this exists. Maven and Gradle both fetch a **jar**, and a
	/// jar is not a directory — `localPath` has to stay nil for one, because a
	/// package row *is* a directory and pointing it at the folder the jar sits in
	/// draws a package whose files are a jar and a checksum. But `not fetched` is
	/// false about a dependency whose jar is right there on disk, so the tooltip
	/// names the artefact instead, and the row stays unexpandable.
	public let artefact: URL?

	public init(
		name: String, version: String?, origin: String, localPath: URL?,
		otherPaths: [URL] = [], artefact: URL? = nil
	) {
		self.name = name
		self.version = version
		self.origin = origin
		self.localPath = localPath
		self.otherPaths = otherPaths
		self.artefact = artefact
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
		case .swiftPackage, .goModule, .cargo: return nil
		case .maven, .gradle: return nil
		case .npm: return 514
		case .bazel, .conan: return 516
		}
	}
}

/// What one root's dependencies came out as.
///
/// Four answers and not two, because "nothing to show" has two quite different
/// causes and a row that conflated them would be the failure this whole item is
/// about: a kind nothing here can read, and a project of a kind that *is* read
/// which has resolved nothing yet.
public struct DependencySet: Equatable, Sendable {
	public enum Contents: Equatable, Sendable {
		/// Read, and this is what it says. Possibly empty — a `go.mod` with no
		/// `require` is a module with no dependencies, and saying so is right.
		case packages([ExternalDependency])
		/// Read, real, and known to be **incomplete** — with the caveat that says
		/// in what way, in the words of the tool that holds the rest.
		///
		/// The fourth answer, added by 0515, and the JVM is why. Every kind read
		/// before it resolves whole from disk: a `Package.resolved`, a `go.mod`, a
		/// `Cargo.lock` are all the finished graph. A `pom.xml` is the *input* to
		/// resolution — no transitives, and a version that may be managed by a BOM
		/// in `~/.m2` — and a Gradle build with no lock file is the same. That
		/// list is not `.unresolved`: the rows in it are true, and dropping them
		/// would hide dependencies a project really has. Nor is it `.packages`,
		/// which reads as the whole of what a project depends on. So it is its own
		/// answer, drawn as the rows *and* a note that says what is missing.
		case partial([ExternalDependency], caveat: String)
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
		switch contents {
		case let .packages(packages): return packages
		case let .partial(packages, _): return packages
		case .notRead, .unresolved: return []
		}
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
	public static func read(root: URL, kind: DependencyKind) -> DependencySet {
		let contents: DependencySet.Contents
		switch kind {
		case .swiftPackage: contents = readSwiftPackages(at: root)
		case .goModule: contents = readGoModules(at: root)
		case .cargo: contents = readCargoPackages(at: root)
		case .maven: contents = readMavenPackages(at: root)
		case .gradle: contents = readGradlePackages(at: root)
		case .npm, .bazel, .conan: contents = .notRead
		}
		return DependencySet(root: root, kind: kind, contents: contents)
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
		return byName(packages)
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
		return byName(packages)
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

	// MARK: - Cargo

	/// One `[[package]]` out of `Cargo.lock`, as the file writes it.
	struct CargoLockPackage: Equatable {
		let name: String
		let version: String?
		/// Absent for a package that is not fetched from anywhere: a workspace
		/// member — the project's own crate is in its own lock file — or a `path`
		/// dependency, which is a directory the tree already shows.
		let source: String?
	}

	/// `Cargo.lock`, which is the resolved graph and is TOML.
	///
	/// The lock file rather than `Cargo.toml`, for the same reason
	/// `Package.resolved` is read rather than `Package.swift`: the manifest says
	/// `serde = "1"` and the lock says `1.0.229`, and the row has to name the
	/// version on disk. `cargo metadata` would answer both at once and is a
	/// subprocess — see the rule on this type; it is `swift package
	/// dump-package` wearing a different name, and it writes a lock file as a
	/// side effect of being asked.
	///
	/// A lock file whose every package is a workspace member or a `path`
	/// dependency reads as `.packages([])` — "no dependencies" — which is right:
	/// those are directories inside the project and the tree already has rows
	/// for them. An *external* section listing them would show the project's own
	/// source twice.
	static func readCargoPackages(at root: URL) -> DependencySet.Contents {
		let lock = root.appendingPathComponent("Cargo.lock")
		guard let text = try? String(contentsOf: lock, encoding: .utf8) else {
			if let workspace = cargoWorkspaceAbove(root) {
				return .unresolved("resolved in the workspace at \(workspace.lastPathComponent)")
			}
			// In cargo's own words: `cargo fetch` writes the lock file and fills
			// the registry cache, which is both halves of what this row needs.
			return .unresolved("no Cargo.lock — run cargo fetch")
		}

		let registries = cargoRegistryDirectories()
		let packages = parseCargoLock(text).compactMap { entry -> ExternalDependency? in
			guard let source = entry.source else { return nil }
			return ExternalDependency(
				name: entry.name,
				version: entry.version,
				origin: cargoOrigin(of: source),
				localPath: cargoSources(
					name: entry.name, version: entry.version, source: source, registries: registries
				)
			)
		}
		return byName(packages)
	}

	/// The `[[package]]` tables of a lock file, line by line.
	///
	/// **Thirty lines instead of a TOML dependency**, which is the same call
	/// `SwiftPackage` made about `Package.swift` and `readGoModules` about
	/// `go.mod`. `Cargo.lock` is generated, never hand-written, and is a flat
	/// sequence of tables of quoted strings — no nesting, no dates, no
	/// multi-line strings, nothing a parser would earn its keep on. `project.md`
	/// asks for an argument before a dependency is added and "one file, four
	/// keys" is not one.
	///
	/// Only the four keys are taken, and only where the key is a bare word: the
	/// `dependencies = [ … ]` array under most packages holds bare strings, and
	/// in the version 1 and 2 layouts those strings are whole package ids with
	/// `git+…?branch=main#sha` inside them. A parser splitting every line on its
	/// first `=` would read that fragment as a table key.
	static func parseCargoLock(_ text: String) -> [CargoLockPackage] {
		var packages: [CargoLockPackage] = []
		var name: String?
		var version: String?
		var source: String?
		var inPackage = false

		func finish() {
			if inPackage, let name, !name.isEmpty {
				packages.append(CargoLockPackage(name: name, version: version, source: source))
			}
			name = nil; version = nil; source = nil
		}

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = rawLine.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("[") {
				// Any other table ends this one: `[metadata]` in the version 1
				// layout, and `[[patch.unused]]` at the end of many real files.
				finish()
				inPackage = line == "[[package]]"
				continue
			}
			guard inPackage, let equals = line.firstIndex(of: "=") else { continue }
			let key = line[..<equals].trimmingCharacters(in: .whitespaces)
			let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
			guard value.hasPrefix("\""), value.count >= 2, value.hasSuffix("\"") else { continue }
			let unquoted = String(value.dropFirst().dropLast())
			switch key {
			case "name": name = unquoted
			case "version": version = unquoted
			case "source": source = unquoted
			default: continue
			}
		}
		finish()
		return packages
	}

	/// The workspace that resolves for this crate, if it is a member of one.
	///
	/// **Found in the app, on the first Rust project it was pointed at.** A
	/// workspace has one `Cargo.lock`, at its root, and none beside its members
	/// — and a Rust repository of any size is a workspace, so every member crate
	/// is a subproject the section has a row for. Telling somebody to run `cargo
	/// fetch` in a member is telling them to run a command that will write
	/// nothing there: the resolving already happened, one directory up. So the
	/// row says where instead.
	///
	/// The list itself is not borrowed from the workspace. It is the *whole*
	/// workspace's resolved set, not this member's, and copying it under every
	/// member would print two hundred rows five times over and claim each crate
	/// depends on all of it.
	///
	/// Walked up rather than asked of cargo, and bounded: a member two or three
	/// directories down (`crates/foo`) is the usual layout and the intervening
	/// directories have no manifest of their own, so there is nothing nearer to
	/// stop at.
	static func cargoWorkspaceAbove(_ root: URL) -> URL? {
		let manager = FileManager.default
		var directory = root.deletingLastPathComponent()
		for _ in 0..<6 {
			guard directory.path != "/", directory.path != root.path else { return nil }
			let lock = directory.appendingPathComponent("Cargo.lock")
			let manifest = directory.appendingPathComponent("Cargo.toml")
			if manager.fileExists(atPath: lock.path), manager.fileExists(atPath: manifest.path) {
				return directory
			}
			directory = directory.deletingLastPathComponent()
		}
		return nil
	}

	/// Where a crate came from, from the `source` the lock file writes.
	///
	///     registry+https://github.com/rust-lang/crates.io-index   → crates.io
	///     sparse+https://index.crates.io/                         → crates.io
	///     git+https://github.com/dtolnay/anyhow#bf3ed914…         → the URL, whole
	///
	/// The default registry is named `crates.io` rather than by its index URL,
	/// which is the one place this departs from "as the lock file writes it".
	/// `github.com/rust-lang` — which is what `shortOrigin` makes of the index
	/// URL — reads as *the crate came from that repository*, and it would say it
	/// on every row of a list of two hundred, which is a column of noise saying
	/// nothing. Another registry keeps its URL, because there the host is the
	/// answer.
	///
	/// A git source keeps its query and fragment: `?branch=main` and the commit
	/// after `#` are what say *which* one of it, `shortOrigin` cuts back to
	/// `github.com/dtolnay` for the row, and the tooltip shows the whole of it.
	static func cargoOrigin(of source: String) -> String {
		guard let plus = source.firstIndex(of: "+") else { return source }
		let kind = String(source[..<plus])
		let location = String(source[source.index(after: plus)...])
		switch kind {
		case "registry", "sparse":
			return isCratesIoIndex(location) ? "crates.io" : location
		default:
			return location
		}
	}

	/// The two spellings of the one registry every Rust project uses: the git
	/// index it had until 1.68, and the sparse index it has had since.
	static func isCratesIoIndex(_ location: String) -> Bool {
		location.contains("rust-lang/crates.io-index") || location.contains("index.crates.io")
	}

	/// `$CARGO_HOME`, or `~/.cargo`.
	///
	/// The variable first, because a machine that has moved it has moved all of
	/// it, and then the documented default. No `cargo --version` and no
	/// `cargo config get`: a subprocess per project on open, for an answer that
	/// is wrong on no machine this is likely to meet, and a crate whose
	/// directory is not found simply has no sources to browse — a state the row
	/// already knows how to show.
	static func cargoHome() -> URL {
		let environment = ProcessInfo.processInfo.environment
		if let path = environment["CARGO_HOME"], !path.isEmpty {
			return URL(fileURLWithPath: path)
		}
		return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo")
	}

	/// The unpacked registry caches, **listed rather than computed**.
	///
	/// `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f`: the last part is
	/// a hash of the registry URL, made by a function inside cargo that is not
	/// specified anywhere and has changed at least once — it was
	/// `github.com-1ecc6299db9ec823` for the git index. Nothing outside cargo
	/// can compute it, so this reads the directory and takes whatever is in it.
	/// A machine with a vendored registry as well as crates.io has two, both are
	/// tried, and the order is fixed so that two reads of the same project agree.
	static func cargoRegistryDirectories() -> [URL] {
		let source = cargoHome().appendingPathComponent("registry/src")
		let entries = (try? FileManager.default.contentsOfDirectory(
			at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []
		return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
	}

	/// The crate's own sources on this machine, or nil when nothing fetched them.
	///
	/// Two caches with two layouts, and neither is inside the project — the same
	/// shape as a Go module and not at all the shape of a Swift package:
	///
	///     registry:  <cargo home>/registry/src/<index-hash>/<name>-<version>
	///     git:       <cargo home>/git/checkouts/<repo>-<hash>/<short revision>
	static func cargoSources(
		name: String, version: String?, source: String, registries: [URL]
	) -> URL? {
		let manager = FileManager.default
		guard let plus = source.firstIndex(of: "+") else { return nil }
		let kind = String(source[..<plus])
		let location = String(source[source.index(after: plus)...])

		guard kind == "git" else {
			guard let version else { return nil }
			let directory = "\(name)-\(version)"
			return registries
				.map { $0.appendingPathComponent(directory) }
				.first { manager.fileExists(atPath: $0.path) }
		}

		// `git+https://github.com/dtolnay/anyhow?branch=main#bf3ed914…`: the
		// checkout is named after the *repository* and the directory inside it
		// after the revision, abbreviated by cargo to a length it does not
		// promise — so the revision is matched by prefix rather than cut to
		// seven characters and compared.
		let revision = location.firstIndex(of: "#").map { String(location[location.index(after: $0)...]) }
		var repository = location
		if let hash = repository.firstIndex(of: "#") { repository = String(repository[..<hash]) }
		if let query = repository.firstIndex(of: "?") { repository = String(repository[..<query]) }
		guard let repositoryName = repositoryName(from: repository), let revision else { return nil }

		let checkouts = cargoHome().appendingPathComponent("git/checkouts")
		let candidates = ((try? manager.contentsOfDirectory(
			at: checkouts, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? [])
			.filter { $0.lastPathComponent.hasPrefix(repositoryName + "-") }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }

		for checkout in candidates {
			let revisions = ((try? manager.contentsOfDirectory(
				at: checkout, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
			)) ?? [])
			guard let worktree = revisions.first(where: {
				revision.hasPrefix($0.lastPathComponent) || $0.lastPathComponent.hasPrefix(revision)
			}) else { continue }
			// One repository can hold several crates, and the lock file does not
			// say which directory this one is in. Its own name is the convention
			// and is worth a `stat`; the checkout root is the honest fallback,
			// since it is where the crate is when the repository is one crate.
			let inside = worktree.appendingPathComponent(name)
			return manager.fileExists(atPath: inside.path) ? inside : worktree
		}
		return nil
	}

	// MARK: - Maven and Gradle: what a partial list says about itself

	/// `byName`, with the caveat that says what this list is missing.
	///
	/// The JVM's two kinds are the only ones that need it, and they need it for
	/// the same reason: what is on disk is the *input* to resolution rather than
	/// its result. Nil means the list is whole — a Gradle build with a
	/// `gradle.lockfile` is as complete as a `Cargo.lock`, and putting a caveat
	/// on it would be an apology for an answer that has nothing wrong with it.
	static func byName(_ packages: [ExternalDependency], caveat: String?) -> DependencySet.Contents {
		let sorted = byName(packages)
		guard let caveat, case let .packages(list) = sorted else { return sorted }
		return .partial(list, caveat: caveat)
	}

	/// The caveat itself, built from what is actually missing rather than fixed.
	///
	/// A sentence and not a list, because it is drawn as one row under the
	/// packages and read as prose. "the transitive ones" is always in it — no
	/// `pom.xml` and no `dependencies { }` block has ever held them — and the
	/// rest is counted from this project: the versions a BOM or a parent holds,
	/// and a parent POM the checkout does not contain.
	static func jvmCaveat(tool: String, missingVersions: Int, alsoMissing: [String] = []) -> String {
		var missing = ["the transitive ones"]
		switch missingVersions {
		case 0: break
		case 1: missing.append("one of these versions")
		default: missing.append("\(missingVersions) of these versions")
		}
		missing += alsoMissing
		let last = missing.removeLast()
		let listed = missing.isEmpty ? last : missing.joined(separator: ", ") + " and " + last
		return "direct dependencies only — \(tool) resolves \(listed)"
	}

	/// The artefact a JVM coordinate resolved to, **by listing the directory it
	/// would be in** rather than by predicting the file inside it.
	///
	/// 0513's lesson in its JVM spelling. The directory is computable in both
	/// caches once the sha1 level is walked, but the file in it is not: the
	/// packaging may be `war` or `aar`, and `-sources.jar` and `-javadoc.jar` sit
	/// beside the artefact when somebody asked for them. So the plain
	/// `<artifact>-<version>.jar` is preferred and anything else with the same
	/// stem is the fallback — and the classified jars are excluded by having
	/// something other than a dot after that stem.
	static func jvmArtefact(named stem: String, in directory: URL) -> URL? {
		let entries = (try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []
		if let jar = entries.first(where: { $0.lastPathComponent == stem + ".jar" }) { return jar }
		return entries
			.filter {
				$0.lastPathComponent.hasPrefix(stem + ".")
					&& ["jar", "war", "aar", "ear"].contains($0.pathExtension)
			}
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
			.first
	}

	// MARK: - Maven

	/// One `<dependency>` as a POM writes it, before anything has resolved it.
	struct PomDependency: Equatable {
		let group: String
		let artifact: String
		/// Nil when the POM leaves the version to `<dependencyManagement>` — which
		/// is commonly a BOM imported from `~/.m2` and not in the project at all.
		let version: String?

		var coordinate: String { group + ":" + artifact }
	}

	/// A `pom.xml`, read for the four things a dependency list needs from it.
	struct PomFile: Equatable {
		let groupId: String?
		let artifactId: String?
		let version: String?
		let packaging: String
		let modules: [String]
		let properties: [String: String]
		/// Written as the file writes them: `${jackson.version}` is still a
		/// `${jackson.version}` here, because it may be resolved by a property
		/// from a POM further up.
		let dependencies: [PomDependency]
		/// `<dependencyManagement>`, keyed `group:artifact`.
		let managed: [String: String]
		/// Where the parent is, when there is one: the path as `<relativePath>`
		/// gives it, or `../pom.xml` when it says nothing. Nil when there is no
		/// parent, or when `<relativePath/>` is written empty — which means "not
		/// beside me, look in the repository" and is *not* the same as absent.
		let parentPath: String?
		/// A `<parent>` this project does not hold, which is a reason the list
		/// below may be short.
		let hasParent: Bool
	}

	/// **`pom.xml` is the input to resolution, not its result.**
	///
	/// There is no lock file anywhere in a Maven project — not in the checkout,
	/// not in `target/`. `mvn dependency:list` is the only thing that answers
	/// properly and it is a subprocess and a JVM, which is the rule on this type
	/// and not a preference: it costs seconds, and this runs when a project opens
	/// and again on every write to a `pom.xml`.
	///
	/// So this reads what the POM says and is honest about the rest. Three things
	/// are genuinely missing and the caveat names all three:
	///
	/// - **transitives**, which no POM has ever held;
	/// - a **version** that `<dependencyManagement>` supplies from an imported
	///   BOM, which lives in `~/.m2` rather than here;
	/// - the **parent chain** beyond this checkout, whose `<properties>` and
	///   `<dependencyManagement>` are what `${jackson.version}` needs.
	///
	/// What it does resolve it resolves properly: properties merged down the
	/// parent chain *inside the project*, `<dependencyManagement>` from the same
	/// chain, and the parent's own `<dependencies>`, which a child inherits.
	static func readMavenPackages(at root: URL, repository: URL? = nil) -> DependencySet.Contents {
		let manager = FileManager.default
		let path = root.appendingPathComponent("pom.xml")
		guard let first = readPom(at: path) else {
			return .unresolved("pom.xml could not be read")
		}

		// The chain, nearest first, and only as far as the checkout goes. A
		// `<relativePath>` pointing outside is followed — a sibling `../parent`
		// is a normal layout — but a parent that is not on disk stops it, and
		// that is a thing the caveat has to say.
		var chain = [first]
		var directory = path.deletingLastPathComponent()
		var incomplete = first.hasParent && first.parentPath == nil
		while let relative = chain[chain.count - 1].parentPath, chain.count < 8 {
			var candidate = directory.appendingPathComponent(relative).standardizedFileURL
			var isDirectory: ObjCBool = false
			if manager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
				candidate = candidate.appendingPathComponent("pom.xml")
			}
			guard let parent = readPom(at: candidate) else { incomplete = true; break }
			chain.append(parent)
			directory = candidate.deletingLastPathComponent()
			if parent.hasParent, parent.parentPath == nil { incomplete = true }
		}

		var properties: [String: String] = [:]
		// Nearest wins, so the chain is merged from the far end inwards.
		for pom in chain.reversed() { properties.merge(pom.properties) { _, new in new } }
		// The three a POM may write about itself. Maven has more of these;
		// these are the ones that turn up in a `<version>`.
		properties["project.groupId"] = first.groupId ?? properties["project.groupId"]
		properties["project.artifactId"] = first.artifactId ?? properties["project.artifactId"]
		properties["project.version"] = first.version ?? properties["project.version"]

		var managed: [String: String] = [:]
		for pom in chain.reversed() { managed.merge(pom.managed) { _, new in new } }

		// A parent's own `<dependencies>` are inherited by the child, so the whole
		// chain contributes — nearest first, and a coordinate is taken once.
		var seen = Set<String>()
		var declared: [PomDependency] = []
		for pom in chain {
			for dependency in pom.dependencies where seen.insert(dependency.coordinate).inserted {
				declared.append(dependency)
			}
		}

		if declared.isEmpty, first.packaging == "pom", !first.modules.isEmpty {
			// The Maven spelling of 0513's workspace member, the other way up: an
			// aggregator declares nothing itself and its modules are subprojects
			// with rows of their own. "no dependencies" would be true of the POM
			// and false about the build.
			return .unresolved("an aggregator POM — its modules have the dependencies")
		}

		let repository = repository ?? mavenLocalRepository()
		var missingVersions = 0
		let packages = declared.map { dependency -> ExternalDependency in
			let written = dependency.version ?? managed[dependency.coordinate]
			let version = written.flatMap { resolveMavenProperties($0, with: properties) }
			if version == nil { missingVersions += 1 }
			let group = resolveMavenProperties(dependency.group, with: properties) ?? dependency.group
			return ExternalDependency(
				name: dependency.artifact,
				version: version,
				// The groupId is where it came from, the way a module path is for
				// Go: the POM does not say which repository served it, and the
				// group is what tells one row from another.
				origin: group,
				// Nil, and deliberately. What is on disk is a jar.
				localPath: nil,
				artefact: mavenArtefact(
					group: group, artifact: dependency.artifact,
					version: version, repository: repository
				)
			)
		}

		let caveat = jvmCaveat(
			tool: "Maven", missingVersions: missingVersions,
			alsoMissing: incomplete ? ["a parent POM this checkout does not hold"] : []
		)
		return byName(packages, caveat: packages.isEmpty && !incomplete ? nil : caveat)
	}

	/// The four parts of a POM this needs, read with `XMLDocument`.
	///
	/// The same call `MavenProject` made and for the same reason: XML has a
	/// parser in the standard library, and half-parsing it with string matching
	/// is how a commented-out `<dependency>` becomes a row.
	static func readPom(at url: URL) -> PomFile? {
		guard let data = try? Data(contentsOf: url),
		      let document = try? XMLDocument(data: data),
		      let root = document.rootElement(),
		      root.localName == "project"
		else { return nil }

		var properties: [String: String] = [:]
		for element in root.child("properties")?.elements() ?? [] {
			guard let name = element.localName else { continue }
			properties[name] = element.stringValue?
				.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		}

		func dependencies(of element: XMLElement?) -> [PomDependency] {
			(element?.children(named: "dependency") ?? []).compactMap { entry in
				guard let group = entry.child("groupId")?.text,
				      let artifact = entry.child("artifactId")?.text
				else { return nil }
				return PomDependency(
					group: group, artifact: artifact, version: entry.child("version")?.text
				)
			}
		}

		let parent = root.child("parent")
		let relative = parent?.child("relativePath")
		// `<relativePath/>` written empty is a POM saying "my parent is not beside
		// me" — the one shape that must not be read as absent, or the chain
		// climbs out of the project into whatever `pom.xml` sits one level up.
		let parentPath: String? = parent == nil
			? nil
			: (relative == nil ? "../pom.xml" : relative?.text)

		return PomFile(
			groupId: root.child("groupId")?.text ?? parent?.child("groupId")?.text,
			artifactId: root.child("artifactId")?.text,
			version: root.child("version")?.text ?? parent?.child("version")?.text,
			packaging: root.child("packaging")?.text ?? "jar",
			modules: (root.child("modules")?.children(named: "module") ?? []).compactMap(\.text),
			properties: properties,
			dependencies: dependencies(of: root.child("dependencies")),
			managed: Dictionary(
				dependencies(of: root.child("dependencyManagement")?.child("dependencies"))
					.compactMap { entry in entry.version.map { (entry.coordinate, $0) } },
				uniquingKeysWith: { first, _ in first }
			),
			parentPath: parentPath,
			hasParent: parent != nil
		)
	}

	/// `${jackson.version}` against the merged properties, or nil.
	///
	/// Nil rather than the literal: a row reading `${jackson.version}` where a
	/// version belongs is worse than a row with no version, which is a state the
	/// section already draws and the caveat already counts. Wound round a few
	/// times because a property may name another.
	static func resolveMavenProperties(_ text: String, with properties: [String: String]) -> String? {
		var value = text
		for _ in 0..<8 {
			guard let open = value.range(of: "${"),
			      let close = value.range(of: "}", range: open.upperBound..<value.endIndex)
			else { return value }
			guard let replacement = properties[String(value[open.upperBound..<close.lowerBound])] else {
				return nil
			}
			value.replaceSubrange(open.lowerBound..<close.upperBound, with: replacement)
		}
		return nil
	}

	/// Where Maven keeps what it has downloaded.
	///
	/// `~/.m2/repository`, or whatever `<localRepository>` in `~/.m2/settings.xml`
	/// says. There is **no environment variable** for it — `M2_HOME` is where
	/// Maven is installed, not where it puts things — and `mvn help:evaluate` is
	/// the subprocess this type does not run. So the default and the one file
	/// that overrides it, and a dependency whose jar is not found simply has none
	/// to name.
	///
	/// The home directory is a parameter because it is the only way to test this.
	/// With no environment variable to move, the alternative is a test that reads
	/// whatever machine it runs on — and 0513 found the other half of that
	/// argument in `CARGO_HOME`, which is process-wide and therefore two parallel
	/// tests reading each other's cache.
	static func mavenLocalRepository(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> URL {
		let settings = home.appendingPathComponent(".m2/settings.xml")
		if let data = try? Data(contentsOf: settings),
		   let document = try? XMLDocument(data: data),
		   let path = document.rootElement()?.child("localRepository")?.text
		{
			// `${user.home}` is the placeholder Maven's own default settings file
			// ships with, so it is the one worth expanding.
			return URL(fileURLWithPath: path
				.replacingOccurrences(of: "${user.home}", with: home.path)
				.replacingOccurrences(of: "${env.HOME}", with: home.path))
		}
		return home.appendingPathComponent(".m2/repository")
	}

	/// `~/.m2/repository/com/fasterxml/jackson/core/jackson-databind/2.17.1/`.
	///
	/// The one part of the JVM that *is* computable: Maven's layout is specified,
	/// the group is the path with its dots as slashes, and there is no hash
	/// anywhere in it. The file inside is still listed rather than guessed.
	static func mavenArtefact(
		group: String, artifact: String, version: String?, repository: URL
	) -> URL? {
		guard let version, !version.isEmpty else { return nil }
		let directory = repository
			.appendingPathComponent(group.replacingOccurrences(of: ".", with: "/"))
			.appendingPathComponent(artifact)
			.appendingPathComponent(version)
		return jvmArtefact(named: "\(artifact)-\(version)", in: directory)
	}

	// MARK: - Gradle

	/// **Gradle is the better case, not the worse one.**
	///
	/// The item that filed this expected Gradle to be the kind where the rule
	/// against subprocesses finally bent — `build.gradle` is a program and
	/// `gradle dependencies` needs a daemon. It is the opposite. A build that has
	/// opted into `dependencyLocking` writes `gradle.lockfile`, and that file
	/// **is** the resolved graph, transitives included: as complete as a
	/// `Cargo.lock`, and read with no caveat at all.
	///
	/// Without one, `dependencies { }` is read as text, and that list is direct
	/// dependencies only — the same partial answer Maven gives, said the same
	/// way. The trap is that the *same block* appears inside `buildscript { }`,
	/// where it is the plugin classpath and not the project's dependencies at
	/// all, so the block only counts at brace depth 0.
	static func readGradlePackages(at root: URL, gradleHome: URL? = nil) -> DependencySet.Contents {
		let home = gradleHome ?? gradleUserHome()
		if let locked = readGradleLockfile(at: root), !locked.isEmpty {
			return byName(locked.map { gradlePackage($0, home: home) }, caveat: nil)
		}

		guard let text = gradleBuildText(at: root) else {
			if GradleBuild.settingsFile(in: root) != nil {
				// A settings file and no build file: the root of a multi-project
				// build, whose projects are subprojects with rows of their own.
				return .unresolved("a settings file only — its projects have the dependencies")
			}
			return .unresolved("no build.gradle — nothing to read")
		}

		let catalog = readGradleVersionCatalog(near: root)
		let accessors = gradleCatalogAccessors(in: root)
		var missingVersions = 0
		let packages = gradleDeclaredDependencies(
			in: text, catalog: catalog, accessors: accessors
		).map { coordinate -> ExternalDependency in
			if coordinate.version == nil { missingVersions += 1 }
			return gradlePackage(coordinate, home: home)
		}
		guard !packages.isEmpty else { return .packages([]) }
		return byName(packages, caveat: jvmCaveat(tool: "Gradle", missingVersions: missingVersions))
	}

	/// One `group:name:version` as Gradle writes it, wherever it was written.
	struct GradleCoordinate: Equatable {
		let group: String
		let name: String
		/// Nil when the build interpolates it — `"g:a:$version"` — or leaves it to
		/// a platform, which is a version this cannot know rather than one it can
		/// print.
		let version: String?
	}

	static func gradlePackage(_ coordinate: GradleCoordinate, home: URL) -> ExternalDependency {
		ExternalDependency(
			name: coordinate.name,
			version: coordinate.version,
			origin: coordinate.group,
			// A jar, like Maven's. Same reason, same answer.
			localPath: nil,
			artefact: gradleArtefact(coordinate, home: home)
		)
	}

	/// `gradle.lockfile`, which is the resolved graph and needs no caveat.
	///
	/// Both layouts: Gradle 6 and later write one file at the project root, one
	/// `group:name:version=configuration,configuration` per line; Gradle 5 wrote
	/// one file per configuration under `gradle/dependency-locks`. `empty=…`
	/// names configurations that resolved to nothing and is not a coordinate.
	///
	/// `buildscript-gradle.lockfile` is deliberately not read: it is the plugin
	/// classpath, which is what builds the project rather than what the project
	/// depends on.
	static func readGradleLockfile(at root: URL) -> [GradleCoordinate]? {
		var texts: [String] = []
		if let text = try? String(
			contentsOf: root.appendingPathComponent("gradle.lockfile"), encoding: .utf8
		) {
			texts.append(text)
		}
		let locks = root.appendingPathComponent("gradle/dependency-locks")
		for file in ((try? FileManager.default.contentsOfDirectory(
			at: locks, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
		where file.pathExtension == "lockfile" {
			if let text = try? String(contentsOf: file, encoding: .utf8) { texts.append(text) }
		}
		guard !texts.isEmpty else { return nil }

		var seen = Set<String>()
		var found: [GradleCoordinate] = []
		for text in texts {
			for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
				var line = rawLine.trimmingCharacters(in: .whitespaces)
				guard !line.isEmpty, !line.hasPrefix("#") else { continue }
				if let equals = line.firstIndex(of: "=") { line = String(line[..<equals]) }
				let parts = line.split(separator: ":", omittingEmptySubsequences: false)
				guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { continue }
				guard seen.insert(line).inserted else { continue }
				found.append(GradleCoordinate(
					group: String(parts[0]), name: String(parts[1]), version: String(parts[2])
				))
			}
		}
		return found
	}

	static func gradleBuildText(at root: URL) -> String? {
		for name in ["build.gradle.kts", "build.gradle"] {
			if let text = try? String(
				contentsOf: root.appendingPathComponent(name), encoding: .utf8
			) { return text }
		}
		return nil
	}

	/// Every coordinate a `dependencies { }` block declares, at brace depth 0.
	///
	/// **The depth is the whole of the correctness here.** `buildscript { }` and
	/// `subprojects { }` both contain a `dependencies { }` of their own, and the
	/// first of them is the plugin classpath — Spring Boot's own plugin would
	/// otherwise appear as something the project depends on.
	///
	/// The forms are the ones builds are written in: a quoted `g:a:v` with or
	/// without parentheses, `platform(…)` and `enforcedPlatform(…)` around one,
	/// the `group:`/`name:`/`version:` map, and `libs.something` out of the
	/// version catalog. `project(":common")` is dropped the way 0513 drops a
	/// Cargo `path` dependency: it is a directory the tree already shows.
	static func gradleDeclaredDependencies(
		in text: String, catalog: [String: GradleCoordinate], accessors: [String]
	) -> [GradleCoordinate] {
		var found: [GradleCoordinate] = []
		var seen = Set<String>()
		var depth = 0
		var blockDepth: Int?

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			var line = String(rawLine)
			if let comment = line.range(of: "//") { line = String(line[..<comment.lowerBound]) }
			line = line.trimmingCharacters(in: .whitespaces)

			let opensBlock = blockDepth == nil && depth == 0 && isGradleDependenciesBlock(line)
			if blockDepth != nil, let coordinate = gradleCoordinate(
				in: line, catalog: catalog, accessors: accessors
			), seen.insert(coordinate.group + ":" + coordinate.name).inserted {
				found.append(coordinate)
			}

			depth += gradleBraceBalance(line)
			if opensBlock {
				blockDepth = depth - 1
			} else if let open = blockDepth, depth <= open {
				blockDepth = nil
			}
		}
		return found
	}

	/// `dependencies {`, and not `dependencies` inside anything else on the line.
	static func isGradleDependenciesBlock(_ line: String) -> Bool {
		guard line.hasPrefix("dependencies") else { return false }
		let rest = line.dropFirst("dependencies".count).trimmingCharacters(in: .whitespaces)
		return rest.hasPrefix("{")
	}

	/// Braces on a line, ignoring the ones inside quotes — `"${a}"` would
	/// otherwise open a block that never closes.
	static func gradleBraceBalance(_ line: String) -> Int {
		var balance = 0
		var quote: Character?
		var previous: Character?
		for character in line {
			if let active = quote {
				if character == active, previous != "\\" { quote = nil }
			} else if character == "\"" || character == "'" {
				quote = character
			} else if character == "{" {
				balance += 1
			} else if character == "}" {
				balance -= 1
			}
			previous = character
		}
		return balance
	}

	/// One line of a `dependencies { }` block, or nil when it declares nothing
	/// external.
	static func gradleCoordinate(
		in line: String, catalog: [String: GradleCoordinate], accessors: [String]
	) -> GradleCoordinate? {
		// A configuration name comes first in every form: `implementation`,
		// `testRuntimeOnly`, `annotationProcessor`, `ksp`, anything a plugin adds.
		let name = line.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
		guard !name.isEmpty else { return nil }
		let rest = line.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
		guard let opener = rest.first, opener == "(" || opener == "'" || opener == "\"" || opener.isLetter
		else { return nil }

		// A project, a file or a jar tree is not something from outside.
		for local in ["project(", "project (", "files(", "fileTree(", "gradleApi(", "localGroovy("]
		where rest.contains(local) {
			return nil
		}

		if let alias = gradleCatalogAlias(in: rest, accessors: accessors) {
			return catalog[alias]
		}

		// `implementation group: 'g', name: 'a', version: 'v'`
		if rest.contains("group:"), rest.contains("name:") {
			guard let group = GradleBuild.quoted(after: "group:", in: rest),
			      let artifact = GradleBuild.quoted(after: "name:", in: rest)
			else { return nil }
			return GradleCoordinate(
				group: group, name: artifact,
				version: GradleBuild.quoted(after: "version:", in: rest)
					.flatMap { $0.contains("$") ? nil : $0 }
			)
		}

		guard let notation = GradleBuild.firstQuoted(in: rest) else { return nil }
		let parts = notation.split(separator: ":", omittingEmptySubsequences: false)
		guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
		// `"org.slf4j:slf4j-api:$slf4jVersion"` interpolates, and the literal is
		// not a version anybody has on disk.
		let version = parts.count > 2 && !parts[2].isEmpty && !parts[2].contains("$")
			? String(parts[2])
			: nil
		return GradleCoordinate(group: String(parts[0]), name: String(parts[1]), version: version)
	}

	/// `libs.commons.lang3` out of `implementation(libs.commons.lang3)`.
	static func gradleCatalogAlias(in text: String, accessors: [String]) -> String? {
		for accessor in accessors {
			// `libs` has to start the reference or follow a bracket: `sublibs.x`
			// is somebody else's identifier, not this catalog's.
			let opening = text.hasPrefix(accessor + ".")
				? text.range(of: accessor + ".")
				: ["(" + accessor + ".", " " + accessor + "."].lazy
					.compactMap { text.range(of: $0) }
					.first
					.map { text.index(after: $0.lowerBound)..<$0.upperBound }
			guard let opening else { continue }
			let alias = text[opening.upperBound...].prefix {
				$0.isLetter || $0.isNumber || $0 == "." || $0 == "_"
			}
			guard !alias.isEmpty else { continue }
			return normalisedCatalogAlias(String(alias))
		}
		return nil
	}

	/// `commons-lang3`, `commons_lang3` and `commons.lang3` are one alias.
	///
	/// Gradle generates the accessor by turning every separator into a dot, so
	/// the two sides only meet if both are normalised the same way.
	static func normalisedCatalogAlias(_ alias: String) -> String {
		alias.replacingOccurrences(of: "-", with: ".").replacingOccurrences(of: "_", with: ".")
	}

	/// `gradle/libs.versions.toml`, which is where a modern build keeps the
	/// coordinates its build file only refers to.
	///
	/// Worth reading because without it such a build yields **no rows at all** —
	/// every line in `dependencies { }` is `libs.something` and resolves to
	/// nothing. Looked for beside the project and then upwards, because the
	/// catalog belongs to the build root and a module is a directory below it.
	static func readGradleVersionCatalog(near root: URL) -> [String: GradleCoordinate] {
		var directory = root
		for _ in 0..<4 {
			let file = directory.appendingPathComponent("gradle/libs.versions.toml")
			if let text = try? String(contentsOf: file, encoding: .utf8) {
				return parseGradleVersionCatalog(text)
			}
			let parent = directory.deletingLastPathComponent()
			guard parent.path != directory.path else { break }
			directory = parent
		}
		return [:]
	}

	/// The catalog's two tables, line by line — the same call 0513 made about
	/// `Cargo.lock`, and for the same reason: two tables of quoted strings is not
	/// an argument for a TOML dependency.
	///
	///     [versions]
	///     jackson = "2.17.1"
	///     [libraries]
	///     jackson-databind = { module = "com.fasterxml.jackson.core:jackson-databind", version.ref = "jackson" }
	///     guava = { group = "com.google.guava", name = "guava", version = "33.2.1-jre" }
	///     commons = "org.apache.commons:commons-lang3:3.14.0"
	static func parseGradleVersionCatalog(_ text: String) -> [String: GradleCoordinate] {
		var versions: [String: String] = [:]
		var libraries: [String: GradleCoordinate] = [:]
		var table = ""

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			var line = String(rawLine)
			if let comment = line.range(of: "#") { line = String(line[..<comment.lowerBound]) }
			line = line.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("[") {
				table = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
				continue
			}
			guard let equals = line.firstIndex(of: "=") else { continue }
			let key = line[..<equals].trimmingCharacters(in: .whitespaces)
			let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
			guard !key.isEmpty else { continue }

			if table == "versions" {
				versions[key] = GradleBuild.firstQuoted(in: value)
				continue
			}
			guard table == "libraries" else { continue }

			var coordinate: GradleCoordinate?
			if value.hasPrefix("{") {
				let reference = GradleBuild.quoted(after: "version.ref", in: value)
				let literal = value.range(of: "version.ref") == nil
					? GradleBuild.quoted(after: "version", in: value)
					: nil
				let version = reference.flatMap { versions[$0] } ?? literal
				if let module = GradleBuild.quoted(after: "module", in: value) {
					let parts = module.split(separator: ":")
					if parts.count == 2 {
						coordinate = GradleCoordinate(
							group: String(parts[0]), name: String(parts[1]), version: version
						)
					}
				} else if let group = GradleBuild.quoted(after: "group", in: value),
				          let name = GradleBuild.quoted(after: "name", in: value)
				{
					coordinate = GradleCoordinate(group: group, name: name, version: version)
				}
			} else if let notation = GradleBuild.firstQuoted(in: value) {
				let parts = notation.split(separator: ":")
				if parts.count >= 2 {
					coordinate = GradleCoordinate(
						group: String(parts[0]), name: String(parts[1]),
						version: parts.count > 2 ? String(parts[2]) : nil
					)
				}
			}
			if let coordinate { libraries[normalisedCatalogAlias(key)] = coordinate }
		}
		return libraries
	}

	/// What the catalog is called in the build file: `libs` unless the settings
	/// file renamed it, which `versionCatalogs { create("…") }` does.
	static func gradleCatalogAccessors(in root: URL) -> [String] {
		var accessors = ["libs"]
		guard let settings = GradleBuild.settingsFile(in: root),
		      let text = try? String(contentsOf: settings, encoding: .utf8),
		      text.contains("versionCatalogs")
		else { return accessors }
		for rawLine in text.split(separator: "\n") where rawLine.contains("create(") {
			if let name = GradleBuild.quoted(after: "create(", in: String(rawLine)) {
				accessors.append(name)
			}
		}
		return accessors
	}

	/// `$GRADLE_USER_HOME`, or `~/.gradle`.
	static func gradleUserHome() -> URL {
		let environment = ProcessInfo.processInfo.environment
		if let path = environment["GRADLE_USER_HOME"], !path.isEmpty {
			return URL(fileURLWithPath: path)
		}
		return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gradle")
	}

	/// The jar in Gradle's cache, found by **listing** the level Maven does not
	/// have.
	///
	///     ~/.gradle/caches/modules-2/files-2.1/<group>/<name>/<version>/<sha1>/<name>-<version>.jar
	///
	/// The `<sha1>` is a checksum of the file itself, so nothing outside Gradle
	/// can compute it — 0513's lesson exactly, in a second spelling. Every sha1
	/// directory under the version is tried, in a fixed order so that two reads
	/// of one project agree.
	static func gradleArtefact(_ coordinate: GradleCoordinate, home: URL) -> URL? {
		guard let version = coordinate.version, !version.isEmpty else { return nil }
		let directory = home
			.appendingPathComponent("caches/modules-2/files-2.1")
			.appendingPathComponent(coordinate.group)
			.appendingPathComponent(coordinate.name)
			.appendingPathComponent(version)
		let checksums = ((try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
		for checksum in checksums {
			if let jar = jvmArtefact(named: "\(coordinate.name)-\(version)", in: checksum) {
				return jar
			}
		}
		return nil
	}
}

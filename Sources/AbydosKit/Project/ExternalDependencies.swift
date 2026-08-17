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
		// Every kind is read as of 0515, so nothing names an item. The switch
		// stays exhaustive rather than becoming `return nil`: a kind added later
		// has to answer this, and answering it is how its rows say "not read yet
		// (0NNN)" instead of quietly rendering as no dependencies at all.
		case .swiftPackage, .goModule, .cargo, .npm, .maven, .gradle, .bazel, .conan: return nil
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
	/// The tool that actually resolved this root, when the kind does not name it.
	///
	/// **0525, and only JavaScript needs it.** `DependencyKind` is keyed off the
	/// marker file, and `package.json` is npm's, pnpm's and yarn's alike — so one
	/// kind covers three tools and its own name is wrong for two of them. Three
	/// kinds would be worse: `kinds(at:)` filters on markers, so every JavaScript
	/// project would grow three sets, two of them saying nothing, which is the
	/// empty-list failure 508 was filed to prevent wearing three headings.
	///
	/// So the kind stays one and the *title* is read off the lock file that is
	/// there, once, when the section is read — not while it is drawn. A tooltip
	/// that cost four `stat`s per hover would be the rule this whole type is
	/// written against.
	public let tool: String?
	public let contents: Contents

	public init(root: URL, kind: DependencyKind, tool: String? = nil, contents: Contents) {
		self.root = root
		self.kind = kind
		self.tool = tool
		self.contents = contents
	}

	/// What the section calls this set: the tool that resolved it where that is
	/// known, and the kind's own name otherwise.
	public var title: String { tool ?? kind.title }

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
/// 0516 asked whether Bazel and Conan could be an exception, since neither has
/// a lock file this obviously reads, and the answer came back a firmer no than
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

	// MARK: - npm

	/// One row of a lock file, as the file writes it — path and all.
	struct NpmLockEntry: Equatable {
		/// The lock file's own key: the path **relative to the project root**,
		/// `node_modules/lodash`. This is the whole of why npm needs no cache
		/// locator: the sources are already named.
		let path: String
		/// Everything after the last `node_modules/`, which is the name somebody
		/// wrote in an `import`.
		let name: String
		let version: String?
		/// The tarball or repository it was fetched from. Absent in a lock file
		/// written without one — see `npmOrigin`.
		let resolved: String?
	}

	/// The four lock files a `package.json` project can be resolved by, in the
	/// order npm itself prefers them, each with the tool that writes it.
	///
	/// **All four are read as of 0525**; 514 read npm's two and named this item on
	/// the rows of the other two. `package.json` is the marker for all three
	/// tools, so a pnpm or a yarn project reaches this reader whatever it does,
	/// and the row 514 replaced said `run npm install` — an instruction to
	/// install a second, conflicting tree over a project that is already
	/// installed.
	///
	/// The **order** outlives that, and is npm's own preference rather than a
	/// choice made here. A repository that has been installed twice — a
	/// `package-lock.json` somebody committed and a `yarn.lock` somebody else did
	/// — has to be answered by one of them and by the *same* one twice running,
	/// or the section's expansion state means nothing between two reads.
	static let npmLockFiles: [(name: String, tool: String)] = [
		("npm-shrinkwrap.json", "npm"),
		("package-lock.json", "npm"),
		("pnpm-lock.yaml", "pnpm"),
		("yarn.lock", "yarn"),
	]

	/// Which of the four resolved this root, or nil for a project nobody has
	/// installed.
	static func npmLockFile(at root: URL) -> (name: String, tool: String)? {
		let manager = FileManager.default
		return npmLockFiles.first {
			manager.fileExists(atPath: root.appendingPathComponent($0.name).path)
		}
	}

	/// `package-lock.json`, which is JSON and is the resolved tree.
	///
	/// **The easiest kind so far, because the lock file's keys are the paths.**
	/// The `packages` object of a version 2 or 3 lock file is keyed by path
	/// relative to the project root — `node_modules/lodash`,
	/// `node_modules/@types/node`, `node_modules/jest/node_modules/chalk` for a
	/// nested conflicting copy — so `localPath` is the key appended to the root
	/// and there is no cache to locate at all. Every other kind here has one.
	///
	/// `npm ls --json` is the subprocess this does not run: it is `cargo
	/// metadata` wearing a different name, it costs a node launch per project on
	/// open and again on every write of the lock file, and it answers with
	/// whichever npm is first on the PATH — which on a machine with `fnm` or
	/// `nvm` is whichever shell last set it. See the rule on this type.
	///
	/// The sources being *inside* the project is the case no other kind has, and
	/// it needs no code: `node_modules` is already in
	/// `FileNode.defaultExcludedDirectoryNames` and in `Subprojects.skipped`, and
	/// a reveal already asks the section before the ordinary tree.
	static func readNpm(at root: URL) -> DependencySet.Contents {
		let manager = FileManager.default
		guard let lock = npmLockFile(at: root) else {
			if let workspace = npmWorkspaceAbove(root) {
				return .unresolved("resolved in the workspace at \(workspace.lastPathComponent)")
			}
			return .unresolved("no package-lock.json — run npm install")
		}
		// The kind is one and the tools are three, so this is where they part.
		// 514 wrote a sentence naming this item here instead; the sentence is
		// gone and the two readers below are what it was promising.
		switch lock.name {
		case "pnpm-lock.yaml": return readPnpm(at: root)
		case "yarn.lock": return readYarn(at: root)
		default: break
		}

		let file = root.appendingPathComponent(lock.name)
		guard let data = try? Data(contentsOf: file),
			let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else {
			return .unresolved("\(lock.name) could not be read")
		}

		// `fileExists` per entry, and a real `node_modules` has hundreds to a few
		// thousand of them — the same shape as the per-pin stat in
		// `readSwiftPackages`, paid on open and again whenever the lock file is
		// written. Measured on a real project on this machine: 992 entries, 7.4 ms
		// warm. That is what makes a `stat` per package affordable and a directory
		// walk of `node_modules` — which is where the "npm is slow" reputation
		// comes from — not worth considering.
		let packages = npmEntries(in: top).map { entry -> ExternalDependency in
			let directory = root.appendingPathComponent(entry.path)
			var isDirectory: ObjCBool = false
			let installed = manager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
				&& isDirectory.boolValue
			return ExternalDependency(
				name: entry.name,
				version: entry.version,
				origin: npmOrigin(of: entry.resolved),
				// A package in the lock file and not on disk is resolved and not
				// installed — a fresh checkout with no `npm install` run — and
				// pointing at the directory anyway would draw a package with no
				// files in it.
				localPath: installed ? directory : nil
			)
		}
		return byName(packages)
	}

	/// The external packages a lock file names, whichever layout it is in.
	///
	/// Version 2 and 3 key `packages` by path; version 1 has no `packages` at all
	/// and instead a `dependencies` tree keyed by name, nested where two
	/// packages need different versions of a third. Version 2 carries both, for
	/// tools that only understand version 1, and `packages` wins — it is the one
	/// with the paths in it. Reading only the newer layout would empty the
	/// section on any project last installed by npm 6, which is the same failure
	/// `readSwiftPackages` refuses for `Package.resolved`'s two layouts.
	static func npmEntries(in top: [String: Any]) -> [NpmLockEntry] {
		if let packages = top["packages"] as? [String: Any] {
			return packages.compactMap { path, value in
				guard let entry = value as? [String: Any] else { return nil }
				return npmEntry(path: path, entry: entry)
			}
		}
		var entries: [NpmLockEntry] = []
		func walk(_ tree: [String: Any], under prefix: String) {
			for (name, value) in tree {
				guard let entry = value as? [String: Any] else { continue }
				let path = prefix + "node_modules/" + name
				if let found = npmEntry(path: path, entry: entry) { entries.append(found) }
				if let nested = entry["dependencies"] as? [String: Any] {
					walk(nested, under: path + "/")
				}
			}
		}
		walk(top["dependencies"] as? [String: Any] ?? [:], under: "")
		return entries
	}

	/// One entry, or nil for one that is not an external dependency.
	///
	/// Two kinds are dropped, both for 508's rule that what the section lists is
	/// what came from outside:
	///
	/// - a key with no `node_modules` in it — `""` is the project itself, and
	///   `packages/app` is a workspace member, which is a directory the tree
	///   already has a row for;
	/// - `"link": true`, which is that same member *symlinked* into
	///   `node_modules` so an import can find it. Its `resolved` is a path
	///   inside the project, so listing it would show the project's own source
	///   twice under a heading saying it came from elsewhere.
	static func npmEntry(path: String, entry: [String: Any]) -> NpmLockEntry? {
		guard entry["link"] as? Bool != true else { return nil }
		guard let name = npmPackageName(inPath: path) else { return nil }
		return NpmLockEntry(
			path: path, name: name,
			version: entry["version"] as? String,
			resolved: entry["resolved"] as? String
		)
	}

	/// `node_modules/jest/node_modules/@types/node` → `@types/node`.
	///
	/// Everything after the **last** `node_modules/`, which is one rule that gets
	/// both hard cases right: a scoped name keeps its `@scope/`, and a nested
	/// copy — the second version of a package, installed under whichever package
	/// needs it — is named after itself rather than after the package it is
	/// buried in. Nil when there is no `node_modules` in the key at all, which is
	/// how the project and its workspace members are left out.
	static func npmPackageName(inPath path: String) -> String? {
		guard let marker = path.range(of: "node_modules/", options: .backwards) else { return nil }
		let name = String(path[marker.upperBound...])
		return name.isEmpty ? nil : name
	}

	/// Where a package came from, from the `resolved` URL the lock file writes.
	///
	///     https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz  → npmjs.com
	///     https://npm.pkg.github.com/@acme/thing/-/thing-1.0.tgz  → npm.pkg.github.com
	///     git+https://github.com/tomasf/thing.git#5aa45a1        → the URL, whole
	///
	/// The host and not the tarball. `shortOrigin` cuts a URL back to everything
	/// but its last component, which for a registry tarball is
	/// `registry.npmjs.org/lodash/-` — three quarters of it noise, on eight
	/// hundred rows. So the registry is named instead, and named `npmjs.com` on
	/// 513's `crates.io` precedent: the default registry is what almost every row
	/// says, and saying it as a host somebody could paste into a browser is the
	/// version of it that carries information. `registry.yarnpkg.com` is a mirror
	/// of that same registry and reads the same — 513's "two spellings of one
	/// registry" again, and here it is in a lock file npm itself wrote.
	///
	/// A git dependency keeps the whole URL, revision included, because that is
	/// what says *which* one of it; `shortOrigin` cuts it to the owner for the
	/// row and the tooltip has all of it. The `git+` prefix is dropped so that
	/// `shortOrigin` can recognise the scheme underneath — and it is what tells a
	/// git dependency from a tarball, since both are `https://` once it is gone
	/// and the host is the wrong answer for one of them: `github.com` on its own
	/// says a package came from GitHub and not which repository.
	///
	/// **A lock file with no `resolved` anywhere is real**, and not only the
	/// bundled-dependency case the format documents: one of the projects on this
	/// machine has 990 entries of 992 without one, from an install through a
	/// registry proxy. Those rows are version-only, which `DependencyNode`
	/// already draws, rather than rows claiming an origin nothing wrote down.
	static func npmOrigin(of resolved: String?) -> String {
		guard var location = resolved, !location.isEmpty else { return "" }
		let isRepository = location.hasPrefix("git+") || location.hasPrefix("git://")
			|| location.contains("#")
		if location.hasPrefix("git+") { location = String(location.dropFirst(4)) }
		guard !isRepository else { return location }
		guard location.hasPrefix("https://") || location.hasPrefix("http://"),
			let host = URL(string: location)?.host
		else { return location }
		return isNpmRegistry(host) ? "npmjs.com" : host
	}

	/// The registry every npm project uses, by either of the two hosts that
	/// serve it: npm's own, and yarn's mirror of it.
	static func isNpmRegistry(_ host: String) -> Bool {
		host == "registry.npmjs.org" || host == "registry.yarnpkg.com"
	}

	/// The workspace that resolves for this package, if it is a member of one.
	///
	/// 513's finding in npm's spelling, and the commoner half of it: an npm
	/// workspace has **one** lock file, at its root, and hoists every dependency
	/// into the root's `node_modules`. Each member has a `package.json`, so each
	/// member is a subproject with a row of its own — and `run npm install` in a
	/// member is worse advice than cargo's was, because npm will do it: it
	/// installs a second `node_modules` inside the member and the workspace's
	/// hoisting stops meaning anything.
	///
	/// The ancestor has to *declare* the workspace — `workspaces` in its
	/// `package.json`, or a `pnpm-workspace.yaml` beside it — and not merely
	/// have a lock file. A `docs` folder with a `package.json` of its own inside
	/// a repository that is not a workspace is a project that genuinely has not
	/// been installed, and `run npm install` is the right thing to tell it.
	///
	/// The workspace's own list is deliberately not borrowed down into the
	/// member, for 513's reason: it is the whole workspace's resolved set, and
	/// copying it under five members would print it five times and claim each
	/// member depends on all of it.
	static func npmWorkspaceAbove(_ root: URL) -> URL? {
		let manager = FileManager.default
		var directory = root.deletingLastPathComponent()
		for _ in 0..<6 {
			guard directory.path != "/", directory.path != root.path else { return nil }
			let manifest = directory.appendingPathComponent("package.json")
			let hasLock = npmLockFiles.contains {
				manager.fileExists(atPath: directory.appendingPathComponent($0.name).path)
			}
			if hasLock, manager.fileExists(atPath: manifest.path), declaresNpmWorkspaces(manifest) {
				return directory
			}
			directory = directory.deletingLastPathComponent()
		}
		return nil
	}

	/// The version an installed package says it is, from its own manifest.
	///
	/// One file read, and only asked where it settles something — see `readYarn`,
	/// which is the only caller and asks it for a handful of names out of a
	/// couple of thousand.
	static func npmInstalledVersion(of name: String, under modules: URL) -> String? {
		let manifest = modules.appendingPathComponent(name).appendingPathComponent("package.json")
		guard let data = try? Data(contentsOf: manifest),
		      let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return nil }
		return top["version"] as? String
	}

	// MARK: - pnpm and yarn: the shapes both lock files are made of

	/// One package a `pnpm-lock.yaml` or a `yarn.lock` names.
	///
	/// The two files look nothing like each other and come out as the same three
	/// facts, which are the whole of what a row draws.
	struct NodeLockEntry: Equatable {
		let name: String
		let version: String?
		/// Empty where the lock file writes no locator at all — which for pnpm is
		/// **most rows**, and is left empty rather than filled in with a guess.
		/// See `readPnpm`.
		let origin: String
	}

	/// The `@` that separates a package's name from what follows it, which is the
	/// **first** one past a leading `@scope/` and never the last.
	///
	/// Found the hard way in pnpm's store, where a directory is
	/// `@babel+helper-module-transforms@7.25.2_@babel+core@7.25.2`: the last `@`
	/// in that is inside the *peer* it was built against, and splitting there
	/// names a package `@babel+helper-module-transforms@7.25.2_@babel+core` at
	/// version `7.25.2`. The same shape turns up in yarn berry's descriptors and
	/// in a `patch:` locator, so the rule is written once.
	static func nodeNameAndRest(_ text: some StringProtocol) -> (name: String, rest: String)? {
		let whole = String(text)
		guard !whole.isEmpty else { return nil }
		let start = whole.hasPrefix("@") ? whole.index(after: whole.startIndex) : whole.startIndex
		guard let at = whole[start...].firstIndex(of: "@") else { return nil }
		let name = String(whole[..<at])
		guard !name.isEmpty else { return nil }
		return (name, String(whole[whole.index(after: at)...]))
	}

	/// A scalar as these two generators write one: bare, single-quoted or
	/// double-quoted.
	///
	/// Nothing else, and that is the point — no block scalars, no anchors, no
	/// tags. See `readPnpm` for why a reader that understands only what these
	/// files contain is the right size of tool for them.
	static func unquotedNodeScalar(_ text: some StringProtocol) -> String {
		var value = String(text).trimmingCharacters(in: .whitespaces)
		for quote in ["'", "\""]
		where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
			value = String(value.dropFirst().dropLast())
			// A single-quoted scalar escapes its own quote by doubling it, and
			// pnpm writes `'@scope/it''s'` rather than switching to double quotes.
			if quote == "'" { value = value.replacingOccurrences(of: "''", with: "'") }
			break
		}
		return value
	}

	/// One key out of a one-line flow mapping — `{integrity: sha512-…, tarball:
	/// https://…}` — which is the only nesting either of these files puts on a
	/// line of its own.
	///
	/// The character in front of a key in a flow mapping is `{`, `,` or a space,
	/// and requiring it is what stops `repo:` being found inside
	/// `https://my-repo:8080/…`.
	static func nodeFlowValue(_ key: String, in text: some StringProtocol) -> String? {
		let whole = String(text)
		var search = whole.startIndex..<whole.endIndex
		while let range = whole.range(of: key + ":", range: search) {
			search = range.upperBound..<whole.endIndex
			if range.lowerBound > whole.startIndex {
				let before = whole[whole.index(before: range.lowerBound)]
				guard before == "{" || before == "," || before == " " else { continue }
			}
			let rest = whole[range.upperBound...]
			let end = rest.firstIndex { $0 == "," || $0 == "}" } ?? rest.endIndex
			let value = unquotedNodeScalar(rest[..<end])
			return value.isEmpty ? nil : value
		}
		return nil
	}

	// MARK: - pnpm

	/// `pnpm-lock.yaml`, which is the resolved set and is YAML.
	///
	/// **There is no YAML reader in this repository, and this item does not add
	/// one.** That is 513's "there is no TOML reader" a second time, and 0525 was
	/// filed insisting the argument be made again rather than inherited, because
	/// 513's reason — `Cargo.lock` is generated and *flat* — plainly does not
	/// carry over: this file has `importers:`, `packages:` and `snapshots:` at the
	/// top level and two more levels under each.
	///
	/// It is made again, and it comes out the same way, on a different reason.
	/// What this section wants out of the file is **the keys of one block**. The
	/// `packages:` block is a mapping whose keys are `name@version` and whose
	/// values this reader looks at exactly one line of. It never descends into
	/// `importers:`, which is the ranges somebody wrote rather than what was
	/// resolved; it must never descend into `snapshots:`, which repeats every one
	/// of those keys with its peers attached and would draw the whole project
	/// twice. So the nesting a YAML library would earn its keep on is nesting
	/// this reader is required to *skip*.
	///
	/// Against that: a library is Yams, which vendors libyaml, for a file that is
	/// machine-written by `js-yaml` with fixed options and is never hand-edited —
	/// so the constructs a hand-written reader is bad at (anchors, tags, block
	/// scalars, flow sequences spanning lines) are constructs that do not occur in
	/// it. It would also build the whole document — twenty thousand lines, most of
	/// it `snapshots:` — to be asked for two thousand keys, on a path that runs
	/// when a project opens and again on every write of the lock file. `project.md`
	/// asks for a reason that survives being written down, and "one block's keys,
	/// out of a generated file" is not one.
	///
	/// What is bought instead is the guard below: a file this reader does not
	/// understand says so, rather than coming out as a project that depends on
	/// nothing. That is the failure a hand-written reader can actually cause, and
	/// it is the failure the section exists to prevent, so it is answered
	/// explicitly — `readConanPackages` makes the same move for a Conan 1 lock.
	static func readPnpm(at root: URL) -> DependencySet.Contents {
		let file = root.appendingPathComponent("pnpm-lock.yaml")
		guard let text = try? String(contentsOf: file, encoding: .utf8) else {
			return .unresolved("pnpm-lock.yaml could not be read")
		}
		// Guarded on a key and not on the parse. Every pnpm lock from 5.x to 9.x
		// opens with `lockfileVersion`, so a file without one is not a shape this
		// reader knows, and `.packages([])` over it would read as "no
		// dependencies" — the one claim this section must never make by accident.
		guard text.hasPrefix("lockfileVersion:") || text.contains("\nlockfileVersion:") else {
			return .unresolved("pnpm-lock.yaml could not be read")
		}

		let store = pnpmStoreDirectories(at: root)
		let manager = FileManager.default
		let packages = parsePnpmLock(text).map { entry -> ExternalDependency in
			let directory = entry.version
				.flatMap { store[pnpmStoreKey(name: entry.name, version: $0)] }?
				.appendingPathComponent("node_modules")
				.appendingPathComponent(entry.name)
			let installed = directory.map { manager.fileExists(atPath: $0.path) } ?? false
			return ExternalDependency(
				name: entry.name, version: entry.version, origin: entry.origin,
				localPath: installed ? directory : nil
			)
		}
		return byName(packages)
	}

	/// The keys of the `packages:` block, and the one line under each worth
	/// reading.
	///
	/// **`snapshots:` is the trap.** A 9.x lock lists every package twice: once
	/// under `packages:`, which is what was resolved, and again under
	/// `snapshots:`, which is the same key with the peers it was built against in
	/// parentheses and the graph beneath it. A reader that took every indented key
	/// ending in a colon would draw a project of two thousand packages as four
	/// thousand rows, half of them named after a peer set. So the top-level block
	/// is tracked and only one of them is read.
	static func parsePnpmLock(_ text: String) -> [NodeLockEntry] {
		var entries: [NodeLockEntry] = []
		var block = ""
		var keyIndent: Int?
		var current: NodeLockEntry?

		func finish() {
			if let current { entries.append(current) }
			current = nil
		}

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = String(rawLine)
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
			let indent = line.prefix { $0 == " " }.count

			if indent == 0 {
				finish()
				keyIndent = nil
				block = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : ""
				continue
			}
			guard block == "packages" else { continue }
			if keyIndent == nil { keyIndent = indent }
			guard let depth = keyIndent else { continue }

			if indent == depth {
				finish()
				current = pnpmPackage(fromKey: trimmed)
				continue
			}
			guard let package = current, indent > depth, trimmed.hasPrefix("resolution:") else {
				continue
			}
			let flow = trimmed.dropFirst("resolution:".count)
			// `{directory: ../shared, type: directory}` is a `file:` or `link:`
			// dependency: a directory inside the project, which the tree already
			// has rows for. 513's Cargo `path` dependency in pnpm's spelling.
			if nodeFlowValue("type", in: flow) == "directory" {
				current = nil
				continue
			}
			guard let locator = pnpmResolutionLocator(in: flow) else { continue }
			current = NodeLockEntry(
				name: package.name, version: package.version, origin: npmOrigin(of: locator)
			)
		}
		finish()
		return entries
	}

	/// Where a `resolution:` says a package came from, when it says at all.
	///
	/// A registry package's resolution is `{integrity: sha512-…}` and nothing
	/// else — see `readPnpm` on why that is left as no origin rather than filled
	/// in. A tarball and a git checkout do write a locator, and it is the answer.
	static func pnpmResolutionLocator(in flow: some StringProtocol) -> String? {
		if let repository = nodeFlowValue("repo", in: flow) {
			guard let commit = nodeFlowValue("commit", in: flow) else { return repository }
			return repository + "#" + commit
		}
		return nodeFlowValue("tarball", in: flow)
	}

	/// One key of the `packages:` block, across every layout still on disk.
	///
	/// Three of them, and they are not tellable apart by the lock file's version
	/// number alone because a repository holds whichever one it was last
	/// installed with:
	///
	///     lodash@4.17.21                     9.x, and 6.x with a leading slash
	///     /@abandonware/bleno/0.6.1          5.x: a path, the version last
	///     registry.example.com/lodash/4.17.21   5.x, from another registry
	///
	/// **The layouts are told apart by counting slashes**, not by the leading one:
	/// the `name@version` form has exactly one slash when the name is scoped and
	/// none when it is not, and anything with more of them is a path. A leading
	/// slash alone would get `registry.example.com/lodash/4.17.21` wrong, and
	/// splitting on the first `@` would get it wrong the other way, by finding the
	/// `@` of `@babel` in the middle of the host.
	///
	/// The registry in front of a 5.x path is kept as the origin, which is the
	/// only layout of the three that records one at all.
	static func pnpmPackage(fromKey rawKey: String) -> NodeLockEntry? {
		guard rawKey.hasSuffix(":") else { return nil }
		var key = unquotedNodeScalar(rawKey.dropLast())
		// `…@7.25.2(@babel/core@7.25.2)` — the peers it was built against, which
		// are not part of what the package is called or which version of it this
		// is. `snapshots:` is where those matter and `snapshots:` is not read.
		if let peers = key.firstIndex(of: "(") { key = String(key[..<peers]) }
		if key.hasPrefix("/") { key = String(key.dropFirst()) }
		guard !key.isEmpty else { return nil }

		// A directory inside the project, dropped for the reason above. Caught
		// here as well as at `resolution:` because 5.x wrote no resolution for one.
		guard !key.contains("@file:"), !key.contains("@link:") else { return nil }

		if key.contains("://") {
			// `foo@https://codeload.github.com/…`: the version is a URL, which is
			// where it came from and is not a version anybody could type.
			guard let split = nodeNameAndRest(key) else { return nil }
			return NodeLockEntry(name: split.name, version: nil, origin: npmOrigin(of: split.rest))
		}

		let slashes = key.filter { $0 == "/" }.count
		guard slashes > (key.hasPrefix("@") ? 1 : 0) else {
			guard let split = nodeNameAndRest(key) else { return nil }
			return NodeLockEntry(name: split.name, version: split.rest, origin: "")
		}

		var parts = key.split(separator: "/").map(String.init)
		guard parts.count >= 2 else { return nil }
		let version = parts.removeLast()
		let scoped = parts.count >= 2 && parts[parts.count - 2].hasPrefix("@")
		let name = parts.suffix(scoped ? 2 : 1).joined(separator: "/")
		guard !name.isEmpty else { return nil }
		return NodeLockEntry(
			name: name, version: version,
			origin: parts.dropLast(scoped ? 2 : 1).joined(separator: "/")
		)
	}

	/// `@babel/core`, `7.25.2` → `@babel+core@7.25.2`, which is what the store
	/// calls the directory.
	static func pnpmStoreKey(name: String, version: String) -> String {
		name.replacingOccurrences(of: "/", with: "+") + "@" + version
	}

	/// The store, **listed rather than computed** — cargo's registry hash and
	/// Bazel's separator, a third time.
	///
	/// pnpm's `node_modules` is a tree of symlinks into
	/// `node_modules/.pnpm/<name>@<version>/node_modules/<name>`, and *that* is
	/// what a package row is rooted at: it is a real directory, so nothing has to
	/// follow a symlink and the tree lists it like any other folder. The
	/// top-level `node_modules/<name>` symlink is deliberately not used instead —
	/// it exists only for a project's direct dependencies, and points at one
	/// version of a package a lock file may hold three of.
	///
	/// The directory name carries the peers a package was built against, after an
	/// underscore: `@babel+helper-module-transforms@7.25.2_@babel+core@7.25.2`.
	/// Those are cut off here rather than reproduced, because pnpm's own escaping
	/// of them has changed across releases and a package name may itself contain
	/// an underscore — so the cut is made at the first underscore *after* the
	/// version, which semver cannot contain one of.
	///
	/// One listing per project and then a dictionary, not a scan per package: a
	/// real store has hundreds to a few thousand entries and the linear form
	/// would be that many comparisons per package, on a path that runs when a
	/// project opens. Measured on a real pnpm 9 project on this machine: 234
	/// packages against a store of 200 directories, 29 ms for the whole section.
	static func pnpmStoreDirectories(at root: URL) -> [String: URL] {
		let store = root.appendingPathComponent("node_modules/.pnpm")
		let entries = ((try? FileManager.default.contentsOfDirectory(
			at: store, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }

		var found: [String: URL] = [:]
		for entry in entries {
			let key = pnpmStoreName(withoutPeers: entry.lastPathComponent)
			// One package at one version can be in the store several times, once
			// per peer set, and the sources under each are the same. Sorted and
			// first-wins so that two reads of one project show the same path.
			if found[key] == nil { found[key] = entry }
		}
		return found
	}

	/// `@babel+core@7.25.2_typescript@5.3.3` → `@babel+core@7.25.2`.
	static func pnpmStoreName(withoutPeers directory: String) -> String {
		guard let at = nodeNameAndRest(directory) else { return directory }
		guard let underscore = at.rest.firstIndex(of: "_") else { return directory }
		let version = at.rest[..<underscore]
		return at.name + "@" + version
	}

	// MARK: - yarn

	/// `yarn.lock`, in **both** of the syntaxes yarn has written.
	///
	/// The item that filed this called it three formats. It is two, and the third
	/// is a version number: yarn 1 writes a bespoke file — a header naming one or
	/// more ranges, then fields indented under it — and every yarn since 2 writes
	/// YAML. The YAML one has been through four `__metadata.version` numbers and
	/// the two fields this reads, the entry's header and its `version`, are the
	/// same in all of them, so there is nothing to tell apart there.
	///
	/// And the two syntaxes are the same *shape*: a top-level entry, then indented
	/// fields, differing in `version "4.17.21"` against `version: 4.17.21`. One
	/// reader covers both, which is why this is shorter than pnpm's and not
	/// longer.
	///
	/// **What is not covered**: reading *inside* a Plug'n'Play zip. A berry
	/// project with the pnp linker has no `node_modules` at all — its packages are
	/// zip files under `.yarn/cache` — so those rows name the archive and cannot
	/// be opened, exactly as a Maven dependency names its jar. Browsing a zip is a
	/// different capability from reading a lock file and it is not this item's.
	static func readYarn(at root: URL) -> DependencySet.Contents {
		let file = root.appendingPathComponent("yarn.lock")
		guard let text = try? String(contentsOf: file, encoding: .utf8) else {
			return .unresolved("yarn.lock could not be read")
		}
		// The same guard `readPnpm` and `readConanPackages` make, and yarn needs it
		// as much as either: a lock file for a project that depends on nothing is
		// a header and no entries, and so is a file this reader does not
		// understand. Every yarn.lock ever written stamps one of these two.
		guard text.contains("yarn lockfile v1") || text.contains("__metadata") else {
			return .unresolved("yarn.lock could not be read")
		}

		let entries = parseYarnLock(text)
		let modules = root.appendingPathComponent("node_modules")
		let archives = yarnCacheArchives(at: root)
		let manager = FileManager.default

		// **A yarn.lock does not say where anything was installed.** npm's keys are
		// paths and this file has none, so the sources have to be found rather than
		// read off. A name the lock resolves once is the copy hoisted to
		// `node_modules/<name>`, and needs nothing checked. A name it resolves
		// several times has one copy at the root and the rest nested under whoever
		// needed them, and only the root copy's own manifest says which version it
		// is — so that manifest is read, for those names alone.
		//
		// Measured on a real yarn 1 project on this machine: 883 packages, of
		// which 96 names are resolved more than once, so 96 manifests are read
		// and they cost 6 ms of the 40 ms the whole section takes. Reading every
		// package's manifest instead would be 883 of them, and dropping the
		// sources of every duplicated name would lose a tenth of the rows.
		var counts: [String: Int] = [:]
		for entry in entries { counts[entry.name, default: 0] += 1 }
		var hoisted: [String: String] = [:]
		for (name, count) in counts where count > 1 {
			hoisted[name] = npmInstalledVersion(of: name, under: modules)
		}

		let packages = entries.map { entry -> ExternalDependency in
			var localPath: URL?
			if counts[entry.name] == 1 || (entry.version != nil && hoisted[entry.name] == entry.version) {
				let directory = modules.appendingPathComponent(entry.name)
				var isDirectory: ObjCBool = false
				if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
				   isDirectory.boolValue {
					localPath = directory
				}
			}
			// Plug'n'Play: no directory anywhere, and a zip in the cache that is
			// this package and can be named without being browsed. 0515's `artefact`
			// exactly — a jar is not a directory either — and the row's tooltip
			// already says the archive rather than `not fetched`.
			let archive = localPath == nil
				? entry.version.flatMap { archives[yarnCacheKey(name: entry.name, version: $0)] }
				: nil
			return ExternalDependency(
				name: entry.name, version: entry.version, origin: entry.origin,
				localPath: localPath, artefact: archive
			)
		}
		return byName(packages)
	}

	/// Every entry of a `yarn.lock`, whichever syntax it is in.
	///
	/// An entry starts at column zero and its fields are indented, in both. What
	/// is dropped is what is not a package from outside — 508's rule, in yarn's
	/// four spellings of it: `workspace:` is a member of this repository,
	/// `link:` and `portal:` are directories in it, and `file:` is one of those
	/// two under yarn 1.
	static func parseYarnLock(_ text: String) -> [NodeLockEntry] {
		var entries: [NodeLockEntry] = []
		var seen: Set<String> = []
		var name: String?
		var locator: String?
		var version: String?
		var resolved: String?

		func finish() {
			defer { name = nil; locator = nil; version = nil; resolved = nil }
			guard let name else { return }
			// `patch:` writes the same package and version a second time, wrapping
			// the entry it patches — so the pair is collapsed here rather than
			// dropped by protocol, which would lose a package that is *only*
			// reachable through its patch. Two versions of one package stay two
			// rows, the way npm's nested copies do.
			guard seen.insert(name + "@" + (version ?? "")).inserted else { return }
			let origin = resolved.map { yarnResolvedOrigin(of: $0) }
				?? locator.map { yarnOrigin(ofLocator: $0) }
				?? ""
			entries.append(NodeLockEntry(name: name, version: version, origin: origin))
		}

		for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = String(rawLine)
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

			if line.first != " " && line.first != "\t" {
				finish()
				guard trimmed.hasSuffix(":"), trimmed != "__metadata:" else { continue }
				guard let split = nodeNameAndRest(yarnFirstDescriptor(in: trimmed.dropLast())),
				      !yarnIsInProject(locator: split.rest)
				else { continue }
				name = split.name
				locator = split.rest
				continue
			}
			guard name != nil else { continue }

			if trimmed.hasPrefix("version ") || trimmed.hasPrefix("version:") {
				version = unquotedNodeScalar(
					trimmed.dropFirst("version".count).drop { $0 == ":" || $0 == " " }
				)
			} else if trimmed.hasPrefix("resolved ") {
				// yarn 1, and the one field that names a URL outright.
				resolved = unquotedNodeScalar(trimmed.dropFirst("resolved".count))
			} else if trimmed.hasPrefix("resolution:") {
				// berry, and more trustworthy than the header: the header carries
				// the *range* somebody asked for and this carries what it resolved
				// to. A `workspace:` here is the project's own root entry.
				let value = unquotedNodeScalar(trimmed.dropFirst("resolution:".count))
				guard let split = nodeNameAndRest(value) else { continue }
				if yarnIsInProject(locator: split.rest) { name = nil; continue }
				locator = split.rest
			}
		}
		finish()
		return entries
	}

	/// The first of the ranges an entry's header names, unquoted.
	///
	/// **The two syntaxes put the quotes in different places, and that is the one
	/// place they had to be told apart.** yarn 1 writes a list of quoted
	/// descriptors — `"@babel/code-frame@^7.0.0", "@babel/code-frame@^7.16.7":` —
	/// and berry writes *one* quoted string with the commas inside it:
	/// `"@babel/code-frame@npm:^7.0.0, @babel/code-frame@npm:^7.22.13":`. So the
	/// comma is found first and the quotes are trimmed off whatever is left of
	/// it, either way. Unquoting before splitting reads berry's key as a package
	/// called `"`, which is what this comment is here to stop somebody
	/// re-introducing.
	///
	/// The first is as good as any: the ranges differ and what they resolved to
	/// is one package.
	static func yarnFirstDescriptor(in head: some StringProtocol) -> String {
		let whole = String(head)
		let first = whole.firstIndex(of: ",").map { String(whole[..<$0]) } ?? whole
		return first.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
	}

	/// Whether a yarn locator names something inside this repository rather than
	/// a package from outside it.
	static func yarnIsInProject(locator: String) -> Bool {
		guard let colon = locator.firstIndex(of: ":") else { return false }
		return ["workspace", "link", "portal", "file"].contains(String(locator[..<colon]))
	}

	/// yarn 1's `resolved`, which is **not** an npm `resolved` however much it
	/// looks like one.
	///
	/// Found by a test, and it would have spoiled every row of every yarn 1
	/// project: yarn writes the tarball's sha1 as a fragment on the end of the
	/// URL — `…/lodash-4.17.21.tgz#679591c5` — and npm never does. `npmOrigin`
	/// reads a `#` as *this came from a repository and the fragment says which
	/// revision*, which is right for npm and turns a registry package's origin
	/// into the whole tarball URL here. So the fragment comes off first, and the
	/// two spellings that really are repositories keep theirs.
	static func yarnResolvedOrigin(of resolved: String) -> String {
		guard !resolved.hasPrefix("git+"), !resolved.hasPrefix("git://"),
		      !resolved.contains(".git#")
		else { return npmOrigin(of: resolved) }
		return npmOrigin(of: resolved.firstIndex(of: "#").map { String(resolved[..<$0]) } ?? resolved)
	}

	/// Where a berry entry came from, from the protocol its locator names.
	///
	/// `npm:` is the npm registry, which is the one protocol that is a *statement*
	/// rather than a path — so it reads `npmjs.com`, the way a crates.io index URL
	/// does. Everything else is a locator `npmOrigin` already knows how to shorten:
	/// a `https://…#commit` keeps the whole of itself, a `github:owner/repo` keeps
	/// its own spelling.
	///
	/// **pnpm gets no equivalent of this and that is deliberate.** A
	/// `pnpm-lock.yaml` records no registry at all for an ordinary package — the
	/// resolution is an integrity hash and nothing else — and the registry it was
	/// installed from lives in somebody's `.npmrc`, which says what the *next*
	/// install would use rather than what this one did. 514 met the same question
	/// as a `package-lock.json` with no `resolved` and answered it the same way:
	/// a row with a version and no origin, rather than a row claiming an origin
	/// nobody wrote down.
	static func yarnOrigin(ofLocator locator: String) -> String {
		guard let colon = locator.firstIndex(of: ":") else { return "" }
		let scheme = String(locator[..<colon])
		let rest = String(locator[locator.index(after: colon)...])
		switch scheme {
		case "npm": return "npmjs.com"
		// `foo@patch:foo@npm%3A1.0.0#./p.patch` — the patched package came from
		// wherever the entry it wraps did, and that is written inside it, encoded.
		case "patch": return rest.contains("npm%3A") || rest.contains("npm:") ? "npmjs.com" : ""
		default: return npmOrigin(of: locator)
		}
	}

	/// `@babel/core`, `7.23.0` → `@babel-core-npm-7.23.0`.
	static func yarnCacheKey(name: String, version: String) -> String {
		name.replacingOccurrences(of: "/", with: "-") + "-npm-" + version
	}

	/// The Plug'n'Play cache, **listed rather than computed** for the third time
	/// in this file.
	///
	/// An archive is `<name>-npm-<version>-<hash>-<cacheKey>.zip`, where the hash
	/// is of the file's contents and the cache key is berry's own — neither
	/// computable from outside yarn. So the list is read and both truncations are
	/// registered: older berry wrote no cache key, and guessing which of the two a
	/// project uses would be a lookup that silently found nothing.
	static func yarnCacheArchives(at root: URL) -> [String: URL] {
		let cache = root.appendingPathComponent(".yarn/cache")
		let entries = ((try? FileManager.default.contentsOfDirectory(
			at: cache, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? [])
			.filter { $0.pathExtension == "zip" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }

		var found: [String: URL] = [:]
		for entry in entries {
			let stem = entry.deletingPathExtension().lastPathComponent
			let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
			for drop in [2, 1] where parts.count > drop {
				let key = parts.dropLast(drop).joined(separator: "-")
				if found[key] == nil { found[key] = entry }
			}
		}
		return found
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

	/// Whether a `package.json` says it is the root of a workspace.
	///
	/// `workspaces` is an array of globs in npm's and yarn's spelling and an
	/// object with a `packages` array in yarn v1's, so its presence is what is
	/// asked rather than its shape. pnpm keeps the same list in a
	/// `pnpm-workspace.yaml` beside the manifest, which is YAML and is therefore
	/// tested for by existing rather than by being read.
	static func declaresNpmWorkspaces(_ manifest: URL) -> Bool {
		if FileManager.default.fileExists(
			atPath: manifest.deletingLastPathComponent()
				.appendingPathComponent("pnpm-workspace.yaml").path
		) { return true }
		guard let data = try? Data(contentsOf: manifest),
			let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return false }
		return top["workspaces"] != nil
	}

	// MARK: - Bazel

	/// One module a Bazel workspace depends on, as the lock or the manifest
	/// writes it.
	struct BazelModule: Equatable {
		let name: String
		let version: String?
		/// The registry it was resolved from, where the file says. Empty where
		/// nothing on disk says — which is most of the layouts, and is why this is
		/// a string to be shown rather than a guess to be made.
		let origin: String
	}

	/// A Bazel workspace's external modules, from `MODULE.bazel.lock` when there
	/// is one and `MODULE.bazel` when there is not.
	///
	/// **No `bazel query` and no `bazel mod graph`, and the reason is stronger
	/// here than the cost argument on this type.** Those commands start a Bazel
	/// server, and a server takes a lock on the output base. So the section would
	/// either block behind somebody's build or make their next `bazel` command
	/// block behind the section — on a path that runs when a project opens and
	/// again whenever a file is written. Slow would be a trade; taking somebody's
	/// build lock is not. Bazel also need not be installed, and bazelisk's first
	/// run downloads a release, so opening a project would trigger a package
	/// fetch.
	///
	/// What is left is plenty. The lock is the resolved set, the manifest is the
	/// direct set, and both are text.
	static func readBazelModules(at root: URL) -> DependencySet.Contents {
		let repositories = bazelRepositoryDirectories(for: root)

		func packages(_ modules: [BazelModule]) -> DependencySet.Contents {
			byName(modules.map { module in
				ExternalDependency(
					name: module.name, version: module.version, origin: module.origin,
					localPath: bazelSources(named: module.name, in: repositories)
				)
			})
		}

		if let data = try? Data(contentsOf: root.appendingPathComponent("MODULE.bazel.lock")),
		   let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
			let modules = bazelSelectedModules(inLock: top)
			if !modules.isEmpty { return packages(modules) }
		}

		// The lock's shape is not promised and changes between releases, so an
		// unreadable one falls through to the manifest rather than erroring. The
		// manifest lists less — direct dependencies only — and listing less is a
		// better failure than listing nothing.
		if let text = try? String(
			contentsOf: root.appendingPathComponent("MODULE.bazel"), encoding: .utf8
		) {
			return packages(bazelDeclaredModules(in: text))
		}

		// A `WORKSPACE`-only workspace, and the honest end of this reader. Its
		// repositories are declared by Starlark macros — `http_archive` inside a
		// `.bzl` somebody wrote — and there is no file on disk that lists them.
		// Listing `<output base>/external` does not rescue it either: after a
		// build that directory is mostly Bazel's own autoconfiguration repos and
		// nothing there tells those from the declared ones. Unlike every other
		// unresolved row in this section, no command fixes this one, so it does
		// not name one.
		return .unresolved("WORKSPACE dependencies are Starlark — nothing on disk lists them")
	}

	/// The modules a `MODULE.bazel.lock` says were **selected**, across the two
	/// layouts that are still written.
	///
	/// Bazel 7.0 and 7.1 wrote `moduleDepGraph`, keyed `name@version`, which is
	/// the resolved set outright. 7.2 dropped it for `registryFileHashes`, whose
	/// keys are the registry files consulted — and the trap is that *most of them
	/// are versions merely considered*. Minimal version selection fetches every
	/// candidate's `MODULE.bazel` to compare them and only fetches `source.json`
	/// for the one it settles on, so the keys ending `/source.json` are the
	/// selected set and the keys ending `/MODULE.bazel` are not. Reading the
	/// latter lists three versions of one module and calls them all dependencies.
	static func bazelSelectedModules(inLock top: [String: Any]) -> [BazelModule] {
		if let hashes = top["registryFileHashes"] as? [String: Any] {
			var found: [BazelModule] = []
			var seen: Set<String> = []
			for key in hashes.keys.sorted() where key.hasSuffix("/source.json") {
				guard let module = bazelModule(fromRegistryFile: key) else { continue }
				guard seen.insert(module.name).inserted else { continue }
				found.append(module)
			}
			if !found.isEmpty { return found }
		}

		if let graph = top["moduleDepGraph"] as? [String: Any] {
			var found: [BazelModule] = []
			for (key, value) in graph.sorted(by: { $0.key < $1.key }) {
				// The root module is keyed by the empty string: it is the project
				// itself, and the tree already has every file of it.
				guard !key.isEmpty else { continue }
				let entry = value as? [String: Any]
				let parts = key.split(separator: "@", maxSplits: 1)
				let name = (entry?["name"] as? String) ?? String(parts.first ?? "")
				guard !name.isEmpty else { continue }
				var version = (entry?["version"] as? String)
					?? (parts.count > 1 ? String(parts[1]) : nil)
				// `bazel_tools@_`: the underscore is how this layout writes "no
				// version", for a module that came from an override or from Bazel
				// itself rather than from a registry.
				if version == "_" || version?.isEmpty == true { version = nil }
				found.append(BazelModule(
					name: name, version: version,
					origin: (entry?["registry"] as? String) ?? ""
				))
			}
			return found
		}
		return []
	}

	/// `https://bcr.bazel.build/modules/rules_go/0.50.1/source.json` →
	/// `rules_go`, `0.50.1`, from `https://bcr.bazel.build`.
	///
	/// Split on the `modules` component rather than counted from either end: a
	/// registry can be a `file://` URL into somebody's repository, with any depth
	/// of path in front of it.
	static func bazelModule(fromRegistryFile key: String) -> BazelModule? {
		let parts = key.split(separator: "/", omittingEmptySubsequences: false)
		guard let modules = parts.firstIndex(of: "modules"), parts.count > modules + 2 else {
			return nil
		}
		let name = String(parts[modules + 1])
		let version = String(parts[modules + 2])
		guard !name.isEmpty else { return nil }
		return BazelModule(
			name: name, version: version.isEmpty ? nil : version,
			origin: parts[..<modules].joined(separator: "/")
		)
	}

	/// The `bazel_dep`s a `MODULE.bazel` declares, which are the direct ones.
	///
	/// A call at a time rather than a line at a time, because `buildifier` breaks
	/// a long one across lines and `name` and `version` then sit on different
	/// ones. `BazelBuild` already knows what starts a rule call and where the
	/// comments are; only `attribute` had to grow, to read a second key and to
	/// try every occurrence of it on the line rather than the first.
	static func bazelDeclaredModules(in text: String) -> [BazelModule] {
		var found: [BazelModule] = []
		let lines = text.components(separatedBy: "\n")

		var index = 0
		while index < lines.count {
			guard BazelBuild.ruleName(startingAt: lines[index]) == "bazel_dep" else {
				index += 1
				continue
			}

			var call = ""
			var depth = 0
			var cursor = index
			while cursor < lines.count, cursor - index < 40 {
				let current = BazelBuild.stripComment(lines[cursor])
				call += current + " "
				depth += current.filter { $0 == "(" }.count
				depth -= current.filter { $0 == ")" }.count
				if depth <= 0 { break }
				cursor += 1
			}

			// Keyword arguments only. `bazel_dep("rules_go", "0.50.1")` is legal
			// Starlark and is written by nobody — buildifier names both — and a
			// positional call read wrongly would put a version in the name column.
			if let name = BazelBuild.attribute("name", in: call) {
				found.append(BazelModule(
					name: name, version: BazelBuild.attribute("version", in: call), origin: ""
				))
			}
			index = max(index + 1, cursor + 1)
		}
		return found
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

	/// The external repositories on disk, **listed rather than computed**.
	///
	/// The output base is a directory under `/var/tmp/_bazel_<user>` named by an
	/// md5 of the workspace path — cargo's registry hash again, and not something
	/// to reproduce. What can be followed instead is the convenience symlink
	/// Bazel leaves in the workspace after a build: `bazel-<workspace>` points at
	/// `<output base>/execroot/<name>`, and `bazel-out` and `bazel-bin` point
	/// deeper into the same tree. So any of them will do — resolve one, walk up to
	/// the component named `execroot`, and its parent is the output base.
	///
	/// Empty before the first build, which is correct: the repositories have not
	/// been fetched, so the rows name their modules and offer nothing to open.
	static func bazelRepositoryDirectories(for root: URL) -> [URL] {
		let manager = FileManager.default
		let entries = (try? manager.contentsOfDirectory(
			at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		)) ?? []

		for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
		where entry.lastPathComponent.hasPrefix("bazel-") {
			let resolved = entry.resolvingSymlinksInPath()
			let components = resolved.pathComponents
			guard let execroot = components.firstIndex(of: "execroot") else { continue }

			var base = URL(fileURLWithPath: "/")
			for component in components[1..<execroot] { base.appendPathComponent(component) }
			let external = base.appendingPathComponent("external")
			let repositories = (try? manager.contentsOfDirectory(
				at: external, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
			)) ?? []
			guard !repositories.isEmpty else { continue }
			return repositories.sorted { $0.lastPathComponent < $1.lastPathComponent }
		}
		return []
	}

	/// A module's repository directory, matched rather than named.
	///
	/// **The separator between the module and its version changed between Bazel
	/// releases and is not one character to hard-code.** The same module has been
	/// `rules_go~0.50.1`, `rules_go+0.50.1`, `rules_go+` and plain `rules_go`
	/// across 6, 7.0, 7.2 and the `WORKSPACE` world, and a repository fetched by
	/// a module extension has yet another shape. So the directory is found by
	/// listing and matching a prefix, and the character after the name has to be
	/// one of the separators — otherwise `rules_go` would match `rules_google`'s
	/// directory and open a stranger's sources on the row.
	static func bazelSources(named name: String, in repositories: [URL]) -> URL? {
		for repository in repositories {
			let directory = repository.lastPathComponent
			if directory == name { return repository }
			guard directory.hasPrefix(name), directory.count > name.count else { continue }
			let separator = directory[directory.index(directory.startIndex, offsetBy: name.count)]
			if separator == "~" || separator == "+" { return repository }
		}
		return nil
	}

	static func gradleBuildText(at root: URL) -> String? {
		for name in ["build.gradle.kts", "build.gradle"] {
			if let text = try? String(
				contentsOf: root.appendingPathComponent(name), encoding: .utf8
			) { return text }
		}
		return nil
	}

	// MARK: - Conan

	/// A Conan reference, taken apart: `fmt/10.2.1@user/channel#revision%stamp`.
	struct ConanReference: Equatable {
		let name: String
		let version: String?
		/// `user/channel` where the reference has one. Empty otherwise, and that
		/// is deliberate — a lock file does not record which remote a package came
		/// from, and printing `conancenter` on every row would be a guess dressed
		/// as provenance.
		let origin: String
	}

	/// A Conan project's packages, from `conan.lock`.
	///
	/// **The recipe is never executed, and that is the whole decision.**
	/// `conanfile.py` is a Python program out of somebody's repository and
	/// `conan graph info` evaluates it; `ConanProject` already refuses to run it
	/// to fill in a menu, and filling in a tree row is not a better reason than
	/// that was. Nor is the recipe *scraped* for `self.requires(…)`: requirements
	/// are routinely conditional on options and settings, so a scraped list would
	/// be complete for some projects and quietly short for others, with nothing on
	/// the row able to say which — the failure this section exists to prevent,
	/// wearing a list of packages as a disguise.
	static func readConanPackages(at root: URL) -> DependencySet.Contents {
		let lock = root.appendingPathComponent("conan.lock")
		guard let data = try? Data(contentsOf: lock) else {
			// `conan install` does not write a lock in Conan 2; this is the command
			// that does.
			return .unresolved("no conan.lock — run conan lock create .")
		}
		guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return .unresolved("conan.lock could not be read")
		}

		// **Guarded on the keys, not on the file parsing.** A Conan 1 lock is also
		// JSON and has none of these — it keys everything under `graph_lock` — so a
		// reader that took "parsed, no requires" for an answer would draw `no
		// dependencies` over a project with forty of them. That is the exact lie
		// this section was built to stop, so the two are told apart explicitly and
		// anything that is neither says it could not be read.
		let lists = ["requires", "build_requires", "python_requires", "test_requires", "config_requires"]
			.compactMap { top[$0] as? [Any] }
		guard !lists.isEmpty else {
			if top["graph_lock"] != nil || top["profile_host"] != nil {
				return .unresolved("conan.lock is a Conan 1 lock — run conan lock create .")
			}
			return .unresolved("conan.lock could not be read")
		}

		let cache = conanPackageDirectories()
		var seen: Set<String> = []
		let packages = lists.flatMap { $0 }.compactMap { entry -> ExternalDependency? in
			guard let reference = entry as? String,
			      let parsed = parseConanReference(reference)
			else { return nil }
			// The same package can be a `requires` and a `build_requires`, and the
			// section is a list of what is depended on rather than of how.
			guard seen.insert(parsed.name).inserted else { return nil }
			return ExternalDependency(
				name: parsed.name, version: parsed.version, origin: parsed.origin,
				localPath: conanSources(named: parsed.name, in: cache)
			)
		}
		return byName(packages)
	}

	/// `fmt/10.2.1@user/channel#recipe-revision%timestamp` → the three parts a
	/// row shows.
	///
	/// Peeled from the right, because each piece is optional and only the
	/// `name/version` at the front is always there.
	static func parseConanReference(_ reference: String) -> ConanReference? {
		var text = Substring(reference)
		if let stamp = text.firstIndex(of: "%") { text = text[..<stamp] }
		if let revision = text.firstIndex(of: "#") { text = text[..<revision] }

		var origin = ""
		if let at = text.firstIndex(of: "@") {
			origin = String(text[text.index(after: at)...])
			text = text[..<at]
		}

		let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
		let name = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty else { return nil }
		let version = parts.count > 1 ? String(parts[1]) : ""
		return ConanReference(name: name, version: version.isEmpty ? nil : version, origin: origin)
	}

	/// `$CONAN_HOME`, or `~/.conan2`.
	///
	/// The same shape as `cargoHome()` and for the same reasons: the tool's own
	/// variable first, then the documented default, and never `conan config home`
	/// to ask — a subprocess per project on open, for an answer that is wrong on
	/// no machine this is likely to meet.
	static func conanHome() -> URL {
		let environment = ProcessInfo.processInfo.environment
		if let path = environment["CONAN_HOME"], !path.isEmpty {
			return URL(fileURLWithPath: path)
		}
		return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".conan2")
	}

	/// The cache folders a package's files could be in, **listed rather than
	/// computed**.
	///
	/// The folder is named for a hash of the whole resolved package — recipe
	/// revision, settings, options, the lot — so nothing outside Conan can build
	/// the path from a name and a version. Both halves of the cache are listed:
	/// `p/b/<name><hash>` holds what was built here, `p/<name><hash>` what was
	/// downloaded and the recipe. Built first, because that is the copy whose
	/// headers a local build compiled against.
	static func conanPackageDirectories() -> [URL] {
		let home = conanHome()
		let manager = FileManager.default
		return [home.appendingPathComponent("p/b"), home.appendingPathComponent("p")]
			.flatMap { directory in
				((try? manager.contentsOfDirectory(
					at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
				)) ?? [])
					.sorted { $0.lastPathComponent < $1.lastPathComponent }
			}
	}

	/// A package's own files in the cache, or nil when nothing fetched it.
	///
	/// **The match is strict about what follows the name**, because a prefix alone
	/// would give `fmt` the folder belonging to `fmtlog` and open another
	/// package's headers under a row saying `fmt`. What follows a name in these
	/// folders is a hash and nothing else, so the remainder has to be non-empty
	/// and entirely hexadecimal.
	///
	/// `p` inside the folder is the package — the `include` and `lib` a build
	/// consumes. `e` is the exported recipe, which is the honest fallback when
	/// only the recipe was cached: it is not the library, but it is this package's
	/// files rather than a guess at somebody else's.
	static func conanSources(named name: String, in directories: [URL]) -> URL? {
		let manager = FileManager.default
		for directory in directories {
			let folder = directory.lastPathComponent
			guard folder.hasPrefix(name) else { continue }
			let remainder = folder.dropFirst(name.count)
			guard !remainder.isEmpty, remainder.allSatisfy(\.isHexDigit) else { continue }

			for part in ["p", "e"] {
				let inside = directory.appendingPathComponent(part)
				if manager.fileExists(atPath: inside.path) { return inside }
			}
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

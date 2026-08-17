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
		case .swiftPackage, .goModule, .cargo, .npm: return nil
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
			// npm prefers `npm-shrinkwrap.json` to `package-lock.json` and it is
			// the same format byte for byte, so a project that publishes one
			// resolves through it — and writing one has to reload the section.
			"npm-shrinkwrap.json",
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
		case .npm: contents = readNpm(at: root)
		case .maven, .gradle, .bazel, .conan: contents = .notRead
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
	/// All four are named here and only npm's two are read, which is item 514's
	/// decision and 0525's inheritance. `package.json` is the marker for all
	/// three tools, so a pnpm or a yarn project reaches this reader whatever it
	/// does — and the row it would otherwise draw says `run npm install`, which
	/// is an instruction to install a second, conflicting tree over a project
	/// that is already installed. Naming the file that *did* resolve it costs one
	/// `fileExists` and says something true.
	static let npmLockFiles: [(name: String, tool: String)] = [
		("npm-shrinkwrap.json", "npm"),
		("package-lock.json", "npm"),
		("pnpm-lock.yaml", "pnpm"),
		("yarn.lock", "yarn"),
	]

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
		guard let lock = npmLockFiles.first(where: {
			manager.fileExists(atPath: root.appendingPathComponent($0.name).path)
		}) else {
			if let workspace = npmWorkspaceAbove(root) {
				return .unresolved("resolved in the workspace at \(workspace.lastPathComponent)")
			}
			return .unresolved("no package-lock.json — run npm install")
		}
		guard lock.tool == "npm" else {
			// The kind is read; this one root is resolved by a tool 0525 will
			// teach. Said as a sentence rather than as `.notRead`, because
			// `.notRead` reads the item number off `DependencyKind`, and the kind
			// — which is keyed off `package.json` — is the same one being read
			// three lines up.
			return .unresolved("resolved by \(lock.tool) — \(lock.name) not read yet (0525)")
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
}

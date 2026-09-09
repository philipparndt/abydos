import Foundation

/// Gradle and Conan, which are read from text rather than asked.
///
/// Neither tool is run: `conan graph info` evaluates a Python program out of
/// somebody's repository, and a Gradle invocation starts a daemon. Reading the
/// build file is less complete and is the only version of this that cannot
/// surprise somebody.
extension ExternalDependencies {
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

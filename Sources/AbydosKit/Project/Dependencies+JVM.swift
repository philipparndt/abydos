import Foundation

/// Maven, and Bazel beside it.
///
/// Both answer partially and both say so: a Maven list read from `pom.xml`
/// alone has not resolved anything transitive, and a Bazel `WORKSPACE` cannot
/// be read as text at all. What a partial list says about itself is written
/// once, above them.
extension ExternalDependencies {
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
}

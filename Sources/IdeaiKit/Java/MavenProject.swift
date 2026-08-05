import Foundation

/// A `pom.xml`, read for what it says a project is and how it is built.
///
/// The same job `Makefile` does for make: enough of the file to offer what it
/// can run and to jump around inside it, and nothing more. Maven itself is the
/// authority on everything else — this never resolves a dependency, never
/// inherits from a parent that is not in the checkout, and never pretends to
/// know an effective POM.
public struct MavenProject: Equatable, Sendable {
	/// Something worth running, as it would be typed.
	public struct Goal: Equatable, Sendable, Identifiable {
		public let name: String
		/// What it does, in the words somebody would use for it.
		public let summary: String

		public var id: String { name }

		public init(name: String, summary: String) {
			self.name = name
			self.summary = summary
		}
	}

	public let path: URL
	public let groupId: String?
	public let artifactId: String
	public let version: String?
	/// `jar`, `war`, or `pom` for a module that only aggregates others.
	public let packaging: String
	/// The human name, when the file gives one.
	public let name: String?
	/// Child modules, as the directory names the file lists.
	public let modules: [String]
	public let properties: [String: String]
	/// Plugin artefact ids: `spring-boot-maven-plugin`, `exec-maven-plugin`.
	public let plugins: [String]
	/// Dependency artefact ids, for the outline.
	public let dependencies: [String]
	/// The class the build already names as the one to start, if any.
	public let mainClass: String?

	public var directory: URL { path.deletingLastPathComponent() }

	/// A module whose whole job is to list other modules.
	public var isAggregator: Bool { packaging == "pom" }

	public var isSpringBoot: Bool {
		plugins.contains("spring-boot-maven-plugin")
	}

	public init(
		path: URL,
		groupId: String? = nil,
		artifactId: String,
		version: String? = nil,
		packaging: String = "jar",
		name: String? = nil,
		modules: [String] = [],
		properties: [String: String] = [:],
		plugins: [String] = [],
		dependencies: [String] = [],
		mainClass: String? = nil
	) {
		self.path = path
		self.groupId = groupId
		self.artifactId = artifactId
		self.version = version
		self.packaging = packaging
		self.name = name
		self.modules = modules
		self.properties = properties
		self.plugins = plugins
		self.dependencies = dependencies
		self.mainClass = mainClass
	}

	// MARK: - Reading

	public static func isPom(_ url: URL) -> Bool {
		url.lastPathComponent == "pom.xml"
	}

	public static func read(at url: URL) -> MavenProject? {
		guard let data = try? Data(contentsOf: url) else { return nil }
		return parse(data, path: url)
	}

	/// Reads a POM.
	///
	/// `XMLDocument` rather than a hand-written scan, because XML is a format
	/// with a parser in the standard library and half-parsing it with string
	/// matching is how a comment containing `<module>` ends up as a module.
	///
	/// Namespaces are ignored on purpose: every POM declares the same one, and
	/// matching on the local name means a file that omits it — which Maven
	/// accepts — is read the same way.
	public static func parse(_ data: Data, path: URL) -> MavenProject? {
		guard let document = try? XMLDocument(data: data),
		      let root = document.rootElement(),
		      root.localName == "project"
		else { return nil }

		guard let artifactId = root.child("artifactId")?.text else { return nil }
		let parent = root.child("parent")

		var properties: [String: String] = [:]
		for element in root.child("properties")?.elements() ?? [] {
			guard let name = element.localName else { continue }
			properties[name] = element.stringValue?.trimmed ?? ""
		}

		let modules = (root.child("modules")?.children(named: "module") ?? [])
			.compactMap(\.text)

		let plugins = pluginArtefacts(in: root)
		let dependencies = (root.child("dependencies")?.children(named: "dependency") ?? [])
			.compactMap { $0.child("artifactId")?.text }

		return MavenProject(
			path: path,
			// A module usually states neither its group nor its version and takes
			// both from its parent, which is the file beside it.
			groupId: root.child("groupId")?.text ?? parent?.child("groupId")?.text,
			artifactId: artifactId,
			version: root.child("version")?.text ?? parent?.child("version")?.text,
			packaging: root.child("packaging")?.text ?? "jar",
			name: root.child("name")?.text,
			modules: modules,
			properties: properties,
			plugins: plugins,
			dependencies: dependencies,
			mainClass: mainClass(in: root, properties: properties)
		)
	}

	/// Every plugin the file configures, wherever it configures it.
	private static func pluginArtefacts(in root: XMLElement) -> [String] {
		var found: [String] = []
		for build in [root.child("build"), root.child("build")?.child("pluginManagement")].compactMap({ $0 }) {
			for plugin in build.child("plugins")?.children(named: "plugin") ?? [] {
				if let artefact = plugin.child("artifactId")?.text { found.append(artefact) }
			}
		}
		var seen = Set<String>()
		return found.filter { seen.insert($0).inserted }
	}

	/// The class the build says to start.
	///
	/// Three spellings, all common: the exec plugin's configuration, Spring
	/// Boot's `start-class` property, and a plain `mainClass` property that a
	/// project sets for its own use.
	private static func mainClass(in root: XMLElement, properties: [String: String]) -> String? {
		for build in [root.child("build"), root.child("build")?.child("pluginManagement")].compactMap({ $0 }) {
			for plugin in build.child("plugins")?.children(named: "plugin") ?? [] {
				if let main = plugin.child("configuration")?.child("mainClass")?.text { return main }
			}
		}
		return properties["start-class"] ?? properties["mainClass"] ?? properties["main.class"]
	}

	/// Every `pom.xml` in a project, the root's first.
	///
	/// A Maven repository is nearly always a tree of them, and the aggregator at
	/// the top is the one a build runs in — but the modules are what somebody
	/// wants a play button beside.
	public static func find(in root: URL, maxDepth: Int = 3) -> [URL] {
		let manager = FileManager.default
		var found: [URL] = []

		func scan(_ directory: URL, depth: Int) {
			let candidate = directory.appendingPathComponent("pom.xml")
			if manager.fileExists(atPath: candidate.path) { found.append(candidate) }
			guard depth < maxDepth else { return }

			let contents = (try? manager.contentsOfDirectory(
				at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
			)) ?? []
			for entry in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
				guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
				      !JavaTooling.skipped.contains(entry.lastPathComponent)
				else { continue }
				scan(entry, depth: depth + 1)
			}
		}
		scan(root, depth: 0)
		return found
	}

	// MARK: - Running it

	/// The Maven to run: the project's own wrapper when it has one.
	///
	/// A project that ships `mvnw` has pinned its Maven version, and running a
	/// different one is how a build that works everywhere else fails here. The
	/// wrapper is looked for beside the module and then upwards, because a
	/// multi-module build carries one wrapper at the top.
	public static func executable(for directory: URL, root: URL) -> String {
		let manager = FileManager.default
		var cursor = directory
		let stop = FilePath.canonical(root)

		while true {
			let wrapper = cursor.appendingPathComponent("mvnw")
			if manager.isExecutableFile(atPath: wrapper.path) { return wrapper.path }
			if FilePath.canonical(cursor) == stop { break }
			let parent = cursor.deletingLastPathComponent()
			if parent.path == cursor.path { break }
			cursor = parent
		}
		return "mvn"
	}

	/// The goals worth offering for this module.
	///
	/// Short on purpose. Maven has a hundred goals and a lifecycle nobody
	/// remembers the order of; what a person presses run for is one of these.
	public var goals: [Goal] {
		var found: [Goal] = []
		if isSpringBoot {
			found.append(Goal(name: "spring-boot:run", summary: "run the application"))
		}
		if !isAggregator {
			found.append(Goal(name: "test", summary: "run the tests"))
			found.append(Goal(name: "package", summary: "build the artefact"))
			found.append(Goal(name: "verify", summary: "build it and run every check"))
		} else {
			found.append(Goal(name: "test", summary: "run every module's tests"))
			found.append(Goal(name: "package", summary: "build every module"))
		}
		found.append(Goal(name: "clean", summary: "delete target/"))
		return found
	}

	/// The jar this module builds, by the name Maven gives it.
	///
	/// `finalName` when the build sets one, and otherwise Maven's own
	/// `artifactId-version.jar`. Used to find what to send to a pod, where
	/// guessing wrong means pushing a file that is not there.
	public var artefactName: String {
		let version = self.version.map { "-\($0)" } ?? ""
		return "\(artifactId)\(version).jar"
	}

	/// Where that jar lands.
	public var artefactPath: URL {
		directory.appendingPathComponent("target/\(artefactName)")
	}

	// MARK: - The outline

	/// What ⇧⌘O shows for a POM.
	///
	/// A POM has no language server and the grammar it borrows is HTML's, which
	/// knows about tags and nothing about Maven. Its modules, plugins and
	/// dependencies are the things somebody navigates to, so they are what this
	/// lists.
	public static func symbols(at url: URL) -> [LSPSymbol] {
		guard let project = read(at: url),
		      let text = try? String(contentsOf: url, encoding: .utf8)
		else { return [] }
		return symbols(of: project, in: text, at: url)
	}

	static func symbols(of project: MavenProject, in text: String, at url: URL) -> [LSPSymbol] {
		let lines = text.components(separatedBy: "\n")

		func symbol(_ name: String, kind: LSPSymbol.Kind, matching needle: String, container: String?) -> LSPSymbol {
			let line = lines.firstIndex { $0.contains(needle) } ?? 0
			let position = LSPPosition(line: line, character: 0)
			return LSPSymbol(
				name: name,
				kind: kind,
				location: LSPLocation(
					uri: url.absoluteString,
					range: LSPRange(start: position, end: position)
				),
				container: container
			)
		}

		var found: [LSPSymbol] = [
			symbol(
				project.artifactId,
				kind: .module,
				matching: "<artifactId>\(project.artifactId)</artifactId>",
				container: project.name
			),
		]
		found += project.modules.map {
			symbol($0, kind: .module, matching: "<module>\($0)</module>", container: "module")
		}
		found += project.properties.keys.sorted().map {
			symbol($0, kind: .constant, matching: "<\($0)>", container: "property")
		}
		found += project.plugins.map {
			symbol($0, kind: .function, matching: "<artifactId>\($0)</artifactId>", container: "plugin")
		}
		found += project.dependencies.map {
			symbol($0, kind: .property, matching: "<artifactId>\($0)</artifactId>", container: "dependency")
		}
		return found
	}
}

/// The three lines of XML walking a POM needs, said once.
///
/// `elements(forName:)` matches the qualified name, so a document that uses a
/// namespace prefix — rare in a POM but legal — would answer nothing. Matching
/// on the local name is what was meant every time.
private extension XMLElement {
	func child(_ name: String) -> XMLElement? {
		children(named: name).first
	}

	func children(named name: String) -> [XMLElement] {
		(children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name }
	}

	func elements() -> [XMLElement] {
		(children ?? []).compactMap { $0 as? XMLElement }
	}

	/// The text inside, trimmed, or nil when there is none.
	var text: String? {
		guard let value = stringValue?.trimmed, !value.isEmpty else { return nil }
		return value
	}
}

private extension String {
	var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

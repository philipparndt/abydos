import Foundation

/// A Gradle build, read for what it can run.
///
/// Read as text, not evaluated. A build file is a program — in Groovy or in
/// Kotlin — and the only thing that truly knows what it defines is Gradle
/// itself, which takes seconds to answer and needs a daemon running. What is
/// wanted here is the list a person already has in their head: the tasks this
/// file declares and the plugins that bring the rest. Everything found is
/// something the file says in one line; nothing is inferred from control flow.
public struct GradleBuild: Equatable, Sendable {
	/// A task the build file declares itself.
	public struct Task: Equatable, Sendable, Identifiable {
		public let name: String
		/// 1-based line it is declared on, for a play button beside it.
		public let line: Int
		/// The `group` or `description` when the declaration gives one.
		public let summary: String

		public var id: String { name }

		public init(name: String, line: Int, summary: String = "") {
			self.name = name
			self.line = line
			self.summary = summary
		}
	}

	public let path: URL
	/// Plugin ids: `application`, `java`, `org.springframework.boot`.
	public let plugins: [String]
	public let tasks: [Task]
	/// The class the `application` block names, if it names one.
	public let mainClass: String?
	/// Sub-projects, from `settings.gradle` — empty for a build file.
	public let projects: [String]

	public var directory: URL { path.deletingLastPathComponent() }

	public var isApplication: Bool { plugins.contains("application") }

	public var isSpringBoot: Bool {
		plugins.contains { $0.hasPrefix("org.springframework.boot") }
	}

	public var isKotlinDSL: Bool { path.pathExtension == "kts" }

	public init(
		path: URL,
		plugins: [String] = [],
		tasks: [Task] = [],
		mainClass: String? = nil,
		projects: [String] = []
	) {
		self.path = path
		self.plugins = plugins
		self.tasks = tasks
		self.mainClass = mainClass
		self.projects = projects
	}

	// MARK: - Reading

	public static func isBuildFile(_ url: URL) -> Bool {
		let name = url.lastPathComponent
		return name == "build.gradle" || name == "build.gradle.kts"
			|| name == "settings.gradle" || name == "settings.gradle.kts"
	}

	public static func read(at url: URL) -> GradleBuild? {
		guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
		return parse(text, path: url)
	}

	/// Reads a build file, or a settings file — the two are told apart by their
	/// names, and a settings file's only interesting content is its includes.
	public static func parse(_ text: String, path: URL) -> GradleBuild {
		let lines = text.components(separatedBy: "\n")
		var plugins: [String] = []
		var tasks: [Task] = []
		var projects: [String] = []
		var mainClass: String?
		var inPluginsBlock = false
		/// The task whose block is open, so a `description` on one of the next
		/// lines belongs to it. Nearly no build writes the description beside
		/// the name.
		var describing: Int?

		for (index, raw) in lines.enumerated() {
			let line = raw.trimmingCharacters(in: .whitespaces)
			guard !line.hasPrefix("//"), !line.hasPrefix("*"), !line.hasPrefix("/*") else { continue }

			// plugins { id 'java'; id("org.springframework.boot") version "3.2.0" }
			if line.hasPrefix("plugins") && line.contains("{") { inPluginsBlock = true }
			if inPluginsBlock {
				if let id = pluginID(in: line) { plugins.append(id) }
				if line.hasPrefix("}") { inPluginsBlock = false }
			}
			// The older spelling, which plenty of builds still use.
			if line.hasPrefix("apply plugin:") {
				if let id = quoted(after: "apply plugin:", in: line) { plugins.append(id) }
			}

			if let task = task(in: line, at: index + 1) {
				tasks.append(task)
				describing = line.hasSuffix("{") ? tasks.count - 1 : nil
			} else if let open = describing {
				let summary = description(in: line)
				if line.hasPrefix("}") {
					describing = nil
				} else if !summary.isEmpty {
					tasks[open] = Task(name: tasks[open].name, line: tasks[open].line, summary: summary)
				}
			}
			if let main = mainClassName(in: line) { mainClass = main }
			projects += includes(in: line)
		}

		var seenPlugins = Set<String>()
		var seenTasks = Set<String>()
		return GradleBuild(
			path: path,
			plugins: plugins.filter { seenPlugins.insert($0).inserted },
			tasks: tasks.filter { seenTasks.insert($0.name).inserted },
			mainClass: mainClass,
			projects: projects
		)
	}

	/// `id 'application'`, `id("java")`, and either with a version after it.
	static func pluginID(in line: String) -> String? {
		guard line.hasPrefix("id ") || line.hasPrefix("id(") else { return nil }
		return firstQuoted(in: line)
	}

	/// A task declaration, in any of the four spellings in circulation.
	///
	/// `task foo {`, `task foo(type: Copy)`, `tasks.register("foo")` and
	/// `tasks.register<Copy>("foo")` — the Groovy DSL's two and the Kotlin
	/// DSL's two.
	static func task(in line: String, at lineNumber: Int) -> Task? {
		if line.hasPrefix("tasks.register") || line.hasPrefix("tasks.create") {
			guard let name = firstQuoted(in: line) else { return nil }
			return Task(name: name, line: lineNumber, summary: description(in: line))
		}
		guard line.hasPrefix("task ") else { return nil }
		let rest = line.dropFirst("task ".count).trimmingCharacters(in: .whitespaces)
		let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
		guard !name.isEmpty else { return nil }
		return Task(name: String(name), line: lineNumber, summary: description(in: line))
	}

	/// The three ways a build names the class to start.
	static func mainClassName(in line: String) -> String? {
		for prefix in ["mainClass.set(", "mainClass =", "mainClass=", "mainClassName =", "mainClassName="] {
			guard line.hasPrefix(prefix) else { continue }
			return firstQuoted(in: line)
		}
		return nil
	}

	/// `include 'a', 'b'` or `include(":a", ":b")`, as a settings file writes it.
	static func includes(in line: String) -> [String] {
		guard line.hasPrefix("include ") || line.hasPrefix("include(") else { return [] }
		return quotedValues(in: line).map { name in
			// Gradle names a sub-project with a leading colon and separates
			// nesting with more of them; the directory is the same path with
			// slashes.
			name.hasPrefix(":") ? String(name.dropFirst()) : name
		}
	}

	static func description(in line: String) -> String {
		guard let range = line.range(of: "description") else { return "" }
		return firstQuoted(in: String(line[range.lowerBound...])) ?? ""
	}

	static func quoted(after keyword: String, in line: String) -> String? {
		guard let range = line.range(of: keyword) else { return nil }
		return firstQuoted(in: String(line[range.upperBound...]))
	}

	static func firstQuoted(in line: String) -> String? {
		quotedValues(in: line).first
	}

	/// Every quoted string on a line, single or double quoted as both DSLs
	/// allow.
	static func quotedValues(in line: String) -> [String] {
		var found: [String] = []
		var current = ""
		var quote: Character?

		for character in line {
			if let active = quote {
				if character == active {
					if !current.isEmpty { found.append(current) }
					current = ""
					quote = nil
				} else {
					current.append(character)
				}
				continue
			}
			if character == "\"" || character == "'" { quote = character }
		}
		return found
	}

	// MARK: - Finding it

	/// Every Gradle build file in a project, the root's first.
	public static func find(in root: URL, maxDepth: Int = 3) -> [URL] {
		let manager = FileManager.default
		var found: [URL] = []

		func scan(_ directory: URL, depth: Int) {
			for name in ["build.gradle.kts", "build.gradle"] {
				let candidate = directory.appendingPathComponent(name)
				if manager.fileExists(atPath: candidate.path) {
					found.append(candidate)
					// A directory has one build file; a project with both would be
					// a mistake, and offering the same tasks twice compounds it.
					break
				}
			}
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

	/// The settings file of a Gradle build, which is what makes a directory the
	/// root of one rather than a module inside it.
	public static func settingsFile(in directory: URL) -> URL? {
		for name in ["settings.gradle.kts", "settings.gradle"] {
			let url = directory.appendingPathComponent(name)
			if FileManager.default.fileExists(atPath: url.path) { return url }
		}
		return nil
	}

	// MARK: - Running it

	/// The Gradle to run: the wrapper, nearly always.
	///
	/// More strongly than with Maven — a Gradle build is written against one
	/// Gradle version and commonly will not evaluate under another, which is
	/// the whole reason the wrapper exists and is committed.
	public static func executable(for directory: URL, root: URL) -> String {
		let manager = FileManager.default
		var cursor = directory
		let stop = FilePath.canonical(root)

		while true {
			let wrapper = cursor.appendingPathComponent("gradlew")
			if manager.isExecutableFile(atPath: wrapper.path) { return wrapper.path }
			if FilePath.canonical(cursor) == stop { break }
			let parent = cursor.deletingLastPathComponent()
			if parent.path == cursor.path { break }
			cursor = parent
		}
		return "gradle"
	}

	/// The tasks worth offering, the build's own first.
	///
	/// The standard ones are added rather than discovered: `test` and `build`
	/// exist in every Java build through the plugin, and asking Gradle for the
	/// full list means starting a daemon and waiting.
	public var runnableTasks: [Task] {
		var found = tasks
		var names = Set(found.map(\.name))

		func add(_ name: String, _ summary: String) {
			guard names.insert(name).inserted else { return }
			found.append(Task(name: name, line: 0, summary: summary))
		}

		if isSpringBoot { add("bootRun", "run the application") }
		if isApplication { add("run", "run the application") }
		add("test", "run the tests")
		add("build", "compile, test and package")
		if isSpringBoot {
			add("bootJar", "build the executable jar")
		} else {
			add("assemble", "build the artefacts")
		}
		return found
	}

	// MARK: - The outline

	/// What ⇧⌘O shows for a build file.
	///
	/// The tasks it declares, the plugins it applies and the projects a
	/// settings file includes — which is everything in the file somebody
	/// navigates *to*. Groovy has a grammar here and Kotlin has one, but
	/// neither ships a tags query, so without this a build file is the one
	/// file in a Gradle project with no outline at all.
	public static func symbols(at url: URL) -> [LSPSymbol] {
		guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
		return symbols(of: parse(text, path: url), in: text, at: url)
	}

	static func symbols(of build: GradleBuild, in text: String, at url: URL) -> [LSPSymbol] {
		let lines = text.components(separatedBy: "\n")

		func symbol(_ name: String, kind: LSPSymbol.Kind, line: Int, container: String?) -> LSPSymbol {
			let position = LSPPosition(line: max(0, line), character: 0)
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

		func lineHolding(_ needle: String) -> Int {
			lines.firstIndex { $0.contains(needle) } ?? 0
		}

		var found = build.tasks.map {
			// The parser's lines are 1-based and a position's are not.
			symbol($0.name, kind: .function, line: $0.line - 1, container: $0.summary.isEmpty ? "task" : $0.summary)
		}
		found += build.plugins.map {
			symbol($0, kind: .module, line: lineHolding($0), container: "plugin")
		}
		found += build.projects.map {
			symbol($0, kind: .module, line: lineHolding($0), container: "project")
		}
		return found
	}

	/// Where a Gradle build leaves its jar.
	///
	/// A directory rather than a file: the name depends on the archive
	/// settings, the version and whether Spring Boot repackaged it, and reading
	/// the directory afterwards is both simpler and right more often than
	/// predicting the name.
	public var artefactDirectory: URL {
		directory.appendingPathComponent("build/libs")
	}
}

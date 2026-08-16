import Foundation

/// Something the user can run.
public struct RunConfiguration: Equatable, Sendable, Identifiable {
	/// Where the configuration came from, which is what the UI groups by.
	public enum Source: String, Sendable {
		/// `.idea/runConfigurations/*.xml`, or the RunManager in workspace.xml.
		case intelliJ
		/// `.vscode/launch.json`.
		case vscode
		/// A target in a Makefile.
		case make
		/// A `main` package found by scanning for go.mod.
		case goModule
		/// A goal of a `pom.xml`.
		case maven
		/// A task of a Gradle build.
		case gradle
		/// A class with a `main` method, run through whichever build tool the
		/// project uses.
		case javaMain
		/// A scheme of an Xcode project or workspace, run on a destination
		/// chosen beside it.
		case xcodeScheme
		/// An executable product of a `Package.swift`, or that package's tests.
		case swiftPackage
		/// A `*_binary` or `*_test` rule in a Bazel `BUILD` file.
		case bazel
		/// What a Conan package can be asked to do: install, build, create.
		case conan
	}

	public let name: String
	public let source: Source
	public let executable: String
	public let arguments: [String]
	/// Absolute path the command runs in.
	public let workingDirectory: String
	public let environment: [String: String]
	/// File and 1-based line this configuration belongs to, when it has one.
	/// Used to put a play button beside it.
	public let file: String?
	public let line: Int?
	/// The class to start, for a Java configuration.
	///
	/// The command line runs Maven or Gradle, and a debugger cannot be attached
	/// to a build tool — it needs the class, the classpath and a JVM of its own.
	/// This is what tells the debugger which class was meant.
	public let mainClass: String?

	/// The scheme this runs, and the project it belongs to.
	///
	/// Kept rather than folded into the command line, because the command
	/// depends on something this does not know yet: where it is going to run.
	/// A scheme is one entry whichever destination is chosen, and the
	/// destination is answered when there is somebody to ask.
	public let xcode: XcodeTarget?

	public var id: String { "\(source.rawValue):\(name):\(workingDirectory)" }

	/// Whether the native debugger can start on this.
	///
	/// Delve debugs a Go package, so anything that is not one — a make target
	/// wrapping a build, a launch.json entry for another language — has nothing
	/// to hand it. A Java configuration is debuggable when it says which class
	/// it starts, whatever the command line runs to get there.
	public var isDebuggable: Bool {
		if source == .javaMain, mainClass != nil { return true }
		return executable == "go" && arguments.first == "run"
	}

	/// The command as a shell would show it, for the terminal and for tooltips.
	public var commandLine: String {
		([executable] + arguments).map(Self.quote).joined(separator: " ")
	}

	static func quote(_ token: String) -> String {
		guard token.contains(" ") || token.contains("\"") else { return token }
		return "\"\(token.replacingOccurrences(of: "\"", with: "\\\""))\""
	}

	public init(
		name: String,
		source: Source,
		executable: String,
		arguments: [String] = [],
		workingDirectory: String,
		environment: [String: String] = [:],
		file: String? = nil,
		line: Int? = nil,
		mainClass: String? = nil,
		xcode: XcodeTarget? = nil
	) {
		self.mainClass = mainClass
		self.xcode = xcode
		self.name = name
		self.source = source
		self.executable = executable
		self.arguments = arguments
		self.workingDirectory = workingDirectory
		self.environment = environment
		self.file = file
		self.line = line
	}
}

/// Finds the things a project can run.
///
/// Nothing here assumes the project root *is* the module. A Go repository
/// commonly keeps `go.mod` in a subdirectory with the deployment files beside
/// it, and refusing to run anything because the root has no go.mod — which is
/// what the Go commands used to do — is wrong for a large share of real
/// projects.
public enum RunConfigurationDiscovery {
	public static func canonicalPath(_ url: URL) -> String {
		FilePath.canonical(url)
	}

	/// How deep to look for modules and makefiles.
	public static let searchDepth = 3

	/// Directories not worth walking into.
	static let skipped: Set<String> = [
		"node_modules", "vendor", "dist", "build", "target", ".build", "Pods",
	]

	/// The files `discover(in:)` reads, by name.
	///
	/// Kept beside the finders that read them so the two cannot drift: a name
	/// added to one of those and not to this list means a build file whose
	/// arrival is not noticed until the project is reopened.
	static let definingFileNames: Set<String> = [
		"Makefile", "makefile", "GNUmakefile",
		"go.mod",
		"pom.xml",
		"build.gradle", "build.gradle.kts",
		"BUILD", "BUILD.bazel", "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel", "WORKSPACE.bzlmod",
		"conanfile.py", "conanfile.txt",
		// By this exact name, and deliberately not by the `swift` extension:
		// an extension here would put every save in every Swift project
		// through the whole search, which is the fault 0446 measured.
		"Package.swift",
		"launch.json",
		"workspace.xml",
	]

	/// The extensions of files that can hold an entry point.
	static let definingExtensions: Set<String> = ["java", "kt", "xcodeproj", "xcworkspace"]

	/// Whether writing this path could change what the project can run.
	///
	/// The point of asking. `discover(in:)` walks every Java and Kotlin source
	/// in the project looking for `main` methods, and 0446 measured what that
	/// costs when it is done once per filesystem event: opening the Eclipse
	/// Platform corpus spent **668 seconds of processor time in ninety**, because
	/// jdtls importing a Tycho reactor writes `.project`, `.classpath` and
	/// `.settings` into a thousand bundles and every one of those writes asked
	/// the same question again.
	///
	/// None of those files is one of these. A `main` method appears when a
	/// *source file* changes or when a build file arrives — not when a language
	/// server writes Eclipse metadata beside them. So the scan is not merely
	/// coalesced but skipped, which is the difference between a fault that is
	/// survivable and one that is absent.
	///
	/// Deliberately generous in the other direction: anything under `.idea` or
	/// `.vscode` counts, because IDEA rewrites `workspace.xml` under several
	/// names and a run configuration that fails to appear is a worse failure
	/// than a scan that was not needed.
	public static func couldDefineConfiguration(_ url: URL) -> Bool {
		let name = url.lastPathComponent
		if definingFileNames.contains(name) { return true }
		if definingExtensions.contains(url.pathExtension) { return true }

		// A component rather than a suffix: the file inside an `.xcodeproj` that
		// changed is `project.pbxproj`, and the schemes live further down still.
		for component in url.pathComponents {
			if component == ".idea" || component == ".vscode" { return true }
			if component.hasSuffix(".xcodeproj") || component.hasSuffix(".xcworkspace") { return true }
		}
		return false
	}

	/// Whether a batch from the watcher is worth rescanning the project for.
	///
	/// Here rather than in the window controller so that a test can hold it: the
	/// engine is where the rule about what a run configuration is made of
	/// belongs, and the window's job is only to obey the answer.
	public static func deservesRescan(after change: FileSystemChange) -> Bool {
		// A batch the kernel refused to describe file by file could be anything,
		// including a checkout that brought a new module in. Those are rare, and
		// a scan too many is only slow; a scan too few is a play button that
		// never appears.
		guard change.namesEveryPath else { return true }
		return change.paths.contains(where: couldDefineConfiguration)
	}

	/// Whether a configuration is a test run.
	///
	/// Tests are run constantly and from anywhere in a file, so they must
	/// never become saved configurations: one per test function would fill a
	/// project with hundreds of them, and none of them worth keeping. A test
	/// is run, not configured.
	public static func isTest(_ configuration: RunConfiguration) -> Bool {
		let arguments = configuration.arguments
		if arguments.contains("test") || arguments.contains("-run") { return true }
		if configuration.executable.hasSuffix("go") && arguments.first == "test" { return true }

		let name = configuration.name.lowercased()
		return name.hasPrefix("test ") || name.hasSuffix(" test") || name.contains("go test")
	}

	public static func discover(in root: URL) -> [RunConfiguration] {
		var result: [RunConfiguration] = []
		result += intelliJConfigurations(in: root)
		result += vscodeConfigurations(in: root)

		for directory in searchDirectories(from: root) {
			result += makeTargets(in: directory)
			result += goModules(in: directory)
			result += mavenGoals(in: directory, root: root)
			result += gradleTasks(in: directory, root: root)
			result += xcodeSchemes(in: directory)
			result += swiftPackageRuns(in: directory, root: root)
			result += bazelTargets(in: directory)
			result += conanActions(in: directory)
		}
		result += javaMainClasses(in: root)

		// Stable order: source first, then name, so the list does not reshuffle
		// between scans.
		return result.sorted {
			$0.source.rawValue != $1.source.rawValue
				? $0.source.rawValue < $1.source.rawValue
				: $0.name < $1.name
		}
	}

	/// Directories to search, root first.
	public static func searchDirectories(from root: URL, depth: Int = 0) -> [URL] {
		guard depth <= searchDepth else { return [] }
		var result = [root]

		let contents = try? FileManager.default.contentsOfDirectory(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)
		for url in contents ?? [] {
			guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
			guard !skipped.contains(url.lastPathComponent) else { continue }
			result += searchDirectories(from: url, depth: depth + 1)
		}
		return result
	}

	// MARK: - IntelliJ

	static func intelliJConfigurations(in root: URL) -> [RunConfiguration] {
		var result: [RunConfiguration] = []
		let ideaDirectory = root.appendingPathComponent(".idea")

		// Shared configurations live one per file.
		let configurationsDirectory = ideaDirectory.appendingPathComponent("runConfigurations")
		let files = (try? FileManager.default.contentsOfDirectory(
			at: configurationsDirectory,
			includingPropertiesForKeys: nil
		)) ?? []
		for file in files where file.pathExtension == "xml" {
			result += parseIntelliJ(contentsOf: file, root: root)
		}

		// Everything else — including the temporary configurations IDEA creates
		// when you hit run on a main function — lives in workspace.xml.
		result += parseIntelliJ(
			contentsOf: ideaDirectory.appendingPathComponent("workspace.xml"),
			root: root
		)

		var seen = Set<String>()
		return result.filter { seen.insert($0.id).inserted }
	}

	static func parseIntelliJ(contentsOf url: URL, root: URL) -> [RunConfiguration] {
		guard let data = try? Data(contentsOf: url),
		      let document = try? XMLDocument(data: data)
		else { return [] }

		let nodes = (try? document.nodes(forXPath: "//configuration")) ?? []
		return nodes.compactMap { node -> RunConfiguration? in
			guard let element = node as? XMLElement,
			      let name = element.attribute(forName: "name")?.stringValue
			else { return nil }

			let type = element.attribute(forName: "type")?.stringValue ?? ""
			// Only Go is understood so far; anything else would produce a
			// configuration that looks runnable and is not.
			guard type.hasPrefix("GoApplication") || type.hasPrefix("GoTest") else { return nil }

			func option(_ optionName: String) -> String? {
				let child = element.elements(forName: optionName).first
				return child?.attribute(forName: "value")?.stringValue
			}

			let directory = expand(option("working_directory") ?? "$PROJECT_DIR$", root: root)
			let filePath = option("filePath").map {
				canonicalPath(URL(fileURLWithPath: expand($0, root: root)))
			}

			var arguments = ["run"]
			if let path = filePath, option("kind") == "FILE" {
				arguments.append(path)
			} else {
				arguments.append(".")
			}
			// Program arguments, split the way a shell would.
			arguments += splitArguments(expand(option("parameters") ?? "", root: root))

			return RunConfiguration(
				name: name,
				source: .intelliJ,
				executable: "go",
				arguments: arguments,
				workingDirectory: directory,
				environment: environmentOptions(in: element, root: root),
				file: filePath
			)
		}
	}

	private static func environmentOptions(in element: XMLElement, root: URL) -> [String: String] {
		var result: [String: String] = [:]
		for envs in element.elements(forName: "envs") {
			for entry in envs.elements(forName: "env") {
				guard let key = entry.attribute(forName: "name")?.stringValue,
				      let value = entry.attribute(forName: "value")?.stringValue
				else { continue }
				result[key] = expand(value, root: root)
			}
		}
		return result
	}

	/// Resolves IDEA's path macros.
	static func expand(_ value: String, root: URL) -> String {
		value
			.replacingOccurrences(of: "$PROJECT_DIR$", with: root.path)
			.replacingOccurrences(of: "$MODULE_DIR$", with: root.path)
			.replacingOccurrences(of: "$USER_HOME$", with: NSHomeDirectory())
	}

	// MARK: - VS Code

	static func vscodeConfigurations(in root: URL) -> [RunConfiguration] {
		let url = root.appendingPathComponent(".vscode/launch.json")
		guard let data = try? Data(contentsOf: url) else { return [] }
		return parseLaunchJSON(data, root: root)
	}

	static func parseLaunchJSON(_ data: Data, root: URL) -> [RunConfiguration] {
		// launch.json is JSON with comments and trailing commas, which
		// JSONSerialization rejects outright.
		guard let object = try? JSONSerialization.jsonObject(
			with: Data(stripJSONComments(String(decoding: data, as: UTF8.self)).utf8)
		) as? [String: Any] else { return [] }

		let entries = object["configurations"] as? [[String: Any]] ?? []
		return entries.compactMap { entry -> RunConfiguration? in
			guard let name = entry["name"] as? String else { return nil }
			guard (entry["type"] as? String) == "go" else { return nil }

			let program = expandVSCode(entry["program"] as? String ?? ".", root: root)
			let cwd = expandVSCode(entry["cwd"] as? String ?? "${workspaceFolder}", root: root)
			let args = (entry["args"] as? [String] ?? []).map { expandVSCode($0, root: root) }

			var environment: [String: String] = [:]
			for (key, value) in entry["env"] as? [String: String] ?? [:] {
				environment[key] = expandVSCode(value, root: root)
			}

			return RunConfiguration(
				name: name,
				source: .vscode,
				executable: "go",
				arguments: ["run", program] + args,
				workingDirectory: cwd,
				environment: environment
			)
		}
	}

	static func expandVSCode(_ value: String, root: URL) -> String {
		value
			.replacingOccurrences(of: "${workspaceFolder}", with: root.path)
			.replacingOccurrences(of: "${workspaceRoot}", with: root.path)
			.replacingOccurrences(of: "${userHome}", with: NSHomeDirectory())
	}

	/// Removes // and /* */ comments, and trailing commas, from JSONC.
	///
	/// Not a parser: it only has to survive the comments editors write into
	/// launch.json, and it must not touch anything inside a string — a URL in
	/// a value contains `//` and dropping the rest of that line would corrupt
	/// the file.
	static func stripJSONComments(_ text: String) -> String {
		var result = ""
		var inString = false
		var escaped = false
		var index = text.startIndex

		while index < text.endIndex {
			let character = text[index]

			if inString {
				result.append(character)
				if escaped { escaped = false }
				else if character == "\\" { escaped = true }
				else if character == "\"" { inString = false }
				index = text.index(after: index)
				continue
			}

			if character == "\"" {
				inString = true
				result.append(character)
				index = text.index(after: index)
				continue
			}

			let next = text.index(after: index)
			if character == "/", next < text.endIndex {
				if text[next] == "/" {
					while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
					continue
				}
				if text[next] == "*" {
					index = text.index(after: next)
					while index < text.endIndex {
						let closing = text.index(after: index)
						if text[index] == "*", closing < text.endIndex, text[closing] == "/" {
							index = text.index(after: closing)
							break
						}
						index = text.index(after: index)
					}
					continue
				}
			}

			result.append(character)
			index = next
		}

		return removeTrailingCommas(result)
	}

	private static func removeTrailingCommas(_ text: String) -> String {
		var result = ""
		var pending: Character?
		var inString = false
		var escaped = false

		for character in text {
			if inString {
				if let held = pending { result.append(held); pending = nil }
				result.append(character)
				if escaped { escaped = false }
				else if character == "\\" { escaped = true }
				else if character == "\"" { inString = false }
				continue
			}

			if let held = pending {
				// A comma followed by a closing bracket is the trailing one.
				if character == "]" || character == "}" {
					pending = nil
				} else {
					result.append(held)
					pending = nil
				}
			}

			if character == "," {
				pending = character
				continue
			}
			if character == "\"" { inString = true }
			result.append(character)
		}

		if let held = pending { result.append(held) }
		return result
	}

	// MARK: - Make

	static func makeTargets(in directory: URL) -> [RunConfiguration] {
		for name in ["Makefile", "makefile", "GNUmakefile"] {
			let url = directory.appendingPathComponent(name)
			guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
			return parseMakefile(
				text,
				path: canonicalPath(url),
				directory: canonicalPath(directory)
			)
		}
		return []
	}

	/// Reads target names and the lines they are declared on.
	static func parseMakefile(_ text: String, path: String, directory: String) -> [RunConfiguration] {
		var result: [RunConfiguration] = []
		var seen = Set<String>()

		for (index, raw) in text.components(separatedBy: "\n").enumerated() {
			// A recipe line starts with a tab; a target never does.
			guard !raw.hasPrefix("\t"), !raw.hasPrefix("#") else { continue }
			guard let colon = raw.firstIndex(of: ":") else { continue }

			let name = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
			guard !name.isEmpty else { continue }
			// `.PHONY` and friends are directives; `foo = bar:baz` is a variable;
			// a pattern rule is not something to offer running.
			guard !name.hasPrefix("."), !name.contains("="), !name.contains("%") else { continue }
			guard !name.contains("$"), !name.contains(" ") else { continue }
			// `:=`, `::=` and `:::=` are assignments that happen to start with a
			// colon. Any run of colons followed by `=` is one.
			var after = raw.index(after: colon)
			while after < raw.endIndex, raw[after] == ":" { after = raw.index(after: after) }
			if after < raw.endIndex, raw[after] == "=" { continue }
			guard seen.insert(name).inserted else { continue }

			result.append(RunConfiguration(
				name: name,
				source: .make,
				executable: "make",
				arguments: [name],
				workingDirectory: directory,
				file: path,
				line: index + 1
			))
		}
		return result
	}

	// MARK: - Bazel

	/// The runnable rules declared in this directory's build file.
	///
	/// Read from the file rather than asked of `bazel query`: the query is the
	/// correct answer and it is also a build-graph load that needs Bazel
	/// installed and can take a minute on a large repository, which is too much
	/// to spend filling in a menu.
	static func bazelTargets(in directory: URL) -> [RunConfiguration] {
		for name in BazelBuild.buildFileNames {
			let url = directory.appendingPathComponent(name)
			guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
			guard let workspace = BazelBuild.workspaceRoot(for: directory) else { continue }

			return BazelBuild.targets(in: url, contents: text, workspace: workspace).map { target in
				let command = BazelBuild.command(for: target)
				return RunConfiguration(
					name: target.label,
					source: .bazel,
					executable: command.executable,
					arguments: command.arguments,
					// From the workspace root, which is where labels resolve
					// from and where Bazel expects to be run.
					workingDirectory: canonicalPath(workspace),
					file: canonicalPath(url),
					line: target.line
				)
			}
		}
		return []
	}

	// MARK: - Conan

	/// What the Conan package in this directory can be asked to do.
	static func conanActions(in directory: URL) -> [RunConfiguration] {
		guard let project = ConanProject.find(in: directory) else { return [] }

		// Named after the package where it says what it is called, so two
		// packages in one repository are told apart in the list.
		let packageName: String? = {
			guard case let .recipe(url) = project,
			      let text = try? String(contentsOf: url, encoding: .utf8)
			else { return nil }
			return ConanProject.packageName(inRecipe: text)
		}()

		return project.actions.map { action in
			let command = project.command(for: action)
			return RunConfiguration(
				name: packageName.map { "\(action.title) (\($0))" } ?? action.title,
				source: .conan,
				executable: command.executable,
				arguments: command.arguments,
				workingDirectory: canonicalPath(project.directory),
				file: canonicalPath(project.file),
				line: 1
			)
		}
	}

	// MARK: - Xcode

	/// The schemes of an Xcode project or workspace in this directory.
	///
	/// Only the ones that launch something. A project with Swift package
	/// dependencies has a scheme for each of them, and a library scheme in a
	/// list of things to run is an entry that builds and then has nowhere to go.
	static func xcodeSchemes(in directory: URL) -> [RunConfiguration] {
		guard let project = XcodeProject.find(in: directory) else { return [] }

		return project.schemes().filter(\.isRunnable).map { scheme in
			RunConfiguration(
				name: scheme.name,
				source: .xcodeScheme,
				// What it does before a destination is chosen, which is also
				// what it falls back to: a build is the part of running a
				// scheme that does not depend on where it is going.
				executable: "xcodebuild",
				arguments: ["-scheme", scheme.name, "build"],
				workingDirectory: directory.path,
				xcode: XcodeTarget(project: project, scheme: scheme)
			)
		}
	}

	// MARK: - SwiftPM

	/// What the Swift package in this directory can run.
	///
	/// One entry per executable product — the name `swift run` takes, which is
	/// the product's and not the target's — and one `swift test` when the
	/// package declares a test target. See `SwiftPackage` for why the manifest
	/// is read rather than handed to `swift package dump-package`.
	///
	/// **The working directory is the package root**, which is the directory
	/// holding `Package.swift`. Not a choice so much as the only answer: it is
	/// where `swift run` has to be invoked from to find the package at all, and
	/// it is what somebody typing the command would be standing in. It is also
	/// the house default — every per-directory finder here passes the directory
	/// it searched, and only Bazel and Gradle differ, each because its tool
	/// insists on being run somewhere else. Written down because item 0499
	/// depends on it: Cadova writes its output beside the package, so the
	/// working directory is what decides where the file lands.
	static func swiftPackageRuns(in directory: URL, root: URL) -> [RunConfiguration] {
		guard let package = SwiftPackage.find(in: directory) else { return [] }

		let manifest = canonicalPath(package.manifest)
		let workingDirectory = canonicalPath(directory)
		let suffix = moduleSuffix(for: directory, root: root)

		var result = package.executables.map { executable in
			RunConfiguration(
				name: "swift run \(executable.name)\(suffix)",
				source: .swiftPackage,
				executable: "swift",
				arguments: ["run", executable.name],
				workingDirectory: workingDirectory,
				file: manifest,
				line: executable.line
			)
		}

		// `swift test` is a kind, because it is the same discovery and one
		// entry for the whole package. `isTest` already recognises it by the
		// `test` in its arguments, so it is offered and never saved — which is
		// the rule about test runs this list has always had, and the reason a
		// per-function entry would have been wrong where this is not.
		if let line = package.testLine {
			result.append(RunConfiguration(
				name: "swift test\(suffix)",
				source: .swiftPackage,
				executable: "swift",
				arguments: ["test"],
				workingDirectory: workingDirectory,
				file: manifest,
				line: line
			))
		}

		return result
	}

	// MARK: - Java

	/// The goals of a `pom.xml`, if this directory has one.
	static func mavenGoals(in directory: URL, root: URL) -> [RunConfiguration] {
		let manifest = directory.appendingPathComponent("pom.xml")
		guard let project = MavenProject.read(at: manifest) else { return [] }

		let executable = MavenProject.executable(for: directory, root: root)
		let suffix = moduleSuffix(for: directory, root: root)
		return project.goals.map { goal in
			RunConfiguration(
				name: "mvn \(goal.name)\(suffix)",
				source: .maven,
				executable: executable,
				arguments: [goal.name],
				workingDirectory: canonicalPath(directory),
				file: canonicalPath(manifest)
			)
		}
	}

	/// The tasks of a Gradle build, if this directory has one.
	static func gradleTasks(in directory: URL, root: URL) -> [RunConfiguration] {
		var buildFile: URL?
		for name in ["build.gradle.kts", "build.gradle"] {
			let candidate = directory.appendingPathComponent(name)
			if FileManager.default.fileExists(atPath: candidate.path) {
				buildFile = candidate
				break
			}
		}
		guard let buildFile, let build = GradleBuild.read(at: buildFile) else { return [] }

		let executable = GradleBuild.executable(for: directory, root: root)
		let suffix = moduleSuffix(for: directory, root: root)
		// The wrapper is written as `./gradlew`, so it is run from the directory
		// that holds it rather than from the module — and the module is named
		// with Gradle's own `:module:task` instead.
		let wrapperDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent()
		let isWrapper = executable.hasSuffix("gradlew")
		let prefix = isWrapper ? gradlePath(of: directory, under: wrapperDirectory) : ""

		return build.runnableTasks.map { task in
			RunConfiguration(
				name: "gradle \(task.name)\(suffix)",
				source: .gradle,
				executable: executable,
				arguments: [prefix + task.name],
				workingDirectory: canonicalPath(isWrapper ? wrapperDirectory : directory),
				file: canonicalPath(buildFile),
				line: task.line > 0 ? task.line : nil
			)
		}
	}

	/// Gradle's name for a sub-project: `:api:test` rather than `test` run in
	/// `api/`, which is the same thing said in the way Gradle understands from
	/// the root it is invoked at.
	static func gradlePath(of directory: URL, under root: URL) -> String {
		let rootPath = FilePath.canonical(root)
		let path = FilePath.canonical(directory)
		guard path != rootPath, path.hasPrefix(rootPath + "/") else { return "" }
		return ":" + String(path.dropFirst(rootPath.count + 1)).replacingOccurrences(of: "/", with: ":") + ":"
	}

	/// ` (api)` for a module, and nothing for the root — so a multi-module
	/// build's menu says which module each goal belongs to, and a single-module
	/// project is not made to read `mvn test (my-project)`.
	static func moduleSuffix(for directory: URL, root: URL) -> String {
		let rootPath = FilePath.canonical(root)
		let path = FilePath.canonical(directory)
		guard path != rootPath, path.hasPrefix(rootPath + "/") else { return "" }
		return " (\(String(path.dropFirst(rootPath.count + 1))))"
	}

	/// A configuration for every class with a `main` method.
	///
	/// What it runs is the build tool, because a JVM needs a classpath and only
	/// the build knows it: Spring Boot's plugin, Gradle's application plugin, or
	/// Maven's exec plugin, in that order of preference. The class travels with
	/// the configuration regardless, so the debugger — which builds its own
	/// classpath from the language server — can start the right one.
	static func javaMainClasses(in root: URL) -> [RunConfiguration] {
		JavaTooling.mainClasses(in: root).compactMap { main in
			let module = URL(fileURLWithPath: main.module)
			guard let command = javaRunCommand(for: main, module: module, root: root) else { return nil }

			return RunConfiguration(
				name: "run \(main.simpleName)",
				source: .javaMain,
				executable: command.executable,
				arguments: command.arguments,
				workingDirectory: canonicalPath(command.directory),
				file: main.file,
				line: main.line,
				mainClass: main.name
			)
		}
	}

	/// How to start one class, given what its module is built with.
	static func javaRunCommand(
		for main: JavaTooling.MainClass,
		module: URL,
		root: URL
	) -> (executable: String, arguments: [String], directory: URL)? {
		let manager = FileManager.default

		if manager.fileExists(atPath: module.appendingPathComponent("pom.xml").path) {
			let maven = MavenProject.executable(for: module, root: root)
			let project = MavenProject.read(at: module.appendingPathComponent("pom.xml"))
			if project?.isSpringBoot == true, project?.mainClass == nil || project?.mainClass == main.name {
				return (maven, ["spring-boot:run"], module)
			}
			// The exec plugin does not have to be declared in the POM — Maven
			// resolves it — so this works for a module that has said nothing
			// about how to run itself, which is most of them.
			return (maven, ["compile", "exec:java", "-Dexec.mainClass=\(main.name)"], module)
		}

		for name in ["build.gradle.kts", "build.gradle"] {
			let file = module.appendingPathComponent(name)
			guard let build = GradleBuild.read(at: file) else { continue }
			let gradle = GradleBuild.executable(for: module, root: root)
			let wrapperDirectory = gradle.hasSuffix("gradlew")
				? URL(fileURLWithPath: gradle).deletingLastPathComponent()
				: module
			let prefix = gradle.hasSuffix("gradlew") ? gradlePath(of: module, under: wrapperDirectory) : ""

			if build.isSpringBoot { return (gradle, [prefix + "bootRun"], wrapperDirectory) }
			if build.isApplication { return (gradle, [prefix + "run"], wrapperDirectory) }
			// A Gradle module with neither plugin has no task that starts a
			// class, and inventing a `JavaExec` in somebody's build file is not
			// this app's business. It can still be debugged: that path builds
			// its own classpath rather than asking Gradle to run anything.
			return nil
		}
		return nil
	}

	// MARK: - Go

	/// A `go run .` for every directory holding a main package.
	static func goModules(in directory: URL) -> [RunConfiguration] {
		let manifest = directory.appendingPathComponent("go.mod")
		guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }

		// The module directory itself only runs if it has a main package; a
		// library module has nothing to offer.
		var result: [RunConfiguration] = []
		for main in mainPackages(under: directory) {
			result.append(RunConfiguration(
				name: "go run \(displayName(for: main, under: directory))",
				source: .goModule,
				executable: "go",
				arguments: ["run", "."],
				workingDirectory: main.directory,
				file: main.file,
				line: main.line
			))
		}
		return result
	}

	struct MainPackage: Equatable {
		var directory: String
		var file: String
		var line: Int
	}

	/// Finds `func main()` in package main, which is what `go run` needs.
	static func mainPackages(under root: URL, depth: Int = 0) -> [MainPackage] {
		guard depth <= searchDepth else { return [] }
		var result: [MainPackage] = []

		let contents = (try? FileManager.default.contentsOfDirectory(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)) ?? []

		for url in contents {
			let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
			if isDirectory {
				guard !skipped.contains(url.lastPathComponent) else { continue }
				result += mainPackages(under: url, depth: depth + 1)
				continue
			}

			guard url.pathExtension == "go",
			      let text = try? String(contentsOf: url, encoding: .utf8),
			      let line = mainFunctionLine(in: text)
			else { continue }

			result.append(MainPackage(
				directory: canonicalPath(url.deletingLastPathComponent()),
				file: canonicalPath(url),
				line: line
			))
		}
		return result
	}

	/// The 1-based line of `func main()` in a `package main` file, or nil.
	static func mainFunctionLine(in source: String) -> Int? {
		var isMainPackage = false
		var mainLine: Int?

		for (index, raw) in source.components(separatedBy: "\n").enumerated() {
			let line = raw.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("package ") {
				isMainPackage = line.dropFirst("package ".count)
					.trimmingCharacters(in: .whitespaces)
					.hasPrefix("main")
			}
			// `func main()` only counts at the top level, so no leading indent.
			if mainLine == nil, raw.hasPrefix("func main("), raw.contains(")") {
				mainLine = index + 1
			}
		}
		return isMainPackage ? mainLine : nil
	}

	private static func displayName(for main: MainPackage, under root: URL) -> String {
		let directory = main.directory
		guard directory != root.path else { return root.lastPathComponent }
		if directory.hasPrefix(root.path + "/") {
			return String(directory.dropFirst(root.path.count + 1))
		}
		return (directory as NSString).lastPathComponent
	}

	/// Splits a parameter string the way a shell would, honouring quotes.
	static func splitArguments(_ value: String) -> [String] {
		var result: [String] = []
		var current = ""
		var quote: Character?

		for character in value {
			if let active = quote {
				if character == active { quote = nil } else { current.append(character) }
				continue
			}
			switch character {
			case "\"", "'":
				quote = character
			case " ", "\t":
				if !current.isEmpty { result.append(current); current = "" }
			default:
				current.append(character)
			}
		}
		if !current.isEmpty { result.append(current) }
		return result
	}
}

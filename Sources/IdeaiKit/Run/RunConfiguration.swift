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

	public var id: String { "\(source.rawValue):\(name):\(workingDirectory)" }

	/// Whether the native debugger can start on this.
	///
	/// Delve debugs a Go package, so anything that is not one — a make target
	/// wrapping a build, a launch.json entry for another language — has nothing
	/// to hand it.
	public var isDebuggable: Bool {
		executable == "go" && arguments.first == "run"
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
		line: Int? = nil
	) {
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

	public static func discover(in root: URL) -> [RunConfiguration] {
		var result: [RunConfiguration] = []
		result += intelliJConfigurations(in: root)
		result += vscodeConfigurations(in: root)

		for directory in searchDirectories(from: root) {
			result += makeTargets(in: directory)
			result += goModules(in: directory)
		}

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

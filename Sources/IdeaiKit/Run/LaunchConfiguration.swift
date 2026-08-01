import Foundation

/// One entry in `.vscode/launch.json`.
///
/// VS Code's format rather than one of our own, because a project usually
/// already has this file and the people you share it with expect it to keep
/// working. Everything not understood here is carried through untouched, so
/// editing the arguments of one configuration cannot quietly delete a key some
/// other tool relies on.
public struct LaunchConfiguration: Equatable, Sendable, Identifiable {
	public var name: String
	/// `go`, `lldb`, `node` — what a debug adapter is picked by.
	public var type: String
	/// `launch` or `attach`.
	public var request: String
	/// What to run: a package directory for Go, a binary for LLDB.
	public var program: String
	public var arguments: [String]
	/// Where it runs, unexpanded — `${workspaceFolder}` and friends survive.
	public var workingDirectory: String
	public var environment: [String: String]

	/// Everything else the file said, kept so writing back loses nothing.
	public var extras: [String: JSONValue]

	public var id: String { name }

	public init(
		name: String,
		type: String = "go",
		request: String = "launch",
		program: String = "${workspaceFolder}",
		arguments: [String] = [],
		workingDirectory: String = "${workspaceFolder}",
		environment: [String: String] = [:],
		extras: [String: JSONValue] = [:]
	) {
		self.name = name
		self.type = type
		self.request = request
		self.program = program
		self.arguments = arguments
		self.workingDirectory = workingDirectory
		self.environment = environment
		self.extras = extras
	}

	/// Keys this type owns. Anything else is an extra.
	static let knownKeys: Set<String> = [
		"name", "type", "request", "program", "args", "cwd", "env",
	]

	public init?(json: [String: Any]) {
		guard let name = json["name"] as? String else { return nil }
		self.name = name
		type = json["type"] as? String ?? "go"
		request = json["request"] as? String ?? "launch"
		program = json["program"] as? String ?? "${workspaceFolder}"
		arguments = json["args"] as? [String] ?? []
		workingDirectory = json["cwd"] as? String ?? "${workspaceFolder}"
		environment = json["env"] as? [String: String] ?? [:]

		extras = [:]
		for (key, value) in json where !Self.knownKeys.contains(key) {
			extras[key] = JSONValue(value)
		}
	}

	public var json: [String: Any] {
		var object: [String: Any] = [
			"name": name,
			"type": type,
			"request": request,
			"program": program,
		]
		if !arguments.isEmpty { object["args"] = arguments }
		if workingDirectory != "${workspaceFolder}" { object["cwd"] = workingDirectory }
		if !environment.isEmpty { object["env"] = environment }
		for (key, value) in extras { object[key] = value.any }
		return object
	}

	/// Where this runs, with VS Code's variables filled in.
	public func expandedWorkingDirectory(root: URL) -> String {
		Self.expand(workingDirectory, root: root)
	}

	public func expandedProgram(root: URL) -> String {
		Self.expand(program, root: root)
	}

	public func expandedArguments(root: URL) -> [String] {
		arguments.map { Self.expand($0, root: root) }
	}

	public func expandedEnvironment(root: URL) -> [String: String] {
		environment.mapValues { Self.expand($0, root: root) }
	}

	public static func expand(_ value: String, root: URL) -> String {
		value
			.replacingOccurrences(of: "${workspaceFolder}", with: root.path)
			.replacingOccurrences(of: "${workspaceRoot}", with: root.path)
			.replacingOccurrences(of: "${userHome}", with: NSHomeDirectory())
	}

	/// Whether a debugger can start on this, and which one.
	public var adapterID: String { type == "go" ? "delve" : "lldb" }
}

/// Just enough of a JSON value to carry unknown keys through unchanged.
public enum JSONValue: Equatable, Sendable {
	case string(String)
	case number(Double)
	case bool(Bool)
	case array([JSONValue])
	case object([String: JSONValue])
	case null

	public init(_ any: Any) {
		switch any {
		case let value as String: self = .string(value)
		case let value as Bool where "\(type(of: any))" == "__NSCFBoolean": self = .bool(value)
		case let value as NSNumber:
			// NSNumber does not distinguish a bool from a 0 or 1 by type alone.
			self = CFGetTypeID(value) == CFBooleanGetTypeID()
				? .bool(value.boolValue)
				: .number(value.doubleValue)
		case let value as [Any]: self = .array(value.map(JSONValue.init))
		case let value as [String: Any]: self = .object(value.mapValues(JSONValue.init))
		default: self = .null
		}
	}

	public var any: Any {
		switch self {
		case let .string(value): return value
		case let .number(value): return value == value.rounded() ? Int(value) : value
		case let .bool(value): return value
		case let .array(values): return values.map(\.any)
		case let .object(values): return values.mapValues(\.any)
		case .null: return NSNull()
		}
	}
}

/// Reading and writing `.vscode/launch.json`.
public enum LaunchFile {
	public static func url(in root: URL) -> URL {
		root.appendingPathComponent(".vscode/launch.json")
	}

	/// The configurations a project defines, in the order the file lists them.
	public static func read(in root: URL) -> [LaunchConfiguration] {
		guard let data = try? Data(contentsOf: url(in: root)) else { return [] }
		return parse(data)
	}

	static func parse(_ data: Data) -> [LaunchConfiguration] {
		// The file is JSON with comments and trailing commas, which
		// JSONSerialization rejects outright.
		let text = RunConfigurationDiscovery.stripJSONComments(String(decoding: data, as: UTF8.self))
		guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
		      let entries = object["configurations"] as? [[String: Any]]
		else { return [] }
		return entries.compactMap(LaunchConfiguration.init(json:))
	}

	/// Writes the configurations back, keeping the file's own version field.
	///
	/// The whole file is rewritten, so comments in it are lost — which is why
	/// nothing writes unless the user asked for a change. Formatted with sorted
	/// keys so a diff of two edits is the edit and not a reshuffle.
	public static func write(_ configurations: [LaunchConfiguration], in root: URL) throws {
		let file = url(in: root)
		try FileManager.default.createDirectory(
			at: file.deletingLastPathComponent(), withIntermediateDirectories: true
		)

		let object: [String: Any] = [
			"version": "0.2.0",
			"configurations": configurations.map(\.json),
		]
		let data = try JSONSerialization.data(
			withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		)
		var text = String(decoding: data, as: UTF8.self)
		if !text.hasSuffix("\n") { text += "\n" }
		try text.write(to: file, atomically: true, encoding: .utf8)
	}

	/// Adds a configuration, or replaces the one with the same name.
	@discardableResult
	public static func save(_ configuration: LaunchConfiguration, in root: URL) throws -> [LaunchConfiguration] {
		var all = read(in: root)
		if let index = all.firstIndex(where: { $0.name == configuration.name }) {
			all[index] = configuration
		} else {
			all.append(configuration)
		}
		try write(all, in: root)
		return all
	}

	public static func remove(named name: String, in root: URL) throws -> [LaunchConfiguration] {
		let remaining = read(in: root).filter { $0.name != name }
		try write(remaining, in: root)
		return remaining
	}

	/// A configuration for a project that has none, from what is actually
	/// there.
	///
	/// Pressing play in a project with no launch.json should run the obvious
	/// thing and leave a file behind saying what it did, rather than asking a
	/// question nobody has the information to answer yet.
	public static func suggestion(for root: URL) -> LaunchConfiguration? {
		let goModules = RunConfigurationDiscovery.searchDirectories(from: root)
			.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("go.mod").path) }

		if let module = goModules.first {
			// Both canonical before comparing: the search may report
			// `/private/var/...` for a root spelled `/var/...`, and subtracting
			// one length from the other then cuts the path in the wrong place.
			let rootPath = FilePath.canonical(root)
			let modulePath = FilePath.canonical(module)
			let relative = modulePath == rootPath
				? "${workspaceFolder}"
				: "${workspaceFolder}/" + String(modulePath.dropFirst(rootPath.count + 1))
			return LaunchConfiguration(
				name: root.lastPathComponent,
				type: "go",
				request: "launch",
				program: relative,
				workingDirectory: relative
			)
		}
		return nil
	}
}

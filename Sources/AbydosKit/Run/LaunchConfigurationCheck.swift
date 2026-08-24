import Foundation

/// What is wrong with a launch configuration, said before it is run.
///
/// Every one of these is a failure that has actually happened here, and each
/// cost an hour or more, because none of them fails in a way that points at the
/// configuration:
///
/// - A Go program with `"type": "lldb"` starts LLDB on a source directory. LLDB
///   says nothing, the adapter reports nothing, and the debugger simply never
///   starts — which reads as a broken debugger, or as a permissions problem.
/// - An argument naming a file that is not there is passed through as written.
///   In a pod it is a path from another machine; locally it is a file the
///   program cannot open. Either way the program complains about *its*
///   configuration, not about this one.
/// - A file listed to send that is not there is skipped silently, and the pod
///   starts without the configuration it was promised.
///
/// Warnings rather than errors: a path can be produced by the build, an
/// argument can be a flag that looks like a path, and a configuration somebody
/// is halfway through writing should not be shouted at.
public enum LaunchConfigurationCheck {
	public struct Problem: Equatable, Sendable, Identifiable {
		/// Which field it belongs beside, matching the editor's keys:
		/// `program`, `cwd`, `arguments`, `files`, `type`.
		public let field: String
		public let message: String
		/// What to do about it, when there is something specific to do.
		public let fix: String?

		public var id: String { "\(field):\(message)" }

		public init(field: String, message: String, fix: String? = nil) {
			self.field = field
			self.message = message
			self.fix = fix
		}
	}

	/// Everything worth saying about one configuration.
	/// - `scriptKind`: injectable for the same reason `fileExists` is — deciding
	///   this reads the first two bytes of the file, and the fixtures these rules
	///   are checked against have no files.
	public static func problems(
		for configuration: LaunchConfiguration,
		root: URL,
		fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
		scriptKind: (String) -> ScriptLaunch.Kind? = { ScriptLaunch.kind(ofProgramAt: $0) }
	) -> [Problem] {
		var found: [Problem] = []
		let program = expand(configuration.program, root: root)

		// The debugger against what it is being pointed at.
		if configuration.type == "lldb", isGoPackage(program, fileExists: fileExists) {
			found.append(Problem(
				field: "type",
				message: "This runs a Go package, but the debugger is LLDB, which cannot build one.",
				fix: "Set what it runs to Go."
			))
		}

		if !configuration.program.isEmpty, !fileExists(program) {
			found.append(Problem(
				field: "program",
				message: "Nothing at \(shorten(program, root: root)).",
				fix: nil
			))
		}

		// A script, which is not a thing a debugger opens. Said here because the
		// alternative is finding out from LLDB — "is not a valid executable",
		// about a file that is perfectly valid and simply is not a binary — and
		// because what happens instead is worth knowing before pressing play:
		// debugging goes through the JVM the script starts, and for Gradle it
		// goes through a port that cannot be chosen.
		if !configuration.program.isEmpty, fileExists(program),
		   let kind = scriptKind(program) {
			switch kind {
			case .maven:
				found.append(Problem(
					field: "program",
					message: "This is a script, so debugging attaches to the JVM Maven starts.",
					fix: "A forked goal starts a JVM that does not inherit MAVEN_OPTS; Surefire "
						+ "wants the option in argLine, Spring Boot in jvmArguments."
				))
			case .gradle:
				found.append(Problem(
					field: "program",
					message: "This is a script, so debugging runs it with --debug-jvm and attaches "
						+ "to the JVM Gradle forks.",
					fix: "Gradle's debug port is always \(ScriptLaunch.gradleDebugPort) and cannot "
						+ "be chosen, so only one such launch can be waiting at a time."
				))
			case .script:
				found.append(Problem(
					field: "program",
					message: "This is a script, so there is no native debugger for it.",
					fix: "It runs with JAVA_TOOL_OPTIONS asking the first JVM it starts to wait "
						+ "for the debugger. If it starts none, it simply runs."
				))
			}
		}

		let directory = expand(configuration.workingDirectory, root: root)
		if !configuration.workingDirectory.isEmpty, !fileExists(directory) {
			found.append(Problem(
				field: "cwd",
				message: "Nothing at \(shorten(directory, root: root)).",
				fix: nil
			))
		}

		// An argument that looks like a path in this project and is not one.
		// Only inside the project, because a path elsewhere may belong to the
		// machine this runs on rather than to this one.
		for argument in configuration.arguments {
			let expanded = expand(argument, root: root)
			guard looksLikeAProjectPath(argument, expanded: expanded, root: root),
			      !fileExists(expanded)
			else { continue }
			found.append(Problem(
				field: "arguments",
				message: "\(shorten(expanded, root: root)) is not there.",
				fix: "The program is given this path as written, and cannot open it either."
			))
		}

		for entry in devPodFiles(in: configuration) {
			// `local:remote` — only the local half is this machine's.
			let local = entry.split(separator: ":", maxSplits: 1).map(String.init)[0]
			let expanded = absolute(expand(local, root: root), root: root)
			guard !fileExists(expanded) else { continue }
			found.append(Problem(
				field: "files",
				message: "\(shorten(expanded, root: root)) is not there to send.",
				fix: "It is skipped, and the pod starts without it."
			))
		}

		return found
	}

	/// A directory holding a `go.mod`, or one inside a module — which is what
	/// Delve builds and LLDB cannot.
	static func isGoPackage(_ path: String, fileExists: (String) -> Bool) -> Bool {
		var directory = URL(fileURLWithPath: path)
		// A file cannot be a package; its directory can.
		if directory.pathExtension == "go" { directory = directory.deletingLastPathComponent() }

		for _ in 0..<4 {
			if fileExists(directory.appendingPathComponent("go.mod").path) { return true }
			let parent = directory.deletingLastPathComponent()
			if parent.path == directory.path { break }
			directory = parent
		}
		return false
	}

	/// Whether an argument is meant to be a file in this project.
	///
    /// A flag is not, a number is not, and a bare word is not: what counts is
	/// something that names a place — written with a variable, with a slash, or
	/// as a path under the project.
	static func looksLikeAProjectPath(_ argument: String, expanded: String, root: URL) -> Bool {
		guard !argument.hasPrefix("-") else { return false }
		guard argument.contains("${") || argument.contains("/") else { return false }
		return expanded.hasPrefix(FilePath.canonical(root) + "/")
	}

	static func devPodFiles(in configuration: LaunchConfiguration) -> [String] {
		guard case let .object(pod)? = configuration.extra("devPod"),
		      case let .array(files)? = pod["files"]
		else { return [] }
		return files.compactMap { if case let .string(value) = $0 { return value } else { return nil } }
	}

	static func expand(_ value: String, root: URL) -> String {
		LaunchConfiguration.expand(value, root: root)
	}

	/// Relative entries are the project's, which is how this app writes them.
	static func absolute(_ path: String, root: URL) -> String {
		path.hasPrefix("/") ? path : FilePath.canonical(root) + "/" + path
	}

	/// Paths read better without the part that is the same for all of them.
	static func shorten(_ path: String, root: URL) -> String {
		let base = FilePath.canonical(root) + "/"
		return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
	}
}

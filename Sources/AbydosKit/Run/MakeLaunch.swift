import Foundation

/// Turning a make goal into something that can be debugged.
///
/// `make dev` builds a frontend, builds a Go binary with `-ldflags "-s -w"`,
/// and runs it with a config path and two credentials fetched from sops. Every
/// part of that is worth keeping except one: the binary make produces has its
/// symbols stripped, so a debugger attached to it can tell you nothing.
///
/// So the work is divided. Everything that is not the Go build still runs
/// through make — it is what the project says those steps are — and the Go
/// build is left to the debugger, which compiles the same package with the
/// symbols it needs. The program then starts with the arguments and the
/// environment the recipe would have given it, including the values that come
/// out of a shell.
public enum MakeLaunch {
	/// What a goal turns into.
	public struct Plan: Equatable, Sendable {
		/// The make targets to run first, in order. Empty when the goal builds
		/// nothing but the Go program.
		public let buildTargets: [String]
		/// The package the debugger should build, relative to the Makefile.
		public let package: String
		public let arguments: [String]
		/// Environment the recipe sets outright.
		public let environment: [String: String]
		/// Assignments whose value comes from a command — `X=$(sops -d ...)`.
		/// Evaluated in a shell at launch, because that is the only thing that
		/// can evaluate them.
		public let environmentCommands: [String: String]
		/// Where the recipe would have run.
		public let workingDirectory: String

		public init(
			buildTargets: [String],
			package: String,
			arguments: [String] = [],
			environment: [String: String] = [:],
			environmentCommands: [String: String] = [:],
			workingDirectory: String = "."
		) {
			self.buildTargets = buildTargets
			self.package = package
			self.arguments = arguments
			self.environment = environment
			self.environmentCommands = environmentCommands
			self.workingDirectory = workingDirectory
		}
	}

	/// Reads a goal and works out how to run it under a debugger.
	///
	/// Nil when the goal never starts a Go program of this project — `make
	/// test` and `make docker` are worth running, but not worth debugging.
	public static func plan(for goal: String, in makefile: Makefile) -> Plan? {
		let chain = makefile.chain(from: goal)
		guard !chain.isEmpty else { return nil }

		// The Go build in the chain says which package the binary comes from
		// and what the binary is called.
		var packagePath: String?
		var builtBinaries: Set<String> = []
		var goBuildTargets: Set<String> = []

		for target in chain {
			for line in target.recipe {
				let expanded = makefile.expand(line)
				guard let build = goBuild(in: expanded) else { continue }
				packagePath = build.package
				builtBinaries.insert(build.output)
				goBuildTargets.insert(target.name)
			}
		}

		// The line that starts the binary: it names one of the things built,
		// and everything before it is environment.
		var run: RunLine?
		for target in chain.reversed() {
			for line in target.recipe.reversed() {
				let expanded = makefile.expand(line)
				guard let candidate = runLine(in: expanded, binaries: builtBinaries) else { continue }
				run = candidate
				break
			}
			if run != nil { break }
		}

		guard let run, let packagePath else { return nil }

		// Everything else make would have done first, in order, minus the Go
		// build the debugger is taking over — and minus the target that only
		// runs the program.
		let buildTargets = chain
			.filter { !goBuildTargets.contains($0.name) }
			.filter { !$0.recipe.isEmpty }
			.filter { $0.name != goal || chain.count == 1 }
			.map(\.name)

		return Plan(
			buildTargets: buildTargets,
			package: relative(packagePath, to: makefile.directory),
			arguments: run.arguments,
			environment: run.environment,
			environmentCommands: run.environmentCommands,
			workingDirectory: makefile.directory.path
		)
	}

	/// A launch configuration for a goal, in the same file every other one
	/// lives in.
	/// What choosing a goal from the run menu should do.
	///
	/// Always something. A goal that can be debugged becomes a launch
	/// configuration; every other goal is still perfectly runnable — `make dev`
	/// builds and starts things all day — and becomes a plain run. The one
	/// answer that was allowed before, and should not have been, is silence:
	/// deciding at menu-build time that a goal is debuggable and then finding
	/// at click time that no plan can be made left the click doing nothing at
	/// all, with no selection and no word about why.
	public enum Choice: Equatable, Sendable {
		/// Debuggable: a configuration to save and select.
		case debug(LaunchConfiguration)
		/// Not debuggable, but runnable: `make <goal>`, in the terminal.
		case run(RunConfiguration)
	}

	/// The app bundle a goal launches, if that is what it does.
	///
	/// `open build/thing.app` hands the app to the system and returns at once,
	/// which is why running one this way looked like it had finished the moment
	/// it started: the make process really had. Nothing was left to stop, and
	/// nothing to attach a debugger to.
	///
	/// The binary inside the bundle is a process like any other. Run that and
	/// the app is ours: its output is in the panel, the stop button stops it,
	/// and lldb can be told to launch it instead.
	public static func launchedApp(for goal: String, in makefile: Makefile) -> String? {
		for target in makefile.chain(from: goal).reversed() {
			for line in target.recipe.reversed() {
				let expanded = makefile.expand(line)
					.trimmingCharacters(in: CharacterSet(charactersIn: "@-\t "))
				guard expanded.hasPrefix("open ") else { continue }
				// `open -a Thing.app file`, or a flag before the path: the
				// bundle is the argument that ends in `.app`.
				let bundle = ArgumentLine.split(String(expanded.dropFirst("open ".count)))
					.first { $0.hasSuffix(".app") }
				guard let bundle else { continue }
				let name = URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent
				return "\(bundle)/Contents/MacOS/\(name)"
			}
		}
		return nil
	}

	public static func choice(
		for goal: String,
		in makefile: Makefile,
		projectRoot: URL
	) -> Choice {
		if let configuration = configuration(for: goal, in: makefile, projectRoot: projectRoot) {
			return .debug(configuration)
		}

		// A goal that builds an app and hands it to `open`: run the binary
		// inside the bundle instead, so the thing that was started is the thing
		// that can be stopped and debugged.
		if let program = launchedApp(for: goal, in: makefile) {
			let directory = relativeToWorkspace(makefile.directory, root: projectRoot)
			let build = makefile.chain(from: goal)
				.filter { !$0.recipe.isEmpty && $0.name != goal }
				.map(\.name)

			var extras: [String: JSONValue] = [:]
			if !build.isEmpty {
				extras[LaunchConfiguration.extraPrefix + "make"] = .object([
					"targets": .array(build.map(JSONValue.string)),
					"directory": .string(directory),
				])
			}
			return .debug(LaunchConfiguration(
				name: "make \(goal)",
				// lldb, not delve: this is the binary of a macOS app, and what
				// debugs it is the debugger Xcode uses.
				type: "lldb",
				program: directory == "." ? program : directory + "/" + program,
				workingDirectory: directory,
				extras: extras
			))
		}
		return .run(RunConfiguration(
			name: "make \(goal)",
			source: .make,
			executable: "make",
			arguments: [goal],
			workingDirectory: makefile.path.deletingLastPathComponent().path
		))
	}

	public static func configuration(
		for goal: String,
		in makefile: Makefile,
		projectRoot: URL
	) -> LaunchConfiguration? {
		guard let plan = plan(for: goal, in: makefile) else { return nil }

		let directory = relativeToWorkspace(makefile.directory, root: projectRoot)
		let program = plan.package == "."
			? directory
			: directory + "/" + plan.package

		var extras: [String: JSONValue] = [:]
		if !plan.buildTargets.isEmpty {
			// Our own key, carried through launch.json untouched by anything
			// else that reads the file.
			extras[LaunchConfiguration.extraPrefix + "make"] = .object([
				"targets": .array(plan.buildTargets.map(JSONValue.string)),
				"directory": .string(directory),
			])
		}
		if !plan.environmentCommands.isEmpty {
			extras[LaunchConfiguration.extraPrefix + "envCommands"] =
				.object(plan.environmentCommands.mapValues(JSONValue.string))
		}

		return LaunchConfiguration(
			name: "make \(goal)",
			type: "go",
			request: "launch",
			program: program,
			arguments: plan.arguments.map { relativeToWorkspace(path: $0, root: projectRoot) },
			workingDirectory: directory,
			environment: plan.environment,
			extras: extras
		)
	}

	// MARK: - Reading a recipe

	struct RunLine: Equatable {
		let arguments: [String]
		let environment: [String: String]
		let environmentCommands: [String: String]
	}

	/// `go build -o build/app .` — the package built and where it goes.
	static func goBuild(in line: String) -> (package: String, output: String)? {
		let words = shellWords(line).map { ArgumentLine.split($0).first ?? $0 }
		guard let goIndex = words.firstIndex(where: { $0 == "go" || $0.hasSuffix("/go") }),
		      words.indices.contains(goIndex + 1),
		      words[goIndex + 1] == "build"
		else { return nil }

		var output = ""
		var package = "."
		var index = goIndex + 2
		while index < words.count {
			let word = words[index]
			if word == "-o", words.indices.contains(index + 1) {
				output = words[index + 1]
				index += 2
				continue
			}
			// Flags and their values are make's business, not ours; the last
			// bare word is the package.
			if word.hasPrefix("-") {
				// `-ldflags "..."` takes a value; a lone flag does not, and
				// treating its successor as the package would be wrong.
				if word.contains("flags"), words.indices.contains(index + 1) { index += 1 }
				index += 1
				continue
			}
			package = word
			index += 1
		}
		guard !output.isEmpty else { return nil }
		return (package, output)
	}

	/// The line that starts the program, with whatever is set in front of it.
	///
	/// A recipe runs the binary it just built, usually with `VAR=$(...)`
	/// assignments before it. Those are the credentials, and dropping them is
	/// the difference between a program that starts and one that exits with a
	/// message about a missing password.
	static func runLine(in line: String, binaries: Set<String>) -> RunLine? {
		let words = shellWords(line)
		guard !words.isEmpty else { return nil }

		var environment: [String: String] = [:]
		var commands: [String: String] = [:]
		var index = 0

		// `env` before the assignments is a way of writing the same thing.
		if words[index] == "env" { index += 1 }

		while index < words.count, let (name, value) = assignment(words[index]) {
			if value.hasPrefix("$(") || value.hasPrefix("`") || value.contains("$(") {
				commands[name] = value
			} else {
				environment[name] = value
			}
			index += 1
		}

		guard index < words.count else { return nil }
		let program = words[index]
		// The word has to be something this Makefile built, or the line is
		// some other command that happens to follow assignments.
		guard binaries.contains(where: { matches(program, binary: $0) }) else { return nil }

		return RunLine(
			// The words go to a program rather than to a shell, so their
			// quoting comes off here.
			arguments: words[(index + 1)...].map { ArgumentLine.split($0).first ?? $0 },
			environment: environment,
			environmentCommands: commands
		)
	}

	/// Splits a command line into words the way a shell would, keeping a
	/// substitution whole.
	///
	/// `ArgumentLine.split` is for what somebody types into a field; this is
	/// for a recipe, where `USER=$(sops -d x | awk '{print $2}')` is one word
	/// with spaces in it and cutting it at the first space produces nonsense.
	static func shellWords(_ line: String) -> [String] {
		var words: [String] = []
		var current = ""
		var quote: Character?
		var depth = 0
		var index = line.startIndex

		func flush() {
			if !current.isEmpty { words.append(current) }
			current = ""
		}

		while index < line.endIndex {
			let character = line[index]
			let next = line.index(after: index)

			if character == "\\", next < line.endIndex {
				current.append(character)
				current.append(line[next])
				index = line.index(after: next)
				continue
			}
			if let open = quote {
				current.append(character)
				if character == open { quote = nil }
				index = next
				continue
			}
			switch character {
			case "\"", "'":
				quote = character
				current.append(character)
			case "$" where next < line.endIndex && (line[next] == "(" || line[next] == "{"):
				depth += 1
				current.append(character)
			case ")", "}":
				if depth > 0 { depth -= 1 }
				current.append(character)
			case " ", "\t":
				// Whitespace inside a substitution belongs to it.
				if depth == 0 { flush() } else { current.append(character) }
			default:
				current.append(character)
			}
			index = next
		}
		flush()
		return words
	}

	/// `NAME=value`, as a shell reads it before a command.
	static func assignment(_ word: String) -> (String, String)? {
		guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return nil }
		let name = String(word[word.startIndex..<equals])
		guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
		      name.first?.isNumber != true
		else { return nil }
		return (name, String(word[word.index(after: equals)...]))
	}

	/// Whether a word names a binary the Makefile builds.
	///
	/// `./build/app` and `build/app` and `$(PWD)/build/app` are the same file
	/// written three ways, and a recipe uses whichever it feels like.
	static func matches(_ word: String, binary: String) -> Bool {
		let clean = { (path: String) in
			var value = path
			while value.hasPrefix("./") { value.removeFirst(2) }
			return (value as NSString).standardizingPath
		}
		let one = clean(word), other = clean(binary)
		return one == other
			|| one.hasSuffix("/" + other)
			|| other.hasSuffix("/" + one)
			|| (one as NSString).lastPathComponent == (other as NSString).lastPathComponent
	}

	// MARK: - Paths

	static func relative(_ path: String, to directory: URL) -> String {
		let base = directory.path
		if path == base { return "." }
		if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
		return path
	}

	/// A path under the project, written the way launch.json writes them.
	public static func relativeToWorkspace(_ url: URL, root: URL) -> String {
		relativeToWorkspace(path: url.path, root: root)
	}

	public static func relativeToWorkspace(path: String, root: URL) -> String {
		let base = FilePath.canonical(root)
		let canonical = FilePath.canonical(path)
		if canonical == base { return "${workspaceFolder}" }
		if canonical.hasPrefix(base + "/") {
			return "${workspaceFolder}/" + String(canonical.dropFirst(base.count + 1))
		}
		return path
	}
}

/// The parts of a configuration that only this app understands.
///
/// Kept in `extras`, so a `launch.json` carrying them still opens in anything
/// else that reads the format — those tools ignore what they do not know, and
/// so does this one when the keys are absent.
public extension LaunchConfiguration {
	struct MakeStep: Equatable, Sendable {
		public let targets: [String]
		/// Where to run make, unexpanded.
		public let directory: String

		public init(targets: [String], directory: String) {
			self.targets = targets
			self.directory = directory
		}

		/// What to run, as a shell would be given it.
		public func commandLine(root: URL) -> String {
			let path = LaunchConfiguration.expand(directory, root: root)
			return (["make", "-C", path] + targets)
				.map { $0.contains(" ") ? "'\($0)'" : $0 }
				.joined(separator: " ")
		}
	}

	/// The build to run before this starts, if there is one.
	var makeStep: MakeStep? {
		guard case let .object(fields)? = extra("make"),
		      case let .array(targets)? = fields["targets"]
		else { return nil }

		let names = targets.compactMap { value -> String? in
			guard case let .string(name) = value else { return nil }
			return name
		}
		guard !names.isEmpty else { return nil }

		var directory = "${workspaceFolder}"
		if case let .string(value)? = fields["directory"] { directory = value }
		return MakeStep(targets: names, directory: directory)
	}

	/// Environment whose values have to be produced by a shell — a password
	/// out of sops, a token out of a keychain — rather than written down.
	var environmentCommands: [String: String] {
		guard case let .object(fields)? = extra("envCommands") else { return [:] }
		return fields.compactMapValues { value in
			guard case let .string(command) = value else { return nil }
			return command
		}
	}
}

/// Running the commands that produce environment values.
public enum ShellEnvironment {
	/// Evaluates each command in a login shell and returns what it printed.
	///
	/// A login shell because these reach for tools — sops, gpg, a cloud CLI —
	/// that live wherever the user's profile puts them, which is not on a GUI
	/// application's PATH. Failures are reported rather than swallowed: a
	/// program started without its credentials fails later and less clearly.
	public static func evaluate(
		_ commands: [String: String],
		in directory: URL
	) async -> (values: [String: String], failures: [String: String]) {
		var values: [String: String] = [:]
		var failures: [String: String] = [:]

		for (name, command) in commands.sorted(by: { $0.key < $1.key }) {
			let result = await run("printf %s \"\(command)\"", in: directory)
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
			if result.exitCode == 0, !output.isEmpty {
				values[name] = output
			} else {
				failures[name] = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
			}
		}
		return (values, failures)
	}

	/// What the shell that will run the command already has in these variables.
	///
	/// **Not `ProcessInfo.processInfo.environment`, and the difference is the
	/// whole point.** That is *this app's* environment, and an app launched from
	/// the Finder has launchd's — not the one a login shell builds from somebody's
	/// profile, and not the one an environment agent injects into terminals. So
	/// asking it whether `JAVA_TOOL_OPTIONS` is set answers about the wrong
	/// process: it says no, the caller writes the variable as though it were
	/// starting from nothing, and `env VAR=…` in front of the command then
	/// *replaces* what the shell would have supplied.
	///
	/// That was measured, not imagined: a client launched this way lost
	/// `-Djavax.net.ssl.trustStore` and failed to log in, reporting
	/// `SSL error. Check cacerts (<default>)` — a store that was not wrong but
	/// absent.
	///
	/// One shell for all of them, and unset is left out rather than returned
	/// empty, so a caller can tell "not set" from "set to nothing".
	/// - Parameter preparing: shell run before the variables are read. For tests,
	///   which cannot export anything into a shell they do not start.
	public static func values(
		of names: [String],
		in directory: URL,
		preparing: String = ""
	) async -> [String: String] {
		guard !names.isEmpty else { return [:] }

		// A record separator between them, because these hold whitespace and
		// quotes and a newline-separated answer cannot be taken apart again.
		//
		// The stand-in for "not set" is the literal text below rather than a
		// control character: `${VAR-…}` does not interpret escapes, so whatever
		// is written there arrives as itself. Only printf's own format is
		// interpreted, which is why the separator can be `\037` and this cannot.
		let script = names
			.map { "printf '%s\\037' \"${\($0)-\\036}\"" }
			.joined(separator: "; ")

		let line = preparing.isEmpty ? script : preparing + "; " + script
		let result = await run(line, in: directory)
		guard result.exitCode == 0 else { return [:] }

		let fields = result.output.components(separatedBy: "\u{1f}")
		var values: [String: String] = [:]
		for (name, field) in zip(names, fields) where field != unsetMarker {
			values[name] = field
		}
		return values
	}

	/// What a variable that is not set comes back as. See `values(of:in:)`.
	static let unsetMarker = "\\036"

	public static func run(
		_ line: String,
		in directory: URL,
		environment: [String: String] = [:]
	) async -> (exitCode: Int32, output: String, error: String) {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/bin/sh")
				process.arguments = ["-lc", line]
				process.currentDirectoryURL = directory
				if !environment.isEmpty {
					process.environment = ProcessInfo.processInfo.environment
						.merging(environment) { _, new in new }
				}

				let out = Pipe(), err = Pipe()
				process.standardOutput = out
				process.standardError = err

				do {
					try process.run()
				} catch {
					continuation.resume(returning: (127, "", error.localizedDescription))
					return
				}
				let captured = ProcessPipes.drainText(process, out: out, err: err)

				continuation.resume(returning: (
					process.terminationStatus,
					captured.stdout,
					captured.stderr
				))
			}
		}
	}
}

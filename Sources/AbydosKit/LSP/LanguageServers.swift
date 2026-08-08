import Foundation

/// How to start a language server.
public struct LanguageServerDefinition: Equatable, Sendable {
	/// The languages it answers for, as the editor names them.
	public let languageIds: [String]
	/// The command, looked up on the path.
	public let command: String
	public let arguments: [String]
	/// Where to get it, said in the one sentence somebody needs when it is
	/// missing rather than left as "no language server found".
	public let installHint: String
	/// A file that marks the root of a project this server understands, so a
	/// Go server is not started for a repository with one `.go` file in a
	/// vendored directory.
	public let rootMarkers: [String]
	/// Anything this server needs worked out per project rather than stated
	/// once here.
	public let setup: Setup

	/// Servers that cannot be started from a fixed command line.
	///
	/// Most can: the command takes no arguments, or the same two every time.
	/// One cannot, and pretending otherwise would mean either a stringly-typed
	/// escape hatch in the table or a special case at every call site.
	public enum Setup: String, Equatable, Sendable {
		case plain
		/// jdtls keeps a compiled index per project and will not share one
		/// between two, so each project is given a data directory of its own;
		/// and its debugger arrives as an Eclipse bundle that has to be named in
		/// the initialize request or it is never loaded.
		case java
		/// sourcekit-lsp builds the package to index it, and by default builds
		/// it into the package's own `.build` — the directory a terminal build
		/// uses. Two builds in one directory take turns holding its lock and
		/// invalidate each other's work, and where the toolchains differ they
		/// rebuild the world in turn: on this machine a nine-second incremental
		/// build took ten minutes while the indexer had it. It is given a
		/// directory of its own.
		case swift
	}

	public init(
		languageIds: [String],
		command: String,
		arguments: [String] = [],
		installHint: String,
		rootMarkers: [String] = [],
		setup: Setup = .plain
	) {
		self.languageIds = languageIds
		self.command = command
		self.arguments = arguments
		self.installHint = installHint
		self.rootMarkers = rootMarkers
		self.setup = setup
	}
}

/// Which server answers for which language, and whether it is installed.
///
/// No server is bundled and none is installed on anybody's behalf. A language
/// server is a large program with opinions about your toolchain, and the one
/// already on the machine — the one matching the compiler actually being used
/// — is nearly always the right one.
public enum LanguageServers {
	public static let known: [LanguageServerDefinition] = [
		LanguageServerDefinition(
			languageIds: ["swift"],
			command: "sourcekit-lsp",
			installHint: "Comes with Xcode and with the Swift toolchain.",
			rootMarkers: ["Package.swift", "*.xcodeproj", "compile_commands.json"],
			setup: .swift
		),
		LanguageServerDefinition(
			languageIds: ["go"],
			command: "gopls",
			installHint: "go install golang.org/x/tools/gopls@latest",
			rootMarkers: ["go.mod", "go.work"]
		),
		LanguageServerDefinition(
			languageIds: ["rust"],
			command: "rust-analyzer",
			installHint: "rustup component add rust-analyzer",
			rootMarkers: ["Cargo.toml"]
		),
		LanguageServerDefinition(
			languageIds: ["typescript", "javascript", "tsx", "jsx"],
			command: "typescript-language-server",
			arguments: ["--stdio"],
			// The 5 is not a preference, it is the only thing that works.
			// TypeScript 7 is the native compiler and ships no `tsserver.js`;
			// typescript-language-server drives exactly that file, so the pair
			// installed without a version starts, answers the handshake with
			// "Could not find a valid TypeScript installation", and exits.
			installHint: "npm install -g typescript-language-server typescript@5",
			rootMarkers: ["package.json", "tsconfig.json"]
		),
		LanguageServerDefinition(
			languageIds: ["python"],
			command: "pyright-langserver",
			arguments: ["--stdio"],
			installHint: "npm install -g pyright",
			rootMarkers: ["pyproject.toml", "setup.py", "requirements.txt"]
		),
		LanguageServerDefinition(
			languageIds: ["c", "cpp", "objc"],
			command: "clangd",
			installHint: "Comes with Xcode's toolchain, or: brew install llvm",
			rootMarkers: ["compile_commands.json", "CMakeLists.txt"]
		),
		LanguageServerDefinition(
			languageIds: ["java"],
			command: "jdtls",
			installHint: "brew install jdtls",
			// A build file, and not `*.java`: rooting jdtls at the first
			// directory that happens to hold a source file gets a project with no
			// classpath, which answers nothing and explains nothing.
			rootMarkers: [
				"pom.xml", "build.gradle", "build.gradle.kts",
				"settings.gradle", "settings.gradle.kts", ".classpath",
			],
			setup: .java
		),
		LanguageServerDefinition(
			languageIds: ["json"],
			command: "vscode-json-language-server",
			arguments: ["--stdio"],
			installHint: "npm install -g vscode-langservers-extracted",
			rootMarkers: []
		),
		LanguageServerDefinition(
			languageIds: ["plantuml"],
			command: "plantuml-lsp",
			installHint: "go install github.com/ptdewey/plantuml-lsp@latest",
			rootMarkers: []
		),
		LanguageServerDefinition(
			languageIds: ["openscad"],
			command: "openscad-lsp",
			// It listens on a TCP port unless told otherwise, and this client
			// speaks over a pipe. Without this the server starts, waits on
			// 127.0.0.1:3245 for a client that never arrives, and the editor
			// waits for a handshake that never comes.
			arguments: ["--stdio"],
			installHint: "cargo install openscad-lsp",
			// OpenSCAD has no manifest to look for — a model is a file, and a
			// project is a directory of them. Anywhere a `.scad` is opened is a
			// place this server can answer.
			rootMarkers: []
		),
	]

	public static func definition(forLanguage languageId: String) -> LanguageServerDefinition? {
		known.first { $0.languageIds.contains(languageId) }
	}

	/// Where the command lives, or nil if it is not installed.
	///
	/// A GUI app inherits almost nothing of a login shell's `PATH`, so the
	/// usual places are searched explicitly. Without this, everything works
	/// from a terminal and nothing works from the Dock.
	public static func executable(for definition: LanguageServerDefinition) -> String? {
		if definition.command.contains("/") {
			return FileManager.default.isExecutableFile(atPath: definition.command) ? definition.command : nil
		}

		for directory in searchPaths {
			let candidate = (directory as NSString).appendingPathComponent(definition.command)
			if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
		}

		// Swift's server is usually reached through xcrun rather than sitting
		// on the path at all.
		if definition.command == "sourcekit-lsp", let found = xcrunPath(for: "sourcekit-lsp") {
			return found
		}
		return nil
	}

	/// Directories searched for a server, in order.
	///
	/// Three sources, and the order is the point. What this process was given
	/// first, so a PATH somebody set deliberately still chooses the toolchain;
	/// then the PATH their login shell has, which is where a version manager
	/// puts things and the only source that keeps up with them; then the
	/// well-known directories, as a floor for when the shell cannot be asked.
	public static var searchPaths: [String] {
		var paths: [String] = []
		if let environment = ProcessInfo.processInfo.environment["PATH"] {
			paths += environment.split(separator: ":").map(String.init)
		}
		paths += UserShell.loginPath
		paths += toolDirectories

		var seen = Set<String>()
		return paths.filter { seen.insert($0).inserted }
	}

	/// Where a toolchain lives when `PATH` does not say.
	public static var toolDirectories: [String] {
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		return [
			"/opt/homebrew/bin",
			"/usr/local/bin",
			"/usr/bin",
			"/bin",
			"/usr/local/go/bin",
			"\(home)/go/bin",
			"\(home)/.cargo/bin",
			"\(home)/.local/bin",
			"\(home)/.bun/bin",
			"\(home)/.volta/bin",
		]
	}

	// MARK: - Starting one

	/// The command line for a server in a project.
	///
	/// The same arguments every time for all but one of them. jdtls is told
	/// where to keep this project's index, which is not something a fixed table
	/// can say.
	public static func arguments(for definition: LanguageServerDefinition, root: URL) -> [String] {
		switch definition.setup {
		case .plain:
			return definition.arguments
		case .java:
			return definition.arguments + ["-data", JavaTooling.serverWorkspace(for: root).path]
		case .swift:
			return definition.arguments + ["--scratch-path", indexScratchPath(for: root).path]
		}
	}

	/// Where the Swift indexer builds, which is not where anybody else does.
	///
	/// Beside the caches rather than in the project: it is derived data, it can
	/// be thrown away at any time, and a directory inside the checkout is one
	/// more thing to add to an ignore file and one more thing to search by
	/// accident.
	public static func indexScratchPath(for root: URL) -> URL {
		let path = FilePath.canonical(root)
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSTemporaryDirectory())
		return caches
			.appendingPathComponent("abydos/index", isDirectory: true)
			.appendingPathComponent("\(root.lastPathComponent)-\(shortHash(path))", isDirectory: true)
	}

	/// Enough of a hash to keep two projects of the same name apart.
	static func shortHash(_ text: String) -> String {
		var hash: UInt64 = 0xCBF2_9CE4_8422_2325
		for byte in text.utf8 {
			hash ^= UInt64(byte)
			hash = hash &* 0x0000_0100_0000_01B3
		}
		return String(hash, radix: 36)
	}

	/// Anything that has to exist on disk before the server is started.
	///
	/// Only jdtls needs this, and only to be given a directory it can write its
	/// index into. Failing is not fatal — jdtls creates the directory itself
	/// when it can — so nothing is thrown.
	public static func prepare(_ definition: LanguageServerDefinition, root: URL) {
		switch definition.setup {
		case .java:
			try? FileManager.default.createDirectory(
				at: JavaTooling.serverWorkspace(for: root), withIntermediateDirectories: true
			)
		case .swift:
			try? FileManager.default.createDirectory(
				at: indexScratchPath(for: root), withIntermediateDirectories: true
			)
		case .plain:
			break
		}
	}

	/// What to send as `initializationOptions`, or nil when there is nothing to
	/// say.
	///
	/// This is where jdtls learns two things it cannot work out for itself: the
	/// JDKs installed here, so a project targeting 17 is compiled against 17
	/// rather than against whatever the server happens to run on, and the
	/// java-debug bundle, without which there is no debugging at all.
	public static func initializationOptions(
		for definition: LanguageServerDefinition,
		root: URL
	) -> [String: Any]? {
		guard definition.setup == .java else { return nil }

		var options: [String: Any] = [:]
		if let plugin = JavaTooling.debugPlugin() { options["bundles"] = [plugin] }
		options["workspaceFolders"] = [root.absoluteString]

		let installed = JavaTooling.installedRuntimes()
		let runtimes = installed.enumerated().map { index, runtime -> [String: Any] in
			[
				"name": runtime.name,
				"path": runtime.home,
				// The newest is the default a project falls back to when its build
				// file does not say. They are sorted newest first.
				"default": index == 0,
			]
		}

		options["settings"] = [
			"java": [
				"configuration": [
					"runtimes": runtimes,
					// The build file is the truth about the classpath, and it
					// changes while you work. Left to "interactive", jdtls asks
					// with a dialog this app does not show, so the answer would be
					// no for ever and the classpath would go stale.
					"updateBuildConfiguration": "automatic",
				],
				"import": [
					"maven": ["enabled": true],
					// The wrapper, not whatever gradle is on the path: a project
					// pins its Gradle version for the same reason it pins its
					// dependencies.
					"gradle": ["enabled": true, "wrapper": ["enabled": true]],
				],
				// This editor formats nothing, and a server that thinks it does
				// spends time preparing an answer nobody asks for.
				"format": ["enabled": false],
			],
		]
		return options
	}

	/// The environment to start a server in.
	///
	/// Finding the server is only half of it: a language server is a front end
	/// for a compiler, and it shells out to the one on its `PATH`. An app
	/// launched from the Dock has `/usr/bin:/bin` and the two sbins — so `gopls`
	/// starts, answers the handshake, and then cannot run `go`. What it says
	/// then is "No active builds contain main.go", which sounds like a fact
	/// about the project rather than about this app's environment, and the
	/// symptom is an editor that shows diagnostics and answers nothing else.
	///
	/// The same directories the server itself was found in, appended rather than
	/// prepended: a `PATH` somebody set deliberately still chooses the toolchain.
	public static var serverEnvironment: [String: String] {
		var environment = ProcessInfo.processInfo.environment
		environment["PATH"] = searchPaths.joined(separator: ":")
		// jdtls is a Java program before it is a language server, and its
		// launcher looks for a JVM in `JAVA_HOME` before it looks anywhere else.
		// Unset — which is what a Dock-launched app has — it falls back to
		// `/usr/bin/java`, the stub that opens a download page.
		if environment["JAVA_HOME"] == nil, let home = JavaTooling.javaHome() {
			environment["JAVA_HOME"] = home
		}
		return environment
	}

	private static func xcrunPath(for tool: String) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["--find", tool]
		let output = Pipe()
		process.standardOutput = output
		process.standardError = Pipe()

		guard (try? process.run()) != nil else { return nil }
		let data = ProcessPipes.drain(process, out: output)
		guard process.terminationStatus == 0 else { return nil }

		let path = String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return FileManager.default.isExecutableFile(atPath: path) ? path : nil
	}

	/// Whether a project looks like one this server should be started for.
	///
	/// A server with no markers is happy anywhere; one with markers wants to
	/// see at least one of them, so opening a repository that happens to
	/// contain a stray `.py` file does not start a Python server for it.
	public static func suits(_ definition: LanguageServerDefinition, root: URL) -> Bool {
		markerDirectory(for: definition, in: root) != nil
	}

	/// Where this server should be rooted, or nil if the project is not one it
	/// understands.
	///
	/// Not only the project root. A repository commonly keeps its manifest a
	/// level or two down — `app/go.mod`, `backend/Cargo.toml` — and rooting a
	/// server at a directory with no manifest in it gets nothing: no symbols,
	/// no diagnostics, no go-to-definition, and no explanation either.
	public static func markerDirectory(
		for definition: LanguageServerDefinition,
		in root: URL,
		maxDepth: Int = 2
	) -> URL? {
		guard !definition.rootMarkers.isEmpty else { return root }
		if holdsMarker(definition, at: root) { return root }
		guard maxDepth > 0 else { return nil }

		let manager = FileManager.default
		let skipped: Set<String> = ["node_modules", "vendor", ".build", ".git", "target", "dist"]
		let contents = (try? manager.contentsOfDirectory(
			at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
		)) ?? []

		// Breadth first, so a manifest one level down wins over one three
		// levels down inside an example.
		let directories = contents.filter {
			(try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
				&& !skipped.contains($0.lastPathComponent)
		}
		for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
		where holdsMarker(definition, at: directory) {
			return directory
		}
		for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
			if let found = markerDirectory(for: definition, in: directory, maxDepth: maxDepth - 1) {
				return found
			}
		}
		return nil
	}

	private static func holdsMarker(_ definition: LanguageServerDefinition, at directory: URL) -> Bool {
		let manager = FileManager.default
		for marker in definition.rootMarkers {
			if marker.hasPrefix("*.") {
				let suffix = String(marker.dropFirst(1))
				let contents = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
				if contents.contains(where: { $0.hasSuffix(suffix) }) { return true }
			} else if manager.fileExists(atPath: directory.appendingPathComponent(marker).path) {
				return true
			}
		}
		return false
	}

	/// A server that would answer for the file on screen, and is not installed.
	public struct Suggestion: Equatable, Sendable {
		public let languageId: String
		/// What the language is called in a sentence — "Go", not "go".
		public let languageName: String
		public let command: String
		public let installHint: String

		public init(languageId: String, languageName: String, command: String, installHint: String) {
			self.languageId = languageId
			self.languageName = languageName
			self.command = command
			self.installHint = installHint
		}

		/// The manual, for whoever wants to do something about it.
		///
		/// Everything somebody needs and nothing they have to look up: what it
		/// is for, the one command, where the binary has to end up, and how to
		/// tell whether it worked. The list of directories is the app's own — a
		/// GUI app inherits almost no PATH, so "it is on my PATH" and "this app
		/// can find it" are not the same sentence, and that difference has cost
		/// real hours.
		public var manual: String {
			let directories = LanguageServers.toolDirectories
				.map { "  \($0)" }
				.joined(separator: "\n")

			return """
			\(languageName) files get completion, problems, go-to-declaration and
			find-usages from \(command), which is not installed on this machine.

			INSTALL

			  \(installHint)

			WHERE IT HAS TO END UP

			This app is usually launched from the Dock, and an app launched that way
			inherits almost none of a login shell's PATH. So it looks for a server on
			the PATH it does have, and then in these directories:

			\(directories)

			A server installed by the command above lands in one of them. One built by
			hand somewhere else will not be found, however well `which \(command)`
			answers in a terminal.

			CHECKING

			  which \(command)

			AFTERWARDS

			Nothing to restart. The next file of this kind you open starts the server,
			and this bar stops appearing.
			"""
		}
	}

	/// What is worth saying about the file in front of somebody, if anything.
	///
	/// Nil unless all of it holds: this language has a server, this project is
	/// one that server understands, the server is not installed, and nobody has
	/// said they do not want to hear about this language. Anything else and
	/// there is nothing to offer — an editor that suggests installing something
	/// you already have, or that cannot help with the project you are in, is an
	/// editor people learn to ignore.
	///
	/// `ignoring` is passed in rather than read from the settings so this can
	/// be decided without one.
	public static func suggestion(
		forLanguage languageId: String,
		root: URL,
		ignoring: Set<String> = []
	) -> Suggestion? {
		guard let definition = definition(forLanguage: languageId) else { return nil }
		return suggestion(definition, forLanguage: languageId, root: root, ignoring: ignoring)
	}

	/// Split out so the decision can be tested with a server that is certainly
	/// missing, on a machine where the real ones may be installed or not.
	static func suggestion(
		_ definition: LanguageServerDefinition,
		forLanguage languageId: String,
		root: URL,
		ignoring: Set<String>
	) -> Suggestion? {
		guard !ignoring.contains(languageId) else { return nil }
		guard suits(definition, root: root) else { return nil }
		guard executable(for: definition) == nil else { return nil }
		return Suggestion(
			languageId: languageId,
			languageName: LanguageRegistry.shared.displayName(for: languageId),
			command: definition.command,
			installHint: definition.installHint
		)
	}

	/// The server to start for a language in a project, if there is one and it
	/// is installed.
	/// The server to start for a language in a project: which one, where it
	/// lives, and which directory to root it at.
	public static func resolve(
		languageId: String,
		root: URL
	) -> (definition: LanguageServerDefinition, executable: String, root: URL)? {
		guard let definition = definition(forLanguage: languageId),
		      let serverRoot = markerDirectory(for: definition, in: root),
		      let executable = executable(for: definition)
		else { return nil }
		return (definition, executable, serverRoot)
	}
}

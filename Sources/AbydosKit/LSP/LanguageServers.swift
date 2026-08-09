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
	/// What this server is called where an image is chosen for it — in settings
	/// and in `.abydos/tools.json`.
	///
	/// Usually the command, and not always: Python's server ships a binary
	/// called `pyright-langserver`, and the tool everybody means by that is
	/// `pyright`. A key nobody would think to type is a setting nothing reads.
	public let toolKey: String
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
		toolKey: String? = nil,
		setup: Setup = .plain
	) {
		self.languageIds = languageIds
		self.command = command
		self.arguments = arguments
		self.installHint = installHint
		self.rootMarkers = rootMarkers
		self.toolKey = toolKey ?? command
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
			rootMarkers: ["pyproject.toml", "setup.py", "requirements.txt"],
			toolKey: "pyright"
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

	/// Whether a project's servers are still somebody's, now that one window has
	/// finished with it.
	///
	/// The question that has to be asked before stopping them, and the reason it
	/// is not simply "this window has closed": a torn-off window shares its
	/// project with the window it was dragged out of, and two windows can be
	/// opened on the same checkout. Stopping a server that another window is
	/// still asking questions of is worse than leaving it running, because a
	/// leak shows up in `ps` and a missing answer shows up as nothing at all.
	///
	/// - Parameter others: what the other windows are showing. The window doing
	///   the asking is not among them — mid-switch it is still holding the
	///   project it is leaving.
	public static func serversAreStillWanted(for project: URL, shownBy others: [URL]) -> Bool {
		let path = project.standardizedFileURL.path
		return others.contains { $0.standardizedFileURL.path == path }
	}

	/// Where the command lives, or nil if it is not installed.
	///
	/// Two searches, and which one goes first is the whole point.
	///
	/// A tool Xcode owns is asked of Xcode, before the `PATH` is looked at at
	/// all: `sourcekit-lsp` and `clangd` are shipped by every toolchain manager
	/// as well, and the first one on a login shell's `PATH` is swiftly's — a
	/// release older than the SDK the build uses. Measured here: the servers
	/// answering were `~/.swiftly/bin/sourcekit-lsp` while `xcrun` had Xcode's
	/// all along. See `XcodeToolchain` for what that costs.
	///
	/// Everything else is looked for on the `PATH` and then in the usual homes,
	/// because a GUI app inherits almost nothing of a login shell's `PATH`.
	/// Without that half, everything works from a terminal and nothing works
	/// from the Dock.
	public static func executable(for definition: LanguageServerDefinition) -> String? {
		if definition.command.contains("/") {
			return FileManager.default.isExecutableFile(atPath: definition.command) ? definition.command : nil
		}

		if XcodeToolchain.owns(definition.command),
		   let found = XcodeToolchain.path(for: definition.command) {
			return found
		}

		for directory in searchPaths {
			let candidate = (directory as NSString).appendingPathComponent(definition.command)
			if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
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
	/// - Parameter inContainer: whether the server is running from an image, in
	///   which case the things on this machine cannot be offered to it. The JDKs
	///   and the debug bundle are paths, and a path here names nothing there —
	///   an image that wants a JDK has to carry one, which is what the tool
	///   catalogue tells whoever builds it.
	public static func initializationOptions(
		for definition: LanguageServerDefinition,
		root: URL,
		inContainer: Bool = false
	) -> [String: Any]? {
		guard definition.setup == .java else { return nil }

		var options: [String: Any] = [:]
		if !inContainer, let plugin = JavaTooling.debugPlugin() { options["bundles"] = [plugin] }
		options["workspaceFolders"] = [root.absoluteString]

		let installed = inContainer ? [] : JavaTooling.installedRuntimes()
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

	/// A server to start: which one, where it is rooted, and how it starts.
	public struct Resolution: Equatable, Sendable {
		public let definition: LanguageServerDefinition
		/// Where the server is rooted, named on this machine. The launch says
		/// what the server itself will call it.
		public let root: URL
		public let launch: LanguageServerLaunch

		public init(definition: LanguageServerDefinition, root: URL, launch: LanguageServerLaunch) {
			self.definition = definition
			self.root = root
			self.launch = launch
		}
	}

	/// The server to start for a language in a project: which one, where it
	/// lives, and which directory to root it at.
	///
	/// - Parameters:
	///   - project: the checkout. This is what gets mounted, not the directory
	///     the server is rooted at: the manifest is often a level or two down,
	///     and a mount of that subdirectory would leave every file outside it
	///     with no name the container could use.
	///   - image: the image named for this server, if any.
	///   - runtime: what would run it. Nil — nothing installed to run a
	///     container with — falls back to the copy on this machine, since an
	///     image nothing can run is not an answer.
	public static func resolve(
		languageId: String,
		project: URL,
		image: String? = nil,
		runtime: ContainerRuntime? = nil
	) -> Resolution? {
		guard let definition = definition(forLanguage: languageId),
		      let root = markerDirectory(for: definition, in: project)
		else { return nil }

		// An image the project named wins over a copy installed here, the same
		// way it does for a diagram: naming one is a statement about what this
		// project needs, and a local copy quietly overriding it would mean the
		// same code getting different answers on two machines.
		if let image, !image.isEmpty, let runtime {
			// Canonical, both sides. A server resolves a package by realpath,
			// and a mount named `/tmp/x` while the file it is sent is
			// `/private/tmp/x` is a mapping that matches nothing.
			let paths = ContainerPaths(host: FilePath.canonical(project))
			let container = ToolContainer(
				image: image,
				mounts: [paths.mount],
				// Started where the manifest is, in the container's own names.
				workingDirectory: paths.toContainer(path: FilePath.canonical(root)),
				// And named, so that stopping the server can also remove the
				// container it was running in. Terminating the `run` process does
				// not: the container keeps going, holding the mount and whatever
				// the server was doing to the project.
				name: ToolContainers.mint("lsp-\(definition.command)")
			)
			return Resolution(
				definition: definition,
				root: root,
				launch: .image(container: container, runtime: runtime, paths: paths)
			)
		}

		guard let executable = executable(for: definition) else { return nil }
		return Resolution(
			definition: definition,
			root: root,
			launch: .installed(
				executable: executable,
				arguments: arguments(for: definition, root: root)
			)
		)
	}

	/// The same, for a caller that only wants a server from this machine.
	public static func resolve(
		languageId: String,
		root: URL
	) -> (definition: LanguageServerDefinition, executable: String, root: URL)? {
		guard let resolution = resolve(languageId: languageId, project: root),
		      case let .installed(executable, _) = resolution.launch
		else { return nil }
		return (resolution.definition, executable, resolution.root)
	}
}

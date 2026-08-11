import Foundation

/// How to start a language server.
public struct LanguageServerDefinition: Equatable, Sendable {
	/// The languages it answers for, as the editor names them.
	///
	/// Not "the server for those languages": two servers may claim the same id,
	/// and which of them a project uses is `LanguageServerChoices`.
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
	/// What this server is called — the name a person types to ask for it, and
	/// the name it is filed under everywhere: the choice of server for a
	/// language, the image chosen for it, the running server in the list.
	///
	/// Distinct from the command, and it has to be. Usually they are the same
	/// word, and twice they are not: Python's server ships a binary called
	/// `pyright-langserver` while the tool everybody means by it is `pyright`,
	/// and — the reason this is a name rather than a key — two servers for one
	/// language cannot both be "the Java one". A name nobody would think to
	/// type is a setting nothing reads.
	public let name: String
	/// Anything this server needs worked out per project rather than stated
	/// once here.
	public let setup: Setup
	/// Directories this server reads that are not in the project, for the case
	/// where it runs from an image and can see only what it is given.
	///
	/// Empty for all but one of them, and it is worth saying why rather than
	/// generalising: what a server needs beyond the project is a fact about
	/// that server, and the three that plausibly want something differ in
	/// whether it is the answer or a saving. kmp-lsp resolves a dependency's
	/// source out of `~/.m2` and `~/.gradle`, so without them it indexes the
	/// project perfectly and answers nothing at every dependency boundary —
	/// which is the state 0450's fork exists to end. gopls would like
	/// `~/go/pkg/mod`, but `ToolImages/gopls/Dockerfile` carries a module cache
	/// of its own and an empty one costs a download rather than an answer.
	/// jdtls builds its classpath by *running* Maven, which fetches what it is
	/// missing, and a read-only `~/.m2` would break that rather than help it.
	///
	/// So this is a list, in a table, one line per server, and the line is
	/// added when somebody has driven it — not a rule applied to all of them
	/// from one case that happened to be measured.
	public let outside: [OutsideDirectory]

	/// Whether what this server knows about the code is its text rather than its
	/// types.
	///
	/// It changes nothing about a question and everything about an *answer that
	/// changes files*. A go-to-definition from a syntactic server that lands in
	/// the wrong place costs a keystroke to undo; a rename from one is a
	/// substitution over what it indexed, so a method called `size()` on two
	/// unrelated classes is one name to it, and renaming one renames both — in
	/// forty files, some of which nobody had open.
	///
	/// So this is not a rating of servers. It is the one fact somebody needs
	/// before they accept a refactoring, and 0449 made it possible for a project
	/// to be pointed at such a server without the person at the editor knowing.
	public let isSyntactic: Bool

	/// What choosing this server costs and what it buys, in one line, for the
	/// page where somebody chooses.
	///
	/// Nil for every server that has no competition, because a language with one
	/// server offers no trade to describe — "gopls, the only one Abydos has" is
	/// already the whole answer. Set on the two that do, and 0449 asked for it in
	/// exactly those words: a menu offering two Java servers should say what the
	/// choice is between rather than two bare names.
	///
	/// 0449 left it to 0450, which knew what kmp-lsp trades away, and 0450 wrote
	/// it into its own entry rather than onto the screen. 0452 is what makes it a
	/// sentence somebody reads, and it is also what changed one of the two: the
	/// debugger no longer goes with the choice.
	public let trade: String?

	/// A directory outside the project that a server has to be able to read.
	///
	/// Named on both sides. The host side is relative to the home directory,
	/// because that is what these are — a person's caches, not a machine's —
	/// and an absolute path in a table would be one user's. The container side
	/// is written out rather than derived, because deriving it means guessing
	/// what `$HOME` is inside somebody's image, and a mount at the wrong place
	/// in there is not an error: the server starts, finds an empty cache and
	/// says nothing about it.
	public struct OutsideDirectory: Equatable, Sendable {
		/// Where it is on this machine, under the home directory.
		public let home: String
		/// Where the image must see it.
		public let container: String
		/// Read-only unless the server has to write there.
		///
		/// A language server has no business writing to a dependency cache: it
		/// reads jars out of it, and a mount that lets it do more than that is
		/// a mount that can corrupt somebody's build on a machine where the
		/// editor is the newcomer. The exception is a directory that is the
		/// server's *own* scratch, and even that is only writable because what
		/// it writes has to be readable from this side afterwards.
		public let isReadOnly: Bool

		public init(home: String, container: String, isReadOnly: Bool = true) {
			self.home = home
			self.container = container
			self.isReadOnly = isReadOnly
		}
	}

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

	/// Whether the debug adapter for this language can be loaded *into* this
	/// server.
	///
	/// `.java` is exactly that set, and it is the setup rather than the name for
	/// the reason 0449 gave: a name would go stale the day jdtls is packaged under
	/// another one. Named here rather than written as `setup == .java` at every
	/// call site, because since 0452 there are several and one of them asks the
	/// question of a server the project did *not* choose — which reads as a
	/// mistake unless the predicate says what it is for.
	public var hostsDebugAdapter: Bool { setup == .java }

	public init(
		languageIds: [String],
		command: String,
		arguments: [String] = [],
		installHint: String,
		rootMarkers: [String] = [],
		name: String? = nil,
		setup: Setup = .plain,
		outside: [OutsideDirectory] = [],
		isSyntactic: Bool = false,
		trade: String? = nil
	) {
		self.languageIds = languageIds
		self.command = command
		self.arguments = arguments
		self.installHint = installHint
		self.rootMarkers = rootMarkers
		self.name = name ?? command
		self.setup = setup
		self.outside = outside
		self.isSyntactic = isSyntactic
		self.trade = trade
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
			name: "pyright"
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
			setup: .java,
			trade: "type-aware, and a JVM. It reads the build file for the classpath, so it "
				+ "knows a call has the wrong argument type — and importing a five-hundred-bundle "
				+ "reactor is minutes and gigabytes before it answers anything."
		),
		// The second opinion about Java, and the reason 0449's mechanism exists.
		// Rust and tree-sitter: no JVM, no reactor import, and no type checking
		// at all. Measured on Eclipse's `eclipse.platform.ui` — 143 bundles,
		// 7,566 Java files — it had the whole project indexed at 2.6 seconds and
		// answered go-to-definition across bundles, while jdtls on the same file
		// and the same position was still silent at ten minutes holding 3.97 GB.
		// On the smaller Sirius, 106 bundles, jdtls answered at 26 seconds and
		// this at 3.2. Neither is wrong: this one cannot tell you a type is
		// wrong, and it is the debugger's host that jdtls is (see
		// `JavaDebugFailure.wrongServer`).
		//
		// Listed after jdtls, so the default is unchanged and this is something a
		// project asks for. Java only, though it also answers for Kotlin and
		// Swift: Swift here means sourcekit-lsp and displacing it is not
		// something any measurement in 0450 supports, and nothing has driven its
		// Kotlin.
		//
		// The same root markers as jdtls, so the two are offered for exactly the
		// same projects. It needs no build file of its own — it indexes source —
		// but a server that started at the first directory holding a `.java`
		// would start in a vendored tree, which is the failure the markers are
		// for.
		LanguageServerDefinition(
			languageIds: ["java"],
			command: "kmp-lsp",
			installHint: "cargo install kmp-lsp",
			rootMarkers: [
				"pom.xml", "build.gradle", "build.gradle.kts",
				"settings.gradle", "settings.gradle.kts", ".classpath",
			],
			// The three directories it reads that are not in the project, and the
			// reason 0457 exists. Two are where a dependency's source actually is —
			// this server has no classpath and runs no build tool, so it finds a
			// library by walking the caches the build tools left behind — and the
			// third is where it puts a file unpacked out of a jar so that an editor
			// can open it. Without them a containerised kmp-lsp indexes the project
			// perfectly and answers `null` at every dependency boundary, which is
			// the state 0450's fork was written to end.
			//
			// The *caches*, not the tool homes. `~/.m2/settings.xml` and
			// `~/.gradle/gradle.properties` are where people keep registry
			// passwords and signing keys, and a language server has no reason to
			// see either. `~/.m2/repository` and `~/.gradle/caches` are jars.
			//
			// `/root`, because that is where `ToolImages/kmp-lsp/Dockerfile` puts
			// them — and that file sets `MAVEN_REPO_LOCAL`, `GRADLE_USER_HOME` and
			// `XDG_CACHE_HOME` to match rather than trusting `$HOME` to still be
			// `/root` in whatever the base image becomes.
			outside: [
				LanguageServerDefinition.OutsideDirectory(
					home: ".m2/repository", container: "/root/.m2/repository"
				),
				// `caches` rather than the whole of `~/.gradle`: the server looks
				// under `caches/modules-2/files-2.1`, and the rest of that
				// directory is the daemon's, the wrapper's, and the properties
				// file with the credentials in it.
				LanguageServerDefinition.OutsideDirectory(
					home: ".gradle/caches", container: "/root/.gradle/caches"
				),
				// The one that is written to, and it has to be. A go-to-definition
				// into a library is answered by unpacking one entry of a
				// `-sources.jar` to disk and returning a `file:` URI for it,
				// because that is what an editor can open. Unpacked inside the
				// container and nowhere else, that URI names a file this machine
				// does not have — an answer that looks right and opens nothing,
				// which is worse than the `null` it replaced.
				//
				// The same directory a copy installed here would use, rather than
				// one of our own beside it: it is that server's cache and it is
				// keyed by the path of the jar it came from, so the container's
				// entries and this machine's cannot collide.
				LanguageServerDefinition.OutsideDirectory(
					home: ".cache/kmp-lsp", container: "/root/.cache/kmp-lsp", isReadOnly: false
				),
			],
			// The one place this matters is 0453's rename. Everything above is
			// about what this server can *answer*, where being syntactic is a
			// trade somebody made on purpose; a rename is the first thing it can
			// be asked that changes files, and a substitution over an index is a
			// different promise from jdtls's. It renames — well, and fast — over
			// exactly the symbols it indexed, and two unrelated `size()` methods
			// are one symbol to it.
			isSyntactic: true,
			// Measured rather than described, and every number here is 0450's.
			// **The last clause is what 0452 changed**, and it is the reason this
			// line is worth having at all: until then, choosing this server cost the
			// debugger outright, and the page where somebody chose said nothing
			// about it.
			trade: "instant and syntactic. The whole project navigable in seconds for a fifth of "
				+ "the memory, no JVM — and no type checking at all, so nothing tells you a call "
				+ "has the wrong argument type and a rename matches names rather than symbols. "
				+ "Debugging still works: jdtls is started for the debugger alone when you press "
				+ "Debug, and that first Debug waits for it to import the project."
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

	// MARK: - Which server a language uses

	/// Which server a language uses here, and why it is that one.
	///
	/// Three answers rather than an optional, because the two ways of having no
	/// server are not the same thing to say. A language nothing answers for is
	/// silence — most files are in one. A server somebody *named* and that is
	/// not there is a sentence, and it must never quietly become the other
	/// server: choosing the fast one and getting the 1.9 GB one anyway is an
	/// afternoon of wondering why.
	public enum Selection: Equatable, Sendable {
		/// The server to start, and where the choice came from.
		case server(LanguageServerDefinition, source: LanguageServerChoices.Source)
		/// A server was named, and no server of that name answers for this
		/// language — either Abydos has never heard of it, or it has and it
		/// answers for something else.
		case noSuchServer(name: String, source: LanguageServerChoices.Source)
		/// Nothing here answers for this language at all.
		case nothing
	}

	/// Every server that claims a language, in the order they are listed above.
	///
	/// One today for each of them, several once there is a second opinion about
	/// a language — Java is the one this was written for. The order is the
	/// default: the first is what a project gets when it says nothing.
	///
	/// - Parameter servers: the table to look in, which is the app's own unless
	///   a test says otherwise. The seam exists because the mechanism for
	///   choosing between two servers was built before there were two: 0450 adds
	///   the second Java server, and this had to be provable without it rather
	///   than on the day it lands.
	public static func candidates(
		forLanguage languageId: String, among servers: [LanguageServerDefinition] = known
	) -> [LanguageServerDefinition] {
		servers.filter { $0.languageIds.contains(languageId) }
	}

	/// Every language that has more than one server to choose between, each
	/// with the ids that share that set of candidates.
	///
	/// Grouped because one server answers for several ids and a settings page
	/// with four rows saying the same thing about TypeScript, JavaScript, TSX
	/// and JSX is four rows nobody reads. Ids that have exactly the same
	/// candidates in the same order are the same question.
	public static func languageGroups(
		among servers: [LanguageServerDefinition] = known
	) -> [(languageIds: [String], candidates: [LanguageServerDefinition])] {
		var order: [[String]] = []
		var groups: [[String]: [String]] = [:]
		for definition in servers {
			for languageId in definition.languageIds {
				let names = candidates(forLanguage: languageId, among: servers).map(\.name)
				if groups[names] == nil {
					groups[names] = []
					order.append(names)
				}
				if !groups[names]!.contains(languageId) { groups[names]!.append(languageId) }
			}
		}
		return order.map { names in
			(
				languageIds: groups[names] ?? [],
				candidates: names.compactMap { server(named: $0, among: servers) }
			)
		}
	}

	public static func server(
		named name: String, among servers: [LanguageServerDefinition] = known
	) -> LanguageServerDefinition? {
		servers.first { $0.name == name }
	}

	/// The first language this server is the chosen one for, which is what a
	/// caller starting one server per definition should ask about.
	///
	/// Not `languageIds.first`, which is what every such caller used to say and
	/// which was right only while a language had one server. clangd answers for
	/// `c`, `cpp` and `objc`; a project that points `c` at something else still
	/// wants clangd, and starting it by asking about `c` would start the other
	/// one instead.
	public static func chosenLanguage(
		for definition: LanguageServerDefinition,
		choosing choices: LanguageServerChoices,
		among servers: [LanguageServerDefinition] = known
	) -> String? {
		definition.languageIds.first {
			self.definition(forLanguage: $0, choosing: choices, among: servers)?.name
				== definition.name
		}
	}

	/// Which server this project uses for a language.
	///
	/// - Parameter choices: what the project's `.abydos/tools.json` and the
	///   settings behind it say, already resolved. Passed in rather than read
	///   here: this is asked once per document opened and once per query, and a
	///   file read on the main actor at that rate is a keystroke somebody feels.
	public static func selection(
		forLanguage languageId: String,
		choosing choices: LanguageServerChoices,
		among servers: [LanguageServerDefinition] = known
	) -> Selection {
		let candidates = candidates(forLanguage: languageId, among: servers)
		guard let chosen = choices.chosen(forLanguage: languageId) else {
			guard let first = candidates.first else { return .nothing }
			return .server(first, source: .builtIn)
		}
		guard let named = candidates.first(where: { $0.name == chosen.name }) else {
			return .noSuchServer(name: chosen.name, source: chosen.source)
		}
		return .server(named, source: chosen.source)
	}

	/// The server for a language, or nil when there is not one to start.
	///
	/// The thin answer, for the callers that only want to know what to run.
	/// Anything that has to *say* why there is nothing wants `selection`.
	public static func definition(
		forLanguage languageId: String,
		choosing choices: LanguageServerChoices,
		among servers: [LanguageServerDefinition] = known
	) -> LanguageServerDefinition? {
		guard case let .server(definition, _) = selection(
			forLanguage: languageId, choosing: choices, among: servers
		) else { return nil }
		return definition
	}

	/// What to say when a project asked for a server that will not be started.
	///
	/// The whole of it in one paragraph, because the person reading it is
	/// looking at a file with no diagnostics and needs three things: what they
	/// asked for, where they asked for it, and what they can ask for instead.
	/// The last sentence is the one that matters — nothing has been started in
	/// its place, so nobody goes looking for a fault in a server that is not
	/// running.
	public static func refusal(
		named name: String,
		forLanguage languageId: String,
		source: LanguageServerChoices.Source,
		among servers: [LanguageServerDefinition] = known
	) -> String {
		let language = LanguageRegistry.shared.displayName(for: languageId)
		let reason: String
		if let elsewhere = server(named: name, among: servers) {
			let answersFor = elsewhere.languageIds
				.map { LanguageRegistry.shared.displayName(for: $0) }
				.joined(separator: ", ")
			reason = "\(name) is a language server Abydos knows, but it answers for "
				+ "\(answersFor) rather than for \(language)."
		} else {
			reason = "Abydos has no language server called \(name)."
		}

		let others = candidates(forLanguage: languageId, among: servers).map(\.name)
		let instead = others.isEmpty
			? "Abydos has no \(language) server at all."
			: "For \(language) it has: \(others.joined(separator: ", "))."

		return "\(source.origin) asks for \(name) to answer for \(language). \(reason) "
			+ "\(instead) Nothing has been started in its place — a server you did not "
			+ "choose would answer as though you had chosen it."
	}

	/// What a project's running server is held under: the project and the
	/// *server*, not the project and the language.
	///
	/// One definition answers for several language ids — clangd for `c`, `cpp`
	/// and `objc`; typescript-language-server for four — so a table keyed by the
	/// id started a second copy of the same program the first time somebody
	/// opened a `.cpp` beside a `.c`. Measured, with two files open in one
	/// project: two `clangd`, each indexing the same compilation database.
	///
	/// The server's name rather than its command, since that is what the same
	/// server is called everywhere else: where an image is chosen for it, and
	/// where a project chooses it.
	///
	/// A named server nobody can find keeps its own key, under the name that was
	/// asked for. It has to: everything remembered about the failure hangs off
	/// this key, and filing it under the server that was *not* chosen would mean
	/// changing the file from one to the other and being told about the old one.
	///
	/// The project is standardized, so two windows on one checkout — a torn-off
	/// window and the one it came from, the same path spelled with and without a
	/// trailing slash — hold the same server rather than one each.
	public static func serverKey(
		project: URL, languageId: String, choosing choices: LanguageServerChoices,
		among servers: [LanguageServerDefinition] = known
	) -> String {
		let server: String
		switch selection(forLanguage: languageId, choosing: choices, among: servers) {
		case let .server(definition, _): server = definition.name
		case let .noSuchServer(name, _): server = name
		case .nothing: server = languageId
		}
		return serverKey(project: project, server: server)
	}

	/// The same key, for a caller that already knows which server it means.
	///
	/// Where a tool comes from is settled under the tool's own name and never
	/// under a language, so a change to an image is a sentence about one of
	/// these keys directly. Written once here rather than spelled out again at
	/// the two call sites: the format is what makes an entry findable, and two
	/// places agreeing by eye is the sort of thing that stops being true.
	public static func serverKey(project: URL, server name: String) -> String {
		"\(project.standardizedFileURL.path)#\(name)"
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
	/// Everything else goes to `Executables`, which is the one search this app
	/// has: the `PATH` this process was given, then the one the person's login
	/// shell has, then the usual homes. A GUI app inherits almost nothing of a
	/// login shell's `PATH`, and without that middle source everything works
	/// from a terminal and nothing works from the Dock.
	public static func executable(for definition: LanguageServerDefinition) -> String? {
		if definition.command.contains("/") {
			return FileManager.default.isExecutableFile(atPath: definition.command) ? definition.command : nil
		}

		if XcodeToolchain.owns(definition.command),
		   let found = XcodeToolchain.path(for: definition.command) {
			return found
		}

		return Executables.locate(definition.command)
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

	/// The directories this server needs beyond the project, as mounts, for the
	/// ones this machine actually has.
	///
	/// Two decisions live here and both are about a directory that is not there,
	/// which is an ordinary machine rather than a broken one — a person who has
	/// never run Maven has no `~/.m2`, and a bind mount of a path that does not
	/// exist is a runtime error on Apple's `container` and a root-owned empty
	/// directory conjured into somebody's home folder on docker. Neither is an
	/// acceptable thing to do to a machine because an editor was opened.
	///
	/// - **A read-only directory that is not there is left out.** There is
	///   nothing to show the server, and saying so by not mounting it is exactly
	///   true: it then reports no jars, which is the fact.
	/// - **A writable one is created.** It is not somebody's cache, it is the
	///   server's own scratch, and the reason it is mounted at all is that this
	///   side has to be able to read what gets written into it. Left out, the
	///   server writes inside the container instead and hands back the name of a
	///   file that exists nowhere here.
	///
	/// - Parameter home: this machine's home directory. A parameter rather than
	///   `NSHomeDirectory()` read in here, so that a test can drive the whole
	///   thing — the mounts, the mapping and a real server reading a real
	///   dependency out of a real Maven layout — against a fixture instead of
	///   against whatever happens to be in the person's own `~/.m2`.
	public static func mounts(
		outsideTheProjectFor definition: LanguageServerDefinition,
		home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
	) -> [ContainerMount] {
		let manager = FileManager.default
		return definition.outside.compactMap { directory in
			let url = home.appendingPathComponent(directory.home, isDirectory: true)
			var isDirectory: ObjCBool = false
			let there = manager.fileExists(atPath: url.path, isDirectory: &isDirectory)
				&& isDirectory.boolValue
			if !there {
				guard !directory.isReadOnly,
				      (try? manager.createDirectory(at: url, withIntermediateDirectories: true)) != nil
				else { return nil }
			}
			// Canonical on the host side for the same reason the project is: the
			// server answers with the path it was given, and a mount named one
			// way while the answer comes back named another maps to nothing.
			return ContainerMount(
				host: FilePath.canonical(url),
				container: directory.container,
				isReadOnly: directory.isReadOnly
			)
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
		environment["PATH"] = Executables.searchPaths.joined(separator: ":")
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
	/// Marked, because this is a depth-2 directory walk and three of its callers
	/// are on the main actor asking it once per server definition — so the cost
	/// of "is there anything here for this server" is paid a dozen times over,
	/// on the queue the keyboard shares. `StallWatch.mark` is a no-op off the
	/// main thread, so the calls that are already somewhere else stay silent.
	public static func suits(_ definition: LanguageServerDefinition, root: URL) -> Bool {
		StallWatch.mark("language server scan") { markerDirectory(for: definition, in: root) != nil }
	}

	/// Every server definition whose markers this project shows, decided from
	/// one walk of it rather than one walk per definition.
	///
	/// `warmUp` and `serverStatus` each loop over `known` asking `suits` about
	/// every definition in turn, and the walk is identical every time: the same
	/// directories listed, the same names read, once for each of the seven
	/// definitions that name markers. Sharing one index across the loop makes it
	/// one listing per directory, which is the roughly tenfold cut 0437 said was
	/// there.
	///
	/// Definitions that name no markers are left out, because both callers
	/// already skip them and for the same reason: a server that fits every
	/// project on earth would be started everywhere, wasting a process and —
	/// when it turns out not to be installed — drowning out the language the
	/// project is actually written in.
	///
	/// And definitions this project did not choose, which is what keeps two
	/// servers for one language from both being started here. A definition
	/// stays in as long as it is the chosen server for at least one of the ids
	/// it answers for, so clangd is not dropped from a project that pointed
	/// `objc` somewhere else.
	public static func suitedDefinitions(
		in root: URL, choosing choices: LanguageServerChoices,
		among servers: [LanguageServerDefinition] = known
	) -> [LanguageServerDefinition] {
		StallWatch.mark("language server scan") {
			let index = DirectoryIndex()
			return servers.filter { definition in
				guard !definition.rootMarkers.isEmpty else { return false }
				guard definition.languageIds.contains(where: {
					self.definition(forLanguage: $0, choosing: choices, among: servers)?.name
						== definition.name
				}) else { return false }
				return markerDirectory(for: definition, in: root, maxDepth: 2, index: index) != nil
			}
		}
	}

	/// One listing of a directory, held for as long as a single question about a
	/// project is being answered and then thrown away.
	///
	/// Thrown away deliberately. A project that gains a `go.mod` a minute from
	/// now must be answered from the directory as it is then, and a cache that
	/// outlived the call would answer from the directory as it was. Within one
	/// call there is nothing to be stale against.
	///
	/// It also removes a second duplicate, smaller but sillier: `holdsMarker`
	/// listed the directory again for every `*.ext` marker it was asked about,
	/// having in most cases just been handed that listing by the walk above it.
	/// Not private, so a test can count what one walk of a project costs from
	/// the index itself. A process-wide counter would be read by whatever other
	/// suite happened to be asking about a project at the same moment; a count
	/// held by the index is exact.
	final class DirectoryIndex {
		/// Directories actually listed, as opposed to answered from the map.
		private(set) var listingCount = 0

		struct Listing {
			/// Every entry, hidden ones included. `.classpath` is one of jdtls's
			/// markers, and a listing that skipped hidden files would not see it.
			let names: Set<String>
			/// The subdirectories worth descending into, in name order:
			/// visible ones, minus the output directories nobody keeps a
			/// manifest in.
			let subdirectories: [URL]
		}

		private var listings: [String: Listing] = [:]
		private static let skipped: Set<String> = [
			"node_modules", "vendor", ".build", ".git", "target", "dist",
		]

		func listing(of directory: URL) -> Listing {
			let key = directory.path
			if let cached = listings[key] { return cached }
			listingCount += 1

			// `isHiddenKey` rather than the `skipsHiddenFiles` option, which
			// would give a listing with the markers missing from it. Asking for
			// the flag reproduces exactly what that option decides, on a listing
			// that still holds everything.
			let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
			let entries = (try? FileManager.default.contentsOfDirectory(
				at: directory, includingPropertiesForKeys: keys, options: []
			)) ?? []

			var names = Set<String>()
			var subdirectories: [URL] = []
			for entry in entries {
				let name = entry.lastPathComponent
				names.insert(name)
				let values = try? entry.resourceValues(forKeys: Set(keys))
				guard values?.isDirectory == true, values?.isHidden != true,
				      !DirectoryIndex.skipped.contains(name)
				else { continue }
				subdirectories.append(entry)
			}

			let listing = Listing(
				names: names,
				subdirectories: subdirectories.sorted { $0.lastPathComponent < $1.lastPathComponent }
			)
			listings[key] = listing
			return listing
		}
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
		markerDirectory(for: definition, in: root, maxDepth: maxDepth, index: DirectoryIndex())
	}

	/// The walk itself, over an index shared with whoever else is asking about
	/// the same project in the same breath.
	static func markerDirectory(
		for definition: LanguageServerDefinition,
		in root: URL,
		maxDepth: Int,
		index: DirectoryIndex
	) -> URL? {
		guard !definition.rootMarkers.isEmpty else { return root }
		if holdsMarker(definition, at: root, index: index) { return root }
		guard maxDepth > 0 else { return nil }

		// Breadth first, so a manifest one level down wins over one three
		// levels down inside an example.
		let directories = index.listing(of: root).subdirectories
		for directory in directories where holdsMarker(definition, at: directory, index: index) {
			return directory
		}
		for directory in directories {
			if let found = markerDirectory(
				for: definition, in: directory, maxDepth: maxDepth - 1, index: index
			) {
				return found
			}
		}
		return nil
	}

	private static func holdsMarker(
		_ definition: LanguageServerDefinition, at directory: URL, index: DirectoryIndex
	) -> Bool {
		let names = index.listing(of: directory).names
		for marker in definition.rootMarkers {
			if marker.hasPrefix("*.") {
				let suffix = String(marker.dropFirst(1))
				if names.contains(where: { $0.hasSuffix(suffix) }) { return true }
			} else if names.contains(marker) {
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
			let directories = Executables.toolDirectories
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
		choosing choices: LanguageServerChoices,
		ignoring: Set<String> = []
	) -> Suggestion? {
		guard let definition = definition(forLanguage: languageId, choosing: choices) else { return nil }
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
		// Asked before the walk, not after: somebody who has said they do not
		// want to hear about this language should not pay to be told again.
		guard !ignoring.contains(languageId) else { return nil }
		guard suits(definition, root: root) else { return nil }
		return suggestion(suited: definition, forLanguage: languageId, ignoring: ignoring)
	}

	/// The same offer, for a caller that has already established that the
	/// project suits this server.
	///
	/// `LanguageService.notice` asks `suits` for its own reasons — a running
	/// server has one sentence to say about itself and a return in front of it
	/// would hide it — and then called through the version above, which asked
	/// again. Two depth-2 walks of the project, on the main actor, for one file
	/// being opened, for an answer that cannot have changed between them.
	public static func suggestion(
		suited definition: LanguageServerDefinition,
		forLanguage languageId: String,
		ignoring: Set<String>
	) -> Suggestion? {
		guard !ignoring.contains(languageId) else { return nil }
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
	///   - choices: which server the project wants for this language. Which
	///     server and where it comes from are two questions, and they stay two:
	///     this decides the first and `image` the second.
	public static func resolve(
		languageId: String,
		project: URL,
		image: String? = nil,
		runtime: ContainerRuntime? = nil,
		choosing choices: LanguageServerChoices,
		home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
	) -> Resolution? {
		guard let definition = definition(forLanguage: languageId, choosing: choices),
		      let root = markerDirectory(for: definition, in: project)
		else { return nil }

		// `build` is not an image name but a request for one, and this is where
		// it becomes a name — the tag carries the recipe's fingerprint, so it
		// can only be worked out at the moment it is used and never written
		// down in `.abydos/tools.json`. A project asking to build a tool this
		// app ships no Dockerfile for gets nil, which falls through to the copy
		// installed here: that is the same answer as naming an image nothing
		// can run, and better than starting a container from a name nobody has.
		let image = image.flatMap { ToolImageRecipes.resolve(image: $0, forTool: definition.name) }

		// An image the project named wins over a copy installed here, the same
		// way it does for a diagram: naming one is a statement about what this
		// project needs, and a local copy quietly overriding it would mean the
		// same code getting different answers on two machines.
		if let image, !image.isEmpty, let runtime {
			// Canonical, both sides. A server resolves a package by realpath,
			// and a mount named `/tmp/x` while the file it is sent is
			// `/private/tmp/x` is a mapping that matches nothing.
			//
			// And whatever this server reads that is not in the project, which
			// for all but one of them is nothing. `paths` carries them as well as
			// the mount does, because a server given a directory it can read will
			// name files in it back at us and a name we cannot map is a
			// go-to-definition that opens nothing.
			let paths = ContainerPaths(
				host: FilePath.canonical(project),
				beyond: mounts(outsideTheProjectFor: definition, home: home)
			)
			let container = ToolContainer(
				image: image,
				mounts: paths.mounts,
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

	/// The server for a language, run inside the devcontainer the project is
	/// already open in.
	///
	/// The whole of step four of 0424, and it is mostly *not* doing things. The
	/// server is `exec`'d into the container that is up rather than started
	/// beside it in one of its own, because a devcontainer is the project's
	/// toolchain and a second container would be a second answer to what `go`
	/// means here.
	///
	/// Three things that hold on this machine do not hold in there, and each is
	/// a bug waiting to be written:
	///
	/// - **The command is not resolved here.** No `xcrun`, no walk of this
	///   machine's PATH, no `/opt/homebrew`: the server is not on this machine
	///   and a path found here names nothing there. The bare command goes in and
	///   the container's own PATH resolves it, which is the only side that can.
	/// - **The arguments are the definition's own**, not `arguments(for:root:)`.
	///   What that adds is jdtls's data directory and the Swift indexer's
	///   scratch path, and both are directories on this machine — a server told
	///   to write its index to a path the container has never heard of either
	///   fails or writes it somewhere nobody will ever look.
	/// - **The root is the container's.** Rooted where the manifest is, as the
	///   container names it, which is under the workspace folder the *file*
	///   asked for rather than `/workspace`.
	public static func resolve(
		languageId: String,
		project: URL,
		inDevContainer session: DevContainers.Session,
		choosing choices: LanguageServerChoices
	) -> Resolution? {
		guard let definition = definition(forLanguage: languageId, choosing: choices),
		      let root = markerDirectory(for: definition, in: project)
		else { return nil }
		let paths = session.configuration.paths
		// A manifest outside the mount cannot be named in there at all, so the
		// server is rooted at the workspace folder instead of at a path that
		// resolves to nothing. `ContainerPaths` is what knows the difference.
		let inside = paths.toContainer(path: FilePath.canonical(root))
			?? session.configuration.workspaceFolder
		return Resolution(
			definition: definition,
			root: root,
			launch: .devcontainer(
				session: session,
				command: definition.command,
				arguments: definition.arguments,
				root: inside
			)
		)
	}

	/// The same, for a caller that only wants a server from this machine.
	public static func resolve(
		languageId: String,
		root: URL,
		choosing choices: LanguageServerChoices
	) -> (definition: LanguageServerDefinition, executable: String, root: URL)? {
		guard let resolution = resolve(languageId: languageId, project: root, choosing: choices),
		      case let .installed(executable, _) = resolution.launch
		else { return nil }
		return (resolution.definition, executable, resolution.root)
	}
}

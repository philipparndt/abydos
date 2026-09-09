import Foundation

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
	/// A command containing `/` is a path and is taken as one, `~` expanded —
	/// which is what makes `LanguageServerOverrides` usable from a file two people
	/// share. A path is not searched for and not substituted: something named and
	/// absent is nil, and the caller says which of "not installed" and "not where
	/// you said" it was.
	public static func executable(for definition: LanguageServerDefinition) -> String? {
		if definition.command.contains("/") {
			let path = (definition.command as NSString).expandingTildeInPath
			return FileManager.default.isExecutableFile(atPath: path) ? path : nil
		}

		if XcodeToolchain.owns(definition.command),
		   let found = XcodeToolchain.path(for: definition.command) {
			return found
		}

		return Executables.locate(definition.command)
	}
}

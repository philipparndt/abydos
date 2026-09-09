import Foundation

/// Starting a language server: the command line, the project root it is given,
/// and what to say when it is not installed.
///
/// The half of `LanguageServers` that is about a *particular* project on a
/// particular machine — which folder is the root, whether the executable is
/// there, where an index is kept — as against the table above, which is about
/// languages and is the same everywhere.
extension LanguageServers {
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

	/// Where to *start* the Swift indexer, which is not where its project is.
	///
	/// A working directory looks like a detail until something writes a relative
	/// path, and 0518 is the day something did: following a symbol into
	/// `.build/checkouts/Cadova` left 1424 files —
	/// `AddingExclusive-2.swiftmodule`, `Angle-2.dia`, one set of four per source
	/// file of the package — loose in the project's own root directory, in the
	/// user's git status, in every search.
	///
	/// The chain is three links long and only the last one is ours:
	///
	/// 1.  Opening a file under `.build/checkouts/<Package>` makes sourcekit-lsp
	///     treat that checkout as a **second** SwiftPM package, beside the
	///     project's own, and prepare it:
	///     `swift-build --package-path <root>/.build/checkouts/Cadova
	///     --scratch-path <the index scratch> --target Cadova
	///     --experimental-prepare-for-indexing`. That is the invocation the
	///     leaked `.d` files name — their prerequisites are the 356 sources of
	///     *that* copy, not of the one under the scratch path.
	/// 2.  A prepare run emits a module per file rather than an object, and when
	///     a supplementary output has no entry in the output file map, swift-driver
	///     falls back to a *temporary* path — `Angle-2.swiftmodule`, the `-2`
	///     being the driver's own uniquing suffix. `swiftc -driver-print-jobs`
	///     shows the same shape for ordinary temporaries: `Alpha-1.o`.
	/// 3.  A temporary that resolves relative is written **where the process
	///     stands**. That is the link this program owns, and it stood in
	///     somebody's checkout.
	///
	/// So the indexer is started in the directory its index already lives in.
	/// Nothing about *finding* the project depends on this: `rootUri` and
	/// `workspaceFolders` are absolute file URLs in the initialize request,
	/// `--scratch-path` is absolute, and every `--package-path` the server passes
	/// on is absolute too. What changes is only where a stray relative write
	/// lands — derived data, in the directory whose whole point is that it can be
	/// thrown away.
	///
	/// Everything else is started in its project, which is the answer that has
	/// always been right for it: a server with no build of its own writes nothing
	/// relative, and jdtls is already given `-data`.
	public static func workingDirectory(for definition: LanguageServerDefinition, root: URL) -> URL {
		switch definition.setup {
		case .swift:
			// `prepare` makes this directory a moment before the server starts,
			// and a `Process` whose working directory does not exist refuses to
			// run at all. So a cache that could not be created leaves the project
			// as the answer: a server that works with the old fault is better than
			// a server that will not start.
			let scratch = indexScratchPath(for: root)
			var isDirectory: ObjCBool = false
			let there = FileManager.default.fileExists(atPath: scratch.path, isDirectory: &isDirectory)
			return there && isDirectory.boolValue ? scratch : root
		case .java, .plain:
			return root
		}
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
			capBackgroundIndexing()
		case .plain:
			break
		}
	}

	/// What share of the machine one server's background indexing may take.
	///
	/// A quarter, because the number that matters is not this one but this one
	/// times the number of servers: 0427 keeps a server for every project that
	/// has been opened, so a session with four of them is the ordinary case and
	/// four quarters is already the whole machine. Lower would make a single
	/// project's first index slower than it needs to be for a session that only
	/// ever has one.
	public static let backgroundIndexingCoreShare = 0.25

	/// Where sourcekit-lsp reads settings that are not one project's.
	public static var userConfigurationPath: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".sourcekit-lsp/config.json")
	}

	/// Stops background indexing taking the whole machine, in the one file
	/// sourcekit-lsp reads it from.
	///
	/// **Why the app writes a file outside itself at all.** A server is kept for
	/// every project that has been opened — 0427, and the reason is good:
	/// navigating between two projects every few minutes should not pay for a
	/// server start each time. What that decision does not price is that each of
	/// those servers indexes on its own account and fans its build out to every
	/// core. Measured on a fourteen-core machine: four live servers, one of them
	/// running `swift-build` at `-j14` with thirteen concurrent `swift-frontend`
	/// under it, against a 9.7 GB scratch tree every write of which this
	/// machine's endpoint-security filter scans. `StallWatch` logged the result
	/// as stalls of 104 s, 54 s and 22 s at `cpu 1%` — a main thread that was
	/// not computing but blocked, in the filter, behind the app's own indexer.
	///
	/// The cap is sourcekit-lsp's own option and it reads it from exactly two
	/// places: the workspace root, and here. The workspace root is somebody's
	/// checkout, and 0518 is the whole reason nothing of ours is written into
	/// one — so it is here, which also means it is set once rather than per
	/// project.
	///
	/// **Never over a value somebody set.** The file is parsed first and the key
	/// added only when it is missing, so anybody with an opinion about their own
	/// indexing keeps it; setting it to `1` is how you say "take the machine"
	/// and have that answer stick. Anything already in the file is written back
	/// untouched, and a file that does not parse is left exactly as it is —
	/// rewriting somebody's malformed JSON as our own is worse than the fault.
	///
	/// This is a shared file and other editors' servers read it too. That is a
	/// real cost and it is the one being chosen: a machine this close to its
	/// limit does not have a spare fourteen cores for whichever editor asks
	/// second.
	static func capBackgroundIndexing() {
		let path = userConfigurationPath
		guard let data = cappedConfiguration(from: try? Data(contentsOf: path)) else { return }
		try? FileManager.default.createDirectory(
			at: path.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try? data.write(to: path, options: .atomic)
	}

	/// What the configuration file should become, or nil when it should be left
	/// exactly as it is.
	///
	/// Separated from the writing so the decision can be tested without a home
	/// directory: every "leave it alone" case below is one somebody could
	/// otherwise only find by losing their own settings to it.
	///
	/// - Parameter existing: the file's contents, or nil when there is no file.
	static func cappedConfiguration(from existing: Data?) -> Data? {
		var configuration: [String: Any] = [:]

		if let existing {
			// Present but not JSON we understand: left alone. Replacing a file
			// we did not write and cannot read is worse than the fault it has.
			guard let parsed = try? JSONSerialization.jsonObject(with: existing),
			      let object = parsed as? [String: Any]
			else { return nil }
			configuration = object
		}

		var index = configuration["index"] as? [String: Any] ?? [:]
		let key = "maxCoresPercentageToUseForBackgroundIndexing"
		// Somebody's own answer, including one that says take everything.
		guard index[key] == nil else { return nil }
		index[key] = backgroundIndexingCoreShare
		configuration["index"] = index

		return try? JSONSerialization.data(
			withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys]
		)
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
	/// - Parameter merging: what the project or the person said to add, from
	///   `LanguageServerOverrides`. Merged over the table above rather than
	///   replacing it, key by key and all the way down, so that a project adding
	///   one setting to a server this app already configures keeps the rest of it.
	///   This is also the only way a server that gets *nothing* from the table —
	///   which is every server but jdtls — can be told anything at all.
	public static func initializationOptions(
		for definition: LanguageServerDefinition,
		root: URL,
		inContainer: Bool = false,
		merging extra: [String: JSONValue] = [:]
	) -> [String: Any]? {
		guard definition.setup == .java else {
			return extra.isEmpty ? nil : extra.mapValues(\.any)
		}

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
		return extra.isEmpty ? options : deepMerging(options, over: extra)
	}

	/// One JSON object over another, the second winning, recursing where both
	/// sides hold an object.
	///
	/// Two objects merged shallowly is the mistake worth avoiding by hand here:
	/// `settings.java.format` added from a project file would replace the whole of
	/// `settings`, taking the runtimes and the build configuration with it, and
	/// the symptom would be a Java project compiled against the wrong JDK because
	/// somebody turned formatting on.
	static func deepMerging(_ base: [String: Any], over extra: [String: JSONValue]) -> [String: Any] {
		var merged = base
		for (key, value) in extra {
			if case let .object(nested) = value, let below = merged[key] as? [String: Any] {
				merged[key] = deepMerging(below, over: nested)
			} else {
				merged[key] = value.any
			}
		}
		return merged
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

	/// The root that owns a *file*, found by climbing rather than searching.
	///
	/// **The direction `markerDirectory` does not have.** That one searches
	/// downward from a root, two levels, breadth-first — which is right when
	/// there is no file in hand, and is what produced the report: with the scope
	/// on `go-service`, the hunt for `Package.swift` started at `go-service` and
	/// went down, found none, and started no Swift server at all. A Swift file
	/// open in front of somebody got no answers because a pill said Go.
	///
	/// It is also what let a Go file in one module be answered by a server
	/// rooted in another: three `go.mod`s side by side, and breadth-first
	/// returns whichever it reaches first. That fault does not go silent — it
	/// answers, from the wrong module.
	///
	/// Which server knows about a file is a question about **the file**. So this
	/// starts at the file and walks up to the nearest directory holding that
	/// language's markers, and stops at the project: a file in a plain folder
	/// answers the project root, which is what every file answered before, and
	/// nothing ever walks to `/`.
	///
	/// - Parameters:
	///   - file: the file the question is about.
	///   - project: the ceiling. Never climbed past, so a checkout inside a
	///     home directory cannot be answered by a manifest in the home
	///     directory.
	public static func rootDirectory(
		for definition: LanguageServerDefinition,
		containing file: URL,
		in project: URL
	) -> URL {
		rootDirectory(for: definition, containing: file, in: project, index: DirectoryIndex())
	}

	static func rootDirectory(
		for definition: LanguageServerDefinition,
		containing file: URL,
		in project: URL,
		index: DirectoryIndex
	) -> URL {
		guard !definition.rootMarkers.isEmpty else { return project }

		let ceiling = FilePath.canonicalEvenIfMissing(project)
		var directory = FilePath.canonicalEvenIfMissing(file.deletingLastPathComponent())

		// A file outside the project is not this project's business, and
		// climbing from it would leave the tree altogether.
		guard directory == ceiling || directory.hasPrefix(ceiling + "/") else { return project }

		while true {
			// The project as the caller spelled it, not as the filesystem does.
			// `markerDirectory` returns the very `root` it was handed when that
			// root holds the markers, and a caller comparing the two answers
			// would otherwise find `/tmp/x` unequal to `/private/tmp/x` — which
			// is a symlink on macOS, and is how the first two tests here failed.
			let url = directory == ceiling
				? project
				: URL(fileURLWithPath: directory, isDirectory: true)
			// Nearest wins, which is what makes a package inside a package
			// answer for its own files.
			if holdsMarker(definition, at: url, index: index) { return url }
			guard directory != ceiling else { return project }
			let parent = (directory as NSString).deletingLastPathComponent
			// Belt and braces: `deletingLastPathComponent` on "/" is "/", and a
			// ceiling that was never reached would otherwise spin here.
			guard parent != directory, !parent.isEmpty else { return project }
			directory = parent
		}
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
	///   - command: the executable to run instead of the definition's own, when a
	///     project or a person named one. Honoured on both routes and it has to
	///     be: a name resolved through a toolchain manager's proxy is the thing
	///     `LanguageServerOverrides` exists to get away from, and the proxy is on
	///     the `PATH` inside an image as readily as out here — `espressif/idf-rust`
	///     has `/home/esp/.cargo/bin` first in its `PATH` and no rust-analyzer
	///     behind it. Where it is a container the path is the container's; nothing
	///     from this machine means anything in there.
	public static func resolve(
		languageId: String,
		project: URL,
		image: String? = nil,
		runtime: ContainerRuntime? = nil,
		choosing choices: LanguageServerChoices,
		command: String? = nil,
		home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
	) -> Resolution? {
		guard let definition = definition(forLanguage: languageId, choosing: choices),
		      let root = markerDirectory(for: definition, in: project)
		else { return nil }
		let command = command.flatMap { $0.isEmpty ? nil : $0 }

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
				// The entry point unless a command was named, and then that instead.
				// It arrives after the image name, so it *replaces* the image's `CMD`
				// and is appended to any `ENTRYPOINT` — which is why the recipes here
				// put the server on the entry point and an image somebody else built
				// may need naming rather than trusting.
				command: command.map { [$0] } ?? [],
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

		// A named command goes through `executable(for:)` rather than round it, so
		// the one rule about what a command is — a `/` in it makes it a path — is
		// stated once and in the place everything else already asks. A path with
		// nothing executable at it comes back nil here, the same as a server that
		// is not installed, and the sentence about *which* of those it was belongs
		// to whoever is going to say it: `LanguageServerOverrides.refusal`.
		let running = command.map(definition.running) ?? definition
		guard let executable = executable(for: running) else { return nil }
		return Resolution(
			definition: running,
			root: root,
			launch: .installed(
				executable: executable,
				arguments: arguments(for: running, root: root)
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
	/// - Parameter command: what to run inside, when one was named. A path here is
	///   the *container's* path, like everything else on this route, and a project
	///   that names one is a project saying its own devcontainer keeps the server
	///   somewhere the container's `PATH` does not reach.
	public static func resolve(
		languageId: String,
		project: URL,
		inDevContainer session: DevContainers.Session,
		choosing choices: LanguageServerChoices,
		command: String? = nil
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
				command: command.flatMap { $0.isEmpty ? nil : $0 } ?? definition.command,
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

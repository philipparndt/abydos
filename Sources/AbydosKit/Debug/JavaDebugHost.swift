import Foundation

/// jdtls, running for one reason: to host the debug adapter.
///
/// ## What this is for
///
/// java-debug is an Eclipse bundle loaded *inside* the Java language server, so
/// until 0452 a project that chose another Java server for editing had no
/// debugger at all. That was a trade nobody should have to make: the fast server
/// is wanted for editing five hundred bundles, and the debugger is wanted a few
/// times a day. This is the second jdtls — started when somebody presses Debug,
/// and only then — whose whole job is to answer `vscode.java.startDebugSession`
/// and `java.project.getClasspaths`.
///
/// ## Why it is not the mess 0449 refused
///
/// 0449 rejected two servers for one language, and the reason was specific: two
/// sets of diagnostics over one file with no rule for which wins. **This one
/// answers nothing about files**, and that is enforced here rather than promised
/// in a comment:
///
/// - **The client is private and there is no accessor.** `LSPClient` can open a
///   document, ask for completion, ask for symbols; none of that is reachable
///   from outside this file, because nothing hands the client out. A caller that
///   wanted to route `textDocument/didOpen` here would have to change this file
///   to do it, which is a diff somebody reads.
/// - **It is not in `LanguageService.servers`.** That table is what every query
///   and every `didOpen` is routed through, and `workspaceSymbols` fans out over
///   *every* entry with the project's prefix — so an entry there really would be
///   a second answer to one question.
/// - **What it publishes about files is counted and dropped.** jdtls reports
///   compilation problems for everything it imports, unasked. Those arrive here,
///   are counted in `diagnosticsDropped`, and go nowhere — so the count is the
///   proof that the drop happened rather than that nothing was sent.
///
/// ## Its own Eclipse workspace, deliberately
///
/// Two jdtls sharing one `-data` directory corrupt it. They can never run at
/// once by construction — a project whose chosen Java server hosts the adapter
/// debugs through the server it already has, and no host is started — but
/// "cannot happen" and "cannot happen even if somebody changes the choice while
/// a session is up" are different claims, and the second one is worth a second
/// directory. What it costs is one import if a project later switches to jdtls
/// for editing.
///
/// ## Always the copy on this machine
///
/// Never an image and never the project's devcontainer. The bundle is a path on
/// *this* machine — `LanguageServers.initializationOptions` already refuses to
/// offer it to a containerised server, because a path here names nothing there —
/// and a JVM started out here for a project built in there would be a different
/// toolchain from the one the code was compiled with. A project worked in its
/// devcontainer still has no Java debugger, which was true before this existed
/// and is now said rather than discovered.
@MainActor
public final class JavaDebugHost {
	public enum Failure: LocalizedError, Equatable {
		/// Abydos has no Java server that hosts an adapter at all, or this
		/// project shows none of its root markers.
		case nothingHostsIt
		/// It is the right server, and it is not installed here.
		case notInstalled(hint: String)
		/// Installed, and the bundle it loads the debugger from is missing.
		case noBundle
		/// The project is worked on inside its own devcontainer.
		case inDevContainer(name: String)
		/// It started and then would not answer.
		case refused(String)
		/// It is running and still importing. Not a fault — a wait.
		case stillImporting(seconds: Int, saying: String?)

		/// Whether nothing anybody does in this session will change this answer.
		///
		/// It decides whether Debug is *offered*. Installing jdtls or its bundle is
		/// something somebody does in a minute and comes back from, so those are
		/// offered and explained when pressed — which is what this app already does
		/// for a missing Delve. A project worked on inside its own devcontainer, or
		/// a language nothing here can host an adapter for, is not: an offer that
		/// cannot be honoured however the person answers it is worse than an
		/// absence.
		public var isSettledHere: Bool {
			switch self {
			case .nothingHostsIt, .inDevContainer: return true
			case .notInstalled, .noBundle, .refused, .stillImporting: return false
			}
		}

		public var errorDescription: String? {
			switch self {
			case .nothingHostsIt:
				return "Abydos has no Java server that can host a debug adapter for this project."
			case let .notInstalled(hint):
				return "The Java debugger is a bundle loaded inside jdtls, and jdtls is not "
					+ "installed on this machine. \(hint)"
			case .noBundle:
				return "jdtls is here but the java-debug bundle it loads the debugger from is not."
			case let .inDevContainer(name):
				return "This project is worked on inside \(name), and the Java debugger is a "
					+ "bundle loaded into a jdtls on this machine. Work on this machine to debug."
			case let .refused(reason):
				return reason
			case let .stillImporting(seconds, saying):
				let said = saying.map { " It says: \($0)" } ?? ""
				return "jdtls has been importing this project for \(seconds) s and cannot start a "
					+ "debug session until it has finished.\(said)"
			}
		}
	}

	/// The one connection to the server, and the whole of the enforcement. See
	/// the note above: private, no accessor, and nothing in this file asks it
	/// anything about a document.
	private let client: LSPClient

	public let definition: LanguageServerDefinition
	/// The checkout this host was started for.
	public let project: URL
	/// Where the server is rooted, which is where the build file is.
	public let root: URL
	public let executable: String
	/// When it was started, so a wait can say how long it has been waiting.
	public let startedAt: Date

	/// How many `publishDiagnostics` this host has thrown away.
	///
	/// The count exists so that "it answers nothing about files" is a measurement
	/// rather than a claim: jdtls reports problems for everything it imports, and
	/// a host that had received none would prove nothing about where they went.
	public private(set) var diagnosticsDropped = 0
	/// The last thing the server said about how far it has got, in its own words.
	///
	/// jdtls's `language/status` is the only place it says this, and a wait that
	/// cannot say what it is waiting for looks exactly like a hang.
	public private(set) var lastStatus: String?
	/// What it last wrote to standard error, for a refusal in its own words.
	public private(set) var lastStandardError: String?

	public var isRunning: Bool { client.isRunning }
	public var processIdentifier: pid_t? { client.processIdentifier }
	/// How long it has been up, for a sentence about the wait.
	public var age: TimeInterval { Date().timeIntervalSince(startedAt) }

	private init(
		client: LSPClient,
		definition: LanguageServerDefinition,
		project: URL,
		root: URL,
		executable: String
	) {
		self.client = client
		self.definition = definition
		self.project = project
		self.root = root
		self.executable = executable
		startedAt = Date()
	}

	// MARK: - Starting one

	/// Where the debugger's own jdtls keeps its Eclipse workspace.
	///
	/// Beside the editing server's rather than in it, for the reason above: two
	/// jdtls in one `-data` directory corrupt it.
	public static func workspace(for root: URL) -> URL {
		let editing = JavaTooling.serverWorkspace(for: root)
		return editing
			.deletingLastPathComponent()
			.appendingPathComponent(editing.lastPathComponent + "-debugger", isDirectory: true)
	}

	/// The server definition that can host an adapter for a language, whatever
	/// the project chose for editing.
	///
	/// **Not `definition(forLanguage:choosing:)`.** Which server answers about
	/// files is a choice; which one hosts the debugger is not — there is one that
	/// can and the rest cannot, and asking the project's preference would give
	/// back the server that has no adapter in it.
	public static func definition(
		forLanguage languageId: String,
		among servers: [LanguageServerDefinition] = LanguageServers.known
	) -> LanguageServerDefinition? {
		LanguageServers.candidates(forLanguage: languageId, among: servers)
			.first { $0.hostsDebugAdapter }
	}

	/// Why this project cannot be debugged, or nil when it can.
	///
	/// **Asked before Debug is offered, and again before anything waits.** Every
	/// one of these is knowable in milliseconds — a directory walk, a `PATH`
	/// lookup, a jar on disk — and finding out after a five-minute import is the
	/// same information delivered as an insult. What is *not* knowable ahead is
	/// whether the import will finish, and that is deliberately not in here.
	public static func refusal(
		languageId: String = "java",
		project: URL,
		inDevContainer: String? = nil,
		among servers: [LanguageServerDefinition] = LanguageServers.known
	) -> Failure? {
		if let inDevContainer { return .inDevContainer(name: inDevContainer) }
		guard let definition = definition(forLanguage: languageId, among: servers),
		      LanguageServers.markerDirectory(for: definition, in: project) != nil
		else { return .nothingHostsIt }
		guard LanguageServers.executable(for: definition) != nil else {
			return .notInstalled(hint: definition.installHint)
		}
		guard JavaTooling.debugPlugin() != nil else { return .noBundle }
		return nil
	}

	/// Starts one, or says why it cannot be.
	///
	/// - Parameter inDevContainer: the name of the devcontainer this project is
	///   worked on inside, when it is. Passed in rather than looked up: this type
	///   knows nothing about consent, sessions or what the window is doing, and
	///   the answer is a refusal rather than something to work around.
	public static func start(
		languageId: String = "java",
		project: URL,
		inDevContainer: String? = nil,
		among servers: [LanguageServerDefinition] = LanguageServers.known
	) throws -> JavaDebugHost {
		if let refusal = refusal(
			languageId: languageId, project: project,
			inDevContainer: inDevContainer, among: servers
		) { throw refusal }
		guard let definition = definition(forLanguage: languageId, among: servers),
		      let root = LanguageServers.markerDirectory(for: definition, in: project),
		      let executable = LanguageServers.executable(for: definition)
		else { throw Failure.nothingHostsIt }

		let data = workspace(for: root)
		try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)

		let client = LSPClient()
		let host = JavaDebugHost(
			client: client,
			definition: definition,
			project: project,
			root: root,
			executable: executable
		)

		// Everything a server can say that is *about a file* ends here. Counted
		// rather than ignored, so a test can show that jdtls did send them.
		client.onDiagnostics = { [weak host] _, _ in host?.diagnosticsDropped += 1 }
		client.onStatus = { [weak host] text in host?.lastStatus = text }
		client.onStandardError = { [weak host] text in host?.lastStandardError = text }

		try client.start(
			executable: executable,
			arguments: definition.arguments + ["-data", data.path],
			workingDirectory: root,
			environment: LanguageServers.serverEnvironment
		)
		return host
	}

	/// The handshake, which is also what starts the import.
	///
	/// Nothing is opened afterwards and nothing needs to be: jdtls imports what
	/// `workspaceFolders` names, and the classpath the adapter needs is what that
	/// import computes. A `didOpen` would buy nothing and is the one thing this
	/// type will not do.
	@discardableResult
	public func handshake(timeout: TimeInterval = 120) async throws -> [String: Any] {
		try await client.initialize(
			rootURL: root,
			options: LanguageServers.initializationOptions(for: definition, root: root),
			timeout: timeout
		)
	}

	// MARK: - What it is for

	/// Asks the server to start a debug session, and returns the port it answers
	/// with.
	public func startDebugSession() async throws -> Int {
		guard isRunning else { throw Failure.refused(lastStandardError ?? "jdtls is not running.") }
		let result = try await client.executeCommand(JavaDebug.startCommand)
		if let port = result as? Int { return port }
		if let port = (result as? NSNumber)?.intValue { return port }
		throw Failure.refused("jdtls started no debug session.")
	}

	/// The runtime classpath of the project a file belongs to, which is what a
	/// launch cannot be built without.
	public func classpath(for url: URL) async -> (projectName: String?, classPaths: [String])? {
		guard isRunning else { return nil }
		guard let result = try? await client.executeCommand(
			JavaDebug.classpathCommand,
			arguments: [url.absoluteString, JavaDebug.classpathOptions()]
		), let object = result as? [String: Any] else { return nil }
		let paths = object["classpaths"] as? [String] ?? []
		let modules = object["modulepaths"] as? [String] ?? []
		let name = (object["projectRoot"] as? String).map {
			URL(fileURLWithPath: $0).lastPathComponent
		}
		let all = paths + modules
		return all.isEmpty ? nil : (name, all)
	}

	/// Everything a launch needs, waited for rather than asked once.
	///
	/// **This is the wait 0452 chose to pay.** Both halves have to be there: the
	/// port says java-debug is listening, and the classpath says the import has
	/// got far enough to say what a launch would *run*. A port with an empty
	/// classpath starts a JVM that fails with `ClassNotFoundException` on the
	/// class it was asked for, which reads as a missing class rather than as a
	/// server that had not finished.
	///
	/// - Parameter saying: called with what the wait is waiting for, every time
	///   that changes. A spinner that says nothing looks like a hang, and this is
	///   the one place that knows both how long it has been and what the server
	///   last said about itself.
	public func waitUntilLaunchable(
		anchor: URL,
		deadline: TimeInterval,
		saying: @escaping (String) -> Void = { _ in }
	) async throws -> (port: Int, projectName: String?, classPaths: [String]) {
		var port: Int?
		var said: String?
		while age < deadline {
			if port == nil { port = try? await startDebugSession() }
			if let port, let resolved = await classpath(for: anchor) {
				return (port, resolved.projectName, resolved.classPaths)
			}

			let waiting = port == nil
				? "Starting the Java debugger inside jdtls"
				: "Waiting for jdtls to finish importing the project, "
					+ "which is where the classpath comes from"
			let sentence = "\(waiting) — \(Int(age)) s"
				+ (lastStatus.map { ". It says: \($0)" } ?? "")
			if sentence != said {
				said = sentence
				saying(sentence)
			}
			guard isRunning else {
				throw Failure.refused(lastStandardError ?? "jdtls exited while starting up.")
			}
			try? await Task.sleep(nanoseconds: 1_000_000_000)
		}
		throw Failure.stillImporting(seconds: Int(age), saying: lastStatus)
	}

	public func stop() {
		let client = self.client
		Task { await client.shutdown() }
	}
}

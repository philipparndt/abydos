import AppKit
import AbydosKit

extension Notification.Name {
	/// Diagnostics arrived for a file. The object is its URL.
	static let ideaiDiagnosticsChanged = Notification.Name("ideai.diagnosticsChanged")
	/// A language server started, stopped, or failed to be found.
	static let ideaiLanguageServersChanged = Notification.Name("ideai.languageServersChanged")
}

/// The language servers a project is using.
///
/// One server per language, started the first time a file of that language is
/// opened and kept until the project closes — starting them is slow and they
/// spend the first minute indexing, so a server per file would mean never
/// getting an answer. Nothing here blocks the editor: a server that is missing,
/// slow, or broken costs the features it provides and nothing else.
@MainActor
final class LanguageService {
	static let shared = LanguageService()

	private struct Server {
		let client: LSPClient
		let definition: LanguageServerDefinition
	}

	/// Keyed by project path and language.
	private var servers: [String: Server] = [:]
	/// Which languages have already been looked for and not found, so a missing
	/// server is reported once rather than on every keystroke.
	private var unavailable: Set<String> = []

	/// Diagnostics per file, newest wins.
	private(set) var diagnostics: [String: [LSPDiagnostic]] = [:]

	/// Documents this service has told a server about, and their version.
	private var openDocuments: [String: Int] = [:]

	/// What to say in the status bar about servers: names of those running.
	private(set) var runningNames: [String] = []
	/// A language whose server is not installed, and how to get it.
	private(set) var missingHints: [String: String] = [:]
	/// A server that is running and has said it cannot work, and what it said.
	///
	/// The state that had no name before: `gopls` starts, answers the
	/// handshake, publishes a diagnostic — and knows nothing about any symbol,
	/// because it could not load the workspace. Everything asking about it saw
	/// "a server is running", so every empty answer read as "nothing here".
	private(set) var failures: [String: String] = [:]
	/// Failures already said out loud, so a server that repeats itself on every
	/// file does not repeat the toast on every file.
	private var announced: Set<String> = []
	/// Files a server has already declared nothing in, so the log says it once
	/// rather than once per keystroke in the symbol palette.
	private var emptied: Set<String> = []

	/// Where the log is, for a sentence that tells somebody where to look.
	static let logPath = DiagnosticLog.path("lsp")

	/// A line in ~/Library/Logs/Abydos/lsp.log.
	///
	/// Language servers fail on other people's machines: a toolchain that is
	/// not on this app's PATH, a manifest one directory further down, a server
	/// that exits on startup. None of that is visible from the editor, and
	/// without a record the only report anybody can make is "it does not
	/// work". Lifetime events only — starts, handshakes, failures, exits —
	/// never a line per keystroke.
	private func log(_ message: String) {
		DiagnosticLog.write(message, to: "lsp")
	}

	private init() {}

	private func key(project: URL, languageId: String) -> String {
		"\(project.standardizedFileURL.path)#\(languageId)"
	}

	/// Starts the servers a project evidently needs, without waiting for a file
	/// of that language to be opened.
	///
	/// Otherwise nothing knows anything until a file is opened, and "go to a
	/// symbol" answers with an empty list in a project full of them — which
	/// reads as broken rather than as not-started-yet.
	func warmUp(project: URL) {
		for definition in LanguageServers.known where !definition.rootMarkers.isEmpty {
			// Markers only. A server that names none of them — the JSON one —
			// fits every project on earth, and starting it everywhere both
			// wastes a process and drowns out the language the project is
			// actually written in when it turns out not to be installed.
			guard LanguageServers.suits(definition, root: project) else { continue }
			guard let languageId = definition.languageIds.first else { continue }
			_ = server(for: languageId, project: project)
		}
	}

	/// Which languages have a server running for this project, and which are
	/// missing one, so a search can say why it found nothing.
	func serverStatus(project: URL) -> (running: [String], missing: [(language: String, hint: String)]) {
		let prefix = project.standardizedFileURL.path + "#"
		var running: [String] = []
		var missing: [(String, String)] = []

		for definition in LanguageServers.known where !definition.rootMarkers.isEmpty {
			guard LanguageServers.suits(definition, root: project),
			      let languageId = definition.languageIds.first
			else { continue }

			if servers[prefix + languageId] != nil {
				running.append(definition.command)
			} else if LanguageServers.executable(for: definition) == nil {
				missing.append((definition.languageIds.first ?? "?", definition.installHint))
			}
		}
		return (running, missing)
	}

	/// How a file is named when talking to a language server.
	///
	/// The real path, always: a server resolves a module or a package by
	/// realpath, and a workspace given as `/tmp/x` then does not contain the
	/// module it just found at `/private/tmp/x` — gopls says as much and
	/// answers nothing about any symbol in it.
	private func canonical(_ url: URL) -> URL {
		URL(fileURLWithPath: FilePath.canonical(url), isDirectory: true)
	}

	private func uri(for url: URL) -> String {
		URL(fileURLWithPath: FilePath.canonical(url)).absoluteString
	}

	// MARK: - Documents

	/// A file was opened. Starts a server for it if this is the first of its
	/// language, and hands it the text.
	func opened(url: URL, languageId: String, text: String, project: URL) {
		guard let server = server(for: languageId, project: project) else { return }
		let uri = uri(for: url)
		openDocuments[uri] = 1
		server.client.didOpen(uri: uri, languageId: languageId, version: 1, text: text)
	}

	func changed(url: URL, languageId: String, text: String, project: URL) {
		guard let server = servers[key(project: project, languageId: languageId)] else { return }
		let uri = uri(for: url)
		let version = (openDocuments[uri] ?? 0) + 1
		openDocuments[uri] = version
		server.client.didChange(uri: uri, version: version, text: text)
	}

	func saved(url: URL, languageId: String, text: String, project: URL) {
		guard let server = servers[key(project: project, languageId: languageId)] else { return }
		server.client.didSave(uri: uri(for: url), text: text)
	}

	func closed(url: URL, languageId: String, project: URL) {
		guard let server = servers[key(project: project, languageId: languageId)] else { return }
		let uri = uri(for: url)
		openDocuments.removeValue(forKey: uri)
		server.client.didClose(uri: uri)

		// A closed file's problems are no longer on screen and no longer
		// anybody's business.
		diagnostics.removeValue(forKey: uri)
		NotificationCenter.default.post(name: .ideaiDiagnosticsChanged, object: url)
	}

	// MARK: - Questions

	func definition(url: URL, position: LSPPosition, languageId: String, project: URL) async -> [LSPLocation] {
		guard let server = ready(languageId, project: project, for: "definition") else { return [] }
		do {
			return try await server.client.definition(uri: uri(for: url), position: position)
		} catch {
			note(error, asked: "definition", of: server, about: url)
			return []
		}
	}

	func hover(url: URL, position: LSPPosition, languageId: String, project: URL) async -> LSPHover? {
		guard let server = ready(languageId, project: project, for: "hover") else { return nil }
		do {
			return try await server.client.hover(uri: uri(for: url), position: position)
		} catch {
			note(error, asked: "hover", of: server, about: url)
			return nil
		}
	}

	func completions(
		url: URL,
		position: LSPPosition,
		languageId: String,
		project: URL
	) async -> [LSPCompletion] {
		guard let server = ready(languageId, project: project, for: "completion") else { return [] }
		do {
			return try await server.client.completion(uri: uri(for: url), position: position)
		} catch {
			note(error, asked: "completion", of: server, about: url)
			return []
		}
	}

	/// Symbols anywhere in the project, from whichever servers are running.
	///
	/// Every language at once, because "where is that thing called X" does not
	/// know or care which language X is written in.
	func workspaceSymbols(matching query: String, project: URL) async -> [LSPSymbol] {
		let prefix = project.standardizedFileURL.path + "#"
		var found: [LSPSymbol] = []
		for (key, server) in servers where key.hasPrefix(prefix) {
			do {
				found += try await server.client.workspaceSymbols(query: query)
			} catch {
				log("\(server.definition.command) workspace/symbol failed: \(error.localizedDescription)")
			}
		}
		return found
	}

	func documentSymbols(url: URL, languageId: String, project: URL) async -> [LSPSymbol] {
		guard let server = ready(languageId, project: project, for: "documentSymbol") else { return [] }
		do {
			let symbols = try await server.client.documentSymbols(uri: uri(for: url))
			// Empty is an answer, and a suspicious one: it is what a server
			// that never loaded the workspace says about every file in it.
			//
			// Once per file: this is asked again on every keystroke in the
			// symbol palette, and a log written per keystroke is a log nobody
			// can read.
			if symbols.isEmpty, emptied.insert("\(server.definition.command)|\(url.path)").inserted {
				log("\(server.definition.command) declared nothing in \(url.lastPathComponent)"
					+ (failures[languageId].map { " — it had already said: \($0)" } ?? ""))
			}
			return symbols
		} catch {
			note(error, asked: "documentSymbol", of: server, about: url)
			return []
		}
	}

	func references(
		url: URL,
		position: LSPPosition,
		languageId: String,
		project: URL
	) async -> [LSPLocation] {
		guard let server = ready(languageId, project: project, for: "references") else { return [] }
		do {
			return try await server.client.references(uri: uri(for: url), position: position)
		} catch {
			note(error, asked: "references", of: server, about: url)
			return []
		}
	}

	/// The server for a question, or nil with a line in the log saying there
	/// was none — "no answer" and "nobody was asked" look identical on screen.
	private func ready(_ languageId: String, project: URL, for question: String) -> Server? {
		guard let server = servers[key(project: project, languageId: languageId)] else {
			log("no \(languageId) server for \(project.lastPathComponent): \(question) unanswered")
			return nil
		}
		return server
	}

	private func note(_ error: Error, asked question: String, of server: Server, about url: URL) {
		log("\(server.definition.command) \(question) failed for \(url.lastPathComponent): "
			+ error.localizedDescription)
	}

	func diagnostics(for url: URL) -> [LSPDiagnostic] {
		diagnostics[uri(for: url)] ?? []
	}

	// MARK: - Java

	/// What went wrong on the way to a Java debug session.
	///
	/// Each case is a different thing to do about it, which is why they are
	/// separate: install a server, wait for it, or install the bundle it loads
	/// the debugger from.
	enum JavaDebugFailure: LocalizedError {
		case noServer
		case noBundle
		case refused(String)

		var errorDescription: String? {
			switch self {
			case .noServer:
				return "The Java language server is not running for this project, "
					+ "and it is what hosts the debugger. \(LanguageServers.definition(forLanguage: "java")?.installHint ?? "")"
			case .noBundle:
				return "The Java language server is running but has no debugger in it: "
					+ "the java-debug bundle was not found when it started."
			case let .refused(reason):
				return reason
			}
		}
	}

	/// Asks jdtls to start a debug session, and returns the port it answers
	/// with.
	///
	/// This is the whole reason Java debugging needs the language server: the
	/// adapter lives inside it. A server that is still importing the project
	/// refuses, which is worth saying out loud — it is a wait, not a fault.
	func startJavaDebugAdapter(project: URL) async throws -> Int {
		guard let server = server(for: "java", project: project), server.client.isRunning else {
			throw JavaDebugFailure.noServer
		}
		guard JavaTooling.debugPlugin() != nil else { throw JavaDebugFailure.noBundle }

		// Retried, because "not yet" and "never" look the same from here: a
		// server that is still importing the project refuses, and a few seconds
		// later the same call succeeds. Pressing debug the moment a project
		// opens is exactly when this happens.
		var lastError: Error?
		for attempt in 0..<5 {
			if attempt > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
			do {
				let result = try await server.client.executeCommand(JavaDebug.startCommand)
				// The port comes back as a number, and which flavour of number
				// depends on the JSON decoder's mood.
				if let port = result as? Int { return port }
				if let port = result as? NSNumber { return port.intValue }
				lastError = JavaDebugFailure.refused("The language server started no debug session.")
			} catch {
				lastError = error
				log("java debug session refused (attempt \(attempt + 1)): \(error.localizedDescription)")
			}
		}

		throw JavaDebugFailure.refused(
			"The Java language server would not start a debug session: "
				+ "\(lastError?.localizedDescription ?? "no reason given"). A project it is still "
				+ "importing cannot be debugged yet — the status bar says when it has finished."
		)
	}

	/// The runtime classpath of the project a file belongs to.
	///
	/// Java cannot be started without one and nothing but the build knows it,
	/// which is why this asks the server that read the build file rather than
	/// guessing from `target/` and `build/`.
	func javaClasspath(for url: URL, project: URL) async -> (projectName: String?, classPaths: [String])? {
		guard let server = server(for: "java", project: project), server.client.isRunning else { return nil }
		do {
			let result = try await server.client.executeCommand(
				JavaDebug.classpathCommand,
				arguments: [uri(for: url), JavaDebug.classpathOptions()]
			)
			guard let object = result as? [String: Any] else { return nil }
			let paths = object["classpaths"] as? [String] ?? []
			let modules = object["modulepaths"] as? [String] ?? []
			let root = (object["projectRoot"] as? String).map {
				URL(fileURLWithPath: $0).lastPathComponent
			}
			return (root, paths + modules)
		} catch {
			log("java classpath unavailable for \(url.lastPathComponent): \(error.localizedDescription)")
			return nil
		}
	}

	// MARK: - Servers

	@discardableResult
	private func server(for languageId: String, project: URL) -> Server? {
		let key = key(project: project, languageId: languageId)
		if let existing = servers[key] {
			// A server that died — crashed, or killed by somebody's `pkill` —
			// is started again rather than silently doing nothing for ever.
			if existing.client.isRunning { return existing }
			servers.removeValue(forKey: key)
		}
		guard !unavailable.contains(key) else { return nil }

		guard let resolved = LanguageServers.resolve(languageId: languageId, root: project) else {
			unavailable.insert(key)
			if let definition = LanguageServers.definition(forLanguage: languageId),
			   LanguageServers.suits(definition, root: project) {
				missingHints[languageId] = definition.installHint
				// Logged, not said out loud. Half the projects on a machine
				// touch a language whose server nobody installed, and a toast
				// on every open for something that was never going to work is
				// the notification people turn off. Where it matters — asking
				// for symbols and getting none — the empty state says it.
				log("\(definition.command) is not installed — \(languageId) in "
					+ "\(project.lastPathComponent) has no server. \(definition.installHint)")
				NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			} else {
				log("nothing to start for \(languageId) in \(project.path)")
			}
			return nil
		}

		let client = LSPClient()
		client.onDiagnostics = { [weak self] uri, diagnostics in
			guard let self else { return }
			self.diagnostics[uri] = diagnostics
			NotificationCenter.default.post(
				name: .ideaiDiagnosticsChanged,
				object: URL(string: uri)
			)
		}
		client.onExit = { [weak self] in
			guard let self else { return }
			self.servers.removeValue(forKey: key)
			self.runningNames.removeAll { $0 == resolved.definition.command }
			self.log("\(resolved.definition.command) exited")
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		// Everything the server says about itself goes to the log, and the part
		// of it that means "I cannot work" is said out loud once.
		client.onMessage = { [weak self] level, text in
			self?.serverSaid(level: level, text: text, definition: resolved.definition, languageId: languageId)
		}
		client.onStandardError = { [weak self] text in
			self?.log("\(resolved.definition.command) stderr: \(Self.oneLine(text))")
		}

		do {
			// Rooted where the manifest is, which is not always the project
			// root: a server pointed at a directory with no manifest in it
			// answers nothing and says nothing about why.
			//
			// And with a PATH that has the toolchain on it. A language server
			// runs the compiler; a GUI app's PATH does not have one.
			LanguageServers.prepare(resolved.definition, root: resolved.root)
			try client.start(
				executable: resolved.executable,
				arguments: LanguageServers.arguments(for: resolved.definition, root: resolved.root),
				workingDirectory: canonical(resolved.root),
				environment: LanguageServers.serverEnvironment
			)
			log("\(resolved.definition.command) started for \(languageId) "
				+ "at \(canonical(resolved.root).path) [\(resolved.executable)]")
		} catch {
			unavailable.insert(key)
			log("\(resolved.definition.command) would not start: \(error.localizedDescription)")
			Toast.post(
				"\(resolved.definition.command) would not start",
				detail: "\(error.localizedDescription)\n\(Self.logPath) has the rest.",
				kind: .error
			)
			return nil
		}

		let server = Server(client: client, definition: resolved.definition)
		servers[key] = server

		Task { @MainActor in
			// The handshake has to finish before anything else is sent, but
			// nothing waits on it: notifications queue up on the pipe in order,
			// and the first answers simply arrive a moment later.
			do {
				// A Java server reads the build file before it answers the
				// handshake, and on a multi-module Maven project that is tens of
				// seconds. Ten would report a working server as broken.
				let isJava = resolved.definition.setup == .java
				_ = try await client.initialize(
					rootURL: canonical(resolved.root),
					options: LanguageServers.initializationOptions(
						for: resolved.definition, root: resolved.root
					),
					timeout: isJava ? 120 : 10
				)
				log("\(resolved.definition.command) initialized")
			} catch {
				log("\(resolved.definition.command) handshake failed: \(error.localizedDescription)")
				failures[languageId] = error.localizedDescription
				Toast.post(
					"\(resolved.definition.command) did not answer",
					detail: "\(error.localizedDescription)\n\(Self.logPath) has the rest.",
					kind: .error
				)
			}
			runningNames.append(resolved.definition.command)
			missingHints.removeValue(forKey: languageId)
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		return server
	}

	/// Something the server said about itself.
	///
	/// Everything is logged; an error is also said out loud, once. A server
	/// that cannot load its workspace repeats itself for every file opened
	/// afterwards, and a toast per file would be worse than the silence it
	/// replaces.
	private func serverSaid(
		level: Int,
		text: String,
		definition: LanguageServerDefinition,
		languageId: String
	) {
		let line = Self.oneLine(text)
		// Everything down to info, which is where a server says what it made of
		// the project — the view it created, the packages it loaded. Not level
		// 4: that is the server's own debug logging, and some of them are
		// generous with it.
		if level <= 3 { log("\(definition.command) says [\(Self.levelName(level))] \(line)") }

		// 1 is an error in the protocol's numbering, and only an error means
		// "this server is not going to answer anything". Warnings are ordinary
		// enough that a toast for each would be the thing people turn off.
		guard level == 1 else { return }
		failures[languageId] = line
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)

		// Once per server, not once per message. A server that cannot load a
		// workspace says so again for every file opened afterwards, with a
		// slightly different URI in it each time — so keying this on the text
		// put the same failure in the corner twice over.
		guard announced.insert(definition.command).inserted else { return }
		Toast.post(
			"\(definition.command) cannot read this project",
			detail: "\(line)\n\n\(Self.logPath) has the rest.",
			kind: .error
		)
	}

	private static func levelName(_ level: Int) -> String {
		switch level {
		case 1: return "error"
		case 2: return "warning"
		case 3: return "info"
		default: return "log"
		}
	}

	/// A server's message on one line, short enough to be read in a corner.
	private static func oneLine(_ text: String) -> String {
		let collapsed = text
			.split(whereSeparator: \.isNewline)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
			.joined(separator: " ")
		return collapsed.count > 300 ? String(collapsed.prefix(300)) + "…" : collapsed
	}

	/// Stops every server for a project, when its window closes or it is
	/// swapped for another.
	func shutdown(project: URL) {
		let prefix = project.standardizedFileURL.path + "#"
		for (key, server) in servers where key.hasPrefix(prefix) {
			servers.removeValue(forKey: key)
			runningNames.removeAll { $0 == server.definition.command }
			let client = server.client
			Task { await client.shutdown() }
		}
		unavailable = unavailable.filter { !$0.hasPrefix(prefix) }
		failures.removeAll()
		announced.removeAll()
		emptied.removeAll()
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	func shutdownAll() {
		for server in servers.values {
			let client = server.client
			Task { await client.shutdown() }
		}
		servers.removeAll()
		runningNames.removeAll()
	}

	// MARK: - Testing

	/// Puts diagnostics in as though a server had sent them, so the drawing and
	/// the navigation can be exercised without one installed.
	func injectForTesting(_ diagnostics: [LSPDiagnostic], for url: URL) {
		self.diagnostics[uri(for: url)] = diagnostics
		NotificationCenter.default.post(name: .ideaiDiagnosticsChanged, object: url)
	}
}

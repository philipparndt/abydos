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
/// One server per project per server, started the first time a file it answers
/// for is opened and kept until the app quits — starting them is slow and they
/// spend the first minute indexing, so a server per file would mean never
/// getting an answer. Nothing here blocks the editor: a server that is missing,
/// slow, or broken costs the features it provides and nothing else.
///
/// Until the app quits, and not until the project is switched away from or its
/// window closes: that is decided in 0427, against a measured cost. A session
/// that opens many projects keeps a server for each of them, and the servers
/// counted there — nine, with fifteen gigabytes of `swift-frontend` under
/// them — are what that looks like when it goes wrong. It is chosen anyway,
/// because coming back to a project has to be instant and stopping a server
/// costs a re-index. Every one of them is registered with `ToolProcesses`,
/// which the three exits — `applicationWillTerminate`, the `atexit` handler
/// and the uncaught-exception handler — all empty.
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
	/// The last thing each server wrote to standard error, so a failure can be
	/// reported in the server's own words.
	private var lastStandardError: [String: String] = [:]

	/// Diagnostics per file, newest wins.
	private(set) var diagnostics: [String: [LSPDiagnostic]] = [:]

	/// Documents this service has told a server about, and their version.
	private var openDocuments: [String: Int] = [:]
	/// Which server each open document was announced to, by URI.
	///
	/// The scope moves: a file open in the whole checkout is still open when
	/// somebody works on the subproject it belongs to, and 0432 is what happens
	/// when that is not noticed — the file was announced to the repository's
	/// server and asked about under the subproject's. This is what lets it be
	/// announced again: closed at the server that had it, opened at the one that
	/// answers now, and nothing done at all when the two are the same server.
	private var documentServers: [String: String] = [:]

	/// Servers whose image is being fetched, so nothing starts a second fetch
	/// and nothing reports the server missing while it is on its way.
	private var fetching: Set<String> = []
	/// What was opened while a server's image was still being fetched, by server
	/// and then by URI.
	///
	/// A fetch is minutes the first time, and the file somebody opened is on
	/// screen for all of them. Without this the server finally starts knowing
	/// about no documents at all — running, answering the handshake, and saying
	/// nothing about the file in front of them.
	private var deferredOpens: [String: [String: (languageId: String, text: String)]] = [:]
	/// Which images a project asks for, read once: it is a file on disk, and the
	/// answer does not change while a project is open.
	private var toolImages: [String: ToolImages] = [:]

	// MARK: - The projects worked on in a container

	/// Whether a project's servers belong inside its devcontainer, by project
	/// path. Read once — it is a file on disk — and set to false when the
	/// container turns out not to be startable, which is what makes the fallback
	/// to this machine happen once rather than per language.
	private var devcontainerProjects: [String: Bool] = [:]
	/// The container each such project's servers run in, once it is up.
	private var devcontainerSessions: [String: DevContainers.Session] = [:]
	/// Which language servers that container actually has, asked once.
	///
	/// The question nobody can answer by reading: an image carries what it
	/// carries. Without it, every language the project touches starts a server
	/// that fails its handshake ten seconds later with the runtime's own
	/// `executable file not found` — which says nothing about the project.
	private var devcontainerCommands: [String: Set<String>] = [:]
	/// Projects whose container is on its way up, so that ten files opened at
	/// once ask for one container rather than ten.
	private var devcontainerStarting: Set<String> = []
	/// Which languages were asked for while it was coming up, so they can be
	/// started when it lands.
	private var devcontainerWaiting: [String: Set<String>] = [:]

	/// What to say in the status bar about servers: names of those running.
	private(set) var runningNames: [String] = []
	/// A server that is not there, and how to get it — keyed by the server, the
	/// way `servers` is, and not by the language.
	///
	/// The reason is 0432's, one table along: "pyright is not in this project's
	/// devcontainer" is a sentence about *that* project, and a table keyed by
	/// the language alone offers it above a file in the next one. It is set for
	/// the same key the server would have been filed under, and cleared when
	/// one starts under it.
	private var missingHints: [String: String] = [:]
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

	/// Keyed by the server rather than by the language asked about: see
	/// `LanguageServers.serverKey`, which is where the reason is written down.
	private func key(project: URL, languageId: String) -> String {
		LanguageServers.serverKey(project: project, languageId: languageId)
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
		var running: [String] = []
		var missing: [(String, String)] = []

		for definition in LanguageServers.known where !definition.rootMarkers.isEmpty {
			guard LanguageServers.suits(definition, root: project),
			      let languageId = definition.languageIds.first
			else { continue }

			if servers[key(project: project, languageId: languageId)] != nil {
				running.append(definition.command)
			} else if images(for: project).image(for: definition.toolKey) != nil {
				// An image is named for it, so it is not missing: it is either
				// being fetched or about to start. Nothing to install.
				continue
			} else if usesDevContainer(project) {
				// In a project worked on in a container, "installed" is a
				// question about the container. Installing it here would change
				// nothing, so the hint has to be about the file that builds it.
				let path = project.standardizedFileURL.path
				guard let inside = devcontainerCommands[path] else { continue }
				if !inside.contains(definition.command) {
					missing.append((
						languageId,
						missingHints[key(project: project, languageId: languageId)]
							?? "\(definition.command) is not in this project's devcontainer."
					))
				}
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
		let key = key(project: project, languageId: languageId)
		let uri = uri(for: url)

		if let previous = documentServers[uri], previous != key {
			// The scope moved under an open file. Closed at the server that had
			// it before it is opened at the one that answers now — a server left
			// holding a document nobody will ask it about goes on publishing
			// diagnostics for it, which land on screen from a toolchain that is
			// no longer the project's.
			servers[previous]?.client.didClose(uri: uri)
			deferredOpens[previous]?.removeValue(forKey: uri)
			documentServers.removeValue(forKey: uri)
		} else if documentServers[uri] == key, servers[key] != nil {
			// The same file to the same server: it already knows, and a second
			// didOpen for a document a server holds is undefined in the protocol.
			return
		}

		guard let server = server(for: languageId, project: project) else {
			// A server whose image is still being fetched — or whose container
			// is still coming up — will want this as soon as it starts, which
			// may be minutes from now.
			if fetching.contains(key) {
				deferredOpens[key, default: [:]][uri] = (languageId, text)
				documentServers[uri] = key
			}
			return
		}
		openDocuments[uri] = 1
		documentServers[uri] = key
		server.client.didOpen(uri: uri, languageId: languageId, version: 1, text: text)
	}

	func changed(url: URL, languageId: String, text: String, project: URL) {
		let waiting = key(project: project, languageId: languageId)
		guard let server = servers[waiting] else {
			// Still being fetched: the text that will be sent as the didOpen is
			// the text as it is now, not as it was when the file was opened.
			if deferredOpens[waiting]?[uri(for: url)] != nil {
				deferredOpens[waiting]?[uri(for: url)] = (languageId, text)
			}
			return
		}
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
		// A file closed before its server ever started is not one to announce
		// when it does.
		deferredOpens[key(project: project, languageId: languageId)]?
			.removeValue(forKey: uri(for: url))
		guard let server = servers[key(project: project, languageId: languageId)] else {
			documentServers.removeValue(forKey: uri(for: url))
			return
		}
		let uri = uri(for: url)
		openDocuments.removeValue(forKey: uri)
		documentServers.removeValue(forKey: uri)
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
		// One already on its way. Not missing, not started: it arrives when the
		// image does, and asking again would start a second fetch.
		guard !fetching.contains(key) else { return nil }

		// A project that says what it is worked on in has its servers in there.
		if usesDevContainer(project) {
			return serverInDevContainer(for: languageId, project: project, key: key)
		}

		guard let resolved = resolution(for: languageId, project: project) else {
			unavailable.insert(key)
			if let definition = LanguageServers.definition(forLanguage: languageId),
			   LanguageServers.suits(definition, root: project) {
				missingHints[key] = definition.installHint
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

		guard let image = resolved.launch.image else {
			return start(resolved, languageId: languageId, key: key)
		}

		// An image that is not on the machine is fetched first, and the first
		// time that is minutes rather than seconds. Nothing waits on it: the
		// fetch runs on its own and the server starts when the image lands,
		// which is the same shape a slow handshake already has. What was opened
		// meanwhile is kept and sent then.
		fetching.insert(key)
		log("\(resolved.definition.command) comes from \(image.name); making sure it is here")
		Task { @MainActor in
			let outcome = await ContainerImageStore.shared.ensure(
				image.name,
				using: image.runtime,
				progress: { message in
					// A pull with nothing on screen is indistinguishable from a
					// feature that does not work.
					Task { @MainActor in Toast.post(message, kind: .information) }
				}
			)
			// Gone while the image was on its way: the project was closed, and a
			// server started for it now would be a process nobody is waiting for.
			guard fetching.remove(key) != nil else { return }
			if case let .failed(reason) = outcome {
				// Not tried again for this project: a name that is wrong is
				// wrong every time, and a registry that wants a sign-in wants
				// one until somebody gives it. Reopening the project asks again.
				unavailable.insert(key)
				failures[languageId] = reason
				log("\(resolved.definition.command): \(reason)")
				Toast.post(
					"\(resolved.definition.command) could not be fetched",
					detail: reason,
					kind: .error
				)
				NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
				return
			}
			guard let server = start(resolved, languageId: languageId, key: key) else { return }
			replayDeferredOpens(to: server, key: key)
		}
		return nil
	}

	// MARK: - Servers inside the project's devcontainer

	/// Whether this project's language servers belong in a container.
	///
	/// **A project with a devcontainer this app can honour gets its servers
	/// inside it, and the container is started for them.** That is a decision
	/// and it could be reversed, so here is the reasoning. A devcontainer.json
	/// is a project saying which toolchain it is worked on with; running the
	/// editor's servers against a different one is how the errors on screen stop
	/// being the errors from the build, which is 0427's fault one floor up and
	/// worse than a slow machine because a red squiggle is believed. The
	/// alternative — servers on this machine beside a container that is up — is
	/// exactly that state. Projects without a devcontainer.json, which is nearly
	/// all of them, are untouched.
	private func usesDevContainer(_ project: URL) -> Bool {
		let path = project.standardizedFileURL.path
		if let known = devcontainerProjects[path] { return known }
		let uses = DevContainerFile.exists(in: project)
		devcontainerProjects[path] = uses
		return uses
	}

	/// The server for a language, inside the project's own container.
	private func serverInDevContainer(
		for languageId: String, project: URL, key: String
	) -> Server? {
		let path = project.standardizedFileURL.path
		guard let session = devcontainerSessions[path] else {
			// Not up yet, and bringing one up is a pull the first time. Held the
			// way a fetched image already is: nothing waits, what is opened
			// meanwhile is kept, and the server starts when the container lands.
			fetching.insert(key)
			devcontainerWaiting[path, default: []].insert(languageId)
			startDevContainer(project)
			return nil
		}
		guard let resolved = LanguageServers.resolve(
			languageId: languageId, project: project, inDevContainer: session
		) else {
			unavailable.insert(key)
			log("nothing to start for \(languageId) in \(project.path)")
			return nil
		}

		// The container has it or it does not, and the file is what decides.
		// Falling back to a copy on this machine would be the thing this whole
		// path exists to avoid: the same code getting different answers
		// depending on whose laptop it is on.
		guard devcontainerCommands[path]?.contains(resolved.definition.command) == true else {
			unavailable.insert(key)
			let hint = "\(resolved.definition.command) is not in this project's devcontainer. "
				+ "Add it to the image or the Dockerfile that "
				+ "\(session.configuration.file.lastPathComponent) names, or run its "
				+ "postCreateCommand — the copy on this machine is not used for a project that "
				+ "says which toolchain it is worked on with."
			missingHints[key] = hint
			log("\(resolved.definition.command) is not in \(session.name) — \(languageId) in "
				+ "\(project.lastPathComponent) has no server")
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			return nil
		}
		return start(resolved, languageId: languageId, key: key)
	}

	/// Brings the project's devcontainer up, once, however many languages ask.
	private func startDevContainer(_ project: URL) {
		let path = project.standardizedFileURL.path
		guard devcontainerStarting.insert(path).inserted else { return }
		guard let runtime = ContainerRuntime.discover(
			preference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
				?? .automatic
		) else {
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(project, because: "nothing here can run a container")
			return
		}
		log("\(project.lastPathComponent) is worked on in a devcontainer; "
			+ "its language servers go inside it")

		// **A project offering several containers gets its servers in the first,
		// and is told so.** The terminal can ask which one somebody means — that
		// is what the + chevron's menu is for — and this cannot: a language
		// server starts because a file was opened, before anybody has said
		// anything, and there is no gesture behind it to attach a question to.
		//
		// The first in the menu's own order, which is sorted and so is the same
		// answer every time, rather than whichever container happens to be up —
		// that would make the toolchain the editor checks against depend on
		// whether somebody had opened a terminal yet, which is a coin toss with
		// extra steps. Said out loud because a silent choice here is exactly the
		// "picking somebody's toolchain for them" the several-file refusal
		// existed to prevent.
		//
		// **This is the owner's to revisit** and 0424 records it as such: a
		// setting naming the container a project's tools belong in, or the
		// question asked once when the project is opened, are both better answers
		// than a rule, and neither belongs in this commit.
		let choices = DevContainerFile.choices(in: project)
		if choices.count > 1, let first = choices.first {
			let others = choices.dropFirst().map(\.name).joined(separator: ", ")
			log("\(project.lastPathComponent) offers \(choices.count) devcontainers; "
				+ "its language servers go in \(first.name), not \(others)")
			Toast.post(
				"\(project.lastPathComponent)'s language servers run in \(first.name)",
				detail: "This project offers \(choices.count) devcontainers and nothing says which "
					+ "one its tools belong in, so the first is used. A terminal can be opened in "
					+ "any of them from the + beside the terminal tabs.",
				kind: .information
			)
		}

		Task { @MainActor in
			let outcome = await DevContainers.shared.session(
				for: project,
				using: runtime,
				progress: DevContainers.Progress(step: { message in
					// A pull and a postCreateCommand are both minutes, and a
					// minute with nothing on screen is a feature that looks
					// broken.
					//
					// The steps and not the output: a language server starting is
					// not something somebody asked to watch, and there is no pane
					// of its own to put ten minutes of `npm ci` in. A terminal
					// opened in the same container while this is going on gets
					// both, because it joins this very start.
					Task { @MainActor in Toast.post(message, kind: .information) }
				})
			)
			devcontainerStarting.remove(path)
			switch outcome {
			case let .running(session)?:
				devcontainerSessions[path] = session
				// A language server is something attaching to the container, and
				// `postAttachCommand` is the moment that names.
				await DevContainers.shared.attach(to: session)
				// One question for every server there is, rather than one failed
				// handshake per language.
				devcontainerCommands[path] = await DevContainers.shared.provides(
					LanguageServers.known.map(\.command), in: session
				)
				log("\(session.name) is up; it has "
					+ "\(devcontainerCommands[path]?.sorted().joined(separator: ", ") ?? "no")"
					+ " language server(s)")
				startWhatWasWaiting(for: project)
			case let .refused(reason)?:
				Toast.post(
					"\(project.lastPathComponent)'s devcontainer was not started",
					detail: "\(reason)\nIts language servers run on this machine instead.",
					kind: .error
				)
				runOnThisMachineInstead(project, because: reason)
			case .none:
				// The file went away between the check and the ask, which is not
				// a failure and must not be reported as one.
				runOnThisMachineInstead(project, because: "it has no devcontainer.json")
			}
		}
	}

	/// The project's servers run here after all, and the reason is said once.
	private func runOnThisMachineInstead(_ project: URL, because reason: String) {
		let path = project.standardizedFileURL.path
		devcontainerProjects[path] = false
		log("\(project.lastPathComponent)'s devcontainer is not available (\(reason)); "
			+ "its language servers run on this machine")
		startWhatWasWaiting(for: project)
	}

	/// Starts the servers asked for while the container was coming up, and
	/// hands each the files opened meanwhile.
	private func startWhatWasWaiting(for project: URL) {
		let path = project.standardizedFileURL.path
		// Gone while the container was on its way — the project was closed — so
		// there is nobody to start a server for.
		let waiting = devcontainerWaiting.removeValue(forKey: path) ?? []
		for languageId in waiting.sorted() {
			let key = key(project: project, languageId: languageId)
			guard fetching.remove(key) != nil else { continue }
			guard let server = server(for: languageId, project: project) else { continue }
			replayDeferredOpens(to: server, key: key)
		}
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	/// Starts a server whose image, if it has one, is already here.
	private func start(
		_ resolved: LanguageServers.Resolution,
		languageId: String,
		key: String
	) -> Server? {
		let client = LSPClient()
		// Before anything is sent, including the handshake: from here on every
		// path going out is the container's and every one coming back is ours.
		client.containerPaths = resolved.launch.paths
		// And what the container it runs in is called, so that stopping this
		// server stops the container too rather than only the process in front
		// of it.
		client.containerLaunch = resolved.launch.container
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
			guard let self else { return }
			let line = Self.oneLine(text)
			self.log("\(resolved.definition.command) stderr: \(line)")
			// Kept for the message. A server that dies on the way up says why
			// here and nowhere else: "the language server is not running" is
			// what the client knows, and it is the one thing nobody can act on.
			if !line.isEmpty { self.lastStandardError[key] = line }
		}

		let run = resolved.launch.invocation
		do {
			// Rooted where the manifest is, which is not always the project
			// root: a server pointed at a directory with no manifest in it
			// answers nothing and says nothing about why.
			//
			// And with a PATH that has the toolchain on it. A language server
			// runs the compiler; a GUI app's PATH does not have one.
			//
			// Nothing to prepare for a container: what jdtls would be given a
			// directory for is inside the image, and a directory made out here
			// for it would be litter nothing ever reads.
			if resolved.launch.paths == nil {
				LanguageServers.prepare(resolved.definition, root: resolved.root)
			}
			try client.start(
				executable: run.executable,
				arguments: run.arguments,
				// The runtime's own working directory, in the container's case,
				// which it does not mind: where the server starts is `-w`, and
				// that is in the command line already. The environment is the
				// same story — the runtime needs it to find its socket.
				workingDirectory: canonical(resolved.root),
				environment: LanguageServers.serverEnvironment
			)
			log("\(resolved.definition.command) started for \(languageId) "
				+ "at \(canonical(resolved.root).path) [\(resolved.launch.description)]")
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
						for: resolved.definition,
						root: canonical(resolved.root),
						inContainer: resolved.launch.paths != nil
					),
					timeout: isJava ? 120 : 10
				)
				log("\(resolved.definition.command) initialized")
			} catch {
				log("\(resolved.definition.command) handshake failed: \(error.localizedDescription)")

				// Not tried again for this project. A server that dies on the
				// way up dies the same way every time — a rustup shim with no
				// rust-analyzer behind it exits in a second, for ever — and the
				// restart-on-demand rule that brings a crashed server back was
				// turning that into a toast every few seconds. Opening the
				// project again is what asks for another go, which is also when
				// somebody has had the chance to install the thing.
				unavailable.insert(key)
				servers.removeValue(forKey: key)

				// In the server's own words where it left any: "Unknown binary
				// 'rust-analyzer' in official toolchain" says what to do, and
				// "the language server is not running" does not.
				let said = lastStandardError[key] ?? error.localizedDescription
				failures[languageId] = said
				Toast.post(
					"\(resolved.definition.command) did not answer",
					detail: "\(said)\n\(Self.logPath) has the rest.",
					kind: .error
				)
			}
			runningNames.append(resolved.definition.command)
			missingHints.removeValue(forKey: key)
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		return server
	}

	/// Which server to start, and whether it comes from an image.
	///
	/// An image is named per project in `.abydos/tools.json` or once in
	/// settings, under the tool's own name rather than its command — `pyright`,
	/// not `pyright-langserver`.
	private func resolution(for languageId: String, project: URL) -> LanguageServers.Resolution? {
		let image = LanguageServers.definition(forLanguage: languageId)
			.flatMap { images(for: project).image(for: $0.toolKey) }

		// Looked for only when one is named: finding a runtime means walking the
		// PATH, and most projects name no image at all.
		var runtime: ContainerRuntime?
		if let image, !image.isEmpty {
			runtime = ContainerRuntime.discover(
				preference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
					?? .automatic
			)
			if runtime == nil {
				// Said, because the alternative is a project that pinned a
				// version quietly getting whatever is installed instead.
				log("\(image) is named for \(languageId) but nothing here can run a "
					+ "container; using what is installed instead")
			}
		}
		return LanguageServers.resolve(
			languageId: languageId, project: project, image: image, runtime: runtime
		)
	}

	/// The images a project asks for, project first and settings behind it.
	private func images(for project: URL) -> ToolImages {
		let path = project.standardizedFileURL.path
		if let known = toolImages[path] { return known }
		let resolved = ToolImages.resolve(
			project: ToolImages.inProject(project),
			settings: ToolImages(images: Settings.shared.toolImages)
		)
		toolImages[path] = resolved
		return resolved
	}

	/// Tells a server that has just started about the files opened while its
	/// image was being fetched.
	private func replayDeferredOpens(to server: Server, key: String) {
		let waiting = deferredOpens.removeValue(forKey: key) ?? [:]
		guard !waiting.isEmpty else { return }
		for (uri, document) in waiting {
			openDocuments[uri] = 1
			documentServers[uri] = key
			server.client.didOpen(
				uri: uri, languageId: document.languageId, version: 1, text: document.text
			)
		}
		log("\(server.definition.command) was told about \(waiting.count) file(s) "
			+ "opened while its image was being fetched")
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

	/// Stops every server for a project.
	///
	/// Nothing in the app calls this, and that is the decision rather than an
	/// oversight: closing a window and switching a project both used to, and
	/// 0427 reversed it — a server ends when the app ends. What it is kept for
	/// is stopping one by hand, which is the list of what is running that 0427
	/// now carries as the answer to a session that has collected too many.
	func shutdown(project: URL) {
		let prefix = project.standardizedFileURL.path + "#"
		for (key, server) in servers where key.hasPrefix(prefix) {
			servers.removeValue(forKey: key)
			runningNames.removeAll { $0 == server.definition.command }
			let client = server.client
			Task { await client.shutdown() }
		}
		unavailable = unavailable.filter { !$0.hasPrefix(prefix) }
		lastStandardError = lastStandardError.filter { !$0.key.hasPrefix(prefix) }
		// A fetch still running is left to finish — the image is worth having on
		// the machine either way — but nothing is waiting for it any more, and
		// the project is read again next time it opens.
		fetching = fetching.filter { !$0.hasPrefix(prefix) }
		deferredOpens = deferredOpens.filter { !$0.key.hasPrefix(prefix) }
		documentServers = documentServers.filter { !$0.value.hasPrefix(prefix) }
		missingHints = missingHints.filter { !$0.key.hasPrefix(prefix) }
		toolImages.removeValue(forKey: project.standardizedFileURL.path)
		// The servers inside the project's devcontainer went with the rest of
		// them, above — the protocol's own `exit` is what ends one in there, and
		// it travels down the same pipe. **The container itself is left up**, for
		// the reason 0424 records: switching away and back has to be instant, and
		// there is somebody's terminal in it. `ToolContainers.removeAll` on the
		// way out and 0406's sweep are what end it.
		let path = project.standardizedFileURL.path
		devcontainerProjects.removeValue(forKey: path)
		devcontainerCommands.removeValue(forKey: path)
		devcontainerWaiting.removeValue(forKey: path)
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
		fetching.removeAll()
		deferredOpens.removeAll()
		documentServers.removeAll()
		missingHints.removeAll()
		toolImages.removeAll()
		devcontainerProjects.removeAll()
		devcontainerSessions.removeAll()
		devcontainerCommands.removeAll()
		devcontainerWaiting.removeAll()
	}

	// MARK: - Testing

	/// Puts diagnostics in as though a server had sent them, so the drawing and
	/// the navigation can be exercised without one installed.
	func injectForTesting(_ diagnostics: [LSPDiagnostic], for url: URL) {
		self.diagnostics[uri(for: url)] = diagnostics
		NotificationCenter.default.post(name: .ideaiDiagnosticsChanged, object: url)
	}
}

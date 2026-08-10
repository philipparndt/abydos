import AppKit
import AbydosKit

extension Notification.Name {
	/// Diagnostics arrived for a file. The object is its URL.
	static let ideaiDiagnosticsChanged = Notification.Name("ideai.diagnosticsChanged")
	/// A language server started, stopped, or failed to be found.
	static let ideaiLanguageServersChanged = Notification.Name("ideai.languageServersChanged")
	/// A project's servers moved between this machine and its devcontainer, so
	/// every file open in it has to be opened again at whichever answers for it
	/// now. The object is the project root. Distinct from the one above, which
	/// says a server's state changed and is answered by re-reading the strip:
	/// this one is answered by re-sending the documents.
	static let ideaiLanguageServersMoved = Notification.Name("ideai.languageServersMoved")
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
		/// Which project asked for it, kept so the list of what is running can
		/// say whose server this is — the key carries the path, but a path is
		/// not a URL and the row wants both the name and the whole of it.
		let project: URL
		/// The container it is running inside, whoever owns that container —
		/// which for a server in the project's devcontainer is not the same
		/// question as what stopping the server removes.
		let insideContainer: String?
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
	/// The container each such project's servers run in, once it is up, together
	/// with what that container turned out to carry and which languages are
	/// waiting for it.
	///
	/// **One table rather than three**, and `DevContainerAttachments` is where
	/// the reason is written down: these used to be a session table and a
	/// capability table filled at the same moment and dropped at different ones,
	/// which is 0438's second fault.
	private var devcontainers = DevContainerAttachments()
	/// Projects whose container is on its way up, so that ten files opened at
	/// once ask for one container rather than ten.
	private var devcontainerStarting: Set<String> = []
	/// Whether a project has a `devcontainer.json` at all, by project path.
	///
	/// A fact about the disk, kept apart from `devcontainerProjects`, which is
	/// what is being *done* about it and goes false when somebody declines or
	/// when the container turns out not to be startable. The strip needs the
	/// first to say which of the two declines is in force — a project with no
	/// devcontainer has nothing to say about one.
	private var devcontainerFiles: [String: Bool] = [:]
	/// What was said about working each project inside its devcontainer, this
	/// session. Nil means nobody has been asked yet.
	///
	/// In front of `Settings` rather than instead of it, because one of the three
	/// answers is deliberately not written down: "not now" is about this
	/// afternoon and has to hold until the project is closed and no longer.
	private var devcontainerConsent: [String: DevContainerConsent] = [:]
	/// Projects whose written-down answer named a devcontainer they no longer
	/// offer, so that the file system is asked about it once rather than on every
	/// lookup.
	///
	/// A project is in here only until it is asked again, and being asked writes
	/// a fresh answer over the stale one — so this is a cache with one use, and it
	/// is cleared wherever the rest of a project's devcontainer bookkeeping is.
	private var staleDevcontainerChoices: Set<String> = []
	/// Projects whose devcontainer was said yes to and would not come up, so that
	/// nothing goes on saying it is starting.
	///
	/// The answer stays on file — somebody did say yes and has not changed their
	/// mind — which is why this cannot be read off the consent. It is about the
	/// last attempt rather than about the project, so it is not written down, and
	/// it goes the moment anything is asked for again.
	private var devcontainerFailures: Set<String> = []

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

	private init() {
		// A devcontainer can be stopped from the list of running tools, which goes
		// through `DevContainers` and never through here. Without this, the
		// attachment would outlive the container it names and the next file opened
		// would be handed a session nothing answers to.
		NotificationCenter.default.addObserver(
			forName: .abydosDevContainersChanged, object: nil, queue: .main
		) { _ in
			Task { @MainActor in
				LanguageService.shared.devContainersChanged(
					alive: await DevContainers.shared.containerNames
				)
			}
		}
	}

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
		// Markers only — which is what `suitedDefinitions` returns. A server that
		// names none of them — the JSON one — fits every project on earth, and
		// starting it everywhere both wastes a process and drowns out the
		// language the project is actually written in when it turns out not to
		// be installed. Asked as one question so the project is walked once
		// rather than once per definition.
		for definition in LanguageServers.suitedDefinitions(in: project) {
			guard let languageId = definition.languageIds.first else { continue }
			_ = server(for: languageId, project: project)
		}
	}

	/// Which languages have a server running for this project, and which are
	/// missing one, so a search can say why it found nothing.
	func serverStatus(project: URL) -> (running: [String], missing: [(language: String, hint: String)]) {
		var running: [String] = []
		var missing: [(String, String)] = []

		// One walk of the project for all of them, as in `warmUp` above.
		for definition in LanguageServers.suitedDefinitions(in: project) {
			guard let languageId = definition.languageIds.first else { continue }

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
				guard let carries = devcontainers.carries(definition.command, for: project)
				else { continue }
				if !carries {
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

	// MARK: - What the strip above the editor should say

	/// What is worth saying above a file, if anything.
	///
	/// This replaces `LanguageServers.suggestion` at the call site, and the
	/// difference is the whole of 0432's second fault. That asks the file
	/// system a question with two answers — the server is on this machine or it
	/// is not — and a devcontainer has a third: it is coming, and it will be
	/// here in anything from a second to a cold `docker build`. Asked of the
	/// file system, that third state reads as the second for ever, which is a
	/// strip saying "install pyright" over a file the container's pyright is
	/// answering about. Asked here, it is a state that ends.
	struct ServerNotice: Equatable {
		let languageId: String
		let languageName: String
		/// The sentence in the strip.
		let text: String
		/// What "How to install" opens, or nil when there is nothing on this
		/// machine to install — a server on its way, or one that belongs in a
		/// container whose copy here would not be used instead.
		let manual: String?
		/// Whether "Ignore for X" is offered. Never while something is on its
		/// way: the answer to "not yet" is to wait, and a language switched off
		/// for ever because a container was slow is the wrong bargain.
		let isIgnorable: Bool
		/// A button offering the one thing that would change this, if there is
		/// one — see `Offer`. Most notices have none.
		var offer: Offer? = nil

		/// The way out of a state somebody chose, offered where they are looking
		/// at the consequence of having chosen it.
		///
		/// A named case rather than a bare button title, so that what the click
		/// agreed to is a value rather than a string match on the words in a
		/// button. There is one of them today.
		enum Offer: Equatable {
			/// Start this project's devcontainer after all, and keep the answer.
			/// Offered to a project whose servers were declined, in either of the
			/// two ways of declining — otherwise "not now" would be a decision
			/// nothing on screen could reverse until the project was reopened.
			case useDevContainer(container: String)

			/// What the button says.
			var title: String {
				switch self {
				case let .useDevContainer(container):
					return DevContainerConsent.offerTitle(container: container)
				}
			}
		}
	}

	/// What to say about a language in a project, or nil for nothing.
	///
	/// Nil is the common answer and the important one: a server that is
	/// answering has nothing to say about itself, and that is what withdraws
	/// the strip when a container's server lands two minutes after the file was
	/// opened.
	func notice(
		forLanguage languageId: String,
		project: URL,
		ignoring: Set<String> = []
	) -> ServerNotice? {
		guard !ignoring.contains(languageId) else { return nil }
		guard let definition = LanguageServers.definition(forLanguage: languageId) else { return nil }
		let key = key(project: project, languageId: languageId)

		// Not a project this server understands — a stray `.py` in a Go
		// repository — so neither the offer nor the wait is about anything.
		//
		// Asked before the running-server return below rather than after it,
		// which is where it used to be: the devcontainer sentence underneath is
		// the one case where a *running* server has something to say about
		// itself, and a return in front of it would hide that. The two orders
		// agree everywhere else, because a server that is running is one that
		// suited the project when it was started.
		guard LanguageServers.suits(definition, root: project) else { return nil }

		let name = LanguageRegistry.shared.displayName(for: languageId)

		// A project that has a devcontainer and is deliberately not being worked
		// on inside it. **The one sentence a running server has to say about
		// itself**, and 0433 is why: a Python file with no squiggles at all and
		// one being checked by a server that is not the project's are the same
		// picture, and telling them apart is the whole of what "no" had to leave
		// behind. It says which of the two declines is in force and offers the
		// way back, since neither is written anywhere else on screen — the pill
		// says *running*, and there is no container running to put one beside.
		if let declined = declinedNotice(languageId: languageId, name: name, project: project, key: key) {
			return declined
		}

		// Answering, or at least running and about to. Nothing to say.
		if let server = servers[key], server.client.isRunning { return nil }

		// On its way. Either the project's devcontainer is coming up with the
		// server inside it, or an image named for the server is being fetched;
		// both are minutes the first time and instant afterwards.
		//
		// **What it says and does not say.** One sentence, no progress, no
		// percentage — the steps are already on screen as toasts from
		// `DevContainers.Progress`, and a terminal opened in the same container
		// joins this very start and shows the whole of it (`PreparingTerminal`).
		// A second progress report would be two things counting the same pull.
		// The strip's job here is only to say why nothing is answering yet, and
		// then to stop saying it.
		if fetching.contains(key) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: devcontainerProjects[project.standardizedFileURL.path] == true
					? "\(name)'s language server is starting in this project's devcontainer."
					: "\(name)'s language server is being fetched.",
				manual: nil,
				isIgnorable: false
			)
		}

		// A project worked on in a container whose container does not carry the
		// server. Installing it here would change nothing — the copy on this
		// machine is deliberately not used — so the sentence is the one about
		// the file that would have to carry it.
		if usesDevContainer(project), let hint = missingHints[key] {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: "\(name) has no language server in this project's devcontainer.",
				manual: hint,
				isIgnorable: true
			)
		}

		// `suited:`, because the guard near the top of this function already
		// asked whether the project suits this server and the answer cannot have
		// changed since. The version that takes a root asked again, which was a
		// second depth-2 walk of the project for one file being opened.
		guard let suggestion = LanguageServers.suggestion(
			suited: definition, forLanguage: languageId, ignoring: ignoring
		) else { return nil }
		return ServerNotice(
			languageId: suggestion.languageId,
			languageName: suggestion.languageName,
			text: "\(suggestion.languageName) has no language server. Install \(suggestion.command) "
				+ "for completion, problems and go-to-declaration.",
			manual: suggestion.manual,
			isIgnorable: true
		)
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
			return start(resolved, languageId: languageId, project: project, key: key)
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
			guard let server = start(resolved, languageId: languageId, project: project, key: key) else { return }
			replayDeferredOpens(to: server, key: key)
		}
		return nil
	}

	// MARK: - Servers inside the project's devcontainer

	/// What the strip says about a project whose devcontainer was declined, or
	/// nil when it was not.
	///
	/// The two declines are shown at different moments, and deliberately so.
	/// **"Not now"** is shown always, because nothing is running anywhere and an
	/// editor that is silent about a file has to say why it is silent.
	/// **"Work on this machine"** is shown only once a server here is actually
	/// answering: before that the ordinary sentence — install `pyright` — is the
	/// useful one, and replacing it with a note about a container somebody has
	/// already turned down would be the app arguing with them.
	private func declinedNotice(
		languageId: String, name: String, project: URL, key: String
	) -> ServerNotice? {
		guard let consent = consent(for: project), consent != .container else { return nil }
		guard hasDevContainerFile(project) else { return nil }
		if consent == .thisMachine, servers[key]?.client.isRunning != true { return nil }
		// The one this project would use, not the one that sorts first: with
		// several, "its language server is in X, which has not been started" has
		// to name the container the button beside it would start.
		guard let container = containerChoice(for: project)?.name,
		      let text = DevContainerConsent.notice(
		      	language: name, container: container, consent: consent
		      )
		else { return nil }
		return ServerNotice(
			languageId: languageId,
			languageName: name,
			text: text,
			// Nothing to install: what is missing here is a decision, not a
			// binary, and the button beside it is the decision.
			manual: nil,
			// Never. "Ignore for Python" is about the language everywhere on the
			// machine, and this is about one project's toolchain — switching the
			// language off to be rid of a sentence about a container is a bargain
			// nobody would knowingly make.
			isIgnorable: false,
			offer: .useDevContainer(container: container)
		)
	}

	/// Whether this project has a `devcontainer.json` on disk, read once.
	private func hasDevContainerFile(_ project: URL) -> Bool {
		let path = project.standardizedFileURL.path
		if let known = devcontainerFiles[path] { return known }
		let exists = DevContainerFile.exists(in: project)
		devcontainerFiles[path] = exists
		return exists
	}

	/// What was said about this project, from this session or from the
	/// preferences it was written to, or nil when nobody has been asked.
	///
	/// **A yes that names a container the project no longer offers is not an
	/// answer**, and this is where it stops being one. `devcontainer.json` is
	/// committed, so the set of containers a project offers is somebody else's to
	/// change between one session and the next; a stored "use `.devcontainer/go`"
	/// against a checkout that now has `.devcontainer/tools` is about a container
	/// nobody can start. Degrading it to nil puts the question back rather than
	/// failing, and rather than quietly starting whichever one sorts first —
	/// which would be choosing a toolchain for somebody who had chosen a
	/// different one. 0444.
	private func consent(for project: URL) -> DevContainerConsent? {
		let path = project.standardizedFileURL.path
		if let held = devcontainerConsent[path] { return held }
		guard !staleDevcontainerChoices.contains(path) else { return nil }
		guard let stored = Settings.shared.devContainerConsent(forProject: project) else { return nil }
		if stored == .container,
		   let named = Settings.shared.devContainerChoice(forProject: project),
		   DevContainerFile.choice(identified: named, in: project) == nil {
			staleDevcontainerChoices.insert(path)
			log("\(project.lastPathComponent) was to be worked on in \(named), which it no longer "
				+ "offers; it will be asked again")
			return nil
		}
		devcontainerConsent[path] = stored
		return stored
	}

	/// Keeps an answer, in the two places it belongs: for this session always,
	/// and in the preferences when it is one of the two that are about the
	/// project rather than about this afternoon.
	///
	/// The container is written down beside it when the answer names one. It is
	/// left alone otherwise — see `Settings.setDevContainerChoice` for why a
	/// decline does not forget which container this project's is.
	private func remember(
		_ consent: DevContainerConsent, choice: DevContainerFile.Choice?, for project: URL
	) {
		devcontainerConsent[project.standardizedFileURL.path] = consent
		staleDevcontainerChoices.remove(project.standardizedFileURL.path)
		devcontainerFailures.remove(project.standardizedFileURL.path)
		Settings.shared.setDevContainerConsent(consent, forProject: project)
		if consent == .container, let choice {
			Settings.shared.setDevContainerChoice(
				DevContainerFile.identifier(of: choice.file, in: project), forProject: project
			)
		}
	}

	/// What is in force for a project, for the titlebar's pill and its menu.
	func devContainerConsent(for project: URL) -> DevContainerConsent? { consent(for: project) }

	/// Whether the last attempt to bring this project's devcontainer up failed,
	/// so that nothing goes on saying it is starting.
	func devContainerFailedToStart(for project: URL) -> Bool {
		devcontainerFailures.contains(project.standardizedFileURL.path)
	}

	/// **Which** of a project's devcontainers its language servers belong in.
	///
	/// The one written down when it is still one of the project's, and the
	/// preferred one otherwise — which covers both a project with a single
	/// container, where there is nothing to choose, and every answer given before
	/// there was anything to choose *with*. Nil only when the project offers none
	/// at all.
	///
	/// This is the single place that turns "yes" into "that one", so the
	/// question, the pill, the menu and the container that actually comes up
	/// cannot come to disagree about which one was meant.
	func containerChoice(for project: URL) -> DevContainerFile.Choice? {
		let choices = DevContainerFile.choices(in: project)
		guard let named = Settings.shared.devContainerChoice(forProject: project) else {
			return choices.first
		}
		return choices.first { DevContainerFile.identifier(of: $0.file, in: project) == named }
			?? choices.first
	}

	/// Work this project inside its devcontainer after all — from the strip
	/// above a file, or from the pill in the titlebar.
	func useDevContainer(for project: URL) {
		move(to: .container, choice: containerChoice(for: project), for: project)
	}

	/// Work this project inside **that** one of its devcontainers — from the
	/// pill's menu, which is the one place with room to list them.
	///
	/// The same call whether the project is already in another container, in none,
	/// or being worked on this machine: `move` is what knows which of those it is,
	/// and all three end with the servers in the container that was clicked.
	func useDevContainer(_ choice: DevContainerFile.Choice, for project: URL) {
		move(to: .container, choice: choice, for: project)
	}

	/// Work this project with the servers on this machine, knowing they are not
	/// the toolchain it names.
	func workOnThisMachine(for project: URL) {
		move(to: .thisMachine, choice: nil, for: project)
	}

	/// Changes which machine — or which container — a project's language servers
	/// run on, after they have already started somewhere.
	///
	/// Everything for the project is ended first, because the two sets answer
	/// differently about the same file and a server left holding a document goes
	/// on publishing diagnostics for it — the fault `opened` guards against one
	/// floor down. The container itself is left up whichever way this goes: it
	/// may hold somebody's terminal, and 0424 is explicit that coming back has to
	/// be instant.
	///
	/// **Moving between two containers is the same move**, which is 0444's part 2
	/// and the reason this takes a choice rather than only a consent. It costs one
	/// thing more than the others: the attachment naming the container the servers
	/// were in has to go, or `warmUp` finds it, decides the project already has a
	/// container, and starts the servers back up in the one somebody has just
	/// asked to leave. A switch that leaves the old container's servers running is
	/// exactly 0427's fault with a gesture behind it.
	private func move(
		to consent: DevContainerConsent, choice: DevContainerFile.Choice?, for project: URL
	) {
		guard hasDevContainerFile(project) else { return }
		let path = project.standardizedFileURL.path
		// Which container this project's servers are in, or would be put in. The
		// one that is actually up when there is one, because that is the fact; the
		// resolved answer otherwise.
		let current = devcontainers[project]?.session.configuration.file
			?? containerChoice(for: project)?.file
		// Nothing to do only when both halves of the answer are already in force.
		// "Use the one we are already using" is a no-op; "use the other one" is
		// not, and the two read identically from the menu.
		let staying = self.consent(for: project) == consent
			&& (consent != .container
				|| choice.map { FilePath.canonical($0.file) } == current.map(FilePath.canonical))
		guard !staying else { return }
		let where_: String
		switch consent {
		case .container: where_ = choice.map { "its devcontainer \($0.name)" } ?? "its devcontainer"
		case .thisMachine, .notNow: where_ = "this machine"
		}
		log("\(project.lastPathComponent)'s language servers move to \(where_)")
		// **The question may still be in the corner, and it holds the guard.**
		// `devcontainerStarting` is what makes ten files opened at once one
		// question rather than ten, and it is held across the *asking* as well as
		// the starting — so a project with a question outstanding cannot start
		// anything, including this. Answering from the pill is answering; the
		// guard is given back here rather than by the withdrawal, so that
		// `questionWithdrawn` finds nothing to hand back and does not log this as
		// an answer nobody gave.
		//
		// **Found by driving it**, and it is the one gesture 0444 makes easy that
		// was hard before: the menu lists every container, so somebody with the
		// question on screen picks from it rather than from the toast — and until
		// this, nothing at all happened, with the pill left saying the container
		// they chose was starting.
		if devcontainerStarting.remove(path) != nil {
			log("\(project.lastPathComponent): the devcontainer question was answered "
				+ "from the titlebar instead")
		}
		withdrawDevContainerQuestion(for: project)
		shutdown(project: project)
		// After the shutdown, which stops them, and before the warm-up, which
		// would otherwise start them straight back up in the container they are
		// leaving. **Only when it is a different container.** Moving onto this
		// machine keeps the attachment, and 0438 proved why: coming back then
		// reuses the very same one, with no second round of asking the image what
		// it carries and no second `is up; it has` in the log.
		if consent == .container, let choice, let current,
		   FilePath.canonical(choice.file) != FilePath.canonical(current) {
			devcontainers.detach(project)
		}
		remember(consent, choice: choice, for: project)
		devcontainerProjects[path] = (consent == .container)
		warmUp(project: project)
		// The files already open belong to the other side's servers now, and
		// nothing here can reach them: the editor groups are what hold the text.
		NotificationCenter.default.post(name: .ideaiLanguageServersMoved, object: project)
	}

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
		guard let attachment = devcontainers[project] else {
			// Declined for now. Nothing is started in the container and nothing
			// takes its place here, because "not now" is not "use this machine's"
			// and the difference is the whole reason there are two ways to say no.
			// The strip says so, and offers the container.
			guard consent(for: project) != .notNow else { return nil }
			// Not up yet, and bringing one up is a pull the first time. Held the
			// way a fetched image already is: nothing waits, what is opened
			// meanwhile is kept, and the server starts when the container lands.
			fetching.insert(key)
			devcontainers.wait(for: languageId, in: project)
			startDevContainer(project)
			// So the strip above the file says the server is on its way rather
			// than nothing at all — and, when it lands, stops saying it. The
			// same notification carries both halves.
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			return nil
		}
		let session = attachment.session
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
		guard attachment.carries(resolved.definition.command) else {
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
		return start(resolved, languageId: languageId, project: project, key: key)
	}

	/// Asks whether this project's devcontainer should come up, once, however
	/// many languages ask, and then does what the answer says.
	///
	/// **The question is here because this is the choke point.** Every route in —
	/// any language, any number of files opened at once — is funnelled through
	/// this function and guarded by `devcontainerStarting`, so the question has
	/// one place to live and cannot be asked twice for one container. The guard
	/// is held across the asking as well as across the starting, which is what
	/// makes ten files opened at once one question rather than ten.
	///
	/// **And it is here rather than when the project is opened.** Most sessions
	/// in a project never open a file the servers care about, and a dialog in
	/// front of a project that is only being read is the kind of prompt people
	/// learn to dismiss without reading. The moment something needs the container
	/// is the moment the question means anything.
	private func startDevContainer(_ project: URL) {
		let path = project.standardizedFileURL.path
		guard devcontainerStarting.insert(path).inserted else { return }
		guard let consent = consent(for: project) else {
			// Still holding `devcontainerStarting`: the answer resolves it, and
			// until then this project has one question outstanding and no more.
			ask(about: project)
			return
		}
		apply(consent, to: project)
	}

	/// What each of the three answers does. The path is in `devcontainerStarting`
	/// when this is called, and every branch either keeps it there because a
	/// container really is coming up or gives it back.
	private func apply(_ consent: DevContainerConsent, to project: URL) {
		let path = project.standardizedFileURL.path
		switch consent {
		case .container:
			bringUpDevContainer(project, choice: containerChoice(for: project))
		case .thisMachine:
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(
				project, because: "its language servers were asked to run on this machine"
			)
		case .notNow:
			devcontainerStarting.remove(path)
			holdWhatWasWaiting(for: project)
		}
	}

	/// Asks, and applies the answer.
	///
	/// **A toast, and one that stays.** 0433 reached for `NSAlert` — a sheet when
	/// there was a window and `runModal` when there was not — and `Toast.swift`
	/// opens with the rule that should have caught it: nothing interrupts unless
	/// the user asked a question, and a confirmation is modal only when it is the
	/// answer to something somebody just did. Opening a `.py` file is neither. So
	/// the question goes to the corner and stays there until it is answered,
	/// which is what `Toast.Lifetime.untilAnswered` was added for.
	///
	/// **And it needs no window to wait for**, which is the other half of what
	/// the modal cost. `warmUp` runs while a project is still loading, with no
	/// key window and nothing on screen to hang a sheet on, so the old path had
	/// to wait a quarter of a second at a time for one to appear and fall back to
	/// an app-modal dialog in front of nothing. A toast is posted; whichever
	/// window is speaking for the app shows it whenever that turns out to be.
	///
	/// What was opened meanwhile is already being held by `serverInDevContainer`,
	/// so an answer given a minute later still hands the server the file somebody
	/// is looking at.
	/// **The question stays three answers however many containers there are**,
	/// which is 0444's part 1 and the shape that entry proposes. Answers stack
	/// rather than sit in a row — a devcontainer's `name` is a whole sentence, so
	/// three side by side would be three truncations — and a fourth and fifth
	/// stacked under them would be a wall in the corner of the screen for a
	/// decision most projects do not have to make. So the question names the one
	/// it would use, and *which* is asked where there is room: the pill's menu
	/// lists them and can change it afterwards, without reopening the project.
	private func ask(about project: URL) {
		let path = project.standardizedFileURL.path
		guard let choice = containerChoice(for: project) else {
			// The file went away between the check and the question, which is not
			// a failure and must not be reported as one.
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(project, because: "it has no devcontainer.json")
			return
		}
		let firstStart = DevContainerFile.read(choice.file, project: project)
			.configuration.map(DevContainerConsent.FirstStart.of)

		// In the order the answers are offered in, the project's own first. There
		// is no Escape to wire "not now" to any more, and it does not need one:
		// the answer that decides nothing is a button like the others, and a
		// question that cannot be dismissed by accident is the point of it.
		let answers = DevContainerConsent.answersInOrder.map { answer in
			Toast.Answer(DevContainerConsent.buttonTitle(answer, container: choice.name)) {
				[weak self] in
				guard let self else { return }
				self.log("\(project.lastPathComponent): \(choice.name) — \(answer.rawValue)")
				// The container the question named, written down with the yes: it
				// is the one thing the answer meant that a bare `container` cannot
				// carry, and a project offering several must not be able to start a
				// different one from the one whose name was on the button.
				self.remember(answer, choice: choice, for: project)
				self.apply(answer, to: project)
			}
		}

		Toast.ask(Toast(
			kind: .information,
			title: DevContainerConsent.questionTitle,
			detail: DevContainerConsent.questionBody(
				project: project.lastPathComponent, container: choice.name, firstStart: firstStart
			),
			answers: answers,
			lifetime: .untilAnswered,
			identifier: Self.questionIdentifier(for: project),
			onWithdrawn: { [weak self] in self?.questionWithdrawn(about: project) }
		))
	}

	/// What a question about this project's devcontainer is filed under, so that
	/// it can be taken back.
	private static func questionIdentifier(for project: URL) -> String {
		"devcontainer-question:" + FilePath.canonical(project)
	}

	/// The window stopped showing this project, so the question about its
	/// devcontainer has nobody left to answer it.
	///
	/// Called by whatever moved — switching project, or moving between the
	/// subprojects of one. **Withdrawing is not answering**: nothing is decided
	/// and nothing is written down, because leaving a question about a project
	/// nobody is looking at one click from being answered is how somebody agrees
	/// to a `docker build` for a checkout they left.
	func withdrawDevContainerQuestion(for project: URL) {
		Toast.withdraw(Self.questionIdentifier(for: project))
	}

	/// The question went off the screen unanswered.
	///
	/// **The guard has to be given back**, and this is the only thing that does
	/// it. `devcontainerStarting` is held across the asking as well as the
	/// starting — which is what makes ten files opened at once one question — so
	/// a question withdrawn without releasing it would leave the project unable
	/// ever to ask again and unable to start anything either: a state nothing on
	/// screen could get somebody out of. What was waiting stops waiting, for the
	/// same reason "not now" makes it stop — the strip must not go on saying a
	/// server is on its way to a container nobody is bringing up.
	private func questionWithdrawn(about project: URL) {
		let path = project.standardizedFileURL.path
		guard devcontainerStarting.remove(path) != nil else { return }
		log("\(project.lastPathComponent): the devcontainer question was withdrawn unanswered")
		holdWhatWasWaiting(for: project)
	}

	/// Nothing is started, here or there, and what was held stops being held.
	///
	/// Without the second half the strip goes on saying a server is on its way to
	/// a container nobody is bringing up. Nothing takes its place: a server on
	/// this machine is the *other* answer, and quietly giving it to somebody who
	/// said "not now" would be the app deciding whose toolchain the code is
	/// checked against — which is what the whole devcontainer path exists to
	/// avoid.
	private func holdWhatWasWaiting(for project: URL) {
		for languageId in devcontainers.takeWaiting(for: project) {
			fetching.remove(key(project: project, languageId: languageId))
		}
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	/// Brings up **that** devcontainer of the project's, the answer having been
	/// yes to it by name.
	///
	/// **The file rather than the project**, which is 0444's part 1 arriving at
	/// the bottom of it. `DevContainers.session(for project:)` starts whichever
	/// container the project prefers and has nowhere to be told otherwise; a
	/// session is remembered against the file, so asking by file is what lets a
	/// project have its servers in the second of two containers, and lets the pill
	/// move them to the other one.
	///
	/// The toast that used to say "this project offers N devcontainers … so the
	/// first is used" is gone with the thing it was apologising for. What replaced
	/// it is not a quieter apology: the question names the container it would use,
	/// the answer is written down as a *which*, and the pill's menu lists all of
	/// them with the one in use marked. A toast repeating that would be news about
	/// a decision somebody made.
	private func bringUpDevContainer(_ project: URL, choice: DevContainerFile.Choice?) {
		let path = project.standardizedFileURL.path
		guard let choice else {
			// The file went away between the answer and the start, which is not a
			// failure and must not be reported as one.
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(project, because: "it has no devcontainer.json")
			return
		}
		guard let runtime = ContainerRuntime.discover(
			preference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
				?? .automatic
		) else {
			devcontainerStarting.remove(path)
			runOnThisMachineInstead(project, because: "nothing here can run a container")
			return
		}
		log("\(project.lastPathComponent) is worked on in \(choice.name); "
			+ "its language servers go inside it")

		// **Somewhere to watch it happen**, which is 0444's part 4. The first
		// start is an image pulled or a Dockerfile built and then three lifecycle
		// commands — minutes, during which the only thing that used to reach the
		// screen was a passing toast per step, with the `docker build` output
		// going nowhere a person could read it.
		//
		// `PreparingTerminal` already is the view being asked for and its own note
		// describes it: the tab opens at once, the work is written into it, and the
		// same pane becomes the shell. It was only ever reached from somebody
		// opening a terminal in the container. Now the language-server path opens
		// one too — never taking the keyboard, since the whole point is that they
		// were doing something else when the file they opened started this.
		//
		// Nil when no window is showing this project, which happens: `warmUp` runs
		// while a project is still loading. Then it is toasts, exactly as before.
		let watching = MainWindowController.watchDevContainerStarting(
			project: project, choice: choice
		)
		let progress = watching?.progress ?? DevContainers.Progress(step: { message in
			// A pull and a postCreateCommand are both minutes, and a minute with
			// nothing on screen is a feature that looks broken. The steps and not
			// the output: there is no pane to put ten minutes of `npm ci` in, and
			// it goes to devcontainer.log either way.
			Task { @MainActor in Toast.post(message, kind: .information) }
		})

		Task { @MainActor in
			let outcome = await DevContainers.shared.session(
				for: choice.file, in: project, using: runtime, progress: progress
			)
			devcontainerStarting.remove(path)
			switch outcome {
			case let .running(session):
				devcontainerFailures.remove(path)
				// A language server is something attaching to the container, and
				// `postAttachCommand` is the moment that names.
				await DevContainers.shared.attach(to: session)
				// One question for every server there is, rather than one failed
				// handshake per language — and asked *before* the session is
				// recorded, so that the pair goes in together. Anything that finds
				// a session finds what it carries beside it or finds neither.
				let provides = await DevContainers.shared.provides(
					LanguageServers.known.map(\.command), in: session
				)
				devcontainers.attach(session, providing: provides, to: project)
				log("\(session.name) is up; it has "
					+ "\(provides.isEmpty ? "no" : provides.sorted().joined(separator: ", "))"
					+ " language server(s)")
				// The pane that watched it come up becomes a shell inside it, which
				// is what `PreparingTerminal` is for and is the one thing 0433's
				// report went looking for and could not find: a way to be *in* the
				// container. Without the keyboard — see `becomeShell`.
				watching?.becomeShell(running: DevContainers.terminalCommand(session))
				startWhatWasWaiting(for: project)
			case let .refused(reason):
				// Said yes, and it did not come up. The answer stays on file, so
				// this is the only thing that stops the titlebar saying a container
				// is starting for the rest of the session.
				devcontainerFailures.insert(path)
				// **The pane is the error and the toast points at it.** A failed
				// build is a hundred lines of `docker build` ending in one that
				// matters, and a toast cannot hold either — 0444's part 4. Where
				// there is a pane, the reason goes in it under everything the build
				// said, and what is posted is short and says where to look.
				if let watching, watching.isOpen {
					watching.refuse(reason)
					Toast.post(
						"\(project.lastPathComponent)'s devcontainer was not started",
						detail: "Its language servers run on this machine instead. What the build "
							+ "said is in the \(choice.name) tab in the terminal panel.",
						kind: .error
					)
				} else {
					Toast.post(
						"\(project.lastPathComponent)'s devcontainer was not started",
						detail: "\(reason)\nIts language servers run on this machine instead.",
						kind: .error
					)
				}
				runOnThisMachineInstead(project, because: reason)
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
		// Gone while the container was on its way — the project was closed — so
		// there is nobody to start a server for.
		for languageId in devcontainers.takeWaiting(for: project).sorted() {
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
		project: URL,
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
		client.onExit = { [weak self, weak client] in
			guard let self else { return }
			// Only if the table still holds this very client, rather than
			// whatever is filed under this key now.
			//
			// A server stopped by hand from the list of what is running is taken
			// out of the table at once, and the next file of that language
			// starts another one for the same key — while the first one's
			// process is still on its way out. Removing by key alone then takes
			// the *new* server out of the table a second later, and the app has
			// a running language server it no longer knows about: measured, and
			// it showed as the list going empty and staying empty after a Stop.
			guard let held = self.servers[key]?.client, held === client else { return }
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

		let server = Server(
			client: client,
			definition: resolved.definition,
			project: project,
			insideContainer: resolved.launch.hostContainerName
		)
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

	// MARK: - What is running, and stopping one by hand

	/// One running server, for the list of what this app has started.
	///
	/// The pid is what makes the row worth looking at: `sourcekit-lsp` is thirty
	/// megabytes and the `swift-frontend` it starts underneath is the fifteen
	/// gigabytes 0427 opened with, so the number beside a row is measured from
	/// this pid downwards rather than read off the process itself.
	struct RunningServer: Identifiable, Sendable {
		/// What `shutdown(server:)` is given back.
		let key: String
		/// The command as it was resolved — `sourcekit-lsp`, `gopls`.
		let command: String
		/// The project that asked for it.
		let project: URL
		/// Its process id on this machine, which for a server in a container is
		/// the runtime's `run` rather than the server.
		let pid: pid_t?
		/// The container this server owns, which goes when it goes.
		let containerName: String?
		/// The container it runs inside, which may be the same one or may be the
		/// project's devcontainer — shared with terminals, builds and every other
		/// server in it, and nobody's to remove on one server's account.
		let insideContainer: String?

		var id: String { key }
	}

	/// Every server running now, in the order a list should show them.
	///
	/// Sorted by project and then command so that the same session gives the
	/// same order twice: a list that shuffles between refreshes is one nobody
	/// can watch a number on.
	var running: [RunningServer] {
		servers.compactMap { key, server in
			guard server.client.isRunning else { return nil }
			return RunningServer(
				key: key,
				command: server.definition.command,
				project: server.project,
				pid: server.client.processIdentifier,
				containerName: server.client.containerLaunch?.name,
				insideContainer: server.insideContainer
			)
		}
		.sorted {
			($0.project.lastPathComponent, $0.command) < ($1.project.lastPathComponent, $1.command)
		}
	}

	/// Stops one server, by the key its row carries.
	///
	/// This is what 0427 kept `shutdown` for. The protocol's own `shutdown` and
	/// `exit` first, then the process, then — for a server in a container — the
	/// container, all of which `LSPClient.shutdown` and its termination handler
	/// do between them.
	///
	/// **It can come back.** The key is taken out of `unavailable` rather than
	/// put into it, and what the server was told about is forgotten, so the next
	/// file of that language to be opened starts another one and announces the
	/// file to it. Stopping a server by hand is "not now", not "never again" —
	/// the alternative would make this list a way to break the editor quietly.
	@discardableResult
	func shutdown(server key: String) -> Bool {
		guard let server = servers.removeValue(forKey: key) else { return false }
		runningNames.removeAll { $0 == server.definition.command }
		let client = server.client
		Task { await client.shutdown() }

		unavailable.remove(key)
		lastStandardError.removeValue(forKey: key)
		fetching.remove(key)
		deferredOpens.removeValue(forKey: key)
		// The documents it held are nobody's now. Forgotten rather than closed:
		// the server they were open at is going, and the next `didOpen` has to
		// happen against whatever starts in its place.
		for (uri, held) in documentServers where held == key {
			documentServers.removeValue(forKey: uri)
			openDocuments.removeValue(forKey: uri)
		}
		missingHints.removeValue(forKey: key)
		log("\(server.definition.command) was stopped by hand for "
			+ "\(server.project.lastPathComponent)")
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		return true
	}

	/// Stops every server for a project.
	///
	/// Nothing in the app calls this on a project's behalf, and that is the
	/// decision rather than an oversight: closing a window and switching a
	/// project both used to, and 0427 reversed it — a server ends when the app
	/// ends. What it is kept for is stopping servers by hand, which is the list
	/// of what is running that 0427 carries as the answer to a session that has
	/// collected too many; that list stops them one at a time, through
	/// `shutdown(server:)`, and this is the whole project at once.
	func shutdown(project: URL) {
		let prefix = project.standardizedFileURL.path + "#"
		// Over a copy of the keys: `shutdown(server:)` takes each out of the very
		// table this is walking.
		for key in Array(servers.keys) where key.hasPrefix(prefix) {
			shutdown(server: key)
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
		//
		// **And so is everything known about that container**, which is 0438's
		// second fault: this line used to drop the list of language servers the
		// image carries while keeping the session, so coming back found a session,
		// skipped the start that fills the list, and told somebody their server
		// was not in a container it was sitting in. `letGo` hands back only what
		// was *about to* happen — the languages waiting on a container — because
		// nothing is going to start them now.
		let path = project.standardizedFileURL.path
		devcontainers.letGo(project)
		devcontainerProjects.removeValue(forKey: path)
		// Read again next time, which cannot contradict a kept container: a
		// session exists only because there was a `devcontainer.json`, and if the
		// file has since gone then reading the disk again is the more correct
		// answer rather than the stale one.
		devcontainerFiles.removeValue(forKey: path)
		// **And the answer, which is what makes "not now" mean this afternoon.**
		// The other two are in the preferences and come straight back; that one is
		// nowhere else on purpose, so a project let go of is a project that will
		// be asked again.
		devcontainerConsent.removeValue(forKey: path)
		// The disk is read again with it: a project let go of may come back to a
		// checkout where the container it named exists again.
		staleDevcontainerChoices.remove(path)
		devcontainerFailures.remove(path)
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
		devcontainers.removeAll()
		devcontainerFiles.removeAll()
		devcontainerConsent.removeAll()
		staleDevcontainerChoices.removeAll()
		devcontainerFailures.removeAll()
	}

	/// The containers this app has up have changed, and one of this project's
	/// may have been among the ones that went.
	///
	/// **Why this exists at all.** A devcontainer can be stopped by hand from the
	/// list of running tools, which goes through `DevContainers` and not through
	/// here — so without this the attachment would outlive the container it names,
	/// and the next file opened would be handed a session nothing answers to. It
	/// is the other half of keeping the session and its capabilities together:
	/// they arrive together, they survive a project being let go of together, and
	/// they go when the container goes.
	func devContainersChanged(alive: Set<String>) {
		devcontainers.containersStopped(keeping: alive)
	}

	// MARK: - Testing

	/// Puts diagnostics in as though a server had sent them, so the drawing and
	/// the navigation can be exercised without one installed.
	func injectForTesting(_ diagnostics: [LSPDiagnostic], for url: URL) {
		self.diagnostics[uri(for: url)] = diagnostics
		NotificationCenter.default.post(name: .ideaiDiagnosticsChanged, object: url)
	}
}

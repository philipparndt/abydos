import AppKit
import AbydosKit

extension Notification.Name {
	/// Diagnostics arrived for a file. The object is its URL.
	static let ideaiDiagnosticsChanged = Notification.Name("abydos.diagnosticsChanged")
	/// A language server started, stopped, or failed to be found.
	static let ideaiLanguageServersChanged = Notification.Name("abydos.languageServersChanged")
	/// A project's servers moved between this machine and its devcontainer, so
	/// every file open in it has to be opened again at whichever answers for it
	/// now. The object is the project root. Distinct from the one above, which
	/// says a server's state changed and is answered by re-reading the strip:
	/// this one is answered by re-sending the documents.
	static let ideaiLanguageServersMoved = Notification.Name("abydos.languageServersMoved")
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

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	internal(set) var didCloseCount = 0

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// How many `textDocument/didOpen` and `didClose` notifications have gone
	/// out, for a script that needs to say what walking a list of results costs
	/// the server.
	///
	/// A count and not a timing. What is claimed about a list of usages walked
	/// with ↓ is a number of messages, and a number of messages is the same on a
	/// loaded machine as on an idle one — which a duration is not.
	internal(set) var didOpenCount = 0
	static let shared = LanguageService()

	struct Server {
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
		/// Where this server came from, in the terms the footer beside the caret
		/// says it. Worked out once, here, while the launch is still in hand —
		/// the view that shows it is redrawn on every caret move and has to be
		/// handed a value rather than allowed to go and ask for one.
		let origin: LanguageServerFooter.Origin
	}

	/// Keyed by project path and language.
	var servers: [String: Server] = [:]
	/// Which languages have already been looked for and not found, so a missing
	/// server is reported once rather than on every keystroke.
	var unavailable: Set<String> = []
	/// The last thing each server wrote to standard error, so a failure can be
	/// reported in the server's own words.
	var lastStandardError: [String: String] = [:]

	/// Diagnostics per file, newest wins.
	internal(set) var diagnostics: [String: [LSPDiagnostic]] = [:]

	/// How a server's own edit gets applied, set by the window in front.
	///
	/// `workspace/applyEdit` arrives on a client and has to be carried out where
	/// the open documents are, which is a window — so this is a hook rather than
	/// anything this service does itself. Whoever takes it must answer exactly
	/// once, and must answer `false` when the edit did not happen.
	/// How many edits servers have asked this app to apply, for a driver that
	/// has to say whether the second half of a command actually arrived.
	internal(set) var serverEditsForTesting = 0

	var applyEditFromServer: ((
		_ edit: WorkspaceEdit,
		_ label: String?,
		_ answer: @escaping (Bool, String?) -> Void
	) -> Void)?

	/// Documents this service has told a server about, and their version.
	var openDocuments: [String: Int] = [:]
	/// Which server each open document was announced to, by URI.
	///
	/// The scope moves: a file open in the whole checkout is still open when
	/// somebody works on the subproject it belongs to, and 0432 is what happens
	/// when that is not noticed — the file was announced to the repository's
	/// server and asked about under the subproject's. This is what lets it be
	/// announced again: closed at the server that had it, opened at the one that
	/// answers now, and nothing done at all when the two are the same server.
	var documentServers: [String: String] = [:]

	/// Servers whose image is being fetched, so nothing starts a second fetch
	/// and nothing reports the server missing while it is on its way.
	var fetching: Set<String> = []
	/// Which of those are a *build* rather than a fetch, so the strip above the
	/// file can say which.
	///
	/// Kept beside `fetching` rather than worked out where the sentence is
	/// written: the strip is redrawn as the editor is, and finding out would mean
	/// resolving the server and hashing a build context on every redraw.
	///
	/// Only read while `fetching` holds the same key, and written on every one of
	/// those inserts, so a key left here after a fetch has finished says nothing
	/// to anybody. That is why it does not have to be removed everywhere
	/// `fetching` is — only where the whole set is emptied, so it cannot grow
	/// without bound.
	var buildingHere: Set<String> = []
	/// What was opened while a server's image was still being fetched, by server
	/// and then by URI.
	///
	/// A fetch is minutes the first time, and the file somebody opened is on
	/// screen for all of them. Without this the server finally starts knowing
	/// about no documents at all — running, answering the handshake, and saying
	/// nothing about the file in front of them.
	var deferredOpens: [String: [String: (languageId: String, text: String)]] = [:]
	/// Which images a project asks for, read once: it is a file on disk, and the
	/// answer does not change while a project is open.
	var toolImages: [String: ToolImages] = [:]
	/// Which toolchains a project pins for itself, read once per project.
	///
	/// Held for the same reason as the images above and one more of its own:
	/// finding a pin is a depth-2 walk of the project, and the strip asks for it
	/// every time a file is opened. Once per project is the same bargain
	/// `suitedDefinitions` struck when it stopped walking once per server.
	var toolchainPins: [String: [ToolchainPin]] = [:]
	/// Which server a project wants for each language, out of the same file and
	/// held for the same reason — but asked far harder. Every key a running
	/// server is filed under now depends on it, so this is read once per
	/// document opened and once per query, and a file read at that rate on the
	/// main actor is a keystroke somebody feels.
	var serverChoices: [String: LanguageServerChoices] = [:]
	/// What a project says about a server's executable and its initialize
	/// options, out of the same file and held for the same reason as the two
	/// above.
	var serverOverrides: [String: LanguageServerOverrides] = [:]
	/// Choices already refused out loud, by server key, so a project naming a
	/// server nobody has says so once rather than once per file opened.
	var refused: Set<String> = []

	// MARK: - The projects worked on in a container

	/// Whether a project's servers belong inside its devcontainer, by project
	/// path. Read once — it is a file on disk — and set to false when the
	/// container turns out not to be startable, which is what makes the fallback
	/// to this machine happen once rather than per language.
	var devcontainerProjects: [String: Bool] = [:]
	/// The container each such project's servers run in, once it is up, together
	/// with what that container turned out to carry and which languages are
	/// waiting for it.
	///
	/// **One table rather than three**, and `DevContainerAttachments` is where
	/// the reason is written down: these used to be a session table and a
	/// capability table filled at the same moment and dropped at different ones,
	/// which is 0438's second fault.
	var devcontainers = DevContainerAttachments()
	/// Projects whose container is on its way up, so that ten files opened at
	/// once ask for one container rather than ten.
	var devcontainerStarting: Set<String> = []
	/// Whether a project has a `devcontainer.json` at all, by project path.
	///
	/// A fact about the disk, kept apart from `devcontainerProjects`, which is
	/// what is being *done* about it and goes false when somebody declines or
	/// when the container turns out not to be startable. The strip needs the
	/// first to say which of the two declines is in force — a project with no
	/// devcontainer has nothing to say about one.
	var devcontainerFiles: [String: Bool] = [:]
	/// What was said about working each project inside its devcontainer, this
	/// session. Nil means nobody has been asked yet.
	///
	/// In front of `Settings` rather than instead of it, because one of the three
	/// answers is deliberately not written down: "not now" is about this
	/// afternoon and has to hold until the project is closed and no longer.
	var devcontainerConsent: [String: DevContainerConsent] = [:]
	/// Projects whose written-down answer named a devcontainer they no longer
	/// offer, so that the file system is asked about it once rather than on every
	/// lookup.
	///
	/// A project is in here only until it is asked again, and being asked writes
	/// a fresh answer over the stale one — so this is a cache with one use, and it
	/// is cleared wherever the rest of a project's devcontainer bookkeeping is.
	var staleDevcontainerChoices: Set<String> = []
	/// Projects whose devcontainer was said yes to and would not come up, so that
	/// nothing goes on saying it is starting.
	///
	/// The answer stays on file — somebody did say yes and has not changed their
	/// mind — which is why this cannot be read off the consent. It is about the
	/// last attempt rather than about the project, so it is not written down, and
	/// it goes the moment anything is asked for again.
	var devcontainerFailures: Set<String> = []

	/// What to say in the status bar about servers: names of those running.
	internal(set) var runningNames: [String] = []
	/// A server that is not there, and how to get it — keyed by the server, the
	/// way `servers` is, and not by the language.
	///
	/// The reason is 0432's, one table along: "pyright is not in this project's
	/// devcontainer" is a sentence about *that* project, and a table keyed by
	/// the language alone offers it above a file in the next one. It is set for
	/// the same key the server would have been filed under, and cleared when
	/// one starts under it.
	var missingHints: [String: String] = [:]
	/// What is known about each server *after* it started — see `ServerHealth`,
	/// which is where the rule for reading it is written down.
	///
	/// The state that had no name before: `gopls` starts, answers the
	/// handshake, publishes a diagnostic — and knows nothing about any symbol,
	/// because it could not load the workspace. Everything asking about it saw
	/// "a server is running", so every empty answer read as "nothing here".
	///
	/// **Keyed by the server, the way `servers` and `missingHints` are**, and
	/// not by the language, which is what this was. 0432's fault one table
	/// along: "rust-analyzer cannot read this project" is a sentence about
	/// *that* project, and a table keyed by the language alone put it above a
	/// file in the next one — a Rust project that fails leaves every other Rust
	/// project on the machine looking broken for the rest of the session.
	var health: [String: ServerHealth] = [:]
	/// Servers that are running and are not ready to be believed yet.
	///
	/// Keyed like `servers` and `health`, and for the same reason: a Swift
	/// package building its dependencies is a fact about *that* project, and a
	/// table keyed by the language would say "preparing" over a file in the next
	/// one.
	///
	/// **A set rather than something asked of the client**, because `footer` is
	/// read beside every caret move and must stay a handful of lookups — the same
	/// shape as `fetching` and `buildingHere`, which are the other waits. It is
	/// written twice per server, from `LSPClient.onPreparing`. 0501.
	var preparing: Set<String> = []
	/// Failures already said out loud, so a server that repeats itself on every
	/// file does not repeat the toast on every file.
	var announced: Set<String> = []
	/// Files a server has already declared nothing in, so the log says it once
	/// rather than once per keystroke in the symbol palette.
	var emptied: Set<String> = []

	/// jdtls started for the debugger alone, by project path.
	///
	/// **A table of its own, and that is the enforcement rather than a
	/// convenience.** `servers` is what every query and every `didOpen` is routed
	/// through, and `workspaceSymbols` fans out over every entry with a project's
	/// prefix — so a debug host in there would be a second answer to questions the
	/// chosen server is already answering, which is exactly what 0449 refused.
	/// Nothing in this table can be reached by asking about a language, and what
	/// is in it is a `JavaDebugHost`, which has no way to be asked about a file.
	var debugHosts: [String: JavaDebugHost] = [:]

	/// The preferences that decide which server answers and where it comes from,
	/// as they were the last time anything was done about them.
	var preferences = ToolPreferences(Settings.shared)
	/// The reconsideration a settings change has asked for and not had yet, held
	/// so that the next change cancels it.
	var reconsidering: Task<Void, Never>?

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
	func log(_ message: String) {
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

		// And a preference that decides which server answers, or where it comes
		// from. Everything remembered here about a server not working — it is
		// unavailable, this is the hint above the file, this is what it said — is
		// an answer given under conditions somebody has just changed, and until
		// 0460 nothing went back to look. There is one notification for every
		// setting and it says nothing about which one, so the reading is done in
		// `settingsChanged`.
		NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { _ in
			Task { @MainActor in LanguageService.shared.settingsChanged() }
		}
	}

	/// Keyed by the server rather than by the language asked about: see
	/// `LanguageServers.serverKey`, which is where the reason is written down.
	func key(project: URL, languageId: String) -> String {
		LanguageServers.serverKey(
			project: project, languageId: languageId, choosing: choices(for: project)
		)
	}

	/// The project a *file* belongs to, for the purpose of asking about it.
	///
	/// **One place decides it**, and that is the whole of this change. There are
	/// twenty call sites in the editor asking questions of a language server; if
	/// any two of them disagree about which root a file is filed under, the file
	/// is opened at one server and asked about through another — which answers
	/// nothing and looks exactly like the fault being fixed.
	///
	/// The scope is not the answer. `Project.scopeRoot` says which launch
	/// configurations there are, which module a build runs in, which tree git
	/// acts on — all questions about *what somebody is working on*. Which server
	/// knows about a file is a question about the file, and answering it with the
	/// scope pill meant a Swift file got no Swift server while the pill said Go.
	///
	/// Falls back to the project wherever the file has no root of its own, which
	/// is what every file answered before this existed.
	func root(for url: URL, languageId: String, project: URL) -> URL {
		guard let definition = LanguageServers.definition(
			forLanguage: languageId, choosing: choices(for: project)
		) else { return project }
		return LanguageServers.rootDirectory(for: definition, containing: url, in: project)
	}

	/// Which server this project uses for a language, and where that was said.
	func selection(for languageId: String, project: URL) -> LanguageServers.Selection {
		LanguageServers.selection(forLanguage: languageId, choosing: choices(for: project))
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
		let choices = choices(for: project)

		// **The scan is a directory walk, so it does not happen here.**
		//
		// 0437 cut this from one walk per definition to one walk; 0428 asked what
		// the remaining walk costs "at a thousand bundles, on the queue the
		// keyboard shares". The answer, measured on a work tree of thirteen
		// thousand folders, is 1,190 ms — and `warmUp` is called from
		// `load(project:)`, so that was 1,190 ms of a window that had stopped
		// answering. Together with the dependency walk beside it, switching
		// projects held the main thread for two and a half seconds.
		//
		// It walks the filesystem and reads nothing of ours, so it runs off the
		// main actor and comes back to start the servers. Nothing waits for it:
		// a server exists to answer questions about a file, and no file can be
		// asked about before it is open.
		Task.detached(priority: .userInitiated) {
			let suited = LanguageServers.suitedDefinitions(in: project, choosing: choices)
            await MainActor.run {
				// The mark sits after the walk and before the servers start, so
				// what it times is the scan and not the first handshake.
				LaunchClock.mark("language servers scanned")
				for definition in suited {
					guard let languageId = LanguageServers.chosenLanguage(
						for: definition, choosing: choices
					) else { continue }
					_ = LanguageService.shared.server(for: languageId, project: project)
				}
				LanguageService.shared.refuseUnknownServers(for: project, choosing: choices)
			}
		}
		LaunchClock.mark("language servers started")
	}

	/// A server the project asked for and this app has never heard of appears
	/// in no scan — there is no definition to have markers — so the only
	/// evidence of it would be a language quietly without diagnostics.
	/// Refused when the project opens, rather than whenever somebody happens to
	/// open a file of that language. Only the choices that cannot be honoured:
	/// asking about the rest would decide that a project has no Go manifest at a
	/// moment when it may not have been cloned yet, and `unavailable` is
	/// remembered for the session.
	private func refuseUnknownServers(for project: URL, choosing choices: LanguageServerChoices) {
		for languageId in choices.byLanguage.keys.sorted() {
			guard case .noSuchServer = LanguageServers.selection(
				forLanguage: languageId, choosing: choices
			) else { continue }
			_ = server(for: languageId, project: project)
		}
	}

	/// Which languages have a server running for this project, and which are
	/// missing one, so a search can say why it found nothing.
	func serverStatus(project: URL) -> (running: [String], missing: [(language: String, hint: String)]) {
		var running: [String] = []
		var missing: [(String, String)] = []

		let choices = choices(for: project)
		// One walk of the project for all of them, as in `warmUp` above.
		for definition in LanguageServers.suitedDefinitions(in: project, choosing: choices) {
			guard let languageId = LanguageServers.chosenLanguage(for: definition, choosing: choices)
			else { continue }

			if servers[key(project: project, languageId: languageId)] != nil {
				running.append(definition.command)
			} else if images(for: project).image(for: definition.name) != nil {
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
				missing.append((languageId, missingHints[key(project: project, languageId: languageId)]
					?? definition.installHint))
			}
		}

		// And the servers this project asked for that do not exist, which no
		// walk of it can find: a search that comes back empty says why rather
		// than looking like a project with nothing in it.
		for languageId in choices.byLanguage.keys.sorted() {
			guard case let .noSuchServer(name, source) = LanguageServers.selection(
				forLanguage: languageId, choosing: choices
			) else { continue }
			missing.append((
				languageId,
				LanguageServers.refusal(named: name, forLanguage: languageId, source: source)
			))
		}
		return (running, missing)
	}
}

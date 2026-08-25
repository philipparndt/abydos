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
		/// Where this server came from, in the terms the footer beside the caret
		/// says it. Worked out once, here, while the launch is still in hand —
		/// the view that shows it is redrawn on every caret move and has to be
		/// handed a value rather than allowed to go and ask for one.
		let origin: LanguageServerFooter.Origin
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

	/// How a server's own edit gets applied, set by the window in front.
	///
	/// `workspace/applyEdit` arrives on a client and has to be carried out where
	/// the open documents are, which is a window — so this is a hook rather than
	/// anything this service does itself. Whoever takes it must answer exactly
	/// once, and must answer `false` when the edit did not happen.
	/// How many edits servers have asked this app to apply, for a driver that
	/// has to say whether the second half of a command actually arrived.
	private(set) var serverEditsForTesting = 0

	var applyEditFromServer: ((
		_ edit: WorkspaceEdit,
		_ label: String?,
		_ answer: @escaping (Bool, String?) -> Void
	) -> Void)?

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
	private var buildingHere: Set<String> = []
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
	/// Which toolchains a project pins for itself, read once per project.
	///
	/// Held for the same reason as the images above and one more of its own:
	/// finding a pin is a depth-2 walk of the project, and the strip asks for it
	/// every time a file is opened. Once per project is the same bargain
	/// `suitedDefinitions` struck when it stopped walking once per server.
	private var toolchainPins: [String: [ToolchainPin]] = [:]
	/// Which server a project wants for each language, out of the same file and
	/// held for the same reason — but asked far harder. Every key a running
	/// server is filed under now depends on it, so this is read once per
	/// document opened and once per query, and a file read at that rate on the
	/// main actor is a keystroke somebody feels.
	private var serverChoices: [String: LanguageServerChoices] = [:]
	/// What a project says about a server's executable and its initialize
	/// options, out of the same file and held for the same reason as the two
	/// above.
	private var serverOverrides: [String: LanguageServerOverrides] = [:]
	/// Choices already refused out loud, by server key, so a project naming a
	/// server nobody has says so once rather than once per file opened.
	private var refused: Set<String> = []

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
	private var health: [String: ServerHealth] = [:]
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
	private var preparing: Set<String> = []
	/// Failures already said out loud, so a server that repeats itself on every
	/// file does not repeat the toast on every file.
	private var announced: Set<String> = []
	/// Files a server has already declared nothing in, so the log says it once
	/// rather than once per keystroke in the symbol palette.
	private var emptied: Set<String> = []

	/// jdtls started for the debugger alone, by project path.
	///
	/// **A table of its own, and that is the enforcement rather than a
	/// convenience.** `servers` is what every query and every `didOpen` is routed
	/// through, and `workspaceSymbols` fans out over every entry with a project's
	/// prefix — so a debug host in there would be a second answer to questions the
	/// chosen server is already answering, which is exactly what 0449 refused.
	/// Nothing in this table can be reached by asking about a language, and what
	/// is in it is a `JavaDebugHost`, which has no way to be asked about a file.
	private var debugHosts: [String: JavaDebugHost] = [:]

	/// The preferences that decide which server answers and where it comes from,
	/// as they were the last time anything was done about them.
	private var preferences = ToolPreferences(Settings.shared)
	/// The reconsideration a settings change has asked for and not had yet, held
	/// so that the next change cancels it.
	private var reconsidering: Task<Void, Never>?

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
	private func key(project: URL, languageId: String) -> String {
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
	private func selection(for languageId: String, project: URL) -> LanguageServers.Selection {
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
		/// Whether this is something being reported rather than something being
		/// offered. It decides the glyph, and the glyph is what the strip is
		/// read by from across the room: a lightbulb is an idea somebody could
		/// act on, and "your server is not answering for this project" is not
		/// one of those.
		var problem: Bool = false
		/// What the button in front of `manual` says.
		///
		/// Almost always "How to install", which is what all of these were until
		/// two of them were not about installing anything: a project pinning a
		/// toolchain nothing here can supply has no installation to offer, and a
		/// server that is installed, started and complaining has nothing left to
		/// install either. A button saying there is one is the wrong advice
		/// printed in the place somebody looks for the right one.
		var detailsTitle: String = "How to install"
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

	/// What to say about a project whose selected launch wants a Java debugger
	/// that is not here, or nil when there is nothing to say.
	///
	/// **Asked when a launch is chosen rather than when Debug is pressed**, which
	/// is what `JavaDebugHost.refusal` was written for and has always said in its
	/// own documentation: every one of these answers is a `PATH` lookup or a jar
	/// on disk, knowable in milliseconds, and finding out afterwards is the same
	/// information delivered as an insult. Pressing Debug on a project with no
	/// jdtls used to start a JVM, suspend it on a port, and only then admit that
	/// nothing was ever going to attach to it.
	///
	/// `.nothingHostsIt` is deliberately not reported. It means the project shows
	/// none of the server's markers — no pom, no Gradle build — and a strip
	/// saying Java cannot be debugged here belongs to a Java project, not to
	/// every project with a launch configuration in it.
	///
	/// Ignorable, and a problem rather than an idea: it is a statement about what
	/// this project cannot do, and somebody who never debugs Java should be able
	/// to put it away for good.
	func javaDebugNotice(project: URL) -> ServerNotice? {
		guard let refusal = JavaDebugHost.refusal(
			project: project,
			inDevContainer: devContainerNameHoldingServers(for: project)
		) else { return nil }
		guard refusal != .nothingHostsIt else { return nil }

		// No manual, and nothing lost by it: every one of these `Failure` cases
		// already carries its own remedy in its sentence — `.notInstalled` has
		// the server's install hint spliced into it, and java-debug is not a
		// program any package manager carries, so a "How to install" button would
		// promise a page that says less than the strip already does.
		return ServerNotice(
			languageId: "java",
			languageName: LanguageRegistry.shared.displayName(for: "java"),
			text: refusal.errorDescription ?? "Java cannot be debugged in this project.",
			manual: nil,
			isIgnorable: true,
			problem: true
		)
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
		let key = key(project: project, languageId: languageId)

		let definition: LanguageServerDefinition
		switch selection(for: languageId, project: project) {
		case let .server(chosen, _):
			definition = chosen
		case let .noSuchServer(name, source):
			// **The whole point of the item this came from.** Somebody asked for
			// one server and would otherwise be looking at a file with no
			// diagnostics, with nothing on screen saying that what they asked for
			// is not here. Not ignorable: "ignore Java for this session" would
			// bury a sentence about a file they wrote and can fix, and the strip
			// goes as soon as they fix it.
			//
			// No marker check in front of it either. The markers belong to a
			// definition and there is no definition — and a person looking at a
			// Java file is looking at the language they named, whatever the
			// project's build files happen to be.
			return ServerNotice(
				languageId: languageId,
				languageName: LanguageRegistry.shared.displayName(for: languageId),
				text: "\(name) was asked for and is not here, so this file has no language server.",
				manual: LanguageServers.refusal(named: name, forLanguage: languageId, source: source),
				isIgnorable: false
			)
		case .nothing:
			return nil
		}

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

		// **An executable somebody named, with nothing at that path.** Ahead of
		// the pin below it, which is the only thing ahead of everything else, and
		// the order is the argument: a pin is a fact about the project that several
		// routes might yet answer, and this is a line in a file that is wrong.
		// Whoever wrote the path is the person looking at the strip and can fix it
		// in one edit, so it is the first thing said.
		//
		// Said rather than falling through to the install hint at the bottom of
		// this function, which would be false twice: something *was* named, and
		// "rustup component add rust-analyzer" is the advice that produces the proxy
		// a named path exists to get away from. 0466.
		if let named = overrides(for: project).override(forTool: definition.name),
		   let command = named.command,
		   LanguageServers.executable(for: definition.running(command)) == nil,
		   // Not in a container. The path is the container's there, and this side
		   // has no way to look at it — a path that is absent here is the ordinary
		   // case rather than the fault, and the server failing to start says so
		   // through `ServerHealth` instead.
		   images(for: project).image(for: definition.name) == nil,
		   !usesDevContainer(project) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: "\(definition.name) was pointed at \(command), and there is nothing to "
					+ "run there, so this file has no language server.",
				manual: LanguageServerOverrides.refusal(
					command: command, forTool: definition.name, source: named.source
				),
				// Nothing to ignore: it is one line in a file, and the strip goes the
				// moment the line is right.
				isIgnorable: false,
				problem: true,
				detailsTitle: "What was named"
			)
		}

		// **A toolchain this project pins that the server cannot have.** Said
		// ahead of every state below it, including the running one, because it is
		// the one thing here that is true whatever the server is doing: it starts,
		// it answers the handshake, and it then refuses every question about every
		// file. Sentences about fetching an image or installing a copy are all
		// beside a project that none of them would read, so this goes first and
		// they are named inside its own details instead.
		if let objection = toolchainObjection(for: definition, project: project) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: objection.sentence,
				manual: objection.detail,
				// Nothing to ignore. "Ignore Rust for ever" would bury a sentence
				// about a file in this project that says exactly what is wrong with
				// it, and the strip goes by itself the moment the pin or the choice
				// of where the server comes from changes.
				isIgnorable: false,
				// Not "How to install": the answer here is not an installation and
				// offering one would be the wrong advice printed on the button.
				detailsTitle: "What can read it"
			)
		}

		// **The third state, and the whole of 0461.** A server that started and
		// then could not make sense of the project is in none of the states
		// below: it is not missing, it is not on its way, and the line under
		// this one used to return nil for it because a client that is running
		// looked like a client that is answering. What the server said about
		// itself is the evidence, and `ServerHealth` is the rule for reading it.
		//
		// In front of the running-server return rather than behind it, for the
		// same reason the devcontainer sentence above is: these are the sentences
		// a *running* server has to say about itself, and a return before them
		// hides exactly the case they exist for.
		//
		// *Behind* the pinned toolchain, though, and the two came from the same
		// project: 0462 knows the cause and can say what would read it, while
		// this only knows the server complained and can quote it. Where both
		// would fire, the one that names the reason is the better sentence.
		if let health = health[key], let text = health.sentence(for: definition.command) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				text: text,
				// Its own words, which are nearly always better than anything
				// this app could write: "custom toolchain 'esp' specified in
				// override file '/workspace/esp32/rust-toolchain.toml' is not
				// installed" names the toolchain, the file and the fault.
				manual: health.said.map { "\($0)\n\n\(Self.logPath) has the rest." },
				// Never. "Ignore Rust" is about the language on this machine and
				// this is about one project's toolchain; and the strip goes by
				// itself when the server starts answering.
				isIgnorable: false,
				problem: true,
				// Not "How to install": there is nothing missing to install, and
				// what somebody wants here is the sentence the server wrote.
				detailsTitle: "What it said"
			)
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
		if let arriving = arriving(key: key, project: project) {
			return ServerNotice(
				languageId: languageId,
				languageName: name,
				// Three sentences and not two. "Being fetched" was said of a build
				// as well, and somebody told their server is being downloaded while
				// a compiler runs for three minutes concludes their network is
				// broken — the same conflation `ToolImageRecipes.progressMessage`
				// has its own sentence to avoid. 0459.
				//
				// Written once, in `LanguageServerFooter`, because the chip beside
				// the caret says the same three things in its tool tip and 0463
				// asked that the two agree rather than each invent a vocabulary.
				text: LanguageServerFooter.arrivalSentence(languageName: name, state: arriving),
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

	/// Which of the three waits a server is in, or nil when it is not waiting.
	///
	/// One table lookup and two set lookups; nothing here touches the disk.
	/// `fetching` is the whole of "on its way" and the other two only say which
	/// kind of way it is, which is why they are read inside it — `buildingHere`
	/// is only meaningful while `fetching` holds the same key, and says nothing
	/// to anybody otherwise.
	private func arriving(key: String, project: URL) -> LanguageServerFooter.State? {
		guard fetching.contains(key) else { return nil }
		if devcontainerProjects[project.standardizedFileURL.path] == true { return .starting }
		return buildingHere.contains(key) ? .building : .fetching
	}

	// MARK: - What the footer beside the caret should say

	/// The server answering for a file, for the chip beside the caret's
	/// position, or nil for nothing.
	///
	/// **Nothing here asks the file system anything, and that is the constraint
	/// rather than a nicety.** The answer is pushed into a view that redraws on
	/// every caret move, so this must stay a handful of lookups: the project's
	/// choices, which are cached; the table of running servers; the two sets that
	/// say what is on its way. In particular there is no `LanguageServers.suits`,
	/// which walks the project two levels deep, and no `executable`, which walks
	/// the `PATH` — both of which `notice` above can afford because the strip is
	/// refreshed when a file is opened and this is read beside every keystroke.
	///
	/// **Nil is the common answer and the deliberate one.** A file whose language
	/// has no server running and none coming says nothing at all: most files in
	/// most projects are in that state, and a footer that nags about every one of
	/// them is a footer people stop reading. What there is to say about a missing
	/// server is the strip above the file, which has room for the sentence, the
	/// install hint and a way to switch it off for good.
	///
	/// **Which server, when a file's language has several.** The question does
	/// not arise, and `LanguageServers.serverKey` is why: a running server is
	/// filed under the *server's* name rather than the language's, so a `.c` and
	/// a `.cpp` in one project both find the one `clangd` entry and the chip says
	/// `clangd` under either. The footer follows the file, the file names its
	/// language, and the key turns that into the one server that answers for it.
	func footer(forLanguage languageId: String, project: URL) -> LanguageServerFooter? {
		let key = key(project: project, languageId: languageId)
		let languageName = LanguageRegistry.shared.displayName(for: languageId)

		if let server = servers[key], server.client.isRunning {
			return LanguageServerFooter(
				command: server.definition.command,
				languageName: languageName,
				origin: server.origin,
				// Running is not the same as ready, which is what this used to
				// say. A Swift package whose dependencies are not built answers
				// `No such module` for the minute it spends building them, and
				// the chip said `sourcekit-lsp` throughout — the same word it
				// says when every answer is right. 0501.
				state: preparing.contains(key) ? .preparing : .answering
			)
		}

		guard let arriving = arriving(key: key, project: project),
		      let definition = LanguageServers.definition(
		      	forLanguage: languageId, choosing: choices(for: project)
		      )
		else { return nil }
		// Where it will come from, said now rather than when it lands: a server
		// being fetched has no launch yet, and the two states the wait can be in
		// are exactly the two the name of the image tells apart.
		let origin: LanguageServerFooter.Origin = arriving == .starting
			? .devcontainer(name: nil)
			: .image(images(for: project).image(for: definition.name) ?? "")
		return LanguageServerFooter(
			command: definition.command,
			languageName: languageName,
			origin: origin,
			state: arriving
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

	/// How many `textDocument/didOpen` and `didClose` notifications have gone
	/// out, for a script that needs to say what walking a list of results costs
	/// the server.
	///
	/// A count and not a timing. What is claimed about a list of usages walked
	/// with ↓ is a number of messages, and a number of messages is the same on a
	/// loaded machine as on an idle one — which a duration is not.
	private(set) var didOpenCount = 0
	private(set) var didCloseCount = 0

	var documentTrafficForTesting: String {
		"didOpen=\(didOpenCount) didClose=\(didCloseCount) open=\(openDocuments.count)"
	}

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
			didCloseCount += 1
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
		didOpenCount += 1
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
		didCloseCount += 1
		server.client.didClose(uri: uri)

		// A closed file's problems are no longer on screen and no longer
		// anybody's business.
		diagnostics.removeValue(forKey: uri)
		NotificationCenter.default.post(name: .ideaiDiagnosticsChanged, object: url)
	}

	// MARK: - Questions

	func definition(url: URL, position: LSPPosition, languageId: String, project: URL) async -> [LSPLocation] {
		guard let (key, server) = ready(languageId, project: project, for: "definition") else { return [] }
		do {
			let found = try await server.client.definition(uri: uri(for: url), position: position)
			// Only the answer with something in it is evidence. An empty one is
			// what the cursor being on a comma looks like, every time.
			if !found.isEmpty { answered(withContent: true, for: key) }
			return found
		} catch {
			note(error, asked: "definition", of: server, about: url)
			answered(withContent: false, for: key)
			return []
		}
	}

	func hover(url: URL, position: LSPPosition, languageId: String, project: URL) async -> LSPHover? {
		guard let (key, server) = ready(languageId, project: project, for: "hover") else { return nil }
		do {
			let hover = try await server.client.hover(uri: uri(for: url), position: position)
			if hover != nil { answered(withContent: true, for: key) }
			return hover
		} catch {
			note(error, asked: "hover", of: server, about: url)
			answered(withContent: false, for: key)
			return nil
		}
	}

	func completions(
		url: URL,
		position: LSPPosition,
		languageId: String,
		project: URL
	) async -> [LSPCompletion] {
		guard let (key, server) = ready(languageId, project: project, for: "completion") else { return [] }
		do {
			let completions = try await server.client.completion(uri: uri(for: url), position: position)
			if !completions.isEmpty { answered(withContent: true, for: key) }
			return completions
		} catch {
			note(error, asked: "completion", of: server, about: url)
			answered(withContent: false, for: key)
			return []
		}
	}

	/// The characters this project's server for a language wants to be asked on.
	///
	/// Nothing where no server is running, which is the same as "ask on words
	/// only" and is what a `.scad` gets: openscad-lsp names none. Cheap on
	/// purpose — this is read on the keystroke, before anything is scheduled, so
	/// it is two dictionary lookups and a set that was built at the handshake.
	func completionTriggers(languageId: String, project: URL) -> Set<String> {
		guard let server = servers[key(project: project, languageId: languageId)] else { return [] }
		return server.client.completionTriggerCharacters
	}

	/// Whether this project's server for a language answers signature help.
	func offersSignatureHelp(languageId: String, project: URL) -> Bool {
		guard let server = servers[key(project: project, languageId: languageId)] else { return false }
		return server.client.offersSignatureHelp
	}

	/// The characters that mean "ask about this call again".
	///
	/// Empty for a server with no signature help, which is what keeps
	/// openscad-lsp from ever being sent a request it does not answer.
	func signatureTriggers(languageId: String, project: URL) -> Set<String> {
		guard let server = servers[key(project: project, languageId: languageId)] else { return [] }
		return server.client.signatureHelpTriggerCharacters
	}

	/// Whether the server that would answer for this file is still getting ready.
	///
	/// The difference between "this language has nothing to offer here" and "ask
	/// again in a minute", which the completion list had no way of telling apart:
	/// measured against a Cadova package, sourcekit-lsp answered 0 items with no
	/// error at 1, 11, 32 and 62 seconds after the file was opened, and the
	/// enum cases somebody was waiting for at 123 — after an index build of 651
	/// files. What the list showed in that window was the words already in the
	/// file, which looks like an answer.
	func isPreparing(languageId: String, project: URL) -> Bool {
		preparing.contains(key(project: project, languageId: languageId))
	}

	/// How ready this project's language servers are, taken together.
	///
	/// **For the titlebar, and the question it answers is "can I start yet".**
	/// A language server in a dev container takes a minute or two to be useful —
	/// the image, the handshake, then an index — and until now nothing said when
	/// that had happened. Everything an editor does with a server is quietly
	/// wrong before it: go-to-definition finds nothing, completion is the words
	/// already in the file, and both look like answers.
	///
	/// One state for the whole project rather than one per language: a pill has
	/// room for a colour, and what somebody wants from it is a yes.
	enum Readiness {
		/// Nothing started — a project of Markdown, or one not opened yet.
		case none
		/// At least one is on its way.
		case preparing
		/// At least one has said something is wrong, and none is still trying.
		case failed
		/// Every one that started is answering.
		case ready
	}

	func readiness(project: URL) -> Readiness {
		// Every key for a project is `<path>#<server name>`, so this is the
		// prefix they share and nothing else does — `/a/b#` is not a prefix of
		// `/a/bc#`, which is why the separator is part of it.
		let prefix = LanguageServers.serverKey(project: project, server: "")

		let started = servers.filter { $0.key.hasPrefix(prefix) }
		let onTheWay = preparing.union(fetching).filter { $0.hasPrefix(prefix) }
		guard !started.isEmpty || !onTheWay.isEmpty else { return .none }
		if !onTheWay.isEmpty { return .preparing }
		// **The handshake, not the process.** A client goes into this table the
		// moment it is spawned and answers `initialize` some seconds later, so
		// "there is a server" would go green while the server could still not be
		// asked anything — the false start this is meant to replace.
		if started.values.contains(where: { !$0.client.hasInitialized }) { return .preparing }
		if started.keys.contains(where: { health[$0]?.isWorking == false }) { return .failed }
		return .ready
	}

	/// Why a server cannot answer yet, in a sentence — or nil when it has no
	/// excuse.
	///
	/// **Telling the three apart is the whole of it.** An empty list means one
	/// of "ask again in a minute", "this server is not working", and "there is
	/// nothing here", and they want three different things from whoever is
	/// reading: wait, look at the server, or ask something else. It used to be
	/// shown only where a list happened to be on screen already; a question
	/// asked on purpose — ⌃Space, ⇧⌘O — deserves an answer even when the answer
	/// is "not yet".
	func notReadySentence(languageId: String, project: URL) -> String? {
		let key = key(project: project, languageId: languageId)
		// The strongest first: a server that has said something is wrong is not
		// preparing, it has finished and failed.
		if let failure = failure(forLanguage: languageId, project: project) { return failure }
		if preparing.contains(key) { return "\(languageId) server is still preparing…" }
		// Started nothing, and not because it is on its way. A language with no
		// server at all is not an obstacle — it is a file the words in it are
		// the best answer for — so this speaks only where one was expected.
		if servers[key] == nil, fetching.contains(key) {
			return "\(languageId) server is being fetched…"
		}
		return nil
	}

	func signatureHelp(
		url: URL,
		position: LSPPosition,
		languageId: String,
		project: URL
	) async -> LSPSignatureHelp? {
		guard let (key, server) = ready(languageId, project: project, for: "signatureHelp") else { return nil }
		// **Never sent to a server that did not claim it.** openscad-lsp
		// advertises no `signatureHelpProvider`, and driven anyway it sends no
		// reply of any kind — not an error, nothing — so the request sits until
		// its timeout. A capability nobody claimed is a question nobody asks.
		guard server.client.offersSignatureHelp else { return nil }
		do {
			let help = try await server.client.signatureHelp(uri: uri(for: url), position: position)
			if help != nil { answered(withContent: true, for: key) }
			return help
		} catch {
			note(error, asked: "signatureHelp", of: server, about: url)
			answered(withContent: false, for: key)
			return nil
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
				let symbols = try await server.client.workspaceSymbols(query: query)
				if !symbols.isEmpty { answered(withContent: true, for: key) }
				found += symbols
			} catch {
				log("\(server.definition.command) workspace/symbol failed: \(error.localizedDescription)")
				answered(withContent: false, for: key)
			}
		}
		return found
	}

	func documentSymbols(url: URL, languageId: String, project: URL) async -> [LSPSymbol] {
		guard let (key, server) = ready(languageId, project: project, for: "documentSymbol") else { return [] }
		do {
			let symbols = try await server.client.documentSymbols(uri: uri(for: url))
			// Empty is an answer, and a suspicious one: it is what a server
			// that never loaded the workspace says about every file in it. It
			// is only *evidence* where the server has already said something is
			// wrong — see `ServerHealth` — because a file with nothing declared
			// in it gives the same answer and there are plenty of those.
			//
			// Once per file: this is asked again on every keystroke in the
			// symbol palette, and a log written per keystroke is a log nobody
			// can read.
			if symbols.isEmpty, emptied.insert("\(server.definition.command)|\(url.path)").inserted {
				log("\(server.definition.command) declared nothing in \(url.lastPathComponent)"
					+ (health[key]?.said.map { " — it had already said: \($0)" } ?? ""))
			}
			answered(withContent: !symbols.isEmpty, for: key)
			return symbols
		} catch {
			note(error, asked: "documentSymbol", of: server, about: url)
			answered(withContent: false, for: key)
			return []
		}
	}

	func references(
		url: URL,
		position: LSPPosition,
		languageId: String,
		project: URL
	) async -> [LSPLocation] {
		guard let (key, server) = ready(languageId, project: project, for: "references") else { return [] }
		do {
			let found = try await server.client.references(uri: uri(for: url), position: position)
			if !found.isEmpty { answered(withContent: true, for: key) }
			return found
		} catch {
			note(error, asked: "references", of: server, about: url)
			answered(withContent: false, for: key)
			return []
		}
	}

	// MARK: - Changing code

	/// Whether renaming can be offered where the caret is.
	///
	/// Asked before anything appears on screen, because an offer that fails is
	/// worse than an absence: a field that opens, takes a name and then says the
	/// server cannot do this has wasted somebody's attention and taught them not
	/// to try again.
	///
	/// Two gates, in this order and for different reasons. **The server's
	/// capabilities** say whether it renames at all, and that is a fact about
	/// the server rather than about the caret — a server that does not rename
	/// should never be asked, and several answer `MethodNotFound` in a way that
	/// is indistinguishable from "nothing here". **`prepareRename`** then says
	/// whether there is anything at this position, and that is the ordinary
	/// silent no.
	///
	/// - Parameter fallback: the word under the caret as the editor sees it, for
	///   the servers that rename but have no `prepareRename` — which is most of
	///   them. Asking those anyway gets a refusal that reads exactly like a
	///   symbol that cannot be renamed, so the editor's own answer is used
	///   instead. It is the answer it had before it asked anything.
	func renameOffer(
		url: URL,
		position: LSPPosition,
		languageId: String,
		project: URL,
		fallback: RenameSubject?
	) async -> RenameOffer {
		guard let (key, server) = ready(languageId, project: project, for: "rename") else {
			return .noServer
		}
		guard server.client.renames else { return .serverCannot(server: server.definition.name) }

		let syntactic = server.definition.isSyntactic
		func offer(_ subject: RenameSubject?) -> RenameOffer {
			guard var subject else { return .notHere }
			subject.isSyntactic = syntactic
			return .offered(subject)
		}

		guard server.client.preparesRenames else { return offer(fallback) }

		do {
			guard let target = try await server.client.prepareRename(
				uri: uri(for: url), position: position
			) else {
				// The server's own "nothing here", which is an answer rather
				// than a failure and is not evidence about its health.
				return .notHere
			}
			answered(withContent: true, for: key)
			// `{ defaultBehavior: true }` is the server saying yes and leaving
			// the extent to the editor, which is exactly the fallback.
			guard let range = target.range else { return offer(fallback) }
			return offer(RenameSubject(
				name: target.placeholder ?? fallback?.name ?? "",
				range: range
			))
		} catch {
			note(error, asked: "prepareRename", of: server, about: url)
			// Not `answered(withContent: false)`. A server that will not answer
			// this one question has not failed to read the project — several
			// answer `MethodNotFound` for it while working perfectly — and
			// counting it against the server's health would put a sentence above
			// the file about a rename nobody has done yet.
			return offer(fallback)
		}
	}

	/// The whole change renaming this symbol comes to, and which server said so
	/// when it comes to nothing.
	///
	/// Nothing is applied here. What comes back is a description of a change,
	/// and turning it into files is `WorkspaceEditPlan` and whoever knows which
	/// documents are open — which is not this class.
	///
	/// The server's name travels with the answer rather than being looked up
	/// again at the call site: which server was asked is decided here, by
	/// `ready`, and working it out a second time somewhere else is a chance for
	/// the two to disagree about who declined.
	func rename(
		url: URL,
		position: LSPPosition,
		to newName: String,
		languageId: String,
		project: URL
	) async -> RenameAnswer {
		guard let (key, server) = ready(languageId, project: project, for: "rename") else {
			return .failed(LSPClient.ClientError.notRunning)
		}
		let name = server.definition.name
		do {
			// A server that answers `null`, or an edit that touches nothing, has
			// decided there is nothing to do. Not a failure — nothing changed,
			// and nothing is wrong — but not silent either, now that a
			// `prepareRename` has already agreed there is a symbol here: the
			// name of the server that changed its mind is what there is to say.
			guard let edit = try await server.client.rename(
				uri: uri(for: url), position: position, to: newName
			) else {
				return .nothingToChange(server: name)
			}
			answered(withContent: !edit.isEmpty, for: key)
			return edit.isEmpty ? .nothingToChange(server: name) : .edit(edit)
		} catch {
			note(error, asked: "rename", of: server, about: url)
			answered(withContent: false, for: key)
			return .failed(error)
		}
	}

	// MARK: - What a server offers

	/// What came back when a server was asked what it offers, and who said it.
	///
	/// **The server's name travels with the list**, because the lists differ in
	/// kind and not only in length: a syntactic server offers text
	/// substitutions it worked out by shape, and jdtls offers what a compiler
	/// knows. Somebody looking at a short list should be able to tell which they
	/// are getting rather than wondering why the menu changed.
	struct CodeActionOffer {
		var server: String
		/// Whether the server answering knows the code by its text rather than
		/// by its types — the same caveat a rename carries.
		var isSyntactic: Bool
		var actions: [LSPCodeAction]

		var isEmpty: Bool { actions.isEmpty }
	}

	/// What the server offers about a range, with the diagnostics under it.
	///
	/// The diagnostics are this app's own record of what the server last
	/// published for the file, sent back as they arrived. A quick fix is a fix
	/// *for* a diagnostic, and a request with an empty context comes back with
	/// refactorings and no fixes — which reads as a server that does not offer
	/// much.
	func codeActions(
		url: URL,
		range: LSPRange,
		languageId: String,
		project: URL,
		only: [String]? = nil
	) async -> CodeActionOffer? {
		guard let (key, server) = ready(languageId, project: project, for: "code actions") else {
			return nil
		}
		guard server.client.offersCodeActions else {
			return CodeActionOffer(
				server: server.definition.name,
				isSyntactic: server.definition.isSyntactic,
				actions: []
			)
		}
		let under = diagnostics(for: url).filter {
			$0.range.start.line <= range.end.line && $0.range.end.line >= range.start.line
		}
		do {
			let actions = try await server.client.codeActions(
				uri: uri(for: url), range: range, diagnostics: under, only: only
			)
			answered(withContent: !actions.isEmpty, for: key)
			return CodeActionOffer(
				server: server.definition.name,
				isSyntactic: server.definition.isSyntactic,
				actions: actions
			)
		} catch {
			note(error, asked: "code actions", of: server, about: url)
			answered(withContent: false, for: key)
			return nil
		}
	}

	/// Fills an action in, where it arrived without its work.
	///
	/// Returns the action unchanged when the server has nothing to add or
	/// refuses — the caller then has an action that still needs resolving,
	/// which is a thing that can be said out loud, rather than an empty edit
	/// that quietly does nothing.
	func resolve(
		_ action: LSPCodeAction, url: URL, languageId: String, project: URL
	) async -> LSPCodeAction {
		guard action.needsResolving,
		      let (_, server) = ready(languageId, project: project, for: "resolving an action"),
		      server.client.resolvesCodeActions
		else { return action }
		do {
			return try await server.client.resolveCodeAction(action)
		} catch {
			note(error, asked: "codeAction/resolve", of: server, about: url)
			return action
		}
	}

	/// Runs a command an action carried, and says whether the server took it.
	///
	/// What the server does next may be to ask *this* program to apply an edit,
	/// which arrives as `workspace/applyEdit` and is answered elsewhere. So a
	/// `true` here means the command was accepted, not that anything changed.
	func run(
		_ command: LSPCommand, url: URL, languageId: String, project: URL
	) async -> Bool {
		guard let (_, server) = ready(languageId, project: project, for: "running a command") else {
			return false
		}
		do {
			_ = try await server.client.executeCommand(command.command, arguments: command.argumentList)
			return true
		} catch {
			note(error, asked: "executeCommand", of: server, about: url)
			return false
		}
	}

	/// The server for a question, or nil with a line in the log saying there
	/// was none — "no answer" and "nobody was asked" look identical on screen.
	///
	/// The key comes back with it because how the question went is filed under
	/// the server, and working it out a second time at every call site is a walk
	/// of the project's choices for an answer already in hand.
	private func ready(
		_ languageId: String, project: URL, for question: String
	) -> (key: String, server: Server)? {
		let key = key(project: project, languageId: languageId)
		guard let server = servers[key] else {
			log("no \(languageId) server for \(project.lastPathComponent): \(question) unanswered")
			return nil
		}
		return (key, server)
	}

	private func note(_ error: Error, asked question: String, of server: Server, about url: URL) {
		log("\(server.definition.command) \(question) failed for \(url.lastPathComponent): "
			+ error.localizedDescription)
	}

	// MARK: - What a server has said about itself since it started

	/// What this project's server for a language said, when it is not working.
	///
	/// Read by the empty state of the symbol palette, which is where this used
	/// to be the *first* thing anybody heard — 0461 — and where the sentence it
	/// produces is already the right one.
	func failure(forLanguage languageId: String, project: URL) -> String? {
		let health = health[key(project: project, languageId: languageId)]
		guard let health, !health.isWorking else { return nil }
		return health.said
	}

	/// How a question to a server went.
	///
	/// Nothing at all when the server has said nothing wrong, which is nearly
	/// every call: this is on the path of every completion and every hover, and
	/// the whole of it there is one dictionary lookup. Where a server *has* said
	/// something, this is what decides between the two readings of it — an
	/// answer with content in it takes the sentence back, and a question it
	/// could not answer confirms it.
	private func answered(withContent: Bool, for key: String) {
		guard let current = health[key], !current.isWorking else { return }
		// An empty answer from a server that is still preparing is not evidence
		// of anything: it is what preparing *looks like*. Hover and completion
		// over a module that has not been built yet come back with nothing for
		// the whole of that minute, and reading those as the failed question
		// that turns a report into "cannot read this project" would put the
		// strongest sentence this app has over the most ordinary thing a Swift
		// project does. 0501.
		//
		// An answer *with* content is still taken, and taken gladly: it is the
		// evidence that withdraws a sentence, and there is no case for holding
		// good news back.
		guard withContent || !preparing.contains(key) else { return }
		changeHealth(of: key) { $0.answered(withContent: withContent) }
	}

	/// Records something about a server's health, and tells the screen only when
	/// the answer actually moved.
	private func changeHealth(of key: String, _ change: (inout ServerHealth) -> Void) {
		var health = self.health[key] ?? ServerHealth()
		let before = health
		change(&health)
		guard health != before else { return }
		self.health[key] = health
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
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
		case noServer(hint: String)
		case noBundle
		case refused(String)

		var errorDescription: String? {
			switch self {
			case let .noServer(hint):
				return "The Java language server is not running for this project, "
					+ "and it is what hosts the debugger. \(hint)"
			case .noBundle:
				return "The Java language server is running but has no debugger in it: "
					+ "the java-debug bundle was not found when it started."
			case let .refused(reason):
				return reason
			}
		}
	}

	/// Everything a Java launch needs, and it all has to come from one server.
	///
	/// The port and the classpath are two answers from the same jdtls: a port from
	/// one process and a classpath from another would start a JVM with somebody
	/// else's idea of where the classes are.
	struct JavaLaunchTarget {
		let port: Int
		let projectName: String?
		let classPaths: [String]
		/// Whether this came from a jdtls started for the debugger alone, which is
		/// what the log and the status line say — the person who chose the fast
		/// server for editing is paying for a JVM they did not ask to see, and the
		/// least that owes them is a sentence.
		let fromDebugHost: Bool
	}

	/// The port and the classpath a Java launch needs, from whichever jdtls can
	/// give them.
	///
	/// **Two ways in, and which one it is depends on what the project chose for
	/// editing.**
	///
	/// - The chosen server hosts the adapter — jdtls, the default. It is already
	///   running and has already imported the project, so this is the fast path
	///   and the one that existed before 0452.
	/// - The chosen server does not — kmp-lsp. Then jdtls is started *here*, for
	///   the debugger and nothing else, and the wait for its import is what
	///   pressing Debug costs. Which is a wait to explain rather than hide: the
	///   only alternatives were paying it at every project open for the sessions
	///   that never debug, and having no debugger at all.
	///
	/// - Parameter saying: what the wait is waiting for, every time it changes.
	func javaLaunchTarget(
		project: URL,
		anchor: URL?,
		deadline: TimeInterval = 600,
		saying: @escaping (String) -> Void = { _ in }
	) async throws -> JavaLaunchTarget {
		// Off the main actor: this type is @MainActor, and the scan reads every
		// source file in the project. Spelled out rather than through `??`,
		// whose autoclosure cannot carry an await.
		var chosen = anchor
		if chosen == nil {
			chosen = await JavaTooling.mainClassesOffMain(in: project).first
				.map { URL(fileURLWithPath: $0.file) }
		}
		let anchor = chosen

		// The chosen server, when it is one that hosts an adapter. Nothing starts
		// a second jdtls beside a jdtls: the one that is running has the import
		// this needs, and a second would spend the minutes again for the same
		// answer and hold a second copy of it.
		if let server = server(for: "java", project: project), server.client.isRunning,
		   server.definition.hostsDebugAdapter {
			guard JavaTooling.debugPlugin() != nil else { throw JavaDebugFailure.noBundle }
			saying("Asking \(server.definition.name) for a debug port")
			let port = try await portFromEditingServer(server)
			guard let anchor, let resolved = await classpathWaiting(
				for: anchor, project: project, deadline: deadline, saying: saying
			) else {
				throw JavaDebugFailure.refused(
					"\(server.definition.name) is running but has no classpath for this project "
						+ "yet, so there is nothing to start a JVM with. A project it is still "
						+ "importing cannot be debugged until it has finished."
				)
			}
			// An answer with nothing in it, which is a different thing from no
			// answer and was the older code's silent failure: it sent the launch
			// anyway and the JVM died with `ClassNotFoundException` on the class
			// somebody had asked for. Measured on a Tycho bundle, where this is what
			// jdtls says and goes on saying.
			guard !resolved.classPaths.isEmpty else {
				throw JavaDebugHost.Failure.noClasspath(
					project: resolved.projectName ?? project.lastPathComponent
				)
			}
			// Compiled first, for the reason `JavaDebug.buildCommand` records: a
			// classpath is a set of directories and jdtls fills them after the
			// import, so the first launch of a session can be handed a right
			// classpath with nothing in it. A no-op when nothing has changed, which
			// is the ordinary case here — this path is a project somebody has been
			// editing.
			saying("Compiling the project, so there is something on the classpath to run")
			_ = try? await server.client.executeCommand(
				JavaDebug.buildCommand, arguments: [JavaDebug.buildOptions()], timeout: 300
			)
			// **And hot code replace on, before the session exists to want it.**
			// In `AUTO` the provider inside the bundle redefines whatever this
			// server recompiles, so the swap follows the compile finishing rather
			// than this app guessing when it has. Best-effort: a server that will
			// not take the setting costs a session its swaps, where refusing to
			// start over it would cost the debugging too.
			// Logged, because a setting that silently did not take is exactly how
			// this went wrong twice already — first as a dictionary the server
			// refused, then as a JSON string with no `logLevel` in it. Whether
			// the swap is even switched on is not a thing to guess at from the
			// outside.
			let accepted = (try? await server.client.executeCommand(
				JavaDebug.settingsCommand,
				arguments: [JavaDebug.HotSwap.settings(mode: .auto)],
				timeout: 15
			)) != nil
			log("java hot code replace: asked \(server.definition.name) for AUTO — "
				+ (accepted ? "accepted" : "refused or timed out"))
			return JavaLaunchTarget(
				port: port, projectName: resolved.projectName,
				classPaths: resolved.classPaths, fromDebugHost: false
			)
		}

		// Nothing that hosts an adapter is answering about files here, so one is
		// started for the debugger alone.
		guard let anchor else {
			throw JavaDebugFailure.refused(
				"No Java source in this project names a class with a `main` method, so there is "
					+ "nothing for a classpath to be worked out about."
			)
		}
		let host = try debugHost(for: project)
		let ready = try await host.waitUntilLaunchable(
			anchor: anchor, deadline: deadline, saying: saying
		)
		// What a JVM is about to be started with, in the log. A launch that fails
		// says `ClassNotFoundException` on the class somebody asked for, which
		// names the symptom and not one thing about the cause; this is the line
		// that does. Once per session, not per keystroke.
		await host.setHotCodeReplace(.auto)
		log("java launch in \(project.lastPathComponent) from the debugger's own jdtls: "
			+ "project \(ready.projectName ?? "unnamed"), \(ready.classPaths.count) classpath "
			+ "entries, first \(ready.classPaths.first ?? "none")")
		return JavaLaunchTarget(
			port: ready.port, projectName: ready.projectName,
			classPaths: ready.classPaths, fromDebugHost: true
		)
	}

	/// Compiles this project's Java for a swap into a running JVM.
	///
	/// **The same request a launch makes, asked for a different reason.** A
	/// change on disk is not a class file until jdtls has been asked, which is
	/// what `buildCommand` is on the launch path for; a swap needs exactly that
	/// and nothing more, because the adapter is listening to the workspace and
	/// redefines what the compile writes.
	///
	/// Whichever jdtls the debugger is using answers: the editing server when it
	/// hosts the adapter, and otherwise the one started for the debugger alone.
	/// Asking the wrong one would compile into a workspace nothing is watching.
	///
	/// Returns false when there is no such server, which is the ordinary state of
	/// a project nobody is debugging — the caller asks only during a session.
	@discardableResult
	func compileJavaForSwap(project: URL, timeout: TimeInterval = 300) async -> Bool {
		if let server = server(for: "java", project: project), server.client.isRunning,
		   server.definition.hostsDebugAdapter {
			return (try? await server.client.executeCommand(
				JavaDebug.buildCommand, arguments: [JavaDebug.buildOptions()], timeout: timeout
			)) != nil
		}
		guard let host = debugHosts[Self.debugHostKey(project: project)], host.isRunning else {
			return false
		}
		return await host.buildWorkspace(timeout: timeout)
	}

	/// The debug port from a jdtls that is already answering about files.
	///
	/// Retried, because "not yet" and "never" look the same from here: a server
	/// that is still importing refuses, and a few seconds later the same call
	/// succeeds. Pressing Debug the moment a project opens is exactly when that
	/// happens.
	private func portFromEditingServer(_ server: Server) async throws -> Int {
		var lastError: Error?
		for attempt in 0..<5 {
			if attempt > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
			do {
				let result = try await server.client.executeCommand(
					JavaDebug.startCommand, timeout: JavaDebug.queryTimeout
				)
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

	/// The jdtls this project debugs through, started if it is not up.
	///
	/// Filed under a key of its own so the list of what is running has a row for
	/// it and Stop reaches it. It is a JVM holding gigabytes that nobody chose,
	/// and a process this app started and cannot be seen is exactly what 0427 was
	/// about.
	private func debugHost(for project: URL) throws -> JavaDebugHost {
		let key = Self.debugHostKey(project: project)
		if let existing = debugHosts[key] {
			if existing.isRunning { return existing }
			debugHosts.removeValue(forKey: key)
		}
		let host = try JavaDebugHost.start(
			project: project,
			// A project worked on inside its devcontainer is refused rather than
			// given a jdtls out here. That was already true before this existed —
			// `initializationOptions` offers no bundle to a containerised server —
			// and it is now a sentence rather than a silence.
			inDevContainer: devContainerNameHoldingServers(for: project)
		)
		debugHosts[key] = host
		log("jdtls started for the debugger alone in \(project.lastPathComponent): "
			+ "the server answering about files does not host an adapter")
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)

		Task { @MainActor in
			do {
				try await host.handshake()
			} catch {
				log("the debugger's jdtls would not shake hands: \(error.localizedDescription)")
			}
		}
		return host
	}

	/// The devcontainer a project's language servers live inside, when they do.
	///
	/// Asked by the debugger, which cannot follow them in there: the java-debug
	/// bundle is a path on this machine and the JVM would be this machine's, so
	/// what got debugged would be a different toolchain from what the project
	/// builds with.
	func devContainerNameHoldingServers(for project: URL) -> String? {
		guard usesDevContainer(project) else { return nil }
		return devcontainers[project]?.session.name ?? "its devcontainer"
	}

	/// The key a debug host is filed under.
	///
	/// The server's name with what it is here for beside it, so a row in the list
	/// of what is running says why there is a second jdtls — and so it can never
	/// collide with the key the *editing* jdtls would hold for the same project.
	static func debugHostKey(project: URL) -> String {
		LanguageServers.serverKey(project: project, server: "jdtls (debugger)")
	}

	/// The runtime classpath of the project a file belongs to.
	///
	/// Java cannot be started without one and nothing but the build knows it,
	/// which is why this asks the server that read the build file rather than
	/// guessing from `target/` and `build/`.
	///
	/// **An answer about another project is not an answer.** Before jdtls has
	/// imported the project it replies about `jdt.ls-java-project`, the fallback
	/// workspace it keeps inside its own `-data` directory — a well-formed
	/// classpath, for the wrong thing. Taking it starts a JVM that fails with
	/// `UnsupportedClassVersionError` or `ClassNotFoundException`, which reads as a
	/// broken project. See `JavaDebugHost.classpath(for:)`, where this was found.
	/// The classpath, waiting while the server is still working it out.
	///
	/// **One ask used to be the whole of it**, and "not yet" — which is what a
	/// large project answers for as long as it is importing — was reported as
	/// "there is nothing to start a JVM with". It recovered if somebody pressed
	/// Debug again a few minutes later, which is the shape of a wait misreported
	/// as a failure, and it left a suspended JVM behind each time.
	///
	/// The other route to a debug session — `JavaDebugHost.waitUntilLaunchable` —
	/// has waited on the same deadline with the same progress from the start. This
	/// is the editing-server route catching up, so which of the two you get no
	/// longer decides whether Debug can work on a big repository.
	///
	/// Says what it is waiting for, every few seconds: an import of a thousand
	/// modules is minutes of nothing on screen otherwise, and "still importing" is
	/// the difference between a wait somebody will sit through and a hang they
	/// will kill.
	private func classpathWaiting(
		for anchor: URL,
		project: URL,
		deadline: TimeInterval,
		saying: @escaping (String) -> Void
	) async -> (projectName: String?, classPaths: [String])? {
		let started = Date()
		while true {
			if let resolved = await javaClasspath(for: anchor, project: project),
			   !resolved.classPaths.isEmpty {
				return resolved
			}
			let waited = Int(Date().timeIntervalSince(started))
			guard Double(waited) < deadline else { return nil }

			// The server's own state rather than a guess: "importing" is a wait
			// with an end, and anything else is a server that answered "no
			// classpath" and will go on answering it.
			let importing = isPreparing(languageId: "java", project: project)
			saying(
				importing
					? "Waiting for the classpath — jdtls is still importing, \(waited) s"
					: "Waiting for the classpath — \(waited) s"
			)
			// In the log as well as on screen, at a coarser interval: the status
			// line is gone the moment the launch ends, and a launch that failed
			// after four minutes of waiting is unanswerable afterwards without
			// this. Twice today it was.
			if waited > 0, waited % 15 < 3 {
				log("java classpath still unresolved after \(waited) s for "
					+ "\(project.lastPathComponent)"
					+ (importing ? " — jdtls is importing" : " — jdtls is not importing"))
			}
			try? await Task.sleep(nanoseconds: 3_000_000_000)
		}
	}

	func javaClasspath(for url: URL, project: URL) async -> (projectName: String?, classPaths: [String])? {
		guard let server = server(for: "java", project: project), server.client.isRunning else { return nil }
		do {
			let result = try await server.client.executeCommand(
				JavaDebug.classpathCommand,
				arguments: [uri(for: url), JavaDebug.classpathOptions()],
				timeout: JavaDebug.queryTimeout
			)
			guard let object = result as? [String: Any] else { return nil }
			guard let answeredFor = object["projectRoot"] as? String,
			      JavaDebugHost.isInside(answeredFor, project)
			else {
				log("java classpath for \(url.lastPathComponent) came back about "
					+ "\((object["projectRoot"] as? String) ?? "no project") rather than about "
					+ "\(project.lastPathComponent) — the import has not finished")
				return nil
			}
			let paths = object["classpaths"] as? [String] ?? []
			let modules = object["modulepaths"] as? [String] ?? []
			return (
				JavaDebugHost.projectName(fromRoot: answeredFor), paths + modules
			)
		} catch {
			log("java classpath unavailable for \(url.lastPathComponent): \(error.localizedDescription)")
			return nil
		}
	}

	/// How far the Java server is from being able to *launch* something, as
	/// against being able to answer about a file.
	///
	/// 0452's central measurement, and a probe of its own rather than
	/// `startJavaDebugAdapter` because that one retries five times over eight
	/// seconds — the right thing when somebody has pressed Debug, and ruinous
	/// when what is being timed is the moment the answer changes.
	///
	/// Two questions, because they become answerable at different moments and
	/// the distance between them is the finding. The port says java-debug is
	/// loaded and listening, which needs the bundle and nothing else. The
	/// classpath says the import has got far enough to say what a launch would
	/// *run*, and a port with an empty classpath is not a debuggable project.
	/// - Returns: the port, and what the classpath command said — `nil` for a
	///   question it did not answer, and a count for one it did. **The difference
	///   matters and cost an hour to find.** On a Tycho bundle jdtls answers
	///   `getClasspaths` promptly and with *nothing in it*, which through a
	///   `?? 0` is indistinguishable from a server that has not finished — and one
	///   of those is a wait and the other is an answer nobody should wait for.
	func javaDebugReadinessForTesting(
		url: URL, project: URL
	) async -> (port: Int?, classPaths: Int?) {
		guard let server = server(for: "java", project: project), server.client.isRunning,
		      server.definition.hostsDebugAdapter
		else { return (nil, nil) }

		var port: Int?
		if let result = try? await server.client.executeCommand(JavaDebug.startCommand) {
			port = (result as? Int) ?? (result as? NSNumber)?.intValue
		}
		return (port, await javaClasspathCount(for: url, project: project))
	}

	/// How many entries the classpath command answered with, or nil when it did
	/// not answer at all.
	private func javaClasspathCount(for url: URL, project: URL) async -> Int? {
		guard let server = server(for: "java", project: project), server.client.isRunning,
		      let result = try? await server.client.executeCommand(
		      	JavaDebug.classpathCommand,
		      	arguments: [uri(for: url), JavaDebug.classpathOptions()]
		      ),
		      let object = result as? [String: Any]
		else { return nil }
		return (object["classpaths"] as? [String] ?? []).count
			+ (object["modulepaths"] as? [String] ?? []).count
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

		// A server this project named and this app has not got. **It stops
		// here** — and stopping here is the whole of it. Falling through to the
		// server that was not chosen would give somebody who asked for the fast
		// one a JVM and 1.9 GB, with nothing anywhere saying why.
		if case let .noSuchServer(name, source) = selection(for: languageId, project: project) {
			unavailable.insert(key)
			let said = LanguageServers.refusal(named: name, forLanguage: languageId, source: source)
			missingHints[key] = said
			log(said)
			// Said out loud, which the ordinary missing server deliberately is
			// not: that one is a language somebody never asked about, and this
			// one is a sentence they wrote themselves and can fix. Once per
			// server per project, because a project full of Java files would
			// otherwise say it on every open.
			if refused.insert(key).inserted {
				Toast.post(
					"No language server called \(name)",
					detail: said,
					kind: .error
				)
			}
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			return nil
		}

		// A project that says what it is worked on in has its servers in there.
		if usesDevContainer(project) {
			return serverInDevContainer(for: languageId, project: project, key: key)
		}

		guard let resolved = resolution(for: languageId, project: project) else {
			unavailable.insert(key)
			if let definition = LanguageServers.definition(
				forLanguage: languageId, choosing: choices(for: project)
			), LanguageServers.suits(definition, root: project) {
				missingHints[key] = chosenButAbsent(definition, languageId: languageId, project: project)
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
		if ToolImageRecipes.isBuiltHere(image.name) {
			buildingHere.insert(key)
		} else {
			buildingHere.remove(key)
		}
		log("\(resolved.definition.command) comes from \(image.name); making sure it is here")
		// **Somewhere to watch it happen**, which is 0459. The sentence below used
		// to be the whole of what reached the screen, and it was written for a
		// pull: `ensure` also *builds*, from a Dockerfile this app ships, and a
		// cold `rust-analyzer` is 164 seconds of a compiler saying nothing anybody
		// could see. `ImageArrival` opens the same pane the devcontainer path
		// opens, on the same terms, and passes the second sink `ensure` has always
		// taken and this call site never gave it.
		let built = ToolImageRecipes.isBuiltHere(image.name)
		// The **name** and not the command, which is the difference between a tab
		// called "Building pyright" and one called "Building pyright-langserver".
		// `LanguageServers.Definition` keeps the two apart for exactly this: the
		// name is what somebody calls the tool and what they typed to ask for it,
		// and the command is the binary inside the image.
		let named = resolved.definition.name
		let arrival = ImageArrival(image: image.name, tool: named, project: project)
		Task { @MainActor in
			let outcome = await ContainerImageStore.shared.ensure(
				image.name,
				using: image.runtime,
				progress: arrival.watch.step,
				output: arrival.watch.output
			)
			// The pane is ended before anything else, and whatever the project did
			// meanwhile: a tab left saying a build is happening after it has
			// stopped is worse than no tab.
			var tab: String?
			if case let .failed(reason) = outcome {
				tab = arrival.failed(reason)
			} else {
				arrival.arrived()
			}
			// Gone while the image was on its way: the project was closed, and a
			// server started for it now would be a process nobody is waiting for.
			guard fetching.remove(key) != nil else { return }
			if case let .failed(reason) = outcome {
				// Not tried again for this project: a name that is wrong is
				// wrong every time, and a registry that wants a sign-in wants
				// one until somebody gives it. Reopening the project asks again.
				unavailable.insert(key)
				// Not running and never will be, under the conditions in force:
				// the strip says so rather than leaving the file looking like
				// one whose language nobody has a server for.
				changeHealth(of: key) { $0.stopped(saying: reason) }
				log("\(resolved.definition.command): \(reason)")
				Toast.post(
					// "could not be fetched" was said of a build too, which is the
					// same conflation 0434 wrote a separate sentence to avoid:
					// nothing in `abydos-built/` is ever fetched from anywhere.
					// The name here too, so the corner and the tab it points at are
					// about the same thing.
					"\(named) could not be \(built ? "built" : "fetched")",
					// The reason *and* where the log is, which is where this parts
					// company with 0444 on purpose — see `ImageArrival.failed`. The
					// sentence is a diagnosis rather than a summary, so it is worth
					// having in the corner; the tab is for the one failure that is a
					// line somewhere in a hundred.
					detail: tab.map {
						"\(reason)\nWhat the \(built ? "build" : "fetch") printed is in the "
							+ "\($0) tab in the terminal panel."
					} ?? reason,
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

	// MARK: - When a preference changes underneath a server

	/// Settings were written. Which setting is not said — there is one
	/// notification for all of them — so the answer is to look.
	///
	/// **Not at once.** Two reasons, and the second is the one that matters.
	/// Every write posts this, so a slider on the appearance page would otherwise
	/// walk every open project to discover it has nothing to do. And a text field
	/// for an image name is a value on its way to being a value: the field this
	/// app has sends its action when the editing ends rather than per character,
	/// so today's controls settle by themselves — but a preference change costs a
	/// server being stopped and started, and that is not a bill to leave resting
	/// on a control's configuration. Coalescing takes the last of a run of writes
	/// and acts on that one.
	private func settingsChanged() {
		reconsidering?.cancel()
		reconsidering = Task { @MainActor in
			try? await Task.sleep(nanoseconds: 400_000_000)
			guard !Task.isCancelled else { return }
			self.reconsider()
		}
	}

	/// Goes back over what is remembered about servers not working, because a
	/// preference that decided it has changed.
	///
	/// The whole of 0460 is here. A server that failed is not tried again for the
	/// project — deliberately, since a name that is wrong is wrong every time —
	/// and until now the only thing that undid it was `shutdown(server:)`, which
	/// is Stop in the list of running servers. So somebody who chose an image for
	/// a server that had already failed got nothing at all: no container, no
	/// build, no message, and nothing on screen disagreeing with what they asked
	/// for.
	///
	/// **It starts what it clears, rather than only unclearing it.** Clearing the
	/// memory alone would make the *next* file of that language ask again, and
	/// the person who has just chosen an image is looking at the editor now.
	/// "It works when you go back to the file" is the same fault with a longer
	/// fuse — they would have gone and looked for the fault somewhere else long
	/// before opening that file again. So an affected project is warmed up as
	/// though it had just been opened, and the files already on screen are
	/// announced again through `.ideaiLanguageServersMoved`, which is the path a
	/// project moving in or out of its devcontainer already takes.
	///
	/// The cost of that is bounded by `ServerReconsideration` deciding what is
	/// affected: a project with nothing to do is not walked at all.
	private func reconsider() {
		let now = ToolPreferences(Settings.shared)
		let change = now.changes(since: preferences)
		guard !change.isEmpty else { return }
		preferences = now

		// Every project this session has asked anything about, which is what the
		// choices cache holds. A project switched away from is included, and that
		// is 0427's promise rather than an oversight: its servers are deliberately
		// still running, so they are servers this can be wrong about.
		for path in serverChoices.keys.sorted() {
			reconsider(URL(fileURLWithPath: path, isDirectory: true), after: change)
		}
	}

	private func reconsider(_ project: URL, after change: ToolPreferences.Change) {
		let path = project.standardizedFileURL.path
		let wasChoosing = choices(for: project)
		let wasFrom = images(for: project)
		// Read again, both of them, and from the project's file as well as from
		// settings: what is in force is the two merged, and only one half is known
		// to have moved.
		serverChoices.removeValue(forKey: path)
		toolImages.removeValue(forKey: path)

		let decision = ServerReconsideration(
			change: change,
			project: project,
			was: wasChoosing,
			wasFrom: wasFrom,
			now: choices(for: project),
			nowFrom: images(for: project),
			running: Set(servers.keys),
			inDevContainer: usesDevContainer(project)
		)
		guard !decision.isEmpty else { return }

		// Stopped first, and through the same call the list of running servers
		// uses, so a server that is no longer the one being asked for goes the way
		// a server stopped by hand goes: the protocol's own shutdown, the process,
		// the container if it had one, and the documents it held forgotten.
		//
		// **Stopping it is the disruptive reading and it is the right one.** A
		// project holds one server per language and no more, because two answering
		// over one file is two sets of diagnostics with no rule for which wins; and
		// what the old one goes on publishing is a toolchain the project no longer
		// uses, which is the fault 0432 is about. jdtls's import is minutes and
		// those minutes are the cost of the choice that was just made, paid now,
		// while somebody is looking at the thing they changed — rather than at some
		// later moment they cannot connect to it.
		for key in decision.stop.sorted() {
			shutdown(server: key, because: "because a preference changed")
		}

		// And the debugger's own jdtls, if the project has just asked for a server
		// that hosts the adapter itself. It is then a second JVM importing the same
		// reactor for an answer the editing server is about to have, and the next
		// Debug would go through that one — so what this leaves running is a
		// gigabyte or two of nothing.
		//
		// Only in that direction. A project that has just moved *away* from jdtls
		// keeps its debug host, because it is what debugging goes through now.
		let hostKey = Self.debugHostKey(project: project)
		if debugHosts[hostKey] != nil,
		   LanguageServers.definition(
		   	forLanguage: "java", choosing: choices(for: project)
		   )?.hostsDebugAdapter == true {
			shutdown(
				server: hostKey,
				because: "because the project's own Java server now hosts the debugger"
			)
		}

		for key in decision.forget {
			unavailable.remove(key)
			missingHints.removeValue(forKey: key)
			lastStandardError.removeValue(forKey: key)
			refused.remove(key)
			// **Where 0461 meets 0460.** A server that is running and cannot read
			// the project is exactly the state somebody fixes by choosing another
			// image, another server or a runtime that works — and what it said
			// was said about a toolchain that is no longer the one being asked
			// for. Left behind, the strip would go on reporting a refusal from a
			// server that has since been replaced.
			health.removeValue(forKey: key)
			preparing.remove(key)
			// An image still on its way, for an answer that has been replaced. The
			// fetch itself is left to finish — the image is worth having on the
			// machine either way — but taking the key out is what makes it stop at
			// the guard it already has and not start a server nobody asked for.
			fetching.remove(key)
			deferredOpens.removeValue(forKey: key)
		}
		// Said out loud again if it happens again, which is what `shutdown(project:)`
		// does for the same reason.
		announced.removeAll()

		log("\(project.lastPathComponent): a preference changed — "
			+ "\(decision.forget.count) server(s) reconsidered, "
			+ "\(decision.stop.count) stopped")

		warmUp(project: project)
		// The files already open have to be announced to whatever answers for them
		// now: a server that was stopped forgot them, and one that has just started
		// never knew. Nothing here can reach the text — the editor groups hold it —
		// which is what this notification is for.
		NotificationCenter.default.post(name: .ideaiLanguageServersMoved, object: project)
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
			languageId: languageId, project: project, inDevContainer: session,
			choosing: choices(for: project),
			// Named for the container's own PATH, and honoured here for the same
			// reason as everywhere else: a devcontainer built on a toolchain manager
			// has that manager's proxy on its PATH too.
			command: LanguageServers.definition(
				forLanguage: languageId, choosing: choices(for: project)
			).flatMap { overrides(for: project).command(forTool: $0.name) }
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
		// **A server asking this program to change files.** Set on every client
		// because any server may send it — it is usually the second half of a
		// code action that was a command — and answered by whichever window is
		// in front, since applying an edit means the rope of whatever documents
		// are open. Nothing in front is an honest `false`: a server told that
		// the edit did not happen can say so, where one told nothing waits.
		client.onApplyEdit = { [weak self] edit, label, answer in
			self?.serverEditsForTesting += 1
			guard let handler = self?.applyEditFromServer else {
				answer(false, "This editor has no window to apply the edit in.")
				return
			}
			DispatchQueue.main.async { handler(edit, label, answer) }
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
			// A server that died in the middle of preparing. The chip goes with
			// the entry, but the set is what `footer` reads and a key left in it
			// would say "preparing" from the first frame of whatever starts next.
			self.preparing.remove(key)
			self.runningNames.removeAll { $0 == resolved.definition.command }
			self.log("\(resolved.definition.command) exited")
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		// Everything the server says about itself goes to the log, and the part
		// of it that means "I cannot work" is said out loud once.
		client.onMessage = { [weak self] level, text in
			self?.serverSaid(level: level, text: text, definition: resolved.definition, key: key)
		}
		// Twice per server and no more: once when it starts building what the
		// project depends on, once when it has finished. The chip beside the
		// caret is the only thing that reads it, and `.ideaiLanguageServersChanged`
		// is what pushes it there — the same notification every start, stop and
		// refusal already posts, so nothing new has to be listened for.
		client.onPreparing = { [weak self] isPreparing in
			guard let self else { return }
			// By key rather than by client: a server stopped by hand and started
			// again under the same key is a different client, and the one that
			// is filed now is the one the chip is drawn from.
			if isPreparing { self.preparing.insert(key) } else { self.preparing.remove(key) }
			self.log("\(resolved.definition.command) "
				+ (isPreparing ? "is preparing this project" : "has finished preparing"))
			// The same notification the footer's chip is drawn from, and now also
			// what makes a completion list saying "still preparing" ask again:
			// it is posted the moment preparing stops, so nothing polls and
			// nothing sets a timer.
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
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
				//
				// Out here it is asked for, because for one server it is not the
				// project: sourcekit-lsp builds the package to index it, and 0518
				// found a build of it writing 1424 files into somebody's checkout,
				// because a relative path is written where the process stands.
				// `LanguageServers.workingDirectory` says why the answer for that
				// one is the index's own directory. Only on this route: the
				// directory a container's runtime is started in is not the
				// directory the server runs in, and a cache path from this machine
				// would say nothing about either.
				workingDirectory: resolved.launch.paths == nil
					? LanguageServers.workingDirectory(
						for: resolved.definition, root: resolved.root)
					: canonical(resolved.root),
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
			insideContainer: resolved.launch.hostContainerName,
			origin: resolved.launch.origin
		)
		servers[key] = server
		// A new process is a new question: whatever the last server under this
		// key said about the project was said by a program that is not running
		// any more, and leaving it here would put a strip over a server that has
		// not been given the chance to say anything.
		health.removeValue(forKey: key)
		// And it has not started preparing yet. A key left in this set from the
		// server before would have the chip saying "preparing" from the first
		// frame of a server that may never say a word about progress.
		preparing.remove(key)

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
						inContainer: resolved.launch.paths != nil,
						// And whatever this project says to tell it, which for every
						// server but jdtls is the only thing in there. 0466's case is
						// rust-analyzer's `procMacro.server`, a path into a toolchain
						// this repository cannot know the name of.
						merging: overrides(for: project)
							.initializationOptions(forTool: resolved.definition.name)
					),
					timeout: isJava ? 120 : 10
				)
				log("\(resolved.definition.command) initialized")
				// **Said out loud, because something now depends on the moment
				// it happens.** The handshake finishing used to change nothing
				// anybody could see — the strip and the chip are drawn from
				// `preparing`, and a server that never reports progress goes
				// from spawned to usable without touching it. The titlebar's
				// "your tools are ready" is drawn from `readiness`, which turns
				// on exactly here, so exactly here has to post.
				NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
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
				// **The reproduction 0461 was written from ends here.** The
				// rust-analyzer image, pointed at a project that pins a
				// toolchain the image has not got, prints one line on standard
				// error and exits before the handshake — so the toast said it
				// once and then nothing on screen said anything at all, because
				// the strip above the file only ever knew about servers that had
				// not been *started*.
				changeHealth(of: key) { $0.stopped(saying: said) }
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
		let choices = choices(for: project)
		// Two questions and they stay two: which server this project wants, and
		// where that server comes from. The image is looked up under the chosen
		// server's name, so a project that changes its mind about the server gets
		// the image named for the one it now uses rather than the one it dropped.
		let image = LanguageServers.definition(forLanguage: languageId, choosing: choices)
			.flatMap { images(for: project).image(for: $0.name) }

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
			languageId: languageId, project: project, image: image, runtime: runtime,
			choosing: choices,
			// The executable this project or this person named for the server, if
			// either did. Asked of the *chosen* server's name, like the image above
			// and for the same reason.
			command: LanguageServers.definition(forLanguage: languageId, choosing: choices)
				.flatMap { overrides(for: project).command(forTool: $0.name) }
		)
	}

	/// What this project's own toolchain pin means for where this server comes
	/// from, or nil when it pins nothing or pins something the server can have.
	///
	/// **Known before anything is started**, which is the whole of 0462: the pin
	/// is a file in the project and the image's toolchain was decided when the
	/// image was built, so the two can be compared at the moment the image is
	/// chosen rather than at the first request that comes back empty. 0461 is
	/// the same failure noticed afterwards, from what the server says; this one
	/// never needed the server to say anything.
	///
	/// The image is taken as *named* rather than as it will resolve. Working out
	/// that a named image cannot be run here at all means walking the PATH for a
	/// runtime, which is not a thing to do while a strip is being drawn — and it
	/// would change only which of two sentences is said about a project neither
	/// of them can read.
	private func toolchainObjection(
		for definition: LanguageServerDefinition, project: URL
	) -> ToolchainPins.Objection? {
		let path = project.standardizedFileURL.path
		let pins = toolchainPins[path] ?? {
			let read = ToolchainPins.inProject(project)
			toolchainPins[path] = read
			return read
		}()
		guard let pin = pins.first(where: { $0.tool == definition.name }) else { return nil }
		let named = images(for: project).image(for: definition.name)
		let resolved = named.flatMap {
			ToolImageRecipes.resolve(image: $0, forTool: definition.name)
		}
		return ToolchainPins.objection(
			to: pin,
			// The word a recipe is asked for by is not an image name, so it is
			// turned into the name of the image that would be built — which is
			// still an image, and still one whose toolchain was fixed when it was
			// built.
			comingFrom: resolved,
			// An executable already named for this server answers the pin, so there
			// is nothing to say. Whether that path is any good is the sentence above
			// this one in `notice`, and it says so on its own.
			command: overrides(for: project).command(forTool: definition.name),
			// And a recipe from this repository chosen instead of the tool's own is
			// this project's own answer to the channel — see `isVariantRecipe`.
			imageKnowsChannel: resolved.map {
				ToolImageRecipes.isVariantRecipe($0, forTool: definition.name)
			} ?? false
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

	/// Which server a project wants for each language, project first and
	/// settings behind it.
	///
	/// The same order as the images above, and 0424 is where it was settled:
	/// **the file wins and the setting is the default.** A project's choice of
	/// server is a statement about the project — this is the trade we want here
	/// — and a personal preference quietly overriding it would mean two people
	/// on one repository being answered by two different programs.
	func choices(for project: URL) -> LanguageServerChoices {
		let path = project.standardizedFileURL.path
		if let known = serverChoices[path] { return known }
		let resolved = LanguageServerChoices.resolve(
			project: LanguageServerChoices.inProject(project),
			settings: LanguageServerChoices.settings(Settings.shared.languageServers)
		)
		serverChoices[path] = resolved
		return resolved
	}

	/// What a project says about a server's executable and what to tell it,
	/// project first and settings behind it — the same order as everything else
	/// out of this file.
	func overrides(for project: URL) -> LanguageServerOverrides {
		let path = project.standardizedFileURL.path
		if let known = serverOverrides[path] { return known }
		let resolved = LanguageServerOverrides.resolve(
			project: LanguageServerOverrides.inProject(project),
			settings: LanguageServerOverrides.settings(Settings.shared.serverCommands)
		)
		serverOverrides[path] = resolved
		return resolved
	}

	/// What to say about a server that was chosen, exists, and is not here.
	///
	/// The ordinary install hint, and in front of it the fact that somebody
	/// chose this one — without which the sentence reads as though Abydos picked
	/// the server, and the next thought is that surely the other one is running
	/// instead. It is not, and saying so is the difference between five minutes
	/// and an afternoon.
	private func chosenButAbsent(
		_ definition: LanguageServerDefinition, languageId: String, project: URL
	) -> String {
		guard let chosen = choices(for: project).chosen(forLanguage: languageId) else {
			return definition.installHint
		}
		let others = LanguageServers.candidates(forLanguage: languageId)
			.map(\.name)
			.filter { $0 != definition.name }
		let instead = others.isEmpty
			? ""
			: " Nothing has been started in its place — not \(others.joined(separator: " and ")) "
				+ "— because \(definition.name) is what was asked for."
		return "\(chosen.source.origin) chose \(definition.name) for this project, and it is not "
			+ "installed here and no image is named for it.\(instead)\n\n\(definition.installHint)"
	}

	/// Tells a server that has just started about the files opened while its
	/// image was being fetched.
	private func replayDeferredOpens(to server: Server, key: String) {
		let waiting = deferredOpens.removeValue(forKey: key) ?? [:]
		guard !waiting.isEmpty else { return }
		for (uri, document) in waiting {
			openDocuments[uri] = 1
			documentServers[uri] = key
			didOpenCount += 1
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
		key: String
	) {
		let line = Self.oneLine(text)
		// Everything down to info, which is where a server says what it made of
		// the project — the view it created, the packages it loaded. Not level
		// 4: that is the server's own debug logging, and some of them are
		// generous with it.
		if level <= 3 { log("\(definition.command) says [\(Self.levelName(level))] \(line)") }

		// 1 is an error in the protocol's numbering. Warnings are ordinary
		// enough that a toast for each would be the thing people turn off — and
		// **measured, the level is a poorer signal than it looks**: the
		// rust-analyzer image this repository builds reports a project it could
		// not load at level 2, and reports `duplicate DidOpenTextDocument`, which
		// costs nothing, at level 1. That is why an error here is a report and
		// not a verdict; `ServerHealth` is where the difference is written down.
		guard level == 1 else { return }

		// **Not while it is preparing**, and this is the second half of 0501
		// rather than a nicety. Watched in the real app on a cold open of a
		// package with eighteen C++ targets: `sourcekit-lsp` reports the
		// subprocesses of its own index build at error level — `Finished with
		// signal 2`, `Finished with exit code 1` — and every one of them landed
		// here, so twenty seconds into a perfectly ordinary first open the strip
		// said the server *cannot read this project* and a red toast said it
		// again. That sentence is 0461's, it is about a server that will never
		// answer, and it was being said about one that answered thirty seconds
		// later.
		//
		// `ServerHealth` already says the level is a poorer signal than it looks
		// and that a message is a report rather than a verdict. This is the same
		// argument with a fact the app now has: the server has said it is not
		// ready, so what it says about failures while it gets ready is about the
		// build. Nothing is lost for good — `said` keeps the *first* diagnosis
		// and the state is still `.working`, so a server that really cannot read
		// the project says so again on the next file and is believed then.
		guard !preparing.contains(key) else { return }
		changeHealth(of: key) { $0.said(line) }

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
		/// Which language this was chosen for and where the choice was written,
		/// or nil when nobody chose and this is simply the server Abydos has.
		///
		/// The one place a project's choice can be *seen* rather than inferred:
		/// the settings page knows no project, and a row here is looked at by
		/// exactly the person wondering why the server they expected is the one
		/// they are paying for.
		let chosen: String?

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
				insideContainer: server.insideContainer,
				chosen: chosenNote(for: server.definition, project: server.project)
			)
		}
		// And the jdtls this app started for the debugger alone, which is a JVM
		// holding gigabytes that nobody chose. It has to be in this list: it is
		// the row somebody looks at when they wonder what the memory is, and the
		// Stop that ends a debugging session's leftovers.
		+ debugHosts.compactMap { key, host in
			guard host.isRunning else { return nil }
			return RunningServer(
				key: key,
				command: host.definition.command,
				project: host.project,
				pid: host.processIdentifier,
				containerName: nil,
				insideContainer: nil,
				chosen: "the Java debugger, which lives inside \(host.definition.name)"
			)
		}
		.sorted {
			($0.project.lastPathComponent, $0.command) < ($1.project.lastPathComponent, $1.command)
		}
	}

	/// "Java, chosen in .abydos/tools.json", or nil when nobody chose.
	private func chosenNote(for definition: LanguageServerDefinition, project: URL) -> String? {
		let choices = choices(for: project)
		for languageId in definition.languageIds {
			guard let chosen = choices.chosen(forLanguage: languageId),
			      chosen.name == definition.name
			else { continue }
			return "\(LanguageRegistry.shared.displayName(for: languageId)), chosen in "
				+ chosen.source.origin
		}
		return nil
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
	///
	/// - Parameter because: what put it in the log, since this is no longer only
	///   reached from the Stop button. A line saying a server was stopped by hand
	///   when nobody touched it is worse than no line: the log is what somebody
	///   reads when they are trying to work out what the app did on its own.
	@discardableResult
	func shutdown(server key: String, because reason: String = "by hand") -> Bool {
		// A debug host first, since it is under a key of its own and none of what
		// follows applies to it: it holds no documents, published nothing, and has
		// no health anybody was told about.
		if let host = debugHosts.removeValue(forKey: key) {
			host.stop()
			log("the debugger's \(host.definition.command) was stopped \(reason) for "
				+ "\(host.project.lastPathComponent)")
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
			return true
		}
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
		// What it said about this project went with it: the next server started
		// under this key is a new process and a new question.
		health.removeValue(forKey: key)
		preparing.remove(key)
		log("\(server.definition.command) was stopped \(reason) for "
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
		for key in Array(debugHosts.keys) where key.hasPrefix(prefix) {
			shutdown(server: key)
		}
		unavailable = unavailable.filter { !$0.hasPrefix(prefix) }
		lastStandardError = lastStandardError.filter { !$0.key.hasPrefix(prefix) }
		// A fetch still running is left to finish — the image is worth having on
		// the machine either way — but nothing is waiting for it any more, and
		// the project is read again next time it opens.
		fetching = fetching.filter { !$0.hasPrefix(prefix) }
		buildingHere = buildingHere.filter { !$0.hasPrefix(prefix) }
		deferredOpens = deferredOpens.filter { !$0.key.hasPrefix(prefix) }
		documentServers = documentServers.filter { !$0.value.hasPrefix(prefix) }
		missingHints = missingHints.filter { !$0.key.hasPrefix(prefix) }
		toolImages.removeValue(forKey: project.standardizedFileURL.path)
		toolchainPins.removeValue(forKey: project.standardizedFileURL.path)
		serverChoices.removeValue(forKey: project.standardizedFileURL.path)
		refused = refused.filter { !$0.hasPrefix(prefix) }
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
		health = health.filter { !$0.key.hasPrefix(prefix) }
		preparing = preparing.filter { !$0.hasPrefix(prefix) }
		announced.removeAll()
		emptied.removeAll()
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	func shutdownAll() {
		for server in servers.values {
			let client = server.client
			Task { await client.shutdown() }
		}
		// The debugger's own jdtls goes with the rest of them, and by the same
		// promise: a server ends when the app ends, by every way the app ends.
		// A JVM holding four gigabytes left behind by a quit is worse than most
		// of what this list is for.
		for host in debugHosts.values { host.stop() }
		debugHosts.removeAll()
		servers.removeAll()
		runningNames.removeAll()
		health.removeAll()
		preparing.removeAll()
		fetching.removeAll()
		buildingHere.removeAll()
		deferredOpens.removeAll()
		documentServers.removeAll()
		missingHints.removeAll()
		toolImages.removeAll()
		toolchainPins.removeAll()
		serverChoices.removeAll()
		refused.removeAll()
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

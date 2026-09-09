import AppKit
import AbydosKit

/// What a server says it can do, and what it has said about itself since it
/// started.
extension LanguageService {
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
	func ready(
		_ languageId: String, project: URL, for question: String
	) -> (key: String, server: Server)? {
		let key = key(project: project, languageId: languageId)
		guard let server = servers[key] else {
			log("no \(languageId) server for \(project.lastPathComponent): \(question) unanswered")
			return nil
		}
		return (key, server)
	}

	func note(_ error: Error, asked question: String, of server: Server, about url: URL) {
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
	func answered(withContent: Bool, for key: String) {
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
	func changeHealth(of key: String, _ change: (inout ServerHealth) -> Void) {
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
}

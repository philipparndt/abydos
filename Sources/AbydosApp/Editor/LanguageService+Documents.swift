import AppKit
import AbydosKit

/// The documents a server is holding, the questions asked about them, and the
/// edits asked of it.
///
/// A server keeps a copy of every open file and every edit has to reach it in
/// order, or its answers quietly stop matching what is on screen. That rule is
/// what this file is.
extension LanguageService {
	// MARK: - Documents


	var documentTrafficForTesting: String {
		"didOpen=\(didOpenCount) didClose=\(didCloseCount) open=\(openDocuments.count)"
	}

	/// A file was opened. Starts a server for it if this is the first of its
	/// language, and hands it the text.
	///
	/// **Nothing at all for an untrusted project.** A language server is a
	/// program, and the one that answers for a project is often the project's
	/// own — `node_modules/.bin`, a gradle wrapper, a binary in its tree. It is
	/// also handed the file's text, which is the other half of what a project
	/// that has not been trusted should not get. The editor works without one:
	/// syntax, folding and search are this app's.
	func opened(url: URL, languageId: String, text: String, project: URL) {
		guard ProjectTrust.shared.isTrusted(project) else { return }
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
}

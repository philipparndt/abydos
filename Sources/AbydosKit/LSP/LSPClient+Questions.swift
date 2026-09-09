import Foundation

/// The questions asked of a language server, and the edits asked of it.
///
/// Every one of these is the same three lines — name the method, hand it a
/// document and a position, read the answer into a type of this app's own —
/// and what is worth reading in them is the reading, which differs per
/// method. They are here rather than beside the framing and the process for
/// that reason: this file is the protocol's vocabulary, and `LSPClient` is
/// the machine that carries it.
///
/// What a server will answer at all is asked through `capability(_:)`, which
/// takes the client's lock for one entry rather than handing the whole
/// dictionary out.
extension LSPClient {
	// MARK: - Questions

	public func definition(uri: String, position: LSPPosition) async throws -> [LSPLocation] {
		let result = try await request("textDocument/definition", [
			"textDocument": ["uri": uri],
			"position": position.json,
		])
		return LSPLocation.list(from: result)
	}

	public func hover(uri: String, position: LSPPosition) async throws -> LSPHover? {
		let result = try await request("textDocument/hover", [
			"textDocument": ["uri": uri],
			"position": position.json,
		])
		return LSPHover(json: result)
	}

	public func completion(uri: String, position: LSPPosition) async throws -> [LSPCompletion] {
		let result = try await request("textDocument/completion", [
			"textDocument": ["uri": uri],
			"position": position.json,
		])
		return LSPCompletion.list(from: result)
	}

	/// The characters this server wants to be asked on, over and above a word
	/// being typed.
	///
	/// Read from the handshake rather than kept as a list in the editor, because
	/// it is a fact about the server and differs between them: sourcekit-lsp
	/// names `.` and `(`, and openscad-lsp names none at all. Without this the
	/// editor only ever asked on the second letter of a word, so a `.` — where
	/// every enum case in Swift belongs — was never a question anybody asked.
	public var completionTriggerCharacters: Set<String> {
		Self.completionTriggerCharacters(in: allCapabilities)
	}

	/// Read from a handshake's answer rather than from a running server, so what
	/// a real `initialize` result means can be held to in a test without one.
	static func completionTriggerCharacters(in capabilities: [String: Any]) -> Set<String> {
		let provider = capabilities["completionProvider"] as? [String: Any]
		return characters(provider?["triggerCharacters"])
	}

	static func characters(_ value: Any?) -> Set<String> {
		Set((value as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty })
	}

	/// Whether this server answers `textDocument/signatureHelp` at all.
	///
	/// **Asked before the request is sent, and that is not tidiness.** Driven
	/// against openscad-lsp — which advertises no `signatureHelpProvider` — the
	/// request produced no reply of any kind, not even an error, so a client
	/// that sends it anyway is left holding a continuation until its timeout
	/// fires. A capability nobody claimed is a question nobody should ask.
	public var offersSignatureHelp: Bool {
		capability("signatureHelpProvider") != nil
	}

	static func offersSignatureHelp(in capabilities: [String: Any]) -> Bool {
		capabilities["signatureHelpProvider"] != nil
	}

	/// The characters this server wants to be asked about a call on.
	///
	/// Both lists together: `triggerCharacters` opens the question — `(` and
	/// `[` for sourcekit-lsp — and `retriggerCharacters` asks it again as the
	/// arguments go in, which is `,` and `:`. From the editor's side they are
	/// one thing, "ask now", and nothing is remembered between them that would
	/// make the distinction worth keeping.
	public var signatureHelpTriggerCharacters: Set<String> {
		Self.signatureHelpTriggerCharacters(in: allCapabilities)
	}

	static func signatureHelpTriggerCharacters(in capabilities: [String: Any]) -> Set<String> {
		guard let provider = capabilities["signatureHelpProvider"] as? [String: Any] else { return [] }
		return characters(provider["triggerCharacters"])
			.union(characters(provider["retriggerCharacters"]))
	}

	/// What the server says about the call the caret is inside.
	///
	/// - Parameter timeout: how long the answer gets. The default is a
	///   keystroke's worth, because this is asked as somebody types the `(` and
	///   an answer that arrives after they have finished typing the arguments
	///   is not an answer. A *test* asks the same question for its content and
	///   should wait as long as the machine needs — `Patience.seconds` — since
	///   sourcekit-lsp answering a first request while the suite is running is
	///   the machine's business and not the claim under test.
	public func signatureHelp(
		uri: String, position: LSPPosition, timeout: TimeInterval = 10
	) async throws -> LSPSignatureHelp? {
		let result = try await request("textDocument/signatureHelp", [
			"textDocument": ["uri": uri],
			"position": position.json,
		], timeout: timeout)
		return LSPSignatureHelp(json: result)
	}

	/// Symbols anywhere in the project, matching a query.
	public func workspaceSymbols(query: String) async throws -> [LSPSymbol] {
		let result = try await request("workspace/symbol", ["query": query])
		guard let array = result as? [Any] else { return [] }
		return array.compactMap { LSPSymbol(json: $0) }
	}

	/// What is declared in one file.
	public func documentSymbols(uri: String) async throws -> [LSPSymbol] {
		let result = try await request("textDocument/documentSymbol", [
			"textDocument": ["uri": uri],
		])
		return LSPSymbol.list(from: result, uri: uri)
	}

	/// Runs a command the server offers.
	///
	/// The escape hatch in the protocol, and the only way into some of what a
	/// server can do: jdtls's debugger, its classpaths and its list of main
	/// classes are all commands rather than requests with a method of their own.
	public func executeCommand(
		_ command: String,
		arguments: [Any] = [],
		timeout: TimeInterval = 30
	) async throws -> Any? {
		try await request(
			"workspace/executeCommand",
			["command": command, "arguments": arguments],
			timeout: timeout
		)
	}

	// MARK: - Changing code

	/// Whether this server renames at all, and whether it will be asked first.
	///
	/// Read from what it said at the handshake rather than discovered by asking
	/// and being refused: an offer that fails is worse than no offer, and the
	/// only thing a server that cannot rename can answer is an error somebody
	/// has already committed to reading.
	///
	/// `renameProvider` is `true` for a server that renames and takes no options,
	/// or an object for one that has something to say about it — of which the
	/// only field anyone sends is `prepareProvider`.
	public var renames: Bool {
		let provider = capability("renameProvider")
		if let flag = provider as? Bool { return flag }
		return provider is [String: Any]
	}

	/// Whether `prepareRename` may be asked of this server.
	///
	/// A server that renames but has no prepare must not be asked: several
	/// answer `MethodNotFound`, which arrives as a refusal and reads exactly
	/// like a symbol that cannot be renamed. Where it is absent the editor works
	/// the word out itself, which is what it did before asking anything.
	public var preparesRenames: Bool {
		guard let options = capability("renameProvider") as? [String: Any] else {
			return false
		}
		return options["prepareProvider"] as? Bool ?? false
	}

	/// What would be renamed here, and nil where nothing would.
	///
	/// Three shapes on the wire, and the difference between the second and the
	/// third is the whole reason to ask: a plain range, `{ range, placeholder }`
	/// where the placeholder is the text to start the field with, and
	/// `{ defaultBehavior: true }` meaning "yes, and work the word out
	/// yourself". A server that answers `null` is saying there is nothing here
	/// to rename, which is an answer and not a failure.
	public func prepareRename(
		uri: String, position: LSPPosition
	) async throws -> LSPRenameTarget? {
		let result = try await request("textDocument/prepareRename", [
			"textDocument": ["uri": uri],
			"position": position.json,
		])
		return LSPRenameTarget(json: result)
	}

	/// The whole change renaming this symbol comes to.
	///
	/// The timeout is the request's own and generous by default: a rename is a
	/// project-wide search followed by a project-wide edit, and jdtls on a large
	/// reactor takes tens of seconds over it where a hover takes none.
	public func rename(
		uri: String, position: LSPPosition, to newName: String, timeout: TimeInterval = 60
	) async throws -> WorkspaceEdit? {
		let result = try await request("textDocument/rename", [
			"textDocument": ["uri": uri],
			"position": position.json,
			"newName": newName,
		], timeout: timeout)
		return WorkspaceEdit(json: result)
	}

	/// Whether this server offers anything about a place in a file.
	///
	/// Read from the handshake, for the reason `renames` is: a keystroke that
	/// asks a server which does not do this gets an error back, and an error is
	/// not "nothing on offer here" however much it looks like one on screen.
	public var offersCodeActions: Bool {
		let provider = capability("codeActionProvider")
		if let flag = provider as? Bool { return flag }
		return provider is [String: Any]
	}

	/// Whether this server fills an action in when asked.
	///
	/// A server that says so may send a list with no edits in it, which is the
	/// point of asking: the list is cheap and the work happens on the one that
	/// was chosen.
	public var resolvesCodeActions: Bool {
		guard let options = capability("codeActionProvider") as? [String: Any] else {
			return false
		}
		return options["resolveProvider"] as? Bool ?? false
	}

	/// The kinds this server said it answers with, and empty when it said
	/// nothing — which means "ask and find out" rather than "none".
	public var codeActionKinds: [String] {
		guard let options = capability("codeActionProvider") as? [String: Any] else {
			return []
		}
		return (options["codeActionKinds"] as? [Any])?.compactMap { $0 as? String } ?? []
	}

	/// What the server offers about a range, given what it said was wrong there.
	///
	/// **The diagnostics go with the request.** A quick fix is a fix *for* a
	/// diagnostic, and the protocol has the client send back the ones under the
	/// selection rather than have the server work out which of its own it last
	/// published for this file. A request with an empty context still returns
	/// refactorings; it is the fixes that go missing, silently.
	///
	/// `only` is how `source.*` is asked for separately: organise imports is
	/// about the file and has no caret, so it is a different gesture asking a
	/// narrower question.
	public func codeActions(
		uri: String,
		range: LSPRange,
		diagnostics: [LSPDiagnostic] = [],
		only: [String]? = nil,
		timeout: TimeInterval = 30
	) async throws -> [LSPCodeAction] {
		var context: [String: Any] = ["diagnostics": diagnostics.map(\.json)]
		if let only { context["only"] = only }
		let result = try await request("textDocument/codeAction", [
			"textDocument": ["uri": uri],
			"range": range.json,
			"context": context,
		], timeout: timeout)
		return LSPCodeAction.list(from: result)
	}

	/// Asks the server to fill in an action it sent without one.
	///
	/// The whole action goes back, exactly as it arrived — `data` and all —
	/// because that field is the server's own note to itself about which
	/// proposal this was. What comes back replaces it; a server that answers
	/// with something unreadable leaves the action as it was, and the caller
	/// then has an action that still needs resolving rather than one that
	/// silently does nothing.
	public func resolveCodeAction(
		_ action: LSPCodeAction, timeout: TimeInterval = 30
	) async throws -> LSPCodeAction {
		guard let raw = action.raw?.value else { return action }
		let result = try await request("codeAction/resolve", raw as? [String: Any] ?? [:], timeout: timeout)
		return LSPCodeAction(json: result) ?? action
	}

	public func references(uri: String, position: LSPPosition) async throws -> [LSPLocation] {
		let result = try await request("textDocument/references", [
			"textDocument": ["uri": uri],
			"position": position.json,
			"context": ["includeDeclaration": true],
		])
		return LSPLocation.list(from: result)
	}
}

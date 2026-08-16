import Foundation

/// One language server, spoken to over its standard input and output.
///
/// The wire format is the same `Content-Length` framing as the debug adapter
/// protocol, and the shape of this client follows `DAPClient` for that reason:
/// spawn, frame, match replies to requests by id, and hand notifications to a
/// callback. What differs is that LSP servers are long-lived and stateful —
/// they hold a copy of every open document, and every edit has to be told to
/// them in order, or their answers quietly stop matching the file.
public final class LSPClient: @unchecked Sendable {
	public enum ClientError: Error, LocalizedError {
		case notRunning
		case failed(code: Int, message: String)
		case timedOut(String)

		public var errorDescription: String? {
			switch self {
			case .notRunning:
				return "The language server is not running."
			case let .failed(code, message):
				return "The language server refused: \(message) (\(code))."
			case let .timedOut(request):
				return "The language server did not answer \(request)."
			}
		}
	}

	/// Diagnostics arrived for a document.
	public var onDiagnostics: ((_ uri: String, _ diagnostics: [LSPDiagnostic]) -> Void)?
	/// The server said something to the user — a progress note, a warning.
	public var onMessage: ((_ level: Int, _ text: String) -> Void)?
	/// How far the server has got, in its own words.
	///
	/// `language/status` is jdtls's own notification rather than part of the
	/// protocol, which is why nothing read it until something had to *wait* on the
	/// import: it is the only place the server says which minute of a Tycho
	/// reactor it is in, and 0452's Debug is a wait that has to say what it is
	/// waiting for. Every other server sends none, so every other server ignores
	/// this.
	public var onStatus: ((_ text: String) -> Void)?
	/// What the server wrote to its standard error.
	///
	/// Not protocol traffic and not shown to anybody, but it is where a server
	/// says why it is about to be useless — a toolchain it cannot run, a
	/// configuration it will not accept. It used to be read and dropped on the
	/// floor, which is the same as not reading it except that it looked
	/// deliberate.
	public var onStandardError: ((String) -> Void)?
	public var onExit: (() -> Void)?
	/// The server began, or finished, the first stretch of work it reported.
	///
	/// Called once with `true` and once with `false` per server, and not at all
	/// for a server that reports no progress. `WorkDoneProgress` is the rule and
	/// says why the *first* stretch is the only one that counts; what it is for
	/// is 0501 — a Swift package whose dependencies are not built publishes
	/// `No such module` for the minute the server spends building them, and this
	/// is the only thing on the wire that knows the minute is not over.
	public var onPreparing: ((Bool) -> Void)?

	public var callbackQueue: DispatchQueue = .main

	private var process: Process?
	private var inputPipe: Pipe?
	/// The two the server writes to. Held so their readability handlers can be
	/// taken off when it stops: a handler left on a closed descriptor is called
	/// straight back, and a language server that has exited then costs a core
	/// for the rest of the session.
	private var outputPipe: Pipe?
	private var errorPipe: Pipe?

	private let lock = NSLock()
	private var buffer = Data()
	private var nextID = 1
	private var pending: [Int: (Result<Any?, Error>) -> Void] = [:]

	/// What the server has said it is busy with. Behind the lock like everything
	/// else the reader thread touches.
	private var progress = WorkDoneProgress()

	/// Whether the server is still getting ready to answer.
	public var isPreparing: Bool { locked { progress.isPreparing } }

	/// How long the work has to have stopped before preparation is called over.
	///
	/// An order of magnitude clear of the gaps a server leaves *inside* its own
	/// startup — the longest measured was `rust-analyzer`'s 0.1 seconds between
	/// closing `Fetching` and opening `Building CrateGraph` — and far shorter
	/// than the pause before somebody saves a file, which starts the work that
	/// must not count.
	static let preparationGrace: TimeInterval = 1

	/// How many times a reader callback has run.
	///
	/// Kept for one test, and worth the two lines: the failure it guards
	/// against — a handler left on a closed descriptor, called back for ever —
	/// shows up as CPU rather than as a wrong answer, and CPU is the one thing
	/// a test running beside a thousand others cannot measure. A count that
	/// stops growing when the server does is the same fact, stated locally.
	private(set) var readerWakeups = 0

	private func noteReaderWakeup() {
		lock.lock()
		readerWakeups += 1
		lock.unlock()
	}

	/// What the server said it can do, from the initialize reply.
	public private(set) var capabilities: [String: Any] = [:]

	/// The two names for the project, when the server is in a container.
	///
	/// Nil for a server on this machine, where there is only one name for
	/// everything and no translation to do. Set before `start`: everything sent
	/// after that is rewritten to the container's side and everything arriving
	/// is brought home, so nothing above this class ever sees a path that does
	/// not exist here.
	public var containerPaths: ContainerPaths? {
		get { locked { paths } }
		set { locked { paths = newValue } }
	}

	private var paths: ContainerPaths?

	/// The container this server runs in, when it runs in one: its name and the
	/// runtime that can remove it.
	///
	/// Set before `start`, alongside `containerPaths`. It is what makes stopping
	/// this client actually stop the server: terminating the `run` process ends
	/// the process and leaves the container going, so the container is removed
	/// by name as well.
	public var containerLaunch: (name: String, runtime: ContainerRuntime)? {
		get { locked { launch } }
		set { locked { launch = newValue } }
	}

	private var launch: (name: String, runtime: ContainerRuntime)?

	/// Whether the handshake has finished.
	private var isInitialized = false
	/// Notifications sent before it did.
	///
	/// A server rejects everything that arrives before `initialize` — quietly,
	/// so what actually happens is that the document is never registered and
	/// every later question about it comes back "no language service for this
	/// file". Holding them until the handshake lands costs a few milliseconds
	/// once and removes the whole class of race.
	private var queuedNotifications: [(String, [String: Any]?)] = []

	public init() {}

	/// Runs `body` holding the lock.
	///
	/// Synchronous on purpose, and every caller keeps it that way: taking a
	/// lock in an async function and holding it across a suspension point is
	/// how a client like this deadlocks, and Swift 6 makes it an error rather
	/// than a warning. Wrapping it means the critical sections stay short
	/// enough to see, which is the actual guarantee wanted here.
	private func locked<T>(_ body: () -> T) -> T {
		lock.lock()
		defer { lock.unlock() }
		return body()
	}

	public var isRunning: Bool {
		lock.lock()
		defer { lock.unlock() }
		return process?.isRunning ?? false
	}

	/// The server's process id, for a test that has to ask the operating system
	/// rather than this object whether the server really went — and for the list
	/// of what is running, which asks `ps` what this process and everything under
	/// it costs.
	///
	/// Kept for the same reason `readerWakeups` is: what closing a project has to
	/// achieve is a process that is gone, and this object's own opinion of that
	/// is exactly the thing under test.
	public var processIdentifier: pid_t? {
		lock.lock()
		defer { lock.unlock() }
		return process?.processIdentifier
	}

	// MARK: - Lifetime

	public func start(
		executable: String,
		arguments: [String] = [],
		workingDirectory: URL?,
		environment: [String: String]? = nil
	) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		process.currentDirectoryURL = workingDirectory
		if let environment { process.environment = environment }

		let input = Pipe()
		let output = Pipe()
		process.standardInput = input
		process.standardOutput = output
		// A server's own logging is not protocol traffic. Drained rather than
		// inherited: a full pipe would block the server mid-answer. Drained into
		// the log rather than into nothing, because it is the only place some
		// servers explain themselves.
		let errors = Pipe()
		process.standardError = errors
		errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			self?.noteReaderWakeup()
			// Empty means the server closed its end. Nothing removes a
			// readability handler when that happens, and one left on a closed
			// descriptor is called straight back — a core spinning on empty
			// reads for every server that ever exited, which is what a
			// long-lived editor accumulates.
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			guard let self else { return }
			guard let text = String(data: data, encoding: .utf8) else { return }
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { return }
			self.callbackQueue.async { self.onStandardError?(trimmed) }
		}

		output.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			self?.noteReaderWakeup()
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
			self?.consume(data)
		}

		process.terminationHandler = { [weak self] exited in
			ToolProcesses.shared.forget(exited)
			// And the container behind it, which the process ending says nothing
			// about: a `run` that has exited leaves a container that has not.
			if let name = self?.containerLaunch?.name {
				ToolContainers.shared.releaseInBackground(name)
			}
			guard let self else { return }
			self.failAllPending(with: ClientError.notRunning)
			self.callbackQueue.async { self.onExit?() }
		}

		// A language server is the longest-lived child this app has, and one
		// started from an image is a container. Both are registered so that the
		// app going takes them too, however the app goes — the process because
		// it has to be signalled, the container because signalling the process
		// does not touch it.
		ToolProcesses.shared.track(process)
		if let container = containerLaunch {
			ToolContainers.shared.register(container.name, runtime: container.runtime)
		}
		do {
			try process.run()
		} catch {
			// Handed back, because a process that never started is one nothing
			// will ever hand back on its behalf: `terminationHandler` does not
			// run for a process that did not run. `ToolProcesses` no longer
			// sweeps an entry out merely for not being running — it cannot, or
			// it would sweep this one out in the instant between the line above
			// and this one — so the entry would otherwise stay for the life of
			// the app, counting against nothing but never leaving.
			ToolProcesses.shared.forget(process)
			if let container = containerLaunch {
				ToolContainers.shared.releaseInBackground(container.name)
			}
			throw error
		}

		lock.lock()
		self.process = process
		self.inputPipe = input
		self.outputPipe = output
		self.errorPipe = errors
		lock.unlock()
	}

	/// The handshake, after which the server will answer questions.
	///
	/// `options` is the server-specific half of it: jdtls is told there which
	/// JDKs exist and which bundles to load, and there is no second chance to
	/// say it. The timeout is longer than a request's default because a server
	/// that has to read a build file before answering — which every Java server
	/// does — takes seconds rather than milliseconds on a large project.
	@discardableResult
	public func initialize(
		rootURL: URL,
		options: [String: Any]? = nil,
		timeout: TimeInterval = 10
	) async throws -> [String: Any] {
		// The editor's process id, so a server outliving it can stop. Not sent
		// from a container: that number means nothing in another process
		// namespace, and a server that watches it there finds no such process
		// and exits during the handshake — which looks exactly like an image
		// that does not work.
		let watched: Any = containerPaths == nil
			? Int(ProcessInfo.processInfo.processIdentifier)
			: NSNull()
		var parameters: [String: Any] = [
			"processId": watched,
			"rootUri": rootURL.absoluteString,
			"workspaceFolders": [["uri": rootURL.absoluteString, "name": rootURL.lastPathComponent]],
			"capabilities": Self.clientCapabilities,
		]
		if let options { parameters["initializationOptions"] = options }
		let result = try await request("initialize", parameters, timeout: timeout)

		let capabilities = (result as? [String: Any])?["capabilities"] as? [String: Any] ?? [:]
		locked { self.capabilities = capabilities }

		// `initialized` goes first, then whatever was waiting behind it, in the
		// order it was asked for — a `didChange` before its `didOpen` is as
		// broken as no `didOpen` at all.
		write(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
		let queued = locked { () -> [(String, [String: Any]?)] in
			isInitialized = true
			let pending = queuedNotifications
			queuedNotifications = []
			return pending
		}
		for (method, parameters) in queued { send(notification: method, parameters) }
		return capabilities
	}

	/// What this editor claims to support.
	///
	/// Deliberately modest: claiming a capability the editor does not implement
	/// makes servers send things nobody reads, and some of them are expensive
	/// to produce.
	static let clientCapabilities: [String: Any] = [
		// **The one place the editor can find out that a server is not ready
		// yet**, and measured before it was claimed: driven against a Swift
		// package whose dependencies were not built, `sourcekit-lsp` sends no
		// `$/progress` at all to a client that does not ask for it — the whole of
		// what it says about a minute of building is `Preparing <target>` in the
		// log, which never says a target finished. Asked for, it opens a token
		// 13.8 seconds before the false `No such module` appears and closes it
		// 0.1 seconds after it clears. 0501.
		//
		// The cost is about five hundred notifications over that minute, each a
		// dictionary lookup on the reader thread, and `WorkDoneProgress` answers
		// two of them rather than five hundred — so nothing above this is woken
		// for a percentage nobody draws.
		"window": ["workDoneProgress": true],
		"textDocument": [
			"synchronization": ["didSave": true, "dynamicRegistration": false],
			"publishDiagnostics": ["relatedInformation": false],
			"hover": ["contentFormat": ["plaintext", "markdown"]],
			"definition": ["linkSupport": true],
			"documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
			"completion": [
				"completionItem": ["snippetSupport": false, "documentationFormat": ["plaintext"]],
			],
			// `prepareSupport`, because asking first is how the offer to rename is
			// only made where there is something to rename. Without it a server
			// answers `prepareRename` with an error rather than a range, and the
			// editor cannot tell "not renameable here" from "this server is
			// broken".
			"rename": ["prepareSupport": true, "dynamicRegistration": false],
		],
		"workspace": [
			"workspaceFolders": true,
			"symbol": ["dynamicRegistration": false],
			// **This is what decides the shape a rename comes back in.** Servers
			// send the old `changes` map to clients that claim nothing here, and
			// that map carries text only — so a Java rename that has to move
			// `Foo.java` to `Bar.java` would arrive with the move silently
			// missing, leaving a file whose name no longer matches the class in
			// it. Claiming `documentChanges` and the three resource operations is
			// what makes the server say the whole of what it means.
			//
			// `failureHandling: "abort"` is not decoration either: it is this
			// client telling the server that a refused edit leaves the project
			// untouched, which is exactly what `WorkspaceEditPlan` guarantees.
			"workspaceEdit": [
				"documentChanges": true,
				"resourceOperations": ["create", "rename", "delete"],
				"failureHandling": "abort",
				"normalizesLineEndings": false,
			],
		],
	]

	/// Asks the server to stop, and makes sure it does.
	public func shutdown() async {
		guard isRunning else { return }
		// A server that will not shut down politely is still a process holding
		// a few hundred megabytes, so the ask is given a deadline — the request's
		// own, which is the only one that ends the waiting.
		_ = try? await request("shutdown", nil, timeout: 2)
		notify("exit", nil)

		try? await Task.sleep(nanoseconds: 200_000_000)
		let process = locked { self.process }
		if process?.isRunning == true { process?.terminate() }
	}

	public func stop() {
		lock.lock()
		let process = self.process
		let output = self.outputPipe
		let errors = self.errorPipe
		self.process = nil
		self.inputPipe = nil
		self.outputPipe = nil
		self.errorPipe = nil
		isInitialized = false
		queuedNotifications = []
		// A server killed while it was still preparing would otherwise leave the
		// word up over a process that is gone.
		let wasPreparing = progress.stopped()
		lock.unlock()

		if wasPreparing { callbackQueue.async { self.onPreparing?(false) } }

		// Before the process is asked to go: once it has, these fire on a
		// closed descriptor and are called back immediately, for ever.
		output?.fileHandleForReading.readabilityHandler = nil
		errors?.fileHandleForReading.readabilityHandler = nil

		process?.terminationHandler = nil
		if process?.isRunning == true { process?.terminate() }
		// The termination handler was just taken off, so this is the only thing
		// that will remove the container. Not waited for: closing a project
		// should not pause on a runtime.
		if let name = containerLaunch?.name { ToolContainers.shared.releaseInBackground(name) }
		failAllPending(with: ClientError.notRunning)
	}

	// MARK: - Documents

	public func didOpen(uri: String, languageId: String, version: Int, text: String) {
		notify("textDocument/didOpen", [
			"textDocument": [
				"uri": uri,
				"languageId": languageId,
				"version": version,
				"text": text,
			],
		])
	}

	/// Full-text synchronisation.
	///
	/// Incremental sync would send less, but it has to be exactly right or the
	/// server's copy silently drifts from the file and every answer after that
	/// is wrong about a place that no longer exists. Whole documents are cheap
	/// enough at the sizes anyone edits by hand.
	public func didChange(uri: String, version: Int, text: String) {
		notify("textDocument/didChange", [
			"textDocument": ["uri": uri, "version": version],
			"contentChanges": [["text": text]],
		])
	}

	public func didSave(uri: String, text: String? = nil) {
		var parameters: [String: Any] = ["textDocument": ["uri": uri]]
		if let text { parameters["text"] = text }
		notify("textDocument/didSave", parameters)
	}

	public func didClose(uri: String) {
		notify("textDocument/didClose", ["textDocument": ["uri": uri]])
	}

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
		let provider = locked { capabilities["renameProvider"] }
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
		guard let options = locked({ capabilities["renameProvider"] }) as? [String: Any] else {
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

	public func references(uri: String, position: LSPPosition) async throws -> [LSPLocation] {
		let result = try await request("textDocument/references", [
			"textDocument": ["uri": uri],
			"position": position.json,
			"context": ["includeDeclaration": true],
		])
		return LSPLocation.list(from: result)
	}

	// MARK: - Sending

	public func notify(_ method: String, _ parameters: [String: Any]?) {
		let ready = locked { () -> Bool in
			guard isInitialized else {
				queuedNotifications.append((method, parameters))
				return false
			}
			return true
		}
		guard ready else { return }
		send(notification: method, parameters)
	}

	private func send(notification method: String, _ parameters: [String: Any]?) {
		var message: [String: Any] = ["jsonrpc": "2.0", "method": method]
		if let parameters { message["params"] = parameters }
		write(message)
	}

	@discardableResult
	public func request(
		_ method: String,
		_ parameters: [String: Any]?,
		timeout: TimeInterval = 10
	) async throws -> Any? {
		guard isRunning else { throw ClientError.notRunning }

		let id = locked { () -> Int in
			let id = nextID
			nextID += 1
			return id
		}

		// The deadline belongs to the reply rather than to whoever is waiting for
		// it. It used to be a task group racing a sleep, and a group does not
		// return until every task in it has — including the one parked on a
		// continuation the server was never going to resume. So the timeout fired,
		// the group went on waiting, and `shutdown` sat there until the server
		// happened to exit on its own: measured at two minutes against a server
		// that answers nothing, which is exactly the server this has to end.
		//
		// Failing the pending handler is what resumes it, and the handler is
		// removed under the lock, so a reply that lands in the same instant as the
		// deadline delivers one answer and not two.
		return try await withCheckedThrowingContinuation { continuation in
			let expiry = DispatchWorkItem { [weak self] in
				self?.fail(id, with: ClientError.timedOut(method))
			}
			self.lock.lock()
			self.pending[id] = { result in
				expiry.cancel()
				continuation.resume(with: result)
			}
			self.lock.unlock()
			Self.deadlines.asyncAfter(deadline: .now() + timeout, execute: expiry)

			var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
			if let parameters { message["params"] = parameters }
			self.write(message)
		}
	}

	/// Where the deadlines are kept. Its own queue, so a server that has gone
	/// quiet cannot hold up anything else waiting to run.
	private static let deadlines = DispatchQueue(label: "de.rnd7.abydos.lsp.deadlines")

	/// Gives up on one request, leaving every other one alone.
	private func fail(_ id: Int, with error: Error) {
		lock.lock()
		let handler = pending.removeValue(forKey: id)
		lock.unlock()
		handler?(.failure(error))
	}

	/// Everything on its way to the server, one message at a time.
	///
	/// **A pipe write blocks when the reader is not draining it**, and this is
	/// the standard input of somebody else's process. A language server busy
	/// re-indexing, or stopped, or wedged, simply stops reading; the kernel
	/// buffer fills — 64 KB, which one `didChange` of a large file exceeds by
	/// itself — and `write` parks the calling thread until it drains. The caller
	/// was the main thread: `didChange` is sent 0.4 s after a keypress, and
	/// `didSave` after every auto-save. So the app's whole event loop, including
	/// the terminal, waited on how a language server felt about being talked to.
	///
	/// That is a correctness argument rather than a performance one, and it is
	/// why this needs no benchmark: there is no bound on the wait. Off here, the
	/// worst a stuck server can do is make its own queue grow.
	///
	/// Serial, and one per client. Serial because a language server's document
	/// notifications are only meaningful in order — a `didChange` ahead of its
	/// `didOpen` is as broken as no `didOpen` at all — and per client because
	/// one wedged server must not hold up the rest.
	private let outbox = DispatchQueue(label: "de.rnd7.abydos.lsp.outbox")

	/// Queues a message. Framing and JSON both happen on the outbox, so a whole
	/// file's worth of `JSONSerialization` is not on the caller's thread either.
	private func write(_ message: [String: Any]) {
		outbox.async { [weak self] in self?.writeNow(message) }
	}

	/// Sends a message the way a notification is sent, for the one test that
	/// cannot be written any other way.
	///
	/// What is under test is that the *synchronous* path — the one the editor
	/// takes from the main thread on every `didChange` — hands the message over
	/// rather than parking on the pipe, and reaching it through `notify` would
	/// mean a handshake with a real server first.
	func sendForTesting(_ message: [String: Any]) { write(message) }

	private func writeNow(_ message: [String: Any]) {
		// Everything, on the way out: a request, a notification, and a reply to
		// something the server asked. A container server knows the project by
		// one name only, and it is not this one.
		let outgoing = containerPaths.map { $0.containerSide(of: message) } ?? message
		guard let payload = try? JSONSerialization.data(withJSONObject: outgoing) else { return }
		var framed = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
		framed.append(payload)

		lock.lock()
		let pipe = inputPipe
		lock.unlock()
		// A server that has died mid-write takes the pipe with it; the write
		// raises rather than returning an error, so it is caught here. Also the
		// case where `stop` ran while this message was waiting its turn, which
		// is a client that is going and not a failure worth reporting.
		guard let pipe else { return }
		do {
			try pipe.fileHandleForWriting.write(contentsOf: framed)
		} catch {
			failAllPending(with: ClientError.notRunning)
		}
	}

	private func failAllPending(with error: Error) {
		lock.lock()
		let handlers = pending
		pending.removeAll()
		lock.unlock()
		for handler in handlers.values { handler(.failure(error)) }
	}

	// MARK: - Reading

	/// Accumulates bytes and dispatches every complete message in the buffer.
	func consume(_ data: Data) {
		lock.lock()
		buffer.append(data)
		var messages: [[String: Any]] = []

		while true {
			guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { break }
			let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
			guard let headerText = String(data: headerData, encoding: .utf8) else {
				buffer.removeAll()
				break
			}

			var contentLength = 0
			for line in headerText.components(separatedBy: "\r\n") {
				let parts = line.split(separator: ":", maxSplits: 1)
				guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
				contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
			}

			let bodyStart = headerEnd.upperBound
			// Wait for the whole body before dispatching.
			guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else { break }

			let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
			let body = Data(buffer[bodyStart..<bodyEnd])
			buffer.removeSubrange(buffer.startIndex..<bodyEnd)

			if let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
				messages.append(message)
			}
		}
		lock.unlock()

		// Home again before anything looks at it, so a diagnostic, a location or
		// an edit names a file that exists on this machine. Read after the
		// unlock: the accessor takes the same lock.
		let paths = containerPaths
		for message in messages {
			dispatch(paths.map { $0.hostSide(of: message) } ?? message)
		}
	}

	private func dispatch(_ message: [String: Any]) {
		// A reply carries an id and no method; a request from the server carries
		// both; a notification carries only a method.
		if let id = message["id"] as? Int, message["method"] == nil {
			lock.lock()
			let handler = pending.removeValue(forKey: id)
			lock.unlock()

			if let error = message["error"] as? [String: Any] {
				handler?(.failure(ClientError.failed(
					code: error["code"] as? Int ?? 0,
					message: error["message"] as? String ?? "unknown"
				)))
			} else {
				handler?(.success(message["result"]))
			}
			return
		}

		guard let method = message["method"] as? String else { return }
		let parameters = message["params"] as? [String: Any] ?? [:]

		switch method {
		case "textDocument/publishDiagnostics":
			guard let uri = parameters["uri"] as? String else { return }
			let diagnostics = (parameters["diagnostics"] as? [Any] ?? [])
				.compactMap { LSPDiagnostic(json: $0) }
			callbackQueue.async { self.onDiagnostics?(uri, diagnostics) }

		case "window/showMessage", "window/logMessage":
			guard let text = parameters["message"] as? String else { return }
			let level = parameters["type"] as? Int ?? 3
			callbackQueue.async { self.onMessage?(level, text) }

		case "language/status":
			// jdtls's own, and its `type` is a word rather than a level:
			// `Starting`, `Started`, `ProjectStatus`, `ServiceReady`. The two
			// together are the sentence — "Starting 42% Importing Maven
			// project(s)" — because the message alone is often only a percentage.
			let type = parameters["type"] as? String
			let text = parameters["message"] as? String
			let said = [type, text].compactMap { $0 }
				.filter { !$0.isEmpty }
				.joined(separator: " ")
			guard !said.isEmpty else { return }
			callbackQueue.async { self.onStatus?(said) }

		case "$/progress":
			// Where a server says it is not ready yet. The token is a string or a
			// number in the protocol and both are flattened to a string here:
			// what is done with it is set membership, and a server that numbers
			// its tokens is saying the same thing as one that names them.
			//
			// `create` is not handled and does not need to be — it is a request,
			// the `default` below replies null to it, and null is consent. What
			// matters is the begin and the end, which arrive here.
			guard let value = parameters["value"] as? [String: Any],
			      let kind = value["kind"] as? String
			else { return }
			let token = (parameters["token"] as? String)
				?? (parameters["token"] as? NSNumber).map { "\($0)" }
			guard let token else { return }
			lock.lock()
			let change = progress.received(kind: kind, token: token)
			lock.unlock()
			// Only on the ones that change the answer. The measured cold start
			// sent about five hundred of these, and hopping to the main queue for
			// each would be five hundred redraws of a bar the caret is in.
			switch change {
			case .nothing:
				break
			case .startedPreparing:
				callbackQueue.async { self.onPreparing?(true) }
			case .mayHaveFinished:
				// **Asked again rather than believed**, and `WorkDoneProgress` has
				// the measurement: `rust-analyzer` closes each step before opening
				// the next, so its set of open tokens emptied eight times during a
				// startup that ran to 8.7 seconds. Taking the first of those as
				// the end put the word up for one eighth of the wait.
				callbackQueue.asyncAfter(deadline: .now() + Self.preparationGrace) {
					[weak self] in
					guard let self else { return }
					self.lock.lock()
					let finished = self.progress.settleIfStillIdle()
					self.lock.unlock()
					if finished { self.onPreparing?(false) }
				}
			}

		case "workspace/configuration":
			// One answer per section asked about, and the answer is "nothing
			// configured" — everything this editor has to say was said in the
			// initialize request. A reply of the wrong shape is worse than a
			// plain null: a server that expects an array and gets one value
			// stops asking, and stops working.
			guard let id = message["id"] else { return }
			let items = (parameters["items"] as? [Any])?.count ?? 0
			write(["jsonrpc": "2.0", "id": id, "result": Array(repeating: NSNull(), count: items)])

		default:
			// A request from the server that is not answered here still needs a
			// reply, or a server that waits for one stops working.
			if let id = message["id"] {
				write(["jsonrpc": "2.0", "id": id, "result": NSNull()])
			}
		}
	}
}

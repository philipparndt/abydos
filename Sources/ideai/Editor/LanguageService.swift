import AppKit
import IdeaiKit

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

	private init() {}

	private func key(project: URL, languageId: String) -> String {
		"\(project.standardizedFileURL.path)#\(languageId)"
	}

	// MARK: - Documents

	/// A file was opened. Starts a server for it if this is the first of its
	/// language, and hands it the text.
	func opened(url: URL, languageId: String, text: String, project: URL) {
		guard let server = server(for: languageId, project: project) else { return }
		let uri = url.absoluteString
		openDocuments[uri] = 1
		server.client.didOpen(uri: uri, languageId: languageId, version: 1, text: text)
	}

	func changed(url: URL, languageId: String, text: String, project: URL) {
		guard let server = servers[key(project: project, languageId: languageId)] else { return }
		let uri = url.absoluteString
		let version = (openDocuments[uri] ?? 0) + 1
		openDocuments[uri] = version
		server.client.didChange(uri: uri, version: version, text: text)
	}

	func saved(url: URL, languageId: String, text: String, project: URL) {
		guard let server = servers[key(project: project, languageId: languageId)] else { return }
		server.client.didSave(uri: url.absoluteString, text: text)
	}

	func closed(url: URL, languageId: String, project: URL) {
		guard let server = servers[key(project: project, languageId: languageId)] else { return }
		let uri = url.absoluteString
		openDocuments.removeValue(forKey: uri)
		server.client.didClose(uri: uri)

		// A closed file's problems are no longer on screen and no longer
		// anybody's business.
		diagnostics.removeValue(forKey: uri)
		NotificationCenter.default.post(name: .ideaiDiagnosticsChanged, object: url)
	}

	// MARK: - Questions

	func definition(url: URL, position: LSPPosition, languageId: String, project: URL) async -> [LSPLocation] {
		guard let server = servers[key(project: project, languageId: languageId)] else { return [] }
		return (try? await server.client.definition(uri: url.absoluteString, position: position)) ?? []
	}

	func hover(url: URL, position: LSPPosition, languageId: String, project: URL) async -> LSPHover? {
		guard let server = servers[key(project: project, languageId: languageId)] else { return nil }
		return try? await server.client.hover(uri: url.absoluteString, position: position)
	}

	func diagnostics(for url: URL) -> [LSPDiagnostic] {
		diagnostics[url.absoluteString] ?? []
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
				NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
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
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}

		do {
			try client.start(
				executable: resolved.executable,
				arguments: resolved.definition.arguments,
				workingDirectory: project
			)
		} catch {
			unavailable.insert(key)
			return nil
		}

		let server = Server(client: client, definition: resolved.definition)
		servers[key] = server

		Task { @MainActor in
			// The handshake has to finish before anything else is sent, but
			// nothing waits on it: notifications queue up on the pipe in order,
			// and the first answers simply arrive a moment later.
			_ = try? await client.initialize(rootURL: project)
			runningNames.append(resolved.definition.command)
			missingHints.removeValue(forKey: languageId)
			NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
		}
		return server
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
		self.diagnostics[url.absoluteString] = diagnostics
		NotificationCenter.default.post(name: .ideaiDiagnosticsChanged, object: url)
	}
}

import AppKit
import AbydosKit

/// What is running now, and stopping one by hand.
extension LanguageService {
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

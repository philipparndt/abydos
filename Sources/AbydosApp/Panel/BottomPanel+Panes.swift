import AppKit
import AbydosKit

/// The panel's other tabs: search, usages, the backlog and debugging.
///
/// Each is a pane the panel shows rather than owns, and what is here is the
/// showing — which tab it goes in, what its heading says, and what happens to
/// it when the project changes underneath.
extension BottomPanel {
	// MARK: - Search

	/// Shows project search, reusing the existing pane if there is one.
	/// Shows what a program in a cluster is printing.
	///
	/// In a terminal pane with nothing behind it, so the output is coloured
	/// the way the program coloured it — a service's logs are the same logs
	/// wherever the service happens to be running.
	/// A running account of what a launch is doing.
	///
	/// Its own pane, appended to rather than replaced: the interesting part of
	/// a launch that hangs is the order things happened in, and a status line
	/// in the titlebar holds one sentence at a time.
	func appendLaunchLog(_ line: String, reset: Bool = false) {
		let title = "☸ launch"
		let pane: TerminalPane
		if let index = sessions.firstIndex(where: { $0.title == title }),
		   case let .terminal(existing) = sessions[index].kind {
			pane = existing
			// Brought forward when a launch begins, and not again: a log that
			// pulls itself in front on every line is a log that cannot be
			// looked away from.
			if reset { activate(sessions[index], focus: false) }
		} else {
			pane = TerminalPane(readOnly: ())
			let session = Session(title: title, kind: .terminal(pane))
			session.column = focusedColumn
			sessions.append(session)
			activate(session, focus: false)
		}

		if reset { pane.terminalView.clear() }
		pane.terminalView.append(
			line.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
		)
	}

	func showDevPodOutput(_ text: String, from pod: String) {
		let title = "☸ \(pod.split(separator: "/").last.map(String.init) ?? pod)"
		let pane: TerminalPane
		if let index = sessions.firstIndex(where: { $0.title == title }),
		   case let .terminal(existing) = sessions[index].kind {
			// Not activated: this arrives once a second while a program runs in
			// a cluster, and a tab that pulls itself to the front every second
			// is a tab nothing else can be looked at beside.
			pane = existing
		} else {
			pane = TerminalPane(readOnly: ())
			let session = Session(title: title, kind: .terminal(pane))
			sessions.append(session)
			activate(session, focus: false)
		}

		// Replaced rather than appended: the supervisor hands back a tail, and
		// appending it would repeat every line each time it is asked.
		pane.terminalView.clear()
		pane.terminalView.append(
			text.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\n", with: "\r\n")
		)
	}

	/// Opens the profiler, reusing the one that is already there.
	///
	/// One at a time: a second would be a second connection to the same
	/// program, and the question "which of these is the live one" is not worth
	/// asking.
	@discardableResult
	func showProfiler(address: String, connecting: Bool = false) -> ProfilerPane? {
		if let index = sessions.firstIndex(where: {
			if case .profiler = $0.kind { return true }; return false
		}), case let .profiler(pane) = sessions[index].kind {
			activate(sessions[index], focus: true)
			// The one that is already open is pointed at the new address: a
			// profiler showing the last run's port is worse than none.
			if connecting { pane.connect(to: address) }
			return pane
		}

		let pane = ProfilerPane(defaultAddress: address)
		pane.onOpenFunction = { [weak self] name in
			self?.onOpenSymbol?(name)
		}
		let session = Session(title: "Profiler", kind: .profiler(pane))
		sessions.append(session)
		activate(session, focus: true)
		if connecting { pane.connect(to: address) }
		return pane
	}



	/// Makes the search pane if this window has not had one, without showing it
	/// anywhere. Where it goes is the window's business — it has a placement to
	/// honour and this does not know it.
	func makeSearchPaneIfNeeded() -> SearchPane? {
		if let existingSearchPane { return existingSearchPane }
		guard let root = workingDirectory else { return nil }
		let pane = SearchPane(projectRoot: root)
		pane.onOpenResult = { [weak self] url, _, match, intent in
			self?.onOpenResult?(url, match, intent)
		}
		existingSearchPane = pane
		return pane
	}

	@discardableResult
	func showSearch(query: String? = nil) -> SearchPane? {
		guard let pane = makeSearchPaneIfNeeded() else { return nil }
		dockSearch(pane, beside: false, focusList: false)
		if let query { pane.setQuery(query) }
		pane.focusField()
		return pane
	}

	/// Puts the search pane in the panel: a tab in the strip, or a column of its
	/// own beside whatever terminal is showing.
	func dockSearch(_ pane: SearchPane, beside: Bool, focusList: Bool) {
		let session = sessions.first {
			if case let .search(existing) = $0.kind { return existing === pane }
			return false
		} ?? {
			let made = Session(title: "Search", kind: .search(pane))
			sessions.append(made)
			return made
		}()
		place(session, beside: beside, focusList: focusList)
	}

	/// Takes the search tab away without touching the pane, for a list that is
	/// moving to another home rather than being finished with.
	func releaseSearch() {
		guard let session = sessions.first(where: {
			if case .search = $0.kind { return true }; return false
		}) else { return }
		close(session, keepingPane: true)
	}

	/// Where a results list sits inside the panel: a tab in the strip, or a
	/// column of its own with a terminal in the other.
	///
	/// The two are genuinely different homes and it took looking at the running
	/// app to see it. A tab is *instead of* a terminal — click the terminal and
	/// the list is gone. A column is *beside* one, both on screen, which is what
	/// "in the terminal area" turns out to mean once the tab is already there.
	private func place(_ session: Session, beside: Bool, focusList: Bool) {
		if beside {
			// `focusList` reaches here too, and until item 520 it did not. ⇧⌘F
			// asks for the pane *without* the keyboard because it is about to put
			// it in the query field itself — and this branch threw that away and
			// handed the rows the keyboard one turn later. So every ⇧⌘F at a
			// list living beside the terminals landed in the results of the last
			// search: the caret was in the field, and what was typed went to the
			// table.
			putBeside(session, on: .right, focus: focusList)
			return
		}
		// Back into the one strip. Nothing has to unsplit this by hand: a column
		// exists only while a session says it is in it, so the list leaving
		// column one is the split going away, unless something else is out there.
		session.column = 0
		activate(session, focus: focusList)
		refreshTabs()
	}

	// MARK: - Usages


	/// The usages pane if there is one, without making one or moving the
	/// keyboard.
	var existingUsagesPane: UsagesPane? {
		for session in sessions {
			if case let .usages(pane) = session.kind { return pane }
		}
		return nil
	}

	/// Puts a usages pane in the panel and gives it the keyboard.
	///
	/// The pane is made outside and handed in, because the same view moves
	/// between here and a window of its own and there is only ever one of it. A
	/// second tab showing the same list is the "three ways to show one list" this
	/// item exists to avoid.
	func dockUsages(_ pane: UsagesPane, title: String, beside: Bool, focusList: Bool = true) {
		let session = sessions.first {
			if case let .usages(existing) = $0.kind { return existing === pane }
			return false
		} ?? {
			let made = Session(title: "Usages", kind: .usages(pane))
			sessions.append(made)
			return made
		}()
		session.displayTitle = title
		place(session, beside: beside, focusList: focusList)
	}

	/// Takes the usages tab away without touching the pane, for a list that is
	/// moving to another home rather than being finished with.
	func releaseUsages() {
		guard let session = sessions.first(where: {
			if case .usages = $0.kind { return true }; return false
		}) else { return }
		close(session, keepingPane: true)
	}

	// MARK: - The backlog

	/// Shows the backlog dashboard, making it if this is the first time.
	///
	/// One per window and reused, like the search pane: two boards over the
	/// same folder is two things to keep in step for no gain, and the second
	/// one is always the one somebody is looking at when it goes stale.
	@discardableResult
	func showBacklog() -> BacklogPane? {
		guard let root = workingDirectory else { return nil }

		if let index = sessions.firstIndex(where: { if case .backlog = $0.kind { return true }; return false }),
		   case let .backlog(pane) = sessions[index].kind {
			activate(sessions[index], focus: false)
			pane.reload()
			return pane
		}

		let pane = BacklogPane(projectRoot: root)
		pane.onOpenItem = { [weak self] url in self?.onOpenFinding?(url, 1) }
		pane.onNotify = { [weak self] title, detail in self?.onBacklogNotice?(title, detail) }
		pane.onStartAgent = { [weak self] item in self?.startBacklogItem(item) }
		pane.onOpenWorktree = { [weak self] worktree in self?.onOpenProject?(worktree) }
		// A shell in the worktree rather than the agent's own pane: the agent's
		// terminal is somebody else's session, and what is wanted here is a
		// prompt in that checkout to run `git log` in.
		pane.onOpenWorktreeTerminal = { [weak self] worktree in self?.newTerminal(in: worktree) }
		// `openspec init` and nothing else so far: a command the pane wants run
		// where somebody can answer it, in the panel that owns the terminals.
		pane.onRunCommand = { [weak self] title, command, directory in
			self?.runCommand(title: title, command: command, directory: directory)
		}

		let session = Session(title: "Backlog", kind: .backlog(pane))
		sessions.append(session)
		activate(session, focus: false)
		return pane
	}


	/// Picks an item up: a worktree of its own, and the assistant started in a
	/// terminal beside the board.
	///
	/// The agent goes in a pane rather than in the background on purpose. It is
	/// going to work for twenty minutes in a checkout nobody is looking at, and
	/// the one thing that must stay possible is opening the tab, reading what it
	/// decided, and taking over — which is only true if it was started in a
	/// terminal in the first place.
	func startBacklogItem(_ item: BacklogItem) {
		guard let root = workingDirectory else { return }
		// An agent started in a project reads that project's instructions and
		// acts on them — a `CLAUDE.md` in a downloaded repository is a list of
		// things somebody else wants run on this machine. So it waits for
		// trust, like everything else the project can steer.
		guard ProjectTrust.shared.isTrusted(root) else {
			Toast.post("Not trusted", detail: ProjectTrust.shared.decision(for: root).said ?? "")
			return
		}
		let backlog = Backlog(projectRoot: root)
		let configuration = BacklogConfiguration.read(backlog.configFile) ?? BacklogConfiguration()

		Task { @MainActor in
			do {
				let start = try await BacklogRunner.start(
					item,
					in: backlog,
					assistant: configuration.preferred,
					useWorktree: configuration.worktrees
				)
				self.showBacklog()?.reload()

				guard let command = start.command else {
					self.onBacklogNotice?(
						"The worktree is ready, but no assistant is",
						configuration.known.isEmpty
							? "No assistant is configured for this backlog. Run `abydos-backlog init` in the project."
							: "None of \(configuration.known.map(\.name).joined(separator: ", ")) is installed. "
								+ "The worktree is at \(start.directory.path)."
					)
					return
				}

				let title = String(format: "%04d", start.item.number)
				let pane = TerminalPane(
					workingDirectory: start.directory,
					command: (executable: command.executable, arguments: command.arguments)
				)
				let session = Session(title: title, kind: .terminal(pane))
				session.directory = start.directory
				session.isRenamed = true
				session.displayTitle = title
				self.wire(session)
				self.sessions.append(session)
				self.activate(session, focus: true)
			} catch {
				self.onBacklogNotice?("Could not start \(String(format: "%04d", item.number))", "\(error)")
			}
		}
	}

	// MARK: - Debugging

	/// Starts a native debug session for a Go package.
	/// Starts a session on any adapter, however it is to begin.
	@discardableResult
	func startDebugging(
		adapter: DebugAdapter,
		executable: String,
		start: DebugStart,
		breakpoints: [String: [Breakpoint]] = [:],
		location: String? = nil
	) -> DebugSession? {
		// With no project open there is no working directory, and the program's
		// own is the sensible stand-in — debugging a binary should not require
		// having opened a folder first.
		let fallback: URL? = {
			if case let .launch(program, _, directory, _) = start {
				return directory ?? URL(fileURLWithPath: program).deletingLastPathComponent()
			}
			if case .remote = start { return workingDirectory }
			if case .nativeRemote = start { return workingDirectory }
			if case .java = start { return workingDirectory }
			return FileManager.default.homeDirectoryForCurrentUser
		}()
		guard let session = makeDebugSession(breakpoints: breakpoints, fallbackRoot: fallback)
		else { return nil }
		session.location = location

		Task {
			do {
				switch start {
				case let .launch(program, arguments, directory, environment):
					try await session.launch(
						adapter: adapter, executable: executable,
						program: program, arguments: arguments,
						workingDirectory: directory, environment: environment
					)
				case let .attach(pid):
					try await session.attach(adapter: adapter, executable: executable, pid: pid)
				case let .nativeRemote(host, port, binary):
					try await session.attachNatively(
						adapter: adapter, executable: executable,
						program: binary, host: host, port: port
					)
				case let .remote(host, port, program, arguments, directory, environment):
					try await session.launchRemotely(
						host: host, port: port, program: program,
						arguments: arguments, workingDirectory: directory,
						environment: environment
					)
				case let .java(host, port, request):
					try await session.startJava(host: host, port: port, request: request)
				}
			} catch {
				await MainActor.run {
					Toast.post("Could not start the debugger", detail: error.localizedDescription)
				}
			}
		}
		return session
	}

	/// How a session begins.
	enum DebugStart {
		case launch(
			program: String,
			arguments: [String],
			workingDirectory: URL? = nil,
			environment: [String: String] = [:]
		)
		case attach(pid: Int)
		/// A native program held in a pod by gdbserver, with the binary that
		/// was pushed into it still here.
		case nativeRemote(host: String, port: Int, binary: URL)
		/// A debugger already running somewhere else, reached on a local port.
		case remote(
			host: String,
			port: Int,
			program: String,
			arguments: [String],
			workingDirectory: String?,
			environment: [String: String]
		)
		/// Java, where the adapter is hosted by the language server: it is
		/// already listening on a port by the time this is reached, and the
		/// request says whether a class is being started here or a JVM
		/// somewhere else is being attached to.
		case java(host: String, port: Int, request: JavaDebug.Request)
	}

	@discardableResult
	func startDebugging(
		delve: String,
		package: String,
		breakpoints: [String: [Breakpoint]] = [:]
	) -> DebugSession? {
		startDebugging(
			adapter: DebugAdapters.delve,
			executable: delve,
			start: .launch(program: package, arguments: []),
			breakpoints: breakpoints
		)
	}

	/// Builds a session and its pane, wired up but not yet started.
	///
	/// Everything a session needs regardless of which debugger is behind it or
	/// whether it launches a program or attaches to one.
	private func makeDebugSession(
		breakpoints: [String: [Breakpoint]],
		fallbackRoot: URL? = nil
	) -> DebugSession? {
		guard let root = workingDirectory ?? fallbackRoot else { return nil }

		// One debug session at a time; a second would fight over breakpoints.
		if let index = sessions.firstIndex(where: { if case .debug = $0.kind { return true }; return false }) {
			close(index: index, hidingWhenEmpty: false)
		}

		let session = DebugSession(projectRoot: root)
		let pane = installDebugPane(session: session, root: root, focus: false)
		// Straight to the pane's console: `debugOutput` was a hook nobody ever
		// assigned, so every build error and every line the program printed was
		// dropped on the floor.
		session.onOutput = { [weak self, weak pane] text in
			pane?.appendOutput(text)
			self?.debugOutput?(text)
		}
		session.onLaunchStalled = { [weak self, weak pane] message in
			pane?.appendOutput("\n" + message + "\n")
			// Nothing started, so the log is the only thing worth looking at.
			pane?.showConsole()
			self?.debugOutput?("\n" + message + "\n")
			// The console already has the whole story, so the corner only has
			// to say that there is one.
			Toast.post("The debugger did not start", detail: message)
		}

		// Registered before the launch starts, not after it. The adapter asks
		// for breakpoints once, between `initialized` and `configurationDone`,
		// and both arrive within milliseconds — anything added afterwards is
		// simply too late, and the program runs to completion instead.
		session.adopt(breakpoints)


		return session
	}

	/// Puts a debug pane in the panel, with a session behind it or without one.
	///
	/// Both callers want the same pane: the same tab, the same navigation out of
	/// a stack frame, the same run-again buttons, bound to the same sources. What
	/// differs is whether a program is being debugged, and that is the pane's
	/// `session` — nil for one opened to read its breakpoints.
	@discardableResult
	func installDebugPane(session: DebugSession?, root: URL, focus: Bool) -> DebugPane {
		let pane = DebugPane(session: session, projectRoot: root)
		pane.onNavigate = { [weak self] url, line in
			self?.onOpenFinding?(url, line)
		}
		// Its tab wears "running" for as long as the program does, the way a
		// run's does — the debugger is the pane you want to find again.
		pane.onRunningChanged = { [weak self] in
			self?.refreshTabs()
		}
		pane.onRunAgain = { [weak self] in self?.onRunAgain?() }
		pane.onDebugAgain = { [weak self] in self?.onDebugAgain?() }

		let panelSession = Session(title: "Debug", kind: .debug(pane))
		// Bound to the sources it is stopped in — or, with nothing running, to
		// the sources whose breakpoints it is showing.
		panelSession.projectRoot = root
		panelSession.column = focusedColumn
		sessions.append(panelSession)
		activate(panelSession, focus: focus)
		onDebugPaneOpened?(pane)
		return pane
	}

	/// How many debug panes the panel holds, for the claim that a session
	/// starting takes over an empty pane rather than opening a second one.
	var debugPaneCountForTesting: Int {
		sessions.filter { if case .debug = $0.kind { return true }; return false }.count
	}



	/// The running debug session, if any.
	var activeDebugSession: DebugSession? {
		activeDebugPane?.debugSession
	}

	/// The pane itself, for the things that are the pane's rather than the
	/// session's — which tab is showing, and what has just been added to it.
	var activeDebugPane: DebugPane? {
		for session in sessions {
			if case let .debug(pane) = session.kind { return pane }
		}
		return nil
	}
}

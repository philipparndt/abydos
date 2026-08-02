import AppKit
import IdeaiKit

/// The tool panel below the editor: terminals now, agent sessions next.
///
/// Sessions are owned here rather than by whichever view is showing them. That
/// is what lets a pane be hidden and shown again — or handed over for manual
/// takeover — while its process keeps running.
final class BottomPanel: NSView {
	/// Fired when the panel wants to be hidden, so the window can collapse it.
	var onRequestHide: (() -> Void)?
	/// Told when the set of terminals changes, so it can be written down.
	var onTerminalsChanged: (() -> Void)?
	/// Asked to give the panel the whole window, or to hand it back.
	var onToggleMaximize: (() -> Void)?
	/// Asked to start or stop following the shell's project.
	var onToggleFollowProject: (() -> Void)?
	/// The shell moved to another directory.
	var onWorkingDirectoryChanged: ((URL) -> Void)?

	/// Whether the window is following the terminal, shown on the control.
	var isFollowingProject: Bool {
		get { tabStrip.isFollowingProject }
		set {
			tabStrip.isFollowingProject = newValue
			lastReportedDirectory = nil
		}
	}

	/// Where the active terminal was last seen, so only real moves are reported.
	private var lastReportedDirectory: URL?
	private var directoryCheckScheduled = false

	/// Looks again shortly, and only once however much output arrives.
	///
	/// Reading the directory means asking the system about a process, and under
	/// tmux asking the tmux server — neither of which is worth doing for every
	/// chunk of output a build produces.
	private func scheduleDirectoryCheck() {
		guard isFollowingProject, !directoryCheckScheduled else { return }
		directoryCheckScheduled = true
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
			self?.directoryCheckScheduled = false
			self?.reportWorkingDirectory()
		}
	}

	/// Reflects the window's state on the control, so the arrows point the way
	/// the next click would go.
	var isMaximized: Bool {
		get { tabStrip.isMaximized }
		set { tabStrip.isMaximized = newValue }
	}

	private final class Session {
		enum Kind {
			case terminal(TerminalPane)
			/// A review keeps its agent terminal inside the pane, so switching to
			/// the chat is a view change rather than a new process.
			case review(ReviewPane, TerminalPane)
			case search(SearchPane)
			case debug(DebugPane)
			case profiler(ProfilerPane)
		}

		let title: String
		var displayTitle: String
		let kind: Kind
		var hasExited = false
		/// Where the shell was started, so the same terminal can be opened
		/// again next time.
		var directory: URL?
		/// A name somebody typed. The shell reports its running command as a
		/// title, which is a good default and a bad override.
		var isRenamed = false

		init(title: String, kind: Kind) {
			self.title = title
			self.displayTitle = title
			self.kind = kind
		}

		/// The view installed in the content area.
		var view: NSView {
			switch kind {
			case let .terminal(pane): return pane
			case let .review(pane, _): return pane
			case let .search(pane): return pane
			case let .debug(pane): return pane
			case let .profiler(pane): return pane
			}
		}

		/// The terminal behind this session, if it has one.
		var terminal: TerminalPane? {
			switch kind {
			case let .terminal(pane): return pane
			case let .review(_, pane): return pane
			case .search, .debug, .profiler: return nil
			}
		}
	}

	private var sessions: [Session] = []
	private var activeIndex: Int?
	private var workingDirectory: URL?

	/// Forwarded when a review finding or a search result is activated.
	var onOpenFinding: ((URL, Int) -> Void)?

	private var tabStrip: PanelTabStrip!
	private var contentArea: NSView!
	private var placeholder: NSTextField!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		tabStrip = PanelTabStrip()
		tabStrip.onSelect = { [weak self] index in self?.activate(index: index, focus: true) }
		tabStrip.onClose = { [weak self] index in self?.close(index: index) }
		tabStrip.onAdd = { [weak self] in self?.newTerminal() }
		tabStrip.onHide = { [weak self] in self?.onRequestHide?() }
		tabStrip.onRename = { [weak self] index, name in self?.rename(index: index, to: name) }
		tabStrip.onToggleMaximize = { [weak self] in self?.onToggleMaximize?() }
		tabStrip.onToggleFollowProject = { [weak self] in self?.onToggleFollowProject?() }

		contentArea = NSView()

		placeholder = NSTextField(labelWithString: "No terminal open")
		placeholder.font = Theme.current.uiFont(12)
		placeholder.textColor = Theme.current.gitIgnored

		for subview in [tabStrip, contentArea, placeholder] as [NSView] {
			addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		tabStripHeight = tabStrip.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))

		tabStripTop = tabStrip.topAnchor.constraint(equalTo: topAnchor)

		NSLayoutConstraint.activate([
			tabStripTop,
			tabStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
			tabStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
			tabStripHeight,

			contentArea.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),

			placeholder.centerXAnchor.constraint(equalTo: contentArea.centerXAnchor),
			placeholder.centerYAnchor.constraint(equalTo: contentArea.centerYAnchor),
		])
	}

	private var tabStripHeight: NSLayoutConstraint!
	private var tabStripTop: NSLayoutConstraint!

	/// Height the titlebar covers.
	///
	/// Zero while the panel sits at the bottom, where nothing is above it. Given
	/// the whole window it reaches the top, and the window draws under its own
	/// titlebar — so without this the tabs end up behind it.
	func setTopInset(_ inset: CGFloat) {
		tabStripTop.constant = inset
	}

	// MARK: - Project

	func setWorkingDirectory(_ url: URL?) {
		workingDirectory = url
	}

	var hasSessions: Bool { !sessions.isEmpty }

	/// Tells the terminals their pane changed size.
	///
	/// A resize normally arrives through layout, but layout reads the scroll
	/// view's clip before the scroll view has laid it out. Dragging a divider
	/// sends a stream of those and the last one is right; a jump — maximising —
	/// sends one, reads the size the pane had before, and leaves the process
	/// believing it. tmux opened afterwards then draws for a window half the
	/// height of the one it is in.
	/// Looks at where the active terminal is, and says so if it has moved.
	///
	/// Driven by output rather than by a clock: a shell that changes directory
	/// prints a prompt, and one that is sitting idle has not gone anywhere. An
	/// idle terminal therefore costs nothing at all.
	func reportWorkingDirectory() {
		guard isFollowingProject else { return }
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count, let terminal = sessions[index].terminal else { return }
		guard let directory = terminal.currentDirectoryForTesting else { return }

		guard directory.standardizedFileURL.path != lastReportedDirectory?.path else { return }
		lastReportedDirectory = directory.standardizedFileURL
		onWorkingDirectoryChanged?(directory)
	}

	/// Another terminal tab is another shell, quite possibly somewhere else.
	func activeTerminalChanged() {
		lastReportedDirectory = nil
		reportWorkingDirectory()
	}

	func viewportChanged() {
		for session in sessions {
			session.terminal?.terminalViewForTesting.viewportChanged()
		}
	}

	// MARK: - Sessions

	func showDebugConsoleForTesting() {
		showDebug()?.showConsole()
	}

	/// Brings an existing debug session forward, or says there is none.
	@discardableResult
	func showDebug() -> DebugPane? {
		for (index, session) in sessions.enumerated() {
			if case let .debug(pane) = session.kind {
				activate(index: index, focus: true)
				return pane
			}
		}
		return nil
	}

	/// Draws the debug toolbar to a PNG, if there is one.
	@discardableResult
	func writeDebugToolbarImageForTesting(to path: String) -> Bool {
		for session in sessions {
			if case let .debug(pane) = session.kind {
				return pane.writeToolbarImageForTesting(to: path)
			}
		}
		return false
	}

	/// Exercises watches, goroutines, conditions and copying, and says what
	/// each produced.
	func exerciseDebugExtrasForTesting() {
		guard let session = activeDebugSession else {
			print("EXTRAS: no session")
			return
		}

		session.addWatch("number")
		session.addWatch("numbers")
		session.addWatch("answer * 2")
		session.addWatch("nonesuch")

		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 900_000_000)
			for watch in session.watches {
				print("WATCH: \(watch.expression) = \(watch.value ?? "nil") failed=\(watch.failed)")
			}
			print("THREADS: \(session.threads.count) goroutines, showing \(session.selectedThreadID ?? -1)")
			for thread in session.threads.prefix(4) {
				print("THREAD: \(thread.id) \(thread.name)")
			}

			// Another goroutine's stack, without moving the execution marker.
			if let other = session.threads.first(where: { $0.id != session.selectedThreadID }) {
				await session.selectThread(id: other.id)
				print("THREADS: switched to \(other.id), stack has \(session.stackFrames.count) frames")
			}

			for pane in self.debugPanesForTesting {
				print("COPY: \(pane.copyFirstVariableForTesting())")
			}
		}
	}

	var debugPanesForTesting: [DebugPane] {
		sessions.compactMap { if case let .debug(pane) = $0.kind { return pane } else { return nil } }
	}

	var debugToolTipsForTesting: [String] {
		for session in sessions {
			if case let .debug(pane) = session.kind { return pane.toolbarToolTipsForTesting }
		}
		return []
	}

	/// Whether the keyboard is in this panel.
	///
	/// Asked by ⌘T, which means "another terminal tab" while typing in one and
	/// nothing at all anywhere else — the same key doing two jobs depending on
	/// where you are is exactly what makes it feel native.
	var hasKeyboardFocus: Bool {
		guard !isHidden, let responder = window?.firstResponder as? NSView else { return false }
		return responder === self || responder.isDescendant(of: self)
	}

	/// How many sessions are open, for checking a new tab arrived.
	var sessionCountForTesting: Int { sessions.count }

	/// Opens a shell, or focuses the existing one if there already is a terminal.
	@discardableResult
	func showTerminal() -> TerminalPane? {
		if sessions.isEmpty {
			return newTerminal()
		}
		activate(index: activeIndex ?? 0, focus: true)
		return sessions[activeIndex ?? 0].terminal
	}

	/// Opens a shell rooted at a specific directory, for "Open Terminal Here".
	///
	/// Always a new session: the point is the directory, and reusing a shell that
	/// is already somewhere else — possibly mid-command — would not honour it.
	@discardableResult
	func newTerminal(in directory: URL) -> TerminalPane? {
		newTerminal(rootedAt: directory, title: directory.lastPathComponent)
	}

	@discardableResult
	func newTerminal() -> TerminalPane? {
		newTerminal(rootedAt: workingDirectory, title: "Local")
	}

	@discardableResult
	private func newTerminal(
		rootedAt directory: URL?,
		title: String,
		focus: Bool = true
	) -> TerminalPane? {
		let pane = TerminalPane(workingDirectory: directory)
		let session = Session(title: title, kind: .terminal(pane))
		session.directory = directory
		wire(session)

		sessions.append(session)
		activate(index: sessions.count - 1, focus: focus)
		onTerminalsChanged?()
		return pane
	}

	/// Runs a command in a new pane, in a directory of its own.
	///
	/// Through a login shell rather than exec'd directly: a run configuration
	/// names `go` or `make`, and a GUI app's PATH does not have them — the
	/// shell is what knows where the user's tools are.
	@discardableResult
	func runCommand(
		title: String,
		command: String,
		directory: URL,
		environment: [String: String] = [:]
	) -> TerminalPane? {
		let assignments = environment
			.sorted { $0.key < $1.key }
			// Quoted, not merely escaped: a value with a space in it becomes a
			// second word to `env`, which then tries to run it.
			.map { "\($0.key)='\($0.value.replacingOccurrences(of: "'", with: "'\\''"))'" }
			.joined(separator: " ")
		let line = assignments.isEmpty ? command : "env \(assignments) \(command)"

		return runCommand(
			title: title,
			executable: "/bin/sh",
			arguments: ["-lc", line],
			workingDirectory: directory
		)
	}

	/// Runs a command in a new pane. The basis for "Run" and for agent sessions.
	@discardableResult
	func runCommand(
		title: String,
		executable: String,
		arguments: [String],
		workingDirectory: URL? = nil
	) -> TerminalPane? {
		let pane = TerminalPane(
			workingDirectory: workingDirectory ?? self.workingDirectory,
			command: (executable: executable, arguments: arguments)
		)
		let session = Session(title: title, kind: .terminal(pane))
		wire(session)

		sessions.append(session)
		activate(index: sessions.count - 1, focus: true)
		return pane
	}

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
			activate(index: index, focus: false)
		} else {
			pane = TerminalPane(readOnly: ())
			sessions.append(Session(title: title, kind: .terminal(pane)))
			activate(index: sessions.count - 1, focus: false)
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
			pane = existing
			activate(index: index, focus: false)
		} else {
			pane = TerminalPane(readOnly: ())
			let session = Session(title: title, kind: .terminal(pane))
			sessions.append(session)
			activate(index: sessions.count - 1, focus: false)
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
	func showProfiler(address: String) -> ProfilerPane? {
		if let index = sessions.firstIndex(where: {
			if case .profiler = $0.kind { return true }; return false
		}), case let .profiler(pane) = sessions[index].kind {
			activate(index: index, focus: true)
			return pane
		}

		let pane = ProfilerPane(defaultAddress: address)
		pane.onOpenFunction = { [weak self] name in
			self?.onOpenSymbol?(name)
		}
		let session = Session(title: "Profiler", kind: .profiler(pane))
		sessions.append(session)
		activate(index: sessions.count - 1, focus: true)
		return pane
	}

	/// Asked to find a function by name, for a frame somebody clicked.
	var onOpenSymbol: ((String) -> Void)?

	@discardableResult
	func showSearch(query: String? = nil) -> SearchPane? {
		guard let root = workingDirectory else { return nil }

		if let index = sessions.firstIndex(where: { if case .search = $0.kind { return true }; return false }),
		   case let .search(pane) = sessions[index].kind {
			activate(index: index, focus: false)
			if let query { pane.setQuery(query) }
			pane.focusField()
			return pane
		}

		let pane = SearchPane(projectRoot: root)
		pane.onOpenResult = { [weak self] url, line, _ in
			self?.onOpenFinding?(url, line)
		}
		let session = Session(title: "Search", kind: .search(pane))
		sessions.append(session)
		activate(index: sessions.count - 1, focus: false)
		if let query { pane.setQuery(query) }
		pane.focusField()
		return pane
	}

	// MARK: - Debugging

	/// Starts a native debug session for a Go package.
	/// Starts a session on any adapter, however it is to begin.
	@discardableResult
	func startDebugging(
		adapter: DebugAdapter,
		executable: String,
		start: DebugStart,
		breakpoints: [String: [Breakpoint]] = [:]
	) -> DebugSession? {
		// With no project open there is no working directory, and the program's
		// own is the sensible stand-in — debugging a binary should not require
		// having opened a folder first.
		let fallback: URL? = {
			if case let .launch(program, _, directory, _) = start {
				return directory ?? URL(fileURLWithPath: program).deletingLastPathComponent()
			}
			if case .remote = start { return workingDirectory }
			return FileManager.default.homeDirectoryForCurrentUser
		}()
		guard let session = makeDebugSession(breakpoints: breakpoints, fallbackRoot: fallback)
		else { return nil }

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
				case let .remote(host, port, program, arguments, directory, environment):
					try await session.launchRemotely(
						host: host, port: port, program: program,
						arguments: arguments, workingDirectory: directory,
						environment: environment
					)
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
		/// A debugger already running somewhere else, reached on a local port.
		case remote(
			host: String,
			port: Int,
			program: String,
			arguments: [String],
			workingDirectory: String?,
			environment: [String: String]
		)
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
		let pane = DebugPane(session: session, projectRoot: root)
		pane.onNavigate = { [weak self] url, line in
			self?.onOpenFinding?(url, line)
		}
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
		for (file, list) in breakpoints {
			for breakpoint in list.sorted(by: { $0.line < $1.line }) {
				session.toggleBreakpoint(file: file, line: breakpoint.line)
				guard breakpoint.isConditional else { continue }
				session.setBreakpointOptions(
					file: file,
					line: breakpoint.line,
					condition: breakpoint.condition,
					hitCondition: breakpoint.hitCondition,
					logMessage: breakpoint.logMessage
				)
			}
		}

		let panelSession = Session(title: "Debug", kind: .debug(pane))
		sessions.append(panelSession)
		activate(index: sessions.count - 1, focus: false)
		return session
	}

	/// Forwarded debuggee output.
	var debugOutput: ((String) -> Void)?

	/// The running debug session, if any.
	var activeDebugSession: DebugSession? {
		for session in sessions {
			if case let .debug(pane) = session.kind { return pane.debugSession }
		}
		return nil
	}

	// MARK: - Review

	/// Starts an agent review of whatever `scope` names.
	///
	/// The agent reports through this window's own MCP server, so findings
	/// arrive as typed data rather than as text to be parsed out of a TUI.
	@discardableResult
	func startReview(scope: AgentLauncher.ReviewScope) -> Result<Void, ReviewStartError> {
		guard let root = workingDirectory else { return .failure(.noProject) }
		guard let executable = AgentLauncher.findClaudeExecutable() else {
			return .failure(.claudeNotFound)
		}

		let reviewSession = ReviewSession(projectRoot: root)
		let server = MCPServer()
		for tool in reviewSession.makeTools() { server.register(tool) }

		do {
			try server.start()
		} catch {
			return .failure(.serverFailed)
		}

		let command = AgentLauncher.reviewCommand(
			executable: executable,
			server: server,
			prompt: AgentLauncher.reviewPrompt(scope: scope)
		)
		let terminal = TerminalPane(
			workingDirectory: root,
			command: (executable: command.executable, arguments: command.arguments)
		)
		let reviewPane = ReviewPane(session: reviewSession, server: server, terminalPane: terminal)
		reviewPane.onOpenFinding = { [weak self] url, line in
			self?.onOpenFinding?(url, line)
		}

		let session = Session(title: scope.title, kind: .review(reviewPane, terminal))
		wire(session)
		sessions.append(session)
		activate(index: sessions.count - 1, focus: false)
		return .success(())
	}

	enum ReviewStartError: Error {
		case noProject
		case claudeNotFound
		case serverFailed

		var message: String {
			switch self {
			case .noProject: return "Open a project first."
			case .claudeNotFound:
				return "Could not find the `claude` executable. Install Claude Code, or make sure it is in /opt/homebrew/bin or /usr/local/bin."
			case .serverFailed: return "Could not start the local MCP server."
			}
		}
	}

	private func wire(_ session: Session) {
		guard let terminal = session.terminal else { return }
		// A shell that changes directory prints a prompt, so output is the cue
		// to look. An idle terminal produces none and costs nothing.
		terminal.terminalView.onOutput = { [weak self] in
			self?.scheduleDirectoryCheck()
		}
		terminal.terminalView.onProcessExit = { [weak self, weak session] _ in
			guard let self, let session else { return }
			session.hasExited = true
			self.refreshTabs()
		}
		// A review's tab keeps its own name; only a shell borrows the command
		// name from the title sequence.
		guard case .terminal = session.kind else { return }
		terminal.terminalView.onTitleChange = { [weak self, weak session] title in
			guard let self, let session else { return }
			// A shell reports its running command via the title, which is the
			// most useful label a terminal tab can carry.
			guard !session.isRenamed else { return }
			let trimmed = title.split(separator: " ").first.map(String.init) ?? title
			guard !trimmed.isEmpty, session.displayTitle != trimmed else { return }
			session.displayTitle = trimmed
			self.refreshTabs()
		}
	}

	private func activate(index: Int, focus: Bool) {
		guard sessions.indices.contains(index) else { return }
		contentArea.subviews.forEach { $0.removeFromSuperview() }

		activeIndex = index
		let session = sessions[index]
		let view = session.view
		view.translatesAutoresizingMaskIntoConstraints = false
		contentArea.addSubview(view)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: contentArea.topAnchor),
			view.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
		])

		placeholder.isHidden = true
		refreshTabs()
		if focus, case .terminal = session.kind { session.terminal?.focus() }
		activeTerminalChanged()
	}

	/// Closes a session, optionally without asking the panel to go away.
	///
	/// Replacing the only session would otherwise close the panel and open it
	/// again, which from the outside looks exactly like pressing debug having
	/// toggled it shut.
	private func close(index: Int, hidingWhenEmpty: Bool = true) {
		guard sessions.indices.contains(index) else { return }
		let session = sessions[index]
		switch session.kind {
		case let .review(pane, _): pane.shutdown()
		case let .debug(pane): pane.shutdown()
		case let .profiler(pane): pane.shutdown()
		default: session.terminal?.terminalView.terminateProcess()
		}
		session.view.removeFromSuperview()
		sessions.remove(at: index)

		if sessions.isEmpty {
			activeIndex = nil
			contentArea.subviews.forEach { $0.removeFromSuperview() }
			placeholder.isHidden = false
			refreshTabs()
			if hidingWhenEmpty { onRequestHide?() }
			return
		}
		activeIndex = nil
		activate(index: min(index, sessions.count - 1), focus: false)
		onTerminalsChanged?()
	}

	/// Renames a tab.
	///
	/// An empty name gives it back to the shell, which is the only way to undo
	/// a rename without knowing what the shell would have called it.
	func rename(index: Int, to name: String) {
		guard sessions.indices.contains(index) else { return }
		let trimmed = name.trimmingCharacters(in: .whitespaces)
		let session = sessions[index]

		if trimmed.isEmpty {
			session.isRenamed = false
			session.displayTitle = session.title
		} else {
			session.isRenamed = true
			session.displayTitle = trimmed
		}
		refreshTabs()
		onTerminalsChanged?()
	}

	/// Renames whichever tab is in front, for the capture harness.
	func renameActiveForTesting(to name: String) {
		guard let activeIndex else { return }
		rename(index: activeIndex, to: name)
	}

	/// The terminals that are open, to be opened again next time.
	///
	/// Only plain terminals: a debugger, a profiler or a review is attached to
	/// something that is not running any more, and reopening one would be
	/// reopening a window onto nothing.
	func captureTerminals() -> [ProjectSession.OpenTerminal] {
		sessions.compactMap { session in
			guard case .terminal = session.kind, !session.hasExited else { return nil }
			return ProjectSession.OpenTerminal(
				name: session.displayTitle,
				directory: session.directory?.path,
				isRenamed: session.isRenamed
			)
		}
	}

	/// Opens the terminals a project had, with fresh shells in the same places.
	func restoreTerminals(_ terminals: [ProjectSession.OpenTerminal]) {
		for terminal in terminals {
			let directory = terminal.directory.map { URL(fileURLWithPath: $0) } ?? workingDirectory
			// Not focused: this happens while a project is opening, and the
			// keyboard belongs to whatever the person opened it for.
			guard let pane = newTerminal(rootedAt: directory, title: terminal.name, focus: false)
			else { continue }
			guard let session = sessions.last, session.terminal === pane else { continue }
			session.isRenamed = terminal.isRenamed
			session.displayTitle = terminal.name
		}
		refreshTabs()
	}

	/// Closes every plain terminal, for a window that is changing project.
	func closeTerminals() {
		for index in sessions.indices.reversed() {
			guard case .terminal = sessions[index].kind else { continue }
			close(index: index, hidingWhenEmpty: false)
		}
	}

	private func refreshTabs() {
		tabStrip.setItems(
			sessions.map {
				PanelTabItem(
					title: $0.displayTitle,
					hasExited: $0.hasExited,
					canRename: { if case .terminal = $0.kind { return true } else { return false } }($0)
				)
			},
			activeIndex: activeIndex
		)
	}

	// MARK: - Commands

	func focusActive() {
		guard let activeIndex, sessions.indices.contains(activeIndex) else { return }
		sessions[activeIndex].terminal?.focus()
	}

	func applySettings() {
		tabStripHeight.constant = Theme.current.scaled(30)
		placeholder.font = Theme.current.uiFont(12)
		tabStrip.applyThemeChange()
		for session in sessions {
			switch session.kind {
			case let .review(pane, _): pane.applySettings()
			case let .search(pane): pane.applySettings()
			case let .debug(pane): pane.applySettings()
			case let .terminal(pane): pane.terminalView.applyThemeChange()
			case .profiler: break
			}
		}
	}

	/// Terminates every session. Called when the window closes.
	func shutdown() {
		for session in sessions {
			switch session.kind {
			case let .review(pane, _): pane.shutdown()
			case let .debug(pane): pane.shutdown()
			case let .profiler(pane): pane.shutdown()
			default: session.terminal?.terminalView.terminateProcess()
			}
		}
		sessions.removeAll()
	}
}

// MARK: - Tab strip

struct PanelTabItem {
	let title: String
	let hasExited: Bool
	/// Only a terminal is named by the person using it.
	var canRename = false
}

/// Compact tab strip with add and hide affordances.
final class PanelTabStrip: NSView {
	var onSelect: ((Int) -> Void)?
	var onClose: ((Int) -> Void)?
	/// A tab renamed in place. An empty name gives it back to the shell.
	var onRename: ((Int, String) -> Void)?
	var onAdd: (() -> Void)?
	var onHide: (() -> Void)?
	/// Asked to give the panel the whole window, or to give it back.
	var onToggleMaximize: (() -> Void)?
	/// Whether the panel currently has the window to itself, which decides
	/// which way the arrows point.
	var isMaximized = false { didSet { needsDisplay = true } }
	/// Asked to start or stop following the shell's project.
	var onToggleFollowProject: (() -> Void)?
	/// Whether the window is following the terminal, which the control shows.
	var isFollowingProject = false { didSet { needsDisplay = true } }

	private var items: [PanelTabItem] = []
	private var activeIndex: Int?
	private var frames: [NSRect] = []
	private var addButtonFrame: NSRect = .zero
	private var hideButtonFrame: NSRect = .zero
	private var maximizeButtonFrame: NSRect = .zero
	private var followButtonFrame: NSRect = .zero
	private var hoveredIndex: Int?
	private var trackingArea: NSTrackingArea?

	override var isFlipped: Bool { true }

	func setItems(_ items: [PanelTabItem], activeIndex: Int?) {
		self.items = items
		self.activeIndex = activeIndex
		recomputeLayout()
		needsDisplay = true
	}

	func applyThemeChange() {
		recomputeLayout()
		needsDisplay = true
	}

	private var font: NSFont { Theme.current.uiFont(11.5) }
	private var closeSize: CGFloat { Theme.current.scaled(12) }
	private var padding: CGFloat { Theme.current.scaled(10) }

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		recomputeLayout()
	}

	private func recomputeLayout() {
		frames.removeAll()
		var x = Theme.current.scaled(8)
		for item in items {
			let width = (item.title as NSString).size(withAttributes: [.font: font]).width
				+ padding * 2 + closeSize
			frames.append(NSRect(x: x, y: 0, width: ceil(width), height: bounds.height))
			x += ceil(width) + Theme.current.scaled(2)
		}
		addButtonFrame = NSRect(x: x + Theme.current.scaled(4), y: 0, width: Theme.current.scaled(24), height: bounds.height)
		hideButtonFrame = NSRect(
			x: bounds.width - Theme.current.scaled(30),
			y: 0,
			width: Theme.current.scaled(24),
			height: bounds.height
		)
		// Beside the one that puts it away, since they are the same kind of
		// thing: how much room the panel gets.
		maximizeButtonFrame = NSRect(
			x: hideButtonFrame.minX - Theme.current.scaled(26),
			y: 0,
			width: Theme.current.scaled(24),
			height: bounds.height
		)
		followButtonFrame = NSRect(
			x: maximizeButtonFrame.minX - Theme.current.scaled(26),
			y: 0,
			width: Theme.current.scaled(24),
			height: bounds.height
		)
	}

	// MARK: - Renaming in place

	private var renameField: NSTextField?
	private var renamingIndex: Int?

	func beginRenaming(_ index: Int) {
		guard frames.indices.contains(index) else { return }
		endRenaming(commit: true)

		let field = NSTextField(string: items[index].title)
		field.font = font
		field.textColor = Theme.current.sidebarHeaderText
		field.backgroundColor = Theme.current.editorBackground
		field.drawsBackground = true
		field.isBordered = false
		field.isBezeled = false
		field.focusRingType = .none
		field.delegate = self
		field.frame = frames[index].insetBy(dx: Theme.current.scaled(4), dy: Theme.current.scaled(5))
		field.wantsLayer = true
		field.layer?.cornerRadius = 3

		addSubview(field)
		renameField = field
		renamingIndex = index
		window?.makeFirstResponder(field)
		field.currentEditor()?.selectAll(nil)
	}

	private func endRenaming(commit: Bool) {
		guard let field = renameField, let index = renamingIndex else { return }
		renameField = nil
		renamingIndex = nil

		let name = field.stringValue
		field.removeFromSuperview()
		if commit { onRename?(index, name) }
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp], owner: self)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let index = frames.firstIndex { $0.contains(point) }
		if index != hoveredIndex {
			hoveredIndex = index
			needsDisplay = true
		}
	}

	override func mouseExited(with event: NSEvent) {
		hoveredIndex = nil
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)

		if addButtonFrame.contains(point) { onAdd?(); return }
		if hideButtonFrame.contains(point) { onHide?(); return }
		if maximizeButtonFrame.contains(point) { onToggleMaximize?(); return }
		if followButtonFrame.contains(point) { onToggleFollowProject?(); return }

		// Double-clicking the empty part of the strip does what the arrow does,
		// the way double-clicking a window's title bar zooms it.
		if event.clickCount == 2, !frames.contains(where: { $0.contains(point) }) {
			onToggleMaximize?()
			return
		}

		// Double-clicking a tab renames it, in place: the name is a label on a
		// tab, and typing it anywhere else means finding the tab again after.
		if event.clickCount == 2, let index = frames.firstIndex(where: { $0.contains(point) }),
		   items.indices.contains(index), items[index].canRename {
			beginRenaming(index)
			return
		}

		guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return }
		let closeRect = NSRect(
			x: frames[index].maxX - padding - closeSize,
			y: frames[index].midY - closeSize / 2,
			width: closeSize,
			height: closeSize
		)
		if closeRect.contains(point) {
			onClose?(index)
		} else {
			onSelect?(index)
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		for (index, item) in items.enumerated() where index < frames.count {
			draw(item: item, in: frames[index], isActive: index == activeIndex, isHovered: index == hoveredIndex)
		}

		drawGlyph(in: addButtonFrame, symbol: "plus")
		drawGlyph(in: hideButtonFrame, symbol: "chevron.down")
		drawGlyph(
			in: maximizeButtonFrame,
			symbol: isMaximized
				? "arrow.down.right.and.arrow.up.left"
				: "arrow.up.left.and.arrow.down.right"
		)
		// Filled while it is on, so it is obvious at a glance that the window is
		// no longer staying where it was put.
		drawGlyph(
			in: followButtonFrame,
			symbol: isFollowingProject ? "link.circle.fill" : "link.circle",
			tint: isFollowingProject ? Theme.current.gitAdded : nil
		)
	}

	private func draw(item: PanelTabItem, in rect: NSRect, isActive: Bool, isHovered: Bool) {
		if isActive {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.10).setFill()
			path.fill()
		} else if isHovered {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.05).setFill()
			path.fill()
		}

		// An exited session is dimmed rather than removed, so output stays
		// readable after the process finishes.
		let color = item.hasExited
			? Theme.current.gitIgnored
			: (isActive ? Theme.current.sidebarHeaderText : Theme.current.sidebarText)

		let label = NSAttributedString(string: item.title, attributes: [
			.font: font,
			.foregroundColor: color,
		])
		let size = label.size()
		label.draw(at: NSPoint(x: rect.minX + padding, y: rect.midY - size.height / 2))

		if isActive || isHovered {
			let close = NSRect(
				x: rect.maxX - padding - closeSize,
				y: rect.midY - closeSize / 2,
				width: closeSize,
				height: closeSize
			)
			let cross = NSBezierPath()
			let inset = Theme.current.scaled(3)
			cross.move(to: NSPoint(x: close.minX + inset, y: close.minY + inset))
			cross.line(to: NSPoint(x: close.maxX - inset, y: close.maxY - inset))
			cross.move(to: NSPoint(x: close.maxX - inset, y: close.minY + inset))
			cross.line(to: NSPoint(x: close.minX + inset, y: close.maxY - inset))
			cross.lineWidth = 1.2
			cross.lineCapStyle = .round
			Theme.current.sidebarText.setStroke()
			cross.stroke()
		}
	}

	private func drawGlyph(in rect: NSRect, symbol: String, tint: NSColor? = nil) {
		guard let image = Theme.symbol(
			symbol,
			size: 11 * Theme.current.scale,
			color: tint ?? Theme.current.sidebarText
		) else {
			return
		}
		let size = Theme.current.scaled(12)
		image.drawFitted(in: NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size))
	}
}


/// Committing a rename: return keeps it, escape drops it, and clicking away
/// keeps it too — the same as renaming a file in the Finder.
extension PanelTabStrip: NSTextFieldDelegate {
	func controlTextDidEndEditing(_ notification: Notification) {
		endRenaming(commit: true)
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
		switch command {
		case #selector(NSResponder.cancelOperation(_:)):
			endRenaming(commit: false)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			endRenaming(commit: true)
			return true
		default:
			return false
		}
	}
}

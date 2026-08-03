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
		get { columnViews.first?.strip.isFollowingProject ?? storedFollowing }
		set {
			storedFollowing = newValue
			for view in columnViews { view.strip.isFollowingProject = newValue }
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
		get { columnViews.first?.strip.isMaximized ?? storedMaximized }
		set {
			storedMaximized = newValue
			for view in columnViews { view.strip.isMaximized = newValue }
		}
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
		/// Which side of the panel its tab is on. Zero unless the panel is
		/// split, which is the whole of what a split is: some tabs over here
		/// and some over there.
		var column = 0

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

		/// What this holds, for its tab.
		var symbol: String {
			switch kind {
			case .terminal: return "terminal"
			case .review: return "sparkles"
			case .search: return "magnifyingglass"
			case .debug: return "ladybug"
			case .profiler: return "gauge.with.needle"
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
	/// What is in front in each column.
	private var activeByColumn: [Int: Session] = [:]
	/// Which column a new pane appears in, and which one a click last landed on.
	private var focusedColumn = 0
	private var workingDirectory: URL?

	/// How many columns there are: two once anything has been put beside
	/// something, one otherwise.
	private var columnCount: Int { sessions.contains { $0.column == 1 } ? 2 : 1 }

	/// The tabs in a column, in order.
	private func sessions(in column: Int) -> [Session] {
		sessions.filter { $0.column == column }
	}

	private func session(at index: Int, in column: Int) -> Session? {
		let list = sessions(in: column)
		return list.indices.contains(index) ? list[index] : nil
	}

	/// The pane in front, wherever the focus is.
	private var activeSession: Session? {
		activeByColumn[focusedColumn] ?? sessions(in: focusedColumn).last ?? sessions.last
	}

	private var activeIndex: Int? {
		guard let session = activeSession else { return nil }
		return sessions.firstIndex { $0 === session }
	}

	/// Forwarded when a review finding or a search result is activated.
	var onOpenFinding: ((URL, Int) -> Void)?

	/// This panel, so a tab dragged from one is recognised by the other.
	let panelID = UUID()
	/// A terminal dragged out of the panel altogether.
	var onTearOffTerminal: ((DetachedTerminal, NSPoint) -> Void)?

	/// What is on screen, left to right.
	///
	/// One, nearly always. Two when somebody has dropped a tab against the
	/// side of the pane: a shell beside the logs it is producing is the whole
	/// reason for splitting a terminal area.
	private var columns: [Session] = []

	/// Where the columns live.
	private var columnsHost: NSView!
	private var columnViews: [PanelColumn] = []
	private var columnsSplit: ColumnSplitView?
	/// Whether the panel's own controls belong in this panel's strips.
	private var showsPanelControls = true
	private var storedFollowing = false
	private var storedMaximized = false
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
		placeholder = NSTextField(labelWithString: "No terminal open")
		placeholder.font = Theme.current.uiFont(12)
		placeholder.textColor = Theme.current.gitIgnored

		columnsHost = NSView()

		for subview in [columnsHost, placeholder] as [NSView] {
			addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		tabStripTop = columnsHost.topAnchor.constraint(equalTo: topAnchor)
		NSLayoutConstraint.activate([
			tabStripTop,
			columnsHost.leadingAnchor.constraint(equalTo: leadingAnchor),
			columnsHost.trailingAnchor.constraint(equalTo: trailingAnchor),
			columnsHost.bottomAnchor.constraint(equalTo: bottomAnchor),

			placeholder.centerXAnchor.constraint(equalTo: columnsHost.centerXAnchor),
			placeholder.centerYAnchor.constraint(equalTo: columnsHost.centerYAnchor),
		])

		TerminalDragSources.register(self, as: panelID)
		rebuildColumns()
	}

	/// A side of the panel: its own tabs, its own pane.
	///
	/// The editor splits this way and a panel has to as well. One strip across
	/// two panes cannot say which side a tab belongs to, so every question —
	/// which tab is showing, where a new terminal goes, what a click means —
	/// had to be answered by guessing.
	private func makeColumn(_ column: Int) -> PanelColumn {
		let view = PanelColumn(column: column)
		let strip = view.strip

		strip.panelID = panelID
		strip.setUpTabDropping()
		strip.onSelect = { [weak self] index in
			guard let self else { return }
			if let window = self.mirroredWindow(at: index, in: column) {
				self.markMirroredWindowActive(window.index)
				Task {
					await TmuxMirror.select(window: window.index, inSession: self.mirroredSession ?? self.tmuxSession ?? "")
					self.refreshTmuxWindows()
				}
				self.focusTerminal()
				return
			}
			guard let session = self.session(at: index, in: column) else { return }
			self.activate(session, focus: true)
		}
		strip.onClose = { [weak self] index in
			guard let self else { return }
			if let window = self.mirroredWindow(at: index, in: column) {
				Task {
					await TmuxMirror.killWindow(window.index, inSession: self.mirroredSession ?? self.tmuxSession ?? "")
					self.refreshTmuxWindows()
				}
				return
			}
			guard let session = self.session(at: index, in: column) else { return }
			self.close(session)
		}
		strip.onAdd = { [weak self] in
			guard let self else { return }
			if self.mirrorsTmux, column == 0, let session = self.mirroredSession ?? self.tmuxSession {
				Task {
					await TmuxMirror.newWindow(inSession: session)
					self.refreshTmuxWindows()
				}
				self.focusTerminal()
				return
			}
			self.focusedColumn = column
			self.newTerminal()
		}
		strip.onHide = { [weak self] in self?.onRequestHide?() }
		strip.onRename = { [weak self] index, name in
			guard let self else { return }
			if let window = self.mirroredWindow(at: index, in: column) {
				Task {
					await TmuxMirror.rename(
						window: window.index, to: name,
						inSession: self.mirroredSession ?? self.tmuxSession ?? ""
					)
					self.refreshTmuxWindows()
				}
				return
			}
			guard let session = self.session(at: index, in: column) else { return }
			self.rename(session, to: name)
		}
		// Anything in the panel can be moved: a profiler beside the terminal
		// that produced the load is the arrangement somebody wants, and a
		// debugger beside its program is another.
		strip.canDrag = { [weak self] index in
			guard let self else { return false }
			// A mirrored tab is a tmux window: it can be dragged along the
			// strip, but not out into a window of its own or into another
			// column — tmux owns where it lives.
			if self.mirroredWindow(at: index, in: column) != nil { return true }
			return self.session(at: index, in: column) != nil
		}
		strip.onMove = { [weak self] from, to in
			guard let self else { return }
			if let moved = self.mirroredWindow(at: from, in: column) {
				self.moveMirroredWindow(moved, from: from, to: to)
				return
			}
			self.move(from: from, to: to, in: column)
		}
		strip.onTearOff = { [weak self] index, point in
			guard let self else { return }
			// tmux's windows stay in tmux: tearing one into a window of its own
			// would mean a second client, which is not what the drag looked
			// like it would do.
			guard self.mirroredWindow(at: index, in: column) == nil else { return }
			guard let session = self.session(at: index, in: column) else { return }
			self.tearOff(session, at: point)
		}
		strip.onDragStarted = { [weak self] in self?.showDropTargets() }
		strip.onDragEnded = { [weak self] in self?.hideDropTargets() }
		strip.onDragMoved = { [weak self] point in self?.previewDrop(at: point) }
		strip.onDragEndedAt = { [weak self] index, point in
			guard let self, let session = self.session(at: index, in: column) else { return }
			self.finishDrag(session, at: point)
		}
		strip.onSplit = { [weak self] index, zone in
			guard let self, let session = self.session(at: index, in: column) else { return }
			self.putBeside(session, on: zone)
		}
		strip.onUnsplit = { [weak self] in self?.unsplit() }
		strip.isSplit = { [weak self] in (self?.columnCount ?? 1) > 1 }
		strip.acceptsForeign = { payload in
			TerminalDragSources.source(for: payload.panelID) != nil
		}
		strip.column = column
		// A tab dropped on a strip belongs to that strip's column afterwards,
		// wherever it came from: the other column, or another window. Dragging
		// one back is how a split is undone by hand.
		strip.onDropTab = { [weak self] payload, position in
			self?.dropOnStrip(payload, at: position, in: column)
		}
		strip.onMirrorTagClicked = { [weak self] rect in
			self?.showSessionMenu(from: rect, in: column)
		}
		strip.onToggleMaximize = { [weak self] in self?.onToggleMaximize?() }
		strip.onToggleFollowProject = { [weak self] in self?.onToggleFollowProject?() }
		strip.isFollowingProject = isFollowingProject
		strip.isMaximized = isMaximized
		// The panel's own controls belong to one strip, not to each of them:
		// there is one panel to hide however many columns it holds.
		strip.showsPanelControls = showsPanelControls && column == 0
		return view
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

	/// Turns this into the terminal area of a window of its own.
	///
	/// Everything a panel does with terminals — tabs, the +, renaming,
	/// dragging, splitting — is wanted out there too; what is not wanted is the
	/// chrome of a panel that can be hidden, maximised, or made to follow a
	/// project the window does not have.
	func becomeTerminalWindow() {
		showsPanelControls = false
		for view in columnViews {
			view.strip.showsPanelControls = false
			view.strip.showsAddButton = true
		}
	}

	/// Takes in a terminal dragged here from somewhere else.
	func adoptTerminal(_ detached: DetachedTerminal) {
		adopt(detached, zone: .center)
	}

	/// What the terminal in front is called, for a window title.
	var activeTerminalTitle: String? {
		guard let activeIndex, sessions.indices.contains(activeIndex) else { return nil }
		return sessions[activeIndex].displayTitle
	}

	/// Told when the tabs or their names change, so a window can retitle.
	var onActiveTerminalChanged: (() -> Void)?

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
	/// Drives the pointer over the terminal grid: a right-click, then moves.
	/// What a hand does with a tmux menu: press, drag onto an item, let go.
	func terminalMenuDragForTesting(from start: (row: Int, column: Int), over cells: [(row: Int, column: Int)]) {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count, let terminal = sessions[index].terminal else { return }

		terminal.rightPressForTesting(row: start.row, column: start.column)
		for (offset, cell) in cells.enumerated() {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(offset + 1)) {
				terminal.rightDragForTesting(row: cell.row, column: cell.column)
			}
		}
	}

	var terminalGridForTesting: (rows: Int, columns: Int) {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count, let terminal = sessions[index].terminal else {
			return (0, 0)
		}
		return terminal.gridSizeForTesting
	}

	func terminalGeometryForTesting() -> String {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count, let terminal = sessions[index].terminal else {
			return "no terminal"
		}
		return terminal.geometryForTesting
	}

	func activeTerminalDirectoryForTesting() -> URL? {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count else { return nil }
		return sessions[index].terminal?.currentDirectoryForTesting
	}

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
				activate(sessions[index], focus: true)
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
	/// tmux's windows, when the strip is showing those rather than our own
	/// terminals.
	private var tmuxWindows: [TmuxMirror.Window] = []
	private var tmuxPoll: Timer?
	/// The session the tabs are currently showing, which is whatever the client
	/// is attached to rather than whatever it was started with.
	private var mirroredSession: String?

	/// Whether the strip is a view of tmux rather than a list of terminals.
	///
	/// Only with a session to mirror and a terminal attached to it: the mode is
	/// about one shell seen two ways, and without the shell there is nothing to
	/// see.
	private var mirrorsTmux: Bool {
		Settings.shared.strictTmux && Settings.shared.startsTmux && tmuxSession != nil
	}

	/// The name of this window's tmux session, when it should have one.
	///
	/// One per project: reopening a project comes back to the panes it was left
	/// with, and two projects do not share a shell.
	var tmuxSession: String? {
		didSet {
			guard tmuxSession != oldValue else { return }
			startMirroringTmuxIfWanted()
		}
	}

	/// Watches the session, so a window opened or renamed inside tmux shows up
	/// on the strip.
	///
	/// Polled rather than pushed: tmux will run a hook, but a hook has to reach
	/// back into this process somehow, and asking twice a second costs a
	/// millisecond of a shell nobody is waiting on.
	private func startMirroringTmuxIfWanted() {
		tmuxPoll?.invalidate()
		tmuxPoll = nil
		guard mirrorsTmux, tmuxSession != nil else {
			if !tmuxWindows.isEmpty {
				tmuxWindows = []
				rebuildColumns()
			}
			return
		}

		let poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
			self?.refreshTmuxWindows()
		}
		RunLoop.main.add(poll, forMode: .common)
		tmuxPoll = poll
		refreshTmuxWindows()
	}

	/// Looks again soon, when something on screen suggests tmux has moved.
	///
	/// Coalesced: a build's output is thousands of chunks and one question is
	/// enough for all of them.
	private func scheduleMirrorCheck() {
		guard mirrorsTmux, !mirrorCheckScheduled else { return }
		mirrorCheckScheduled = true
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
			self?.mirrorCheckScheduled = false
			self?.refreshTmuxWindows()
		}
	}

	private var mirrorCheckScheduled = false

	/// Asks tmux what it has now.
	///
	/// Also called the moment anything might have changed it — a tab clicked,
	/// output arriving — so the strip keeps up with a hand switching windows
	/// faster than twice a second.
	func refreshTmuxWindows() {
		guard mirrorsTmux, let configured = tmuxSession else { return }
		// The session the client is *looking at*, which `C-b w` changes: the
		// tabs should be what is on screen, not what the window was opened
		// with. The configured one is the fallback for the moment before the
		// client has attached.
		let tty = sessions.first?.terminal?.ttyName

		Task { @MainActor in
			var session = configured
			if let tty, let attached = await TmuxMirror.session(forClient: tty) {
				session = attached
			}
			if session != self.mirroredSession {
				self.mirroredSession = session
				self.tmuxWindows = []
			}
			let windows = await TmuxMirror.windows(inSession: session)
			// Nothing at all means tmux is still starting, or has gone: the
			// strip keeps what it had rather than blinking empty.
			guard !windows.isEmpty, windows != self.tmuxWindows else { return }
			self.tmuxWindows = windows
			self.rebuildColumns()
		}
	}

	/// Moves the highlight before tmux has answered.
	///
	/// A click that waits for a round trip through another process reads as a
	/// click that did not land — and it is the one thing here that can be known
	/// without asking, since we are the ones who asked for the switch.
	private func markMirroredWindowActive(_ index: Int) {
		guard tmuxWindows.contains(where: { $0.index == index }) else { return }
		tmuxWindows = tmuxWindows.map {
			TmuxMirror.Window(
				index: $0.index, name: $0.name, isActive: $0.index == index, command: $0.command
			)
		}
		rebuildColumns()
	}

	/// What the first terminal runs instead of a plain shell.
	private func startupCommand() -> (executable: String, arguments: [String])? {
		guard Settings.shared.startsTmux, let session = tmuxSession else { return nil }
		guard let tmux = Executables.locate("tmux") else { return nil }
		// `new -A` is "attach if it exists, make it if it does not", which is
		// exactly what reopening a project should do.
		return (executable: tmux, arguments: ["new", "-A", "-s", session])
	}

	/// The sessions the server has, to switch this terminal between them.
	///
	/// Where somebody would look for it: the tag says which session the tabs
	/// belong to, so the tag is where the others should be.
	private func showSessionMenu(from rect: NSRect, in column: Int) {
		guard let strip = columnViews.indices.contains(column) ? columnViews[column].strip : nil,
		      let tty = sessions.first?.terminal?.ttyName
		else { return }

		Task { @MainActor in
			let all = await TmuxMirror.sessions()
			let current = self.mirroredSession
			let menu = NSMenu()

			for summary in all {
				let item = NSMenuItem(
					title: "\(summary.name)  ·  \(summary.windowCount) window"
						+ (summary.windowCount == 1 ? "" : "s"),
					action: #selector(BottomPanel.switchToSession(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.representedObject = [summary.name, tty]
				item.state = summary.name == current ? .on : .off
				menu.addItem(item)
			}

			if !all.isEmpty { menu.addItem(.separator()) }
			let new = NSMenuItem(
				title: "New Session…",
				action: #selector(BottomPanel.createSessionFromMenu(_:)),
				keyEquivalent: ""
			)
			new.target = self
			new.representedObject = tty
			menu.addItem(new)

			menu.popUp(
				positioning: nil,
				at: NSPoint(x: rect.minX, y: rect.maxY + Theme.current.scaled(4)),
				in: strip
			)
		}
	}

	@objc private func switchToSession(_ sender: NSMenuItem) {
		guard let parts = sender.representedObject as? [String], parts.count == 2 else { return }
		Task {
			await TmuxMirror.switchClient(onTTY: parts[1], to: parts[0])
			self.refreshTmuxWindows()
		}
	}

	@objc private func createSessionFromMenu(_ sender: NSMenuItem) {
		guard let tty = sender.representedObject as? String else { return }

		let alert = NSAlert()
		alert.messageText = "New tmux session"
		alert.informativeText = "It is made in this project's directory and switched to."
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		field.placeholderString = "name"
		alert.accessoryView = field

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let name = field.stringValue.trimmingCharacters(in: .whitespaces)
			guard !name.isEmpty else { return }
			Task {
				await TmuxMirror.createSession(named: name, in: self.workingDirectory)
				await TmuxMirror.switchClient(onTTY: tty, to: name)
				self.refreshTmuxWindows()
			}
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	/// Reorders tmux's windows to match a dragged tab.
	///
	/// The position dragged past decides the side: dragging right puts the
	/// window after the one it landed on, dragging left puts it before — which
	/// is what the gap the tab was dropped into looked like.
	private func moveMirroredWindow(_ window: TmuxMirror.Window, from: Int, to: Int) {
		let clamped = max(0, min(tmuxWindows.count - 1, to))
		guard clamped != from, tmuxWindows.indices.contains(clamped) else { return }
		let target = tmuxWindows[clamped]
		let session = mirroredSession ?? tmuxSession ?? ""

		// Moved here first, so the strip does not wait for tmux to answer.
		var reordered = tmuxWindows
		reordered.remove(at: from)
		reordered.insert(window, at: clamped)
		tmuxWindows = reordered
		rebuildColumns()

		Task {
			await TmuxMirror.move(
				window: window.index,
				before: target.index,
				after: clamped > from,
				inSession: session
			)
			self.refreshTmuxWindows()
		}
	}

	/// The tmux window a strip position stands for, when the strip is a mirror.
	private func mirroredWindow(at index: Int, in column: Int) -> TmuxMirror.Window? {
		guard mirrorsTmux, column == 0, tmuxWindows.indices.contains(index) else { return nil }
		return tmuxWindows[index]
	}

	/// Puts the keyboard back in the terminal after a tab was clicked: the
	/// point of switching windows is to type in the new one.
	private func focusTerminal() {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count else { return }
		activate(sessions[index], focus: true)
	}

	@discardableResult
	func showTerminal() -> TerminalPane? {
		if sessions.isEmpty {
			return newTerminal()
		}
		activate(sessions[activeIndex ?? 0], focus: true)
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
		// The first terminal of a window can be told to run something instead
		// of a plain shell — `tmux new -A -s ideai`, for whoever lives in tmux.
		// Only the first: the ones opened afterwards are for the odd job that
		// should not join the session.
		let pane = TerminalPane(
			workingDirectory: directory,
			command: sessions.isEmpty ? startupCommand() : nil
		)
		let session = Session(title: title, kind: .terminal(pane))
		session.directory = directory
		wire(session)

		session.column = focusedColumn
		sessions.append(session)
		activate(session, focus: focus)
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
		activate(session, focus: true)
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

	/// Asked to find a function by name, for a frame somebody clicked.
	var onOpenSymbol: ((String) -> Void)?

	@discardableResult
	func showSearch(query: String? = nil) -> SearchPane? {
		guard let root = workingDirectory else { return nil }

		if let index = sessions.firstIndex(where: { if case .search = $0.kind { return true }; return false }),
		   case let .search(pane) = sessions[index].kind {
			activate(sessions[index], focus: false)
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
		activate(session, focus: false)
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
			if case .nativeRemote = start { return workingDirectory }
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
		panelSession.column = focusedColumn
		sessions.append(panelSession)
		activate(panelSession, focus: false)
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
		activate(session, focus: false)
		return .success(())
	}

	/// Puts an agent on a job that is not a review: fixing what a language
	/// server is complaining about.
	///
	/// No MCP server here. A review reports findings back for the panel to
	/// list; this one edits the file, which the agent does with its own tools,
	/// and the session stays open so the change can be talked about.
	func startAgent(title: String, prompt: String) -> Result<Void, ReviewStartError> {
		guard let root = workingDirectory else { return .failure(.noProject) }
		guard let executable = AgentLauncher.findClaudeExecutable() else {
			return .failure(.claudeNotFound)
		}

		let pane = TerminalPane(
			workingDirectory: root,
			command: (
				executable: executable,
				arguments: [prompt] + AgentLauncher.permissionArguments()
			)
		)
		let session = Session(title: title, kind: .terminal(pane))
		wire(session)
		sessions.append(session)
		activate(session, focus: true)
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
			// A window switched inside tmux redraws the screen, so output is
			// also the cue that the tab strip may be out of date.
			self?.scheduleMirrorCheck()
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

	/// Shows a pane in its own column and gives it the focus.
	private func activate(_ session: Session, focus: Bool) {
		guard sessions.contains(where: { $0 === session }) else { return }
		focusedColumn = session.column
		activeByColumn[session.column] = session

		rebuildColumns()
		placeholder.isHidden = true
		if focus, case .terminal = session.kind { session.terminal?.focus() }
		activeTerminalChanged()
	}

	/// Puts a pane on one side, with whatever was showing on the other.
	///
	/// Always two panes, including when the tab asked about is the one already
	/// showing — which is the tab somebody naturally reaches for. What goes
	/// beside it is whatever else is showing, or the pane used before this one,
	/// or a new terminal when the panel holds nothing else.
	private func putBeside(_ session: Session, on zone: TerminalTabDrag.Zone) {
		guard zone != .center else {
			activate(session, focus: true)
			return
		}
		let side = zone.insertsBefore ? 0 : 1
		let otherSide = 1 - side

		let other = sessions.first { $0 !== session && $0.column != session.column }
			?? previouslyActive.flatMap { previous in sessions.first { $0 === previous && $0 !== session } }
			?? sessions.last { $0 !== session }
			?? makeTerminalSession()

		session.column = side
		other.column = otherSide
		activeByColumn[side] = session
		activeByColumn[otherSide] = other
		focusedColumn = side

		rebuildColumns()
		placeholder.isHidden = true
		session.terminal?.focus()
		activeTerminalChanged()
	}

	/// Back to one column, with everything's tab in it.
	private func unsplit() {
		let showing = activeSession
		for session in sessions { session.column = 0 }
		activeByColumn = [0: showing ?? sessions.first].compactMapValues { $0 }
		focusedColumn = 0
		rebuildColumns()
	}

	/// What was in front before whatever is in front now.
	private weak var previouslyActive: Session?

	/// A terminal to put beside something, for a panel that holds nothing else.
	private func makeTerminalSession() -> Session {
		let pane = TerminalPane(workingDirectory: workingDirectory)
		let session = Session(title: "Local", kind: .terminal(pane))
		session.directory = workingDirectory
		wire(session)
		sessions.append(session)
		onTerminalsChanged?()
		return session
	}

	/// Builds the columns and puts each one's active pane in it.
	private func rebuildColumns() {
		// A column with no tabs is not a column. Everything falls back to one.
		if columnCount == 2, sessions(in: 0).isEmpty {
			for session in sessions { session.column = 0 }
		}
		let count = columnCount
		focusedColumn = min(focusedColumn, count - 1)

		if columnViews.count != count {
			columnsHost.subviews.forEach { $0.removeFromSuperview() }
			columnViews = (0..<count).map { makeColumn($0) }
			columnsSplit = nil

			let content: NSView
			if count == 1 {
				content = columnViews[0]
			} else {
				let split = ColumnSplitView()
				split.fraction = splitFraction
				split.isVertical = true
				split.dividerStyle = .thin
				for view in columnViews {
					view.translatesAutoresizingMaskIntoConstraints = true
					split.addArrangedSubview(view)
				}
				columnsSplit = split
				content = split
				watchDivider(split)
			}

			content.translatesAutoresizingMaskIntoConstraints = false
			columnsHost.addSubview(content)
			NSLayoutConstraint.activate([
				content.topAnchor.constraint(equalTo: columnsHost.topAnchor),
				content.bottomAnchor.constraint(equalTo: columnsHost.bottomAnchor),
				content.leadingAnchor.constraint(equalTo: columnsHost.leadingAnchor),
				content.trailingAnchor.constraint(equalTo: columnsHost.trailingAnchor),
			])
		}

		for (index, view) in columnViews.enumerated() {
			let list = sessions(in: index)
			var showing = activeByColumn[index]
			if showing == nil || !list.contains(where: { $0 === showing }) {
				showing = list.last
				activeByColumn[index] = showing
			}
			view.show(showing?.view)

			// In the mirrored mode the first column's strip is tmux's window
			// list. The terminal underneath it never changes — that is the
			// point: switching tabs is a message to tmux, not a teardown.
			let mirroring = mirrorsTmux && index == 0 && !tmuxWindows.isEmpty
			view.strip.mirroredSession = mirroring ? (mirroredSession ?? tmuxSession) : nil
			// Killing a tmux window can take real work with it — a build, an
			// ssh session, an editor with unsaved buffers — so it is not one
			// stray click away. The right-click menu still offers it.
			view.strip.showsCloseButtons = !mirroring

			if mirrorsTmux, index == 0, !tmuxWindows.isEmpty {
				view.strip.setItems(
					tmuxWindows.map { window in
						PanelTabItem(
							title: window.name,
							hasExited: false,
							isTerminal: true,
							symbol: "terminal",
							isShowing: window.isActive
						)
					},
					activeIndex: tmuxWindows.firstIndex { $0.isActive }
				)
				continue
			}

			view.strip.setItems(
				list.map { session in
					PanelTabItem(
						title: session.displayTitle,
						hasExited: session.hasExited,
						isTerminal: { if case .terminal = session.kind { return true } else { return false } }(),
						symbol: session.symbol,
						isShowing: session === showing
					)
				},
				activeIndex: list.firstIndex { $0 === showing }
			)
		}
		placeholder.isHidden = !sessions.isEmpty
	}

	/// How the width is shared, so it survives a rebuild.
	private var splitFraction: CGFloat = 0.5

	/// Remembers where the divider is put.
	private func watchDivider(_ split: NSSplitView) {
		NotificationCenter.default.addObserver(
			forName: NSSplitView.didResizeSubviewsNotification,
			object: split,
			queue: .main
		) { [weak self, weak split] _ in
			guard let split, split.bounds.width > 1,
			      let first = split.arrangedSubviews.first
			else { return }
			MainActor.assumeIsolated {
				self?.splitFraction = min(0.9, max(0.1, first.frame.width / split.bounds.width))
			}
		}
	}

	private func showDropTargets() {}

	private func hideDropTargets() {
		for view in columnViews { view.showPreview(nil) }
	}

	/// The point in this panel's coordinates, or nil when it is elsewhere.
	private func local(_ screenPoint: NSPoint) -> NSPoint? {
		guard let window, window.frame.contains(screenPoint) else { return nil }
		return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
	}

	/// Draws where a dragged tab would land as it moves.
	private func previewDrop(at screenPoint: NSPoint) {
		guard let point = local(screenPoint) else {
			hideDropTargets()
			return
		}
		for view in columnViews {
			let frame = view.content.convert(view.content.bounds, to: self)
			guard frame.contains(point) else {
				view.showPreview(nil)
				continue
			}
			let inside = view.content.convert(point, from: self)
			view.showPreview(TerminalTabDrag.zone(for: inside, in: view.content.bounds))
		}
	}

	/// Where a drag ended that nothing else took: a column, a strip, or a
	/// window of its own.
	///
	/// The pointer decides, rather than a view under the pane: a destination
	/// beneath a terminal is at the mercy of a hit test through whatever the
	/// program is drawing.
	private func finishDrag(_ session: Session, at screenPoint: NSPoint) {
		defer { hideDropTargets() }

		guard let point = local(screenPoint) else {
			tearOff(session, at: screenPoint)
			return
		}
		for view in columnViews {
			if view.content.convert(view.content.bounds, to: self).contains(point) {
				let inside = view.content.convert(point, from: self)
				let zone = TerminalTabDrag.zone(for: inside, in: view.content.bounds)
				if zone == .center {
					session.column = view.column
					activate(session, focus: true)
				} else {
					focusedColumn = view.column
					putBeside(session, on: zone)
				}
				return
			}
			if view.strip.convert(view.strip.bounds, to: self).contains(point) {
				// Into that column's tabs, wherever along them it was dropped.
				session.column = view.column
				activate(session, focus: true)
				return
			}
		}
	}

	/// A tab dropped onto the pane: shown alone, or put beside what is there.
	private func handleDrop(_ payload: TerminalTabDrag.Payload, zone: TerminalTabDrag.Zone) {
		// From somewhere else — a window it had been pulled out into. Take it
		// in first, then treat it as one of ours.
		if payload.panelID != panelID {
			guard let source = TerminalDragSources.source(for: payload.panelID),
			      let detached = source.detachTerminal(at: payload.index)
			else { return }
			adopt(detached, zone: zone)
			return
		}
		guard sessions.indices.contains(payload.index) else { return }
		drop(sessions[payload.index], zone: zone)
	}

	/// A pane dropped somewhere: shown where it landed, or put beside.
	private func drop(_ session: Session, zone: TerminalTabDrag.Zone) {
		switch zone {
		case .center: activate(session, focus: true)
		case .left, .right: putBeside(session, on: zone)
		}
	}

	/// Takes in a terminal that was dragged here from somewhere else.
	private func adopt(_ detached: DetachedTerminal, zone: TerminalTabDrag.Zone) {
		let session = Session(title: detached.title, kind: .terminal(detached.pane))
		session.directory = detached.directory
		session.isRenamed = detached.isRenamed
		session.displayTitle = detached.title
		session.column = focusedColumn
		wire(session)

		sessions.append(session)
		drop(session, zone: zone)
		placeholder.isHidden = true
		onTerminalsChanged?()
	}

	/// A tab dropped on a column's strip.
	///
	/// From the same column it is a reorder; from the other column, or from a
	/// window a terminal was pulled out into, it moves here — which is how a
	/// split is undone by dragging rather than by menu.
	private func dropOnStrip(_ payload: TerminalTabDrag.Payload, at position: Int, in column: Int) {
		// A dropped tab arrives here rather than through `onMove`, and a
		// mirrored one has no session to look up — which is why dragging one
		// looked as though it worked and then did nothing.
		if let window = mirroredWindow(at: payload.index, in: payload.column) {
			guard payload.panelID == panelID, payload.column == column else { return }
			// An insertion index counts the gaps; a position counts the tabs,
			// and the one being moved is not there any more.
			let target = position > payload.index ? position - 1 : position
			moveMirroredWindow(window, from: payload.index, to: target)
			return
		}

		if payload.panelID != panelID {
			guard let source = TerminalDragSources.source(for: payload.panelID),
			      let detached = source.detachTerminal(at: payload.index)
			else { return }
			focusedColumn = column
			adopt(detached, zone: .center)
			return
		}

		guard let session = session(at: payload.index, in: payload.column) else { return }
		if payload.column == column {
			move(from: payload.index, to: position, in: column)
			return
		}

		session.column = column
		place(session, at: position, in: column)
		activate(session, focus: true)
		onTerminalsChanged?()
	}

	/// Puts a session among the tabs of its column, at a place.
	private func place(_ session: Session, at position: Int, in column: Int) {
		guard let from = sessions.firstIndex(where: { $0 === session }) else { return }
		sessions.remove(at: from)

		let list = sessions(in: column)
		if position >= list.count {
			let after = list.last.flatMap { last in sessions.firstIndex { $0 === last } }
			sessions.insert(session, at: after.map { $0 + 1 } ?? sessions.count)
		} else if let index = sessions.firstIndex(where: { $0 === list[position] }) {
			sessions.insert(session, at: index)
		} else {
			sessions.append(session)
		}
	}

	/// Reorders the tabs within one column.
	private func move(from: Int, to: Int, in column: Int) {
		let list = sessions(in: column)
		guard list.indices.contains(from) else { return }
		let session = list[from]

		// Ordered by their place in the panel's own list, so moving a tab is
		// moving it there, among the tabs of its own column.
		guard let source = sessions.firstIndex(where: { $0 === session }) else { return }
		sessions.remove(at: source)

		let remaining = sessions(in: column)
		let clamped = max(0, min(to > from ? to - 1 : to, remaining.count))
		if clamped >= remaining.count {
			// After the last tab of this column, which may be before tabs of
			// the other one.
			let after = remaining.last.flatMap { last in sessions.firstIndex { $0 === last } }
			sessions.insert(session, at: after.map { $0 + 1 } ?? sessions.count)
		} else if let index = sessions.firstIndex(where: { $0 === remaining[clamped] }) {
			sessions.insert(session, at: index)
		} else {
			sessions.append(session)
		}

		rebuildColumns()
		onTerminalsChanged?()
	}

	/// Takes a terminal out of the panel and hands it over to be a window.
	private func tearOff(_ session: Session, at screenPoint: NSPoint) {
		guard let index = sessions.firstIndex(where: { $0 === session }),
		      let detached = detachTerminal(at: index)
		else { return }
		onTearOffTerminal?(detached, screenPoint)
	}

	/// Closes a pane, optionally without asking the panel to go away.
	///
	/// Replacing the only session would otherwise close the panel and open it
	/// again, which from the outside looks exactly like pressing debug having
	/// toggled it shut.
	private func close(_ session: Session, hidingWhenEmpty: Bool = true) {
		guard let index = sessions.firstIndex(where: { $0 === session }) else { return }
		switch session.kind {
		case let .review(pane, _): pane.shutdown()
		case let .debug(pane): pane.shutdown()
		case let .profiler(pane): pane.shutdown()
		default: session.terminal?.terminalView.terminateProcess()
		}
		session.view.removeFromSuperview()
		sessions.remove(at: index)
		for (column, showing) in activeByColumn where showing === session {
			activeByColumn[column] = nil
		}

		if sessions.isEmpty {
			activeByColumn = [:]
			focusedColumn = 0
			rebuildColumns()
			placeholder.isHidden = false
			if hidingWhenEmpty { onRequestHide?() }
			return
		}
		rebuildColumns()
		onTerminalsChanged?()
	}

	private func close(index: Int, hidingWhenEmpty: Bool = true) {
		guard sessions.indices.contains(index) else { return }
		close(sessions[index], hidingWhenEmpty: hidingWhenEmpty)
	}

	/// Renames a tab.
	///
	/// An empty name gives it back to the shell, which is the only way to undo
	/// a rename without knowing what the shell would have called it.
	private func rename(_ session: Session, to name: String) {
		let trimmed = name.trimmingCharacters(in: .whitespaces)
		if trimmed.isEmpty {
			session.isRenamed = false
			session.displayTitle = session.title
		} else {
			session.isRenamed = true
			session.displayTitle = trimmed
		}
		rebuildColumns()
		onTerminalsChanged?()
	}

	func rename(index: Int, to name: String) {
		guard sessions.indices.contains(index) else { return }
		rename(sessions[index], to: name)
	}

	/// The strip of the column in front, so the harness can run what its menu
	/// runs.
	var tabStripForTesting: PanelTabStrip? {
		columnViews.indices.contains(focusedColumn) ? columnViews[focusedColumn].strip : columnViews.first?.strip
	}

	/// Clicks a tab, for the capture harness.
	func selectTabForTesting(_ index: Int) {
		activate(sessions[index], focus: false)
	}

	/// Puts the first tab beside whatever is showing, as the menu does.
	func splitFirstBesideForTesting() {
		handleDrop(TerminalTabDrag.Payload(panelID: panelID, column: 0, index: 0), zone: .left)
	}

	/// The case somebody actually reaches for: the tab in front, told to sit
	/// beside. Exercises the menu's own path.
	func splitActiveBesideForTesting() {
		guard let session = activeSession,
		      let index = sessions(in: session.column).firstIndex(where: { $0 === session })
		else { return }
		tabStripForTesting?.onSplit?(index, .right)
	}

	/// Shows where a dropped tab would land, as the drag does. For the harness.
	func previewDropForTesting() {
		showDropTargets()
		columnViews.first?.showPreview(.right)
	}

	/// Puts the last terminal beside the first, as dragging its tab to the edge
	/// does. For the capture harness.
	func splitForTesting() {
		guard sessions.count >= 2 else { return }
		// The one that is not on screen, which is the case dragging a tab to the
		// edge is for.
		handleDrop(
			TerminalTabDrag.Payload(panelID: panelID, column: 0, index: sessions.count - 2),
			zone: .right
		)
	}

	/// Takes the terminal in front out into a window, as dragging its tab
	/// outside does. For the capture harness.
	func tearOffForTesting(at point: NSPoint) {
		guard let session = activeSession else { return }
		tearOff(session, at: point)
	}

	/// Renames whichever tab is in front, for the capture harness.
	func renameActiveForTesting(to name: String) {
		guard let activeIndex else { return }
		rename(index: activeIndex, to: name)
	}

	/// Opens the in-place editor and leaves it open, so a capture shows it.
	func beginRenameActiveForTesting() {
		guard let session = activeSession,
		      let index = sessions(in: session.column).firstIndex(where: { $0 === session })
		else { return }
		tabStripForTesting?.beginRenaming(index)
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

	/// Whether any plain terminal is open.
	var hasTerminals: Bool {
		sessions.contains { if case .terminal = $0.kind { return true }; return false }
	}

	/// Closes every plain terminal, for a window that is changing project.
	func closeTerminals() {
		for index in sessions.indices.reversed() {
			guard case .terminal = sessions[index].kind else { continue }
			close(index: index, hidingWhenEmpty: false)
		}
	}

	private func refreshTabs() {
		onActiveTerminalChanged?()
		rebuildColumns()
	}

	// MARK: - Commands

	func focusActive() {
		guard let activeIndex, sessions.indices.contains(activeIndex) else { return }
		sessions[activeIndex].terminal?.focus()
	}

	func applySettings() {
		placeholder.font = Theme.current.uiFont(12)
		for view in columnViews { view.applyThemeChange() }
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
	/// A terminal: the only kind somebody names, and the only kind that can go
	/// off into a window of its own.
	var isTerminal = false
	/// What it holds, drawn on the tab the way a file's icon is.
	var symbol = "terminal"
	/// On screen — which, when the pane is split, is more than one of them.
	var isShowing = false
}

/// The panel's content area, which a dragged terminal tab can be dropped on.
final class PanelContentView: NSView {
	var onDrop: ((TerminalTabDrag.Payload, TerminalTabDrag.Zone) -> Void)?
	/// Whether this panel wants a given tab at all.
	var acceptsDrag: ((TerminalTabDrag.Payload) -> Bool)?

	private var zone: TerminalTabDrag.Zone?

	/// Shows the preview without a drag, for the capture harness.
	func previewForTesting(_ zone: TerminalTabDrag.Zone) {
		previewZone(zone)
	}

	/// Draws the half a drop would land in, or nothing.
	func previewZone(_ zone: TerminalTabDrag.Zone?) {
		guard zone != self.zone else { return }
		self.zone = zone
		needsDisplay = true
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		registerForDraggedTypes([TerminalTabDrag.pasteboardType])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		update(with: sender)
	}

	override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
		update(with: sender)
	}

	private func update(with sender: any NSDraggingInfo) -> NSDragOperation {
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard),
		      acceptsDrag?(payload) ?? false
		else { return [] }

		let point = convert(sender.draggingLocation, from: nil)
		let zone = TerminalTabDrag.zone(for: point, in: bounds)
		if zone != self.zone {
			self.zone = zone
			needsDisplay = true
		}
		return .move
	}

	override func draggingExited(_ sender: (any NSDraggingInfo)?) {
		zone = nil
		needsDisplay = true
	}

	override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		defer {
			zone = nil
			needsDisplay = true
		}
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard),
		      acceptsDrag?(payload) ?? false, let zone
		else { return false }
		onDrop?(payload, zone)
		return true
	}

	/// The half it would land in, so a split is something you see before you
	/// commit to it.
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		guard let zone else { return }

		let rect = TerminalTabDrag.highlightRect(for: zone, in: bounds)
		Theme.current.gitModified.withAlphaComponent(0.12).setFill()
		rect.fill()
		Theme.current.gitModified.withAlphaComponent(0.7).setStroke()
		let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
		outline.lineWidth = 2
		outline.stroke()
	}
}

/// Compact tab strip with add and hide affordances.
final class PanelTabStrip: NSView {
	var onSelect: ((Int) -> Void)?
	var onClose: ((Int) -> Void)?
	/// A tab renamed in place. An empty name gives it back to the shell.
	var onRename: ((Int, String) -> Void)?
	/// A tab dropped back into this strip somewhere else.
	var onMove: ((Int, Int) -> Void)?
	/// A tab let go outside the window, which makes it a window.
	var onTearOff: ((Int, NSPoint) -> Void)?
	/// A drag of one of these tabs beginning and ending, so the panel can put
	/// its drop target up while it lasts.
	var onDragStarted: (() -> Void)?
	var onDragEnded: (() -> Void)?
	/// Where the pointer is during a drag, in screen coordinates.
	var onDragMoved: ((NSPoint) -> Void)?
	/// Where a drag ended that nothing else took, so the panel can decide.
	var onDragEndedAt: ((Int, NSPoint) -> Void)?
	/// A tab dropped into this strip, from anywhere: this column, the other
	/// one, or another window.
	var onDropTab: ((TerminalTabDrag.Payload, Int) -> Void)?
	/// Whether a tab from elsewhere is welcome here.
	var acceptsForeign: ((TerminalTabDrag.Payload) -> Bool)?
	/// Asked to put a tab beside what is showing, without a drag.
	var onSplit: ((Int, TerminalTabDrag.Zone) -> Void)?
	/// Asked to go back to one pane.
	var onUnsplit: (() -> Void)?
	/// Whether two panes are showing, so the menu can offer the way back.
	var isSplit: (() -> Bool)?
	/// Whether a tab may be dragged at all — a debugger cannot be.
	var canDrag: ((Int) -> Bool)?
	/// The panel this strip belongs to, so a drag is recognised as its own.
	var panelID = UUID()
	/// Which column of it this strip is.
	var column = 0
	/// Whether the panel's own controls belong here.
	///
	/// They do not in a torn-off terminal window: there is no panel to hide, no
	/// panel to maximise, and following the shell's project belongs to the
	/// window that has a project in it.
	var showsPanelControls = true { didSet { recomputeLayout(); needsDisplay = true } }
	/// Whether the + belongs here. It does in any strip that owns terminals.
	var showsAddButton = true { didSet { recomputeLayout(); needsDisplay = true } }
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

	/// The tmux session these tabs are the windows of, when they are.
	///
	/// Shown as a tag beside the panel's own controls: the tabs look like our
	/// tabs, and it should be visible at a glance that they are not — that
	/// closing one closes a tmux window, and that another client can move them.
	/// Whether a tab may be closed from the strip.
	///
	/// A mirrored tab is a tmux window, and killing one from a stray click on
	/// an ✕ can take real work with it — a build, an ssh session, an editor
	/// with unsaved buffers. The right-click menu still offers it, where the
	/// gesture is deliberate.
	var showsCloseButtons = true {
		didSet {
			guard showsCloseButtons != oldValue else { return }
			recomputeLayout()
			needsDisplay = true
		}
	}

	var mirroredSession: String? {
		didSet {
			guard mirroredSession != oldValue else { return }
			recomputeLayout()
			needsDisplay = true
		}
	}

	private var mirrorTagFrame: NSRect = .zero

	/// The tag was clicked, with where it is on screen so a menu can hang off
	/// it. The tag says which session these tabs belong to; being able to
	/// change it there is where somebody would look for it.
	var onMirrorTagClicked: ((NSRect) -> Void)?

	private var items: [PanelTabItem] = []
	private var activeIndex: Int?
	private var frames: [NSRect] = []
	private var addButtonFrame: NSRect = .zero
	private var hideButtonFrame: NSRect = .zero
	private var maximizeButtonFrame: NSRect = .zero
	private var followButtonFrame: NSRect = .zero
	private var hoveredIndex: Int?
	private var trackingArea: NSTrackingArea?
	private var pressedIndex: Int?
	private var pressOrigin: NSPoint = .zero
	private var draggedIndex: Int?
	private var dropCaret: Int?

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
			// The editor's own measurement: room for the icon, the name, and
			// the cross, and never so narrow that a name is all ellipsis.
			let text = (item.title as NSString).size(withAttributes: [.font: font]).width
			let width = max(
				Theme.current.scaled(96),
				padding * 2 + Theme.current.scaled(14) + Theme.current.scaled(6)
					+ ceil(text) + Theme.current.scaled(8) + closeSize
			)
			frames.append(NSRect(x: x, y: 0, width: ceil(width), height: bounds.height))
			x += ceil(width) + Theme.current.scaled(2)
		}
		addButtonFrame = showsAddButton
			? NSRect(x: x + Theme.current.scaled(4), y: 0, width: Theme.current.scaled(24), height: bounds.height)
			: .zero

		guard showsPanelControls else {
			hideButtonFrame = .zero
			maximizeButtonFrame = .zero
			followButtonFrame = .zero
			return
		}

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

		guard let session = mirroredSession else {
			mirrorTagFrame = .zero
			return
		}
		let label = mirrorTagText(for: session)
		let width = label.size().width + Theme.current.scaled(12)
		let height = Theme.current.scaled(16)
		mirrorTagFrame = NSRect(
			x: followButtonFrame.minX - Theme.current.scaled(8) - width,
			y: (bounds.height - height) / 2,
			width: width,
			height: height
		)
	}

	/// `tmux · session ⌄`, or just `tmux ⌄` when the name would crowd the strip.
	private func mirrorTagText(for session: String) -> NSAttributedString {
		let text = bounds.width > Theme.current.scaled(420) ? "tmux · \(session) ⌄" : "tmux ⌄"
		return NSAttributedString(string: text, attributes: [
			.font: Theme.current.uiFont(10, weight: .medium),
			.foregroundColor: Theme.current.gitModified,
		])
	}

	// MARK: - Renaming in place

	private var renameField: NSTextField?
	private var renamingIndex: Int?

	func beginRenaming(_ index: Int) {
		guard frames.indices.contains(index) else { return }
		endRenaming(commit: true)

		let field = CenteredTextField(string: items[index].title)
		field.font = font
		field.textColor = Theme.current.sidebarHeaderText
		field.backgroundColor = Theme.current.editorBackground
		field.drawsBackground = true
		field.isBordered = false
		field.isBezeled = false
		field.focusRingType = .none
		field.delegate = self
		// The height a line of this font actually needs, centred in the tab: a
		// field the height of the tab puts its text against the top.
		let height = ceil(font.ascender - font.descender + font.leading) + Theme.current.scaled(6)
		let tab = frames[index]
		field.frame = NSRect(
			x: tab.minX + Theme.current.scaled(4),
			y: tab.midY - height / 2,
			width: tab.width - Theme.current.scaled(8),
			height: height
		)
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
		pressedIndex = nil

		if addButtonFrame.contains(point) { onAdd?(); return }
		if hideButtonFrame.contains(point) { onHide?(); return }
		if maximizeButtonFrame.contains(point) { onToggleMaximize?(); return }
		if mirroredSession != nil, mirrorTagFrame.contains(point) {
			onMirrorTagClicked?(mirrorTagFrame)
			return
		}
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
		   items.indices.contains(index), items[index].isTerminal {
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
		if showsCloseButtons, closeRect.contains(point) {
			onClose?(index)
		} else {
			onSelect?(index)
			// Remembered rather than acted on: a press becomes a drag only if
			// the pointer travels, so selecting a tab stays a click.
			pressedIndex = index
			pressOrigin = point
		}
	}

	override func rightMouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let index = frames.firstIndex(where: { $0.contains(point) }),
		      items.indices.contains(index)
		else { return super.rightMouseDown(with: event) }

		let menu = NSMenu()
		func add(_ title: String, _ action: Selector) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.representedObject = index
			menu.addItem(item)
		}

		if items[index].isTerminal { add("Rename\u{2026}", #selector(renameFromMenu(_:))) }
		add("Put Beside, Left", #selector(splitLeftFromMenu(_:)))
		add("Put Beside, Right", #selector(splitRightFromMenu(_:)))
		if isSplit?() == true { add("Show One Only", #selector(unsplitFromMenu(_:))) }
		menu.addItem(.separator())
		// A window of its own is a terminal thing: a debugger belongs to the
		// window whose program it is stopped in.
		if items[index].isTerminal { add("Move to a Window", #selector(tearOffFromMenu(_:))) }
		add("Close", #selector(closeFromMenu(_:)))

		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}

	@objc private func renameFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		beginRenaming(index)
	}

	@objc private func splitLeftFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onSplit?(index, .left)
	}

	@objc private func splitRightFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onSplit?(index, .right)
	}

	@objc private func unsplitFromMenu(_ sender: NSMenuItem) { onUnsplit?() }

	@objc private func tearOffFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		let point = window?.frame.origin ?? .zero
		onTearOff?(index, NSPoint(x: point.x - 60, y: point.y + (window?.frame.height ?? 0) - 80))
	}

	@objc private func closeFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onClose?(index)
	}

	override func mouseDragged(with event: NSEvent) {
		guard let index = pressedIndex, index < frames.count else { return }
		let point = convert(event.locationInWindow, from: nil)
		guard hypot(point.x - pressOrigin.x, point.y - pressOrigin.y) > 6 else { return }
		guard canDrag?(index) ?? false else { return }

		pressedIndex = nil
		beginDrag(index: index, event: event)
	}

	private func beginDrag(index: Int, event: NSEvent) {
		guard let item = TerminalTabDrag.item(panelID: panelID, column: column, index: index)
		else { return }

		let dragItem = NSDraggingItem(pasteboardWriter: item)
		dragItem.setDraggingFrame(frames[index], contents: snapshot(of: index))

		draggedIndex = index
		onDragStarted?()
		let session = beginDraggingSession(with: [dragItem], event: event, source: self)
		// A terminal let go outside the window becomes a window, so sliding it
		// back to where it started would contradict what happens next.
		session.animatesToStartingPositionsOnCancelOrFail = false
	}

	private func snapshot(of index: Int) -> NSImage? {
		guard index < frames.count, index < items.count else { return nil }
		let rect = frames[index]
		guard rect.width > 1, rect.height > 1 else { return nil }

		let image = NSImage(size: rect.size)
		image.lockFocus()
		if let context = NSGraphicsContext.current {
			context.cgContext.translateBy(x: -rect.minX, y: 0)
			draw(item: items[index], in: rect, isActive: true, isHovered: false)
		}
		image.unlockFocus()
		return image
	}

	/// Where a dropped tab would land, as an index between tabs.
	func insertionIndex(at point: NSPoint) -> Int {
		for (index, frame) in frames.enumerated() where point.x < frame.midX {
			return index
		}
		return frames.count
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		// Where a dragged tab would go, drawn where the gap will be.
		if let caret = dropCaret {
			let x = caret < frames.count
				? frames[caret].minX - Theme.current.scaled(1)
				: (frames.last?.maxX ?? Theme.current.scaled(8)) + Theme.current.scaled(1)
			Theme.current.gitModified.setFill()
			NSRect(
				x: x - 1, y: Theme.current.scaled(4),
				width: 2, height: bounds.height - Theme.current.scaled(8)
			).fill()
		}

		for (index, item) in items.enumerated() where index < frames.count {
			draw(item: item, in: frames[index], isActive: index == activeIndex, isHovered: index == hoveredIndex)
		}

		if showsAddButton { drawGlyph(in: addButtonFrame, symbol: "plus") }
		guard showsPanelControls else { return }

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

		drawMirrorTag()
	}

	private func drawMirrorTag() {
		guard let session = mirroredSession, mirrorTagFrame.width > 0 else { return }

		let pill = NSBezierPath(
			roundedRect: mirrorTagFrame,
			xRadius: mirrorTagFrame.height / 2,
			yRadius: mirrorTagFrame.height / 2
		)
		Theme.current.gitModified.withAlphaComponent(0.14).setFill()
		pill.fill()

		let label = mirrorTagText(for: session)
		let size = label.size()
		label.draw(at: NSPoint(
			x: mirrorTagFrame.midX - size.width / 2,
			y: mirrorTagFrame.midY - size.height / 2
		))
	}

	private func draw(item: PanelTabItem, in rect: NSRect, isActive: Bool, isHovered: Bool) {
		drawEditorStyle(item: item, in: rect, isActive: isActive, isHovered: isHovered)
	}

	/// Drawn the way an editor tab is drawn.
	///
	/// The same shape, the same icon-then-name, the same accent under the one
	/// in front: a terminal is a tab like any other and there is no reason for
	/// the panel to have a style of its own.
	private func drawEditorStyle(
		item: PanelTabItem,
		in rect: NSRect,
		isActive: Bool,
		isHovered: Bool
	) {
		if isActive {
			Theme.current.editorBackground.setFill()
			rect.fill()
			Theme.current.gitModified.setFill()
			NSRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2).fill()
		} else if item.isShowing {
			// The other half of a split: on screen, but not the one the
			// keyboard is in.
			NSColor.white.withAlphaComponent(0.06).setFill()
			rect.fill()
		} else if isHovered {
			NSColor.white.withAlphaComponent(0.05).setFill()
			rect.fill()
		}

		if !isActive {
			Theme.current.separator.withAlphaComponent(0.6).setFill()
			NSRect(
				x: rect.maxX - 1, y: Theme.current.scaled(6),
				width: 1, height: rect.height - Theme.current.scaled(12)
			).fill()
		}

		var x = rect.minX + padding
		let iconSize = Theme.current.scaled(14)
		let tint = item.hasExited
			? Theme.current.gitIgnored
			: Theme.current.sidebarText.withAlphaComponent(isActive ? 0.95 : 0.7)
		Theme.symbol(item.symbol, size: 11 * Theme.current.scale, color: tint)?
			.drawFitted(in: NSRect(
				x: x, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize
			))
		x += iconSize + Theme.current.scaled(6)

		let color = item.hasExited
			? Theme.current.gitIgnored
			: (isActive ? Theme.current.sidebarHeaderText : Theme.current.sidebarText.withAlphaComponent(0.8))
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let label = NSAttributedString(string: item.title, attributes: [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
		])
		let size = label.size()
		let reserved = showsCloseButtons ? closeSize + Theme.current.scaled(6) : 0
		let limit = max(0, rect.maxX - padding - reserved - x)
		label.draw(in: NSRect(x: x, y: rect.midY - size.height / 2, width: limit, height: size.height))

		if showsCloseButtons, isActive || isHovered {
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

	private func drawPillStyle(item: PanelTabItem, in rect: NSRect, isActive: Bool, isHovered: Bool) {
		// Beside the focused one when the pane is split: both are on screen,
		// and a strip that marks only one of them makes the other look like it
		// belongs to some other tab.
		if item.isShowing, !isActive {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.05).setFill()
			path.fill()
		}

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


/// Dragging a terminal tab within its own strip, and out of it.
extension PanelTabStrip: NSDraggingSource {
	func draggingSession(
		_ session: NSDraggingSession,
		sourceOperationMaskFor context: NSDraggingContext
	) -> NSDragOperation {
		context == .withinApplication ? .move : []
	}

	/// Let go where nothing wanted it: outside the window, that means a window
	/// of its own.
	func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
		onDragMoved?(screenPoint)
	}

	/// Where the drag ended, when nothing took it.
	///
	/// The panel decides rather than a drop target: a terminal fills the pane
	/// it is in, and relying on a view under it to be offered the drop is
	/// relying on a hit test through whatever the program happens to be
	/// drawing. The pointer's position is not in doubt.
	func draggingSession(
		_ session: NSDraggingSession,
		endedAt screenPoint: NSPoint,
		operation: NSDragOperation
	) {
		let index = draggedIndex
		draggedIndex = nil
		dropCaret = nil
		needsDisplay = true
		onDragEnded?()

		guard operation == [], let index else { return }
		onDragEndedAt?(index, screenPoint)
	}
}

extension PanelTabStrip {
	func setUpTabDropping() {
		registerForDraggedTypes([TerminalTabDrag.pasteboardType])
	}

	override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		draggingUpdated(sender)
	}

	override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard),
		      payload.panelID == panelID || acceptsForeign?(payload) == true
		else { return [] }

		let point = convert(sender.draggingLocation, from: nil)
		let caret = insertionIndex(at: point)
		if caret != dropCaret {
			dropCaret = caret
			needsDisplay = true
		}
		return .move
	}

	override func draggingExited(_ sender: (any NSDraggingInfo)?) {
		dropCaret = nil
		needsDisplay = true
	}

	override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		defer {
			dropCaret = nil
			needsDisplay = true
		}
		guard let payload = TerminalTabDrag.payload(from: sender.draggingPasteboard) else { return false }
		let point = convert(sender.draggingLocation, from: nil)
		onDropTab?(payload, insertionIndex(at: point))
		return true
	}
}


/// A text field whose text sits in the middle of it.
///
/// A tab is taller than a line, and a field left to itself puts its text at
/// the top of the box — which beside the tabs either side of it reads as
/// crooked.
private final class CenteredTextField: NSTextField {
	override class var cellClass: AnyClass? {
		get { CenteredTextFieldCell.self }
		set { super.cellClass = newValue }
	}
}

private final class CenteredTextFieldCell: NSTextFieldCell {
	private func centered(_ rect: NSRect) -> NSRect {
		let height = ceil(font?.boundingRectForFont.height ?? rect.height)
		guard height < rect.height else { return rect }
		return NSRect(
			x: rect.minX + 3, y: rect.minY + (rect.height - height) / 2,
			width: rect.width - 6, height: height
		)
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: centered(rect))
	}

	override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
		super.edit(withFrame: centered(rect), in: view, editor: editor, delegate: delegate, event: event)
	}

	override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
		super.select(withFrame: centered(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
	}
}


/// A terminal can be dragged out of the panel into a window, and the panel is
/// where it goes back to.
extension BottomPanel: TerminalDragSource {
	func detachTerminal(at index: Int) -> DetachedTerminal? {
		guard sessions.indices.contains(index) else { return nil }
		let session = sessions[index]
		guard case let .terminal(pane) = session.kind else { return nil }

		sessions.remove(at: index)
		for (column, showing) in activeByColumn where showing === session {
			activeByColumn[column] = nil
		}
		pane.removeFromSuperview()

		rebuildColumns()
		if sessions.isEmpty { placeholder.isHidden = false }
		onTerminalsChanged?()

		return DetachedTerminal(
			pane: pane,
			title: session.displayTitle,
			isRenamed: session.isRenamed,
			directory: session.directory
		)
	}
}


/// A split view that shares its width the way it was last shared.
///
/// The position has to be set when there is a width to set it against. A panel
/// that has just been shown, or a column whose contents have just changed, has
/// not been laid out yet — and a position set against zero collapses a column
/// to nothing, which looks like a split that never happened.
private final class ColumnSplitView: NSSplitView {
	var fraction: CGFloat = 0.5
	private var placed = false

	override var dividerColor: NSColor { Theme.current.separator }
	override var dividerThickness: CGFloat { 1 }

	override func layout() {
		super.layout()
		guard !placed, bounds.width > 1, arrangedSubviews.count > 1 else { return }
		placed = true
		setPosition(bounds.width * fraction, ofDividerAt: 0)
	}
}


/// One side of the panel: a strip of tabs and the pane they show.
///
/// A panel splits the way the editor does — each side keeps its own tabs —
/// because one strip across two panes cannot say which side a tab belongs to,
/// and every question after that has to be answered by guessing.
@MainActor
final class PanelColumn: NSView {
	let strip = PanelTabStrip()
	let content = NSView()
	/// Drawn over the pane rather than behind it: a terminal fills its column,
	/// and a highlight under it is a highlight nobody sees.
	let preview = PanelContentView()
	let column: Int

	private var stripHeight: NSLayoutConstraint!

	init(column: Int) {
		self.column = column
		super.init(frame: .zero)

		for view in [strip, content, preview] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		// Nothing to hit: it is a drawing, and the drop is decided from the
		// pointer's own position.
		preview.isHidden = true
		stripHeight = strip.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))
		NSLayoutConstraint.activate([
			strip.topAnchor.constraint(equalTo: topAnchor),
			strip.leadingAnchor.constraint(equalTo: leadingAnchor),
			strip.trailingAnchor.constraint(equalTo: trailingAnchor),
			stripHeight,

			content.topAnchor.constraint(equalTo: strip.bottomAnchor),
			content.leadingAnchor.constraint(equalTo: leadingAnchor),
			content.trailingAnchor.constraint(equalTo: trailingAnchor),
			content.bottomAnchor.constraint(equalTo: bottomAnchor),

			preview.topAnchor.constraint(equalTo: content.topAnchor),
			preview.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			preview.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			preview.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	func applyThemeChange() {
		stripHeight.constant = Theme.current.scaled(30)
		strip.applyThemeChange()
	}

	/// Shows where a dropped tab would land, over the pane.
	func showPreview(_ zone: TerminalTabDrag.Zone?) {
		preview.isHidden = (zone == nil)
		preview.previewZone(zone)
		if zone != nil {
			// Above whatever the pane put there since the last drag.
			preview.removeFromSuperview()
			addSubview(preview, positioned: .above, relativeTo: nil)
			NSLayoutConstraint.activate([
				preview.topAnchor.constraint(equalTo: content.topAnchor),
				preview.leadingAnchor.constraint(equalTo: content.leadingAnchor),
				preview.trailingAnchor.constraint(equalTo: content.trailingAnchor),
				preview.bottomAnchor.constraint(equalTo: content.bottomAnchor),
			])
		}
	}

	/// Puts a pane in, taking whatever was there out.
	func show(_ view: NSView?) {
		guard content.subviews.first !== view else { return }
		content.subviews.forEach { $0.removeFromSuperview() }
		guard let view else { return }

		view.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(view)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: content.topAnchor),
			view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
		])
	}
}

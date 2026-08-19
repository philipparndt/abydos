import AppKit
import AbydosKit

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
			/// Everywhere a symbol is used. Beside search rather than in a
			/// window of its own, because it is the same checklist over a
			/// different question and it is read beside the code.
			case usages(UsagesPane)
			/// The backlog as a list and a board. A pane rather than a window
			/// because it is read beside the work, the way the search results
			/// are — the thing you glance at to see what is next and then go
			/// back to the editor.
			case backlog(BacklogPane)
			case debug(DebugPane)
			case profiler(ProfilerPane)
		}

		let title: String
		var displayTitle: String
		let kind: Kind
		var hasExited = false
		/// A name for this session that nothing else has and that outlives its
		/// position in the list.
		///
		/// The tab strip needs one: it remembers which tab its run starts at,
		/// and every tab is called `Local` until somebody renames it. Made once
		/// per session and never shown.
		let identity = UUID().uuidString
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
		/// Which thing this is the console of — a launch configuration, a make
		/// goal, `go test`. Nil for a plain terminal, which is not the console
		/// of anything and belongs to whoever opened it.
		var runKey: String?
		/// Told when this tab is closed, for a pane that something outside is
		/// still writing into — a devcontainer being pulled and built has a
		/// minutes-long head start on somebody changing their mind.
		var onClosed: (() -> Void)?

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
			case let .usages(pane): return pane
			case let .backlog(pane): return pane
			case let .debug(pane): return pane
			case let .profiler(pane): return pane
			}
		}

		/// Whether the program in this pane is still going.
		///
		/// Asked of the process rather than remembered from a callback: the
		/// flag is set by a handler that another one can replace, and a tab
		/// wearing "running" over `[process exited]` is exactly what that
		/// costs.
		var isStillRunning: Bool {
			// A debugger is a program somebody started too. Its tab wore
			// nothing while it was going, so the one pane you would want to
			// find in a panel full of them was the only one not saying so.
			if case let .debug(pane) = kind { return pane.isSessionActive }
			guard isRun else { return false }
			return terminal?.terminalView.isProcessRunning ?? false
		}

		/// The project this pane was started for.
		///
		/// A run and a debugger are about one project's sources. A window that
		/// follows its terminal can be looking at another one by the time
		/// somebody comes back to the pane, and then every file it points at —
		/// a stack frame, a path in the output — resolves against the wrong
		/// tree. Recorded so coming back to the pane can take the window with
		/// it.
		var projectRoot: URL?

		/// Whether this pane is a program somebody started, rather than a shell.
		///
		/// Worth telling apart: a run finishes, and while it has not, its tab
		/// is the one to look at.
		var isRun = false

		/// What this holds, for its tab.
		var symbol: String {
			switch kind {
			case .terminal:
				guard isRun else { return "terminal" }
				// A finished run keeps an icon of its own: it is still not a
				// shell, and its output is still worth coming back to.
				return isStillRunning ? "play.fill" : "stop.fill"
			case .review: return "sparkles"
			case .search: return "magnifyingglass"
			case .usages: return "link"
			case .backlog: return "checklist"
			case .debug: return "ladybug"
			case .profiler: return "gauge.with.needle"
			}
		}

		/// The terminal behind this session, if it has one.
		var terminal: TerminalPane? {
			switch kind {
			case let .terminal(pane): return pane
			case let .review(_, pane): return pane
			case .search, .usages, .debug, .profiler, .backlog: return nil
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

		// With tmux's windows on their own strip below, this one is built as
		// the attached terminal first and everything else after it — so a
		// position is the list's own index only while that terminal happens to
		// be first in the list too.
		//
		// It was, for as long as only the very first pane could be the one
		// attached to tmux. Once a terminal opened *after* something else could
		// be the attached one, every tab from there on answered for its
		// neighbour: clicking the first activated the second.
		if let terminal = mirroredTerminal,
		   mirrorsTmux, column == 0, !tmuxWindows.isEmpty,
		   Settings.shared.tmuxTabsAtBottom,
		   list.contains(where: { $0 === terminal }) {
			if index == 0 { return terminal }
			let others = list.filter { $0 !== terminal }
			let position = index - 1
			return others.indices.contains(position) ? others[position] : nil
		}

		return list.indices.contains(index) ? list[index] : nil
	}

	/// The pane in front, wherever the focus is.
	private var activeSession: Session? {
		activeByColumn[focusedColumn] ?? sessions(in: focusedColumn).last ?? sessions.last
	}

	/// How much of the shown terminal's height is not a whole row.
	///
	/// Nil when there is no terminal to be tidy about — a debugger or a
	/// profiler in the panel has no grid and no opinion about its height.
	var terminalHeightRemainder: CGFloat? {
		activeSession?.terminal?.terminalView.heightRemainder
	}

	private var activeIndex: Int? {
		guard let session = activeSession else { return nil }
		return sessions.firstIndex { $0 === session }
	}

	/// Forwarded when a review finding or a search result is activated.
	var onOpenFinding: ((URL, Int) -> Void)?
	/// The debugger's toolbar asking for the program to be started again, once
	/// it has finished. What to start is a launch configuration, which is the
	/// window's business rather than the panel's.
	var onRunAgain: (() -> Void)?
	var onDebugAgain: (() -> Void)?
	/// A pane that belongs to a project was brought forward.
	var onPaneNeedsProject: ((URL) -> Void)?
	/// A pane asking for another checkout to be opened as a project of its own
	/// — a backlog card whose item is being worked on in a worktree.
	var onOpenProject: ((URL) -> Void)?
	/// `abydos <file>` was typed in one of these terminals.
	var onOpenFileFromTerminal: ((TerminalOpenRequest) -> Void)?
	/// The chevron beside the + was pressed, with the view it is in and where in
	/// that view to hang the menu.
	var onRequestNewTerminalMenu: ((NSView, NSPoint) -> Void)?

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
		wireMirrorStrip(view.mirrorStrip)

		strip.panelID = panelID
		strip.setUpTabDropping()
		strip.onSelect = { [weak self] index in
			guard let self else { return }
			if let session = self.mirroredSession(at: index, in: column) {
				self.activate(session, focus: true)
				return
			}
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
			if let session = self.mirroredSession(at: index, in: column) {
				self.close(session)
				return
			}
			if let window = self.mirroredWindow(at: index, in: column) {
				Task {
					self.mirrorChangedLocally()
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
			// A + makes another of whatever the tabs beside it are. The tabs on
			// this strip are the panel's own panes — the terminal attached to
			// tmux among them, a debugger, a run — so this + makes a terminal,
			// and the + on tmux's strip below makes a tmux window.
			//
			// Both meanings have now been on this one button, one after the
			// other, and each was wrong the same way: the button was told about
			// tmux rather than about the tabs under it. First it put plain
			// shells into a strip whose windows were tmux's; then it made tmux
			// windows from the strip that holds everything except them.
			//
			// The one case where this + does make a window is when tmux's
			// windows *are* this strip's tabs — the single-strip layout, where
			// there is no strip below to press.
			Self.trace(
				"panel + column=\(column) mirrorsTmux=\(self.mirrorsTmux) "
					+ "tabsAtBottom=\(Settings.shared.tmuxTabsAtBottom) "
					+ "strict=\(Settings.shared.strictTmux) starts=\(Settings.shared.startsTmux) "
					+ "mirrored=\(self.mirroredSession ?? "nil") configured=\(self.tmuxSession ?? "nil")"
			)
			if self.mirrorsTmux, column == 0, !Settings.shared.tmuxTabsAtBottom,
			   let session = self.mirroredSession ?? self.tmuxSession {
				Self.trace("panel + -> tmux window (its windows are this strip's tabs)")
				self.addTmuxWindow(to: session)
				return
			}
			Self.trace("panel + -> plain terminal")
			self.focusedColumn = column
			self.newTerminal()
		}
		// The chevron beside it, which offers the kinds of terminal that are not
		// the ordinary one. What they are is the window's business rather than
		// the panel's — only the window knows whether this project has a
		// devcontainer — so the panel does no more than say where it was pressed.
		strip.showsAddMenu = true
		strip.onAddMenu = { [weak self, weak strip] point in
			guard let self, let strip else { return }
			self.focusedColumn = column
			self.onRequestNewTerminalMenu?(strip, point)
		}
		strip.onHide = { [weak self] in self?.onRequestHide?() }
		strip.onRename = { [weak self] index, name in
			guard let self else { return }
			if let session = self.mirroredSession(at: index, in: column) {
				self.rename(session, to: name)
				return
			}
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
			if self.mirroredSession(at: index, in: column) != nil { return true }
			// A mirrored tab is a tmux window: it can be dragged along the
			// strip, but not out into a window of its own or into another
			// column — tmux owns where it lives.
			if self.mirroredWindow(at: index, in: column) != nil { return true }
			return self.session(at: index, in: column) != nil
		}
		strip.onMove = { [weak self] from, to in
			guard let self else { return }
			// A tab that is not a tmux window keeps its own ordering, and does
			// not shuffle tmux's.
			if self.mirroredSession(at: from, in: column) != nil { return }
			if let moved = self.mirroredWindow(at: from, in: column) {
				self.moveMirroredWindow(moved, from: from, to: to)
				return
			}
			self.move(from: from, to: to, in: column)
		}
		strip.onTearOff = { [weak self] index, point in
			guard let self else { return }
			if let session = self.mirroredSession(at: index, in: column) {
				self.tearOff(session, at: point)
				return
			}
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
			// No chevron out here: what it offers is "a terminal in *this
			// project's* devcontainer", and a torn-off terminal window has no
			// project to answer for.
			view.strip.showsAddMenu = false
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

	/// The backlog pane if this window has one, without making it.
	///
	/// `showBacklog()` makes one on demand, which is right for a person clicking
	/// and wrong for anything asking a question — including the report that
	/// checks a switch, which would otherwise open a pane by looking at it.
	var existingBacklogPane: BacklogPane? {
		for session in sessions {
			if case let .backlog(pane) = session.kind { return pane }
		}
		return nil
	}

	/// The window moved to another project: tell the panes that are about one.
	///
	/// **Separate from `setWorkingDirectory` on purpose.** That is called with a
	/// *subproject scope* as well as with a project root, and a backlog is the
	/// repository's — one `.abydos/backlog`, one `openspec/`, both at the top —
	/// so hanging this off it would empty the board the moment somebody stepped
	/// into a subproject. Terminals want the scope; these panes want the project.
	func setProject(_ url: URL) {
		for session in sessions {
			if case let .backlog(pane) = session.kind { pane.setProject(url) }
		}
		existingSearchPane?.setProject(url)
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

	/// What the active terminal has on its screen, for a check that a command
	/// typed into it answered.
	var terminalTextForTesting: String {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count, let terminal = sessions[index].terminal else {
			return ""
		}
		return terminal.terminalViewForTesting.screenTextForTesting
	}

	func terminalGeometryForTesting() -> String {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count, let terminal = sessions[index].terminal else {
			return "no terminal"
		}
		return terminal.geometryForTesting
	}

	/// Where the panel's own strips have ended up inside it.
	///
	/// The number that matters is `gap`: how much of the panel is above its tab
	/// strip. It is zero whenever the panel sits at the bottom of the window,
	/// and the height the titlebar covers only while the panel has the whole
	/// window. Anything else is the band nobody asked for, and it is reported
	/// rather than photographed because a capture lays the view tree out before
	/// it draws — which is exactly the thing that hides this.
	func stripGeometryForTesting() -> String {
		guard let column = columnViews.first else { return "no columns" }
		let strip = column.convert(column.strip.frame, to: self)
		let mirror = column.convert(column.mirrorStrip.frame, to: self)
		return String(
			format: "gap=%.1f inset=%.1f panel=%.1f strip=%.1f@%.1f mirror=%.1f@%.1f maximized=%@",
			strip.minY, tabStripTop.constant, bounds.height,
			strip.height, strip.minY,
			column.mirrorStrip.isHidden ? 0 : mirror.height, mirror.minY,
			isMaximized ? "yes" : "no"
		)
	}

	func activeTerminalDirectoryForTesting() -> URL? {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count else { return nil }
		return sessions[index].terminal?.currentDirectoryForTesting
	}

	/// Asks where the terminal is, off the main thread, and reports it on it.
	///
	/// The asking is not cheap and it is not bounded. Under tmux it runs a tmux
	/// client and waits for it — a fork, an exec and a `waitUntilExit` that
	/// polls, which `ClaudeHookRunner` has measured at sixty-odd milliseconds a
	/// call — and `ProcessPipes.drain` will wait as long as four seconds when a
	/// language server has inherited the write end of the pipe, which is the
	/// very case its own note describes.
	///
	/// This is driven by `onOutput`, which fires on the echo of every keystroke,
	/// up to four times a second. Doing it on the main queue put a subprocess
	/// between a key being pressed and the letter appearing, on the same queue
	/// as the keystroke, the parse and the frame. Nothing about the answer needs
	/// that queue: it is two immutable numbers going in and a path coming back.
	func reportWorkingDirectory() {
		guard isFollowingProject else { return }
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count, let terminal = sessions[index].terminal else { return }

		DispatchQueue.global(qos: .utility).async { [weak self] in
			// The pty's descriptor and device name are fixed once it has
			// started, which is what makes asking from here safe.
			let directory = terminal.currentDirectoryForTesting
			DispatchQueue.main.async {
				guard let self, let directory else { return }
				let standardized = directory.standardizedFileURL
				guard standardized.path != self.lastReportedDirectory?.path else { return }
				self.lastReportedDirectory = standardized
				self.onWorkingDirectoryChanged?(directory)
			}
		}
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

	/// Asks the terminal in front what a key with Option held would send.
	func optionKeyForTesting(bare: String, composed: String) -> String {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count,
		      let terminal = sessions[index].terminal
		else { return "no terminal" }
		return terminal.terminalView.optionKeyForTesting(bare: bare, composed: composed)
	}

	/// Feeds the terminal in front a burst of frames.
	func burstForTesting(frames: Int) -> Int {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count,
		      let terminal = sessions[index].terminal
		else { return -1 }
		terminal.terminalView.burstForTesting(frames: frames)
		return frames
	}

	/// Presses keys by key code in the terminal in front.
	func deadKeyForTesting(presses: [(code: UInt16, shift: Bool)]) -> String {
		let index = activeIndex ?? 0
		guard index >= 0, index < sessions.count,
		      let terminal = sessions[index].terminal
		else { return "no terminal" }
		return terminal.terminalView.deadKeyForTesting(presses: presses)
	}

	/// Opens a shell, or focuses the existing one if there already is a terminal.
	/// tmux's windows, when the strip is showing those rather than our own
	/// terminals.
	private var tmuxWindows: [TmuxMirror.Window] = []
	private var tmuxPoll: Timer?
	/// The session the tabs are currently showing, which is whatever the client
	/// is attached to rather than whatever it was started with.
	private var mirroredSession: String?
	/// Whether a tmux client has ever been seen on this terminal's tty, so a
	/// client that has gone away can be told from one that has not arrived yet.
	private var hasAttachedOnce = false
	/// What tmux was last told about its status bar, and *heard* — the session,
	/// and whether the bar was to go. Nil until something has actually landed,
	/// so a command that went nowhere is retried rather than remembered as done.
	private var statusBarApplied: (session: String, hidden: Bool)?
	/// Polls since the bar was last checked against tmux rather than against
	/// what we believe we told it.
	private var statusBarPollsSinceCheck = 0

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
		// The cheap test first, and that ordering is the whole of it: `mirrorsTmux`
		// reads two preferences, this is called for every chunk that arrives from
		// a pty, and the work below is already coalesced to one question per tenth
		// of a second. Asked the other way round, a build's output paid for
		// thousands of `UserDefaults` reads to reach a `return` — 1,131 samples in
		// `scheduleMirrorCheck` and 1,101 in `mirrorsTmux` out of 61,655 in a fire
		// benchmark, with the preference machinery under them. The coalescing was
		// there; it was just behind the expensive half of the guard.
		//
		// `directoryCheckScheduled` beside it has the two the right way round
		// already, which is where this was noticed.
		guard !mirrorCheckScheduled, mirrorsTmux else { return }
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
	/// One question at a time, with another queued behind it at most.
	///
	/// The poll asks twice a second, output arriving asks again, and clicking a
	/// tab asks a third time — each of those used to start its own pair of
	/// `tmux` processes, and their answers came back in whatever order they
	/// finished in.
	private var mirrorRefreshInFlight = false
	private var mirrorRefreshWanted = false
	/// Bumped whenever this app changes tmux's windows itself, so an answer
	/// worked out before the change can be recognised and dropped.
	private var mirrorGeneration = 0

	/// Adds a window to the session these tabs are a view of.
	///
	/// The only thing either + does while the panel is mirroring tmux, and it
	/// cannot do anything else. Creating a window never needed a client of our
	/// own: `tmux new-window -t <session>` is answered by the server, and
	/// whether this app happens to be looking at that session is beside the
	/// point — so it is asked for first, always, with no condition in front of
	/// it that could quietly turn the press into a plain terminal instead.
	///
	/// Attaching survives in one case only: the server refusing, which by then
	/// means the session itself has gone — its last window closed, and with it
	/// the thing these tabs are a picture of. Making it again does need a
	/// client, and that is the whole of the exception.
	private func addTmuxWindow(to session: String) {
		Task {
			self.mirrorChangedLocally()
			let made = await TmuxMirror.newWindow(inSession: session)
			Self.trace("addTmuxWindow session=\(session) newWindow=\(made)")
			if made {
				self.refreshTmuxWindows()
				self.focusTerminal()
				return
			}
			// Not a terminal, whatever went wrong. This button belongs to
			// tmux's window list and the strip above it is the panel's own —
			// the two are separate things, and a button on one quietly adding
			// a tab to the other is the bug this kept turning into. Say so
			// instead; the session tag is where attaching lives.
			Toast.post(
				"tmux would not open a window",
				detail: "The session \(session) refused it. "
					+ "~/Library/Logs/Abydos/tmux.log has what it said.",
				kind: .warning
			)
			self.refreshTmuxWindows()
		}
	}

	/// A line in ~/Library/Logs/Abydos/tmux.log, written only when one of these
	/// buttons is pressed.
	///
	/// Twice now a fix for this has passed its test and failed on the desk it
	/// was written for, which means the test and the button are not doing the
	/// same thing. Rather than guess a third time: every press says which
	/// branch it took and what tmux answered.
	static func trace(_ message: String) {
		DiagnosticLog.write(message, to: "tmux")
	}

	/// Notes that the tabs have just been changed from this side.
	private func mirrorChangedLocally() {
		mirrorGeneration &+= 1
	}

	/// The tty tmux's client is on: the terminal that is actually attached.
	///
	/// Not "the first pane in the panel". That was the same thing for as long
	/// as only the very first one could be the attached one, and once it was
	/// not, this asked tmux about a search pane's tty — got nothing, concluded
	/// the client had detached, and emptied the window list. Which took the
	/// tmux tabs off the strip, took the green strip with them, and left the
	/// panel's own + as the only one on screen: the button that makes a plain
	/// terminal, where a tmux window was wanted.
	private var tmuxClientTTY: String? {
		mirroredTerminal?.terminal?.ttyName
			?? sessions.first { $0.terminal != nil }?.terminal?.ttyName
	}

	func refreshTmuxWindows() {
		guard mirrorsTmux, let configured = tmuxSession else { return }
		// Already asking. Answering twice from two overlapping questions is
		// what made a tab switch flicker: the click moved the highlight, an
		// answer from before the click moved it back, and the answer from
		// after moved it again.
		guard !mirrorRefreshInFlight else {
			mirrorRefreshWanted = true
			return
		}
		mirrorRefreshInFlight = true
		let generation = mirrorGeneration
		// The session the client is *looking at*, which `C-b w` changes: the
		// tabs should be what is on screen, not what the window was opened
		// with. The configured one is the fallback for the moment before the
		// client has attached.
		let tty = tmuxClientTTY

		Task { @MainActor in
			defer {
				self.mirrorRefreshInFlight = false
				// Something asked while this one was out. Ask once for all of
				// them rather than once each.
				if self.mirrorRefreshWanted {
					self.mirrorRefreshWanted = false
					self.refreshTmuxWindows()
				}
			}

			var session = configured
			var attached: String?
			if let tty { attached = await TmuxMirror.session(forClient: tty) }
			if let attached {
				session = attached
			} else if self.hasAttachedOnce {
				// There was a client on this tty and now there is not: somebody
				// detached, and what is in the pane is a plain shell again: the
				// tabs are for a session this terminal is no longer in.
				//
				// Every poll, not once: the session itself is still there, so
				// falling through would mirror it again a moment later and the
				// tabs would come back for a terminal that is not in it. What
				// ends this is a client appearing on this tty again.
				self.mirroredSession = nil
				if !self.tmuxWindows.isEmpty {
					self.tmuxWindows = []
					self.rebuildColumns()
				}
				return
			}
			if attached != nil { self.hasAttachedOnce = true }
			if session != self.mirroredSession {
				self.mirroredSession = session
				self.tmuxWindows = []
			}
			await self.applyStatusBarWish(to: session)

			let windows = await TmuxMirror.windows(inSession: session)
			// Nothing at all usually means tmux is still starting, and the
			// strip keeps what it had rather than blinking empty — but not
			// when the terminal itself has exited. Then the session really is
			// gone, and tabs for windows nobody can reach are worse than none.
			if windows.isEmpty, self.mirroredTerminal?.hasExited == true, !self.tmuxWindows.isEmpty {
				self.tmuxWindows = []
				self.rebuildColumns()
				return
			}
			// A tab was clicked, or a window made or closed, while this was
			// being answered: the answer describes tmux as it was before that,
			// and publishing it would undo what was just done for as long as
			// it takes to ask again.
			guard generation == self.mirrorGeneration else { return }
			guard !windows.isEmpty, windows != self.tmuxWindows else { return }
			self.tmuxWindows = windows
			StallWatch.mark("tmux tabs") { self.rebuildColumns() }
		}
	}

	/// Which tmux session the tabs are showing, for anything outside that needs
	/// to know whether a session's news belongs to this window.
	var mirroredTmuxSession: String? { mirrorsTmux ? (mirroredSession ?? tmuxSession) : nil }

	/// Closes every terminal tab, as clicking each ✕ would.
	///
	/// The state that had no way out of it: the panel still belongs to a tmux
	/// session, and nothing is attached to it any more.
	func closeTerminalTabsForTesting() {
		for index in sessions.indices.reversed() {
			guard case .terminal = sessions[index].kind else { continue }
			close(index: index, hidingWhenEmpty: false)
		}
	}

	/// Closes the last few, which is the gesture that was reported: somebody
	/// closing tabs one after another and the strip not laying out again.
	/// Closing *all* of them cannot show it — there is nothing left to lay out.
	@discardableResult
	func closeTerminalTabsForTesting(count: Int) -> String {
		var closed = 0
		for index in sessions.indices.reversed() where closed < count {
			guard case .terminal = sessions[index].kind else { continue }
			close(index: index, hidingWhenEmpty: false)
			closed += 1
		}
		return "closed \(closed)"
	}

	/// Presses the + on the first strip, for testing what it does.
	func addTabForTesting() {
		columnViews.first?.strip.pressAddForTesting()
	}

	/// Drags a tmux tab onto another position, as the mouse does.
	func dragTmuxTabForTesting(from: Int, to: Int) {
		guard tmuxWindows.indices.contains(from) else { return }
		moveMirroredWindow(tmuxWindows[from], from: from, to: to)
	}

	/// Presses the + on tmux's own strip, for testing what it does.
	func addTmuxWindowForTesting() {
		columnViews.first?.mirrorStrip.pressAddForTesting()
	}

	/// How many panes the panel is holding, so a press that was supposed to
	/// make a tmux window can be checked for having quietly made a tab.
	var paneCountForTesting: Int { sessions.count }

	/// The consoles that belong to something being run, and what each is the
	/// console of.
	var runConsolesForTesting: String {
		let consoles = sessions
			.filter { $0.isRun }
			.map { "\($0.displayTitle)[\($0.runKey ?? "-")]" }
		return "\(consoles.count): \(consoles.joined(separator: ", "))"
	}

	/// Clicks a tab on the panel's own strip and says what that actually
	/// brought to the front — the two being the same thing is the point.
	func clickPanelTabForTesting(_ index: Int) -> String {
		guard let strip = columnViews.first?.strip else { return "no strip" }
		let before = strip.itemsForTesting
		strip.pressSelectForTesting(index)
		let showing = activeByColumn[0]?.displayTitle ?? "nothing"
		return "strip: \(before)\n  clicked \(index) -> showing \"\(showing)\""
	}

	/// Puts a tab that cannot be closed on tmux's strip, without a tmux server.
	///
	/// The tab that must *not* light up under the pointer is a tmux window, and
	/// standing a server up inside a screenshot run to produce one is a great
	/// deal of machinery for a rounded rect — a `--run` that starts tmux does not
	/// even reach the mirror in the seconds such a run lasts. What is being
	/// checked is the state, and the state is an item whose `isClosable` is
	/// false on the strip that draws them.
	func seedUnclosableTabForTesting() {
		guard let column = columnViews.first else { return }
		column.strip.isMirroringTmux = false
		column.mirrorStrip.isMirroringTmux = true
		column.mirrorStrip.setItems(
			[
				PanelTabItem(
					title: "0:build", hasExited: false, isTerminal: true,
					isClosable: false, tmuxIndex: 0
				),
				PanelTabItem(
					title: "1:shell", hasExited: false, isTerminal: true,
					isClosable: false, tmuxIndex: 1
				),
			],
			activeIndex: 0
		)
		column.showsMirrorStrip = true
	}

	/// Closes a tab on tmux's own strip, as its menu does.
	func closeTmuxTabForTesting(_ index: Int) {
		columnViews.first?.mirrorStrip.pressCloseForTesting(index)
	}

	/// tmux's own strip: every tab on it is a tmux window, so the questions the
	/// mixed strip has to ask — is this a window, a session, something else —
	/// do not arise.
	private func wireMirrorStrip(_ strip: PanelTabStrip) {
		// Dragging a tab needs both halves: something to pick up, and somewhere
		// to drop it. The strip had the first — `canDrag` and `onMove` — but was
		// never registered for the drop, so a dragged tmux tab had nowhere to
		// land and the reorder that used to work quietly stopped.
		strip.panelID = panelID
		strip.column = 0
		strip.setUpTabDropping()
		// tmux's windows are tmux's: a tab from another panel or another window
		// cannot become one, so nothing foreign is taken here.
		strip.acceptsForeign = { _ in false }
		strip.onDropTab = { [weak self] payload, position in
			guard let self, payload.panelID == self.panelID else { return }
			guard self.tmuxWindows.indices.contains(payload.index) else { return }
			self.moveMirroredWindow(
				self.tmuxWindows[payload.index], from: payload.index, to: position
			)
		}

		strip.onSelect = { [weak self] index in
			guard let self, self.tmuxWindows.indices.contains(index) else { return }
			let window = self.tmuxWindows[index]
			self.markMirroredWindowActive(window.index)
			Task {
				await TmuxMirror.select(
					window: window.index,
					inSession: self.mirroredSession ?? self.tmuxSession ?? ""
				)
				self.refreshTmuxWindows()
			}
			self.focusTerminal()
		}
		strip.onAdd = { [weak self] in
			guard let self, let session = self.mirroredSession ?? self.tmuxSession else { return }
			Self.trace("tmux strip + session=\(session)")
			self.addTmuxWindow(to: session)
		}
		strip.onRename = { [weak self] index, name in
			guard let self, self.tmuxWindows.indices.contains(index) else { return }
			Task {
				await TmuxMirror.rename(
					window: self.tmuxWindows[index].index, to: name,
					inSession: self.mirroredSession ?? self.tmuxSession ?? ""
				)
				self.refreshTmuxWindows()
			}
		}
		strip.canDrag = { [weak self] index in self?.tmuxWindows.indices.contains(index) ?? false }
		strip.onMove = { [weak self] from, to in
			guard let self, self.tmuxWindows.indices.contains(from) else { return }
			self.moveMirroredWindow(self.tmuxWindows[from], from: from, to: to)
		}
		// Only from the menu, never from a ✕: killing a window takes whatever
		// is running in it — a build, an ssh session — and that should be a
		// thing somebody meant to do.
		strip.onClose = { [weak self] index in
			guard let self, self.tmuxWindows.indices.contains(index) else { return }
			let window = self.tmuxWindows[index]
			Task {
				self.mirrorChangedLocally()
				await TmuxMirror.killWindow(
					window.index, inSession: self.mirroredSession ?? self.tmuxSession ?? ""
				)
				self.refreshTmuxWindows()
			}
		}
		strip.onMirrorTagClicked = { [weak self] rect in
			self?.showSessionMenu(from: rect, in: 0)
		}
	}

	/// The window the tabs show as active, for deciding whether a session that
	/// has something to say is already the one being looked at.
	var activeTmuxWindow: Int? { tmuxWindows.first { $0.isActive }?.index }

	/// Brings a tmux window to the front, the way clicking its tab does.
	///
	/// For a toast about a session that wants an answer: the whole value of the
	/// message is being one click away from the thing it is about.
	func revealTmuxWindow(_ index: Int) {
		guard mirrorsTmux, let session = mirroredTmuxSession else { return }
		markMirroredWindowActive(index)
		Task {
			await TmuxMirror.select(window: index, inSession: session)
			self.refreshTmuxWindows()
		}
		focusTerminal()
	}

	/// Tells this session whether to draw its own status bar.
	///
	/// Once per session rather than on every poll: the option sticks, and saying
	/// it twice a second would be a `tmux` process twice a second for nothing.
	///
	/// Only once it has landed, though. The first attempt often goes out while
	/// the session is still being created — the poll starts before tmux does —
	/// and `set-option` against a session that is not there yet fails quietly.
	/// Recorded as done anyway, that left the bar on with nothing ever asking
	/// again, which is why turning the setting off and on was what fixed it: the
	/// only other thing that ever re-sent the command.
	///
	/// And asked afresh now and then, because a session option does not outlive
	/// its server. Anything that restarts tmux underneath brings the bar back
	/// without telling this app, and believing what we last said would leave it
	/// there for good.
	private func applyStatusBarWish(to session: String) async {
		let wanted = TmuxSettings.shouldHideStatusBar

		if let applied = statusBarApplied, applied == (session, wanted) {
			// Nothing to check when the bar is theirs again: `-u` restores
			// whatever their own config says, which may be any height.
			guard wanted else { return }
			statusBarPollsSinceCheck += 1
			guard statusBarPollsSinceCheck >= Self.statusBarRecheckPolls else { return }
			statusBarPollsSinceCheck = 0
			guard await TmuxMirror.statusLines(inSession: session) > 0 else { return }
		}

		statusBarPollsSinceCheck = 0
		guard await TmuxMirror.setStatusBar(!wanted, inSession: session) else { return }
		statusBarApplied = (session, wanted)
	}

	/// How many polls between asking tmux what its status bar is really doing.
	/// Twenty seconds at the poll's half-second, against a poll that already
	/// runs tmux every tick — cheap enough to be worth never being wrong.
	private static let statusBarRecheckPolls = 40

	/// Moves the highlight before tmux has answered.
	///
	/// A click that waits for a round trip through another process reads as a
	/// click that did not land — and it is the one thing here that can be known
	/// without asking, since we are the ones who asked for the switch.
	private func markMirroredWindowActive(_ index: Int) {
		guard tmuxWindows.contains(where: { $0.index == index }) else { return }
		mirrorChangedLocally()
		// Everything except which one is active is carried over. Rebuilding
		// these from four fields dropped each window's Claude status, so every
		// tab switch blanked the badges until the next poll put them back — a
		// blink, and a jump when the badges were what set the tab's width.
		tmuxWindows = tmuxWindows.map {
			TmuxMirror.Window(
				index: $0.index,
				name: $0.name,
				isActive: $0.index == index,
				command: $0.command,
				aiStatus: $0.aiStatus,
				silentFor: $0.silentFor
			)
		}
		rebuildColumns()
	}

	/// The command that attaches to one particular session, making it if it is
	/// not there — which is what `new -A` means.
	private func attachCommand(to session: String) -> (executable: String, arguments: [String])? {
		guard let tmux = Executables.locate("tmux") else { return nil }
		return (executable: tmux, arguments: TmuxMirror.attachArguments(to: session))
	}

	/// What the first terminal runs instead of a plain shell.
	private func startupCommand() -> (executable: String, arguments: [String])? {
		guard Settings.shared.startsTmux, let session = tmuxSession else { return nil }
		return attachCommand(to: session)
	}

	/// The sessions the server has, to switch this terminal between them.
	///
	/// Where somebody would look for it: the tag says which session the tabs
	/// belong to, so the tag is where the others should be.
	private func showSessionMenu(from rect: NSRect, in column: Int) {
		guard let strip = columnViews.indices.contains(column) ? columnViews[column].strip : nil
		else { return }
		// A dead terminal has no client to switch, and that is exactly when
		// somebody most needs this menu — picking a session then attaches a
		// new terminal to it instead of switching one that is not there.
		let tty = tmuxClientTTY ?? ""

		Task { @MainActor in
			let all = await TmuxMirror.sessions()
			let current = self.mirroredSession
			let menu = NSMenu()

			// Names in one column and counts in another, on a tab stop: the
			// names are of every length and a run of them with counts trailing
			// behind reads as a jumble.
			let paragraph = NSMutableParagraphStyle()
			paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 150)]

			for summary in all {
				let item = NSMenuItem(
					title: summary.name,
					action: #selector(BottomPanel.switchToSession(_:)),
					keyEquivalent: ""
				)
				let title = NSMutableAttributedString(
					string: summary.name,
					attributes: [
						.font: NSFont.systemFont(ofSize: 13),
						.paragraphStyle: paragraph,
					]
				)
				title.append(NSAttributedString(
					string: "\t\(summary.windowCount) window\(summary.windowCount == 1 ? "" : "s")",
					attributes: [
						.font: NSFont.systemFont(ofSize: 11),
						.foregroundColor: NSColor.secondaryLabelColor,
						.paragraphStyle: paragraph,
					]
				))
				item.attributedTitle = title
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
		// Nothing to switch when there is no client left: attach a new one.
		guard mirroredTerminal?.hasExited != true else {
			reattachTmux(to: parts[0])
			return
		}
		Task {
			await TmuxMirror.switchClient(onTTY: parts[1], to: parts[0])
			self.refreshTmuxWindows()
		}
	}

	/// Puts a live terminal back, attached to a tmux session.
	///
	/// The session behind the tabs can go while the app is looking at it —
	/// closing its last window destroys it, and the client we had attached
	/// exits with it, leaving a dead pane and a strip of tabs for something
	/// that is not there. Rather than making somebody close the terminal and
	/// open another, the + and the session tag both come here: the dead one is
	/// cleared away and a new one attaches, making the session if it has gone.
	func reattachTmux(to session: String) {
		// Not `hidingWhenEmpty`: closing the dead one empties the panel for a
		// moment, and a panel that hid itself there would take the new
		// terminal down with it — the button that was pressed would look like
		// it had closed the terminal rather than replaced it.
		if let dead = mirroredTerminal, dead.hasExited { close(dead, hidingWhenEmpty: false) }
		tmuxSession = session
		mirroredSession = session
		tmuxWindows = []
		newTerminal(rootedAt: workingDirectory, title: session, attachingTo: session)
		refreshTmuxWindows()
	}

	@objc private func createSessionFromMenu(_ sender: NSMenuItem) {
		let tty = sender.representedObject as? String ?? ""

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
			guard !tty.isEmpty, self.mirroredTerminal?.hasExited != true else {
				// No client to point anywhere: attach one, which makes the
				// session on the way in.
				self.reattachTmux(to: name)
				return
			}
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
		mirrorChangedLocally()
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

	/// The terminal attached to tmux, which the mirrored tabs stand for.
	///
	/// The first one: the mode attaches the first terminal of a window, and any
	/// opened afterwards are ordinary shells with tabs of their own.
	/// The terminal that is attached to tmux — the one the tabs below belong
	/// to.
	///
	/// Tracked rather than guessed at: "the first terminal in the list" was
	/// true until the tmux tab became closable and ordinary terminals could sit
	/// beside it, and after that the panel would happily mirror tmux onto a
	/// shell that had never heard of it.
	private var mirroredTerminal: Session? {
		guard let id = attachedTerminalID else { return nil }
		return sessions.first { ObjectIdentifier($0) == id }
	}
	private var attachedTerminalID: ObjectIdentifier?

	/// Whether a living terminal is attached to this window's tmux session.
	///
	/// False when it was closed, and false when its session was destroyed from
	/// inside and the client exited with it. Either way there is nothing
	/// attached, and the next terminal opened here is the one that should be.
	private var hasLiveTmuxTerminal: Bool {
		guard let mirrored = mirroredTerminal else { return false }
		return !mirrored.hasExited
	}

	/// The tmux window a strip position stands for, when the strip is a mirror.
	private func mirroredWindow(at index: Int, in column: Int) -> TmuxMirror.Window? {
		// Only where the two lists share a strip. With tmux's windows on their
		// own strip below, a position in the top one is a pane of the panel's
		// and nothing to do with tmux — the top tabs had been driving tmux,
		// because the items were split but the arithmetic behind the clicks
		// was not.
		guard !Settings.shared.tmuxTabsAtBottom else { return nil }
		guard mirrorsTmux, column == 0, tmuxWindows.indices.contains(index) else { return nil }
		return tmuxWindows[index]
	}


	/// What a strip position means: the tmux windows come first, then whatever
	/// else the column is holding.
	private func mirroredSession(at index: Int, in column: Int) -> Session? {
		guard !Settings.shared.tmuxTabsAtBottom else { return nil }
		guard mirrorsTmux, column == 0, !tmuxWindows.isEmpty else { return nil }
		let others = sessions(in: column).filter { $0 !== mirroredTerminal }
		let position = index - tmuxWindows.count
		return others.indices.contains(position) ? others[position] : nil
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
		// Never the session's own terminal, whatever else is open: attaching
		// puts you wherever tmux left the shell, and the directory asked for
		// here is the whole point of asking.
		newTerminal(rootedAt: directory, title: directory.lastPathComponent, joinsSession: false)
	}

	@discardableResult
	func newTerminal() -> TerminalPane? {
		newTerminal(rootedAt: workingDirectory, title: "Local")
	}

	/// A shell that is not this machine's — one inside the project's
	/// devcontainer — opened before there is anything to run in it.
	///
	/// A terminal tab rather than a run console: it is a shell somebody types
	/// in, not the output of something that was run. The title says which it is,
	/// because a tab that looks like every other tab and is somewhere else
	/// entirely is how somebody ends up building in the wrong place.
	///
	/// It is handed back before the shell exists because getting the container
	/// ready is a pull, a build and everything the file asks to have run once —
	/// minutes, the first time. The pane shows all of that and then becomes the
	/// shell itself; see `PreparingTerminal`, where the reason for it being one
	/// pane rather than two is written down.
	/// - Parameter select: whether the tab comes to the front as it is made.
	///   False for a pane nobody asked for — a devcontainer being brought up for
	///   the language servers — where putting it in front of the shell somebody is
	///   reading would be the disturbance the tab was meant to save them from. It
	///   is brought forward by `PreparingTerminal.reveal` if the wait turns out to
	///   be worth showing.
	func newPreparingTerminal(
		title: String, subject: String, takesFocus: Bool = true, select: Bool = true
	) -> PreparingTerminal {
		// Output only, so nothing can be typed at a shell that does not exist
		// yet, and no login shell starts behind what is being written.
		let pane = TerminalPane(readOnly: ())
		let session = Session(title: title, kind: .terminal(pane))
		session.directory = workingDirectory
		wire(session)

		session.column = focusedColumn
		sessions.append(session)
		if select { activate(session, focus: false) }
		onTerminalsChanged?()

		let preparing = PreparingTerminal(pane: pane, subject: subject, takesFocus: takesFocus)
		session.onClosed = { [weak preparing] in preparing?.paneWasClosed() }
		preparing.bringToFront = { [weak self, weak session] in
			guard let self, let session else { return }
			self.activate(session, focus: false)
		}
		preparing.closeTab = { [weak self, weak session] in
			guard let self, let session else { return }
			self.close(session)
		}
		return preparing
	}

	@discardableResult
	private func newTerminal(
		rootedAt directory: URL?,
		title: String,
		command: (executable: String, arguments: [String])? = nil,
		focus: Bool = true,
		attachingTo session: String? = nil,
		joinsSession: Bool = true
	) -> TerminalPane? {
		// A terminal of a window can be told to run something instead of a
		// plain shell — `tmux new -A -s ideai`, for whoever lives in tmux. One
		// of them, not all: the ones opened beside it are for the odd job that
		// should not join the session.
		//
		// Which one, though, is "there is not one attached" — not "this is the
		// first pane in the panel". Closing the tmux tab left the panel with an
		// attached terminal that no longer existed, and every + after that gave
		// another plain shell with no way back to an integrated one. A leftover
		// pane of any kind — a search, a debugger, a shell for one command —
		// was enough to make it permanent.
		let attaches = command == nil
			&& (session != nil
				|| (joinsSession && !hasLiveTmuxTerminal && startupCommand() != nil))
		let pane = TerminalPane(
			workingDirectory: directory,
			command: command
				?? session.map(attachCommand(to:))
				?? (attaches ? startupCommand() : nil)
		)
		// The one attached to tmux is called `tmux`, in every project. It was
		// called after the session — the project's name — which said nothing
		// about what the tab is, and made the panel's one fixed tab look like a
		// different tab everywhere.
		let session = Session(title: attaches ? "tmux" : title, kind: .terminal(pane))
		if attaches { attachedTerminalID = ObjectIdentifier(session) }
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
		environment: [String: String] = [:],
		reusing key: String? = nil
	) -> TerminalPane? {
		let assignments = environment
			.sorted { $0.key < $1.key }
			// Quoted, not merely escaped: a value with a space in it becomes a
			// second word to `env`, which then tries to run it.
			.map { "\($0.key)='\($0.value.replacingOccurrences(of: "'", with: "'\\''"))'" }
			.joined(separator: " ")
		let line = assignments.isEmpty ? command : "env \(assignments) \(command)"

		// The user's own shell, logged in and interactive — the same one a
		// terminal pane runs, and for the same reason. `/bin/sh -lc` reads
		// `/etc/profile` and nothing a version manager has ever written to, so
		// `make run` here failed on a `pnpm` that the same command finds when
		// typed one tab away.
		let shell = UserShell.invocation(for: line)
		return runCommand(
			title: title,
			executable: shell.executable,
			arguments: shell.arguments,
			workingDirectory: directory,
			reusing: key
		)
	}

	/// Runs a command in a pane. The basis for "Run" and for agent sessions.
	///
	/// - Parameter reusing: what this is the console of. A second run of the
	///   same thing takes over the tab the last one used, instead of leaving a
	///   row of finished consoles behind — the tab stays where it was in the
	///   strip, so the console for a configuration is always in the same place.
	///   Nil means a pane of its own every time, which is what an agent session
	///   or a one-off command wants.
	@discardableResult
	func runCommand(
		title: String,
		executable: String,
		arguments: [String],
		workingDirectory: URL? = nil,
		reusing key: String? = nil
	) -> TerminalPane? {
		// Where the old one was, so the new one lands there rather than at the
		// end of the strip. Somebody who has just pressed Run is looking at the
		// place the last run was.
		var slot: (index: Int, column: Int)?
		if let key, let index = sessions.firstIndex(where: { $0.runKey == key }) {
			slot = (index, sessions[index].column)
			// Whatever it was still doing, it was the previous run of this same
			// thing, and this is what "run it again" means. Not hidden when it
			// leaves the panel empty: the replacement is one line below.
			close(index: index, hidingWhenEmpty: false)
		}

		let pane = TerminalPane(
			workingDirectory: workingDirectory ?? self.workingDirectory,
			command: (executable: executable, arguments: arguments)
		)
		let session = Session(title: title, kind: .terminal(pane))
		session.isRun = true
		session.runKey = key
		// The panel's own root, not the parameter: a configuration's working
		// directory is often a package inside the project, and switching a
		// window to one of those would be switching it to something that is
		// not a project at all.
		session.projectRoot = self.workingDirectory

		if let slot {
			session.column = slot.column
			sessions.insert(session, at: min(slot.index, sessions.count))
		} else {
			sessions.append(session)
		}
		wire(session)
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

	/// The search pane if there already is one, without making one or moving the
	/// keyboard. `showSearch` does both, which is wrong for a script that has
	/// just put the keyboard in the result list on purpose.
	///
	/// Answered from the field rather than by walking the sessions since item
	/// 506: the pane goes on existing while it is showing under the project view
	/// or in a window of its own, where it has no tab here to be found by.
	private(set) var existingSearchPane: SearchPane?

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

	/// A row in a checklist pane — search or usages — was activated, with whether
	/// the keyboard goes with it.
	///
	/// Separate from `onOpenFinding`, which a review's findings and a backlog card
	/// use and which always means "take me there": a checklist row can also mean
	/// "show me this one, and leave the keyboard where it is".
	///
	/// The file, the row's match, and what showing it costs.
	///
	/// The whole match rather than the line it is on, since item 533: a match far
	/// along a long line is off the side of the editor's pane, and one forty
	/// characters wide that starts a column inside the edge is mostly off it. A
	/// line number says neither. It is a value type out of `AbydosKit` that the
	/// list is holding anyway, so carrying it costs nothing and spares the four
	/// hops between the row and the editor from agreeing about an order of loose
	/// integers.
	var onOpenResult: ((URL, SearchMatch, ResultChecklist.Intent) -> Void)?

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

	/// Told when the backlog has something to say that is not a pane's job to
	/// show — a move that failed, a worktree that could not be made.
	var onBacklogNotice: ((String, String?) -> Void)?

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


		let panelSession = Session(title: "Debug", kind: .debug(pane))
		// Bound to the sources it is stopped in.
		panelSession.projectRoot = root
		panelSession.column = focusedColumn
		sessions.append(panelSession)
		activate(panelSession, focus: false)
		return session
	}

	/// Forwarded debuggee output.
	var debugOutput: ((String) -> Void)?

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
		// `abydos <file>` in any pane, run or debug console included: the
		// request names a window, and this panel belongs to exactly one.
		terminal.terminalView.onOpenFile = { [weak self] request in
			self?.onOpenFileFromTerminal?(request)
		}
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
			// Except from tmux, which reports the session and window it is
			// showing — the tab for the client is called `tmux` and stays that
			// way, and what it is showing is the strip underneath it.
			guard ObjectIdentifier(session) != self.attachedTerminalID else { return }
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
		// Coming back to a run or a debugger takes the window back to the
		// project it belongs to — but only while the window is following its
		// terminal, which is when it wanders in the first place.
		// Only when somebody actually reached for it: panes are activated
		// again while a project is being restored, and following those back
		// would pull the window to wherever the last one came from.
		if focus, let root = session.projectRoot { onPaneNeedsProject?(root) }

		rebuildColumns()
		placeholder.isHidden = true
		if focus { giveKeyboard(to: session) }
		// A board is over files, and coming back to it is the moment to be sure
		// it still says what they do. It is watched while there is something to
		// watch, and the gap is the case that has no watcher yet: a project that
		// keeps one record and gains the other, where nothing under the folder
		// being watched has changed at all. The walk is off the main thread.
		if case let .backlog(pane) = session.kind { pane.reload() }
		activeTerminalChanged()
	}

	/// Puts the keyboard where this kind of pane wants it.
	///
	/// A usages list arrives to be walked with ↓, so it arrives with the
	/// keyboard. Nothing did this before — the list appeared with the keyboard
	/// still in the editor, where ↓ scrolls code — and it is deferred by one
	/// turn because the view has only just been put in the column and a
	/// responder set before that is set on a view with no window.
	///
	/// Search is here for item 506's sake rather than 470's: a search pane that
	/// is *moved* is one with rows in it already, and the rows are what somebody
	/// is looking at. Asking for search in the first place still lands in the
	/// field, which is a different call.
	private func giveKeyboard(to session: Session) {
		switch session.kind {
		case .terminal: session.terminal?.focus()
		case let .usages(pane): DispatchQueue.main.async { pane.focusList() }
		case let .search(pane): DispatchQueue.main.async { pane.focusList() }
		default: break
		}
	}

	/// Puts a pane on one side, with whatever was showing on the other.
	///
	/// Always two panes, including when the tab asked about is the one already
	/// showing — which is the tab somebody naturally reaches for. What goes
	/// beside it is whatever else is showing, or the pane used before this one,
	/// or a new terminal when the panel holds nothing else.
	///
	/// `focus` is what the caller asked for, and only one caller ever says no:
	/// ⇧⌘F, which wants the query field rather than the rows. A drag says
	/// nothing and gets the old answer.
	private func putBeside(
		_ session: Session, on zone: TerminalTabDrag.Zone, focus: Bool = true
	) {
		guard zone != .center else {
			activate(session, focus: focus)
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
		// Whatever this pane wants the keyboard for, not `session.terminal`.
		//
		// This is the line item 506's hardest case turned on. A results list has
		// no terminal, so `session.terminal?.focus()` did nothing at all — and
		// the terminal now showing in the other column had just been given the
		// keyboard by whatever put it there. A list put beside a terminal
		// therefore arrived with every key going to the shell: ↓ scrolled its
		// scrollback and ␣ typed a space at a prompt.
		//
		// Unless the caller said not to. Nothing else on this path takes the
		// keyboard, so a `false` leaves it where it was — which is what ⇧⌘F
		// needs, since it puts it in the query field a moment later and this
		// call, deferred by a turn, would otherwise take it straight back.
		if focus { giveKeyboard(to: session) }
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
				&& mirroredTerminal != nil
			view.strip.mirroredSession = mirroring ? (mirroredSession ?? tmuxSession) : nil
			// Where the two lists live is a setting; whether tmux's strip is on
			// screen is a matter of which tab is showing. Keeping those apart
			// matters: tying the layout to the visibility put tmux's windows
			// back in the top strip the moment somebody clicked another tab.
			let splitStrips = mirroring && Settings.shared.tmuxTabsAtBottom
			view.showsMirrorStrip = splitStrips && showing === mirroredTerminal
			if mirroring {
				// Two strips, or one, depending on where tmux's windows are
				// wanted. Along the bottom they are tmux's own: numbered,
				// green, under the terminal they belong to, and the top strip
				// carries a `tmux` tab beside the debugger and the profiler
				// like any other thing the panel is holding. In one strip they
				// are the tabs themselves, which is where they started.
				let others = list.filter { $0 !== mirroredTerminal }
				// No ✕ on a tmux window: killing one can take a build or an
				// ssh session with it, and that should not be one stray click
				// away. The right-click menu still offers it.
				let windows = tmuxWindows.map { window -> PanelTabItem in
					var item = PanelTabItem(
						title: window.name,
						hasExited: false,
						isTerminal: true,
						symbol: "terminal",
						isShowing: window.isActive && showing === mirroredTerminal,
						isClosable: false,
						aiStatus: window.shownStatus,
						tmuxIndex: splitStrips ? window.index : nil
					)
					// tmux's own number for the window, which is the name it
					// keeps while other clients move things around it.
					item.identity = "tmux:\(window.index)"
					return item
				}
				let rest = others.map { session -> PanelTabItem in
					var item = PanelTabItem(
						title: session.displayTitle,
						hasExited: session.hasExited,
						isTerminal: { if case .terminal = session.kind { return true } else { return false } }(),
						symbol: session.symbol,
						isShowing: session === showing,
						isRun: session.isRun,
						isRunning: session.isStillRunning
					)
					item.identity = session.identity
					return item
				}

				if splitStrips {
					// The terminal itself is one tab up top, called `tmux`, and
					// tmux's windows are the strip below it.
					//
					// The name is the same in every project. It was the session's
					// name, which made the one fixed tab of the panel read as a
					// different thing everywhere — `ideai` beside a debugger says
					// nothing about what the tab is, and which session it holds is
					// already written on the tag at the end of the strip below.
					// A name somebody typed still wins, as everywhere else.
					// Closable like anything else up here: closing this tab
					// closes a terminal that is attached to tmux, which costs
					// nothing — the session and every window in it carry on,
					// and the tab comes back attached to the same session.
					var terminal = PanelTabItem(
						title: mirroredTerminal?.isRenamed == true
							? (mirroredTerminal?.displayTitle ?? "tmux")
							: "tmux",
						hasExited: mirroredTerminal?.hasExited ?? false,
						isTerminal: true,
						symbol: "terminal",
						isShowing: showing === mirroredTerminal
					)
					// Which of these tabs is the one tmux is in: its icon is
					// green, the same green as the strip that appears under it.
					terminal.isTmuxAttached = true
					view.strip.setItems(
						[terminal] + rest,
						activeIndex: showing === mirroredTerminal
							? 0
							: others.firstIndex(where: { $0 === showing }).map { $0 + 1 }
					)
					view.mirrorStrip.mirroredSession = mirroredSession ?? tmuxSession
					view.mirrorStrip.setItems(
						windows, activeIndex: tmuxWindows.firstIndex { $0.isActive }
					)
					continue
				}

				let items = windows + rest
				let active: Int?
				if showing === mirroredTerminal {
					active = tmuxWindows.firstIndex { $0.isActive }
				} else if let position = others.firstIndex(where: { $0 === showing }) {
					active = tmuxWindows.count + position
				} else {
					active = nil
				}
				view.strip.setItems(items, activeIndex: active)
				continue
			}

			view.strip.setItems(
				list.map { session in
					PanelTabItem(
						title: session.displayTitle,
						hasExited: session.hasExited,
						isTerminal: { if case .terminal = session.kind { return true } else { return false } }(),
						symbol: session.symbol,
						isShowing: session === showing,
						isRun: session.isRun,
						isRunning: session.isStillRunning
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
	/// `keepingPane` is a tab going away with its pane still wanted — a results
	/// list on its way to another home. Without it, closing the tab is also
	/// forgetting the pane, which is what the ✕ means and what a move must not.
	private func close(
		_ session: Session, hidingWhenEmpty: Bool = true, keepingPane: Bool = false
	) {
		guard let index = sessions.firstIndex(where: { $0 === session }) else { return }
		if !keepingPane, case let .search(pane) = session.kind, pane === existingSearchPane {
			existingSearchPane = nil
		}
		switch session.kind {
		case let .review(pane, _): pane.shutdown()
		case let .debug(pane): pane.shutdown()
		case let .profiler(pane): pane.shutdown()
		default: session.terminal?.terminalView.terminateProcess()
		}
		session.onClosed?()
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

	/// How many columns the panel is showing, so a script can tell a list that
	/// is a tab in the strip from one that is beside a terminal.
	var columnCountForTesting: Int { columnCount }

	/// The strip of the column in front, so the harness can run what its menu
	/// runs.
	var tabStripForTesting: PanelTabStrip? {
		columnViews.indices.contains(focusedColumn) ? columnViews[focusedColumn].strip : columnViews.first?.strip
	}

	/// Whether the pane in front is still showing what is being got ready rather
	/// than being a shell somebody can type at.
	var activeTerminalShowsOutputOnly: Bool {
		activeSession?.terminal?.showsOutputOnly ?? false
	}

	/// What the strip is showing and what its overflow menu holds.
	var overflowReportForTesting: String {
		tabStripForTesting?.overflowReportForTesting ?? "no strip"
	}

	/// Chooses one of the hidden tabs, the way its menu entry would.
	func selectHiddenTabForTesting(_ position: Int) -> String {
		tabStripForTesting?.selectHiddenForTesting(position) ?? "no strip"
	}

	/// What the + and the chevron beside it answer to, for the harness.
	var addControlsForTesting: String {
		tabStripForTesting?.addControlsForTesting ?? "no strip"
	}

	/// Every tab, the one in front marked, and whether it is still a report
	/// rather than a shell — for the harness, which cannot photograph a hidden
	/// panel and is the only witness to 0444's part 4 there is.
	var tabsForTesting: String {
		guard !sessions.isEmpty else { return "(no tabs)" }
		return sessions.enumerated().map { index, session in
			let active = index == activeIndex
			let preparing = active && activeTerminalShowsOutputOnly
			return (active ? "*" : "") + session.displayTitle + (preparing ? " (preparing)" : "")
		}.joined(separator: " | ")
	}

	/// The last lines the pane in front has, so that what a build wrote into it
	/// can be read from outside.
	func activeTerminalTailForTesting(lines: Int) -> String {
		terminalTextForTesting
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
			.suffix(lines)
			.joined(separator: " ⏎ ")
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
	///
	/// And only ones with a shell in them. A pane that is a *report* — a launch
	/// log, a pod's output, an image being built — is a terminal by construction
	/// and has never run a process, so restoring it opens a shell in the
	/// project's directory called "Building rust-analyzer". That is the shape of
	/// the fault 0444 found by watching tabs accumulate to three, and 0459 would
	/// have added a second source of it: a build's pane is the one kind that
	/// never becomes a shell at all, so the tab somebody kept to read would come
	/// back every session as a prompt.
	func captureTerminals() -> [ProjectSession.OpenTerminal] {
		sessions.compactMap { session in
			guard case .terminal = session.kind, !session.hasExited else { return nil }
			guard session.terminal?.showsOutputOnly != true else { return nil }
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
			// The one that attached to tmux keeps the name it was just given —
			// `tmux` — unless the stored name was one somebody typed. What it
			// was called last time was whatever the client happened to report.
			guard terminal.isRenamed || session !== mirroredTerminal else { continue }
			session.displayTitle = terminal.name
		}
		refreshTabs()
	}

	/// tmux's own id for the window being shown, when one is.
	///
	/// Worth remembering across a launch: reopening a project into a window
	/// nobody chose, when the one they were in is still sitting there, is the
	/// sort of thing that makes somebody hunt through a tab strip for the work
	/// they left ten seconds ago.
	var currentTmuxWindowID: String? {
		let active = tmuxWindows.first(where: \.isActive)?.windowID
		return (active?.isEmpty ?? true) ? nil : active
	}

	/// Goes back to the window a project was left in, if it is still there.
	///
	/// Quietly when it is not: the server may have been restarted or the window
	/// closed, and neither is something the person did wrong. tmux's own choice
	/// stands in that case, which is the same as what happened before any of
	/// this was remembered.
	func restoreTmuxWindow(_ windowID: String) {
		guard let session = mirroredSession ?? tmuxSession, !windowID.isEmpty else { return }
		Task { @MainActor in
			guard await TmuxMirror.select(windowID: windowID, inSession: session) else { return }
			self.refreshTmuxWindows()
		}
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

	/// Redraws the tab strip. Called from outside when something a tab shows —
	/// whether its program is still running — has changed without the panel
	/// being told.
	func refreshTabs() {
		onActiveTerminalChanged?()
		rebuildColumns()
	}

	// MARK: - Commands

	func focusActive() {
		guard let activeIndex, sessions.indices.contains(activeIndex) else { return }
		sessions[activeIndex].terminal?.focus()
	}

	func applySettings() {
		// The status bar follows the switches: off while these tabs show the
		// same windows, back the moment they do not. Through the same path the
		// poll uses, so a switch flicked while tmux is not listening is retried
		// rather than being the one thing that was meant to fix it.
		if let session = mirroredSession ?? tmuxSession {
			Task { await applyStatusBarWish(to: session) }
		}

		// "Tabs are tmux's windows" switched: start or stop watching the
		// session, and rebuild the strip so the change is visible now rather
		// than at the next launch.
		startMirroringTmuxIfWanted()
		if !mirrorsTmux, !tmuxWindows.isEmpty {
			tmuxWindows = []
			mirroredSession = nil
		}
		rebuildColumns()

		placeholder.font = Theme.current.uiFont(12)
		for view in columnViews { view.applyThemeChange() }
		for session in sessions {
			switch session.kind {
			case let .review(pane, _): pane.applySettings()
			case let .search(pane): pane.applySettings()
			case let .usages(pane): pane.applySettings()
			case let .backlog(pane): pane.applySettings()
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
	/// Whether the ✕ belongs on it.
	///
	/// A tmux window is closed by killing it, which can take a build or an ssh
	/// session with it; everything the panel owns itself closes with a click,
	/// as it always did.
	var isClosable = true
	/// What the Claude session in this tmux window is doing.
	var aiStatus: TmuxMirror.AIStatus?
	/// tmux's own number for the window, drawn where the icon would be: it is
	/// what `C-b 2` selects, and it is the name everybody using tmux already
	/// has for that window.
	var tmuxIndex: Int?
	/// Whether this tab is the terminal tmux is attached to — the one whose
	/// windows are the strip below.
	var isTmuxAttached = false
	/// A program somebody started, and whether it is still going.
	///
	/// Running, the tab wears the same green the titlebar does — the two are
	/// saying the same thing, and the one in the corner of the eye is the tab.
	var isRun = false
	var isRunning = false
	/// What this tab is called by something more durable than its position.
	///
	/// The strip remembers which tab its run of drawn tabs starts at, and an
	/// index is worthless for that: the list is rebuilt whenever tmux's windows
	/// are re-read, and a window closed in another client shifts every number
	/// after it. Empty where nothing has said — a strip that cannot name its
	/// tabs simply starts at the first, which is what it did before.
	var identity: String = ""
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
final class PanelTabStrip: NSView, TabCloseHovering {
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
	/// Whether the + carries a chevron offering the other kinds of terminal.
	///
	/// The run control's play button already has this shape and this is the same
	/// gesture: the button does the ordinary thing, and the chevron beside it
	/// opens the ways of doing it that are wanted now and then. Off on tmux's own
	/// strip, where the + makes a tmux window and the menu's items would be
	/// answering a different question.
	var showsAddMenu = false { didSet { recomputeLayout(); needsDisplay = true } }
	/// The chevron was pressed, at a point in this view's own coordinates.
	var onAddMenu: ((NSPoint) -> Void)?
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
	var mirroredSession: String? {
		didSet {
			guard mirroredSession != oldValue else { return }
			recomputeLayout()
			needsDisplay = true
		}
	}

	private var mirrorTagFrame: NSRect = .zero

	/// Whether the keyboard is in the panel this strip belongs to.
	///
	/// The whole panel, not one terminal: a split has two of them and one tab
	/// stands for both. A torn-off terminal has no panel, and there everything
	/// in the window counts.
	private var hasKeyboardFocus: Bool {
		// Not conditional on the window being in front: leaving the app does
		// not move the cursor out of the pane it is in.
		guard let window, let responder = window.firstResponder as? NSView
		else { return false }

		var found: NSView? = self
		while let view = found, !(view is BottomPanel) { found = view.superview }
		guard let container = found ?? window.contentView else { return false }
		return responder === container || responder.isDescendant(of: container)
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		// Nothing tells a view when the first responder moves elsewhere, and the
		// line under the active tab is what says where it went.
		NotificationCenter.default.removeObserver(self, name: .keyboardFocusChanged, object: nil)
		NotificationCenter.default.addObserver(
			forName: .keyboardFocusChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.needsDisplay = true }
		}
	}

	/// The tag was clicked, with where it is on screen so a menu can hang off
	/// it. The tag says which session these tabs belong to; being able to
	/// change it there is where somebody would look for it.
	var onMirrorTagClicked: ((NSRect) -> Void)?

	private var items: [PanelTabItem] = []
	private var activeIndex: Int?
	private var frames: [NSRect] = []
	private var addButtonFrame: NSRect = .zero
	/// The chevron on the +, narrow and part of the same shape.
	private var addMenuFrame: NSRect = .zero
	/// The chevron at the trailing end offering the tabs that do not fit.
	private var overflowButtonFrame: NSRect = .zero
	/// Which tabs are drawn, and which are only in the menu.
	private var visibleRun: Range<Int> = 0..<0
	private var hiddenTabs: [Int] = []

	/// Which tab the run of drawn tabs starts at.
	///
	/// **Not a scroll position.** It changes for one reason — the active tab
	/// does not fit — and by the least that makes it fit; the wheel does not
	/// touch it and it is not remembered anywhere. That is the smallest thing
	/// that keeps the promise that the tab somebody just chose is a tab they can
	/// see, and a wheel can be hung off it later by whoever wants one.
	private var runStart = 0
	/// And which tab that is, by name rather than by number.
	///
	/// **An index survives nothing here.** This strip mirrors tmux's window
	/// list and is rebuilt whenever that is re-read, several times a second
	/// while a session is watched: a window closed in another client shifts
	/// every index after it, and a window moved keeps none. A tab that has gone
	/// puts the run back at the start, which is where it is when nothing has
	/// moved.
	private var runStartIdentity: String?
	private var hideButtonFrame: NSRect = .zero
	private var maximizeButtonFrame: NSRect = .zero
	private var followButtonFrame: NSRect = .zero
	private var hoveredIndex: Int?
	/// Whether the pointer is on the hovered tab's ✕ rather than the rest of it,
	/// which is the difference between "click to select" and "click to close" and
	/// so has to be visible before the click.
	private var hoveredClose = false
	private var trackingArea: NSTrackingArea?
	private var pressedIndex: Int?
	private var pressOrigin: NSPoint = .zero
	private var draggedIndex: Int?
	private var dropCaret: Int?
	private var spinnerTimer: Timer?
	private var spinnerPhase: CGFloat = 0

	/// Whether this strip belongs to tmux rather than to the panel.
	///
	/// tmux's own windows, drawn as tmux draws them: numbered rather than
	/// iconned — the number is what `C-b 2` takes you to, and an icon saying
	/// "terminal" on a strip of nothing but terminals says nothing — and in
	/// tmux's green, so it reads as the thing inside the terminal rather than
	/// as more of the app's own chrome.
	var isMirroringTmux = false {
		didSet {
			showsPanelControls = !isMirroringTmux
			recomputeLayout()
			needsDisplay = true
		}
	}

	/// The green a run wears while it is going, matching the titlebar.
	static var runningGreen: NSColor { .hex(0x4E7A4E) }

	/// What is legible on that bar.
	///
	/// Follows the bar rather than being picked alongside it. How far the green
	/// is dimmed is a number somebody will want to turn, and a theme's green can
	/// be any green at all, so the ink is decided from what the bar actually
	/// came out as: tmux's own black-on-green while the bar is light enough for
	/// it, and a bright one once it is not. Chosen either way, one of the two
	/// would eventually be ink the same colour as the thing it is written on.
	///
	/// Bright rather than merely paler than the bar: the tabs nobody is in are
	/// still a list somebody reads across, and a green only a little lighter
	/// than the green behind it is a list you have to lean in for.
	static var onTmuxGreen: NSColor {
		let dark = NSColor.hex(0x1D1F21)
		let pale = tmuxGreen.blended(withFraction: 0.86, of: .white) ?? .hex(0xF0F5E8)
		guard let bar = tmuxGreenBar.usingColorSpace(.sRGB) else { return dark }
		let luminance = 0.2126 * bar.redComponent
			+ 0.7152 * bar.greenComponent
			+ 0.0722 * bar.blueComponent
		// Well clear of where the bar actually sits, rather than at the point
		// the two inks are equally bad. At the dimming this ships with, the bar
		// lands at 0.42 — a threshold there would flip the whole strip to
		// near-black ink on the strength of a rounding difference in somebody's
		// theme green. Black only wins on a bar that is genuinely light.
		return luminance > 0.55 ? dark : pale
	}

	/// The green tmux paints its own status bar with, as this terminal renders
	/// it: the palette's green, so a theme that has one of its own is honoured.
	///
	/// Kept for the things that mean *this window*: the number, and the line
	/// under the tab you are in. At full strength it says one thing, and it can
	/// only go on saying it while it is not also the background.
	static var tmuxGreen: NSColor { TerminalPalette.named.indices.contains(2)
		? TerminalPalette.named[2]
		: .hex(0x8FBF5F)
	}

	/// The bar itself: the same green, sunk into the terminal's own background
	/// until it is a tone rather than a colour.
	///
	/// Full strength across the whole foot of the window, it was the brightest
	/// thing on screen — a bar that shouts for attention it does not want, and
	/// which nothing else in the app could then be louder than. Dimmed, it is
	/// still recognisably tmux's bar: the same hue, over the same background as
	/// the terminal above it, so it reads as part of the terminal rather than
	/// as part of the app.
	static var tmuxGreenBar: NSColor {
		tmuxGreen.blended(withFraction: 0.58, of: TerminalPalette.background) ?? tmuxGreen
	}

	override var isFlipped: Bool { true }

	/// Presses the + from a test, without a mouse.
	func pressAddForTesting() { onAdd?() }

	/// Whether the chevron is drawn and can be pressed.
	///
	/// tmux's strip keeps a bare +: its tabs are tmux's windows, and offering
	/// "a terminal in the devcontainer" from a strip that makes tmux windows
	/// would be one button answering two questions.
	private var offersAddMenu: Bool { showsAddButton && showsAddMenu && !isMirroringTmux }

	/// The two things a click beside the last tab can reach.
	private enum AddControl { case plus, chevron }

	/// Which of them a point is in, chevron first — it overlaps the + slightly
	/// so the pair reads as one shape, and the narrow half must win where they
	/// meet or it could never be pressed.
	private func addControl(at point: NSPoint) -> AddControl? {
		if offersAddMenu, addMenuFrame.contains(point) { return .chevron }
		if showsAddButton, addButtonFrame.contains(point) { return .plus }
		return nil
	}

	/// What a click at the middle of each of those reaches, for the harness.
	///
	/// A menu cannot be photographed while it is open, so what is checkable
	/// about a chevron is that it is there and that it is not the button beside
	/// it: pressing the + must still make a plain terminal.
	var addControlsForTesting: String {
		guard showsAddButton else { return "no +" }
		func name(_ control: AddControl?) -> String {
			switch control {
			case .plus?: return "plus"
			case .chevron?: return "chevron"
			case nil: return "nothing"
			}
		}
		let plus = name(addControl(at: NSPoint(x: addButtonFrame.midX, y: addButtonFrame.midY)))
		guard offersAddMenu else { return "plus->\(plus) chevron->none" }
		let chevron = name(addControl(at: NSPoint(x: addMenuFrame.midX, y: addMenuFrame.midY)))
		return "plus->\(plus) chevron->\(chevron)"
	}

	/// Clicks a tab by its position on the strip, without a mouse — which is
	/// the only way to catch a strip that answers for the tab next door.
	func pressSelectForTesting(_ index: Int) { onSelect?(index) }

	/// What the strip is showing, in order, with the active one marked.
	var itemsForTesting: String {
		items.enumerated()
			.map { "\($0.offset == activeIndex ? "*" : " ")\($0.element.title)" }
			.joined(separator: " | ")
	}

	/// Picks "Close" from a tab's menu, without a mouse.
	func pressCloseForTesting(_ index: Int) { onClose?(index) }

	/// Puts the pointer on a tab's ✕, or off the strip, and says what the strip
	/// now believes is under it.
	///
	/// Through `updateHover` rather than by setting the two flags: what is being
	/// checked is what the pointer does, and a harness that assigned the state
	/// directly would pass with the hit test wired to nothing — which is very
	/// nearly the bug this strip had.
	var tabCountForTesting: Int { items.count }

	@discardableResult
	func hoverCloseForTesting(_ index: Int?) -> String {
		if let frame = index.flatMap({ frames[safe: $0] }) {
			let close = closeRect(for: frame)
			updateHover(at: NSPoint(x: close.midX, y: close.midY))
		} else {
			clearHover()
		}
		let item = index.flatMap { items[safe: $0] }
		return "panel \(isMirroringTmux ? "(tmux)" : "      ")"
			+ " \"\(item?.title ?? "-")\" closable=\(item?.isClosable ?? true)"
			+ " -> tab=\(hoveredIndex.map(String.init) ?? "none") close=\(hoveredClose)"
	}

	func setItems(_ items: [PanelTabItem], activeIndex: Int?) {
		self.items = items
		self.activeIndex = activeIndex
		// Where the run was, by the name of the tab it started at rather than by
		// its number — see `runStartIdentity`. A tab that has gone puts it back
		// at the beginning.
		runStart = runStartIdentity.flatMap { identity in
			items.firstIndex { $0.identity == identity }
		} ?? 0
		recomputeLayout()
		showActiveTab()
		syncSpinner()
		needsDisplay = true
	}

	/// Moves the run, if it has to, so the active tab is one somebody can see.
	///
	/// Selecting a tab from the overflow menu and having it stay hidden is the
	/// same fault with a click in front of it.
	private func showActiveTab() {
		guard let active = activeIndex, items.indices.contains(active) else { return }
		let widths = items.map(width(for:))
		let room = tabRoom(overflowing: true)
		let gap = isMirroringTmux ? 0 : Theme.current.scaled(2)
		// Forward if the active tab does not fit, then back into any room going
		// spare at the trailing end. Closing tabs is the reported case: eight
		// left, room for all of them, and five still behind the chevron.
		let moved = TabOverflow.settled(
			start: TabOverflow.start(
				showing: active, widths: widths, from: runStart, available: room, spacing: gap
			),
			widths: widths,
			available: room,
			spacing: gap
		)
		guard moved != runStart else { return }
		runStart = moved
		runStartIdentity = items[safe: moved]?.identity
		recomputeLayout()
	}

	// MARK: - The spinner on a working tab

	/// Turning while at least one session is working, and stopped otherwise.
	///
	/// A still `⋯` says "something is happening here" no more convincingly than
	/// a full stop does; a turning one says it at a glance from across the
	/// room. The timer exists only while there is something to turn, so an
	/// idle app is an idle app.
	private func syncSpinner() {
		let wanted = items.contains { $0.aiStatus == .working }
		if wanted, spinnerTimer == nil {
			spinnerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
				guard let self else { return }
				self.spinnerPhase += 1
				// Only the badges: redrawing a whole strip twelve times a
				// second to turn three little marks would be silly.
				for (index, item) in self.items.enumerated()
				where item.aiStatus == .working && index < self.frames.count {
					self.setNeedsDisplay(self.badgeRect(in: self.frames[index]))
				}
			}
			// Turning has to carry on while a menu is open or a divider is
			// being dragged, which is exactly what the tracking mode is for.
			RunLoop.main.add(spinnerTimer!, forMode: .common)
		} else if !wanted {
			spinnerTimer?.invalidate()
			spinnerTimer = nil
		}
	}

	/// Where a tab's ✕ goes.
	///
	/// A method rather than a local inside `mouseDown`, which is where it used
	/// to be: the click knew where the cross was and nothing else did, so the
	/// pointer could not tell it was over one and the strip drew no hover.
	/// Three callers now — the click, the hover and the drawing — and one
	/// answer between them.
	private func closeRect(for tabRect: NSRect) -> NSRect {
		NSRect(
			x: tabRect.maxX - padding - closeSize,
			y: tabRect.midY - closeSize / 2,
			width: closeSize,
			height: closeSize
		)
	}

	/// Where a tab's status badge goes: where the ✕ would be, which a tmux tab
	/// does not have.
	private func badgeRect(in rect: NSRect) -> NSRect {
		NSRect(
			x: rect.maxX - padding - statusSize,
			y: rect.midY - statusSize / 2,
			width: statusSize,
			height: statusSize
		)
	}

	func applyThemeChange() {
		recomputeLayout()
		needsDisplay = true
	}

	private var font: NSFont { Theme.current.uiFont(11.5) }
	private var closeSize: CGFloat { Theme.current.scaled(12) }
	/// The Claude badge, the size of the ✕ it sits where.
	private var statusSize: CGFloat { Theme.current.scaled(12) }
	private var padding: CGFloat { Theme.current.scaled(10) }

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		recomputeLayout()
	}

	private func recomputeLayout() {
		frames.removeAll()

		// **The trailing controls are placed before the tabs now, not after.**
		// They used to be laid out from `bounds.width` backwards once the tabs
		// had already been given every point they asked for, which is how the
		// two came to be drawn through each other. What they leave is what the
		// tabs get, and a tab that does not fit in it is one the overflow
		// chevron offers rather than one nobody can reach.
		layoutTrailingControls()

		let widths = items.map(width(for:))
		let gap = isMirroringTmux ? 0 : Theme.current.scaled(2)

		// Measured twice, deliberately. Whether the chevron is there at all
		// depends on whether anything is hidden, and the chevron itself takes
		// room that can hide one more — so the first pass asks without it and
		// the second asks again with its width taken off. It cannot oscillate:
		// reserving room can only ever hide more, never fewer.
		let plain = TabOverflow.measure(
			widths: widths, start: runStart, available: tabRoom(overflowing: false), spacing: gap
		)
		let overflow = plain.isOverflowing
			? TabOverflow.measure(
				widths: widths, start: runStart, available: tabRoom(overflowing: true), spacing: gap
			)
			: plain
		visibleRun = overflow.visible
		hiddenTabs = overflow.hidden
		overflowButtonFrame = overflow.isOverflowing
			? NSRect(
				x: trailingControlsLeadingEdge - overflowButtonWidth,
				y: 0,
				width: overflowButtonWidth,
				height: bounds.height
			)
			: .zero

		// Hard against the left, as tmux's strip already was — there for a
		// reason of its own, since the active tab is a hole cut in the green
		// and green down its outer edge frames that one tab. The rest of the
		// panel starts at the edge too: the terminal below has no margin, and a
		// strip that begins eight points in sits on nothing.
		var x: CGFloat = 0
		for index in items.indices {
			// **A hidden tab keeps its place in `frames` and gets no rectangle.**
			// Everything that finds a tab — the click, the hover, the drop
			// caret, the rename field — asks `frames` by index, so shortening it
			// would renumber every tab after the first hidden one. An empty rect
			// contains no point, so those all say "not this one" without being
			// told about the run.
			guard visibleRun.contains(index) else {
				frames.append(.zero)
				continue
			}
			let width = widths[index]
			frames.append(NSRect(x: x, y: 0, width: width, height: bounds.height))
			// Tabs meet on tmux's strip. Anywhere else the gap between them is
			// the panel's background and reads as a gap; there it is the green
			// bar, and a sliver of it down the side of the tab you are in looks
			// like a frame around it.
			x += width + gap
		}
		addButtonFrame = showsAddButton
			? NSRect(x: x + Theme.current.scaled(4), y: 0, width: Theme.current.scaled(24), height: bounds.height)
			: .zero
		// Hard against the +, the width of the debug button's chevron, so the two
		// read as one control rather than as two buttons.
		addMenuFrame = offersAddMenu
			? NSRect(
				x: addButtonFrame.maxX - Theme.current.scaled(4),
				y: 0,
				width: Theme.current.scaled(14),
				height: bounds.height
			)
			: .zero
	}

	/// What one tab wants to be, which is the same question wherever it is asked.
	private func width(for item: PanelTabItem) -> CGFloat {
		// The editor's own measurement: room for the icon, the name, and
		// the cross, and never so narrow that a name is all ellipsis.
		let text = (item.title as NSString).size(withAttributes: [.font: font]).width
		// Room for the badge whether or not there is one to draw, on the
		// strip where badges come and go: a tab that widens the moment its
		// session starts working shoves every tab after it sideways, and
		// the one somebody was aiming at moves out from under the pointer.
		let badge = isMirroringTmux || item.aiStatus != nil
			? statusSize + Theme.current.scaled(5)
			: 0
		return ceil(max(
			Theme.current.scaled(96),
			padding * 2 + Theme.current.scaled(14) + Theme.current.scaled(6)
				+ ceil(text) + Theme.current.scaled(8) + closeSize + badge
		))
	}

	/// How much room the tabs have: everything up to the controls, less the +
	/// that follows them and the chevron that offers what does not fit.
	private func tabRoom(overflowing: Bool) -> CGFloat {
		var room = trailingControlsLeadingEdge
		if showsAddButton { room -= Theme.current.scaled(28) }
		if offersAddMenu { room -= Theme.current.scaled(14) }
		if overflowing { room -= overflowButtonWidth }
		return max(0, room)
	}

	/// Where the panel's own controls begin, which is where the tabs must stop.
	private var trailingControlsLeadingEdge: CGFloat {
		let leading = [mirrorTagFrame, followButtonFrame, maximizeButtonFrame, hideButtonFrame]
			.filter { $0.width > 0 }
			.map(\.minX)
			.min()
		return (leading ?? bounds.width) - Theme.current.scaled(8)
	}

	/// Wide enough for a chevron and a count of two digits.
	private var overflowButtonWidth: CGFloat { Theme.current.scaled(34) }

	private func layoutTrailingControls() {
		guard showsPanelControls else {
			hideButtonFrame = .zero
			maximizeButtonFrame = .zero
			followButtonFrame = .zero
			mirrorTagFrame = .zero
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
		let width = label.size().width + Theme.current.scaled(12) + mirrorChevronWidth
		let height = Theme.current.scaled(16)
		mirrorTagFrame = NSRect(
			x: followButtonFrame.minX - Theme.current.scaled(8) - width,
			y: (bounds.height - height) / 2,
			width: width,
			height: height
		)
	}

	/// `tmux · session`, or just `tmux` when the name would crowd the strip.
	private func mirrorTagText(for session: String) -> NSAttributedString {
		let text = bounds.width > Theme.current.scaled(420) ? "tmux · \(session)" : "tmux"
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
		updateHover(at: convert(event.locationInWindow, from: nil))
	}

	private func updateHover(at point: NSPoint) {
		let index = frames.firstIndex { $0.contains(point) }

		// The same question the click asks, and asked the same way: a tmux
		// window has no ✕ to be over, so the pointer never lights one up there.
		let overClose = index.map { index in
			(items[safe: index]?.isClosable ?? true) && closeRect(for: frames[index]).contains(point)
		} ?? false

		if index != hoveredIndex || overClose != hoveredClose {
			hoveredIndex = index
			hoveredClose = overClose
			needsDisplay = true
		}
	}

	override func mouseExited(with event: NSEvent) {
		clearHover()
	}

	private func clearHover() {
		hoveredIndex = nil
		hoveredClose = false
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		pressedIndex = nil

		switch addControl(at: point) {
		case .plus?: onAdd?(); return
		case .chevron?: onAddMenu?(NSPoint(x: addButtonFrame.minX, y: bounds.maxY)); return
		case nil: break
		}
		if overflowButtonFrame.width > 0, overflowButtonFrame.contains(point) {
			showOverflowMenu()
			return
		}
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

		guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return }
		let closable = items.indices.contains(index) ? items[index].isClosable : true

		// **The cross is asked about before the click count is.** Closing four
		// terminals means four clicks in the same corner of the screen, and the
		// tabs shuffle left under the pointer as they go — so the second, third
		// and fourth arrive inside the double-click interval and AppKit reports
		// them as a double click. Renaming came first here, so the second press
		// on a close button opened a rename field on whichever tab had just slid
		// into that place, and the terminal somebody meant to close was still
		// there with its name selected.
		//
		// A press on a cross is a close whatever the click count. Nobody has
		// ever meant to rename a tab by hitting the one control on it that is
		// not its name.
		if closable, closeRect(for: frames[index]).contains(point) {
			onClose?(index)
			return
		}

		// Double-clicking a tab renames it, in place: the name is a label on a
		// tab, and typing it anywhere else means finding the tab again after.
		if event.clickCount == 2, items.indices.contains(index), items[index].isTerminal {
			beginRenaming(index)
			return
		}

		onSelect?(index)
		// Remembered rather than acted on: a press becomes a drag only if
		// the pointer travels, so selecting a tab stays a click.
		pressedIndex = index
		pressOrigin = point
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

		if isMirroringTmux {
			// A tmux window is not one of the panel's panes: it cannot be put
			// beside anything here or torn into a window of its own, and the
			// only two things that make sense are its name and its life.
			add("Rename\u{2026}", #selector(renameFromMenu(_:)))
			menu.addItem(.separator())
			add("Kill Window", #selector(closeFromMenu(_:)))
			NSMenu.popUpContextMenu(menu, with: event, for: self)
			return
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
		// tmux's strip is green from end to end, not a green tab here and
		// there on the app's own background: the bar across the foot of the
		// screen is the thing everybody recognises. Dimmed, though — the shape
		// is what is recognised, and full green over that width was the
		// loudest thing in the window.
		(isMirroringTmux ? Self.tmuxGreenBar : Theme.current.sidebarBackground).setFill()
		bounds.fill()
		if !isMirroringTmux {
			Theme.current.separator.setFill()
			NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
		}

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

		// **A hidden tab has no rectangle, and must not be drawn into it.** An
		// empty frame is `.zero`, whose origin is the top-left corner of the
		// strip — so every tab scrolled out of the run painted its icon there,
		// stacked behind the first visible one. That is the clutter reported at
		// the start of the strip.
		for (index, item) in items.enumerated()
		where index < frames.count && !frames[index].isEmpty {
			draw(item: item, in: frames[index], isActive: index == activeIndex, isHovered: index == hoveredIndex)
		}

		if showsAddButton {
			drawGlyph(in: addButtonFrame, symbol: "plus", tint: isMirroringTmux ? Self.onTmuxGreen : nil)
		}
		if offersAddMenu {
			// Smaller and dimmer than the +, the way the chevron beside the
			// ladybird is: it is part of that button, not another one.
			drawGlyph(
				in: addMenuFrame, symbol: "chevron.down", points: 9, tint: Theme.current.gitIgnored
			)
		}
		guard showsPanelControls else { return }

		// **Opaque, because tabs are allowed to run underneath.** The frames are
		// laid out left to right at whatever width each name needs and nothing
		// stops them reaching the trailing edge, while these controls are placed
		// backwards from it — so with a dozen terminals open the session tag and
		// the three buttons were drawn over tab names with both still legible
		// through each other. The editor's tab bar settled this for itself
		// (`drawPreviewControl`) and the answer is the same one: a tab's last few
		// characters matter less than the controls staying readable and
		// reachable.
		drawControlsBackground()
		drawOverflowButton()

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

	/// What the strip is showing and what it is holding back.
	///
	/// The entries are the menu's own titles, built the same way, so a driven
	/// run asserts on what somebody would read rather than on a picture of it.
	var overflowReportForTesting: String {
		let shown = visibleRun.count
		guard !hiddenTabs.isEmpty else { return "\(items.count) tabs, all \(shown) shown" }
		let entries = hiddenTabs.compactMap { index in
			items[safe: index].map { overflowTitle(for: $0, at: index) }
		}
		return "\(items.count) tabs, \(shown) shown, \(hiddenTabs.count) hidden: "
			+ entries.joined(separator: " | ")
	}

	/// Chooses a hidden tab the way its menu entry would, so what happens next
	/// — the run moving to show it — can be looked at.
	func selectHiddenForTesting(_ position: Int) -> String {
		guard hiddenTabs.indices.contains(position) else { return "no hidden tab \(position)" }
		let index = hiddenTabs[position]
		onSelect?(index)
		return "chose tab \(index)"
	}

	/// The tabs there was no room for, offered as a menu.
	///
	/// Only the hidden ones. A list of everything is a tab switcher, which is a
	/// different feature with a different gesture — and it would put the tab
	/// somebody is already looking at into a menu of things they cannot see.
	private func showOverflowMenu() {
		guard !hiddenTabs.isEmpty else { return }
		let menu = NSMenu()
		for index in hiddenTabs {
			guard let item = items[safe: index] else { continue }
			let entry = NSMenuItem(
				title: overflowTitle(for: item, at: index),
				action: #selector(selectFromOverflow(_:)),
				keyEquivalent: ""
			)
			entry.target = self
			entry.representedObject = index
			entry.state = index == activeIndex ? .on : .off
			menu.addItem(entry)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: overflowButtonFrame.minX, y: bounds.maxY),
			in: self
		)
	}

	/// What a hidden tab is called in the menu.
	///
	/// **Not just its name**, and this is the part of the change that answers
	/// the report rather than the fault: sixteen terminals are sixteen tabs
	/// called `Local`, and a menu of sixteen identical lines is no more use than
	/// no menu. tmux's own number where there is one, and the position otherwise
	/// — which is what `C-b 2` selects and what somebody counting along the
	/// strip already has.
	private func overflowTitle(for item: PanelTabItem, at index: Int) -> String {
		let number = item.tmuxIndex ?? index + 1
		return "\(number)  \(item.title)"
	}

	@objc private func selectFromOverflow(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onSelect?(index)
	}

	/// The chevron that offers the tabs there was no room for, with how many.
	///
	/// **The count is not decoration.** Three hidden and eleven hidden are
	/// different situations, and the number is the only thing that says which
	/// without opening the menu — it is also what makes this discoverable at
	/// all, since a bare chevron beside four other glyphs is one more glyph.
	private func drawOverflowButton() {
		guard overflowButtonFrame.width > 0 else { return }

		let colour = isMirroringTmux ? Self.onTmuxGreen : Theme.current.sidebarHeaderText
		let count = NSAttributedString(string: String(hiddenTabs.count), attributes: [
			.font: Theme.current.uiFont(10, weight: .medium),
			.foregroundColor: colour,
		])
		let size = count.size()
		let chevron = Theme.current.scaled(9)
		let content = size.width + Theme.current.scaled(3) + chevron
		let left = overflowButtonFrame.midX - content / 2

		count.draw(at: NSPoint(x: left, y: overflowButtonFrame.midY - size.height / 2))
		drawGlyph(
			in: NSRect(
				x: left + size.width + Theme.current.scaled(3),
				y: 0,
				width: chevron,
				height: overflowButtonFrame.height
			),
			symbol: "chevron.down",
			points: 9,
			tint: colour
		)
	}

	/// The ground the trailing controls are drawn on.
	///
	/// One rectangle covering the tag and all three buttons, from a little way
	/// in front of the leftmost of them to the edge — the strip's own colour, so
	/// a tab that has run this far simply stops being drawn there rather than
	/// showing through. Faded in over its first few points, or the tab it cuts
	/// off ends against a hard vertical edge that reads as a tab of its own.
	private func drawControlsBackground() {
		let leftmost = [mirrorTagFrame, followButtonFrame, maximizeButtonFrame, hideButtonFrame]
			.filter { $0.width > 0 }
			.map(\.minX)
			.min()
		guard let leftmost else { return }

		let colour = isMirroringTmux ? Self.tmuxGreenBar : Theme.current.sidebarBackground
		let fade = Theme.current.scaled(16)
		let solid = NSRect(
			x: leftmost - Theme.current.scaled(6),
			y: 0,
			width: bounds.maxX - leftmost + Theme.current.scaled(6),
			height: bounds.height
		)
		colour.setFill()
		solid.fill()

		let gradient = NSGradient(
			starting: colour.withAlphaComponent(0),
			ending: colour
		)
		gradient?.draw(
			in: NSRect(x: solid.minX - fade, y: 0, width: fade, height: bounds.height),
			angle: 0
		)
	}

	/// Room for the chevron and the gap in front of it.
	private var mirrorChevronWidth: CGFloat { Theme.current.scaled(11) }

	private func drawMirrorTag() {
		guard let session = mirroredSession, mirrorTagFrame.width > 0 else { return }

		let pill = NSBezierPath(
			roundedRect: mirrorTagFrame,
			xRadius: mirrorTagFrame.height / 2,
			yRadius: mirrorTagFrame.height / 2
		)
		Theme.current.gitModified.withAlphaComponent(0.14).setFill()
		pill.fill()

		// The text and the chevron are laid out together, so the pair sits in
		// the middle of the pill rather than the text alone.
		let label = mirrorTagText(for: session)
		let size = label.size()
		let content = size.width + mirrorChevronWidth
		let left = mirrorTagFrame.midX - content / 2

		label.draw(at: NSPoint(x: left, y: mirrorTagFrame.midY - size.height / 2))

		// Drawn rather than typed: a `⌄` is a character with a baseline of its
		// own and sits low beside anything else.
		let centre = NSPoint(
			x: left + size.width + mirrorChevronWidth / 2,
			y: mirrorTagFrame.midY + Theme.current.scaled(0.5)
		)
		let arm = Theme.current.scaled(2.6)
		let chevron = NSBezierPath()
		chevron.move(to: NSPoint(x: centre.x - arm, y: centre.y - arm / 2))
		chevron.line(to: NSPoint(x: centre.x, y: centre.y + arm / 2))
		chevron.line(to: NSPoint(x: centre.x + arm, y: centre.y - arm / 2))
		chevron.lineWidth = Theme.current.scaled(1.2)
		chevron.lineCapStyle = .round
		chevron.lineJoinStyle = .round
		Theme.current.gitModified.setStroke()
		chevron.stroke()
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
		if isMirroringTmux, !isActive, isHovered {
			// The strip is already green; hovering only lifts the one under the
			// pointer out of it.
			Self.onTmuxGreen.withAlphaComponent(0.10).setFill()
			rect.fill()
		}

		if isActive {
			// On tmux's strip the active tab is a hole cut in the green, and
			// what shows through it has to be the terminal that is sitting
			// directly above — the editor's background is a different dark, and
			// the step between the two read as a gap under the green line.
			(isMirroringTmux ? TerminalPalette.background : Theme.current.editorBackground).setFill()
			rect.fill()
			// In colour only when the keyboard is down here: the editor's strip
			// marks its own tab the same way, and two coloured lines at once say
			// the cursor is in both places.
			TabSelectionLine.color(
				focused: hasKeyboardFocus,
				accent: isMirroringTmux ? Self.tmuxGreen : nil
			).setFill()
			// On tmux's strip the line goes along the top, since the strip is
			// under what it belongs to rather than over it.
			TabSelectionLine.rect(in: rect, alongTop: isMirroringTmux).fill()
		} else if item.isShowing {
			// The other half of a split: on screen, but not the one the
			// keyboard is in.
			NSColor.white.withAlphaComponent(0.06).setFill()
			rect.fill()
		} else if isHovered {
			NSColor.white.withAlphaComponent(0.05).setFill()
			rect.fill()
		}

		// A run in progress: the tab wears the titlebar's green so the two say
		// the same thing, and the one in the corner of the eye is the tab.
		// After the backgrounds, or the active tab's own fill covers it.
		if item.isRunning {
			Self.runningGreen.withAlphaComponent(isActive ? 0.38 : 0.24).setFill()
			rect.fill()
		}

		if !isActive {
			// On tmux's strip the divider is green and full height, the way
			// tmux separates the entries in its own window list.
			if isMirroringTmux {
				Self.onTmuxGreen.withAlphaComponent(0.18).setFill()
				NSRect(x: rect.maxX - 1, y: 0, width: 1, height: rect.height).fill()
			} else {
				Theme.current.separator.withAlphaComponent(0.6).setFill()
				NSRect(
					x: rect.maxX - 1, y: Theme.current.scaled(6),
					width: 1, height: rect.height - Theme.current.scaled(12)
				).fill()
			}
		}

		var x = rect.minX + padding
		let iconSize = Theme.current.scaled(14)
		let tint = item.hasExited
			? Theme.current.gitIgnored
			: Theme.current.sidebarText.withAlphaComponent(isActive ? 0.95 : 0.7)

		if let number = item.tmuxIndex {
			// tmux's number: the label somebody already uses for this window
			// when they type `C-b 2`. Green on dark for the window you are in,
			// dark on green for the rest — which is tmux's own status bar,
			// the other way up.
			let text = NSAttributedString(string: "\(number)", attributes: [
				.font: Theme.current.uiFont(11, weight: .semibold),
				.foregroundColor: isActive ? Self.tmuxGreen : Self.onTmuxGreen,
			])
			let size = text.size()
			text.draw(at: NSPoint(
				x: x + (iconSize - size.width) / 2, y: rect.midY - size.height / 2
			))
		} else {
			let symbolColour: NSColor
			if item.isTmuxAttached {
				symbolColour = Self.tmuxGreen
			} else if item.isRunning {
				symbolColour = Theme.current.gitAdded
			} else {
				symbolColour = tint
			}
			Theme.symbol(
				item.symbol,
				size: 11 * Theme.current.scale,
				color: symbolColour
			)?.drawFitted(in: NSRect(
				x: x, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize
			))
		}
		x += iconSize + Theme.current.scaled(6)

		let color: NSColor
		if isMirroringTmux, !isActive {
			color = Self.onTmuxGreen
		} else if item.hasExited {
			color = Theme.current.gitIgnored
		} else {
			color = isActive
				? Theme.current.sidebarHeaderText
				: Theme.current.sidebarText.withAlphaComponent(0.8)
		}
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let label = NSAttributedString(string: item.title, attributes: [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
		])
		let size = label.size()
		let badge = isMirroringTmux || item.aiStatus != nil
			? statusSize + Theme.current.scaled(5)
			: 0
		let reserved = (item.isClosable ? closeSize + Theme.current.scaled(6) : 0) + badge
		let limit = max(0, rect.maxX - padding - reserved - x)
		label.draw(in: NSRect(x: x, y: rect.midY - size.height / 2, width: limit, height: size.height))

		// The Claude session's state, where the ✕ would be — a tmux tab has
		// none, and the two never appear together.
		if let status = item.aiStatus {
			let badge = badgeRect(in: rect)
			let onGreen = isMirroringTmux && !isActive
			if status == .working {
				drawSpinner(in: badge, colour: onGreen ? Self.onTmuxGreen : nil)
			} else {
				// On a green tab the badge is drawn in the ink the rest of the
				// tab uses: amber on green is a smudge, and the mark itself —
				// ⟳, !, ✓ — already says which of the three it is.
				Theme.symbol(
					Self.symbol(for: status),
					size: 11 * Theme.current.scale,
					color: onGreen ? Self.onTmuxGreen : Self.colour(for: status),
					weight: .semibold
				)?.drawFitted(in: badge)
			}
		}

		if item.isClosable, isActive || isHovered {
			// `isHovered` is this tab being the hovered one and `hoveredClose` is
			// the pointer being on a cross, so the two together name this cross
			// without the drawing needing to know its own index.
			TabCloseButton.draw(
				in: closeRect(for: rect),
				hovered: isHovered && hoveredClose,
				inset: Theme.current.scaled(3),
				lineWidth: 1.2
			)
		}
	}

	/// An arc chasing its own tail, a twelfth of a turn at a time.
	///
	/// Drawn rather than an `NSProgressIndicator`: the strip is one view that
	/// draws all its tabs, and a control per tab would have to be created,
	/// placed and torn down every time tmux's window list changes — which is
	/// twice a second.
	private func drawSpinner(in rect: NSRect, colour: NSColor? = nil) {
		let radius = rect.width / 2 - Theme.current.scaled(1.5)
		let centre = NSPoint(x: rect.midX, y: rect.midY)
		let start = spinnerPhase * 30

		let arc = NSBezierPath()
		arc.appendArc(
			withCenter: centre,
			radius: radius,
			startAngle: start,
			endAngle: start + 280
		)
		arc.lineWidth = Theme.current.scaled(1.6)
		arc.lineCapStyle = .round
		(colour ?? Self.colour(for: .working)).setStroke()
		arc.stroke()
	}

	/// cmanager's three states, in this app's alphabet.
	///
	/// The same meanings it writes on tmux's own status line — working, needs
	/// you, finished — drawn as symbols rather than as `…` `⚠` `✓`, so they sit
	/// on the baseline of a tab beside an icon rather than wherever a glyph's
	/// own metrics put them.
	///
	/// Bare marks, not the ringed or filled ones: at the size a tab badge can
	/// be, a `.circle.fill` symbol is a dot and nothing else, and telling
	/// "needs you" from "finished" would come down to colour alone.
	static func symbol(for status: TmuxMirror.AIStatus) -> String {
		switch status {
		case .working:    return "ellipsis"
		case .needsInput: return "exclamationmark"
		case .done:       return "checkmark"
		}
	}

	/// Amber for the one that wants something: it is the only one worth
	/// crossing the room for, and the other two should not compete with it.
	static func colour(for status: TmuxMirror.AIStatus) -> NSColor {
		switch status {
		case .working:    return Theme.current.sidebarText.withAlphaComponent(0.55)
		case .needsInput: return .hex(0xD6A05E)
		case .done:       return Theme.current.gitAdded
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
			TabCloseButton.draw(
				in: closeRect(for: rect),
				hovered: isHovered && hoveredClose,
				inset: Theme.current.scaled(3),
				lineWidth: 1.2
			)
		}
	}

	/// - Parameter points: how big the glyph is, before the theme's scale. The
	///   default is what every control on this strip is; the + 's chevron is
	///   smaller, because it is part of that button rather than another one.
	private func drawGlyph(
		in rect: NSRect, symbol: String, points: CGFloat = 12, tint: NSColor? = nil
	) {
		guard let image = Theme.symbol(
			symbol,
			size: (points - 1) * Theme.current.scale,
			color: tint ?? Theme.current.sidebarText
		) else {
			return
		}
		let size = Theme.current.scaled(points)
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
	/// tmux's own windows, along the bottom where tmux itself puts them.
	///
	/// A separate strip rather than more tabs in the one above, because they
	/// are a different kind of thing: the top strip is what this panel holds —
	/// a terminal, a debugger, a profiler — and the bottom one is what tmux
	/// holds inside the terminal. Two lists, in the two places each is
	/// expected.
	let mirrorStrip = PanelTabStrip()
	let content = NSView()
	/// Drawn over the pane rather than behind it: a terminal fills its column,
	/// and a highlight under it is a highlight nobody sees.
	let preview = PanelContentView()
	let column: Int

	private var stripHeight: NSLayoutConstraint!
	private var mirrorHeight: NSLayoutConstraint!

	/// Whether tmux's windows get their own strip along the bottom.
	var showsMirrorStrip = false {
		didSet {
			guard showsMirrorStrip != oldValue else { return }
			mirrorStrip.isHidden = !showsMirrorStrip
			mirrorHeight.constant = showsMirrorStrip ? Theme.current.scaled(26) : 0
		}
	}

	init(column: Int) {
		self.column = column
		super.init(frame: .zero)

		mirrorStrip.isMirroringTmux = true
		mirrorStrip.showsPanelControls = false
		mirrorStrip.isHidden = true
		for view in [strip, content, preview, mirrorStrip] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		// Nothing to hit: it is a drawing, and the drop is decided from the
		// pointer's own position.
		preview.isHidden = true
		stripHeight = strip.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))
		mirrorHeight = mirrorStrip.heightAnchor.constraint(equalToConstant: 0)
		NSLayoutConstraint.activate([
			strip.topAnchor.constraint(equalTo: topAnchor),
			strip.leadingAnchor.constraint(equalTo: leadingAnchor),
			strip.trailingAnchor.constraint(equalTo: trailingAnchor),
			stripHeight,

			content.topAnchor.constraint(equalTo: strip.bottomAnchor),
			content.leadingAnchor.constraint(equalTo: leadingAnchor),
			content.trailingAnchor.constraint(equalTo: trailingAnchor),
			content.bottomAnchor.constraint(equalTo: mirrorStrip.topAnchor),

			mirrorStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
			mirrorStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
			mirrorStrip.bottomAnchor.constraint(equalTo: bottomAnchor),
			mirrorHeight,

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
		mirrorHeight.constant = showsMirrorStrip ? Theme.current.scaled(26) : 0
		strip.applyThemeChange()
		mirrorStrip.applyThemeChange()
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

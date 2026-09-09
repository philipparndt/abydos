import AppKit
import AbydosKit

/// The tool panel below the editor: terminals now, agent sessions next.
///
/// Sessions are owned here rather than by whichever view is showing them. That
/// is what lets a pane be hidden and shown again — or handed over for manual
/// takeover — while its process keeps running.
final class BottomPanel: NSView {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Asked to find a function by name, for a frame somebody clicked.
	var onOpenSymbol: ((String) -> Void)?
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
	/// Told when the backlog has something to say that is not a pane's job to
	/// show — a move that failed, a worktree that could not be made.
	var onBacklogNotice: ((String, String?) -> Void)?
	/// A debug pane has been put in the panel.
	///
	/// The window wires its breakpoint list from here: the list's verbs belong to
	/// `DebugCoordinator`, which the panel has no business knowing about, and a
	/// pane can now appear without a session having started it.
	var onDebugPaneOpened: ((DebugPane) -> Void)?
	/// Forwarded debuggee output.
	var debugOutput: ((String) -> Void)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	var mirrorCheckScheduled = false
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
	var mirrorRefreshInFlight = false
	var mirrorRefreshWanted = false
	/// Bumped whenever this app changes tmux's windows itself, so an answer
	/// worked out before the change can be recognised and dropped.
	var mirrorGeneration = 0

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// What was in front before whatever is in front now.
	weak var previouslyActive: Session?
	/// How the width is shared, so it survives a rebuild.
	var splitFraction: CGFloat = 0.5
	var attachedTerminalID: ObjectIdentifier?
	var tmuxPoll: Timer?
	/// The project this window is on, so the pill's list can open on it and a
	/// record seeded from a mirrored tmux window can be filed under it.
	var projectRoot: () -> URL? = { nil }
	/// The pill on the strips, the clock behind it and the list under it.
	lazy var runningSessions: PanelRunningSessions = {
		let sessions = PanelRunningSessions()
		sessions.strips = { [weak self] in self?.columnViews.map(\.strip) ?? [] }
		sessions.projectRoot = { [weak self] in self?.projectRoot() }
		sessions.reach = { [weak self] running, appTerminals in
			self?.reach(of: running, appTerminals: appTerminals) ?? .elsewhere
		}
		sessions.reveal = { [weak self] running in self?.reveal(running) ?? false }
		return sessions
	}()
	/// Whether tmux's strip holds windows a driven run put there, which the
	/// mirror must then not overwrite.
	var mirrorSeededForTesting = false
	/// Whether a tmux client has ever been seen on this terminal's tty, so a
	/// client that has gone away can be told from one that has not arrived yet.
	var hasAttachedOnce = false
	/// What tmux was last told about its status bar, and *heard* — the session,
	/// and whether the bar was to go. Nil until something has actually landed,
	/// so a command that went nowhere is retried rather than remembered as done.
	var statusBarApplied: (session: String, hidden: Bool)?
	/// Polls since the bar was last checked against tmux rather than against
	/// what we believe we told it.
	var statusBarPollsSinceCheck = 0

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Opens a shell, or focuses the existing one if there already is a terminal.
	/// tmux's windows, when the strip is showing those rather than our own
	/// terminals.
	var tmuxWindows: [TmuxMirror.Window] = []
	/// The session the tabs are currently showing, which is whatever the client
	/// is attached to rather than whatever it was started with.
	var mirroredSession: String?
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
	/// The search pane if there already is one, without making one or moving the
	/// keyboard. `showSearch` does both, which is wrong for a script that has
	/// just put the keyboard in the result list on purpose.
	///
	/// Answered from the field rather than by walking the sessions since item
	/// 506: the pane goes on existing while it is showing under the project view
	/// or in a window of its own, where it has no tab here to be found by.
	var existingSearchPane: SearchPane?
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
	func scheduleDirectoryCheck() {
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

	final class Session {
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

	var sessions: [Session] = []
	/// What is in front in each column.
	var activeByColumn: [Int: Session] = [:]
	/// Which column a new pane appears in, and which one a click last landed on.
	var focusedColumn = 0
	var workingDirectory: URL?

	/// How many columns there are: two once anything has been put beside
	/// something, one otherwise.
	var columnCount: Int { sessions.contains { $0.column == 1 } ? 2 : 1 }

	/// Which kinds of pane are in front, for the rail's bottom group.
	///
	/// **A set, one per column, and not the focused column's alone.** The panel
	/// splits, and a shell beside the backlog is an ordinary arrangement — so two
	/// panes are on screen and the rail has room to say so. Answering with
	/// `activeSession` would take the fill off a pane somebody is plainly looking
	/// at the moment they clicked the other half, which is the fault this was
	/// reported for, arriving from the other direction.
	///
	/// Empty while the panel is closed, so "nothing is lit for a pane that is not
	/// on screen" needs no second path through the rail.
	var frontPaneKinds: Set<PanelToolKind> {
		guard !isHidden else { return [] }
		var kinds: Set<PanelToolKind> = []
		for column in 0..<columnCount {
			guard let session = activeByColumn[column] ?? sessions(in: column).last else { continue }
			// A kind with no button contributes nothing rather than being mapped
			// to a neighbour.
			switch session.kind {
			case .backlog: kinds.insert(.backlog)
			case .review: kinds.insert(.review)
			case .debug: kinds.insert(.debug)
			case .terminal: kinds.insert(.terminal)
			case .search, .usages, .profiler: break
			}
		}
		return kinds
	}

	/// The tabs in a column, in order.
	func sessions(in column: Int) -> [Session] {
		sessions.filter { $0.column == column }
	}

	func session(at index: Int, in column: Int) -> Session? {
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
	var activeSession: Session? {
		activeByColumn[focusedColumn] ?? sessions(in: focusedColumn).last ?? sessions.last
	}

	/// How much of the shown terminal's height is not a whole row.
	///
	/// Nil when there is no terminal to be tidy about — a debugger or a
	/// profiler in the panel has no grid and no opinion about its height.
	var terminalHeightRemainder: CGFloat? {
		activeSession?.terminal?.terminalView.heightRemainder
	}

	var activeIndex: Int? {
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
	var columnsHost: NSView!
	var columnViews: [PanelColumn] = []
	var columnsSplit: ColumnSplitView?
	/// Whether the panel's own controls belong in this panel's strips.
	private var showsPanelControls = true
	private var storedFollowing = false
	private var storedMaximized = false
	var placeholder: NSTextField!

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
	func makeColumn(_ column: Int) -> PanelColumn {
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
		runningSessions.attach(strip)
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
	/// Which panes are in front has changed, so the rail's bottom group can say
	/// so.
	///
	/// **A second hook rather than a rename**, which was the design's open
	/// question. `onActiveTerminalChanged` fires from `refreshTabs()` alone and
	/// never from `activate` — so a backlog tab coming to the front raises it not
	/// at all, which is exactly the moment the rail needs telling. And its one
	/// subscriber wants the narrower question it is named for.
	var onFrontPanesChanged: (() -> Void)?

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

	/// The active pane's screen, row by row, with what is above it counted.
	///
	/// `terminalTextForTesting` is the scrollback and the screen in one string,
	/// which answers "did the command print" and not "where". A shell making
	/// room for a completion listing is a question of where: the rows that were
	/// on the screen should now be in the history above it, and the listing
	/// should sit on the rows below the prompt. So the screen's rows are named
	/// by number, and the count of lines above them is said, so two readings
	/// can be compared line for line.
	func terminalScreenReportForTesting(label: String) -> String {
		var out = "TERMINAL SCREEN \(label): sessions=\(sessions.count) active=\(activeIndex ?? -1)"
		// Every pane, not only the active one: a report that read a pane other
		// than the one on screen would describe a terminal nobody is looking at
		// and call it the screen.
		for (index, session) in sessions.enumerated() {
			guard let terminal = session.terminal else {
				out += "\nTERMINAL pane \(index): no terminal"
				continue
			}
			let view = terminal.terminalViewForTesting
			let grid = terminal.gridSizeForTesting
			let lines = view.screenTextForTesting.components(separatedBy: "\n")
			let above = max(0, lines.count - grid.rows)
			out += "\nTERMINAL pane \(index): rows=\(grid.rows) columns=\(grid.columns) lines-above=\(above) engine=\(view.engineNameForTesting)"
			for (offset, line) in lines.suffix(grid.rows).enumerated() {
				let text = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
				out += String(format: "\nTERMINAL %d.%02d| %@", index, offset, text)
			}
		}
		return out
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

	/// Where the backlog pane's header is against the strip, in the panel's own
	/// coordinates — a measurement, because the report was a screenshot with
	/// `List` under `tmux` and the word *sometimes* in it.
	func backlogGeometryForTesting() -> String {
		guard let column = columnViews.first else { return "no columns" }
		let strip = column.convert(column.strip.frame, to: self)
		guard let showing = activeByColumn[0], case let .backlog(pane) = showing.kind else {
			return "backlog not showing; " + stripGeometryForTesting()
		}
		let header = pane.convert(pane.headerFrameForTesting, to: self)
		let body = pane.convert(pane.bounds, to: self)
		return String(
			format: "strip=%.1f–%.1f pane=%.1f–%.1f header=%.1f–%.1f below-strip-by=%.1f",
			strip.minY, strip.maxY, body.minY, body.maxY, header.minY, header.maxY,
			header.minY - strip.maxY
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
			// **The shell's own directory, not the foreground's.** The window
			// follows where somebody walked, not where a script went: `brew`
			// changes directory several times while it works, and reading the
			// foreground process's answer dragged the window through every one
			// of them — while answering nothing during a run deselected the
			// project a script was started from, and a pane holding a Claude
			// session never answered at all, so switching to its tab followed
			// nowhere. The shell's own directory is all three answers at once;
			// see `TerminalDirectory.settled`.
			let directory = terminal.settledDirectoryForTesting
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

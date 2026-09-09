import AppKit
import AbydosKit

/// The review tab: a change read a file at a time, with what was said about
/// each of them.
extension BottomPanel {
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

	func wire(_ session: Session) {
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
	func activate(_ session: Session, focus: Bool) {
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
		// A stopped session arrives to be read, and reading a tree means walking
		// it: an outline view answers ↑↓←→ itself once it has the keyboard, and
		// never had it here.
		case let .debug(pane): DispatchQueue.main.async { pane.focusVariables() }
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
	func putBeside(
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
	func unsplit() {
		let showing = activeSession
		for session in sessions { session.column = 0 }
		activeByColumn = [0: showing ?? sessions.first].compactMapValues { $0 }
		focusedColumn = 0
		rebuildColumns()
	}


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
	func rebuildColumns() {
		// **Raised here and not from each of the eighteen callers.** Activating a
		// tab, closing one, splitting, unsplitting and restoring a session all
		// come through this, and each of them can change which pane is in front.
		// Cheap to answer and cheaper to act on: the rail sets four booleans and
		// redraws only the ones that moved.
		defer { onFrontPanesChanged?() }

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

		// A seeded tmux strip is left alone. The mirror re-reads tmux's window
		// list several times a second and would put the one real window back
		// over the sixteen a driven run seeded — which is what happened, and
		// left a photograph of a strip with nothing to overflow.
		guard !mirrorSeededForTesting else { return }

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
					// Read off the pane's own engine, never off the setting:
					// the two differ for every pane older than a change to it,
					// and for every pane whose engine would not start.
					var note: String?
					var symbol = session.symbol
					if case let .terminal(pane) = session.kind, let engineNote = pane.terminalView.engineNote {
						note = engineNote
						// A filled terminal where the outline one would be: no
						// room taken, nothing added to a strip that is already
						// full, and different enough to be asked about.
						symbol = "terminal.fill"
					}
					return PanelTabItem(
						title: session.displayTitle,
						hasExited: session.hasExited,
						isTerminal: { if case .terminal = session.kind { return true } else { return false } }(),
						symbol: symbol,
						isShowing: session === showing,
						isRun: session.isRun,
						isRunning: session.isStillRunning,
						engineNote: note
					)
				},
				activeIndex: list.firstIndex { $0 === showing }
			)
		}
		placeholder.isHidden = !sessions.isEmpty
	}


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

	func showDropTargets() {}

	func hideDropTargets() {
		for view in columnViews { view.showPreview(nil) }
	}

	/// The point in this panel's coordinates, or nil when it is elsewhere.
	private func local(_ screenPoint: NSPoint) -> NSPoint? {
		guard let window, window.frame.contains(screenPoint) else { return nil }
		return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
	}

	/// Draws where a dragged tab would land as it moves.
	func previewDrop(at screenPoint: NSPoint) {
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
	func finishDrag(_ session: Session, at screenPoint: NSPoint) {
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
	func handleDrop(_ payload: TerminalTabDrag.Payload, zone: TerminalTabDrag.Zone) {
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
	func adopt(_ detached: DetachedTerminal, zone: TerminalTabDrag.Zone) {
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
	func dropOnStrip(_ payload: TerminalTabDrag.Payload, at position: Int, in column: Int) {
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
	func move(from: Int, to: Int, in column: Int) {
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
	func tearOff(_ session: Session, at screenPoint: NSPoint) {
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
	func close(
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

	func close(index: Int, hidingWhenEmpty: Bool = true) {
		guard sessions.indices.contains(index) else { return }
		close(sessions[index], hidingWhenEmpty: hidingWhenEmpty)
	}

	/// Renames a tab.
	///
	/// An empty name gives it back to the shell, which is the only way to undo
	/// a rename without knowing what the shell would have called it.
	func rename(_ session: Session, to name: String) {
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
}

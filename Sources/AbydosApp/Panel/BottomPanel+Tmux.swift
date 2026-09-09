import AppKit
import AbydosKit

/// The tmux mirror: the windows of a session shown as tabs of this panel, and
/// the strip that keeps up with them.
///
/// The one piece of this panel that is about somebody else's program. Every
/// question here is "what does the server say now", asked on a timer because
/// tmux has no way to tell us.
extension BottomPanel {
	/// Watches the session, so a window opened or renamed inside tmux shows up
	/// on the strip.
	///
	/// Polled rather than pushed: tmux will run a hook, but a hook has to reach
	/// back into this process somehow, and asking twice a second costs a
	/// millisecond of a shell nobody is waiting on.
	func startMirroringTmuxIfWanted() {
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
	func scheduleMirrorCheck() {
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
	func addTmuxWindow(to session: String) {
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
	func mirrorChangedLocally() {
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
	var tmuxClientTTY: String? {
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
				self.runningSessions.forgetSeeded(inTmuxSession: self.mirroredSession)
				self.mirroredSession = nil
				if !self.tmuxWindows.isEmpty {
					self.tmuxWindows = []
					self.rebuildColumns()
				}
				return
			}
			if attached != nil { self.hasAttachedOnce = true }
			if session != self.mirroredSession {
				self.runningSessions.forgetSeeded(inTmuxSession: self.mirroredSession)
				self.mirroredSession = session
				self.tmuxWindows = []
			}
			await self.applyStatusBarWish(to: session)

			let windows = await TmuxMirror.windows(inSession: session)
			// The badges tmux already carries stand in for sessions the hook
			// has not spoken for in this process.
			self.runningSessions.seed(windows: windows, inTmuxSession: session)
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

	/// Clicks one of tmux's own window tabs, as the pointer does — through the
	/// strip's `onSelect`, so everything a real click sets off happens.
	func clickTmuxTabForTesting(_ index: Int) -> String {
		guard let strip = columnViews.first?.mirrorStrip else { return "no strip" }
		guard strip.tabCount > index else { return "tmux strip has \(strip.tabCount) tabs" }
		strip.pressSelectForTesting(index)
		return "clicked tmux tab \(index) of \(strip.tabCount)"
	}

	/// Fills tmux's own strip with windows, without a tmux server.
	///
	/// **The only way to reach the fault from a driver.** The mirroring strip is
	/// only ever filled by a real `tmux list-windows`, and a `--run` that starts
	/// tmux does not reach the mirror in the seconds a driven run lasts — which
	/// is how the strip came to be shipped counting hidden windows it never drew
	/// a chevron for. The items are what the mirror makes: numbered, unclosable,
	/// named the way tmux names them.
	func seedMirrorWindowsForTesting(_ count: Int) -> String {
		guard let column = columnViews.first else { return "no column" }
		mirrorSeededForTesting = true
		column.strip.isMirroringTmux = false
		column.mirrorStrip.isMirroringTmux = true
		column.mirrorStrip.mirroredSession = "abydos"
		column.mirrorStrip.setItems(
			(0..<count).map { index in
				PanelTabItem(
					title: "\(index):\(["build", "shell", "watch", "logs", "notes"][index % 5])",
					hasExited: false, isTerminal: true, isClosable: false, tmuxIndex: index
				)
			},
			activeIndex: 0
		)
		column.showsMirrorStrip = true
		layoutSubtreeIfNeeded()
		return "tmux strip: " + column.mirrorStrip.overflowReportForTesting
	}

	/// What tmux's strip is showing and what it is holding back, and choosing
	/// one of the windows it had no room for.
	var mirrorOverflowReportForTesting: String {
		columnViews.first.map { "tmux strip: " + $0.mirrorStrip.overflowReportForTesting } ?? "no column"
	}

	func selectHiddenMirrorWindowForTesting(_ position: Int) -> String {
		columnViews.first.map { $0.mirrorStrip.selectHiddenAndActivateForTesting(position) } ?? "no column"
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
	func wireMirrorStrip(_ strip: PanelTabStrip) {
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

	/// ⌘⇧] and ⌘⇧[ with the keyboard in the panel: the neighbouring tab on the
	/// strip of the column being typed in. A top strip holding a single tab
	/// over tmux's own strip has no neighbour, and the windows below are the
	/// tabs somebody means.
	func selectNeighbouringTab(offset: Int) {
		guard columnViews.indices.contains(focusedColumn) else { return }
		let column = columnViews[focusedColumn]
		let strip = column.strip.tabCount > 1 || column.mirrorStrip.tabCount == 0
			? column.strip
			: column.mirrorStrip
		strip.selectNeighbour(offset: offset)
	}

	/// The register moved: a session appeared, ended or changed state
	/// somewhere on the machine. `PanelRunningSessions` owns the rest.
	func runningSessionsChanged() { runningSessions.changed() }
	/// ⇧⌘A, which needs no pill and no open panel.
	func showRunningSessionsPalette(over window: NSWindow?) {
		runningSessions.showPalette(over: window)
	}

	func seedTmuxSessionsForTesting(_ count: Int) -> String {
		runningSessions.seedTmuxWindowsForTesting(count)
	}
	/// Hovers a trailing control on whichever strip has one, and says what it
	/// says. The panel's own strip first, then tmux's.
	func hoverStripControlForTesting(_ name: String) -> String {
		guard let column = columnViews.first else { return "no column" }
		let said = column.strip.hoverTrailingForTesting(name)
		guard said.contains("not on this strip") else { return said }
		return column.mirrorStrip.hoverTrailingForTesting(name)
	}

	func runningSessionsReportForTesting() -> String { runningSessions.reportForTesting() }
	func openRunningSessionsForTesting(filter: String? = nil) -> String {
		runningSessions.openForTesting(filter: filter)
	}
	func openRunningSessionsPaletteForTesting(over window: NSWindow?, filter: String? = nil) -> String {
		runningSessions.openPaletteForTesting(over: window, filter: filter)
	}
	func chooseFirstRunningSessionForTesting() -> String { runningSessions.chooseFirstForTesting() }
	func pressInRunningSessionsForTesting(_ keys: String) -> String { runningSessions.pressForTesting(keys) }
	func terminalIdentityForTesting(_ index: Int) -> String? {
		sessions.indices.contains(index) ? sessions[index].identity : nil
	}

	/// The tab tells its shell which tab it is, as `ABYDOS_TERMINAL`, so a
	/// hook running in the pane can say so and a row in the running-sessions
	/// list can bring the tab forward. Set as `TERM_PROGRAM` is — deliberately,
	/// not inherited — since the inherited value would name the tab the app
	/// itself was launched from.
	func nameTab(_ session: Session, of pane: TerminalPane) {
		pane.terminalView.launchEnvironment["ABYDOS_TERMINAL"] = session.identity
		// **The one thing in a shell that runs the project's own files.**
		// direnv reads an `.envrc` on entering a directory — it refuses one it
		// has not been allowed, so this is belt to that brace rather than the
		// brace itself, and best-effort by nature: a hook somebody wrote
		// themselves is theirs, and this app does not read anybody's shell
		// configuration to find out.
		//
		// The shell itself is not gated: it is *yours*, and typing `make` in it
		// is you choosing to run the project's code exactly as you would in
		// Terminal.app. What this app must not do is start that code by itself.
		if let root = projectRoot(), !ProjectTrust.shared.isTrusted(root) {
			pane.terminalView.launchEnvironment["DIRENV_DISABLE"] = "1"
		}
	}
}

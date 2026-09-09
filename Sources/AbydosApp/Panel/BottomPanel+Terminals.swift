import AppKit
import AbydosKit

/// Making terminals and finding them again: a new one, one beside the current
/// one, one already running that somebody asked to be shown.
extension BottomPanel {
	/// The identities of the tabs this panel holds, for the app to say which
	/// running sessions are in one of its windows.
	var terminalIdentities: Set<String> { Set(sessions.map(\.identity)) }

	/// Brings one of this panel's tabs to the front by identity, for a row
	/// clicked in another window. False when the tab is not here.
	func revealTab(identity: String) -> Bool {
		guard let session = sessions.first(where: { $0.identity == identity }) else { return false }
		activate(session, focus: true)
		return true
	}

	/// Where a running session is, as far as this panel can act on it.
	///
	/// The list draws from this and the click acts on it, so what a row says
	/// and what it does cannot drift: *here* is a tab of this panel, *another
	/// window* is a tab the app holds elsewhere, *tmux* is a place any panel
	/// can reach by switching or attaching a client, and *elsewhere* is a
	/// session in some other program's terminal — the one case where the
	/// resume command is the only honest offer.
	func reach(of running: RunningSessions.Session, appTerminals: Set<String>) -> SessionReach {
		if let terminal = running.terminal {
			if sessions.contains(where: { $0.identity == terminal }) { return .here }
			if appTerminals.contains(terminal) { return .anotherWindow }
		}
		if let tmux = running.tmuxSession {
			return mirroredTmuxSession == tmux ? .tmuxHere : .tmuxSession(tmux)
		}
		return .elsewhere
	}

	/// Brings the tab a running session is in to the front, when this panel
	/// holds it or can reach it through tmux; false when it cannot.
	///
	/// **Without the `tmux` tab having to be in front**, which was the report:
	/// the toast's `revealTmuxWindow` only ever selected a window of the
	/// mirrored session, and every other session copied a command.
	func reveal(_ running: RunningSessions.Session) -> Bool {
		if let terminal = running.terminal,
		   let session = sessions.first(where: { $0.identity == terminal }) {
			activate(session, focus: true)
			return true
		}
		guard let tmux = running.tmuxSession else { return false }

		// The window and the pane, by the pane's own id where the hook gave
		// one — it survives the window being renumbered — and by index else.
		let select = { @MainActor [weak self] in
			if let pane = running.pane, await TmuxMirror.select(pane: pane) {
			} else if let index = running.window {
				await TmuxMirror.select(window: index, inSession: tmux)
			}
			self?.refreshTmuxWindows()
		}

		if mirroredTmuxSession == tmux {
			if let index = running.window { markMirroredWindowActive(index) }
			if let terminal = mirroredTerminal { activate(terminal, focus: true) }
			Task { await select() }
			return true
		}
		if mirrorsTmux, let tty = tmuxClientTTY, mirroredTerminal?.hasExited != true {
			// Another session on the same server: the client this panel has
			// is switched to it, as the tag's menu does.
			if let terminal = mirroredTerminal { activate(terminal, focus: true) }
			Task {
				await TmuxMirror.switchClient(onTTY: tty, to: tmux)
				await select()
			}
			return true
		}
		// No `tmux` tab, or a dead one: attach one to the session, then select
		// once the client is up.
		reattachTmux(to: tmux)
		Task {
			try? await Task.sleep(nanoseconds: 600_000_000)
			await select()
		}
		return true
	}

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
	func applyStatusBarWish(to session: String) async {
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
	func markMirroredWindowActive(_ index: Int) {
		guard tmuxWindows.contains(where: { $0.index == index }) else { return }
		mirrorChangedLocally()
		// Everything except which one is active is carried over. Rebuilding
		// these from four fields dropped each window's Claude status, so every
		// tab switch blanked the badges until the next poll put them back — a
		// blink, and a jump when the badges were what set the tab's width.
		tmuxWindows = tmuxWindows.map {
			TmuxMirror.Window(
				index: $0.index,
				windowID: $0.windowID,
				name: $0.name,
				isActive: $0.index == index,
				command: $0.command,
				aiStatus: $0.aiStatus,
				silentFor: $0.silentFor,
				directory: $0.directory
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
	func showSessionMenu(from rect: NSRect, in column: Int) {
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
	func moveMirroredWindow(_ window: TmuxMirror.Window, from: Int, to: Int) {
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
	var mirroredTerminal: Session? {
		guard let id = attachedTerminalID else { return nil }
		return sessions.first { ObjectIdentifier($0) == id }
	}

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
	func mirroredWindow(at index: Int, in column: Int) -> TmuxMirror.Window? {
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
	func mirroredSession(at index: Int, in column: Int) -> Session? {
		guard !Settings.shared.tmuxTabsAtBottom else { return nil }
		guard mirrorsTmux, column == 0, !tmuxWindows.isEmpty else { return nil }
		let others = sessions(in: column).filter { $0 !== mirroredTerminal }
		let position = index - tmuxWindows.count
		return others.indices.contains(position) ? others[position] : nil
	}

	/// Puts the keyboard back in the terminal after a tab was clicked: the
	/// point of switching windows is to type in the new one.
	func focusTerminal() {
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

	/// The same shell ⌘T opens, put in a column beside the one in front.
	///
	/// **Beside, not after.** A tab appended to the strip is still the same one
	/// pane showing one terminal at a time; what somebody wants when they open a
	/// shell to do one thing next to the one they are reading is *both on
	/// screen*, which in this panel is a second column. It is the drag somebody
	/// would otherwise do — tab, to the right edge, drop — so it ends in
	/// `putBeside`, the same code that drag ends in.
	@discardableResult
	func newTerminalBesideCurrent() -> TerminalPane? {
		guard let pane = newTerminal() else { return nil }
		guard let made = sessions.last else { return pane }
		putBeside(made, on: .right)
		onTerminalsChanged?()
		return pane
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
	func newTerminal(
		rootedAt directory: URL?,
		title: String,
		command: (executable: String, arguments: [String])? = nil,
		focus: Bool = true,
		attachingTo session: String? = nil,
		joinsSession: Bool = true
	) -> TerminalPane? {
		// **An untrusted project still gets a terminal**, and the first cut of
		// this refused one. The reasoning was that a shell in the project's
		// directory is a general-purpose runner standing in it — but the shell
		// is *yours*, with your configuration, and typing `make` in it is you
		// choosing to run the project's code exactly as you would in
		// Terminal.app. What this app must not do is *start* the project's
		// code by itself; policing what somebody types is a different job and
		// not one it can do.
		//
		// The cost was the thing that settled it: this is a terminal-first IDE
		// and the terminal is how somebody moves between projects. Reported as
		// exactly that.
		//
		// What is left of the risk is the shell running the *project's* files
		// on its own — direnv's `.envrc`, which direnv already refuses until it
		// has been allowed. `DIRENV_DISABLE` is set for an untrusted project
		// as well, which is belt to that brace and best-effort by nature: a
		// hook somebody wrote themselves is theirs.
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
		nameTab(session, of: pane)
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
		nameTab(session, of: pane)
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
}

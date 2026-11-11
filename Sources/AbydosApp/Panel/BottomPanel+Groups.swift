import AppKit
import AbydosKit

/// Two windows' terminals on one tmux server without moving each other.
///
/// A tmux session has one current window, and two clients of it show the same
/// one: a tab chosen in either window switched both. So a terminal arriving at a
/// session another window's terminal is on is given a session of its own in the
/// same group — attached that way when it starts, or moved there straight after
/// a `C-b s` or `C-b w` took it to one. The decisions are `TmuxGroups`'; this is
/// where the panel asks the other windows what they are on and acts.
extension BottomPanel {
	/// The tmux sessions the other windows' terminals are on.
	var sessionsHeldElsewhere: Set<String> {
		Set(otherPanels().compactMap(\.tmuxSessionInUse))
	}

	/// The tmux session this panel's terminal is on, as far as it knows: what
	/// the tabs mirror, which follows `C-b s`; or, with the tabs this app's
	/// own, the session it was attached to, which does not.
	var tmuxSessionInUse: String? {
		if let mirrored = mirroredTmuxSession { return mirrored }
		guard Settings.shared.startsTmux, hasTerminals else { return nil }
		return attachedTmuxSession
	}

	/// Whether a session this terminal has just arrived at has another client
	/// on it: another of this app's windows, or a terminal in any other program.
	/// Asked only on arrival, so the `list-clients` it may cost is not per poll.
	func isSharedOnArrival(_ session: String, tty: String) async -> Bool {
		if sessionsHeldElsewhere.contains(session) { return true }
		return await TmuxMirror.clients().contains { $0.session == session && $0.tty != tty }
	}

	/// The session a project should remember for this terminal: the one a
	/// grouped session of ours was made from, since ours goes with the window.
	var rememberedTmuxSession: String? {
		mirroredTmuxSession.map { groupedBases[$0] ?? $0 }
	}

	/// Whether the tabs are showing `session`, or another session of its group
	/// — ours made from it, or one another window made — for news about a
	/// window in it, which is a window here too.
	///
	/// By group and not by name: an agent in the other window's `<base>~2`
	/// reports that session, and a window on `<base>` that took it for a session
	/// of its own would switch its client into the other window's.
	func isShowing(tmuxSession session: String) -> Bool {
		guard let mirrored = mirroredTmuxSession else { return false }
		return mirrored == session || knownBase(of: mirrored) == knownBase(of: session)
	}

	/// The session a grouped one was made from, as this app's windows know it:
	/// each knows the ones it made. A session none of them made is its own.
	func knownBase(of session: String) -> String {
		groupedBases[session] ?? otherPanels().lazy.compactMap { $0.groupedBases[session] }.first ?? session
	}

	/// Forgets what this panel knew about its tmux client once the client has
	/// gone — detached, or replaced by a new one: the windows it showed, the
	/// grouped sessions it made and the session it was on. Kept, they made other
	/// windows treat a session nobody is on as taken, and sent a step away back
	/// to a session the terminal had long left.
	func forgetTmuxClient() {
		// Only a client that was seen: before a new one has attached, what
		// `attachDecision` has just set is about it, not about one gone.
		guard !shownWindowLog.isEmpty || clientWindowID != nil else { return }
		Self.trace("forget client session=\(attachedTmuxSession ?? mirroredSession ?? "-")")
		shownWindowLog = []
		clientWindowID = nil
		attachedTmuxSession = nil
		groupedBases = [:]
	}

	/// Whether arriving at `session` from `previous` is entering another
	/// session rather than choosing a window in this one: a different group. A
	/// first reading has nowhere it came from, and enters.
	func entersAnotherSession(_ session: String, from previous: String?) async -> Bool {
		guard let previous else { return true }
		let all = await TmuxMirror.sessions()
		func base(_ name: String) -> String { groupedBases[name] ?? TmuxGroups.base(of: name, in: all) }
		return base(previous) != base(session)
	}

	/// The other sessions known to share `session`'s windows: the one ours was
	/// made from, and what the other windows are on in the same group. A hook
	/// that ran in any of them has spoken for a window as much as one that ran
	/// in this session — see `RunningSessions.seed`.
	func groupMates(of session: String) -> Set<String> {
		let base = groupedBases[session] ?? session
		var mates: Set<String> = [base]
		for panel in otherPanels() where panel.rememberedTmuxSession == base {
			if let theirs = panel.mirroredTmuxSession { mates.insert(theirs) }
		}
		mates.remove(session)
		return mates
	}

	/// How a terminal starting now attaches to `session`.
	///
	/// Asked of the server synchronously, since the command is decided in the
	/// pass that starts the terminal; and with one window open too, since a
	/// terminal in another program can be on the session. Once per terminal:
	/// a new client, so what the panel knew about the one before is dropped.
	func attachDecision(for session: String) -> TmuxGroups.Attach {
		shownWindowLog = []
		clientWindowID = nil
		groupedBases = [:]
		// Taken by another of this app's windows, or by any client at all: a
		// terminal in another program — another copy of Abydos, iTerm — is a
		// client of the session like ours, and shares its one current window
		// and its one size just the same. Reported 2026-10-26: the installed app
		// attached to `firefly` all morning, and a test copy's window attached
		// beside it. Ours is not attached yet, so every attached session is
		// somebody else's.
		let sessions = TmuxMirror.sessionsNow()
		let elsewhere = sessionsHeldElsewhere.union(sessions.filter(\.isAttached).map(\.name))
		let decision = TmuxGroups.attach(to: session, sessions: sessions, heldElsewhere: elsewhere)
		switch decision {
		case let .session(name): attachedTmuxSession = name
		case let .grouped(joining: base, as: name):
			groupedBases[name] = base
			attachedTmuxSession = name
		case let .rejoined(member: _, as: name): attachedTmuxSession = name
		}
		Self.trace("attach session=\(session) decision=\(decision)")
		return decision
	}

	/// Moves this terminal's client off `session`, which another window is on,
	/// to a grouped session of its own showing the same window; then tells the
	/// windows on `session` that somebody passed through, so one whose window
	/// was pulled away by a `C-b w` can put it back.
	///
	/// - Returns: whether the client was moved.
	func moveToGroupedSession(from session: String, tty: String) async -> Bool {
		let cameFrom = shownWindowLog.last?.session
		let all = await TmuxMirror.sessions()
		let base = TmuxGroups.base(of: session, in: all)
		let name = TmuxGroups.freeName(for: base, among: Set(all.map(\.name)))
		let shown = await TmuxMirror.windows(inSession: session).first(where: \.isActive)?.index
		guard await TmuxMirror.moveClient(onTTY: tty, toGroupedSession: name, joining: session, showing: shown)
		else {
			Self.trace("group session=\(session) as=\(name) refused")
			return false
		}
		groupedBases[name] = base
		attachedTmuxSession = name
		Self.trace("group session=\(session) as=\(name) window=\(shown.map(String.init) ?? "-")")
		let detected = Date()
		var kept: [(panel: BottomPanel, windowID: String)] = []
		for panel in otherPanels() where panel.tmuxSessionInUse == session {
			if let theirs = panel.anotherWindowPassedThrough(at: detected) { kept.append((panel, theirs)) }
		}
		if kept.isEmpty { await putBackOutsideClients(of: session, at: detected, besides: tty) }
		// Arrived at the very window the other one keeps in front. From another
		// session — `C-b s`, the session menu — that is the session's current
		// window and nobody chose it: this one lands beside, on a window nobody
		// has in front, as a window joining the group does. Within the group it
		// was chosen, and that window is raised and this one goes back, as a
		// tab clicked for it would; so too when there is nothing beside it.
		let arrived = await TmuxMirror.windows(inSession: name).first(where: \.isActive)?.windowID
		if let arrived, let other = kept.first(where: { $0.windowID == arrived })?.panel {
			let entered = cameFrom.map { (groupedBases[$0] ?? TmuxGroups.base(of: $0, in: all)) != base } ?? true
			if entered, await arriveBesideTheOtherWindow(arrived, in: name) { return true }
			await stepAway(from: arrived, in: name, tty: tty, raising: other)
		} else {
			// Judged here, so the next reading does not judge it again against
			// the other window's tabs before they have caught up.
			noteShownWindow(arrived, in: name, byThisWindow: false)
			if mirroredTmuxSession == nil { clientWindowID = arrived }
		}
		return true
	}

	/// Remembers which tmux window is in front, and whether this window put it
	/// there. Only changes are kept, and only the last few.
	func noteShownWindow(_ windowID: String?, in session: String, byThisWindow: Bool) {
		guard let windowID, !windowID.isEmpty, shownWindowLog.last?.windowID != windowID else { return }
		shownWindowLog.append((windowID, session, Date(), byThisWindow))
		if shownWindowLog.count > 8 { shownWindowLog.removeFirst(shownWindowLog.count - 8) }
	}

	/// Another window's terminal arrived at this session and has been moved to
	/// one of its own. If it arrived by `C-b w`, it chose a window in *this*
	/// session on its way — the session's one current window — and this window
	/// followed. That window is put back.
	///
	/// What was in front before is the newest entry that this window chose, or
	/// that is older than the arrival could be: the other window is read every
	/// half second, so a change here within the second before it noticed is
	/// the one it caused. A change somebody made here with tmux's own keys in
	/// that same second is undone with it, which is the price of tmux not
	/// saying who moved a window.
	///
	/// - Returns: the tmux window this one keeps in front, so the one that
	///   arrived can tell whether it is standing on it.
	@discardableResult
	func anotherWindowPassedThrough(at detected: Date) -> String? {
		guard let session = tmuxSessionInUse else { return nil }
		let settled = detected.addingTimeInterval(-1)
		guard let wanted = shownWindowLog.last(where: { $0.byThisWindow || $0.at <= settled })?.windowID
		else { return shownWindowID }
		// Said at once, before tmux has done it: the window that arrived asks
		// what this one keeps in front straight after this returns, and a tab
		// strip read before the put-back lands would still name the window it
		// was pulled to.
		if mirroredTmuxSession == nil {
			clientWindowID = wanted
		} else if let index = tmuxWindows.first(where: { $0.windowID == wanted })?.index {
			markMirroredWindowActive(index)
		}
		Task { @MainActor in
			let windows = await TmuxMirror.windows(inSession: session)
			guard windows.first(where: \.isActive)?.windowID != wanted,
			      let index = windows.first(where: { $0.windowID == wanted })?.index
			else { return }
			Self.trace("put back session=\(session) window=\(wanted)")
			await TmuxMirror.select(window: index, inSession: session)
			self.refreshTmuxWindows()
		}
		return wanted
	}

	/// A `C-b w` from here chose a window in a session a terminal in another
	/// program is on — the session's one current window — and moved that
	/// terminal too. It is put back to what the client watch saw it showing
	/// before. This app's own windows put themselves back.
	private func putBackOutsideClients(of session: String, at detected: Date, besides ours: String) async {
		let ownTTYs = Set(otherPanels().compactMap(\.tmuxClientTTY) + [ours])
		let outside = await TmuxMirror.clients().filter { $0.session == session && !ownTTYs.contains($0.tty) }
		guard let client = outside.first,
		      let before = TmuxClientWatch.windowBefore(detected, forClient: client.tty),
		      before.session == session, before.windowID != client.windowID,
		      let index = await TmuxMirror.windows(inSession: session).first(where: { $0.windowID == before.windowID })?.index
		else { return }
		Self.trace("put back outside client=\(client.tty) session=\(session) window=\(before.windowID)")
		await TmuxMirror.select(window: index, inSession: session)
	}

	/// Leaves the tmux window another Abydos window has in front, raising that
	/// window instead — the rule a tab click keeps, kept for tmux's own keys.
	///
	/// Reported 2026-10-26: `C-b w` in the second window onto the window the
	/// first had in front put both on it, and with `window-size latest` the two,
	/// on two monitors, then resized it between them on every keystroke. The
	/// person expected to be taken to the first window, and is.
	///
	/// Back to where this one was: the newest window in the log that is not this
	/// one, in the session it was in. A grouped session this window left has
	/// usually gone by now — `destroy-unattached` ends it as the client leaves —
	/// and one that is still there may have another client on it; either way the
	/// way back is a grouped session of its own in that session's group.
	/// Reported 2026-11-09: a window that had come from `abydos~2` found it gone,
	/// stayed, and the two windows were left on one tmux window.
	///
	/// `C-b n` across that window therefore stops on it: the window is raised,
	/// and this one stays on the window before. A window shown in one place is
	/// the price.
	func stepAway(from windowID: String, in session: String, tty: String?, raising other: BottomPanel) async {
		let before = shownWindowLog.last(where: { $0.windowID != windowID })
		// The window it showed was closed, and tmux, not the person, put it
		// here: nobody asked for the other window, so nothing is raised.
		if let before, let tty, await !TmuxMirror.windowExists(before.windowID) {
			await giveWay(on: windowID, in: session, tty: tty, to: other)
			return
		}
		Self.trace("step away window=\(windowID) shown elsewhere; back to \(before?.windowID ?? "-") in \(before?.session ?? "-")")
		other.window?.makeKeyAndOrderFront(nil)
		guard let before else { return }
		var target = session
		if before.session != session, let tty {
			target = await goBack(to: before.session, showing: before.windowID, tty: tty) ?? session
		}
		if let index = await TmuxMirror.windows(inSession: target).first(where: { $0.windowID == before.windowID })?.index {
			await TmuxMirror.select(window: index, inSession: target)
		}
		if mirroredTmuxSession == nil { clientWindowID = before.windowID }
		refreshTmuxWindows()
	}

	/// Leaves the tmux window another Abydos window has in front after tmux put
	/// this one on it because its own window was closed (`C-x y`, a tab's close
	/// button): to a window of the session nobody has in front, or — with none
	/// left — out of tmux, as tmux leaves a session whose last window closed.
	///
	/// Never a new window, which would make closing them endless, and never
	/// another session, which is somebody else's work. Reported 2026-11-09:
	/// the two stayed on one window and typing went to both.
	private func giveWay(on windowID: String, in session: String, tty: String, to other: BottomPanel) async {
		let clients = await TmuxMirror.clients().filter { $0.tty != tty }
		let taken = Set(otherPanels().compactMap(\.shownWindowID) + clients.map(\.windowID))
		let windows = await TmuxMirror.windows(inSession: session)
		if let free = windows.first(where: { !taken.contains($0.windowID) }) {
			Self.trace("closed under session=\(session); off \(windowID) to free \(free.windowID)")
			await TmuxMirror.select(window: free.index, inSession: session)
			noteShownWindow(free.windowID, in: session, byThisWindow: true)
			if mirroredTmuxSession == nil { clientWindowID = free.windowID }
			refreshTmuxWindows()
			return
		}
		Self.trace("closed under session=\(session); nothing free beside \(windowID), leaves tmux")
		await TmuxMirror.detachClient(onTTY: tty)
		let name = windows.first(where: { $0.windowID == windowID })?.name ?? "The last window"
		let base = knownBase(of: session)
		forgetTmuxClient()
		(window?.windowController as? MainWindowController)?.toasts.show(Toast(
			kind: .information,
			title: "\(name) is in front in another window",
			detail: "The tmux window this terminal showed was closed, and every other window of "
				+ "\(base) is in front elsewhere, so it has left tmux.",
			actionTitle: "Go there",
			action: { [weak other] in other?.window?.makeKeyAndOrderFront(nil) }
		))
	}

	/// Moves the client back to `session`, or — when it has gone or somebody
	/// else is on it — to a grouped session of its own in that session's group,
	/// showing `windowID`.
	///
	/// - Returns: the session the client is on now, or nil when it could not be
	///   moved.
	private func goBack(to session: String, showing windowID: String, tty: String) async -> String? {
		let all = await TmuxMirror.sessions()
		let taken = sessionsHeldElsewhere.union(all.filter(\.isAttached).map(\.name))
		if all.contains(where: { $0.name == session }), !taken.contains(session) {
			await TmuxMirror.switchClient(onTTY: tty, to: session)
			return session
		}
		let base = groupedBases[session] ?? TmuxGroups.base(of: session, in: all)
		guard let member = all.first(where: { $0.name == base })?.name
			?? all.first(where: { $0.group == base })?.name
		else { return nil }
		let index = await TmuxMirror.windows(inSession: member).first(where: { $0.windowID == windowID })?.index
		let name = TmuxGroups.freeName(for: base, among: Set(all.map(\.name)))
		guard await TmuxMirror.moveClient(onTTY: tty, toGroupedSession: name, joining: member, showing: index)
		else { return nil }
		groupedBases[name] = base
		attachedTmuxSession = name
		Self.trace("back session=\(session) as=\(name) window=\(windowID)")
		return name
	}

	/// A terminal that has just joined a group on the window another Abydos
	/// window has in front moves to one nobody has — a group starts on its
	/// first window, which is often the one beside it. A terminal in another
	/// program counts: two clients on one window share its one size.
	///
	/// Never in a session another client is on, where choosing a window would
	/// move that client too.
	func arriveBesideTheOtherWindow(_ windowID: String, in session: String) async -> Bool {
		let clients = await TmuxMirror.clients().filter { $0.tty != tmuxClientTTY }
		guard !clients.contains(where: { $0.session == session }) else { return false }
		let shownElsewhere = Set(otherPanels().compactMap(\.shownWindowID) + clients.map(\.windowID))
		guard shownElsewhere.contains(windowID),
		      let free = await TmuxMirror.windows(inSession: session).first(where: { !shownElsewhere.contains($0.windowID) })
		else { return false }
		Self.trace("arrive session=\(session) beside \(windowID), on \(free.windowID)")
		await TmuxMirror.select(window: free.index, inSession: session)
		noteShownWindow(free.windowID, in: session, byThisWindow: true)
		if mirroredTmuxSession == nil { clientWindowID = free.windowID }
		refreshTmuxWindows()
		return true
	}
}

// MARK: - The same tmux window in two Abydos windows

extension BottomPanel {
	/// The tmux window in front here, by tmux's own id, while the tabs are
	/// tmux's.
	var shownWindowID: String? {
		guard mirroredTmuxSession != nil else { return clientWindowID }
		return tmuxWindows.first(where: \.isActive)?.windowID
	}

	/// The other window whose terminal has `window` in front, if one has.
	///
	/// By `window_id`, which tmux gives a window once on the whole server: in a
	/// group the same window is listed by every session, so an id that matches
	/// is the same window, wherever it was read.
	func panelShowing(_ window: TmuxMirror.Window) -> BottomPanel? {
		guard !window.windowID.isEmpty else { return nil }
		return otherPanels().first { $0.shownWindowID == window.windowID }
	}

	/// A tab clicked for the tmux window another Abydos window has in front
	/// raises that window, and this one stays as it was.
	///
	/// Both windows are on screen — that is what a second monitor is for — so a
	/// second view of the same window shows nothing new, and tmux has one size
	/// for a window: two views of different sizes crop one of them.
	///
	/// - Returns: whether a window was raised, and the click is spent.
	func raiseWindowShowing(_ window: TmuxMirror.Window) -> Bool {
		guard !window.isActive, let other = panelShowing(window), let theirs = other.window else {
			return false
		}
		Self.trace("raise window=\(window.windowID) shown elsewhere")
		theirs.makeKeyAndOrderFront(nil)
		return true
	}
}

// MARK: - Terminals whose tabs are this app's own

extension BottomPanel {
	/// What one reading of the server's clients says about this panel's: the
	/// session it is on and the window in front there.
	///
	/// For a panel whose tabs are this app's own, which has no poll of its own
	/// to notice `C-b s` or `C-b w` take its client to a session another window
	/// is on — see `TmuxClientWatch`. A panel mirroring tmux learns the same
	/// from its own poll and is passed over.
	func clientWasRead(session: String, windowID: String, sharedWithAnotherClient: Bool) async {
		guard mirroredTmuxSession == nil, Settings.shared.startsTmux, let tty = tmuxClientTTY else { return }
		// Moved to a session of its own first, and only then noted: the log is
		// what a step away goes back to, and the session it arrived at is not
		// somewhere to go back to.
		if session != attachedTmuxSession {
			if sessionsHeldElsewhere.contains(session) || sharedWithAnotherClient,
			   await moveToGroupedSession(from: session, tty: tty) {
				return
			}
			attachedTmuxSession = session
		}
		let firstReading = shownWindowLog.isEmpty
		let previous = shownWindowLog.last
		let moved = previous.map { $0.windowID != windowID } ?? false
		clientWindowID = windowID
		noteShownWindow(windowID, in: session, byThisWindow: false)
		if firstReading {
			_ = await arriveBesideTheOtherWindow(windowID, in: session)
		} else if moved, let other = otherPanels().first(where: { $0.shownWindowID == windowID }) {
			if await entersAnotherSession(session, from: previous?.session),
			   await arriveBesideTheOtherWindow(windowID, in: session) { return }
			await stepAway(from: windowID, in: session, tty: tty, raising: other)
		}
	}
}

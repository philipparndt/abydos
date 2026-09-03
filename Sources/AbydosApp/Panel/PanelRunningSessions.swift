import AppKit
import AbydosKit

/// Where a running session is, as far as the app can act on it.
///
/// Decided once by the panel and used twice: the list draws a row from it and
/// the click acts on it, so what a row says and what it does cannot drift. The
/// report was a row that looked like every other until it was clicked, and a
/// toast saying "Copied" as the first sign the session was somewhere else.
enum SessionReach: Equatable {
	/// A tab of this panel.
	case here
	/// A tab of another window's panel.
	case anotherWindow
	/// A window of the tmux session this panel mirrors.
	case tmuxHere
	/// A window of another tmux session on the same server, reached by
	/// switching or attaching this panel's client.
	case tmuxSession(String)
	/// Some other program's terminal: the resume command is the only offer.
	case elsewhere

	/// What a row says beside the age, and nothing for the two that are one
	/// click away with nothing to explain.
	var tag: String? {
		switch self {
		case .here, .tmuxHere: return nil
		case .anotherWindow: return "another window"
		case .tmuxSession(let session): return "tmux · \(session)"
		case .elsewhere: return "elsewhere"
		}
	}

	var isReachable: Bool { self != .elsewhere }

	/// One word for a driven report.
	var word: String {
		switch self {
		case .here: return "here"
		case .anotherWindow: return "another-window"
		case .tmuxHere: return "tmux"
		case .tmuxSession(let session): return "tmux:\(session)"
		case .elsewhere: return "elsewhere"
		}
	}
}

/// The panel's half of the running-sessions pill: what the strips are told to
/// draw, the clock that keeps a working count honest, the list under the pill,
/// and what a row in it does.
///
/// An object of its own rather than more of `BottomPanel`, which is over five
/// thousand lines and forbidden to grow. Everything here is state of its own —
/// a timer, a popover — and the panel hands it what it needs to know and
/// nothing else: which strips carry the pill, which project the window is on,
/// where a session is and how to get there.
@MainActor
final class PanelRunningSessions {
	/// What the app as a whole holds, over every window: the identities of
	/// every tab, and bringing one forward wherever it is. Set once by the app
	/// delegate, because the register is the machine's and the reach is the
	/// app's — a row clicked in one window may name a tab in another.
	struct AppReach {
		var terminals: () -> Set<String> = { [] }
		var reveal: (_ identity: String) -> Bool = { _ in false }
	}
	static var app = AppReach()

	/// The strips that carry the pill: every column's top strip.
	var strips: () -> [PanelTabStrip] = { [] }
	/// The project this window is on, so the list opens on it and a record
	/// seeded from a mirrored tmux window is filed under it.
	var projectRoot: () -> URL? = { nil }
	/// Where a session is, given the tabs the app holds.
	var reach: (RunningSessions.Session, Set<String>) -> SessionReach = { _, _ in .elsewhere }
	/// Brings the session's terminal forward when this panel holds it or can
	/// reach it through tmux; false when it cannot.
	var reveal: (RunningSessions.Session) -> Bool = { _ in false }

	/// Ticks once a second while a working session is in the register, so the
	/// pill can stop believing one that has fallen silent. Absent otherwise: an
	/// idle app is an idle app.
	private var clock: Timer?
	/// The list under the pill, while it is open.
	private var popover: RunningSessionsPopover?

	private var projectSlugs: [String] {
		projectRoot().map(AgentSessions.slugs(of:)) ?? []
	}

	private func counts(at now: Date = Date()) -> RunningSessions.Counts? {
		RunningSessions.shared.isEmpty ? nil : RunningSessions.shared.counts(at: now)
	}

	private func reachOf(_ session: RunningSessions.Session) -> SessionReach {
		reach(session, Self.app.terminals())
	}

	/// A strip made: it shows what is already running — a driven run seeds the
	/// register before the window opens, and a second window opens onto a
	/// machine that has been busy for hours — and clicking its pill opens the
	/// list from it.
	func attach(_ strip: PanelTabStrip) {
		strip.runningCounts = counts()
		strip.onSessionsPillClicked = { [weak self, weak strip] rect in
			guard let self, let strip else { return }
			self.show(from: rect, of: strip)
		}
		syncClock()
	}

	/// The register moved: a session appeared, ended or changed state
	/// somewhere on the machine.
	func changed() { sync() }

	/// The badges tmux already carries stand in for sessions the hook has not
	/// spoken for in this process — one that was running before the app
	/// launched, sitting at a prompt. Filed under each pane's own directory,
	/// which tmux knows, and under this window's project only for a pane that
	/// has none.
	func seed(windows: [TmuxMirror.Window], inTmuxSession session: String) {
		guard let root = projectRoot() else { return }
		if RunningSessions.shared.seed(windows: windows, inTmuxSession: session, cwd: root.path) {
			sync()
		}
	}

	/// Nothing will read the old session's windows again, so what was seeded
	/// from them would otherwise stay for good.
	func forgetSeeded(inTmuxSession session: String?) {
		if RunningSessions.shared.forgetSeeded(inTmuxSession: session) { sync() }
	}

	/// Puts what the register says on every strip, and on the list if it is
	/// open. Called for a move and once a second while anything is working;
	/// a strip redraws only if its two numbers actually changed.
	private func sync() {
		let now = Date()
		RunningSessions.shared.prune(at: now)
		let counts = counts(at: now)
		for strip in strips() { strip.runningCounts = counts }
		popover?.reload()
		syncClock()
	}

	/// Running while at least one session is working, and stopped otherwise,
	/// in the shape of the strip's own spinner timer.
	private func syncClock() {
		let wanted = RunningSessions.shared.needsClock
		if wanted, clock == nil {
			clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
				MainActor.assumeIsolated { self?.sync() }
			}
			RunLoop.main.add(clock!, forMode: .common)
		} else if !wanted {
			clock?.invalidate()
			clock = nil
		}
	}

	private func show(from rect: NSRect, of strip: PanelTabStrip) {
		// Clicking the pill while the list is open puts it away rather than
		// stacking another.
		if let popover, popover.isShown {
			popover.close()
			self.popover = nil
			return
		}
		let popover = RunningSessionsPopover(
			firstSlugs: { [weak self] in self?.projectSlugs ?? [] },
			reach: { [weak self] session in self?.reachOf(session) ?? .elsewhere },
			onChoose: { [weak self] session in self?.go(to: session) }
		)
		self.popover = popover
		// `.maxY` is the bottom edge of a flipped view, and the strip is one.
		popover.show(relativeTo: rect, of: strip, preferredEdge: .maxY)
	}

	/// What a row does: the nearest terminal the app holds, and the resume
	/// command only for a session the app does not hold at all.
	///
	/// This panel first — a tab of its own, or a tmux place it can switch or
	/// attach to — then another window's tab, then the pasteboard.
	private func go(to session: RunningSessions.Session) {
		if reveal(session) { return }
		if let terminal = session.terminal, Self.app.reveal(terminal) { return }
		guard !session.isSeeded else {
			Toast.post(
				"Nothing to copy yet",
				detail: "This session has not announced its id. It will at its next event.",
				kind: .information
			)
			return
		}
		let command = AgentSessions.resumeCommand(forID: session.id)
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(command, forType: .string)
		Toast.post("Copied", detail: command, kind: .information)
	}

	// MARK: - For the harness

	/// What the pill says and what its list holds, each row with its reach.
	func reportForTesting() -> String {
		let now = Date()
		let register = RunningSessions.shared
		guard !register.isEmpty else { return "SESSIONS: (none)" }
		let counts = register.counts(at: now)
		return "SESSIONS: pill=[working=\(counts.working) needs=\(counts.needsInput) total=\(counts.total)] "
			+ RunningSessionsListView.describe(
				register.grouped(firstSlugs: projectSlugs, at: now),
				reach: { [weak self] in self?.reachOf($0) ?? .elsewhere },
				at: now
			)
	}

	/// Clicks the pill, as a person would, types a filter if one is given, and
	/// says what came up.
	func openForTesting(filter: String? = nil) -> String {
		guard let strip = strips().first, strip.sessionsPillFrameForTesting.width > 0
		else { return "SESSIONS: no pill to click" }
		show(from: strip.sessionsPillFrameForTesting, of: strip)
		if let filter, let popover { popover.typeFilterForTesting(filter) }
		let shown = popover?.isShown == true ? " (open)" : " (not open)"
		return reportForTesting() + shown
			+ (popover.map { " visible=[\($0.visibleRowsForTesting())]" } ?? "")
	}

	/// Clicks the first row shown, as ⏎ in the filter does.
	func chooseFirstForTesting() -> String {
		guard let popover, popover.isShown else { return "SESSIONS: no list open" }
		return "SESSIONS chose: " + popover.chooseFirstForTesting()
	}
}

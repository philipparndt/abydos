import Foundation
import Testing
@testable import AbydosKit

/// Which sessions the hook says are running, and what each last said.
///
/// Every payload here is the shape `ClaudeHookRunner.announce` posts — the same
/// keys, including the ones it leaves out — because the whole point of reading
/// the hook is that it states a fact, and a test against an invented shape would
/// be checking this file against itself.
struct RunningSessionsTests {
	private func payload(
		_ event: String, session: String = "s-1", cwd: String = "/Users/x/dev/probe",
		status: String? = nil, tmux: (String, Int, String)? = nil,
		announce: String? = nil, message: String? = nil, type: String? = nil
	) -> [String: String] {
		var payload = ["event": event, "session": session, "cwd": cwd]
		if let status { payload["status"] = status }
		if let type { payload["notificationType"] = type }
		if let tmux {
			payload["tmuxSession"] = tmux.0
			payload["window"] = String(tmux.1)
			payload["windowName"] = tmux.2
		}
		if let announce { payload["announce"] = announce }
		if let message { payload["message"] = message }
		return payload
	}

	private let slugs = ["-Users-x-dev-probe"]
	private let t0 = Date(timeIntervalSince1970: 1_000_000)

	@Test func aSessionStartsAndEnds() {
		var running = RunningSessions()
		#expect(running.note(payload("SessionStart")) == .init(slug: "-Users-x-dev-probe", sessionsChanged: true))
		#expect(running.ids(forSlugs: slugs) == ["s-1"])

		#expect(running.note(payload("SessionEnd")) == .init(slug: "-Users-x-dev-probe", sessionsChanged: true))
		#expect(running.ids(forSlugs: slugs).isEmpty)
		#expect(running.isEmpty)
	}

	/// **The one that decides whether this is affordable.** A session at work
	/// sends one of these on every tool use, dozens a minute, and counting what
	/// is under a session means walking it. The first tool use is the session
	/// going from started to working, which moves the pill's count and nothing
	/// in the tree; every one after it moves neither.
	@Test func aToolUseFromAKnownSessionAsksForNothing() {
		var running = RunningSessions()
		running.note(payload("SessionStart"))
		#expect(running.note(payload("PreToolUse", status: "working"))?.sessionsChanged == false)
		#expect(running.note(payload("PostToolUse", status: "working")) == nil)
		#expect(running.note(payload("PreToolUse", status: "working")) == nil)
		#expect(running.ids(forSlugs: slugs) == ["s-1"])
	}

	/// And the same event from a session nobody had heard of does change the
	/// answer — which is how a session that started before the app did is found
	/// without anybody asking a process table.
	@Test func aToolUseFromAnUnknownSessionIsNews() {
		var running = RunningSessions()
		#expect(running.note(payload("PostToolUse", session: "s-2", status: "working"))?.sessionsChanged == true)
		#expect(running.ids(forSlugs: slugs) == ["s-2"])
	}

	/// A finished turn is the moment files have landed, so the row saying
	/// `running` with nothing under it may now have something — and it says so
	/// even when the status was already done.
	@Test func aFinishedTurnAsksForAReadEvenThoughNothingMoved() {
		var running = RunningSessions()
		running.note(payload("SessionStart"))
		running.note(payload("PreToolUse", status: "working"))
		#expect(running.note(payload("Stop", status: "working")) == nil)
		#expect(running.note(payload("Stop", status: "done"))?.sessionsChanged == true)
		#expect(running.note(payload("Stop", status: "done"))?.sessionsChanged == true)
	}

	/// A status change moves the pill and leaves the tree alone: nothing has
	/// landed in a scratchpad because Claude asked a question.
	@Test func aStatusChangeMovesThePillAndNotTheTree() {
		var running = RunningSessions()
		running.note(payload("SessionStart"))
		running.note(payload("PreToolUse", status: "working"))
		let moved = running.note(payload("Notification", status: "needs", announce: "probe needs you"))
		#expect(moved == .init(slug: "-Users-x-dev-probe", sessionsChanged: false))
		#expect(running.session(id: "s-1")?.status == .needsInput)
		// And back again when somebody answers.
		#expect(running.note(payload("PostToolUse", status: "working"))?.sessionsChanged == false)
	}

	/// The hook sends an empty status for an event that says nothing about the
	/// state — a notification about a push going out — and the record keeps
	/// what it had, as tmux's own option does.
	@Test func anEmptyStatusLeavesTheStateAlone() {
		var running = RunningSessions()
		running.note(payload("SessionStart"))
		running.note(payload("PreToolUse", status: "working"))
		#expect(running.note(payload("Notification", status: "")) == nil)
		#expect(running.session(id: "s-1")?.status == .working)
	}

	@Test func theLastLineAndItsPlaceAreKept() {
		var running = RunningSessions()
		running.note(payload("SessionStart", tmux: ("abydos", 2, "screencasts")), now: t0)
		running.note(payload(
			"Notification", status: "needs", tmux: ("abydos", 2, "screencasts"),
			announce: "screencasts needs you", message: "Claude needs your permission to use Bash"
		), now: t0.addingTimeInterval(5))
		let session = running.session(id: "s-1")
		#expect(session?.tmuxSession == "abydos")
		#expect(session?.window == 2)
		#expect(session?.windowName == "screencasts")
		#expect(session?.line == "screencasts needs you")
		#expect(session?.message == "Claude needs your permission to use Bash")
		#expect(session?.lastEvent == t0.addingTimeInterval(5))

		// A tool use carries no line, and the last one said stays.
		running.note(payload("PostToolUse", status: "working", tmux: ("abydos", 2, "screencasts")), now: t0.addingTimeInterval(9))
		#expect(running.session(id: "s-1")?.line == "screencasts needs you")
	}

	// MARK: - Nothing resurrects a finished turn

	private func finished(_ running: inout RunningSessions) {
		running.note(payload("SessionStart"))
		running.note(payload("PreToolUse", status: "working"))
		running.note(payload("Stop", status: "done"))
	}

	/// The idle nudge a minute after an answer, for a session outside tmux:
	/// the hook has no window to ask and says `needs`; the register knows
	/// better, and the corner can ask it first.
	@Test func aNudgeDoesNotWakeAFinishedSession() {
		var running = RunningSessions()
		finished(&running)
		let nudge = payload(
			"Notification", status: "needs", announce: "probe needs you",
			message: "Claude is waiting for your input", type: "idle_prompt"
		)
		#expect(running.disregards(nudge))
		#expect(running.note(nudge) == nil)
		#expect(running.session(id: "s-1")?.status == .done)
		#expect(running.counts().needsInput == 0)
	}

	@Test func aSubagentFinishingAfterTheTurnEndedIsDisregarded() {
		var running = RunningSessions()
		finished(&running)
		let handback = payload("SubagentStop", status: "working", announce: "probe · a subagent finished")
		#expect(running.disregards(handback))
		#expect(running.note(handback) == nil)
		#expect(running.session(id: "s-1")?.status == .done)
	}

	/// Claude paused mid-turn for an answer: the same nudge, and it is real.
	@Test func aNudgeForAWorkingSessionIsAQuestion() {
		var running = RunningSessions()
		running.note(payload("SessionStart"))
		running.note(payload("PreToolUse", status: "working"))
		let nudge = payload("Notification", status: "needs", type: "idle_prompt")
		#expect(!running.disregards(nudge))
		#expect(running.note(nudge)?.sessionsChanged == false)
		#expect(running.session(id: "s-1")?.status == .needsInput)
	}

	@Test func aRealQuestionAfterAFinishedTurnIsHeard() {
		var running = RunningSessions()
		finished(&running)
		let question = payload("Notification", status: "needs", type: "permission_prompt")
		#expect(!running.disregards(question))
		#expect(running.note(question) != nil)
		#expect(running.session(id: "s-1")?.status == .needsInput)
	}

	/// Where a session is, for a row to reach it: the tmux pane by its own id
	/// when the hook ran in one, and the app's tab identity when it ran in one
	/// of ours outside tmux.
	@Test func thePaneAndTheTabAreKept() {
		var running = RunningSessions()
		var inTmux = payload("PreToolUse", session: "t", status: "working", tmux: ("abydos", 2, "screencasts"))
		inTmux["pane"] = "%7"
		running.note(inTmux)
		#expect(running.session(id: "t")?.pane == "%7")
		#expect(running.session(id: "t")?.terminal == nil)

		var inTab = payload("PreToolUse", session: "l", status: "working")
		inTab["terminal"] = "1C2D-TAB"
		running.note(inTab)
		#expect(running.session(id: "l")?.terminal == "1C2D-TAB")
		#expect(running.session(id: "l")?.tmuxSession == nil)
	}

	@Test func anEndForASessionNobodyKnewIsNotNews() {
		var running = RunningSessions()
		#expect(running.note(payload("SessionEnd")) == nil)
	}

	@Test func anEventWithNoSessionOrNoDirectorySaysNothing() {
		var running = RunningSessions()
		#expect(running.note(["event": "SessionStart", "cwd": "/Users/x"]) == nil)
		#expect(running.note(["event": "SessionStart", "session": "s-1"]) == nil)
		#expect(running.note([:]) == nil)
	}

	/// Two projects, and neither hears the other's sessions.
	@Test func anotherProjectsSessionIsNotThisOne() {
		var running = RunningSessions()
		running.note(payload("SessionStart", session: "theirs", cwd: "/Users/x/dev/other"))
		#expect(running.ids(forSlugs: slugs).isEmpty)
		#expect(running.ids(forSlugs: ["-Users-x-dev-other"]) == ["theirs"])
	}

	/// **`/tmp` is a symlink here**, so the same project is spelled two ways
	/// depending on which of them the shell had. The register is keyed by slug
	/// and the lookup offers both, which is what `AgentSessions.slugs` produces.
	@Test func eitherSpellingOfTheSameProjectFindsIt() {
		// `/tmp` itself, because a path that does not exist resolves to itself
		// and there would be only one spelling to offer.
		var running = RunningSessions()
		running.note(payload("SessionStart", cwd: "/tmp"))
		let both = AgentSessions.slugs(of: URL(fileURLWithPath: "/tmp"))
		#expect(both == ["-tmp", "-private-tmp"])
		#expect(running.ids(forSlugs: both) == ["s-1"])

		// And the other way about: the shell said the resolved one.
		var resolved = RunningSessions()
		resolved.note(payload("SessionStart", cwd: "/private/tmp"))
		#expect(resolved.ids(forSlugs: both) == ["s-1"])
	}

	/// **Exactly, not by prefix.** A session started in a subdirectory is filed
	/// under a key of its own and has a scratch directory of its own.
	@Test func aSubdirectoryIsADifferentProject() {
		var running = RunningSessions()
		running.note(payload("SessionStart", cwd: "/Users/x/dev/probe/Sources"))
		#expect(running.ids(forSlugs: slugs).isEmpty)
		#expect(RunningSessions.belongs(payload("SessionStart", cwd: "/Users/x/dev/probe/Sources"), toSlugs: slugs) == false)
		#expect(RunningSessions.belongs(payload("SessionStart"), toSlugs: slugs))
	}

	@Test func twoSessionsInOneProject() {
		var running = RunningSessions()
		running.note(payload("SessionStart", session: "a"))
		running.note(payload("SessionStart", session: "b"))
		#expect(running.ids(forSlugs: slugs) == ["a", "b"])
		running.note(payload("SessionEnd", session: "a"))
		#expect(running.ids(forSlugs: slugs) == ["b"])
	}

	// MARK: - The pill

	/// Three working, one waiting, one finished: the pill reads 3 and 1, and the
	/// finished one is in the total and nowhere else.
	@Test func thePillCountsTheWorkingAndTheWaitingAndNothingElse() {
		var running = RunningSessions()
		for id in ["a", "b", "c"] {
			running.note(payload("SessionStart", session: id), now: t0)
			running.note(payload("PreToolUse", session: id, status: "working"), now: t0)
		}
		running.note(payload("Notification", session: "d", status: "needs"), now: t0)
		running.note(payload("Stop", session: "e", status: "done"), now: t0)
		#expect(running.counts(at: t0) == .init(working: 3, needsInput: 1, total: 5))
	}

	/// The tabs' rule, on the hook's clock: a working session silent past the
	/// bound is hollow, counted under neither number, and still running.
	@Test func aWorkingSessionThatFallsSilentIsCountedUnderNeither() {
		var running = RunningSessions()
		running.note(payload("PreToolUse", status: "working"), now: t0)
		#expect(running.counts(at: t0.addingTimeInterval(29)) == .init(working: 1, needsInput: 0, total: 1))
		let later = t0.addingTimeInterval(TmuxMirror.Window.staleAfter + 1)
		#expect(running.counts(at: later) == .init(working: 0, needsInput: 0, total: 1))
		#expect(running.session(id: "s-1")?.shown(at: later) == .unknown)
		#expect(running.needsClock)
	}

	/// Waiting and finished are states a session stays in, quietly, for as long
	/// as somebody likes — so neither goes stale and neither wants the clock.
	@Test func waitingAndFinishedNeverGoStale() {
		var running = RunningSessions()
		running.note(payload("Notification", session: "a", status: "needs"), now: t0)
		running.note(payload("Stop", session: "b", status: "done"), now: t0)
		let hour = t0.addingTimeInterval(3600)
		#expect(running.counts(at: hour) == .init(working: 0, needsInput: 1, total: 2))
		#expect(running.session(id: "a")?.shown(at: hour) == .needsInput)
		#expect(running.session(id: "b")?.shown(at: hour) == .done)
		#expect(!running.needsClock)
	}

	/// A session that has started and said nothing is hollow too: there is
	/// nothing known about what it is doing.
	@Test func aSessionThatHasSaidNothingIsUnknown() {
		var running = RunningSessions()
		running.note(payload("SessionStart"), now: t0)
		#expect(running.session(id: "s-1")?.shown(at: t0) == .unknown)
		#expect(running.counts(at: t0) == .init(working: 0, needsInput: 0, total: 1))
	}

	/// A session killed mid-turn sends no `SessionEnd`; ten minutes of silence
	/// is what removes it. A waiting session is never removed this way.
	@Test func aWorkingSessionSilentForTenMinutesIsForgotten() {
		var running = RunningSessions()
		running.note(payload("PreToolUse", session: "killed", status: "working"), now: t0)
		running.note(payload("Notification", session: "waiting", status: "needs"), now: t0)
		#expect(running.prune(at: t0.addingTimeInterval(RunningSessions.forgottenAfter)) == false)
		#expect(running.prune(at: t0.addingTimeInterval(RunningSessions.forgottenAfter + 1)) == true)
		#expect(running.ids(forSlugs: slugs) == ["waiting"])
		#expect(!running.needsClock)
	}

	// MARK: - The popover

	/// The window's own project first, then the others most recently heard
	/// first; within a project, tmux's windows in tmux's order and then the
	/// sessions outside tmux, newest first.
	@Test func theListOpensOnThisProjectAndOrdersTheRestByRecency() {
		var running = RunningSessions()
		running.note(payload("PreToolUse", session: "old", cwd: "/Users/x/dev/older", status: "working"), now: t0)
		running.note(payload("PreToolUse", session: "w2", status: "working", tmux: ("abydos", 2, "screencasts")), now: t0.addingTimeInterval(1))
		running.note(payload("PreToolUse", session: "w1", status: "working", tmux: ("abydos", 1, "abydos")), now: t0.addingTimeInterval(2))
		running.note(payload("PreToolUse", session: "loose", status: "working"), now: t0.addingTimeInterval(3))
		running.note(payload("Notification", session: "new", cwd: "/Users/x/dev/newer", status: "needs"), now: t0.addingTimeInterval(4))

		let groups = running.grouped(firstSlugs: slugs, at: t0.addingTimeInterval(5))
		#expect(groups.map(\.slug) == ["-Users-x-dev-probe", "-Users-x-dev-newer", "-Users-x-dev-older"])
		#expect(groups[0].cwd == "/Users/x/dev/probe")
		#expect(groups[0].sessions.map(\.id) == ["w1", "w2", "loose"])
	}

	@Test func aProjectWithNoSessionIsNotAGroup() {
		var running = RunningSessions()
		running.note(payload("SessionStart", cwd: "/Users/x/dev/other"), now: t0)
		#expect(running.grouped(firstSlugs: slugs, at: t0).map(\.slug) == ["-Users-x-dev-other"])
	}

	// MARK: - Seeding from the mirrored tmux session

	private func window(
		_ index: Int, _ name: String, status: TmuxMirror.AIStatus?, silent: TimeInterval = 0,
		directory: String = "/Users/x/dev/probe"
	) -> TmuxMirror.Window {
		TmuxMirror.Window(
			index: index, name: name, isActive: false, aiStatus: status, silentFor: silent, directory: directory
		)
	}

	/// A tmux session is somebody's workspace: its windows sit in many
	/// projects, and a seeded record is filed under the pane's own directory,
	/// not under the project the panel is on. `screencasts` was under
	/// `~/dev/oss` for an afternoon.
	@Test func aSeededWindowIsFiledUnderItsOwnDirectory() {
		var running = RunningSessions()
		running.seed(
			windows: [
				window(1, "abydos", status: .working),
				window(2, "screencasts", status: .working, directory: "/Users/x/dev/vehub/screencasts"),
				window(3, "nameless", status: .done, directory: ""),
			],
			inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0
		)
		let groups = running.grouped(firstSlugs: slugs, at: t0)
		#expect(groups.map(\.slug) == ["-Users-x-dev-probe", "-Users-x-dev-vehub-screencasts"])
		#expect(groups[0].sessions.map(\.windowName) == ["abydos", "nameless"])
		#expect(groups[1].cwd == "/Users/x/dev/vehub/screencasts")
	}

	/// A window with a badge and no record is counted and can be revealed,
	/// though nobody has its id yet.
	@Test func aBadgedWindowNobodyHasHeardFromIsSeeded() {
		var running = RunningSessions()
		let windows = [window(1, "abydos", status: nil), window(3, "examples", status: .needsInput)]
		let changed = running.seed(windows: windows, inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0)
		#expect(changed)
		#expect(running.counts(at: t0) == .init(working: 0, needsInput: 1, total: 1))

		let seeded = running.grouped(firstSlugs: slugs, at: t0).first?.sessions.first
		#expect(seeded?.isSeeded == true)
		#expect(seeded?.tmuxSession == "abydos")
		#expect(seeded?.window == 3)
		#expect(seeded?.windowName == "examples")
		// No id, so no row in the tree, which names rows by id.
		#expect(running.ids(forSlugs: slugs).isEmpty)

		// Read again with nothing changed: nothing to redraw.
		#expect(running.seed(windows: windows, inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0.addingTimeInterval(1)) == false)
	}

	/// The hook catches up: one record, the hook's, and the counts stand still.
	@Test func theHooksOwnRecordReplacesTheSeededOne() {
		var running = RunningSessions()
		running.seed(windows: [window(3, "examples", status: .needsInput)], inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0)
		running.note(payload("Notification", session: "real", status: "needs", tmux: ("abydos", 3, "examples")), now: t0.addingTimeInterval(1))
		#expect(running.counts(at: t0.addingTimeInterval(1)) == .init(working: 0, needsInput: 1, total: 1))
		#expect(running.ids(forSlugs: slugs) == ["real"])

		// And the next read of tmux does not seed it back.
		#expect(running.seed(windows: [window(3, "examples", status: .needsInput)], inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0.addingTimeInterval(2)) == false)
		#expect(running.counts(at: t0.addingTimeInterval(2)).total == 1)
	}

	/// A seeded working window takes its silence from tmux, so it goes hollow
	/// on the same clock as its tab.
	@Test func aSeededWorkingWindowGoesHollowByTmuxsClock() {
		var running = RunningSessions()
		running.seed(windows: [window(1, "abydos", status: .working, silent: 5)], inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0)
		#expect(running.counts(at: t0).working == 1)
		running.seed(windows: [window(1, "abydos", status: .working, silent: 40)], inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0.addingTimeInterval(35))
		#expect(running.counts(at: t0.addingTimeInterval(35)).working == 0)
		#expect(running.session(id: "")?.isSeeded == nil, "a seeded record is not reachable by id, having none")
	}

	/// A window that lost its badge, or went away, takes its seeded record
	/// with it.
	@Test func aSeededRecordGoesWithItsBadge() {
		var running = RunningSessions()
		running.seed(windows: [window(1, "abydos", status: .done), window(2, "build", status: .working)], inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0)
		#expect(running.counts(at: t0).total == 2)
		let dropped = running.seed(windows: [window(1, "abydos", status: nil)], inTmuxSession: "abydos", cwd: "/Users/x/dev/probe", now: t0)
		#expect(dropped)
		#expect(running.isEmpty)
	}
}

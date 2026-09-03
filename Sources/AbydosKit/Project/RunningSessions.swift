import Foundation

/// Which Claude Code sessions are running on this machine, and what each of them
/// last said, from the hook.
///
/// **The signal was already crossing the process boundary and being dropped.**
/// `ClaudeHookRunner.announce` posts a distributed notification on *every* event
/// carrying `event`, `session` and `cwd`; the app listened for the ones worth a
/// toast and returned early on the rest, which is every `SessionStart` and
/// `SessionEnd`. So a session that had started and written nothing was invisible
/// to a tree keyed on files, while the thing that knew about it was being
/// delivered several times a minute.
///
/// This holds what those events say. It is the only source that can say
/// *running* rather than *active*: `SessionStart` and `SessionEnd` bracket a
/// session exactly, where a transcript's modification time is a guess about
/// somebody's attention.
///
/// **And what each said last, not only that it exists.** The terminal panel's
/// pill counts the sessions working and the sessions waiting for somebody,
/// anywhere on the machine, and its popover lists them with their last line —
/// which is the question the tabs cannot answer for a session in another tmux
/// session or another project, and the toast cannot answer once it has gone.
///
/// Nothing here reads a disk or asks a process. The alternatives both did and
/// neither could answer: a watcher on `/tmp/claude-<uid>` rebuilds a root nobody
/// is looking at for somebody else's session, several times a second, and the
/// process table cannot say *which* session a `claude` process is, because its
/// id is nowhere in the arguments.
public struct RunningSessions: Equatable, Sendable {
	/// One session, as the hook last described it.
	public struct Session: Equatable, Sendable, Identifiable {
		/// The session's own id. **Empty for a record seeded from a tmux
		/// window** — see `seed` — which is a session known to exist and to be
		/// in some state, whose id nobody has heard yet.
		public let id: String
		/// The slug of `cwd`, which is the key the scratch directories are
		/// filed under.
		public let slug: String
		/// Where the session was announced from.
		public let cwd: String
		/// What the hook last derived. Nil for a session that has started and
		/// said nothing yet.
		public var status: TmuxMirror.AIStatus?
		/// The tmux session and window the hook ran in, when it ran in one.
		public var tmuxSession: String?
		public var window: Int?
		public var windowName: String?
		/// The tmux pane by its own id, `%7`, when the hook ran in one.
		public var pane: String?
		/// The identity of the app's tab the hook ran in, when it ran in one of
		/// ours outside tmux — the tab's `ABYDOS_TERMINAL`.
		public var terminal: String?
		/// The last line the hook announced, and the message behind it.
		public var line: String?
		public var message: String?
		/// When the hook last spoke for this session — or, for a seeded record,
		/// when tmux last saw the window produce anything.
		public var lastEvent: Date

		public var isSeeded: Bool { id.isEmpty }

		/// What a pill or a row shows for a session, given the time.
		///
		/// The tabs' vocabulary and nothing more: a `working` that has been
		/// silent past `TmuxMirror.Window.staleAfter` is not believed, and a
		/// session that has said nothing at all is in the same position — both
		/// are drawn hollow and counted under neither number.
		public enum Shown: String, Sendable, CaseIterable {
			case working
			case needsInput = "needs"
			case done
			case unknown
		}

		public func shown(at now: Date) -> Shown {
			switch status {
			case .working?:
				return now.timeIntervalSince(lastEvent) > TmuxMirror.Window.staleAfter ? .unknown : .working
			case .needsInput?: return .needsInput
			case .done?: return .done
			case nil: return .unknown
			}
		}
	}

	/// What one event did to the register, for the two things that draw it.
	///
	/// **Two questions, one answer.** The navigator asks "should I read this
	/// project's sessions again", which is a walk of somebody's scratchpad and
	/// is asked only when a session appeared, ended or finished a turn. The
	/// pill asks "did the counts move", which is a redraw of one control and is
	/// asked whenever the status changed as well — a session going from
	/// *started* to *working* moves the working count from nought to one and
	/// changes nothing in the tree. Answering both with one slug made the pill
	/// miss that first move or made the tree walk on every status change.
	public struct Moved: Equatable, Sendable {
		/// The project whose sessions moved.
		public let slug: String
		/// Whether the set of sessions, or what is under one, may have changed
		/// — the navigator's question.
		public let sessionsChanged: Bool
	}

	/// The two numbers on the pill, and the one in its tooltip.
	public struct Counts: Equatable, Sendable {
		public let working: Int
		public let needsInput: Int
		public let total: Int

		public init(working: Int, needsInput: Int, total: Int) {
			self.working = working
			self.needsInput = needsInput
			self.total = total
		}
	}

	/// The sessions of one project, for the popover.
	public struct Group: Equatable, Sendable {
		public let slug: String
		public let cwd: String
		public let sessions: [Session]
	}

	/// How long a working session may say nothing before it is forgotten.
	///
	/// A session killed mid-turn — `kill -9`, a machine put to sleep with the
	/// terminal gone when it wakes — sends no `SessionEnd`, and nothing else
	/// ever removes it. Thirty seconds of silence makes it hollow; ten minutes
	/// of it means nobody is coming back to answer for it. A session waiting
	/// for input or finished is never forgotten this way: those are states a
	/// session stays in for as long as somebody likes.
	public static let forgottenAfter: TimeInterval = 600

	/// Every record, by the session's id — or, for a seeded record, by the tmux
	/// window it stands for, so there can only be one per window.
	private var records: [String: Session] = [:]

	public init() {}

	/// The one register, because there is one machine.
	///
	/// **Not held by the window that draws the rows**, which is where it first
	/// sat: the notification is distributed to the *process*, two windows may be
	/// on the same project, and a session is running or it is not regardless of
	/// who is looking. Nor by the thing that listens for it, which the navigator
	/// would then need a way of reaching.
	@MainActor public static var shared = RunningSessions()

	public var isEmpty: Bool { records.isEmpty }

	/// Whether anything here changes with the clock — a working record going
	/// hollow, or a hollow one being forgotten — so the pill knows whether to
	/// tick.
	public var needsClock: Bool { records.values.contains { $0.status == .working } }

	// MARK: - What the hook says

	/// What one hook event does to this, and who should redraw.
	///
	/// Nil when the event changes nothing worth a redraw. **Not a list of event
	/// names**: what matters is whether the answer moved. A `PostToolUse` from a
	/// session already known to be working says nothing new and asks for
	/// nothing — and they arrive dozens of times a minute, each one otherwise
	/// starting a walk of somebody's scratchpad. The same event from a session
	/// nobody had heard of does change the answer, and gets its redraw.
	///
	/// A finished turn asks for a read as well, even though the set is
	/// unchanged: that is the moment files have landed, and the row that has
	/// been saying *running* with nothing under it may now have something.
	@discardableResult
	public mutating func note(_ payload: [String: String], now: Date = Date()) -> Moved? {
		guard let id = payload["session"], !id.isEmpty,
		      let cwd = payload["cwd"], !cwd.isEmpty
		else { return nil }
		let slug = AgentSessions.slug(ofPath: cwd)

		if payload["event"] == "SessionEnd" {
			guard records.removeValue(forKey: id) != nil else { return nil }
			return Moved(slug: slug, sessionsChanged: true)
		}

		let known = records[id]

		// **Nothing resurrects a finished turn** — the hook's own rule for a
		// tmux window whose badge says `done`, kept here for the sessions the
		// hook has no window to ask about. Claude sends an idle nudge a minute
		// after every answer, and a subagent can hand back work after the turn
		// that sent it off has ended; both arrived as "needs you" for a session
		// in one of the panel's own tabs, an amber row over an empty prompt.
		if let known, known.status == .done, Self.isNudgeOrHandback(payload) { return nil }

		var record = known ?? Session(
			id: id, slug: slug, cwd: cwd, status: nil,
			tmuxSession: nil, window: nil, windowName: nil,
			line: nil, message: nil, lastEvent: now
		)
		let before = record.status

		// An empty status is the hook saying "nothing to say about the state"
		// — a notification about a push going out, say — and leaves the badge
		// as it was, exactly as the hook leaves tmux's own option alone.
		let status = TmuxMirror.AIStatus(rawValue: payload["status"] ?? "")
		if let status { record.status = status }
		if let session = payload["tmuxSession"], !session.isEmpty {
			record.tmuxSession = session
			record.window = payload["window"].flatMap(Int.init)
			record.windowName = payload["windowName"]
			record.pane = payload["pane"]
		}
		if let terminal = payload["terminal"], !terminal.isEmpty {
			record.terminal = terminal
		}
		if let line = payload["announce"], !line.isEmpty {
			record.line = line
			record.message = payload["message"]
		}
		record.lastEvent = now
		records[id] = record

		// The session now speaks for itself, so a record seeded from its window
		// has nothing left to stand in for.
		if let session = record.tmuxSession, let window = record.window {
			records.removeValue(forKey: Self.seededKey(session: session, window: window))
		}

		let isNew = known == nil
		let turnEnded = status == .done
		let statusMoved = before != record.status
		guard isNew || turnEnded || statusMoved else { return nil }
		return Moved(slug: slug, sessionsChanged: isNew || turnEnded)
	}

	/// Whether `note` would leave this event unrecorded — so the corner can
	/// leave it unsaid. Asked before `note`, on the state the event arrives to.
	public func disregards(_ payload: [String: String]) -> Bool {
		guard let id = payload["session"], let known = records[id], known.status == .done else { return false }
		return Self.isNudgeOrHandback(payload)
	}

	/// Claude's idle nudge: the `Notification` it sends when nobody has typed
	/// for a while, which is not somebody being waited for.
	public static func isIdleNudge(_ payload: [String: String]) -> Bool {
		payload["event"] == "Notification" && payload["notificationType"]?.lowercased() == "idle_prompt"
	}

	private static func isNudgeOrHandback(_ payload: [String: String]) -> Bool {
		isIdleNudge(payload) || payload["event"] == "SubagentStop"
	}

	/// The sessions running in any of a project's spellings — the ones with an
	/// id, since that is what a row in the tree is named by.
	public func ids(forSlugs slugs: [String]) -> Set<String> {
		Set(records.values.filter { !$0.isSeeded && slugs.contains($0.slug) }.map(\.id))
	}

	/// Whether this event belongs to a project spelled any of these ways.
	public static func belongs(_ payload: [String: String], toSlugs slugs: [String]) -> Bool {
		guard let cwd = payload["cwd"], !cwd.isEmpty else { return false }
		// **Exactly, not by prefix.** A session started in a subdirectory is
		// filed under a key of its own and has a scratch directory of its own, so
		// it is not this project's session by any reading this feature can use.
		return slugs.contains(AgentSessions.slug(ofPath: cwd))
	}

	// MARK: - What the pill and the popover ask

	/// The two counts, against a clock: a working session that has fallen
	/// silent is under neither, and a finished one never is.
	public func counts(at now: Date = Date()) -> Counts {
		var working = 0, needs = 0
		for record in records.values {
			switch record.shown(at: now) {
			case .working: working += 1
			case .needsInput: needs += 1
			case .done, .unknown: break
			}
		}
		return Counts(working: working, needsInput: needs, total: records.count)
	}

	/// Every running session, grouped by project.
	///
	/// The projects named first come first, in the order given — the window's
	/// own, so the list opens on what is nearest — and the rest follow with the
	/// most recently heard project first. Within a group the windows of a tmux
	/// session come in tmux's order, and sessions outside any come after them,
	/// newest first.
	public func grouped(firstSlugs: [String], at now: Date = Date()) -> [Group] {
		var bySlug: [String: [Session]] = [:]
		for record in records.values { bySlug[record.slug, default: []].append(record) }

		func ordered(_ sessions: [Session]) -> [Session] {
			sessions.sorted { a, b in
				switch (a.window, b.window) {
				case let (x?, y?):
					if a.tmuxSession != b.tmuxSession { return (a.tmuxSession ?? "") < (b.tmuxSession ?? "") }
					return x < y
				case (_?, nil): return true
				case (nil, _?): return false
				case (nil, nil): return a.lastEvent > b.lastEvent
				}
			}
		}
		func group(_ slug: String) -> Group? {
			guard let sessions = bySlug[slug], let first = sessions.first else { return nil }
			return Group(slug: slug, cwd: first.cwd, sessions: ordered(sessions))
		}

		let leading = firstSlugs.compactMap(group)
		let rest = bySlug.keys
			.filter { !firstSlugs.contains($0) }
			.sorted { a, b in
				let latest = { (slug: String) in bySlug[slug]!.map(\.lastEvent).max() ?? .distantPast }
				return latest(a) > latest(b)
			}
			.compactMap(group)
		return leading + rest
	}

	/// The record for a session id, for whoever holds one.
	public func session(id: String) -> Session? { records[id] }

	// MARK: - What tmux already knew

	/// Records for the windows of the mirrored tmux session that the hook has
	/// not spoken for yet.
	///
	/// A session running before the app launched has announced nothing to this
	/// process. A working one announces itself within seconds, since every tool
	/// use is an event; one sitting at a prompt says nothing until it is asked
	/// something. The tabs already read `@ai_status` and `window_activity` for
	/// the one session they mirror, so a window with a state and no record gets
	/// one — enough to count and to reveal — and the hook's own replaces it at
	/// the session's next event. Nothing is seeded for sessions outside the
	/// mirrored tmux session; those appear when they next speak.
	///
	/// **Filed under the window's own directory**, which tmux reports, and
	/// under `cwd` — the panel's project — only for a window that has none. A
	/// tmux session is somebody's workspace and its windows sit in many
	/// projects; the first afternoon listed `screencasts` under `~/dev/oss`.
	///
	/// - Returns: whether anything a pill shows changed.
	@discardableResult
	public mutating func seed(
		windows: [TmuxMirror.Window], inTmuxSession session: String, cwd: String, now: Date = Date()
	) -> Bool {
		func home(of window: TmuxMirror.Window) -> String {
			window.directory.isEmpty ? cwd : window.directory
		}
		var changed = false

		let live = Dictionary(
			windows.filter { $0.aiStatus != nil }.map { ($0.index, $0) },
			uniquingKeysWith: { first, _ in first }
		)
		let spokenFor = Set(
			records.values
				.filter { !$0.isSeeded && $0.tmuxSession == session }
				.compactMap(\.window)
		)

		// Seeded records whose window is gone, has no badge any more, or now
		// has a session speaking for itself.
		for (key, record) in records where record.isSeeded && record.tmuxSession == session {
			guard let window = record.window, live[window] != nil, !spokenFor.contains(window) else {
				records.removeValue(forKey: key)
				changed = true
				continue
			}
		}

		for (index, window) in live where !spokenFor.contains(index) {
			let key = Self.seededKey(session: session, window: index)
			let lastEvent = now.addingTimeInterval(-window.silentFor)
			if var seeded = records[key] {
				let before = seeded.shown(at: now)
				seeded.status = window.aiStatus
				seeded.windowName = window.name
				seeded.lastEvent = lastEvent
				records[key] = seeded
				if seeded.shown(at: now) != before { changed = true }
				continue
			}
			let directory = home(of: window)
			records[key] = Session(
				id: "", slug: AgentSessions.slug(ofPath: directory), cwd: directory, status: window.aiStatus,
				tmuxSession: session, window: index, windowName: window.name,
				line: nil, message: nil, lastEvent: lastEvent
			)
			changed = true
		}
		return changed
	}

	/// Drops what was seeded from a tmux session the panel has stopped
	/// mirroring: nothing will read those windows again, so nothing would ever
	/// take the records away.
	@discardableResult
	public mutating func forgetSeeded(inTmuxSession session: String?) -> Bool {
		guard let session else { return false }
		let keys = records.filter { $0.value.isSeeded && $0.value.tmuxSession == session }.keys
		for key in keys { records.removeValue(forKey: key) }
		return !keys.isEmpty
	}

	private static func seededKey(session: String, window: Int) -> String {
		"@\(session):\(window)"
	}

	// MARK: - The clock

	/// Forgets the working sessions that have said nothing for
	/// `forgottenAfter`.
	///
	/// - Returns: whether anything was forgotten.
	@discardableResult
	public mutating func prune(at now: Date = Date()) -> Bool {
		let forgotten = records.filter { _, record in
			record.status == .working && now.timeIntervalSince(record.lastEvent) > Self.forgottenAfter
		}
		for key in forgotten.keys { records.removeValue(forKey: key) }
		return !forgotten.isEmpty
	}
}

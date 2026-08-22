import Foundation

/// Which Claude Code sessions are running, per project, from the hook.
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
/// Nothing here reads a disk or asks a process. The alternatives both did and
/// neither could answer: a watcher on `/tmp/claude-<uid>` rebuilds a root nobody
/// is looking at for somebody else's session, several times a second, and the
/// process table cannot say *which* session a `claude` process is, because its
/// id is nowhere in the arguments.
public struct RunningSessions: Equatable, Sendable {
	/// Session ids by the slug of the `cwd` they were announced from.
	///
	/// **Keyed by slug and not by path**, so that the lookup is the same key the
	/// scratch directories are filed under and `/tmp` against `/private/tmp`
	/// stops being a special case: `AgentSessions.slugs(of:)` already offers a
	/// project both of its spellings and either may be the one the shell had.
	private var byProject: [String: Set<String>] = [:]

	public init() {}

	/// The one register, because there is one machine.
	///
	/// **Not held by the window that draws the rows**, which is where it first
	/// sat: the notification is distributed to the *process*, two windows may be
	/// on the same project, and a session is running or it is not regardless of
	/// who is looking. Nor by the thing that listens for it, which the navigator
	/// would then need a way of reaching.
	@MainActor public static var shared = RunningSessions()

	/// What one hook event does to this, and whether anybody showing that
	/// project should read their sessions again.
	///
	/// Returns the slug whose root wants re-reading, or nil when the event
	/// changes nothing worth a redraw. **Not a list of event names**: what
	/// matters is whether the answer moved. A `PostToolUse` from a session
	/// already known to be running says nothing new and asks for nothing — and
	/// they arrive dozens of times a minute, each one otherwise starting a walk
	/// of somebody's scratchpad. The same event from a session nobody had heard
	/// of does change the answer, and gets its redraw.
	///
	/// A finished turn asks for one as well, even though the set is unchanged:
	/// that is the moment files have landed, and the row that has been saying
	/// *running* with nothing under it may now have something.
	@discardableResult
	public mutating func note(_ payload: [String: String]) -> String? {
		guard let id = payload["session"], !id.isEmpty,
		      let cwd = payload["cwd"], !cwd.isEmpty
		else { return nil }
		let slug = AgentSessions.slug(ofPath: cwd)

		if payload["event"] == "SessionEnd" {
			guard byProject[slug]?.remove(id) != nil else { return nil }
			if byProject[slug]?.isEmpty == true { byProject[slug] = nil }
			return slug
		}

		let isNew = byProject[slug, default: []].insert(id).inserted
		let turnEnded = payload["status"] == TmuxMirror.AIStatus.done.rawValue
		return isNew || turnEnded ? slug : nil
	}

	/// The sessions running in any of a project's spellings.
	public func ids(forSlugs slugs: [String]) -> Set<String> {
		slugs.reduce(into: Set<String>()) { $0.formUnion(byProject[$1] ?? []) }
	}

	/// Whether this event belongs to a project spelled any of these ways.
	public static func belongs(_ payload: [String: String], toSlugs slugs: [String]) -> Bool {
		guard let cwd = payload["cwd"], !cwd.isEmpty else { return false }
		// **Exactly, not by prefix.** A session started in a subdirectory is
		// filed under a key of its own and has a scratch directory of its own, so
		// it is not this project's session by any reading this feature can use.
		return slugs.contains(AgentSessions.slug(ofPath: cwd))
	}
}

import Foundation

/// Two Abydos windows on one tmux server without moving each other.
///
/// A tmux session has one current window, and every client attached to it shows
/// that one. Two windows' terminals on one session were two clients of it: a tab
/// chosen in either switched both, a window made in either jumped both to it, and
/// tmux sized the shared window to fit them together. Reported 2026-10-22 as the
/// terminals "acting weird" in a second window.
///
/// tmux's own answer is a group: `new-session -t <session> -s <name>` makes a
/// session that shares the other's windows and keeps a current window of its
/// own. So a terminal arriving at a session another window is on is given one of
/// those instead — by attaching that way, or, when it got there by `C-b s` or
/// `C-b w`, by being moved to one straight after. A session made like that is
/// set to go when its last client does (`destroy-unattached`), so a window
/// closed, a window moved on, or the app killed leaves nothing behind.
///
/// Everything here is the decision, and none of it runs tmux.
public enum TmuxGroups {
	/// How a terminal for a session is to be attached.
	public enum Attach: Equatable, Sendable {
		/// The session itself, made if it is not there: `new -A -s`.
		case session(String)
		/// A session of its own in the named one's group, because another window
		/// is on that one. It goes when its client does.
		case grouped(joining: String, as: String)
		/// The session itself under its own name, put back into the group that
		/// outlived it: `new -t <member> -s <name>`. Not one that goes when its
		/// client does — it is the session a project remembers.
		case rejoined(member: String, as: String)
	}

	/// How to attach a terminal to `session`, given the sessions on the server
	/// and which of them other windows' terminals are on.
	///
	/// - Another window on the session: a grouped one of our own.
	/// - The session gone and its group not — somebody killed it, or it was the
	///   first of several and went — the group is joined under the session's
	///   name, rather than a new, empty session made beside it. A project's
	///   session holding its agents is the point of attaching to it at all.
	/// - Otherwise the session itself, made if need be.
	public static func attach(
		to session: String,
		sessions: [TmuxMirror.SessionSummary],
		heldElsewhere: Set<String>
	) -> Attach {
		let names = Set(sessions.map(\.name))
		if names.contains(session) {
			guard heldElsewhere.contains(session) else { return .session(session) }
			return .grouped(joining: session, as: freeName(for: session, among: names))
		}
		// The group of a session that has gone is still named after it.
		if let member = sessions.first(where: { $0.group == session }) {
			return .rejoined(member: member.name, as: session)
		}
		return .session(session)
	}

	/// A name for a grouped session of `base` that nothing on the server has.
	///
	/// `<base>~2`, `<base>~3`, …, the lowest free: it is what shows in `C-b s`
	/// and `tmux ls`, where nothing hides it, so it should read as "another view
	/// of `base`" at a glance. tmux will not take `:` or `.` in a session name;
	/// `~` it takes.
	public static func freeName(for base: String, among names: Set<String>) -> String {
		var number = 2
		while names.contains("\(base)~\(number)") { number += 1 }
		return "\(base)~\(number)"
	}

	/// The session a project remembers for one a terminal is on: the group's,
	/// for a session in one, since a grouped session of our own goes with the
	/// window and would be nothing to come back to.
	public static func base(of session: String, in sessions: [TmuxMirror.SessionSummary]) -> String {
		sessions.first(where: { $0.name == session })?.group ?? session
	}

	/// The sessions as somebody choosing between them should see them: a group
	/// as one row, under the session the group is named after when it is still
	/// there and under its oldest member when it is not, attached if any member
	/// is. In the order given.
	public static func shownAsOne(_ sessions: [TmuxMirror.SessionSummary]) -> [TmuxMirror.SessionSummary] {
		var shown: [TmuxMirror.SessionSummary] = []
		var seenGroups: Set<String> = []
		for session in sessions {
			guard let group = session.group else {
				shown.append(session)
				continue
			}
			guard !seenGroups.contains(group) else { continue }
			seenGroups.insert(group)
			let members = sessions.filter { $0.group == group }
			let named = members.first(where: { $0.name == group }) ?? members.min(by: { $0.created < $1.created }) ?? session
			shown.append(TmuxMirror.SessionSummary(
				name: named.name,
				windowCount: named.windowCount,
				isAttached: members.contains(where: \.isAttached),
				created: named.created,
				group: group
			))
		}
		return shown
	}

	/// The other sessions in the group `session` is in.
	public static func groupMates(of session: String, in sessions: [TmuxMirror.SessionSummary]) -> Set<String> {
		guard let group = sessions.first(where: { $0.name == session })?.group else { return [] }
		return Set(sessions.filter { $0.group == group && $0.name != session }.map(\.name))
	}
}

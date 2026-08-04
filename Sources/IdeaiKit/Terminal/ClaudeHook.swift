import Foundation

/// What Claude Code tells us about a session, and what it means for a tab.
///
/// Claude Code runs a command on its own events and hands it the event as JSON
/// on stdin. That is the only honest source for "is this session working, or
/// waiting for me": a pane running `node` looks identical in every state, and
/// reading the screen would be guessing at a picture drawn for a person.
///
/// This is the part with no side effects — the event, what state it means, and
/// what is worth saying out loud — so the mapping can be tested against the
/// real payloads rather than by running Claude and watching tabs.
public enum ClaudeHook {
	/// One event, with the fields that matter here.
	public struct Event: Equatable, Sendable {
		public let name: String
		public let sessionID: String
		/// Where the session is working, which is what names it for a person.
		public let cwd: String
		/// What Claude wants to say, on the events that carry a message.
		public let message: String?
		/// Which kind of notification it is, on the events that have one.
		///
		/// The field that matters: a `Notification` is not by itself somebody
		/// being waited for. Claude sends them for signing in, for a push
		/// having gone out, for compaction — and treating all of those as
		/// "needs you" is how an amber badge stops meaning anything.
		public let notificationType: String?
		/// A `Stop` that is only a pause: Claude carries on afterwards, so it
		/// is not the end of a turn and must not read as one.
		public let isIntermediateStop: Bool

		public init(
			name: String,
			sessionID: String = "",
			cwd: String = "",
			message: String? = nil,
			notificationType: String? = nil,
			isIntermediateStop: Bool = false
		) {
			self.name = name
			self.sessionID = sessionID
			self.cwd = cwd
			self.message = message
			self.notificationType = notificationType
			self.isIntermediateStop = isIntermediateStop
		}
	}

	/// Reads the JSON Claude Code writes to the hook's stdin.
	public static func parse(_ data: Data) -> Event? {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let name = object["hook_event_name"] as? String, !name.isEmpty
		else { return nil }

		return Event(
			name: name,
			sessionID: object["session_id"] as? String ?? "",
			cwd: object["cwd"] as? String ?? "",
			message: object["message"] as? String,
			notificationType: object["notification_type"] as? String,
			isIntermediateStop: object["stop_hook_active"] as? Bool ?? false
		)
	}

	/// What the tab should say after this event.
	///
	/// `nil` means the window has nothing to show — the session has ended, or
	/// the event is one this does not speak for.
	public static func status(after event: Event) -> TmuxMirror.AIStatus? {
		switch event.name {
		// Work starting, and work carrying on after an answer: the second is
		// why a ⚠ clears the moment somebody replies rather than lingering
		// until the whole turn is done.
		case "UserPromptSubmit", "PostToolUse", "PreToolUse":
			return .working
		case "Notification":
			// Only the ones that are actually about somebody being waited for.
			// Anything else — compaction, a push going out, signing in — leaves
			// the badge as it was: a session that was working still is.
			return wantsAnswer(event) ? .needsInput : nil
		case "Stop":
			return event.isIntermediateStop ? .working : .done
		// A subagent finishing is not the session finishing: the one that sent
		// it off is still going, and a tab that says ✓ while the main session
		// is mid-turn is worse than saying nothing.
		case "SubagentStop":
			return .working
		case "SessionStart", "SessionEnd":
			return nil
		default:
			return nil
		}
	}

	/// Whether this event should be said out loud rather than only drawn.
	///
	/// The ones worth crossing a room for: a session that wants an answer, one
	/// that has finished, and a subagent handing its work back. Everything else
	/// is progress, and progress that interrupts is just noise.
	public static func isWorthAnnouncing(_ event: Event) -> Bool {
		switch event.name {
		case "Notification":  return wantsAnswer(event)
		case "Stop":          return !event.isIntermediateStop
		case "SubagentStop":  return true
		default:              return false
		}
	}

	/// The one line for it, which always begins with where it happened.
	///
	/// The window comes first in every case, including a subagent's: "a
	/// subagent finished" on its own is a sentence about nowhere. What
	/// somebody needs from the corner of their eye is which of eight tabs is
	/// talking.
	public static func announcement(for event: Event, window: String) -> String? {
		guard isWorthAnnouncing(event) else { return nil }
		let name = window.isEmpty ? "A Claude session" : window
		switch event.name {
		case "Notification":  return "\(name) needs you"
		case "Stop":          return "\(name) finished"
		case "SubagentStop":  return "\(name) · a subagent finished"
		default:              return nil
		}
	}

	/// Whether a notification is Claude waiting on a person.
	///
	/// `notification_type` says so outright, and is the field to trust:
	/// `agent_needs_input`, `idle_prompt` and a permission prompt are somebody
	/// being waited for; `auth_success`, `push_notification` and the rest are
	/// Claude talking to itself. Older versions send no type, so the message is
	/// read instead — the two sentences it uses when it is waiting.
	static func wantsAnswer(_ event: Event) -> Bool {
		if let type = event.notificationType?.lowercased(), !type.isEmpty {
			return type.contains("needs_input")
				|| type.contains("permission")
				|| type == "idle_prompt"
		}
		let message = (event.message ?? "").lowercased()
		return message.contains("needs your permission")
			|| message.contains("waiting for your input")
			|| message.contains("permission to use")
	}

	/// Whether a notification is only the nudge Claude sends when nobody has
	/// answered it yet.
	///
	/// It arrives moments after a turn ends as well as when Claude is stopped
	/// mid-turn waiting, and the two mean different things to a tab: after a
	/// finished turn there is nothing being waited for that a ✓ does not
	/// already say. Only the caller knows which of the two happened, because
	/// only the caller knows what the tab said before.
	public static func isIdleNudge(_ event: Event) -> Bool {
		event.notificationType?.lowercased() == "idle_prompt"
	}

	/// What a nudge means, given what the window already said.
	///
	/// A turn that finished stays finished: the badge said ✓ a second ago, and
	/// turning it amber because nobody has typed since is how a "needs you"
	/// stops meaning "go and look at this one".
	public static func status(after event: Event, whenWindowSays current: AIStatusName?) -> TmuxMirror.AIStatus? {
		if isIdleNudge(event), current == .done { return nil }
		return status(after: event)
	}

	/// What the window option currently holds, as far as this cares.
	public typealias AIStatusName = TmuxMirror.AIStatus

	/// Whether this event should be announced, given what the window said.
	public static func isWorthAnnouncing(_ event: Event, whenWindowSays current: AIStatusName?) -> Bool {
		if isIdleNudge(event), current == .done { return false }
		return isWorthAnnouncing(event)
	}

	/// The detail behind the line: whatever Claude said, if it said anything.
	public static func detail(for event: Event) -> String? {
		guard let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines),
		      !message.isEmpty
		else { return nil }
		return message
	}

	/// The name of the notification the hook posts and the app listens for.
	///
	/// Distributed, because the hook is a separate process: Claude Code starts
	/// it, it does its work in a few milliseconds and exits, and the app it is
	/// talking to may not even be running.
	public static let notificationName = "de.rnd7.ideai.claude"
}

import Foundation
import Testing
@testable import IdeaiKit

/// Reading Claude Code's own events, which is the only honest way to know what
/// a session is doing: a pane running `node` looks the same in every state.
struct ClaudeHookTests {
	private func event(_ json: String) -> ClaudeHook.Event? {
		ClaudeHook.parse(Data(json.utf8))
	}

	@Test func readsWhatClaudeSends() {
		let parsed = event("""
		{"hook_event_name": "Notification", "session_id": "abc123",
		 "cwd": "/Users/x/dev/ideai", "transcript_path": "/tmp/t.jsonl",
		 "message": "Claude needs your permission to use Bash"}
		""")

		#expect(parsed?.name == "Notification")
		#expect(parsed?.sessionID == "abc123")
		#expect(parsed?.cwd == "/Users/x/dev/ideai")
		#expect(parsed?.message == "Claude needs your permission to use Bash")
	}

	@Test func anythingThatIsNotAnEventIsNotOne() {
		#expect(event("not json") == nil)
		#expect(event("{\"session_id\": \"a\"}") == nil, "no event name")
		#expect(event("{\"hook_event_name\": \"\"}") == nil)
	}

	// MARK: - What a tab should say

	@Test func workStartingAndCarryingOnBothReadAsWorking() {
		for name in ["UserPromptSubmit", "PreToolUse", "PostToolUse"] {
			#expect(ClaudeHook.status(after: .init(name: name)) == .working, "\(name)")
		}
	}

	@Test func aNotificationIsSomebodyBeingWaitedFor() {
		#expect(ClaudeHook.status(after: .init(name: "Notification")) == .needsInput)
	}

	@Test func aFinishedTurnIsDone() {
		#expect(ClaudeHook.status(after: .init(name: "Stop")) == .done)
	}

	/// Claude stops and carries on several times inside one turn; that is not
	/// the turn ending, and a ✓ that appears mid-turn teaches people to ignore
	/// the badge.
	@Test func anIntermediateStopIsStillWorking() {
		#expect(ClaudeHook.status(after: .init(name: "Stop", isIntermediateStop: true)) == .working)
	}

	/// The one this gets right that a tab-level state easily gets wrong: the
	/// session that sent the subagent off is still going.
	@Test func aSubagentFinishingDoesNotFinishTheSession() {
		#expect(ClaudeHook.status(after: .init(name: "SubagentStop")) == .working)
	}

	@Test func anEndedSessionLeavesNoBadge() {
		#expect(ClaudeHook.status(after: .init(name: "SessionEnd")) == nil)
		#expect(ClaudeHook.status(after: .init(name: "SessionStart")) == nil)
	}

	// MARK: - What is said out loud

	/// Progress is not news. Only the two things somebody would get up for,
	/// and a subagent handing work back.
	@Test func onlyTheEventsWorthInterruptingFor() {
		#expect(ClaudeHook.isWorthAnnouncing(.init(name: "Notification")))
		#expect(ClaudeHook.isWorthAnnouncing(.init(name: "Stop")))
		#expect(!ClaudeHook.isWorthAnnouncing(.init(name: "Stop", isIntermediateStop: true)))
		#expect(!ClaudeHook.isWorthAnnouncing(.init(name: "PostToolUse")))
		#expect(!ClaudeHook.isWorthAnnouncing(.init(name: "UserPromptSubmit")))
	}

	/// Every line begins with where it happened — including a subagent's.
	/// "A subagent finished" is a sentence about nowhere, and the thing
	/// somebody needs from the corner of their eye is which of eight tabs is
	/// talking.
	@Test func everyAnnouncementNamesItsWindow() {
		#expect(ClaudeHook.announcement(for: .init(name: "Notification"), window: "docscanner")
			== "docscanner needs you")
		#expect(ClaudeHook.announcement(for: .init(name: "Stop"), window: "pulse")
			== "pulse finished")
		#expect(ClaudeHook.announcement(for: .init(name: "SubagentStop"), window: "ideai")
			== "ideai · a subagent finished")
	}

	@Test func aSessionOutsideTmuxStillSaysSomething() {
		#expect(ClaudeHook.announcement(for: .init(name: "Stop"), window: "")
			== "A Claude session finished")
	}

	@Test func nothingIsSaidAboutProgress() {
		#expect(ClaudeHook.announcement(for: .init(name: "PostToolUse"), window: "ideai") == nil)
	}

	/// What Claude said goes in the detail, when it said anything: "needs your
	/// permission to use Bash" is the difference between getting up now and
	/// getting up later.
	@Test func theMessageBecomesTheDetail() {
		#expect(ClaudeHook.detail(for: .init(name: "Notification", message: "Permission to use Bash"))
			== "Permission to use Bash")
		#expect(ClaudeHook.detail(for: .init(name: "Notification", message: "  \n ")) == nil)
		#expect(ClaudeHook.detail(for: .init(name: "Stop")) == nil)
	}
}

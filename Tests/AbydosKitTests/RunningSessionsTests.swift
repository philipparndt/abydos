import Foundation
import Testing
@testable import AbydosKit

/// Which sessions the hook says are running.
///
/// Every payload here is the shape `ClaudeHookRunner.announce` posts — the same
/// keys, including the ones it leaves out — because the whole point of reading
/// the hook is that it states a fact, and a test against an invented shape would
/// be checking this file against itself.
struct RunningSessionsTests {
	private func payload(
		_ event: String, session: String = "s-1", cwd: String = "/Users/x/dev/probe",
		status: String? = nil
	) -> [String: String] {
		var payload = ["event": event, "session": session, "cwd": cwd]
		if let status { payload["status"] = status }
		return payload
	}

	private let slugs = ["-Users-x-dev-probe"]

	@Test func aSessionStartsAndEnds() {
		var running = RunningSessions()
		#expect(running.note(payload("SessionStart")) == "-Users-x-dev-probe")
		#expect(running.ids(forSlugs: slugs) == ["s-1"])

		#expect(running.note(payload("SessionEnd")) == "-Users-x-dev-probe")
		#expect(running.ids(forSlugs: slugs).isEmpty)
	}

	/// **The one that decides whether this is affordable.** A session at work
	/// sends one of these on every tool use, dozens a minute, and counting what
	/// is under a session means walking it.
	@Test func aToolUseFromAKnownSessionAsksForNothing() {
		var running = RunningSessions()
		running.note(payload("SessionStart"))
		#expect(running.note(payload("PreToolUse", status: "working")) == nil)
		#expect(running.note(payload("PostToolUse", status: "working")) == nil)
		#expect(running.ids(forSlugs: slugs) == ["s-1"])
	}

	/// And the same event from a session nobody had heard of does change the
	/// answer — which is how a session that started before the app did is found
	/// without anybody asking a process table.
	@Test func aToolUseFromAnUnknownSessionIsNews() {
		var running = RunningSessions()
		#expect(running.note(payload("PostToolUse", session: "s-2", status: "working")) == "-Users-x-dev-probe")
		#expect(running.ids(forSlugs: slugs) == ["s-2"])
	}

	/// A finished turn is the moment files have landed, so the row saying
	/// `running` with nothing under it may now have something.
	@Test func aFinishedTurnAsksForAReadEvenThoughNothingMoved() {
		var running = RunningSessions()
		running.note(payload("SessionStart"))
		#expect(running.note(payload("Stop", status: "working")) == nil)
		#expect(running.note(payload("Stop", status: "done")) == "-Users-x-dev-probe")
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
}

import Foundation
import Testing
@testable import AbydosKit

/// The hook itself, run as Claude Code runs it, against a real tmux session.
///
/// The mapping has unit tests; this is the plumbing around it — reading what
/// the window already says, writing what it should say now — which is where
/// both of the badge bugs actually lived. Skipped where tmux or the built
/// binary is missing.
@Suite(.serialized)
struct ClaudeHookLiveTests {
	private var tmux: String? { Executables.locate("tmux") }

	/// The hook binary, wherever this package was built.
	///
	/// Not beside the test bundle: SwiftPM puts the products in an
	/// architecture-named directory, and a test that silently found nothing
	/// would pass while testing nothing.
	private var hook: URL? {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()   // AbydosKitTests
			.deletingLastPathComponent()   // Tests
			.deletingLastPathComponent()   // the package
		let build = root.appendingPathComponent(".build")
		let candidates = [
			build.appendingPathComponent("debug/abydos-hook"),
			build.appendingPathComponent("release/abydos-hook"),
		] + ((try? FileManager.default.contentsOfDirectory(atPath: build.path)) ?? [])
			.filter { $0.contains("apple-macosx") }
			.flatMap { architecture in
				["debug", "release"].map {
					build.appendingPathComponent("\(architecture)/\($0)/abydos-hook")
				}
			}
		return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
	}

	@discardableResult
	private func run(_ launchPath: String, _ arguments: [String], input: String? = nil) -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments

		let output = Pipe()
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice

		var environment = ProcessInfo.processInfo.environment
		if let pane { environment["TMUX_PANE"] = pane }
		process.environment = environment

		if let input {
			let stdin = Pipe()
			process.standardInput = stdin
			try? process.run()
			stdin.fileHandleForWriting.write(Data(input.utf8))
			try? stdin.fileHandleForWriting.close()
		} else {
			try? process.run()
		}
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// The pane the events are pretended to come from.
	private var pane: String?

	private mutating func startSession(_ name: String) -> Bool {
		guard let tmux else { return false }
		run(tmux, ["kill-session", "-t", name])
		run(tmux, ["new-session", "-d", "-s", name, "-x", "80", "-y", "24"])
		pane = run(tmux, ["list-panes", "-t", name, "-F", "#{pane_id}"])
			.split(separator: "\n").first.map(String.init)
		return pane != nil
	}

	private func badge() -> String {
		guard let tmux, let pane else { return "" }
		// Asked of the pane the events were fired from, not of `session:0`: a
		// machine whose tmux.conf says `base-index 1` has no window 0 at all,
		// and asking for one read as an empty badge on every claim here — nine
		// expectation failures whose real subject was somebody's dotfile.
		return run(tmux, ["show-options", "-w", "-t", pane, "-v", "@ai_status"])
	}

	/// The sequence from the tab strip, through the binary Claude Code runs.
	@Test mutating func aTurnThatEndsStaysEnded() throws {
		let tmux = try #require(self.tmux)
		let hook = try #require(self.hook, "run `swift build` so abydos-hook is beside the tests")
		let session = "abydos-hook-live-\(UUID().uuidString.prefix(8))"
		try #require(startSession(session))
		defer { run(tmux, ["kill-session", "-t", session]) }

		func fire(_ json: String) {
			run(hook.path, [], input: json)
		}

		fire(#"{"hook_event_name":"UserPromptSubmit","cwd":"/x"}"#)
		#expect(badge() == "working")

		fire(#"{"hook_event_name":"SubagentStop","cwd":"/x"}"#)
		#expect(badge() == "working", "a subagent finishing mid-turn changes nothing")

		fire(#"{"hook_event_name":"Stop","cwd":"/x"}"#)
		#expect(badge() == "done")

		// The two that used to unfinish it.
		fire(#"{"hook_event_name":"SubagentStop","cwd":"/x"}"#)
		#expect(badge() == "done", "a straggling subagent")

		fire(#"{"hook_event_name":"Notification","cwd":"/x","notification_type":"idle_prompt"}"#)
		#expect(badge() == "done", "the nudge about nobody having answered")

		fire(#"{"hook_event_name":"UserPromptSubmit","cwd":"/x"}"#)
		#expect(badge() == "working", "and the next turn starts it again")
	}

	/// Being asked something really does warn, whatever the tab said before.
	@Test mutating func aPermissionPromptWarnsEvenAfterAFinishedTurn() throws {
		let tmux = try #require(self.tmux)
		let hook = try #require(self.hook)
		let session = "abydos-hook-live-\(UUID().uuidString.prefix(8))"
		try #require(startSession(session))
		defer { run(tmux, ["kill-session", "-t", session]) }

		run(hook.path, [], input: #"{"hook_event_name":"Stop","cwd":"/x"}"#)
		#expect(badge() == "done")

		run(hook.path, [], input: """
		{"hook_event_name":"Notification","cwd":"/x",
		 "notification_type":"worker_permission_prompt",
		 "message":"Claude needs your permission to use Bash"}
		""")
		#expect(badge() == "needs")
	}

	/// A session that ends takes its badge with it, rather than leaving a tab
	/// claiming something is happening in a window nobody is working in.
	@Test mutating func endingASessionClearsTheBadge() throws {
		let tmux = try #require(self.tmux)
		let hook = try #require(self.hook)
		let session = "abydos-hook-live-\(UUID().uuidString.prefix(8))"
		try #require(startSession(session))
		defer { run(tmux, ["kill-session", "-t", session]) }

		run(hook.path, [], input: #"{"hook_event_name":"UserPromptSubmit","cwd":"/x"}"#)
		#expect(badge() == "working")

		run(hook.path, [], input: #"{"hook_event_name":"SessionEnd","cwd":"/x"}"#)
		#expect(badge().isEmpty)
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// Editing somebody's own `~/.claude/settings.json`.
struct ClaudeHookSetupTests {
	/// **The command as it actually is today.** These tests were written when the
	/// app was called ideai and the hook was `ideai claude-hook`, and they went
	/// on asserting against that string after the binary became `abydos-hook` —
	/// so `isOurs`, which looked for `ideai` *and* `claude-hook`, was false for
	/// every entry the app now writes and no test noticed. Remove did nothing
	/// and a moved app left its old entry beside the new one.
	private let command = "/Applications/Abydos.app/Contents/MacOS/abydos-hook"

	/// What the entry looked like before the project was renamed, which an
	/// upgrade still has to recognise and replace.
	private let historical = "/Applications/ideai.app/Contents/MacOS/ideai claude-hook"

	private func commands(_ settings: [String: Any], _ event: String) -> [String] {
		let hooks = settings["hooks"] as? [String: Any] ?? [:]
		let matchers = (hooks[event] as? [[String: Any]]) ?? []
		return matchers.flatMap { matcher in
			((matcher["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
		}
	}

	@Test func everyEventIsWiredUp() {
		let settings = ClaudeHookSetup.adding(command: command, to: [:])
		for event in ClaudeHookSetup.events {
			#expect(commands(settings, event) == [command], "\(event)")
		}
	}

	/// Somebody's own settings are not ours to rearrange: everything that is
	/// not a hook, and every hook that is not one of ours, comes through
	/// untouched.
	@Test func nothingElseInTheFileIsDisturbed() {
		let before: [String: Any] = [
			"model": "opus",
			"permissions": ["allow": ["Bash(git:*)"]],
			"hooks": [
				"PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "audit.sh"]]]],
			],
		]
		let after = ClaudeHookSetup.adding(command: command, to: before)

		#expect(after["model"] as? String == "opus")
		#expect(((after["permissions"] as? [String: Any])?["allow"] as? [String]) == ["Bash(git:*)"])
		#expect(commands(after, "PreToolUse") == ["audit.sh"], "somebody else's hook stays")
	}

	/// Run twice — after an upgrade, say — and there is still one of ours per
	/// event, pointing at where the app is now.
	@Test func installingTwiceLeavesOneOfEach() {
		var settings = ClaudeHookSetup.adding(command: command, to: [:])
		settings = ClaudeHookSetup.adding(command: command, to: settings)
		#expect(commands(settings, "Stop") == [command])
	}

	@Test func anAppThatMovedReplacesItsOldEntry() {
		let old = "/Users/x/dev/abydos/.build/debug/abydos-hook"
		var settings = ClaudeHookSetup.adding(command: old, to: [:])
		settings = ClaudeHookSetup.adding(command: command, to: settings)
		#expect(commands(settings, "Stop") == [command])
	}

	/// The upgrade path: a settings file written before the rename holds an
	/// `ideai claude-hook` entry, and installing over it must replace that
	/// rather than leave both — two entries announce everything twice.
	@Test func theEntryFromBeforeTheRenameIsReplaced() {
		var settings = ClaudeHookSetup.adding(command: historical, to: [:])
		settings = ClaudeHookSetup.adding(command: command, to: settings)
		#expect(commands(settings, "Stop") == [command])
	}

	/// And it can be taken out, which is what the switch in Settings needs: the
	/// test for ours looked for a name the binary no longer has, so `remove`
	/// removed nothing at all.
	@Test func removingWorksForTheNameTheBinaryActuallyHas() {
		let settings = ClaudeHookSetup.adding(command: command, to: [:])
		let after = ClaudeHookSetup.removing(from: settings)
		#expect(after["hooks"] == nil, "every entry was ours, so the key goes too")
		#expect(!ClaudeHookSetup.isInstalled(command: command, in: after))
	}

	/// This replaces cmanager, and leaving both would set the same tmux option
	/// twice and announce everything twice — once in tmux's status line and
	/// once in the corner of the window.
	@Test func cmanagerIsShownTheDoor() {
		let before: [String: Any] = [
			"hooks": [
				"Stop": [["matcher": "", "hooks": [["type": "command", "command": "cmanager hook"]]]],
				"Notification": [["matcher": "", "hooks": [["type": "command", "command": "cmanager hook"]]]],
			],
		]
		let after = ClaudeHookSetup.adding(command: command, to: before)
		#expect(commands(after, "Stop") == [command])
		#expect(commands(after, "Notification") == [command])
	}

	@Test func removingTakesOnlyOurs() {
		var settings: [String: Any] = [
			"hooks": [
				"PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "audit.sh"]]]],
			],
		]
		settings = ClaudeHookSetup.adding(command: command, to: settings)
		let after = ClaudeHookSetup.removing(from: settings)

		#expect(commands(after, "PreToolUse") == ["audit.sh"])
		#expect(commands(after, "Stop").isEmpty)
		// An event nobody listens to any more should not linger as an empty
		// array in somebody's file.
		#expect((after["hooks"] as? [String: Any])?["Stop"] == nil)
	}

	@Test func aFileWithNoHooksLeftLosesTheKeyEntirely() {
		let settings = ClaudeHookSetup.adding(command: command, to: ["model": "opus"])
		let after = ClaudeHookSetup.removing(from: settings)
		#expect(after["hooks"] == nil)
		#expect(after["model"] as? String == "opus")
	}

	@Test func itKnowsWhetherItIsInstalled() {
		#expect(!ClaudeHookSetup.isInstalled(command: command, in: [:]))
		let settings = ClaudeHookSetup.adding(command: command, to: [:])
		#expect(ClaudeHookSetup.isInstalled(command: command, in: settings))
		#expect(!ClaudeHookSetup.isInstalled(command: "/elsewhere/ideai claude-hook", in: settings))
	}

	// MARK: - The file

	@Test func readingAndWritingKeepsACopyOfWhatWasThere() throws {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("claude-hooks-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("settings.json")

		try #require(ClaudeHookSetup.read(at: file).isEmpty, "no file yet is not an error")

		try "{\"model\": \"opus\"}".write(to: file, atomically: true, encoding: .utf8)
		let settings = try ClaudeHookSetup.read(at: file)
		let backup = try ClaudeHookSetup.write(
			ClaudeHookSetup.adding(command: command, to: settings), to: file
		)

		#expect(ClaudeHookSetup.isInstalled(command: command, in: try ClaudeHookSetup.read(at: file)))
		let saved = try #require(backup)
		#expect(try String(contentsOf: saved, encoding: .utf8).contains("opus"))
	}

	/// A settings file that is not JSON is somebody's problem to fix, not
	/// something to overwrite with a fresh one.
	@Test func nonsenseIsNotReplaced() throws {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("claude-hooks-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("settings.json")
		try "{ not json".write(to: file, atomically: true, encoding: .utf8)

		#expect(throws: ClaudeHookSetup.Failure.self) { try ClaudeHookSetup.read(at: file) }
	}
}

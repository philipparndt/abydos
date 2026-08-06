import Foundation

/// Wiring ideai into `~/.claude/settings.json`, and out of it again.
///
/// Claude Code will not tell anyone what its sessions are doing unless it is
/// asked to, and asking means an entry per event in a file the user owns and
/// has their own things in. So this edits it the way somebody would want their
/// own settings edited: only the entries that are ours, never a rewrite, and a
/// backup first.
public enum ClaudeHookSetup {
	/// The events worth listening to, and why each one is there.
	///
	/// Both halves of "working" are needed: `UserPromptSubmit` catches the
	/// start of a turn, and `PostToolUse` catches work resuming after an
	/// answer, which is what makes a "needs you" badge clear the moment it is
	/// answered rather than at the end of the turn.
	public static let events = [
		"Notification",
		"UserPromptSubmit",
		"PostToolUse",
		"Stop",
		"SubagentStop",
		"SessionStart",
		"SessionEnd",
	]

	public static var settingsURL: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".claude/settings.json")
	}

	/// Adds ideai's hooks to a settings object, leaving everything else alone.
	///
	/// Idempotent: running it twice leaves one entry per event, so somebody who
	/// re-runs it after an update gets the new path rather than two hooks.
	///
	/// Hooks belonging to cmanager are taken out, because this replaces it —
	/// leaving both would set the same tmux option twice and announce
	/// everything twice, once in tmux's status line and once in the corner.
	public static func adding(
		command: String,
		to settings: [String: Any]
	) -> [String: Any] {
		var settings = settings
		var hooks = settings["hooks"] as? [String: Any] ?? [:]

		for event in events {
			var matchers = (hooks[event] as? [[String: Any]]) ?? []
			matchers = matchers.compactMap { matcher in
				var matcher = matcher
				let commands = (matcher["hooks"] as? [[String: Any]]) ?? []
				let kept = commands.filter { !isOurs($0) && !isCmanager($0) }
				// A matcher we emptied was only ever there for us or cmanager,
				// and an empty one left behind would be noise in their file.
				if kept.isEmpty, !commands.isEmpty { return nil }
				matcher["hooks"] = kept
				return matcher
			}
			matchers.append([
				"matcher": "",
				"hooks": [["type": "command", "command": command]],
			])
			hooks[event] = matchers
		}

		settings["hooks"] = hooks
		return settings
	}

	/// Takes ideai's hooks — and only those — back out.
	public static func removing(from settings: [String: Any]) -> [String: Any] {
		var settings = settings
		guard var hooks = settings["hooks"] as? [String: Any] else { return settings }

		for (event, value) in hooks {
			guard let matchers = value as? [[String: Any]] else { continue }
			let cleaned: [[String: Any]] = matchers.compactMap { matcher in
				var matcher = matcher
				let commands = (matcher["hooks"] as? [[String: Any]]) ?? []
				let kept = commands.filter { !isOurs($0) }
				if kept.isEmpty, !commands.isEmpty { return nil }
				matcher["hooks"] = kept
				return matcher
			}
			// An event nobody is listening to any more goes entirely, rather
			// than staying as an empty array in somebody's settings.
			if cleaned.isEmpty {
				hooks.removeValue(forKey: event)
			} else {
				hooks[event] = cleaned
			}
		}

		if hooks.isEmpty {
			settings.removeValue(forKey: "hooks")
		} else {
			settings["hooks"] = hooks
		}
		return settings
	}

	/// Whether the settings already point at this command for every event.
	public static func isInstalled(command: String, in settings: [String: Any]) -> Bool {
		guard let hooks = settings["hooks"] as? [String: Any] else { return false }
		return events.allSatisfy { event in
			let matchers = (hooks[event] as? [[String: Any]]) ?? []
			return matchers.contains { matcher in
				((matcher["hooks"] as? [[String: Any]]) ?? []).contains {
					($0["command"] as? String) == command
				}
			}
		}
	}

	/// Ours by what it runs, not by where it is: the app can be installed in
	/// /Applications or run out of a build directory, and an upgrade that moves
	/// it must replace the old entry rather than add a second one.
	private static func isOurs(_ hook: [String: Any]) -> Bool {
		guard let command = hook["command"] as? String else { return false }
		return command.contains("ideai") && command.contains("claude-hook")
	}

	private static func isCmanager(_ hook: [String: Any]) -> Bool {
		guard let command = hook["command"] as? String else { return false }
		return command.contains("cmanager")
	}

	// MARK: - The file itself

	public enum Failure: Error, Equatable {
		case unreadable(String)
		case unwritable(String)
	}

	/// Reads the settings, or an empty object when there are none yet.
	public static func read(at url: URL = settingsURL) throws -> [String: Any] {
		guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
		guard let data = try? Data(contentsOf: url) else {
			throw Failure.unreadable(url.path)
		}
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw Failure.unreadable(url.path)
		}
		return object
	}

	/// Writes them back, keeping a copy of what was there.
	///
	/// The backup is the point: this is somebody's own settings file, and the
	/// answer to "what did that do to my file" has to be better than "trust me".
	@discardableResult
	public static func write(
		_ settings: [String: Any],
		to url: URL = settingsURL,
		backup: Bool = true
	) throws -> URL? {
		var backupURL: URL?
		if backup, FileManager.default.fileExists(atPath: url.path) {
			let stamp = ISO8601DateFormatter().string(from: Date())
				.replacingOccurrences(of: ":", with: "-")
			let copy = url.deletingLastPathComponent()
				.appendingPathComponent("settings.json.bak-\(stamp)")
			try? FileManager.default.copyItem(at: url, to: copy)
			backupURL = copy
		}

		guard let data = try? JSONSerialization.data(
			withJSONObject: settings,
			options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		) else {
			throw Failure.unwritable(url.path)
		}

		try? FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		do {
			try (String(decoding: data, as: UTF8.self) + "\n").write(
				to: url, atomically: true, encoding: .utf8
			)
		} catch {
			throw Failure.unwritable(url.path)
		}
		return backupURL
	}
}

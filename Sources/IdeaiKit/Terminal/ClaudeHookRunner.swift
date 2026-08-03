import Foundation

/// The app, run as a Claude Code hook rather than as an app.
///
/// Claude Code announces its own events by running a command and handing it the
/// event as JSON on stdin. This is that command: it marks the tmux window the
/// session lives in, and tells any running ideai what happened so it can say so
/// in the corner. It must be quick and it must never fail loudly — a hook that
/// takes a second, or exits non-zero, is a hook that makes Claude worse to use.
///
/// It runs before `NSApplication` exists and never starts one.
public enum ClaudeHookRunner {
	/// The subcommand, as it appears in `~/.claude/settings.json`.
	public static let command = "claude-hook"

	/// Runs the hook and exits. Never returns.
	public static func run() -> Never {
		// Whatever happens, Claude Code sees success: this is a bystander to
		// somebody's session, and a bystander does not get to interrupt it.
		defer { exit(0) }

		let timing = ProcessInfo.processInfo.environment["IDEAI_HOOK_TIMING"] != nil
		let started = Date()
		func note(_ what: String) {
			guard timing else { return }
			FileHandle.standardError.write(Data(String(
				format: "%-12s %5.0f ms\n", (what as NSString).utf8String!, -started.timeIntervalSinceNow * 1000
			).utf8))
		}

		let input = FileHandle.standardInput.readDataToEndOfFile()
		guard let event = ClaudeHook.parse(input) else { exit(0) }
		note("read")

		let place = tmuxPlace()
		note("tmux place")
		if let place { mark(event: event, at: place) }
		note("tmux mark")
		announce(event: event, at: place)
		note("announce")
		exit(0)
	}

	// MARK: - tmux

	/// Which window the session is in, from the pane Claude Code was started in.
	public struct Place {
		let pane: String
		let session: String
		let windowIndex: Int
		let windowName: String
	}

	private static func tmuxPlace() -> Place? {
		guard let pane = ProcessInfo.processInfo.environment["TMUX_PANE"], !pane.isEmpty,
		      let tmux = Executables.locate("tmux")
		else { return nil }

		// One call for all three, in the format the rest of the app already
		// speaks: semicolons, and the name last because it can hold anything.
		let printed = run(tmux, [
			"display-message", "-p", "-t", pane,
			"#{session_name};#{window_index};#{window_name}",
		])
		let fields = (printed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
		guard fields.count == 3, let index = Int(fields[1]) else { return nil }

		return Place(
			pane: pane,
			session: String(fields[0]),
			windowIndex: index,
			windowName: String(fields[2])
		)
	}

	/// Puts the state on the window, where the tab strip reads it.
	///
	/// The same `@ai_status` option cmanager writes, deliberately: somebody
	/// whose tmux status line already shows it keeps what they had, and the two
	/// can be swapped without touching `~/.tmux.conf`.
	private static func mark(event: ClaudeHook.Event, at place: Place) {
		guard let tmux = Executables.locate("tmux") else { return }
		guard let status = ClaudeHook.status(after: event) else {
			// Ended, or an event with nothing to say: the window goes back to
			// having no badge at all rather than keeping a stale one.
			if event.name == "SessionEnd" {
				_ = run(tmux, ["set-option", "-t", place.pane, "-wu", "@ai_status"])
			}
			return
		}
		_ = run(tmux, ["set-option", "-t", place.pane, "-w", "@ai_status", status.rawValue])
	}

	// MARK: - Telling the app

	private static func announce(event: ClaudeHook.Event, at place: Place?) {
		var payload: [String: String] = [
			"event": event.name,
			"session": event.sessionID,
			"cwd": event.cwd,
			"status": ClaudeHook.status(after: event)?.rawValue ?? "",
		]
		if let place {
			payload["tmuxSession"] = place.session
			payload["window"] = String(place.windowIndex)
			payload["windowName"] = place.windowName
		}
		if let message = ClaudeHook.detail(for: event) { payload["message"] = message }
		if let line = ClaudeHook.announcement(
			for: event,
			window: place?.windowName ?? URL(fileURLWithPath: event.cwd).lastPathComponent
		) {
			payload["announce"] = line
		}

		DistributedNotificationCenter.default().postNotificationName(
			Notification.Name(ClaudeHook.notificationName),
			object: nil,
			userInfo: payload,
			deliverImmediately: true
		)
	}

	// MARK: - Running tmux

	private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments

		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice

		do { try process.run() } catch { return nil }
		// Read to the end of the pipe and stop there, rather than calling
		// `waitUntilExit`: that polls, and the poll costs sixty-odd
		// milliseconds a call — which for a hook Claude runs on every tool use
		// is the difference between unnoticeable and felt. The pipe reaching
		// its end *is* the child having gone, and the exit status is not
		// something any caller here asks about.
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(decoding: data, as: UTF8.self)
	}
}

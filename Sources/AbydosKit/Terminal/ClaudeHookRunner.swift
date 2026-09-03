import Foundation

/// The app, run as a Claude Code hook rather than as an app.
///
/// Claude Code announces its own events by running a command and handing it the
/// event as JSON on stdin. This is that command: it marks the tmux window the
/// session lives in, and tells any running Abydos what happened so it can say so
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

		let timing = ProcessInfo.processInfo.environment["ABYDOS_HOOK_TIMING"] != nil
		let started = Date()
		func note(_ what: String) {
			guard timing else { return }
			FileHandle.standardError.write(Data(String(
				format: "%-12s %5.0f ms\n", (what as NSString).utf8String!, -started.timeIntervalSinceNow * 1000
			).utf8))
		}

		let input = FileHandle.standardInput.readDataToEndOfFile()
		log(input)
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

	/// Keeps what Claude actually sent, when asked to.
	///
	/// A badge that says something surprising is otherwise an argument about
	/// what the payload probably was. `ABYDOS_HOOK_LOG=<path>` makes it a
	/// question anybody can answer by reading a file.
	private static func log(_ input: Data) {
		guard let path = ProcessInfo.processInfo.environment["ABYDOS_HOOK_LOG"], !path.isEmpty
		else { return }
		let line = String(decoding: input, as: UTF8.self)
			.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
		let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
		if let handle = try? FileHandle(forWritingTo: url) {
			defer { try? handle.close() }
			_ = try? handle.seekToEnd()
			try? handle.write(contentsOf: Data(line.utf8))
		} else {
			try? Data(line.utf8).write(to: url)
		}
	}

	// MARK: - tmux

	/// Which window the session is in, from the pane Claude Code was started in.
	public struct Place {
		let pane: String
		let session: String
		let windowIndex: Int
		let windowName: String
		/// What the window's badge says right now, which decides whether an
		/// idle nudge means anything.
		let status: TmuxMirror.AIStatus?
	}

	private static func tmuxPlace() -> Place? {
		guard let pane = ProcessInfo.processInfo.environment["TMUX_PANE"], !pane.isEmpty,
		      let tmux = Executables.locate("tmux")
		else { return nil }

		// One call for all three, in the format the rest of the app already
		// speaks: semicolons, and the name last because it can hold anything.
		// The badge the window already carries comes back with the rest: it is
		// the difference between "Claude is waiting mid-turn" and "the turn
		// ended and nobody has typed since".
		let printed = run(tmux, [
			"display-message", "-p", "-t", pane,
			"#{session_name};#{window_index};#{@ai_status};#{window_name}",
		])
		let fields = (printed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false)
		guard fields.count == 4, let index = Int(fields[1]) else { return nil }

		return Place(
			pane: pane,
			session: String(fields[0]),
			windowIndex: index,
			windowName: String(fields[3]),
			status: TmuxMirror.AIStatus(rawValue: String(fields[2]))
		)
	}

	/// Puts the state on the window, where the tab strip reads it.
	///
	/// The same `@ai_status` option cmanager writes, deliberately: somebody
	/// whose tmux status line already shows it keeps what they had, and the two
	/// can be swapped without touching `~/.tmux.conf`.
	private static func mark(event: ClaudeHook.Event, at place: Place) {
		guard let tmux = Executables.locate("tmux") else { return }
		guard let status = ClaudeHook.status(after: event, whenWindowSays: place.status) else {
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
			"status": ClaudeHook.status(after: event, whenWindowSays: place?.status)?.rawValue ?? "",
		]
		// The type as well as the verdict: outside tmux there is no window to
		// say `done`, so the verdict above takes an idle nudge for a question.
		// The app has the memory this process lacks, and this is the field it
		// needs to apply the same rule.
		if let type = event.notificationType, !type.isEmpty {
			payload["notificationType"] = type
		}
		if let place {
			payload["tmuxSession"] = place.session
			payload["window"] = String(place.windowIndex)
			payload["windowName"] = place.windowName
			// The pane by its own id, `%7`: global to the server and kept when
			// the window is renumbered, which is what a row selects by.
			payload["pane"] = place.pane
		} else if let terminal = ProcessInfo.processInfo.environment["ABYDOS_TERMINAL"],
		          !terminal.isEmpty {
			// Which of the app's tabs this pane is, from the name the tab gave
			// its shell. Outside tmux only: inside, the variable is whatever
			// the tmux server inherited from the tab that started it, and the
			// tmux place above is the truth.
			payload["terminal"] = terminal
		}
		if let message = ClaudeHook.detail(for: event) { payload["message"] = message }
		// Nothing announced for a nudge about a turn that already finished: the
		// tab said ✓ a second ago and nobody needs telling twice.
		if ClaudeHook.isWorthAnnouncing(event, whenWindowSays: place?.status),
		   let line = ClaudeHook.announcement(
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
		// Rather than inheriting it, for the reason in `TmuxSocketPath`. This
		// one runs inside somebody's own tmux, so a short `TMUX_TMPDIR` here is
		// likelier to be deliberate than anywhere else — and it is kept.
		process.environment = TmuxSocketPath.environment

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

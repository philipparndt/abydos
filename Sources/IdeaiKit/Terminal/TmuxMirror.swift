import Foundation

/// The tmux session behind a terminal, as a list of windows.
///
/// For the mode where the panel's tabs *are* tmux's windows rather than
/// terminals of our own: one shell, one pty, and a tab strip that shows what
/// tmux has. Switching tabs switches tmux's window, and switching it inside
/// tmux moves the tab — the same thing seen from either end.
public enum TmuxMirror {
	/// What the Claude session in a window is doing, if one is there.
	///
	/// Not ours to work out: cmanager's hooks put it on the window as the
	/// `@ai_status` user option, and tmux hands user options to a format like
	/// any other field. So a tab can say whether the session in it is working,
	/// waiting for an answer, or finished, for the price of a wider format
	/// string on a query the strip already makes.
	public enum AIStatus: String, Sendable, CaseIterable {
		case working
		case needsInput = "needs"
		case done
	}

	/// One window of a session.
	public struct Window: Equatable, Sendable, Identifiable {
		public let index: Int
		public let name: String
		public let isActive: Bool
		/// What is running in its active pane, for a tab that has no name of
		/// its own worth showing.
		public let command: String
		/// What the Claude session in the window is doing, when a hook has told
		/// us. Not necessarily still true — see `silentFor`.
		public let aiStatus: AIStatus?
		/// How long the window has produced nothing, by tmux's own reckoning.
		///
		/// The badge is a memory of the last event, and events can go missing:
		/// a session that was working when the app was last closed, one that
		/// was already running before the hooks were installed, a Claude that
		/// was killed mid-turn. A window that claims to be working and has
		/// printed nothing for half a minute is not working.
		public let silentFor: TimeInterval

		public var id: Int { index }

		public init(
			index: Int,
			name: String,
			isActive: Bool,
			command: String = "",
			aiStatus: AIStatus? = nil,
			silentFor: TimeInterval = 0
		) {
			self.index = index
			self.name = name
			self.isActive = isActive
			self.command = command
			self.aiStatus = aiStatus
			self.silentFor = silentFor
		}

		/// What the tab should actually show.
		///
		/// A stale "working" is worse than no badge: it says a session is busy
		/// when it has been sitting waiting for somebody. "Needs you" and
		/// "finished" do not go stale in the same way — they are states a
		/// session stays in, quietly, until somebody comes back to it.
		public var shownStatus: AIStatus? {
			guard aiStatus == .working, silentFor > Self.staleAfter else { return aiStatus }
			return nil
		}

		/// How long a working window may say nothing before it is not believed.
		///
		/// Claude prints a spinner and its running total while it works, so a
		/// working pane is never quiet for long; a person reading a permission
		/// prompt is quiet for as long as they like.
		static let staleAfter: TimeInterval = 30
	}

	/// Which session the client on this terminal is looking at.
	///
	/// Not the one it was started with: `C-b w` and `switch-client` move a
	/// client between sessions, and the tabs should follow what is on screen
	/// rather than what was asked for when the window opened.
	public static func session(forClient tty: String) async -> String? {
		guard let tmux = Executables.locate("tmux") else { return nil }
		let result = await run(tmux, [
			"list-clients",
			"-F", "#{client_session}",
			"-f", "#{==:#{client_tty},\(tty)}",
		])
		guard let result, result.exitCode == 0 else { return nil }
		let name = result.output
			.split(separator: "\n")
			.first
			.map { $0.trimmingCharacters(in: .whitespaces) }
		return (name?.isEmpty ?? true) ? nil : name
	}

	/// One session of the server.
	public struct SessionSummary: Equatable, Sendable {
		public let name: String
		public let windowCount: Int
		public let isAttached: Bool
		/// When tmux made it, which is the order it cycles through them in.
		public let created: Int

		public init(name: String, windowCount: Int, isAttached: Bool, created: Int = 0) {
			self.name = name
			self.windowCount = windowCount
			self.isAttached = isAttached
			self.created = created
		}
	}

	/// Every session the server has, for choosing another one.
	public static func sessions() async -> [SessionSummary] {
		guard let tmux = Executables.locate("tmux") else { return [] }
		let format = "#{session_windows};#{?session_attached,1,0};#{session_created};#{session_name}"
		let result = await run(tmux, ["list-sessions", "-F", format])
		guard let result, result.exitCode == 0 else { return [] }
		return parseSessions(result.output)
	}

	/// Reads `list-sessions` output. The name comes last, since a session can
	/// be called anything.
	/// In the order tmux cycles through them — oldest first, which is what
	/// `C-b (` and `C-b )` walk and what the session list in tmux shows.
	static func parseSessions(_ output: String) -> [SessionSummary] {
		var sessions: [SessionSummary] = []
		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			let fields = line.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false)
			// Three fields is the older format, kept so a fixture without a
			// creation time still reads.
			guard fields.count >= 3, let windows = Int(fields[0]) else { continue }
			let hasCreated = fields.count == 4
			sessions.append(SessionSummary(
				name: String(fields[hasCreated ? 3 : 2]),
				windowCount: windows,
				isAttached: fields[1] == "1",
				created: hasCreated ? Int(fields[2]) ?? 0 : 0
			))
		}
		return sessions.sorted { $0.created < $1.created }
	}

	/// Points this terminal's client at another session.
	public static func switchClient(onTTY tty: String, to session: String) async {
		await command(["switch-client", "-c", tty, "-t", session])
	}

	/// Makes a session and leaves it running, for switching to afterwards.
	public static func createSession(named name: String, in directory: URL?) async {
		var arguments = ["new-session", "-d", "-s", name]
		if let directory { arguments += ["-c", directory.path] }
		await command(arguments)
	}

	/// Reads the windows of a session, in the order tmux lists them.
	///
	/// Nothing at all when there is no such session, which is also the answer
	/// while tmux is still starting: the caller keeps what it had rather than
	/// blanking the strip.
	public static func windows(inSession session: String) async -> [Window] {
		guard let tmux = Executables.locate("tmux") else { return [] }

		// Semicolons, not tabs: tmux replaces a tab in a format with an
		// underscore, and a name with a semicolon in it is rarer than one with
		// a space. The name comes last so what is left of the line is all of it.
		let format = "#{window_index};#{?window_active,1,0};#{pane_current_command}"
			+ ";#{@ai_status};#{window_activity};#{window_name}"
		let result = await run(tmux, ["list-windows", "-t", session, "-F", format])
		guard let result, result.exitCode == 0 else { return [] }
		return parse(result.output)
	}

	/// Reads `list-windows` output.
	///
	/// Internal so the shapes can be tested: a window whose name holds a
	/// semicolon, one running nothing, and the line tmux prints for a session
	/// that has just been created.
	static func parse(_ output: String, now: Date = Date()) -> [Window] {
		var windows: [Window] = []
		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			// Exactly the six the format asks for, and no shorter form
			// accepted: a window called "one; two" would otherwise be
			// indistinguishable from a line carrying fewer fields, and the
			// name — which can hold anything — has to stay whole. tmux prints
			// an empty field for an option that is not set, so a window with
			// no Claude session in it still arrives as six.
			let fields = line.split(separator: ";", maxSplits: 5, omittingEmptySubsequences: false)
			guard fields.count == 6, let index = Int(fields[0]) else { continue }
			let activity = Double(fields[4]) ?? 0
			windows.append(Window(
				index: index,
				name: String(fields[5]),
				isActive: fields[1] == "1",
				command: String(fields[2]),
				aiStatus: AIStatus(rawValue: String(fields[3])),
				silentFor: activity > 0 ? max(0, now.timeIntervalSince1970 - activity) : 0
			))
		}
		return windows
	}

	// MARK: - Telling tmux what to do

	public static func select(window index: Int, inSession session: String) async {
		await command(["select-window", "-t", "\(session):\(index)"])
	}

	/// Makes a window in a session, saying whether it could.
	///
	/// It cannot when the session is gone — which is what closing its last
	/// window does — and the caller's answer to that is to start the session
	/// again rather than to do nothing.
	@discardableResult
	public static func newWindow(inSession session: String) async -> Bool {
		guard let tmux = Executables.locate("tmux") else { return false }
		let result = await run(tmux, ["new-window", "-t", session])
		return result?.exitCode == 0
	}

	/// How many rows this session's status bar takes.
	///
	/// `off` is none, `on` is one, and tmux also takes a number — somebody can
	/// have two or five. Asked rather than assumed, because the whole point of
	/// reporting a taller pane is to hide exactly what tmux will draw: one row
	/// too few leaves a bar on screen, one too many leaves a gap, and somebody
	/// who has already turned their bar off must get neither.
	public static func statusLines(inSession session: String) async -> Int {
		guard let tmux = Executables.locate("tmux") else { return 0 }
		let result = await run(tmux, ["display-message", "-p", "-t", session, "#{status}"])
		guard let text = result?.output.trimmingCharacters(in: .whitespacesAndNewlines),
		      result?.exitCode == 0
		else { return 0 }
		if text == "off" { return 0 }
		if text == "on" { return 1 }
		return Int(text) ?? 1
	}

	/// Hides — or gives back — tmux's own status bar, for one session only.
	///
	/// A session option, set at runtime: nothing is written to anybody's
	/// `.tmux.conf`, every other session on the server keeps its bar, and so
	/// does every other terminal attached to those. Worth having because in the
	/// mirrored mode this app draws the same window list as tabs, and two rows
	/// of the same thing is one row too many.
	public static func setStatusBar(_ shown: Bool, inSession session: String) async {
		await command(shown
			? ["set-option", "-t", session, "-u", "status"]
			: ["set-option", "-t", session, "status", "off"])
	}

	/// Whether the server has a session by this name.
	public static func sessionExists(_ name: String) async -> Bool {
		guard let tmux = Executables.locate("tmux") else { return false }
		return await run(tmux, ["has-session", "-t", "=\(name)"])?.exitCode == 0
	}

	/// Moves a window to where another one is, shifting the rest along.
	///
	/// tmux does this properly — `move-window -b/-a` inserts before or after a
	/// target and pushes the others up — so a dragged tab is a real reorder
	/// rather than a swap of two. Renumbered afterwards so the indices stay the
	/// positions they look like.
	public static func move(
		window index: Int,
		before target: Int,
		after isAfter: Bool,
		inSession session: String
	) async {
		await command([
			"move-window", isAfter ? "-a" : "-b",
			"-s", "\(session):\(index)",
			"-t", "\(session):\(target)",
		])
		await command(["move-window", "-r", "-t", session])
	}

	public static func killWindow(_ index: Int, inSession session: String) async {
		await command(["kill-window", "-t", "\(session):\(index)"])
	}

	public static func rename(window index: Int, to name: String, inSession session: String) async {
		await command(["rename-window", "-t", "\(session):\(index)", name])
	}

	private static func command(_ arguments: [String]) async {
		guard let tmux = Executables.locate("tmux") else { return }
		_ = await run(tmux, arguments)
	}

	private static func run(
		_ launchPath: String,
		_ arguments: [String]
	) async -> (output: String, exitCode: Int32)? {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: launchPath)
				process.arguments = arguments

				let pipe = Pipe()
				process.standardOutput = pipe
				process.standardError = FileHandle.nullDevice

				do { try process.run() } catch {
					continuation.resume(returning: nil)
					return
				}
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()
				continuation.resume(returning: (
					String(decoding: data, as: UTF8.self), process.terminationStatus
				))
			}
		}
	}
}

import Foundation

/// The tmux session behind a terminal, as a list of windows.
///
/// For the mode where the panel's tabs *are* tmux's windows rather than
/// terminals of our own: one shell, one pty, and a tab strip that shows what
/// tmux has. Switching tabs switches tmux's window, and switching it inside
/// tmux moves the tab — the same thing seen from either end.
public enum TmuxMirror {
	/// One window of a session.
	public struct Window: Equatable, Sendable, Identifiable {
		public let index: Int
		public let name: String
		public let isActive: Bool
		/// What is running in its active pane, for a tab that has no name of
		/// its own worth showing.
		public let command: String

		public var id: Int { index }

		public init(index: Int, name: String, isActive: Bool, command: String = "") {
			self.index = index
			self.name = name
			self.isActive = isActive
			self.command = command
		}
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
		let format = "#{window_index};#{?window_active,1,0};#{pane_current_command};#{window_name}"
		let result = await run(tmux, ["list-windows", "-t", session, "-F", format])
		guard let result, result.exitCode == 0 else { return [] }
		return parse(result.output)
	}

	/// Reads `list-windows` output.
	///
	/// Internal so the shapes can be tested: a window whose name holds a
	/// semicolon, one running nothing, and the line tmux prints for a session
	/// that has just been created.
	static func parse(_ output: String) -> [Window] {
		var windows: [Window] = []
		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			let fields = line.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false)
			guard fields.count == 4, let index = Int(fields[0]) else { continue }
			windows.append(Window(
				index: index,
				name: String(fields[3]),
				isActive: fields[1] == "1",
				command: String(fields[2])
			))
		}
		return windows
	}

	// MARK: - Telling tmux what to do

	public static func select(window index: Int, inSession session: String) async {
		await command(["select-window", "-t", "\(session):\(index)"])
	}

	public static func newWindow(inSession session: String) async {
		await command(["new-window", "-t", session])
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

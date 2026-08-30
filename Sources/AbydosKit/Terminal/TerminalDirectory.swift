import Darwin
import Foundation

/// Where the shell in a terminal currently is.
///
/// Asked of the system rather than of the shell. The usual way for a terminal
/// to learn this is OSC 7, which the shell has to be configured to send and
/// which tmux keeps for itself rather than passing on. Reading it from the
/// process costs nothing to set up and works in a shell nobody has configured.
public enum TerminalDirectory {
	/// The directory of whatever is in the foreground of this terminal.
	///
	/// `slaveName` is the terminal's own device, which is how tmux is asked
	/// about the pane on screen — see below.
	public static func current(masterDescriptor: Int32, slaveName: String?) -> URL? {
		guard masterDescriptor >= 0 else { return nil }

		// The foreground process group is what the user is looking at: the
		// shell when it is waiting, or whatever it is running.
		let foreground = tcgetpgrp(masterDescriptor)
		guard foreground > 0 else { return nil }

		// tmux runs the shell under its own server, in another process tree
		// entirely, so the client in front of us is sitting wherever tmux was
		// started and knows nothing about where the pane has been. The server
		// does, and will say if asked about this particular client.
		let name = processName(of: foreground)

		if let slaveName, name?.hasPrefix("tmux") == true {
			return tmuxPaneDirectory(client: slaveName)
		}

		return directory(of: foreground)
	}

	/// The working directory of a process.
	public static func directory(of pid: pid_t) -> URL? {
		var info = proc_vnodepathinfo()
		let size = MemoryLayout<proc_vnodepathinfo>.size
		let read = withUnsafeMutablePointer(to: &info) {
			proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, Int32(size))
		}
		guard read == Int32(size) else { return nil }

		let path = withUnsafePointer(to: info.pvi_cdir.vip_path) {
			$0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
		}
		guard !path.isEmpty else { return nil }
		return URL(fileURLWithPath: path, isDirectory: true)
	}

	/// The executable name of a process, for recognising tmux.
	public static func processName(of pid: pid_t) -> String? {
		var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
		let read = proc_name(pid, &buffer, UInt32(buffer.count))
		guard read > 0 else { return nil }
		return String(cString: buffer)
	}

	/// The directory to follow a terminal to, or nil while it is busy.
	///
	/// **A window follows where somebody walked, not where a script went.**
	/// `current` answers with the working directory of whatever is in the
	/// foreground, which during a command is the command — so `brew`, which
	/// changes directory several times while it works, dragged the window
	/// through every one of them and left it wherever the last one happened to
	/// be. A build script does the same. Reported as the folder changing
	/// several times during one run, from somebody who wanted it to change when
	/// *they* changed directory and at no other time.
	///
	/// So: only while the shell itself is what the terminal is showing. A `cd`
	/// is a builtin — the shell forks nothing and stays in the foreground — so
	/// every directory change somebody types is still followed, at the moment
	/// they type it. A directory a command wandered into is not: the shell's
	/// own is unchanged, which is the truth about where the terminal *is*.
	///
	/// - Parameter shell: the process the pty was opened around. It is a
	///   session leader, so its process group is its own pid, which is what
	///   `tcgetpgrp` answers with while nothing else is running.
	public static func settled(
		masterDescriptor: Int32, slaveName: String?, shell: pid_t
	) -> URL? {
		guard masterDescriptor >= 0 else { return nil }
		let foreground = tcgetpgrp(masterDescriptor)
		guard foreground > 0 else { return nil }

		let name = processName(of: foreground)
		if let slaveName, name?.hasPrefix("tmux") == true {
			return tmuxPaneDirectory(client: slaveName, onlyWhenIdle: true)
		}

		guard shell > 0, foreground == shell else { return nil }
		return directory(of: foreground)
	}

	/// The shells a pane is *waiting* in rather than running something in.
	///
	/// tmux is asked what its pane is running, and the answer is a command
	/// name; there is no process group to compare against, the shell being in
	/// another process tree entirely. A name it does not know counts as busy —
	/// the wrong way for an unusual shell, which then simply is not followed,
	/// rather than the wrong way for every script, which is the fault being
	/// fixed.
	static let shellNames: Set<String> = [
		"bash", "csh", "dash", "elvish", "fish", "ksh", "nu", "sh", "tcsh", "xonsh", "zsh",
	]

	/// Asks the tmux server where the pane in front of this client is.
	///
	/// Targeted at the client rather than the session, so switching windows or
	/// panes gives a different answer straight away — which is the whole point
	/// of following a terminal that has tmux in it.
	static func tmuxPaneDirectory(client: String, onlyWhenIdle: Bool = false) -> URL? {
		// Found rather than run through `env`: an app started from the Finder
		// has almost no PATH, and tmux is in Homebrew's — so this worked when
		// the app was launched from a terminal and did nothing at all when it
		// was launched the way anybody actually launches it.
		guard let tmux = Executables.locate("tmux") else { return nil }

		// Filtered to this client rather than asked about it. The obvious
		// spelling — display-message -c <client> — chooses who the message
		// would be shown to, not whose pane the format is about: asked about
		// one client while another is current, tmux answers about the current
		// one, and following that would put the window in somebody else's pane.
		//
		// The filter leaves one line, so the format needs no separator — which
		// is just as well, since tmux replaces a tab in a format with an
		// underscore and the field never came apart again.
		//
		// The command comes back beside the path when the answer has to be
		// gated on it. A space between them, not a tab: tmux replaces a tab in
		// a format with an underscore, which is the note above, and a command
		// name has no spaces in it — so the *first* field is the command and
		// everything after it is the path, which a path with spaces in it
		// survives and a split on space would not.
		let format = onlyWhenIdle
			? "#{pane_current_command} #{pane_current_path}"
			: "#{pane_current_path}"
		let output = run(tmux, [
			"list-clients",
			"-F", format,
			"-f", "#{==:#{client_tty},\(client)}",
		])
		guard let output else { return nil }

		for line in output.split(separator: "\n") {
			var said = line.trimmingCharacters(in: .whitespaces)
			if onlyWhenIdle {
				guard let space = said.firstIndex(of: " ") else { continue }
				let command = String(said[said.startIndex..<space])
				// A login shell arrives as `-zsh`.
				guard shellNames.contains(command.hasPrefix("-")
					? String(command.dropFirst()) : command) else { return nil }
				said = String(said[said.index(after: space)...])
					.trimmingCharacters(in: .whitespaces)
			}
			guard said.hasPrefix("/") else { continue }
			return URL(fileURLWithPath: said, isDirectory: true)
		}
		return nil
	}

	private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments
		// Rather than inheriting it: an inherited `TMUX_TMPDIR` too long to
		// make a socket would leave this answering nothing, and a window that
		// follows its terminal would simply stop following.
		process.environment = TmuxSocketPath.environment

		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice

		do { try process.run() } catch { return nil }
		let data = ProcessPipes.drain(process, out: pipe)
		guard process.terminationStatus == 0 else { return nil }
		return String(decoding: data, as: UTF8.self)
	}
}

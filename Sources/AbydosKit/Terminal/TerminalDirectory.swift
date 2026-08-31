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

	/// The directory to follow a terminal to: the *shell's* own, whatever is
	/// running in front of it.
	///
	/// **A window follows where somebody walked, not where a script went.**
	/// `current` answers with the working directory of whatever is in the
	/// foreground, which during a command is the command — so `brew`, which
	/// changes directory several times while it works, dragged the window
	/// through every one of them and left it wherever the last one happened to
	/// be. The first fix answered nothing while anything ran, which traded that
	/// fault for two more: a script's own project was deselected the moment it
	/// started, and a pane holding something long-lived — a Claude session —
	/// never answered at all, so switching to its tab followed nowhere.
	///
	/// The shell's own directory is the answer to all three at once. A script
	/// never moves it, so nothing is dragged and the project stays the one the
	/// script was started from; a `cd` is a builtin, so every move somebody
	/// types shows up in it the moment it is made; and it is always there to
	/// read, however long whatever is in front of it runs.
	///
	/// - Parameter shell: the process the pty was opened around.
	public static func settled(
		masterDescriptor: Int32, slaveName: String?, shell: pid_t
	) -> URL? {
		guard masterDescriptor >= 0 else { return nil }

		// tmux runs its shells under its own server, in another process tree:
		// the pane's first process is the one to ask, and the server knows it.
		let foreground = tcgetpgrp(masterDescriptor)
		if foreground > 0, let slaveName,
		   processName(of: foreground)?.hasPrefix("tmux") == true {
			return tmuxPaneShellDirectory(client: slaveName)
		}

		guard shell > 0 else { return nil }
		return directory(of: shell)
	}

	/// The directory of the pane's own shell — `#{pane_pid}` is the process
	/// tmux spawned the pane around, and its working directory is readable
	/// like any other process's. Not `#{pane_current_path}`, which on this
	/// platform follows the *foreground* process and is the dragging fault
	/// all over again.
	static func tmuxPaneShellDirectory(client: String) -> URL? {
		guard let tmux = Executables.locate("tmux") else { return nil }
		let output = run(tmux, [
			"list-clients",
			"-F", "#{pane_pid}",
			"-f", "#{==:#{client_tty},\(client)}",
		])
		guard let output,
		      let pid = pid_t(output.trimmingCharacters(in: .whitespacesAndNewlines)),
		      pid > 0 else { return nil }
		return directory(of: pid)
	}

	/// Asks the tmux server where the pane in front of this client is.
	///
	/// Targeted at the client rather than the session, so switching windows or
	/// panes gives a different answer straight away — which is the whole point
	/// of following a terminal that has tmux in it.
	static func tmuxPaneDirectory(client: String) -> URL? {
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
		let output = run(tmux, [
			"list-clients",
			"-F", "#{pane_current_path}",
			"-f", "#{==:#{client_tty},\(client)}",
		])
		guard let output else { return nil }

		for line in output.split(separator: "\n") {
			let said = line.trimmingCharacters(in: .whitespaces)
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

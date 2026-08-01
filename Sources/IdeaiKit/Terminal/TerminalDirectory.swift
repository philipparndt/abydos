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

	/// Asks the tmux server where the pane in front of this client is.
	///
	/// Targeted at the client rather than the session, so switching windows or
	/// panes gives a different answer straight away — which is the whole point
	/// of following a terminal that has tmux in it.
	static func tmuxPaneDirectory(client: String) -> URL? {
		// Listed and filtered rather than asked about directly. The obvious
		// spelling — display-message -c <client> — chooses who the message would
		// be shown to, not whose pane the format is about: asked about one
		// client while another is current, tmux answers about the current one.
		// Following that would put the window in somebody else's pane.
		//
		// list-clients evaluates its format once per client, so filtering it to
		// this one gives this one's answer, and nothing at all when the client
		// is not there.
		let output = run("/usr/bin/env", [
			"tmux", "list-clients",
			"-F", "#{client_tty}\t#{pane_current_path}",
			"-f", "#{==:#{client_tty},\(client)}",
		])
		guard let output else { return nil }

		for line in output.split(separator: "\n") {
			let parts = line.split(separator: "\t")
			guard parts.count == 2, String(parts[0]) == client else { continue }
			let path = String(parts[1])
			guard !path.isEmpty else { continue }
			return URL(fileURLWithPath: path, isDirectory: true)
		}
		return nil
	}

	private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = arguments

		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice

		do { try process.run() } catch { return nil }
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { return nil }
		return String(decoding: data, as: UTF8.self)
	}
}

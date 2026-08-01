import Foundation
import Darwin

/// A child process attached to a real pseudo-terminal.
///
/// A real PTY rather than pipes, for three reasons that matter here:
/// interactive tools only enable colour and full-screen UI when `isatty` is
/// true; a PTY carries a window size, so programs reflow when the pane resizes;
/// and job control works, so ⌃C reaches the process.
///
/// It also underpins the agent-session model: because the PTY belongs to ideai
/// and not to any particular view, a session can be shown, hidden, and shown
/// again — or handed to a terminal view for the user to take over — while the
/// process keeps running throughout.
public final class PseudoTerminal {
	public enum State: Equatable, Sendable {
		case notStarted
		case running(pid: pid_t)
		case exited(code: Int32)
	}

	public private(set) var state: State = .notStarted

	/// Queue the callbacks below are delivered on. Defaults to main because the
	/// app drives views from them; tests point it elsewhere so they do not depend
	/// on a running main run loop.
	public var callbackQueue: DispatchQueue = .main

	/// Bytes read from the process.
	public var onOutput: ((Data) -> Void)?
	/// Called when the process exits, with its status.
	public var onExit: ((Int32) -> Void)?

	private var masterDescriptor: Int32 = -1
	/// The terminal's own device, as the child sees it.
	///
	/// Kept because it is how the tmux server is asked about the client running
	/// here, rather than about whichever client it last spoke to.
	public private(set) var slaveName: String?
	private var childPID: pid_t = -1
	private var readSource: DispatchSourceRead?
	private let readQueue = DispatchQueue(label: "ideai.pty.read", qos: .userInitiated)
	/// Whether reading is paused because the reader has a backlog.
	///
	/// Suspending the source leaves the bytes in the pty's own buffer, and once
	/// that fills the process writing to it blocks. That back-pressure is the
	/// whole mechanism by which a terminal stays responsive under a program that
	/// can produce output faster than anyone can read it: without it, a fast
	/// enough writer takes the reader's every cycle and nothing is ever drawn.
	private var isReadingSuspended = false

	public init() {}

	deinit {
		terminate()
	}

	public var isRunning: Bool {
		if case .running = state { return true }
		return false
	}

	// MARK: - Launch

	@discardableResult
	public func start(
		executable: String,
		arguments: [String] = [],
		workingDirectory: URL? = nil,
		environment: [String: String]? = nil,
		rows: Int = 24,
		columns: Int = 80
	) -> Bool {
		guard case .notStarted = state else { return false }

		var size = winsize(
			ws_row: UInt16(max(1, rows)),
			ws_col: UInt16(max(1, columns)),
			ws_xpixel: 0,
			ws_ypixel: 0
		)

		var master: Int32 = -1
		// forkpty does the fork, opens the pty pair, makes the slave the child's
		// controlling terminal and wires it to stdin/stdout/stderr. Doing that by
		// hand needs setsid plus TIOCSCTTY in the child, which posix_spawn cannot
		// express.
		let pid = forkpty(&master, nil, nil, &size)

		if pid < 0 {
			return false
		}

		if pid == 0 {
			// Child. Only async-signal-safe work is legal here before exec.
			if let workingDirectory {
				_ = workingDirectory.withUnsafeFileSystemRepresentation { path in
					path.map { chdir($0) }
				}
			}

			var merged = environment ?? ProcessInfo.processInfo.environment
			// Claim a capable terminal so tools enable colour and full-screen UI.
			merged["TERM"] = merged["TERM"] ?? "xterm-256color"
			merged["COLORTERM"] = merged["COLORTERM"] ?? "truecolor"
			merged["LANG"] = merged["LANG"] ?? "en_US.UTF-8"
			// Stop pagers from hanging a pane waiting for a keypress.
			merged["PAGER"] = merged["PAGER"] ?? "cat"

			let environmentStrings = merged.map { "\($0.key)=\($0.value)" }
			var environmentPointers: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { strdup($0) }
			environmentPointers.append(nil)

			var argumentPointers: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
			argumentPointers.append(nil)

			execve(executable, &argumentPointers, &environmentPointers)
			// Only reached if exec failed; _exit avoids running atexit handlers
			// inherited from the parent.
			_exit(127)
		}

		masterDescriptor = master
		slaveName = String(validatingCString: ptsname(master)) ?? nil
		childPID = pid
		state = .running(pid: pid)

		configureNonBlocking(master)
		startReading()
		watchForExit(pid: pid)
		return true
	}

	/// Launches the user's login shell, which is what a terminal pane wants.
	@discardableResult
	public func startLoginShell(workingDirectory: URL?, rows: Int, columns: Int) -> Bool {
		let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
		// `-l` so the usual profile is sourced and PATH matches a normal terminal;
		// without it, tools installed via Homebrew are frequently missing.
		return start(
			executable: shell,
			arguments: ["-l"],
			workingDirectory: workingDirectory,
			rows: rows,
			columns: columns
		)
	}

	private func configureNonBlocking(_ descriptor: Int32) {
		let flags = fcntl(descriptor, F_GETFL, 0)
		_ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
	}

	// MARK: - IO

	private func startReading() {
		let source = DispatchSource.makeReadSource(fileDescriptor: masterDescriptor, queue: readQueue)
		source.setEventHandler { [weak self] in
			guard let self else { return }

			// Gathered into one delivery rather than one per read. A program
			// painting a whole screen produces its frame in many small writes,
			// and handing each of them over separately was costing far more in
			// hops between queues than the bytes themselves cost to parse.
			var gathered = Data()
			var buffer = [UInt8](repeating: 0, count: 64 * 1024)
			while gathered.count < 512 * 1024 {
				let count = read(self.masterDescriptor, &buffer, buffer.count)
				guard count > 0 else { break }
				gathered.append(contentsOf: buffer[0..<count])
				if count < buffer.count { break }
			}
			guard !gathered.isEmpty else { return }

			self.callbackQueue.async {
				self.onOutput?(gathered)
			}
		}
		source.resume()
		readSource = source
	}

	/// Stops or resumes taking bytes out of the pty.
	///
	/// While stopped the bytes stay in the pty's buffer and, once it is full,
	/// the process writing to it blocks — which is how a terminal tells a
	/// program that it is going faster than anyone can look at.
	/// Where the process in the foreground of this terminal currently is.
	public func currentDirectory() -> URL? {
		TerminalDirectory.current(masterDescriptor: masterDescriptor, slaveName: slaveName)
	}

	public func setReadingSuspended(_ suspended: Bool) {
		readQueue.async { [weak self] in
			guard let self, let source = self.readSource else { return }
			guard suspended != self.isReadingSuspended else { return }
			self.isReadingSuspended = suspended
			// Balanced by construction: the flag changes only here, on one queue.
			if suspended { source.suspend() } else { source.resume() }
		}
	}

	public func write(_ data: Data) {
		guard masterDescriptor >= 0, isRunning else { return }
		data.withUnsafeBytes { raw in
			guard let base = raw.baseAddress else { return }
			var written = 0
			// A short write is normal on a pty when the buffer fills.
			while written < raw.count {
				let result = Darwin.write(masterDescriptor, base.advanced(by: written), raw.count - written)
				if result <= 0 { break }
				written += result
			}
		}
	}

	public func write(_ string: String) {
		write(Data(string.utf8))
	}

	/// Tells the process the pane changed size, so it can reflow.
	public func resize(rows: Int, columns: Int) {
		guard masterDescriptor >= 0 else { return }
		var size = winsize(
			ws_row: UInt16(max(1, rows)),
			ws_col: UInt16(max(1, columns)),
			ws_xpixel: 0,
			ws_ypixel: 0
		)
		_ = ioctl(masterDescriptor, TIOCSWINSZ, &size)
		// SIGWINCH is what full-screen applications actually listen for.
		if case let .running(pid) = state {
			kill(pid, SIGWINCH)
		}
	}

	// MARK: - Lifecycle

	private func watchForExit(pid: pid_t) {
		// A dedicated thread blocking in waitpid is simpler and more reliable than
		// a DispatchSource process source, which does not report the exit status.
		Thread.detachNewThread { [weak self] in
			var status: Int32 = 0
			let result = waitpid(pid, &status, 0)
			guard result == pid else { return }

			let code: Int32
			if status & 0x7F == 0 {
				code = (status >> 8) & 0xFF
			} else {
				// Killed by a signal; report it the way a shell does.
				code = 128 + (status & 0x7F)
			}

			(self?.callbackQueue ?? .main).async {
				guard let self else { return }
				self.state = .exited(code: code)
				self.readSource?.cancel()
				self.readSource = nil
				if self.masterDescriptor >= 0 {
					close(self.masterDescriptor)
					self.masterDescriptor = -1
				}
				self.onExit?(code)
			}
		}
	}

	/// Sends SIGHUP and closes the master, ending the session.
	public func terminate() {
		if case let .running(pid) = state {
			// The whole foreground process group, so children go too.
			kill(-pid, SIGHUP)
			kill(pid, SIGHUP)
		}
		readSource?.cancel()
		readSource = nil
		if masterDescriptor >= 0 {
			close(masterDescriptor)
			masterDescriptor = -1
		}
	}

	/// Sends an interrupt, as ⌃C would.
	public func interrupt() {
		guard case let .running(pid) = state else { return }
		kill(-pid, SIGINT)
	}
}

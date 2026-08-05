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
	/// Whether a drain is already running, so writing again only adds to what
	/// it is working through.
	private var isDraining = false
	/// Bytes the pty could not take yet.
	private var pendingOutput = Data()
	private let writeLock = NSRecursiveLock()
	private let writeQueue = DispatchQueue(label: "ideai.pty.write")
	private let readQueue = DispatchQueue(label: "ideai.pty.read", qos: .userInitiated)
	/// Whether reading is paused because the reader has a backlog.
	///
	/// Suspending the source leaves the bytes in the pty's own buffer, and once
	/// that fills the process writing to it blocks. That back-pressure is the
	/// whole mechanism by which a terminal stays responsive under a program that
	/// can produce output faster than anyone can read it: without it, a fast
	/// enough writer takes the reader's every cycle and nothing is ever drawn.
	private var isReadingSuspended = false

	/// How large one character cell is, in pixels.
	///
	/// A window size carries the pane in pixels as well as in cells, and that is
	/// the only way a program can work out how big a cell is. Anything drawing
	/// pictures needs it: `icat`, `timg` and `chafa` all read it from
	/// `TIOCGWINSZ` and refuse to size an image without it. Zero — which is
	/// what this was before — reads to them as "this terminal cannot show
	/// pictures at all".
	///
	/// Set by whoever owns the view, since the cell size is a fact about the
	/// font and nothing here knows it.
	public var cellPixelSize: (width: Int, height: Int) = (0, 0)

	public init() {}

	/// The size to hand the kernel: cells, and the pixels they come to.
	private func windowSize(rows: Int, columns: Int) -> winsize {
		let rows = max(1, rows)
		let columns = max(1, columns)
		return winsize(
			ws_row: UInt16(rows),
			ws_col: UInt16(columns),
			ws_xpixel: UInt16(clamping: columns * max(0, cellPixelSize.width)),
			ws_ypixel: UInt16(clamping: rows * max(0, cellPixelSize.height))
		)
	}

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

		var size = windowSize(rows: rows, columns: columns)

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
	/// The terminal device the child sees, which is how tmux is asked about
	/// the client sitting on it.
	public var ttyName: String? { slaveName }

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

	/// Sends bytes to the program, however many there are.
	///
	/// The master is non-blocking, so a write that fills the pty's buffer —
	/// which a pasted crash report does several times over — comes back saying
	/// "not now". What is left is kept and written when the program has read
	/// enough to make room, rather than dropped: the old loop broke out on that
	/// and the rest of a paste simply never arrived.
	public func write(_ data: Data) {
		guard masterDescriptor >= 0, isRunning, !data.isEmpty else { return }
		writeLock.lock()
		pendingOutput.append(data)
		writeLock.unlock()
		flushPendingOutput()
	}

	/// How much is waiting to go to the program.
	///
	/// Anything advisory — a mouse moving over the pane — is worth dropping
	/// while there is a backlog: those reports are about where the pointer was
	/// a moment ago, and delivering them late is how they end up in the middle
	/// of somebody's paste.
	public var pendingInputCount: Int {
		writeLock.lock()
		defer { writeLock.unlock() }
		return pendingOutput.count
	}

	/// Writes what is queued, waiting for room when there is none.
	///
	/// On a queue of its own, and never on the one that reads: waiting for room
	/// to write while holding up the reading of what the program is sending
	/// back is how both ends come to wait for each other for ever.
	private func flushPendingOutput() {
		writeLock.lock()
		let alreadyDraining = isDraining
		isDraining = true
		writeLock.unlock()
		guard !alreadyDraining else { return }

		writeQueue.async { [weak self] in
			while let self, self.drainOnce() {
				// `poll` rather than a timer: the pty says when it has room,
				// and a canonical-mode line discipline takes about a line at a
				// time, so this happens often and should cost nothing while it
				// waits.
				var descriptor = pollfd(fd: self.masterDescriptor, events: Int16(POLLOUT), revents: 0)
				_ = poll(&descriptor, 1, 200)
			}
			self?.writeLock.lock()
			self?.isDraining = false
			self?.writeLock.unlock()
		}
	}

	/// One pass: writes what it can, and says whether anything is still queued.
	private func drainOnce() -> Bool {
		writeLock.lock()
		defer { writeLock.unlock() }

		while !pendingOutput.isEmpty {
			guard masterDescriptor >= 0 else {
				pendingOutput.removeAll()
				return false
			}
			let written = pendingOutput.withUnsafeBytes { raw -> Int in
				guard let base = raw.baseAddress else { return 0 }
				return Darwin.write(masterDescriptor, base, raw.count)
			}
			if written > 0 {
				pendingOutput.removeFirst(written)
				continue
			}
			let failure = errno
			// Full, or interrupted: come back when there is room. Anything else
			// means the program has gone, and what is queued has nowhere to go.
			if failure == EAGAIN || failure == EWOULDBLOCK || failure == EINTR { return true }
			pendingOutput.removeAll()
			return false
		}
		return false
	}

	public func write(_ string: String) {
		write(Data(string.utf8))
	}

	/// Tells the process the pane changed size, so it can reflow.
	public func resize(rows: Int, columns: Int) {
		guard masterDescriptor >= 0 else { return }
		var size = windowSize(rows: rows, columns: columns)
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

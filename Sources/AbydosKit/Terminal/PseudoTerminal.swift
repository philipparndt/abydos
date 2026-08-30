import Foundation
import Darwin

/// The descriptors of one pseudo-terminal, and the only thing that may close
/// them.
///
/// Both of them, because they belong together. The master is the end this
/// process reads and writes. The slave is the child's end, and this process
/// keeps a descriptor on it for as long as the child runs — which is the whole
/// of 0476. **A macOS pty gives output the child has written 600 ms to be read,
/// and then discards it**: the child's exit waits that long for the terminal's
/// queue to be drained, and when the wait runs out the kernel revokes the
/// terminal, the last slave descriptor closes, and closing it flushes the queue.
/// A `/bin/echo` whose output nobody read within 600 ms had not printed late, it
/// had printed nothing. Holding a slave descriptor here removes the deadline —
/// measured out to 15 s with the bytes still there — because the queue is only
/// flushed when the *last* slave descriptor goes, and this one has not.
///
/// It costs one thing, and it is the reason this class exists rather than a
/// second `Int32` beside the first: with the deadline gone, **the child cannot
/// finish exiting until this pty is read or closed**. Read it and the child is
/// reaped in under a millisecond; close either descriptor and the same; do
/// neither and it waits for ever. So there must be no path that stops reading
/// without also closing, and there is exactly one close, here.
///
/// A lock and not a flag, because closing a descriptor number is not a local
/// act: the kernel may hand the same number straight back out, so a `read`, an
/// `ioctl` or a second `close` already on its way lands on a file belonging to
/// something else. The many users take it shared — several threads use these
/// numbers at once and none of them conflicts — and the close takes it
/// exclusively, so it runs after every call already in flight, and once.
private final class TerminalDescriptors: @unchecked Sendable {
	private let lock = UnsafeMutablePointer<pthread_rwlock_t>.allocate(capacity: 1)
	private var master: Int32 = -1
	private var slave: Int32 = -1

	init() { pthread_rwlock_init(lock, nil) }

	deinit {
		close()
		pthread_rwlock_destroy(lock)
		lock.deallocate()
	}

	/// Takes ownership of a freshly opened pair.
	func adopt(master: Int32, slave: Int32) {
		pthread_rwlock_wrlock(lock)
		self.master = master
		self.slave = slave
		pthread_rwlock_unlock(lock)
	}

	/// Runs `body` with the master, or answers nil if it has been closed.
	///
	/// The answer being optional is the point: every caller has to say what it
	/// does when the terminal has gone, rather than making a syscall on -1 and
	/// reading the result as a failure of the terminal.
	func withMaster<T>(_ body: (Int32) -> T) -> T? {
		pthread_rwlock_rdlock(lock)
		defer { pthread_rwlock_unlock(lock) }
		guard master >= 0 else { return nil }
		return body(master)
	}

	var isOpen: Bool { withMaster { _ in true } ?? false }

	/// Closes both, once, whoever asks and however often they ask.
	func close() {
		pthread_rwlock_wrlock(lock)
		if master >= 0 { Darwin.close(master); master = -1 }
		if slave >= 0 { Darwin.close(slave); slave = -1 }
		pthread_rwlock_unlock(lock)
	}
}

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

	/// Bytes read from the process, and the moment they were taken off the pty.
	///
	/// The time comes from here rather than from the handler because the handler
	/// runs on `callbackQueue` — the main queue, in the app — and the question
	/// somebody asks of a terminal is "how far behind what the program has
	/// already said is the picture on the screen". When the main thread is busy,
	/// the hop is part of that answer, and a stamp taken after it would report
	/// zero for exactly the backlog it exists to find.
	public var onOutput: ((Data, Date) -> Void)?
	/// Called when the process exits, with its status.
	public var onExit: ((Int32) -> Void)?

	/// The master and the slave, and the one place either of them is closed.
	private let descriptors = TerminalDescriptors()
	/// The terminal's own device, as the child sees it.
	///
	/// Kept because it is how the tmux server is asked about the client running
	/// here, rather than about whichever client it last spoke to.
	public private(set) var slaveName: String?
	private var readSource: DispatchSourceRead?
	/// Whether a drain is already running, so writing again only adds to what
	/// it is working through.
	private var isDraining = false
	/// Bytes the pty could not take yet.
	private var pendingOutput = Data()
	private let writeLock = NSRecursiveLock()
	/// Guards the read source and whether it is suspended, so that suspending,
	/// resuming and cancelling it cannot happen at once from three threads.
	private let sourceLock = NSLock()
	private let writeQueue = DispatchQueue(label: "abydos.pty.write")
	private let readQueue = DispatchQueue(label: "abydos.pty.read", qos: .userInitiated)
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
	///
	/// Writing it tells the program straight away rather than waiting for the
	/// next resize. The winsize is one structure — cells *and* pixels — and the
	/// only thing that used to write it was a change in the number of cells, so
	/// a pane whose cell size changed while its grid stayed the same left the
	/// program believing the old one indefinitely. That is not a corner: the
	/// view works out the cell in pixels from the display's scale, and the first
	/// answer is given before the view is in a window and therefore before there
	/// is a display to ask. kitty's `icat` sizes a picture entirely from this,
	/// so the same file came out at one size on the first run and twice that
	/// later, once something happened to resize the pane.
	public var cellPixelSize: (width: Int, height: Int) = (0, 0) {
		didSet {
			guard cellPixelSize != oldValue else { return }
			resize(rows: grid.rows, columns: grid.columns)
		}
	}

	/// The grid last reported, so a change of cell size can be reported with it.
	private var grid: (rows: Int, columns: Int) = (24, 80)

	/// What this terminal has done, for whoever has to explain an empty pane.
	///
	/// 0476 was three wrong diagnoses in one evening, and every one of them would
	/// have been settled in a minute by these four numbers: whether the descriptor
	/// that keeps output alive was obtained, whether anything was ever read, how
	/// much, and what the program's exit status was. A failure that quotes them
	/// says which mechanism it was; one that says `""` starts the evening again.
	public struct Diagnostics: Sendable, CustomStringConvertible {
		/// Whether this process holds the child's end of the terminal.
		///
		/// Recorded when it was taken and never cleared, rather than asked of the
		/// descriptor now. Asking now was the first version and the answer was
		/// useless: by the time anything has an empty pane to complain about the
		/// terminal has been closed, so it says "no" whether it was held for the
		/// whole run or never obtained at all.
		public var holdsChildEnd: Bool
		/// How many times the read source fired — as distinct from how many times
		/// anything read, since the exit path reads once on its own account. Zero
		/// here with output missing says the reading queue never got a thread,
		/// which is a different fault from the pty discarding anything.
		public var sourceEvents: Int
		public var reads: Int
		public var bytesRead: Int
		/// How long the child took to be reaped, measured from the fork.
		///
		/// Worth having because it separates two failures that look identical from
		/// outside. Around 600 ms is the kernel's grace period running out, which
		/// means nothing was protecting the output. A millisecond or two means the
		/// child was already finished with this terminal.
		public var millisecondsToExit: Double
		/// What the last read got: `0` is end of file, so the terminal had already
		/// been torn down; `EAGAIN` means it was alive and simply empty.
		public var lastReadErrno: Int32
		public var terminalName: String?

		public var description: String {
			let ending = lastReadErrno == 0
				? "at end of file"
				: "still open (\(String(cString: strerror(lastReadErrno))))"
			return """
				pty \(terminalName ?? "unnamed"): child's end \
				\(holdsChildEnd ? "held" : "NOT HELD"), \(bytesRead) bytes in \
				\(reads) reads, read source fired \(sourceEvents)×, child reaped \
				\(String(format: "%.0f", millisecondsToExit))ms after the fork, \
				terminal \(ending)
				"""
		}
	}

	public var diagnostics: Diagnostics {
		readCounts.lock()
		defer { readCounts.unlock() }
		return Diagnostics(
			holdsChildEnd: holdsChildEnd,
			sourceEvents: sourceEvents,
			reads: reads,
			bytesRead: bytesRead,
			millisecondsToExit: millisecondsToExit,
			lastReadErrno: lastReadErrno,
			terminalName: slaveName
		)
	}

	/// The process on the other end, for as long as there is one.
	///
	/// Separate from `state`, which stops naming it the moment it exits — so a
	/// caller that wants to check afterwards that nothing was left behind has
	/// nothing to ask about. That is not hypothetical: it is how the test for
	/// exactly that failed on its first run.
	public private(set) var childProcessID: pid_t = -1

	private let readCounts = NSLock()
	private var reads = 0
	private var sourceEvents = 0
	private var bytesRead = 0
	private var holdsChildEnd = false
	private var millisecondsToExit: Double = -1
	private var lastReadErrno: Int32 = -1
	private var forkedAt = Date()

	public init() {}

	/// The size to hand the kernel: cells, and the pixels they come to.
	private func windowSize(rows: Int, columns: Int) -> winsize {
		let rows = max(1, rows)
		let columns = max(1, columns)
		grid = (rows, columns)
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

		// Everything the child needs is built here, before the fork, and the
		// child then does nothing but `chdir`, `execve` and `_exit`.
		//
		// After a fork the child is one thread in a copy of a process whose
		// other threads were stopped wherever they happened to be — including
		// inside a lock. Anything that allocates, reads Foundation or asks
		// Swift for type metadata can then wait for a lock nobody will release,
		// or find one already corrupt and abort. That is not theoretical: this
		// used to merge the environment on the far side, and merging it maps a
		// dictionary, which yields `(key, value)` tuples, and instantiating
		// tuple metadata takes exactly the lock a crash report named as
		// corrupt — "crashed on child side of fork pre-exec".
		let bundledCommands = BundledCommands.directory
		let environmentArray = Self.cStrings(
			Self.mergedEnvironment(environment, bundled: bundledCommands).map { "\($0.key)=\($0.value)" }
		)
		let argumentArray = Self.cStrings([executable] + arguments)
		let executablePath = strdup(executable)
		let directoryPath = workingDirectory.map { strdup($0.path) } ?? nil
		// An empty signal mask, built here for the same reason as everything else
		// on this side of the fork: the child only gets to make C calls on memory
		// that already existed. What it is for is where it is used, below.
		var noSignalsBlocked = sigset_t()
		sigemptyset(&noSignalsBlocked)
		defer {
			Self.free(environmentArray)
			Self.free(argumentArray)
			Foundation.free(executablePath)
			directoryPath.map { Foundation.free($0) }
		}

		// `openpty` and `fork`, rather than the `forkpty` that used to be here.
		// They do the same three things — open the pair, fork, and give the child
		// the terminal — but in that order, and the order is the whole point.
		//
		// `forkpty` hands the parent only the master: it closes the slave on this
		// side before it returns. This process has to hold a descriptor on the
		// child's end or the pty discards output nobody read within 600 ms (all of
		// `TerminalDescriptors` is about why), and with `forkpty` the only way to
		// get one back is to reopen it by name *after* the child already exists.
		//
		// **That window is not theoretical and it is not small.** Measured, with
		// the reopen in place and the full suite under load: the child wrote its
		// line, exited, had its output discarded and was reaped — all before this
		// side got as far as the reopen. The descriptor was obtained, faithfully,
		// and it was obtained too late to protect anything. Between `forkpty`
		// returning and the next few statements running there is a thread that can
		// be descheduled, and on a machine at twenty runnable threads per core it
		// is descheduled for longer than the deadline.
		//
		// Opened before the fork there is no window at all: the descriptor exists
		// before the child does, so there is no instant at which the child's output
		// is unprotected.
		var master: Int32 = -1
		var slave: Int32 = -1
		guard openpty(&master, &slave, nil, nil, &size) == 0 else { return false }

		// Close-on-exec on both, which is about *other* people's children rather
		// than this one's.
		//
		// A pty is freed when the last descriptor on either end goes, and until
		// then it counts against `kern.tty.ptmx_max` — 511 for the whole machine,
		// shared with every terminal, every tmux and every ssh on it. `openpty`
		// hands back two ordinary inheritable descriptors, so every program
		// started after this one — another pane, a `git`, a language server —
		// gets a copy of both, and goes on holding this terminal open for as long
		// as it runs. Closing the pane then frees nothing.
		//
		// That was measured rather than reasoned about: a leaked `/bin/cat` from
		// the test suite had `187u  CHR  16,1  /dev/ttys001` — a descriptor on a
		// *different* test's terminal, which it had no idea it was holding and
		// which could not be freed while it lived. Six such children pinned one
		// pty between them (item 0526).
		//
		// The child below is unaffected: it closes the master itself, and
		// `login_tty` puts the slave onto 0, 1 and 2 with `dup2`, which clears the
		// flag on the copies. It is the exec of something else entirely that this
		// stops.
		_ = fcntl(master, F_SETFD, FD_CLOEXEC)
		_ = fcntl(slave, F_SETFD, FD_CLOEXEC)

		// Named before the fork too, for the same reason and one more: `ptsname_r`
		// rather than `ptsname`, which answers into a static buffer shared by the
		// whole process. Two panes starting at once is the ordinary case here.
		var nameBuffer = [CChar](repeating: 0, count: 128)
		let name = ptsname_r(master, &nameBuffer, nameBuffer.count) == 0
			? String(validatingCString: nameBuffer) : nil

		guard let fork = Self.systemFork else {
			close(master)
			close(slave)
			return false
		}
		let pid = fork()
		// Stamped here so "how long until the child was reaped" is measured from
		// the fork and not from the end of the setup below.
		let forkReturned = Date()

		if pid < 0 {
			close(master)
			close(slave)
			return false
		}

		if pid == 0 {
			// Child. C calls on memory that already existed before the fork, and
			// nothing else — see the note above the fork.
			//
			// `login_tty` is the part `forkpty` did here: `setsid`, then TIOCSCTTY
			// to take this terminal as the controlling one, then the slave onto
			// stdin, stdout and stderr. It is the whole reason a pty is worth the
			// trouble — a program only turns on colour and full-screen drawing for
			// a terminal it believes it owns — and it is what `posix_spawn` cannot
			// express.
			//
			// Its answer is checked, which `forkpty` did not leave room to do: it
			// puts the slave onto stdin, stdout and stderr *after* taking the
			// terminal, so a failure means the program runs with this process's own
			// descriptors — writing what should have been a pane's output onto the
			// app's stdout. Better to be a child that exited than a child talking
			// to the wrong end of the machine.
			close(master)
			if login_tty(slave) != 0 { _exit(127) }
			// A signal state of the child's own, which is the whole of item 0526.
			//
			// Both halves of it survive `execve`: a thread's *blocked* mask is
			// inherited by the child of a fork and kept across the exec, and a
			// disposition of `SIG_IGN` is kept across the exec too. So a program
			// started here does not begin life with the signals a program expects
			// — it begins with whatever this process happened to be holding.
			//
			// Neither of those is hypothetical here, and the first one cost days.
			// This fork runs on whichever thread called `start`, and under the
			// test runner that is a Swift concurrency worker, whose mask is
			// `0b11111011111111101110000000100111` — SIGHUP, SIGINT and SIGTERM
			// all blocked. `terminate()` sends SIGHUP; the child cannot receive
			// it; the signal sits pending for the rest of the process's life. A
			// `/bin/cat` on a pty then survives being terminated, is re-parented
			// to launchd when the test run ends, and holds its pty for as long as
			// the machine is up. 443 of them had accumulated before anything
			// noticed, and what noticed was three unrelated terminal suites
			// failing at once because the machine was out of ptys.
			//
			// The second half is smaller and older: this package ignores SIGPIPE
			// process-wide (`BrokenPipes`, and it must), and without this every
			// shell in every pane inherited that — so `yes | head` in a pane left
			// `yes` running rather than killing it, which is not what a terminal
			// is for.
			//
			// `signal` and `sigprocmask` are both async-signal-safe, which is the
			// bar for anything between the fork and the exec.
			var signalNumber: Int32 = 1
			while signalNumber < NSIG {
				// SIGKILL and SIGSTOP refuse, harmlessly.
				signal(signalNumber, SIG_DFL)
				signalNumber += 1
			}
			sigprocmask(SIG_SETMASK, &noSignalsBlocked, nil)
			if let directoryPath { chdir(directoryPath) }
			execve(executablePath, argumentArray, environmentArray)
			// Only reached if exec failed; _exit avoids running atexit handlers
			// inherited from the parent.
			_exit(127)
		}

		slaveName = name
		descriptors.adopt(master: master, slave: slave)
		readCounts.lock()
		holdsChildEnd = slave >= 0
		readCounts.unlock()
		forkedAt = forkReturned
		childProcessID = pid
		state = .running(pid: pid)

		// Anything the merge refused, said in the pane it was refused for.
		//
		// Delivered as though the program had printed it, because a pane has no
		// other channel: what it shows is the bytes it is given. Queued before
		// reading starts, and the callback queue is serial, so it is ahead of
		// the shell's first byte rather than racing it into the middle of a
		// prompt.
		//
		// And in the log as well as in the pane, because the pane is not
		// certain to keep it: the tab that attaches tmux runs `tmux new -A` as
		// its first command, and tmux switches to the alternate screen and
		// clears it — so the sentence is written, shown, and gone inside a
		// second. That was watched happening rather than guessed at. The pane
		// that stays plain keeps it above the first prompt.
		//
		// The log write goes to a queue of its own, and that is not tidiness:
		// written here it put a file open, a size check and a close between the
		// fork and the reader starting, and `/bin/echo` had said its piece and
		// closed the slave before there was anything listening. A test that had
		// passed for a year started timing out, which is the only reason this
		// is known.
		if let refusal = Self.refusals(environment) {
			DispatchQueue.global(qos: .utility).async {
				DiagnosticLog.write(
					refusal.trimmingCharacters(in: .whitespacesAndNewlines), to: "tmux"
				)
			}
			let refusedAt = Date()
			callbackQueue.async { [weak self] in
				self?.onOutput?(Data(refusal.utf8), refusedAt)
			}
		}

		configureNonBlocking(master)
		startReading()
		watchForExit(pid: pid)
		return true
	}

	/// The environment a shell in this app is started with.
	///
	/// Built before the fork, and separated out so what it puts there can be
	/// checked without starting anything.
	static func mergedEnvironment(
		_ given: [String: String]?,
		bundled: String?,
		app: String? = BundledCommands.appBundle,
		inherited: [String: String] = ProcessInfo.processInfo.environment
	) -> [String: String] {
		var merged = given ?? inherited
		// Claim a capable terminal so tools enable colour and full-screen UI.
		merged["TERM"] = merged["TERM"] ?? "xterm-256color"
		merged["COLORTERM"] = merged["COLORTERM"] ?? "truecolor"
		merged["LANG"] = merged["LANG"] ?? "en_US.UTF-8"
		// Stop pagers from hanging a pane waiting for a keypress.
		merged["PAGER"] = merged["PAGER"] ?? "cat"

		// Which terminal this is, by the name every other terminal uses for
		// itself. `abydos <file>` reads it to decide whether the escape that
		// opens a file in this window is worth writing at all, and any inherited
		// value is a lie here — the app launched from Ghostty inherits
		// `TERM_PROGRAM=ghostty`, and a pane of ours claiming to be Ghostty is
		// exactly the wrong answer. So it is set rather than defaulted.
		merged["TERM_PROGRAM"] = BundledCommands.termProgram
		// Which build to fall back to when the escape does not reach anybody.
		// Without it the command opens `/Applications/Abydos.app`, which is not
		// the app somebody running a checkout is looking at.
		if let app { merged["IDEAI_APP"] = app }

		// And a pane is not inside tmux until something in it starts tmux.
		//
		// The same lie as `TERM_PROGRAM`, and inherited the same way: an app
		// launched from a shell that is inside tmux — which is how anybody
		// running `make run` launches it — hands `TMUX` to every pane it opens,
		// naming a session none of them is in. `abydos <file>` believed it,
		// wrapped its question in a tmux passthrough nothing was there to
		// unwrap, heard no answer, and quietly opened the file through
		// LaunchServices instead of in the window it was typed in. It cost an
		// afternoon to see, because every part of it behaved correctly given
		// what it had been told.
		//
		// Removed rather than blanked: a shell that finds `TMUX` set to the
		// empty string is in no tmux either, but tmux itself sets the variable
		// when it starts, and something that has to be right for both wants the
		// absence rather than a second spelling of it. A pane that goes on to
		// run `tmux new -A` gets its own from tmux, which is the only thing
		// entitled to say so.
		merged["TMUX"] = nil
		merged["TMUX_PANE"] = nil

		// And one variable further along, for the same reason and with a louder
		// ending. `TMUX_TMPDIR` says where tmux keeps its sockets, it is
		// inherited exactly as `TMUX` was, and tmux appends `tmux-<uid>/default`
		// to it — so a directory that is merely long produces a socket path over
		// the length a unix socket can have. tmux says `File name too long` and
		// the pane is dead before it draws a prompt, naming a path nobody typed.
		//
		// Refused on what it produces rather than on being set at all: somebody
		// with a short, valid one means it, and taking it away would put their
		// panes on a different server from their other tools. `TmuxSocketPath`
		// has the arithmetic and the sentence the pane is given.
		merged = TmuxSocketPath.honouringWhatFits(merged)

		// The commands this app ships — `abydos-icat`, `abydos-bench` — on the
		// PATH of every shell it starts, without an install step. Appended
		// rather than prepended: a command somebody already has wins, since
		// shadowing what is on somebody's PATH is not this app's business.
		if let bundled {
			let path = merged["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
			if !path.split(separator: ":").contains(Substring(bundled)) {
				merged["PATH"] = path + ":" + bundled
			}
		}
		return merged
	}

	/// What the merge above threw away, ready to be written to a pane.
	///
	/// Separate from the merge because the two answers go to different places:
	/// one to `execve`, one to whoever is looking. Both are worked out from the
	/// same input, so a value refused is always a value explained.
	///
	/// It ends `\r\n` rather than `\n`: this goes to a terminal in raw mode,
	/// where a bare newline drops a line without returning to column one, and
	/// the shell's prompt would then start under the end of the sentence.
	static func refusals(
		_ given: [String: String]?,
		inherited: [String: String] = ProcessInfo.processInfo.environment
	) -> String? {
		let environment = given ?? inherited
		guard let refusal = TmuxSocketPath.refusal(for: environment["TMUX_TMPDIR"]) else {
			return nil
		}
		return refusal + "\r\n"
	}

	/// C's `fork`, which Swift's Darwin overlay refuses to expose.
	///
	/// It is marked unavailable — "Please use threads or posix_spawn*()" — and for
	/// almost everything that is the right advice. This is the exception: the child
	/// has to call `setsid` and TIOCSCTTY on a terminal descriptor between the fork
	/// and the exec, and `posix_spawn` has no way to say that. `forkpty` was doing
	/// exactly this fork underneath; the only thing that changed is that this side
	/// now keeps the slave, which it must.
	///
	/// Resolved by name rather than declared with `@_silgen_name`, so what is
	/// happening is a documented C API call and not a compiler-internal attribute
	/// that could mean something different next release.
	private static let systemFork: (@convention(c) () -> pid_t)? = {
		// RTLD_DEFAULT: the ordinary search order, which is where libc is.
		guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "fork") else {
			return nil
		}
		return unsafeBitCast(symbol, to: (@convention(c) () -> pid_t).self)
	}()

	/// A null-terminated C array of copies, for `execve`.
	static func cStrings(_ strings: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
		let array = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
		for (index, string) in strings.enumerated() { array[index] = strdup(string) }
		array[strings.count] = nil
		return array
	}

	static func free(_ array: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) {
		var index = 0
		while let element = array[index] {
			Foundation.free(element)
			index += 1
		}
		array.deallocate()
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

	/// Set before the first byte goes anywhere near a descriptor. The app does
	/// this at launch; a tool that only uses the kit gets it here.
	private func ignoreBrokenPipes() {
		BrokenPipes.ignore()
	}

	private func startReading() {
		ignoreBrokenPipes()
		guard let master = descriptors.withMaster({ $0 }) else { return }
		let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: readQueue)
		source.setEventHandler { [weak self] in
			guard let self else { return }
			self.readCounts.lock()
			self.sourceEvents += 1
			self.readCounts.unlock()
			let gathered = self.readWhatIsThere()
			guard !gathered.isEmpty else { return }
			self.deliver(gathered)
		}
		// The close hangs off the cancel handler rather than following the
		// `cancel()` call, because dispatch runs this once the source has
		// genuinely finished with the descriptor. Closing a number a source is
		// still watching is the way a source ends up reporting events about
		// whatever file the kernel handed the number to next. It holds the
		// descriptors and not `self`, so it still closes them if the terminal
		// itself has been deallocated by then.
		source.setCancelHandler { [descriptors] in descriptors.close() }
		source.resume()
		readSource = source
	}

	/// Everything the pty has for us right now.
	///
	/// Gathered into one delivery rather than one per read. A program painting a
	/// whole screen produces its frame in many small writes, and handing each of
	/// them over separately was costing far more in hops between queues than the
	/// bytes themselves cost to parse.
	///
	/// Always on `readQueue`, which is serial — so "what is in the pty" is only
	/// ever asked by one thread, and the last read before the terminal closes has
	/// finished before the descriptor goes.
	private func readWhatIsThere(limit: Int = 512 * 1024) -> Data {
		var gathered = Data()
		var buffer = [UInt8](repeating: 0, count: 64 * 1024)
		var ending: Int32 = -1
		while gathered.count < limit {
			let count = descriptors.withMaster { read($0, &buffer, buffer.count) } ?? -1
			if count <= 0 { ending = count == 0 ? 0 : errno }
			guard count > 0 else { break }
			gathered.append(contentsOf: buffer[0..<count])
			if count < buffer.count { break }
		}
		readCounts.lock()
		reads += 1
		bytesRead += gathered.count
		lastReadErrno = ending
		readCounts.unlock()
		return gathered
	}

	/// Bytes read but not yet handed over, in pieces, each stamped with when the
	/// first of its bytes was read.
	///
	/// A list rather than one buffer so that no byte is reported older than it is:
	/// a read is merged into the last piece while that piece is still under the
	/// hand-over limit, and starts a new one after that. One merged buffer would
	/// have to carry a single stamp for bytes read tens of milliseconds apart, and
	/// the only safe choice — the oldest — reports a screen further behind than it
	/// is and holds back frames that were current.
	private var held: [(bytes: Data, readAt: Date)] = []
	private var heldBytes = 0
	private var deliveryScheduled = false
	private let deliveryLock = NSLock()

	/// Hands bytes to the callback queue, one delivery in flight at a time.
	///
	/// `readWhatIsThere` already gathers everything the pty has into one
	/// delivery, and this does the same thing one level up: everything read
	/// *while the last delivery is still waiting to be looked at* is gathered
	/// into the next one. Only ever one block is queued, so the callback queue
	/// cannot become the place a backlog hides (item 0491).
	///
	/// It used to hop once per read, and that had two costs which turned out to
	/// be the same cost. A busy terminal read a kilobyte at a time and posted
	/// fifteen thousand blocks a second at the main thread; and because each
	/// block carried its own bytes, the queue of blocks *was* the backlog — a
	/// third of a second of output on ordinary log output, nearly three seconds
	/// on a slow engine, none of it visible to anything counting what was left to
	/// parse, and none of it something back-pressure could reach. Merging makes
	/// the queue of unparsed output the only queue there is, which is what lets it
	/// be measured and bounded.
	///
	/// Memory is no worse than it was: the same bytes were previously held by the
	/// same number of blocks, one `Data` each, and are now one buffer.
	///
	/// Handed over in pieces of at most `deliveryLimit`, and both halves of that
	/// number were measured. Too small and an engine with a fixed cost per write
	/// pays it per kilobyte — libghostty-vt spends about half a millisecond
	/// bringing its render state up to date on every `write`, whatever its size,
	/// which at a kilobyte a read is where forty-five frames a second became one.
	/// Too large and a single `write` runs past the frame it is in: merging with
	/// no limit at all produced deliveries of five megabytes that took 235 ms,
	/// and the screen fell to fourteen frames a second on ordinary log output.
	private func deliver(_ gathered: Data) {
		recordRawOutput(gathered)
		// Stamped on the reading queue, before the hop, for the reason on
		// `onOutput`: the wait for the main thread is part of how stale these
		// bytes are by the time anybody could see them. The stamp kept is the
		// *oldest* in the batch, because that is how far behind the picture is.
		let readAt = Date()
		deliveryLock.lock()
		if !held.isEmpty, held[held.count - 1].bytes.count < Self.deliveryLimit {
			held[held.count - 1].bytes.append(gathered)
		} else {
			held.append((gathered, readAt))
		}
		heldBytes += gathered.count
		let alreadyOnItsWay = deliveryScheduled
		deliveryScheduled = true
		deliveryLock.unlock()
		guard !alreadyOnItsWay else { return }

		handOver()
	}

	/// How much a single hand-over may carry.
	private static let deliveryLimit = 128 << 10

	private func handOver() {
		callbackQueue.async {
			self.deliveryLock.lock()
			guard !self.held.isEmpty else {
				self.deliveryScheduled = false
				self.deliveryLock.unlock()
				return
			}
			let piece = self.held.removeFirst()
			self.heldBytes -= piece.bytes.count
			// More left over: the flag stays up, so a read arriving meanwhile
			// merges into what is here rather than queueing a second hand-over.
			let more = !self.held.isEmpty
			self.deliveryScheduled = more
			self.deliveryLock.unlock()
			self.onOutput?(piece.bytes, piece.readAt)
			if more { self.handOver() }
		}
	}

	/// Bytes read from the pty and not yet handed to `onOutput`, and when the
	/// oldest of them was read.
	///
	/// Read by whoever is deciding how far behind the screen is and whether the
	/// program should be made to wait. It has to be asked here because these bytes
	/// have left the pty and not arrived anywhere else: counting only what the
	/// caller has been given would report an empty backlog for output that is
	/// already a second old (item 0491).
	public var undeliveredBacklog: (bytes: Int, oldestAt: Date?) {
		deliveryLock.lock()
		defer { deliveryLock.unlock() }
		return (heldBytes, held.first?.readAt)
	}

	/// Every byte the program produced, appended to a file, when asked.
	///
	/// `ABYDOS_TERM_LOG=<path>` and nothing otherwise — one `getenv` per read of
	/// a pty, which is nothing beside the read. It exists because the questions
	/// worth asking about a terminal are about the bytes it was given, and
	/// reproducing those from the program that sent them is guesswork: what
	/// `script` records is what the program wrote, not what arrived here after
	/// tmux and the line discipline had their turn.
	/// Where raw output is recorded, asked of the environment **once**.
	///
	/// `ProcessInfo.environment` builds a fresh dictionary out of `environ` every
	/// time it is read, and this is called for every chunk that arrives from the
	/// pty. In a CPU profile of the fire benchmark `recordRawOutput` was 2,488 of
	/// 85,488 samples — about three per cent of the run spent deciding not to log,
	/// on a machine where the variable is not set at all.
	///
	/// A `static let` because the environment of a running process does not
	/// change: `setenv` from another thread is not something this program does,
	/// and a diagnostic that has to be turned on before launch is the only kind
	/// that would catch the first bytes anyway.
	private static let rawOutputPath: String? = {
		guard let path = ProcessInfo.processInfo.environment["ABYDOS_TERM_LOG"],
		      !path.isEmpty
		else { return nil }
		return path
	}()

	private func recordRawOutput(_ data: Data) {
		guard let path = Self.rawOutputPath else { return }
		if let handle = FileHandle(forWritingAtPath: path) {
			handle.seekToEndOfFile()
			try? handle.write(contentsOf: data)
			try? handle.close()
		} else {
			try? data.write(to: URL(fileURLWithPath: path))
		}
	}

	/// The terminal device the child sees, which is how tmux is asked about the
	/// client sitting on it.
	public var ttyName: String? { slaveName }

	/// Where the process in the foreground of this terminal currently is.
	public func currentDirectory() -> URL? {
		descriptors.withMaster {
			TerminalDirectory.current(masterDescriptor: $0, slaveName: slaveName)
		} ?? nil
	}

	/// Where the shell is, asked only while it is the thing in front — see
	/// `TerminalDirectory.settled`. Nil while a command is running, which is
	/// what stops a window being dragged through every directory a script
	/// visits.
	public func settledDirectory() -> URL? {
		descriptors.withMaster {
			TerminalDirectory.settled(
				masterDescriptor: $0, slaveName: slaveName, shell: childProcessID
			)
		} ?? nil
	}

	/// Stops or resumes taking bytes out of the pty.
	///
	/// While stopped the bytes stay in the pty's buffer and, once it is full,
	/// the process writing to it blocks — which is how a terminal tells a
	/// program that it is going faster than anyone can look at.
	///
	/// Under a lock rather than hopped onto the reading queue. Both keep the
	/// suspends and resumes balanced, which is what matters — an unbalanced
	/// count is a source that never runs again or a crash — but the lock also
	/// makes it synchronous, and the close path needs that: it has to know
	/// whether the source is suspended before it cancels it. A hop would leave
	/// the answer in a queue that may not run for a while, which is exactly the
	/// condition this is all about.
	public func setReadingSuspended(_ suspended: Bool) {
		sourceLock.lock()
		defer { sourceLock.unlock() }
		guard let source = readSource, suspended != isReadingSuspended else { return }
		isReadingSuspended = suspended
		if suspended { source.suspend() } else { source.resume() }
	}

	/// Sends bytes to the program, however many there are.
	///
	/// The master is non-blocking, so a write that fills the pty's buffer —
	/// which a pasted crash report does several times over — comes back saying
	/// "not now". What is left is kept and written when the program has read
	/// enough to make room, rather than dropped: the old loop broke out on that
	/// and the rest of a paste simply never arrived.
	public func write(_ data: Data) {
		guard descriptors.isOpen, isRunning, !data.isEmpty else { return }
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
				//
				// It waits with the descriptors held, which delays nothing that
				// matters: reading holds them the same way and the two do not
				// exclude each other. Only a close waits, and only when there is
				// a paste still going out that the program has stopped reading.
				let waited = self.descriptors.withMaster { master -> Int32 in
					var descriptor = pollfd(fd: master, events: Int16(POLLOUT), revents: 0)
					return poll(&descriptor, 1, 200)
				}
				// The terminal went while we were queueing: nothing left to wait for.
				guard waited != nil else { break }
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
			let written = pendingOutput.withUnsafeBytes { raw -> Int? in
				guard let base = raw.baseAddress else { return nil }
				return descriptors.withMaster { Darwin.write($0, base, raw.count) }
			}
			// No terminal any more, so what is queued has nowhere to go.
			guard let written else {
				pendingOutput.removeAll()
				return false
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
		// `windowSize` records the numbers whether or not there is anything to
		// tell them to: with no terminal yet these are the ones the child will be
		// started with.
		var size = windowSize(rows: rows, columns: columns)
		guard descriptors.withMaster({ ioctl($0, TIOCSWINSZ, &size) }) != nil else { return }
		// SIGWINCH is what full-screen applications actually listen for.
		if case let .running(pid) = state {
			kill(pid, SIGWINCH)
		}
	}

	/// What the kernel currently believes about this terminal.
	///
	/// Read back from the device rather than from what was last handed to it,
	/// because the claim worth checking is that the program on the other end can
	/// see the change — not that this file remembered it.
	public var reportedWindowSize: (rows: Int, columns: Int, pixelWidth: Int, pixelHeight: Int)? {
		var size = winsize()
		guard descriptors.withMaster({ ioctl($0, TIOCGWINSZ, &size) }) == 0 else { return nil }
		return (Int(size.ws_row), Int(size.ws_col), Int(size.ws_xpixel), Int(size.ws_ypixel))
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

			guard let self else { return }
			self.readCounts.lock()
			self.millisecondsToExit = -self.forkedAt.timeIntervalSinceNow * 1000
			self.readCounts.unlock()
			// Through the reading queue, and that is what makes the order true
			// rather than likely. It is serial, so a read already running has
			// finished and handed its bytes on before this block starts, and
			// anything still sitting in the pty is taken here — all of it before
			// the terminal is closed and before the exit is announced. A pane
			// that showed a command's exit above its output would be showing
			// them in the order two queues happened to get threads.
			//
			// Not `callbackQueue`, which is where this used to be. That queue
			// belongs to whoever is watching — the main queue in the app — and
			// closing the terminal from it meant closing it while the reading
			// queue might still be inside a read on the same descriptor.
			self.readQueue.async {
				self.deliverWhatIsLeft()
				self.closeDescriptors()
				self.callbackQueue.async {
					self.state = .exited(code: code)
					self.onExit?(code)
				}
			}
		}
	}

	/// Takes what the program left in the pty and hands it on.
	///
	/// With a slave descriptor held, `waitpid` cannot return until the pty has
	/// been drained, so by this point the read source has usually had it all
	/// already and this finds nothing. It runs anyway, for the case where the
	/// slave could not be opened: then the old deadline is back, and this is the
	/// last chance anybody has at those bytes.
	private func deliverWhatIsLeft() {
		while true {
			let gathered = readWhatIsThere()
			guard !gathered.isEmpty else { return }
			deliver(gathered)
		}
	}

	/// Sends SIGHUP and closes the terminal, ending the session.
	public func terminate() {
		if case let .running(pid) = state {
			// The whole foreground process group, so children go too.
			kill(-pid, SIGHUP)
			kill(pid, SIGHUP)
		}
		closeDescriptors()
	}

	/// Closes the terminal: one place, once, whoever asks.
	///
	/// Both callers used to do this themselves — this one and the exit watcher —
	/// each guarding on the descriptor being set and neither knowing about the
	/// other. Closing a descriptor number twice is not harmless: the kernel may
	/// hand the number out again in between, and the second close then lands on a
	/// file belonging to something else entirely.
	private func closeDescriptors() {
		sourceLock.lock()
		let source = readSource
		readSource = nil
		// A cancelled source that is suspended does not run its cancel handler
		// until something resumes it, and the close hangs off that handler. It
		// would matter anyway; it matters much more now that this process holds a
		// slave descriptor, because a child cannot finish exiting until the pty is
		// read or closed. A terminal left shut would leave the child waiting for
		// ever, which is a worse bug than the one being fixed.
		if source != nil, isReadingSuspended {
			source?.resume()
			isReadingSuspended = false
		}
		sourceLock.unlock()

		if let source {
			source.cancel()
		} else {
			// Never started, or already closed: nothing is watching the
			// descriptors, so there is nothing to wait for.
			descriptors.close()
		}
	}

	/// Sends an interrupt, as ⌃C would.
	public func interrupt() {
		guard case let .running(pid) = state else { return }
		kill(-pid, SIGINT)
	}
}

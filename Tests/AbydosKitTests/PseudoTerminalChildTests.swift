import Foundation
import Testing
@testable import AbydosKit

/// What a program started on a pty inherits from this process, and what it must
/// not.
///
/// Both of these are about the same afternoon (item 0526). The suite had 443
/// `/bin/cat` processes left over from previous runs, the oldest five days old,
/// each holding a pty; `kern.tty.ptmx_max` is 511 for the whole machine, so once
/// they crossed it every terminal test failed at once — in three suites that had
/// nothing to do with each other and nothing wrong with them — and so did every
/// new terminal in every other program on the machine.
///
/// Neither half of it is visible from inside a test that only checks its own
/// terminal works, which is why both are checked here directly.
struct PseudoTerminalChildTests {
	/// A signal sent to the child arrives, whatever the thread that forked it
	/// happened to be blocking.
	///
	/// A blocked signal mask is inherited by the child of a fork and kept across
	/// `execve`, and `start` forks on whichever thread called it. Under the test
	/// runner that is a Swift concurrency worker with SIGHUP, SIGINT and SIGTERM
	/// already blocked — so `terminate()` sent a SIGHUP that could never be
	/// delivered, and the `cat` on the other end went on running for days. The
	/// three are blocked here explicitly rather than relied upon, since what the
	/// runner does with its threads is not this package's to promise.
	///
	/// Sent straight to the child with the terminal left open, so that nothing
	/// but the signal can be what ended it: the exit status says which. 143 is
	/// 128 + SIGTERM, the way a shell reports it.
	@Test func aSignalReachesTheChildEvenWhenThisThreadBlocksIt() async throws {
		let terminal = PseudoTerminal()
		terminal.callbackQueue = DispatchQueue(label: "ideai.tests.pty.signals")
		let exit = Exited()
		terminal.onExit = { exit.note($0) }

		// No suspension between blocking and restoring: an `await` in here could
		// come back on another thread and leave this one blocked for good.
		var blocked = sigset_t()
		sigemptyset(&blocked)
		sigaddset(&blocked, SIGHUP)
		sigaddset(&blocked, SIGINT)
		sigaddset(&blocked, SIGTERM)
		var previous = sigset_t()
		sigemptyset(&previous)
		pthread_sigmask(SIG_BLOCK, &blocked, &previous)
		let started = terminal.start(
			executable: "/bin/cat", arguments: [], rows: 24, columns: 80
		)
		pthread_sigmask(SIG_SETMASK, &previous, nil)

		try #require(started)
		defer { terminal.terminate() }
		let child = terminal.childProcessID
		try #require(child > 0)

		#expect(kill(child, SIGTERM) == 0)
		#expect(await exit.wait(seconds: 10), "the child outlived a signal sent to it")
		#expect(exit.code == 143, "128 + SIGTERM, so the signal is what ended it")
	}

	/// The terminal's own descriptors are not handed to the next program this
	/// process starts.
	///
	/// A pty is freed when the last descriptor on either end goes, and `openpty`
	/// hands back two ordinary inheritable ones — so without close-on-exec every
	/// program started afterwards, in this process or any other part of the app,
	/// keeps a copy and keeps this terminal allocated for as long as it runs.
	/// Closing the pane then frees nothing.
	///
	/// It was found the other way round: a leaked `cat` had `187u CHR 16,1
	/// /dev/ttys001` — a descriptor on a *different* test's terminal, which it
	/// had no idea it was holding.
	///
	/// Checked against the slave by device, because that is the end whose name is
	/// known and the end that pins the pty.
	@Test func theTerminalsDescriptorsAreNotInheritedByTheNextProgramStarted() throws {
		let terminal = PseudoTerminal()
		terminal.callbackQueue = DispatchQueue(label: "ideai.tests.pty.inheritance")
		try #require(terminal.start(
			executable: "/bin/cat", arguments: [], rows: 24, columns: 80
		))
		defer { terminal.terminate() }

		let name = try #require(terminal.slaveName)
		var device = stat()
		try #require(stat(name, &device) == 0)

		var found = 0
		for descriptor in Int32(0)..<1024 {
			var opened = stat()
			guard fstat(descriptor, &opened) == 0 else { continue }
			guard opened.st_mode & S_IFMT == S_IFCHR, opened.st_rdev == device.st_rdev
			else { continue }
			found += 1
			let flags = fcntl(descriptor, F_GETFD)
			#expect(
				flags >= 0 && flags & FD_CLOEXEC != 0,
				"descriptor \(descriptor) on \(name) would be handed to the next exec"
			)
		}
		#expect(found == 1, "the child's end, which this process holds until the pty closes")
	}

	/// The exit status, from the queue it is delivered on.
	private final class Exited: @unchecked Sendable {
		private let lock = NSLock()
		private var status: Int32?

		func note(_ code: Int32) {
			lock.lock(); status = code; lock.unlock()
		}

		var code: Int32 {
			lock.lock(); defer { lock.unlock() }
			return status ?? -1
		}

		var hasExited: Bool {
			lock.lock(); defer { lock.unlock() }
			return status != nil
		}

		func wait(seconds: TimeInterval) async -> Bool {
			let deadline = Date().addingTimeInterval(seconds)
			while Date() < deadline {
				if hasExited { return true }
				try? await Task.sleep(nanoseconds: 20_000_000)
			}
			return hasExited
		}
	}
}

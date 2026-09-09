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
final class TerminalDescriptors: @unchecked Sendable {
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

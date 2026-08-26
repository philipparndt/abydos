import Foundation

/// Collecting what a subprocess wrote, without deadlocking against it.
///
/// The obvious way is wrong, and it was written the obvious way in six places
/// here:
///
///     let outData = out.fileHandleForReading.readDataToEndOfFile()
///     let errData = err.fileHandleForReading.readDataToEndOfFile()
///
/// The first read only returns when the program closes its output, which it
/// does when it exits — and it cannot exit while it is blocked writing to the
/// other pipe. A pipe nobody is reading holds very little, and the kernel only
/// grows one that is being drained, so "very little" can be a paragraph. So a
/// program that says more on stderr than that stops, forever, and takes
/// whatever was waiting for it with it.
///
/// This hung the test suite several times in one afternoon — `git push` with no
/// upstream prints a paragraph of advice — and the same shape sat in front of
/// `helm`, `kubectl`, `make` and `plantuml`, all of which are chattier on
/// stderr than git is.
///
/// The fix is only to read both at once, which is what this does.
public enum ProcessPipes {
	/// Reads both pipes to the end, sends `input` if there is any, and waits
	/// for the process to finish.
	///
	/// - Parameters:
	///   - stdin: the pipe attached to the process's input, when it has one.
	///     Written on a thread of its own and then closed, since input larger
	///     than a pipe blocks in the same way from the other end.
	///   - onOutput: each piece of both streams, as it arrives, for a caller
	///     showing the program's output rather than waiting for all of it. It is
	///     called on the reading threads — one per stream, so two of them — which
	///     is the point: a `docker build` that takes four minutes is four minutes
	///     of nothing at all if its output only appears at the end.
	public static func drain(
		_ process: Process,
		out: Pipe,
		err: Pipe,
		input: Data? = nil,
		stdin: Pipe? = nil,
		onOutput: (@Sendable (Data) -> Void)? = nil
	) -> (stdout: Data, stderr: Data) {
		let group = DispatchGroup()
		let output = Box(), errors = Box()
		let stop = Flag()

		// Taken before anything can be closed: asking a closed `FileHandle` for
		// its descriptor is its own kind of trouble.
		let outDescriptor = out.fileHandleForReading.fileDescriptor
		let errDescriptor = err.fileHandleForReading.fileDescriptor

		// **Threads of their own, and not the global queue.** This is what made
		// the git suites unreliable, and it is worse than unreliable tests: a
		// reader that never got a thread came back empty from a command that had
		// *succeeded*, so callers were handed exit code 0 and no output and read
		// it as "no changes", "no stashes", "no files in that commit".
		//
		// GCD's global queues overcommit only so far — about sixty-four threads
		// per quality of service — and every one of these reads blocks its
		// thread until end of file. Run enough commands at once and the readers
		// for the newest of them are still queued when the two-second grace
		// below runs out, so `stop` is set on a read that never began.
		//
		// Measured: the git suites failed every run with twenty to fifty
		// expectation failures, all of them a value that should have been read
		// coming back empty, and passed every run when the same tests were
		// serialised. A thread apiece cannot be starved by other work, which is
		// the whole of the fix; the grace below then means what it says, which
		// is "the program has exited, drain what it left".
		startReader(group: group) {
			output.data = readToEnd(outDescriptor, until: stop, onData: onOutput)
		}
		startReader(group: group) {
			errors.data = readToEnd(errDescriptor, until: stop, onData: onOutput)
		}
		if let stdin {
			if let input {
				DispatchQueue.global(qos: .userInitiated).async(group: group) {
					try? stdin.fileHandleForWriting.write(contentsOf: input)
					try? stdin.fileHandleForWriting.close()
				}
			} else {
				// Closed at once, so a program that reads its input sees the
				// end of it rather than waiting for one that never comes.
				try? stdin.fileHandleForWriting.close()
			}
		}

		// What is actually being waited for is the program finishing. The reads
		// are waiting for end of file, which is a different thing and can be a
		// great deal longer.
		//
		// End of file needs *every* copy of the write end to be closed, and
		// Foundation does not mark a pipe's descriptors close-on-exec — so any
		// other subprocess that happened to be started while this one was being
		// set up inherited them, and holds them open for as long as it runs. A
		// language server or a debug adapter that outlives the command is
		// enough to pin the pipe open forever. That is not hypothetical: two
		// stray `/bin/cat` processes left behind by a test held a `git` pipe
		// open and hung the suite for twenty minutes, with `lsof` showing them
		// holding five pipes rather than their own three.
		//
		// So: wait for the program, then give the readers a moment to finish
		// draining what it left, and then tell them to stop. A truncated
		// capture from a program that has already exited beats waiting for a
		// stranger to quit.
		//
		// *Tell*, not close. Closing the descriptor under a blocked reader was
		// how this used to end the read, and it ended the app instead: see
		// `readToEnd`.
		process.waitUntilExit()
		// Waited for here rather than on a borrowed thread. This used to dispatch
		// a block that did `group.wait()` and signalled a semaphore — which is
		// the same starvation the readers had, one layer up: a waiter that had
		// not been given a thread yet made the two seconds expire against a
		// group that was already finished, and `stop` was set on a completed
		// read. `DispatchGroup` can be waited on with a timeout directly, so
		// there is nothing to borrow.
		if group.wait(timeout: .now() + .seconds(2)) == .timedOut {
			stop.set()
			_ = group.wait(timeout: .now() + .seconds(2))
		}
		return (output.data, errors.data)
	}

	/// For a program whose errors go somewhere else — `/dev/null`, or the same
	/// pipe as its output — where there is only one thing to read.
	///
	/// Still waits for the program rather than for end of file, which is the
	/// point: one pipe is no protection from a stray process holding it open.
	public static func drain(_ process: Process, out: Pipe) -> Data {
		let group = DispatchGroup()
		let output = Box()
		let stop = Flag()
		let descriptor = out.fileHandleForReading.fileDescriptor
		// A thread of its own, and waited for here — for the reasons the two-pipe
		// `drain` above gives at length.
		startReader(group: group) {
			output.data = readToEnd(descriptor, until: stop)
		}
		process.waitUntilExit()
		if group.wait(timeout: .now() + .seconds(2)) == .timedOut {
			stop.set()
			_ = group.wait(timeout: .now() + .seconds(2))
		}
		return output.data
	}

	/// The same, decoded, which is what every caller here wants.
	public static func drainText(
		_ process: Process,
		out: Pipe,
		err: Pipe,
		input: Data? = nil,
		stdin: Pipe? = nil,
		onOutput: (@Sendable (String) -> Void)? = nil
	) -> (stdout: String, stderr: String) {
		// Decoded a piece at a time, which is what "as it arrives" costs: a
		// multi-byte character split across two reads comes out as a replacement
		// character in the piece rather than in the whole, which the strings
		// returned below are not — nothing is lost, and what is being fed here is
		// a runtime's progress lines.
		//
		// `@Sendable` written on the inner closure and not left to be inferred.
		// Every parameter in this chain is already `@Sendable` — this one, `drain`'s
		// below, and `RuntimeCommand.run`'s above it — but the annotation does not
		// reach through `Optional.map`: the transform's result type is inferred
		// bare, so the closure literal was built non-Sendable and then converted,
		// which is a data-race warning today and a Swift 6 error later. Saying it
		// here costs no caller anything.
		let pieces: (@Sendable (Data) -> Void)? = onOutput.map { report in
			{ @Sendable chunk in report(String(decoding: chunk, as: UTF8.self)) }
		}
		let data = drain(process, out: out, err: err, input: input, stdin: stdin, onOutput: pieces)
		return (
			String(decoding: data.stdout, as: UTF8.self),
			String(decoding: data.stderr, as: UTF8.self)
		)
	}

	/// Reads a descriptor to the end, and can be told to give up.
	///
	/// POSIX rather than `readDataToEndOfFile()`, and the reason is a crash
	/// report. Ending a read by closing the descriptor under it — which is what
	/// the timeout above did, deliberately and with a comment explaining why —
	/// makes Foundation *raise* `NSFileHandleOperationException`. An
	/// Objective-C exception cannot be caught in Swift, so it went straight to
	/// the uncaught handler and aborted the app, from a path written to make it
	/// more robust. `read(2)` returns -1 and sets `errno` instead, and here
	/// nothing has to be closed at all.
	///
	/// The tick is what makes "give up" possible: a blocking read cannot be
	/// interrupted without doing something to the descriptor, which is the
	/// thing that was wrong. Polling costs nothing while output is flowing,
	/// since `poll` returns the moment there is anything to read.
	private static func readToEnd(
		_ descriptor: Int32, until stop: Flag, onData: (@Sendable (Data) -> Void)? = nil
	) -> Data {
		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 64 * 1024)

		while !stop.isSet {
			var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
			let ready = withUnsafeMutablePointer(to: &watched) { poll($0, 1, 100) }
			if ready < 0 {
				if errno == EINTR { continue }
				break
			}
			// Nothing yet — round again, and look at `stop` on the way past.
			if ready == 0 { continue }
			// The descriptor is gone from under us. Not expected any more, but
			// it is one comparison to be sure of never spinning on it.
			if watched.revents & Int16(POLLNVAL) != 0 { break }

			let count = buffer.withUnsafeMutableBytes { raw in
				Darwin.read(descriptor, raw.baseAddress, raw.count)
			}
			// POLLHUP arrives with the last of the data rather than instead of
			// it, so end of file is a read of zero, not a flag.
			if count > 0 {
				let chunk = Data(buffer[0 ..< count])
				data.append(chunk)
				onData?(chunk)
				continue
			}
			if count == 0 { break }
			if errno == EINTR || errno == EAGAIN { continue }
			break
		}
		return data
	}

	/// One bool, set by whoever gave up and read by the threads still reading.
	/// Runs a pipe reader on a thread of its own, tied to `group`.
	///
	/// `Thread` rather than a queue because a queue is a promise to run the work
	/// eventually and this work has a deadline: see the comment in `drain`.
	private static func startReader(group: DispatchGroup, _ work: @escaping @Sendable () -> Void) {
		group.enter()
		let thread = Thread {
			work()
			group.leave()
		}
		// Smaller than the 512 KB default: these read into a buffer that is
		// already allocated and call one closure. Thousands of git commands over
		// a session should not each reserve half a megabyte of stack.
		thread.stackSize = 128 * 1024
		thread.name = "abydos.pipe-reader"
		thread.start()
	}

	private final class Flag: @unchecked Sendable {
		private let lock = NSLock()
		private var value = false

		func set() {
			lock.lock()
			value = true
			lock.unlock()
		}

		var isSet: Bool {
			lock.lock()
			defer { lock.unlock() }
			return value
		}
	}

	/// Somewhere for the background read to put what it read.
	///
	/// The group's wait is the only ordering there is, and it is enough: one
	/// thread writes it, and nobody reads it until that thread has finished.
	private final class Box: @unchecked Sendable {
		var data = Data()
	}
}

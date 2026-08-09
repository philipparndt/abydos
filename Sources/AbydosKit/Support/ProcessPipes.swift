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
	public static func drain(
		_ process: Process,
		out: Pipe,
		err: Pipe,
		input: Data? = nil,
		stdin: Pipe? = nil
	) -> (stdout: Data, stderr: Data) {
		let group = DispatchGroup()
		let output = Box(), errors = Box()
		let stop = Flag()

		// Taken before anything can be closed: asking a closed `FileHandle` for
		// its descriptor is its own kind of trouble.
		let outDescriptor = out.fileHandleForReading.fileDescriptor
		let errDescriptor = err.fileHandleForReading.fileDescriptor

		DispatchQueue.global(qos: .userInitiated).async(group: group) {
			output.data = readToEnd(outDescriptor, until: stop)
		}
		DispatchQueue.global(qos: .userInitiated).async(group: group) {
			errors.data = readToEnd(errDescriptor, until: stop)
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
		let drained = DispatchSemaphore(value: 0)
		DispatchQueue.global(qos: .userInitiated).async {
			group.wait()
			drained.signal()
		}
		if drained.wait(timeout: .now() + .seconds(2)) == .timedOut {
			stop.set()
			_ = drained.wait(timeout: .now() + .seconds(2))
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
		DispatchQueue.global(qos: .userInitiated).async(group: group) {
			output.data = readToEnd(descriptor, until: stop)
		}
		process.waitUntilExit()
		let drained = DispatchSemaphore(value: 0)
		DispatchQueue.global(qos: .userInitiated).async {
			group.wait()
			drained.signal()
		}
		if drained.wait(timeout: .now() + .seconds(2)) == .timedOut {
			stop.set()
			_ = drained.wait(timeout: .now() + .seconds(2))
		}
		return output.data
	}

	/// The same, decoded, which is what every caller here wants.
	public static func drainText(
		_ process: Process,
		out: Pipe,
		err: Pipe,
		input: Data? = nil,
		stdin: Pipe? = nil
	) -> (stdout: String, stderr: String) {
		let data = drain(process, out: out, err: err, input: input, stdin: stdin)
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
	private static func readToEnd(_ descriptor: Int32, until stop: Flag) -> Data {
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
				data.append(contentsOf: buffer[0 ..< count])
				continue
			}
			if count == 0 { break }
			if errno == EINTR || errno == EAGAIN { continue }
			break
		}
		return data
	}

	/// One bool, set by whoever gave up and read by the threads still reading.
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

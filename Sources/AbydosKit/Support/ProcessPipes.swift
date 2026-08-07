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

		DispatchQueue.global(qos: .userInitiated).async(group: group) {
			output.data = out.fileHandleForReading.readDataToEndOfFile()
		}
		DispatchQueue.global(qos: .userInitiated).async(group: group) {
			errors.data = err.fileHandleForReading.readDataToEndOfFile()
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
		// draining what it left, and then take the descriptors away from them.
		// A truncated capture from a program that has already exited beats
		// waiting for a stranger to quit.
		process.waitUntilExit()
		let drained = DispatchSemaphore(value: 0)
		DispatchQueue.global(qos: .userInitiated).async {
			group.wait()
			drained.signal()
		}
		if drained.wait(timeout: .now() + .seconds(2)) == .timedOut {
			try? out.fileHandleForReading.close()
			try? err.fileHandleForReading.close()
			_ = drained.wait(timeout: .now() + .seconds(2))
		}
		return (output.data, errors.data)
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

	/// Somewhere for the background read to put what it read.
	///
	/// The group's wait is the only ordering there is, and it is enough: one
	/// thread writes it, and nobody reads it until that thread has finished.
	private final class Box: @unchecked Sendable {
		var data = Data()
	}
}

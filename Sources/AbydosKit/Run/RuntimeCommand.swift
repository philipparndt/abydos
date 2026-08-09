import Foundation

/// Asking a container runtime a question, with a deadline and nothing left
/// behind.
///
/// Every command sent to a runtime goes through here, and the deadline is the
/// whole point: a runtime whose service is down accepts the command and then
/// waits for something that is not coming, and a process waiting on that
/// outlives whatever asked for it. That is the shape of the bug this file is
/// part of fixing — asking a wedged runtime a question is itself a way of
/// leaving something behind.
enum RuntimeCommand {
	struct Result {
		/// Both streams together, since the runtimes disagree about which one a
		/// failure goes to.
		let output: String
		let exitCode: Int32
		/// Whether the deadline is what ended it.
		let timedOut: Bool

		var succeeded: Bool { exitCode == 0 && !timedOut }
	}

	/// Runs a command with a deadline, and does not leave it behind.
	///
	/// Terminated first and killed after, because a program stuck in a system
	/// call does not always get round to noticing the polite one.
	static func run(
		_ command: (executable: String, arguments: [String]),
		deadline: TimeInterval
	) -> Result {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: command.executable)
		process.arguments = command.arguments
		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		// Nothing on standard input, and said in the one way that means it.
		//
		// A `Pipe()` here reads as "no input" and is the opposite: this process
		// holds the write end, so the child sees an input that never ends. Apple's
		// `container` then waits for it — `container images inspect` with a pipe
		// held open never answers at all — and every caller waits with it.
		process.standardInput = FileHandle.nullDevice
		do { try process.run() } catch {
			return Result(output: error.localizedDescription, exitCode: -1, timedOut: false)
		}

		// Whether the deadline is what ended it, recorded where both threads can
		// see it: `terminationReason` cannot tell a program this killed from one
		// that died of its own accord.
		let expired = Expired()
		let watchdog = DispatchWorkItem {
			guard process.isRunning else { return }
			expired.record()
			process.terminate()
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
				if process.isRunning { kill(process.processIdentifier, SIGKILL) }
			}
		}
		DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: watchdog)

		let captured = ProcessPipes.drainText(process, out: out, err: err)
		watchdog.cancel()
		return Result(
			output: captured.stderr + captured.stdout,
			exitCode: process.terminationStatus,
			timedOut: expired.happened
		)
	}

	/// One bool, written by the deadline and read by whoever was waiting.
	private final class Expired: @unchecked Sendable {
		private let lock = NSLock()
		private var value = false

		func record() {
			lock.lock()
			value = true
			lock.unlock()
		}

		var happened: Bool {
			lock.lock()
			defer { lock.unlock() }
			return value
		}
	}
}

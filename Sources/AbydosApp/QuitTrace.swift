import AppKit
import AbydosKit

/// How long a quit took, step by step, in `~/Library/Logs/Abydos/quit.log` —
/// and, for one that is slow, a sample of the process while it was being slow.
///
/// Reported 2026-09-17: "abydos does not exit very fast at least when working
/// with music … it was some longer sessions. But I noticed it multiple times",
/// and then: "if we cant find a trace we need to improve the logging". It could
/// not be found. Driven, a quit took 0.35 s with a song rendered, 0.38 s with
/// one playing, 0.37 s in the middle of a render, and 0.36 s after twenty-one
/// renders under a playing song — so whatever makes it slow is in a session
/// nobody has reproduced, and the next one has to say for itself what it was.
///
/// Two things are written. Every quit leaves one line with the time each step
/// took, so a slow step has a name. And a quit still going after
/// `slowAfter` has `/usr/bin/sample` pointed at it from another thread, which
/// writes where every thread was — the main thread's stack is the answer, and
/// it cannot be asked for from inside once it is stuck.
///
/// A class with a lock rather than an actor: it is written from the main thread
/// and read from the one watching it, at the one moment the app cannot wait.
final class QuitTrace: @unchecked Sendable {
	static let shared = QuitTrace()

	/// How long a quit may take before it is sampled. Longer than any quit that
	/// was measured, by four times.
	static let slowAfter: TimeInterval = 1.5

	private let lock = NSLock()
	private var began: Date?
	private var last = Date()
	private var steps: [String] = []
	private var finished = false

	/// The quit has been asked for. Starts the clock, and the watch for a slow
	/// one.
	func begin(_ context: String) {
		lock.withLock {
			guard began == nil else { return }
			began = Date()
			last = Date()
			steps = [context]
		}
		let pid = ProcessInfo.processInfo.processIdentifier
		Thread.detachNewThread { [self] in
			Thread.sleep(forTimeInterval: Self.slowAfter)
			// Still here to run this line at all is the whole test: a process
			// that has gone takes this thread with it. Whether the app's own
			// steps were over by now says which side of `exit` the wait is on.
			let (done, soFar) = lock.withLock { (finished, steps.joined(separator: ", ")) }
			let file = DiagnosticLog.directory().appendingPathComponent("quit-slow-\(pid).sample.txt")
			DiagnosticLog.write(
				"slow: still alive \(Self.slowAfter) s after the quit was asked for, "
					+ (done ? "with the app's own steps over" : "inside the app's own steps")
					+ " [\(soFar)] — sampling into \(file.path)", to: "quit"
			)
			let sample = Process()
			sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
			sample.arguments = ["\(pid)", "3", "-file", file.path]
			sample.standardOutput = FileHandle.nullDevice
			sample.standardError = FileHandle.nullDevice
			try? sample.run()
		}
	}

	/// A step of the quit is over: what it was, and how long it took.
	func step(_ name: String) {
		lock.withLock {
			guard began != nil else { return }
			let now = Date()
			steps.append(String(format: "%@ %.0f ms", name, now.timeIntervalSince(last) * 1000))
			last = now
		}
	}

	/// The quit is over as far as this app's own code goes. Written whatever it
	/// took: a fast quit is the baseline a slow one is read against.
	func end() {
		let line: String? = lock.withLock {
			guard let began, !finished else { return nil }
			finished = true
			let total = Date().timeIntervalSince(began)
			return String(format: "quit %.0f ms [%@]", total * 1000, steps.joined(separator: ", "))
		}
		if let line { DiagnosticLog.write(line, to: "quit") }
	}
}

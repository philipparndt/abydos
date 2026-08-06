import Foundation

/// Catches the moments the main thread stops answering.
///
/// Typing that "feels slow" is nearly always the main thread being busy with
/// something else for a few hundred milliseconds — and by the time it is
/// noticed, whatever did it has finished and left nothing behind. So this
/// pings the main queue from a thread of its own and writes down every ping
/// that came back late, with whatever the app said it was doing at the time.
///
/// The cost is one sleeping thread and ten empty blocks a second, which is why
/// it can be left on: the point is to be already running when a rare hitch
/// happens, since asking somebody to reproduce one is asking for nothing.
public enum StallWatch {
	/// How long a ping may take before it counts as a stall.
	///
	/// A frame is 8 ms at 120 Hz; a keystroke that lands three frames late is
	/// not worth waking anybody for. A fifth of a second is where a person
	/// stops believing the keyboard.
	public static let threshold: TimeInterval = 0.2

	/// One late ping.
	public struct Stall: Sendable, Equatable {
		public let at: Date
		public let duration: TimeInterval
		/// What the app said it was doing, or "idle" when nothing claimed it.
		public let activity: String

		public init(at: Date, duration: TimeInterval, activity: String) {
			self.at = at
			self.duration = duration
			self.activity = activity
		}

		/// A line for the log, and for anybody reading it later.
		public var line: String {
			let stamp = ISO8601DateFormatter().string(from: at)
			return String(format: "%@ %6.0f ms  %@", stamp, duration * 1000, activity)
		}
	}

	// MARK: - What the app is doing

	private static let lock = NSLock()
	nonisolated(unsafe) private static var current: String = "idle"
	nonisolated(unsafe) private static var stalls: [Stall] = []
	nonisolated(unsafe) private static var started = false

	/// Names the work about to run on the main thread, so a stall inside it has
	/// something to say for itself.
	///
	/// Nested marks keep the innermost name: the interesting one is what was
	/// running, not what asked for it.
	public static func mark<T>(_ activity: String, _ work: () throws -> T) rethrows -> T {
		lock.lock()
		let previous = current
		current = activity
		lock.unlock()
		defer {
			lock.lock()
			current = previous
			lock.unlock()
		}
		return try work()
	}

	/// The stalls seen so far, worst first.
	public static func worst(limit: Int = 20) -> [Stall] {
		lock.lock()
		defer { lock.unlock() }
		return Array(stalls.sorted { $0.duration > $1.duration }.prefix(limit))
	}

	public static func clear() {
		lock.lock()
		stalls = []
		lock.unlock()
	}

	// MARK: - Watching

	/// Where the stalls are written, so a hitch that happened an hour ago is
	/// still answerable.
	public static var logURL: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Logs/Abydos/stalls.log")
	}

	/// Starts pinging. Safe to call more than once; the second call does
	/// nothing.
	public static func start(interval: TimeInterval = 0.1) {
		lock.lock()
		let alreadyRunning = started
		started = true
		lock.unlock()
		guard !alreadyRunning else { return }

		let thread = Thread {
			while true {
				Thread.sleep(forTimeInterval: interval)
				let sent = Date()
				let waited = DispatchSemaphore(value: 0)
				DispatchQueue.main.async { waited.signal() }

				// Two waits, because the answer to "doing what" only exists
				// while it is still being done: by the time the ping comes back
				// the work has finished and unmarked itself. So the first wait
				// ends at the threshold and reads the activity there, with the
				// main thread still inside it.
				guard waited.wait(timeout: .now() + threshold) == .timedOut else { continue }
				let activity = activityNow()
				waited.wait()
				record(Stall(at: sent, duration: Date().timeIntervalSince(sent), activity: activity))
			}
		}
		thread.name = "ideai.stallwatch"
		// Below everything it is measuring: a watchdog that competes for the
		// CPU reports its own waiting as somebody else's stall.
		thread.qualityOfService = .utility
		thread.start()
	}

	private static func activityNow() -> String {
		lock.lock()
		defer { lock.unlock() }
		return current
	}

	/// Keeps a stall and appends it to the log.
	///
	/// Internal so the arithmetic can be tested without waiting for a real
	/// hitch to happen.
	static func record(_ stall: Stall, writing: Bool = true) {
		lock.lock()
		stalls.append(stall)
		// A day of hitches is more than anybody reads; the log has the rest.
		if stalls.count > 200 { stalls.removeFirst(stalls.count - 200) }
		lock.unlock()
		guard writing else { return }
		append(stall.line)
	}

	private static func append(_ line: String) {
		let url = logURL
		try? FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		guard let data = (line + "\n").data(using: .utf8) else { return }
		if let handle = try? FileHandle(forWritingTo: url) {
			defer { try? handle.close() }
			// Truncated rather than rotated: this is a trail to read after a
			// hitch, not a record to keep.
			if (try? handle.seekToEnd()) ?? 0 > 512 * 1024 {
				try? handle.truncate(atOffset: 0)
			}
			try? handle.write(contentsOf: data)
		} else {
			try? data.write(to: url)
		}
	}
}

extension StallWatch {
	/// What the app says it is doing right now, for the tests.
	static var activityForTesting: String { activityNow() }
}

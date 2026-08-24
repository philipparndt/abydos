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
	/// It was a fifth of a second, on the argument that a fifth of a second is
	/// where a person stops believing the keyboard. That is true and it was the
	/// wrong number, because it answers a different question: 200 ms is where a
	/// stall is worth *complaining* about, and this log is not a complaint, it
	/// is the only evidence of what holds the main queue. Typing feels bad well
	/// below it — a letter that arrives four frames after the key is a letter
	/// somebody notices — and every one of those was invisible.
	///
	/// 50 ms: three frames at 60 Hz, and comfortably above the noise of a
	/// utility-priority thread being descheduled on a busy machine. The cost is
	/// more lines in a log that already truncates itself.
	public static let threshold: TimeInterval = 0.05

	/// One late ping.
	public struct Stall: Sendable, Equatable {
		public let at: Date
		public let duration: TimeInterval
		/// What the app said it was doing, or "idle" when nothing claimed it.
		public let activity: String

		/// How much of the stall the main thread spent on a processor, 0 to 1,
		/// or `nil` when it could not be asked.
		///
		/// This is the difference between the two things `idle` used to mean,
		/// and they want opposite fixes. Near 1, the main thread was *running*
		/// the whole stall, inside work nobody has marked: there is code to find
		/// and give a name to. Near 0, it executed almost nothing, and the fix
		/// is somewhere else entirely.
		///
		/// **Near 0 is not the same as "not our fault".** It says the thread was
		/// not on a processor, which covers being descheduled by a busy machine
		/// *and* being blocked — a pipe write nobody is draining, a lock, a
		/// subprocess being waited on — and this entry's worst bug was exactly
		/// the second kind. Measured: a `--stall 800`, which is a `Thread.sleep`
		/// on the main thread, logs `cpu 0%`. So the field halves the search
		/// rather than ending it, and that is worth having: every reading in
		/// 0437 was taken without it, and two hours of a quiet session produced
		/// thirteen stalls of which every single one was `idle`.
		public let mainThreadRunning: Double?

		/// Which process wrote the line.
		///
		/// One log file, and more than one Abydos can be running against it: a
		/// second instance opened beside the first to measure something writes
		/// into the same file, in the same format, and there was nothing to tell
		/// the two apart. That cost a measurement.
		public let pid: Int32

		public init(
			at: Date,
			duration: TimeInterval,
			activity: String,
			mainThreadRunning: Double? = nil,
			pid: Int32 = ProcessInfo.processInfo.processIdentifier
		) {
			self.at = at
			self.duration = duration
			self.activity = activity
			self.mainThreadRunning = mainThreadRunning
			self.pid = pid
		}

		/// A line for the log, and for anybody reading it later.
		///
		/// The two new fields go *after* the activity rather than in front of
		/// it, so that the summarising command in 0437 — which splits on
		/// `"ms  "` and then takes the first word-pair of what follows — reads
		/// a line written before them and a line written after them the same
		/// way. A log spans a rebuild; a format that invalidates everything
		/// older than the newest change is a format that is never readable.
		public var line: String {
			let stamp = ISO8601DateFormatter().string(from: at)
			var text = String(format: "%@ %6.0f ms  %@", stamp, duration * 1000, activity)
			if let running = mainThreadRunning {
				text += String(format: "  cpu %3.0f%%", running * 100)
			}
			text += "  pid \(pid)"
			return text
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
	///
	/// **Off the main thread it does nothing but run the work.** There is one
	/// name and the watcher reads it when a *main-queue* ping is late, so a mark
	/// taken on a background queue would put its name on somebody else's stall —
	/// and the names are the whole point. The guard is what lets a mark live
	/// inside shared code like `LanguageServers.suits` or `UserShell`, which is
	/// called from both sides and is only a suspect from one of them.
	public static func mark<T>(_ activity: String, _ work: () throws -> T) rethrows -> T {
		guard Thread.isMainThread else { return try work() }
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

		// `mach_thread_self()` answers for whichever thread asks, so the main
		// thread's port has to be taken on the main thread. `start()` is called
		// from `applicationDidFinishLaunching`, so the ordinary case takes it
		// inline and the very first ping already has it; anybody calling from
		// elsewhere waits one hop and loses the `cpu` field until then.
		if Thread.isMainThread { rememberMainThread() }
		else { DispatchQueue.main.async { rememberMainThread() } }

		let thread = Thread {
			while true {
				Thread.sleep(forTimeInterval: interval)
				let sent = Date()
				let cpuBefore = mainThreadProcessorTime()
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
				let elapsed = Date().timeIntervalSince(sent)
				record(Stall(
					at: sent,
					duration: elapsed,
					activity: activity,
					mainThreadRunning: fractionRunning(from: cpuBefore, over: elapsed)
				))
			}
		}
		thread.name = "abydos.stallwatch"
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

	// MARK: - Was the main thread even running?

	/// The main thread's port, so its processor time can be read from outside it.
	///
	/// Kept for the life of the process and never deallocated on purpose:
	/// `mach_thread_self()` hands back a send right the caller owns, and giving
	/// it up would leave nothing to ask. One right, taken once.
	nonisolated(unsafe) private static var mainThreadPort: mach_port_t = mach_port_t(MACH_PORT_NULL)

	private static func rememberMainThread() {
		let port = mach_thread_self()
		lock.lock()
		mainThreadPort = port
		lock.unlock()
	}

	/// User plus system time the main thread has used since it started, or `nil`
	/// before its port has been taken or if the kernel declines to say.
	private static func mainThreadProcessorTime() -> TimeInterval? {
		lock.lock()
		let port = mainThreadPort
		lock.unlock()
		guard port != mach_port_t(MACH_PORT_NULL) else { return nil }

		var info = thread_basic_info()
		// `THREAD_BASIC_INFO_COUNT` is a macro over `sizeof`, which does not
		// come through the importer, so the same arithmetic is done here.
		var count = mach_msg_type_number_t(
			MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
		)
		let result = withUnsafeMutablePointer(to: &info) { pointer in
			pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
				thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
			}
		}
		guard result == KERN_SUCCESS else { return nil }
		return seconds(info.user_time) + seconds(info.system_time)
	}

	private static func seconds(_ time: time_value_t) -> TimeInterval {
		TimeInterval(time.seconds) + TimeInterval(time.microseconds) / 1_000_000
	}

	/// How much of a stall of `elapsed` the main thread spent on a processor.
	///
	/// Clamped to 0…1 rather than reported raw. The two readings are taken from
	/// a different thread and are not simultaneous with the stall's own
	/// endpoints, so a busy main thread can come out a hair over 1; a fraction
	/// of 103% in a log invites an explanation that does not exist.
	static func fractionRunning(from before: TimeInterval?, over elapsed: TimeInterval) -> Double? {
		guard let before, elapsed > 0, let after = mainThreadProcessorTime() else { return nil }
		return min(1, max(0, (after - before) / elapsed))
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

	/// The main thread's processor time, for the tests, which have to take its
	/// port themselves because they do not run `start()`.
	static func rememberMainThreadForTesting() { rememberMainThread() }
	static var mainThreadProcessorTimeForTesting: TimeInterval? { mainThreadProcessorTime() }
}

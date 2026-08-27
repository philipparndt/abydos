import Foundation

/// A number of bytes, in the units somebody reads.
///
/// One implementation, because two would drift on the boundary: the sessions
/// section rounds `10.0 MiB` to `10 MiB` and anything smaller keeps a decimal,
/// and a second copy written from the same description would put `9.95` where
/// this puts `10.0`.
///
/// **MiB and not MB, everywhere.** A binary-file notice once said `405,7 MB` in
/// its sentence and `387 MiB` beside it — the same number in two conventions,
/// which reads as a mistake because it is one. `ByteCountFormatter` is where
/// both came from: its `.file` style divides by 1000 and its `.memory` style
/// divides by 1024 and labels the result `MB` anyway. So neither is used, and
/// this is what a size looks like in this app.
public enum ByteSize {
	public static func said(_ bytes: Int64) -> String {
		let units = ["KiB", "MiB", "GiB"]
		guard bytes >= 1024 else { return "\(bytes) B" }
		var value = Double(bytes) / 1024
		var unit = 0
		while value >= 1024, unit < units.count - 1 { value /= 1024; unit += 1 }
		return value >= 10
			? "\(Int(value.rounded())) \(units[unit])"
			: String(format: "%.1f %@", value, units[unit])
	}

	/// The size of a file, or nil when there is nothing to measure.
	public static func ofFile(at url: URL) -> Int64? {
		let values = try? url.resourceValues(forKeys: [.fileSizeKey])
		return (values?.fileSize).map(Int64.init)
	}

	/// What a directory takes up, or nil when it cannot be measured *in time*.
	///
	/// **`du`, and with a deadline.** The number is for a sentence in a dialog —
	/// "deleting this frees 4.9 GB" — and a dialog that waits on a walk of a
	/// build directory is worse than one that does not mention the size. So the
	/// answer is whatever `du -sk` has by the deadline and nil otherwise: the
	/// sentence loses a clause, and nothing else changes.
	///
	/// `-k` because `du`'s default block size is not the same everywhere, and a
	/// number whose unit depends on the machine is not a number.
	public static func ofDirectory(
		at url: URL, within deadline: Duration = .seconds(2)
	) async -> Int64? {
		// **The process, not the task.** Cancelling a Swift task does not stop a
		// `Process` — `waitUntilExit` waits either way — so the deadline has to
		// reach the `du` itself. It is held here for the timer to kill.
		let running = KillableProcess()
		let measuring = Task.detached(priority: .userInitiated) { () -> Int64? in
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
			process.arguments = ["-sk", url.path]
			let pipe = Pipe()
			process.standardOutput = pipe
			process.standardError = FileHandle.nullDevice
			do { try process.run() } catch { return nil }
			running.hold(process)
			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			process.waitUntilExit()
			// `du` exits non-zero over a directory it could not read all of and
			// still prints a total for what it could, which is the right number
			// to show: what is there is what would be freed. A `du` killed by
			// the deadline prints nothing, and nothing parses to nil.
			let said = String(decoding: data, as: UTF8.self)
			guard let kilobytes = said.split(separator: "\t").first.flatMap({ Int64($0) })
			else { return nil }
			return kilobytes * 1024
		}
		let timing = Task {
			try? await Task.sleep(for: deadline)
			// A `du` still walking when the dialog is due is a `du` nobody is
			// waiting for any more.
			running.stop()
		}
		defer { timing.cancel() }
		return await measuring.value
	}
}

/// A `Process` two tasks share: one waiting on it, one holding the deadline.
///
/// Not `RunningProcess`, which the debug tool already has and which is a model
/// of somebody else's process rather than a handle on one of ours.
private final class KillableProcess: @unchecked Sendable {
	private let lock = NSLock()
	private var process: Process?
	private var stopped = false

	/// Killed on the spot if the deadline went by while it was starting.
	func hold(_ process: Process) {
		lock.lock()
		let alreadyStopped = stopped
		self.process = process
		lock.unlock()
		if alreadyStopped { process.terminate() }
	}

	func stop() {
		lock.lock()
		stopped = true
		let held = process
		lock.unlock()
		held?.terminate()
	}
}

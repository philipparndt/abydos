import Darwin
import Foundation

/// When each part of starting up finished, counted from the moment the kernel
/// made the process.
///
/// 0428 asks for two numbers that sound like one: time to a window, and time to
/// something usable. Nothing outside the process can tell them apart. A
/// stopwatch on `open -a` stops when the app is *launched*, `ps` can say the
/// process exists, and a screenshot taken at a fixed delay says only that the
/// delay was long enough — none of them can say that the window was on screen at
/// 900 ms and that the tree in it was still empty at 3 seconds, which on the
/// Platform corpus is the difference somebody actually feels.
///
/// **Counted from `p_starttime`, not from the first line of `main`.** A static
/// initialiser runs after dyld has mapped the app and every framework it links,
/// and on a cold launch that is a large part of the wait. Asking the kernel when
/// the process was made puts that time inside the number, where the person
/// waiting for the window experiences it.
///
/// The marks are free when nobody is asking: one `Date()` and a dictionary
/// insert, on events that happen once per project open.
public enum LaunchClock {
	/// When the kernel made this process.
	///
	/// `KERN_PROC_PID` gives a `kinfo_proc` whose `p_starttime` is a wall-clock
	/// `timeval`. It is not the monotonic clock, so a step of the system clock
	/// during launch would show up here — which has never happened and would be
	/// visible as a negative elapsed time rather than as a plausible wrong
	/// answer.
	public static let processStart: Date = {
		var info = kinfo_proc()
		var size = MemoryLayout<kinfo_proc>.stride
		var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
		guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return Date() }
		let started = info.kp_proc.p_un.__p_starttime
		return Date(timeIntervalSince1970:
			Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
	}()

	public struct Mark: Sendable {
		public let name: String
		/// Seconds since the process was made.
		public let at: TimeInterval
	}

	private static let lock = NSLock()
	nonisolated(unsafe) private static var marks: [Mark] = []

	/// Writes down that something finished, the first time it finishes.
	///
	/// First only, deliberately. The tree is re-read and `git status` re-applied
	/// on every filesystem event for the rest of the session, and what this is
	/// measuring is the launch: a mark that moved every time the watcher fired
	/// would report how long ago the last build was.
	public static func mark(_ name: String) {
		lock.lock()
		defer { lock.unlock() }
		guard !marks.contains(where: { $0.name == name }) else { return }
		marks.append(Mark(name: name, at: Date().timeIntervalSince(processStart)))
	}

	public static var recorded: [Mark] {
		lock.lock()
		defer { lock.unlock() }
		return marks
	}

	/// How much processor this process has burned, both threads and children.
	///
	/// Wall clock is what somebody feels and processor time is what changes when
	/// the code does — 0416's distinction, and the reason both are printed. The
	/// children's total is what makes the honest answer to "how much of this is
	/// ours" possible at all: it does *not* include a language server, which is
	/// started as a sibling rather than waited on, so a large `self` beside a
	/// small `children` says the cost is in this process.
	public static func processorSeconds() -> (own: Double, children: Double) {
		func seconds(_ who: Int32) -> Double {
			var usage = rusage()
			guard getrusage(who, &usage) == 0 else { return 0 }
			func total(_ time: timeval) -> Double {
				Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
			}
			return total(usage.ru_utime) + total(usage.ru_stime)
		}
		return (seconds(RUSAGE_SELF), seconds(RUSAGE_CHILDREN))
	}

	/// Resident size in bytes, as the kernel sees it.
	///
	/// `phys_footprint` rather than `resident_size`: Activity Monitor's "Memory"
	/// column is the footprint, and a number that disagrees with the one the
	/// person reading it can see on screen is a number they will not believe.
	public static func residentBytes() -> UInt64 {
		var info = task_vm_info_data_t()
		var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
		let result = withUnsafeMutablePointer(to: &info) {
			$0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
				task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
			}
		}
		return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
	}

	/// The one-minute load average per core, so every duration this prints can
	/// be read against what the machine was doing while it was taken.
	///
	/// The same argument as `MachineLoad` in the test suite, which cannot be
	/// used here: it is a test helper and this runs in the app. A duration
	/// written down without the load beside it cannot be argued with afterwards.
	public static var loadSaid: String {
		var averages = [Double](repeating: 0, count: 3)
		guard getloadavg(&averages, 3) == 3 else { return "load unknown" }
		let cores = ProcessInfo.processInfo.activeProcessorCount
		return String(format: "load %.1f over %d cores (%.1f per core)",
			averages[0], cores, averages[0] / Double(cores))
	}

	/// Every mark, one per line, for a harness to read off the app's output.
	public static func report() -> [String] {
		let processor = processorSeconds()
		var lines = recorded.map { String(format: "OPEN %-24s %8.0f ms", ($0.name as NSString).utf8String!, $0.at * 1000) }
		lines.append(String(format: "OPEN %-24s %8.0f ms cpu", ("processor (ours)" as NSString).utf8String!, processor.own * 1000))
		lines.append(String(format: "OPEN %-24s %8.0f ms cpu", ("processor (children)" as NSString).utf8String!, processor.children * 1000))
		lines.append(String(format: "OPEN %-24s %8.1f MB", ("memory (ours)" as NSString).utf8String!, Double(residentBytes()) / 1_048_576))
		lines.append("OPEN " + loadSaid)
		return lines
	}
}

import Darwin
import Foundation

/// What the machine was doing while a test was being timed.
///
/// Every duration this suite measures is a wall clock over work the operating
/// system schedules, and these tests run beside builds, other test runs, and
/// whatever else is open. A duration written down without the load beside it
/// cannot be argued with afterwards, which is most of what 0435 cost: deadline
/// assertions in seven different suites failing at load averages between 27 and
/// 386, and five separate people having to prove by hand that the red was not
/// theirs.
///
/// So this is not a way of excusing a failure. It is a way of making the
/// evidence for or against one part of the failure itself.
enum MachineLoad {
	/// The one-minute load average, or nil on a kernel that will not say.
	static var oneMinute: Double? {
		var averages = [Double](repeating: 0, count: 3)
		guard getloadavg(&averages, 3) == 3 else { return nil }
		return averages[0]
	}

	static var cores: Int { ProcessInfo.processInfo.activeProcessorCount }

	/// Runnable work per core — the number that means the same thing on a ten-core
	/// machine as on a hundred-core one.
	///
	/// One is a machine with exactly enough to do. This suite has been seen at
	/// thirty-eight.
	static var perCore: Double? { oneMinute.map { $0 / Double(cores) } }

	/// A phrase to put beside a duration, in a `print` or in a failure.
	static var said: String {
		guard let oneMinute, let perCore else { return "load unknown" }
		return String(format: "load %.1f over %d cores (%.1f per core)", oneMinute, cores, perCore)
	}

	/// Above this, a wall clock is measuring the machine rather than the code.
	///
	/// Four runnable threads per core. Chosen from what was seen rather than
	/// from theory, and the two ends are a long way apart: a normal `make test`
	/// on this machine sits between one and three per core and its live tests
	/// pass, while the runs that produced 0435's reds were at 3 to 38. Nothing
	/// interesting lives at exactly four, which is the only property a threshold
	/// used this way needs.
	static let busy = 4.0

	/// Whether a timing measurement taken now is worth believing.
	///
	/// **This is deliberately not used to skip assertions about behaviour.** A
	/// test that says "the picture is the same bytes" or "the deadline is what
	/// ended it" is true at any load and stays. It is only for the assertions
	/// whose subject is a *duration*, where a loaded machine makes the test
	/// measure something other than what it names.
	static var canBeTimed: Bool { (perCore ?? 0) < busy }
}

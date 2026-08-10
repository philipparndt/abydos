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

	/// Runnable work per core — the number that means the same thing on a
	/// ten-core machine as on a hundred-core one.
	///
	/// One is a machine with exactly enough to do. Measured on this one while
	/// 0435 was being worked out: 2.5 with nothing else happening, 5 during a
	/// plain `make test`, 14 with a suite and forty spinners, and 38.6 on the
	/// run that produced the reds this item is about.
	static var perCore: Double? { oneMinute.map { $0 / Double(cores) } }

	/// A phrase to put beside a duration, in a `print` or in a failure.
	static var said: String {
		guard let oneMinute, let perCore else { return "load unknown" }
		return String(format: "load %.1f over %d cores (%.1f per core)", oneMinute, cores, perCore)
	}

	/// Above this, a stopwatch is measuring the machine rather than the code.
	///
	/// Four runnable threads per core, chosen from what was measured on both
	/// sides rather than from theory. A `make test` whose live tests all pass
	/// sat between 2.5 and 5 per core; the runs that produced 0435's reds were
	/// between 5 and 38.6. Four is inside that gap, and being inside the gap is
	/// the only property a threshold used this way needs.
	static let busy = 4.0

	/// Whether an upper bound on a duration measured now is worth believing.
	///
	/// **Only for upper bounds on durations.** A test that says "the picture is
	/// the same bytes", "the deadline rather than the program is what ended it",
	/// or "the server knows the document" is true at any load and is asserted at
	/// any load. It is only the assertions whose subject is *how long something
	/// took* that stop being about the code when the machine has nothing left to
	/// give, and those are the ones 0435 is made of.
	///
	/// Two things this does not do, and neither is fixed here:
	///
	///  * The load average is a one-minute exponentially decayed figure, so it
	///    lags. A burst that begins and ends inside a short test is invisible to
	///    it, and a red caused by that burst still lands.
	///  * The same lag runs the other way: for about a minute after a build
	///    finishes the machine reads as loaded while it is not, and a real
	///    regression in that window would be skipped rather than caught.
	///
	/// What it does buy is that the load is printed beside every timing
	/// measurement whether the bound is asserted or not, so the next person
	/// reading the log has the number instead of having to re-run the suite to
	/// get it.
	static var canBeTimed: Bool { (perCore ?? 0) < busy }
}

/// How long a test waits for something to happen, said once.
///
/// Seven suites had seven numbers — 1, 3, 10, 20, 30, 60, 90 seconds — each
/// chosen by somebody who had just watched theirs fail and each meaning the
/// same thing: long enough that this is not a real wait. `DevContainerLiveTests`
/// records two agents fixing one race on the same day, one settling on ninety
/// seconds and the other on thirty. That is the state 0435 describes.
///
/// **A wait's timeout is a hang detector, not an assertion.** Nothing is being
/// claimed by it: the test is waiting for something it expects to happen, and
/// the number only exists so that a test which will never finish fails instead
/// of hanging. That makes generosity free — a wait that ends in one second on a
/// quiet machine costs nothing for being allowed a hundred — and it is why
/// these are so much larger than the numbers they replace.
///
/// The ceiling is not arbitrary either. `make test` runs under
/// `Scripts/run-tests.sh` with a `TEST_TIMEOUT` of 300 seconds for the whole
/// run, so one stuck test may not be allowed to eat all of it: at two minutes,
/// a hang still leaves the runner time to report which test was running.
enum Patience {
	/// For something this machine has to do: a process to start, a pty to echo,
	/// a language server to answer.
	static let seconds: TimeInterval = 120

	/// For something a container runtime has to do.
	///
	/// The same reasoning and a larger number, because the phase this covers is
	/// the one measured to scale worst with load. `docker run -d` for the
	/// PlantUML image took 0.30 s at 2.5 runnable per core and 16.0 s at 15.8,
	/// while every other phase of the same start — `docker port`, and the JVM
	/// answering its first request — stayed within a factor of four across the
	/// whole range. Three minutes is roughly five times the worst measured here.
	static let forAContainer: TimeInterval = 180
}

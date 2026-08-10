import Foundation
import Testing
@testable import AbydosKit

/// Writing down the moments the main thread stopped answering.
@Suite(.serialized)
struct StallWatchTests {
	@Test func aStallSaysWhenHowLongAndDoingWhat() {
		let stall = StallWatch.Stall(
			at: Date(timeIntervalSince1970: 1_750_000_000),
			duration: 0.412,
			activity: "terminal parse"
		)
		#expect(stall.line.contains("412 ms"))
		#expect(stall.line.contains("ms  terminal parse"))
		#expect(stall.line.hasPrefix("2025-"), "an absolute time, not \"a moment ago\"")
	}

	/// `idle` used to mean two opposite things — the main thread running inside
	/// work nobody marked, and the main thread not scheduled at all — and every
	/// reading taken for 0437 had to guess which.
	@Test func aStallSaysHowMuchOfItTheMainThreadSpentRunning() {
		let busy = StallWatch.Stall(
			at: Date(timeIntervalSince1970: 1_750_000_000),
			duration: 0.412,
			activity: "idle",
			mainThreadRunning: 0.93
		)
		#expect(busy.line.contains("cpu  93%"))

		// Not asked is not zero. A line with no answer says nothing rather than
		// claiming the main thread was asleep.
		let unknown = StallWatch.Stall(
			at: Date(timeIntervalSince1970: 1_750_000_000),
			duration: 0.412,
			activity: "idle"
		)
		#expect(!unknown.line.contains("cpu"))
	}

	/// One log file, and more than one Abydos can be writing into it — which is
	/// how an afternoon of measuring for 0437 was lost.
	@Test func aStallSaysWhichProcessWroteIt() {
		let stall = StallWatch.Stall(
			at: Date(timeIntervalSince1970: 1_750_000_000),
			duration: 0.412,
			activity: "idle",
			pid: 4242
		)
		#expect(stall.line.hasSuffix("pid 4242"))
	}

	/// A log outlives the build that wrote it, so the fields added later go on
	/// the end: the command that summarises the log splits on `"ms  "` and then
	/// takes what is in front of the next double space, and must get the same
	/// answer from a line written before those fields existed and one written
	/// after.
	@Test func theActivityIsStillTheFirstThingAfterTheDuration() {
		func activity(in line: String) -> String? {
			guard let tail = line.components(separatedBy: "ms  ").last else { return nil }
			return tail.components(separatedBy: "  ").first
		}
		let old = "2026-08-10T15:15:52Z     96 ms  navigator watcher"
		let new = StallWatch.Stall(
			at: Date(timeIntervalSince1970: 1_750_000_000),
			duration: 0.096,
			activity: "navigator watcher",
			mainThreadRunning: 0.07,
			pid: 4242
		).line
		#expect(activity(in: old) == "navigator watcher")
		#expect(activity(in: new) == "navigator watcher")
	}

	/// The fraction is a reading of the main thread's own clock, taken from
	/// another thread, so it has to survive both ends of its own arithmetic.
	@MainActor @Test func theFractionIsClampedAndAbsentWhenItCannotBeAsked() {
		StallWatch.rememberMainThreadForTesting()
		#expect(
			StallWatch.fractionRunning(from: nil, over: 1) == nil,
			"nothing to compare against is unknown, not zero"
		)
		// A main thread that has been up for minutes, measured over a stall of
		// one millisecond, is the arithmetic's problem and not a discovery. It
		// reads as "running", not as four million per cent.
		#expect(StallWatch.fractionRunning(from: 0, over: 0.001) == 1)
	}

	/// The whole mechanism rests on this: that the number the kernel gives for
	/// the main thread moves when the main thread works. Asserted as a
	/// direction rather than a rate, so a loaded machine cannot make it fail.
	@MainActor @Test func theMainThreadsProcessorTimeMovesWhenItWorks() throws {
		StallWatch.rememberMainThreadForTesting()
		let before = try #require(StallWatch.mainThreadProcessorTimeForTesting)
		var total = 0.0
		for step in 1...2_000_000 { total += Double(step).squareRoot() }
		#expect(total > 0, "and the compiler may not throw the loop away")
		let after = try #require(StallWatch.mainThreadProcessorTimeForTesting)
		#expect(after > before)
	}

	/// The worst hitch is the one worth reading about, not the latest.
	@Test func theWorstOnesComeFirst() {
		StallWatch.clear()
		for (index, seconds) in [0.3, 1.2, 0.5].enumerated() {
			StallWatch.record(
				StallWatch.Stall(
					at: Date(timeIntervalSince1970: 1_750_000_000 + Double(index)),
					duration: seconds,
					activity: "work \(index)"
				),
				writing: false
			)
		}
		#expect(StallWatch.worst().map(\.activity) == ["work 1", "work 2", "work 0"])
		StallWatch.clear()
		#expect(StallWatch.worst().isEmpty)
	}

	/// What the app was doing is the whole point, and the innermost answer is
	/// the useful one: "parsing terminal output", not "handling a timer".
	@MainActor @Test func theInnermostMarkWins() {
		StallWatch.clear()
		var seen: [String] = []
		StallWatch.mark("outer") {
			seen.append(StallWatch.activityForTesting)
			StallWatch.mark("inner") { seen.append(StallWatch.activityForTesting) }
			seen.append(StallWatch.activityForTesting)
		}
		seen.append(StallWatch.activityForTesting)
		#expect(seen == ["outer", "inner", "outer", "idle"])
	}

	/// A mark taken anywhere else must not name the main thread's stall.
	///
	/// There is one name, read when a *main-queue* ping is late, so a mark from
	/// a background queue would hang its label on whatever the main thread
	/// happened to be doing at the time — which is worse than "idle", because
	/// "idle" at least reads as unknown.
	@MainActor @Test func aMarkTakenOffTheMainThreadClaimsNothing() async {
		StallWatch.clear()
		let queue = DispatchQueue(label: "stallwatch.test")
		await withCheckedContinuation { continuation in
			queue.async {
				StallWatch.mark("somebody else's work") {
					continuation.resume()
				}
			}
		}
		#expect(StallWatch.activityForTesting == "idle")
	}

	@MainActor @Test func aMarkHandsBackWhatTheWorkReturned() {
		#expect(StallWatch.mark("counting") { 6 * 7 } == 42)
		// And off the main thread too, where it names nothing but still runs.
		let queue = DispatchQueue(label: "stallwatch.test.result")
		#expect(queue.sync { StallWatch.mark("counting") { 6 * 7 } } == 42)
	}

	/// A ping that came back in time is not news; only late ones are kept —
	/// and "in time" is a frame or two, not a fifth of a second. See the
	/// threshold's own note for why it came down.
	@Test func onlyLatePingsCount() {
		#expect(StallWatch.threshold >= 0.03, "a single frame late is not a stall")
		#expect(StallWatch.threshold <= 0.1, "typing already feels bad well under 200 ms")
	}
}

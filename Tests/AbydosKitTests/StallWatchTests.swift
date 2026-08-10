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
		#expect(stall.line.hasSuffix("terminal parse"))
		#expect(stall.line.hasPrefix("2025-"), "an absolute time, not \"a moment ago\"")
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

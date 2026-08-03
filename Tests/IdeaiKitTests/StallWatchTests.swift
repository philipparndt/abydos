import Foundation
import Testing
@testable import IdeaiKit

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
	@Test func theInnermostMarkWins() {
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

	@Test func aMarkHandsBackWhatTheWorkReturned() {
		#expect(StallWatch.mark("counting") { 6 * 7 } == 42)
	}

	/// A ping that came back in time is not news; only late ones are kept.
	@Test func onlyLatePingsCount() {
		#expect(StallWatch.threshold >= 0.1, "a frame late is not a stall")
		#expect(StallWatch.threshold <= 0.3, "a fifth of a second is already felt")
	}
}

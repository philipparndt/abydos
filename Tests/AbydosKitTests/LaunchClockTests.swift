import Testing
import Foundation
@testable import AbydosKit

/// The clock 0428 takes its two launch numbers from.
struct LaunchClockTests {
	@Test func theProcessStartedBeforeThisTestRan() {
		let since = Date().timeIntervalSince(LaunchClock.processStart)
		#expect(since > 0, "the process cannot have started in the future")
		// A day, not a second: the suite is minutes and a `swift test` left
		// running while somebody works on something else is longer. The claim
		// is that this is the process's own start rather than, say, the epoch.
		#expect(since < 86_400)
	}

	@Test func aMarkKeepsTheFirstTimeItWasReached() throws {
		let name = "a mark that only this test uses"
		LaunchClock.mark(name)
		let first = try #require(LaunchClock.recorded.first { $0.name == name })
		Thread.sleep(forTimeInterval: 0.05)
		LaunchClock.mark(name)
		let again = try #require(LaunchClock.recorded.first { $0.name == name })
		#expect(first.at == again.at, "the tree is re-read all session; the mark is about the launch")
		#expect(LaunchClock.recorded.filter { $0.name == name }.count == 1)
	}

	@Test func theReportSaysWhatTheMachineWasDoing() {
		let report = LaunchClock.report().joined(separator: "\n")
		#expect(report.contains("load "), "a duration with no load beside it cannot be argued with")
		#expect(report.contains("memory (ours)"))
		#expect(report.contains("ms cpu"), "wall clock alone is a fact about the machine")
	}

	@Test func residentMemoryIsSomethingRatherThanNothing() {
		// A real number and not a plausible one: `task_info` failing returns
		// zero, and zero would read as a very light app rather than as a
		// measurement that did not happen.
		#expect(LaunchClock.residentBytes() > 1_000_000)
	}
}

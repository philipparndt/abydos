import Foundation
import Testing

/// The waiting helper itself, since everything converted away from a sleep now
/// rests on it.
struct WaitUntilTests {
	/// Asked once and no more, which is the claim — and not "returned within a
	/// tenth of a second", which is what this said and which went red inside a
	/// full `make test`. That is a wall-clock assertion in the suite, the exact
	/// bet this helper exists to remove, written three times in one afternoon by
	/// the hand removing it. The clock is not the evidence; the count is.
	@Test func somethingAlreadyTrueIsAskedOnceAndNoMore() async {
		let asked = Counter()
		await waitUntil("a condition that is already true", within: 5) {
			_ = asked.next()
			return true
		}
		#expect(asked.count == 1)
	}

	/// The claim is that it keeps asking until the answer changes, and that is
	/// asserted without anything being scheduled.
	///
	/// **It used to start a `Task` that set a flag after 30 ms**, and that went
	/// red inside a full `make test`: an unstructured task can wait a long time
	/// for the cooperative pool when 2963 tests are competing for it, so the
	/// test was really asserting that the machine was not busy — in the test for
	/// the helper written to stop tests doing exactly that. The condition now
	/// changes because it was asked, which is the only thing being claimed.
	@Test func somethingThatBecomesTrueIsWaitedFor() async {
		let asked = Counter()
		await waitUntil("the condition came true") { asked.next() >= 3 }
		#expect(asked.count >= 3, "it should have asked more than once")
	}

	/// **The half that matters.** A wait that gave up quietly would leave the
	/// assertions after it to report the symptom — which is exactly the fault
	/// being replaced, where a timing failure read as a framing bug.
	@Test func somethingThatNeverHappensFailsSayingSo() async {
		await withKnownIssue("the wait is expected to record a failure") {
			await waitUntil("the thing that never happens", within: 0.05) { false }
		}
	}

	/// And it comes back rather than hanging, which is the claim worth making —
	/// a hang in a parallel suite costs the whole run.
	///
	/// **Without a wall-clock bound on it**, which this test had and which went
	/// red inside a full `make test`: a hundred-millisecond wait against a
	/// one-second assertion is exactly the bet the change that introduced this
	/// helper is about, written by the same hand on the same day. That it
	/// returns at all is what the test being finished demonstrates; how long it
	/// took is a measurement, and a measurement belongs to `make timing`.
	@Test func aFailedWaitComesBackRatherThanHanging() async {
		await withKnownIssue {
			await waitUntil("nothing", within: 0.1) { false }
		}
	}

	/// Counts how many times it was asked, and is true from the third.
	private final class Counter: @unchecked Sendable {
		private let lock = NSLock()
		private var value = 0
		var count: Int { lock.lock(); defer { lock.unlock() }; return value }
		func next() -> Int { lock.lock(); value += 1; defer { lock.unlock() }; return value }
	}
}

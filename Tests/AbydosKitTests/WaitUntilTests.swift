import Foundation
import Testing

/// The waiting helper itself, since everything converted away from a sleep now
/// rests on it.
struct WaitUntilTests {
	@Test func somethingAlreadyTrueReturnsAtOnce() async {
		let started = Date()
		await waitUntil("a condition that is already true", within: 5) { true }
		#expect(Date().timeIntervalSince(started) < 0.1)
	}

	@Test func somethingThatBecomesTrueIsWaitedFor() async {
		let flag = Flag()
		Task {
			try? await Task.sleep(nanoseconds: 30_000_000)
			flag.set()
		}

		await waitUntil("the flag was set") { flag.isSet }
		#expect(flag.isSet)
	}

	/// **The half that matters.** A wait that gave up quietly would leave the
	/// assertions after it to report the symptom — which is exactly the fault
	/// being replaced, where a timing failure read as a framing bug.
	@Test func somethingThatNeverHappensFailsSayingSo() async {
		await withKnownIssue("the wait is expected to record a failure") {
			await waitUntil("the thing that never happens", within: 0.05) { false }
		}
	}

	/// And it does not wait the whole bound before saying so — a hang in a
	/// parallel suite costs the whole run.
	@Test func aFailedWaitTakesAboutItsBoundAndNoLonger() async {
		let started = Date()
		await withKnownIssue {
			await waitUntil("nothing", within: 0.1) { false }
		}
		#expect(Date().timeIntervalSince(started) < 1)
	}

	private final class Flag: @unchecked Sendable {
		private let lock = NSLock()
		private var value = false
		var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
		func set() { lock.lock(); value = true; lock.unlock() }
	}
}

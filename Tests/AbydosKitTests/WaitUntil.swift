import Foundation
import Testing

/// Waits for something to become true, and fails saying what did not.
///
/// **A timeout as a failure bound is not the same bet as a sleep**, and 0530 is
/// what the difference costs. `try? await Task.sleep(nanoseconds: 200_000_000)`
/// asserts that two hundred milliseconds is *always* enough — on a laptop
/// running the suite in parallel with fifteen other tests, on a machine
/// building containers, on whatever CI turns out to be. When it is not, the
/// assertion after it fails, and it fails as though the thing under test were
/// wrong: `readsAMessageArrivingInPieces` reported `received.uri` as the wrong
/// string, and two people went looking at the framing code.
///
/// A wait asserts something much weaker — that five seconds is enough or
/// something is broken — and it returns the moment the thing happens. A loaded
/// machine costs it time instead of turning it red, and a genuine failure says
/// *what never happened* rather than what the value was afterwards.
///
/// Polling rather than a continuation, because what is being waited for is a
/// callback delivered on somebody else's queue, and a poll needs nothing of the
/// code under test. Two milliseconds is far below the cost of the test around
/// it and far above the cost of asking.
///
/// - Parameters:
///   - what: named in the failure, in the form "the diagnostics callback fired".
///   - within: how long before this is a failure rather than a wait.
func waitUntil(
	_ what: String,
	within seconds: TimeInterval = 5,
	sourceLocation: SourceLocation = #_sourceLocation,
	_ condition: @Sendable () -> Bool
) async {
	let deadline = Date().addingTimeInterval(seconds)
	while Date() < deadline {
		if condition() { return }
		try? await Task.sleep(nanoseconds: 2_000_000)
	}

	// **Fails rather than returning quietly.** A wait that gave up silently
	// would leave the assertions after it to report the symptom, which is the
	// fault this replaces — and a wait that hung would cost the whole parallel
	// run rather than one test.
	Issue.record(
		"waited \(Int(seconds))s and \(what) never happened",
		sourceLocation: sourceLocation
	)
}

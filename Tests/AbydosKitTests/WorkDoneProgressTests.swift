import Testing
@testable import AbydosKit

/// 0501. A Swift package whose dependencies are not built is told it has no such
/// module for the minute the server spends building them, and the rule for
/// knowing that minute is over is the work the server says it is doing.
///
/// Three claims pull against each other here: the word has to be up for the
/// whole of the first stretch, it has to survive the gaps *inside* that stretch,
/// and it has to be down for ever afterwards.
///
/// The value is a `mutating` one and `#expect` cannot call into it — the macro
/// wraps the call in a closure that takes the receiver immutably — so every
/// answer is taken into a `let` first.
struct WorkDoneProgressTests {
	/// The tokens are the ones measured coming out of the real servers, so the
	/// suite is arguing about the real shape rather than about `a` and `b`.
	private let indexing = "indexing.2F606256-652F-4715-A50D-04463DBA6251"
	private let reloading = "package-reloading.C0C36593-F525-44E4-8C0F-C4836B469564"

	@Test func aServerThatHasSaidNothingIsNotPreparing() {
		let progress = WorkDoneProgress()
		#expect(!progress.isPreparing)
	}

	@Test func aTokenThatBeginsIsPreparingUntilItEnds() {
		var progress = WorkDoneProgress()
		let begun = progress.received(kind: "begin", token: indexing)
		#expect(begun == .startedPreparing)
		#expect(progress.isPreparing)

		let ended = progress.received(kind: "end", token: indexing)
		#expect(ended == .mayHaveFinished)
		// Still preparing until the grace has passed and nothing else opened:
		// the end on its own is a question, not the answer.
		#expect(progress.isPreparing)

		let settled = progress.settleIfStillIdle()
		#expect(settled)
		#expect(!progress.isPreparing)
	}

	/// The measured cold start sent about five hundred reports between the begin
	/// and the end, and each one would otherwise redraw a bar the caret is in.
	@Test func aReportChangesNothingAtAll() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		for reported in 1 ... 500 {
			let change = progress.received(kind: "report", token: indexing)
			#expect(change == .nothing, "report \(reported) told somebody something")
		}
		#expect(progress.isPreparing)
	}

	/// Two tokens overlap on a real cold open of a Swift package —
	/// `package-reloading` ends at 14 s and `indexing` runs to 75 s — and the
	/// false diagnostic is up for the whole of it. Preparation being over when
	/// the *first* of them ends would put the word away with a minute of the wait
	/// still to go.
	@Test func preparationLastsUntilTheLastOpenTokenEnds() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		let second = progress.received(kind: "begin", token: reloading)
		#expect(second == .nothing)

		let firstEnd = progress.received(kind: "end", token: reloading)
		#expect(firstEnd == .nothing)
		#expect(progress.isPreparing)

		let lastEnd = progress.received(kind: "end", token: indexing)
		#expect(lastEnd == .mayHaveFinished)
	}

	/// **The one that was got wrong first time, and measured right.** On a cold
	/// crate `rust-analyzer` closes each step before opening the next: its set of
	/// open tokens emptied eight times during a startup that ran to 8.7 seconds,
	/// the first of them at 1.1 seconds. Treating the first empty set as the end
	/// of preparation put the word up for the first eighth of the wait and never
	/// again.
	@Test func aServerThatClosesEachStepBeforeOpeningTheNextIsStillPreparing() {
		var progress = WorkDoneProgress()
		let fetching = progress.received(kind: "begin", token: "rustAnalyzer/Fetching")
		#expect(fetching == .startedPreparing)
		let fetched = progress.received(kind: "end", token: "rustAnalyzer/Fetching")
		#expect(fetched == .mayHaveFinished)

		// The next step opens before the grace is up, so the question is answered
		// no: nothing is told, and the word never came down.
		let graph = progress.received(kind: "begin", token: "rustAnalyzer/Building CrateGraph")
		#expect(graph == .nothing)
		#expect(progress.isPreparing)
		let settledEarly = progress.settleIfStillIdle()
		#expect(!settledEarly)
		#expect(progress.isPreparing)

		let built = progress.received(kind: "end", token: "rustAnalyzer/Building CrateGraph")
		#expect(built == .mayHaveFinished)
		let settled = progress.settleIfStillIdle()
		#expect(settled)
		#expect(!progress.isPreparing)
	}

	/// The flicker this exists to prevent. A server goes on reporting progress
	/// for as long as it runs — `rust-analyzer` runs `cargo check` after every
	/// save and reports it as `rust-analyzer/flycheck/0` — and none of that is
	/// the wait 0501 is about.
	@Test func workAfterTheFirstStretchIsNotPreparation() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		progress.received(kind: "end", token: indexing)
		progress.settleIfStillIdle()

		let saved = progress.received(kind: "begin", token: "rust-analyzer/flycheck/0")
		#expect(saved == .nothing)
		#expect(!progress.isPreparing)
		let done = progress.received(kind: "end", token: "rust-analyzer/flycheck/0")
		#expect(done == .nothing)
		#expect(!progress.isPreparing)
	}

	/// Settling happens once. A second grace check — there is one scheduled per
	/// empty set, and `rust-analyzer` empties eight times — must not announce it
	/// again.
	@Test func settlingHappensOnceHoweverOftenItIsAsked() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		progress.received(kind: "end", token: indexing)
		let first = progress.settleIfStillIdle()
		let second = progress.settleIfStillIdle()
		let third = progress.settleIfStillIdle()
		#expect(first)
		#expect(!second)
		#expect(!third)
	}

	/// A report with no begin in front of it is not an implicit begin. A token
	/// opened that way could be closed by an end this never saw, and the word
	/// would stay up for the rest of the session.
	@Test func aReportWithNoBeginStartsNothing() {
		var progress = WorkDoneProgress()
		let reported = progress.received(kind: "report", token: indexing)
		#expect(reported == .nothing)
		#expect(!progress.isPreparing)
	}

	/// An `end` for something that never began closes nothing, and must not ask
	/// the caller to schedule a grace check for a server that has said nothing.
	@Test func anEndWithNoBeginAsksNothing() {
		var progress = WorkDoneProgress()
		let ended = progress.received(kind: "end", token: indexing)
		#expect(ended == .nothing)
		let settled = progress.settleIfStillIdle()
		#expect(!settled)
	}

	@Test func aServerThatStopsMidPreparationIsNoLongerPreparing() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		let stopped = progress.stopped()
		#expect(stopped)
		#expect(!progress.isPreparing)
		// And nothing it says on the way out starts it again.
		let again = progress.received(kind: "begin", token: indexing)
		#expect(again == .nothing)
	}
}

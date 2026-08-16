import Testing
@testable import AbydosKit

/// 0501. A Swift package whose dependencies are not built is told it has no such
/// module for the minute the server spends building them, and the rule for
/// knowing that minute is over is the work the server says it is doing.
///
/// The two claims that matter pull against each other: the word has to be up for
/// the whole of the first stretch, and it has to be down for ever afterwards.
///
/// The value is a `mutating` one and `#expect` cannot call into it — the macro
/// wraps the call in a closure that takes the receiver immutably — so every
/// answer is taken into a `let` first. That is also why the tests read as they
/// do rather than as one-liners.
struct WorkDoneProgressTests {
	/// The tokens are the ones measured coming out of `sourcekit-lsp` on a cold
	/// open, so the suite is arguing about the real shape rather than about `a`
	/// and `b`.
	private let indexing = "indexing.2F606256-652F-4715-A50D-04463DBA6251"
	private let reloading = "package-reloading.C0C36593-F525-44E4-8C0F-C4836B469564"

	@Test func aServerThatHasSaidNothingIsNotPreparing() {
		let progress = WorkDoneProgress()
		#expect(!progress.isPreparing)
	}

	@Test func aTokenThatBeginsIsPreparingUntilItEnds() {
		var progress = WorkDoneProgress()
		let begun = progress.received(kind: "begin", token: indexing)
		#expect(begun)
		#expect(progress.isPreparing)
		let ended = progress.received(kind: "end", token: indexing)
		#expect(ended)
		#expect(!progress.isPreparing)
	}

	/// The measured cold start sent about five hundred reports between the begin
	/// and the end, and each one would otherwise redraw a bar the caret is in.
	@Test func onlyTheTwoNotificationsThatChangeAnythingSaySoAsMuch() {
		var progress = WorkDoneProgress()
		var changes = 0
		if progress.received(kind: "begin", token: indexing) { changes += 1 }
		for reported in 1 ... 500 {
			if progress.received(kind: "report", token: indexing) { changes += 1 }
			#expect(progress.isPreparing, "still preparing at report \(reported)")
		}
		if progress.received(kind: "end", token: indexing) { changes += 1 }
		#expect(changes == 2)
	}

	/// Two tokens overlap on a real cold open — `package-reloading` ends at 14 s
	/// and `indexing` runs to 75 s — and the false diagnostic is up for the whole
	/// of it. Preparation being over when the *first* of them ends would put the
	/// word away with a minute of the wait still to go.
	@Test func preparationLastsUntilTheLastOpenTokenEnds() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		progress.received(kind: "begin", token: reloading)

		let firstEnd = progress.received(kind: "end", token: reloading)
		#expect(!firstEnd)
		#expect(progress.isPreparing)

		let lastEnd = progress.received(kind: "end", token: indexing)
		#expect(lastEnd)
		#expect(!progress.isPreparing)
	}

	/// The flicker this exists to prevent. A server goes on reporting progress
	/// for as long as it runs — a reindex after ⌘S, a flycheck — and none of that
	/// is the wait 0501 is about.
	@Test func workAfterTheFirstStretchIsNotPreparation() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		progress.received(kind: "end", token: indexing)

		let saved = progress.received(kind: "begin", token: "reindexing.after-a-save")
		#expect(!saved)
		#expect(!progress.isPreparing)
		let done = progress.received(kind: "end", token: "reindexing.after-a-save")
		#expect(!done)
		#expect(!progress.isPreparing)
	}

	/// A report with no begin in front of it is not an implicit begin. A token
	/// opened that way could be closed by an end this never saw, and the word
	/// would stay up for the rest of the session.
	@Test func aReportWithNoBeginStartsNothing() {
		var progress = WorkDoneProgress()
		let reported = progress.received(kind: "report", token: indexing)
		#expect(!reported)
		#expect(!progress.isPreparing)
	}

	@Test func aServerThatStopsMidPreparationIsNoLongerPreparing() {
		var progress = WorkDoneProgress()
		progress.received(kind: "begin", token: indexing)
		let stopped = progress.stopped()
		#expect(stopped)
		#expect(!progress.isPreparing)
	}
}

import Foundation

/// Whether a language server is still getting ready to answer, read from the
/// work it says it is doing.
///
/// A server that has to build something before it can answer says so wrongly in
/// the meantime, and it says it in the one place nobody can argue with: a Swift
/// package whose dependencies are not built publishes `No such module 'Cadova'`
/// thirteen seconds after the file is opened and withdraws it a minute later,
/// with the right answers behind it. For that minute the file is covered in red
/// for a reason that has nothing to do with the code. 0501 is that minute.
///
/// **Work-done progress is the seam, and it was chosen against the log.**
/// Measured on that package with the build directory deleted, `sourcekit-lsp`
/// opens a token titled `Indexing` 13.8 seconds *before* the false diagnostic
/// appears and ends it 0.1 seconds *after* it clears — so the token brackets the
/// window almost exactly. The same run's `window/logMessage` prose could not:
/// `Preparing <target>` says a target started and never says one finished, the
/// finish it does print is shared with hundreds of indexing subprocesses, and
/// `Preparing` is one server's word. `$/progress` is the protocol's, it has an
/// explicit end, and every server that makes a client wait uses it — measured,
/// `gopls` opens one numbered token titled `Setting up workspace` and
/// `rust-analyzer` opens seven named ones, `Fetching` through `cachePriming`.
///
/// **Preparation is the first stretch of work and only the first.** Once the
/// server has settled, this stays quiet for the rest of its life, and that is
/// the difference between a word and a flicker: servers go on reporting progress
/// for as long as they run — `rust-analyzer` runs `cargo check` after every save
/// and reports it — and a chip that said "preparing" every time somebody pressed
/// ⌘S is a chip people stop reading.
///
/// **Which is why "no tokens open" is not the same as "finished", and this is
/// the part that had to be measured rather than reasoned about.** The obvious
/// rule — preparation ends when the set of open tokens empties — is right for
/// `sourcekit-lsp`, which holds one token across the whole minute, and quite
/// wrong for `rust-analyzer`, which closes each step before opening the next: on
/// a cold crate its set emptied **eight times** during a startup that ran to 8.7
/// seconds, the first of them at 1.1 seconds. The obvious rule puts the word up
/// for the first eighth of the wait and never again, and reporting each gap
/// would flash the chip eight times.
///
/// So an empty set is a *question* rather than an answer — `mayHaveFinished` —
/// and the caller asks again after a grace. The longest of those eight gaps was
/// 0.1 seconds and the rest were too short to measure, so a grace of about a
/// second is an order of magnitude clear of them, and still far shorter than the
/// pause before somebody saves a file and starts the work that must *not* count.
public struct WorkDoneProgress: Equatable, Sendable {
	/// What the caller should do about a notification.
	public enum Change: Equatable, Sendable {
		/// Nothing anybody has to be told: a report, or work after the server
		/// settled.
		case nothing
		/// The server has begun the work it has to do before it can answer. Say
		/// so.
		case startedPreparing
		/// Nothing is open any more — but see the type's comment: several servers
		/// close each step before opening the next, so this is a question. Ask
		/// `settleIfStillIdle()` again after the grace.
		case mayHaveFinished
	}

	/// Tokens the server has begun and not yet ended.
	private var open: Set<String> = []
	/// Whether the first stretch of work is over. Never goes back.
	private var settled = false

	/// Whether the server is still in the first stretch of work it began.
	///
	/// True from the first begin until the work stops for longer than the grace,
	/// *including* the gaps in between — which is the whole reason this is not
	/// simply `!open.isEmpty`.
	public private(set) var isPreparing = false

	public init() {}

	/// A `$/progress` notification arrived.
	///
	/// - Parameters:
	///   - kind: `begin`, `report` or `end`, as the notification's value says.
	///   - token: the notification's token, as a string. The protocol allows an
	///     integer as well and `gopls` uses one, so the caller is what flattens
	///     the two — a server that numbers its tokens and one that names them are
	///     saying the same thing here.
	@discardableResult
	public mutating func received(kind: String, token: String) -> Change {
		guard !settled else { return .nothing }
		switch kind {
		case "begin":
			open.insert(token)
			guard !isPreparing else { return .nothing }
			isPreparing = true
			return .startedPreparing
		case "end":
			open.remove(token)
			// Only worth asking about if something was up to finish. An `end` for
			// a token this never saw begin closes nothing.
			guard open.isEmpty, isPreparing else { return .nothing }
			return .mayHaveFinished
		default:
			// `report`, and anything a future protocol adds. Deliberately not
			// treated as an implicit begin: the specification requires a begin
			// first, and inventing one from a report would mean an `end` this
			// never saw the start of could not close the token it opened —
			// leaving the word on screen for the rest of the session, which is
			// the one failure that would be worse than saying nothing.
			return .nothing
		}
	}

	/// Asked after the grace, when `mayHaveFinished` was returned.
	///
	/// - Returns: whether preparation really has finished, and the screen should
	///   be told. False when the server opened something else in the meantime —
	///   which is the ordinary case for a server that closes each step before
	///   opening the next — and false for every later call, because settling
	///   happens once.
	@discardableResult
	public mutating func settleIfStillIdle() -> Bool {
		guard !settled, isPreparing, open.isEmpty else { return false }
		isPreparing = false
		settled = true
		return true
	}

	/// The server stopped, so whatever it had open is over.
	///
	/// Without this a server killed mid-preparation would leave `isPreparing`
	/// true on a value somebody might still read. Nothing resumes afterwards: a
	/// server started again under the same key is a new client and a new one of
	/// these.
	@discardableResult
	public mutating func stopped() -> Bool {
		let wasPreparing = isPreparing
		open.removeAll()
		isPreparing = false
		settled = true
		return wasPreparing
	}
}

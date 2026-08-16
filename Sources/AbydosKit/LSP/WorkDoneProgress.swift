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
/// explicit end, and every server that makes a client wait uses it.
///
/// **Preparation is the first stretch of work and only the first.** Once the
/// server has been idle, this stays quiet for the rest of its life, and that is
/// the difference between a word and a flicker: servers go on reporting progress
/// for as long as they run — a reindex after a save, a flycheck — and a chip that
/// said "preparing" every time somebody pressed ⌘S is a chip people stop reading.
/// The first stretch is the one the item is about, it happens once per server,
/// and it is over when the server first has nothing to do.
public struct WorkDoneProgress: Equatable, Sendable {
	/// Tokens the server has begun and not yet ended.
	private var open: Set<String> = []
	/// Whether the first stretch of work has finished. Never goes back.
	private var settled = false

	/// Whether the server is still in the first stretch of work it began.
	public private(set) var isPreparing = false

	public init() {}

	/// A `$/progress` notification arrived.
	///
	/// - Parameters:
	///   - kind: `begin`, `report` or `end`, as the notification's value says.
	///   - token: the notification's token, as a string. The protocol allows an
	///     integer as well, and the caller is what flattens the two — a server
	///     that numbers its tokens and one that names them are the same thing
	///     here, and a `Set<String>` keyed on `"7"` behaves.
	/// - Returns: whether `isPreparing` changed, so that a caller can tell the
	///   screen on the two notifications that matter rather than on all five
	///   hundred. The measured cold start sent about five hundred reports and
	///   this returns true twice.
	@discardableResult
	public mutating func received(kind: String, token: String) -> Bool {
		let before = isPreparing
		switch kind {
		case "begin":
			// Only before the server has ever settled: see the type's comment.
			// A begin after that is ordinary background work and is not counted,
			// which also keeps `open` from growing for a set nobody reads.
			guard !settled else { return false }
			open.insert(token)
			isPreparing = true
		case "end":
			guard !settled else { return false }
			open.remove(token)
			if open.isEmpty && isPreparing {
				isPreparing = false
				settled = true
			}
		default:
			// `report` and anything a future protocol adds. Deliberately not
			// treated as an implicit begin: the specification requires a begin
			// first, and inventing one from a report would mean an `end` this
			// never saw the start of could not close the token it opened —
			// leaving the word on screen for the rest of the session, which is
			// the one failure that would be worse than saying nothing.
			break
		}
		return isPreparing != before
	}

	/// The server stopped, so whatever it had open is over.
	///
	/// Without this a server killed mid-preparation would leave `isPreparing`
	/// true on a value somebody might still read. Nothing resumes afterwards: a
	/// server started again under the same key is a new client and a new one of
	/// these.
	@discardableResult
	public mutating func stopped() -> Bool {
		let before = isPreparing
		open.removeAll()
		isPreparing = false
		settled = true
		return isPreparing != before
	}
}

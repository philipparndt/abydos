import Foundation

/// Which rows of a list somebody has ticked, and what each tick was about.
///
/// **Marking done used to be one-way**: a row stayed struck through until
/// somebody unstruck it or the list was rebuilt from scratch. That is right for
/// a usages list and for a search, where the rows are answers to a question
/// asked once and the question is asked again from the beginning.
///
/// It is wrong for a list of files in a pull request, where the list stays and
/// the *rows* change underneath it. A tick left standing against a diff the
/// author has since rewritten says a file has been read when nobody has read
/// it — and a checklist whose ticks cannot be trusted is worse than no
/// checklist, because it is believed.
///
/// So a tick may carry a **token**: whatever the tick was about, as a string
/// this type never interprets. `revalidate` clears the ticks whose token has
/// changed and keeps the rest. Nothing is invalidated unless a token was given,
/// which is the case the usages list and the search results are in.
///
/// `Subject` is whatever names a row — a search mark, a file's path. This type
/// knows nothing about either.
public struct Checklist<Subject: Hashable & Sendable>: Equatable, Sendable {
	private var done: Set<Subject> = []
	/// What each tick was recorded against, for the rows that carried one.
	///
	/// Kept only for ticked rows: a token for a row nobody ticked is nothing to
	/// compare against later.
	private var tokens: [Subject: String] = [:]

	public init() {}

	public init(done: Set<Subject>, tokens: [Subject: String] = [:]) {
		self.done = done
		self.tokens = tokens.filter { done.contains($0.key) }
	}

	public var isEmpty: Bool { done.isEmpty }
	public var count: Int { done.count }
	public var subjects: Set<Subject> { done }
	/// What each tick was made against, for whatever has to write it down.
	public var recordedTokens: [Subject: String] { tokens }

	public func isDone(_ subject: Subject) -> Bool { done.contains(subject) }

	public func token(of subject: Subject) -> String? { tokens[subject] }

	/// Marks or unmarks a batch, and answers with the set as it was before.
	///
	/// The whole previous set rather than a diff, because that is what ⌘Z needs
	/// and it is small: a set of marks is a few dozen short strings even after a
	/// long session, and there is nothing here worth being clever about.
	@discardableResult
	public mutating func set(
		_ subjects: [Subject],
		done isDone: Bool,
		tokens newTokens: [Subject: String] = [:]
	) -> Set<Subject> {
		let previous = done
		if isDone {
			done.formUnion(subjects)
			for subject in subjects {
				if let token = newTokens[subject] { tokens[subject] = token }
			}
		} else {
			done.subtract(subjects)
			for subject in subjects { tokens.removeValue(forKey: subject) }
		}
		return previous
	}

	/// Puts a whole set of ticks back as it was, for ⌘Z.
	///
	/// The tokens are kept for whatever comes back and dropped for whatever does
	/// not: an undo restores what was ticked, and a tick with no record of what
	/// it was about is one `revalidate` can never clear.
	public mutating func restore(_ subjects: Set<Subject>) {
		done = subjects
		tokens = tokens.filter { subjects.contains($0.key) }
	}

	/// Clears the ticks whose subject has changed, and keeps the rest.
	///
	/// - Parameter current: what each row is about *now*. A row missing from it
	///   keeps its tick — it is a row this list no longer has, not a row that
	///   changed, and the two must not be confused: a file that leaves a pull
	///   request and comes back unchanged should come back ticked.
	/// - Returns: the rows whose ticks were cleared, so a caller can say so.
	@discardableResult
	public mutating func revalidate(against current: [Subject: String]) -> Set<Subject> {
		var cleared: Set<Subject> = []
		for subject in done {
			guard let was = tokens[subject], let now = current[subject], was != now else { continue }
			cleared.insert(subject)
		}
		guard !cleared.isEmpty else { return [] }
		done.subtract(cleared)
		for subject in cleared { tokens.removeValue(forKey: subject) }
		return cleared
	}
}

import Foundation

/// The stops of an inserted snippet, held where they are in the document while
/// somebody types into them.
///
/// A `Snippet` says where its stops are in the text it produced. The moment
/// that text is in a file those offsets start going out of date — typing `10`
/// over `size` moves everything after it — so something has to follow the
/// edits, and this is that something. It is a value rather than part of the
/// view because the whole of the difficulty is arithmetic on ranges, and
/// arithmetic is worth testing without a window.
///
/// The rule for staying alive is deliberately narrow: **an edit inside the
/// stop being typed into keeps the session; anything else ends it.** Which
/// means the ranges can never quietly describe text that has moved out from
/// under them — the alternative, guessing at how an edit somewhere else in the
/// file should move a stop, is how a snippet ends up putting the caret in the
/// middle of a word half a line away.
public struct SnippetSession: Equatable, Sendable {
	/// Absolute UTF-16 ranges in the document, in the order Tab visits them.
	/// Not in the order they appear in the text: `${2:a} ${1:b}` is visited
	/// right to left, and stepping through them is what the order is for.
	public private(set) var stops: [Range<Int>]
	/// Which of them the caret is on.
	public private(set) var index: Int

	/// Nil when there is nothing to step through.
	///
	/// One stop is not a session: `union() $0` has a single place for the
	/// caret to go, it goes there, and Tab afterwards means what Tab has
	/// always meant.
	public init?(_ snippet: Snippet, insertedAt start: Int) {
		let ranges = snippet.stops.map {
			(start + $0.range.lowerBound)..<(start + $0.range.upperBound)
		}
		guard ranges.count > 1 else { return nil }
		self.stops = ranges
		self.index = 0
	}

	/// Where the caret is meant to be now. Selected rather than merely arrived
	/// at, when it has any width: the default is text to type over.
	public var current: Range<Int> { stops[index] }

	/// Whether this is the last stop, after which there is nothing to visit.
	public var isOnLastStop: Bool { index == stops.count - 1 }

	/// Moves one stop forwards or backwards, and says where the caret goes.
	///
	/// Nil at either end: there is no stop before the first, and none after
	/// the last. What the caller does with that differs at the two ends, which
	/// is why this reports rather than decides.
	public mutating func advance(_ direction: Int) -> Range<Int>? {
		let next = index + direction
		guard stops.indices.contains(next) else { return nil }
		index = next
		return stops[next]
	}

	/// Takes an edit the document has just made, and says whether the session
	/// survives it.
	///
	/// `false` means the edit was not in the stop being typed into, and the
	/// caller should let the session go.
	public mutating func edited(replacing range: Range<Int>, insertedLength: Int) -> Bool {
		guard range.lowerBound >= current.lowerBound,
		      range.upperBound <= current.upperBound
		else { return false }

		let delta = insertedLength - (range.upperBound - range.lowerBound)
		guard delta != 0 else { return true }

		stops[index] = current.lowerBound..<(current.upperBound + delta)
		for other in stops.indices where other != index {
			// Positional, not by visiting order — the stops are numbered in
			// whatever order the server felt like, and only where they *are*
			// decides whether this edit pushed them along.
			guard stops[other].lowerBound >= range.upperBound else { continue }
			stops[other] = (stops[other].lowerBound + delta)..<(stops[other].upperBound + delta)
		}
		return true
	}

	/// Whether the caret is somewhere this session still speaks for.
	///
	/// Clicking elsewhere does not end a session by itself — nothing has moved
	/// and nothing is wrong — but Tab there is a tab, not a jump back into a
	/// snippet somebody has visibly left.
	public func covers(caret: Int) -> Bool {
		caret >= current.lowerBound && caret <= current.upperBound
	}
}

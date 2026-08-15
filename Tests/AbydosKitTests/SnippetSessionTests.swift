import Foundation
import Testing
@testable import AbydosKit

/// Holding a snippet's stops while the text under them changes.
///
/// The case throughout is the one openscad-lsp answers `cube` with, inserted at
/// the start of an empty line:
///
///     cube(size = size, center = false);
///     ^12  ^16                          ^34
///
/// stop 1 is `size` at 12..<16, and `$0` is the end of the line at 34.
///
/// `edited` and `advance` are mutating, and `#expect` cannot call a mutating
/// member — hence the local before each check rather than the call inside it.
struct SnippetSessionTests {
	private let cube = Snippet.expand("cube(size = ${1:size}, center = false);$0")

	private func session(at start: Int = 0) -> SnippetSession {
		guard let session = SnippetSession(cube, insertedAt: start) else {
			Issue.record("cube has two stops and should make a session")
			return SnippetSession(Snippet.expand("$1$0"), insertedAt: 0)!
		}
		return session
	}

	@Test func startsOnTheFirstStop() {
		#expect(session().current == 12..<16)
		#expect(session().isOnLastStop == false)
	}

	/// Inserted partway into a file, the stops are where the text went.
	@Test func offsetsTheStopsByWhereItWasInserted() {
		#expect(session(at: 100).current == 112..<116)
	}

	/// One place for the caret is not something to step through.
	@Test func refusesASnippetWithOneStop() {
		#expect(SnippetSession(Snippet.expand("union() $0"), insertedAt: 0) == nil)
		#expect(SnippetSession(Snippet.expand("difference"), insertedAt: 0) == nil)
	}

	@Test func stepsToTheLastStop() {
		var session = session()
		let last = session.advance(1)
		#expect(last == 34..<34)
		#expect(session.isOnLastStop)

		let beyond = session.advance(1)
		#expect(beyond == nil)
	}

	@Test func stepsBack() {
		var session = session()
		_ = session.advance(1)
		let back = session.advance(-1)
		#expect(back == 12..<16)

		let beforeTheFirst = session.advance(-1)
		#expect(beforeTheFirst == nil)
	}

	/// Typing over the selected default: everything after it moves by what the
	/// length changed by, which is the whole point of holding these ranges.
	@Test func followsTheStopBeingTypedInto() {
		var session = session()
		let alive = session.edited(replacing: 12..<16, insertedLength: 2)
		#expect(alive)
		#expect(session.current == 12..<14)

		let last = session.advance(1)
		#expect(last == 32..<32)
	}

	/// A run of single characters, the way somebody actually types.
	@Test func followsOneCharacterAtATime() {
		var session = session()
		// `size` selected and replaced by the first keystroke, then two more.
		let first = session.edited(replacing: 12..<16, insertedLength: 1)
		let second = session.edited(replacing: 13..<13, insertedLength: 1)
		let third = session.edited(replacing: 14..<14, insertedLength: 1)
		#expect(first && second && third)
		#expect(session.current == 12..<15)

		let last = session.advance(1)
		#expect(last == 33..<33)
	}

	/// Deleting inside the stop shortens it rather than ending anything.
	@Test func followsADeletionInsideTheStop() {
		var session = session()
		let alive = session.edited(replacing: 15..<16, insertedLength: 0)
		#expect(alive)
		#expect(session.current == 12..<15)

		let last = session.advance(1)
		#expect(last == 33..<33)
	}

	/// An edit anywhere else ends it. The alternative is guessing where a stop
	/// went, and a wrong guess puts the caret in the middle of a word.
	@Test func endsOnAnEditOutsideTheStop() {
		var session = session()
		let alive = session.edited(replacing: 30..<30, insertedLength: 1)
		#expect(alive == false)
	}

	/// Including one that starts inside and runs past the end — a selection
	/// dragged out of the stop, or ⌥⌫ from just after it.
	@Test func endsOnAnEditThatLeavesTheStop() {
		var session = session()
		let alive = session.edited(replacing: 14..<20, insertedLength: 0)
		#expect(alive == false)
	}

	/// Backspacing at the left edge takes the character before the stop, which
	/// is outside it.
	@Test func endsOnADeletionAtTheLeftEdge() {
		var session = session()
		let alive = session.edited(replacing: 11..<12, insertedLength: 0)
		#expect(alive == false)
	}

	/// Stops are visited by number and numbered however the server liked, so
	/// what moves a stop along is where it is, not when it is visited.
	@Test func movesStopsThatSitAfterTheEditWhicheverOrderTheyAreVisitedIn() {
		// `${2:bb} ${1:a}` — stop 1 is visited first and sits second.
		var session = SnippetSession(Snippet.expand("${2:bb} ${1:a}$0"), insertedAt: 0)!
		#expect(session.stops == [3..<4, 0..<2, 4..<4])

		// Typing `xyz` over the `a` at stop 1 moves `$0` and leaves `bb` alone.
		let alive = session.edited(replacing: 3..<4, insertedLength: 3)
		#expect(alive)
		#expect(session.stops == [3..<6, 0..<2, 6..<6])
	}

	/// An empty stop grows from nothing when it is typed into.
	@Test func followsAnEmptyStop() {
		var session = SnippetSession(Snippet.expand("if ($1) {$0}"), insertedAt: 0)!
		#expect(session.current == 4..<4)

		let alive = session.edited(replacing: 4..<4, insertedLength: 3)
		#expect(alive)
		#expect(session.current == 4..<7)

		let last = session.advance(1)
		#expect(last == 10..<10)
	}

	/// The caret at either edge of a stop is still in it: typing at the end of
	/// what you just typed is the commonest thing there is.
	@Test func coversTheEdgesOfTheStop() {
		let session = session()
		#expect(session.covers(caret: 12))
		#expect(session.covers(caret: 16))
		#expect(session.covers(caret: 11) == false)
		#expect(session.covers(caret: 17) == false)
	}
}

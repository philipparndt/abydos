import Foundation
import Testing
@testable import AbydosKit

/// Find highlights belong to the text as it is now.
///
/// The picture this was written from: a file searched for a path, then edited so
/// that eight of its ten lines no longer held it, still drawing eight bands —
/// the old lengths at the old offsets, over words that matched nothing.
struct MatchesAfterEditTests {
	static func match(_ range: Range<Int>) -> SearchMatch {
		SearchMatch(utf16Range: range, line: 0, lineText: "")
	}

	@Test func aMatchBeforeTheEditDoesNotMove() {
		let (matches, _) = MatchesAfterEdit.adjusted(
			[Self.match(0..<4)], current: 0, replacing: 10..<12, insertedLength: 5
		)
		#expect(matches.map(\.utf16Range) == [0..<4])
	}

	@Test func aMatchAfterTheEditMovesByWhatTheEditChanged() {
		let (grown, _) = MatchesAfterEdit.adjusted(
			[Self.match(20..<24)], current: nil, replacing: 5..<5, insertedLength: 3
		)
		#expect(grown.map(\.utf16Range) == [23..<27])

		let (shrunk, _) = MatchesAfterEdit.adjusted(
			[Self.match(20..<24)], current: nil, replacing: 5..<9, insertedLength: 0
		)
		#expect(shrunk.map(\.utf16Range) == [16..<20])
	}

	/// The eight lines in the picture. What the edit reached into is not a match
	/// any more, and no arithmetic on its offsets makes it one.
	@Test func aMatchTheEditReachedIntoIsGone() {
		let (matches, _) = MatchesAfterEdit.adjusted(
			[Self.match(0..<10), Self.match(20..<30)],
			current: 0,
			replacing: 5..<7,
			insertedLength: 0
		)
		#expect(matches.map(\.utf16Range) == [18..<28])
	}

	@Test func anEditThatTakesEverythingLeavesNothing() {
		let (matches, current) = MatchesAfterEdit.adjusted(
			[Self.match(0..<4), Self.match(8..<12)],
			current: 1,
			replacing: 0..<20,
			insertedLength: 3
		)
		#expect(matches.isEmpty)
		#expect(current == nil)
	}

	/// A file rewritten underneath — a reload, a `git checkout` — arrives as one
	/// edit over the whole text, so every match goes and the search that follows
	/// is the only thing that puts any back.
	@Test func aWholeFileRewriteLeavesNoOldOffsets() {
		let (matches, current) = MatchesAfterEdit.adjusted(
			[Self.match(3..<7)], current: 0, replacing: 0..<400, insertedLength: 12
		)
		#expect(matches.isEmpty)
		#expect(current == nil)
	}

	@Test func theCurrentMatchStaysTheOneItWas() {
		let (matches, current) = MatchesAfterEdit.adjusted(
			[Self.match(0..<4), Self.match(20..<24), Self.match(40..<44)],
			current: 2,
			replacing: 10..<10,
			insertedLength: 2
		)
		#expect(matches.count == 3)
		#expect(current == 2)
		#expect(matches[2].utf16Range == 42..<46)
	}

	/// Typing inside the current match: it is destroyed, and the next one after
	/// the caret takes over — so ⌘G goes on from where the person is rather than
	/// back to the top of the file.
	@Test func aDestroyedCurrentMatchHandsOverToTheNextOneAlong() {
		let (matches, current) = MatchesAfterEdit.adjusted(
			[Self.match(0..<4), Self.match(20..<24), Self.match(40..<44)],
			current: 1,
			replacing: 21..<22,
			insertedLength: 0
		)
		#expect(matches.count == 2)
		#expect(current == 1)
		#expect(matches[1].utf16Range == 39..<43)
	}

	@Test func aDestroyedLastMatchFallsBackToTheOneBeforeIt() {
		let (matches, current) = MatchesAfterEdit.adjusted(
			[Self.match(0..<4), Self.match(20..<24)],
			current: 1,
			replacing: 21..<22,
			insertedLength: 0
		)
		#expect(matches.map(\.utf16Range) == [0..<4])
		#expect(current == 0)
	}

	@Test func nothingFoundStaysNothing() {
		let (matches, current) = MatchesAfterEdit.adjusted(
			[], current: nil, replacing: 0..<1, insertedLength: 1
		)
		#expect(matches.isEmpty)
		#expect(current == nil)
	}
}

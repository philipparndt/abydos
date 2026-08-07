import Foundation
import Testing
@testable import AbydosKit

/// Moving through a list with headers in it.
///
/// The palette lists entries under headings, so "down" is the next row somebody
/// can choose and a page is a number of those — not a number of rows.
struct ListSelectionTests {
	/// header, a, b, header, c, d
	private let selectable = [false, true, true, false, true, true]

	private func move(from: Int, by: Int) -> Int? {
		ListSelection.move(from: from, by: by, count: selectable.count) { selectable[$0] }
	}

	/// Down from an entry goes to the next entry, stepping over the heading
	/// between them rather than landing on it.
	@Test func stepsOverHeadings() {
		#expect(move(from: 2, by: 1) == 4)
		#expect(move(from: 4, by: -1) == 2)
	}

	/// Nothing selected yet: down finds the first entry, and up the last.
	@Test func startsFromEitherEnd() {
		#expect(move(from: -1, by: 1) == 1)
		#expect(ListSelection.move(from: 6, by: -1, count: 6) { selectable[$0] } == 5)
	}

	/// An arrow at the end stays where it is. There is nothing below, and
	/// jumping back to the top is somebody losing their place.
	@Test func anArrowAtTheEndStaysPut() {
		#expect(move(from: 5, by: 1) == nil)
		#expect(move(from: 1, by: -1) == nil)
	}

	/// A page that runs off the end lands on the last entry, which is what a
	/// page key does everywhere — the difference between a key that feels
	/// finished and one that feels stuck.
	@Test func aPageRunsToTheEndRatherThanNowhere() {
		#expect(move(from: 1, by: 10) == 5)
		#expect(move(from: 5, by: -10) == 1)
	}

	/// A page in the middle moves a page.
	@Test func aPageMovesAPageOfEntries() {
		#expect(move(from: 1, by: 2) == 4)
		#expect(move(from: 5, by: -2) == 2)
	}

	/// A list with nothing to select, and a list with nothing in it.
	@Test func survivesAListWithNowhereToGo() {
		#expect(ListSelection.move(from: 0, by: 1, count: 3) { _ in false } == nil)
		#expect(ListSelection.move(from: -1, by: 1, count: 0) { _ in true } == nil)
		#expect(ListSelection.move(from: 0, by: 0, count: 3) { _ in true } == nil)
	}

	/// A page is what fits, less a row: the overlap is what makes it possible
	/// to read down a long list without losing the place.
	@Test func aPageOverlapsByOneRow() {
		#expect(ListSelection.pageSize(viewportHeight: 260, rowHeight: 26) == 9)
		#expect(ListSelection.pageSize(viewportHeight: 26, rowHeight: 26) == 1)
		// Never zero, however small the list is.
		#expect(ListSelection.pageSize(viewportHeight: 10, rowHeight: 26) == 1)
		#expect(ListSelection.pageSize(viewportHeight: 100, rowHeight: 0) == 1)
	}
}

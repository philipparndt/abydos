import Foundation
import Testing
@testable import AbydosKit

/// Which part of a search match falls on which visual row.
///
/// 0540: the bands were measured along a `CTLine` built for the whole document
/// line while being painted on one visual row of it, so every match past the
/// first row landed at the x it would have had if the line had never wrapped.
/// The pixels are in the view; the arithmetic is here, which is what lets it be
/// asserted at all.
struct SearchBandTests {
	/// A line of sixty characters starting at document offset 100, wrapped at
	/// twenty columns: rows are 0..<20, 20..<40, 40..<60 within the line.
	private let lineStart = 100
	private let firstRow = 0..<20
	private let secondRow = 20..<40
	private let thirdRow = 40..<60

	@Test func aMatchOnTheFirstRowIsMeasuredFromTheRow() throws {
		let match = 105..<110
		let band = try #require(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: firstRow))
		#expect(band == 5..<10)
	}

	/// The case in the report: a match on the second visual row. Measured along
	/// the line it would be 25..<30 and drawn a whole row's width too far
	/// right; measured along the row it is 5..<10.
	@Test func aMatchOnTheSecondRowIsMeasuredFromThatRow() throws {
		let match = 125..<130
		let band = try #require(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: secondRow))
		#expect(band == 5..<10)
		// And it is not on the first row at all.
		#expect(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: firstRow) == nil)
	}

	@Test func aMatchCrossingAWrapGivesAPieceOnEachRow() throws {
		// 118..<124 straddles the boundary at 120.
		let match = 118..<124
		let first = try #require(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: firstRow))
		let second = try #require(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: secondRow))

		#expect(first == 18..<20, "the piece on the first row stops at its end")
		#expect(second == 0..<4, "the piece on the second row starts at its start")
		#expect(first.count + second.count == match.count, "between them they cover the match")
	}

	/// The row in the middle of a long match is banded across all of its text —
	/// the case that "clamp it to the first row" gets wrong, and the most likely
	/// half-right outcome.
	@Test func aRowInsideALongMatchIsBandedRightAcross() throws {
		let match = 110..<155
		let middle = try #require(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: secondRow))
		#expect(middle == 0..<20)

		let first = try #require(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: firstRow))
		let last = try #require(WrapLayout.bandRange(for: match, lineStart: lineStart, segment: thirdRow))
		#expect(first == 10..<20)
		#expect(last == 0..<15)
	}

	@Test func aMatchOnAnotherRowIsNotDrawnHere() {
		#expect(WrapLayout.bandRange(for: 145..<150, lineStart: lineStart, segment: firstRow) == nil)
		#expect(WrapLayout.bandRange(for: 145..<150, lineStart: lineStart, segment: secondRow) == nil)
	}

	/// An unwrapped line is one row covering the whole line, and the answer is
	/// what it always was.
	@Test func anUnwrappedLineIsUnchanged() throws {
		let wholeLine = 0..<60
		let band = try #require(WrapLayout.bandRange(for: 125..<130, lineStart: lineStart, segment: wholeLine))
		#expect(band == 25..<30)
	}

	/// A match that touches the row's edge exactly, both ends. An empty overlap
	/// is nothing rather than a zero-width band.
	@Test func aMatchThatOnlyTouchesTheEdgeIsNotOnThisRow() {
		#expect(WrapLayout.bandRange(for: 115..<120, lineStart: lineStart, segment: secondRow) == nil)
		#expect(WrapLayout.bandRange(for: 120..<125, lineStart: lineStart, segment: firstRow) == nil)
	}

	// MARK: - The two answers agreeing

	/// **The test that stops them drifting apart again.** The caret finds its row
	/// with `segment(forOffset:)` and its x along that row's text; a band now
	/// slices with `segmentRange` and measures along the same row. For any offset
	/// in a match, the row the caret would be on is the row the band's piece is
	/// on, and the offset within it is the same number.
	@Test func theBandAndTheCaretAgreeOnTheSameOffset() throws {
		let text = String(repeating: "abcdefghij", count: 6)
		let columns = 20
		let tabWidth = 4

		for offset in [0, 5, 19, 20, 21, 39, 40, 41, 59] {
			let row = WrapLayout.segment(
				forOffset: offset, in: text, columns: columns, tabWidth: tabWidth
			)
			let rowRange = WrapLayout.segmentRange(
				in: text, segment: row, columns: columns, tabWidth: tabWidth
			)
			// A one-unit match at that offset, in document coordinates.
			let match = (lineStart + offset)..<(lineStart + offset + 1)
			guard offset < text.utf16.count else { continue }

			let band = try #require(
				WrapLayout.bandRange(for: match, lineStart: lineStart, segment: rowRange),
				"offset \(offset) fell on no row"
			)
			#expect(
				band.lowerBound == offset - rowRange.lowerBound,
				"offset \(offset): the band starts where the caret would"
			)
		}
	}

	/// Tabs, because the row slicing is by display width and not by unit count —
	/// which is the thing that makes `segmentRange` more than division.
	@Test func aRowSlicedAroundATabStillAgrees() throws {
		let text = "\tone\ttwo\tthree\tfour\tfive\tsix"
		let columns = 12
		let tabWidth = 4

		for offset in 0..<text.utf16.count {
			let row = WrapLayout.segment(forOffset: offset, in: text, columns: columns, tabWidth: tabWidth)
			let rowRange = WrapLayout.segmentRange(in: text, segment: row, columns: columns, tabWidth: tabWidth)
			let match = (lineStart + offset)..<(lineStart + offset + 1)
			let band = try #require(
				WrapLayout.bandRange(for: match, lineStart: lineStart, segment: rowRange),
				"offset \(offset) fell on no row"
			)
			#expect(band.lowerBound == offset - rowRange.lowerBound)
		}
	}
}

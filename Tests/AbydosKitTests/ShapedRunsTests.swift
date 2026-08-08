import AppKit
import Foundation
import Testing
@testable import AbydosKit

/// What the shaper made of a run, remembered so it is not asked twice.
struct ShapedRunsTests {
	private var font: NSFont { NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) }

	/// Offsets come back relative to the run, never as columns.
	///
	/// The cache is keyed by the run's text, and the same text turns up at
	/// different places on a line — a prompt segment twice, the same operator
	/// on either side of an expression. Storing a column meant the second
	/// occurrence was drawn at the first one's, which is text piled on top of
	/// other text and is exactly what it looked like.
	@Test func offsetsAreRelativeToTheRun() throws {
		var runs = ShapedRuns()
		let piecesPieces = runs.pieces(
			for: "->", cellOfOffset: [0, 1], font: font, faceIndex: 0
		)
		let pieces = try #require(piecesPieces)
		#expect(pieces.map(\.cellOffset) == [0, 1])
	}

	/// And the answer for a run does not depend on where it was first asked
	/// about — which is the whole point of keying the cache by the text.
	@Test func theSameRunAnsweredTwiceIsTheSameAnswer() throws {
		var runs = ShapedRuns()
		let firstPieces = runs.pieces(
			for: "!=", cellOfOffset: [0, 1], font: font, faceIndex: 0
		)
		let first = try #require(firstPieces)
		let secondPieces = runs.pieces(
			for: "!=", cellOfOffset: [0, 1], font: font, faceIndex: 0
		)
		let second = try #require(secondPieces)
		#expect(first.map(\.cellOffset) == second.map(\.cellOffset))
		#expect(first.map(\.glyph) == second.map(\.glyph))
		#expect(first.allSatisfy { $0.cellOffset < 2 }, "an offset past the run is a column in disguise")
	}

	/// A run of ordinary text gives one piece per cell, in order.
	@Test func everyCellOfAPlainRunIsAccountedFor() throws {
		var runs = ShapedRuns()
		let text = "abcdef"
		let piecesPieces = runs.pieces(
			for: text, cellOfOffset: Array(0..<text.count), font: font, faceIndex: 0
		)
		let pieces = try #require(piecesPieces)
		#expect(pieces.map(\.cellOffset) == Array(0..<text.count))
	}

	/// Different faces are different answers, or bold text would be drawn with
	/// the glyphs of regular.
	@Test func theFaceIsPartOfTheQuestion() throws {
		var runs = ShapedRuns()
		let regularPieces = runs.pieces(
			for: "->", cellOfOffset: [0, 1], font: font, faceIndex: 0
		)
		let regular = try #require(regularPieces)
		let boldPieces = runs.pieces(
			for: "->", cellOfOffset: [0, 1],
			font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), faceIndex: 1
		)
		let bold = try #require(boldPieces)
		#expect(regular.count == bold.count)
	}

	@Test func clearingItLosesNothingButTheMemory() throws {
		var runs = ShapedRuns()
		let beforePieces = runs.pieces(for: "==", cellOfOffset: [0, 1], font: font, faceIndex: 0)
		let before = try #require(beforePieces)
		runs.removeAll()
		let afterPieces = runs.pieces(for: "==", cellOfOffset: [0, 1], font: font, faceIndex: 0)
		let after = try #require(afterPieces)
		#expect(before.map(\.glyph) == after.map(\.glyph))
	}
}

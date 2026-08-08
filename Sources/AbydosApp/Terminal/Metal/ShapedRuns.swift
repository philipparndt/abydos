import AppKit
import AbydosKit
import CoreText

/// What a shaper made of a run, remembered so it is not asked twice.
///
/// A terminal draws the same runs over and over — a prompt, a keyword, the
/// same operator on forty lines — so shaping is worth doing once and keeping.
/// Without that, turning ligatures on would mean handing CoreText every run of
/// every frame, which is what the per-cell path exists to avoid.
struct ShapedRuns {
	/// One glyph, and which cell of the run it starts at.
	struct Piece {
		let glyph: CGGlyph
		let font: CTFont
		/// Offset from the first cell of the run.
		let cellOffset: Int
	}

	private struct Key: Hashable {
		let text: String
		let face: UInt8
	}

	private var cache: [Key: [Piece]] = [:]
	/// Bounded, since a terminal can show an unbounded number of distinct runs.
	/// Cleared wholesale rather than evicted one at a time: the working set is
	/// small and stable, and a run that falls out is one shaping away.
	private static let capacity = 4096

	mutating func removeAll() { cache.removeAll(keepingCapacity: true) }

	/// The glyphs for a run, shaped once.
	///
	/// - Parameter text: the run's characters, one per cell it covers, in order.
	/// - Returns: nil when the run cannot be laid back onto the grid — when a
	///   glyph belongs to no character of it, which is what a shaper does with
	///   text this has no business reordering.
	mutating func pieces(
		for text: String, cellOfOffset: [Int], font: NSFont, faceIndex: UInt8
	) -> [Piece]? {
		let key = Key(text: text, face: faceIndex)
		if let known = cache[key] { return known }

		let attributed = NSAttributedString(string: text, attributes: [.font: font])
		let line = CTLineCreateWithAttributedString(attributed)
		guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return nil }

		var pieces: [Piece] = []
		for run in runs {
			let count = CTRunGetGlyphCount(run)
			guard count > 0 else { continue }
			var glyphs = [CGGlyph](repeating: 0, count: count)
			var indices = [CFIndex](repeating: 0, count: count)
			CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
			CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)

			let attributes = CTRunGetAttributes(run) as NSDictionary
			guard let runFont = attributes[kCTFontAttributeName as String] as! CTFont? else {
				return nil
			}
			for index in 0..<count {
				let offset = Int(indices[index])
				guard offset >= 0, offset < cellOfOffset.count else { return nil }
				pieces.append(Piece(
					glyph: glyphs[index], font: runFont, cellOffset: cellOfOffset[offset]
				))
			}
		}

		if cache.count >= Self.capacity { cache.removeAll(keepingCapacity: true) }
		cache[key] = pieces
		return pieces
	}
}

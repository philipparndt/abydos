import Foundation

/// Which stretches of a line are worth asking a font to shape.
///
/// A terminal draws a glyph per cell, at a whole-point column, because that is
/// what keeps the text on the grid: the font's advance is fractional, and
/// letting a line lay itself out makes it creep a fraction of a pixel per
/// character — a whole cell by the end of a typed command. Shaping is the
/// opposite of that, so it is done only where it can change anything, and the
/// result is placed back on the grid rather than taken from the shaper.
///
/// A ligature in a programming font is made of punctuation: `->`, `!=`, `=>`,
/// `<=`, `::`, `...`, `|>`. So a run can only ligate if it has two of these
/// side by side, and almost no run of ordinary text does. That check is a
/// couple of comparisons per cell against a table, which is worth paying to
/// avoid shaping every run of every frame.
public enum Ligatures {
	/// Characters that appear in the ligatures programming fonts ship.
	///
	/// Deliberately generous: a character listed here that never ligates costs
	/// one wasted shaping of a short run, while one missing means a ligature
	/// that silently never appears. Letters and digits are not here — the
	/// handful of fonts that ligate `www` or `0x` are paying for it with every
	/// word of prose on the screen.
	static let candidates: Set<UInt32> = {
		var set = Set<UInt32>()
		for character in "=<>-+*/\\!&|:.~?;#$@^%_" {
			set.insert(character.unicodeScalars.first!.value)
		}
		return set
	}()

	public static func isCandidate(_ scalar: UInt32) -> Bool { candidates.contains(scalar) }

	/// Whether a run has two candidates side by side, and so might ligate.
	///
	/// - Parameter scalars: the run's cells, left to right. A cell that draws
	///   nothing — a blank, the trailing half of a wide glyph — breaks the pair,
	///   which is right: nothing ligates across a space.
	public static func mayLigate<Row: Collection>(_ scalars: Row) -> Bool
	where Row.Element == UInt32 {
		var previousWasCandidate = false
		for scalar in scalars {
			let candidate = isCandidate(scalar)
			if candidate, previousWasCandidate { return true }
			previousWasCandidate = candidate
		}
		return false
	}
}

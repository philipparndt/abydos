import Foundation

/// How large a character cell is in real pixels, from a cell in points and
/// whatever the window system will say about the display.
///
/// Its own thing, and in the kit rather than beside the view, because it is
/// arithmetic with one consequence and no way to see it: the number decided
/// here is written into the pty's winsize, and `icat`, `timg` and `chafa` size
/// a whole picture from it and from nothing else.
public enum CellPixelSize {
	/// The first scale worth believing, applied to a cell — or nothing.
	///
	/// The scales are offered in the order they should be trusted, and a
	/// non-positive one is skipped rather than used. That distinction is the
	/// whole of this: `??` steps past an answer that is *absent*, and
	/// `NSWindow.backingScaleFactor` is not absent when it cannot be given, it
	/// is **zero** — which is what a window not on a screen reports, and a
	/// window is not on a screen while a display is being reconfigured: waking,
	/// being unplugged, a window sliding between two of them.
	///
	/// Zero fell straight through the chain, and since 0397 the answer is
	/// written to the pty and signalled the moment it is worked out rather than
	/// waiting for the grid to change. A cell of no pixels is exactly how a
	/// terminal says it cannot show pictures at all, so the program stops
	/// drawing them — reserving no space and printing nothing, which from the
	/// outside is the command appearing to do nothing whatsoever. And it stays
	/// that way, because nothing works the cell size out again until the font
	/// or the display changes.
	///
	/// Nothing comes back when no scale is usable. The caller leaves the last
	/// size alone: it was worked out on a screen that really existed, which is
	/// closer than any constant.
	public static func pixels(
		cellWidth: Double, cellHeight: Double, scales: [Double?]
	) -> (width: Int, height: Int)? {
		guard cellWidth > 0, cellHeight > 0,
		      let scale = scales.compactMap({ $0 }).first(where: { $0 > 0 })
		else { return nil }
		let width = Int((cellWidth * scale).rounded())
		let height = Int((cellHeight * scale).rounded())
		guard width > 0, height > 0 else { return nil }
		return (width: width, height: height)
	}
}

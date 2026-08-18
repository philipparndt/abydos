import Foundation

/// Maps document lines to visual rows when soft wrap is on.
///
/// Tractable only because the editor uses a fixed-advance font: a line's row
/// count is `ceil(columns / width)`, arithmetic rather than typesetting. The
/// per-line column counts are prefix-summed once so both directions of the
/// mapping are binary searches, which is what keeps scrolling cheap on a large
/// file.
///
/// Folding composes with this: hidden lines contribute no rows at all.
public struct WrapLayout: Sendable {
	/// Columns available for text. Nil means wrapping is off.
	public private(set) var columns: Int?

	/// Document line for each entry, in visual order.
	private var documentLines: [Int32] = []
	/// First visual row of each entry.
	private var rowStarts: [Int32] = []
	public private(set) var totalRows: Int = 0

	private var documentLineCount = 0

	public init() {}

	public var isWrapping: Bool { columns != nil }

	/// Rebuilds the mapping.
	///
	/// `rowsForLine` returns how many visual rows a line occupies. The caller
	/// supplies it so the count and the slicing come from the same walk —
	/// deriving it here as `ceil(width / columns)` disagrees whenever a tab has
	/// to move to the next row whole, and a row the layout allocated with
	/// nothing to put in it renders as a gap.
	public mutating func rebuild(
		documentLineCount: Int,
		columns: Int?,
		folding: FoldingState,
		rowsForLine: (Int) -> Int
	) {
		self.columns = columns
		self.documentLineCount = documentLineCount

		documentLines.removeAll(keepingCapacity: true)
		rowStarts.removeAll(keepingCapacity: true)
		documentLines.reserveCapacity(documentLineCount)
		rowStarts.reserveCapacity(documentLineCount)

		var row = 0
		for line in 0..<max(0, documentLineCount) {
			guard !folding.isHidden(line: line) else { continue }
			documentLines.append(Int32(line))
			rowStarts.append(Int32(row))
			row += columns == nil ? 1 : max(1, rowsForLine(line))
		}
		totalRows = max(1, row)
	}

	/// UTF-16 range of one wrapped segment of a line.
	///
	/// Cut by *display* width rather than by character count. A tab occupies up
	/// to `tabWidth` columns on screen but one UTF-16 unit, so slicing by unit
	/// count makes a row wider than the space it was measured for — the overflow
	/// is then clipped away and those characters are never seen anywhere.
	///
	/// The row count above is derived from the same display width, so the two
	/// have to agree or the last segment of a line goes missing.
	public static func segmentRange(
		in text: String,
		segment: Int,
		columns: Int,
		tabWidth: Int
	) -> Range<Int> {
		guard columns > 0, segment >= 0 else { return 0..<0 }

		let units = Array(text.utf16)
		var start = 0
		var column = 0
		var index = 0
		var currentSegment = 0

		let tab = UInt16(0x09)

		while index < units.count {
			let width = units[index] == tab ? tabWidth - (column % tabWidth) : 1

			// A tab that would straddle the edge moves to the next row whole,
			// which is what the renderer does with it too.
			if column + width > columns, column > 0 {
				if currentSegment == segment { return start..<index }
				currentSegment += 1
				start = index
				column = 0
				continue
			}

			column += width
			index += 1
		}

		return currentSegment == segment ? start..<units.count : units.count..<units.count
	}

	/// What part of a match falls on one visual row, in that row's own offsets.
	///
	/// **A match is a list of rectangles, not a rectangle**, and this is the
	/// arithmetic that says which. 0540: the bands behind search matches were
	/// measured along a `CTLine` built for the whole document line while being
	/// painted on one visual row of it, so every match past the first row landed
	/// at the x it would have had if the line had never wrapped. The caret's own
	/// answer knew about wrapping and this one did not, which is two answers to
	/// "where is this offset on screen" — the shape of fault that keeps coming
	/// back here.
	///
	/// Nil where the match does not touch this row at all. A match that crosses
	/// a wrap boundary is asked once per row it touches and answers a piece each
	/// time; a row in the middle of a long match answers the whole row.
	///
	/// Pure offsets, so it can be asserted without a window — which is what 0536
	/// did for the *order* the bands are painted in, and why that part has tests
	/// while this part did not.
	///
	/// - Parameters:
	///   - match: the match, in document UTF-16 offsets.
	///   - lineStart: the document UTF-16 offset of the line's first unit.
	///   - segment: the row's range within the line, as `segmentRange` gives it.
	/// - Returns: the range to band, in offsets from the start of the row.
	public static func bandRange(
		for match: Range<Int>,
		lineStart: Int,
		segment: Range<Int>
	) -> Range<Int>? {
		// The row, in document offsets.
		let rowStart = lineStart + segment.lowerBound
		let rowEnd = lineStart + segment.upperBound

		let from = max(match.lowerBound, rowStart)
		let to = min(match.upperBound, rowEnd)
		guard to > from else { return nil }

		return (from - rowStart)..<(to - rowStart)
	}

	/// Which segment of a line a UTF-16 offset falls in.
	///
	/// Walks the same display widths `segmentRange` does, so the caret lands on
	/// the row that actually shows it.
	public static func segment(
		forOffset offset: Int,
		in text: String,
		columns: Int,
		tabWidth: Int
	) -> Int {
		guard columns > 0, offset > 0 else { return 0 }

		let units = Array(text.utf16)
		var column = 0
		var index = 0
		var segment = 0
		let tab = UInt16(0x09)

		let limit = min(offset, units.count)
		while index < limit {
			let width = units[index] == tab ? tabWidth - (column % tabWidth) : 1
			if column + width > columns, column > 0 {
				segment += 1
				column = 0
				continue
			}
			column += width
			index += 1
		}

		// A break can fall exactly *at* the offset — the caret then belongs on
		// the row that is about to start, not at the end of the one that just
		// filled. Not applied at end of line: there is no next row there.
		if index == offset, index < units.count, column > 0 {
			let width = units[index] == tab ? tabWidth - (column % tabWidth) : 1
			if column + width > columns { segment += 1 }
		}
		return segment
	}

	/// Rows a line occupies, by the same walk that slices it.
	public static func rowCount(in text: String, columns: Int, tabWidth: Int) -> Int {
		guard columns > 0 else { return 1 }

		let units = Array(text.utf16)
		var rows = 1
		var column = 0
		var index = 0
		let tab = UInt16(0x09)

		while index < units.count {
			let width = units[index] == tab ? tabWidth - (column % tabWidth) : 1
			if column + width > columns, column > 0 {
				rows += 1
				column = 0
				continue
			}
			column += width
			index += 1
		}
		return rows
	}

	private func unusedRowCount(forLine line: Int, columns: Int?, columnsForLine: (Int) -> Int) -> Int {
		guard let columns, columns > 0 else { return 1 }
		let width = columnsForLine(line)
		// An empty line still occupies one row.
		return max(1, Int((width + columns - 1) / columns))
	}

	/// The document line shown at a visual row, and which wrapped segment it is.
	public func position(forRow row: Int) -> (line: Int, segment: Int) {
		guard !rowStarts.isEmpty else { return (0, 0) }
		let target = max(0, min(row, totalRows - 1))

		// Last entry whose first row is at or before the target.
		var low = 0
		var high = rowStarts.count - 1
		while low < high {
			let mid = (low + high + 1) / 2
			if Int(rowStarts[mid]) <= target { low = mid } else { high = mid - 1 }
		}
		return (Int(documentLines[low]), target - Int(rowStarts[low]))
	}

	/// The visual row a document line starts on.
	public func firstRow(forLine line: Int) -> Int {
		guard !documentLines.isEmpty else { return 0 }

		var low = 0
		var high = documentLines.count - 1
		while low < high {
			let mid = (low + high + 1) / 2
			if Int(documentLines[mid]) <= line { low = mid } else { high = mid - 1 }
		}
		return Int(rowStarts[low])
	}

	/// Rows a line occupies.
	public func rowCount(forLine line: Int) -> Int {
		guard !documentLines.isEmpty else { return 1 }
		let start = firstRow(forLine: line)

		var low = 0
		var high = documentLines.count - 1
		while low < high {
			let mid = (low + high + 1) / 2
			if Int(documentLines[mid]) <= line { low = mid } else { high = mid - 1 }
		}
		let next = low + 1 < rowStarts.count ? Int(rowStarts[low + 1]) : totalRows
		return max(1, next - start)
	}
}

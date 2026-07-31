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
	/// `columnsForLine` returns a line's display width; the caller supplies it so
	/// tab expansion stays in one place.
	public mutating func rebuild(
		documentLineCount: Int,
		columns: Int?,
		folding: FoldingState,
		columnsForLine: (Int) -> Int
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
			row += rowCount(forLine: line, columns: columns, columnsForLine: columnsForLine)
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

	private func rowCount(forLine line: Int, columns: Int?, columnsForLine: (Int) -> Int) -> Int {
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

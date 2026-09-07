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

	/// Where a line's visual rows begin, in UTF-16 offsets: the first is always
	/// 0, and every other is where a row was cut.
	///
	/// **Cut at words, not in them.** A row is filled by display width — a tab
	/// is `tabWidth` columns and one unit — and when the next unit would not
	/// fit, the cut goes back to just after the last whitespace on the row, so
	/// a word moves down whole; the whitespace stays at the end of the row
	/// above, where the eye does not look for it. A word longer than the row
	/// has no such place and is cut at the edge, as it always was. Prose read
	/// in the editor — a `README`, a commit message, a comment block — was
	/// being broken mid-word, which is the one thing that stops the reading
	/// flow soft wrap exists to keep.
	///
	/// One walk for the three questions below, so the row count, the slicing
	/// and the caret's row cannot disagree — which is the fault this file
	/// keeps recording.
	public static func rowStarts(in text: String, columns: Int, tabWidth: Int) -> [Int] {
		guard columns > 0 else { return [0] }
		let units = Array(text.utf16)
		var starts = [0]
		var rowStart = 0
		var column = 0
		var index = 0
		/// The offset just after the last whitespace on this row that came
		/// after a word, or nil. Whitespace at the start of a row is
		/// indentation, and a cut there would make a row of nothing but it.
		var wordBreak: Int?
		var sawWord = false
		let tab = UInt16(0x09), space = UInt16(0x20)

		while index < units.count {
			let unit = units[index]
			let width = unit == tab ? tabWidth - (column % tabWidth) : 1
			if column + width > columns, column > 0 {
				// Somewhere on this row a word ended: cut there and put the
				// rest of the row's units back to be laid out again.
				if let cut = wordBreak, cut > rowStart, cut < index {
					index = cut
				}
				starts.append(index)
				rowStart = index
				column = 0
				wordBreak = nil
				sawWord = false
				continue
			}
			column += width
			index += 1
			if unit == space || unit == tab {
				if sawWord { wordBreak = index }
			} else {
				sawWord = true
			}
		}
		return starts
	}

	/// UTF-16 range of one wrapped segment of a line, by the cuts above.
	public static func segmentRange(
		in text: String,
		segment: Int,
		columns: Int,
		tabWidth: Int
	) -> Range<Int> {
		guard columns > 0, segment >= 0 else { return 0..<0 }
		let starts = rowStarts(in: text, columns: columns, tabWidth: tabWidth)
		let count = text.utf16.count
		guard segment < starts.count else { return count..<count }
		let end = segment + 1 < starts.count ? starts[segment + 1] : count
		return starts[segment]..<end
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

	/// Which segment of a line a UTF-16 offset falls in, by the same cuts.
	///
	/// A cut can fall exactly *at* the offset — the caret then belongs on the
	/// row that is about to start, not at the end of the one that just filled.
	/// Not applied at end of line: there is no next row there.
	public static func segment(
		forOffset offset: Int,
		in text: String,
		columns: Int,
		tabWidth: Int
	) -> Int {
		guard columns > 0, offset > 0 else { return 0 }
		let starts = rowStarts(in: text, columns: columns, tabWidth: tabWidth)
		let count = text.utf16.count
		var segment = 0
		for (index, start) in starts.enumerated() where index > 0 {
			if start < offset || (start == offset && offset < count) { segment = index } else { break }
		}
		return segment
	}

	/// Rows a line occupies, by the same cuts.
	public static func rowCount(in text: String, columns: Int, tabWidth: Int) -> Int {
		guard columns > 0 else { return 1 }
		return rowStarts(in: text, columns: columns, tabWidth: tabWidth).count
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

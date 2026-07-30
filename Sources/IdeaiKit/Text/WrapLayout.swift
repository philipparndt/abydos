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

import Foundation

/// A place in a diff, as the view's rows number them: which row, and how far
/// into that row's text.
///
/// **A row and an offset, not a document offset.** There is no document behind a
/// diff view: its rows are derived from a `GitPatch` and rebuilt when the
/// arrangement changes, when the preamble preference moves, when a remark is
/// written and when the whole-file switch is thrown. A single offset into a
/// notional whole would have to be remapped through every one of those, and each
/// remapping is a place to be quietly wrong about which line somebody selected.
///
/// The offset is in UTF-16 code units, because that is what Core Text answers in
/// and what an `NSAttributedString` is indexed by. Nothing here converts: a
/// number that came from a hit test is used as it arrived.
public struct DiffTextPoint: Equatable, Comparable, Sendable {
	/// Which row, in the order the view draws them.
	public let row: Int
	/// How far into that row's text, in UTF-16 code units.
	public let offset: Int

	public init(row: Int, offset: Int) {
		self.row = row
		self.offset = offset
	}

	/// Row first, then offset — the order the rows are read in.
	public static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.row == rhs.row ? lhs.offset < rhs.offset : lhs.row < rhs.row
	}
}

/// A run of a diff's text, and the characters it puts on the clipboard.
///
/// **This is the half of copying out of a diff most likely to be quietly
/// wrong** — off by one at a row boundary, a pair given backwards, a selection
/// ending at the very start of a row, an empty row in the middle — and it is
/// arithmetic over strings, so it lives here where a test can hold it. The view
/// hands it the text of the rows the selection covers and asks; it knows nothing
/// about geometry, AppKit, or what a row looked like.
///
/// **What it produces is code, not a diff**: no line number, no `+`/`-` marker
/// and no gutter. That is the caller's half of the bargain — `rows` is what a
/// row *says* — and it is what makes a selection copy the same characters
/// whether the diff is drawn unified or side by side, the second of which draws
/// no marker at all.
public struct DiffTextSpan: Equatable, Sendable {
	/// The earlier end, whichever end the drag started at.
	public let start: DiffTextPoint
	/// The later end.
	public let end: DiffTextPoint
	/// The text of the rows from `start.row` to `end.row`, in the order drawn.
	///
	/// Only the covered rows, so a selection over five rows of a five-thousand
	/// row diff costs five strings. Fewer than the span covers is not an error:
	/// see `text`.
	public let rows: [String]

	/// Takes the two ends in either order and puts them in reading order.
	///
	/// **Ordered here rather than at the call site**, because a drag upwards is
	/// as ordinary as a drag downwards and every caller would otherwise have to
	/// remember it.
	public init(from: DiffTextPoint, to: DiffTextPoint, rows: [String]) {
		self.start = min(from, to)
		self.end = max(from, to)
		self.rows = rows
	}

	/// Whether it covers no characters at all — a press with no drag.
	public var isEmpty: Bool { start == end }

	/// How many rows it runs through, counting both ends.
	public var rowCount: Int { end.row - start.row + 1 }

	/// What the clipboard would hold: the first row cut at its offset, the last
	/// row cut at its offset, the whole of everything between, joined by one
	/// newline.
	///
	/// A span whose rows have gone — fewer strings than it covers, because the
	/// diff was rebuilt under it — gives what is there rather than trapping or
	/// inventing blank lines. The view drops its selection on a rebuild, so this
	/// is a belt beside that brace.
	public var text: String {
		guard !rows.isEmpty else { return "" }
		let taken = rows.prefix(rowCount)
		guard taken.count > 1 else {
			return slice(taken[taken.startIndex], from: start.offset, to: end.offset)
		}

		var lines: [String] = [slice(taken[taken.startIndex], from: start.offset, to: .max)]
		lines += taken.dropFirst().dropLast()
		// The last row is cut at the offset only when it really is the row the
		// selection ends on. Where the rows ran out, the one that is there is
		// whole — its offset belongs to a row nobody has.
		if taken.count == rowCount {
			lines.append(slice(taken[taken.index(before: taken.endIndex)], from: 0, to: end.offset))
		} else {
			lines.append(taken[taken.index(before: taken.endIndex)])
		}
		return lines.joined(separator: "\n")
	}

	/// A row's text between two UTF-16 offsets, either of which may be past
	/// either end of it.
	///
	/// Clamped rather than trusted: an offset arrives from a hit test against a
	/// row that may since have been redrawn shorter, and a crash is not what a
	/// stale selection should cost.
	private func slice(_ text: String, from lower: Int, to upper: Int) -> String {
		let units = Array(text.utf16)
		let low = min(max(0, lower), units.count)
		let high = min(max(low, upper), units.count)
		guard low < high else { return "" }
		return String(decoding: units[low..<high], as: UTF16.self)
	}
}

import Foundation

/// A cell in the terminal's total line space: scrollback first, then the screen.
///
/// Rows are absolute rather than viewport-relative so a selection survives
/// scrolling, which is the whole point of selecting text that has scrolled off.
public struct TerminalPosition: Equatable, Comparable, Sendable {
	public var row: Int
	public var column: Int

	public init(row: Int, column: Int) {
		self.row = row
		self.column = column
	}

	public static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
	}
}

/// A range of cells, held as the point the drag started from and the point it
/// currently reaches, so dragging backwards works without special-casing.
public struct TerminalSelection: Equatable, Sendable {
	public var anchor: TerminalPosition
	public var head: TerminalPosition

	public init(anchor: TerminalPosition, head: TerminalPosition) {
		self.anchor = anchor
		self.head = head
	}

	public var isEmpty: Bool { anchor == head }

	/// The end points in reading order.
	public var ordered: (start: TerminalPosition, end: TerminalPosition) {
		anchor <= head ? (anchor, head) : (head, anchor)
	}

	/// The selected column range on one row, or nil when the row is outside it.
	///
	/// The upper bound is exclusive, and rows in the middle of a multi-row
	/// selection run to `columns` so the highlight reaches the right edge the
	/// way a text selection does.
	public func columnRange(onRow row: Int, columns: Int) -> Range<Int>? {
		let (start, end) = ordered
		guard row >= start.row, row <= end.row, !isEmpty else { return nil }

		// Clamped before the range is formed, not after: a selection made while
		// the grid was wider outlives the resize, and `from > columns` would
		// otherwise build a range with its bounds the wrong way round and trap.
		let from = min(max(0, row == start.row ? start.column : 0), columns)
		let to = min(max(0, row == end.row ? end.column : columns), columns)
		guard from < to else { return nil }
		return from..<to
	}
}

public extension TerminalLine {
	/// The characters in a column range, with trailing blanks trimmed.
	func text(in range: Range<Int>) -> String {
		let clamped = max(0, range.lowerBound)..<min(cells.count, range.upperBound)
		guard clamped.lowerBound < clamped.upperBound else { return "" }

		var result = ""
		for index in clamped where !cells[index].isWideTrailer {
			if let combining = cells[index].combining {
				result += combining
			} else if let scalar = UnicodeScalar(cells[index].scalar) {
				result.unicodeScalars.append(scalar)
			}
		}
		while result.hasSuffix(" ") { result.removeLast() }
		return result
	}

	/// Characters that count as part of a word for double-click selection.
	///
	/// Includes the path punctuation, because in a terminal the thing you
	/// double-click is usually a path or a URL and splitting it at every dot
	/// would make the gesture useless.
	private static let wordCharacters = CharacterSet.alphanumerics
		.union(CharacterSet(charactersIn: "_-./~:@+"))

	private func isWordCharacter(at index: Int) -> Bool {
		guard cells.indices.contains(index) else { return false }
		guard cells[index].combining == nil,
		      let scalar = UnicodeScalar(cells[index].scalar)
		else { return true }              // Anything exotic is treated as a word.
		return Self.wordCharacters.contains(scalar)
	}

	/// The word around a column, for double-click. Nil on whitespace.
	func wordRange(around column: Int) -> Range<Int>? {
		guard cells.indices.contains(column), isWordCharacter(at: column) else { return nil }

		var start = column
		while start > 0, isWordCharacter(at: start - 1) { start -= 1 }

		var end = column + 1
		while end < cells.count, isWordCharacter(at: end) { end += 1 }

		return start..<end
	}
}

/// Reading a grid: selection, and the two gestures that make one.
///
/// **On `TerminalGridReading` rather than on `TerminalScreen`** (item 0485).
/// Every body below is written in terms of `line(at:)` and `totalLineCount` and
/// nothing else, so widening the extension gives both engines one
/// implementation instead of two — and it is what let the six `emulator.screen`
/// call sites in `TerminalView` become `emulator.grid`. Not one line of any body
/// changed when it moved; `TerminalScreen` conforms, so every existing caller
/// still resolves exactly what it used to.
public extension TerminalGridReading {
	/// Total number of rows, scrollback included.
	var selectableRowCount: Int { totalLineCount }

	/// The selected text, with one newline per row.
	func text(in selection: TerminalSelection) -> String {
		let (start, end) = selection.ordered
		guard !selection.isEmpty, start.row <= end.row else { return "" }

		var rows: [String] = []
		for row in start.row...end.row {
			guard let line = line(at: row) else { continue }
			guard let range = selection.columnRange(onRow: row, columns: line.cells.count) else {
				rows.append("")
				continue
			}
			rows.append(line.text(in: range))
		}
		return rows.joined(separator: "\n")
	}

	/// Selection covering the word at a position, for a double-click.
	func wordSelection(atRow row: Int, column: Int) -> TerminalSelection? {
		guard let line = line(at: row), let range = line.wordRange(around: column) else { return nil }
		return TerminalSelection(
			anchor: TerminalPosition(row: row, column: range.lowerBound),
			head: TerminalPosition(row: row, column: range.upperBound)
		)
	}

	/// Selection covering a whole row, for a triple-click.
	func lineSelection(atRow row: Int) -> TerminalSelection? {
		guard let line = line(at: row) else { return nil }
		return TerminalSelection(
			anchor: TerminalPosition(row: row, column: 0),
			head: TerminalPosition(row: row, column: line.cells.count)
		)
	}

	/// Everything in the buffer, for Select All.
	var fullSelection: TerminalSelection? {
		guard totalLineCount > 0, let last = line(at: totalLineCount - 1) else { return nil }
		return TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: totalLineCount - 1, column: last.cells.count)
		)
	}

	/// The last few lines that say something.
	///
	/// Used to show that a long-running agent is alive without making the user
	/// switch to its terminal: a status message it chooses to send is sparse,
	/// but its output moves continuously.
	///
	/// Lines made only of frame — box drawing, rules, a bare prompt character —
	/// are skipped. A full-screen TUI keeps its input box pinned to the bottom,
	/// so the last non-blank lines are its borders, and a tail of those tells
	/// you nothing about whether anything is happening.
	func recentLines(_ count: Int) -> [String] {
		guard count > 0 else { return [] }
		var result: [String] = []
		var index = totalLineCount - 1
		while index >= 0, result.count < count {
			if let line = line(at: index) {
				let text = line.text.trimmingCharacters(in: .whitespaces)
				if Self.isSubstantive(text) { result.append(text) }
			}
			index -= 1
		}
		return result.reversed()
	}

	/// Whether a line carries words rather than decoration.
	static func isSubstantive(_ text: String) -> Bool {
		text.unicodeScalars.contains {
			CharacterSet.alphanumerics.contains($0)
		}
	}
}

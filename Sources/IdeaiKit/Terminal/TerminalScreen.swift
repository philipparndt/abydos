import Foundation

/// A colour in terminal terms: default, one of the 16 named, 256-palette, or
/// true colour. Kept as an enum rather than resolved to RGB here so the theme
/// decides what "red" actually looks like.
public enum TerminalColor: Equatable, Sendable {
	case `default`
	case indexed(UInt8)
	case rgb(UInt8, UInt8, UInt8)
}

public struct TerminalAttributes: Equatable, Sendable {
	public var foreground: TerminalColor = .default
	public var background: TerminalColor = .default
	public var bold = false
	public var dim = false
	public var italic = false
	public var underline = false
	public var inverse = false
	public var strikethrough = false
	public var hidden = false

	public init() {}

	/// Applies inverse by swapping, so the renderer never has to know about it.
	public var resolved: (foreground: TerminalColor, background: TerminalColor) {
		inverse ? (background, foreground) : (foreground, background)
	}
}

/// One character cell.
public struct TerminalCell: Equatable, Sendable {
	/// The character shown. A space for empty cells.
	public var character: Character
	public var attributes: TerminalAttributes
	/// Second half of a double-width character; drawn as nothing, but occupies
	/// a column so the grid stays aligned.
	public var isWideTrailer: Bool

	public init(character: Character = " ", attributes: TerminalAttributes = .init(), isWideTrailer: Bool = false) {
		self.character = character
		self.attributes = attributes
		self.isWideTrailer = isWideTrailer
	}

	public static let blank = TerminalCell()
}

/// One row of cells.
public struct TerminalLine: Equatable, Sendable {
	public var cells: [TerminalCell]

	public init(columns: Int) {
		cells = Array(repeating: .blank, count: max(0, columns))
	}

	public mutating func resize(to columns: Int) {
		if columns < cells.count {
			cells.removeLast(cells.count - columns)
		} else if columns > cells.count {
			cells.append(contentsOf: Array(repeating: .blank, count: columns - cells.count))
		}
	}

	/// True when nothing has been written to the line.
	///
	/// Used by a resize to decide which end to take rows from: an untouched line
	/// at the bottom can be discarded, real content at the top cannot.
	public var isBlank: Bool {
		cells.allSatisfy { $0 == .blank }
	}

	/// Trailing blanks trimmed, for text extraction and selection.
	public var text: String {
		var result = ""
		for cell in cells where !cell.isWideTrailer {
			result.append(cell.character)
		}
		while result.hasSuffix(" ") { result.removeLast() }
		return result
	}
}

/// The visible grid plus scrollback.
///
/// Scrollback is a plain array of completed lines: a terminal only ever appends
/// to it and reads a window out of it, so the rope machinery the editor needs
/// would buy nothing here.
public struct TerminalScreen: Sendable {
	public private(set) var rows: Int
	public private(set) var columns: Int

	/// The active grid, `rows` tall.
	public private(set) var lines: [TerminalLine]
	/// Completed lines that scrolled off the top.
	public private(set) var scrollback: [TerminalLine] = []

	/// Lines dropped off the top of scrollback since the screen was created.
	///
	/// Absolute row indices are stable while the buffer grows, but every
	/// discarded line shifts them, and anything holding one — a selection —
	/// needs to know by how much.
	public private(set) var discardedLineCount = 0

	public var maximumScrollback = 5_000

	public init(rows: Int, columns: Int) {
		let clampedRows = max(1, rows)
		let clampedColumns = max(1, columns)
		self.rows = clampedRows
		self.columns = clampedColumns
		self.lines = (0..<clampedRows).map { _ in TerminalLine(columns: clampedColumns) }
	}

	public var totalLineCount: Int { scrollback.count + lines.count }

	/// Indexes scrollback and the active grid as one continuous buffer, which is
	/// what the view scrolls through.
	public func line(at index: Int) -> TerminalLine? {
		if index < 0 { return nil }
		if index < scrollback.count { return scrollback[index] }
		let active = index - scrollback.count
		return active < lines.count ? lines[active] : nil
	}

	public subscript(row: Int) -> TerminalLine {
		get { lines[row] }
		set { lines[row] = newValue }
	}

	// MARK: - Mutation

	/// Writes a run of printable ASCII into one row.
	///
	/// The run is known to fit: the caller has already cut it to the row.
	public mutating func setASCII(
		row: Int,
		column: Int,
		bytes: UnsafeBufferPointer<UInt8>,
		from start: Int,
		count: Int,
		attributes: TerminalAttributes
	) {
		guard row >= 0, row < rows, column >= 0, column + count <= columns else { return }
		lines[row].cells.withUnsafeMutableBufferPointer { cells in
			for offset in 0..<count {
				cells[column + offset] = TerminalCell(
					character: Character(UnicodeScalar(bytes[start + offset])),
					attributes: attributes
				)
			}
		}
	}

	public mutating func setCell(row: Int, column: Int, cell: TerminalCell) {
		guard row >= 0, row < rows, column >= 0, column < columns else { return }
		lines[row].cells[column] = cell
	}

	/// Scrolls the region [top, bottom] up by one, pushing the top line into
	/// scrollback when the region is the whole screen.
	public mutating func scrollUp(top: Int, bottom: Int, attributes: TerminalAttributes) {
		guard top >= 0, bottom < rows, top <= bottom else { return }

		let retired = lines[top]
		// Only a full-height region represents lines leaving the screen; a
		// restricted scroll region is an application redrawing in place.
		if top == 0 && bottom == rows - 1 {
			scrollback.append(retired)
			if scrollback.count > maximumScrollback {
				let dropped = scrollback.count - maximumScrollback
				scrollback.removeFirst(dropped)
				discardedLineCount += dropped
			}
		}

		for row in top..<bottom {
			lines[row] = lines[row + 1]
		}
		lines[bottom] = blankLine(attributes: attributes)
	}

	public mutating func scrollDown(top: Int, bottom: Int, attributes: TerminalAttributes) {
		guard top >= 0, bottom < rows, top <= bottom else { return }
		var row = bottom
		while row > top {
			lines[row] = lines[row - 1]
			row -= 1
		}
		lines[top] = blankLine(attributes: attributes)
	}

	public func blankLine(attributes: TerminalAttributes) -> TerminalLine {
		var line = TerminalLine(columns: columns)
		// Erasure carries the current background, which is how full-width
		// coloured bars are drawn.
		if attributes.background != .default {
			var cell = TerminalCell.blank
			cell.attributes.background = attributes.background
			line.cells = Array(repeating: cell, count: columns)
		}
		return line
	}

	// MARK: - Resize

	/// Resizes the grid.
	///
	/// Growing taller pulls lines back out of scrollback rather than padding with
	/// blanks, so widening a window does not leave a band of empty rows above
	/// output that is still on screen.
	/// Resizes the grid, returning how far the cursor's row moved.
	///
	/// Rows are added and removed at whichever end preserves what is on screen.
	/// Shrinking discards untouched lines below the cursor before retiring real
	/// content off the top; growing pulls history back down from scrollback,
	/// which pushes everything below it further down.
	///
	/// Both of those shift the cursor's row, and the caller **must** apply the
	/// returned delta. A shell redraws its prompt at the cursor after SIGWINCH,
	/// so a cursor left pointing at the wrong line writes the new prompt over
	/// unrelated output, which reads as duplicated content.
	@discardableResult
	public mutating func resize(rows newRows: Int, columns newColumns: Int, cursorRow: Int = 0) -> Int {
		let newRows = max(1, newRows)
		let newColumns = max(1, newColumns)
		guard newRows != rows || newColumns != columns else { return 0 }

		if newColumns != columns {
			for index in lines.indices { lines[index].resize(to: newColumns) }
			for index in scrollback.indices { scrollback[index].resize(to: newColumns) }
		}
		columns = newColumns

		var cursorDelta = 0

		if newRows < rows {
			let excess = rows - newRows

			// Blank lines below the cursor are space the shell has not used yet,
			// so they go first. Taking from the top instead would push the visible
			// prompt — and everything above it — into scrollback, which is the
			// "previous lines disappeared" case.
			var fromBottom = 0
			var index = lines.count - 1
			while fromBottom < excess, index > cursorRow, lines[index].isBlank {
				fromBottom += 1
				index -= 1
			}
			lines.removeLast(fromBottom)

			let fromTop = excess - fromBottom
			if fromTop > 0 {
				scrollback.append(contentsOf: lines.prefix(fromTop))
				lines.removeFirst(fromTop)
				if scrollback.count > maximumScrollback {
					let dropped = scrollback.count - maximumScrollback
				scrollback.removeFirst(dropped)
				discardedLineCount += dropped
				}
				cursorDelta = -fromTop
			}
		} else if newRows > rows {
			var needed = newRows - rows
			while needed > 0, let recovered = scrollback.popLast() {
				lines.insert(recovered, at: 0)
				needed -= 1
				cursorDelta += 1
			}
			while needed > 0 {
				lines.append(TerminalLine(columns: newColumns))
				needed -= 1
			}
		}
		rows = newRows
		return cursorDelta
	}

	/// Plain text of the whole buffer, used for copy and for feeding an agent's
	/// output to a parser.
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
	public func recentLines(_ count: Int) -> [String] {
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

	public func allText() -> String {
		(scrollback + lines).map(\.text).joined(separator: "\n")
	}
}

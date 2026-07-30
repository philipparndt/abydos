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
				scrollback.removeFirst(scrollback.count - maximumScrollback)
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
	public mutating func resize(rows newRows: Int, columns newColumns: Int) {
		let newRows = max(1, newRows)
		let newColumns = max(1, newColumns)
		guard newRows != rows || newColumns != columns else { return }

		if newColumns != columns {
			for index in lines.indices { lines[index].resize(to: newColumns) }
			for index in scrollback.indices { scrollback[index].resize(to: newColumns) }
		}
		columns = newColumns

		if newRows < rows {
			// Retire lines from the top so the cursor's neighbourhood survives.
			let excess = rows - newRows
			scrollback.append(contentsOf: lines.prefix(excess))
			lines.removeFirst(excess)
			if scrollback.count > maximumScrollback {
				scrollback.removeFirst(scrollback.count - maximumScrollback)
			}
		} else if newRows > rows {
			var needed = newRows - rows
			while needed > 0, let recovered = scrollback.popLast() {
				lines.insert(recovered, at: 0)
				needed -= 1
			}
			while needed > 0 {
				lines.append(TerminalLine(columns: newColumns))
				needed -= 1
			}
		}
		rows = newRows
	}

	/// Plain text of the whole buffer, used for copy and for feeding an agent's
	/// output to a parser.
	public func allText() -> String {
		(scrollback + lines).map(\.text).joined(separator: "\n")
	}
}

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
	/// Which hyperlink this cell belongs to, or 0 for none.
	///
	/// A number rather than the address itself: a link covers a run of cells
	/// and the same one often covers several runs, and a string per cell would
	/// cost more than the text does. The emulator keeps the table.
	public var link: UInt16 = 0

	public init() {}

	/// Applies inverse by swapping, so the renderer never has to know about it.
	public var resolved: (foreground: TerminalColor, background: TerminalColor) {
		inverse ? (background, foreground) : (foreground, background)
	}
}

/// One character cell.
public struct TerminalCell: Equatable, Sendable {
	/// The code point shown; a space for an empty cell.
	///
	/// A number rather than a `Character`. Building a Character means building a
	/// String, with the grapheme breaking that implies, and doing that once per
	/// cell written was the largest single cost of filling the grid — non-ASCII
	/// text ran at a third the speed of ASCII purely because of it.
	public var scalar: UInt32
	/// The whole grapheme cluster, on the rare cell that is more than its base
	/// code point — a letter with a combining accent, an emoji sequence. Nil
	/// everywhere else, which is almost everywhere.
	public var combining: String?
	public var attributes: TerminalAttributes
	/// Second half of a double-width character; drawn as nothing, but occupies
	/// a column so the grid stays aligned.
	public var isWideTrailer: Bool

	public init(
		scalar: UInt32,
		attributes: TerminalAttributes = .init(),
		isWideTrailer: Bool = false
	) {
		self.scalar = scalar
		self.combining = nil
		self.attributes = attributes
		self.isWideTrailer = isWideTrailer
	}

	public init(
		character: Character = " ",
		attributes: TerminalAttributes = .init(),
		isWideTrailer: Bool = false
	) {
		self.attributes = attributes
		self.isWideTrailer = isWideTrailer
		self.scalar = 0
		self.combining = nil
		self.character = character
	}

	/// What to draw, assembled from the parts above.
	public var character: Character {
		get {
			if let combining, let first = combining.first { return first }
			guard let base = UnicodeScalar(scalar) else { return " " }
			return Character(base)
		}
		set {
			var scalars = newValue.unicodeScalars.makeIterator()
			let base = scalars.next() ?? " "
			scalar = base.value
			// Only a cluster needs the string; a lone code point is the number.
			combining = scalars.next() == nil ? nil : String(newValue)
		}
	}

	public static let blank = TerminalCell(scalar: 0x20)

	/// Overwrites this cell with a single code point, field by field.
	///
	/// Not `cell = TerminalCell(scalar:attributes:)`, and the difference is the
	/// whole reason this exists. `combining` is a `String?`, so a `TerminalCell`
	/// is not a plain value as far as the compiler is concerned: assigning one
	/// destroys the old cell and copies the new one through outlined value
	/// witnesses, each releasing and retaining a string that is nil in
	/// essentially every cell a terminal ever holds. Filling a row that way
	/// cost two hundred reference-counting calls for a hundred columns of
	/// text.
	///
	/// Written a field at a time it is four stores and, when the cell being
	/// overwritten had no cluster on it, a pointer comparison — no reference
	/// counting at all. `initializeWithCopy for TerminalCell` and `outlined
	/// destroy of TerminalCell` were the top two entries in a profile of the
	/// parser reading ordinary log output; this is what they were.
	mutating func write(scalar: UInt32, attributes: TerminalAttributes, isWideTrailer: Bool = false) {
		// Checked rather than cleared: nil is what it almost always already is,
		// and assigning nil over nil is still a release.
		if combining != nil { combining = nil }
		self.scalar = scalar
		self.attributes = attributes
		self.isWideTrailer = isWideTrailer
	}
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
			if let combining = cell.combining {
				result += combining
			} else if let scalar = UnicodeScalar(cell.scalar) {
				result.unicodeScalars.append(scalar)
			}
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
	public private(set) var scrollback: ScrollbackBuffer

	/// Lines dropped off the top of scrollback since the screen was created.
	///
	/// Absolute row indices are stable while the buffer grows, but every
	/// discarded line shifts them, and anything holding one — a selection —
	/// needs to know by how much.
	public private(set) var discardedLineCount = 0

	/// Lines whose contents changed since the view last drew, as absolute
	/// indices into scrollback-plus-grid.
	///
	/// Absolute rather than grid rows because a line keeps its place in the
	/// document as history grows: scrolling adds a line at the bottom instead of
	/// moving everything up, so printing a line dirties one row rather than all
	/// of them. Nil means nothing changed; the whole document is marked when
	/// something moves that cannot be described as a range.
	public private(set) var dirtyRange: ClosedRange<Int>?

	/// Marks grid rows as needing to be drawn again.
	public mutating func markDirty(rows: ClosedRange<Int>) {
		let base = scrollback.count
		markDirty(absolute: (base + rows.lowerBound)...(base + rows.upperBound))
	}

	public mutating func markDirty(absolute range: ClosedRange<Int>) {
		guard let existing = dirtyRange else {
			dirtyRange = range
			return
		}
		let low = Swift.min(existing.lowerBound, range.lowerBound)
		let high = Swift.max(existing.upperBound, range.upperBound)
		dirtyRange = low...high
	}

	/// Everything, for the changes that move lines rather than rewrite them.
	public mutating func markAllDirty() {
		markDirty(absolute: 0...Swift.max(0, totalLineCount))
	}

	/// Hands over what changed and starts again, which is what drawing does.
	public mutating func takeDirtyRange() -> ClosedRange<Int>? {
		defer { dirtyRange = nil }
		return dirtyRange
	}

	/// How much history is kept. Changing it resizes the ring, dropping the
	/// oldest lines if it shrank.
	public var maximumScrollback: Int {
		get { scrollback.capacity }
		set { scrollback.setCapacity(newValue) }
	}

	public init(rows: Int, columns: Int, maximumScrollback: Int = 5_000) {
		let clampedRows = max(1, rows)
		let clampedColumns = max(1, columns)
		self.rows = clampedRows
		self.columns = clampedColumns
		self.lines = (0..<clampedRows).map { _ in TerminalLine(columns: clampedColumns) }
		self.scrollback = ScrollbackBuffer(capacity: maximumScrollback)
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
		set {
			lines[row] = newValue
			markDirty(rows: row...row)
		}
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
		markDirty(rows: row...row)
		lines[row].cells.withUnsafeMutableBufferPointer { cells in
			for offset in 0..<count {
				cells[column + offset].write(
					scalar: UInt32(bytes[start + offset]),
					attributes: attributes
				)
			}
		}
	}

	public mutating func setCell(row: Int, column: Int, cell: TerminalCell) {
		guard row >= 0, row < rows, column >= 0, column < columns else { return }
		markDirty(rows: row...row)
		lines[row].cells[column] = cell
	}

	/// Writes one code point into a cell, keeping no cluster on it.
	///
	/// The same thing as `setCell` with a freshly built cell, without paying
	/// for the copy — see `TerminalCell.write`.
	public mutating func setScalar(
		row: Int,
		column: Int,
		scalar: UInt32,
		attributes: TerminalAttributes,
		isWideTrailer: Bool = false
	) {
		guard row >= 0, row < rows, column >= 0, column < columns else { return }
		markDirty(rows: row...row)
		lines[row].cells.withUnsafeMutableBufferPointer { cells in
			cells[column].write(scalar: scalar, attributes: attributes, isWideTrailer: isWideTrailer)
		}
	}

	/// Scrolls the region [top, bottom] up by one, pushing the top line into
	/// scrollback when the region is the whole screen.
	public mutating func scrollUp(top: Int, bottom: Int, attributes: TerminalAttributes) {
		guard top >= 0, bottom < rows, top <= bottom else { return }
		// A region that is not the whole screen moves its lines within the grid,
		// so all of them have to be drawn again.
		if !(top == 0 && bottom == rows - 1) { markDirty(rows: top...bottom) }

		let retired = lines[top]
		// The line that fell out of the far end of history, whose storage the
		// blank line arriving at the bottom of the screen can have.
		//
		// A scroll retires the top line into history and needs a blank one at
		// the bottom, and once history is full — which is where a terminal
		// spends almost all of its life — a line falls out of the other end at
		// the same moment. It is the right length and nothing refers to it any
		// more, so the blank line is written over it rather than a new array
		// being allocated and the old one freed.
		//
		// `TerminalCell` carries a `String?`, so neither of those is cheap: the
		// allocation copies every cell one at a time and the free destroys
		// every cell one at a time. Together they were **most of what it cost
		// this emulator to read plain log output** — a line of text scrolls
		// once per fifty bytes, where a screen of colour changes scrolls once
		// per fifteen hundred, which is why plain output measured six times
		// slower than the path that parses an escape sequence per cell.
		//
		// `ScrollbackBuffer.append` has handed the displaced line back for
		// exactly this since it was written, and says so in its own comment.
		// Nothing took it until now.
		var recycled: TerminalLine?
		// Only a full-height region represents lines leaving the screen; a
		// restricted scroll region is an application redrawing in place.
		if top == 0 && bottom == rows - 1 {
			if let evicted = scrollback.append(retired) {
				discardedLineCount += 1
				recycled = evicted
				// Every absolute index just shifted by one, so nothing is where
				// the view last drew it.
				markAllDirty()
			} else {
				// The retired line keeps its index and its contents; only the
				// blank line arriving at the bottom is new.
				markDirty(absolute: (scrollback.count + rows - 1)...(scrollback.count + rows - 1))
			}
		}

		for row in top..<bottom {
			lines[row] = lines[row + 1]
		}

		// The evicted line goes into the slot *before* it is blanked, and the
		// local reference to it is dropped, so that the grid is its only owner
		// when the blanking runs. Passing it to something that blanks it and
		// hands it back would leave two references to the same storage for as
		// long as the call lasts, and an array with two references copies
		// itself before it is written to — which measured *slower* than
		// allocating a fresh line, the thing this is here to avoid.
		if recycled?.cells.count == columns {
			lines[bottom] = recycled.unsafelyUnwrapped
			recycled = nil
			blank(row: bottom, columns: 0..<columns, attributes: attributes)
		} else {
			lines[bottom] = blankLine(attributes: attributes)
		}
	}

	/// Writes blanks over part of a row already in the grid, in place.
	///
	/// The whole erase family goes through this rather than assigning cell by
	/// cell through `subscript(row:)`. That subscript has a getter and a setter
	/// and no `_modify`, so `screen[row].cells[column] = blank` is a read of the
	/// whole line, a mutation, and a write back — and while the getter's copy is
	/// alive the line's storage has two owners, so the mutation **copies every
	/// cell in the row**. A loop over the columns therefore cost a hundred
	/// copies of a hundred cells to erase one line of a hundred columns, and
	/// marked the row dirty a hundred times over on the way.
	public mutating func blank(row: Int, columns range: Range<Int>, attributes: TerminalAttributes) {
		guard row >= 0, row < rows else { return }
		let range = range.clamped(to: 0..<columns)
		guard !range.isEmpty else { return }
		markDirty(rows: row...row)
		// Erasure carries the current background, which is how full-width
		// coloured bars are drawn, and nothing else about the attributes.
		var blank = TerminalAttributes()
		blank.background = attributes.background
		lines[row].cells.withUnsafeMutableBufferPointer { cells in
			// Field by field, for the reason `TerminalCell.write` gives.
			for index in range.clamped(to: cells.indices) {
				cells[index].write(scalar: 0x20, attributes: blank)
			}
		}
	}

	public mutating func scrollDown(top: Int, bottom: Int, attributes: TerminalAttributes) {
		guard top >= 0, bottom < rows, top <= bottom else { return }
		markDirty(rows: top...bottom)
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
		markAllDirty()
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
				for line in lines.prefix(fromTop) {
					if scrollback.append(line) != nil { discardedLineCount += 1 }
				}
				lines.removeFirst(fromTop)
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
	// `recentLines` and `isSubstantive` used to be here. They moved to the
	// `TerminalGridReading` extension in `TerminalSelection.swift` for item
	// 0485, unchanged, so that both engines have them; `TerminalScreen`
	// conforms, so `screen.recentLines(3)` and `TerminalScreen.isSubstantive`
	// still resolve to exactly the same code.

	public func allText() -> String {
		(Array(scrollback) + lines).map(\.text).joined(separator: "\n")
	}
}

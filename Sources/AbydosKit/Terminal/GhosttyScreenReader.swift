import Foundation
import GhosttyVt

/// What reading the screen needs of the terminal it is reading.
///
/// A named seam rather than the whole engine: five things the reader copies
/// cells through, and the one thing it has to say back — that pruning
/// renumbered every absolute row, so the whole document is dirty.
protocol GhosttyScreen: AnyObject {
	var screenTerminal: GhosttyTerminal? { get }
	var screenRenderState: GhosttyRenderState? { get }
	var screenRows: Int { get }
	var screenColumns: Int { get }
	/// How many times the terminal has been written to, which is what stamps a
	/// snapshot and what tells a stale one from a current one.
	var screenWriteCount: Int { get }
	func screenNoteDirty(_ range: ClosedRange<Int>)
}

/// libghostty-vt's screen, read out into this app's grid.
///
/// This is the half of the engine that owns state of its own rather than the
/// library's: the anchor that counts pruned lines, the snapshot cache a frame
/// reads twenty times, the table URIs are interned into, and the record of
/// which of the two read paths last answered. None of it is the terminal's — it
/// exists because the terminal reports absolute indices that move, hands back
/// URIs where our cells carry numbers, and offers two APIs for the same rows
/// with very different costs.
///
/// It is a collaborator and not an extension for exactly that reason: the state
/// is its own, and the engine asks it questions rather than reaching into it.
final class GhosttyScreenReader {
	/// The terminal this reads, which owns this reader.
	private unowned let screen: GhosttyScreen

	init(of screen: GhosttyScreen) { self.screen = screen }

	private var terminal: GhosttyTerminal? { screen.screenTerminal }
	private var renderState: GhosttyRenderState? { screen.screenRenderState }
	private var rows: Int { screen.screenRows }
	private var columns: Int { screen.screenColumns }
	private var writeCount: Int { screen.screenWriteCount }
	private func note(dirty range: ClosedRange<Int>) { screen.screenNoteDirty(range) }
	/// What a snapshot was stamped with, so one made before a write refuses to
	/// answer for rows it can no longer have been describing.
	var currentWriteCount: Int { writeCount }

	// MARK: - Hyperlinks

	/// Hyperlink addresses, interned so a cell can carry a `UInt16` the way ours
	/// does.
	///
	/// libghostty-vt hands back the URI itself (`grid_ref_hyperlink_uri`) rather
	/// than an index, which is the better shape — but `TerminalCell.attributes`
	/// has a `UInt16` and the renderer, the hover cursor and `link(for:)` are all
	/// written to it. So the snapshot interns, and this is the table. It only ever
	/// grows: a URI that has left the screen may still be under a selection made
	/// before it did.
	private var links: [String] = []
	private var linkIndex: [String: UInt16] = [:]

	func link(for id: UInt16) -> String? {
		guard id > 0, Int(id) <= links.count else { return nil }
		return links[Int(id) - 1]
	}

	/// The id a URI is known by, assigning one the first time it is seen.
	private func internedLink(_ uri: String) -> UInt16 {
		if let existing = linkIndex[uri] { return existing }
		// 0 means "no link", so ids start at 1 — the same numbering ours uses.
		guard links.count < Int(UInt16.max) else { return 0 }
		links.append(uri)
		let id = UInt16(links.count)
		linkIndex[uri] = id
		return id
	}

	// `size_t`, not `uint32_t`. Every one of these output types is documented in
	// the header and getting one wrong is a silent stack write of the wrong
	// width, which is exactly the kind of bug that passes its tests: the first
	// draft of this file read both of these into a `UInt32` and the suite was
	// green.
	var totalLineCount: Int {
		guard let terminal else { return rows }
		var total = 0
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &total) == GHOSTTY_SUCCESS
		else { return rows }
		return total
	}

	/// Lines that have fallen off the top for good.
	///
	/// **libghostty-vt does not report this**, which 0474 named as the one thing
	/// genuinely missing. It prunes its own scrollback and says nothing about how
	/// much it threw away, so absolute indices from an older frame could not be
	/// told apart from current ones and the engine used to answer 0 — which the
	/// `unimplemented` list had to admit made the scrollbar and selection
	/// realignment wrong.
	///
	/// The answer is the tracked grid reference the header points at: it "follows
	/// its cell across … scrolling, scrollback pruning, resize/reflow". So an
	/// anchor is pinned to the bottom row after every write, and how far its
	/// absolute index has *fallen* between two writes is exactly how many lines
	/// were pruned in between. Re-anchoring each time keeps the anchor inside the
	/// active grid, where nothing can prune it.
	///
	/// The one case it cannot be exact about, stated rather than hidden: a single
	/// write that scrolls so far that the anchor itself is pruned. Then the anchor
	/// reports no value, and all that is known is that *at least* everything up to
	/// it went, so that lower bound is what gets added. The count is then low, and
	/// the visible consequence is a selection made before the burst sitting a few
	/// rows off. Ours is exact here because it does its own pruning and can count.
	private(set) var discardedLineCount = 0

	/// The anchor, and the absolute index it was at when it was last set.
	private var anchor: GhosttyTrackedGridRef?
	private var anchorIndex = 0

	/// Frees the anchor, which the engine does from its own `deinit`.
	///
	/// Not this object's `deinit`, because the order matters and this object does
	/// not control it: a tracked reference may outlive its terminal, but freeing
	/// it while the terminal is still there is the documented order, and the
	/// terminal is the engine's.
	func releaseAnchor() {
		if let anchor { ghostty_tracked_grid_ref_free(anchor) }
		anchor = nil
	}

	func updateDiscardedLineCount() {
		guard let terminal else { return }
		let bottom = max(0, totalLineCount - 1)

		if let anchor {
			var coordinate = GhosttyPointCoordinate()
			var pruned = 0
			if ghostty_tracked_grid_ref_point(anchor, GHOSTTY_POINT_TAG_SCREEN, &coordinate)
				== GHOSTTY_SUCCESS {
				// Its index can only have gone *down*, and only by pruning.
				pruned = max(0, anchorIndex - Int(coordinate.y))
			} else {
				// Gone. At least everything up to and including it was pruned.
				pruned = anchorIndex + 1
			}
			discardedLineCount += pruned
			// A line leaving history renumbers every absolute row, and
			// `TerminalDirtyRows` unions ranges taken at different moments as absolute
			// rows — which is only sound because the moment of renumbering is also a
			// moment the whole document is marked.
			// `TerminalDirtyRangeTests.aDiscardedLineDirtiesEverything` asserts that of
			// our engine; this is the same promise from this one, and it has to be made
			// here rather than in `noteDirtyRows` because pruning is counted on the
			// parse path and the rows are read on the frame.
			if pruned > 0 { note(dirty: 0...bottom) }
		}

		var point = GhosttyPoint()
		point.tag = GHOSTTY_POINT_TAG_SCREEN
		point.value.coordinate.x = 0
		point.value.coordinate.y = UInt32(bottom)
		if let anchor {
			_ = ghostty_tracked_grid_ref_set(anchor, terminal, point)
		} else {
			var created: GhosttyTrackedGridRef?
			guard ghostty_terminal_grid_ref_track(terminal, point, &created) == GHOSTTY_SUCCESS
			else { return }
			anchor = created
		}
		anchorIndex = bottom
	}

	/// Shrinks the scrollback budget so a test can see pruning happen.
	///
	/// libghostty-vt's default byte budget is large enough that reaching it in a
	/// test would mean writing a hundred thousand lines, and the thing worth
	/// testing is the counting rather than the budget.
	func setScrollbackByteLimitForTesting(_ bytes: Int) {
		guard let terminal else { return }
		var limit = bytes
		ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, &limit)
	}

	var scrollbackCount: Int {
		guard let terminal else { return 0 }
		var back = 0
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &back) == GHOSTTY_SUCCESS
		else { return 0 }
		return back
	}

	/// A snapshot: the visible rows copied, the scrollback fetched if asked for.
	///
	/// The protocol promises a grid that survives later writes, and
	/// libghostty-vt's grid references explicitly do not: an untracked reference
	/// "is only valid until the next update to the terminal instance … even if a
	/// seemingly unrelated part of the grid is changed". So the rows have to be
	/// copied out while we hold the terminal.
	///
	/// **What changed for item 0485**: it used to copy *every* row. 0474 measured
	/// that at 4.372 ms a frame on a 40-row screen with 5,200 lines of history —
	/// 524,000 cells across FFI to draw forty rows — which gave back the 17× the
	/// parser wins. The cost is now O(viewport): the active grid is copied, and a
	/// row in scrollback is copied only when something asks for it, which happens
	/// when somebody scrolls up, drags a selection through history, or copies.
	///
	/// A row fetched late is fetched from a terminal that may have moved on, so
	/// `GhosttyGrid` records the write count it was made at and **refuses** —
	/// returns nil — rather than hand back a row from a different moment. In
	/// practice it never has to: the view snapshots and walks the snapshot inside
	/// one turn of the main queue, and writes happen on the same queue.
	/// The snapshot for the current state of the terminal, made once.
	///
	/// Cached because `TerminalView` reads `emulator.grid` about twenty times in a
	/// frame — for the row count, the column count, the scrollback offset, a line,
	/// the selection — and for our own engine every one of those is a retain of a
	/// value type. A fresh copy each time would multiply the per-frame cost by
	/// twenty and hide it behind an innocent-looking `.rows`. Thrown away by the
	/// next write, which is the only thing that can make it wrong.
	private var cachedGrid: GhosttyGrid?

	/// The snapshot, made once per write and handed out until the next one.
	///
	/// The engine brings the render state up to date before asking; this does not,
	/// because it is not the thing that knows when that is stale.
	var grid: TerminalGridReading {
		if let cachedGrid, cachedGrid.matches(writeCount: writeCount) { return cachedGrid }
		let scrollback = scrollbackCount
		let made = GhosttyGrid(
			rows: rows, columns: columns,
			totalLineCount: totalLineCount,
			scrollbackCount: scrollback,
			discardedLineCount: discardedLineCount,
			// The render state for the rows on screen, which is what a frame reads
			// and what its documentation says to use. `copyLines` — grid references
			// — remains for scrollback, which the render state does not cover and
			// which is not a render loop.
			visible: visibleRows(from: scrollback),
			source: self,
			writeCount: writeCount)
		cachedGrid = made
		return made
	}

	/// Whether the last read of the visible rows came from the render state.
	///
	/// A test asserts this, because the fallback below produces *identical* rows —
	/// that is what makes it a safe fallback — and a silent permanent fallback
	/// would therefore be invisible. It is the difference between the render path
	/// being on `render.h` and merely being able to be.
	private(set) var usedRenderStateForVisibleRows = false

	/// The rows on screen: the render state if it will answer, grid references if
	/// it will not.
	private func visibleRows(from scrollback: Int) -> [TerminalLine] {
		if let fromRenderState = copyVisibleRowsFromRenderState() {
			usedRenderStateForVisibleRows = true
			return fromRenderState
		}
		usedRenderStateForVisibleRows = false
		return copyLines(from: scrollback, count: rows)
	}

	/// The rows on screen, from the render state.
	///
	/// **This is the hot path, and `render.h` is what it is meant to use.** Grid
	/// references say so themselves: "the grid reference APIs are *not* meant to be
	/// used as the core of a render loop. They are not built to sustain the
	/// framerates needed for rendering large screens. Use the render state API for
	/// that." The difference in practice is that a grid reference costs a point
	/// resolution *per cell* — `ghostty_terminal_grid_ref` walks the page list to
	/// find the node — while the render state hands out a row iterator and then a
	/// cell iterator that simply advance.
	///
	/// Two things still need a grid reference and are asked for per *row* rather
	/// than per cell, only when the row says it has them: a grapheme cluster's
	/// codepoints, and a hyperlink's URI. The render state reports the cluster
	/// length and can write the codepoints, but there is no URI accessor on it at
	/// all, so a row carrying a link falls back for that row alone. Ordinary output
	/// has neither, and pays for neither.
	///
	/// Returns nil if there is no render state, in which case the caller falls back
	/// to `copyLines`, which is the obviously-correct version and the one the
	/// differential tests were first written against.
	private func copyVisibleRowsFromRenderState() -> [TerminalLine]? {
		guard let renderState else { return nil }

		var iterator: GhosttyRenderStateRowIterator?
		guard ghostty_render_state_row_iterator_new(nil, &iterator) == GHOSTTY_SUCCESS,
		      let rowIterator = iterator
		else { return nil }
		defer { ghostty_render_state_row_iterator_free(rowIterator) }
		guard ghostty_render_state_get(
			renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator) == GHOSTTY_SUCCESS
		else { return nil }

		var cellsHandle: GhosttyRenderStateRowCells?
		guard ghostty_render_state_row_cells_new(nil, &cellsHandle) == GHOSTTY_SUCCESS,
		      let cells = cellsHandle
		else { return nil }
		defer { ghostty_render_state_row_cells_free(cells) }

		var lines: [TerminalLine] = []
		lines.reserveCapacity(rows)
		var codepoints = [UInt32](repeating: 0, count: 16)
		// The absolute index of the first row on screen, for the rows that have to
		// fall back to a grid reference.
		let firstRow = scrollbackCount

		while ghostty_render_state_row_iterator_next(rowIterator) {
			var line = TerminalLine(columns: columns)

			var rawRow = GhosttyRow()
			var hasHyperlink = false
			if ghostty_render_state_row_get(
				rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_RAW, &rawRow) == GHOSTTY_SUCCESS {
				ghostty_row_get(rawRow, GHOSTTY_ROW_DATA_HYPERLINK, &hasHyperlink)
			}

			guard ghostty_render_state_row_get(
				rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cellsHandle) == GHOSTTY_SUCCESS
			else {
				lines.append(line)
				continue
			}

			var column = 0
			while column < columns, ghostty_render_state_row_cells_next(cells) {
				defer { column += 1 }

				var rawCell = GhosttyCell()
				guard ghostty_render_state_row_cells_get(
					cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &rawCell) == GHOSTTY_SUCCESS
				else { continue }

				var scalar: UInt32 = 0
				var wide: Int32 = 0
				ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_CODEPOINT, &scalar)
				ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_WIDE, &wide)

				var cell = TerminalCell(scalar: scalar == 0 ? 0x20 : scalar)
				cell.isWideTrailer = wide == 2

				// The *raw* style, so a palette index stays an index and the editor's
				// theme decides what "red" is. The render state also offers resolved
				// RGB, which is what a renderer with no theme of its own would want.
				var styled = false
				ghostty_render_state_row_cells_get(
					cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING, &styled)
				if styled {
					var style = GhosttyStyle()
					style.size = MemoryLayout<GhosttyStyle>.size
					if ghostty_render_state_row_cells_get(
						cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style) == GHOSTTY_SUCCESS {
						cell.attributes = attributes(from: style)
					}
				}

				// A grapheme cluster, when there is one. The length comes off the
				// render state; the codepoints go into a buffer we own.
				var clusterLength: UInt32 = 0
				ghostty_render_state_row_cells_get(
					cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &clusterLength)
				if clusterLength > 1 {
					if Int(clusterLength) > codepoints.count {
						codepoints = [UInt32](repeating: 0, count: Int(clusterLength))
					}
					let wrote = codepoints.withUnsafeMutableBufferPointer { buffer in
						ghostty_render_state_row_cells_get(
							cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
							buffer.baseAddress) == GHOSTTY_SUCCESS
					}
					if wrote {
						var text = ""
						for index in 0..<Int(clusterLength) {
							if let unicode = UnicodeScalar(codepoints[index]) {
								text.unicodeScalars.append(unicode)
							}
						}
						cell.combining = text
					}
				}
				line.cells[column] = cell
			}

			// A row with a link on it: the URIs are not on the render state, so this
			// one row is read again through grid references. Rare enough that a whole
			// extra row costs less than a check per cell would.
			if hasHyperlink,
			   let refetched = copyLines(from: firstRow + lines.count, count: 1).first {
				for index in 0..<min(line.cells.count, refetched.cells.count) {
					line.cells[index].attributes.link = refetched.cells[index].attributes.link
				}
			}
			lines.append(line)
		}

		// The render state should hand back exactly the rows on screen. If it hands
		// back a different number the caller is being lied to about the size of the
		// grid, and falling back is better than drawing a short screen.
		guard lines.count == rows else { return nil }
		return lines
	}

	/// Rows `from ..< from + count`, in absolute indices, through grid references.
	///
	/// Not the render path — see `copyVisibleRowsFromRenderState` — but the right
	/// tool for scrollback, which the render state does not cover: a grid reference
	/// is documented as "a snapshot … meant to be read and have their values cached
	/// immediately", which is exactly what a scroll back into history is.
	func copyLines(from: Int, count: Int) -> [TerminalLine] {
		guard let terminal, count > 0 else { return [] }
		var lines: [TerminalLine] = []
		lines.reserveCapacity(count)
		var codepoints = [UInt32](repeating: 0, count: 16)
		var uriBytes = [UInt8](repeating: 0, count: 512)

		for y in from..<(from + count) {
			var line = TerminalLine(columns: columns)
			for x in 0..<columns {
				var point = GhosttyPoint()
				point.tag = GHOSTTY_POINT_TAG_SCREEN
				point.value.coordinate.x = UInt16(x)
				point.value.coordinate.y = UInt32(max(0, y))

				var ref = GhosttyGridRef()
				ref.size = MemoryLayout<GhosttyGridRef>.size
				guard ghostty_terminal_grid_ref(terminal, point, &ref) == GHOSTTY_SUCCESS else { continue }

				var cellHandle = GhosttyCell()
				guard ghostty_grid_ref_cell(&ref, &cellHandle) == GHOSTTY_SUCCESS else { continue }

				var scalar: UInt32 = 0
				var wide: Int32 = 0
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_CODEPOINT, &scalar)
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_WIDE, &wide)

				var cell = TerminalCell(scalar: scalar == 0 ? 0x20 : scalar)
				// `wide` is a four-way — narrow 0, wide 1, spacer-**tail** 2,
				// spacer-**head** 3 — and only the tail is our `isWideTrailer`. A
				// spacer *head* is the blank left at the end of a row when a wide
				// glyph would not fit in the last column, which is a real cell
				// with nothing in it rather than the second half of anything.
				cell.isWideTrailer = wide == 2
				cell.attributes = attributes(of: cellHandle, at: &ref)

				// A grapheme cluster is more than its base codepoint. Ask only
				// when the cell says it has one, because this call is not free.
				var hasText = false
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_HAS_TEXT, &hasText)
				if hasText {
					var written = 0
					let result = codepoints.withUnsafeMutableBufferPointer { buffer in
						ghostty_grid_ref_graphemes(&ref, buffer.baseAddress, buffer.count, &written)
					}
					if result == GHOSTTY_SUCCESS, written > 1 {
						var text = ""
						for index in 0..<written {
							if let unicode = UnicodeScalar(codepoints[index]) {
								text.unicodeScalars.append(unicode)
							}
						}
						cell.combining = text
					}
				}

				// A hyperlink, if the cell has one. libghostty-vt hands back the URI
				// itself rather than an index, so it is interned here into the
				// `UInt16` our cells carry — asked for only when the cell says there
				// is one, which on ordinary output is never.
				var hasHyperlink = false
				ghostty_cell_get(cellHandle, GHOSTTY_CELL_DATA_HAS_HYPERLINK, &hasHyperlink)
				if hasHyperlink {
					var written = 0
					let result = uriBytes.withUnsafeMutableBufferPointer { buffer in
						ghostty_grid_ref_hyperlink_uri(&ref, buffer.baseAddress, buffer.count, &written)
					}
					if result == GHOSTTY_SUCCESS, written > 0 {
						cell.attributes.link = internedLink(
							String(decoding: uriBytes.prefix(written), as: UTF8.self))
					}
				}
				line.cells[x] = cell
			}
			lines.append(line)
		}
		return lines
	}

	private func attributes(
		of cell: GhosttyCell, at ref: inout GhosttyGridRef
	) -> TerminalAttributes {
		let plain = TerminalAttributes()
		var styled = false
		ghostty_cell_get(cell, GHOSTTY_CELL_DATA_HAS_STYLING, &styled)
		guard styled else { return plain }

		var style = GhosttyStyle()
		style.size = MemoryLayout<GhosttyStyle>.size
		guard ghostty_grid_ref_style(&ref, &style) == GHOSTTY_SUCCESS else { return plain }
		return attributes(from: style)
	}

	/// One `GhosttyStyle` as our attributes. Shared by both read paths, so the
	/// render state and grid references cannot come to disagree about a colour.
	private func attributes(from style: GhosttyStyle) -> TerminalAttributes {
		var attributes = TerminalAttributes()
		// The *raw* style, not the resolved foreground colour. Resolving would
		// put a palette index through the palette and hand back RGB, and this
		// app deliberately keeps a colour unresolved so the editor's theme
		// decides what "red" is.
		attributes.foreground = colour(style.fg_color)
		attributes.background = colour(style.bg_color)
		attributes.bold = style.bold
		attributes.italic = style.italic
		attributes.dim = style.faint
		attributes.inverse = style.inverse
		attributes.hidden = style.invisible
		attributes.strikethrough = style.strikethrough
		// Ours is a Bool and theirs is an SGR underline style, so every kind of
		// underline but "none" becomes true. That is the same flattening
		// `TerminalEmulator` already does with SGR 4:3.
		attributes.underline = style.underline != 0
		return attributes
	}

	private func colour(_ value: GhosttyStyleColor) -> TerminalColor {
		switch value.tag {
		case GHOSTTY_STYLE_COLOR_PALETTE: return .indexed(UInt8(truncatingIfNeeded: value.value.palette))
		case GHOSTTY_STYLE_COLOR_RGB:
			let rgb = value.value.rgb
			return .rgb(rgb.r, rgb.g, rgb.b)
		default: return .default
		}
	}
}

/// The snapshot `GhosttyTerminalEngine.grid` hands out.
///
/// The visible rows are copied when the snapshot is made, because that is what a
/// frame reads and it has to survive whatever the terminal does next. Scrollback
/// is not: on a full buffer that would be five thousand rows copied to draw
/// forty, which is 0474's 4.372 ms a frame. A scrollback row is fetched the first
/// time somebody asks for it — scrolling up, dragging a selection back through
/// history, Select All, `recentLines` — and then kept.
///
/// A class rather than a struct because of that keeping: the cache is shared by
/// every copy of the snapshot, and a value type would either lose it or copy it.
final class GhosttyGrid: TerminalGridReading {
	let rows: Int
	let columns: Int
	let totalLineCount: Int
	let scrollbackCount: Int
	let discardedLineCount: Int

	/// Rows `scrollbackCount ..< totalLineCount`, copied up front.
	let visible: [TerminalLine]
	/// Rows below that, copied on demand and then remembered.
	private var history: [Int: TerminalLine] = [:]
	private weak var source: GhosttyScreenReader?
	/// What the engine's write count was when this snapshot was made.
	private let writeCount: Int

	init(
		rows: Int, columns: Int, totalLineCount: Int, scrollbackCount: Int,
		discardedLineCount: Int, visible: [TerminalLine],
		source: GhosttyScreenReader, writeCount: Int
	) {
		self.rows = rows
		self.columns = columns
		self.totalLineCount = totalLineCount
		self.scrollbackCount = scrollbackCount
		self.discardedLineCount = discardedLineCount
		self.visible = visible
		self.source = source
		self.writeCount = writeCount
	}

	/// Whether this snapshot still describes the terminal as it is now.
	func matches(writeCount: Int) -> Bool { self.writeCount == writeCount }

	func line(at index: Int) -> TerminalLine? {
		guard index >= 0, index < totalLineCount else { return nil }
		if index >= scrollbackCount {
			let offset = index - scrollbackCount
			guard offset < visible.count else { return nil }
			return visible[offset]
		}
		if let cached = history[index] { return cached }
		// **A refusal, not a guess.** Once the engine has taken more bytes, the row
		// at this index is not the row this snapshot was describing, and handing
		// back the new one would be the "silently misrenders" failure in its
		// quietest form — a selection copying text it was never over. In practice
		// this never fires: the view snapshots and walks the snapshot within one
		// turn of the main queue, and writes are on the same queue.
		guard let source, source.currentWriteCount == writeCount else { return nil }
		guard let fetched = source.copyLines(from: index, count: 1).first else { return nil }
		history[index] = fetched
		return fetched
	}
}

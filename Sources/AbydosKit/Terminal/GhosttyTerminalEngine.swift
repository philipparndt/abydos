import Foundation
// Only the umbrella header, never a sub-header. Measured reason: two of the
// breaking changes in libghostty-vt's last four months were declarations moving
// between sub-headers with their names and signatures untouched
// (`ghostty_terminal_selection_*` from terminal.h to selection.h,
// `GhosttyFormatterFormat` from formatter.h to types.h). Including only the
// umbrella makes both of those non-events.
import GhosttyVt

/// libghostty-vt as an engine under our terminal, off by default (item 0474).
///
/// ghostty's terminal state machine with no pty and no renderer: bytes in, grid
/// out. The parts we would be buying from it are the ones we have repeatedly got
/// wrong ourselves — wrapping, reflow on resize, scrollback, and the cursor
/// arithmetic that 0468 turned out to be.
///
/// ## What is implemented and what refuses
///
/// Text is implemented: codepoints, grapheme clusters, wide cells, SGR colours
/// and attributes, scrollback, wrapping, reflow, cursor, alternate screen,
/// title. That is enough to run a shell and read it.
///
/// **Kitty graphics is not implemented here and refuses rather than half-works.**
/// See `unimplemented`. The reason is specific and worth knowing before anybody
/// tries: libghostty-vt covers one of `icat`'s two protocols and not the other.
/// 0468 established which two they are.
///
/// - The **`t=f` real placement** used outside tmux is fully covered.
///   `ghostty_kitty_graphics_placement_iterator_new` enumerates placements, and
///   `ghostty_kitty_graphics_placement_grid_size` even does the thing 0468
///   needed — "if the placement specifies explicit columns and rows those are
///   returned directly; otherwise they are calculated from the pixel size and
///   cell dimensions" — which is exactly the `s=`/`v=`-with-no-`c=`/`r=` case.
/// - The **`U=1` unicode placeholder** protocol used inside tmux is only half
///   covered. The escape is honoured and the virtual placement is stored and
///   enumerable (`GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IS_VIRTUAL`), but the
///   part that turns placeholder cells into picture fragments is *not exported*.
///   The geometry calls actively refuse virtual placements — `placement_rect`
///   and `placement_viewport_pos` both document returning `GHOSTTY_NO_VALUE` for
///   them — and there is no U+10EEEE constant, no diacritic table and no
///   placeholder iterator anywhere in the headers. ghostty has that code
///   (`src/terminal/kitty/graphics_unicode.zig`, 1,361 lines, with a 297-entry
///   diacritic table) but its only consumer is ghostty's own GUI renderer, and
///   `src/lib_vt.zig` exports none of it.
///
/// So `UnicodePlaceholder` (226 lines) is not replaceable by this library at
/// all, and `KittyGraphics` (1,066) is only partly. Both stay on our side of the
/// seam whatever happens.
///
/// ## Two things the library requires that are easy to get silently wrong
///
/// - Kitty graphics is **off** until a non-zero storage limit is set, and file
///   media are **off** by default (`image_limits = .direct`). A forgotten
///   storage limit looks exactly like "this terminal has no graphics".
/// - Query responses (`a=q`, DSR, DA) are **not even encoded** unless a
///   `WRITE_PTY` callback is installed. Outside tmux `icat` asks three questions
///   and waits, so with no callback it hangs rather than misdraws.
///
/// Both are set up in `init`, so that if graphics is ever finished here the
/// plumbing is not the missing piece.
public final class GhosttyTerminalEngine: TerminalEngine {
	public static var engineName: String { "libghostty-vt" }

	private var terminal: GhosttyTerminal?
	private var pendingResponse = ""

	public var onUpdate: (() -> Void)?
	public var onResponse: ((String) -> Void)?

	public private(set) var cursorRow = 0
	public private(set) var cursorColumn = 0
	public private(set) var isCursorVisible = true
	public private(set) var title: String?
	public private(set) var isAlternateScreen = false

	private var rows: Int
	private var columns: Int
	private var dirty: ClosedRange<Int>?

	public var cellPixelSize: (width: Int, height: Int) = (0, 0) {
		didSet {
			guard cellPixelSize != oldValue else { return }
			applySize()
		}
	}

	/// Named plainly, because this string is shown in the settings window and in
	/// `--report-geometry`. Somebody turning the engine on should learn what is
	/// missing there rather than by noticing it.
	public var unimplemented: [String] {
		[
			"Kitty graphics: images and placements are parsed but never drawn "
				+ "(the unicode-placeholder protocol tmux uses is not in libghostty-vt's C API)",
			"OSC 440 (abydos open-file), OSC 52 clipboard, OSC 4/10/11/12 colour queries",
			// The library does have these — `ghostty/vt/key/encoder.h` and
			// `mouse/encoder.h` — they are simply not wired up here yet. Named
			// anyway, because from outside "not implemented" and "not wired" look
			// the same and both mean the pane will not behave.
			"Key, mouse and focus encoding not wired (the library has encoders; this engine ignores them)",
			"discardedLineCount always reports 0, so the scrollbar and selection realignment are wrong after pruning",
		]
	}

	public init(rows: Int = 24, columns: Int = 80) {
		self.rows = max(1, rows)
		self.columns = max(1, columns)

		var handle: GhosttyTerminal?
		// `ghostty_terminal_new(allocator, out, cols, rows)` — cols before rows,
		// and both `uint16_t`. This signature is one of the two places
		// libghostty-vt has actually broken in the last four months (it used to
		// take a `GhosttyTerminalOptions` struct), which is why construction is
		// wrapped here rather than called from several places.
		guard ghostty_terminal_new(nil, &handle, UInt16(self.columns), UInt16(self.rows)) == GHOSTTY_SUCCESS,
		      let handle
		else { return }
		terminal = handle

		// Query responses have to have somewhere to go or they are not encoded
		// at all — the library checks for this callback before it bothers to
		// build the reply.
		let this = Unmanaged.passUnretained(self).toOpaque()
		ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_USERDATA, this)
		let writePty: GhosttyTerminalWritePtyFn = { _, userdata, data, len in
			guard let userdata, let data else { return }
			let engine = Unmanaged<GhosttyTerminalEngine>
				.fromOpaque(userdata).takeUnretainedValue()
			engine.pendingResponse += String(
				decoding: UnsafeBufferPointer(start: data, count: len), as: UTF8.self)
		}
		ghostty_terminal_set(
			handle, GHOSTTY_TERMINAL_OPT_WRITE_PTY,
			unsafeBitCast(writePty, to: UnsafeMutableRawPointer.self))

		applySize()
	}

	deinit {
		if let terminal { ghostty_terminal_free(terminal) }
	}

	/// True when the library is actually there. False means every call below is
	/// a no-op — which is a refusal, not a silent fallback: `unimplemented`
	/// carries the reason and the panel shows it.
	public var isUsable: Bool { terminal != nil }

	// MARK: - Bytes in

	public func write(_ data: Data) {
		guard let terminal else { return }
		data.withUnsafeBytes { raw in
			guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
			ghostty_terminal_vt_write(terminal, base, raw.count)
		}
		afterWrite()
	}

	public func write(_ string: String) {
		guard let terminal else { return }
		var bytes = Array(string.utf8)
		bytes.withUnsafeBufferPointer { buffer in
			guard let base = buffer.baseAddress else { return }
			ghostty_terminal_vt_write(terminal, base, buffer.count)
		}
		afterWrite()
	}

	private func afterWrite() {
		refreshState()
		// The whole grid, because libghostty-vt tracks dirtiness per row inside
		// its render state rather than as a range, and this engine does not use
		// the render state yet. Honest and slow rather than clever and wrong: the
		// Metal path throws the dirty range away anyway, and the CoreGraphics
		// path will simply repaint more than it needs to.
		dirty = 0...max(0, totalLineCount - 1)
		if !pendingResponse.isEmpty {
			let response = pendingResponse
			pendingResponse = ""
			onResponse?(response)
		}
		onUpdate?()
	}

	private func refreshState() {
		guard let terminal else { return }
		var cx: UInt16 = 0, cy: UInt16 = 0, visible = false
		var cols: UInt16 = 0, rowCount: UInt16 = 0
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_CURSOR_X, &cx)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_CURSOR_Y, &cy)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_CURSOR_VISIBLE, &visible)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLS, &cols)
		ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ROWS, &rowCount)
		cursorColumn = Int(cx)
		cursorRow = Int(cy)
		isCursorVisible = visible
		columns = Int(cols)
		rows = Int(rowCount)

		// `GhosttyTerminalScreen *`, so the imported enum type rather than a
		// guessed integer width.
		var screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY
		if ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen) == GHOSTTY_SUCCESS {
			isAlternateScreen = screen != GHOSTTY_TERMINAL_SCREEN_PRIMARY
		}
	}

	// MARK: - Size

	public func resize(rows: Int, columns: Int) {
		self.rows = max(1, rows)
		self.columns = max(1, columns)
		applySize()
		refreshState()
		dirty = 0...max(0, totalLineCount - 1)
	}

	private func applySize() {
		guard let terminal else { return }
		// The cell pixel size goes in on the same call as the grid size. This is
		// the library's only route for it, and it is what
		// `placement_grid_size` divides by — a cell of no pixels is how a
		// terminal says it cannot show pictures at all, which is 0468's other
		// half.
		ghostty_terminal_resize(
			terminal, UInt16(columns), UInt16(rows),
			UInt32(max(0, cellPixelSize.width)), UInt32(max(0, cellPixelSize.height)))
	}

	public func reset() {
		guard let terminal else { return }
		ghostty_terminal_reset(terminal)
		refreshState()
		dirty = 0...max(0, totalLineCount - 1)
	}

	public func takeDirtyRange() -> ClosedRange<Int>? {
		defer { dirty = nil }
		return dirty
	}

	// MARK: - Grid out

	// `size_t`, not `uint32_t`. Every one of these output types is documented in
	// the header and getting one wrong is a silent stack write of the wrong
	// width, which is exactly the kind of bug that passes its tests: the first
	// draft of this file read both of these into a `UInt32` and the suite was
	// green.
	private var totalLineCount: Int {
		guard let terminal else { return rows }
		var total = 0
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &total) == GHOSTTY_SUCCESS
		else { return rows }
		return total
	}

	private var scrollbackCount: Int {
		guard let terminal else { return 0 }
		var back = 0
		guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &back) == GHOSTTY_SUCCESS
		else { return 0 }
		return back
	}

	/// A snapshot, by copying.
	///
	/// The protocol promises a grid that survives later writes, and
	/// libghostty-vt's grid references explicitly do not: an untracked reference
	/// "is only valid until the next update to the terminal instance … even if a
	/// seemingly unrelated part of the grid is changed". So the only honest way
	/// to satisfy the seam is to copy the rows out while we hold the terminal.
	///
/// That copy is this engine's main cost and it is measured in the item. The
	/// fix, when it matters, is `render.h` — a stateful render state with its own
	/// per-row dirty tracking, built for exactly this and documented as the API
	/// to use instead of grid references, which "are not built to sustain the
	/// framerates needed for rendering large screens".
	public var grid: TerminalGridReading {
		GhosttyGrid(
			rows: rows, columns: columns,
			totalLineCount: totalLineCount,
			scrollbackCount: scrollbackCount,
			lines: copyAllLines())
	}

	private func copyAllLines() -> [TerminalLine] {
		guard let terminal else { return [] }
		let total = totalLineCount
		var lines: [TerminalLine] = []
		lines.reserveCapacity(total)
		var codepoints = [UInt32](repeating: 0, count: 16)

		for y in 0..<total {
			var line = TerminalLine(columns: columns)
			for x in 0..<columns {
				var point = GhosttyPoint()
				point.tag = GHOSTTY_POINT_TAG_SCREEN
				point.value.coordinate.x = UInt16(x)
				point.value.coordinate.y = UInt32(y)

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
				line.cells[x] = cell
			}
			lines.append(line)
		}
		return lines
	}

	private func attributes(
		of cell: GhosttyCell, at ref: inout GhosttyGridRef
	) -> TerminalAttributes {
		var attributes = TerminalAttributes()
		var styled = false
		ghostty_cell_get(cell, GHOSTTY_CELL_DATA_HAS_STYLING, &styled)
		guard styled else { return attributes }

		var style = GhosttyStyle()
		style.size = MemoryLayout<GhosttyStyle>.size
		guard ghostty_grid_ref_style(&ref, &style) == GHOSTTY_SUCCESS else { return attributes }

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

/// The snapshot `GhosttyTerminalEngine.grid` hands out: plain copied rows, so it
/// keeps the frame it was given no matter what the terminal does next.
private struct GhosttyGrid: TerminalGridReading {
	let rows: Int
	let columns: Int
	let totalLineCount: Int
	let scrollbackCount: Int
	let lines: [TerminalLine]

	/// Always 0: libghostty-vt prunes its own scrollback and does not report how
	/// many lines it has thrown away, so absolute indices from an older frame
	/// cannot be told apart from current ones. Ours counts them
	/// (`TerminalScreen.discardedLineCount`) and the scrollbar uses it. A real
	/// answer needs a tracked grid reference pinned to the oldest line —
	/// `ghostty_terminal_grid_ref_track`, which "follows its cell across …
	/// scrollback pruning" and reports no value once the line is gone.
	var discardedLineCount: Int { 0 }

	func line(at index: Int) -> TerminalLine? {
		guard index >= 0, index < lines.count else { return nil }
		return lines[index]
	}
}

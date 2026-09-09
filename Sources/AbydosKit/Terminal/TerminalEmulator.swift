import Foundation

/// A VT100/xterm-compatible terminal emulator.
///
/// Deliberately UI-free: it consumes bytes and maintains a `TerminalScreen`,
/// which makes the awkward parts — escape sequences, wide characters, scroll
/// regions, the alternate screen — testable by feeding in byte strings and
/// inspecting the grid, with no window involved.
///
/// The supported subset targets what interactive tools actually emit: shells,
/// git, and agent CLIs like Claude Code, which lean on colour, cursor
/// positioning, line erasure and the alternate screen.
public final class TerminalEmulator {
	public internal(set) var screen: TerminalScreen

	/// Cursor position within the active grid.
	public internal(set) var cursorRow = 0
	public internal(set) var cursorColumn = 0
	public internal(set) var isCursorVisible = true

	/// Window title from OSC 0/2.
	public internal(set) var title: String?

	/// What changed since the view last drew, as absolute line indices.
	///
	/// Taken rather than read, so the next redraw starts from nothing.
	public func takeDirtyRange() -> ClosedRange<Int>? {
		screen.takeDirtyRange()
	}

	/// Fired when the grid changed and the view should redraw.
	public var onUpdate: (() -> Void)?
	/// Replies the terminal must send back to the process (device status, etc).
	public var onResponse: ((String) -> Void)?
	/// Fired on BEL.
	public var onBell: (() -> Void)?

	/// The addresses behind the hyperlinks on screen, by the id cells carry.
	var links: [String] = []

	/// The address a cell belongs to, if it belongs to one.
	public func link(for id: UInt16) -> String? {
		guard id > 0, Int(id) <= links.count else { return nil }
		return links[Int(id) - 1]
	}

	/// A program put something on the clipboard (OSC 52).
	///
	/// How a copy inside tmux — or inside anything on the other end of an ssh
	/// connection — reaches the clipboard of the machine somebody is sitting
	/// at. Without it those copies go nowhere at all.
	public var onClipboardWrite: ((String) -> Void)?

	/// A program in this pane asked for a file to be opened (OSC 440).
	///
	/// The one thing `open -a` cannot say is *which window asked*. A command
	/// typed in a pane is already connected to the window it was typed in, by
	/// the pty it is running on, so the request arrives here with that fact
	/// already established — and the window can then put the file in its own
	/// editor, move the keyboard into it, and get the terminal out of the way.
	public var onOpenFile: ((TerminalOpenRequest) -> Void)?

	/// A program asked what a colour is, and the answer has to come from
	/// whoever owns the palette.
	///
	/// `nil` means "no such colour", and nothing is sent — a program that
	/// asked is expected to cope with silence.
	public var colourLookup: ((ColourQuery) -> (red: Double, green: Double, blue: Double)?)?

	/// Which colour a program is asking about.
	public enum ColourQuery: Equatable, Sendable {
		/// A palette entry, 0–255.
		case palette(Int)
		case foreground
		case background
		case cursor
	}

	var attributes = TerminalAttributes()
	var savedCursor: (row: Int, column: Int, attributes: TerminalAttributes)?

	/// DECSTBM scroll region, inclusive.
	var scrollTop = 0
	var scrollBottom: Int

	/// Set after writing to the last column: the next character wraps. Without
	/// this, writing exactly `columns` characters would wrap one column early.
	var pendingWrap = false

	/// Set when a program asked for the row one below the last one.
	///
	/// The cursor is clamped to the last row, because there is nowhere else for
	/// it to be, but the fact that it was pushed one past the bottom is kept:
	/// a program that parks the cursor there measures its next vertical move
	/// from where it parked it, not from where the clamp put it.
	///
	/// tmux does exactly that, and it is what 0404 turned out to be. With its
	/// status bar off, tmux draws its command prompt on the pane's last row, and
	/// while the prompt is up it parks the cursor at `CSI <rows+1> d` — one row
	/// below the screen — then writes the prompt with a relative `CSI A` from
	/// that park. Measured from the clamp, `CSI A` lands the prompt one row too
	/// high, in the middle of the pane, on top of output the pane will repaint
	/// over it: "a fragment, in the wrong place, gone by the next repaint" is
	/// what the report says, and it is what a capture shows. Measured from the
	/// park, it lands on the last row, which is the row tmux is holding for it
	/// and stops painting the pane into for as long as the prompt is open. So
	/// the last line is protected — by tmux, once it is asked the way tmux
	/// meant to ask.
	///
	/// One row and no further. A program that asks for row 999 is guessing at
	/// the size of the screen rather than parking on the edge of it, and
	/// clamping is the only answer to that; this is the same kind of memory as
	/// `pendingWrap`, one edge over, and it lasts exactly as long — until
	/// something puts the cursor somewhere real.
	var isParkedBelowScreen = false

	/// Alternate screen (used by full-screen apps), saved main screen.
	var alternateSaved: (screen: TerminalScreen, row: Int, column: Int)?
	public internal(set) var isAlternateScreen = false

	public var applicationCursorKeys = false
	public var bracketedPaste = false

	/// Whether a program is part-way through rewriting the screen.
	///
	/// Set by mode 2026 and cleared when the program says it has finished. What
	/// is on the grid in between is half-drawn — a pane erased but not yet
	/// filled in — and drawing it is what makes a repaint flicker.
	public internal(set) var isSynchronizingOutput = false

	/// How the program wants pointer events reported, if at all.
	public enum MouseTracking: Equatable, Sendable {
		case off
		/// 1000 — press and release only.
		case click
		/// 1002 — press, release, and drag.
		case buttonEvent
		/// 1003 — every motion.
		case anyEvent
	}

	public internal(set) var mouseTracking: MouseTracking = .off
	/// 1004 — whether the program wants to hear about the window gaining and
	/// losing the keyboard. tmux passes it through to whatever is in the pane,
	/// which is how a full-screen program knows to stop animating.
	public internal(set) var reportsFocus = false

	/// The kitty keyboard protocol's flags, and the stack a program pushes them
	/// on so it can put them back.
	///
	/// Bit 1 is the one that matters: "disambiguate escape codes", which is how
	/// a program tells Shift+Enter from Enter, or Ctrl+I from Tab. Without it
	/// both halves of each pair send the same byte and no program can tell.
	public internal(set) var keyboardFlags: UInt8 = 0
	var keyboardStack: [UInt8] = []

	/// xterm's older answer to the same problem: `CSI > 4 ; 2 m` asks for
	/// modified keys as `CSI 27 ; modifiers ; code ~`.
	public internal(set) var modifyOtherKeys = 0

	/// Whether either protocol is on, in whichever form.
	public var reportsModifiedKeys: Bool { keyboardFlags & 1 != 0 || modifyOtherKeys >= 2 }

	/// What shape the cursor should be, as the program last asked (DECSCUSR).
	///
	/// Blinking is not honoured — a cursor that blinks repaints the screen
	/// twice a second whatever the program is doing — but the shape is: vim in
	/// insert mode asks for a bar, and a block there is a lie about what typing
	/// will do.
	public internal(set) var cursorShape: CursorShape = .block

	public enum CursorShape: Sendable, Equatable {
		case block, underline, bar
	}

	/// 1006 — SGR encoding. The legacy encoding cannot express coordinates past
	/// column 223, so modern programs all ask for this one.
	public internal(set) var sgrMouseEncoding = false

	/// How large one character cell is, in pixels.
	///
	/// The emulator has no opinion about fonts, so this is told to it by whoever
	/// is drawing. It is here because two things a program asks about are
	/// answered in pixels: `CSI t`, and where an image goes — a picture is
	/// placed on the grid but measured in pixels, and the two only meet through
	/// this number.
	public var cellPixelSize: (width: Int, height: Int) = (0, 0) {
		didSet { graphics.cellPixelSize = cellPixelSize }
	}

	// MARK: - Parser state

	enum State {
		case ground
		case escape
		case csi
		case osc
		/// `ESC _` — where a kitty graphics command arrives.
		case apc
		/// Consuming a sequence we recognise but do not implement.
		case ignore(terminator: UInt8)
		/// Discards exactly one byte, for charset designators.
		case skipOne
	}

	var state = State.ground

	/// CSI parameters, folded into integers as their digits arrive.
	///
	/// Every number in the sequence in order, with `componentStarts` marking
	/// where each `;`-separated component begins: its primary value first, then
	/// any `:` subparameters.
	///
	/// This replaced a string that was split apart again on every read — and a
	/// read happens several times per sequence. A truecolour SGR arrives for
	/// every cell of a full-screen repaint, so that splitting cost more than
	/// everything else the parser did put together.
	/// Storage of its own rather than arrays. A sequence arrives for every cell
	/// of a screen repaint, and an array checks that it is uniquely referenced
	/// on every single write — which came to more than reading the digits did.
	/// The capacity is fixed: no sequence anyone sends carries thirty-two
	/// components, and anything longer is dropped rather than grown into.
	static let parameterCapacity = 32
	let parameterValues: UnsafeMutablePointer<Int32>
	let componentStarts: UnsafeMutablePointer<Int32>
	var parameterCount = 0
	var componentTotal = 0
	var pendingValue = 0
	var atComponentStart = true
	/// The `?`, `>`, `<` or `=` marking a sequence as private rather than ANSI.
	var introducer: UInt8?
	/// Intermediate bytes, such as the `$` that makes `CSI ? p` a mode query.
	var intermediateBytes: [UInt8] = []
	var oscBytes: [UInt8] = []
	var apcBytes: [UInt8] = []
	/// Whether the sequence being gathered ran past the cap, in which case it
	/// is dropped whole rather than acted on short.
	var apcOverflowed = false

	/// The pictures on the screen, and the ones a program has sent but not shown.
	///
	/// Public because drawing them is the view's job: the emulator knows where an
	/// image goes and what its pixels are, and nothing about how to put them on a
	/// screen.
	public let graphics = TerminalImageStore()

	/// Placements belonging to the screen that is not the current one.
	var alternateGraphics: [TerminalImagePlacement] = []
	/// What `screen.discardedLineCount` was when the placements were last moved.
	var lastDiscardedLineCount = 0

	/// Partial UTF-8 sequence carried between writes, since a read can split one.
	/// The UTF-8 sequence being assembled, decoded by hand.
	///
	/// A read can split a sequence, so this has to persist between writes. It
	/// used to be an array run through the standard decoder once per byte —
	/// three times over for a three-byte character, each building an iterator
	/// and a decoder — which was most of what a non-ASCII character cost.
	private var utf8Value: UInt32 = 0
	private var utf8Remaining = 0
	/// Smallest value this many bytes may legally encode, so an overlong
	/// sequence is rejected rather than silently accepted.
	private var utf8Minimum: UInt32 = 0

	/// Widths already worked out, indexed by scalar value; -1 for not yet asked.
	///
	/// Establishing a width means consulting the Unicode property tables, and
	/// that was being done for every character written. A terminal writes the
	/// same few hundred characters over and over, so one byte per code point of
	/// the Basic Multilingual Plane buys all of them back. Per emulator rather
	/// than shared, which keeps it off any thread but the one writing.
	private var widthCache = [Int8](repeating: -1, count: 0x1_0000)

	public init(rows: Int = 24, columns: Int = 80) {
		parameterValues = .allocate(capacity: Self.parameterCapacity)
		componentStarts = .allocate(capacity: Self.parameterCapacity)
		screen = TerminalScreen(rows: rows, columns: columns)
		scrollBottom = screen.rows - 1
	}

	deinit {
		parameterValues.deallocate()
		componentStarts.deallocate()
	}

	// MARK: - Input

	public func write(_ data: Data) {
		write(Array(data))
	}

	public func write(_ bytes: [UInt8]) {
		bytes.withUnsafeBufferPointer { buffer in
			var index = 0
			while index < buffer.count {
				// Plain text arrives in runs — words, lines, whole paragraphs —
				// and the whole run can go into the grid at once. Stepping through
				// it a byte at a time, building a Character for each and asking
				// the screen to store it, was the rest of the parser's cost once
				// parameter parsing stopped being it.
				if isGround, utf8Remaining == 0, buffer[index] >= 0x20, buffer[index] < 0x7F {
					var end = index
					while end < buffer.count, buffer[end] >= 0x20, buffer[end] < 0x7F { end += 1 }
					putASCII(buffer, from: index, to: end)
					index = end
					continue
				}
				consume(buffer[index])
				index += 1
			}
		}
		realignGraphicsForDiscardedLines()
		onUpdate?()
	}

	/// Lines dropped off the top of scrollback move every absolute row, and a
	/// picture is anchored to one.
	///
	/// Without this a long-running session slides its images upward relative to
	/// the text they belong to, a row at a time, until they are drawn over
	/// something else entirely.
	private func realignGraphicsForDiscardedLines() {
		let discarded = screen.discardedLineCount
		guard discarded != lastDiscardedLineCount else { return }
		graphics.shiftRows(by: discarded - lastDiscardedLineCount)
		lastDiscardedLineCount = discarded
	}

	private var isGround: Bool {
		if case .ground = state { return true }
		return false
	}

	/// Writes a run of printable ASCII, wrapping as it fills each row.
	private func putASCII(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) {
		// As in `put`: drawing puts the cursor somewhere real, so a park below
		// the screen is over.
		isParkedBelowScreen = false
		var index = start
		while index < end {
			if pendingWrap {
				cursorColumn = 0
				lineFeed()
				pendingWrap = false
			}
			guard cursorRow < screen.rows, cursorColumn < screen.columns else { return }

			// Up to the end of the row; what is left goes on the next one.
			let room = screen.columns - cursorColumn
			let run = min(room, end - index)
			screen.setASCII(
				row: cursorRow,
				column: cursorColumn,
				bytes: bytes,
				from: index,
				count: run,
				attributes: attributes
			)
			index += run

			let advance = cursorColumn + run
			if advance >= screen.columns {
				// Deferred, exactly as a single character write defers it: the
				// wrap happens when the next character arrives, not before.
				cursorColumn = screen.columns - 1
				pendingWrap = true
			} else {
				cursorColumn = advance
			}
		}
	}

	public func write(_ string: String) {
		write(Array(string.utf8))
	}

	private func consume(_ byte: UInt8) {
		switch state {
		case .ground:
			consumeGround(byte)
		case .escape:
			consumeEscape(byte)
		case .csi:
			consumeCSI(byte)
		case .osc:
			consumeOSC(byte)
		case .apc:
			consumeAPC(byte)
		case let .ignore(terminator):
			if byte == terminator { state = .ground }
		case .skipOne:
			state = .ground
		}
	}

	// MARK: - Ground

	private func consumeGround(_ byte: UInt8) {
		if utf8Remaining > 0 {
			if byte & 0xC0 == 0x80 {
				utf8Value = (utf8Value << 6) | UInt32(byte & 0x3F)
				utf8Remaining -= 1
				if utf8Remaining == 0 { put(scalar: decodedScalar()) }
				return
			}
			// Not a continuation, so the sequence is malformed. Show a
			// replacement and read this byte as whatever it is instead.
			utf8Remaining = 0
			put(scalar: "\u{FFFD}")
		}

		switch byte {
		case 0x07: onBell?()
		case 0x08: moveCursor(row: cursorRow, column: cursorColumn - 1)
		case 0x09: tab()
		case 0x0A, 0x0B, 0x0C: lineFeed()
		case 0x0D: cursorColumn = 0; pendingWrap = false
		case 0x1B: state = .escape; resetParameters()
		case 0x00...0x06, 0x0E...0x1A, 0x1C...0x1F:
			break // Other C0 controls are not meaningful here.
		case 0x20...0x7F:
			put(scalar: UnicodeScalar(byte))
		// Lead bytes. 0xC0 and 0xC1 could only ever be overlong, and nothing
		// past 0xF4 can reach a code point that exists.
		case 0xC2...0xDF:
			utf8Value = UInt32(byte & 0x1F); utf8Remaining = 1; utf8Minimum = 0x80
		case 0xE0...0xEF:
			utf8Value = UInt32(byte & 0x0F); utf8Remaining = 2; utf8Minimum = 0x800
		case 0xF0...0xF4:
			utf8Value = UInt32(byte & 0x07); utf8Remaining = 3; utf8Minimum = 0x1_0000
		default:
			// A stray continuation byte, or a lead byte that cannot begin
			// anything valid.
			put(scalar: "\u{FFFD}")
		}
	}

	/// The scalar just assembled, or a replacement if it is not a legal one.
	///
	/// Overlong encodings, surrogate halves and anything past the last plane are
	/// all malformed. A terminal shows malformed input rather than guessing at
	/// what was meant by it.
	private func decodedScalar() -> UnicodeScalar {
		guard utf8Value >= utf8Minimum, let scalar = UnicodeScalar(utf8Value) else {
			return "\u{FFFD}"
		}
		return scalar
	}

	/// Writes a code point at the cursor, handling wrap and double-width glyphs.
	///
	/// The scalar is what the stream actually carries; assembling a Character
	/// for it is only needed when marks are combined onto it, which is rare.
	private func put(scalar: UnicodeScalar) {
		// Anything written goes where the cursor really is, so a park below the
		// screen is over the moment a program draws.
		isParkedBelowScreen = false
		if pendingWrap {
			cursorColumn = 0
			lineFeed()
			pendingWrap = false
		}

		let width = displayWidth(of: scalar)
		if width == 0 {
			combine(scalar: scalar)
			return
		}

		if width == 2, cursorColumn == screen.columns - 1 {
			screen.setScalar(row: cursorRow, column: cursorColumn, scalar: 0x20, attributes: attributes)
			cursorColumn = 0
			lineFeed()
		}

		screen.setScalar(row: cursorRow, column: cursorColumn, scalar: scalar.value, attributes: attributes)
		if width == 2 {
			screen.setScalar(
				row: cursorRow,
				column: cursorColumn + 1,
				scalar: 0x20,
				attributes: attributes,
				isWideTrailer: true
			)
		}

		advanceCursor(by: width)
	}

	/// Attaches a zero-width mark to the cell before the cursor.
	private func combine(scalar: UnicodeScalar) {
		let target = max(0, cursorColumn - 1)
		guard cursorRow < screen.rows, target < screen.columns else { return }

		var cell = screen[cursorRow].cells[target]
		// Rebuilt rather than edited: a grapheme cluster is not mutable in place.
		var combined = cell.combining ?? String(UnicodeScalar(cell.scalar) ?? " ")
		combined.unicodeScalars.append(scalar)
		cell.character = combined.first ?? cell.character
		screen.setCell(row: cursorRow, column: target, cell: cell)
	}

	private func advanceCursor(by width: Int) {
		let advance = cursorColumn + width
		if advance >= screen.columns {
			// Defer the wrap; see `pendingWrap`.
			cursorColumn = screen.columns - 1
			pendingWrap = true
		} else {
			cursorColumn = advance
		}
	}

	/// Writes a whole grapheme cluster, which only the tests hand over directly.
	private func put(_ character: Character) {
		if pendingWrap {
			cursorColumn = 0
			lineFeed()
			pendingWrap = false
		}

		let width = displayWidth(of: character)
		if width == 0 {
			// Combining mark: attach to the previous cell rather than advancing.
			let target = max(0, cursorColumn - 1)
			if cursorRow < screen.rows, target < screen.columns {
				var cell = screen[cursorRow].cells[target]
				// Rebuild the grapheme with the mark attached; Character is not
				// mutable in place.
				var combined = String(cell.character)
				combined.append(character)
				cell.character = combined.first ?? cell.character
				screen.setCell(row: cursorRow, column: target, cell: cell)
			}
			return
		}

		// A double-width glyph will not straddle the right margin.
		if width == 2 && cursorColumn == screen.columns - 1 {
			screen.setCell(row: cursorRow, column: cursorColumn, cell: TerminalCell(character: " ", attributes: attributes))
			cursorColumn = 0
			lineFeed()
		}

		screen.setCell(row: cursorRow, column: cursorColumn, cell: TerminalCell(character: character, attributes: attributes))
		if width == 2 {
			screen.setCell(
				row: cursorRow,
				column: cursorColumn + 1,
				cell: TerminalCell(character: " ", attributes: attributes, isWideTrailer: true)
			)
		}

		let advance = cursorColumn + width
		if advance >= screen.columns {
			// Defer the wrap; see `pendingWrap`.
			cursorColumn = screen.columns - 1
			pendingWrap = true
		} else {
			cursorColumn = advance
		}
	}

	/// Terminal column width, remembering what it has already worked out.
	private func displayWidth(of scalar: UnicodeScalar) -> Int {
		// Plain ASCII is one column and never a mark. It is most of everything a
		// terminal ever shows, and it is not worth a lookup to say so.
		if scalar.value >= 0x20, scalar.value < 0x7F { return 1 }
		guard scalar.value < 0x1_0000 else { return Self.displayWidth(of: Character(scalar)) }

		let cached = widthCache[Int(scalar.value)]
		if cached >= 0 { return Int(cached) }

		let width = Self.displayWidth(of: Character(scalar))
		widthCache[Int(scalar.value)] = Int8(width)
		return width
	}

	/// A whole cluster's width, which is its base's.
	private func displayWidth(of character: Character) -> Int {
		// One pass: asking for the scalar count walks the grapheme, and doing
		// that to decide whether the answer can be remembered costs as much as
		// remembering it saves.
		var scalars = character.unicodeScalars.makeIterator()
		guard let scalar = scalars.next() else { return 0 }
		guard scalars.next() == nil else { return Self.displayWidth(of: character) }
		return displayWidth(of: scalar)
	}

	/// Terminal column width. Combining marks take none; CJK and emoji take two.
	static func displayWidth(of character: Character) -> Int {
		guard let scalar = character.unicodeScalars.first else { return 0 }

		// Only true combining marks and formatting controls are zero-width.
		//
		// Not `isGraphemeBase`: that is false for the Private Use Area, so every
		// powerline separator was treated as a combining mark and merged into the
		// previous cell, which made prompt separators vanish entirely.
		switch scalar.properties.generalCategory {
		case .nonspacingMark, .enclosingMark, .format:
			return 0
		default:
			break
		}

		let value = scalar.value

		// Zero-width before anything else. A variation selector is how a scalar
		// is *asked* for emoji presentation, so the emoji test below would claim
		// it as two columns of its own.
		switch value {
		case 0x0300...0x036F, 0x200B...0x200F, 0xFE00...0xFE0F: return 0
		default: break
		}

		// **Asked of Unicode rather than listed by hand.** A scalar whose default
		// presentation is emoji is East Asian Wide, and that is the whole rule —
		// so this one line is every emoji block, including the ones added after
		// it was written.
		//
		// The list it replaces was `0x1F300...0x1F64F` and `0x1F900...0x1F9FF`,
		// which is a real but arbitrary slice of the emoji planes. Everything
		// outside it was measured as one column while the font drew two, and the
		// two failures compound: the glyph is clipped to half its width, *and*
		// every cell after it on the line sits one column to the left of where
		// the program put it. What was missing included ✅ U+2705, ❌ U+274C,
		// 🟩 U+1F7E9, ✨ U+2728, ⌚ U+231A, the zodiac, all of Transport and Map
		// (🚀 U+1F680 onwards) and all of the coloured squares and circles.
		//
		// A build log full of ✅ was the report, and it is the ordinary case:
		// these are what a script prints to say a step passed.
		//
		// Deliberately *not* extended to a base scalar plus U+FE0F. U+2714 is
		// Neutral and one column wide on its own; whether `2714 FE0F` becomes two
		// is a question about presentation rather than about East Asian Width,
		// and libghostty-vt answers one there too, so agreeing with it costs
		// nothing and keeps the two engines comparable.
		if scalar.properties.isEmojiPresentation { return 2 }

		switch value {
		case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF,
		     0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
		     0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F,
		     0xFF00...0xFF60, 0xFFE0...0xFFE6,
		     0x1F200...0x1F2FF, 0x20000...0x3FFFD:
			return 2
		default:
			return 1
		}
	}

	private func tab() {
		// Tab stops every 8 columns, the standard default.
		let next = ((cursorColumn / 8) + 1) * 8
		cursorColumn = min(next, screen.columns - 1)
		pendingWrap = false
	}

	func lineFeed() {
		pendingWrap = false
		isParkedBelowScreen = false
		if cursorRow == scrollBottom {
			screen.scrollUp(top: scrollTop, bottom: scrollBottom, attributes: attributes)
		} else if cursorRow < screen.rows - 1 {
			cursorRow += 1
		}
	}

	func moveCursor(row: Int, column: Int) {
		isParkedBelowScreen = row == screen.rows
		cursorRow = max(0, min(row, screen.rows - 1))
		cursorColumn = max(0, min(column, screen.columns - 1))
		pendingWrap = false
	}

	/// Where a vertical move counts from: the cursor's row, unless it was parked
	/// one row below the screen — see `isParkedBelowScreen`.
	var verticalOrigin: Int { isParkedBelowScreen ? screen.rows : cursorRow }

	// MARK: - Escape

	private func consumeEscape(_ byte: UInt8) {
		switch byte {
		case 0x5B: // [
			state = .csi
			resetParameters()
		case 0x5D: // ]
			state = .osc
			oscBytes = []
		case 0x5F: // _ — APC, which is where a kitty graphics command arrives
			state = .apc
			apcBytes = []
		case 0x50, 0x58, 0x5E: // DCS, SOS, PM — consumed to ST
			state = .ignore(terminator: 0x5C)
		case 0x37: // 7 — save cursor
			savedCursor = (cursorRow, cursorColumn, attributes)
			state = .ground
		case 0x38: // 8 — restore cursor
			restoreCursor()
			state = .ground
		case 0x44: // D — index
			lineFeed()
			state = .ground
		case 0x45: // E — next line
			cursorColumn = 0
			lineFeed()
			state = .ground
		case 0x4D: // M — reverse index
			isParkedBelowScreen = false
			if cursorRow == scrollTop {
				screen.scrollDown(top: scrollTop, bottom: scrollBottom, attributes: attributes)
			} else {
				cursorRow = max(0, cursorRow - 1)
			}
			state = .ground
		case 0x63: // c — full reset
			reset()
			state = .ground
		case 0x28, 0x29, 0x2A, 0x2B:
			// Charset designation (ESC ( B and friends). One designator byte
			// follows and is discarded — we always render UTF-8.
			state = .skipOne
		default:
			state = .ground
		}
	}
}

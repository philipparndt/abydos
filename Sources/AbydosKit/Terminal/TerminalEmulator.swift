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
	public private(set) var screen: TerminalScreen

	/// Cursor position within the active grid.
	public private(set) var cursorRow = 0
	public private(set) var cursorColumn = 0
	public private(set) var isCursorVisible = true

	/// Window title from OSC 0/2.
	public private(set) var title: String?

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
	private var links: [String] = []

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

	private var attributes = TerminalAttributes()
	private var savedCursor: (row: Int, column: Int, attributes: TerminalAttributes)?

	/// DECSTBM scroll region, inclusive.
	private var scrollTop = 0
	private var scrollBottom: Int

	/// Set after writing to the last column: the next character wraps. Without
	/// this, writing exactly `columns` characters would wrap one column early.
	private var pendingWrap = false

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
	private var isParkedBelowScreen = false

	/// Alternate screen (used by full-screen apps), saved main screen.
	private var alternateSaved: (screen: TerminalScreen, row: Int, column: Int)?
	public private(set) var isAlternateScreen = false

	public var applicationCursorKeys = false
	public var bracketedPaste = false

	/// Whether a program is part-way through rewriting the screen.
	///
	/// Set by mode 2026 and cleared when the program says it has finished. What
	/// is on the grid in between is half-drawn — a pane erased but not yet
	/// filled in — and drawing it is what makes a repaint flicker.
	public private(set) var isSynchronizingOutput = false

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

	public private(set) var mouseTracking: MouseTracking = .off
	/// 1004 — whether the program wants to hear about the window gaining and
	/// losing the keyboard. tmux passes it through to whatever is in the pane,
	/// which is how a full-screen program knows to stop animating.
	public private(set) var reportsFocus = false

	/// The kitty keyboard protocol's flags, and the stack a program pushes them
	/// on so it can put them back.
	///
	/// Bit 1 is the one that matters: "disambiguate escape codes", which is how
	/// a program tells Shift+Enter from Enter, or Ctrl+I from Tab. Without it
	/// both halves of each pair send the same byte and no program can tell.
	public private(set) var keyboardFlags: UInt8 = 0
	private var keyboardStack: [UInt8] = []

	/// xterm's older answer to the same problem: `CSI > 4 ; 2 m` asks for
	/// modified keys as `CSI 27 ; modifiers ; code ~`.
	public private(set) var modifyOtherKeys = 0

	/// Whether either protocol is on, in whichever form.
	public var reportsModifiedKeys: Bool { keyboardFlags & 1 != 0 || modifyOtherKeys >= 2 }

	/// What shape the cursor should be, as the program last asked (DECSCUSR).
	///
	/// Blinking is not honoured — a cursor that blinks repaints the screen
	/// twice a second whatever the program is doing — but the shape is: vim in
	/// insert mode asks for a bar, and a block there is a lie about what typing
	/// will do.
	public private(set) var cursorShape: CursorShape = .block

	public enum CursorShape: Sendable, Equatable {
		case block, underline, bar
	}

	/// 1006 — SGR encoding. The legacy encoding cannot express coordinates past
	/// column 223, so modern programs all ask for this one.
	public private(set) var sgrMouseEncoding = false

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

	private enum State {
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

	private var state = State.ground

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
	private static let parameterCapacity = 32
	private let parameterValues: UnsafeMutablePointer<Int32>
	private let componentStarts: UnsafeMutablePointer<Int32>
	private var parameterCount = 0
	private var componentTotal = 0
	private var pendingValue = 0
	private var atComponentStart = true
	/// The `?`, `>`, `<` or `=` marking a sequence as private rather than ANSI.
	private var introducer: UInt8?
	/// Intermediate bytes, such as the `$` that makes `CSI ? p` a mode query.
	private var intermediateBytes: [UInt8] = []
	private var oscBytes: [UInt8] = []
	private var apcBytes: [UInt8] = []
	/// Whether the sequence being gathered ran past the cap, in which case it
	/// is dropped whole rather than acted on short.
	private var apcOverflowed = false

	/// The pictures on the screen, and the ones a program has sent but not shown.
	///
	/// Public because drawing them is the view's job: the emulator knows where an
	/// image goes and what its pixels are, and nothing about how to put them on a
	/// screen.
	public let graphics = TerminalImageStore()

	/// Placements belonging to the screen that is not the current one.
	private var alternateGraphics: [TerminalImagePlacement] = []
	/// What `screen.discardedLineCount` was when the placements were last moved.
	private var lastDiscardedLineCount = 0

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
		switch value {
		case 0x0300...0x036F, 0x200B...0x200F, 0xFE00...0xFE0F: return 0
		case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF,
		     0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
		     0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F,
		     0xFF00...0xFF60, 0xFFE0...0xFFE6,
		     0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
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

	private func lineFeed() {
		pendingWrap = false
		isParkedBelowScreen = false
		if cursorRow == scrollBottom {
			screen.scrollUp(top: scrollTop, bottom: scrollBottom, attributes: attributes)
		} else if cursorRow < screen.rows - 1 {
			cursorRow += 1
		}
	}

	private func moveCursor(row: Int, column: Int) {
		isParkedBelowScreen = row == screen.rows
		cursorRow = max(0, min(row, screen.rows - 1))
		cursorColumn = max(0, min(column, screen.columns - 1))
		pendingWrap = false
	}

	/// Where a vertical move counts from: the cursor's row, unless it was parked
	/// one row below the screen — see `isParkedBelowScreen`.
	private var verticalOrigin: Int { isParkedBelowScreen ? screen.rows : cursorRow }

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

	// MARK: - CSI

	private func consumeCSI(_ byte: UInt8) {
		switch byte {
		case 0x30...0x39: // digits
			// Capped rather than allowed to overflow: no real sequence carries a
			// value this large, and a stream of digits must not trap.
			pendingValue = min(pendingValue * 10 + Int(byte - 0x30), 65_535)
		case 0x3B: // ;  — next component
			pushParameter()
			atComponentStart = true
		case 0x3A: // :  — next subparameter of this component
			pushParameter()
		case 0x3C...0x3F: // ? > < =
			introducer = byte
		case 0x20...0x2F: // intermediates
			intermediateBytes.append(byte)
		case 0x40...0x7E: // final byte
			pushParameter()
			executeCSI(final: byte)
			state = .ground
		default:
			state = .ground
		}
	}

	private func resetParameters() {
		parameterCount = 0
		componentTotal = 0
		// Checked rather than cleared: intermediates are rare, and this runs for
		// every escape sequence that arrives.
		if !intermediateBytes.isEmpty { intermediateBytes.removeAll(keepingCapacity: true) }
		pendingValue = 0
		atComponentStart = true
		introducer = nil
	}

	/// Closes off the number being read.
	///
	/// Called for the final byte too, so `CSI m` yields one component of 0 —
	/// which is what SGR reset is, and what splitting an empty string used to
	/// produce.
	private func pushParameter() {
		defer { pendingValue = 0 }
		guard parameterCount < Self.parameterCapacity else { return }

		if atComponentStart {
			componentStarts[componentTotal] = Int32(parameterCount)
			componentTotal += 1
			atComponentStart = false
		}
		parameterValues[parameterCount] = Int32(pendingValue)
		parameterCount += 1
	}

	/// How many `;`-separated components the sequence carried.
	private var componentCount: Int { componentTotal }

	/// A component's primary value, or 0 when it was not given.
	private func componentValue(_ index: Int) -> Int {
		guard index >= 0, index < componentTotal else { return 0 }
		return Int(parameterValues[Int(componentStarts[index])])
	}

	/// The first component, which most sequences are entirely made of.
	private var firstParameter: Int { componentValue(0) }

	/// A component's `:` subparameters, which carry variants — SGR `4:3` for a
	/// curly underline, `58:2::r:g:b` for its colour.
	private func subparameter(_ index: Int, at position: Int) -> Int? {
		guard index >= 0, index < componentTotal else { return nil }
		let start = Int(componentStarts[index]) + 1 + position
		let end = index + 1 < componentTotal
			? Int(componentStarts[index + 1])
			: parameterCount
		guard start < end else { return nil }
		return Int(parameterValues[start])
	}

	/// How many `:` subparameters a component carried.
	private func subparameterCount(_ index: Int) -> Int {
		guard index >= 0, index < componentTotal else { return 0 }
		let start = Int(componentStarts[index]) + 1
		let end = index + 1 < componentTotal
			? Int(componentStarts[index + 1])
			: parameterCount
		return Swift.max(0, end - start)
	}

	private var isPrivateSequence: Bool {
		guard let introducer else { return false }
		return (0x3C...0x3F).contains(introducer)
	}

	/// Parameter bytes that mark a sequence as private rather than ANSI.
	///
	/// The same set the parameter parser strips, so a sequence cannot be
	/// recognised as private by one and read as ANSI by the other.
	static let privateIntroducers: Set<Character> = ["?", ">", "<", "="]

	/// Final bytes whose handlers inspect the introducer themselves.
	///
	/// - `h`/`l`: DEC private modes.
	/// - `c`: primary, secondary and tertiary device attributes.
	/// - `p`: DECRQM, a mode query — tmux and modern shells probe synchronised
	///   output (mode 2026) with it and wait for the reply.
	/// - `n`: DECXCPR, the private cursor position report.
	/// - `u`: the kitty keyboard protocol — push, pop, set and query.
	/// - `m`: XTMODKEYS with `>`, which is xterm's older answer to the same
	///   question and not SGR at all.
	static let introducerAwareFinals: Set<UInt8> = [
		0x68, 0x6C, 0x63, 0x70, 0x6E, 0x75, 0x6D, // h l c p n u m
	]

	private func parameter(_ index: Int, default fallback: Int) -> Int {
		guard index < componentCount else { return fallback }
		let value = componentValue(index)
		return value == 0 ? fallback : value
	}

	private func executeCSI(final: UInt8) {
		let isPrivate = introducer == 0x3F // ?

		// A private-prefixed sequence is a different command that happens to end
		// in the same byte, not a variant of the standard one. `CSI > 4 ; 2 m`
		// is XTMODKEYS, which Claude Code sends on startup — read as SGR it says
		// "underline, dim", and every character after it came out underlined.
		//
		// Only the handlers that understand an introducer see one; everything
		// else is ignored rather than run as its ANSI namesake. A final byte
		// belongs in the set below once its handler checks the introducer
		// itself — leaving one out silently drops a query the sender is
		// blocking on, which is worse than the mis-parse this guard prevents.
		if isPrivateSequence, !Self.introducerAwareFinals.contains(final) {
			return
		}

		switch final {
		// The vertical four count from `verticalOrigin` rather than from
		// `cursorRow`, which is the same thing except after a park below the
		// screen — see `rowBelowScreen`.
		case 0x41: moveCursor(row: verticalOrigin - parameter(0, default: 1), column: cursorColumn) // A
		case 0x42: moveCursor(row: verticalOrigin + parameter(0, default: 1), column: cursorColumn) // B
		case 0x43: moveCursor(row: cursorRow, column: cursorColumn + parameter(0, default: 1)) // C
		case 0x44: moveCursor(row: cursorRow, column: cursorColumn - parameter(0, default: 1)) // D
		case 0x45: moveCursor(row: verticalOrigin + parameter(0, default: 1), column: 0) // E
		case 0x46: moveCursor(row: verticalOrigin - parameter(0, default: 1), column: 0) // F
		case 0x47, 0x60: moveCursor(row: cursorRow, column: parameter(0, default: 1) - 1) // G `
		case 0x64: moveCursor(row: parameter(0, default: 1) - 1, column: cursorColumn) // d
		case 0x48, 0x66: // H f
			moveCursor(row: parameter(0, default: 1) - 1, column: parameter(1, default: 1) - 1)
		case 0x4A: eraseInDisplay(mode: firstParameter) // J
		case 0x4B: eraseInLine(mode: firstParameter) // K
		case 0x4C: insertLines(parameter(0, default: 1)) // L
		case 0x4D: deleteLines(parameter(0, default: 1)) // M
		case 0x50: deleteCharacters(parameter(0, default: 1)) // P
		case 0x40: insertCharacters(parameter(0, default: 1)) // @
		case 0x58: eraseCharacters(parameter(0, default: 1)) // X
		case 0x53: screen.scrollUp(top: scrollTop, bottom: scrollBottom, attributes: attributes) // S
		case 0x54: screen.scrollDown(top: scrollTop, bottom: scrollBottom, attributes: attributes) // T
		case 0x71 where intermediateBytes.contains(0x20): // SP q — DECSCUSR
			// 0 and 1 are a blinking block, 2 a steady one, 3/4 underline,
			// 5/6 bar. Blink is dropped; shape is kept.
			switch parameter(0, default: 1) {
			case 0, 1, 2: cursorShape = .block
			case 3, 4: cursorShape = .underline
			case 5, 6: cursorShape = .bar
			default: break
			}
			onUpdate?()
		case 0x75 where introducer == 0x3E: // > u — push keyboard flags
			keyboardStack.append(keyboardFlags)
			if keyboardStack.count > 16 { keyboardStack.removeFirst() }
			keyboardFlags = UInt8(truncatingIfNeeded: parameter(0, default: 0))
		case 0x75 where introducer == 0x3C: // < u — pop them again
			for _ in 0..<max(1, parameter(0, default: 1)) {
				keyboardFlags = keyboardStack.popLast() ?? 0
			}
		case 0x75 where introducer == 0x3D: // = u — set, or or, or clear
			let value = UInt8(truncatingIfNeeded: parameter(0, default: 0))
			switch parameter(1, default: 1) {
			case 2: keyboardFlags |= value
			case 3: keyboardFlags &= ~value
			default: keyboardFlags = value
			}
		case 0x75 where introducer == 0x3F: // ? u — what are they now?
			onResponse?("\u{1B}[?\(keyboardFlags)u")
		case 0x6D where introducer == 0x3E: // > m — XTMODKEYS
			// `CSI > 4 ; n m` sets the level; `CSI > 4 m` puts it back.
			if parameter(0, default: 0) == 4 {
				modifyOtherKeys = parameterCount > 1 ? parameter(1, default: 0) : 0
			}
		case 0x6D: applySGR() // m
		case 0x72: // r
			let top = parameter(0, default: 1) - 1
			let bottom = componentCount > 1 ? parameter(1, default: screen.rows) - 1 : screen.rows - 1
			if top < bottom, bottom < screen.rows {
				scrollTop = max(0, top)
				scrollBottom = bottom
				moveCursor(row: scrollTop, column: 0)
			}
		case 0x68: setMode(enabled: true, isPrivate: isPrivate) // h
		case 0x6C: setMode(enabled: false, isPrivate: isPrivate) // l
		case 0x73: savedCursor = (cursorRow, cursorColumn, attributes) // s
		case 0x75: restoreCursor() // u
		case 0x6E: // n
			// Device status. A shell blocks on these, so they must be answered.
			switch firstParameter {
			case 5 where !isPrivate: onResponse?("\u{1B}[0n")   // terminal OK
			case 6:
				// DECXCPR (`CSI ? 6 n`) carries the marker back, so a sender that
				// issued both forms can tell the replies apart.
				let marker = isPrivate ? "?" : ""
				onResponse?("\u{1B}[\(marker)\(cursorRow + 1);\(cursorColumn + 1)R")
			default: break
			}
		case 0x63: // c
			// Primary and secondary device attributes are different questions and
			// need different answers. Replying to a secondary query with a primary
			// response is what made tmux and powerlevel10k leave `^[[?6c` on
			// screen: the reply was not what they were parsing, so it fell through
			// to the shell, which echoed it as input.
			if introducer == 0x3E { // >
				// Secondary DA: terminal type 0, firmware version, cartridge 0.
				onResponse?("\u{1B}[>0;95;0c")
			} else if isPrivateSequence {
				// Tertiary (`CSI = c`) and anything else private: a primary reply
				// is not an answer to the question that was asked, and an
				// unrecognised reply ends up echoed by the shell.
				break
			} else {
				// Primary DA: VT220 with 132 columns, ANSI colour.
				onResponse?("\u{1B}[?62;1;6;22c")
			}
		case 0x74: // t
			windowOperation()
		case 0x70: // p
			// DECRQM — a mode query. Answering "not recognised" is far better than
			// silence, which leaves the program waiting.
			if introducer == 0x3F, intermediateBytes.contains(0x24) { // ? and $
				let mode = firstParameter
				// 1 means set, 2 reset, 0 not recognised. A program only uses
				// synchronised output if the terminal says it has it, so this
				// one has to answer properly rather than plead ignorance.
				let state: Int
				switch mode {
				case 2026: state = isSynchronizingOutput ? 1 : 2
				default: state = 0
				}
				onResponse?("\u{1B}[?\(mode);\(state)$y")
			}
		default:
			break
		}
	}

	/// `CSI t` — the window operations that are questions rather than commands.
	///
	/// Only the three that report a size are answered. The rest of the set moves,
	/// resizes, raises and iconifies the window on the program's say-so, which is
	/// not something a terminal here is going to do.
	///
	/// A program drawing pictures needs to know how many pixels a cell is: it has
	/// to turn "this image is 300 pixels wide" into a number of columns. The
	/// window size carries it, and this is the fallback for a program that cannot
	/// read that — or is on the far side of an ssh connection, where the ioctl
	/// describes the wrong machine.
	private func windowOperation() {
		// The two that answer in pixels can only be answered once somebody has
		// said how large a cell is; the one that answers in cells always can.
		let knowsPixels = cellPixelSize.width > 0 && cellPixelSize.height > 0
		switch firstParameter {
		case 14 where knowsPixels: // Text area, in pixels.
			onResponse?("\u{1B}[4;\(screen.rows * cellPixelSize.height);\(screen.columns * cellPixelSize.width)t")
		case 16 where knowsPixels: // One cell, in pixels.
			onResponse?("\u{1B}[6;\(cellPixelSize.height);\(cellPixelSize.width)t")
		case 18: // Text area, in cells.
			onResponse?("\u{1B}[8;\(screen.rows);\(screen.columns)t")
		default:
			break
		}
	}

	private func restoreCursor() {
		guard let saved = savedCursor else { return }
		cursorRow = min(saved.row, screen.rows - 1)
		cursorColumn = min(saved.column, screen.columns - 1)
		attributes = saved.attributes
		pendingWrap = false
		isParkedBelowScreen = false
	}

	// MARK: - Modes

	private func setMode(enabled: Bool, isPrivate: Bool) {
		guard isPrivate else { return }
		for index in 0..<componentCount {
			switch componentValue(index) {
			case 1: applicationCursorKeys = enabled
			case 25: isCursorVisible = enabled
			case 1000: mouseTracking = enabled ? .click : .off
			case 1002: mouseTracking = enabled ? .buttonEvent : .off
			case 1003: mouseTracking = enabled ? .anyEvent : .off
			case 1004: reportsFocus = enabled
			case 1006: sgrMouseEncoding = enabled
			case 1049, 1047, 47:
				setAlternateScreen(enabled)
			case 2004: bracketedPaste = enabled
			case 2026:
				// Synchronised output. A program that is about to rewrite a lot
				// of the screen says so first, and says when it has finished:
				// what is shown in between is half-drawn, and showing it is what
				// makes a repaint flicker. tmux and full-screen tools use it.
				isSynchronizingOutput = enabled
			default: break
			}
		}
	}

	/// The alternate screen is a separate blank grid with no scrollback, which is
	/// what stops full-screen apps from polluting history.
	private func setAlternateScreen(_ enabled: Bool) {
		if enabled {
			guard !isAlternateScreen else { return }
			alternateSaved = (screen, cursorRow, cursorColumn)
			var fresh = TerminalScreen(rows: screen.rows, columns: screen.columns)
			fresh.maximumScrollback = 0
			screen = fresh
			cursorRow = 0
			cursorColumn = 0
			isAlternateScreen = true
			// A picture belongs to the screen it was put on. A full-screen program
			// must not find the ones the shell left behind, and the shell must find
			// them again when the program exits — the same rule its text follows.
			alternateGraphics = graphics.takePlacements()
		} else {
			guard isAlternateScreen, let saved = alternateSaved else { return }
			screen = saved.screen
			cursorRow = min(saved.row, screen.rows - 1)
			cursorColumn = min(saved.column, screen.columns - 1)
			alternateSaved = nil
			isAlternateScreen = false
			graphics.restorePlacements(alternateGraphics)
			alternateGraphics = []
		}
		// Every row on the screen is now a different row, and no write said so:
		// the grid was swapped for another one whole, taking its dirty range
		// with it.
		//
		// It has to be said out loud, because the dirty range is the only
		// account of what changed that a renderer gets. Both draw paths used to
		// get away with not being told — the document's height changes as the
		// scrollback comes and goes, and AppKit repaints a view whose frame
		// changed — but the GPU path now keeps the instances it built for each
		// row (0488) and nothing about a frame size reaches that.
		screen.markAllDirty()
		scrollTop = 0
		scrollBottom = screen.rows - 1
		isParkedBelowScreen = false
	}

	// MARK: - Erase and edit

	private func eraseInDisplay(mode: Int) {
		switch mode {
		case 0: // cursor to end
			eraseInLine(mode: 0)
			blankRows((cursorRow + 1)..<screen.rows)
			erasePictures(from: cursorRow, to: screen.rows - 1)
		case 1: // start to cursor
			eraseInLine(mode: 1)
			blankRows(0..<cursorRow)
			erasePictures(from: 0, to: cursorRow)
		case 2, 3:
			blankRows(0..<screen.rows)
			erasePictures(from: 0, to: screen.rows - 1)
		default:
			break
		}
	}

	/// Blanks whole rows in place, carrying the current background.
	///
	/// In place rather than `screen[row] = screen.blankLine(…)`: a full-screen
	/// erase is what a program does at the start of every repaint, and the
	/// replacement spelling allocated a row of cells and freed the old one for
	/// each of the forty rows.
	private func blankRows(_ rows: Range<Int>) {
		for row in rows {
			screen.blank(row: row, columns: 0..<screen.columns, attributes: attributes)
		}
	}

	/// Takes the pictures standing on erased rows with them.
	///
	/// Erasing text is how a program says "there is nothing here now", and a
	/// picture left behind by it cannot be got rid of by any means the program
	/// has — which is what left one on screen until the app was restarted.
	private func erasePictures(from first: Int, to last: Int) {
		guard first <= last else { return }
		let offset = screen.scrollback.count
		graphics.removePlacements(inRows: (offset + first)...(offset + last))
	}

	private func eraseInLine(mode: Int) {
		guard cursorRow < screen.rows else { return }
		switch mode {
		case 0:
			screen.blank(row: cursorRow, columns: cursorColumn..<screen.columns, attributes: attributes)
		case 1:
			screen.blank(row: cursorRow, columns: 0..<(cursorColumn + 1), attributes: attributes)
		case 2:
			screen.blank(row: cursorRow, columns: 0..<screen.columns, attributes: attributes)
		default:
			break
		}
	}

	private func insertLines(_ count: Int) {
		guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
		for _ in 0..<count {
			screen.scrollDown(top: cursorRow, bottom: scrollBottom, attributes: attributes)
		}
	}

	private func deleteLines(_ count: Int) {
		guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
		for _ in 0..<count {
			screen.scrollUp(top: cursorRow, bottom: scrollBottom, attributes: attributes)
		}
	}

	private func deleteCharacters(_ count: Int) {
		guard cursorRow < screen.rows else { return }
		var cells = screen[cursorRow].cells
		let removable = min(count, screen.columns - cursorColumn)
		guard removable > 0 else { return }
		cells.removeSubrange(cursorColumn..<(cursorColumn + removable))
		cells.append(contentsOf: Array(repeating: TerminalCell.blank, count: removable))
		screen[cursorRow].cells = cells
	}

	private func insertCharacters(_ count: Int) {
		guard cursorRow < screen.rows else { return }
		var cells = screen[cursorRow].cells
		let insertable = min(count, screen.columns - cursorColumn)
		guard insertable > 0 else { return }
		cells.insert(contentsOf: Array(repeating: TerminalCell.blank, count: insertable), at: cursorColumn)
		cells.removeLast(insertable)
		screen[cursorRow].cells = cells
	}

	private func eraseCharacters(_ count: Int) {
		guard cursorRow < screen.rows else { return }
		let end = min(cursorColumn + count, screen.columns)
		guard cursorColumn < end else { return }
		screen.blank(row: cursorRow, columns: cursorColumn..<end, attributes: attributes)
	}

	// MARK: - SGR

	private func applySGR() {
		let count = componentCount
		var index = 0
		while index < count {
			let value = componentValue(index)
			switch value {
			case 0: attributes = TerminalAttributes()
			case 1: attributes.bold = true
			case 2: attributes.dim = true
			case 3: attributes.italic = true
			case 4:
				// `4:0` is *no* underline; every other style — single, double,
				// curly, dotted, dashed — is one. Treating the subparameter as
				// decoration and keeping the 4 turned underline on for text that
				// asked for it to be off, which underlines whole applications.
				attributes.underline = subparameter(index, at: 0) != 0
			case 7: attributes.inverse = true
			case 8: attributes.hidden = true
			case 9: attributes.strikethrough = true
			case 21, 22: attributes.bold = false; attributes.dim = false
			case 23: attributes.italic = false
			case 24: attributes.underline = false
			case 27: attributes.inverse = false
			case 28: attributes.hidden = false
			case 29: attributes.strikethrough = false
			case 30...37: attributes.foreground = .indexed(UInt8(value - 30))
			case 39: attributes.foreground = .default
			case 40...47: attributes.background = .indexed(UInt8(value - 40))
			case 49: attributes.background = .default
			case 90...97: attributes.foreground = .indexed(UInt8(value - 90 + 8))
			case 100...107: attributes.background = .indexed(UInt8(value - 100 + 8))
			case 38, 48:
				// Extended colour, in either of the two spellings.
				//
				// `38;2;r;g;b` separates with semicolons, which is what almost
				// everything writes. `38:2:r:g:b` separates with colons, which
				// is what the standard actually specifies and what kitty's own
				// `icat` uses for the colour that names an image — so ignoring
				// it meant the placeholder cells had no id, and kitty's icat
				// drew nothing here while working everywhere else.
				//
				// The colon form may carry a colour space before the channels:
				// `38:2::r:g:b` is the full spelling and `38:2:r:g:b` the
				// common short one. Five subparameters means the long form.
				let isForeground = value == 38
				if let kind = subparameter(index, at: 0) {
					let colour: TerminalColor?
					if kind == 5 {
						colour = subparameter(index, at: 1)
							.map { .indexed(UInt8(clamping: $0)) }
					} else if kind == 2 {
						// With a colour space the channels start one later.
						let offset = subparameterCount(index) >= 5 ? 2 : 1
						if let red = subparameter(index, at: offset),
						   let green = subparameter(index, at: offset + 1),
						   let blue = subparameter(index, at: offset + 2) {
							colour = .rgb(
								UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue)
							)
						} else {
							colour = nil
						}
					} else {
						colour = nil
					}
					if let colour {
						if isForeground { attributes.foreground = colour }
						else { attributes.background = colour }
					}
					index += 1
					continue
				}
				guard index + 1 < count else { index = count; break }
				let kind = componentValue(index + 1)
				if kind == 5, index + 2 < count {
					let color = TerminalColor.indexed(UInt8(clamping: componentValue(index + 2)))
					if isForeground { attributes.foreground = color } else { attributes.background = color }
					index += 2
				} else if kind == 2, index + 4 < count {
					let color = TerminalColor.rgb(
						UInt8(clamping: componentValue(index + 2)),
						UInt8(clamping: componentValue(index + 3)),
						UInt8(clamping: componentValue(index + 4))
					)
					if isForeground { attributes.foreground = color } else { attributes.background = color }
					index += 4
				} else {
					index = count
				}
			default:
				break
			}
			index += 1
		}
	}

	// MARK: - APC

	/// APC carries the kitty graphics protocol, and nothing else anybody sends.
	///
	/// Terminated by ST, exactly as OSC is. It used to be discarded wholesale,
	/// which is why an image sent to this terminal did nothing at all.
	private func consumeAPC(_ byte: UInt8) {
		if byte == 0x1B {
			finishAPC()
			state = .escape
			return
		}
		// A stream that never terminates must not be accumulated forever. Past
		// the cap the sequence is marked and dropped whole at the end rather
		// than delivered short: a truncated payload is a picture that fails to
		// decode, or worse decodes to something wrong, and neither says why.
		guard apcBytes.count < Self.longestAPC else {
			apcOverflowed = true
			return
		}
		apcBytes.append(byte)
	}

	/// Longest APC sequence held.
	///
	/// The protocol says a chunk should be at most 4096 bytes of base64, and
	/// this was 8192 on the strength of it. kitty's own `icat` does not follow
	/// its own recommendation when it believes the terminal can cope: it sends
	/// the whole image in two chunks of 131072. Everything past 8192 was
	/// swallowed, the base64 was truncated, the PNG did not decode and no
	/// picture appeared — which is why kitty's icat drew nothing here and
	/// everything in the terminals it was tested against.
	///
	/// Eight megabytes is far past any real chunk and still a bound. What a
	/// picture actually costs is capped separately, by the image store's own
	/// budget, once it is decoded.
	private static let longestAPC = 8 * 1024 * 1024

	private func finishAPC() {
		let bytes = apcBytes
		let overflowed = apcOverflowed
		apcBytes = []
		apcOverflowed = false
		guard !overflowed else {
			state = .ground
			return
		}
		state = .ground
		// `G` is kitty's; there is no other APC to answer.
		guard bytes.first == 0x47 else { return }

		let command = KittyGraphicsCommand(Array(bytes.dropFirst()))
		let result = graphics.apply(command, context: .init(
			scrollbackCount: screen.scrollback.count,
			cursorRow: cursorRow,
			cursorColumn: cursorColumn,
			rows: screen.rows,
			columns: screen.columns
		))

		if let response = result.response { onResponse?(response) }
		if let dirty = result.dirtyRows { screen.markDirty(absolute: dirty) }
		if let advance = result.cursorAdvance {
			// Down first, then across, so a picture wider than what is left of the
			// row still lands the cursor on the row the image ends on.
			//
			// A line feed for each row rather than one move to the row it ends on.
			// A move *clamps* at the last row, and a picture placed where fewer
			// rows are left than it needs then keeps the rows it was given —
			// rows below the bottom of the screen, which are never drawn, and
			// which overlap everything the shell erases from its next prompt
			// downwards, so `ESC[J` took the picture away. A feed makes the room
			// instead: the retired lines go into the scrollback, every absolute
			// row stays where it was, and the picture comes onto the screen.
			//
			// This is what a program placing a picture is asking for. It is told
			// nothing about how tall the pane is — `icat` outside tmux sends no
			// `r` at all — so making room is the terminal's part, exactly as it
			// is when a program prints that many lines.
			for _ in 0..<advance.rows { lineFeed() }
			for _ in 0..<advance.columns {
				if cursorColumn == screen.columns - 1 {
					cursorColumn = 0
					lineFeed()
				} else {
					cursorColumn += 1
				}
			}
		}
	}

	// MARK: - OSC

	private func consumeOSC(_ byte: UInt8) {
		// Terminated by BEL or ST (ESC \).
		if byte == 0x07 {
			finishOSC()
			return
		}
		if byte == 0x1B {
			// The backslash of ST follows. Handing it back to the escape handler
			// consumes it; finishing straight to ground left it to be printed as
			// ordinary text.
			finishOSC()
			state = .escape
			return
		}
		oscBytes.append(byte)
	}

	private func finishOSC() {
		// Decoded as UTF-8, not byte-per-character. A title is arbitrary text and
		// routinely contains an emoji; treating each byte as a scalar turned
		// "\u{23F3}" into "\u{00E2}\u{008F}\u{00B3}" and put mojibake in the tab.
		let text = String(decoding: oscBytes, as: UTF8.self)
		oscBytes = []
		state = .ground

		let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		guard let code = Int(parts.first ?? "") else { return }
		let body = parts.count > 1 ? String(parts[1]) : ""

		switch code {
		case 0, 2:
			title = body
		case 4:
			applyPaletteRequest(body)
		case 8:
			applyHyperlink(body)
		case 10, 11, 12:
			applyColourRequest(code: code, body: body)
		case 52:
			applyClipboard(body)
		case TerminalOpenRequest.osc:
			applyOpenRequest(body)
		default:
			break
		}
	}

	/// OSC 440 — a program asking this window to open a file.
	///
	/// Two messages share the code. `?` is the question a command asks before
	/// it commits to anything: it is answered only by this app, so a command
	/// that gets no answer knows it is somewhere else and can fall back to
	/// `open -a` rather than writing an escape into the void. `open;…` is the
	/// request itself.
	private func applyOpenRequest(_ body: String) {
		if body == "?" {
			onResponse?(TerminalOpenRequest.reply)
			return
		}
		guard let request = TerminalOpenRequest(body: body) else { return }
		onOpenFile?(request)
	}

	/// OSC 52 — a program handing something to the clipboard.
	///
	/// Only writing. A program that asks to *read* the clipboard is refused in
	/// silence: anything that can run in a terminal could then take whatever
	/// somebody last copied, which is a password as often as not.
	private func applyClipboard(_ body: String) {
		let parts = body.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		guard parts.count == 2 else { return }
		let payload = String(parts[1])
		guard payload != "?" else { return }

		guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else { return }
		onClipboardWrite?(String(decoding: data, as: UTF8.self))
	}

	/// OSC 10, 11, 12 — the default foreground, background and cursor colours.
	///
	/// A query is what matters: a program asks what the background is so it can
	/// choose a palette that can be read against it, and one that gets no
	/// answer guesses — which is how a light theme ends up with grey-on-white
	/// diffs.
	private func applyColourRequest(code: Int, body: String) {
		let query: ColourQuery = code == 10 ? .foreground : (code == 11 ? .background : .cursor)
		for request in body.split(separator: ";") where request == "?" {
			guard let colour = colourLookup?(query) else { continue }
			onResponse?("\u{1B}]\(code);\(Self.xtermColour(colour))\u{1B}\\")
		}
	}

	/// OSC 4 — a palette entry, asked about by number.
	private func applyPaletteRequest(_ body: String) {
		let fields = body.split(separator: ";", omittingEmptySubsequences: false)
		var index = 0
		for (position, field) in fields.enumerated() {
			if position % 2 == 0 {
				index = Int(field) ?? -1
			} else if field == "?", index >= 0 {
				guard let colour = colourLookup?(.palette(index)) else { continue }
				onResponse?("\u{1B}]4;\(index);\(Self.xtermColour(colour))\u{1B}\\")
			}
		}
	}

	/// OSC 8 — the text that follows belongs to an address.
	///
	/// `OSC 8 ; params ; uri ST` opens one and `OSC 8 ; ; ST` closes it, so a
	/// program brackets the text it wants to make clickable. The parameters
	/// carry an id for linking runs that are far apart, which nothing here
	/// needs: what matters is which address a cell belongs to.
	private func applyHyperlink(_ body: String) {
		let parts = body.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		let uri = parts.count > 1 ? String(parts[1]) : ""
		guard !uri.isEmpty else {
			attributes.link = 0
			return
		}

		// Only the addresses a screenful can hold: a program printing thousands
		// of links should not grow a table nobody will look at again.
		if let existing = links.firstIndex(of: uri) {
			attributes.link = UInt16(existing + 1)
			return
		}
		guard links.count < Int(UInt16.max) - 1 else { return }
		links.append(uri)
		attributes.link = UInt16(links.count)
	}

	/// `rgb:RRRR/GGGG/BBBB`, which is the form every terminal answers in.
	static func xtermColour(_ colour: (red: Double, green: Double, blue: Double)) -> String {
		func component(_ value: Double) -> String {
			String(format: "%04x", Int((max(0, min(1, value)) * 65535).rounded()))
		}
		return "rgb:\(component(colour.red))/\(component(colour.green))/\(component(colour.blue))"
	}

	// MARK: - Lifecycle

	public func resize(rows: Int, columns: Int) {
		let delta = screen.resize(rows: rows, columns: columns, cursorRow: cursorRow)

		// The grid moved under the cursor; without this the shell's post-SIGWINCH
		// redraw lands on the wrong line and duplicates the prompt.
		cursorRow = max(0, min(cursorRow + delta, screen.rows - 1))
		cursorColumn = min(cursorColumn, screen.columns - 1)

		// The saved normal screen has to track the new size too, or leaving a
		// full-screen app after a resize restores a grid of the wrong shape.
		if var saved = alternateSaved {
			let savedDelta = saved.screen.resize(rows: rows, columns: columns, cursorRow: saved.row)
			saved.row = max(0, min(saved.row + savedDelta, saved.screen.rows - 1))
			saved.column = min(saved.column, saved.screen.columns - 1)
			alternateSaved = saved
		}

		scrollTop = 0
		scrollBottom = screen.rows - 1
		pendingWrap = false
		isParkedBelowScreen = false
		onUpdate?()
	}

	public func reset() {
		let rows = screen.rows, columns = screen.columns
		screen = TerminalScreen(rows: rows, columns: columns)
		// A fresh grid reports nothing dirty, and everything about it is. See
		// `setAlternateScreen`, which replaces the screen for the other reason.
		screen.markAllDirty()
		attributes = TerminalAttributes()
		cursorRow = 0
		cursorColumn = 0
		scrollTop = 0
		scrollBottom = rows - 1
		isCursorVisible = true
		isAlternateScreen = false
		alternateSaved = nil
		pendingWrap = false
		isParkedBelowScreen = false
		graphics.removeAll()
		alternateGraphics = []
		lastDiscardedLineCount = 0
		onUpdate?()
	}

	/// Encodes a key the way the program asked to hear about it, or nil when it
	/// has not asked and the ordinary bytes should be sent.
	///
	/// Only for keys that are otherwise ambiguous — Enter, Tab, Escape,
	/// Backspace, and anything held with Control — because that is the whole
	/// point: Shift+Enter and Enter are one byte apart in a program's mind only
	/// if the terminal says which was pressed.
	public func encodeModifiedKey(
		code: Int,
		shift: Bool = false,
		option: Bool = false,
		control: Bool = false,
		command: Bool = false
	) -> String? {
		guard reportsModifiedKeys else { return nil }

		// 1 is "no modifiers", and each one adds its bit.
		var modifiers = 1
		if shift { modifiers += 1 }
		if option { modifiers += 2 }
		if control { modifiers += 4 }
		if command { modifiers += 8 }

		// Nothing held is what it always was; a protocol that changed those
		// would break every program that only asked about the modified ones.
		guard modifiers > 1 else { return nil }

		if keyboardFlags & 1 != 0 {
			return "\u{1B}[\(code);\(modifiers)u"
		}
		return "\u{1B}[27;\(modifiers);\(code)~"
	}

	/// Encodes a key for the process, honouring application cursor key mode.
	public func encodeArrow(_ direction: ArrowKey) -> String {
		let prefix = applicationCursorKeys ? "\u{1B}O" : "\u{1B}["
		return prefix + direction.rawValue
	}

	public enum ArrowKey: String, Sendable {
		case up = "A", down = "B", right = "C", left = "D"
	}

	public enum MouseButton: Int, Sendable {
		case left = 0, middle = 1, right = 2
		/// No button held. Only meaningful with motion, where it is how a
		/// program hears that the pointer has moved over something — which is
		/// what makes a menu highlight the item under it.
		case none = 3
		case scrollUp = 64, scrollDown = 65
	}

	/// Encodes a pointer event, or nil when the program is not tracking the mouse.
	///
	/// Coordinates are 1-based. SGR encoding is preferred because the legacy form
	/// adds 32 to each coordinate and therefore cannot address a terminal wider
	/// than 223 columns.
	public func encodeMouse(
		button: MouseButton,
		row: Int,
		column: Int,
		isRelease: Bool,
		isDrag: Bool = false,
		shift: Bool = false,
		option: Bool = false,
		control: Bool = false
	) -> String? {
		guard mouseTracking != .off else { return nil }
		if isDrag, mouseTracking == .click { return nil }
		// Motion with nothing held is only wanted by a program that asked for
		// every event; the others would be flooded by it.
		if button == .none, mouseTracking != .anyEvent { return nil }

		var code = button.rawValue
		if isDrag { code += 32 }
		if shift { code += 4 }
		if option { code += 8 }
		if control { code += 16 }

		let row = max(1, min(row, screen.rows))
		let column = max(1, min(column, screen.columns))

		if sgrMouseEncoding {
			return "\u{1B}[<\(code);\(column);\(row)\(isRelease ? "m" : "M")"
		}
		// Legacy X10 encoding: release is reported as button 3.
		let legacyCode = isRelease ? 3 : code
        guard column + 32 < 256, row + 32 < 256 else { return nil }
		let columnByte = Character(UnicodeScalar(UInt8(column + 32)))
		let rowByte = Character(UnicodeScalar(UInt8(row + 32)))
		return "\u{1B}[M\(Character(UnicodeScalar(UInt8(legacyCode + 32))))\(columnByte)\(rowByte)"
	}
}

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

	private var attributes = TerminalAttributes()
	private var savedCursor: (row: Int, column: Int, attributes: TerminalAttributes)?

	/// DECSTBM scroll region, inclusive.
	private var scrollTop = 0
	private var scrollBottom: Int

	/// Set after writing to the last column: the next character wraps. Without
	/// this, writing exactly `columns` characters would wrap one column early.
	private var pendingWrap = false

	/// Alternate screen (used by full-screen apps), saved main screen.
	private var alternateSaved: (screen: TerminalScreen, row: Int, column: Int)?
	public private(set) var isAlternateScreen = false

	public var applicationCursorKeys = false
	public var bracketedPaste = false

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
	/// 1006 — SGR encoding. The legacy encoding cannot express coordinates past
	/// column 223, so modern programs all ask for this one.
	public private(set) var sgrMouseEncoding = false

	// MARK: - Parser state

	private enum State {
		case ground
		case escape
		case csi
		case osc
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
	private var parameterValues: [Int] = []
	private var componentStarts: [Int] = []
	private var pendingValue = 0
	private var atComponentStart = true
	/// The `?`, `>`, `<` or `=` marking a sequence as private rather than ANSI.
	private var introducer: UInt8?
	/// Intermediate bytes, such as the `$` that makes `CSI ? p` a mode query.
	private var intermediateBytes: [UInt8] = []
	private var oscBytes: [UInt8] = []

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
		screen = TerminalScreen(rows: rows, columns: columns)
		scrollBottom = screen.rows - 1
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
		onUpdate?()
	}

	private var isGround: Bool {
		if case .ground = state { return true }
		return false
	}

	/// Writes a run of printable ASCII, wrapping as it fills each row.
	private func putASCII(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) {
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
			screen.setCell(
				row: cursorRow,
				column: cursorColumn,
				cell: TerminalCell(scalar: 0x20, attributes: attributes)
			)
			cursorColumn = 0
			lineFeed()
		}

		screen.setCell(
			row: cursorRow,
			column: cursorColumn,
			cell: TerminalCell(scalar: scalar.value, attributes: attributes)
		)
		if width == 2 {
			screen.setCell(
				row: cursorRow,
				column: cursorColumn + 1,
				cell: TerminalCell(scalar: 0x20, attributes: attributes, isWideTrailer: true)
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
		if cursorRow == scrollBottom {
			screen.scrollUp(top: scrollTop, bottom: scrollBottom, attributes: attributes)
		} else if cursorRow < screen.rows - 1 {
			cursorRow += 1
		}
	}

	private func moveCursor(row: Int, column: Int) {
		cursorRow = max(0, min(row, screen.rows - 1))
		cursorColumn = max(0, min(column, screen.columns - 1))
		pendingWrap = false
	}

	// MARK: - Escape

	private func consumeEscape(_ byte: UInt8) {
		switch byte {
		case 0x5B: // [
			state = .csi
			resetParameters()
		case 0x5D: // ]
			state = .osc
			oscBytes = []
		case 0x50, 0x58, 0x5E, 0x5F: // DCS, SOS, PM, APC — consumed to ST
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
		parameterValues.removeAll(keepingCapacity: true)
		componentStarts.removeAll(keepingCapacity: true)
		intermediateBytes.removeAll(keepingCapacity: true)
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
		if atComponentStart {
			componentStarts.append(parameterValues.count)
			atComponentStart = false
		}
		parameterValues.append(pendingValue)
		pendingValue = 0
	}

	/// How many `;`-separated components the sequence carried.
	private var componentCount: Int { componentStarts.count }

	/// A component's primary value, or 0 when it was not given.
	private func componentValue(_ index: Int) -> Int {
		guard index >= 0, index < componentStarts.count else { return 0 }
		return parameterValues[componentStarts[index]]
	}

	/// The first component, which most sequences are entirely made of.
	private var firstParameter: Int { componentValue(0) }

	/// A component's `:` subparameters, which carry variants — SGR `4:3` for a
	/// curly underline, `58:2::r:g:b` for its colour.
	private func subparameter(_ index: Int, at position: Int) -> Int? {
		guard index >= 0, index < componentStarts.count else { return nil }
		let start = componentStarts[index] + 1 + position
		let end = index + 1 < componentStarts.count
			? componentStarts[index + 1]
			: parameterValues.count
		guard start < end else { return nil }
		return parameterValues[start]
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
	static let introducerAwareFinals: Set<UInt8> = [0x68, 0x6C, 0x63, 0x70, 0x6E] // h l c p n

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
		case 0x41: moveCursor(row: cursorRow - parameter(0, default: 1), column: cursorColumn) // A
		case 0x42: moveCursor(row: cursorRow + parameter(0, default: 1), column: cursorColumn) // B
		case 0x43: moveCursor(row: cursorRow, column: cursorColumn + parameter(0, default: 1)) // C
		case 0x44: moveCursor(row: cursorRow, column: cursorColumn - parameter(0, default: 1)) // D
		case 0x45: moveCursor(row: cursorRow + parameter(0, default: 1), column: 0) // E
		case 0x46: moveCursor(row: cursorRow - parameter(0, default: 1), column: 0) // F
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
		case 0x70: // p
			// DECRQM — a mode query. Answering "not recognised" is far better than
			// silence, which leaves the program waiting.
			if introducer == 0x3F, intermediateBytes.contains(0x24) { // ? and $
				let mode = firstParameter
				onResponse?("\u{1B}[?\(mode);0$y")
			}
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
			case 1006: sgrMouseEncoding = enabled
			case 1049, 1047, 47:
				setAlternateScreen(enabled)
			case 2004: bracketedPaste = enabled
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
		} else {
			guard isAlternateScreen, let saved = alternateSaved else { return }
			screen = saved.screen
			cursorRow = min(saved.row, screen.rows - 1)
			cursorColumn = min(saved.column, screen.columns - 1)
			alternateSaved = nil
			isAlternateScreen = false
		}
		scrollTop = 0
		scrollBottom = screen.rows - 1
	}

	// MARK: - Erase and edit

	private func eraseInDisplay(mode: Int) {
		switch mode {
		case 0: // cursor to end
			eraseInLine(mode: 0)
			for row in (cursorRow + 1)..<screen.rows {
				screen[row] = screen.blankLine(attributes: attributes)
			}
		case 1: // start to cursor
			eraseInLine(mode: 1)
			for row in 0..<cursorRow {
				screen[row] = screen.blankLine(attributes: attributes)
			}
		case 2, 3:
			for row in 0..<screen.rows {
				screen[row] = screen.blankLine(attributes: attributes)
			}
		default:
			break
		}
	}

	private func eraseInLine(mode: Int) {
		guard cursorRow < screen.rows else { return }
		var blank = TerminalCell.blank
		blank.attributes.background = attributes.background

		switch mode {
		case 0:
			for column in cursorColumn..<screen.columns { screen[cursorRow].cells[column] = blank }
		case 1:
			for column in 0...min(cursorColumn, screen.columns - 1) { screen[cursorRow].cells[column] = blank }
		case 2:
			screen[cursorRow] = screen.blankLine(attributes: attributes)
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
		var blank = TerminalCell.blank
		blank.attributes.background = attributes.background
		for column in cursorColumn..<end { screen[cursorRow].cells[column] = blank }
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
				// Extended colour: 5;n for the 256 palette, 2;r;g;b for true colour.
				let isForeground = value == 38
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
		let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		if parts.count == 2, let code = Int(parts[0]), code == 0 || code == 2 {
			title = String(parts[1])
		}
		oscBytes = []
		state = .ground
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
		onUpdate?()
	}

	public func reset() {
		let rows = screen.rows, columns = screen.columns
		screen = TerminalScreen(rows: rows, columns: columns)
		attributes = TerminalAttributes()
		cursorRow = 0
		cursorColumn = 0
		scrollTop = 0
		scrollBottom = rows - 1
		isCursorVisible = true
		isAlternateScreen = false
		alternateSaved = nil
		pendingWrap = false
		onUpdate?()
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

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
	private var parameterBuffer = ""
	private var intermediates = ""
	private var oscBuffer = ""

	/// Partial UTF-8 sequence carried between writes, since a read can split one.
	private var utf8Buffer: [UInt8] = []

	public init(rows: Int = 24, columns: Int = 80) {
		screen = TerminalScreen(rows: rows, columns: columns)
		scrollBottom = screen.rows - 1
	}

	// MARK: - Input

	public func write(_ data: Data) {
		write(Array(data))
	}

	public func write(_ bytes: [UInt8]) {
		for byte in bytes { consume(byte) }
		onUpdate?()
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
		// A continuation byte only makes sense mid-sequence.
		if !utf8Buffer.isEmpty {
			utf8Buffer.append(byte)
			if let scalar = Self.decodeUTF8(utf8Buffer) {
				utf8Buffer.removeAll()
				put(Character(scalar))
			} else if utf8Buffer.count >= 4 {
				// Malformed; drop it rather than stalling the stream.
				utf8Buffer.removeAll()
				put("\u{FFFD}")
			}
			return
		}

		switch byte {
		case 0x07: onBell?()
		case 0x08: moveCursor(row: cursorRow, column: cursorColumn - 1)
		case 0x09: tab()
		case 0x0A, 0x0B, 0x0C: lineFeed()
		case 0x0D: cursorColumn = 0; pendingWrap = false
		case 0x1B: state = .escape; parameterBuffer = ""; intermediates = ""
		case 0x00...0x06, 0x0E...0x1A, 0x1C...0x1F:
			break // Other C0 controls are not meaningful here.
		case 0x20...0x7E:
			put(Character(UnicodeScalar(byte)))
		default:
			// Start of a multi-byte UTF-8 sequence.
			utf8Buffer = [byte]
			if let scalar = Self.decodeUTF8(utf8Buffer) {
				utf8Buffer.removeAll()
				put(Character(scalar))
			}
		}
	}

	private static func decodeUTF8(_ bytes: [UInt8]) -> UnicodeScalar? {
		var decoder = UTF8()
		var iterator = bytes.makeIterator()
		switch decoder.decode(&iterator) {
		case let .scalarValue(scalar): return scalar
		default: return nil
		}
	}

	/// Writes a character at the cursor, handling wrap and double-width glyphs.
	private func put(_ character: Character) {
		if pendingWrap {
			cursorColumn = 0
			lineFeed()
			pendingWrap = false
		}

		let width = Self.displayWidth(of: character)
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
			parameterBuffer = ""
			intermediates = ""
		case 0x5D: // ]
			state = .osc
			oscBuffer = ""
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
		case 0x30...0x3F: // parameters, including ? and ;
			parameterBuffer.append(Character(UnicodeScalar(byte)))
		case 0x20...0x2F: // intermediates
			intermediates.append(Character(UnicodeScalar(byte)))
		case 0x40...0x7E: // final byte
			executeCSI(final: Character(UnicodeScalar(byte)))
			state = .ground
		default:
			state = .ground
		}
	}

	private var csiParameters: [Int] {
		parameterBuffer
			.drop(while: { $0 == "?" || $0 == ">" || $0 == "!" })
			.split(separator: ";", omittingEmptySubsequences: false)
			.map { component in
				// Colon subparameters (SGR 4:3 curly underline, 58:2::r:g:b
				// underline colour) carry a variant after the primary value.
				// Parsing the whole token yields nil, which used to fall back to
				// 0 — that is SGR "reset everything", so a single styled run
				// wiped all attributes and left the rest of the screen wrong.
				let primary = component.split(separator: ":", maxSplits: 1).first ?? ""
				return Int(primary) ?? 0
			}
	}

	private func parameter(_ index: Int, default fallback: Int) -> Int {
		let values = csiParameters
		guard index < values.count else { return fallback }
		return values[index] == 0 ? fallback : values[index]
	}

	private func executeCSI(final: Character) {
		let isPrivate = parameterBuffer.hasPrefix("?")

		switch final {
		case "A": moveCursor(row: cursorRow - parameter(0, default: 1), column: cursorColumn)
		case "B": moveCursor(row: cursorRow + parameter(0, default: 1), column: cursorColumn)
		case "C": moveCursor(row: cursorRow, column: cursorColumn + parameter(0, default: 1))
		case "D": moveCursor(row: cursorRow, column: cursorColumn - parameter(0, default: 1))
		case "E": moveCursor(row: cursorRow + parameter(0, default: 1), column: 0)
		case "F": moveCursor(row: cursorRow - parameter(0, default: 1), column: 0)
		case "G", "`": moveCursor(row: cursorRow, column: parameter(0, default: 1) - 1)
		case "d": moveCursor(row: parameter(0, default: 1) - 1, column: cursorColumn)
		case "H", "f":
			moveCursor(row: parameter(0, default: 1) - 1, column: parameter(1, default: 1) - 1)
		case "J": eraseInDisplay(mode: parameter(0, default: 0) == 0 ? csiParameters.first ?? 0 : parameter(0, default: 0))
		case "K": eraseInLine(mode: csiParameters.first ?? 0)
		case "L": insertLines(parameter(0, default: 1))
		case "M": deleteLines(parameter(0, default: 1))
		case "P": deleteCharacters(parameter(0, default: 1))
		case "@": insertCharacters(parameter(0, default: 1))
		case "X": eraseCharacters(parameter(0, default: 1))
		case "S": screen.scrollUp(top: scrollTop, bottom: scrollBottom, attributes: attributes)
		case "T": screen.scrollDown(top: scrollTop, bottom: scrollBottom, attributes: attributes)
		case "m": applySGR()
		case "r":
			let top = parameter(0, default: 1) - 1
			let bottom = csiParameters.count > 1 ? parameter(1, default: screen.rows) - 1 : screen.rows - 1
			if top < bottom, bottom < screen.rows {
				scrollTop = max(0, top)
				scrollBottom = bottom
				moveCursor(row: scrollTop, column: 0)
			}
		case "h": setMode(enabled: true, isPrivate: isPrivate)
		case "l": setMode(enabled: false, isPrivate: isPrivate)
		case "s": savedCursor = (cursorRow, cursorColumn, attributes)
		case "u": restoreCursor()
		case "n":
			// Device status. A shell blocks on these, so they must be answered.
			switch csiParameters.first ?? 0 {
			case 5: onResponse?("\u{1B}[0n")   // terminal OK
			case 6: onResponse?("\u{1B}[\(cursorRow + 1);\(cursorColumn + 1)R")
			default: break
			}
		case "c":
			// Primary and secondary device attributes are different questions and
			// need different answers. Replying to a secondary query with a primary
			// response is what made tmux and powerlevel10k leave `^[[?6c` on
			// screen: the reply was not what they were parsing, so it fell through
			// to the shell, which echoed it as input.
			if parameterBuffer.hasPrefix(">") {
				// Secondary DA: terminal type 0, firmware version, cartridge 0.
				onResponse?("\u{1B}[>0;95;0c")
			} else {
				// Primary DA: VT220 with 132 columns, ANSI colour.
				onResponse?("\u{1B}[?62;1;6;22c")
			}
		case "p":
			// DECRQM — a mode query. Answering "not recognised" is far better than
			// silence, which leaves the program waiting.
			if parameterBuffer.hasPrefix("?"), intermediates.contains("$") {
				let mode = csiParameters.first ?? 0
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
		for value in csiParameters {
			switch value {
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
		let values = csiParameters.isEmpty ? [0] : csiParameters
		var index = 0
		while index < values.count {
			let value = values[index]
			switch value {
			case 0: attributes = TerminalAttributes()
			case 1: attributes.bold = true
			case 2: attributes.dim = true
			case 3: attributes.italic = true
			case 4: attributes.underline = true
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
				guard index + 1 < values.count else { index = values.count; break }
				let kind = values[index + 1]
				if kind == 5, index + 2 < values.count {
					let color = TerminalColor.indexed(UInt8(clamping: values[index + 2]))
					if isForeground { attributes.foreground = color } else { attributes.background = color }
					index += 2
				} else if kind == 2, index + 4 < values.count {
					let color = TerminalColor.rgb(
						UInt8(clamping: values[index + 2]),
						UInt8(clamping: values[index + 3]),
						UInt8(clamping: values[index + 4])
					)
					if isForeground { attributes.foreground = color } else { attributes.background = color }
					index += 4
				} else {
					index = values.count
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
			// Expect the backslash of ST; finishing here is close enough.
			finishOSC()
			return
		}
		oscBuffer.append(Character(UnicodeScalar(byte)))
	}

	private func finishOSC() {
		let parts = oscBuffer.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
		if parts.count == 2, let code = Int(parts[0]), code == 0 || code == 2 {
			title = String(parts[1])
		}
		oscBuffer = ""
		state = .ground
	}

	// MARK: - Lifecycle

	public func resize(rows: Int, columns: Int) {
		screen.resize(rows: rows, columns: columns)
		scrollTop = 0
		scrollBottom = screen.rows - 1
		cursorRow = min(cursorRow, screen.rows - 1)
		cursorColumn = min(cursorColumn, screen.columns - 1)
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

import Foundation

/// `ESC [` — the sequences that move the cursor, scroll the screen and ask the
/// terminal about itself.
///
/// The largest of the parser's five states by a long way, and the one a bug is
/// most often in: nearly every complaint about a program drawing itself wrongly
/// ends up being one final byte here.
extension TerminalEmulator {
	// MARK: - CSI

	func consumeCSI(_ byte: UInt8) {
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

	func resetParameters() {
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
	var componentCount: Int { componentTotal }

	/// A component's primary value, or 0 when it was not given.
	func componentValue(_ index: Int) -> Int {
		guard index >= 0, index < componentTotal else { return 0 }
		return Int(parameterValues[Int(componentStarts[index])])
	}

	/// The first component, which most sequences are entirely made of.
	private var firstParameter: Int { componentValue(0) }

	/// A component's `:` subparameters, which carry variants — SGR `4:3` for a
	/// curly underline, `58:2::r:g:b` for its colour.
	func subparameter(_ index: Int, at position: Int) -> Int? {
		guard index >= 0, index < componentTotal else { return nil }
		let start = Int(componentStarts[index]) + 1 + position
		let end = index + 1 < componentTotal
			? Int(componentStarts[index + 1])
			: parameterCount
		guard start < end else { return nil }
		return Int(parameterValues[start])
	}

	/// How many `:` subparameters a component carried.
	func subparameterCount(_ index: Int) -> Int {
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

	func restoreCursor() {
		guard let saved = savedCursor else { return }
		cursorRow = min(saved.row, screen.rows - 1)
		cursorColumn = min(saved.column, screen.columns - 1)
		attributes = saved.attributes
		pendingWrap = false
		isParkedBelowScreen = false
	}
}

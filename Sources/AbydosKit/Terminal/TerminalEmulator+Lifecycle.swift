import Foundation

/// Resizing, resetting, and what the terminal sends when a key or the mouse is
/// used: the parts that are about the emulator's own life rather than about a
/// byte that arrived.
extension TerminalEmulator {
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

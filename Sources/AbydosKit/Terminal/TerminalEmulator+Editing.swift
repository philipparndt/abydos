import Foundation

/// What a CSI sequence does to the screen once it has been read: the modes it
/// turns on, the parts of the grid it blanks or shifts, and the attributes the
/// next character is written with.
///
/// Kept together because they are the three things a single escape usually
/// touches at once, and apart from the parser because none of them is about
/// bytes.
extension TerminalEmulator {
	// MARK: - Modes

	func setMode(enabled: Bool, isPrivate: Bool) {
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

	func eraseInDisplay(mode: Int) {
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

	func eraseInLine(mode: Int) {
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

	func insertLines(_ count: Int) {
		guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
		for _ in 0..<count {
			screen.scrollDown(top: cursorRow, bottom: scrollBottom, attributes: attributes)
		}
	}

	func deleteLines(_ count: Int) {
		guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
		for _ in 0..<count {
			screen.scrollUp(top: cursorRow, bottom: scrollBottom, attributes: attributes)
		}
	}

	func deleteCharacters(_ count: Int) {
		guard cursorRow < screen.rows else { return }
		var cells = screen[cursorRow].cells
		let removable = min(count, screen.columns - cursorColumn)
		guard removable > 0 else { return }
		cells.removeSubrange(cursorColumn..<(cursorColumn + removable))
		cells.append(contentsOf: Array(repeating: TerminalCell.blank, count: removable))
		screen[cursorRow].cells = cells
	}

	func insertCharacters(_ count: Int) {
		guard cursorRow < screen.rows else { return }
		var cells = screen[cursorRow].cells
		let insertable = min(count, screen.columns - cursorColumn)
		guard insertable > 0 else { return }
		cells.insert(contentsOf: Array(repeating: TerminalCell.blank, count: insertable), at: cursorColumn)
		cells.removeLast(insertable)
		screen[cursorRow].cells = cells
	}

	func eraseCharacters(_ count: Int) {
		guard cursorRow < screen.rows else { return }
		let end = min(cursorColumn + count, screen.columns)
		guard cursorColumn < end else { return }
		screen.blank(row: cursorRow, columns: cursorColumn..<end, attributes: attributes)
	}

	// MARK: - SGR

	func applySGR() {
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
}

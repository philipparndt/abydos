import AppKit
import AbydosKit

/// The pointer: selecting text, following a link, and reporting a click to a
/// program that asked to hear about them.
extension TerminalView {
	// MARK: - Mouse

	/// Grid position under a pointer event, 1-based as the protocol expects.
	/// The cell under the pointer, in absolute rows including scrollback.
	///
	/// Rounded to the nearest boundary rather than truncated, so a drag that
	/// ends halfway across a cell includes the half it covers — which is what
	/// makes selecting up to the last character possible.
	private func selectionPosition(for event: NSEvent) -> TerminalPosition {
		position(for: event, roundingToBoundary: true)
	}

	/// The character under the pointer, as opposed to the nearest gap.
	///
	/// A double-click on the right half of a cell rounds up to the next
	/// boundary, which as a character index is the cell after the one that was
	/// clicked — so the word picked was the one to its right.
	private func characterPosition(for event: NSEvent) -> TerminalPosition {
		position(for: event, roundingToBoundary: false)
	}

	private func position(for event: NSEvent, roundingToBoundary: Bool) -> TerminalPosition {
		let point = convert(event.locationInWindow, from: nil)
		let row = Int(floor((point.y - Self.verticalInset) / max(1, cellHeight)))
		let exact = (point.x - Self.horizontalInset) / max(1, cellWidth)
		let column = Int(roundingToBoundary ? exact.rounded() : exact.rounded(.down))
		let lastRow = max(0, shownLineCount - 1)
		let onRow = max(0, min(row, lastRow))
		// The row's own text rather than the grid's width. Anchoring out in the
		// blank space past the end of a line anchors at a place with nothing in
		// it: the drag begins somewhere the highlight cannot show and the copied
		// text does not include, so what is drawn and what is copied disagree
		// with where the pointer was pressed.
		//
		// Falls back to the grid when the row cannot be read at all, which is
		// the old behaviour and the only answer available.
		let limit = emulator.grid.line(at: onRow)?.usedColumns ?? emulator.metrics.columns
		return TerminalPosition(
			row: onRow,
			column: max(0, min(column, limit))
		)
	}

	/// Selection is for reading output, so a program that tracks the mouse gets
	/// the events instead — unless Shift is held, the usual escape hatch.
	var mouseSelects: Bool {
		emulator.mouseTracking == .off
	}

	/// Follows the selection when lines fall out of the top of scrollback.
	///
	/// Absolute rows are stable while the buffer only grows; once it is full,
	/// every discarded line renumbers everything above the selection, and a
	/// selection left alone would drift down the screen on its own.
	func realignSelectionForDiscardedLines() {
		// **`metrics`, not `grid`.** This runs on every delivery of output, and asking
		// for a snapshot here was half of item 0492: 1,400 snapshots a second, each of
		// them eleven thousand cells copied out of libghostty-vt, to answer one number
		// that engine already had to hand.
		let discarded = sizeAndHistory.discardedLineCount
		defer { lastDiscardedLineCount = discarded }

		let shift = discarded - lastDiscardedLineCount
		guard shift > 0, var updated = selection else { return }

		updated.anchor.row -= shift
		updated.head.row -= shift
		// Scrolled off entirely; there is nothing left to keep highlighted.
		guard max(updated.anchor.row, updated.head.row) >= 0 else {
			setSelection(nil)
			return
		}
		updated.anchor.row = max(0, updated.anchor.row)
		updated.head.row = max(0, updated.head.row)
		setSelection(updated)
	}

	func setSelection(_ new: TerminalSelection?) {
		guard new != selection else { return }
		selection = new
		repaint()
	}

	private func gridPosition(for event: NSEvent) -> (row: Int, column: Int) {
		let point = convert(event.locationInWindow, from: nil)
		let column = Int((point.x - Self.horizontalInset) / max(1, cellWidth)) + 1
		var row = Int((point.y - Self.verticalInset) / max(1, cellHeight))
		// The protocol addresses the visible grid, so scrollback is subtracted.
		row -= emulator.metrics.scrollbackCount
		return (max(1, row + 1), max(1, column))
	}

	/// Where in the window a grid cell is, for driving the pointer from a test.
	private func windowPoint(row: Int, column: Int) -> NSPoint {
		let x = Self.horizontalInset + (CGFloat(column - 1) + 0.5) * cellWidth
		let y = Self.verticalInset
			+ (CGFloat(row - 1 + emulator.metrics.scrollbackCount) + 0.5) * cellHeight
		return convert(NSPoint(x: x, y: y), to: nil)
	}

	private func mouseEventForTesting(_ type: NSEvent.EventType, row: Int, column: Int) -> NSEvent? {
		NSEvent.mouseEvent(
			with: type,
			location: windowPoint(row: row, column: column),
			modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window?.windowNumber ?? 0,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 1
		)
	}

	/// Presses the right button on a cell and holds it.
	func rightPressForTesting(row: Int, column: Int) {
		window?.makeFirstResponder(self)
		guard let down = mouseEventForTesting(.rightMouseDown, row: row, column: column) else { return }
		rightMouseDown(with: down)
	}

	/// Drags to a cell with the right button held, then lets go.
	func rightDragForTesting(row: Int, column: Int) {
		guard let event = mouseEventForTesting(.rightMouseDragged, row: row, column: column) else { return }
		rightMouseDragged(with: event)
	}

	func rightReleaseForTesting(row: Int, column: Int) {
		guard let up = mouseEventForTesting(.rightMouseUp, row: row, column: column) else { return }
		rightMouseUp(with: up)
	}

	/// Moves the pointer over a cell without pressing anything.
	func moveMouseForTesting(row: Int, column: Int) {
		guard let event = mouseEventForTesting(.mouseMoved, row: row, column: column) else { return }
		mouseMoved(with: event)
	}

	/// The visible grid, so a test can aim at the last row.
	var gridSizeForTesting: (rows: Int, columns: Int) {
		(emulator.metrics.rows, emulator.metrics.columns)
	}

	private func modifiers(_ event: NSEvent) -> (Bool, Bool, Bool) {
		let flags = event.modifierFlags
		return (flags.contains(.shift), flags.contains(.option), flags.contains(.control))
	}

	/// Forwards a pointer event, returning true when the program consumed it.
	private func forwardMouse(
		_ event: NSEvent,
		button: TerminalEmulator.MouseButton,
		isRelease: Bool,
		isDrag: Bool = false
	) -> Bool {
		// Shift is the conventional override for "let the terminal handle it",
		// which is how selection stays possible while a program grabs the mouse.
		guard !event.modifierFlags.contains(.shift) else { return false }

		let position = gridPosition(for: event)
		let (shift, option, control) = modifiers(event)
		guard let sequence = emulator.encodeMouse(
			button: button,
			row: position.row,
			column: position.column,
			isRelease: isRelease,
			isDrag: isDrag,
			shift: shift,
			option: option,
			control: control
		) else { return false }

		lastReportedMouseCell = GridCell(row: position.row, column: position.column)
		if isDrag { forwardedDragsForTesting += 1 }
		pty.write(sequence)
		return true
	}

	/// The click that activates the window also lands in the terminal.
	///
	/// macOS swallows that first click by default, so clicking into an inactive
	/// window puts the app in front and nothing else — and the click has to be
	/// made again to reach what it was aimed at. In a terminal that is worse
	/// than elsewhere: the thing being aimed at is usually a tmux pane, and
	/// selecting one is what the click is *for*. The pane change goes to tmux
	/// on its own, since a click in a terminal with mouse reporting on is
	/// forwarded to whatever is running in it.
	///
	/// Safe here because a click in a terminal moves a selection or tells tmux
	/// which pane has the keyboard. Nothing is closed, deleted or run by one,
	/// which is what the default is guarding against.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)

		// ⌘-click over a link opens it, and that is all it does: no selection
		// begins, and a program tracking the mouse is not told. It used to be a
		// bare click that opened a marked link — the one place in the pane
		// where starting a selection did something else, sprung on exactly the
		// text somebody wanted to copy. ⌘ is the modifier every other terminal
		// here uses, and it is kept from a tracking program the way iTerm2
		// keeps it, because a pane inside tmux with the mouse on is where most
		// of this project's addresses appear.
		if event.modifierFlags.contains(.command), event.clickCount == 1,
		   let link = link(atWindowPoint: event.locationInWindow) {
			LinkOpener.open(link.url)
			return
		}

		guard mouseSelects || event.modifierFlags.contains(.shift) else {
			clickSlack.pressed(at: convert(event.locationInWindow, from: nil))
			_ = forwardMouse(event, button: .left, isRelease: false)
			return
		}

		switch event.clickCount {
		case 2:
			let position = characterPosition(for: event)
			setSelection(emulator.grid.wordSelection(atRow: position.row, column: position.column))
		case 3...:
			setSelection(emulator.grid.lineSelection(atRow: characterPosition(for: event).row))
		default:
			let position = selectionPosition(for: event)
			isSelecting = true
			setSelection(TerminalSelection(
				anchor: position, head: position, isBlock: event.modifierFlags.contains(.option)
			))
		}
	}

	override func mouseUp(with event: NSEvent) {
		clickSlack.released()
		if isSelecting {
			isSelecting = false
			// A click that never moved is a click, not an empty selection.
			if selection?.isEmpty == true { setSelection(nil) }
			return
		}
		_ = forwardMouse(event, button: .left, isRelease: true)
	}

	/// Tells a program where the pointer is, when it has asked to know.
	///
	/// Only mode 1003 asks — and tmux turns it on while one of its own menus is
	/// open, which is how the item under the pointer comes to be highlighted.
	/// Without this the menu appears and then sits there, dead.
	override func mouseMoved(with event: NSEvent) {
		updateHoveredLink(at: event.locationInWindow, flags: event.modifierFlags)
		guard emulator.mouseTracking == .anyEvent else { return }
		// Not while the program is behind on what it has already been sent. A
		// motion report says where the pointer was; delivered after a long
		// paste has drained it says something untrue, and lands in the middle
		// of what was pasted.
		guard pty.pendingInputCount == 0 else { return }
		// A button is down: that is a drag, and dragging reports itself.
		guard NSEvent.pressedMouseButtons == 0 else { return }

		// Only when the pointer has actually left the cell it was last seen in
		// — including the cell it was clicked in. A menu opened by that click
		// is waiting for the pointer to move somewhere, and being told it is
		// still where it was reads as somewhere else entirely.
		let cell = gridPosition(for: event)
		let position = GridCell(row: cell.row, column: cell.column)
		guard position != lastReportedMouseCell else { return }
		lastReportedMouseCell = position

		_ = forwardMouse(event, button: .none, isRelease: false, isDrag: true)
	}


	/// ⌘ pressed or released with the pointer still.
	///
	/// The gesture is "hold ⌘ and look", and looking does not move the
	/// pointer, so the underline has to follow the key and not only the mouse.
	/// This reaches the view only while it is first responder; a pane without
	/// the keyboard gets the underline on the next pointer move, which is the
	/// moment before a click anyway.
	override func flagsChanged(with event: NSEvent) {
		if let window {
			updateHoveredLink(at: window.mouseLocationOutsideOfEventStream, flags: event.modifierFlags)
		}
		super.flagsChanged(with: event)
	}

	func updateHoveredLink(at windowPoint: NSPoint, flags: NSEvent.ModifierFlags) {
		let link = flags.contains(.command) ? self.link(atWindowPoint: windowPoint) : nil
		guard link != hoveredLink else { return }
		hoveredLink = link
		// A pointer over something clickable should say so, and stop saying so
		// the moment it leaves — or the moment ⌘ is let go.
		if link != nil { NSCursor.pointingHand.set() } else { NSCursor.iBeam.set() }
		repaint()
	}

	/// The pointer put on a cell with ⌘ held, as the events would put it, and
	/// what the pane makes of that — for `--terminal-link`.
	///
	/// Through `updateHoveredLink` and `LinkOpener`, which is the path a real
	/// ⌘ and a real click take, so a run cannot pass with the lookup wired to
	/// nothing. `underlined` is whether the range both renderers draw from is
	/// set; the rule itself is a picture, and `--screenshot` beside this is how
	/// to look at it.
	func linkReportForTesting(row: Int, column: Int, click: Bool, bare: Bool = false) -> String {
		let point = NSPoint(
			x: Self.horizontalInset + (CGFloat(column) + 0.5) * cellWidth,
			y: Self.verticalInset + (CGFloat(row) + 0.5) * cellHeight
		)
		updateHoveredLink(at: convert(point, to: nil), flags: [.command])
		var out = "LINK row=\(row) column=\(column) renderer=\(metal == nil ? "coregraphics" : "metal")"
		guard let link = hoveredLink else { return out + " none underlined=false" }
		out += " columns=\(link.columns.lowerBound)…\(link.columns.upperBound - 1)"
			+ " url=\(link.url.absoluteString) marked=\(link.isMarked) underlined=true"
		// The click as `mouseDown` receives it, with ⌘ or without, so what is
		// exercised is the handler's own order — the ⌘ branch ahead of the
		// tracking guard and of selection — and not a call to the opener.
		guard click, let window else { return out }
		let opened = LinkOpener.openedForTesting.count
		let flags: NSEvent.ModifierFlags = bare ? [] : [.command]
		if let down = NSEvent.mouseEvent(
			with: .leftMouseDown, location: convert(point, to: nil), modifierFlags: flags,
			timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
			context: nil, eventNumber: 0, clickCount: 1, pressure: 1
		) {
			mouseDown(with: down)
		}
		out += bare ? " bare-click:" : " cmd-click:"
		out += " opened=\(LinkOpener.openedForTesting.count - opened) selecting=\(isSelecting)"
			+ " tracking=\(emulator.mouseTracking != .off)"
		return out
	}

	/// The link under a point in the window, marked or printed, or nil.
	///
	/// One row is read, the one under the pointer: a marked link by the id its
	/// cell carries — the program said what it meant, and a printed address
	/// inside a marked run defers to it — and otherwise the row's own text,
	/// scanned for an address. Never the scrollback, and never per frame.
	func link(atWindowPoint windowPoint: NSPoint) -> HoveredLink? {
		let point = convert(windowPoint, from: nil)
		let row = Int((point.y - Self.verticalInset) / max(1, cellHeight))
		let column = Int((point.x - Self.horizontalInset) / max(1, cellWidth))
		guard row >= 0, column >= 0,
		      let line = emulator.grid.line(at: row),
		      column < line.cells.count
		else { return nil }

		let id = line.cells[column].attributes.link
		if id != 0, let text = emulator.link(for: id), let url = URL(string: text) {
			// The whole run the program marked, so the underline covers what
			// it meant and not the one cell the pointer happens to be on.
			var start = column, end = column + 1
			while start > 0, line.cells[start - 1].attributes.link == id { start -= 1 }
			while end < line.cells.count, line.cells[end].attributes.link == id { end += 1 }
			return HoveredLink(row: row, columns: start..<end, url: url, isMarked: true)
		}
		guard let found = line.webAddresses().first(where: { $0.columns.contains(column) }) else {
			return nil
		}
		return HoveredLink(row: row, columns: found.columns, url: found.url, isMarked: false)
	}

	/// `--wobble <points>`: the gesture that was emptying the clipboard.
	///
	/// Presses over a pane that has asked for the mouse, moves the pointer that
	/// far without meaning to, and releases. tmux copies on selection, so every
	/// drag report this sends is a chance for it to select nothing and put that
	/// nothing on the clipboard. The number to want is zero.
	///
	/// Mouse tracking is turned on here, by writing what a program writes, so
	/// the check does not need tmux running to be about tmux's problem. 1002 and
	/// not 1000: mode 1000 reports presses and releases and no motion at all, so
	/// a wobble could not reach the program under it whatever this did. 1002 is
	/// button-event tracking — motion while a button is held — which is what
	/// tmux turns on and the mode the bug lives in.
	func wobbleClickForTesting(_ points: Int) -> String {
		writeForTesting("\u{1B}[?1002h")
		guard !mouseSelects else { return "WOBBLE: the terminal is not tracking the mouse" }

		let origin = NSPoint(
			x: Self.horizontalInset + cellWidth * 8,
			y: Self.verticalInset + cellHeight * 2
		)
		func event(_ type: NSEvent.EventType, dx: CGFloat, dy: CGFloat) -> NSEvent? {
			NSEvent.mouseEvent(
				with: type,
				location: convert(NSPoint(x: origin.x + dx, y: origin.y + dy), to: nil),
				modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window?.windowNumber ?? 0,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		}
		guard let down = event(.leftMouseDown, dx: 0, dy: 0) else { return "WOBBLE: no events" }

		forwardedDragsForTesting = 0
		mouseDown(with: down)
		// Every point on the way, because a hand does not arrive at its wobble in
		// one step and each event is a separate chance to report a drag.
		for step in 1...max(1, points) {
			if let drag = event(.leftMouseDragged, dx: CGFloat(step), dy: CGFloat(step % 2)) {
				mouseDragged(with: drag)
			}
		}
		let reported = forwardedDragsForTesting
		if let up = event(.leftMouseUp, dx: CGFloat(max(1, points)), dy: 0) { mouseUp(with: up) }

		return "WOBBLE \(points)pt: \(reported) drag report(s) reached the program"
			+ " (cell \(Int(cellWidth))x\(Int(cellHeight)))"
	}

	/// A cell of the visible grid, as the mouse protocol addresses it.
	struct GridCell: Equatable {
		let row: Int
		let column: Int
	}

	override func mouseDragged(with event: NSEvent) {
		guard isSelecting else {
			// A hand that moves two points between pressing and releasing is
			// clicking, not dragging. Telling tmux otherwise makes it select
			// nothing and copy that nothing over the clipboard — see
			// `ClickSlack`, where the whole of that is written down.
			guard clickSlack.hasLeftTheSlack(
				at: convert(event.locationInWindow, from: nil),
				cellWidth: cellWidth, cellHeight: cellHeight
			) else { return }
			_ = forwardMouse(event, button: .left, isRelease: false, isDrag: true)
			return
		}
		guard var updated = selection else { return }
		updated.head = selectionPosition(for: event)
		// Read again rather than remembered from the press, so pressing or
		// releasing Option mid-drag switches the selection between a rectangle
		// and a run of lines under the pointer. Both reference terminals do
		// this, and it is the only behaviour that does not require deciding
		// which kind of selection this is before starting one.
		//
		// Nothing to resolve against `forwardMouse`: a drag either selects
		// (mouse tracking off) or is forwarded, never both, and this branch is
		// only reached while selecting.
		updated.isBlock = event.modifierFlags.contains(.option)
		setSelection(updated)

		// Dragging past an edge should keep going, the way it does in a list.
		autoscroll(with: event)
	}

	/// A drag with the right button held.
	///
	/// tmux's own menus are press-drag-release: the menu opens on the press and
	/// closes on the release, so the item under the pointer is chosen by
	/// dragging onto it. Without this the menu opens and nothing highlights,
	/// which is what right-clicking a tmux tab looked like.
	override func rightMouseDragged(with event: NSEvent) {
		guard !mouseSelects else { return }
		_ = forwardMouse(event, button: .right, isRelease: false, isDrag: true)
	}

	/// Everything past left and right, of which only the middle button is ours.
	///
	/// **`buttonNumber` is read.** macOS raises `otherMouseDown` for button 2 —
	/// the middle one — and for 3 and 4, the side buttons, and all three used to
	/// be forwarded as `.middle`. Middle is button 1 on the wire and middle
	/// click in a terminal is commonly paste, so a side button pressed over this
	/// view could put the selection into somebody's shell. `MouseButtons` says
	/// which number means what, in one place, because the window reads the same
	/// numbers to navigate on.
	///
	/// **Anything not forwarded travels up**, rather than stopping here. Both
	/// branches used to return without calling `super`: the one for a program
	/// that is not tracking the mouse, and the one where `forwardMouse` declines
	/// — shift held, or the emulator with nothing to encode. That is why a side
	/// button did nothing over a terminal even once the window knew what to do
	/// with one: the event never reached it. A view that does not act on an
	/// event has no business eating it.
	///
	/// Side buttons are not forwarded to the program at all, in any branch:
	/// `TerminalEmulator.MouseButton` is left, middle, right, none and the two
	/// scroll codes, and there is no code to send.
	override func otherMouseDown(with event: NSEvent) {
		MouseReport.say("terminal down", event, tracking: !mouseSelects)
		guard isMiddle(event), !mouseSelects,
		      forwardMouse(event, button: .middle, isRelease: false)
		else {
			super.otherMouseDown(with: event)
			return
		}
	}

	override func otherMouseUp(with event: NSEvent) {
		MouseReport.say("terminal up", event, tracking: !mouseSelects)
		guard isMiddle(event), !mouseSelects,
		      forwardMouse(event, button: .middle, isRelease: true)
		else {
			super.otherMouseUp(with: event)
			return
		}
	}

	override func otherMouseDragged(with event: NSEvent) {
		guard isMiddle(event), !mouseSelects,
		      forwardMouse(event, button: .middle, isRelease: false, isDrag: true)
		else {
			super.otherMouseDragged(with: event)
			return
		}
	}

	/// Whether this event is the one button this view forwards.
	private func isMiddle(_ event: NSEvent) -> Bool {
		MouseButtons.purpose(of: event.buttonNumber) == .middleClick
	}

	override func rightMouseDown(with event: NSEvent) {
		guard mouseSelects else {
			_ = forwardMouse(event, button: .right, isRelease: false)
			return
		}
		NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
	}

	override func rightMouseUp(with event: NSEvent) {
		guard mouseSelects else {
			_ = forwardMouse(event, button: .right, isRelease: true)
			return
		}
	}

	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		// AppKit recomputes isEnabled from the responder chain by default, which
		// discards whatever the items were built with.
		menu.autoenablesItems = false

		func item(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			item.isEnabled = enabled
			return item
		}

		menu.addItem(item("Copy", #selector(copy(_:)), enabled: selection != nil))
		menu.addItem(item("Paste", #selector(paste(_:))))
		menu.addItem(.separator())
		menu.addItem(item("Select All", #selector(selectAll(_:))))
		menu.addItem(item("Clear Selection", #selector(clearSelection), enabled: selection != nil))
		menu.addItem(.separator())
		// What ⌘K does in every other terminal, and the only thing to do with
		// a console full of a run somebody has finished reading.
		menu.addItem(item("Clear", #selector(clearConsole(_:))))
		return menu
	}

	override func scrollWheel(with event: NSEvent) {
		// Shift and the wheel is history even over a program tracking the
		// mouse, which is how every terminal lets somebody read past a TUI.
		let forTheProgram = (emulator.mouseTracking != .off && !event.modifierFlags.contains(.shift))
			|| emulator.isAlternateScreen
		guard forTheProgram else {
			MouseReport.wheel(event, steps: 0, forTheProgram: false)
			super.scrollWheel(with: event)
			return
		}

		// One formula for a wheel and another for a trackpad, because they raise
		// events of different shapes: a notch is whole on its own, and a
		// trackpad's hundred events a second are added up into cells. Before
		// `WheelSteps` every trackpad event was at least a line, and a slow drag
		// of one cell moved ten of them (reported 2026-09-10).
		if event.phase == .began { wheelSteps.reset() }
		let steps = wheelSteps.take(
			delta: event.scrollingDeltaY,
			precise: event.hasPreciseScrollingDeltas,
			cellHeight: cellHeight
		)
		MouseReport.wheel(event, steps: steps, forTheProgram: true)
		guard steps != 0 else { return }

		// A program tracking the mouse gets wheel events as button 64/65.
		if emulator.mouseTracking != .off, !event.modifierFlags.contains(.shift) {
			let button: TerminalEmulator.MouseButton = steps > 0 ? .scrollUp : .scrollDown
			let position = gridPosition(for: event)
			for _ in 0..<abs(steps) {
				if let sequence = emulator.encodeMouse(
					button: button,
					row: position.row,
					column: position.column,
					isRelease: false,
					isDrag: false,
					shift: false,
					option: false,
					control: false
				) {
					pty.write(sequence)
				}
			}
			return
		}

		// On the alternate screen there is no scrollback to move through, so the
		// wheel drives the program's own cursor instead of doing nothing.
		let key: TerminalEmulator.ArrowKey = steps > 0 ? .up : .down
		pty.write(String(repeating: emulator.encodeArrow(key), count: abs(steps)))
	}
}

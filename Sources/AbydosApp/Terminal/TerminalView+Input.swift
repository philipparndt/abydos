import AppKit
import AbydosKit

/// Keys in, and the files somebody drops on the terminal.
extension TerminalView {
	// MARK: - Input

	/// Claims the ⌘ movement keys before the menu sees them.
	///
	/// A ⌘ combination is offered around as a key equivalent first, and one
	/// that nothing claims never arrives as a keyDown. Only the three the
	/// terminal has a meaning for are taken — ⌘C, ⌘V and the rest stay with the
	/// menu, where they belong.
	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		guard window?.firstResponder === self,
		      event.modifierFlags.contains(.command),
		      let key = TerminalKeys.Key(rawValue: event.keyCode),
		      let sequence = TerminalKeys.editingSequence(for: key, option: false, command: true)
		else { return super.performKeyEquivalent(with: event) }

		isPinnedToBottom = true
		pty.write(sequence)
		scrollToBottom()
		return true
	}

	var totalRowsForTesting: Int { max(1, emulator.metrics.totalLineCount) }

	/// Where the process in the foreground of this terminal is.
	func currentDirectory() -> URL? { pty.currentDirectory() }
	func settledDirectory() -> URL? { pty.settledDirectory() }

	/// The terminal device this pane's shell is on.
	var ttyName: String? { pty.ttyName }

	/// The numbers behind "the last line is not on screen": how tall the
	/// document is, where the clip view sits in it, and how much of the grid
	/// that leaves visible.
	var geometryForTesting: String {
		let clip = enclosingScrollView?.contentView.bounds ?? .zero
		let bottomOfLastRow = Self.verticalInset
			+ CGFloat(shownLineCount) * cellHeight
		// The width as well as the height. A grid wider than the pane is
		// invisible until somebody types: every line runs off the right-hand
		// edge instead of wrapping, because the program was told the width the
		// pane used to be and is writing to it.
		let fits = Int(floor((clip.width - Self.horizontalInset * 2) / max(1, cellWidth)))
		let windowWidth = window?.frame.width ?? 0
		// The clip view's bounds *and* its frame. They are the same number
		// unless something has scaled the view, and a scaled clip view is
		// exactly how a grid comes out a factor of the backing scale too wide.
		let clipFrame = enclosingScrollView?.contentView.frame.width ?? 0
		let scale = window?.backingScaleFactor ?? 0
		return String(
			format: "engine=%@ gpu=%@ link=%@ onScreen=%@ alt=%@ rows=%d columns=%d fits=%d "
				+ "window=%.0f clipW=%.0f "
				+ "clipFrameW=%.0f scale=%.1f cell=%.1f "
				+ "frame=%.1f clip=%.1f origin=%.1f "
				+ "lastRowBottom=%.1f visible=%@ widthOK=%@",
			// Which engine emulated this pane. There are two of them now (0474),
			// so the first question about any terminal bug report is which one
			// drew it, and this is where the answer is — off the running app,
			// rather than by asking somebody to remember a setting.
			engineNameForTesting,
			// And which renderer drew it, for the same reason and one more: every
			// number `ABYDOS_METAL_PROBE` prints is zero when this says no, and a
			// probe reporting zero renders looks exactly like a renderer doing
			// nothing rather than like a renderer that was never made.
			metal != nil ? "yes" : "no",
			// The two other ways that probe reads zero while everything works.
			// The GPU path draws on the display's clock, and AppKit stops that
			// clock for a view whose window nobody can see — so a benchmark run
			// behind another window renders nothing, draws its picture through
			// the CoreGraphics path instead, screenshots perfectly, and reports
			// zeroes. That cost an hour of item 0488 before either of these
			// existed to be asked.
			displayLink != nil ? "yes" : "no",
			(window?.occlusionState.contains(.visible) ?? false) ? "yes" : "no",
			emulator.isAlternateScreen ? "yes" : "no",
			emulator.metrics.rows, emulator.metrics.columns, max(20, fits),
			windowWidth, clip.width, clipFrame, scale, cellWidth,
			frame.height, clip.height, clip.origin.y, bottomOfLastRow,
			bottomOfLastRow <= clip.origin.y + clip.height + 0.5 ? "yes" : "NO",
			max(20, fits) == emulator.metrics.columns ? "yes" : "NO"
		) + " " + winsizeForTesting
	}

	/// The engine this pane is actually using.
	///
	/// Read off the instance rather than off the setting, which is the difference
	/// between reporting what is drawing and reporting what somebody asked for.
	/// A pane made before the setting was changed keeps the engine it was made
	/// with, and this says so. Item 0474 added it and item 0485 made it true.
	var engineNameForTesting: String { engineName }

	/// The engine this pane is actually using, for anything that shows it.
	var engineName: String { type(of: emulator).engineName }

	/// Whether this pane is drawn by the engine everything is drawn by unless
	/// somebody asked otherwise.
	///
	/// **The mark is for the other one.** A mark present on every pane in the
	/// ordinary case is a mark nobody reads, and it costs the strip room it does
	/// not have — the same argument 0463 settled by showing the container and
	/// not the local copy.
	var isDrawnByTheUsualEngine: Bool { engineName == TerminalEmulator.engineName }

	/// What to say about the engine on a tab that is not drawn by the usual one,
	/// or nil when it is.
	///
	/// Three facts were indistinguishable and this separates two of them: the
	/// setting is one thing and *this pane* is another, because a pane picks its
	/// engine when it is built and keeps it — deliberately, since a running
	/// shell would lose its scrollback otherwise. The third, that the engine
	/// started at all, is said by the fallback when it happens and by this
	/// afterwards: a pane that fell back says the usual engine drew it, which is
	/// true.
	///
	/// The declared gaps go in it. They are the reason somebody turned the
	/// engine on deliberately, they live in a source file otherwise, and this is
	/// where the person running it will be looking.
	var engineNote: String? {
		guard !isDrawnByTheUsualEngine else { return nil }
		var lines = ["Drawn by \(engineName), not this app's own emulator."]
		let gaps = emulator.unimplemented
		if !gaps.isEmpty {
			lines.append("")
			lines.append("What it cannot do:")
			lines.append(contentsOf: gaps.map { "  • \($0)" })
		}
		return lines.joined(separator: "\n")
	}

	/// Builds the engine the setting asks for.
	///
	/// **The setting is read once, when a pane is made**, and not afterwards: an
	/// engine holds the scrollback, the modes and the images, and swapping one out
	/// under a running shell would throw all three away mid-session. Turning the
	/// setting on therefore applies to the next pane, which is the same rule
	/// `terminalGPURendering` follows.
	///
	/// If libghostty-vt will not start — the library missing, or
	/// `ghostty_terminal_new` failing — this falls back to ours rather than
	/// handing back an engine whose every call is a no-op. A pane that draws
	/// nothing is worse than a pane drawn by the other engine, and
	/// `--report-geometry` prints which one it got.
	/// Makes libghostty-vt answer as it does on a machine where the library will
	/// not start, for `--engine-refuses`.
	///
	/// A seam rather than a driven install: whether the library loads is a fact
	/// about this machine, and the branch that matters — the silent fall back —
	/// cannot be reached on one where it does load. The same shape as the seam
	/// in the backlog pane's offer, and off unless a driver asked.
	static var pretendsTheLibraryWillNotStart = false

	static func makeEngine(rows: Int, columns: Int) -> TerminalEngine {
		guard Settings.shared.terminalGhosttyEngine else {
			return TerminalEmulator(rows: rows, columns: columns)
		}
		guard !pretendsTheLibraryWillNotStart else {
			EngineFallback.sayOnce()
			return TerminalEmulator(rows: rows, columns: columns)
		}
		let ghostty = GhosttyTerminalEngine(rows: rows, columns: columns)
		guard ghostty.isUsable else {
			// **Silent is right for drawing and wrong for telling.** Falling
			// back rather than handing back an engine whose every call is a
			// no-op is the correct behaviour and stays; what was missing is that
			// somebody who asked for libghostty-vt and got this instead had no
			// way to find out. Said once — it is a fact about the library on
			// this machine, not about this pane, and one per pane opened would
			// be a stream of the same sentence.
			EngineFallback.sayOnce()
			return TerminalEmulator(rows: rows, columns: columns)
		}
		return ghostty
	}

	/// What the kernel says this pane is, which is what the program sizing a
	/// picture actually reads.
	///
	/// Read back off the device rather than from what was last handed to it: the
	/// claim worth checking is that the program on the other end can see the
	/// number, not that this file remembered writing it. `icat` derives how many
	/// cells a picture needs from one thing only — `ypixel / rows` and `xpixel /
	/// columns` — so a `c=`/`r=` that surprises somebody is answered here and
	/// nowhere else, and a cell of `0x0` is the terminal saying it cannot show
	/// pictures at all. 0397 had to work this out from `icat`'s own bytes; 0468
	/// wanted it from a running app and there was no way to ask.
	var winsizeForTesting: String {
		guard let reported = pty.reportedWindowSize else { return "winsize=none" }
		let cell = (
			width: reported.columns > 0 ? reported.pixelWidth / reported.columns : 0,
			height: reported.rows > 0 ? reported.pixelHeight / reported.rows : 0
		)
		return "winsize=\(reported.rows)x\(reported.columns)"
			+ " pixels=\(reported.pixelHeight)x\(reported.pixelWidth)"
			+ " ptyCell=\(cell.width)x\(cell.height)"
	}

	/// Draws what is on screen through Metal and writes it out as a PNG.
	///
	/// The same content the CoreGraphics path would draw, so the two can be put
	/// side by side.
	func renderWithMetalForTesting(to path: String) -> Bool {
		let scale = window?.backingScaleFactor ?? 2
		guard let renderer = TerminalMetalRenderer(scale: scale) else { return false }

		// A screenful, laid out as the view would.
		let rows = 40
		let width = max(bounds.width, 400)
		let height = CGFloat(rows) * cellHeight + Self.verticalInset * 2
		let screen = emulator.grid
		var lines: [(index: Int, line: TerminalLine)] = []
		for row in 0..<rows {
			guard let line = screen.line(at: row) else { continue }
			lines.append((row, line))
		}

		let background = TerminalPalette.background.components
		let frame = TerminalMetalRenderer.Frame(
			cellSize: CGSize(width: cellWidth, height: cellHeight),
			inset: CGPoint(x: Self.horizontalInset, y: Self.verticalInset),
			origin: .zero,
			background: background,
			foreground: TerminalPalette.foreground.components
		)
		renderer.buildImages(
			placements: emulator.graphics.placements
				+ placeholderPlacements(from: 0, to: screen.scrollbackCount + screen.rows),
			store: emulator.graphics,
			frame: frame
		)
		renderer.build(
			rows: lines,
			frame: frame,
			faces: faces,
			// Drawn whatever has focus: a window rendered offscreen has none,
			// and the cursor is one of the things worth being able to look at.
			cursor: .init(
				row: screen.scrollbackCount + emulator.cursorRow,
				column: emulator.cursorColumn,
				colour: TerminalPalette.cursor.components
			)
		)
		// Whatever the bell is doing right now, since that is usually the
		// reason for taking one of these offscreen.
		renderer.bell = bellState()
		return renderer.writePNG(
			to: path,
			points: SIMD2(Float(width), Float(height)),
			clear: background
		)
	}

	/// What is on the screen and in the scrollback, for a check that something
	/// typed into a terminal answered.
	var screenTextForTesting: String {
		let screen = emulator.grid
		return (0..<screen.totalLineCount)
			.compactMap { screen.line(at: $0)?.text }
			.joined(separator: "\n")
	}

	/// Feeds output straight to the emulator, bypassing the process.
	func writeForTesting(_ text: String) {
		emulator.write(text)
		displayIfNeeded()
	}

	/// Shows text that came from somewhere other than a pty.
	func append(_ text: String) {
		enqueue(Data(text.utf8), arrivedAt: Date())
	}

	@objc func clearConsole(_ sender: Any?) { clear() }

	/// Empties the screen and the scrollback, for a session starting again.
	func clear() {
		emulator.write("\u{1B}c")
		scheduleRedraw()
	}

	// MARK: - Dropping files

	/// Files dropped here are typed as paths.
	///
	/// What the terminal is running does not matter: the path arrives as
	/// keystrokes, so it works at a shell prompt and equally in an agent's
	/// prompt, which is the case this exists for.
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		guard !droppedURLs(from: sender).isEmpty else { return [] }
		isDropTarget = true
		repaint()
		return .copy
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		isDropTarget = false
		repaint()
	}

	override func draggingEnded(_ sender: NSDraggingInfo) {
		isDropTarget = false
		repaint()
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		isDropTarget = false
		repaint()

		let urls = droppedURLs(from: sender)
		guard !urls.isEmpty else { return false }

		window?.makeFirstResponder(self)
		send(TerminalDrop.text(for: urls))
		return true
	}

	private func droppedURLs(from sender: NSDraggingInfo) -> [URL] {
		let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
		let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
		return (objects as? [URL]) ?? []
	}

	override func keyDown(with event: NSEvent) {
		// **A view that shows output carries one key and drops the rest.**
		// Taking first responder means every key now arrives somewhere that used
		// to receive none, and the program behind this view is usually not
		// reading stdin — a pane somebody believes is read-only quietly
		// delivering what they typed would be a worse fault than the one ⌃C is
		// here to fix. So: the interrupt, and nothing else.
		if !runsProcess {
			let isInterrupt = TerminalKeys.isInterrupt(
				charactersIgnoringModifiers: event.charactersIgnoringModifiers,
				control: event.modifierFlags.contains(.control),
				command: event.modifierFlags.contains(.command),
				option: event.modifierFlags.contains(.option)
			)
			if let onInterrupt, isInterrupt { onInterrupt() }
			return
		}
		// ⌘K clears, as it does in Terminal and every editor's console. A
		// program is never sent it: nothing reads it, and every terminal on
		// this platform takes it for this.
		if event.modifierFlags.contains(.command),
		   event.charactersIgnoringModifiers?.lowercased() == "k" {
			clear()
			return
		}
		// ⇧⇞, ⇧⇟, ⇧Home and ⇧End read history, on the screen that has some. On
		// the alternate screen the key is the program's as it always was; a
		// trackpad was the only way through a build log before this, and on a
		// trackpad the wheel was the complaint.
		if !emulator.isAlternateScreen,
		   let motion = TerminalKeys.scrollbackMotion(
			keyCode: event.keyCode,
			shift: event.modifierFlags.contains(.shift),
			control: event.modifierFlags.contains(.control),
			option: event.modifierFlags.contains(.option),
			command: event.modifierFlags.contains(.command)
		   ) {
			scrollHistory(motion)
			return
		}
		// A dead key or an input method has to compose before there is anything
		// to send. `^` and `` ` `` on a German layout could not be typed at all
		// while every event was encoded here: they carry no character of their
		// own, so there was nothing to encode.
		if TerminalKeys.needsComposition(
			characters: event.characters,
			keyCode: event.keyCode,
			control: event.modifierFlags.contains(.control),
			command: event.modifierFlags.contains(.command),
			option: event.modifierFlags.contains(.option),
			optionAsMeta: Settings.shared.terminalOptionAsMeta,
			composing: hasMarkedText()
		) {
			composingEvent = event
			let handled = inputContext?.handleEvent(event)
			composingEvent = nil
			TerminalView.compositionRouteForTesting = handled.map { "im:\($0)" } ?? "no context"
			return
		}

		guard let bytes = encode(event: event) else { return }
		send(typed: bytes)
	}

	/// What has been typed at the program while a test is watching.
	static var typedForTesting: [String]?

	/// Where the last key went, for a test to say why nothing was composed.
	static var compositionRouteForTesting = "encoded"

	/// Writes typed text to the program, and starts the stopwatch on it.
	func send(typed text: String) {
		TerminalView.typedForTesting?.append(text)
		keyPressedAt = Date()
		keyEchoedAt = nil
		keyParsedAt = nil
		hasDrawnEcho = false
		// Typing always jumps back to the prompt, as every terminal does.
		isPinnedToBottom = true
		pty.write(text)
		scrollToBottom()
	}

	/// Records how long the last keystroke took to reach the screen.
	///
	/// Split three ways, because only the middle part is ours: the shell (and
	/// tmux, if it is in the way) has to echo the byte back before there is
	/// anything to draw at all.
	func noteKeystrokeShown() {
		guard InputProbe.enabled, let pressed = keyPressedAt, let parsed = keyParsedAt else { return }
		let now = Date()
		InputProbe.record(
			echo: (keyEchoedAt ?? parsed).timeIntervalSince(pressed),
			parse: parsed.timeIntervalSince(keyEchoedAt ?? pressed),
			draw: now.timeIntervalSince(parsed),
			total: now.timeIntervalSince(pressed)
		)
		keyPressedAt = nil
		keyEchoedAt = nil
		keyParsedAt = nil
	}

	/// Types one character as the keyboard would, for measuring.
	func typeForTesting(_ character: String) {
		guard let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window?.windowNumber ?? 0, context: nil,
			characters: character, charactersIgnoringModifiers: character,
			isARepeat: false, keyCode: 0
		) else { return }
		keyDown(with: event)
	}

	/// The kitty or xterm form of a key, when the program has asked for it.
	///
	/// Only the keys that are genuinely ambiguous. Sending every keystroke
	/// through the protocol would be correct by the letter of it and would
	/// break the shells and programs that never asked.
	private func modifiedKeySequence(for event: NSEvent) -> String? {
		guard emulator.reportsModifiedKeys else { return nil }
		let flags = event.modifierFlags

		// ⌘ belongs to the app: ⌘K clears, ⌘V pastes, and a program should not
		// see either.
		guard !flags.contains(.command) else { return nil }

		let code: Int
		switch event.keyCode {
		case 36, 76: code = 13   // Return
		case 48: code = 9        // Tab
		case 51: code = 127      // Backspace
		case 53: code = 27       // Escape
		default:
			// Anything else only when Control is held, which is where the
			// pairs live: Ctrl+I is Tab, Ctrl+M is Return, Ctrl+/ is Ctrl+_.
			guard flags.contains(.control),
			      let scalar = event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first,
			      scalar.isASCII
			else { return nil }
			code = Int(scalar.value)
		}

		// Every argument spelled out: a protocol requirement cannot carry default
		// values, and ⌘ is never passed on because the app keeps it.
		return emulator.encodeModifiedKey(
			code: code,
			shift: flags.contains(.shift),
			option: flags.contains(.option),
			control: flags.contains(.control),
			command: false
		)
	}

	/// What a key with Option held would send, for checking the wiring.
	///
	/// Through the same translation a keystroke goes through, because what was
	/// wrong was not the rule but which rule the view asked: a test of the rule
	/// alone would have passed while a German keyboard still could not type a
	/// brace.
	func optionKeyForTesting(bare: String, composed: String) -> String {
		let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.option],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: composed,
			charactersIgnoringModifiers: bare,
			isARepeat: false,
			keyCode: 0
		)
		guard let event else { return "no event" }
		return encode(event: event) ?? "nothing"
	}

	/// Feeds the view a burst of frames the way a program that has been
	/// running unwatched does, and says how many pictures came out of it.
	///
	/// Through `enqueue`, which is the path output actually takes: what was
	/// wrong was not the rule but how often it was consulted, and a test of the
	/// rule alone would have passed while the screen still replayed a minute of
	/// somebody's afternoon.
	/// Arrival times are spread backwards rather than all stamped now, and that
	/// is the whole point of the exercise: what makes this a backlog is that the
	/// frames in it were produced while nobody could see them. Twenty a second is
	/// what a spinner and a clock come to, so forty thousand of them is a little
	/// over half an hour of somebody's afternoon — and every frame but the last
	/// is history, which is what the rule has to notice (item 0491).
	func burstForTesting(frames: Int) {
		TerminalView.drawCountForTesting = 0
		let now = Date()
		for frame in 0..<frames {
			// A repaint of the kind an agent's window sends: home the cursor,
			// draw a spinner and a clock, over and over.
			let seconds = frame % 600
			let spinner = ["|", "/", "-", "\\"][frame % 4]
			let picture = "\u{1B}[H\u{1B}[2J\(spinner) working (\(seconds)s)\r\n"
			let age = Double(frames - frame) / 20
			enqueue(Data(picture.utf8), arrivedAt: now.addingTimeInterval(-age))
		}
	}

	/// Drags in the grid the way a pointer does, and says what came of it.
	///
	/// **Through `mouseDown` and `mouseDragged` with real events**, rather than
	/// by setting a selection directly, because where a press *lands* is the
	/// thing worth asking about: `position(for:)` reads a pixel, works out a
	/// column and clamps it to the row's own text, and a check that assembled a
	/// `TerminalSelection` by hand could not be wrong about any of that. It is
	/// the same reason `pressKeyForTesting` goes through `keyDown`.
	///
	/// Columns are addressed at their left edge, which is the boundary a
	/// selection rounds to; rows at their middle, which is what a row means.
	/// `optionOnPress` and `optionOnDrag` are separate so the modifier can be
	/// taken up *during* a drag, which is its own requirement: Option is read on
	/// every event rather than remembered from the press, so pressing it without
	/// releasing the button turns a run of lines into a rectangle.
	func dragForTesting(
		fromRow: Int, fromColumn: Int, toRow: Int, toColumn: Int,
		optionOnPress: Bool, optionOnDrag: Bool
	) -> String {
		func event(_ type: NSEvent.EventType, row: Int, column: Int, option: Bool) -> NSEvent? {
			let point = NSPoint(
				x: Self.horizontalInset + CGFloat(column) * cellWidth,
				y: Self.verticalInset + (CGFloat(row) + 0.5) * cellHeight
			)
			// **Shift is always held**, because the pane a drag is being driven
			// over is nearly always running tmux, and a program that has asked
			// for the mouse gets the events instead — `selects=false` in the
			// report below. Shift is the escape hatch a person uses for exactly
			// this, so it is the gesture worth driving.
			return NSEvent.mouseEvent(
				with: type,
				location: convert(point, to: nil),
				modifierFlags: option ? [.option, .shift] : [.shift],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window?.windowNumber ?? 0,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			)
		}
		guard let down = event(.leftMouseDown, row: fromRow, column: fromColumn, option: optionOnPress),
		      let drag = event(.leftMouseDragged, row: toRow, column: toColumn, option: optionOnDrag),
		      let up = event(.leftMouseUp, row: toRow, column: toColumn, option: optionOnDrag)
		else { return "no events" }

		mouseDown(with: down)
		let anchored = selection?.anchor
		let pressedAs = selection?.isBlock
		mouseDragged(with: drag)
		// The selection is read before the release, which is what clears one
		// that never moved — a click is a click and not an empty selection.
		let report = selectionReportForTesting
		mouseUp(with: up)

		// **A drag that selected nothing has to say why it selected nothing.**
		// A program that has asked for the mouse gets the events instead, a
		// pane that has not been laid out has no cells to land in, and both come
		// back as "selection=none" if the report only describes the selection.
		return "tracking=\(emulator.mouseTracking) selects=\(mouseSelects) "
			+ "cell=\(Int(cellWidth))x\(Int(cellHeight)) rows=\(shownLineCount) "
			+ "anchored=\(anchored.map { "\($0.row),\($0.column)" } ?? "nothing") "
			+ "pressedAsBlock=\(pressedAs.map(String.init) ?? "nothing") "
			+ report
	}

	/// What is selected, what each row of it is highlighted across, and what it
	/// would copy.
	///
	/// The per-row ranges are the half a screenshot cannot be read for: an
	/// overlay of translucent colour over ragged text is exactly the thing this
	/// change is about, and "does it stop at the text" is a number.
	var selectionReportForTesting: String {
		guard let selection, !selection.isEmpty else { return "selection=none" }
		let (start, end) = selection.ordered
		var rows: [String] = []
		for row in start.row...end.row {
			guard let line = emulator.grid.line(at: row) else { continue }
			let range = selectionRange(on: line, atRow: row)
			rows.append("\(row):" + (range.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "none")
				+ "/\(line.usedColumns)")
		}
		let copied = emulator.grid.text(in: selection)
			.replacingOccurrences(of: "\n", with: "⏎")
		return "block=\(selection.isBlock) "
			+ "from=\(start.row),\(start.column) to=\(end.row),\(end.column) "
			+ "rows=[\(rows.joined(separator: " "))] copied=\"\(copied)\""
	}

	/// Presses keys by their key code and says what each one did.
	///
	/// Through `keyDown`, not through the encoder: what was wrong was never the
	/// encoding but that the layout was never asked, and a test that called the
	/// encoder would have agreed with the view while `^` still typed nothing.
	/// The layout itself does the composing here — whichever one the machine is
	/// set to — so this shows what the keyboard in front of the user does.
	func deadKeyForTesting(presses: [(code: UInt16, shift: Bool)]) -> String {
		NSApp.activate(ignoringOtherApps: true)
		window?.makeKeyAndOrderFront(nil)
		window?.makeFirstResponder(self)
		var report: [String] = []
		for press in presses {
			TerminalView.typedForTesting = []
			TerminalView.compositionRouteForTesting = "encoded"
			// Built as a real keyboard event rather than by hand: the input
			// manager translates through the layout using what the event source
			// carries, and an NSEvent made from parts carries none of it — it
			// accepts the key and composes nothing, which looks exactly like the
			// bug this is here to catch.
			guard let raw = CGEvent(
				keyboardEventSource: CGEventSource(stateID: .combinedSessionState),
				virtualKey: press.code,
				keyDown: true
			) else { return "no event" }
			if press.shift { raw.flags.insert(.maskShift) }
			guard let event = NSEvent(cgEvent: raw) else { return "no event" }
			keyDown(with: event)
			let typed = (TerminalView.typedForTesting ?? []).joined()
			report.append(
				"key \(press.code): \(TerminalView.compositionRouteForTesting) "
					+ "marked=\(markedText.isEmpty ? "-" : markedText) "
					// Escaped: a carriage return typed at the end of the report
					// would print as the cursor going back to the margin, which
					// reads as nothing having been sent at all.
					+ "typed=\(typed.isEmpty ? "-" : typed.debugDescription)"
			)
		}
		TerminalView.typedForTesting = nil
		return report.joined(separator: " | ")
	}

	/// Translates a key event into the bytes a terminal would send.
	func encode(event: NSEvent) -> String? {
		let flags = event.modifierFlags

		// Shift+Tab, ahead of the protocols rather than through them. `CSI Z` is
		// what the advertised terminfo promises for `kcbt` and what both
		// protocols' legacy tables give; `TerminalKeys.backtabSequence` has the
		// argument and what the bare tab this used to send cost.
		if let backtab = TerminalKeys.backtabSequence(
			keyCode: event.keyCode,
			shift: flags.contains(.shift),
			control: flags.contains(.control),
			option: flags.contains(.option),
			command: flags.contains(.command)
		) {
			return backtab
		}

		// A program that asked to be told which key was pressed, rather than
		// which byte it maps to, gets that first: Shift+Enter and Enter are one
		// byte apart otherwise, and no program can tell them apart.
		if let modified = modifiedKeySequence(for: event) { return modified }

		// Shift+Return breaks the line as ⌥⏎ does, for a program that has not
		// asked for the protocol above. `TerminalKeys.shiftReturnSequence` has
		// the argument.
		if let newline = TerminalKeys.shiftReturnSequence(
			keyCode: event.keyCode,
			shift: flags.contains(.shift),
			control: flags.contains(.control),
			option: flags.contains(.option),
			command: flags.contains(.command)
		) {
			return newline
		}

		// Keys with a fixed sequence, and the Option-as-Meta rule that goes with
		// them. Applied here rather than after the switch: returning early was
		// how ⌥Return came to send a bare carriage return, which submits the
		// line instead of breaking it.
		if let key = TerminalKeys.Key(rawValue: event.keyCode) {
			// Modified navigation first: ⌥← is a word movement, not an arrow
			// with a prefix, and ⌘← is the start of the line.
			if let editing = TerminalKeys.editingSequence(
				for: key,
				option: flags.contains(.option),
				command: flags.contains(.command)
			) {
				return editing
			}

			let base: String?
			switch key {
			case .upArrow:    base = emulator.encodeArrow(.up)
			case .downArrow:  base = emulator.encodeArrow(.down)
			case .rightArrow: base = emulator.encodeArrow(.right)
			case .leftArrow:  base = emulator.encodeArrow(.left)
			default:          base = TerminalKeys.sequence(for: key)
			}

			guard let base else { return nil }
			return TerminalKeys.applyingMeta(base, key: key, optionHeld: flags.contains(.option))
		}

		guard var characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }

		if flags.contains(.control) {
			// ⌃A…⌃Z and the handful of punctuation controls.
			guard let scalar = characters.lowercased().unicodeScalars.first else { return nil }
			switch scalar {
			case "a"..."z":
				return String(UnicodeScalar(scalar.value - 96)!)
			case "[": return "\u{1B}"
			case "\\": return "\u{1C}"
			case "]": return "\u{1D}"
			case " ", "2": return "\u{0}"
			default: return nil
			}
		}

		// Option: what the layout composed, or Meta when it composed nothing.
		// A German keyboard reaches `{` at ⌥8 and could not type one at all
		// while this prefixed ESC unconditionally.
		if flags.contains(.option) {
			return TerminalKeys.optionOutput(
				composed: event.characters,
				bare: characters,
				asMeta: Settings.shared.terminalOptionAsMeta
			)
		}

		// Otherwise send what was actually typed, so dead keys and IME work.
		if let typed = event.characters, !typed.isEmpty {
			characters = typed
		}
		return characters
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// The differential test for item 0474: the same bytes through both engines,
/// compared cell for cell.
///
/// This is the whole experiment, and it is cheap because the fixtures already
/// exist — `tmux-prompt.bin`, `tmux-prompt-repaint.bin` and `return-burst.bin`
/// were captured for 0404, 0397 and 0468, from real programs in a real pane.
/// Anything two independent emulators disagree about on real bytes is worth
/// knowing about, whichever of them turns out to be wrong.
///
/// These assert only what both engines are *meant* to agree on. Where they
/// legitimately differ — libghostty-vt reflows on resize and we truncate, it
/// prunes scrollback by bytes and we by lines — the test prints rather than
/// fails, because a difference there is a fact about the two designs and not a
/// regression in either.
struct GhosttyEngineTests {
	private func fixture(_ name: String) throws -> Data {
		let url = try #require(
			Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
			"fixture \(name) is missing")
		return try Data(contentsOf: url)
	}

	/// The rows both engines produced, as text, so a mismatch names the row.
	private func rowsOf(_ grid: TerminalGridReading, from: Int, count: Int) -> [String] {
		(from..<(from + count)).map { grid.line(at: $0)?.text ?? "<none>" }
	}

	@Test func aBasicGridAgreesWithOurs() {
		let ours = TerminalEmulator(rows: 6, columns: 20)
		let theirs = GhosttyTerminalEngine(rows: 6, columns: 20)
		try? #require(theirs.isUsable)

		let script = "hello\r\nworld\r\n\u{1B}[1;31mred bold\u{1B}[0m\r\nplain"
		ours.write(script)
		theirs.write(script)

		let a = ours.grid, b = theirs.grid
		#expect(a.rows == b.rows)
		#expect(a.columns == b.columns)
		#expect(rowsOf(a, from: a.scrollbackCount, count: 4)
			== rowsOf(b, from: b.scrollbackCount, count: 4))
		#expect(ours.cursorRow == theirs.cursorRow)
		#expect(ours.cursorColumn == theirs.cursorColumn)

		// The style, not just the text: a colour that arrived as a palette index
		// has to still be a palette index, because the editor's theme is what
		// decides what index 1 looks like.
		let ourRed = a.line(at: a.scrollbackCount + 2)?.cells[0].attributes
		let theirRed = b.line(at: b.scrollbackCount + 2)?.cells[0].attributes
		#expect(ourRed?.bold == true)
		#expect(theirRed?.bold == true)
		#expect(ourRed?.foreground == theirRed?.foreground)
	}

	/// Wide glyphs and combining marks, which is where a cell model shows.
	@Test func wideAndCombiningCellsLineUp() {
		let ours = TerminalEmulator(rows: 4, columns: 20)
		let theirs = GhosttyTerminalEngine(rows: 4, columns: 20)
		try? #require(theirs.isUsable)

		let script = "aあb\r\ne\u{301}f"
		ours.write(script)
		theirs.write(script)

		let a = ours.grid, b = theirs.grid
		let ourRow = a.line(at: a.scrollbackCount)
		let theirRow = b.line(at: b.scrollbackCount)
		// The wide glyph occupies two columns in both, and the second is a
		// trailer in both.
		#expect(ourRow?.cells[1].scalar == theirRow?.cells[1].scalar)
		#expect(ourRow?.cells[2].isWideTrailer == true)
		#expect(theirRow?.cells[2].isWideTrailer == true)
		#expect(ourRow?.text == theirRow?.text)

		// The combining mark belongs to the cell before it, not a cell of its own.
		#expect(b.line(at: b.scrollbackCount + 1)?.cells[0].combining == "e\u{301}")
		#expect(a.line(at: a.scrollbackCount + 1)?.text
			== b.line(at: b.scrollbackCount + 1)?.text)
	}

	/// 0468's fixture, and the reason this item exists at all.
	///
	/// `return-burst.bin` is a real capture of Return pressed many times, which
	/// is the shape 0468's clamped cursor advance got wrong. What is asserted is
	/// that both engines put the same number of lines in history for the same
	/// bytes — the count 0468 turned on.
	@Test func theReturnBurstScrollsTheSameAmountInBothEngines() throws {
		let data = try fixture("return-burst.bin")
		let ours = TerminalEmulator(rows: 30, columns: 100)
		let theirs = GhosttyTerminalEngine(rows: 30, columns: 100)
		try #require(theirs.isUsable)

		ours.write(data)
		theirs.write(data)

		let a = ours.grid, b = theirs.grid
		let lineFeeds = data.filter { $0 == 0x0A }.count
		// Ours is exact here and 0468 is why. libghostty-vt keeps a byte-budgeted
		// scrollback rather than a line-budgeted one, so it may hold a different
		// number of retired lines; what must match is that neither *loses* the
		// burst.
		#expect(a.totalLineCount == lineFeeds + 1)
		#expect(b.totalLineCount >= b.rows)
		print("BURST ours=\(a.totalLineCount) theirs=\(b.totalLineCount) linefeeds=\(lineFeeds)")

		// The last 30 rows are the ones on screen, and they must be identical:
		// whatever either engine did with history, the visible pane is the thing
		// somebody looks at.
		#expect(rowsOf(a, from: a.totalLineCount - 30, count: 30)
			== rowsOf(b, from: b.totalLineCount - 30, count: 30))
	}

	/// tmux over a *scrolling* pane, which both engines get identically right.
	///
	/// 30 rows, tmux drawing its prompt where the cursor already is. Every one of
	/// the 30 visible rows agrees, which is the reassuring half of the
	/// comparison: on ordinary output, absolute addressing, erases and scrolling,
	/// two independently written emulators produce the same grid from 30 KB of
	/// real tmux.
	@Test func tmuxOverAScrollingPaneAgreesEntirely() throws {
		let data = try fixture("tmux-prompt.bin")
		let ours = TerminalEmulator(rows: 30, columns: 100)
		let theirs = GhosttyTerminalEngine(rows: 30, columns: 100)
		try #require(theirs.isUsable)

		ours.write(data)
		theirs.write(data)

		let a = ours.grid, b = theirs.grid
		let ourRows = rowsOf(a, from: a.totalLineCount - 30, count: 30)
		let theirRows = rowsOf(b, from: b.totalLineCount - 30, count: 30)
		let differing = zip(ourRows, theirRows).enumerated()
			.filter { $0.element.0 != $0.element.1 }.map(\.offset)
		#expect(differing.isEmpty, "rows \(differing) differ")
		#expect(ours.cursorRow == theirs.cursorRow)
		#expect(ours.cursorColumn == theirs.cursorColumn)
	}

	/// **The one real disagreement, and it is 0404 all over again.**
	///
	/// tmux parks the cursor one row *below* the screen — `CSI 25 d` on 24 rows —
	/// and then draws its prompt with a relative `CSI A` counted from that park.
	/// 0404 established that this app has to remember the park where tmux put it:
	/// a terminal that clamps the park to the last row and then moves up from the
	/// clamp draws the prompt one row too high, over the pane's own output. That
	/// was the reported fault, and fixing it is why `tmux-prompt-repaint.bin`
	/// exists.
	///
	/// **libghostty-vt clamps.** So on this capture it puts tmux's prompt on row
	/// 22 instead of row 23, over the line the pane had just painted — the exact
	/// symptom 0404 was filed for.
	///
	/// This is the finding that matters most in item 0474, because it points the
	/// opposite way to the item's premise. The premise was that an engine a
	/// thousand people use daily gets this class of thing right and we do not.
	/// Here we are right and it is wrong, and the reason is that **this app turns
	/// tmux's status bar off**, which is unusual: with the bar on, tmux draws its
	/// prompts on the bar and never parks below a pane, so nobody else's terminal
	/// is asked this question.
	///
	/// Asserted as a *known difference* rather than as agreement, so that it
	/// fails loudly if libghostty-vt ever changes its mind — at which point this
	/// test becomes the evidence that the engine got better.
	@Test func libghosttyClampsTheOffScreenParkAndWeDoNot() throws {
		let ours = TerminalEmulator(rows: 24, columns: 60)
		let theirs = GhosttyTerminalEngine(rows: 24, columns: 60)
		try #require(theirs.isUsable)

		let data = TmuxPromptTests.untilTheFirstPromptDraw(of: TmuxPromptTests.repainting)
		ours.write(data)
		theirs.write(data)

		// Ours: the prompt on the last row, the pane's output above it. 0404.
		#expect(ours.grid.line(at: 23)?.text.hasPrefix("(rename-window) ") == true)
		#expect(ours.grid.line(at: 22)?.text.hasPrefix("PAINT ") == true)
		// Theirs: one row too high, over the pane.
		#expect(theirs.grid.line(at: 22)?.text.hasPrefix("(rename-window) ") == true)
		#expect(theirs.cursorRow == 22)
		#expect(ours.cursorRow == 23)
	}

	/// The same disagreement with no tmux in it, which is the rule underneath:
	/// a park one row below the screen is where the next vertical move counts
	/// from, even though the cursor itself sits on the last row.
	@Test func theParkRuleIsWhereTheTwoEnginesDiffer() throws {
		let ours = TerminalEmulator(rows: 5, columns: 10)
		let theirs = GhosttyTerminalEngine(rows: 5, columns: 10)
		try #require(theirs.isUsable)

		for engine: TerminalEngine in [ours, theirs] {
			engine.write("\u{1B}[6d")   // park one row below a five-row screen
			engine.write("\u{1B}[A")    // up one from there
			engine.write("X")
		}
		// Ours counts from the park: up one from row 6 is row 5, the last row.
		#expect(ours.grid.line(at: 4)?.text == "X")
		// libghostty-vt counts from the clamp: up one from row 5 is row 4.
		#expect(theirs.grid.line(at: 3)?.text == "X")
	}

	/// The engine says what it cannot do, rather than drawing something
	/// plausible. This is the condition for the option being safe to ship
	/// half-built.
	@Test func theGhosttyEngineDeclaresWhatIsMissing() {
		let theirs = GhosttyTerminalEngine(rows: 4, columns: 10)
		theirs.cellPixelSize = (width: 10, height: 20)
		// Three entries and each is a refusal or a named divergence, not a guess:
		// OSC 440 does nothing at all, modifyOtherKeys sends the ordinary bytes
		// rather than a sequence nobody asked for, and the tmux prompt row is
		// *named* rather than a silently different pane. Item 0485 emptied the rest.
		#expect(theirs.unimplemented.count == 3)
		#expect(theirs.unimplemented.contains { $0.contains("OSC 440") })
		#expect(theirs.unimplemented.contains { $0.contains("status bar is off") })
		#expect(theirs.unimplemented.contains { $0.contains("modifyOtherKeys") })
		// Kitty graphics is no longer on the list, which is item 0485's step one.
		#expect(!theirs.unimplemented.contains { $0.contains("Kitty graphics: images") })
		// And ours claims nothing missing, because every terminal test in the
		// suite was written against it.
		#expect(TerminalEmulator(rows: 4, columns: 10).unimplemented.isEmpty)
	}

	/// A pane with no cell size says so rather than pretending it could place a
	/// picture. A cell of no pixels is how a terminal tells `icat` it cannot show
	/// one, and 0468 is what happens when that answer is wrong.
	@Test func anEngineWithNoCellSizeSaysPicturesCannotBePlaced() {
		let theirs = GhosttyTerminalEngine(rows: 4, columns: 10)
		#expect(theirs.unimplemented.contains { $0.contains("no cell size") })
	}

	// MARK: - The sixteen members, both engines held to one answer (item 0485)

	/// Both engines, the same bytes, the same modes.
	///
	/// These are what `TerminalView` asks before it decides whether to wrap a
	/// paste, report focus, hold a frame, send a mouse event or draw a bar
	/// cursor — so a disagreement here is a pane that behaves differently under
	/// the setting, which is the whole thing item 0485 is trying not to ship.
	@Test func theModesAgreeInBothEngines() throws {
		let ours = TerminalEmulator(rows: 6, columns: 20)
		let theirs = GhosttyTerminalEngine(rows: 6, columns: 20)
		try #require(theirs.isUsable)

		for engine: TerminalEngine in [ours, theirs] {
			#expect(engine.bracketedPaste == false)
			#expect(engine.reportsFocus == false)
			#expect(engine.isSynchronizingOutput == false)
			#expect(engine.mouseTracking == .off)
			#expect(engine.cursorShape == .block)
		}

		// Everything a program turns on, in one go.
		let on = "\u{1B}[?2004h\u{1B}[?1004h\u{1B}[?1003h\u{1B}[?2026h\u{1B}[5 q"
		ours.write(on)
		theirs.write(on)
		for engine: TerminalEngine in [ours, theirs] {
			#expect(engine.bracketedPaste == true)
			#expect(engine.reportsFocus == true)
			#expect(engine.isSynchronizingOutput == true)
			#expect(engine.mouseTracking == .anyEvent)
			#expect(engine.cursorShape == .bar)
		}

		// And off again, because a mode that cannot be cleared freezes a pane:
		// synchronised output in particular stops the screen being drawn at all.
		let off = "\u{1B}[?2004l\u{1B}[?1004l\u{1B}[?1003l\u{1B}[?2026l\u{1B}[2 q"
		ours.write(off)
		theirs.write(off)
		for engine: TerminalEngine in [ours, theirs] {
			#expect(engine.bracketedPaste == false)
			#expect(engine.reportsFocus == false)
			#expect(engine.isSynchronizingOutput == false)
			#expect(engine.mouseTracking == .off)
			#expect(engine.cursorShape == .block)
		}
	}

	/// The three weaker mouse modes, which the view treats differently: a program
	/// that asked for presses only must not be sent every movement.
	@Test func eachMouseTrackingModeIsReportedInBothEngines() throws {
		for (mode, expected) in [
			(1000, TerminalMouseTracking.click),
			(1002, .buttonEvent),
			(1003, .anyEvent),
		] {
			let ours = TerminalEmulator(rows: 6, columns: 20)
			let theirs = GhosttyTerminalEngine(rows: 6, columns: 20)
			try #require(theirs.isUsable)
			ours.write("\u{1B}[?\(mode)h")
			theirs.write("\u{1B}[?\(mode)h")
			#expect(ours.mouseTracking == expected)
			#expect(theirs.mouseTracking == expected, "mode \(mode)")
		}
	}

	/// Arrow keys, which change shape when a program asks for application cursor
	/// keys — and every full-screen program does.
	@Test func arrowKeysEncodeTheSameInBothEngines() throws {
		let ours = TerminalEmulator(rows: 6, columns: 20)
		let theirs = GhosttyTerminalEngine(rows: 6, columns: 20)
		try #require(theirs.isUsable)

		for direction: TerminalArrowKey in [.up, .down, .left, .right] {
			#expect(ours.encodeArrow(direction) == theirs.encodeArrow(direction))
			#expect(ours.encodeArrow(direction).hasPrefix("\u{1B}["))
		}

		ours.write("\u{1B}[?1h")
		theirs.write("\u{1B}[?1h")
		for direction: TerminalArrowKey in [.up, .down, .left, .right] {
			#expect(ours.encodeArrow(direction) == theirs.encodeArrow(direction))
			#expect(ours.encodeArrow(direction).hasPrefix("\u{1B}O"), "application cursor keys")
		}
	}

	/// The kitty keyboard protocol, which is how a program tells Shift+Enter from
	/// Enter. Both engines must answer nothing until it is asked for, and then the
	/// same bytes.
	@Test func theKittyKeyboardProtocolEncodesTheSameInBothEngines() throws {
		let ours = TerminalEmulator(rows: 6, columns: 20)
		let theirs = GhosttyTerminalEngine(rows: 6, columns: 20)
		try #require(theirs.isUsable)

		// Nothing asked for: the caller's own key handling keeps the keystroke.
		for engine: TerminalEngine in [ours, theirs] {
			#expect(engine.reportsModifiedKeys == false)
			#expect(engine.encodeModifiedKey(
				code: 13, shift: true, option: false, control: false, command: false) == nil)
		}

		ours.write("\u{1B}[>1u")
		theirs.write("\u{1B}[>1u")
		for engine: TerminalEngine in [ours, theirs] {
			#expect(engine.reportsModifiedKeys == true)
		}
		// Shift+Enter, Ctrl+I and Ctrl+A — the pairs the protocol exists for.
		for (code, shift, control) in [(13, true, false), (9, false, true), (97, false, true)] {
			let a = ours.encodeModifiedKey(
				code: code, shift: shift, option: false, control: control, command: false)
			let b = theirs.encodeModifiedKey(
				code: code, shift: shift, option: false, control: control, command: false)
			#expect(a == b, "code \(code): ours \(a ?? "nil") theirs \(b ?? "nil")")
			#expect(a != nil)
		}
		// Nothing held stays what it always was, in both.
		#expect(ours.encodeModifiedKey(
			code: 13, shift: false, option: false, control: false, command: false) == nil)
		#expect(theirs.encodeModifiedKey(
			code: 13, shift: false, option: false, control: false, command: false) == nil)
	}

	/// **xterm's `modifyOtherKeys` is the one named divergence in key encoding**,
	/// and this test is what keeps it honest.
	///
	/// Ours honours `CSI > 4 ; 2 m`. libghostty-vt does not report whether it is
	/// on: no `GHOSTTY_TERMINAL_DATA_*` kind carries it, and its own key encoder
	/// cannot be used as an oracle because that encoder emits the
	/// `CSI 27;mods;code~` form whether or not the program asked — measured, and
	/// written down in `GhosttyKeyEncoding`.
	///
	/// So under this engine an ambiguous key sends its ordinary bytes, which is the
	/// conservative direction and what every terminal without the feature does. It
	/// is named in `unimplemented`, and this test fails if that entry is ever
	/// dropped without the behaviour changing.
	@Test func theOlderModifyOtherKeysProtocolIsOursAloneAndSaysSo() throws {
		let ours = TerminalEmulator(rows: 6, columns: 20)
		let theirs = GhosttyTerminalEngine(rows: 6, columns: 20)
		try #require(theirs.isUsable)

		ours.write("\u{1B}[>4;2m")
		theirs.write("\u{1B}[>4;2m")
		#expect(ours.reportsModifiedKeys == true)
		#expect(ours.encodeModifiedKey(
			code: 13, shift: true, option: false, control: false, command: false)
			== "\u{1B}[27;2;13~")

		// Theirs sends nothing special, and admits it in words.
		#expect(theirs.reportsModifiedKeys == false)
		#expect(theirs.encodeModifiedKey(
			code: 13, shift: true, option: false, control: false, command: false) == nil)
		#expect(theirs.unimplemented.contains { $0.contains("modifyOtherKeys") })
	}

	/// Mouse reporting, in both forms. SGR is the only one that can address a
	/// terminal wider than 223 columns, and the legacy form is what a program that
	/// never asked for SGR still gets.
	@Test func mouseEventsEncodeTheSameInBothEngines() throws {
		let ours = TerminalEmulator(rows: 30, columns: 100)
		let theirs = GhosttyTerminalEngine(rows: 30, columns: 100)
		try #require(theirs.isUsable)

		// Not tracking: nothing at all, so a click selects text instead.
		for engine: TerminalEngine in [ours, theirs] {
			#expect(engine.encodeMouse(
				button: .left, row: 3, column: 5, isRelease: false,
				isDrag: false, shift: false, option: false, control: false) == nil)
		}

		ours.write("\u{1B}[?1002h\u{1B}[?1006h")
		theirs.write("\u{1B}[?1002h\u{1B}[?1006h")
		for (button, isRelease, isDrag) in [
			(TerminalMouseButton.left, false, false),
			(.left, true, false),
			(.left, false, true),
			(.right, false, false),
			(.scrollUp, false, false),
		] {
			let a = ours.encodeMouse(
				button: button, row: 3, column: 5, isRelease: isRelease,
				isDrag: isDrag, shift: false, option: false, control: false)
			let b = theirs.encodeMouse(
				button: button, row: 3, column: 5, isRelease: isRelease,
				isDrag: isDrag, shift: false, option: false, control: false)
			#expect(a == b, "\(button) release=\(isRelease) drag=\(isDrag)")
			#expect(a != nil)
		}

		// The legacy form, with SGR turned back off.
		ours.write("\u{1B}[?1006l")
		theirs.write("\u{1B}[?1006l")
		#expect(ours.encodeMouse(
			button: .left, row: 3, column: 5, isRelease: false,
			isDrag: false, shift: false, option: false, control: false)
			== theirs.encodeMouse(
				button: .left, row: 3, column: 5, isRelease: false,
				isDrag: false, shift: false, option: false, control: false))
	}

	/// A hyperlink: OSC 8 through both engines, and the address readable back out
	/// of the cell it is on. libghostty-vt hands back the URI itself rather than an
	/// index, so this is the interning working.
	@Test func aHyperlinkIsReadableFromTheCellInBothEngines() throws {
		let ours = TerminalEmulator(rows: 4, columns: 20)
		let theirs = GhosttyTerminalEngine(rows: 4, columns: 20)
		try #require(theirs.isUsable)

		let script = "\u{1B}]8;;https://example.com/x\u{1B}\\link\u{1B}]8;;\u{1B}\\ plain"
		ours.write(script)
		theirs.write(script)

		for engine: TerminalEngine in [ours, theirs] {
			let grid = engine.grid
			let row = try #require(grid.line(at: grid.scrollbackCount))
			let id = row.cells[0].attributes.link
			#expect(id != 0, "\(type(of: engine).engineName) lost the hyperlink")
			#expect(engine.link(for: id) == "https://example.com/x")
			// And the text after the link is not part of it.
			#expect(row.cells[5].attributes.link == 0)
		}
	}

	/// A BEL reaches the application in both engines.
	@Test func theBellRingsInBothEngines() throws {
		let ours = TerminalEmulator(rows: 4, columns: 10)
		let theirs = GhosttyTerminalEngine(rows: 4, columns: 10)
		try #require(theirs.isUsable)

		var rung = 0
		ours.onBell = { rung += 1 }
		theirs.onBell = { rung += 1 }
		ours.write("a\u{07}")
		theirs.write("a\u{07}")
		#expect(rung == 2)
	}

	/// OSC 52, which is how a copy made inside tmux or over ssh reaches the
	/// clipboard of the machine somebody is sitting at.
	@Test func aClipboardWriteArrivesInBothEngines() throws {
		let ours = TerminalEmulator(rows: 4, columns: 10)
		let theirs = GhosttyTerminalEngine(rows: 4, columns: 10)
		try #require(theirs.isUsable)

		var written: [String] = []
		ours.onClipboardWrite = { written.append($0) }
		theirs.onClipboardWrite = { written.append($0) }
		let payload = Data("copied".utf8).base64EncodedString()
		ours.write("\u{1B}]52;c;\(payload)\u{1B}\\")
		theirs.write("\u{1B}]52;c;\(payload)\u{1B}\\")
		#expect(written == ["copied", "copied"])
	}

	/// The grid snapshot, which the view reads about twenty times a frame, is the
	/// visible rows and not the scrollback.
	///
	/// 0474 measured the old shape at 4.372 ms a frame — 524,000 cells across FFI
	/// to draw forty rows — and this is the property that fixed it, asserted
	/// rather than timed: `make timing` is where a budget lives, and a count of
	/// what the snapshot holds is stable on any machine at any load.
	@Test func theSnapshotHoldsTheVisibleRowsAndFetchesHistoryOnDemand() throws {
		let theirs = GhosttyTerminalEngine(rows: 10, columns: 20)
		try #require(theirs.isUsable)
		for index in 0..<200 { theirs.write("row \(index)\r\n") }

		let grid = theirs.grid
		#expect(grid.totalLineCount > 100, "there should be history to not copy")
		// The visible band reads straight out of the snapshot.
		let last = try #require(grid.line(at: grid.totalLineCount - 2))
		#expect(last.text == "row 199")
		// And a row from history is still readable — fetched, then kept.
		let old = try #require(grid.line(at: 5))
		#expect(old.text == "row 5")
		#expect(grid.line(at: 5)?.text == "row 5")
		// Out of range in either direction is nil rather than a guess.
		#expect(grid.line(at: -1) == nil)
		#expect(grid.line(at: grid.totalLineCount) == nil)
	}

	/// **The render path is on `render.h`, not on grid references.**
	///
	/// Grid references say so themselves — "not meant to be used as the core of a
	/// render loop … Use the render state API for that" — and 0474 kept them only
	/// because they were the obviously-correct version to compare against. They are
	/// still the fallback, and still what reads scrollback, which is not a render
	/// loop. This asserts the fallback is not what is running: it produces
	/// identical rows, which is what makes it safe and also what would make a
	/// permanent silent fallback invisible.
	@Test func theVisibleRowsComeFromTheRenderState() throws {
		let theirs = GhosttyTerminalEngine(rows: 6, columns: 20)
		try #require(theirs.isUsable)
		theirs.write("hello\r\n\u{1B}[1;31mred\u{1B}[0m")

		_ = theirs.grid
		#expect(theirs.usedRenderStateForVisibleRows)
	}

	/// And the two ways of reading the same rows agree, cell for cell, on a real
	/// capture. This is what licenses the fallback to exist at all.
	@Test func theRenderStateAndGridReferencesReadTheSameRows() throws {
		let data = try fixture("tmux-prompt.bin")
		let theirs = GhosttyTerminalEngine(rows: 30, columns: 100)
		try #require(theirs.isUsable)
		theirs.write(data)

		let grid = theirs.grid
		try #require(theirs.usedRenderStateForVisibleRows)
		let fromRenderState = rowsOf(grid, from: grid.scrollbackCount, count: 30)
		let fromGridRefs = (0..<30).map { offset in
			theirs.copyLines(from: grid.scrollbackCount + offset, count: 1)
				.first?.text ?? "<none>"
		}
		let differing = zip(fromRenderState, fromGridRefs).enumerated()
			.filter { $0.element.0 != $0.element.1 }.map(\.offset)
		#expect(differing.isEmpty, "rows \(differing) differ between the two read paths")
	}

	/// A snapshot asked for a history row *after* the terminal has moved on
	/// refuses rather than handing back whatever is at that index now.
	///
	/// The visible band it copied is still the frame it was given; history it never
	/// copied cannot be, and a selection quietly copying text it was never over is
	/// the worst kind of failure this engine could have.
	@Test func aStaleSnapshotRefusesAHistoryRowItNeverCopied() throws {
		let theirs = GhosttyTerminalEngine(rows: 10, columns: 20)
		try #require(theirs.isUsable)
		for index in 0..<200 { theirs.write("row \(index)\r\n") }

		let grid = theirs.grid
		let visibleBefore = grid.line(at: grid.totalLineCount - 2)?.text
		theirs.write("something else\r\n")

		#expect(grid.line(at: 5) == nil, "a history row from a moved-on terminal")
		// The copied band is unchanged, which is what "keeps the frame it was
		// given" means.
		#expect(grid.line(at: grid.totalLineCount - 2)?.text == visibleBefore)
	}

	/// `discardedLineCount`, which 0474 found had no answer at all and which the
	/// scrollbar and the selection both depend on.
	///
	/// Both engines are given far more lines than they will keep, and both must
	/// report that lines went. Not the same *number*: ours prunes by lines and
	/// libghostty-vt by bytes, so how much history each holds is a design
	/// difference rather than a bug. What must hold is that the count moves, that
	/// it only ever grows, and that `discarded + totalLineCount` accounts for every
	/// line ever produced.
	@Test func discardedLinesAreCountedInBothEngines() throws {
		let theirs = GhosttyTerminalEngine(rows: 10, columns: 20)
		try #require(theirs.isUsable)
		// A small byte budget, so pruning happens inside a test rather than after
		// a hundred thousand lines.
		theirs.setScrollbackByteLimitForTesting(64 * 1024)

		let produced = 20_000
		for index in 0..<produced { theirs.write("line \(index)\r\n") }

		let grid = theirs.grid
		#expect(grid.discardedLineCount > 0, "nothing was reported as pruned")
		// Every line is accounted for: what is kept plus what went is what was
		// produced. `+1` for the row the cursor is on after the last newline.
		#expect(grid.discardedLineCount + grid.totalLineCount == produced + 1)

		// And it only grows.
		let before = grid.discardedLineCount
		for index in 0..<1_000 { theirs.write("more \(index)\r\n") }
		#expect(theirs.grid.discardedLineCount >= before)
	}

	/// Both engines answer to the same name-carrying protocol, so a bug report
	/// can say which one drew the pane.
	@Test func eachEngineNamesItself() {
		#expect(TerminalEmulator.engineName == "abydos")
		#expect(GhosttyTerminalEngine.engineName == "libghostty-vt")
	}

	// MARK: - What happens on a write, and what waits for a read (item 0492)

	/// **A thousand writes and one read is one render-state update.**
	///
	/// This is item 0492 as an assertion rather than a timing, which is what makes it
	/// worth having: `ghostty_render_state_update` brings a whole viewport up to date
	/// and used to run from `afterWrite`, so the app paid for it 1,400 times a second
	/// to read it 60 times. A count is stable at any load, and it is the number that
	/// moves if anybody puts the call back on the parse path.
	@Test func aThousandWritesAndOneReadIsOneRenderStateUpdate() throws {
		let theirs = GhosttyTerminalEngine(rows: 24, columns: 80)
		try #require(theirs.isUsable)
		let before = theirs.renderStateUpdates

		for index in 0..<1_000 { theirs.write("line \(index)\r\n") }
		#expect(theirs.renderStateUpdates == before, "a write must not update the render state")

		// Reading the rows is what needs it, and needs it once however many times the
		// view asks — `TerminalView` reads `grid` about twenty times a frame.
		_ = theirs.grid
		_ = theirs.grid
		_ = theirs.takeDirtyRange()
		#expect(theirs.renderStateUpdates == before + 1)

		// One more write, one more read, one more update. Not zero: a frame after
		// output has to see the output.
		theirs.write("and one more\r\n")
		_ = theirs.grid
		#expect(theirs.renderStateUpdates == before + 2)
	}

	/// The cheap answers do not need a snapshot, and that is what `metrics` is for.
	///
	/// `TerminalView.realignSelectionForDiscardedLines` runs on every delivery of
	/// output and wants one number: how many lines have been pruned. It used to ask
	/// `emulator.grid` for it, and for this engine a snapshot means copying every
	/// visible cell across the FFI boundary — 194 µs a call against 4.67 µs to parse
	/// the kilobyte that provoked it. Asserted as a count of render-state updates,
	/// because that is the observable side of "no snapshot was taken".
	@Test func theMetricsAnswerWithoutASnapshot() throws {
		let theirs = GhosttyTerminalEngine(rows: 10, columns: 40)
		try #require(theirs.isUsable)
		for index in 0..<200 { theirs.write("row \(index)\r\n") }
		_ = theirs.grid
		let after = theirs.renderStateUpdates

		for index in 0..<200 {
			theirs.write("more \(index)\r\n")
			// Exactly what the parse path asks for, once per delivery.
			_ = theirs.metrics.discardedLineCount
			_ = theirs.metrics.totalLineCount
		}
		#expect(theirs.renderStateUpdates == after, "metrics must not cost a render state")
	}

	/// Both engines agree that `metrics` and the snapshot describe the same terminal.
	///
	/// The seam gained a second way to ask the same questions, and the failure it
	/// could have is that the two disagree — a scrollbar drawn from one and rows
	/// fetched by the other, off by a line.
	@Test func metricsAndTheSnapshotAgreeInBothEngines() throws {
		let data = try fixture("return-burst.bin")
		for engine in [
			TerminalEmulator(rows: 30, columns: 100) as TerminalEngine,
			GhosttyTerminalEngine(rows: 30, columns: 100),
		] {
			let name = type(of: engine).engineName
			engine.write(data)
			let metrics = engine.metrics
			let grid = engine.grid
			#expect(metrics.rows == grid.rows, "\(name) rows")
			#expect(metrics.columns == grid.columns, "\(name) columns")
			#expect(metrics.totalLineCount == grid.totalLineCount, "\(name) totalLineCount")
			#expect(metrics.scrollbackCount == grid.scrollbackCount, "\(name) scrollbackCount")
			#expect(metrics.discardedLineCount == grid.discardedLineCount, "\(name) discarded")
		}
	}

	// MARK: - The dirty range this engine used to throw away (item 0492)

	/// **A prompt rewritten in place dirties one row, in both engines.**
	///
	/// This engine used to answer `0...totalLineCount - 1` after every write, which is
	/// truthful and useless: item 0488's row cache keeps what it built for every row
	/// that did not change, and a range covering the document tells it nothing was
	/// kept. libghostty-vt tracks dirtiness per row inside its render state and
	/// `render.h` exports it; this is that, turned into the range the seam speaks.
	///
	/// The pattern is `abydos-bench --mode prompt`: cursor up, clear the line, write it
	/// again — a shell redrawing its prompt when somebody presses a key.
	@Test func aPromptRewriteDirtiesOneRowInBothEngines() throws {
		for engine in [
			TerminalEmulator(rows: 12, columns: 40) as TerminalEngine,
			GhosttyTerminalEngine(rows: 12, columns: 40),
		] {
			let name = type(of: engine).engineName
			// Fill the screen and scroll a while, so there is history and the range
			// below is measured against a document rather than a blank grid.
			engine.write(String(repeating: "filler\r\n", count: 60))
			engine.write("$ a recalled command\r\n")
			_ = engine.takeDirtyRange()

			// The prompt line, rewritten where it already is.
			engine.write("\u{1B}[1A\u{1B}[2K$ a longer recalled command")
			let range = engine.takeDirtyRange()
			let rows = engine.metrics.rows
			#expect(range != nil, "\(name) reported nothing changed")
			#expect(
				(range?.count ?? .max) <= 2,
				"\(name) dirtied \(range?.count ?? -1) rows for a one-line rewrite")
			#expect(
				(range?.count ?? .max) < rows / 2,
				"\(name): under half a viewport is what the CoreGraphics path turns on")

			// And taking it clears it, so the frame after a frame is free.
			#expect(engine.takeDirtyRange() == nil, "\(name) reported the same rows twice")
		}
	}

	/// A line falling out of history renumbers every absolute row, and that really is
	/// the whole document — in this engine too.
	///
	/// `TerminalDirtyRows` unions ranges taken at different moments as absolute rows,
	/// and that is only sound because the moment of renumbering is also a moment the
	/// whole document is marked. Ours is held to this by
	/// `TerminalDirtyRangeTests.aDiscardedLineDirtiesEverything`; making the range
	/// narrow here without making the same promise would have broken the union
	/// quietly, which is the failure that shows up as a stale row weeks later.
	@Test func aDiscardedLineDirtiesEverythingHereToo() throws {
		let theirs = GhosttyTerminalEngine(rows: 8, columns: 40)
		try #require(theirs.isUsable)
		// A small byte budget, so pruning happens inside a test.
		theirs.setScrollbackByteLimitForTesting(32 * 1024)
		for index in 0..<4_000 { theirs.write("line \(index)\r\n") }
		let before = theirs.metrics.discardedLineCount
		try #require(before > 0, "the history has to be full for this to be the case tested")
		_ = theirs.takeDirtyRange()

		// Written until a line actually goes, rather than a fixed number of them.
		// **libghostty-vt prunes a page at a time, not a line at a time**, which is
		// worth knowing for anybody testing this: four hundred more lines went in here
		// and the count did not move, because the page they went into had room. Ours
		// prunes per line and this loop would end on its first turn.
		var index = 0
		while theirs.metrics.discardedLineCount == before, index < 20_000 {
			theirs.write("pushes a line off the top \(index)\r\n")
			index += 1
		}
		#expect(theirs.metrics.discardedLineCount > before, "nothing was pruned in 20,000 lines")
		let range = theirs.takeDirtyRange()
		#expect(range?.lowerBound == 0, "pruning must dirty from the first row")
		#expect((range?.count ?? 0) >= theirs.metrics.totalLineCount)
	}

	/// Swapping the whole grid for another one is a change, and this engine has to
	/// report it as one.
	///
	/// The case item 0488 found: a renderer that keeps what it built per row draws the
	/// shell's last screen underneath a program that has just taken the terminal over.
	/// The old answer here — the whole document, always — could not get this wrong. A
	/// narrow answer can, which is why this is asserted rather than assumed.
	@Test func takingOverTheScreenDirtiesEverythingHereToo() throws {
		let theirs = GhosttyTerminalEngine(rows: 8, columns: 40)
		try #require(theirs.isUsable)
		theirs.write(String(repeating: "history\r\n", count: 40))
		_ = theirs.takeDirtyRange()

		theirs.write("\u{1B}[?1049h")
		#expect(theirs.takeDirtyRange()?.lowerBound == 0, "the alternate screen")

		theirs.write("a full screen program")
		_ = theirs.takeDirtyRange()

		theirs.write("\u{1B}[?1049l")
		#expect(theirs.takeDirtyRange()?.lowerBound == 0, "and handing it back")

		theirs.write("more output\r\n")
		_ = theirs.takeDirtyRange()
		theirs.reset()
		#expect(theirs.takeDirtyRange()?.lowerBound == 0, "a reset")
	}

	/// Nothing new is nothing to draw.
	///
	/// The other half of a narrow dirty range, and the half a cache depends on: a
	/// frame drawn for a reason of its own — a cursor blink, a window coming forward —
	/// must not be told that rows changed when none did. The old answer failed this by
	/// construction and it did not matter, because the range was the document anyway.
	@Test func aFrameWithNothingNewIsToldNothingChanged() throws {
		let theirs = GhosttyTerminalEngine(rows: 8, columns: 40)
		try #require(theirs.isUsable)
		theirs.write("hello\r\n")
		_ = theirs.takeDirtyRange()
		#expect(theirs.takeDirtyRange() == nil)
		_ = theirs.grid
		#expect(theirs.takeDirtyRange() == nil, "a snapshot is not a change")
	}
}

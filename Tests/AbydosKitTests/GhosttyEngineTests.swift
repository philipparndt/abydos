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
	/// half-built: kitty graphics is the notable gap and it has to be named.
	@Test func theGhosttyEngineDeclaresWhatIsMissing() {
		let theirs = GhosttyTerminalEngine(rows: 4, columns: 10)
		#expect(!theirs.unimplemented.isEmpty)
		#expect(theirs.unimplemented.contains { $0.contains("Kitty graphics") })
		// And ours claims nothing missing, because every terminal test in the
		// suite was written against it.
		#expect(TerminalEmulator(rows: 4, columns: 10).unimplemented.isEmpty)
	}

	/// Both engines answer to the same name-carrying protocol, so a bug report
	/// can say which one drew the pane.
	@Test func eachEngineNamesItself() {
		#expect(TerminalEmulator.engineName == "abydos")
		#expect(GhosttyTerminalEngine.engineName == "libghostty-vt")
	}
}

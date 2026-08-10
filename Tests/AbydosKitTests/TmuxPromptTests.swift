import Testing
import Foundation
@testable import AbydosKit

/// tmux's command prompt, drawn on the pane's last row because the status bar
/// is off — backlog 0404.
///
/// This app turns tmux's bar off, because the panel already draws the same
/// window list as tabs. tmux's prompts live on that bar, so with it off tmux
/// borrows the pane's last row instead. The report was that pressing prefix-`,`
/// over a busy pane leaves nothing worth typing into: sometimes nothing, and
/// sometimes a fragment in the wrong place, gone by the next repaint.
///
/// Two captures, both from a real client on a private socket — `tmux -S … -f …
/// attach` inside a pty, status off, with a program running in the pane. They
/// differ in what the pane is doing, and only one of them shows the fault,
/// which is why the fault took finding:
///
/// - `tmux-prompt.bin` — 30×100, the pane printing a line every 50ms, so it
///   scrolls. tmux draws the prompt where the cursor already is, and it lands
///   on the last row whatever the terminal does about clamping.
/// - `tmux-prompt-repaint.bin` — 24×60, the pane repainting all 24 rows by
///   absolute address ten times a second, which is what an agent CLI does.
///   Here tmux parks the cursor at `CSI 25 d` — one row below a 24-row screen —
///   and writes the prompt with a relative `CSI A` from that park. A terminal
///   that clamps the park to the last row and then moves up from the clamp
///   draws the prompt one row too high, over pane output, and that is the
///   fragment in the wrong place.
///
/// What the captures also show, and what the report could not: tmux does hold
/// the last row once the prompt is up. Between the prompt appearing and it
/// being dismissed, tmux sends nothing for the pane at all — the pane goes on
/// printing and none of it arrives. So the last line is protected already, by
/// tmux; the whole of the fault was addressing it one row wrong.
struct TmuxPromptTests {
	static func capture(_ name: String) -> Data {
		let url = Bundle.module.url(
			forResource: name, withExtension: "bin", subdirectory: "Fixtures"
		)!
		return try! Data(contentsOf: url)
	}

	static let scrolling = capture("tmux-prompt")
	static let repainting = capture("tmux-prompt-repaint")

	/// The bytes up to and including the first time the prompt is drawn.
	///
	/// The interesting moment is that first draw and no later one: tmux writes
	/// every echo after it with an absolute `CSI 24;1H`, which lands correctly
	/// however the park was read, so a screen looked at only at the end of the
	/// capture cannot tell the two apart.
	static func untilTheFirstPromptDraw(of capture: Data) -> Data {
		let prompt = Data("(rename-window)".utf8)
		let end = Data("\u{1B}[?25h".utf8)
		guard let drawn = capture.range(of: prompt),
		      let finished = capture.range(of: end, in: drawn.upperBound..<capture.endIndex)
		else {
			Issue.record("the capture has no prompt in it")
			return capture
		}
		return capture.subdata(in: capture.startIndex..<finished.upperBound)
	}

	// MARK: - The pane repainting, which is the reported case

	/// The prompt lands on the last row, and the row above it keeps the pane's.
	///
	/// This is 0404 itself. Before the fix the two rows held each other's
	/// contents: the prompt on row 23 over the pane's own output, and the
	/// pane's row 24 on row 24 where the prompt should have been.
	@Test func thePromptLandsOnTheLastRowOverARepaintingPane() {
		let emulator = TerminalEmulator(rows: 24, columns: 60)
		emulator.write(Self.untilTheFirstPromptDraw(of: Self.repainting))

		#expect(emulator.screen[23].text.hasPrefix("(rename-window) "))
		#expect(emulator.screen[22].text.hasPrefix("PAINT "))
	}

	/// And it is still there at the end, with everything typed into it.
	///
	/// The capture ends with the prompt open and `abd` typed — the `d` because
	/// a prefix pressed at a prompt is text like any other, which is itself
	/// worth knowing.
	@Test func whatIsTypedIntoThePromptStaysOnTheLastRow() {
		let emulator = TerminalEmulator(rows: 24, columns: 60)
		emulator.write(Self.repainting)

		#expect(emulator.screen[23].text.hasPrefix("(rename-window) Pythonabd"))
		// The row above is the pane's, not a prompt left behind on the wrong one.
		#expect(emulator.screen[22].text.hasPrefix("PAINT "))
	}

	// MARK: - The pane scrolling, which never showed the fault

	/// The same prompt over a pane that scrolls, which always worked.
	///
	/// Kept because it is the case anybody reaches for first when trying to
	/// reproduce this, and a fix that broke it would be a bad trade.
	@Test func thePromptHoldsTheBottomRowOverAScrollingPane() {
		let emulator = TerminalEmulator(rows: 30, columns: 100)
		emulator.write(Self.scrolling)

		#expect(emulator.screen[29].text == "(rename-window) sleepx")
		#expect(emulator.screen[28].text.hasPrefix("noise "))
	}

	/// tmux parks the cursor one row past the bottom — `CSI 31 d` on a 30-row
	/// screen — and the cursor itself has nowhere to go but the last row.
	@Test func theOffScreenCursorParkClampsToThePromptRow() {
		let emulator = TerminalEmulator(rows: 30, columns: 100)
		emulator.write(Self.scrolling)

		#expect(emulator.cursorRow == 29)
		#expect(emulator.screen.totalLineCount >= 30)
	}

	// MARK: - The rule underneath, without tmux

	/// A park one row below the screen is where the next vertical move counts
	/// from, even though the cursor itself sits on the last row.
	@Test func aVerticalMoveCountsFromTheParkRatherThanFromTheClamp() {
		let emulator = TerminalEmulator(rows: 4, columns: 10)
		emulator.write("\u{1B}[5d")
		#expect(emulator.cursorRow == 3)

		emulator.write("\u{1B}[A")
		#expect(emulator.cursorRow == 3)

		emulator.write("x")
		#expect(emulator.screen[3].text.hasPrefix("x"))
	}

	/// Without a park, up from the last row is the row above it, as always.
	@Test func aVerticalMoveFromTheLastRowIsUnchanged() {
		let emulator = TerminalEmulator(rows: 4, columns: 10)
		emulator.write("\u{1B}[4d\u{1B}[A")
		#expect(emulator.cursorRow == 2)
	}

	/// A park lasts until something puts the cursor somewhere real.
	@Test func drawingEndsThePark() {
		let emulator = TerminalEmulator(rows: 4, columns: 10)
		emulator.write("\u{1B}[5dz\u{1B}[A")
		#expect(emulator.cursorRow == 2)
	}

	/// One row below the screen is a park. Row 999 is a program guessing at the
	/// size of the screen, and there is nothing to remember about that.
	@Test func onlyOneRowBelowTheScreenCounts() {
		let emulator = TerminalEmulator(rows: 4, columns: 10)
		emulator.write("\u{1B}[99d\u{1B}[A")
		#expect(emulator.cursorRow == 2)
	}
}

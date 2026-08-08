import Testing
import Foundation
@testable import AbydosKit

/// Replaying the recorded burst of Return presses that put blank rows between
/// the prompts on screen.
///
/// The blank rows are in the bytes: the same 30×100 grid comes out of tmux,
/// and a plain `zsh -l` under a bare pty — no terminal emulator anywhere —
/// writes the same extra line feeds. What these tests pin is the half that is
/// ours, which is that the emulator adds nothing to them: one row per line
/// feed, no early wrap off the full-width prompt filler, and not a byte sent
/// back to a shell that asked for nothing.
struct ReturnBurstTests {
	static let capture: Data = {
		let url = Bundle.module.url(
			forResource: "return-burst", withExtension: "bin", subdirectory: "Fixtures"
		)!
		return try! Data(contentsOf: url)
	}()

	/// The grid the capture is meant to leave behind, taken from tmux replaying
	/// the same bytes at the same size. `~` is the prompt, empty is a blank row.
	private static let expectedGrid = [
		"", "", "~", "~", "", "", "~", "", "", "~",
		"", "", "~", "", "", "~", "", "", "~", "",
		"", "~", "", "", "~", "", "", "~", "~", "~",
	]

	private func shape(_ line: TerminalLine) -> String {
		line.text.isEmpty ? "" : "~"
	}

	/// The emulator consumes exactly one row per line feed and never one more.
	///
	/// This is the whole question the capture was recorded to answer. The
	/// prompt filler is `%` plus `columns - 1` spaces, which is exactly a full
	/// row: wrap it a column early and every press would take a row it should
	/// not have, which is what a blank row looks like from the outside.
	@Test func advancesOneRowPerLineFeed() {
		let emulator = TerminalEmulator(rows: 30, columns: 100)
		emulator.write(Self.capture)

		let lineFeeds = Self.capture.filter { $0 == 0x0A }.count
		#expect(lineFeeds == 149)
		#expect(
			emulator.screen.totalLineCount == lineFeeds + 1,
			"the grid grew by something other than the line feeds in the capture"
		)
	}

	/// And the grid it leaves is the one tmux leaves, row for row.
	@Test func leavesTheSameGridAsAnotherTerminal() {
		let emulator = TerminalEmulator(rows: 30, columns: 100)
		emulator.write(Self.capture)

		let grid = (0..<emulator.screen.rows).map { shape(emulator.screen[$0]) }
		#expect(grid == Self.expectedGrid)
		#expect(emulator.cursorRow == 29)
		#expect(emulator.cursorColumn == 6)
	}

	/// Nothing in the capture is a question, so nothing may be answered.
	///
	/// A reply the shell was not waiting for is read as typing, and typing at a
	/// prompt is a line of its own — which would look exactly like this bug.
	@Test func answersNothingTheShellDidNotAsk() {
		let emulator = TerminalEmulator(rows: 30, columns: 100)
		var replies: [String] = []
		emulator.onResponse = { replies.append($0) }
		emulator.write(Self.capture)
		#expect(replies.isEmpty, "sent \(replies) to a shell that asked nothing")
	}

	/// One press, in the shape zsh writes when it is not behind: the filler
	/// fills the row, the cursor comes back to the start of it, and the erase
	/// puts the prompt on that same row. No blank row anywhere.
	@Test func promptFillerLeavesNoBlankRow() {
		let emulator = TerminalEmulator(rows: 6, columns: 20)
		let filler = "%" + String(repeating: " ", count: 19)
		emulator.write("$ ")
		for _ in 0..<3 {
			emulator.write("\r\r\n\(filler)\r \r\u{1B}[J$ ")
		}
		#expect((0...3).map { emulator.screen[$0].text } == ["$", "$", "$", "$"])
		#expect(emulator.screen.totalLineCount == 6, "the grid grew past the four presses")
	}

	/// The same press with the extra line feeds the shell writes when it is
	/// behind, which is where the blank rows actually come from: the erase
	/// happens a row below the filler, so the filled row is left standing —
	/// blank, because the trailing space overwrote the `%`.
	@Test func extraLineFeedsAreWhatLeaveTheBlankRow() {
		let emulator = TerminalEmulator(rows: 6, columns: 20)
		let filler = "%" + String(repeating: " ", count: 19)
		emulator.write("$ ")
		emulator.write("\r\r\n\(filler)\r \r\r\n\r\u{1B}[J$ ")
		#expect(emulator.screen[0].text == "$")
		#expect(emulator.screen[1].text == "", "the filler row is what is left standing")
		#expect(emulator.screen[2].text == "$")
	}
}

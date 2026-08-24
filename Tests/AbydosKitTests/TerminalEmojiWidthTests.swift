import Foundation
import Testing
@testable import AbydosKit

/// How many columns an emoji takes, which decides both how it is drawn and
/// where everything after it on the line goes.
///
/// The report was a build log full of ✅: each one drawn clipped to half its
/// width, with the text after it a column to the left of where the program put
/// it. Both are the same mistake — the emoji measured one column while the font
/// drew two — and the second is the worse of them, because a line whose columns
/// are wrong is wrong for the selection, the reflow and the renderer alike.
///
/// The width table listed `0x1F300...0x1F64F` and `0x1F900...0x1F9FF`, which is a
/// real but arbitrary slice of the emoji planes. It is now asked of Unicode
/// instead: a scalar whose default presentation is emoji is East Asian Wide.
struct TerminalEmojiWidthTests {
	/// The one from the report, and the ordinary case: what a script prints to
	/// say a step passed.
	@Test func theEmojiAScriptPrintsToSayAStepPassedTakesTwoColumns() {
		#expect(TerminalEmulator.displayWidth(of: "✅") == 2)
		#expect(TerminalEmulator.displayWidth(of: "❌") == 2)
	}

	/// Every block the old list missed. Each of these was one column and drew as
	/// two.
	@Test func theBlocksTheOldListMissedAreAllWide() {
		for (name, scalar) in [
			("✅ check", "\u{2705}"),
			("❌ cross", "\u{274C}"),
			("❗ exclamation", "\u{2757}"),
			("✨ sparkles", "\u{2728}"),
			("⌚ watch", "\u{231A}"),
			("♈ zodiac", "\u{2648}"),
			("⚡ high voltage", "\u{26A1}"),
			("⬛ black square", "\u{2B1B}"),
			("⭐ star", "\u{2B50}"),
			("🚀 transport", "\u{1F680}"),
			("🟩 green square", "\u{1F7E9}"),
			("🩰 symbols extended-A", "\u{1FA70}"),
		] {
			#expect(TerminalEmulator.displayWidth(of: Character(scalar)) == 2, "\(name)")
		}
	}

	/// The blocks that were already right stay right.
	@Test func theBlocksTheOldListHadAreStillWide() {
		#expect(TerminalEmulator.displayWidth(of: "🌍") == 2)
		#expect(TerminalEmulator.displayWidth(of: "😀") == 2)
		#expect(TerminalEmulator.displayWidth(of: "🤖") == 2)
	}

	/// CJK is not emoji and is not decided by the emoji property, so it needs its
	/// own ranges and they are still there.
	@Test func cjkIsStillWide() {
		for character in ["漢", "字", "が", "ハ", "한", "（", "￥"] {
			#expect(TerminalEmulator.displayWidth(of: Character(character)) == 2, "\(character)")
		}
	}

	/// A text-presentation dingbat is one column, which is what makes this a
	/// property of the scalar rather than "anything that looks like an icon".
	/// U+2714 is Neutral in East Asian Width and libghostty-vt agrees.
	@Test func aTextPresentationDingbatIsOneColumn() {
		#expect(TerminalEmulator.displayWidth(of: "\u{2714}") == 1)
		#expect(TerminalEmulator.displayWidth(of: "\u{2716}") == 1)
	}

	/// Combining marks and variation selectors take no column of their own. The
	/// emoji test has to come after this one: a variation selector is how a
	/// scalar is asked for emoji presentation.
	@Test func combiningMarksAndVariationSelectorsTakeNoColumn() {
		#expect(TerminalEmulator.displayWidth(of: "\u{0301}") == 0)
		#expect(TerminalEmulator.displayWidth(of: "\u{FE0F}") == 0)
		#expect(TerminalEmulator.displayWidth(of: "\u{200D}") == 0)
	}

	/// Ordinary text is untouched.
	@Test func plainTextIsOneColumn() {
		for character in ["a", "Z", "0", " ", "-", "~"] {
			#expect(TerminalEmulator.displayWidth(of: Character(character)) == 1, "\(character)")
		}
	}

	// MARK: - What it does to the grid

	/// The grid is what the renderer and the selection read, so the claim that
	/// matters is about cells and not about a number.
	///
	/// A wide glyph occupies its own cell and marks the next as its trailer; the
    /// renderer widens a cell by looking for exactly that.
	@Test func aWideEmojiClaimsTwoCellsAndMarksTheSecond() throws {
		let terminal = TerminalEmulator(rows: 3, columns: 20)
		terminal.write("\u{2705} ok")

		let grid = terminal.grid
		let line = try #require(grid.line(at: grid.scrollbackCount))
		#expect(line.cells[0].scalar == 0x2705)
		#expect(line.cells[1].isWideTrailer, "without this the renderer clips it to one cell")
		// And so the text after it lands where the program put it, rather than a
		// column to the left.
		#expect(line.cells[3].scalar == UInt32(UnicodeScalar("o").value))
		#expect(line.cells[4].scalar == UInt32(UnicodeScalar("k").value))
	}

	/// The same bytes through libghostty-vt, which had this right all along —
	/// so the two engines agreeing is the strongest statement available that
	/// this is now correct rather than merely different.
	@Test func bothEnginesNowAgreeOnEmojiWidth() throws {
		let script = "\u{2705} a \u{274C} b \u{1F7E9} c \u{1F680} d \u{2714} e"

		let ours = TerminalEmulator(rows: 3, columns: 40)
		ours.write(script)

		let theirs = GhosttyTerminalEngine(rows: 3, columns: 40)
		try #require(theirs.isUsable)
		theirs.write(script)

		let a = try #require(ours.grid.line(at: ours.grid.scrollbackCount))
		let b = try #require(theirs.grid.line(at: theirs.grid.scrollbackCount))

		let shape: (TerminalLine) -> [String] = { line in
			line.cells.prefix(24).map { "\($0.scalar):\($0.isWideTrailer ? "T" : "-")" }
		}
		#expect(shape(a) == shape(b))
	}
}

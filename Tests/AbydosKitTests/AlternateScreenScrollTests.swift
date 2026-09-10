import Foundation
import Testing
@testable import AbydosKit

/// A whole-screen scroll on a screen with no history does not pretend the
/// document grew.
///
/// Relayed 2026-09-09: a completion listing overwrote the output above it
/// instead of scrolling. Reproduced only under the app's own engine, inside
/// tmux with the status bar hidden — which is the alternate screen, given a
/// scrollback of zero. `TerminalScreen` there took the eviction path of
/// `scrollUp`: `ScrollbackBuffer.append` at capacity zero hands the line
/// straight back, and `scrollUp` counted that as a line discarded from history
/// and advanced `discardedLineCount`. The renderer keys its rows on that count
/// and `line(at:)` does not, so the two drifted a row apart per scroll and the
/// grid held rows the renderer was not showing.
struct AlternateScreenScrollTests {
	private func filled(rows: Int, columns: Int) -> TerminalScreen {
		var screen = TerminalScreen(rows: rows, columns: columns)
		screen.maximumScrollback = 0
		for row in 0..<rows {
			for (column, character) in "row\(row)".prefix(columns).enumerated() {
				screen[row].cells[column] = TerminalCell(character: character)
			}
		}
		return screen
	}

	/// **The bug, as a claim.** With no history, the document is only the grid,
	/// so nothing is ever discarded from the front of it and the count stays
	/// zero however many times the screen scrolls.
	@Test func aScrollWithNoHistoryDiscardsNothing() {
		var screen = filled(rows: 18, columns: 20)
		#expect(screen.discardedLineCount == 0)
		for _ in 0..<9 {
			screen.scrollUp(top: 0, bottom: 17, attributes: TerminalAttributes())
		}
		#expect(screen.discardedLineCount == 0, "no history, nothing discarded")
		#expect(screen.scrollbackCount == 0)
		#expect(screen.totalLineCount == 18)
	}

	/// The rows the renderer would ask for by absolute index are the grid rows,
	/// because with nothing discarded the absolute index is the grid row.
	@Test func lineAtAgreesWithTheGridAfterScrolling() {
		var screen = filled(rows: 18, columns: 20)
		for _ in 0..<5 {
			screen.scrollUp(top: 0, bottom: 17, attributes: TerminalAttributes())
		}
		// Row 5 of the original is now at the top; the bottom five are blank.
		for row in 0..<18 {
			#expect(screen.line(at: row)?.text == screen[row].text, "row \(row)")
		}
		#expect(screen.line(at: 0)?.text == "row5")
		#expect(screen.line(at: 12)?.text == "row17")
		#expect(screen.line(at: 13)?.text == "")
	}

	/// A screen that does keep history still counts a real eviction, so the fix
	/// is only about the no-history case.
	@Test func aScrollThatEvictsRealHistoryStillCounts() {
		var screen = TerminalScreen(rows: 4, columns: 10)
		screen.maximumScrollback = 2
		for row in 0..<4 { screen[row].cells[0] = TerminalCell(character: Character("\(row)")) }
		// Fill scrollback (2), then one more scroll evicts the oldest.
		for _ in 0..<3 { screen.scrollUp(top: 0, bottom: 3, attributes: TerminalAttributes()) }
		#expect(screen.discardedLineCount == 1, "the third scroll evicted one kept line")
		#expect(screen.scrollbackCount == 2)
	}
}

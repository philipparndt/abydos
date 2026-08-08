import Foundation
import Testing
@testable import AbydosKit

/// SGR 38 and 48 in both of their spellings.
///
/// `38;2;r;g;b` with semicolons is what almost everything writes.
/// `38:2:r:g:b` with colons is what the standard specifies, and what kitty's
/// own `icat` uses for the colour that names an image — so a terminal that
/// reads only the first spelling draws no picture for it while every other
/// terminal does.
struct ExtendedColourTests {
	private func colour(after sequence: String) -> TerminalColor {
		let terminal = TerminalEmulator(rows: 4, columns: 20)
		terminal.write(sequence + "x")
		return terminal.screen[0].cells[0].attributes.foreground
	}

	private func background(after sequence: String) -> TerminalColor {
		let terminal = TerminalEmulator(rows: 4, columns: 20)
		terminal.write(sequence + "x")
		return terminal.screen[0].cells[0].attributes.background
	}

	@Test func semicolonsStillWork() {
		#expect(colour(after: "\u{1B}[38;2;10;20;30m") == .rgb(10, 20, 30))
		#expect(colour(after: "\u{1B}[38;5;42m") == .indexed(42))
		#expect(background(after: "\u{1B}[48;2;1;2;3m") == .rgb(1, 2, 3))
	}

	/// The short colon form, which is what kitty writes.
	@Test func colonsAreReadToo() {
		#expect(colour(after: "\u{1B}[38:2:109:93:205m") == .rgb(109, 93, 205))
		#expect(colour(after: "\u{1B}[38:5:42m") == .indexed(42))
		#expect(background(after: "\u{1B}[48:2:1:2:3m") == .rgb(1, 2, 3))
	}

	/// The long colon form names a colour space first, and it is usually empty.
	@Test func aColourSpaceBeforeTheChannelsIsSkipped() {
		#expect(colour(after: "\u{1B}[38:2::109:93:205m") == .rgb(109, 93, 205))
		#expect(background(after: "\u{1B}[48:2::1:2:3m") == .rgb(1, 2, 3))
	}

	/// Mixed into a longer run, which is how it actually arrives.
	@Test func itSurvivesCompanyInTheSameSequence() {
		#expect(colour(after: "\u{1B}[0;1;38:2:7:8:9m") == .rgb(7, 8, 9))
		let terminal = TerminalEmulator(rows: 4, columns: 20)
		terminal.write("\u{1B}[38:2:7:8:9;48;5;3mx")
		#expect(terminal.screen[0].cells[0].attributes.foreground == .rgb(7, 8, 9))
		#expect(terminal.screen[0].cells[0].attributes.background == .indexed(3))
	}

	/// Nonsense leaves the colour alone rather than setting something arbitrary.
	@Test func anIncompleteColourChangesNothing() {
		#expect(colour(after: "\u{1B}[38:2:7m") == .default)
		#expect(colour(after: "\u{1B}[38:9:1:2:3m") == .default)
	}
}

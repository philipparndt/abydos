import Foundation
import Testing
@testable import AbydosKit

/// Inverse video with the default colours on, which is what `\u{1B}[7m` alone means.
///
/// The renderer paints a cell's background only when it is not `.default`, and
/// `resolved` swaps the two colours for an inverse cell — so an inverse cell
/// whose colours were never set resolves to a background of `.default` and is
/// not painted at all. The reversal it asked for does not happen.
struct InverseVideoTests {
	@Test func inverseSwapsTheTwoColours() {
		var attributes = TerminalAttributes()
		attributes.foreground = .indexed(1)
		attributes.background = .indexed(4)
		attributes.inverse = true
		#expect(attributes.resolved.foreground == .indexed(4))
		#expect(attributes.resolved.background == .indexed(1))
	}

	/// **The case the renderer cannot draw.** Both colours are `.default`, so
	/// swapping them changes nothing a `!= .default` test can see — and a cell
	/// that asked to be drawn the other way round is drawn the usual way.
	@Test func inverseWithNoColoursSetIsIndistinguishableFromPlain() {
		var attributes = TerminalAttributes()
		attributes.inverse = true
		#expect(attributes.resolved.background == .default)
		#expect(attributes.resolved.foreground == .default)

		var plain = TerminalAttributes()
		plain.inverse = false
		#expect(
			attributes.resolved == plain.resolved,
			"nothing downstream can tell an inverse cell from a plain one"
		)
	}

	/// What the emulator records for `\u{1B}[7m`, so the flag is known to arrive.
	@Test func theEmulatorRecordsTheFlag() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		emulator.write("\u{1B}[7mON\u{1B}[27mOFF")
		let cells = emulator.screen[0].cells
        #expect(cells[0].attributes.inverse)
		#expect(!cells[2].attributes.inverse)
	}
}

import Foundation
import Testing
@testable import AbydosKit

/// What a program paints, and whether it can be read — the half of a palette
/// the ground check never asked about.
///
/// Reported 2026-09-10: under the Level AAA theme, k9s's selected row could
/// barely be read. The pane's own cells said why: `indexed(0)` bold on
/// `indexed(14)`, which the bold rule brightened to the palette's dim grey on
/// bright cyan, 1.54:1. Two claims fall out, and they are here.
struct PaintedPairTests {
	/// **The fix, as a claim.** Bold brightens black on the ground, as prompts
	/// rely on, and leaves it black on a background a program painted.
	@Test func boldBrightensABaseColourOnTheGroundOnly() {
		var onGround = TerminalAttributes()
		onGround.bold = true
		onGround.foreground = .indexed(0)
		#expect(onGround.brightensBold)

		var painted = onGround
		painted.background = .indexed(14)
		#expect(!painted.brightensBold)

		var truecolour = onGround
		truecolour.background = .rgb(0, 255, 255)
		#expect(!truecolour.brightensBold)
	}

	@Test func onlyBoldOnTheFirstEightBrightens() {
		var plain = TerminalAttributes()
		plain.foreground = .indexed(0)
		#expect(!plain.brightensBold)
		var bright = TerminalAttributes()
		bright.bold = true
		bright.foreground = .indexed(12)
		#expect(!bright.brightensBold)
		var rgb = TerminalAttributes()
		rgb.bold = true
		rgb.foreground = .rgb(0, 0, 0)
		#expect(!rgb.brightensBold)
	}

	/// Inverse swaps the two, so a bold inverse cell is judged by what will be
	/// drawn, not by what was set.
	@Test func inverseIsJudgedAfterTheSwap() {
		var inverse = TerminalAttributes()
		inverse.bold = true
		inverse.inverse = true
		inverse.background = .indexed(1)   // becomes the foreground
		#expect(inverse.brightensBold, "the swapped foreground is red, on the default ground")
	}

	/// tmux is told outright that this terminal shows true colour, so what a
	/// program sends as 24-bit arrives as 24-bit rather than as the nearest of
	/// 256 — which is how a true black became ANSI black in the first place.
	@Test func tmuxIsToldTheTerminalShowsRGB() {
		let arguments = TmuxMirror.attachArguments(to: "abydos")
		#expect(arguments.prefix(2) == ["-T", "RGB"])
		#expect(arguments.contains("allow-passthrough"))
	}

	/// The pairs a program paints for a highlight — dark text on a colour — are
	/// readable in every bundled palette, and stay so.
	@Test func everyBundledPaletteKeepsDarkTextReadableOnWhatProgramsPaint() {
		let library = SchemeLibrary(personal: nil, logsProblems: false)
		#expect(library.terminalSchemes.count >= 5, "the bundled schemes were not found")
		let shortfalls = SchemeContrast.paintedShortfalls(in: library)
		let list = shortfalls.map { "  \($0)" }.joined(separator: "\n")
		#expect(shortfalls.isEmpty, Comment(rawValue: "\(shortfalls.count) painted pair(s) under the floor:\n\(list)"))
	}

	/// A shortfall names its pair, so a palette added later that fails says
	/// exactly which colour on which.
	@Test func aPaintedPairUnderTheFloorIsNamed() throws {
		var ansi: [SchemeAnsi: SchemePair] = [:]
		for colour in SchemeAnsi.allCases { ansi[colour] = SchemePair(light: 0xFFFFFF, dark: 0x202020) }
		ansi[.black] = SchemePair(light: 0x000000, dark: 0xB0B0B0)        // a light "black"
		ansi[.brightCyan] = SchemePair(light: 0x000000, dark: 0xA0E0E0)   // on a light cyan
		let scheme = Scheme(
			id: "pale", title: "Pale",
			terminal: SchemeTerminal(
				background: SchemePair(light: 0xFFFFFF, dark: 0x000000),
				foreground: nil, cursor: nil, ansi: ansi
			),
			origin: "/tmp/pale.json"
		)
		let found = SchemeContrast.paintedShortfalls(in: scheme)
		#expect(found.contains { $0.text == .black && $0.background == .brightCyan })
		#expect(found.first?.description.contains("black on brightCyan") == true)
	}
}

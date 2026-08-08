import AppKit
import CoreText
import Foundation
import Testing
@testable import AbydosKit

/// What a programming font actually does with an operator, which the terminal's
/// drawing depends on and had wrong.
///
/// These fonts do not merge cells — that is what lets a terminal have ligatures
/// at all — so `...` is still three glyphs across three cells. What they do is
/// put the whole group's ink on the *last* of them, hanging off it to the left,
/// and make every glyph before it empty. A renderer that treats "this glyph has
/// nothing to draw" as "then draw the character instead" puts a plain dot under
/// ink that already covers it: two dots for `..`, three for `...`, and the
/// first of `!!` painted twice.
struct LigatureShapingTests {
	/// The font this app ships, registered from the repository rather than
	/// looked for on the machine.
	private var bundled: NSFont? {
		let fonts = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // AbydosKitTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // package root
			.appendingPathComponent("Resources/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf")
		CTFontManagerRegisterFontsForURL(fonts as CFURL, .process, nil)
		return NSFont(name: "JetBrainsMonoNFM-Regular", size: 14)
	}

	private func ink(_ glyph: CGGlyph, _ font: CTFont) -> CGRect {
		var one = glyph
		var rect = CGRect.zero
		CTFontGetBoundingRectsForGlyphs(font, .horizontal, &one, &rect, 1)
		return rect
	}

	@Test func everyCellButTheLastOfALigatureIsAnEmptyGlyph() {
		guard let font = bundled else { Issue.record("the bundled font is missing"); return }
		var shaped = ShapedRuns()

		guard let pieces = shaped.pieces(
			for: "...", cellOfOffset: [0, 1, 2], font: font, faceIndex: 0
		) else { Issue.record("nothing shaped"); return }
		// One glyph per cell, still. The grid never moves.
		#expect(pieces.count == 3)
		#expect(pieces.map(\.cellOffset) == [0, 1, 2])

		#expect(ink(pieces[0].glyph, pieces[0].font).isEmpty)
		#expect(ink(pieces[1].glyph, pieces[1].font).isEmpty)

		// And the last carries all of it, reaching back over the two before it:
		// wider than a cell, starting well to the left of its own origin.
		let last = ink(pieces[2].glyph, pieces[2].font)
		#expect(last.width > 14, "the ink for three dots is nearly two cells wide")
		#expect(last.origin.x < -8, "and it hangs off the left of the cell it sits on")
	}

	/// The pair from the report, and the shortest ligature there is.
	@Test func aTwoCellLigatureIsOneEmptyGlyphAndOneWithInk() {
		guard let font = bundled else { Issue.record("the bundled font is missing"); return }
		var shaped = ShapedRuns()

		for text in ["!!", "->", "!=", ".."] {
			guard let pieces = shaped.pieces(
				for: text, cellOfOffset: [0, 1], font: font, faceIndex: 0
			) else { Issue.record("nothing shaped for \(text)"); return }
			#expect(pieces.count == 2, "\(text) still covers two cells")
			#expect(ink(pieces[0].glyph, pieces[0].font).isEmpty, "\(text) starts with a carrier")
			#expect(!ink(pieces[1].glyph, pieces[1].font).isEmpty, "\(text) ends with the ink")
		}
	}

	/// Two characters that do not join keep their own glyphs, both with ink —
	/// which is what makes the emptiness above a signal rather than a habit.
	@Test func charactersThatDoNotJoinBothDrawSomething() {
		guard let font = bundled else { Issue.record("the bundled font is missing"); return }
		var shaped = ShapedRuns()
		guard let pieces = shaped.pieces(
			for: "a!", cellOfOffset: [0, 1], font: font, faceIndex: 0
		) else { Issue.record("nothing shaped"); return }
		#expect(pieces.count == 2)
		#expect(!ink(pieces[0].glyph, pieces[0].font).isEmpty)
		#expect(!ink(pieces[1].glyph, pieces[1].font).isEmpty)
	}
}

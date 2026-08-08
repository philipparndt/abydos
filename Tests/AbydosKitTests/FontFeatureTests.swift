import AppKit
import Foundation
import Testing
@testable import AbydosKit

/// Turning programming ligatures off.
///
/// The obvious lever is `NSAttributedString.ligature`, and it is the wrong one:
/// it governs the typographic ligatures of prose — fi, fl — and setting it to
/// zero leaves `->` joined exactly as before. Measured on Fira Code, `->` shapes
/// to glyphs [1186, 1458] with the attribute at 0, at 1 and absent alike; only
/// `calt = 0` on the font gives back the plain [1221, 1580]. These fonts
/// substitute one glyph's shape for another rather than merging cells, which is
/// what lets a terminal have them at all.
struct FontFeatureTests {
	/// What the shaper makes of a string.
	private func shaped(_ text: String, font: NSFont) -> [CGGlyph] {
		let line = CTLineCreateWithAttributedString(
			NSAttributedString(string: text, attributes: [.font: font])
		)
		guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
		return runs.flatMap { run -> [CGGlyph] in
			let count = CTRunGetGlyphCount(run)
			var buffer = [CGGlyph](repeating: 0, count: count)
			CTRunGetGlyphs(run, CFRange(location: 0, length: count), &buffer)
			return buffer
		}
	}

	/// The glyphs a font gives each character on its own, with nothing shaped.
	private func perCharacter(_ text: String, font: NSFont) -> [CGGlyph] {
		var utf16 = Array(text.utf16)
		var out = [CGGlyph](repeating: 0, count: utf16.count)
		CTFontGetGlyphsForCharacters(font as CTFont, &utf16, &out, utf16.count)
		return out
	}

	/// With ligatures off, shaping gives back exactly the per-character glyphs.
	///
	/// True of any font, which is what makes it worth asserting: it holds
	/// vacuously for one with no ligatures and is the whole point for one with
	/// them. It is also what `.ligature = 0` failed to do.
	@Test(arguments: ["FiraCode-Regular", "Menlo-Regular", "Courier"])
	func offMeansTheFontsOwnGlyphs(name: String) throws {
		guard let font = NSFont(name: name, size: 13) else { return }
		let plain = font.withoutLigatures()
		for sample in ["->", "!=", "===", "<=", "|>", "ab"] {
			#expect(
				shaped(sample, font: plain) == perCharacter(sample, font: plain),
				"\(name) still shaped \(sample) into something else"
			)
		}
	}

	/// And where the font has them, on means something different from off —
	/// otherwise the switch is decorative.
	@Test func onMeansSomethingWhereTheFontHasThem() throws {
		guard let font = NSFont(name: "FiraCode-Regular", size: 13) else {
			// Nothing installed that ligates; there is nothing to prove here.
			return
		}
		#expect(shaped("->", font: font) != shaped("->", font: font.withoutLigatures()))
		#expect(shaped("ab", font: font) == shaped("ab", font: font.withoutLigatures()))
	}

	/// The advance is what the cell grid is built on, and a feature that
	/// substitutes shapes must not change it.
	@Test func theCellWidthIsUntouched() {
		let base = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
		let plain = base.withoutLigatures()
		#expect(plain.pointSize == base.pointSize)
		let width = { (font: NSFont) in ("0" as NSString).size(withAttributes: [.font: font]).width }
		#expect(abs(width(plain) - width(base)) < 0.01)
	}
}

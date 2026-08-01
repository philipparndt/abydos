import AppKit
import CoreText

/// Finding a font for a character the terminal's own face cannot draw.
enum GlyphFallback {
	/// Asks for the text form before the emoji one.
	///
	/// Some characters are emoji by default even though they read as symbols —
	/// the record mark Claude Code puts before each of its answers is one, and
	/// left to itself CoreText hands back a coloured button in a rounded box
	/// sitting in the middle of a paragraph. Terminals ask for the text form
	/// instead: a grid of one glyph per cell has no room for a picture, and
	/// what the character means here is a bullet.
	///
	/// U+FE0E is how that is asked for. If nothing has a text form, the emoji
	/// one is better than nothing.
	static func font(for scalar: UnicodeScalar, from base: CTFont) -> CTFont? {
		let textForm = String(scalar) + "\u{FE0E}"
		let candidate = CTFontCreateForString(
			base, textForm as CFString, CFRange(location: 0, length: textForm.utf16.count)
		)
		if !CTFontGetSymbolicTraits(candidate).contains(.traitColorGlyphs), has(scalar, candidate) {
			return candidate
		}

		let plain = String(scalar)
		let fallback = CTFontCreateForString(
			base, plain as CFString, CFRange(location: 0, length: plain.utf16.count)
		)
		return has(scalar, fallback) ? fallback : nil
	}

	private static func has(_ scalar: UnicodeScalar, _ font: CTFont) -> Bool {
		var utf16 = Array(String(scalar).utf16)
		var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
		return CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count) && glyphs[0] != 0
	}
}

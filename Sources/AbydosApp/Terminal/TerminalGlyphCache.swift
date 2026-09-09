import AppKit
import AbydosKit

/// cell on the screen.
struct CachedGlyph {
	let glyph: CGGlyph
	let font: CTFont
}

struct GlyphKey: Hashable {
	let scalar: UInt32
	/// Which of the four faces asked for it.
	let face: UInt8
}

/// Glyphs by code point and face.
///
/// Kept on the view rather than shared, so changing the font throws away the
/// glyphs that went with it.
final class GlyphCache {
	private var entries: [GlyphKey: CachedGlyph?] = [:]

	func clear() { entries.removeAll(keepingCapacity: true) }

	/// The glyph to draw for a code point, or nil when nothing can draw it.
	func glyph(for scalar: UInt32, face: NSFont, faceIndex: UInt8) -> CachedGlyph? {
		let key = GlyphKey(scalar: scalar, face: faceIndex)
		if let known = entries[key] { return known }

		let found = Self.lookUp(scalar: scalar, in: face)
		entries[key] = found
		return found
	}

	static func lookUp(scalar: UInt32, in face: NSFont) -> CachedGlyph? {
		guard let unicode = UnicodeScalar(scalar) else { return nil }
		var utf16 = Array(String(unicode).utf16)
		var glyphs = [CGGlyph](repeating: 0, count: utf16.count)

		let ctFace = face as CTFont
		if CTFontGetGlyphsForCharacters(ctFace, &utf16, &glyphs, utf16.count), glyphs[0] != 0 {
			return CachedGlyph(glyph: glyphs[0], font: ctFace)
		}

		// The terminal's own face has no glyph for it — emoji, CJK and the
		// powerline range all come from somewhere else. CoreText knows where.
		guard let fallback = GlyphFallback.font(for: unicode, from: ctFace),
		      CTFontGetGlyphsForCharacters(fallback, &utf16, &glyphs, utf16.count),
		      glyphs[0] != 0
		else { return nil }
		return CachedGlyph(glyph: glyphs[0], font: fallback)
	}
}

/// Splits a keystroke into where its time actually goes.
///
/// `echo` is the round trip through the pty — the shell, and tmux if it is in
/// the way — which no terminal can do anything about. `parse` and `draw` are
/// ours: how long the bytes wait to be read, and how long the picture then

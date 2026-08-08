import AppKit
import CoreText

public extension NSFont {
	/// The same font with programming ligatures turned off.
	///
	/// `NSAttributedString.ligature` is the obvious lever and it is the wrong
	/// one: it governs the typographic ligatures of prose — fi, fl — and
	/// setting it to 0 leaves `->` joined exactly as before. Fira Code and
	/// JetBrains Mono build their arrows and arrows-with-tails out of
	/// *contextual alternates*, which substitute one glyph's shape for another
	/// without changing how many there are. That is deliberate on their part,
	/// and it is why a terminal can have them at all: the cell count never
	/// changes, so the grid never moves.
	///
	/// So the switch has to reach `calt`, and it has to be on the font, which
	/// is also the right place — every measurement and every draw then agrees
	/// without being told separately.
	func withoutLigatures() -> NSFont {
		let descriptor = fontDescriptor.addingAttributes([
			.featureSettings: [[
				kCTFontOpenTypeFeatureTag as NSFontDescriptor.FeatureKey: "calt",
				kCTFontOpenTypeFeatureValue as NSFontDescriptor.FeatureKey: 0,
			] as [NSFontDescriptor.FeatureKey: Any]],
		])
		return NSFont(descriptor: descriptor, size: pointSize) ?? self
	}

	/// The font the settings ask for: this one, or this one without ligatures.
	func honouringLigatureSetting() -> NSFont {
		Settings.shared.fontLigatures ? self : withoutLigatures()
	}
}

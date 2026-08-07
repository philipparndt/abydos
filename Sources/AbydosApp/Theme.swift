import AppKit
import AbydosKit

/// Colours and metrics matching JetBrains' "New UI" dark theme, which is what the
/// reference screenshots show.
struct Theme {
	static var current = Theme.dusk

	/// Chooses the palette from the setting, and from the system when the
	/// setting defers to it.
	///
	/// Called at startup and whenever either changes. Returns whether anything
	/// actually changed, so a redraw of every window is only asked for when
	/// there is something to see.
	@discardableResult
	static func apply() -> Bool {
		let wanted: Theme
		switch Settings.shared.activeAppearance {
		case "light": wanted = .daylight
		case "dark": wanted = .dusk
		case "abydos": wanted = .abydos
		case "abydos-light": wanted = .abydosLight
		// Abydos, following the system — which the old single list could not
		// say at all, since it had one entry per palette-and-lightness pair.
		case "abydos-system": wanted = systemIsDark ? .abydos : .abydosLight
		default: wanted = systemIsDark ? .dusk : .daylight
		}

		// Native controls — fields, alerts, scrollers, the titlebar — take
		// their look from the app's appearance rather than from this palette,
		// and a light window with dark scrollbars in it looks broken.
		//
		// Except when the theme follows the system, where the app is left to
		// follow it too: that way the controls change when somebody changes the
		// system, without this having to be told.
		if Appearance.mode(of: Settings.shared.activeAppearance) == .system {
			NSApp.appearance = nil
		} else {
			NSApp.appearance = NSAppearance(named: wanted.isLight ? .aqua : .darkAqua)
		}

		guard wanted.name != current.name else { return false }
		previous = current
		current = wanted
		return true
	}

	/// The palette that was in use before the last change, so what was drawn in
	/// it can be recognised and swapped.
	static var previous = Theme.dusk

	/// What the system is set to right now.
	///
	/// Asked of the system rather than of `NSApp.effectiveAppearance`. Every
	/// theme that is not "system" forces an appearance on the app, and once one
	/// is forced the app answers with what it was given — so a theme that
	/// follows the system was following itself, and switching from Light to
	/// System stayed light on a machine set to dark.
	static var systemIsDark: Bool {
		if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
			return style.lowercased().contains("dark")
		}
		// The key is absent in light mode, and also absent when nothing has
		// ever set it — in which case the app's own appearance is the best
		// answer left, and it is unforced here by definition.
		return NSApp.appearance == nil
			? NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			: false
	}

	/// Which palette this is.
	///
	/// The switch used to compare light against dark, which is all there was.
	/// With two dark palettes that comparison says they are the same and the
	/// change is dropped, so they are compared by name.
	var name = "dusk"

	/// Whether this palette is a light one.
	///
	/// Syntax colours are chosen from it rather than stored twenty-odd times
	/// over, and a few places need to know which way round the contrast goes.
	var isLight = false

	// Surfaces
	var windowBackground: NSColor
	var sidebarBackground: NSColor
	var editorBackground: NSColor
	var toolbarBackground: NSColor
	var separator: NSColor

	// Sidebar / navigator
	var sidebarText: NSColor
	var sidebarHeaderText: NSColor
	var selectionActive: NSColor
	var selectionInactive: NSColor
	var excludedDirectoryTint: NSColor

	// Version control states
	var gitAdded: NSColor
	var gitModified: NSColor
	var gitUnversioned: NSColor
	var gitIgnored: NSColor
	var gitConflict: NSColor

	// Editor chrome
	var editorText: NSColor
	var gutterText: NSColor
	var gutterCurrentLineText: NSColor
	var currentLineBackground: NSColor
	var caret: NSColor
	var selectionBackground: NSColor
	var foldPlaceholderBackground: NSColor
	var foldPlaceholderText: NSColor
	var indentGuide: NSColor

	// Metrics. Read from Settings rather than stored, so a preference change
	// applies on the next redraw without a restart.

	/// Global zoom (⌘+ / ⌘- / ⌘0). Every dimension in the window goes through
	/// `scaled(_:)` or `uiFont(_:)` so the interface zooms as one piece.
	///
	/// The presentation zoom while presenting, which is a separate number: the
	/// size a room needs is not the size a desk does, and coming back from a
	/// talk should not mean finding the zoom by hand.
	var scale: CGFloat { CGFloat(Settings.shared.activeScale) }

	/// Scales a design-time dimension. Rounded to whole points so borders and
	/// separators stay crisp instead of landing on half pixels.
	func scaled(_ value: CGFloat) -> CGFloat {
		(value * scale).rounded()
	}

	/// A UI font at a design-time size, scaled.
	func uiFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
		.systemFont(ofSize: size * scale, weight: weight)
	}

	/// The editor's own font size is a separate preference, multiplied by zoom.
	var fontSize: CGFloat { CGFloat(Settings.shared.editorFontSize) * scale }
	var lineHeightMultiple: CGFloat { CGFloat(Settings.shared.editorLineHeight) }
	var tabWidth: Int { Settings.shared.tabWidth }

	/// Renders an SF Symbol in a given colour.
	///
	/// `NSColor.set()` followed by `NSImage.draw(in:)` does *not* tint a template
	/// image — AppKit only applies template tinting when a control draws it, so
	/// hand-drawn symbols come out black and vanish against a dark background.
	/// Baking the colour into the symbol configuration is what actually works.
	static func symbol(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSImage? {
		guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
		let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
			.applying(.init(paletteColors: [color]))
		return base.withSymbolConfiguration(config) ?? base
	}

	/// Font for the terminal, with a fallback chain for powerline glyphs.
	///
	/// Prompt themes draw their separators with Private Use Area codepoints that
	/// SF Mono has no glyphs for, which is why they render as blank boxes. A
	/// cascade list keeps the chosen font for text while borrowing those glyphs
	/// from whichever Nerd Font is installed.
	static func terminalFont(size: CGFloat) -> NSFont {
		let base: NSFont
		if !Settings.shared.terminalFontName.isEmpty,
		   let chosen = NSFont(name: Settings.shared.terminalFontName, size: size) {
			base = chosen
		} else if let bundled = NSFont(name: FontRegistry.bundledMonospaceFamily, size: size) {
			// The shipped Nerd Font, so powerline prompts render on any machine.
			base = bundled
		} else {
			base = .monospacedSystemFont(ofSize: size, weight: .regular)
		}

		let descriptor = base.fontDescriptor.addingAttributes([
			.cascadeList: powerlineFallbackDescriptors,
		])
		return NSFont(descriptor: descriptor, size: size) ?? base
	}

	/// Installed fonts known to carry powerline/Nerd glyphs, most preferred first.
	private static let powerlineFallbackDescriptors: [NSFontDescriptor] = {
		// Not filtered against `availableFontFamilies`: that list does not include
		// process-registered fonts, so filtering silently dropped the one we
		// ship. A descriptor naming a font that is not installed is simply
		// skipped when the cascade is resolved, so listing all of them is safe.
		[
			FontRegistry.bundledMonospaceFamily,
			"MesloLGS Nerd Font", "MesloLGS NF",
			"RobotoMono Nerd Font",
			"JetBrainsMono Nerd Font", "Hack Nerd Font", "FiraCode Nerd Font",
			"Meslo LG M for Powerline", "Meslo LG S for Powerline",
			"DejaVu Sans Mono for Powerline",
			"Menlo",
		].map { NSFontDescriptor(fontAttributes: [.family: $0]) }
	}()

	var editorFont: NSFont {
		// A fixed-advance font lets the code view compute column positions
		// arithmetically instead of measuring, which is a large part of why
		// scrolling stays cheap. The bundled font is fixed-advance and gives the
		// editor the same typeface as the terminal.
		NSFont(name: FontRegistry.bundledMonospaceFamily, size: fontSize)
			?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
	}

	/// The one theme, and ours rather than borrowed.
	///
	/// It started as IDEA's palette value for value, which is a fine place to
	/// learn from and a poor place to stay: those colours are that product's
	/// signature. The shape of the scheme is kept — dark and quiet chrome, one
	/// warm colour for keywords, green for text you wrote, blue for things
	/// that are called — while every value is our own: the greys carry a
	/// little more blue, and the syntax hues are pulled apart so that keyword,
	/// type and call read as three colours rather than three shades.
	static let dusk = Theme(
		name: "dusk",
		windowBackground: .hex(0x1A1C21),
		sidebarBackground: .hex(0x24272E),
		editorBackground: .hex(0x1A1C21),
		toolbarBackground: .hex(0x24272E),
		separator: .hex(0x343842),

		sidebarText: .hex(0xC2C6D0),
		sidebarHeaderText: .hex(0xE3E6EC),
		selectionActive: .hex(0x3A5691),
		selectionInactive: .hex(0x343842),
		excludedDirectoryTint: .hex(0x4A3B24),

		gitAdded: .hex(0x71B382),
		gitModified: .hex(0x4E9ED4),
		gitUnversioned: .hex(0xCE7C6E),
		gitIgnored: .hex(0x6C7383),
		gitConflict: .hex(0xD6706E),

		editorText: .hex(0xC2C6D0),
		gutterText: .hex(0x5C6270),
		gutterCurrentLineText: .hex(0xA7ACBA),
		currentLineBackground: .hex(0x22252C),
		caret: .hex(0xD4D8E2),
		selectionBackground: .hex(0x2C4269),
		foldPlaceholderBackground: .hex(0x363A45),
		foldPlaceholderText: .hex(0xA0A5B3),
		indentGuide: .hex(0x2F323B)
	)

	/// The app's own palette: a sun on the horizon.
	///
	/// Amber earns its place three times over — it is CRT phosphor, it is
	/// desert, and it is a warm ground in a category that is wall to wall blue.
	/// Built from six colours: a core light, an amber, an ember, sandstone, a
	/// deep brown and the ground everything sits on.
	///
	/// The surfaces are nearly black with warmth in them rather than brown:
	/// a brown editor is tiring within the hour, and what should be warm is the
	/// light falling on it, not the paper.
	static let abydos = Theme(
		name: "abydos",
		windowBackground: .hex(0x151210),
		sidebarBackground: .hex(0x1C1712),
		editorBackground: .hex(0x151210),
		toolbarBackground: .hex(0x1C1712),
		separator: .hex(0x33240F),

		sidebarText: .hex(0xCDBFA9),
		sidebarHeaderText: .hex(0xFFE0AC),
		selectionActive: .hex(0x6B3B10),
		selectionInactive: .hex(0x2A2018),
		excludedDirectoryTint: .hex(0x33240F),

		// Semantic before decorative: a conflict is red wherever it happens,
		// and green is the only colour "added" can be. The rest lean warm.
		gitAdded: .hex(0x9FB37A),
		gitModified: .hex(0xF7B44E),
		gitUnversioned: .hex(0xD97F18),
		gitIgnored: .hex(0x7A6A55),
		gitConflict: .hex(0xD6706E),

		editorText: .hex(0xE8D9C0),
		gutterText: .hex(0x6E5B45),
		gutterCurrentLineText: .hex(0xC6A97D),
		currentLineBackground: .hex(0x1E1813),
		caret: .hex(0xF7B44E),
		selectionBackground: .hex(0x4A2C0E),
		foldPlaceholderBackground: .hex(0x2A2118),
		foldPlaceholderText: .hex(0xC0A582),
		indentGuide: .hex(0x2A2118)
	)

	/// Abydos in daylight.
	///
	/// Not the dark one inverted. Amber on near-black works because the amber
	/// is the light in the room; on paper the same amber is a highlighter pen.
	/// So the warmth moves into the surfaces — unbleached paper rather than
	/// white — and the ink is a dark brown that reads as black until it is next
	/// to one. The accent stays amber but is taken down to where it can be read
	/// on paper, which is roughly the colour of the same pigment in shadow.
	static let abydosLight = Theme(
		name: "abydos-light",
		isLight: true,

		windowBackground: .hex(0xFAF5EC),
		sidebarBackground: .hex(0xF3EBDD),
		editorBackground: .hex(0xFFFBF3),
		toolbarBackground: .hex(0xF3EBDD),
		separator: .hex(0xE0D2BB),

		sidebarText: .hex(0x40342A),
		sidebarHeaderText: .hex(0x241C14),
		selectionActive: .hex(0xF2D9A8),
		selectionInactive: .hex(0xE9E0CF),
		excludedDirectoryTint: .hex(0xEADCC0),

		// The same semantics as everywhere else — a conflict is red, added is
		// green — at a weight that survives being read on paper.
		gitAdded: .hex(0x5E7A34),
		gitModified: .hex(0xB07407),
		gitUnversioned: .hex(0xA85A12),
		gitIgnored: .hex(0x9A8B74),
		gitConflict: .hex(0xB33A36),

		editorText: .hex(0x2E241B),
		gutterText: .hex(0xB0A28C),
		gutterCurrentLineText: .hex(0x6B5741),
		currentLineBackground: .hex(0xFBF3E3),
		caret: .hex(0xB07407),
		selectionBackground: .hex(0xF6E3BC),
		foldPlaceholderBackground: .hex(0xEFE4CE),
		foldPlaceholderText: .hex(0x6B5741),
		indentGuide: .hex(0xEAE0CC)
	)

	/// The same interface in daylight.
	///
	/// Not the dark palette inverted: a light theme wants more contrast in the
	/// text and less in the surfaces, or every panel edge shouts. The greys are
	/// close together and the colours do the separating.
	static let daylight = Theme(
		name: "daylight",
		isLight: true,

		windowBackground: .hex(0xF7F8FA),
		sidebarBackground: .hex(0xF2F3F5),
		editorBackground: .hex(0xFFFFFF),
		toolbarBackground: .hex(0xF2F3F5),
		separator: .hex(0xD8DAE0),

		sidebarText: .hex(0x2B2D30),
		sidebarHeaderText: .hex(0x14161A),
		selectionActive: .hex(0xBFD5F5),
		selectionInactive: .hex(0xE1E3E8),
		excludedDirectoryTint: .hex(0xF6E9CC),

		gitAdded: .hex(0x2E8B45),
		gitModified: .hex(0x1F6FCC),
		gitUnversioned: .hex(0xB4553F),
		gitIgnored: .hex(0x8A8F98),
		gitConflict: .hex(0xC5372F),

		editorText: .hex(0x2B2D30),
		gutterText: .hex(0xA1A5AE),
		gutterCurrentLineText: .hex(0x5A5F6A),
		currentLineBackground: .hex(0xF3F6FB),
		caret: .hex(0x1F2126),
		selectionBackground: .hex(0xCBDEFB),
		foldPlaceholderBackground: .hex(0xE4E6EA),
		foldPlaceholderText: .hex(0x5A5F6A),
		indentGuide: .hex(0xE6E8EC)
	)

	/// Maps a syntax token to a colour. `HighlightKind` is produced by AbydosKit
	/// from tree-sitter capture names, so the theme never sees grammar details.
	func color(for kind: HighlightKind) -> NSColor {
		if name == "abydos-light" { return abydosLightColor(for: kind) }
		if isLight { return lightColor(for: kind) }
		if name == "abydos" { return abydosColor(for: kind) }
		switch kind {
		// Keyword warm, string green, call blue: the arrangement every dark
		// scheme has settled on, in our own values. Parameters are tinted
		// away from plain text — they are the one identifier whose meaning
		// comes from where it sits rather than from what it says.
		case .keyword:      return .hex(0xD8926B)
		case .type:         return .hex(0xAFB3EC)
		case .function:     return .hex(0x62B4F0)
		case .method:       return .hex(0x62B4F0)
		case .property:     return .hex(0xC983C5)
		case .variable:     return editorText
		case .parameter:    return .hex(0xB6BDD0)
		case .constant:     return .hex(0xC983C5)
		case .string:       return .hex(0x7FB98C)
		case .escape:       return .hex(0xE0A87E)
		case .number:       return .hex(0x46BDB6)
		case .boolean:      return .hex(0xD8926B)
		case .comment:      return .hex(0x71798B)
		case .documentation:return .hex(0x6B8F84)
		case .operatorToken:return .hex(0xB6BDD0)
		case .punctuation:  return .hex(0x9BA2B2)
		case .tag:          return .hex(0xE5BE72)
		case .attribute:    return .hex(0xB6BDD0)
		case .label:        return .hex(0xC983C5)
		case .namespace:    return .hex(0xA9B4C6)
		case .heading:      return .hex(0xE5BE72)
		case .link:         return .hex(0x6E97F0)
		case .emphasis:     return .hex(0xC2C6D0)
		case .error:        return .hex(0xD6706E)
		case .plain:        return editorText
		}
	}

	/// The same arrangement on a warm ground.
	///
	/// Not the dusk palette reused: those colours are chosen against a
	/// blue-grey, and a blue call on an amber background is the one pairing
	/// that looks like a mistake rather than a choice. Keywords take the ember,
	/// strings a desert green, calls a pale gold — the hues are near each other
	/// and the work is done by lightness, which is what makes a warm scheme
	/// readable rather than muddy.
	/// The warm palette at daylight weights.
	///
	/// The same roles in the same hues as the dark one — keywords amber,
	/// strings green, calls the accent — but each taken to where it can be read
	/// on unbleached paper. Comments are the one thing that moves rather than
	/// darkens: a grey-brown at this weight disappears, so they keep a little
	/// green and sit clearly behind the code.
	private func abydosLightColor(for kind: HighlightKind) -> NSColor {
		switch kind {
		case .keyword:      return .hex(0x9A5B0C)
		case .type:         return .hex(0x7A5A16)
		case .function:     return .hex(0xA8600A)
		case .method:       return .hex(0xA8600A)
		case .property:     return .hex(0x8A5A22)
		case .variable:     return editorText
		case .parameter:    return .hex(0x5C4A33)
		case .constant:     return .hex(0xA2521A)
		case .string:       return .hex(0x4F6B2A)
		case .escape:       return .hex(0x9A5B2A)
		case .number:       return .hex(0x7A5A16)
		case .boolean:      return .hex(0x9A5B0C)
		case .comment:      return .hex(0x8A8266)
		case .documentation:return .hex(0x6A7A4A)
		case .operatorToken:return .hex(0x5C4A33)
		case .punctuation:  return .hex(0x6E5F49)
		case .tag:          return .hex(0x9A5B0C)
		case .attribute:    return .hex(0x5C4A33)
		case .label:        return .hex(0x8A5A22)
		case .namespace:    return .hex(0x6B5741)
		case .heading:      return .hex(0x7A4A08)
		case .link:         return .hex(0xA2521A)
		case .emphasis:     return .hex(0x2E241B)
		case .error:        return .hex(0xB33A36)
		case .plain:        return editorText
		}
	}

	private func abydosColor(for kind: HighlightKind) -> NSColor {
		switch kind {
		case .keyword:      return .hex(0xE0913A)
		case .type:         return .hex(0xD8C08A)
		case .function:     return .hex(0xF7B44E)
		case .method:       return .hex(0xF7B44E)
		case .property:     return .hex(0xD9A05B)
		case .variable:     return editorText
		case .parameter:    return .hex(0xC3B192)
		case .constant:     return .hex(0xE8A05C)
		case .string:       return .hex(0x9FB37A)
		case .escape:       return .hex(0xC98A4B)
		case .number:       return .hex(0xC5A572)
		case .boolean:      return .hex(0xE0913A)
		case .comment:      return .hex(0x7A6A55)
		case .documentation:return .hex(0x8A9A6B)
		case .operatorToken:return .hex(0xC3B192)
		case .punctuation:  return .hex(0xA6947A)
		case .tag:          return .hex(0xE0913A)
		case .attribute:    return .hex(0xC3B192)
		case .label:        return .hex(0xD9A05B)
		case .namespace:    return .hex(0xC0A582)
		case .heading:      return .hex(0xFFE0AC)
		case .link:         return .hex(0xE8A05C)
		case .emphasis:     return .hex(0xE8D9C0)
		case .error:        return .hex(0xD6706E)
		case .plain:        return editorText
		}
	}

	/// The same arrangement on white: keyword blue, string green, call teal.
	///
	/// Darker and more saturated than the dark theme's, because a colour that
	/// reads well against near-black washes out against white.
	private func lightColor(for kind: HighlightKind) -> NSColor {
		switch kind {
		case .keyword:      return .hex(0x0033B3)
		case .type:         return .hex(0x7A3E9D)
		case .function:     return .hex(0x00627A)
		case .method:       return .hex(0x00627A)
		case .property:     return .hex(0x871094)
		case .variable:     return editorText
		case .parameter:    return .hex(0x4B5563)
		case .constant:     return .hex(0x871094)
		case .string:       return .hex(0x067D17)
		case .escape:       return .hex(0x0037A6)
		case .number:       return .hex(0x1750EB)
		case .boolean:      return .hex(0x0033B3)
		case .comment:      return .hex(0x8A8F98)
		case .documentation:return .hex(0x3D7A4E)
		case .operatorToken:return .hex(0x4B5563)
		case .punctuation:  return .hex(0x6B7280)
		case .tag:          return .hex(0x0033B3)
		case .attribute:    return .hex(0x4B5563)
		case .label:        return .hex(0x871094)
		case .namespace:    return .hex(0x374151)
		case .heading:      return .hex(0x0033B3)
		case .link:         return .hex(0x1750EB)
		case .emphasis:     return editorText
		case .error:        return .hex(0xC5372F)
		case .plain:        return editorText
		}
	}

	/// Colour for a file's version-control state in the navigator.
	func color(for status: GitFileStatus) -> NSColor {
		switch status {
		case .unmodified:  return sidebarText
		case .added:       return gitAdded
		case .modified:    return gitModified
		case .unversioned: return gitUnversioned
		case .ignored:     return gitIgnored
		case .conflicted:  return gitConflict
		case .deleted:     return gitIgnored
		}
	}
}

extension NSColor {
	/// 0xRRGGBB literal, which keeps the palette above readable.
	static func hex(_ value: UInt32, alpha: CGFloat = 1.0) -> NSColor {
		NSColor(
			srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
			green: CGFloat((value >> 8) & 0xFF) / 255.0,
			blue: CGFloat(value & 0xFF) / 255.0,
			alpha: alpha
		)
	}
}

extension NSImage {
	/// Draws the image centred in `slot`, keeping its own proportions.
	///
	/// SF Symbols are not square. A folder is wider than it is tall, a chevron
	/// wider still, a document taller than wide — and drawing one into a square
	/// box stretches it to fit. Icons then look squeezed, and a chevron squeezed
	/// horizontally stops reading as a chevron and starts reading as a letter v.
	///
	/// respectFlipped: these views are flipped, and without it every symbol
	/// draws upside down.
	func drawFitted(in slot: NSRect, fraction: CGFloat = 1.0) {
		guard size.width > 0, size.height > 0, slot.width > 0, slot.height > 0 else { return }

		let scale = min(slot.width / size.width, slot.height / size.height)
		let fitted = NSSize(width: size.width * scale, height: size.height * scale)
		draw(
			in: NSRect(
				x: slot.midX - fitted.width / 2,
				y: slot.midY - fitted.height / 2,
				width: fitted.width,
				height: fitted.height
			),
			from: .zero,
			operation: .sourceOver,
			fraction: fraction,
			respectFlipped: true,
			hints: nil
		)
	}
}

import AppKit
import IdeaiKit

/// Colours and metrics matching JetBrains' "New UI" dark theme, which is what the
/// reference screenshots show.
struct Theme {
	static var current = Theme.darcula

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

	// Metrics
	var fontSize: CGFloat = 12.5
	var lineHeightMultiple: CGFloat = 1.4

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

	var editorFont: NSFont {
		// A fixed-advance font lets the code view compute column positions
		// arithmetically instead of measuring, which is a large part of why
		// scrolling stays cheap.
		NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
	}

	static let darcula = Theme(
		windowBackground: .hex(0x1E1F22),
		sidebarBackground: .hex(0x2B2D30),
		editorBackground: .hex(0x1E1F22),
		toolbarBackground: .hex(0x2B2D30),
		separator: .hex(0x393B40),

		sidebarText: .hex(0xBCBEC4),
		sidebarHeaderText: .hex(0xDFE1E5),
		selectionActive: .hex(0x3C5596),
		selectionInactive: .hex(0x393B40),
		excludedDirectoryTint: .hex(0x4A3A22),

		gitAdded: .hex(0x6AAB73),
		gitModified: .hex(0x3592C4),
		gitUnversioned: .hex(0xC7756B),
		gitIgnored: .hex(0x6E7175),
		gitConflict: .hex(0xD16969),

		editorText: .hex(0xBCBEC4),
		gutterText: .hex(0x606366),
		gutterCurrentLineText: .hex(0xA1A3AB),
		currentLineBackground: .hex(0x26282E),
		caret: .hex(0xCED0D6),
		selectionBackground: .hex(0x2E436E),
		foldPlaceholderBackground: .hex(0x3A3D42),
		foldPlaceholderText: .hex(0x9DA0A8),
		indentGuide: .hex(0x33353A)
	)

	/// Maps a syntax token to a colour. `HighlightKind` is produced by IdeaiKit
	/// from tree-sitter capture names, so the theme never sees grammar details.
	func color(for kind: HighlightKind) -> NSColor {
		switch kind {
		case .keyword:      return .hex(0xCF8E6D)
		case .type:         return .hex(0xB5B6E3)
		case .function:     return .hex(0x56A8F5)
		case .method:       return .hex(0x56A8F5)
		case .property:     return .hex(0xC77DBB)
		case .variable:     return .hex(0xBCBEC4)
		case .parameter:    return .hex(0xBCBEC4)
		case .constant:     return .hex(0xC77DBB)
		case .string:       return .hex(0x6AAB73)
		case .escape:       return .hex(0xCF8E6D)
		case .number:       return .hex(0x2AACB8)
		case .boolean:      return .hex(0xCF8E6D)
		case .comment:      return .hex(0x7A7E85)
		case .documentation:return .hex(0x5F826B)
		case .operatorToken:return .hex(0xBCBEC4)
		case .punctuation:  return .hex(0xBCBEC4)
		case .tag:          return .hex(0xE8BF6A)
		case .attribute:    return .hex(0xBABABA)
		case .label:        return .hex(0xC77DBB)
		case .namespace:    return .hex(0xBCBEC4)
		case .heading:      return .hex(0xE8BF6A)
		case .link:         return .hex(0x548AF7)
		case .emphasis:     return .hex(0xBCBEC4)
		case .error:        return .hex(0xD16969)
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

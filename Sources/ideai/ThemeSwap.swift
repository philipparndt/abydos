import AppKit

/// Changing the palette of a window that is already on screen.
///
/// Most of what this app draws reads `Theme.current` at draw time and needs
/// nothing but a repaint. The exceptions are the colours that get *copied*
/// somewhere when a view is built — a layer's background, a table's, a text
/// field's — and there are ninety-odd of those. Chasing each one by hand is how
/// a theme switch ends up nearly working.
///
/// So the swap is done by recognising the colours themselves: anything holding
/// a colour from the palette that was in use is handed the same role from the
/// palette that has taken over. A colour from anywhere else — a syntax token, a
/// git state baked into a control, a deliberate one-off — is left alone.
enum ThemeSwap {
	/// The colours a palette is made of, in role order, so two palettes can be
	/// lined up against each other.
	private static func roles(of theme: Theme) -> [NSColor] {
		[
			theme.windowBackground,
			theme.sidebarBackground,
			theme.editorBackground,
			theme.toolbarBackground,
			theme.separator,
			theme.sidebarText,
			theme.sidebarHeaderText,
			theme.selectionActive,
			theme.selectionInactive,
			theme.excludedDirectoryTint,
			theme.gitAdded,
			theme.gitModified,
			theme.gitUnversioned,
			theme.gitIgnored,
			theme.gitConflict,
			theme.editorText,
			theme.gutterText,
			theme.gutterCurrentLineText,
			theme.currentLineBackground,
			theme.caret,
			theme.selectionBackground,
			theme.foldPlaceholderBackground,
			theme.foldPlaceholderText,
			theme.indentGuide,
		]
	}

	/// The same role in the new palette, or nil when the colour was not the old
	/// palette's to begin with.
	///
	/// Alpha is kept: a background at 98% opacity stays at 98%.
	static func counterpart(of colour: NSColor, from old: Theme, to new: Theme) -> NSColor? {
		guard let srgb = colour.usingColorSpace(.sRGB) else { return nil }
		let alpha = srgb.alphaComponent

		let before = roles(of: old)
		let after = roles(of: new)
		for (index, candidate) in before.enumerated() {
			guard let other = candidate.usingColorSpace(.sRGB) else { continue }
			guard abs(other.redComponent - srgb.redComponent) < 0.004,
			      abs(other.greenComponent - srgb.greenComponent) < 0.004,
			      abs(other.blueComponent - srgb.blueComponent) < 0.004
			else { continue }
			return alpha < 0.999 ? after[index].withAlphaComponent(alpha) : after[index]
		}
		return nil
	}

	/// Walks a view and everything under it, swapping the palette's colours for
	/// their counterparts and asking for a repaint.
	static func apply(from old: Theme, to new: Theme, in view: NSView) {
		swapColours(from: old, to: new, in: view)
		view.needsDisplay = true
		for child in view.subviews {
			apply(from: old, to: new, in: child)
		}
	}

	private static func swapColours(from old: Theme, to new: Theme, in view: NSView) {
		if let coloured = view as? ColoredView { coloured.refreshColour() }

		if let cgColour = view.layer?.backgroundColor,
		   let colour = NSColor(cgColor: cgColour),
		   let swapped = counterpart(of: colour, from: old, to: new) {
			view.layer?.backgroundColor = swapped.cgColor
		}

		switch view {
		case let table as NSTableView:
			if let swapped = counterpart(of: table.backgroundColor, from: old, to: new) {
				table.backgroundColor = swapped
			}
		case let scroll as NSScrollView:
			if let swapped = counterpart(of: scroll.backgroundColor, from: old, to: new) {
				scroll.backgroundColor = swapped
			}
		case let field as NSTextField:
			if let background = field.backgroundColor,
			   let swapped = counterpart(of: background, from: old, to: new) {
				field.backgroundColor = swapped
			}
			if let swapped = counterpart(of: field.textColor ?? .labelColor, from: old, to: new) {
				field.textColor = swapped
			}
		case let text as NSTextView:
			if let background = text.backgroundColor as NSColor?,
			   let swapped = counterpart(of: background, from: old, to: new) {
				text.backgroundColor = swapped
			}
			if let swapped = counterpart(of: text.textColor ?? .labelColor, from: old, to: new) {
				text.textColor = swapped
			}
			if let swapped = counterpart(of: text.insertionPointColor, from: old, to: new) {
				text.insertionPointColor = swapped
			}
		case let box as NSBox:
			if let swapped = counterpart(of: box.fillColor, from: old, to: new) {
				box.fillColor = swapped
			}
		default:
			break
		}
	}
}

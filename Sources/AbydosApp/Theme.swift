import AppKit
import AbydosKit

/// The palette in force: one scheme file, at one lightness.
///
/// The colours themselves are not here. Each scheme is a JSON file with an
/// `app` section — see `Scheme` in AbydosKit and `Schemes/README.md` beside the
/// files — and this is what turns one of those into the `NSColor`s the window
/// draws with, plus the metrics, which are read from Settings rather than
/// stored.
struct Theme {
	/// The palette in force.
	///
	/// **Read and written on the main thread, and that is a rule rather than a
	/// habit.** Assigning one of these is not one store — it is a struct of some
	/// thirty-five `NSColor`s and two more fields — so a reader that caught it
	/// mid-assignment would get a palette belonging to neither, which is exactly
	/// the shape of the abort in 0400: rare, unreproducible by probing the
	/// values, and invisible in the source at the crash site.
	///
	/// The audit that went with that item found no such reader — every writer is
	/// on the main thread, no view sets `canDrawConcurrently`, the terminal's
	/// display link is added to the main run loop, and every background block in
	/// the app target calls only into `AbydosKit`, which cannot see this type at
	/// all. **An audit is true on the day it is done**, and there are 1580 reads
	/// across 99 files, so the finding is kept true by the check below rather
	/// than by anybody remembering it.
	static var current: Theme {
		get {
			ThemeAccess.noteRead()
			return stored
		}
		set {
			ThemeAccess.noteWrite()
			stored = newValue
		}
	}

	private static var stored = Theme(scheme: SchemeLibrary.shared.defaultAppScheme, isLight: false)

	/// Chooses the palette from the setting, and from the system when the
	/// setting defers to it.
	///
	/// Called at startup and whenever either changes. Returns whether anything
	/// actually changed, so a redraw of every window is only asked for when
	/// there is something to see.
	@discardableResult
	static func apply() -> Bool {
		let stored = Settings.shared.activeAppearance
		let library = SchemeLibrary.shared
		let scheme = library.appScheme(id: Appearance.family(of: stored)) ?? library.defaultAppScheme
		let wanted = Theme(
			scheme: scheme,
			isLight: Appearance.isLight(stored, systemIsDark: systemIsDark)
		)

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

		// The name is not enough. A scheme keeps its name when its file is
		// edited, so somebody who has just changed a colour in their own scheme
		// and pressed reload asks for the palette it already thinks it has —
		// same name, different colours, and nothing would repaint.
		guard wanted.name != current.name || wanted.palette != current.palette else {
			return false
		}
		previous = current
		current = wanted
		// The kept symbols were drawn in the old scheme's shades. Emptied here
		// rather than left to be overwritten, because the old ones would never be
		// asked for again and a theme somebody flips twice would keep both.
		forgetSymbols()
		return true
	}

	/// The palette that was in use before the last change, so what was drawn in
	/// it can be recognised and swapped.
	static var previous = Theme.current

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
	/// change is dropped, so they are compared by name — the scheme's, and
	/// which way round it is.
	let name: String

	/// Whether this palette is a light one.
	///
	/// Syntax colours are chosen from it rather than stored twenty-odd times
	/// over, and a few places need to know which way round the contrast goes.
	let isLight: Bool

	/// The file this was read from, which is also where the syntax colours are
	/// looked up as they are asked for.
	private let palette: SchemeApp

	// Surfaces
	let windowBackground: NSColor
	let sidebarBackground: NSColor
	let editorBackground: NSColor
	let toolbarBackground: NSColor
	let separator: NSColor

	// Sidebar / navigator
	let sidebarText: NSColor
	let sidebarHeaderText: NSColor
	let selectionActive: NSColor
	let selectionInactive: NSColor
	let excludedDirectoryTint: NSColor

	// Version control states
	let gitAdded: NSColor
	let gitModified: NSColor
	let gitUnversioned: NSColor
	let gitIgnored: NSColor
	let gitConflict: NSColor

	// Editor chrome
	let editorText: NSColor
	let gutterText: NSColor
	let gutterCurrentLineText: NSColor
	let currentLineBackground: NSColor
	let caret: NSColor
	let selectionBackground: NSColor
	let selectionBackgroundInactive: NSColor
	/// Every find-in-file match on screen except the one being looked at.
	let searchMatchBackground: NSColor
	/// The one being looked at, which is the point of having a current match at
	/// all: it has to be the loudest of them from across the file. See
	/// `CodeView.drawLine`, which paints it *after* the selection for that
	/// reason.
	let searchMatchCurrentBackground: NSColor
	let foldPlaceholderBackground: NSColor
	let foldPlaceholderText: NSColor
	let indentGuide: NSColor

	/// One scheme, at one lightness.
	///
	/// The surfaces are read out once rather than looked up per draw: every one
	/// of these is asked for thousands of times a second while a window is being
	/// scrolled, and a dictionary lookup for each would be felt.
	init(scheme: Scheme, isLight: Bool) {
		let palette = scheme.app ?? Scheme.fallback.app!
		self.palette = palette
		self.isLight = isLight
		name = "\(scheme.id)-\(isLight ? "light" : "dark")"

		func colour(_ role: SchemeRole) -> NSColor { .hex(palette.colour(role, isLight: isLight)) }
		windowBackground = colour(.windowBackground)
		sidebarBackground = colour(.sidebarBackground)
		editorBackground = colour(.editorBackground)
		toolbarBackground = colour(.toolbarBackground)
		separator = colour(.separator)

		sidebarText = colour(.sidebarText)
		sidebarHeaderText = colour(.sidebarHeaderText)
		selectionActive = colour(.selectionActive)
		selectionInactive = colour(.selectionInactive)
		excludedDirectoryTint = colour(.excludedDirectoryTint)

		gitAdded = colour(.gitAdded)
		gitModified = colour(.gitModified)
		gitUnversioned = colour(.gitUnversioned)
		gitIgnored = colour(.gitIgnored)
		gitConflict = colour(.gitConflict)

		editorText = colour(.editorText)
		gutterText = colour(.gutterText)
		gutterCurrentLineText = colour(.gutterCurrentLineText)
		currentLineBackground = colour(.currentLineBackground)
		caret = colour(.caret)
		selectionBackground = colour(.selectionBackground)
		selectionBackgroundInactive = colour(.selectionBackgroundInactive)
		searchMatchBackground = colour(.searchMatchBackground)
		searchMatchCurrentBackground = colour(.searchMatchCurrentBackground)
		foldPlaceholderBackground = colour(.foldPlaceholderBackground)
		foldPlaceholderText = colour(.foldPlaceholderText)
		indentGuide = colour(.indentGuide)
	}

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

	/// The two shapes a selection comes in: a band across a row, or a run
	/// behind text. Each has a colour of its own at each end of the rule, and
	/// the reason is the shape rather than the state — see `selection`.
	enum SelectionKind {
		/// A row in a list: the project tree, a results checklist.
		case row
		/// A run of characters in an editor.
		case text
	}

	/// What a selection is drawn in, from whether the view drawing it has the
	/// keyboard.
	///
	/// One function because there is one rule: with the keyboard, the strong
	/// colour; without it, a quiet one, so a window whose keyboard is in the
	/// terminal gives the same answer in every pane at once — *this is where you
	/// were, and it is not where your keys are going.*
	///
	/// **Four colours and not three, because a row and a run of text need
	/// different amounts of lift from the same ground.** A row is a band the
	/// width of the pane with an edge above and below it; a run of code is a
	/// ragged shape mostly covered by the glyphs sitting on it. 0510 gave both
	/// the tree's `selectionInactive`, and the reporter saw the difference
	/// within the day: on `#151210` that band is a handful of points of lift,
	/// which reads on a row and does not read behind code. So the editor has
	/// `selectionBackgroundInactive`, a scheme's own answer to the same question
	/// one shape further on — chosen by eye in each palette, and derived for a
	/// scheme that does not state one.
	///
	/// They are the scheme's own colours rather than the system's inactive
	/// selection, for the reason every other colour here is: a themed panel
	/// beside a system gray is two programs in one window.
	func selection(_ kind: SelectionKind, hasKeyboard: Bool) -> NSColor {
		switch kind {
		case .row:  return hasKeyboard ? selectionActive : selectionInactive
		case .text: return hasKeyboard ? selectionBackground : selectionBackgroundInactive
		}
	}

	/// A system control's size at this zoom, given the size it was designed at.
	///
	/// A bezel is drawn from `controlSize`, never from the font inside it.
	/// Measured on macOS 27: an `NSPopUpButton` is 24 points tall at `.regular`
	/// and 28 at `.large` whether its text is 12 points or 24, and a button with
	/// `.accessoryBarAction` is 20 at `.small` and 28 at `.large`. So a font that
	/// doubles inside a control that was never told to grow gives the fault this
	/// exists to fix: type too large for the box, hard against its edges, with
	/// the artwork — a pop-up's chevron — still drawn for the size AppKit thinks
	/// it is.
	///
	/// **The limit, and it is AppKit's rather than ours:** `.large` is the
	/// biggest artwork there is. It buys about 1.4× and no more; past that a
	/// system control cannot be drawn at the right size, only stretched around
	/// type it was not made for. Anything that has to be right at 2× has to be
	/// drawn rather than bezelled, the way `PillButton` and the language-server
	/// strip are. See backlog 0423, which has the measurements.
	func controlSize(_ design: NSControl.ControlSize = .regular) -> NSControl.ControlSize {
		let steps: [NSControl.ControlSize] = [.mini, .small, .regular, .large]
		let start = steps.firstIndex(of: design) ?? 2
		let up = scale >= 1.5 ? 2 : (scale >= 1.25 ? 1 : 0)
		return steps[min(steps.count - 1, start + up)]
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
	///
	/// The weight asked for is the weight at a design size; what is actually
	/// drawn comes from `opticalWeight(_:at:)`, since the size here has usually
	/// been through the zoom already.
	/// **Kept, because building one is not cheap and this is called while drawing.**
	/// `NSImage(systemSymbolName:)` goes to CoreUI's glyph catalogue, and applying
	/// a configuration rasterises it — `CUINamedVectorGlyph` and its neighbours
	/// were about six per cent of a fire-benchmark profile, all of it the panel's
	/// tab strip drawing the same handful of icons again on every frame while the
	/// terminal below it streamed.
	///
	/// Keyed on everything that changes the picture: the name, the size, the
	/// weight, and the colour — which is baked in, since AppKit only tints a
	/// template image when a *control* draws it, so a hand-drawn symbol has its
	/// colour in the configuration rather than at the call to draw. Two shades of
	/// the same icon are therefore two entries, which is why the colour is in the
	/// key rather than assumed constant.
	///
	/// Not bounded: the set of symbols this interface draws is a fixed list in the
	/// source, times a handful of sizes and shades. It grows to that and stops.
	/// The zoom changes the sizes, and a theme change the shades, so it is emptied
	/// when either moves rather than left to accumulate a second set that will
	/// never be asked for again.
	static func symbol(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSImage? {
		let rgb = color.usingColorSpace(.sRGB) ?? color
		let key = "\(name)|\(size)|\(weight.rawValue)|"
			+ "\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent),\(rgb.alphaComponent)"
		if let kept = symbolCache[key] { return kept }
		guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
		let config = NSImage.SymbolConfiguration(pointSize: size, weight: opticalWeight(weight, at: size))
			.applying(.init(paletteColors: [color]))
		let made = base.withSymbolConfiguration(config) ?? base
		symbolCache[key] = made
		return made
	}

	private nonisolated(unsafe) static var symbolCache: [String: NSImage] = [:]

	/// Throws the drawn symbols away, for a zoom or a theme that changed both the
	/// sizes and the shades they were built for.
	static func forgetSymbols() { symbolCache.removeAll(keepingCapacity: true) }

	/// The largest point size any symbol in this interface is asked for at 1×.
	private static let symbolDesignSize: CGFloat = 16

	/// The weight a symbol is drawn at, given the size it came out at.
	///
	/// A weight is chosen against a size — `.regular` is what looks unremarkable
	/// at 13pt — and SF Symbols keeps the stroke proportional to the point size.
	/// So the zoom multiplies the ink along with everything else, and past about
	/// twenty points the glyphs stop reading as drawings of things and start
	/// reading as shapes: heavy, square-shouldered, the corners gone. The
	/// markdown icon is the one that gives it away. `text.alignleft` is four
	/// lines of text at 13pt and four thick bars at 26, and a folder of `.md`
	/// files at 2× is a column of those down the side of the tree — which is
	/// what was reported as the tree drawing blue dashes instead of guides.
	///
	/// One notch lighter per √2 the size grows past the largest anything is
	/// asked for at 1×, so nothing at a design size moves at all and the whole
	/// interface at 1× is exactly what it was.
	static func opticalWeight(_ weight: NSFont.Weight, at size: CGFloat) -> NSFont.Weight {
		let ladder: [NSFont.Weight] = [
			.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black,
		]
		guard size > symbolDesignSize, let index = ladder.firstIndex(of: weight) else { return weight }
		let steps = Int((log2(size / symbolDesignSize) * 2).rounded(.down))
		return ladder[max(0, index - steps)]
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
		return (NSFont(descriptor: descriptor, size: size) ?? base).honouringLigatureSetting()
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
		(NSFont(name: FontRegistry.bundledMonospaceFamily, size: fontSize)
			?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular))
			.honouringLigatureSetting()
	}

	/// Maps a syntax token to a colour. `HighlightKind` is produced by AbydosKit
	/// from tree-sitter capture names, so the theme never sees grammar details,
	/// and the scheme file gives one colour per kind at each lightness.
	func color(for kind: HighlightKind) -> NSColor {
		.hex(palette.colour(kind, isLight: isLight))
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
	/// 0xRRGGBB, which is how a scheme file states a colour.
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

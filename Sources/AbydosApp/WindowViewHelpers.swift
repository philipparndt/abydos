import AppKit
import AbydosKit

// Three small types the window is built out of. They sat at the bottom of
// `MainWindowController.swift` under a `// MARK: - Small view helpers`, which
// is what a file says when it has become the place things go.

// MARK: - Small view helpers

/// A view that fills itself with a flat colour. Used instead of relying on
/// `NSBox` or vibrancy so the palette matches the theme exactly.
class ColoredView: NSView {
	/// Whether a double-click here means what one in a titlebar means.
	///
	/// The strip across the top of this window is a view of this app's, drawn
	/// where the titlebar would be — `fullSizeContentView` puts the content
	/// there. A view swallows a double-click, so the one gesture every macOS
	/// window has, and which people use without thinking, did nothing at all.
	var actsAsTitlebar = false

	private var color: NSColor

	/// What it is painted with, for anything swapping palettes.
	var colour: NSColor { color }

	/// Where the colour comes from, for views that follow the palette.
	///
	/// The colour itself is copied into a layer, so a theme change has to hand
	/// it over again — and only the view knows which colour it was.
	var colourSource: (() -> NSColor)? {
		didSet { refreshColour() }
	}

	/// Takes the colour again from whatever supplies it.
	func refreshColour() {
		guard let colourSource else { return }
		setColor(colourSource())
	}

	override func mouseDown(with event: NSEvent) {
		guard actsAsTitlebar, event.clickCount == 2 else {
			super.mouseDown(with: event)
			return
		}
		TitlebarDoubleClick.perform(on: window)
	}

	/// Repaints in another colour, for a strip that means something by it.
	func setColor(_ colour: NSColor) {
		guard colour != color else { return }
		color = colour
		layer?.backgroundColor = colour.cgColor
		needsDisplay = true
	}

	init(color: NSColor) {
		self.color = color
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = color.cgColor
	}

	/// Subclasses draw over their subviews, so drawing order matters to them.
	override var wantsDefaultClipping: Bool { true }

	required init?(coder: NSCoder) { fatalError("not used") }

	override func updateLayer() {
		layer?.backgroundColor = color.cgColor
	}
}

/// What a project's tmux session is called.
///
/// The folder's name, with anything tmux would object to replaced: a session
/// name cannot hold a colon or a full stop, and a project called `v1.2` would
/// otherwise fail to attach with a message about a window index.
enum TmuxSessionName {
	static func of(_ root: URL) -> String {
		let name = root.lastPathComponent
		let cleaned = name.map { character -> Character in
			character.isLetter || character.isNumber || character == "-" || character == "_"
				? character
				: "-"
		}
		let text = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
		return text.isEmpty ? "Abydos" : text
	}
}

/// Split view with a 1px themed divider instead of the system's.
final class ThinDividerSplitView: NSSplitView {
	override var dividerColor: NSColor { Theme.current.separator }
	override var dividerThickness: CGFloat { 1 }
}



/// Keeping the tree the width it was dragged to.
///
/// The constraint is what decides the width, and only dragging the divider
/// changes the constraint. Left to itself the split view re-divides the window
/// whenever what is in the editor changes shape — a page of controls, a wide
/// file — and the tree jumps for reasons that have nothing to do with the tree.

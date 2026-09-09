import AppKit
import AbydosKit

// Three small types the window is built out of. They sat at the bottom of
// `MainWindowController.swift` under a `// MARK: - Small view helpers`, which
// is what a file says when it has become the place things go.

// MARK: - Small view helpers

/// A view that fills itself with a flat colour. Used instead of relying on
/// `NSBox` or vibrancy so the palette matches the theme exactly.
class ColoredView: NSView {
	// No mouse handling of its own, and that is deliberate. The strip drawn
	// where the titlebar would be used to answer a double-click with
	// `performZoom`, because the gesture appeared to do nothing there. Every
	// other mouse event was forwarded to AppKit's frame view as usual, and
	// under the SDK marker the installed binary carries AppKit handles the
	// title-bar double-click for such a view itself, on the second release —
	// so each double-click zoomed on the press and un-zoomed on the release,
	// which is the springback that was reported for weeks. Measured with real
	// mouse events and the window server's account of the bounds, 2026-09-09:
	// with this view forwarding everything, AppKit zooms once and it stays,
	// under either SDK marker.

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

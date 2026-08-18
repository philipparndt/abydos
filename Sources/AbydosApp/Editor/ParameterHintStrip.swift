import AppKit
import AbydosKit

/// What is being filled in, said above the line it is being filled into.
///
/// **The moment this exists for is the moment the completion list closes.**
/// Taking `cube` leaves `cube(size = size, center = false);` with `size`
/// selected, and that is when somebody wants to know what `size` is — a single
/// number, or `[x, y, z]`. The list is gone by then, so the panel beside it
/// cannot be the answer.
///
/// Above the caret's line rather than after the end of it. The strip past the
/// end of a line already belongs to `drawInlineDiagnostic`, and a half-typed
/// call is exactly when there is a diagnostic on that line — two dimmed
/// messages fighting for one place would be a worse fault than the one this
/// fixes.
///
/// A non-activating child panel, like `CompletionPopup` and for the same
/// reason: it hangs past the edge of the editor, and it must never take the
/// caret.
final class ParameterHintStrip: NSObject {
	private var window: NSWindow?
	private var label: HintLabel?

	var isVisible: Bool { window?.isVisible ?? false }

	/// Shows one line, with a range of it picked out as the part being typed
	/// into.
	///
	/// The range is in UTF-16 units of `text`, which is what a server's
	/// `labelOffsetSupport` offsets are — sourcekit-lsp answers
	/// `extruded(height: Double, topEdge: EdgeProfile) -> any Geometry3D` and
	/// says the parameter is characters 25 to 45 of it.
	func show(
		_ text: String,
		emphasising range: Range<Int>? = nil,
		above point: NSPoint,
		parent: NSWindow?
	) {
		guard !text.isEmpty, let parent else {
			hide()
			return
		}

		let window = self.window ?? makeWindow()
		self.window = window
		label?.set(text: text, emphasis: range)

		let size = label?.fittingSize ?? .zero
		let screen = parent.screen ?? NSScreen.main
		var origin = NSPoint(x: point.x, y: point.y + 4)
		if let frame = screen?.visibleFrame {
			// Never off the right-hand edge: a hint whose end is past the screen
			// is a hint with the type in it cut off, which is the half worth
			// reading.
			origin.x = min(origin.x, frame.maxX - size.width - 8)
			origin.x = max(origin.x, frame.minX + 8)
		}

		window.setFrame(NSRect(origin: origin, size: size), display: true)
		if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
		window.orderFront(nil)
	}

	func hide() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
	}

	private func makeWindow() -> NSWindow {
		let label = HintLabel()
		self.label = label

		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 200, height: 22),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		window.hasShadow = true
		window.isOpaque = false
		window.backgroundColor = .clear
		window.level = .popUpMenu
		window.contentView = label
		// Nothing to click: it is a sentence, and a click landing on it rather
		// than in the code behind it would be a click somebody has to repeat.
		window.ignoresMouseEvents = true
		return window
	}

	// MARK: - Testing

	var textForTesting: String? { isVisible ? label?.text : nil }
	var emphasisForTesting: Range<Int>? { label?.emphasis }
}

/// The one line, with the active parameter brighter than the rest of it.
private final class HintLabel: NSView {
	private(set) var text: String = ""
	private(set) var emphasis: Range<Int>?

	override var isFlipped: Bool { true }

	func set(text: String, emphasis: Range<Int>?) {
		self.text = text
		self.emphasis = emphasis
		needsDisplay = true
	}

	private var attributed: NSAttributedString {
		let dim = NSMutableAttributedString(string: text, attributes: [
			.font: Theme.current.editorFont,
			.foregroundColor: Theme.current.gitIgnored,
		])
		guard let emphasis else { return dim }
		let full = NSRange(location: 0, length: (text as NSString).length)
		let range = NSRange(
			location: max(0, min(emphasis.lowerBound, full.length)),
			length: max(0, min(emphasis.count, full.length - min(emphasis.lowerBound, full.length)))
		)
		guard range.length > 0 else { return dim }
		dim.addAttribute(.foregroundColor, value: Theme.current.sidebarText, range: range)
		return dim
	}

	override var fittingSize: NSSize {
		let size = attributed.size()
		return NSSize(width: ceil(size.width) + 16, height: ceil(size.height) + 8)
	}

	override func draw(_ dirtyRect: NSRect) {
		let background = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
		Theme.current.sidebarBackground.setFill()
		background.fill()
		Theme.current.separator.setStroke()
		background.stroke()

		let string = attributed
		string.draw(at: NSPoint(x: 8, y: bounds.midY - string.size().height / 2))
	}
}

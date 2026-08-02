import AppKit
import IdeaiKit

/// What the last run did, in the middle of the titlebar.
///
/// Beside the buttons it pushed them about: a message that grows from
/// "Running" to "Failed — exit code 1" moved the thing you were about to press.
/// In the middle it has room to grow into, and the buttons stay where they
/// were.
final class RunStatusView: NSView {
	/// Asked to forget the message.
	var onClear: (() -> Void)?

	private var text = ""
	private var failed = false
	private var isHoveringClear = false
	private var trackingArea: NSTrackingArea?

	private static var closeSize: CGFloat { Theme.current.scaled(13) }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var intrinsicContentSize: NSSize {
		guard !text.isEmpty else { return NSSize(width: 1, height: Theme.current.scaled(30)) }
		let width = ceil(attributed.size().width) + Self.closeSize + Theme.current.scaled(14)
		return NSSize(width: width, height: Theme.current.scaled(30))
	}

	func setStatus(_ text: String, failed: Bool) {
		guard text != self.text || failed != self.failed else { return }
		self.text = text
		self.failed = failed
		invalidateIntrinsicContentSize()
		needsDisplay = true
		toolTip = text.isEmpty ? nil : text
	}

	var isEmpty: Bool { text.isEmpty }

	// MARK: - Interaction

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let inside = closeRect.contains(convert(event.locationInWindow, from: nil))
		guard inside != isHoveringClear else { return }
		isHoveringClear = inside
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent) {
		guard isHoveringClear else { return }
		isHoveringClear = false
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		guard !text.isEmpty else { return }
		// Anywhere in it, not only the cross: the whole thing is one message
		// and dismissing it is the only thing to do with it.
		onClear?()
	}

	private var closeRect: NSRect {
		let size = Self.closeSize
		return NSRect(
			x: bounds.maxX - size - Theme.current.scaled(4),
			y: bounds.midY - size / 2,
			width: size,
			height: size
		)
	}

	// MARK: - Drawing

	private var attributed: NSAttributedString {
		NSAttributedString(string: text, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: failed ? NSColor.hex(0xE05252) : Theme.current.sidebarText,
		])
	}

	override func draw(_ dirtyRect: NSRect) {
		guard !text.isEmpty else { return }

		let label = attributed
		let size = label.size()
		label.draw(in: NSRect(
			x: Theme.current.scaled(6),
			y: bounds.midY - size.height / 2,
			width: max(0, bounds.width - Self.closeSize - Theme.current.scaled(12)),
			height: size.height
		))

		// A cross that only darkens under the pointer: it is a way out of a
		// message, not a control anybody is looking for.
		let cross = closeRect
		if isHoveringClear {
			NSColor.black.withAlphaComponent(0.12).setFill()
			NSBezierPath(ovalIn: cross).fill()
		}
		Theme.symbol(
			"xmark",
			size: 8 * Theme.current.scale,
			color: Theme.current.gitIgnored.withAlphaComponent(isHoveringClear ? 1 : 0.7)
		)?.drawFitted(in: cross.insetBy(dx: Theme.current.scaled(3), dy: Theme.current.scaled(3)))
	}
}

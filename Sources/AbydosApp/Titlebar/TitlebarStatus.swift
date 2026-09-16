import AppKit

/// What the last run said, drawn on the title bar rather than in the toolbar.
///
/// It used to be part of the run control, which reserved room for it beside
/// the scheme well so that a message arriving would not move the buttons. That
/// room was dead to the title bar: a toolbar refuses the double-click that
/// zooms the window anywhere one of its items sits, whatever the item does
/// with the events — measured 2026-09-16 with two builds side by side, one
/// with the control shrunk to its buttons and one forwarding every event it
/// did not use; only the first zoomed. So the message lives here, on the
/// backdrop the content view paints under the titlebar, just left of the
/// buttons, in the room a double-click already zoomed from.
///
/// It gives the room back on purpose. `hitTest` answers only for the cross
/// that forgets the message; everywhere else the click falls through to the
/// backdrop, so a double-click on the text zooms the window and leaves the
/// text where it was. The hover and the tip do not need the hit: a tracking
/// area is a rectangle the window watches.
final class TitlebarStatus: NSView {
	/// Room for the message, when there is room: the same width the run
	/// control used to reserve. It is a ceiling, not a demand, and the room
	/// between the pills and the buttons decides.
	static var preferredWidth: CGFloat { Theme.current.scaled(230) }

	/// Pressed the cross: the message is to be forgotten.
	var onClear: (() -> Void)?

	private(set) var text = ""
	private var failed = false

	var hasMessage: Bool { !text.isEmpty }

	enum Part { case message, clear }

	private lazy var tips = TipHost<Part>(
		controls: { [weak self] in self?.partRects() ?? [] },
		words: { [weak self] part in
			switch part {
			case .message: return StyledTip.Tip(title: self?.text ?? "")
			case .clear: return StyledTip.Tip(title: "Forget this message")
			}
		}
	)
	private var trackingArea: NSTrackingArea?

	func set(_ text: String, failed: Bool) {
		guard text != self.text || failed != self.failed else { return }
		self.text = text
		self.failed = failed
		needsDisplay = true
	}

	/// The cross at the trailing end, sized as the run control drew it.
	var clearRect: NSRect {
		let size = Theme.current.scaled(14)
		return NSRect(x: bounds.maxX - size, y: bounds.midY - size / 2, width: size, height: size)
	}

	private func partRects() -> [(Part, NSRect)] {
		guard hasMessage else { return [] }
		return [(.clear, clearRect.insetBy(dx: -4, dy: -4)), (.message, bounds)]
	}

	/// Only the cross is this view's to catch. The text is title bar.
	override func hitTest(_ point: NSPoint) -> NSView? {
		guard hasMessage, let hit = super.hitTest(point) else { return nil }
		return clearRect.insetBy(dx: -4, dy: -4).contains(convert(point, from: superview)) ? hit : nil
	}

	override func mouseDown(with event: NSEvent) {
		StyledTip.shared.hide()
		if hasMessage, clearRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) {
			onClear?()
		} else {
			super.mouseDown(with: event)
		}
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		if tips.update(at: convert(event.locationInWindow, from: nil), in: self) { needsDisplay = true }
	}

	override func mouseExited(with event: NSEvent) {
		if tips.clear() { needsDisplay = true }
	}

	/// Puts the pointer on a named part, for a driven run.
	func hoverPartForTesting(_ name: String) -> String {
		tips.hoverForTesting(name, ["status": .message, "clear": .clear], in: self)
	}

	override func draw(_ dirtyRect: NSRect) {
		guard hasMessage else { return }
		if tips.hovered == .clear {
			HoverGround.draw(around: clearRect, ink: Theme.current.sidebarText)
		}
		// One line, ending in an ellipsis when there is more of it: this is a
		// strip in a titlebar, and the whole message is in the tip, the toast
		// and the launch log.
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		paragraph.alignment = .right
		let message = NSAttributedString(string: text, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: failed ? NSColor.hex(0xE05252) : Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
		let size = message.size()
		message.draw(in: NSRect(
			x: 0,
			y: bounds.midY - size.height / 2,
			width: max(0, bounds.width - Theme.current.scaled(18)),
			height: size.height
		))
		Theme.symbol(
			"xmark", size: 8 * Theme.current.scale, color: Theme.current.gitIgnored.withAlphaComponent(0.8)
		)?.drawFitted(in: clearRect.insetBy(dx: Theme.current.scaled(3), dy: Theme.current.scaled(3)))
	}
}

import AppKit
import AbydosKit

/// Flat themed button; `NSButton`'s stock appearance does not match this window.
///
/// **Shared rather than copied.** It was `private` in `FileNoticeView.swift`
/// while the editor's notice about a file it cannot show was the only view of
/// this kind. The backlog pane's "this project has no record of work" is the
/// second, and it is the same sentence in a different pane — so it is drawn the
/// same way, by this. Two of these would be one appearance today and two a week
/// after somebody changes a corner radius.
///
/// A disabled one is drawn dimmed and does not light up under the pointer,
/// which is what an offer whose tool is not installed looks like: still there,
/// still saying what it would do, and plainly not pressable.
final class NoticeButton: NSButton {
	var onClick: (() -> Void)?

	/// The words on it. Readable because a driver reports what a view is
	/// offering, and `NSButton.title` is deliberately empty here — this button
	/// draws its own label beside its own symbol.
	let caption: String
	private let symbol: String
	private var isHovered = false {
		didSet { needsDisplay = true }
	}
	private var trackingArea: NSTrackingArea?

	init(title: String, symbol: String) {
		self.caption = title
		self.symbol = symbol
		super.init(frame: .zero)
		isBordered = false
		title.isEmpty ? () : (self.title = "")
		translatesAutoresizingMaskIntoConstraints = false
		heightAnchor.constraint(equalToConstant: 30).isActive = true
		widthAnchor.constraint(equalToConstant: measuredWidth()).isActive = true
		target = self
		action = #selector(clicked)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	/// Redrawn when it is turned off, which `NSButton` does not do for a button
	/// that draws itself.
	override var isEnabled: Bool {
		didSet { needsDisplay = true }
	}

	private func measuredWidth() -> CGFloat {
		let font = NSFont.systemFont(ofSize: 12.5)
		let width = (caption as NSString).size(withAttributes: [.font: font]).width
		return ceil(width) + 24 + 20
	}

	@objc private func clicked() { onClick?() }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) { isHovered = isEnabled }
	override func mouseExited(with event: NSEvent) { isHovered = false }

	override func draw(_ dirtyRect: NSRect) {
		let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
		let fill: CGFloat = isEnabled ? (isHovered ? 0.10 : 0.05) : 0.02
		NSColor.white.withAlphaComponent(fill).setFill()
		path.fill()
		Theme.current.separator.setStroke()
		path.lineWidth = 1
		path.stroke()

		// Dimmed rather than greyed to a colour of its own: the palette already
		// has the colour for text that is present and not available, and it is
		// the one the navigator uses for an ignored file.
		let symbolColour = isEnabled ? Theme.current.sidebarText : Theme.current.gitIgnored
		let textColour = isEnabled ? Theme.current.sidebarHeaderText : Theme.current.gitIgnored

		var x: CGFloat = 10
		if let icon = Theme.symbol(symbol, size: 12, color: symbolColour) {
			icon.drawFitted(in: NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14))
		}
		x += 20

		let attributed = NSAttributedString(string: caption, attributes: [
			.font: NSFont.systemFont(ofSize: 12.5),
			.foregroundColor: textColour,
		])
		attributed.draw(at: NSPoint(x: x, y: bounds.midY - attributed.size().height / 2))
	}
}

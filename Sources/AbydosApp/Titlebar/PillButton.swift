import AppKit

/// A titlebar control a menu can be anchored to, kept lit while that menu is up.
///
/// The pills and the capsule are drawn differently and share no code, but a
/// menu does not care which it was opened from — only that it can say when it
/// closed again.
protocol TitlebarMenuAnchor: AnyObject {
	var isMenuOpen: Bool { get set }
}

/// Base class for the titlebar pills: a rounded hit area that highlights on
/// hover and stays highlighted while its menu is open.
class PillButton: NSView, TitlebarMenuAnchor {
	var onClick: (() -> Void)?

	/// Kept lit while the popover is open so the pill reads as the menu's anchor.
	var isMenuOpen = false {
		didSet { needsDisplay = true }
	}

	private var isHovered = false {
		didSet { needsDisplay = true }
	}
	private var isPressed = false {
		didSet { needsDisplay = true }
	}

	private var trackingArea: NSTrackingArea?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	// MARK: - Hover tracking

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeInActiveApp],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) { isHovered = true }
	override func mouseExited(with event: NSEvent) { isHovered = false }

	override func mouseDown(with event: NSEvent) {
		isPressed = true
	}

	override func mouseUp(with event: NSEvent) {
		isPressed = false
		// Only fire when released inside, matching standard button behaviour.
		if bounds.contains(convert(event.locationInWindow, from: nil)) {
			onClick?()
		}
	}

	// MARK: - Drawing

	/// How far the pill's own shape sits inside the space it is given.
	///
	/// The toolbar draws a rounded background of its own behind each item, and
	/// a highlight that runs to the very edge of it reads as two frames drawn
	/// on top of each other rather than as one pill being pointed at.
	static var inset: CGFloat { Theme.current.scaled(4) }

	override func draw(_ dirtyRect: NSRect) {
		let radius: CGFloat = 7
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(dx: Self.inset, dy: Self.inset),
			xRadius: radius,
			yRadius: radius
		)

		// Darkening rather than lightening: the toolbar draws its items on a
		// pale background of its own, and white over white says nothing.
		if isMenuOpen || isPressed {
			NSColor.black.withAlphaComponent(0.16).setFill()
			path.fill()
			NSColor.black.withAlphaComponent(0.22).setStroke()
			path.lineWidth = 1
			path.stroke()
		} else if isHovered {
			NSColor.black.withAlphaComponent(0.08).setFill()
			path.fill()
		}

		drawContent(in: bounds)
	}

	/// Subclass hook for the pill's contents.
	func drawContent(in rect: NSRect) {}

	// MARK: - Shared drawing helpers

	static var labelFont: NSFont { Theme.current.uiFont(13, weight: .medium) }

	func drawChevron(at point: NSPoint, color: NSColor) {
		let path = NSBezierPath()
		path.move(to: NSPoint(x: point.x, y: point.y - 2))
		path.line(to: NSPoint(x: point.x + 3.5, y: point.y + 2))
		path.line(to: NSPoint(x: point.x + 7, y: point.y - 2))
		path.lineWidth = 1.3
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		color.setStroke()
		path.stroke()
	}
}

/// The part of the project being worked on.
///
/// Beside the project rather than instead of it: the project is what the tree
/// shows and what somebody came here for, and the subproject is which corner
/// of it the run button, git and the language server are pointed at. The cross
/// gives the whole project back.
final class SubprojectPillButton: PillButton {
	/// Asked to go back to the whole project.
	var onLeave: (() -> Void)?

	private var path: String?

	private static var iconSize: CGFloat { Theme.current.scaled(13) }
	private static var horizontalPadding: CGFloat { Theme.current.scaled(7) }
	private static var gap: CGFloat { Theme.current.scaled(6) }
	private static var crossSize: CGFloat { Theme.current.scaled(12) }

	var hasSubproject: Bool { path != nil }

	func setSubproject(_ path: String?) {
		self.path = path
		isHidden = (path == nil)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override var intrinsicContentSize: NSSize {
		// A toolbar measures a hidden view too, and warns about a zero
		// dimension: a sliver rather than nothing.
		guard let path else { return NSSize(width: 1, height: Theme.current.scaled(28)) }
		let textWidth = (path as NSString).size(withAttributes: [.font: PillButton.labelFont]).width
		return NSSize(
			width: PillButton.inset * 2 + Self.horizontalPadding * 2 + Self.iconSize
				+ Self.gap + ceil(textWidth) + Self.gap + Self.crossSize,
			height: Theme.current.scaled(30)
		)
	}

	/// Where the cross is, so a click there leaves rather than opens the menu.
	private var crossRect: NSRect {
		NSRect(
			x: bounds.maxX - PillButton.inset - Self.horizontalPadding - Self.crossSize,
			y: bounds.midY - Self.crossSize / 2,
			width: Self.crossSize,
			height: Self.crossSize
		)
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard !crossRect.insetBy(dx: -4, dy: -4).contains(point) else {
			onLeave?()
			return
		}
		super.mouseDown(with: event)
	}

	override func drawContent(in rect: NSRect) {
		guard let path else { return }
		var x = Self.horizontalPadding + PillButton.inset

		let tint = Theme.current.sidebarText
		if let icon = Theme.symbol(
			"square.split.bottomrightquarter", size: 11 * Theme.current.scale, color: tint
		) ?? Theme.symbol("square.on.square", size: 11 * Theme.current.scale, color: tint) {
			icon.drawFitted(in: NSRect(
				x: x, y: rect.midY - Self.iconSize / 2,
				width: Self.iconSize, height: Self.iconSize
			))
			x += Self.iconSize + Self.gap
		}

		let attributed = NSAttributedString(string: path, attributes: [
			.font: PillButton.labelFont,
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let size = attributed.size()
		attributed.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))

		Theme.symbol("xmark", size: 8 * Theme.current.scale, color: tint.withAlphaComponent(0.75))?
			.drawFitted(in: crossRect.insetBy(dx: Theme.current.scaled(2), dy: Theme.current.scaled(2)))
	}
}

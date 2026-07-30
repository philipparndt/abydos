import AppKit

/// Base class for the titlebar pills: a rounded hit area that highlights on
/// hover and stays highlighted while its menu is open.
class PillButton: NSView {
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

	override func draw(_ dirtyRect: NSRect) {
		let radius: CGFloat = 6
		let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: radius, yRadius: radius)

		if isMenuOpen || isPressed {
			NSColor.white.withAlphaComponent(0.14).setFill()
			path.fill()
			Theme.current.separator.setStroke()
			path.lineWidth = 1
			path.stroke()
		} else if isHovered {
			NSColor.white.withAlphaComponent(0.08).setFill()
			path.fill()
		}

		drawContent(in: bounds)
	}

	/// Subclass hook for the pill's contents.
	func drawContent(in rect: NSRect) {}

	// MARK: - Shared drawing helpers

	static let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)

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

/// Titlebar pill showing the project badge, name, and a disclosure chevron.
final class ProjectPillButton: PillButton {
	private var name: String = ""
	private var badge: NSImage?

	private static let badgeSize: CGFloat = 18
	private static let horizontalPadding: CGFloat = 8
	private static let gap: CGFloat = 7

	func configure(name: String, colorIndex: Int?) {
		self.name = name
		self.badge = ProjectBadge.image(for: name, colorIndex: colorIndex, size: Self.badgeSize)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override var intrinsicContentSize: NSSize {
		let textWidth = (name as NSString).size(withAttributes: [.font: Self.labelFont]).width
		return NSSize(
			width: Self.horizontalPadding * 2 + Self.badgeSize + Self.gap + ceil(textWidth) + Self.gap + 9,
			height: 28
		)
	}

	override func drawContent(in rect: NSRect) {
		var x = Self.horizontalPadding

		if let badge {
			badge.draw(in: NSRect(
				x: x,
				y: rect.midY - Self.badgeSize / 2,
				width: Self.badgeSize,
				height: Self.badgeSize
			))
			x += Self.badgeSize + Self.gap
		}

		let attributes: [NSAttributedString.Key: Any] = [
			.font: Self.labelFont,
			.foregroundColor: Theme.current.sidebarHeaderText,
		]
		let attributed = NSAttributedString(string: name, attributes: attributes)
		let textSize = attributed.size()
		attributed.draw(at: NSPoint(x: x, y: rect.midY - textSize.height / 2))
		x += ceil(textSize.width) + Self.gap

		drawChevron(
			at: NSPoint(x: x, y: rect.midY),
			color: Theme.current.sidebarText.withAlphaComponent(0.8)
		)
	}
}

/// Titlebar pill showing the current git branch.
final class BranchPillButton: PillButton {
	private var branch: String?

	private static let iconSize: CGFloat = 14
	private static let horizontalPadding: CGFloat = 7
	private static let gap: CGFloat = 6

	func setBranch(_ branch: String?) {
		self.branch = branch
		// A directory that is not a work tree has no branch to show, so the pill
		// disappears rather than showing an empty state.
		isHidden = (branch == nil)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override var intrinsicContentSize: NSSize {
		// NSToolbar measures the view even while hidden and warns about a zero
		// dimension, so report a sliver rather than nothing when there is no branch.
		guard let branch else { return NSSize(width: 1, height: 28) }
		let textWidth = (branch as NSString).size(withAttributes: [.font: PillButton.labelFont]).width
		return NSSize(
			width: Self.horizontalPadding * 2 + Self.iconSize + Self.gap + ceil(textWidth) + Self.gap + 9,
			height: 28
		)
	}

	override func drawContent(in rect: NSRect) {
		guard let branch else { return }
		var x = Self.horizontalPadding

		let tint = Theme.current.sidebarText
		// Colour baked into the symbol configuration — see Theme.symbol.
		if let rendered = Theme.symbol("arrow.trianglehead.branch", size: 12, color: tint)
			?? Theme.symbol("arrow.triangle.branch", size: 12, color: tint) {
			let iconRect = NSRect(
				x: x,
				y: rect.midY - Self.iconSize / 2,
				width: Self.iconSize,
				height: Self.iconSize
			)
			// respectFlipped: this view is flipped; without it the glyph mirrors.
			rendered.draw(in: iconRect, from: .zero, operation: .sourceOver,
			              fraction: 1.0, respectFlipped: true, hints: nil)
			x += Self.iconSize + Self.gap
		}

		let attributes: [NSAttributedString.Key: Any] = [
			.font: PillButton.labelFont,
			.foregroundColor: Theme.current.sidebarHeaderText,
		]
		let attributed = NSAttributedString(string: branch, attributes: attributes)
		let textSize = attributed.size()
		attributed.draw(at: NSPoint(x: x, y: rect.midY - textSize.height / 2))
		x += ceil(textSize.width) + Self.gap

		drawChevron(at: NSPoint(x: x, y: rect.midY), color: tint.withAlphaComponent(0.8))
	}
}

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

/// The devcontainer this project is worked on inside, or the one it has and is
/// not using.
///
/// **Two states, and 0438's third fault is why there are two.** 0433 built this
/// to say *running*: a project whose container was declined had no pill at all,
/// which meant that the gesture most in need of undoing was the one that removed
/// its own undo — the way back lives in this menu. From the window it read as
/// gone for good, which is exactly how it was reported.
///
/// So a project that has a `devcontainer.json` and is not being worked on inside
/// it keeps its pill, dimmed, without the `⬢` the terminal tab wears. The
/// hexagon is the mark of being *in* the container and the pill must never wear
/// it while nothing of the project's is; the dimming is the whole of how loud
/// this is allowed to be, because somebody who chose to work on this machine
/// chose it and does not need reminding. What state is in force is in the tool
/// tip and at the top of the menu, for whoever goes looking.
///
/// A chevron rather than the subproject pill's cross, and the difference is on
/// purpose: the cross gives the whole project back and costs nothing, whereas
/// everything this pill offers changes which toolchain the code is checked
/// against. That is worth a menu somebody read rather than a small target
/// beside a name.
///
/// **It does not say the container's name, and 0444's part 3 is that decision
/// being reversed.** 0433 gave it `containerTabTitle` so that the pill, the tab
/// in the same container and the menu item that opens one could not drift apart,
/// and the naming argument was that "a window scoped to one subproject of ten
/// that each have a devcontainer cannot say which one it means by saying
/// 'container'". That argument is sound and it is about **the menu item that
/// opens one of several**, where the name is the only thing telling two entries
/// apart. It is much weaker here: this pill has exactly one answer at a time, the
/// window already says which project and which subproject it is showing, and a
/// devcontainer's `name` is a whole sentence — "Python, with its language server
/// in the container" beside a project, a branch and a subproject was most of the
/// titlebar, measured on the example project the whole feature was reported
/// against.
///
/// So what is left is the `⬢`: this window is working inside a container. The
/// name is in the tool tip, and in the menu, which lists every container the
/// project offers with the one in use marked — it has a home now, which is the
/// other half of why this is no longer a loss. The single source is untouched:
/// the name still comes from `MainWindowController.containerName`, and so does
/// the mark. What changed is what the pill shows, not where it learns it from.
final class DevContainerPillButton: PillButton {
	/// The very short thing it shows while the container is in use — the `⬢` the
	/// terminal tab wears — or nil when there is no container to show at all.
	private var mark: String?
	private var inUse = true

	private static var iconSize: CGFloat { Theme.current.scaled(13) }
	private static var horizontalPadding: CGFloat { Theme.current.scaled(7) }
	private static var gap: CGFloat { Theme.current.scaled(6) }
	private static var chevronWidth: CGFloat { Theme.current.scaled(7) }

	var hasContainer: Bool { mark != nil }
	/// Whether the container it stands for is the one this project's tools are in.
	var isInUse: Bool { inUse }

	/// Shows the pill for a container, or takes it away when given nil.
	///
	/// - Parameters:
	///   - mark: the two characters at most that it shows — the `⬢` the terminal
	///     tab wears, from `MainWindowController.containerMark`, so the pill and
	///     the tab in the same container cannot come to disagree about it.
	///   - inUse: whether this project's tools are in there. The mark is drawn
	///     only then: the hexagon means being *inside*, and a pill for a container
	///     that is merely available must not wear it (0438).
	func setContainer(_ mark: String?, inUse: Bool = true) {
		self.mark = mark
		self.inUse = inUse
		isHidden = (mark == nil)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// What is drawn beside the icon, which is the mark or nothing.
	private var label: String? { inUse ? mark : nil }

	override var intrinsicContentSize: NSSize {
		// A toolbar measures a hidden view too, and warns about a zero dimension:
		// a sliver rather than nothing.
		guard mark != nil else { return NSSize(width: 1, height: Theme.current.scaled(28)) }
		let textWidth = label.map {
			ceil(($0 as NSString).size(withAttributes: [.font: PillButton.labelFont]).width)
				+ Self.gap
		} ?? 0
		return NSSize(
			width: PillButton.inset * 2 + Self.horizontalPadding * 2 + Self.iconSize
				+ Self.gap + textWidth + Self.chevronWidth,
			height: Theme.current.scaled(30)
		)
	}

	override func drawContent(in rect: NSRect) {
		guard mark != nil else { return }
		var x = Self.horizontalPadding + PillButton.inset

		// Dimmed rather than coloured. A warning colour would be the app arguing
		// with a decision somebody made on purpose; the same grey the tree gives
		// an ignored file says "there, and not in play" without saying anything
		// about whether that was wise.
		let tint = inUse ? Theme.current.sidebarText : Theme.current.gitIgnored
		if let icon = Theme.symbol("shippingbox", size: 11 * Theme.current.scale, color: tint) {
			icon.drawFitted(in: NSRect(
				x: x, y: rect.midY - Self.iconSize / 2,
				width: Self.iconSize, height: Self.iconSize
			))
			x += Self.iconSize + Self.gap
		}

		if let label {
			let attributed = NSAttributedString(string: label, attributes: [
				.font: PillButton.labelFont,
				.foregroundColor: Theme.current.sidebarHeaderText,
			])
			let size = attributed.size()
			attributed.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
			x += ceil(size.width) + Self.gap
		}

		drawChevron(at: NSPoint(x: x, y: rect.midY), color: tint)
	}
}

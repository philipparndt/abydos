import AppKit

/// The field in the middle of the titlebar: which project on the left, which
/// branch on the right, and the shortcut that turns the whole thing into a
/// search.
///
/// One control rather than two pills, because the two questions it answers —
/// where am I, and where do I want to go — are the same question at different
/// moments. It stays two hit targets, though: the halves light separately and
/// keep the menus the pills had, so nothing that worked by pointing at it
/// stopped working.
final class TitlebarCapsule: NSView, TitlebarMenuAnchor {
	enum Half { case project, branch }

	/// Asked to show the project switcher.
	var onProject: (() -> Void)?
	/// Asked to show the branch menu.
	var onBranch: (() -> Void)?

	/// Which half the menu about to open belongs to.
	///
	/// Set by whoever opens it, a moment before `isMenuOpen`: the popover and
	/// the menu both report only that they are up, and the capsule has two
	/// places that could be lit for them.
	var menuHalf: Half = .project

	private var openHalf: Half?
	private var hoveredHalf: Half?
	private var pressedHalf: Half?

	private var name = ""
	private var worktree: String?
	private var branch: String?

	private var trackingArea: NSTrackingArea?

	// MARK: - Metrics

	private static var padding: CGFloat { Theme.current.scaled(11) }
	private static var gap: CGFloat { Theme.current.scaled(7) }
	private static var chevronWidth: CGFloat { Theme.current.scaled(9) }
	private static var minimumWidth: CGFloat { Theme.current.scaled(300) }

	/// How far the drawn shape sits inside the frame the toolbar hands over.
	///
	/// Small, because that frame is all there is: a toolbar clamps its items to
	/// the row's height whatever they ask for, so asking to be taller does
	/// nothing and the only way to a taller capsule is to stop giving the height
	/// away. Not zero — a hairline of air keeps the shape from touching the
	/// capsule macOS paints behind the item.
	private static var inset: CGFloat { Theme.current.scaled(1) }

	private static var chipPadding: CGFloat { Theme.current.scaled(6) }
	private static var chipFont: NSFont { Theme.current.uiFont(11, weight: .medium) }

	private static var labelFont: NSFont { Theme.current.uiFont(13, weight: .medium) }
	private static var nameFont: NSFont { Theme.current.uiFont(13, weight: .semibold) }
	private static var hintFont: NSFont { Theme.current.uiFont(10.5, weight: .medium) }

	/// Matches the File menu's Go to Project…, which is shifted because plain
	/// ⌘K clears the terminal.
	private static let hint = "⇧⌘K"

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	// MARK: - Content

	func setProject(name: String) {
		self.name = name
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// Which linked worktree this window is looking at, or nil for the main one.
	///
	/// The name stays the repository's — a worktree of ideai is still ideai, and
	/// a titlebar that said `titlebar-capsule` would be naming a directory
	/// rather than the thing being worked on. The chip after it says which
	/// checkout, in the same place and shape a subproject would qualify it.
	func setWorktree(_ worktree: String?) {
		self.worktree = worktree
		toolTip = worktree.map { "Worktree \($0) of \(name)" }
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	func setBranch(_ branch: String?) {
		self.branch = branch
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// Whether the right half has anything to say. A directory that is not a
	/// work tree has no branch, and the divider goes with it.
	var hasBranch: Bool { branch != nil }

	var isMenuOpen: Bool {
		get { openHalf != nil }
		set {
			openHalf = newValue ? menuHalf : nil
			needsDisplay = true
		}
	}

	// MARK: - Layout

	private func width(of text: String, font: NSFont) -> CGFloat {
		ceil((text as NSString).size(withAttributes: [.font: font]).width)
	}

	/// Room for the branch, its chevron and the shortcut, measured from the
	/// right edge.
	private var branchWidth: CGFloat {
		let hintWidth = width(of: Self.hint, font: Self.hintFont)
		guard let branch else { return Self.padding + hintWidth + Self.padding }
		return Self.padding
			+ width(of: branch, font: Self.labelFont)
			+ Self.gap + Self.chevronWidth
			+ Self.gap + hintWidth
			+ Self.padding
	}

	private var chipWidth: CGFloat {
		guard let worktree else { return 0 }
		return Self.gap + Self.chipPadding * 2 + width(of: worktree, font: Self.chipFont)
	}

	private var projectWidth: CGFloat {
		Self.padding + width(of: name, font: Self.nameFont) + chipWidth
			+ Self.gap + Self.chevronWidth + Self.padding
	}

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: Self.inset * 2 + max(Self.minimumWidth, projectWidth + branchWidth),
			height: Theme.current.scaled(30)
		)
	}

	/// The capsule's own shape, inside the space the toolbar gives it.
	private var shapeRect: NSRect {
		bounds.insetBy(dx: Self.inset, dy: Self.inset)
	}

	/// Where the project half ends and the branch half begins.
	private var divider: CGFloat {
		shapeRect.maxX - branchWidth
	}

	/// The project half, for anchoring its popover under it.
	var projectRect: NSRect {
		NSRect(x: shapeRect.minX, y: shapeRect.minY, width: divider - shapeRect.minX, height: shapeRect.height)
	}

	/// The branch half, likewise.
	var branchRect: NSRect {
		NSRect(x: divider, y: shapeRect.minY, width: shapeRect.maxX - divider, height: shapeRect.height)
	}

	private func half(at point: NSPoint) -> Half? {
		guard shapeRect.contains(point) else { return nil }
		// With no branch there is nothing on the right to point at, so the whole
		// capsule belongs to the project.
		guard hasBranch else { return .project }
		return point.x < divider ? .project : .branch
	}

	// MARK: - Pointing

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		// .mouseMoved as well as enter and exit: which half is being pointed at
		// changes without the pointer ever leaving the view.
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	private func setHovered(_ half: Half?) {
		guard hoveredHalf != half else { return }
		hoveredHalf = half
		needsDisplay = true
	}

	override func mouseEntered(with event: NSEvent) {
		setHovered(half(at: convert(event.locationInWindow, from: nil)))
	}

	override func mouseMoved(with event: NSEvent) {
		setHovered(half(at: convert(event.locationInWindow, from: nil)))
	}

	override func mouseExited(with event: NSEvent) {
		setHovered(nil)
	}

	override func mouseDown(with event: NSEvent) {
		pressedHalf = half(at: convert(event.locationInWindow, from: nil))
		needsDisplay = true
	}

	override func mouseUp(with event: NSEvent) {
		let released = half(at: convert(event.locationInWindow, from: nil))
		let pressed = pressedHalf
		pressedHalf = nil
		needsDisplay = true

		// Only when it goes down and comes up on the same half, which is what
		// every other button on the system does.
		guard let released, released == pressed else { return }
		switch released {
		case .project: onProject?()
		case .branch: onBranch?()
		}
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		let radius = Theme.current.scaled(8)
		let shape = shapeRect
		let path = NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius)

		// A raised field on the strip: the toolbar's own colour against the
		// window's, which is the same pairing the sidebar uses against the editor.
		Theme.current.toolbarBackground.setFill()
		path.fill()
		Theme.current.separator.setStroke()
		path.lineWidth = 1
		path.stroke()

		// Darkening rather than lightening, for the reason PillButton gives: on
		// macOS the toolbar paints a pale capsule behind its items, and white
		// over white says nothing.
		if let lit = openHalf ?? pressedHalf ?? hoveredHalf {
			let strong = (openHalf != nil) || (pressedHalf != nil)
			NSGraphicsContext.saveGraphicsState()
			path.setClip()
			NSColor.black.withAlphaComponent(strong ? 0.16 : 0.08).setFill()
			(lit == .project ? projectRect : branchRect).fill()
			NSGraphicsContext.restoreGraphicsState()
		}

		drawProject(in: shape)
		if hasBranch { drawDivider(in: shape) }
		drawBranch(in: shape)
	}

	private func drawProject(in shape: NSRect) {
		let attributed = NSAttributedString(string: name, attributes: [
			.font: Self.nameFont,
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let size = attributed.size()
		let x = shape.minX + Self.padding
		attributed.draw(at: NSPoint(x: x, y: shape.midY - size.height / 2))

		var end = x + ceil(size.width)
		if let worktree {
			end = drawChip(worktree, after: end, in: shape)
		}

		// The chevron is drawn only for the half being pointed at: at rest the
		// capsule is two words and a hint.
		if hoveredHalf == .project || openHalf == .project {
			drawChevron(
				at: NSPoint(x: end + Self.gap, y: shape.midY),
				color: Theme.current.sidebarText.withAlphaComponent(0.8)
			)
		}
	}

	/// The worktree's own folder name, in a chip after the project's.
	///
	/// - Returns: where it ends, so what follows can be placed after it.
	private func drawChip(_ text: String, after x: CGFloat, in shape: NSRect) -> CGFloat {
		let attributed = NSAttributedString(string: text, attributes: [
			.font: Self.chipFont,
			.foregroundColor: Theme.current.sidebarText,
		])
		let size = attributed.size()
		let height = Theme.current.scaled(17)
		let rect = NSRect(
			x: x + Self.gap,
			y: shape.midY - height / 2,
			width: Self.chipPadding * 2 + ceil(size.width),
			height: height
		)

		let radius = Theme.current.scaled(4)
		Theme.current.selectionInactive.setFill()
		NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
		attributed.draw(at: NSPoint(
			x: rect.minX + Self.chipPadding,
			y: rect.midY - size.height / 2
		))
		return rect.maxX
	}

	private func drawDivider(in shape: NSRect) {
		let height = Theme.current.scaled(16)
		Theme.current.separator.setFill()
		NSRect(
			x: divider,
			y: shape.midY - height / 2,
			width: 1,
			height: height
		).fill()
	}

	private func drawBranch(in shape: NSRect) {
		let hint = NSAttributedString(string: Self.hint, attributes: [
			.font: Self.hintFont,
			.foregroundColor: Theme.current.gutterText,
		])
		let hintSize = hint.size()
		let hintX = shape.maxX - Self.padding - ceil(hintSize.width)
		hint.draw(at: NSPoint(x: hintX, y: shape.midY - hintSize.height / 2))

		guard let branch else { return }
		let attributed = NSAttributedString(string: branch, attributes: [
			.font: Self.labelFont,
			.foregroundColor: Theme.current.sidebarText,
		])
		let size = attributed.size()
		let x = divider + Self.padding
		attributed.draw(at: NSPoint(x: x, y: shape.midY - size.height / 2))

		if hoveredHalf == .branch || openHalf == .branch {
			drawChevron(
				at: NSPoint(x: x + ceil(size.width) + Self.gap, y: shape.midY),
				color: Theme.current.sidebarText.withAlphaComponent(0.8)
			)
		}
	}

	private func drawChevron(at point: NSPoint, color: NSColor) {
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

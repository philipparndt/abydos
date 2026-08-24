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
	private var branch: String?
	private var branchIsUnborn = false

	private var trackingArea: NSTrackingArea?
	private var heightConstraint: NSLayoutConstraint?

	// MARK: - Metrics

	private static var padding: CGFloat { Theme.current.scaled(11) }
	private static var gap: CGFloat { Theme.current.scaled(7) }
	private static var chevronWidth: CGFloat { Theme.current.scaled(9) }
	private static var minimumWidth: CGFloat { Theme.current.scaled(300) }

	/// How far the drawn shape sits inside the frame it is given.
	///
	/// Not zero — a hairline of air keeps the shape from touching the capsule
	/// macOS paints behind the item.
	private static var inset: CGFloat { Theme.current.scaled(1) }

	/// The height the capsule would like, before the titlebar has its say.
	private static var wantedHeight: CGFloat { Theme.current.scaled(30) }

	/// What is left of the toolbar row after air above and below.
	///
	/// The row is the system's titlebar — 52 points whatever our zoom is — and
	/// it clips what is taller, so this is the ceiling. Four points at each end
	/// keep the capsule off the window's top edge and off the seam under it.
	private static let rowMargin: CGFloat = 4

	private static var labelFont: NSFont { Theme.current.uiFont(13, weight: .medium) }
	private static var nameFont: NSFont { Theme.current.uiFont(13, weight: .semibold) }
	private static var hintFont: NSFont { Theme.current.uiFont(10.5, weight: .medium) }

	/// Matches the File menu's Go to Anything…, which sits on VS Code's palette
	/// shortcut because that is the one people's hands already know.
	private static let hint = "⇧⌘P"

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		// A toolbar hands a view-based item 28 points of height and pays no
		// attention to what its intrinsic size asks for — a constraint is the
		// one thing it does honour, which is how the capsule grows with the
		// zoom instead of keeping a 1× box around 2× type.
		translatesAutoresizingMaskIntoConstraints = false
		let constraint = heightAnchor.constraint(equalToConstant: Self.wantedHeight)
		constraint.isActive = true
		heightConstraint = constraint
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	// MARK: - Content

	func setProject(name: String) {
		self.name = name
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// - Parameter isUnborn: the branch is real and named, and nothing has been
	///   committed on it yet — a repository straight out of `git init`.
	///
	/// It shows, because the name is a fact and showing nothing was the bug
	/// (item 0477), and it shows *quietly*: dimmed to the weight of the shortcut
	/// hint beside it, with the reason on the tooltip. The name at full weight
	/// would read as an ordinary branch, and on this one the commit page, the
	/// push button and the branch menu all behave differently — a titlebar that
	/// said `main` in the usual way would be the only thing in the window not
	/// admitting there is nothing there.
	/// Whether the repository is still being looked for.
	///
	/// **The gap this fills is 784 ms**, measured opening a large work tree, and
	/// it used to be 784 ms of nothing: no branch half, no divider, and a click
	/// where the pill would be doing nothing at all — `BranchMenu.show` returned
	/// without opening anything while `project.git` was nil. Somebody clicking a
	/// pill that is not there and gets no response concludes the menu is slow,
	/// which is what was reported.
	///
	/// A name rather than a spinner: the half has to reserve its width anyway,
	/// and one word in the place the branch will be says the same thing without
	/// a moving part in a titlebar.
	var isReadingBranch = false {
		didSet {
			guard isReadingBranch != oldValue else { return }
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	func setBranch(_ branch: String?, isUnborn: Bool = false) {
		self.branch = branch
		self.branchIsUnborn = isUnborn
		// Whatever the answer, it has arrived.
		if branch != nil { isReadingBranch = false }
		// The only thing that qualifies what is on the capsule now. It shared
		// this line with the worktree chip until 0490 moved that into a pill of
		// its own, and the two of them writing straight onto `toolTip` — which
		// is what they did at first — meant whichever arrived second was the
		// only one anybody ever saw. On two views it cannot happen again.
		toolTip = isUnborn ? branch.map { "On \($0) — no commits yet" } : nil
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// Whether the right half has anything to say. A directory that is not a
	/// work tree has no branch, and the divider goes with it.
	var hasBranch: Bool { branch != nil || isReadingBranch }

	/// What the branch half says: the branch, or that it is still being looked
	/// for.
	private var branchText: String? { branch ?? (isReadingBranch ? "reading…" : nil) }

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
		guard let shown = branchText else { return Self.padding + hintWidth + Self.padding }
		return Self.padding
			+ width(of: shown, font: Self.labelFont)
			+ Self.gap + Self.chevronWidth
			+ Self.gap + hintWidth
			+ Self.padding
	}

	private var projectWidth: CGFloat {
		Self.padding + width(of: name, font: Self.nameFont)
			+ Self.gap + Self.chevronWidth + Self.padding
	}

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: Self.inset * 2 + max(Self.minimumWidth, projectWidth + branchWidth),
			height: heightConstraint?.constant ?? Self.wantedHeight
		)
	}

	/// Takes the height the zoom asks for, or as much of it as the row has.
	///
	/// Asked again after a zoom, and when the capsule first lands in a toolbar:
	/// the row is only measurable from inside it.
	func updateHeight() {
		let row = superview?.bounds.height ?? 0
		let available = row > 0 ? max(0, row - Self.rowMargin * 2) : Self.wantedHeight
		let height = min(Self.wantedHeight, available)
		guard heightConstraint?.constant != height else { return }
		heightConstraint?.constant = height
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		updateHeight()
	}

	/// The row is only measurable from inside it, and the capsule is built
	/// before it is in one — so the measurement is taken again here, where it
	/// is certain to be true. It settles in one further pass: `updateHeight`
	/// does nothing when the answer has not changed.
	override func layout() {
		super.layout()
		updateHeight()
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

		// The chevron is drawn only for the half being pointed at: at rest the
		// capsule is two words and a hint.
		if hoveredHalf == .project || openHalf == .project {
			drawChevron(
				at: NSPoint(x: x + ceil(size.width) + Self.gap, y: shape.midY),
				color: Theme.current.sidebarText.withAlphaComponent(0.8)
			)
		}
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

		guard let branch = branchText else { return }
		let attributed = NSAttributedString(string: branch, attributes: [
			.font: Self.labelFont,
			// The dimmer of the two, and the same one the ⇧⌘P hint is drawn in:
			// a branch with nothing on it is there, and is not yet a place
			// anything has happened.
			// The dimmer colour also carries "still reading": it is not yet a
			// branch anybody is on.
			.foregroundColor: branchIsUnborn || isReadingBranch
				? Theme.current.gutterText
				: Theme.current.sidebarText,
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

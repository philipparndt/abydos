import AppKit

/// Which tool window the sidebar is showing.
enum SidebarToolKind {
	case project, changes, branches, structure
}

/// The narrow icon strip down the left edge, as in the reference screenshot.
///
/// Only the project button is wired up; the rest are placeholders for tool
/// windows that do not exist yet, so they render disabled rather than pretending
/// to work.
final class ToolWindowBar: NSView {
	static var width: CGFloat { Theme.current.scaled(40) }

	var onToggleNavigator: (() -> Void)?
	var onToggleTerminal: (() -> Void)?
	/// Asked to review; the strip presents the scope choice itself.
	var onReviewBranch: (() -> Void)?
	var onReviewUncommitted: (() -> Void)?
	var onToggleChanges: (() -> Void)?
	var onToggleBranches: (() -> Void)?
	var onToggleStructure: (() -> Void)?

	private var projectButton: StripButton!
	private var terminalButton: StripButton!
	private var reviewButton: StripButton!
	private var commitButton: StripButton!
	private var branchesButton: StripButton!
	private var structureButton: StripButton!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	/// Highlights whichever sidebar tool window is showing.
	///
	/// Nothing is highlighted when the sidebar is closed, so the strip says
	/// what is on screen rather than what was last picked.
	/// Highlights whichever sidebar tool window is showing.
	///
	/// Nothing is highlighted when the sidebar is closed, so the strip says
	/// what is on screen rather than what was last picked.
	func setSidebarSelection(visible: Bool, tool: SidebarToolKind) {
		projectButton.isSelected = visible && tool == .project
		commitButton.isSelected = visible && tool == .changes
		branchesButton.isSelected = visible && tool == .branches
		structureButton.isSelected = visible && tool == .structure
	}

	private func showReviewMenu() {
		let menu = NSMenu()

		let branch = NSMenuItem(title: "Review Branch…", action: #selector(reviewBranchClicked), keyEquivalent: "r")
		branch.keyEquivalentModifierMask = [.command, .shift]
		branch.target = self
		menu.addItem(branch)

		let uncommitted = NSMenuItem(
			title: "Review Uncommitted Changes…",
			action: #selector(reviewUncommittedClicked),
			keyEquivalent: "u"
		)
		uncommitted.keyEquivalentModifierMask = [.command, .shift]
		uncommitted.target = self
		menu.addItem(uncommitted)

		// Beside the button rather than under the pointer, so the strip stays
		// visible and the menu reads as belonging to it.
		let origin = NSPoint(x: reviewButton.bounds.maxX + Theme.current.scaled(4), y: 0)
		menu.popUp(positioning: nil, at: origin, in: reviewButton)
	}

	@objc private func reviewBranchClicked() { onReviewBranch?() }
	@objc private func reviewUncommittedClicked() { onReviewUncommitted?() }

	private func build() {
		projectButton = StripButton(symbol: "folder", tooltip: "Project (⌘1)", enabled: true)
		projectButton.isSelected = true
		projectButton.onClick = { [weak self] in self?.onToggleNavigator?() }

		commitButton = StripButton(symbol: "arrow.up.circle", tooltip: "Commit (⌘2)", enabled: true)
		commitButton.onClick = { [weak self] in self?.onToggleChanges?() }
		branchesButton = StripButton(symbol: "arrow.trianglehead.branch", tooltip: "Branches (⌘3)", enabled: true)
		branchesButton.onClick = { [weak self] in self?.onToggleBranches?() }
		structureButton = StripButton(symbol: "list.bullet.indent", tooltip: "Structure (⌘4)", enabled: true)
		structureButton.onClick = { [weak self] in self?.onToggleStructure?() }

		let stack = NSStackView(views: [projectButton, commitButton, branchesButton, structureButton])
		stack.orientation = .vertical
		stack.spacing = 4
		stack.alignment = .centerX
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		// Bottom-docked tool windows get buttons at the bottom of the strip, which
		// is where IDEA puts them and matches where the panel actually appears.
		terminalButton = StripButton(symbol: "terminal", tooltip: "Terminal (⌘J)", enabled: true)
		terminalButton.onClick = { [weak self] in self?.onToggleTerminal?() }

		// The agent review is the reason this app exists, so it gets a button
		// rather than living only in a menu. Two scopes behind one control: they
		// are the same action asked of different code, and a strip this narrow
		// cannot carry two icons that would be told apart at a glance.
		reviewButton = StripButton(symbol: "checkmark.seal", tooltip: "Review (⇧⌘R)", enabled: true)
		reviewButton.onClick = { [weak self] in self?.showReviewMenu() }

		let bottomStack = NSStackView(views: [reviewButton, terminalButton])
		bottomStack.orientation = .vertical
		bottomStack.spacing = 4
		bottomStack.alignment = .centerX
		bottomStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(bottomStack)

		// Offset below the titlebar so the first icon lines up with the sidebar
		// header rather than sitting behind it. Set from the measured titlebar
		// height, which differs with and without a toolbar.
		topConstraint = stack.topAnchor.constraint(equalTo: topAnchor, constant: 52)
		NSLayoutConstraint.activate([
			topConstraint,
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),

			bottomStack.leadingAnchor.constraint(equalTo: leadingAnchor),
			bottomStack.trailingAnchor.constraint(equalTo: trailingAnchor),
			bottomStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
		])
	}

	/// Lights the terminal button while the panel is showing.
	func setTerminalSelected(_ selected: Bool) {
		terminalButton.isSelected = selected
	}

	private var topConstraint: NSLayoutConstraint!

	/// Distance from the top of the window to the first icon.
	func setTopInset(_ inset: CGFloat) {
		topConstraint.constant = inset + 2
	}

	/// Re-measures the buttons after a zoom change.
	func applySettings() {
		for case let stack as NSStackView in subviews {
			for case let button as StripButton in stack.arrangedSubviews {
				button.applyThemeChange()
			}
		}
		needsDisplay = true
	}


	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
	}
}

/// One icon button in the strip.
final class StripButton: NSView {
	var onClick: (() -> Void)?

	var isSelected = false {
		didSet { needsDisplay = true }
	}

	private let symbol: String
	private let enabled: Bool
	private var sizeConstraints: [NSLayoutConstraint] = []
	private var isHovered = false {
		didSet { needsDisplay = true }
	}
	private var trackingArea: NSTrackingArea?

	init(symbol: String, tooltip: String, enabled: Bool) {
		self.symbol = symbol
		self.enabled = enabled
		super.init(frame: .zero)
		toolTip = tooltip
		translatesAutoresizingMaskIntoConstraints = false
		sizeConstraints = [
			widthAnchor.constraint(equalToConstant: Theme.current.scaled(30)),
			heightAnchor.constraint(equalToConstant: Theme.current.scaled(30)),
		]
		NSLayoutConstraint.activate(sizeConstraints)
	}

	func applyThemeChange() {
		for constraint in sizeConstraints {
			constraint.constant = Theme.current.scaled(30)
		}
		needsDisplay = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) { if enabled { isHovered = true } }
	override func mouseExited(with event: NSEvent) { isHovered = false }

	/// Claims the click.
	///
	/// Without this, `NSResponder`'s default implementation passes the press up
	/// the responder chain, and the matching `mouseUp` is not reliably
	/// delivered here either — so the button fires only sometimes.
	override func mouseDown(with event: NSEvent) {
		guard enabled else {
			super.mouseDown(with: event)
			return
		}
	}

	override func mouseUp(with event: NSEvent) {
		guard enabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
		onClick?()
	}

	override func draw(_ dirtyRect: NSRect) {
		if isSelected || isHovered {
			let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
			NSColor.white.withAlphaComponent(isSelected ? 0.12 : 0.07).setFill()
			path.fill()
		}

		let tint: NSColor = enabled
			? (isSelected ? Theme.current.sidebarHeaderText : Theme.current.sidebarText)
			: Theme.current.gitIgnored.withAlphaComponent(0.5)
		// Colour baked into the symbol configuration — see Theme.symbol.
		guard let rendered = Theme.symbol(symbol, size: 15 * Theme.current.scale, color: tint) else { return }
		// respectFlipped: this view is flipped; without it the glyph mirrors.
		rendered.draw(
			in: NSRect(
				x: bounds.midX - Theme.current.scaled(8),
				y: bounds.midY - Theme.current.scaled(8),
				width: Theme.current.scaled(16),
				height: Theme.current.scaled(16)
			),
			from: .zero,
			operation: .sourceOver,
			fraction: 1.0,
			respectFlipped: true,
			hints: nil
		)
	}
}

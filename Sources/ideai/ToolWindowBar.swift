import AppKit

/// The narrow icon strip down the left edge, as in the reference screenshot.
///
/// Only the project button is wired up; the rest are placeholders for tool
/// windows that do not exist yet, so they render disabled rather than pretending
/// to work.
final class ToolWindowBar: NSView {
	static let width: CGFloat = 40

	var onToggleNavigator: (() -> Void)?

	private var projectButton: StripButton!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		projectButton = StripButton(symbol: "folder", tooltip: "Project (⌘1)", enabled: true)
		projectButton.isSelected = true
		projectButton.onClick = { [weak self] in self?.onToggleNavigator?() }

		let commit = StripButton(symbol: "arrow.up.circle", tooltip: "Commit — not implemented", enabled: false)
		let branches = StripButton(symbol: "arrow.trianglehead.branch", tooltip: "Git — not implemented", enabled: false)
		let structure = StripButton(symbol: "list.bullet.indent", tooltip: "Structure — not implemented", enabled: false)

		let stack = NSStackView(views: [projectButton, commit, branches, structure])
		stack.orientation = .vertical
		stack.spacing = 4
		stack.alignment = .centerX
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		// Offset below the titlebar so the first icon lines up with the sidebar
		// header rather than sitting behind it. Set from the measured titlebar
		// height, which differs with and without a toolbar.
		topConstraint = stack.topAnchor.constraint(equalTo: topAnchor, constant: 52)
		NSLayoutConstraint.activate([
			topConstraint,
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
		])
	}

	private var topConstraint: NSLayoutConstraint!

	/// Distance from the top of the window to the first icon.
	func setTopInset(_ inset: CGFloat) {
		topConstraint.constant = inset + 2
	}

	func setNavigatorSelected(_ selected: Bool) {
		projectButton.isSelected = selected
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
	}
}

/// One icon button in the strip.
private final class StripButton: NSView {
	var onClick: (() -> Void)?

	var isSelected = false {
		didSet { needsDisplay = true }
	}

	private let symbol: String
	private let enabled: Bool
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
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 30),
			heightAnchor.constraint(equalToConstant: 30),
		])
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
		guard let rendered = Theme.symbol(symbol, size: 15, color: tint) else { return }
		// respectFlipped: this view is flipped; without it the glyph mirrors.
		rendered.draw(
			in: NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16),
			from: .zero,
			operation: .sourceOver,
			fraction: 1.0,
			respectFlipped: true,
			hints: nil
		)
	}
}

import AppKit
import AbydosKit

// MARK: - Header

/// The "Project ⌄" strip above the tree.
final class NavigatorHeaderView: NSView {
	override var isFlipped: Bool { true }

	/// The three things a tree this size needs and cannot do by itself: fold
	/// everything away, find its way back to whatever the editor is showing, and
	/// stop spending five rows on what one row could say.
	var onCollapseAll: (() -> Void)?
	var onSelectOpenFile: (() -> Void)?
	var onToggleCompactPackages: (() -> Void)?
	/// The fourth, asked for 2026-09-12: read the folder and the working copy
	/// again, on demand — what a build writing files does to the tree, without
	/// waiting for the watcher to say so.
	var onRefresh: (() -> Void)?

	/// Whether the third button is on, which is the one thing about this header
	/// that is a state rather than a gesture — so it is the one thing drawn
	/// differently.
	var isCompactingPackages = false {
		didSet { if isCompactingPackages != oldValue { restyle() } }
	}

	private lazy var collapseButton = button(
		symbol: "arrow.down.right.and.arrow.up.left",
		action: #selector(collapseAll)
	)
	private lazy var locateButton = button(
		symbol: "scope",
		action: #selector(selectOpenFile)
	)
	private lazy var compactButton = button(
		symbol: "rectangle.compress.vertical",
		action: #selector(toggleCompactPackages)
	)
	private lazy var refreshButton = button(
		symbol: "arrow.clockwise",
		action: #selector(refresh)
	)

	/// Which of the three the pointer is on, and what each says.
	///
	/// **They were explained by AppKit's yellow box and lit up under
	/// nothing.** A button that does something when it is clicked says so
	/// before it is clicked, which the terminal strip's controls have done
	/// since they were given hover and these had not; `TipHost` is that
	/// plumbing, written once.
	private lazy var tips = TipHost<Action>(
		controls: { [weak self] in self?.actionRects() ?? [] },
		words: { [weak self] action in self?.words(for: action) ?? StyledTip.Tip(title: "") }
	)
	private var trackingArea: NSTrackingArea?

	enum Action { case collapse, locate, compact, refresh }

	private func actionRects() -> [(Action, NSRect)] {
		[
			(.locate, locateButton.frame), (.collapse, collapseButton.frame),
			(.compact, compactButton.frame), (.refresh, refreshButton.frame),
		]
	}

	private func words(for action: Action) -> StyledTip.Tip {
		switch action {
		case .collapse:
			return StyledTip.Tip(
				title: "Collapse all",
				detail: "Folds every folder away, leaving the roots."
			)
		case .locate:
			return StyledTip.Tip(
				title: "Select the file in the editor",
				detail: "Finds whatever is in front, opening the folders on the way to it."
			)
		case .refresh:
			return StyledTip.Tip(
				title: "Re-read the project",
				detail: "Reads the folder and the working copy's status again, as a build writing files would make it."
			)
		case .compact:
			return isCompactingPackages
				? StyledTip.Tip(
					title: "Showing middle packages one per row",
					detail: "Click to fold a chain of single folders back into one row."
				)
				: StyledTip.Tip(
					title: "Compact middle packages",
					detail: "A chain of folders holding nothing but the next one is drawn as a single row."
				)
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		for view in [locateButton, collapseButton, compactButton, refreshButton] { addSubview(view) }
		compactButton.wantsLayer = true
		layoutButtons()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("not from a nib") }

	private func button(symbol: String, action: Selector) -> NSButton {
		let button = NSButton(image: NSImage(), target: self, action: action)
		button.image = Theme.symbol(
			symbol, size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		button.isBordered = false
		button.bezelStyle = .shadowlessSquare
		button.imagePosition = .imageOnly
		// No `toolTip`: what these say is drawn, from `tips` below, in the
		// theme's own type rather than the system's box.
		// Nothing here should take focus from the tree, which is the point of
		// the buttons: the keyboard stays where it was.
		button.refusesFirstResponder = true
		return button
	}

	override func layout() {
		super.layout()
		layoutButtons()
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

	override func mouseDown(with event: NSEvent) {
		// A tip explains a control somebody has stopped reading about and
		// started using. The buttons themselves take the click.
		tips.clear()
		super.mouseDown(with: event)
	}

	/// Puts the pointer on one of the three and says whether it lit and what it
	/// would tell somebody, for a driven run.
	func hoverActionForTesting(_ name: String) -> String {
		tips.hoverForTesting(
			name, ["collapse": .collapse, "locate": .locate, "compact": .compact, "refresh": .refresh], in: self
		)
	}

	private func layoutButtons() {
		let size = Theme.current.scaled(20)
		var x = bounds.maxX - Theme.current.scaled(8) - size
		// Rightmost first.
		for view in [locateButton, collapseButton, compactButton, refreshButton] {
			view.frame = NSRect(x: x, y: (bounds.height - size) / 2, width: size, height: size)
			x -= size + Theme.current.scaled(2)
		}
		compactButton.layer?.cornerRadius = Theme.current.scaled(4)
	}

	/// Redrawn on a theme or zoom change, since the symbols carry their colour
	/// and their size in the image itself.
	func restyle() {
		collapseButton.image = Theme.symbol(
			"arrow.down.right.and.arrow.up.left", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		locateButton.image = Theme.symbol(
			"scope", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		compactButton.image = Theme.symbol(
			"rectangle.compress.vertical", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		refreshButton.image = Theme.symbol(
			"arrow.clockwise", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		// On is a pill behind the symbol rather than a colour on it: the symbol
		// is eleven points of line work, and a tint on something that small
		// reads as a rendering artefact on one theme and as nothing at all on
		// the other.
		compactButton.layer?.backgroundColor = isCompactingPackages
			? Theme.current.selectionActive.withAlphaComponent(0.45).cgColor
			: NSColor.clear.cgColor
		layoutButtons()
		needsDisplay = true
	}

	@objc private func collapseAll() { onCollapseAll?() }
	@objc private func selectOpenFile() { onSelectOpenFile?() }
	@objc private func toggleCompactPackages() { onToggleCompactPackages?() }
	@objc private func refresh() { onRefresh?() }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()

		// Under the button the pointer is on, before the symbols are drawn over
		// it. The compact button is a pill of its own when it is on, so its
		// hover has to read against that tint rather than vanish under it.
		if let hovered = tips.hovered {
			HoverGround.draw(
				around: tips.rect(of: hovered),
				ink: Theme.current.sidebarHeaderText,
				overTint: hovered == .compact && isCompactingPackages
			)
		}

		let attributed = NSAttributedString(string: "Project", attributes: [
			.font: Theme.current.uiFont(13, weight: .semibold),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let size = attributed.size()
		attributed.draw(at: NSPoint(x: Theme.current.scaled(12), y: bounds.midY - size.height / 2))

		let path = NSBezierPath()
		let x = Theme.current.scaled(12) + size.width + Theme.current.scaled(8)
		path.move(to: NSPoint(x: x, y: bounds.midY - 2))
		path.line(to: NSPoint(x: x + 3.5, y: bounds.midY + 2))
		path.line(to: NSPoint(x: x + 7, y: bounds.midY - 2))
		path.lineWidth = 1.3
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		Theme.current.sidebarText.withAlphaComponent(0.8).setStroke()
		path.stroke()
	}
}

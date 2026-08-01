import AppKit

/// Which tool window the sidebar is showing.
enum SidebarToolKind {
	case project, changes, branches, structure, scratches, history
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
	var onToggleScratches: (() -> Void)?
	var onToggleHistory: (() -> Void)?
	/// Bring an existing session forward, when there is one.
	var onToggleDebug: (() -> Void)?
	/// Whether anything is being debugged, which decides whether the button
	/// shows the panel or offers ways to start.
	var isDebugRunning: (() -> Bool)?
	var onDebugGoPackage: (() -> Void)?
	var onDebugExecutable: (() -> Void)?
	var onAttachToProcess: (() -> Void)?
	/// Whether this project looks like a Go module, so the Go entry is offered
	/// first rather than at all times.
	var isGoProject: (() -> Bool)?

	private var projectButton: StripButton!
	private var terminalButton: StripButton!
	private var reviewButton: StripButton!
	private var commitButton: StripButton!
	private var branchesButton: StripButton!
	private var structureButton: StripButton!
	private var scratchesButton: StripButton!
	private var historyButton: StripButton!
	private var debugButton: StripButton!

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
		scratchesButton.isSelected = visible && tool == .scratches
		historyButton.isSelected = visible && tool == .history
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

	/// A running session is brought forward; otherwise the button offers the
	/// ways to start one.
	///
	/// It used to start a Go session outright, which in a project that is not
	/// Go produced an error about a missing go.mod — an answer to a question
	/// nobody asked.
	private func debugButtonPressed() {
		if isDebugRunning?() == true {
			onToggleDebug?()
			return
		}

		let menu = NSMenu()
		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			entry.target = self
			return entry
		}

		// Go first where the project is Go, since that is then the likely one.
		if isGoProject?() == true {
			menu.addItem(item("Debug Go Package", #selector(debugGoClicked)))
		}
		menu.addItem(item("Debug Executable\u{2026}", #selector(debugExecutableClicked)))
		menu.addItem(item("Attach to Process\u{2026}", #selector(attachClicked)))

		let origin = NSPoint(x: debugButton.bounds.maxX + Theme.current.scaled(4), y: 0)
		menu.popUp(positioning: nil, at: origin, in: debugButton)
	}

	@objc private func debugGoClicked() { onDebugGoPackage?() }
	@objc private func debugExecutableClicked() { onDebugExecutable?() }
	@objc private func attachClicked() { onAttachToProcess?() }

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

		// Notes are not part of the project, so the icon is a page rather than
		// anything filed: what it opens is the pile you keep beside the work.
		scratchesButton = StripButton(symbol: "note.text", tooltip: "Scratches (⌘5)", enabled: true)
		scratchesButton.onClick = { [weak self] in self?.onToggleScratches?() }

		historyButton = StripButton(symbol: "clock.arrow.circlepath", tooltip: "History (⌘6)", enabled: true)
		historyButton.onClick = { [weak self] in self?.onToggleHistory?() }

		// Commit, branches and history are three views of one repository, and
		// they were scattered between the file tree and the notes. Grouped and
		// fenced off, the strip reads as three things rather than six.
		let gitSeparator = StripSeparator()
		let toolSeparator = StripSeparator()

		let stack = NSStackView(views: [
			projectButton,
			gitSeparator,
			commitButton, branchesButton, historyButton,
			toolSeparator,
			structureButton, scratchesButton,
		])
		stack.orientation = .vertical
		stack.spacing = 4
		stack.alignment = .centerX
		// A little more air around the rules than between the icons they
		// separate, or the grouping reads as an accident.
		stack.setCustomSpacing(7, after: projectButton)
		stack.setCustomSpacing(7, after: gitSeparator)
		stack.setCustomSpacing(7, after: historyButton)
		stack.setCustomSpacing(7, after: toolSeparator)
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

		// Bottom-docked, beside the terminal: the debugger is a panel down
		// there too, and this is where somebody looks for it.
		debugButton = StripButton(symbol: "ladybug", tooltip: "Debug", enabled: true)
		debugButton.onClick = { [weak self] in self?.debugButtonPressed() }

		let bottomStack = NSStackView(views: [reviewButton, debugButton, terminalButton])
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

	/// Lights the debug button while a session is running, so the strip says
	/// something is being debugged even when the panel is closed.
	func setDebugRunning(_ running: Bool) {
		debugButton.isSelected = running
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
		rendered.drawFitted(in: NSRect(
				x: bounds.midX - Theme.current.scaled(8),
				y: bounds.midY - Theme.current.scaled(8),
				width: Theme.current.scaled(16),
				height: Theme.current.scaled(16)
			))
	}
}

/// A hairline between groups of buttons in the strip.
private final class StripSeparator: NSView {
	override var intrinsicContentSize: NSSize {
		NSSize(width: Theme.current.scaled(16), height: 1)
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.separator.setFill()
		bounds.fill()
	}
}

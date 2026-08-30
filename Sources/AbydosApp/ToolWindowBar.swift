import AppKit

/// Which tool window the sidebar is showing.
enum SidebarToolKind {
	case project, changes, branches, structure, scratches, history, pullRequests
}

/// A pane that docks under the editor and has a button on the rail.
///
/// **Not every pane kind, on purpose.** Search, usages and the profiler open in
/// the same panel and are reached from elsewhere; the rail is thirty points wide
/// and does not carry a button for each of them. What it must not do is answer
/// for one of those with a neighbour's button, so they map to nothing rather
/// than to something near.
enum PanelToolKind: Hashable {
	case backlog, review, debug, terminal
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
	/// Show the pull requests of this repository.
	var onTogglePullRequests: (() -> Void)?
	/// Show the backlog: the board and the list over `.abydos/backlog`.
	var onToggleBacklog: (() -> Void)?
	/// Bring an existing session forward, when there is one.
	var onToggleDebug: (() -> Void)?
	/// Whether anything is being debugged, which decides whether the button
	/// shows the panel or offers ways to start.
	var isDebugRunning: (() -> Bool)?

	private var projectButton: StripButton!
	/// One button for the whole repository.
	private var gitButton: StripButton!
	private var terminalButton: StripButton!
	private var reviewButton: StripButton!

	/// How many files are waiting to be committed, and how many commits are
	/// waiting to be pushed.
	///
	/// Shown as a colour on the commit button rather than a number: the useful
	/// question from across the room is "is there anything", and the tooltip
	/// says how much for anybody who wants it.
	var uncommittedCount = 0 {
		didSet {
			guard uncommittedCount != oldValue else { return }
			updateCommitButton()
		}
	}

	var unpushedCount = 0 {
		didSet {
			guard unpushedCount != oldValue else { return }
			updateCommitButton()
		}
	}

	/// Blue for work not committed, green for work not pushed, and blue wins:
	/// committing is what comes first, so it is what the button should be
	/// asking for while there is any of it to do.
	private func updateCommitButton() {
		gitButton?.accent = uncommittedCount > 0
			? Theme.current.gitModified
			: (unpushedCount > 0 ? Theme.current.gitAdded : nil)

		var parts: [String] = []
		if uncommittedCount > 0 {
			parts.append("\(uncommittedCount) changed file\(uncommittedCount == 1 ? "" : "s")")
		}
		if unpushedCount > 0 {
			parts.append("\(unpushedCount) commit\(unpushedCount == 1 ? "" : "s") to push")
		}
		gitButton?.toolTip = parts.isEmpty
			? "Git (⌘2)"
			: "Git (⌘2) — " + parts.joined(separator: ", ")
	}
	private var pullRequestsButton: StripButton!
	private var structureButton: StripButton!
	private var scratchesButton: StripButton!
	private var backlogButton: StripButton!
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
		// Three tool kinds still exist behind one button — the commit view and
		// the log are pages now, and the panes remain for what the driver and
		// the popover reach for — so the button is lit for any of them.
		gitButton.isSelected = visible && [.changes, .branches, .history].contains(tool)
		pullRequestsButton.isSelected = visible && tool == .pullRequests
		structureButton.isSelected = visible && tool == .structure
		scratchesButton.isSelected = visible && tool == .scratches
	}

	/// The button a tool lives on, for hanging a popover off.
	func button(for tool: SidebarToolKind) -> NSView? {
		switch tool {
		case .project: return projectButton
		case .changes, .branches, .history: return gitButton
		case .pullRequests: return pullRequestsButton
		case .structure: return structureButton
		case .scratches: return scratchesButton
		}
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

	/// The debug pane, opened. Nothing else.
	///
	/// **It used to ask how to start a session** — Debug Go Package, Debug
	/// Executable…, Attach to Process… — because with nothing running there was
	/// no debug pane to open: the pane was built only by a session starting. One
	/// button in a group of four behaved unlike the other three, and the question
	/// it asked belongs to the run control, which is the thing in the window
	/// whose subject is starting programs. A pane with no session opens on its
	/// breakpoints now, so there is always something to show.
	private func debugButtonPressed() {
		onToggleDebug?()
	}

	@objc private func reviewBranchClicked() { onReviewBranch?() }
	@objc private func reviewUncommittedClicked() { onReviewUncommitted?() }

	private func build() {
		projectButton = StripButton(symbol: "folder", tooltip: "Project (⌘1)", enabled: true)
		projectButton.isSelected = true
		projectButton.onClick = { [weak self] in self?.onToggleNavigator?() }

		// **One button, not three.** The strip used to carry Commit, Branches
		// and History with a rule drawn round them, and a comment explaining
		// that the rule was there so it "reads as three things rather than
		// six". A group that needs a fence to be understood is one button, and
		// what is behind it is one tree: the working copy, the stashes and the
		// refs are all things this repository holds.
		gitButton = StripButton(
			symbol: "arrow.trianglehead.branch", tooltip: "Git (⌘2)", enabled: true
		)
		gitButton.onClick = { [weak self] in self?.onToggleBranches?() }
		// **Its own button, beside the git one rather than behind it.** What is
		// behind the git button is one tree — the working copy, the stashes and
		// the refs, all things this repository holds. A pull request is not one
		// of those: it lives on somebody else's server, it is asked about over
		// the network, and it is opened to read somebody else's work rather than
		// to see where you are standing.
		pullRequestsButton = StripButton(
			symbol: "arrow.trianglehead.pull", tooltip: "Pull Requests", enabled: true
		)
		pullRequestsButton.onClick = { [weak self] in self?.onTogglePullRequests?() }

		structureButton = StripButton(symbol: "list.bullet.indent", tooltip: "Structure (⌘3)", enabled: true)
		structureButton.onClick = { [weak self] in self?.onToggleStructure?() }

		// Notes are not part of the project, so the icon is a page rather than
		// anything filed: what it opens is the pile you keep beside the work.
		scratchesButton = StripButton(symbol: "note.text", tooltip: "Scratches (⌘4)", enabled: true)
		scratchesButton.onClick = { [weak self] in self?.onToggleScratches?() }

		// **The fence comes out with the buttons it fenced.** There is nothing
		// left to separate: four buttons, each a different kind of thing to
		// look at, which is what the rule was there to say about three.
		let stack = NSStackView(views: [
			projectButton,
			gitButton,
			pullRequestsButton,
			structureButton,
			scratchesButton,
		])
		stack.orientation = .vertical
		stack.spacing = 4
		stack.alignment = .centerX
		// A little more air around the rules than between the icons they
		// separate, or the grouping reads as an accident.
		stack.setCustomSpacing(7, after: projectButton)
		stack.setCustomSpacing(7, after: pullRequestsButton)
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

		// First in the bottom group, which is where it was asked for.
		//
		// Until this button existed the backlog had ⇧⌘B and an entry in the
		// Agent menu and nothing else, so the whole feature was invisible to
		// anybody who had not been told the shortcut. A checklist rather than a
		// board or a list, because what a card actually shows about an item is
		// how much of its `## Steps` is ticked.
		backlogButton = StripButton(symbol: "checklist", tooltip: "Backlog (⇧⌘B)", enabled: true)
		backlogButton.onClick = { [weak self] in self?.onToggleBacklog?() }

		let bottomStack = NSStackView(views: [backlogButton, reviewButton, debugButton, terminalButton])
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

	/// Lights whichever panes are in front, and nothing for a pane that is not.
	///
	/// **The rule the sidebar group already keeps**, now kept by the bottom group
	/// too — which is the whole of what was reported. The fill used to mean three
	/// different things down here: the terminal was lit because
	/// `setPanelVisible` said the panel was open, the ladybird because a session
	/// was running, and the backlog and review were never lit at all. So the
	/// backlog pane could be open and in front with its own button looking
	/// exactly like a button nobody had pressed, and the terminal below it lit.
	///
	/// A set rather than one kind, because the panel splits and a shell beside
	/// the backlog puts two panes on screen.
	func setPanelSelection(_ kinds: Set<PanelToolKind>) {
		frontPanes = kinds
		updateBottomGroup()
	}

	/// Whether a debug session is running.
	///
	/// **Kept, and not folded into the selection.** It is what tells somebody
	/// that something is being debugged *while the panel is closed*, and nothing
	/// else on screen says it. It lights the same button, and the green below is
	/// what tells the two apart.
	func setDebugRunning(_ running: Bool) {
		hasRunningDebugSession = running
		updateBottomGroup()
	}

	private var frontPanes: Set<PanelToolKind> = []
	/// Not `isDebugRunning`, which is taken: that one is a *question* the strip
	/// asks the window when the debug menu is built. This is the answer the
	/// window pushed, which is what the button is drawn from.
	private var hasRunningDebugSession = false

	/// One place that decides what the four buttons at the bottom say.
	private func updateBottomGroup() {
		backlogButton?.isSelected = frontPanes.contains(.backlog)
		reviewButton?.isSelected = frontPanes.contains(.review)
		terminalButton?.isSelected = frontPanes.contains(.terminal)
		// The union: the pane in front, or a session running with the panel shut.
		debugButton?.isSelected = frontPanes.contains(.debug) || hasRunningDebugSession
		// **Green for the running one, which is the theme's green and not a new
		// one.** A second green chosen here would be right in the default theme
		// and wrong in somebody else's; this is the one the commit button already
		// carries for work that is not pushed. `StripButton` draws the accent on
		// the icon and the selection as a fill behind it, so the two compose with
		// nothing new drawn.
		debugButton?.accent = hasRunningDebugSession ? Theme.current.gitAdded : nil
	}

	/// Which buttons are lit and why, for `--rail`.
	///
	/// **A picture of the rail proves the fill and not the reason.** Two of the
	/// four buttons at the bottom can be lit for two different reasons, and a
	/// shot of a ladybird with a fill behind it cannot say whether a session is
	/// running or the pane is merely in front. This says both.
	func reportForTesting() -> String {
		func said(_ name: String, _ button: StripButton?) -> String {
			var parts = [name + "=" + (button?.isSelected == true ? "lit" : "unlit")]
			if button?.accent != nil { parts.append("green") }
			return parts.joined(separator: "+")
		}
		return [
			said("backlog", backlogButton),
			said("review", reviewButton),
			said("debug", debugButton),
			said("terminal", terminalButton),
			said("project", projectButton),
			said("pullRequests", pullRequestsButton),
		].joined(separator: " ")
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
		// Compared, because the rail is now told on every column rebuild and
		// most of those change nothing.
		didSet { if isSelected != oldValue { needsDisplay = true } }
	}

	/// A colour for the symbol when it has something to say — the commit
	/// button when the working copy has changes in it.
	var accent: NSColor? {
		didSet { if accent != oldValue { needsDisplay = true } }
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
			? (accent ?? (isSelected ? Theme.current.sidebarHeaderText : Theme.current.sidebarText))
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

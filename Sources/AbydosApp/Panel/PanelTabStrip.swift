import AppKit
import AbydosKit

/// Compact tab strip with add and hide affordances.
final class PanelTabStrip: NSView, TabCloseHovering {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	var renameField: NSTextField?
	var renamingIndex: Int?
	var onSelect: ((Int) -> Void)?
	var onClose: ((Int) -> Void)?
	/// A tab renamed in place. An empty name gives it back to the shell.
	var onRename: ((Int, String) -> Void)?
	/// A tab dropped back into this strip somewhere else.
	var onMove: ((Int, Int) -> Void)?
	/// A tab let go outside the window, which makes it a window.
	var onTearOff: ((Int, NSPoint) -> Void)?
	/// A drag of one of these tabs beginning and ending, so the panel can put
	/// its drop target up while it lasts.
	var onDragStarted: (() -> Void)?
	var onDragEnded: (() -> Void)?
	/// Where the pointer is during a drag, in screen coordinates.
	var onDragMoved: ((NSPoint) -> Void)?
	/// Where a drag ended that nothing else took, so the panel can decide.
	var onDragEndedAt: ((Int, NSPoint) -> Void)?
	/// A tab dropped into this strip, from anywhere: this column, the other
	/// one, or another window.
	var onDropTab: ((TerminalTabDrag.Payload, Int) -> Void)?
	/// Whether a tab from elsewhere is welcome here.
	var acceptsForeign: ((TerminalTabDrag.Payload) -> Bool)?
	/// Asked to put a tab beside what is showing, without a drag.
	var onSplit: ((Int, TerminalTabDrag.Zone) -> Void)?
	/// Asked to go back to one pane.
	var onUnsplit: (() -> Void)?
	/// Whether two panes are showing, so the menu can offer the way back.
	var isSplit: (() -> Bool)?
	/// Whether a tab may be dragged at all — a debugger cannot be.
	var canDrag: ((Int) -> Bool)?
	/// The panel this strip belongs to, so a drag is recognised as its own.
	var panelID = UUID()
	/// Which column of it this strip is.
	var column = 0
	/// Whether the panel's own controls belong here.
	///
	/// They do not in a torn-off terminal window: there is no panel to hide, no
	/// panel to maximise, and following the shell's project belongs to the
	/// window that has a project in it.
	var showsPanelControls = true { didSet { recomputeLayout(); needsDisplay = true } }
	/// Whether the + belongs here. It does in any strip that owns terminals.
	var showsAddButton = true { didSet { recomputeLayout(); needsDisplay = true } }
	var onAdd: (() -> Void)?
	/// Whether the + carries a chevron offering the other kinds of terminal.
	///
	/// The run control's play button already has this shape and this is the same
	/// gesture: the button does the ordinary thing, and the chevron beside it
	/// opens the ways of doing it that are wanted now and then. Off on tmux's own
	/// strip, where the + makes a tmux window and the menu's items would be
	/// answering a different question.
	var showsAddMenu = false { didSet { recomputeLayout(); needsDisplay = true } }
	/// The chevron was pressed, at a point in this view's own coordinates.
	var onAddMenu: ((NSPoint) -> Void)?
	var onHide: (() -> Void)?
	/// Asked to give the panel the whole window, or to give it back.
	var onToggleMaximize: (() -> Void)?
	/// Whether the panel currently has the window to itself, which decides
	/// which way the arrows point.
	var isMaximized = false { didSet { needsDisplay = true } }
	/// Asked to start or stop following the shell's project.
	var onToggleFollowProject: (() -> Void)?
	/// Whether the window is following the terminal, which the control shows.
	var isFollowingProject = false { didSet { needsDisplay = true } }

	/// The tmux session these tabs are the windows of, when they are.
	///
	/// Shown as a tag beside the panel's own controls: the tabs look like our
	/// tabs, and it should be visible at a glance that they are not — that
	/// closing one closes a tmux window, and that another client can move them.
	var mirroredSession: String? {
		didSet {
			guard mirroredSession != oldValue else { return }
			recomputeLayout()
			needsDisplay = true
		}
	}

	var mirrorTagFrame: NSRect = .zero

	/// Every running Claude Code session on the machine, as the two numbers
	/// `SessionsPill` draws beside the tag. Nil when there is none, and then
	/// there is no pill and the tabs have the room: a grey `0 · 0` would be
	/// furniture, for the reason the git pane draws no `Fetch` without a remote.
	var runningCounts: RunningSessions.Counts? {
		didSet {
			guard runningCounts != oldValue else { return }
			recomputeLayout()
			needsDisplay = true
		}
	}

	var sessionsPillFrame: NSRect = .zero
	/// Where the pill is, for a driven run that wants to click it.
	var sessionsPillFrameForTesting: NSRect { sessionsPillFrame }

	/// The pill was clicked, with where it is so the list can hang off it.
	var onSessionsPillClicked: ((NSRect) -> Void)?

	/// Whether the keyboard is in the panel this strip belongs to.
	///
	/// The whole panel, not one terminal: a split has two of them and one tab
	/// stands for both. A torn-off terminal has no panel, and there everything
	/// in the window counts.
	var hasKeyboardFocus: Bool {
		// Not conditional on the window being in front: leaving the app does
		// not move the cursor out of the pane it is in.
		guard let window, let responder = window.firstResponder as? NSView
		else { return false }

		var found: NSView? = self
		while let view = found, !(view is BottomPanel) { found = view.superview }
		guard let container = found ?? window.contentView else { return false }
		return responder === container || responder.isDescendant(of: container)
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		// A strip torn out of its window leaves no tip hanging over the one it
		// left.
		if window == nil { StyledTip.shared.hide() }
		// Nothing tells a view when the first responder moves elsewhere, and the
		// line under the active tab is what says where it went.
		NotificationCenter.default.removeObserver(self, name: .keyboardFocusChanged, object: nil)
		NotificationCenter.default.addObserver(
			forName: .keyboardFocusChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.needsDisplay = true }
		}
	}

	/// The tag was clicked, with where it is on screen so a menu can hang off
	/// it. The tag says which session these tabs belong to; being able to
	/// change it there is where somebody would look for it.
	var onMirrorTagClicked: ((NSRect) -> Void)?

	var items: [PanelTabItem] = []
	var activeIndex: Int?
	var frames: [NSRect] = []
	/// The same rects, readable by the tooltip owner in the extension below.
	var framesForToolTips: [NSRect] { frames }
	var addButtonFrame: NSRect = .zero
	/// The chevron on the +, narrow and part of the same shape.
	var addMenuFrame: NSRect = .zero
	/// The chevron at the trailing end offering the tabs that do not fit.
	var overflowButtonFrame: NSRect = .zero
	/// Which tabs are drawn, and which are only in the menu.
	var visibleRun: Range<Int> = 0..<0
	var hiddenTabs: [Int] = []

	/// The controls at the trailing end of the strip, named so that the hover
	/// and the tooltips can talk about them.
	enum TrailingControl {
		case sessions, mirrorTag, follow, maximize, hide, overflow, add, addMenu
	}

	/// Where each of them is, in the order they are asked. Empty frames contain
	/// nothing, so a control that is not on this strip answers for nobody.
	private func trailingRects() -> [(TrailingControl, NSRect)] {
		[
			(.sessions, sessionsPillFrame), (.mirrorTag, mirrorTagFrame),
			(.follow, followButtonFrame), (.maximize, maximizeButtonFrame),
			(.hide, hideButtonFrame), (.overflow, overflowButtonFrame),
			// The chevron sits on the +'s trailing edge, so it is asked first.
			(.addMenu, addMenuFrame), (.add, addButtonFrame),
		]
	}

	/// What each of them says when the pointer rests on it.
	///
	/// Written here rather than beside each drawing call so that the whole set
	/// can be read at once — a tooltip is the only place several of these are
	/// ever explained, and they should sound like one another.
	private func words(for control: TrailingControl) -> StyledTip.Tip {
		switch control {
		case .sessions:
			let counts = runningCounts
			return StyledTip.Tip(
				title: "\(counts?.working ?? 0) working, "
					+ "\(counts?.needsInput ?? 0) waiting for you",
				detail: "Claude sessions on this machine. Grey counts the ones getting on "
					+ "with it; amber the ones that have asked a question. A session that has "
					+ "finished is in neither. Click for the list.",
				shortcut: "⇧⌘A"
			)
		case .mirrorTag:
			return StyledTip.Tip(
				title: "tmux session “\(mirroredSession ?? "")”",
				detail: "These tabs are its windows. Click to attach this terminal to "
					+ "another session."
			)
		case .follow:
			return isFollowingProject
				? StyledTip.Tip(
					title: "Following the terminal",
					detail: "Walk the shell into another project and the window opens it. "
						+ "Click to stop.",
					shortcut: "⌃⌘F"
				)
				: StyledTip.Tip(
					title: "Follow the terminal",
					detail: "The window opens whatever project the shell walks into. "
						+ "Click to start.",
					shortcut: "⌃⌘F"
				)
		case .maximize:
			return isMaximized
				? StyledTip.Tip(title: "Give the editor its share back", shortcut: "⇧⌘J")
				: StyledTip.Tip(title: "Give the terminal the whole window", shortcut: "⇧⌘J")
		case .hide:
			return StyledTip.Tip(title: "Hide the panel", shortcut: "⌘J")
		case .overflow:
			return StyledTip.Tip(
				title: hiddenTabs.count == 1 ? "1 that does not fit" : "\(hiddenTabs.count) that do not fit",
				detail: "Click to choose one."
			)
		case .add:
			return isMirroringTmux
				? StyledTip.Tip(title: "New tmux window")
				: StyledTip.Tip(title: "New terminal", shortcut: "⇧⌘T")
		case .addMenu:
			return StyledTip.Tip(title: "The other kinds of terminal")
		}
	}

	/// Where a control is, for putting a tip under it — the same table the hit
	/// test reads, so the two cannot disagree about where a control stands.
	func frame(of control: TrailingControl) -> NSRect {
		tips.rect(of: control)
	}
	/// Which tab the run of drawn tabs starts at.
	///
	/// **Not a scroll position.** It changes for one reason — the active tab
	/// does not fit — and by the least that makes it fit; the wheel does not
	/// touch it and it is not remembered anywhere. That is the smallest thing
	/// that keeps the promise that the tab somebody just chose is a tab they can
	/// see, and a wheel can be hung off it later by whoever wants one.
	var runStart = 0
	/// And which tab that is, by name rather than by number.
	///
	/// **An index survives nothing here.** This strip mirrors tmux's window
	/// list and is rebuilt whenever that is re-read, several times a second
	/// while a session is watched: a window closed in another client shifts
	/// every index after it, and a window moved keeps none. A tab that has gone
	/// puts the run back at the start, which is where it is when nothing has
	/// moved.
	private var runStartIdentity: String?
	var hideButtonFrame: NSRect = .zero
	var maximizeButtonFrame: NSRect = .zero
	var followButtonFrame: NSRect = .zero
	var hoveredIndex: Int?
	/// Whether the pointer is on the hovered tab's ✕ rather than the rest of it,
	/// which is the difference between "click to select" and "click to close" and
	/// so has to be visible before the click.
	var hoveredClose = false
	/// The trailing controls' hover and tooltips, kept by `TipHost` — which
	/// this strip grew by hand and the rest of the window's chrome now shares.
	///
	/// **They had no hover and no tooltips**, which for the sessions pill meant
	/// two coloured dots and two figures with nothing anywhere saying what they
	/// counted — reported as "what is grey/orange on the agents element, what
	/// is the agents element even". A control that explains itself only in a
	/// settings page is a control somebody has to go and look up.
	lazy var tips = TipHost<TrailingControl>(
		controls: { [weak self] in self?.trailingRects() ?? [] },
		words: { [weak self] control in self?.words(for: control) ?? StyledTip.Tip(title: "") }
	)
	var hoveredControl: TrailingControl? { tips.hovered }
	/// The frames the tooltip rects were registered for, so they are only
	/// registered again when one of them has actually moved.
	var toolTipShape: [NSRect] = []
	var trackingArea: NSTrackingArea?
	var pressedIndex: Int?
	var pressOrigin: NSPoint = .zero
	var draggedIndex: Int?
	var dropCaret: Int?
	var spinnerTimer: Timer?
	var spinnerPhase: CGFloat = 0

	/// Whether this strip belongs to tmux rather than to the panel.
	///
	/// tmux's own windows, drawn as tmux draws them: numbered rather than
	/// iconned — the number is what `C-b 2` takes you to, and an icon saying
	/// "terminal" on a strip of nothing but terminals says nothing — and in
	/// tmux's green, so it reads as the thing inside the terminal rather than
	/// as more of the app's own chrome.
	var isMirroringTmux = false {
		didSet {
			showsPanelControls = !isMirroringTmux
			recomputeLayout()
			needsDisplay = true
		}
	}

	/// The green a run wears while it is going, matching the titlebar.
	static var runningGreen: NSColor { .hex(0x4E7A4E) }

	/// What is legible on that bar.
	///
	/// Follows the bar rather than being picked alongside it. How far the green
	/// is dimmed is a number somebody will want to turn, and a theme's green can
	/// be any green at all, so the ink is decided from what the bar actually
	/// came out as: tmux's own black-on-green while the bar is light enough for
	/// it, and a bright one once it is not. Chosen either way, one of the two
	/// would eventually be ink the same colour as the thing it is written on.
	///
	/// Bright rather than merely paler than the bar: the tabs nobody is in are
	/// still a list somebody reads across, and a green only a little lighter
	/// than the green behind it is a list you have to lean in for.
	static var onTmuxGreen: NSColor {
		let dark = NSColor.hex(0x1D1F21)
		let pale = tmuxGreen.blended(withFraction: 0.86, of: .white) ?? .hex(0xF0F5E8)
		guard let bar = tmuxGreenBar.usingColorSpace(.sRGB) else { return dark }
		let luminance = 0.2126 * bar.redComponent
			+ 0.7152 * bar.greenComponent
			+ 0.0722 * bar.blueComponent
		// Well clear of where the bar actually sits, rather than at the point
		// the two inks are equally bad. At the dimming this ships with, the bar
		// lands at 0.42 — a threshold there would flip the whole strip to
		// near-black ink on the strength of a rounding difference in somebody's
		// theme green. Black only wins on a bar that is genuinely light.
		return luminance > 0.55 ? dark : pale
	}

	/// The green tmux paints its own status bar with, as this terminal renders
	/// it: the palette's green, so a theme that has one of its own is honoured.
	///
	/// Kept for the things that mean *this window*: the number, and the line
	/// under the tab you are in. At full strength it says one thing, and it can
	/// only go on saying it while it is not also the background.
	static var tmuxGreen: NSColor { TerminalPalette.named.indices.contains(2)
		? TerminalPalette.named[2]
		: .hex(0x8FBF5F)
	}

	/// The bar itself: the same green, sunk into the terminal's own background
	/// until it is a tone rather than a colour.
	///
	/// Full strength across the whole foot of the window, it was the brightest
	/// thing on screen — a bar that shouts for attention it does not want, and
	/// which nothing else in the app could then be louder than. Dimmed, it is
	/// still recognisably tmux's bar: the same hue, over the same background as
	/// the terminal above it, so it reads as part of the terminal rather than
	/// as part of the app.
	static var tmuxGreenBar: NSColor {
		tmuxGreen.blended(withFraction: 0.58, of: TerminalPalette.background) ?? tmuxGreen
	}

	override var isFlipped: Bool { true }

	/// Presses the + from a test, without a mouse.
	func pressAddForTesting() { onAdd?() }

	/// Whether the chevron is drawn and can be pressed.
	///
	/// tmux's strip keeps a bare +: its tabs are tmux's windows, and offering
	/// "a terminal in the devcontainer" from a strip that makes tmux windows
	/// would be one button answering two questions.
	var offersAddMenu: Bool { showsAddButton && showsAddMenu && !isMirroringTmux }

	/// The two things a click beside the last tab can reach.
	enum AddControl { case plus, chevron }

	/// Which of them a point is in, chevron first — it overlaps the + slightly
	/// so the pair reads as one shape, and the narrow half must win where they
	/// meet or it could never be pressed.
	func addControl(at point: NSPoint) -> AddControl? {
		if offersAddMenu, addMenuFrame.contains(point) { return .chevron }
		if showsAddButton, addButtonFrame.contains(point) { return .plus }
		return nil
	}

	/// What a click at the middle of each of those reaches, for the harness.
	///
	/// A menu cannot be photographed while it is open, so what is checkable
	/// about a chevron is that it is there and that it is not the button beside
	/// it: pressing the + must still make a plain terminal.
	var addControlsForTesting: String {
		guard showsAddButton else { return "no +" }
		func name(_ control: AddControl?) -> String {
			switch control {
			case .plus?: return "plus"
			case .chevron?: return "chevron"
			case nil: return "nothing"
			}
		}
		let plus = name(addControl(at: NSPoint(x: addButtonFrame.midX, y: addButtonFrame.midY)))
		guard offersAddMenu else { return "plus->\(plus) chevron->none" }
		let chevron = name(addControl(at: NSPoint(x: addMenuFrame.midX, y: addMenuFrame.midY)))
		return "plus->\(plus) chevron->\(chevron)"
	}

	/// Clicks a tab by its position on the strip, without a mouse — which is
	/// the only way to catch a strip that answers for the tab next door.
	func pressSelectForTesting(_ index: Int) { onSelect?(index) }

	/// What the strip is showing, in order, with the active one marked.
	var itemsForTesting: String {
		items.enumerated()
			.map { "\($0.offset == activeIndex ? "*" : " ")\($0.element.title)" }
			.joined(separator: " | ")
	}

	/// Picks "Close" from a tab's menu, without a mouse.
	func pressCloseForTesting(_ index: Int) { onClose?(index) }

	/// Puts the pointer on a tab's ✕, or off the strip, and says what the strip
	/// now believes is under it.
	///
	/// Through `updateHover` rather than by setting the two flags: what is being
	/// checked is what the pointer does, and a harness that assigned the state
	/// directly would pass with the hit test wired to nothing — which is very
	/// nearly the bug this strip had.
	var tabCountForTesting: Int { items.count }

	@discardableResult
	func hoverCloseForTesting(_ index: Int?) -> String {
		if let frame = index.flatMap({ frames[safe: $0] }) {
			let close = closeRect(for: frame)
			updateHover(at: NSPoint(x: close.midX, y: close.midY))
		} else {
			clearHover()
		}
		let item = index.flatMap { items[safe: $0] }
		return "panel \(isMirroringTmux ? "(tmux)" : "      ")"
			+ " \"\(item?.title ?? "-")\" closable=\(item?.isClosable ?? true)"
			+ " -> tab=\(hoveredIndex.map(String.init) ?? "none") close=\(hoveredClose)"
	}

	/// Puts the pointer on one of the trailing controls and says what it is and
	/// what it would tell somebody — the hover and the tooltip in one answer,
	/// since they are the same question asked with the pointer.
	func hoverTrailingForTesting(_ name: String) -> String {
		tips.hoverForTesting(name, [
			"sessions": .sessions, "tag": .mirrorTag, "follow": .follow,
			"maximize": .maximize, "hide": .hide, "overflow": .overflow,
			"add": .add, "add-menu": .addMenu,
		], in: self)
	}

	/// How many tabs the strip holds, for deciding which strip the keys mean.
	var tabCount: Int { items.count }

	/// Selects the tab `offset` places from the active one, wrapping, exactly as
	/// a click on it would — through the same `onSelect`, so a tmux window, a
	/// terminal and a debugger are each selected the way they already are.
	///
	/// For ⌘⇧] and ⌘⇧[ while the keyboard is in the panel, which used to move
	/// the editor's tabs behind it.
	func selectNeighbour(offset: Int) {
		guard !items.isEmpty else { return }
		let count = items.count
		let current = activeIndex ?? 0
		onSelect?(((current + offset) % count + count) % count)
	}

	func setItems(_ items: [PanelTabItem], activeIndex: Int?) {
		self.items = items
		self.activeIndex = activeIndex
		// Where the run was, by the name of the tab it started at rather than by
		// its number — see `runStartIdentity`. A tab that has gone puts it back
		// at the beginning.
		runStart = runStartIdentity.flatMap { identity in
			items.firstIndex { $0.identity == identity }
		} ?? 0
		recomputeLayout()
		showActiveTab()
		syncSpinner()
		needsDisplay = true
	}

	/// A tooltip on any tab whose pane is drawn by the other engine.
	///
	/// The mark says *that* something is different; this says what, and carries
	/// the engine's declared gaps — which are the reason somebody turned it on
	/// deliberately and which live in a source file otherwise.
	func refreshEngineTips() {
		removeAllToolTips()
		for (index, item) in items.enumerated() {
			guard let note = item.engineNote, frames.indices.contains(index) else { continue }
			// The owner answers from the point, so nothing has to be kept in
			// step with a strip that is rebuilt every time tmux is re-read.
			_ = note
			addToolTip(frames[index], owner: self, userData: nil)
		}
		// **No system tooltip for the trailing controls.** They have a drawn
		// one — `StyledTip`, shown from the hover — and registering both would
		// be two tips for one control, at two delays, in two styles.
	}

	/// Which tabs are marked and what they would say, for a driver to print.
	var engineMarksForTesting: String {
		// Every terminal tab, marked or not. The claim has two halves — a pane
		// younger than the setting says the other engine drew it, and one older
		// says what it actually has — and a list of only the marked ones can
		// say the first.
		let tabs = items.filter(\.isTerminal).map { item -> String in
			let mark = item.engineNote == nil ? "the usual engine" : "libghostty-vt, marked"
			return "\(item.title): \(mark)"
		}
		let notes = items.compactMap(\.engineNote)
		return (tabs.isEmpty ? "no terminal tabs" : tabs.joined(separator: " | "))
			// The whole note once, because the gaps are the reason somebody
			// turned the engine on and a first line cannot show them.
			+ (notes.isEmpty ? "" : "\nwhat the tooltip says:\n\(notes[0])")
	}

	/// Moves the run, if it has to, so the active tab is one somebody can see.
	///
	/// Selecting a tab from the overflow menu and having it stay hidden is the
	/// same fault with a click in front of it.
	private func showActiveTab() {
		guard let active = activeIndex, items.indices.contains(active) else { return }
		let widths = items.map(width(for:))
		let room = tabRoom(overflowing: true)
		let gap = isMirroringTmux ? 0 : Theme.current.scaled(2)
		// Forward if the active tab does not fit, then back into any room going
		// spare at the trailing end. Closing tabs is the reported case: eight
		// left, room for all of them, and five still behind the chevron.
		let moved = TabOverflow.settled(
			start: TabOverflow.start(
				showing: active, widths: widths, from: runStart, available: room, spacing: gap
			),
			widths: widths,
			available: room,
			spacing: gap
		)
		guard moved != runStart else { return }
		runStart = moved
		runStartIdentity = items[safe: moved]?.identity
		recomputeLayout()
	}
}

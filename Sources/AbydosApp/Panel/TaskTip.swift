import AppKit
import AbydosKit

/// The open tasks of a card in progress, listed under it, each one tickable.
///
/// **`StyledTip`'s shape, and the opposite of its one guarantee.** The app's
/// drawn tooltip is a panel that ignores the mouse, and the comment on that
/// line says why: a tip that answered the pointer would keep itself alive after
/// the pointer had left the control it is about. A list of boxes has to answer
/// the pointer, so this is a second panel in the same shape — borderless,
/// non-activating, `.popUpMenu`, a child of the window, the sidebar's ground
/// and edge, the same delay and the same placement — with
/// `ignoresMouseEvents = false`, the way `CompletionPopup` is.
///
/// Extending `StyledTip` with an optional list was considered and dropped. It
/// would put a mouse-taking mode into a type whose one guarantee is that it
/// never takes the mouse, and every caller of `TipHost` would inherit a code
/// path it does not want. Two panels sharing a look through `Theme` cost one
/// more file; one panel with two natures costs a rule.
///
/// **Nothing here reads a file while drawing.** The list is read once, when the
/// tip opens, and again on each reload — which is what a tick causes, through
/// the watcher on the directory. A board redraws on every scroll.
@MainActor
final class TaskTip {
	/// One tip at a time, everywhere, exactly as `StyledTip` is one.
	static let shared = TaskTip()

	/// How long the pointer rests on a card before the tip opens.
	///
	/// The app's own tooltip delay and not a second number: a card that
	/// answered sooner or later than everything else in this window would read
	/// as a different kind of thing.
	static var delay: TimeInterval { StyledTip.delay }

	/// How long the pointer may be on neither the card nor the tip.
	///
	/// The gap between a card's foot and the tip's head is six points, and a
	/// pointer crosses it in well under a quarter of a second. Without the
	/// grace the tip would close in the middle of being reached for, which is
	/// the one gesture it exists to allow.
	static let grace: TimeInterval = 0.25

	private var window: NSPanel?
	private var view: TaskTipView?

	/// The card the tip is about, as the last walk had it.
	private var entry: BoardEntry?
	/// The card the delay is running for, which is not yet the one above.
	private var pending: BoardEntry?
	private var delayTimer: Timer?
	private var graceTimer: Timer?
	private var monitor: Any?
	private var resignation: (any NSObjectProtocol)?

	/// Where the card is, so the panel can be placed again after a reload
	/// changes how tall it is.
	private weak var host: NSView?
	private var cardRect: NSRect = .zero
	private var colour: NSColor = .controlAccentColor

	/// The same three for the card being waited for, which is not the card the
	/// tip is about until `open` promotes them.
	///
	/// **Two anchors, because the pointer is on the second card while the tip
	/// still belongs to the first.** One set of them meant that brushing the
	/// card below — which is what reaching a tip does — moved the *open* tip's
	/// anchor to that card, and the next redraw placed the tip under a card it
	/// was not about, out from under the pointer that was reaching for it. The
	/// tip then closed on the grace, having been moved rather than dismissed.
	/// Reported 2026-09-10, and the half of it that survived the first fix.
	private weak var pendingHost: NSView?
	private var pendingRect: NSRect = .zero
	private var pendingColour: NSColor = .controlAccentColor

	/// Told when a tick has been written, so the board can walk again without
	/// waiting for the watcher.
	///
	/// The watcher does report it — a tick in a terminal already moves a card —
	/// but FSEvents coalesces on its own schedule, and a driven run that ticked
	/// and then printed the fraction would be printing whichever answer the
	/// coalescing had got to. What the pointer does and what a driver does go
	/// through the same call, so both are certain.
	var onTicked: (() -> Void)?
	/// A tick that was written — which file, which line, which words — for the
	/// pane to register with its undo manager, so ⌘Z can take it back.
	var onTickWritten: ((URL, Int, String) -> Void)?
	/// The ticks this tip has made while it has been on screen, oldest first.
	///
	/// Each is a row that stays, dimmed, with *Undo* at its end. **Every one of
	/// them, not only the newest**: a tip is where somebody ticks off several
	/// things at once, and until this was a list the second tick took the first
	/// one's way back off the screen, so the only tick undoable from the tip was
	/// the last one made. Asked for 2026-09-10.
	///
	/// Forgotten when the tip goes: a tick undone from a tip that is not
	/// showing is ⌘Z's, through the pane.
	private var ticks: [(file: URL, line: Int, text: String)] = []

	/// The newest of them, which is what ⌘Z and the driven `undo` take back.
	private var lastTick: (file: URL, line: Int, text: String)? { ticks.last }

	private init() {}

	var isShowing: Bool { window?.isVisible == true }

	/// Which card the tip is about, for a column deciding whether to disturb it.
	var identity: BoardEntry.Identity? { entry?.identity }

	/// Whether the tip is up, which card it is about, and where it is — for a
	/// run posting real pointer moves at it.
	///
	/// **Because the fault this was written for is a path and not a state.**
	/// Reaching a tip means crossing the card below it, and whether that
	/// crossing closes the tip cannot be asked of the tip from inside the
	/// process — `openForTesting` puts one up without a pointer ever having
	/// moved. A run posts the moves from outside and reads this.
	var pointerReportForTesting: String {
		let name: String
		switch entry?.identity {
		case let .change(change)?: name = change
		case let .item(number)?:   name = String(format: "%04d", number)
		case nil:                  name = "none"
		}
		let frame = window?.frame ?? .zero
		var out = "TIP showing=\(isShowing) card=\(name) pending=\(pending != nil)"
			+ " grace=\(graceTimer != nil) wait=\(delayTimer != nil)"
			+ String(format: " frame=%.0f,%.0f,%.0f,%.0f",
				frame.minX, frame.minY, frame.width, frame.height)
		// Every row's box, on the screen, so a run can press one without
		// guessing where a row of two lines put the one after it.
		for row in view?.rowRectsForTesting ?? [] {
			let onScreen = window?.convertToScreen(row.rect) ?? .zero
			out += String(format: "\nTIPROW %d ticked=%@ box=%.0f,%.0f",
				row.index, row.ticked ? "yes" : "no",
				onScreen.minX + Theme.current.scaled(20), onScreen.midY)
		}
		return out
	}

	// MARK: - The pointer

	/// The pointer is on this card, at this rectangle in the host's own
	/// coordinates.
	///
	/// **The same card again asks for nothing.** A board rebuilds its rows on
	/// every reload — including the reload a tick causes — and a tip that
	/// restarted its wait each time would never open under a still pointer.
	/// `StyledTip.show` refuses for the same reason.
	func pointerIsOn(
		_ entry: BoardEntry, at rect: NSRect, of host: NSView, colour: NSColor
	) {
		guard entry.isInProgress else { return pointerIsOnNothing() }
		graceTimer?.invalidate()
		graceTimer = nil

		// The same card, already up: keep what is drawn, and take the newer
		// reading of where it is.
		if self.entry?.identity == entry.identity, isShowing {
			self.entry = entry
			remember(rect, of: host, colour: colour)
			return
		}
		// The same card, still being waited for: the wait does not restart.
		if pending?.identity == entry.identity, delayTimer != nil {
			pending = entry
			rememberPending(rect, of: host, colour: colour)
			return
		}

		// Another card in progress takes the tip's place, after the same wait —
		// and the tip already up is left alone until it does.
		//
		// **This is how a tip was reached.** It opens under its card, and the
		// card below is between the two: a pointer on its way down brushes it,
		// and closing here made every card but the last of a column impossible
		// to reach, since only the last has empty space beneath it and empty
		// space is what the grace was written for. Reported 2026-09-10. The old
		// tip now stays until one of three things happens — the wait below
		// opens the new one over it, the pointer reaches the tip and
		// `pointerIsInside` drops that wait, or the pointer lands on nothing
		// and the grace closes it.
		pending = entry
		rememberPending(rect, of: host, colour: colour)
		delayTimer = Timer.scheduledTimer(withTimeInterval: Self.delay, repeats: false) { _ in
			MainActor.assumeIsolated { self.open() }
		}
	}

	private func remember(_ rect: NSRect, of host: NSView, colour: NSColor) {
		self.host = host
		cardRect = rect
		self.colour = colour
	}

	private func rememberPending(_ rect: NSRect, of host: NSView, colour: NSColor) {
		pendingHost = host
		pendingRect = rect
		pendingColour = colour
	}

	/// The pointer is on no card of this column, or has left it altogether.
	///
	/// The wait is dropped at once — crossing a board must not leave a trail of
	/// tips — but a tip already open is given the grace, because the pointer is
	/// very likely on its way into it.
	func pointerIsOnNothing() {
		delayTimer?.invalidate()
		delayTimer = nil
		pending = nil
		pendingHost = nil
		guard isShowing, graceTimer == nil else { return }
		graceTimer = Timer.scheduledTimer(withTimeInterval: Self.grace, repeats: false) { _ in
			MainActor.assumeIsolated { self.hide() }
		}
	}

	/// The pointer has come inside the tip, which is the gesture the grace
	/// exists for.
	///
	/// The wait is dropped as well as the grace. The pointer is in the tip, so
	/// it is on no card; a wait started by brushing the card below on the way
	/// here would otherwise open that card's tip over the one being read, half
	/// a second after it was reached.
	fileprivate func pointerIsInside() {
		graceTimer?.invalidate()
		graceTimer = nil
		delayTimer?.invalidate()
		delayTimer = nil
		pending = nil
		pendingHost = nil
	}

	/// And has left it again.
	fileprivate func pointerHasLeftTheTip() {
		pointerIsOnNothing()
	}

	// MARK: - Opening, reloading, closing

	private func open() {
		delayTimer?.invalidate()
		delayTimer = nil
		guard let entry = pending, let host = pendingHost, host.window != nil else { return }
		pending = nil
		self.entry = entry
		// The waiting card's anchor becomes the tip's, and only now.
		remember(pendingRect, of: host, colour: pendingColour)
		show()
	}

	/// The board has walked again — this is what the card is now.
	///
	/// Nothing where the tip is not up. A card that has left In progress takes
	/// its tip with it, which is what ticking the last open task does.
	func boardReloaded(entry: BoardEntry?) {
		guard isShowing else { return }
		guard let entry, entry.isInProgress else { return hide() }
		self.entry = entry
		show()
	}

	/// Re-reads the file and redraws, keeping the panel where it is.
	///
	/// The sentence is passed in rather than set afterwards, because it is part
	/// of how tall the panel is: set after the frame had been worked out, a
	/// line saying the file could not be written would be drawn outside it.
	private func show(saying said: String? = nil) {
		guard let entry, let host, let parent = host.window else { return hide() }

		// One read, on the main thread, for both numbers and every row. A
		// `tasks.md` is a few kilobytes and one read per hover is the cost of
		// the feature; asking the card's `progress` for the total instead would
		// be a second answer, from a walk that may be a tick behind.
		let markdown = (try? String(contentsOf: entry.checklistFile, encoding: .utf8)) ?? ""
		let steps = BacklogItem.openSteps(in: markdown)
		// The rows ticked from this tip stay, each one that the file still has
		// ticked with the same words: those are the rows *Undo* is offered on. A
		// file that has moved on since — an agent rewrote it — offers nothing to
		// undo for that row, which is what the write itself would decide.
		let undo = ticks.compactMap { tick -> BacklogItem.OpenStep? in
			guard tick.file == entry.checklistFile,
			      BacklogItem.unticking(line: tick.line, text: tick.text, in: markdown) != nil
			else { return nil }
			return BacklogItem.OpenStep(line: tick.line, text: tick.text)
		}
		// Nothing left open closes it — which is what ticking the last task
		// does — unless there is a sentence to say, and the sentence that gets
		// here is a file that could not be read at all. A row to undo counts as
		// something left: ticking the last task is the tick most worth a way back.
		guard !steps.isEmpty || !undo.isEmpty || said != nil else { return hide() }

		let window = self.window ?? makeWindow()
		self.window = window
		view?.colour = colour
		view?.put(
			steps: steps,
			of: BacklogItem.progress(in: markdown)?.total ?? steps.count,
			saying: said,
			undo: undo
		)

		// A third of the screen, and scrolling past that. A change here has had
		// thirty open tasks, and a thirty-row panel over a five-column board
		// hides the board; a panel capped at twelve rows with "and eighteen
		// more" hides the tasks somebody most wants to reach, since the last
		// ones are the manual ones.
		let visible = parent.screen?.visibleFrame ?? parent.frame
		let size = view?.wantedSize(within: visible.height / 3) ?? .zero

		// Under the card, aligned with its leading edge, and kept on the screen
		// the window is on — the same placement `StyledTip` uses.
		let onScreen = parent.convertToScreen(host.convert(cardRect, to: nil))
		let gap = Theme.current.scaled(6)
		let x = min(max(visible.minX + gap, onScreen.minX), visible.maxX - size.width - gap)
		var y = onScreen.minY - size.height - gap
		// Above the card instead, where there is no room below — which is the
		// board's usual position at the bottom of the window.
		if y < visible.minY + gap { y = onScreen.maxY + gap }

		window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
		if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
		window.orderFront(nil)
		watchForAClickElsewhere(over: parent)
	}

	func hide() {
		delayTimer?.invalidate()
		delayTimer = nil
		graceTimer?.invalidate()
		graceTimer = nil
		pending = nil
		entry = nil
		host = nil
		view?.said = nil
		// The ticks this tip offered a way back on go with it, which is what
		// its own comment always claimed and nothing did: they were kept, so a
		// tip opened later on the same file drew *Undo* on a row somebody had
		// ticked minutes ago and forgotten. Once the tip is gone, ⌘Z through
		// the pane is the way back.
		ticks = []
		stopWatchingForAClickElsewhere()
		guard let window, window.isVisible else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
	}

	// MARK: - Ticking

	/// Ticks the n-th row of what is drawn, which is what a click on it does.
	///
	/// **The check is made at the moment of writing**, in `ticking(line:in:)`:
	/// the list was read when the tip opened, and an agent in a worktree may
	/// have rewritten the file since. A refusal writes nothing and reloads, so
	/// what is on screen becomes what the file says now.
	@discardableResult
	fileprivate func tick(row: Int) -> String {
		guard let entry, let step = view?.step(at: row) else { return "no row \(row)" }
		// The dimmed row with *Undo* on it: the click takes the tick back.
		if view?.undoRows.contains(row) == true { return untick(step) }
		let file = entry.checklistFile
		do {
			guard try BacklogItem.tick(line: step.line, in: file) else {
				// The file moved on under the list. Nothing was written, and
				// what is drawn becomes what the file says now.
				show(saying: "That task has moved. This is the list as the file has it now.")
				return "refused, and the list was read again"
			}
			ticks.append((file, step.line, step.text))
			onTickWritten?(file, step.line, step.text)
			onTicked?()
			// Re-read at once rather than waiting for the walk to come back off
			// its own thread: the row somebody just ticked goes dim and gains
			// *Undo*, and the rows still open stay.
			show()
			return "ticked \(step.text)"
		} catch {
			// Named, because the case that reaches here is a worktree deleted
			// while its card was still on the board, and which file it was is
			// the whole of what somebody needs to know.
			show(saying: "Could not write \(file.path)")
			return "could not write \(file.path)"
		}
	}

	/// Takes one tick back, the way it was made: only if the line still reads as
	/// that ticked step, byte for byte otherwise, refused and re-read when the
	/// file has moved on.
	///
	/// The row is named rather than assumed to be the newest, because every row
	/// ticked from this tip carries its own *Undo* and they can be pressed in
	/// any order.
	@discardableResult
	private func untick(_ step: BacklogItem.OpenStep) -> String {
		guard let tick = ticks.last(where: { $0.line == step.line && $0.text == step.text })
		else { return "nothing to undo" }
		do {
			guard try BacklogItem.untick(line: tick.line, text: tick.text, in: tick.file) else {
				forget(tick)
				show(saying: "That task has moved. This is the list as the file has it now.")
				return "refused, and the list was read again"
			}
			forget(tick)
			onTicked?()
			show()
			return "unticked \(tick.text)"
		} catch {
			show(saying: "Could not write \(tick.file.path)")
			return "could not write \(tick.file.path)"
		}
	}

	private func forget(_ tick: (file: URL, line: Int, text: String)) {
		ticks.removeAll { $0.file == tick.file && $0.line == tick.line && $0.text == tick.text }
	}

	/// What ⌘Z reaches: the newest tick this tip made.
	@discardableResult
	fileprivate func undoLast() -> String {
		guard let last = lastTick else { return "nothing to undo" }
		return untick(BacklogItem.OpenStep(line: last.line, text: last.text))
	}

	// MARK: - What closes it from outside

	/// A click or a scroll anywhere that is not the tip.
	///
	/// A non-activating panel that takes clicks cannot see the ones that land
	/// elsewhere, so the monitor sees the mouse-down first and closes the tip;
	/// the click then goes where it was going. This is what `CompletionPopup`
	/// does and it has held.
	private func watchForAClickElsewhere(over parent: NSWindow) {
		if monitor == nil {
			monitor = NSEvent.addLocalMonitorForEvents(
				matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]
			) { [weak self] event in
				guard let self, self.isShowing else { return event }
				// A click or a scroll inside the tip is somebody using it. Every
				// other one is somebody leaving it, and the event still goes
				// where it was going.
				if event.window !== self.window { self.hide() }
				return event
			}
		}
		if resignation == nil {
			resignation = NotificationCenter.default.addObserver(
				forName: NSWindow.didResignKeyNotification, object: parent, queue: .main
			) { _ in
				MainActor.assumeIsolated { TaskTip.shared.hide() }
			}
		}
	}

	private func stopWatchingForAClickElsewhere() {
		if let monitor { NSEvent.removeMonitor(monitor) }
		monitor = nil
		if let resignation { NotificationCenter.default.removeObserver(resignation) }
		resignation = nil
	}

	// MARK: - Building

	private func makeWindow() -> NSPanel {
		let view = TaskTipView()
		view.onClick = { [weak self] row in _ = self?.tick(row: row) }
		view.onEnter = { [weak self] in self?.pointerIsInside() }
		view.onExit = { [weak self] in self?.pointerHasLeftTheTip() }
		self.view = view

		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		window.hasShadow = true
		window.isOpaque = false
		window.backgroundColor = .clear
		window.level = .popUpMenu
		window.contentView = view
		// **The difference from `StyledTip`, and the whole of this type.** A
		// list of boxes has to be reachable; a tooltip must not be.
		window.ignoresMouseEvents = false
		return window
	}

	func applySettings() {
		guard isShowing else { return }
		view?.applySettings()
		show()
	}

	// MARK: - Testing

	/// The heading and the rows, so what the tip lists is checkable without a
	/// screenshot.
	var reportForTesting: String {
		guard isShowing, let view else { return "no tip" }
		return view.reportForTesting
	}

	/// Clicks a row through the same handler the pointer reaches, so a harness
	/// cannot pass with the hit test wired to nothing.
	func tickForTesting(row: Int) -> String { tick(row: row) }

	/// Takes the last tick back, as the *Undo* row does, and says what the
	/// file's line reads afterwards.
	func undoForTesting() -> String {
		guard let last = lastTick else { return "nothing to undo" }
		let said = undoLast()
		let line = (try? String(contentsOf: last.file, encoding: .utf8))
			.map { $0.split(separator: "\n", omittingEmptySubsequences: false) }
			.flatMap { $0.indices.contains(last.line) ? String($0[last.line]) : nil } ?? "(gone)"
		return "\(said) \u{2192} line \(last.line): \(line.trimmingCharacters(in: .whitespaces))"
	}

	/// Draws the tip to a PNG, since a child window is invisible to a capture
	/// of the main one.
	@discardableResult
	func writeImageForTesting(to path: String) -> Bool {
		guard let view = window?.contentView else { return false }
		view.layoutSubtreeIfNeeded()
		guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
		view.cacheDisplay(in: view.bounds, to: rep)
		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		return (try? data.write(to: URL(fileURLWithPath: path))) != nil
	}

	/// Opens the tip at once, without the wait, for a driven run.
	///
	/// Through the same `open` a rested pointer reaches, so what is driven is
	/// what the pointer does.
	func showNowForTesting(_ entry: BoardEntry, at rect: NSRect, of host: NSView, colour: NSColor) {
		hide()
		pending = entry
		// The *pending* anchor, because that is the one `open` promotes. Set on
		// the shown one instead, this opened nothing at all: `open` found no
		// card waiting and returned, and every driven verb that goes through
		// here — the tip's report, its tick, its picture — said the tip was not
		// up. Caught by driving them; there is no test target for this layer.
		rememberPending(rect, of: host, colour: colour)
		open()
	}
}

/// The panel's one view: a heading, a scrolling list of rows, and a sentence
/// under it where something could not be written.
private final class TaskTipView: NSView {
	var onClick: ((Int) -> Void)?
	var onEnter: (() -> Void)?
	var onExit: (() -> Void)?

	/// The column's colour, which a row's box is filled in under the pointer so
	/// it reads as the thing about to be pressed.
	var colour: NSColor = .controlAccentColor {
		didSet { tableView.reloadData() }
	}

	/// A sentence in place of nothing happening: a file that could not be
	/// written, or a list that had moved on.
	var said: String? {
		didSet {
			guard said != oldValue else { return }
			needsDisplay = true
			// The list gets whatever the sentence leaves, so the sentence
			// arriving or going is a layout and not only a redraw.
			needsLayout = true
		}
	}

	private var steps: [BacklogItem.OpenStep] = []
	private var total = 0
	private var hovered = -1
	/// The row that was just ticked and stays with *Undo* on it, by its place in
	/// `steps`, or nil. It sits where the task sits in the file, among the open
	/// ones, so the list does not reorder under the pointer.
	/// The rows drawn ticked, with *Undo* at their end — one per tick this tip
	/// has made and the file still has.
	private(set) var undoRows: Set<Int> = []

	private var tableView: NSTableView!
	private var scrollView: NSScrollView!
	private var tracking: NSTrackingArea?

	override var isFlipped: Bool { true }

	private var inset: CGFloat { Theme.current.scaled(10) }
	private var widest: CGFloat { Theme.current.scaled(360) }
	private var headingFont: NSFont { Theme.current.uiFont(12, weight: .semibold) }
	private var rowFont: NSFont { Theme.current.uiFont(11) }
	private var saidFont: NSFont { Theme.current.uiFont(11) }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = .clear
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		// Nothing is selected in here. The row under the pointer is the one
		// about to be pressed, and a second highlight for a selection nobody
		// made would be two rows claiming to be the one.
		table.selectionHighlightStyle = .none
		table.style = .plain
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task")))
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.action = #selector(rowClicked)
		tableView = table

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		scroll.autohidesScrollers = true
		// Overlay, so a scroller does not take a strip out of a panel that is
		// only a few hundred points wide.
		scroll.scrollerStyle = .overlay
		scrollView = scroll

		addSubview(scroll)
	}

	override func layout() {
		super.layout()
		let top = inset + headingHeight + Theme.current.scaled(6)
		scrollView.frame = NSRect(
			x: inset - Theme.current.scaled(4),
			y: top,
			width: bounds.width - inset * 2 + Theme.current.scaled(8),
			height: max(0, bounds.height - top - inset - saidHeight)
		)
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let tracking { removeTrackingArea(tracking) }
		let area = NSTrackingArea(
			rect: bounds,
			// Always, because the window this is in never becomes key: a
			// tooltip that took focus from the editor would be worse than one
			// that never opened.
			options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
			owner: self
		)
		addTrackingArea(area)
		tracking = area
	}

	override func mouseEntered(with event: NSEvent) { onEnter?() }

	override func mouseExited(with event: NSEvent) {
		lightUp(row: -1)
		onExit?()
	}

	override func mouseMoved(with event: NSEvent) {
		onEnter?()
		lightUp(row: tableView.row(at: tableView.convert(event.locationInWindow, from: nil)))
	}

	/// Two rows redrawn rather than the whole list.
	///
	/// `reloadData` on every pointer move is thirty rows rebuilt to change one,
	/// in a panel the pointer is crossing on its way to a box.
	private func lightUp(row: Int) {
		guard row != hovered else { return }
		let was = hovered
		hovered = row
		for index in [was, row] where steps.indices.contains(index) {
			(tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? TaskRowView)
				.map { $0.isUnderThePointer = index == row }
		}
	}

	@objc private func rowClicked() {
		guard steps.indices.contains(tableView.clickedRow) else { return }
		onClick?(tableView.clickedRow)
	}

	func put(steps: [BacklogItem.OpenStep], of total: Int, saying said: String?,
	         undo: [BacklogItem.OpenStep] = []) {
		// Each ticked row goes back where its line puts it, so the list stays in
		// the file's order and a row does not move as its neighbours are ticked.
		var rows = steps
		for one in undo.sorted(by: { $0.line < $1.line }) {
			let place = rows.firstIndex { $0.line > one.line } ?? rows.count
			rows.insert(one, at: place)
		}
		undoRows = Set(rows.indices.filter { index in
			undo.contains { $0.line == rows[index].line && $0.text == rows[index].text }
		})
		self.steps = rows
		self.total = max(total, steps.count)
		self.said = said
		hovered = -1
		tableView.reloadData()
		needsDisplay = true
	}

	/// Each row's rectangle in the tip's own window, and whether it is one of
	/// the ticked ones — for a run that presses a box from outside.
	/// In the window's coordinates, ready for `convertToScreen`. A rect in this
	/// view's own coordinates handed straight to the window converts a flipped
	/// y as though it were not one, and the rows come back in the wrong order
	/// and the wrong places.
	var rowRectsForTesting: [(index: Int, rect: NSRect, ticked: Bool)] {
		steps.indices.map { row in
			let inView = convert(tableView.rect(ofRow: row), from: tableView)
			return (row, convert(inView, to: nil), undoRows.contains(row))
		}
	}

	func step(at row: Int) -> BacklogItem.OpenStep? {
		steps.indices.contains(row) ? steps[row] : nil
	}

	func applySettings() {
		tableView.reloadData()
		needsDisplay = true
	}

	// MARK: What it measures

	private var heading: String { "\(steps.count - undoRows.count) open of \(total)" }

	private var headingHeight: CGFloat {
		ceil(headingFont.ascender - headingFont.descender + headingFont.leading)
	}

	private var saidHeight: CGFloat {
		guard let said, !said.isEmpty else { return 0 }
		return ceil(sentence(said).boundingRect(
			with: NSSize(width: widest - inset * 2, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height) + Theme.current.scaled(6)
	}

	/// How tall each row wants to be: one line, or two where the words need
	/// them, and never three.
	func height(of row: Int) -> CGFloat {
		guard let step = step(at: row) else { return 0 }
		var room = widest - inset * 2 - boxRoom
		if undoRows.contains(row) {
			room -= Self.undoWords(colour: colour).size().width + Theme.current.scaled(8)
		}
		let oneLine = ceil(rowFont.ascender - rowFont.descender + rowFont.leading)
		let wanted = ceil(words(step.text).boundingRect(
			with: NSSize(width: room, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height)
		return min(max(oneLine, wanted), oneLine * 2) + Theme.current.scaled(8)
	}

	/// The room a box and its gap take out of a row, before any words.
	private var boxRoom: CGFloat { Theme.current.scaled(13) + Theme.current.scaled(8) }

	/// The size the panel wants, bounded by how much of the screen it may have.
	///
	/// One row is the floor even where the bound is smaller than that, because
	/// a panel too short to show anything is a panel that says nothing about
	/// the screen it did not fit on.
	func wantedSize(within tallest: CGFloat) -> NSSize {
		let rows = (0..<steps.count).reduce(0) { $0 + height(of: $1) }
		let chrome = inset * 2 + headingHeight + Theme.current.scaled(6) + saidHeight
		let atLeast = chrome + (steps.isEmpty ? 0 : height(of: 0))
		return NSSize(width: widest, height: max(atLeast, min(chrome + rows, tallest)))
	}

	// MARK: What it draws

	/// A task's words, with its markdown drawn rather than shown.
	///
	/// **These lines come out of a markdown checklist**, so they carry its
	/// markup, and until this was written they were drawn exactly as the file
	/// has them: a card showed `**Measure the build before settling this.**`
	/// with the asterisks in the words, and `` `buildWorkspace` `` with the
	/// backticks. Reported 2026-09-10. `InlineMarkdown` says which runs are
	/// emphasis and this gives each run its face — the rule is in the Kit,
	/// where it can be checked without a window, and the fonts are here, where
	/// they are known.
	private func words(_ text: String, ticked: Bool = false) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byWordWrapping
		// Full ink rather than the dimmed body `StyledTip` uses: these are
		// the thing to read and the thing to press, not a note about a
		// control. The row just ticked is the exception: dimmed, because it
		// is done, with the one word that is not.
		let ink = ticked
			? Theme.current.sidebarText.withAlphaComponent(0.45)
			: Theme.current.sidebarText
		let line = NSMutableAttributedString()
		for span in InlineMarkdown.spans(of: text) {
			// A code run is fixed pitch a size down: at the row's own size a
			// monospaced face is visibly wider than the prose around it, and a
			// task is mostly prose with one identifier in it.
			let font: NSFont = span.code
				? Theme.current.monoFont(10)
				: Theme.current.uiFont(11, weight: span.bold ? .semibold : .regular)
			line.append(NSAttributedString(string: span.text, attributes: [
				.font: span.italic ? italicised(font) : font,
				.foregroundColor: ink,
				.paragraphStyle: paragraph,
			]))
		}
		return line
	}

	/// The word at the end of a ticked row, drawn on its own.
	///
	/// **Not appended to the words any more.** A row is two lines at most and a
	/// task's first two lines routinely fill them, so *Undo* flowed past the
	/// bottom of its own row and was drawn nowhere: the one row in the list
	/// whose action is not the obvious one was the one that could not say so.
	/// Drawn against the trailing edge instead, with the words given the room
	/// that is left.
	static func undoWords(colour: NSColor) -> NSAttributedString {
		NSAttributedString(string: "Undo", attributes: [
			.font: Theme.current.uiFont(11, weight: .semibold),
			.foregroundColor: colour,
		])
	}

	/// The same face, slanted.
	///
	/// Through the font manager rather than a second `Theme` call, because the
	/// italic of a UI font is a trait of that font and not a font of its own;
	/// where the family has none, the upright face comes back and the run is
	/// drawn plain rather than in something else's italic.
	private func italicised(_ font: NSFont) -> NSFont {
		let slanted = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
		return slanted.fontName == font.fontName ? font : slanted
	}

	private func sentence(_ text: String) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byCharWrapping
		return NSAttributedString(string: text, attributes: [
			.font: saidFont,
			.foregroundColor: Theme.current.gitConflict,
			.paragraphStyle: paragraph,
		])
	}

	override func draw(_ dirtyRect: NSRect) {
		// The sidebar's ground and its edge, so a tip over the board reads as
		// part of this app — `StyledTip`'s, unchanged.
		let shape = NSBezierPath(
			roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
			xRadius: Theme.current.scaled(6), yRadius: Theme.current.scaled(6)
		)
		Theme.current.sidebarBackground.setFill()
		shape.fill()
		Theme.current.separator.setStroke()
		shape.lineWidth = 1
		shape.stroke()

		NSAttributedString(string: heading, attributes: [
			.font: headingFont, .foregroundColor: Theme.current.sidebarText,
		]).draw(at: NSPoint(x: inset, y: inset))

		guard let said, !said.isEmpty else { return }
		sentence(said).draw(with: NSRect(
			x: inset,
			y: bounds.maxY - inset - saidHeight + Theme.current.scaled(6),
			width: bounds.width - inset * 2,
			height: saidHeight
		), options: [.usesLineFragmentOrigin, .usesFontLeading])
	}

	var reportForTesting: String {
		var lines = [heading]
		for (index, step) in steps.enumerated() {
			lines.append("  \(index + 1). \(step.text)  [line \(step.line)]")
		}
		if let said, !said.isEmpty { lines.append("  said: \(said)") }
		return lines.joined(separator: "\n")
	}
}

extension TaskTipView: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { steps.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { height(of: row) }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let view = TaskRowView()
		view.isTicked = undoRows.contains(row)
		view.words = words(steps[row].text, ticked: view.isTicked)
		view.colour = colour
		view.isUnderThePointer = row == hovered
		return view
	}

	/// Nothing is ever selected. The click is the whole of the gesture, and a
	/// row left highlighted after it would be a row claiming to be next.
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}

/// One open task: a drawn box and the step's first line.
///
/// Drawn rather than an `NSButton` checkbox, because every control in this
/// window's chrome is drawn in the theme's ink and a row of system checkboxes
/// in a panel that otherwise looks like `StyledTip` would look like a dialog.
/// **The whole row is the click target**: a box thirteen points wide is not one.
private final class TaskRowView: NSView {
	var words: NSAttributedString?
	var colour: NSColor = .controlAccentColor
	/// The row just ticked: its box is drawn filled, and its words carry *Undo*.
	var isTicked = false
	var isUnderThePointer = false {
		didSet {
			guard isUnderThePointer != oldValue else { return }
			needsDisplay = true
		}
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let inset = Theme.current.scaled(4)
		let side = Theme.current.scaled(13)
		let gap = Theme.current.scaled(8)

		if isUnderThePointer {
			let lit = NSBezierPath(
				roundedRect: bounds.insetBy(dx: Theme.current.scaled(2), dy: 1),
				xRadius: Theme.current.scaled(4), yRadius: Theme.current.scaled(4)
			)
			Theme.current.sidebarText.withAlphaComponent(0.07).setFill()
			lit.fill()
		}

		// On the first line of the words, not in the middle of two.
		let box = NSRect(
			x: inset + Theme.current.scaled(4),
			y: inset + Theme.current.scaled(1),
			width: side, height: side
		)
		let shape = NSBezierPath(
			roundedRect: box, xRadius: Theme.current.scaled(3), yRadius: Theme.current.scaled(3)
		)
		if isTicked {
			// Filled in the card's colour, as a box just ticked is: the row
			// says it is done, and the word after the words says how to unsay it.
			colour.withAlphaComponent(0.6).setFill()
			shape.fill()
		}
		if isUnderThePointer {
			// The column's own colour, so the box reads as the thing about to
			// be pressed rather than as one more outline.
			colour.withAlphaComponent(0.25).setFill()
			shape.fill()
			colour.setStroke()
		} else {
			Theme.current.separator.setStroke()
		}
		shape.lineWidth = 1
		shape.stroke()

		guard let words else { return }
		// A ticked row keeps the trailing edge for *Undo*, so the words wrap
		// short of it rather than under it.
		let undo = isTicked ? TaskTipView.undoWords(colour: colour) : nil
		let undoWidth = undo.map { $0.size().width + gap } ?? 0
		words.draw(with: NSRect(
			x: box.maxX + gap,
			y: inset,
			width: max(0, bounds.width - box.maxX - gap - inset - undoWidth),
			height: bounds.height - inset * 2
		), options: [.usesLineFragmentOrigin, .usesFontLeading])
		if let undo {
			let size = undo.size()
			undo.draw(at: NSPoint(
				x: bounds.maxX - inset - size.width,
				y: (bounds.height - size.height) / 2
			))
		}
	}
}

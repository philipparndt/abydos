import AppKit
import AbydosKit

/// The list under the panel's running-sessions pill: every Claude Code session
/// on the machine, grouped by project, one line each, with a filter above and
/// a scroll around.
///
/// The pill answers "is anything waiting for me" from across the room; this
/// answers "where". It is drawn from `RunningSessions.shared` and nothing else
/// — no disk, no process — and it is the same list whichever window opens it,
/// because the register is the machine's rather than the window's. The window's
/// own project comes first, which is the one difference between two windows'
/// lists.
///
/// **A list, after an afternoon of use.** The first version gave every row two
/// lines and a blank, so nine sessions filled a screen and a dozen ran off the
/// popover's edge with no way to reach them. Now a row is a line, the rows
/// scroll inside a bounded height, and a field at the top narrows them as it
/// is typed into — the switcher's own shape, for the same reason.
final class RunningSessionsPopover: NSPopover, RunningSessionsHost {
	private let controller: RunningSessionsController

	init(
		firstSlugs: @escaping () -> [String],
		reach: @escaping (RunningSessions.Session) -> SessionReach,
		onChoose: @escaping (RunningSessions.Session) -> Void
	) {
		// The key is said here and nowhere else: somebody who found the list by
		// clicking the pill is exactly the person who does not know there is a
		// key for it, and the palette's own reader has just pressed it.
		controller = RunningSessionsController(
			firstSlugs: firstSlugs, reach: reach, shortcut: RunningSessionsPopover.shortcut
		)
		super.init()
		controller.onChoose = { [weak self] session in
			self?.close()
			onChoose(session)
		}
		controller.onResize = { [weak self] size in self?.contentSize = size }
		controller.onEscape = { [weak self] in self?.close() }
		contentViewController = controller
		behavior = .transient
		appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)
		reload()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// What the menu item that opens the same list is bound to, drawn in the
	/// corner of the filter row.
	static let shortcut = "\u{21E7}\u{2318}A"

	/// Reads the register again and resizes to what it holds. Called on every
	/// move while the list is open, so a session finishing under the pointer
	/// changes its row rather than going stale in it.
	func reload() {
		controller.reload()
		contentSize = controller.wantedSize
	}

	func typeFilterForTesting(_ text: String) { controller.typeFilterForTesting(text) }
	func visibleRowsForTesting() -> String { controller.visibleRowsForTesting() }
	func chooseFirstForTesting() -> String { controller.chooseFirstForTesting() }
	func pressForTesting(_ key: String) -> String { controller.pressForTesting(key) }
	func shortcutForTesting() -> String { controller.shortcutForTesting() }
}

/// The filter field over the scrolling rows, and the keys the field answers.
final class RunningSessionsController: NSViewController, NSSearchFieldDelegate {
	var onChoose: ((RunningSessions.Session) -> Void)?
	var onResize: ((NSSize) -> Void)?
	/// Escape, from the field or the rows: the popover puts itself away.
	var onEscape: (() -> Void)?

	private let list: RunningSessionsListView
	/// The key that opens this list, shown dimmed at the trailing edge of the
	/// filter row — or nil where saying it would be telling somebody what they
	/// just did.
	private let shortcut: String?
	private var field: ScaledSearchField!
	private var scroll: NSScrollView!
	private var shortcutLabel: NSTextField?
	private var widthConstraint: NSLayoutConstraint?
	private var heightConstraint: NSLayoutConstraint?

	/// The rows scroll past this; a dozen sessions are a dozen rows, not a
	/// screen.
	private var listCeiling: CGFloat { Theme.current.scaled(400) }

	init(
		firstSlugs: @escaping () -> [String],
		reach: @escaping (RunningSessions.Session) -> SessionReach,
		shortcut: String? = nil
	) {
		self.shortcut = shortcut
		list = RunningSessionsListView(firstSlugs: firstSlugs, reach: reach)
		super.init(nibName: nil, bundle: nil)
		list.onChoose = { [weak self] session in self?.onChoose?(session) }
		list.onLeaveTop = { [weak self] in self?.takeKeyboardBackToFilter() }
		list.onEscape = { [weak self] in self?.onEscape?() }
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func loadView() {
		let container = NSView()
		container.wantsLayer = true
		// The list's own ground behind the field as well, or the popover's
		// default grey shows around it.
		container.layer?.backgroundColor = Theme.current.sidebarBackground.cgColor

		let field = ScaledSearchField(placeholder: "Filter sessions", fontSize: 11)
		field.delegate = self
		field.translatesAutoresizingMaskIntoConstraints = false
		self.field = field

		let scroll = NSScrollView()
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.documentView = list
		scroll.translatesAutoresizingMaskIntoConstraints = false
		self.scroll = scroll

		container.addSubview(field)
		container.addSubview(scroll)

		// The key in the corner, in the shape the titlebar capsule says ⇧⌘P in:
		// dimmed, small, and out of the way of the sessions, which are what
		// somebody opened this to read.
		var fieldTrailing: NSLayoutConstraint?
		if let shortcut {
			let label = NSTextField(labelWithString: shortcut)
			label.font = Theme.current.uiFont(10)
			label.textColor = Theme.current.sidebarText.withAlphaComponent(0.45)
			label.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(label)
			self.shortcutLabel = label
			NSLayoutConstraint.activate([
				label.centerYAnchor.constraint(equalTo: field.centerYAnchor),
				label.trailingAnchor.constraint(
					equalTo: container.trailingAnchor, constant: -Theme.current.scaled(12)
				),
			])
			fieldTrailing = field.trailingAnchor.constraint(
				equalTo: label.leadingAnchor, constant: -Theme.current.scaled(8)
			)
		}
		// The container's own size, held by constraints the reload updates: a
		// popover sizes its window to the view's fitting size, and a scroll
		// view has none, so without these the window shrank to the field's
		// magnifier and nothing else.
		let width = container.widthAnchor.constraint(equalToConstant: wantedSize.width)
		let height = container.heightAnchor.constraint(equalToConstant: wantedSize.height)
		// Just under required, because the palette's window pins this same view
		// to its own frame: the two agree, since the window is sized from
		// `wantedSize`, and a rounding apart from each other should bend rather
		// than fill the log with a conflict nobody can act on.
		width.priority = .init(999)
		height.priority = .init(999)
		widthConstraint = width
		heightConstraint = height
		let inset = Theme.current.scaled(10)
		NSLayoutConstraint.activate([
			width, height,
			field.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
			field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
			fieldTrailing
				?? field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
			scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: Theme.current.scaled(6)),
			scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		view = container
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		focusFilter()
	}

	/// The theme, again, on a controller that is kept between openings.
	///
	/// The container's ground is set when the view is made, and the palette's
	/// view is made once for the life of the window.
	func applyTheme() {
		view.wantsLayer = true
		view.layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		shortcutLabel?.textColor = Theme.current.sidebarText.withAlphaComponent(0.45)
	}

	/// Gives the filter the keyboard, with whatever is in it selected.
	///
	/// Called on every opening rather than only on the first: the palette keeps
	/// its window and its controller between openings, so `viewDidAppear` is
	/// not to be relied on for the second one. What was typed last time is
	/// selected rather than cleared, so the next letter replaces it and ⌫ is
	/// not needed to start again — a palette's own habit.
	func focusFilter() {
		guard let window = view.window else { return }
		window.makeFirstResponder(field)
		field.currentEditor()?.selectAll(nil)
	}

	/// The field's height, the gap, and the rows up to the ceiling.
	var wantedSize: NSSize {
		let fieldHeight = field?.fittingSize.height ?? Theme.current.scaled(24)
		let rows = min(list.wantedSize.height, listCeiling)
		return NSSize(
			width: list.wantedSize.width,
			height: Theme.current.scaled(10) + fieldHeight + Theme.current.scaled(6) + rows
		)
	}

	func reload() {
		list.reload()
		let size = wantedSize
		widthConstraint?.constant = size.width
		heightConstraint?.constant = size.height
		preferredContentSize = size
		onResize?(size)
	}

	// MARK: - The field

	func controlTextDidChange(_ notification: Notification) {
		list.filter = field.stringValue
		reload()
	}

	/// ⏎ in the field chooses the first row still shown, so a filter typed
	/// down to one session is one key from it; ↓ hands the keyboard to the rows
	/// with the first of them selected, which is the way out of the field.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			// The row that is lit, and the first one when none is: with a
			// selection restored from the last time the list was open, the
			// highlight is a promise about what ⏎ does.
			if let session = list.selectedSession ?? list.firstVisibleSession { onChoose?(session) }
			return true
		case #selector(NSResponder.moveDown(_:)):
			return list.selectFirst()
		default:
			return false
		}
	}

	/// The rows handing the keyboard back, from ↑ off the top.
	///
	/// The caret goes to the end of what was typed rather than selecting it
	/// all: somebody moving back up to the filter is adding a letter, and a
	/// selected field would replace what they had narrowed to.
	private func takeKeyboardBackToFilter() {
		guard let window = view.window else { return }
		window.makeFirstResponder(field)
		field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
	}

	// MARK: - For the harness

	func typeFilterForTesting(_ text: String) {
		field.stringValue = text
		list.filter = text
		reload()
	}

	func visibleRowsForTesting() -> String { list.visibleRowsForTesting() }

	/// A fresh opening decides a fresh order; see `freezeOrderAgain`.
	func freezeOrderAgain() { list.freezeOrderAgain() }

	func shortcutForTesting() -> String { shortcutLabel?.stringValue ?? "" }

	/// Presses one key where the keyboard is, and says where it went.
	func pressForTesting(_ key: String) -> String {
		if view.window?.firstResponder === field, key == "down" {
			_ = control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
		} else if let arrow = TreeKeys.arrow(key) {
			TreeKeys.press(arrow.code, arrow.scalar, in: view.window)
		} else if key == "return" {
			TreeKeys.press(36, "\r", in: view.window)
		} else if key == "wait" {
			// A real second of the app's own life: the staleness clock ticks,
			// a session scheduled to start arrives, and the list is rebuilt
			// underneath whatever the keys just did. That rebuild is the thing
			// being asked about, so it has to actually happen.
			RunLoop.main.run(until: Date().addingTimeInterval(1.2))
		}
		return list.keyboardReportForTesting + " filter=\(field.stringValue)"
	}

	func chooseFirstForTesting() -> String {
		guard let first = list.firstVisibleSession else { return "nothing shown" }
		onChoose?(first)
		return RunningSessionsListView.title(of: first)
	}
}

/// The rows themselves: a header per project, a line per session, a line at
/// the foot saying how many.
///
/// Drawn rather than built from table views, the way the strip above it draws
/// its tabs: there are three kinds of row and none of them is edited, and one
/// `draw` that reads the theme where it is used is how everything else in this
/// panel stays right when the zoom moves.
final class RunningSessionsListView: NSView {
	var onChoose: ((RunningSessions.Session) -> Void)?

	/// What is typed into the field: a row stays when its project, its window
	/// name or its last line contains it, and a group with no rows left goes.
	var filter = ""

	private let firstSlugs: () -> [String]
	private let reach: (RunningSessions.Session) -> SessionReach

	private enum Row {
		case header(RunningSessions.Group)
		case session(RunningSessions.Session, SessionReach)
		case footer(shown: Int, total: Int)
	}

	private var rows: [(row: Row, frame: NSRect)] = []
	private var hovered: Int?
	/// Which row the keyboard is on, as an index into `rows`.
	///
	/// Kept by the session's id across a reload rather than by index: the list
	/// is rebuilt from the register on every event, and an index into a rebuilt
	/// array is a different row. Nil until ↓ out of the filter puts it on the
	/// first session.
	private var selected: Int?
	/// Told when ↑ walks off the top, so the field can take the keyboard back.
	var onLeaveTop: (() -> Void)?
	/// Told when Escape is pressed, so the popover can put itself away.
	var onEscape: (() -> Void)?
	/// The order the list came up in, kept for as long as it is open: a
	/// session's id to its place, and a project's slug to its.
	///
	/// **A list that reorders itself under a pointer cannot be used.** The
	/// order is a good one — where a session is, never when it spoke — but it
	/// is computed from data that arrives while somebody is reading: a session
	/// learns its tmux window and moves out of the windowless tail, a session
	/// in another project appears and its group takes its place by name, the
	/// mirror seeds a badged window and drops it again. Each of those is a row
	/// moving, and the highlight travels with its session, which is what the
	/// report "the selection is still jumping around" describes.
	///
	/// So the order is decided once, when the list opens, and held. Whatever
	/// arrives afterwards goes at the end, where it can be seen to have
	/// arrived. Reopening the list computes it again — that is the moment a
	/// fresh order costs nobody anything.
	private var placeOfSession: [String: Int] = [:]
	private var placeOfGroup: [String: Int] = [:]
	/// The place a tmux window's row has, whichever record is speaking for it.
	///
	/// **A row can change its id without moving.** The register seeds a record
	/// for a badged tmux window the hook has not spoken for yet, keyed by the
	/// window; the moment that session announces itself, the seeded record is
	/// dropped and the real one takes its place — a different id for the same
	/// window, in the same project. Keyed by id alone, that reads as one row
	/// leaving the middle and another arriving at the end, which is a row
	/// jumping about at the exact moment a session starts working.
	private var placeOfWindow: [String: Int] = [:]
	private var nextPlace = 0
	/// The last shape the rows had, so a change of order can be *logged* rather
	/// than theorised about: this has now been reported three times, and each
	/// answer was written from a reading of the code rather than from a record
	/// of what actually moved. `~/Library/Logs/Abydos/sessions.log`.
	private var lastShape: [String] = []
	private var now = Date()
	private var trackingArea: NSTrackingArea?

	/// How far round the working rows' spinners are, and the timer that turns
	/// them. Its own timer and not the panel's one-second clock: that one is
	/// for believing a session, and a spinner wants twelve frames a second.
	/// It exists only while a row is turning, and only the badges are redrawn —
	/// redrawing a list of a dozen rows twelve times a second to turn three
	/// little marks would be as silly here as it is on the strip.
	private var spinnerPhase: CGFloat = 0
	private var spinnerTimer: Timer?

	override var isFlipped: Bool { true }

	private var width: CGFloat { Theme.current.scaled(440) }
	private var headerHeight: CGFloat { Theme.current.scaled(24) }
	private var rowHeight: CGFloat { Theme.current.scaled(22) }
	private var footerHeight: CGFloat { Theme.current.scaled(24) }
	private var inset: CGFloat { Theme.current.scaled(14) }
	private var badgeSize: CGFloat { Theme.current.scaled(12) }

	init(
		firstSlugs: @escaping () -> [String],
		reach: @escaping (RunningSessions.Session) -> SessionReach
	) {
		self.firstSlugs = firstSlugs
		self.reach = reach
		super.init(frame: .zero)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// What the whole list wants to be, for the scroll view and the popover.
	var wantedSize: NSSize {
		NSSize(width: width, height: (rows.last?.frame.maxY ?? 0) + Theme.current.scaled(6))
	}

	/// The first session still shown, which is what ⏎ chooses.
	var firstVisibleSession: RunningSessions.Session? {
		for entry in rows {
			if case let .session(session, _) = entry.row { return session }
		}
		return nil
	}

	// MARK: - The selection and the keys

	/// The session the keyboard is on, if any.
	var selectedSession: RunningSessions.Session? {
		guard let selected, rows.indices.contains(selected),
		      case let .session(session, _) = rows[selected].row
		else { return nil }
		return session
	}

	private func firstSessionRow() -> Int? {
		rows.indices.first { if case .session = rows[$0].row { return true } else { return false } }
	}

	private func index(ofSessionWith identity: String) -> Int? {
		rows.indices.first {
			guard case let .session(session, _) = rows[$0].row else { return false }
			return session.identity == identity
		}
	}

	/// Puts the selection on the first session and asks for the keyboard, which
	/// is what ↓ in the filter means.
	@discardableResult
	func selectFirst() -> Bool {
		guard let first = firstSessionRow() else { return false }
		selected = first
		window?.makeFirstResponder(self)
		show(row: first)
		return true
	}

	/// Moves the selection by one session, skipping the headers and the footer:
	/// they are rows in the same array and the arrows must not land where ⏎ has
	/// nothing to do.
	///
	/// - Returns: false when there is nowhere to go, which above the first row
	///   means the filter takes the keyboard back.
	@discardableResult
	func moveSelection(by step: Int) -> Bool {
		guard !rows.isEmpty else { return false }
		guard let from = selected else { return selectFirst() }
		var index = from + step
		while rows.indices.contains(index) {
			if case .session = rows[index].row {
				selected = index
				show(row: index)
				return true
			}
			index += step
		}
		return false
	}

	private func show(row: Int) {
		needsDisplay = true
		guard rows.indices.contains(row) else { return }
		scrollToVisible(rows[row].frame.insetBy(dx: 0, dy: -Theme.current.scaled(6)))
	}

	override var acceptsFirstResponder: Bool { true }

	/// Whether the arrows and ⏎ would land here rather than in the filter.
	///
	/// The selection is drawn brightly only then. Reopening the list restores
	/// the row it was left on while the keyboard starts in the filter, and a
	/// row lit as though a key would act on it — while the caret blinks
	/// somewhere else — is the confusion that asked for this: a bright row and
	/// a live caret both claiming the next keystroke.
	private var rowsHaveTheKeyboard: Bool { window?.firstResponder === self }

	override func becomeFirstResponder() -> Bool {
		if selected == nil { selected = firstSessionRow() }
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		switch event.keyCode {
		case 125: moveSelection(by: 1)
		case 126:
			// Off the top is back to the filter: narrowing and choosing are one
			// movement in each direction.
			if !moveSelection(by: -1) { onLeaveTop?() }
		case 36, 76:
			guard let session = selectedSession else { return }
			onChoose?(session)
		case 53: onEscape?()
		default: super.keyDown(with: event)
		}
	}

	/// Where the keyboard is and what it is on, for a driven run.
	var keyboardReportForTesting: String {
		let holder = window?.firstResponder === self ? "the rows" : TreeKeys.keyboardHolder(in: window)
		let row = selectedSession.map { "\(Self.title(of: $0)) [\($0.identity.suffix(6))]" } ?? "nothing"
		let under = hovered.flatMap { index -> String? in
			guard rows.indices.contains(index), case let .session(session, _) = rows[index].row
			else { return "row \(index)" }
			return Self.title(of: session)
		} ?? "nothing"
		return "keyboard=\(holder) selected=\(row) hovered=\(under)"
	}

	/// Forgets the order that was being held, so the next reload decides a new
	/// one. Called when the list is opened.
	func freezeOrderAgain() {
		placeOfSession.removeAll()
		placeOfGroup.removeAll()
		placeOfWindow.removeAll()
		nextPlace = 0
		lastShape.removeAll()
	}

	/// Where a session's row goes, decided once and remembered.
	private func place(of session: RunningSessions.Session) -> Int {
		let windowKey = session.tmuxSession.flatMap { name in
			session.window.map { "\(name):\($0)" }
		}
		if let known = placeOfSession[session.identity] {
			// Learnt where it is since it was first placed, so the window can
			// hand the place on if this record is ever replaced.
			if let windowKey, placeOfWindow[windowKey] == nil { placeOfWindow[windowKey] = known }
			return known
		}
		if let windowKey, let inherited = placeOfWindow[windowKey] {
			placeOfSession[session.identity] = inherited
			return inherited
		}
		let place = nextPlace
		nextPlace += 1
		placeOfSession[session.identity] = place
		if let windowKey { placeOfWindow[windowKey] = place }
		return place
	}

	/// The register's order the first time, and the order already on screen
	/// every time after it.
	private func held(_ groups: [RunningSessions.Group]) -> [RunningSessions.Group] {
		for group in groups where placeOfGroup[group.slug] == nil {
			placeOfGroup[group.slug] = placeOfGroup.count
		}
		var held: [RunningSessions.Group] = []
		for group in groups {
			// Placed before sorting, in the register's own order, so that the
			// first reading after the list opens is that order exactly.
			let places = group.sessions.map { ($0, place(of: $0)) }
			held.append(group.ordered(
				places.sorted { ($0.1, $0.0.identity) < ($1.1, $1.0.identity) }.map(\.0)
			))
		}
		return held.sorted {
			(placeOfGroup[$0.slug] ?? 0, $0.slug) < (placeOfGroup[$1.slug] ?? 0, $1.slug)
		}
	}

	func reload() {
		now = Date()
		let groups = held(RunningSessions.shared.grouped(firstSlugs: firstSlugs(), at: now))
		let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
		var placed: [(row: Row, frame: NSRect)] = []
		var y = Theme.current.scaled(4)
		var shown = 0
		for group in groups {
			let kept = group.sessions.filter { Self.matches($0, in: group, needle: needle, at: now) }
			guard !kept.isEmpty else { continue }
			placed.append((.header(group), NSRect(x: 0, y: y, width: width, height: headerHeight)))
			y += headerHeight
			for session in kept {
				placed.append((.session(session, reach(session)), NSRect(x: 0, y: y, width: width, height: rowHeight)))
				y += rowHeight
				shown += 1
			}
			y += Theme.current.scaled(4)
		}
		let total = groups.reduce(0) { $0 + $1.sessions.count }
		placed.append((.footer(shown: shown, total: total), NSRect(x: 0, y: y, width: width, height: footerHeight)))
		let wasSelected = selectedSession?.identity
		rows = placed
		// **Both highlights are re-found, never carried over as numbers.** A
		// row's index means nothing across a rebuild: this list is rebuilt on
		// every hook event and once a second by the staleness clock, and a
		// session appearing or ending renumbers everything after it. Kept as
		// numbers, the two lit rows moved to whatever now sat at those numbers
		// — reported as the selection jumping about on its own.
		//
		// The selection is re-found by the session's id, and dropped when the
		// row it was on is gone rather than left pointing at a stranger.
		selected = wasSelected.flatMap { index(ofSessionWith: $0) ?? firstSessionRow() }
		// The hover is re-found from where the pointer actually is. Nothing
		// tells a view that the thing under a motionless pointer has changed,
		// so `mouseMoved` never corrects this on its own.
		hovered = rowUnderPointer()
		setFrameSize(wantedSize)
		needsDisplay = true
		syncSpinner()
		sayIfTheShapeChanged()
	}

	/// Writes a line whenever the rows are not what they were, and nothing at
	/// all while they hold still.
	///
	/// The order was reported as unstable three times over, and each time the
	/// cause was worked out by reading rather than observed: recency in the
	/// sort, then indices kept across a rebuild, then the order being recomputed
	/// from data that keeps arriving. A log costs nothing while the list is
	/// shut, and turns the fourth report into evidence.
	private func sayIfTheShapeChanged() {
		guard window != nil else { return }
		let shape = rows.compactMap { entry -> String? in
			guard case let .session(session, _) = entry.row else { return nil }
			return String(session.identity.suffix(6))
		}
		guard shape != lastShape else { return }
		DiagnosticLog.write(
			"rows \(lastShape.joined(separator: " ")) -> \(shape.joined(separator: " "))",
			to: "sessions"
		)
		lastShape = shape
	}

	/// Turning while a row is working, stopped otherwise — the shape the tab
	/// strip's own spinner keeps, for the same reason: an idle list is idle.
	private func syncSpinner() {
		let wanted = rows.contains { entry in
			guard case let .session(session, _) = entry.row else { return false }
			return session.shown(at: now) == .working
		}
		if wanted, spinnerTimer == nil {
			spinnerTimer = Timer.scheduledTimer(withTimeInterval: Spinner.interval, repeats: true) { [weak self] _ in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.spinnerPhase += 1
					// Only the badges: the rest of the row has not moved.
					for entry in self.rows {
						guard case let .session(session, _) = entry.row,
						      session.shown(at: self.now) == .working
						else { continue }
						self.setNeedsDisplay(self.badgeRect(in: entry.frame))
					}
				}
			}
			// A popover's tracking mode is its own; the strip's spinner keeps
			// turning through a menu for the same reason.
			RunLoop.main.add(spinnerTimer!, forMode: .common)
		} else if !wanted {
			spinnerTimer?.invalidate()
			spinnerTimer = nil
		}
	}

	deinit { spinnerTimer?.invalidate() }

	/// Where a row's badge is, which is all a spinner redraws.
	private func badgeRect(in frame: NSRect) -> NSRect {
		NSRect(x: inset, y: frame.midY - badgeSize / 2, width: badgeSize, height: badgeSize)
	}

	private static func matches(
		_ session: RunningSessions.Session, in group: RunningSessions.Group, needle: String, at now: Date
	) -> Bool {
		guard !needle.isEmpty else { return true }
		return name(of: group).lowercased().contains(needle)
			|| title(of: session).lowercased().contains(needle)
			|| subtitle(of: session, at: now).lowercased().contains(needle)
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()

		for (index, entry) in rows.enumerated() {
			switch entry.row {
			case .header(let group): drawHeader(group, in: entry.frame, isFirst: index == 0)
			case .session(let session, let reach):
				drawSession(
					session, reach: reach, in: entry.frame,
					isHovered: index == hovered, isSelected: index == selected
				)
			case .footer(let shown, let total): drawFooter(shown: shown, total: total, in: entry.frame)
			}
		}
	}

	private func drawHeader(_ group: RunningSessions.Group, in frame: NSRect, isFirst: Bool) {
		if !isFirst {
			Theme.current.separator.setFill()
			NSRect(x: inset, y: frame.minY, width: frame.width - inset * 2, height: 1).fill()
		}
		let name = Self.text(
			Self.name(of: group), Theme.current.uiFont(11, weight: .semibold), Theme.current.sidebarText
		)
		let place = Self.text(
			Self.parent(of: group), Theme.current.uiFont(10), Theme.current.sidebarHeaderText
		)
		let baseline = frame.midY + Theme.current.scaled(2)
		let nameSize = name.size()
		name.draw(at: NSPoint(x: inset, y: baseline - nameSize.height / 2))
		let placeSize = place.size()
		let placeLeft = max(inset + nameSize.width + Theme.current.scaled(10), frame.maxX - inset - placeSize.width)
		place.draw(
			with: NSRect(
				x: placeLeft, y: baseline - placeSize.height / 2,
				width: frame.maxX - inset - placeLeft, height: placeSize.height
			),
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
		)
	}

	/// One line: badge, name, the last line dimmed after it, then the reach's
	/// word and the age at the right. A session the app cannot reach is drawn
	/// in the dim ink throughout, so it reads as out of reach before it is
	/// clicked.
	private func drawSession(
		_ session: RunningSessions.Session, reach: SessionReach, in frame: NSRect,
		isHovered: Bool, isSelected: Bool
	) {
		// **Two questions, two answers.** The hover tint is a hint about the
		// pointer; the selection is the row a key will act on, and it takes the
		// palette's own selection colour. With the pointer resting on one row
		// and the selection on another, the list has to say which is which.
		//
		// **And a third state: selected while the filter has the keyboard.** The
		// list is reopened on the row it was left on, and a filled row there
		// claims the next keystroke that the caret in the field is going to
		// take. Drawn as a ring rather than a second fill: two fills a shade
		// apart cannot be told from the hover tint — and the pointer resting on
		// one row while another is remembered is the ordinary case, not a
		// corner — while an outline says "remembered, and not where the keys
		// are" in any palette, without a colour being invented for it.
		if isSelected || isHovered {
			let band = NSBezierPath(
				roundedRect: frame.insetBy(dx: Theme.current.scaled(6), dy: Theme.current.scaled(1)),
				xRadius: Theme.current.scaled(4), yRadius: Theme.current.scaled(4)
			)
			if isSelected, !rowsHaveTheKeyboard {
				Theme.current.selectionBackground.setStroke()
				band.lineWidth = Theme.current.scaled(1.2)
				band.stroke()
			} else {
				(isSelected ? Theme.current.selectionBackground : Theme.current.selectionBackgroundInactive).setFill()
				band.fill()
			}
		}

		let shown = session.shown(at: now)
		let badge = badgeRect(in: frame)
		drawBadge(shown, in: badge, dimmed: !reach.isReachable)

		// Dimmed text ink, not the header ink: in this theme the header ink is
		// the brighter of the two, and a row drawn in it read as the one to look
		// at rather than the one out of reach.
		let dim = Theme.current.sidebarText.withAlphaComponent(0.55)
		let small = Theme.current.uiFont(10)
		let age = Self.text(Self.age(of: session, at: now), small, dim)
		let ageSize = age.size()
		var right = frame.maxX - inset
		age.draw(at: NSPoint(x: right - ageSize.width, y: frame.midY - ageSize.height / 2))
		right -= ageSize.width
		if let tag = reach.tag {
			let word = Self.text(tag, small, dim)
			let size = word.size()
			right -= Theme.current.scaled(10) + size.width
			word.draw(at: NSPoint(x: right, y: frame.midY - size.height / 2))
		}

		let ink: NSColor = !reach.isReachable
			? dim
			: shown == .needsInput ? PanelTabStrip.colour(for: .needsInput) : Theme.current.sidebarText
		let title = Self.text(Self.title(of: session), Theme.current.uiFont(11, weight: .medium), ink)
		let rest = Self.trailing(of: session, at: now)
		let line = NSMutableAttributedString(attributedString: title)
		if !rest.isEmpty {
			line.append(Self.text("  ·  " + rest, Theme.current.uiFont(10), dim))
		}
		let left = badge.maxX + Theme.current.scaled(8)
		let height = line.size().height
		line.draw(
			with: NSRect(x: left, y: frame.midY - height / 2, width: right - Theme.current.scaled(10) - left, height: height),
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
		)
	}

	/// The tabs' own marks, so a row and the tab it is about say the same
	/// thing in the same alphabet; a hollow ring for a session nothing is
	/// known about; and all of it dimmed for a session out of reach.
	private func drawBadge(_ shown: RunningSessions.Session.Shown, in rect: NSRect, dimmed: Bool) {
		let status: TmuxMirror.AIStatus?
		switch shown {
		case .working: status = .working
		case .needsInput: status = .needsInput
		case .done: status = .done
		case .unknown: status = nil
		}
		if let status {
			let colour = dimmed ? Theme.current.sidebarHeaderText : PanelTabStrip.colour(for: status)
			// A working session turns, as its tmux tab does. The still `⋯` the
			// tabs replaced for this reason was drawn here too, so the pill
			// counted a session as working while the row beside it looked
			// asleep — reported 2026-09-03.
			if status == .working {
				Spinner.draw(in: rect, phase: spinnerPhase, colour: colour)
			} else {
				Theme.symbol(
					PanelTabStrip.symbol(for: status),
					size: 11 * Theme.current.scale,
					color: colour,
					weight: .semibold
				)?.drawFitted(in: rect)
			}
		} else {
			let ring = NSBezierPath(ovalIn: rect.insetBy(dx: Theme.current.scaled(2.5), dy: Theme.current.scaled(2.5)))
			ring.lineWidth = Theme.current.scaled(1.2)
			Theme.current.sidebarHeaderText.setStroke()
			ring.stroke()
		}
	}

	private func drawFooter(shown: Int, total: Int, in frame: NSRect) {
		Theme.current.separator.setFill()
		NSRect(x: inset, y: frame.minY, width: frame.width - inset * 2, height: 1).fill()
		let words: String
		if total == 0 {
			words = "No Claude session is running on this machine"
		} else if shown < total {
			words = "\(shown) of \(total) \(total == 1 ? "session" : "sessions") match"
		} else {
			words = "\(total) \(total == 1 ? "session" : "sessions") on this machine"
		}
		let label = Self.text(words, Theme.current.uiFont(10), Theme.current.sidebarHeaderText)
		let size = label.size()
		label.draw(at: NSPoint(x: inset, y: frame.midY + Theme.current.scaled(2) - size.height / 2))
		// What a click does, said once at the foot rather than on every row —
		// and not at all when there is nothing to click. With no session
		// running, the two halves met in the middle and read as one sentence:
		// "No Claude session is running on this machine elsewhere copies the
		// resume command". Only the key can reach that state, since the pill
		// the popover hangs from is absent when nothing runs.
		guard total > 0 else { return }
		let hint = Self.text("elsewhere copies the resume command", Theme.current.uiFont(10), Theme.current.sidebarHeaderText)
		let hintSize = hint.size()
		hint.draw(at: NSPoint(x: frame.maxX - inset - hintSize.width, y: frame.midY + Theme.current.scaled(2) - hintSize.height / 2))
	}

	// MARK: - The words

	private static func text(_ string: String, _ font: NSFont, _ colour: NSColor) -> NSAttributedString {
		NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: colour])
	}

	/// The project's own name, which a slug is not.
	static func name(of group: RunningSessions.Group) -> String {
		let name = URL(fileURLWithPath: group.cwd).lastPathComponent
		return name.isEmpty ? group.slug : name
	}

	/// Where it is, home-relative.
	static func parent(of group: RunningSessions.Group) -> String {
		(URL(fileURLWithPath: group.cwd).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
	}

	/// The tmux window when the hook could say it — the name a person knows the
	/// session by — and otherwise its last line, and failing that the fact.
	static func title(of session: RunningSessions.Session) -> String {
		if let window = session.window {
			let name = session.windowName ?? ""
			return name.isEmpty ? "window \(window)" : "\(window) \(name)"
		}
		if let line = session.line, !line.isEmpty { return line }
		return "A session that has said nothing yet"
	}

	/// What the session is doing, in the tabs' words, and what it last said.
	static func subtitle(of session: RunningSessions.Session, at now: Date) -> String {
		var pieces: [String] = []
		switch session.shown(at: now) {
		case .working: pieces.append("working")
		case .needsInput: pieces.append("needs you")
		case .done: pieces.append("finished")
		case .unknown:
			pieces.append(session.status == .working
				? "was working · silent for \(age(of: session, at: now))"
				: "has said nothing yet")
		}
		// Beside the state, so the fuller sentence the driven report and the
		// filter read carries it too — typing `subagent` then finds them.
		if session.subagents > 0 {
			pieces.append(session.subagents == 1 ? "1 subagent" : "\(session.subagents) subagents")
		}
		// The line is the title already when there is no window to be one.
		if session.window != nil, let line = session.line, !line.isEmpty { pieces.append(line) }
		if let message = session.message, !message.isEmpty, message != session.line { pieces.append(message) }
		return pieces.joined(separator: " · ")
	}

	/// What follows the title on the one line: the subtitle, less the state
	/// word the badge already says, unless the state is all there is.
	static func trailing(of session: RunningSessions.Session, at now: Date) -> String {
		var pieces: [String] = []
		// A session that has sent work off looks exactly like one working alone
		// without this. Nought is not drawn: a count of none is not news.
		if session.subagents > 0 {
			pieces.append(session.subagents == 1 ? "1 subagent" : "\(session.subagents) subagents")
		}
		if session.shown(at: now) == .unknown {
			pieces.append(session.status == .working
				? "silent for \(age(of: session, at: now))"
				: "has said nothing yet")
		}
		if session.window != nil, let line = session.line, !line.isEmpty { pieces.append(line) }
		if let message = session.message, !message.isEmpty, message != session.line { pieces.append(message) }
		return pieces.joined(separator: " · ")
	}

	/// How long since the hook last spoke for it.
	static func age(of session: RunningSessions.Session, at now: Date) -> String {
		let seconds = max(0, now.timeIntervalSince(session.lastEvent))
		switch seconds {
		case ..<60: return "\(Int(seconds)) s"
		case ..<3600: return "\(Int(seconds / 60)) min"
		case ..<86400: return "\(Int(seconds / 3600)) h"
		default: return "\(Int(seconds / 86400)) d"
		}
	}

	/// The list in one line, for a driven run to read: each row with its
	/// state, its title, what follows, and where the app can reach it.
	static func describe(
		_ groups: [RunningSessions.Group],
		reach: (RunningSessions.Session) -> SessionReach,
		at now: Date
	) -> String {
		"groups=[" + groups.map { group in
			name(of: group) + ": " + group.sessions.map { session in
				"{\(session.shown(at: now).rawValue) \(title(of: session)) · \(subtitle(of: session, at: now)) · \(reach(session).word)}"
			}.joined(separator: " ")
		}.joined(separator: " | ") + "]"
	}

	/// The rows as shown, after the filter.
	func visibleRowsForTesting() -> String {
		rows.compactMap { entry -> String? in
			guard case let .session(session, reach) = entry.row else { return nil }
			return "\(Self.title(of: session)) · \(reach.word)"
		}.joined(separator: " | ")
	}

	// MARK: - The pointer

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	/// Which session row the pointer is over right now, asked of the window
	/// rather than of the last event: after a rebuild there has been no event.
	private func rowUnderPointer() -> Int? {
		guard let window, window.isVisible else { return nil }
		let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
		guard bounds.contains(point) else { return nil }
		return sessionRow(at: point)
	}

	private func sessionRow(at point: NSPoint) -> Int? {
		rows.firstIndex { entry in
			if case .session = entry.row { return entry.frame.contains(point) }
			return false
		}
	}

	override func mouseMoved(with event: NSEvent) {
		let index = sessionRow(at: convert(event.locationInWindow, from: nil))
		guard index != hovered else { return }
		hovered = index
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent) {
		hovered = nil
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		guard let index = sessionRow(at: convert(event.locationInWindow, from: nil)),
		      case let .session(session, _) = rows[index].row
		else { return }
		onChoose?(session)
	}
}

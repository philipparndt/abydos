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
final class RunningSessionsPopover: NSPopover {
	private let controller: RunningSessionsController

	init(
		firstSlugs: @escaping () -> [String],
		reach: @escaping (RunningSessions.Session) -> SessionReach,
		onChoose: @escaping (RunningSessions.Session) -> Void
	) {
		controller = RunningSessionsController(firstSlugs: firstSlugs, reach: reach)
		super.init()
		controller.onChoose = { [weak self] session in
			self?.close()
			onChoose(session)
		}
		controller.onResize = { [weak self] size in self?.contentSize = size }
		contentViewController = controller
		behavior = .transient
		appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)
		reload()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

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
}

/// The filter field over the scrolling rows, and the keys the field answers.
final class RunningSessionsController: NSViewController, NSSearchFieldDelegate {
	var onChoose: ((RunningSessions.Session) -> Void)?
	var onResize: ((NSSize) -> Void)?

	private let list: RunningSessionsListView
	private var field: ScaledSearchField!
	private var scroll: NSScrollView!
	private var widthConstraint: NSLayoutConstraint?
	private var heightConstraint: NSLayoutConstraint?

	/// The rows scroll past this; a dozen sessions are a dozen rows, not a
	/// screen.
	private var listCeiling: CGFloat { Theme.current.scaled(400) }

	init(
		firstSlugs: @escaping () -> [String],
		reach: @escaping (RunningSessions.Session) -> SessionReach
	) {
		list = RunningSessionsListView(firstSlugs: firstSlugs, reach: reach)
		super.init(nibName: nil, bundle: nil)
		list.onChoose = { [weak self] session in self?.onChoose?(session) }
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
		// The container's own size, held by constraints the reload updates: a
		// popover sizes its window to the view's fitting size, and a scroll
		// view has none, so without these the window shrank to the field's
		// magnifier and nothing else.
		let width = container.widthAnchor.constraint(equalToConstant: wantedSize.width)
		let height = container.heightAnchor.constraint(equalToConstant: wantedSize.height)
		widthConstraint = width
		heightConstraint = height
		let inset = Theme.current.scaled(10)
		NSLayoutConstraint.activate([
			width, height,
			field.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
			field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
			field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
			scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: Theme.current.scaled(6)),
			scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		view = container
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		// Typing filters: the field has the keyboard the moment the list is up.
		view.window?.makeFirstResponder(field)
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
	/// down to one session is one key from it.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
		if let first = list.firstVisibleSession { onChoose?(first) }
		return true
	}

	// MARK: - For the harness

	func typeFilterForTesting(_ text: String) {
		field.stringValue = text
		list.filter = text
		reload()
	}

	func visibleRowsForTesting() -> String { list.visibleRowsForTesting() }

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

	func reload() {
		now = Date()
		let groups = RunningSessions.shared.grouped(firstSlugs: firstSlugs(), at: now)
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
		rows = placed
		if let hovered, hovered >= rows.count { self.hovered = nil }
		setFrameSize(wantedSize)
		needsDisplay = true
		syncSpinner()
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
				drawSession(session, reach: reach, in: entry.frame, isHovered: index == hovered)
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
		_ session: RunningSessions.Session, reach: SessionReach, in frame: NSRect, isHovered: Bool
	) {
		if isHovered {
			Theme.current.selectionBackgroundInactive.setFill()
			NSBezierPath(
				roundedRect: frame.insetBy(dx: Theme.current.scaled(6), dy: Theme.current.scaled(1)),
				xRadius: Theme.current.scaled(4), yRadius: Theme.current.scaled(4)
			).fill()
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
		// What a click does, said once at the foot rather than on every row.
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
		// The line is the title already when there is no window to be one.
		if session.window != nil, let line = session.line, !line.isEmpty { pieces.append(line) }
		if let message = session.message, !message.isEmpty, message != session.line { pieces.append(message) }
		return pieces.joined(separator: " · ")
	}

	/// What follows the title on the one line: the subtitle, less the state
	/// word the badge already says, unless the state is all there is.
	static func trailing(of session: RunningSessions.Session, at now: Date) -> String {
		var pieces: [String] = []
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

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
	var scroll: NSScrollView!
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

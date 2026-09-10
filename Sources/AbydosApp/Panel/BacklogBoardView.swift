import AppKit
import AbydosKit

/// The board: a column a state, cards dragged between them, and the tip that
/// opens over one.
// MARK: - The board

/// One column per state, and cards that can be dragged between them.
final class BacklogBoardView: NSView {
	weak var pane: BacklogPane? {
		didSet { columns.forEach { $0.pane = pane } }
	}

	private var columns: [BacklogColumnView] = []
	private var stack: NSStackView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// The columns this board is over, which the source decides.
	///
	/// Rebuilt rather than relabelled: the two records do not have the same
	/// number of columns in general, and a column view carries the drop
	/// behaviour of the state it was made for. Nothing happens where the set is
	/// already the right one, which is every reload but the two that follow a
	/// click on the switch.
	func setColumns(_ wanted: [BoardColumn]) {
		guard wanted != columns.map(\.column) else { return }
		for column in columns {
			stack.removeArrangedSubview(column)
			column.removeFromSuperview()
		}
		columns = wanted.map { BacklogColumnView(column: $0) }
		for column in columns {
			column.pane = pane
			stack.addArrangedSubview(column)
		}
	}

	private func build() {
		columns = BacklogState.board.map { BacklogColumnView(column: .backlog($0)) }
		stack = NSStackView(views: columns)
		stack.orientation = .horizontal
		stack.distribution = .fillEqually
		stack.spacing = 1
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

		let scrollView = NSScrollView()
		scrollView.documentView = stack
		scrollView.hasHorizontalScroller = true
		scrollView.hasVerticalScroller = false
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.separator
		scrollView.scrollerStyle = .overlay

		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		stack.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

			stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
			stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			// Never narrower than five legible columns. Below that the board
			// scrolls sideways, because a kanban board squeezed to sixty points
			// a column is five lists of numbers.
			stack.widthAnchor.constraint(
				greaterThanOrEqualToConstant: Theme.current.scaled(
					CGFloat(max(BacklogState.board.count, OpenSpecState.board.count)) * 190
				)
			),
		])

		// The pane's width, and only as strongly as that.
		//
		// Required, this fights the minimum above in a narrow window and one of
		// them has to lose. Absent, the stack takes the width its columns ask
		// for — and a column asks for whatever its widest label would like,
		// which made a board that fitted easily scroll sideways anyway.
		let fit = stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
		fit.priority = .defaultHigh
		fit.isActive = true
	}

	/// The columns themselves, for a report about what each is drawing.
	var columnViewsForTesting: [BacklogColumnView] { columns }

	/// Every card the tip can open over, and where it is on the screen.
	///
	/// Screen coordinates because the only thing that reads this is a process
	/// posting mouse events, which knows nothing of anybody's views. The order
	/// is the order down each column, so "the card above the last one" — the
	/// case that was broken — can be picked without guessing.
	var inProgressCardsForTesting: String {
		var lines: [String] = []
		for view in columns {
			for (row, entry) in view.entriesForTesting.enumerated() where entry.isInProgress {
				guard let screen = view.screenRectForTesting(row: row) else { continue }
				let name: String
				switch entry.identity {
				case let .change(change): name = change
				case let .item(number):   name = String(format: "%04d", number)
				}
				lines.append(String(format: "CARD %@ %@ row=%d %.0f,%.0f,%.0f,%.0f",
					"\(view.column.key)", name, row,
					screen.minX, screen.minY, screen.width, screen.height))
			}
		}
		return lines.isEmpty ? "CARD none in progress" : lines.joined(separator: "\n")
	}

	func reload() {
		columns.forEach { $0.reload() }
	}

	func applySettings() {
		columns.forEach { $0.applySettings() }
	}
}

/// One state, with its cards.
final class BacklogColumnView: NSView {
	weak var pane: BacklogPane?
	let column: BoardColumn

	/// What a dragged card carries: the number, which is the only durable name
	/// an item has.
	static let dragType = NSPasteboard.PasteboardType("dev.abydos.backlog.item")

	private var entries: [BoardEntry] = []
	private var tableView: NSTableView!
	private var headerLabel: NSTextField!
	private var emptyLabel: NSTextField!
	/// The width the cached row heights were measured at. See `widthChanged`.
	private var measuredWidth: CGFloat = 0
	/// Where the pointer is watched from. See `updateTrackingAreas`.
	private var tracking: NSTrackingArea?

	override func layout() {
		super.layout()
		widthChanged(to: cardWidth)
	}

	// MARK: - The pointer, and the tip it opens

	/// **One tracking area, on the column, and it asks the row.**
	///
	/// Not one per card: `BacklogCardView` is a cell the table recycles, so a
	/// tracking area per card would be a tracking area per recycled view with
	/// the wrong entry in it. The column already owns the table and its
	/// entries, so it hit-tests the row under the pointer and hands the tip the
	/// entry — or tells it the pointer is on nothing.
	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let tracking { removeTrackingArea(tracking) }
		let area = NSTrackingArea(
			rect: bounds,
			// `inVisibleRect` so a column that scrolls or is resized does not
			// need the area rebuilt by hand; `activeInKeyWindow` because a
			// board in a window nobody is looking at should open nothing.
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		tracking = area
	}

	override func mouseMoved(with event: NSEvent) {
		let inTable = tableView.convert(event.locationInWindow, from: nil)
		let row = tableView.row(at: inTable)
		// Only a card somebody is in the middle of. That is one `switch` on the
		// entry's column and costs nothing per move — **the file is not read
		// until the delay has elapsed and the tip is about to open**.
		guard entries.indices.contains(row), entries[row].isInProgress else {
			return TaskTip.shared.pointerIsOnNothing()
		}
		let card = tableView.rect(ofRow: row)
		TaskTip.shared.onTicked = { [weak self] in self?.pane?.reload() }
		TaskTip.shared.onTickWritten = { [weak self] file, line, text in
			self?.pane?.registerTick(file: file, line: line, text: text)
		}
		TaskTip.shared.pointerIsOn(
			entries[row],
			at: convert(card, from: tableView),
			of: self,
			colour: BacklogPalette.colour(for: column)
		)
	}

	override func mouseExited(with event: NSEvent) {
		TaskTip.shared.pointerIsOnNothing()
	}

	var entriesForTesting: [BoardEntry] { entries }

	/// Where one card is on the screen, for a run posting pointer moves at it.
	func screenRectForTesting(row: Int) -> NSRect? {
		guard entries.indices.contains(row), let window else { return nil }
		let card = convert(tableView.rect(ofRow: row), from: tableView)
		return window.convertToScreen(convert(card, to: nil))
	}

	/// Opens the tip on a card, without the wait, for a driven run.
	///
	/// **The same hand-off `mouseMoved` makes**, down to the rectangle and the
	/// colour, so what a driver opens is what a rested pointer opens. Only the
	/// half-second is skipped: a run that waited for it would be a run whose
	/// report depended on a timer under load.
	func openTheTipForTesting(on entry: BoardEntry) {
		guard let row = entries.firstIndex(where: { $0.identity == entry.identity }) else { return }
		TaskTip.shared.onTicked = { [weak self] in self?.pane?.reload() }
		TaskTip.shared.onTickWritten = { [weak self] file, line, text in
			self?.pane?.registerTick(file: file, line: line, text: text)
		}
		TaskTip.shared.showNowForTesting(
			entry,
			at: convert(tableView.rect(ofRow: row), from: tableView),
			of: self,
			colour: BacklogPalette.colour(for: column)
		)
	}

	/// A card's context menu is about to show.
	///
	/// **Here and not in `pane.menu(for:)`**, which was where this was going to
	/// go: that is called while the table builds its rows, once per card per
	/// reload, so a `hide()` in it would close the tip every time the board
	/// walked — which is exactly the reload a tick causes. `willOpenMenu` is
	/// the menu actually opening, and it runs before the menu is on screen.
	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		TaskTip.shared.hide()
		super.willOpenMenu(menu, with: event)
	}

	/// The column scrolled, so the card the tip is under has moved out from
	/// under it.
	///
	/// Watched on the clip view rather than as `scrollWheel`, which the scroll
	/// view handles and never passes here — and which would miss a scroller
	/// dragged, a trackpad flick continuing, or the table scrolling itself.
	private func closeTheTipWhenTheColumnScrolls(_ scrollView: NSScrollView) {
		scrollView.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
		) { _ in
			MainActor.assumeIsolated { TaskTip.shared.hide() }
		}
	}

	/// The table says when its own width changed, because `layout()` is too
	/// early to ask.
	///
	/// `layout()` runs on this view, and the table lays its column out during
	/// its *own* pass afterwards — so `cardWidth` read from here is still the
	/// previous width, `widthChanged` sees no difference, and the cached row
	/// heights are never thrown away. That is invisible while a board is only
	/// ever built once, and obvious the moment somebody drags the panel to the
	/// side and back: every card keeps the height it had at the old width while
	/// its text is drawn at the new one, so titles truncate, marks land on them
	/// and the text runs outside the card altogether.
	///
	/// A frame notification fires when the width has actually changed, which is
	/// the thing being waited for. It cannot loop: `measuredWidth` tracks only
	/// the width, and re-measuring rows changes the table's *height*.
	private func watchTableWidth() {
		tableView.postsFrameChangedNotifications = true
		NotificationCenter.default.addObserver(
			forName: NSView.frameDidChangeNotification, object: tableView, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.widthChanged(to: self?.cardWidth ?? 0) }
		}
	}

	init(column: BoardColumn) {
		self.column = column
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		headerLabel = NSTextField(labelWithString: column.title.uppercased())
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: column)

		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.rowSizeStyle = .custom
		table.intercellSpacing = NSSize(width: 0, height: Theme.current.scaled(6))
		table.gridStyleMask = []
		table.selectionHighlightStyle = .none
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("card")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.doubleAction = #selector(cardDoubleClicked)
		table.registerForDraggedTypes([Self.dragType])
		table.setDraggingSourceOperationMask(.move, forLocal: true)
		tableView = table
		watchTableWidth()

		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
		// Five columns, five scrollers, four of which are usually over nothing.
		// A board is mostly whitespace by design and a permanent grey bar down
		// the side of every column is most of what the eye lands on.
		scrollView.autohidesScrollers = true
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.contentInsets = NSEdgeInsets(
			top: Theme.current.scaled(6), left: 0, bottom: Theme.current.scaled(6), right: 0
		)
		closeTheTipWhenTheColumnScrolls(scrollView)

		// What belongs in this column, for a column with nothing in it.
		//
		// An empty board is the state somebody is in on their first day with
		// one, and five unlabelled columns explain nothing. `ready` is the one
		// that matters: it is the folder an agent picks from, and the reason
		// nothing is in it is that moving something there is a decision.
		emptyLabel = NSTextField(wrappingLabelWithString: column.summary)
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		emptyLabel.alignment = .left
		emptyLabel.isSelectable = false
		// Neither label gets to decide how wide a column is. Five columns each
		// asking for the width of a sentence is a board that scrolls sideways
		// in a window twice as wide as it needs to be.
		emptyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		emptyLabel.preferredMaxLayoutWidth = Theme.current.scaled(160)
		headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		addSubview(headerLabel)
		addSubview(scrollView)
		addSubview(emptyLabel)
		headerLabel.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.current.scaled(8)),
			headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(10)),
			headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

			scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: Theme.current.scaled(6)),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

			emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Theme.current.scaled(8)),
			emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(18)),
			emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(18)),
		])
	}

	/// What the table is using for each row and what the card view was given,
	/// against what the card wants — the three that a cached height lets drift
	/// apart.
	///
	/// `uses` is `rect(ofRow:)`, which includes the intercell spacing, so it is
	/// a row taller than the card by design and compared with that allowed for.
	/// `draws` is the card view's own frame, and it is the one that matters:
	/// everything at the foot of a card — the bar above all — is measured from
	/// its bottom edge, and a view left taller than its row has that edge, and
	/// the bar on it, below the row's clip. A card whose bottom corners are
	/// square in a photograph is this, and nothing else.
	var rowHeightReportForTesting: String {
		var lines: [String] = []
		let spacing = tableView.intercellSpacing.height
		for (index, entry) in entries.enumerated() {
			let wanted = BacklogCardView.height(for: entry, width: cardWidth)
			let used = tableView.rect(ofRow: index).height - spacing
			let drawn = tableView.view(atColumn: 0, row: index, makeIfNecessary: false)?.frame.height
			let name: String
			switch entry {
			case let .item(card): name = String(format: "%04d", card.number)
			case let .change(card): name = card.name
			}
			let clipped = drawn.map { $0 - used > 0.5 } ?? false
			lines.append("    \(name): wants=\(wanted) uses=\(used)"
				+ " draws=\(drawn.map(String.init(describing:)) ?? "not made")"
				+ (abs(wanted - used) > 0.5 ? "  ← DIFFERS" : "")
				+ (clipped ? "  ← CLIPPED" : ""))
		}
		return lines.joined(separator: "\n")
	}

	func reload() {
		entries = pane?.entries(in: column) ?? []
		headerLabel.stringValue = entries.isEmpty
			? column.title.uppercased()
			: "\(column.title.uppercased())  \(entries.count)"
		emptyLabel.isHidden = !entries.isEmpty
		tableView.reloadData()
	}

	@objc private func cardDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < entries.count else { return }
		switch entries[tableView.clickedRow] {
		case let .item(card):   pane?.open(card.item)
		case let .change(card): pane?.open(card)
		}
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: column)
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		tableView.backgroundColor = Theme.current.editorBackground
		tableView.intercellSpacing = NSSize(width: 0, height: Theme.current.scaled(6))
		tableView.enclosingScrollView?.backgroundColor = Theme.current.editorBackground
	}
}

extension BacklogColumnView: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		BacklogCardView.height(for: entries[row], width: cardWidth)
	}

	/// The width a card will actually be drawn at.
	///
	/// **Not `tableView.bounds.width`**, which is what this asked before and is
	/// the width of the table *before* it has been laid out inside its scroll
	/// view. Measured: 375 against the 343 the cell then got, a difference of a
	/// scroller — enough that a title fitting one line while being measured
	/// needed two while being drawn, and the card came out a line short. The
	/// column's width is what the row is given.
	var cardWidth: CGFloat {
		let column = tableView.tableColumns.first?.width ?? 0
		return column > 0 ? column : tableView.bounds.width
	}

	/// Measured heights are only true for the width they were measured at.
	///
	/// A card's height is how many lines its title wraps to, and AppKit asks
	/// once and then caches: the first answer comes back at whatever width the
	/// table had while the board was still being laid out, and nothing asks
	/// again when the column settles. A title that wraps to two lines at the
	/// real width and one at the width it was measured at gets a card a line
	/// short — which is how a branch name came to be drawn across the second
	/// line of a title.
	///
	/// So the heights are thrown away when the width actually changes, and only
	/// then: `layout()` runs for every scroll and every reload, and telling a
	/// table its rows have all changed height is not free.
	///
	/// **The rows are reloaded rather than re-measured**, which is the
	/// difference between a card view built for the new height and one left at
	/// the old. `noteHeightOfRows` is the cheaper call and it was the one made
	/// here: it tells the table what each row is worth now, and a card view
	/// already on screen could be left at the height it was made with. A view
	/// taller than its row is clipped at the row's foot, and everything a card
	/// draws from its bottom edge — the progress bar, the rounded corners — is
	/// under that clip. Photographed, that is a card with square bottom corners
	/// and no bar, which is what was reported: the bar arrived when Refresh was
	/// pressed, and Refresh is a `reloadData`.
	func widthChanged(to width: CGFloat) {
		guard abs(width - measuredWidth) > 0.5 else { return }
		// Remembered even with nothing to re-measure, which is the state a
		// column is in for the moment between being built and the walk coming
		// back off its own thread. Left at zero through that moment, the first
		// layout after the cards arrive reports a width change that has already
		// been accounted for — the cards were measured at that width — and
		// reloads the rows in the middle of a layout pass for nothing.
		measuredWidth = width
		guard !entries.isEmpty else { return }
		tableView.reloadData()
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let view = BacklogCardView()
		switch entries[row] {
		case let .item(card):
			view.configure(card)
			view.menu = pane?.menu(for: card)
		case let .change(card):
			view.configure(card)
			view.menu = pane?.menu(for: card)
		}
		return view
	}

	// MARK: Dragging

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
		// A drag starting takes the card out from under the tip, and a panel
		// left floating over a board a card is being dragged across is a panel
		// in the way of the drop.
		TaskTip.shared.hide()
		switch entries[row] {
		case let .item(card):
			let entry = NSPasteboardItem()
			entry.setString(String(card.number), forType: BacklogColumnView.dragType)
			return entry
		case let .change(card):
			// **Refused here, where the drag begins, so that it can be said.**
			// Returning nil is what stops it; the sentence is what stops it
			// being a card that mysteriously will not move. A change's column is
			// read out of its files, so the only thing a drag could mean is
			// ticking somebody's checkboxes.
			pane?.refuseDrag(of: card)
			return nil
		}
	}

	func tableView(
		_ tableView: NSTableView,
		validateDrop info: any NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation operation: NSTableView.DropOperation
	) -> NSDragOperation {
		// Onto the column, never between two cards. The order within a state is
		// the number order and nothing else — an item's place in the list is
		// not something a drag should be able to change, because two people
		// dragging would then disagree and neither would know.
		tableView.setDropRow(-1, dropOperation: .on)
		// A column that is not a folder cannot be dropped into, and the type is
		// what says so: an OpenSpec column has no `BacklogState` to move a file
		// to. The drag itself is refused where it starts, with a sentence.
		guard let target = column.backlogState else { return [] }
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else {
			return []
		}
		return item.state == target ? [] : .move
	}

	func tableView(
		_ tableView: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation: NSTableView.DropOperation
	) -> Bool {
		guard let target = column.backlogState else { return false }
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else { return false }
		guard item.state != target else { return false }
		pane?.move(item, to: target)
		return true
	}

	private func draggedNumber(from info: any NSDraggingInfo) -> Int? {
		guard let entries = info.draggingPasteboard.pasteboardItems else { return nil }
		return entries.compactMap { $0.string(forType: BacklogColumnView.dragType) }.compactMap(Int.init).first
	}
}

/// One item as a card: the number, the title, and what it carries.
final class BacklogCardView: NSView {
	/// **A resized card redraws.**
	///
	/// A row's height is measured once and cached, and `widthChanged` re-measures
	/// them all when the column's width changes — at which point AppKit resizes
	/// the cell view that is already on screen. A resized `NSView` keeps the
	/// drawing it already has unless it is told otherwise, and everything on a
	/// card is positioned from one edge or the other: the stripe, the number and
	/// the title hang off the top and survive, and the progress bar is measured
	/// from `card.maxY` and does not. It stayed at the old bottom — outside the
	/// new bounds, and therefore gone.
	///
	/// That is why the bar was missing on some cards and not others: the ones
	/// whose height had changed since they were drawn. Scrolling the column or
	/// resizing the window brought them back, because either forces the redraw
	/// this asks for in the first place.
	override func setFrameSize(_ newSize: NSSize) {
		let changed = newSize.height != frame.height || newSize.width != frame.width
		super.setFrameSize(newSize)
		if changed { needsDisplay = true }
	}

	private var number = ""
	private var title = ""
	private var marks = ""
	private var tint = NSColor.gray
	private var progress: BacklogItem.Progress?

	/// The breathing room inside a card, and the gap between a card and the
	/// column's edge.
	///
	/// Both came down — 8 to 6, and 10 to 6 — because a board is read by
	/// scanning it, and padding is space that pushes the next card off the
	/// screen. At the old numbers a column of five cards showed four, and the
	/// gutter was doing the work the gap between rows already does.
	private static let inset: CGFloat = 6
	private static let gutter: CGFloat = 6
	private static let barHeight: CGFloat = 3

	/// Whether every card says what it drew, for `--draw-report`.
	static var reportsDrawing = false

	func configure(_ card: BacklogCard) {
		number = String(format: "%04d", card.number)
		title = card.title
		tint = BacklogPalette.colour(for: card.state)
		marks = BacklogPalette.marks(for: card)
		progress = card.progress
		needsDisplay = true
	}

	/// A change: its name where an item has its title, its fraction where an
	/// item has its number, and — before there is a fraction — what has been
	/// written of it, which is what "how far along" means at that stage.
	func configure(_ card: OpenSpecCard) {
		number = card.progress?.summary ?? ""
		title = card.name
		tint = BacklogPalette.colour(for: card.state)
		marks = card.marks
		progress = card.progress
		needsDisplay = true
	}

	/// Tall enough for the title to fit, which is what makes the board readable
	/// — a card that truncates at forty characters is a card whose title is
	/// "the settings page will not stay the width" for four different items.
	static func height(for entry: BoardEntry, width: CGFloat) -> CGFloat {
		switch entry {
		case let .item(card):
			return height(
				title: card.title,
				marks: BacklogPalette.marks(for: card),
				hasProgress: card.progress != nil,
				width: width
			)
		case let .change(card):
			return height(
				title: card.name,
				marks: card.marks,
				hasProgress: card.progress != nil,
				width: width
			)
		}
	}

	private static func height(
		title: String, marks: String, hasProgress: Bool, width: CGFloat
	) -> CGFloat {
		let inset = Theme.current.scaled(Self.inset)
		let gutter = Theme.current.scaled(Self.gutter)
		let available = max(width - gutter * 2 - inset * 2, 40)
		let font = Theme.current.uiFont(12)
		let bounds = (title as NSString).boundingRect(
			with: NSSize(width: available, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: font]
		)
		return ceil(bounds.height) + numberLine + Theme.current.scaled(2)
			+ footer(
				markLines: markLines(marks, width: available),
				progress: hasProgress
			)
			+ inset * 2 + Theme.current.scaled(6)
	}

	/// How many lines the marks want, and never more than three.
	///
	/// One line was enough while the longest thing on it was a branch name at
	/// the end, which is the one mark that can be lost. It stopped being enough
	/// when the fraction gained "in the worktree" and an estimate arrived behind
	/// it: photographed on a board at the width a five-column panel gives, `1/12
	/// in the worktree` filled the line and the estimate came out as `a…`, which
	/// is worse than not drawing it — a card that shows the first letter of a
	/// fact is a card somebody has to open anyway. At two lines the estimate got
	/// as far as `as of 07:…`, which loses the half of it that matters.
	///
	/// Three, and no more. A card only takes the lines its marks need, so this
	/// is a line taller for the four or five items being worked on and unchanged
	/// for the rest of the board; and past three the tail is a branch name that
	/// is the item's number and title with a prefix on it, which the card is
	/// already showing and the menu can open.
	static func markLines(_ marks: String, width: CGFloat) -> Int {
		guard !marks.isEmpty else { return 0 }
		let bounds = (marks as NSString).boundingRect(
			with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: Theme.current.uiFont(11)]
		)
		return min(3, max(1, Int((ceil(bounds.height) / markLine).rounded())))
	}

	/// The two measures the height and the drawing must agree on.
	///
	/// They did not. The height reserved two of `boundingRectForFont.height`
	/// while the drawing advanced by `size(withAttributes:).height`, which is
	/// the larger of the two — so a card came out about a line short, and a
	/// two-line title had nowhere for its second line. That is the whole of the
	/// fault: not the width, not the wrap, a font metric asked two ways.
	///
	/// Both sides read these now, so the only way they can disagree again is if
	/// somebody changes one of these and not the drawing that uses it.
	static var numberLine: CGFloat {
		("0000" as NSString)
			.size(withAttributes: [.font: Theme.current.uiFont(11, weight: .medium)]).height
	}

	/// One line of the marks, measured the way the marks are drawn.
	///
	/// `boundingRect` and not `size(withAttributes:)`, which is what this used
	/// while the marks were a single line placed by its baseline. They are wrapped
	/// into a rect now, and a wrapped line advances by the line-fragment height —
	/// so counting lines with one metric and reserving them with the other is the
	/// same fault this comment was written about the first time, one font metric
	/// asked two ways.
	static var markLine: CGFloat {
		("0/0" as NSString).boundingRect(
			with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: Theme.current.uiFont(11)]
		).height
	}

	/// What sits below the title: the marks, and the bar when there is one.
	/// The footer a card reserves, for the geometry report.
	static func footerForTesting(marks: String, progress: Bool, width: CGFloat) -> CGFloat {
		footer(markLines: markLines(marks, width: width), progress: progress)
	}

	static func footer(markLines: Int, progress: Bool) -> CGFloat {
		var footer = markLine * CGFloat(markLines)
		if progress { footer += Theme.current.scaled(Self.barHeight) + Theme.current.scaled(4) }
		return footer
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let gutter = Theme.current.scaled(Self.gutter)
		let inset = Theme.current.scaled(Self.inset)
		// **The height this card's own contents want, where that is less than
		// the frame it was given**, and the frame otherwise.
		//
		// The two agree whenever the table asked for a height at the width the
		// card is drawn at, which is every ordinary pass — so this changes
		// nothing that is already right. It is here for the pass that is not:
		// a card left in a frame taller than its row hangs over the row's foot,
		// and the foot is where the bar and the bottom corners are. Drawn to
		// the height the contents want, they stay above the clip and the card
		// is whole, with the spare points left blank where they can be seen and
		// fixed rather than swallowing the bar where they cannot.
		let wanted = Self.height(
			title: title, marks: marks, hasProgress: progress != nil, width: bounds.width
		)
		let card = NSRect(
			x: gutter, y: 0,
			width: max(bounds.width - gutter * 2, 0),
			height: min(bounds.height, wanted)
		)

		let path = NSBezierPath(roundedRect: card, xRadius: Theme.current.scaled(5), yRadius: Theme.current.scaled(5))
		Theme.current.selectionInactive.setFill()
		path.fill()

		// Nothing a card draws leaves the card.
		//
		// A guard rather than a feature, and it earns its place: a row's height
		// is measured once and cached, so any moment where the cached height is
		// wrong for the width being drawn at puts more text on a card than fits.
		// Without a clip that text simply carries on — over the card's rounded
		// edge, over the gap, and over the card below, which is what dragging
		// the panel to the side and back used to look like.
		//
		// With it, the same fault truncates instead: still wrong, still worth
		// fixing, and contained to the card it belongs to rather than making
		// three of its neighbours unreadable as well.
		NSGraphicsContext.saveGraphicsState()
		defer { NSGraphicsContext.restoreGraphicsState() }
		path.setClip()
		// A stripe in the state's colour down the left edge, which is what
		// makes a card recognisable at the speed somebody scans a board: the
		// title is what it is about, the stripe is where it stands.
		let stripe = NSBezierPath(
			roundedRect: NSRect(x: card.minX, y: card.minY, width: Theme.current.scaled(3), height: card.height),
			xRadius: Theme.current.scaled(1.5),
			yRadius: Theme.current.scaled(1.5)
		)
		tint.setFill()
		stripe.fill()

		var y = card.minY + inset
		let x = card.minX + inset
		let width = card.width - inset * 2

		let numberAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11, weight: .medium),
			.foregroundColor: tint,
		]
		(number as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: numberAttributes)
		y += (number as NSString).size(withAttributes: numberAttributes).height + Theme.current.scaled(2)

		let titleAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.editorText,
		]
		// The title stops above the footer rather than running to the bottom of
		// the card.
		//
		// It used to be given every point left, and the marks were then drawn on
		// top of whatever the title had put in that space — a branch name across
		// the second line of a two-line title, both unreadable. That only shows
		// when the height is a line short, which `height(for:width:)` can be
		// when it measured at a different width from the one the card is drawn
		// at, so this is the half that makes the overlap impossible rather than
		// unlikely. `lines` is the same measure the height reserves two of.
		// The same count the height reserved, from the same string at the same
		// width, so that the two can only disagree when the cached height is
		// stale for the width being drawn at — which the clip above contains.
		let markLines = Self.markLines(marks, width: width)
		let footer = Self.footer(markLines: markLines, progress: progress != nil)
		let titleRect = NSRect(
			x: x, y: y, width: width, height: max(0, card.maxY - y - inset - footer)
		)
		(title as NSString).draw(
			with: titleRect,
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: titleAttributes
		)

		var bottom = card.maxY - inset

		// What this card actually drew, when asked. A progress bar that is
		// missing until something forces a second pass is a question about the
		// pass that drew it first, and nothing outside `draw` can answer it.
		if BacklogCardView.reportsDrawing {
			let has = progress != nil
			print("DRAW \(title.prefix(38)): bounds=\(bounds.size)"
				+ " card=\(card.size) progress=\(has)"
				+ " footer=\(Self.footer(markLines: Self.markLines(marks, width: width), progress: has))")
			fflush(stdout)
		}

		// The checklist, as a bar along the foot of the card.
		//
		// A bar as well as the `3/7` in the line above it, because they answer
		// the question at two speeds: the fraction is what you read when you
		// have stopped at a card, and the bar is what you see when you have
		// not. A board is mostly looked at rather than read.
		if let progress {
			let height = Theme.current.scaled(Self.barHeight)
			bottom -= height + Theme.current.scaled(4)
			let track = NSRect(x: x, y: bottom + Theme.current.scaled(4), width: width, height: height)
			let radius = height / 2
			Theme.current.separator.setFill()
			NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

			// Nothing drawn at zero rather than a sliver: a bar with a dot at
			// the left end reads as "started", and an item with five unticked
			// steps has not been.
			if progress.done > 0 {
				var filled = track
				filled.size.width = max(track.width * CGFloat(progress.fraction), height)
				tint.setFill()
				NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
			}
		}

		guard !marks.isEmpty else { return }
		// Into a rect, and truncating, because this is the one line on a card
		// whose length is not ours: a branch name is
		// `backlog/0435-the-plantuml-server-test-fails-only-when-the-suite-is-busy`,
		// which is the item's whole title with a prefix on it. Drawn `at:` a
		// point it had no width to obey and ran out past the card's rounded
		// edge and over its neighbour.
		//
		// Wrapping, with the last visible line truncated: what a mark says first
		// is what identifies it — `3/7`, `2 images`, `spec`, and a branch that
		// begins with the number — so the end is the part that can go, and the
		// order the marks are built in is the order they are lost in.
		//
		// **`byWordWrapping`, not `byTruncatingTail`.** A truncating line break
		// mode means "this is one line", so with it the second line of the rect
		// was reserved, paid for in card height, and left empty while the first
		// line ended in `a…`. Photographed before it was understood, which is
		// the only way this pane's faults have ever been found.
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byWordWrapping
		let markAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		]
		let markHeight = Self.markLine * CGFloat(markLines)
		(marks as NSString).draw(
			with: NSRect(x: x, y: bottom - markHeight, width: width, height: markHeight),
			options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
			attributes: markAttributes
		)
	}
}

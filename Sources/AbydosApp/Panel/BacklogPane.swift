import AppKit
import AbydosKit

/// One item, with everything a row or a card says about it already worked out.
///
/// Exists so that drawing costs nothing. An item's title, its checklist, its
/// screenshots and its spec delta are four reads of the file system, and a
/// board redraws on every scroll — so they are done once, on the thread that
/// re-reads the folder, and what reaches `draw(_:)` is five fields.
struct BacklogCard {
	let item: BacklogItem
	let progress: BacklogItem.Progress?
	let images: Int
	let hasSpecDelta: Bool
	let run: BacklogRun?

	init(_ item: BacklogItem, run: BacklogRun?) {
		self.item = item
		self.progress = item.progress()
		self.images = item.images().count
		self.hasSpecDelta = !item.specDeltas().isEmpty
		self.run = run
	}

	var number: Int { item.number }
	var title: String { item.title }
	var state: BacklogState { item.state }
}

/// The backlog, as a list and as a board.
///
/// Two presentations of one directory, and the toggle between them is a view
/// change rather than a mode: the list is for reading — everything in one
/// column, in number order, which is how you find the thing you half remember
/// — and the board is for moving, because dragging a card from `ready` to
/// `in-progress` is the same `mv` and is the one gesture a list cannot make.
///
/// Neither holds any state of its own. What is on screen is what is in
/// `.abydos/backlog`, re-read when it changes, so somebody moving a file in a
/// terminal sees the board move too.
final class BacklogPane: NSView {
	/// Open an item's markdown in the editor.
	var onOpenItem: ((URL) -> Void)?
	/// Pick an item up: a worktree of its own, and an agent in it.
	var onStartAgent: ((BacklogItem) -> Void)?
	/// Say something in the corner of the window.
	var onNotify: ((String, String?) -> Void)?

	private let backlog: Backlog
	private var watcher: FileSystemWatcher?

	private var cardsByState: [BacklogState: [BacklogCard]] = [:]

	private enum Mode: Int { case list, board }
	private var mode: Mode = .board

	private var modeControl: NSSegmentedControl!
	private var summaryLabel: NSTextField!
	private var startButton: NSButton!
	private var contentArea: NSView!
	private var listView: BacklogListView!
	private var boardView: BacklogBoardView!

	init(projectRoot: URL) {
		self.backlog = Backlog(projectRoot: projectRoot)
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		reload()
		watch()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		watcher?.stop()
	}

	override var isFlipped: Bool { true }

	// MARK: - Building

	private func build() {
		modeControl = NSSegmentedControl(
			labels: ["List", "Board"],
			trackingMode: .selectOne,
			target: self,
			action: #selector(modeChanged)
		)
		modeControl.selectedSegment = mode.rawValue
		modeControl.font = Theme.current.uiFont(11)

		summaryLabel = NSTextField(labelWithString: "")
		summaryLabel.font = Theme.current.uiFont(11)
		summaryLabel.textColor = Theme.current.gitIgnored

		startButton = NSButton(title: "Start the next ready item", target: self, action: #selector(startNext))
		startButton.bezelStyle = .rounded
		startButton.controlSize = .small
		startButton.font = Theme.current.uiFont(11)

		let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked))
		refresh.bezelStyle = .rounded
		refresh.controlSize = .small
		refresh.font = Theme.current.uiFont(11)

		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

		let header = NSStackView(views: [modeControl, summaryLabel, spacer, startButton, refresh])
		header.orientation = .horizontal
		header.spacing = Theme.current.scaled(8)
		header.edgeInsets = NSEdgeInsets(
			top: 0, left: Theme.current.scaled(8), bottom: 0, right: Theme.current.scaled(8)
		)

		listView = BacklogListView()
		listView.pane = self
		boardView = BacklogBoardView()
		boardView.pane = self

		contentArea = NSView()
		addSubview(header)
		addSubview(contentArea)
		header.translatesAutoresizingMaskIntoConstraints = false
		contentArea.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: topAnchor),
			header.leadingAnchor.constraint(equalTo: leadingAnchor),
			header.trailingAnchor.constraint(equalTo: trailingAnchor),
			header.heightAnchor.constraint(equalToConstant: Theme.current.scaled(34)),

			contentArea.topAnchor.constraint(equalTo: header.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		showContent()
	}

	private func showContent() {
		let wanted: NSView = mode == .list ? listView : boardView
		guard wanted.superview !== contentArea else { return }
		contentArea.subviews.forEach { $0.removeFromSuperview() }
		contentArea.addSubview(wanted)
		wanted.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			wanted.topAnchor.constraint(equalTo: contentArea.topAnchor),
			wanted.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			wanted.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
			wanted.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
		])
	}

	@objc private func modeChanged() {
		mode = Mode(rawValue: modeControl.selectedSegment) ?? .board
		showContent()
		refreshViews()
	}

	/// Which presentation is showing, set from outside for `--backlog list`.
	func showList(_ list: Bool) {
		mode = list ? .list : .board
		modeControl.selectedSegment = mode.rawValue
		showContent()
		refreshViews()
	}

	@objc private func refreshClicked() { reload() }

	/// The theme or the zoom changed.
	///
	/// Every card and every row is drawn rather than laid out, so there is
	/// nothing to re-measure by hand: the surfaces take their new colour and
	/// the tables are told to draw again, and the row heights come back through
	/// `heightOfRow` at the new scale.
	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		modeControl.font = Theme.current.uiFont(11)
		summaryLabel.font = Theme.current.uiFont(11)
		summaryLabel.textColor = Theme.current.gitIgnored
		startButton.font = Theme.current.uiFont(11)
		listView.applySettings()
		boardView.applySettings()
		refreshViews()
	}

	// MARK: - Reading

	/// Re-reads the folder, off the main thread.
	///
	/// Off it because everything a card says comes out of the file system: the
	/// title and the checklist are the item's own markdown, the image count and
	/// the delta are two directory reads each. Forty items is a hundred and
	/// sixty syscalls, and on a cold cache that is long enough to be a stutter
	/// in a window somebody is dragging a card across.
	///
	/// Read once into a card and not asked again while drawing, which is the
	/// other half: `draw(_:)` runs on every scroll, and a fraction that costs a
	/// file open is a fraction nobody should be able to put on a card.
	func reload() {
		let backlog = self.backlog
		DispatchQueue.global(qos: .userInitiated).async {
			let runs = Dictionary(
				uniqueKeysWithValues: BacklogRuns(projectRoot: backlog.projectRoot).all().map { ($0.number, $0) }
			)
			var found: [BacklogState: [BacklogCard]] = [:]
			for state in BacklogState.board {
				found[state] = backlog.items(in: state).map { BacklogCard($0, run: runs[$0.number]) }
			}

			DispatchQueue.main.async {
				self.cardsByState = found
				self.refreshViews()
			}
		}
	}

	/// Watches the backlog for somebody else moving a file.
	///
	/// The point of a dashboard over files is that the files are the truth. An
	/// agent finishing an item in a worktree writes into this folder, and a
	/// board that only updated when it was clicked would be the one place in
	/// the app that disagreed with the disk.
	private func watch() {
		guard FileManager.default.fileExists(atPath: backlog.directory.path) else { return }
		let watcher = FileSystemWatcher(root: backlog.directory) { [weak self] _ in
			DispatchQueue.main.async { self?.reload() }
		}
		watcher.start()
		self.watcher = watcher
	}

	private func refreshViews() {
		let counts = BacklogState.board.map { "\(cards(in: $0).count) \($0.directoryName)" }
		summaryLabel.stringValue = counts.joined(separator: "   ")
		startButton.isEnabled = !cards(in: .ready).isEmpty

		if mode == .list {
			listView.reload()
		} else {
			boardView.reload()
		}
	}

	func cards(in state: BacklogState) -> [BacklogCard] { cardsByState[state] ?? [] }

	func item(number: Int) -> BacklogItem? {
		BacklogState.board.compactMap { cards(in: $0).first { $0.item.number == number }?.item }.first
	}

	// MARK: - Acting

	func open(_ item: BacklogItem) {
		onOpenItem?(item.file)
	}

	/// Moves an item, and says so if it will not go.
	func move(_ item: BacklogItem, to state: BacklogState) {
		do {
			_ = try backlog.move(item, to: state)
		} catch {
			onNotify?("Could not move \(String(format: "%04d", item.number))", "\(error)")
		}
		reload()
	}

	@objc private func startNext() {
		guard let card = cards(in: .ready).first else { return }
		onStartAgent?(card.item)
	}

	func start(_ item: BacklogItem) {
		onStartAgent?(item)
	}

	/// The menu a card and a row both use.
	func menu(for item: BacklogItem) -> NSMenu {
		let menu = NSMenu()

		let open = NSMenuItem(title: "Open", action: #selector(openFromMenu(_:)), keyEquivalent: "")
		open.target = self
		open.representedObject = item
		menu.addItem(open)

		if item.state == .ready {
			let start = NSMenuItem(
				title: "Start in a Worktree\u{2026}",
				action: #selector(startFromMenu(_:)),
				keyEquivalent: ""
			)
			start.target = self
			start.representedObject = item
			menu.addItem(start)
		}

		menu.addItem(.separator())
		for state in BacklogState.board where state != item.state {
			let move = NSMenuItem(
				title: "Move to \(state.title)",
				action: #selector(moveFromMenu(_:)),
				keyEquivalent: ""
			)
			move.target = self
			move.representedObject = MoveRequest(item: item, state: state)
			menu.addItem(move)
		}

		menu.addItem(.separator())
		let reveal = NSMenuItem(
			title: item.carriesFiles ? "Show Folder in Finder" : "Show in Finder",
			action: #selector(revealFromMenu(_:)),
			keyEquivalent: ""
		)
		reveal.target = self
		reveal.representedObject = item
		menu.addItem(reveal)
		return menu
	}

	/// A pair, because a menu item carries one object.
	private final class MoveRequest: NSObject {
		let item: BacklogItem
		let state: BacklogState
		init(item: BacklogItem, state: BacklogState) {
			self.item = item
			self.state = state
		}
	}

	@objc private func openFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		open(item)
	}

	@objc private func startFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		start(item)
	}

	@objc private func moveFromMenu(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? MoveRequest else { return }
		move(request.item, to: request.state)
	}

	@objc private func revealFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		NSWorkspace.shared.activateFileViewerSelecting([item.folder ?? item.file])
	}
}

// MARK: - The list

/// Everything, in one column, grouped by state.
final class BacklogListView: NSView {
	weak var pane: BacklogPane?

	private enum Row {
		case header(BacklogState, Int)
		case item(BacklogCard)
	}

	private var rows: [Row] = []
	private var tableView: NSTableView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.doubleAction = #selector(rowDoubleClicked)
		tableView = table

		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
		scrollView.autohidesScrollers = true

		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	func reload() {
		guard let pane else { return }
		rows = []
		for state in BacklogState.board {
			let cards = pane.cards(in: state)
			guard !cards.isEmpty else { continue }
			rows.append(.header(state, cards.count))
			rows += cards.map(Row.item)
		}
		tableView.reloadData()
	}

	@objc private func rowDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < rows.count else { return }
		guard case let .item(card) = rows[tableView.clickedRow] else { return }
		pane?.open(card.item)
	}

	func applySettings() {
		tableView.backgroundColor = Theme.current.editorBackground
		tableView.enclosingScrollView?.backgroundColor = Theme.current.editorBackground
	}
}

extension BacklogListView: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		switch rows[row] {
		case .header: return Theme.current.scaled(26)
		case .item: return Theme.current.scaled(22)
		}
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		switch rows[row] {
		case let .header(state, count):
			return BacklogSectionHeader(state: state, count: count)
		case let .item(card):
			let view = BacklogRowCell()
			view.configure(card)
			view.menu = pane?.menu(for: card.item)
			return view
		}
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		if case .header = rows[row] { return false }
		return true
	}
}

/// `Ready — 3`, over the items in it.
private final class BacklogSectionHeader: NSView {
	private let state: BacklogState
	private let count: Int

	init(state: BacklogState, count: Int) {
		self.state = state
		self.count = count
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let font = Theme.current.uiFont(11, weight: .semibold)
		let text = "\(state.title.uppercased())  \(count)"
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: BacklogPalette.colour(for: state),
		]
		let size = (text as NSString).size(withAttributes: attributes)
		(text as NSString).draw(
			at: NSPoint(x: Theme.current.scaled(10), y: (bounds.height - size.height) / 2),
			withAttributes: attributes
		)

		Theme.current.separator.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
	}
}

/// One item on one line.
private final class BacklogRowCell: NSView {
	private var number = ""
	private var title = ""
	private var marks = ""
	private var tint = NSColor.gray

	func configure(_ card: BacklogCard) {
		number = String(format: "%04d", card.number)
		title = card.title
		tint = BacklogPalette.colour(for: card.state)
		marks = BacklogPalette.marks(for: card)
		needsDisplay = true
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// Every piece is drawn into a rect of the same height at the same y,
		// with the same line-fragment origin. Mixing `draw(at:)` — which places
		// a baseline — with `draw(with:options:)` — which places the top of a
		// line box — put the number and the title on two different lines that
		// were four points apart, which reads as a misprint.
		let font = Theme.current.uiFont(12)
		let line = ceil(font.ascender - font.descender + font.leading)
		let y = ((bounds.height - line) / 2).rounded()
		let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]

		let truncating = NSMutableParagraphStyle()
		truncating.lineBreakMode = .byTruncatingTail

		var x = Theme.current.scaled(10)
		let numberAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(12, weight: .medium),
			.foregroundColor: tint,
		]
		let numberWidth = ceil((number as NSString).size(withAttributes: numberAttributes).width)
		(number as NSString).draw(
			with: NSRect(x: x, y: y, width: numberWidth, height: line),
			options: options,
			attributes: numberAttributes
		)
		x += numberWidth + Theme.current.scaled(10)

		var markWidth: CGFloat = 0
		if !marks.isEmpty {
			let markAttributes: [NSAttributedString.Key: Any] = [
				.font: Theme.current.uiFont(11),
				.foregroundColor: Theme.current.gitIgnored,
				.paragraphStyle: truncating,
			]
			markWidth = ceil((marks as NSString).size(withAttributes: markAttributes).width)
				+ Theme.current.scaled(12)
			(marks as NSString).draw(
				with: NSRect(x: bounds.width - markWidth, y: y, width: markWidth, height: line),
				options: options,
				attributes: markAttributes
			)
		}

		let available = bounds.width - x - markWidth - Theme.current.scaled(8)
		guard available > 0 else { return }
		(title as NSString).draw(
			with: NSRect(x: x, y: y, width: available, height: line),
			options: options,
			attributes: [
				.font: font,
				.foregroundColor: Theme.current.editorText,
				.paragraphStyle: truncating,
			]
		)
	}
}

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

	private func build() {
		columns = BacklogState.board.map { BacklogColumnView(state: $0) }
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
				greaterThanOrEqualToConstant: Theme.current.scaled(CGFloat(BacklogState.board.count) * 190)
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
	let state: BacklogState

	/// What a dragged card carries: the number, which is the only durable name
	/// an item has.
	static let dragType = NSPasteboard.PasteboardType("dev.abydos.backlog.item")

	private var cards: [BacklogCard] = []
	private var tableView: NSTableView!
	private var headerLabel: NSTextField!
	private var emptyLabel: NSTextField!

	init(state: BacklogState) {
		self.state = state
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		headerLabel = NSTextField(labelWithString: state.title.uppercased())
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: state)

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

		// What belongs in this column, for a column with nothing in it.
		//
		// An empty board is the state somebody is in on their first day with
		// one, and five unlabelled columns explain nothing. `ready` is the one
		// that matters: it is the folder an agent picks from, and the reason
		// nothing is in it is that moving something there is a decision.
		emptyLabel = NSTextField(wrappingLabelWithString: state.summary)
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

	func reload() {
		cards = pane?.cards(in: state) ?? []
		headerLabel.stringValue = cards.isEmpty
			? state.title.uppercased()
			: "\(state.title.uppercased())  \(cards.count)"
		emptyLabel.isHidden = !cards.isEmpty
		tableView.reloadData()
	}

	@objc private func cardDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < cards.count else { return }
		pane?.open(cards[tableView.clickedRow].item)
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: state)
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		tableView.backgroundColor = Theme.current.editorBackground
		tableView.intercellSpacing = NSSize(width: 0, height: Theme.current.scaled(6))
		tableView.enclosingScrollView?.backgroundColor = Theme.current.editorBackground
	}
}

extension BacklogColumnView: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { cards.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		BacklogCardView.height(for: cards[row], width: tableView.bounds.width)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let card = cards[row]
		let view = BacklogCardView()
		view.configure(card)
		view.menu = pane?.menu(for: card.item)
		return view
	}

	// MARK: Dragging

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
		let entry = NSPasteboardItem()
		entry.setString(String(cards[row].number), forType: BacklogColumnView.dragType)
		return entry
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
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else {
			return []
		}
		return item.state == state ? [] : .move
	}

	func tableView(
		_ tableView: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation: NSTableView.DropOperation
	) -> Bool {
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else { return false }
		guard item.state != state else { return false }
		pane?.move(item, to: state)
		return true
	}

	private func draggedNumber(from info: any NSDraggingInfo) -> Int? {
		guard let entries = info.draggingPasteboard.pasteboardItems else { return nil }
		return entries.compactMap { $0.string(forType: BacklogColumnView.dragType) }.compactMap(Int.init).first
	}
}

/// One item as a card: the number, the title, and what it carries.
private final class BacklogCardView: NSView {
	private var number = ""
	private var title = ""
	private var marks = ""
	private var tint = NSColor.gray
	private var progress: BacklogItem.Progress?

	private static let inset: CGFloat = 8
	private static let gutter: CGFloat = 10
	private static let barHeight: CGFloat = 3

	func configure(_ card: BacklogCard) {
		number = String(format: "%04d", card.number)
		title = card.title
		tint = BacklogPalette.colour(for: card.state)
		marks = BacklogPalette.marks(for: card)
		progress = card.progress
		needsDisplay = true
	}

	/// Tall enough for the title to fit, which is what makes the board readable
	/// — a card that truncates at forty characters is a card whose title is
	/// "the settings page will not stay the width" for four different items.
	static func height(for card: BacklogCard, width: CGFloat) -> CGFloat {
		let inset = Theme.current.scaled(Self.inset)
		let gutter = Theme.current.scaled(Self.gutter)
		let available = max(width - gutter * 2 - inset * 2, 40)
		let font = Theme.current.uiFont(12)
		let bounds = (card.title as NSString).boundingRect(
			with: NSSize(width: available, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: font]
		)
		let lines = Theme.current.uiFont(11).boundingRectForFont.height
		var height = ceil(bounds.height) + lines * 2 + inset * 2 + Theme.current.scaled(6)
		if card.progress != nil { height += Theme.current.scaled(Self.barHeight) + Theme.current.scaled(4) }
		return height
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let gutter = Theme.current.scaled(Self.gutter)
		let inset = Theme.current.scaled(Self.inset)
		let card = bounds.insetBy(dx: gutter, dy: 0)

		let path = NSBezierPath(roundedRect: card, xRadius: Theme.current.scaled(5), yRadius: Theme.current.scaled(5))
		Theme.current.selectionInactive.setFill()
		path.fill()
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
		let titleRect = NSRect(x: x, y: y, width: width, height: card.maxY - y - inset)
		(title as NSString).draw(
			with: titleRect,
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: titleAttributes
		)

		var bottom = card.maxY - inset

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
		let markAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.gitIgnored,
		]
		let markHeight = (marks as NSString).size(withAttributes: markAttributes).height
		(marks as NSString).draw(
			at: NSPoint(x: x, y: bottom - markHeight),
			withAttributes: markAttributes
		)
	}
}

// MARK: - Shared drawing

/// What a state looks like, and what an item is wearing.
enum BacklogPalette {
	/// Borrowed from the version-control colours rather than invented.
	///
	/// Not laziness: those five are already the palette of "something is going
	/// on with this file" everywhere else in the window, and a board with its
	/// own green means two greens in one app that mean different things.
	static func colour(for state: BacklogState) -> NSColor {
		switch state {
		case .open: return Theme.current.gitUnversioned
		case .ready: return Theme.current.gitAdded
		case .inProgress: return Theme.current.gitModified
		case .waiting: return Theme.current.gitConflict
		case .completed, .history: return Theme.current.gitIgnored
		}
	}

	/// The line under a card: how far along it is, what it carries, and where
	/// it is being worked on.
	static func marks(for card: BacklogCard) -> String {
		var marks: [String] = []
		// First, because it is the one thing that changes while somebody is
		// watching the board.
		if let progress = card.progress { marks.append(progress.summary) }
		if card.images > 0 { marks.append("\(card.images) image\(card.images == 1 ? "" : "s")") }
		if card.hasSpecDelta { marks.append("spec") }
		if let run = card.run, run.isPresent { marks.append(run.branch) }
		return marks.joined(separator: "  \u{00B7}  ")
	}
}

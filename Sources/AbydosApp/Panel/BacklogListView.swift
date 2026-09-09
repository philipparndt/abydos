import AppKit
import AbydosKit

/// The list: one column of cards, with a heading a section, which is what the
/// backlog looks like when there is not room for a board.
// MARK: - The list

/// Everything, in one column, grouped by state.
final class BacklogListView: NSView {
	weak var pane: BacklogPane?

	private enum Row {
		case header(BoardColumn, Int)
		case entry(BoardEntry)
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
		// The columns of whichever record is showing, the archive among them —
		// it used to be a section of its own down here because it was not a
		// column anywhere.
		for column in pane.columns {
			let entries = pane.entries(in: column)
			guard !entries.isEmpty else { continue }
			rows.append(.header(column, entries.count))
			rows += entries.map(Row.entry)
		}
		tableView.reloadData()
	}

	@objc private func rowDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < rows.count else { return }
		guard case let .entry(entry) = rows[tableView.clickedRow] else { return }
		switch entry {
		case let .item(card):   pane?.open(card.item)
		case let .change(card): pane?.open(card)
		}
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
		case .entry: return Theme.current.scaled(22)
		}
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		switch rows[row] {
		case let .header(column, count):
			return BacklogSectionHeader(column: column, count: count)
		case let .entry(entry):
			let view = BacklogRowCell()
			switch entry {
			case let .item(card):
				view.configure(card)
				view.menu = pane?.menu(for: card)
			case let .change(card):
				view.configure(card)
				view.menu = pane?.menu(for: card)
			}
			return view
		}
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		switch rows[row] {
		case .header: return false
		case .entry: return true
		}
	}
}

/// `Ready — 3`, over the items in it.
final class BacklogSectionHeader: NSView {
	private let column: BoardColumn
	private let count: Int

	init(column: BoardColumn, count: Int) {
		self.column = column
		self.count = count
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let font = Theme.current.uiFont(11, weight: .semibold)
		let text = "\(column.title.uppercased())  \(count)"
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: BacklogPalette.colour(for: column),
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
final class BacklogRowCell: NSView {
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

	/// A change has no number, so the column that holds one holds its fraction
	/// instead — and, before there is one to hold, what has been written.
	func configure(_ card: OpenSpecCard) {
		number = card.progress?.summary ?? ""
		title = card.name
		tint = BacklogPalette.colour(for: card.state)
		marks = card.marks
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
			// Measured, then capped at half the room. The paragraph style
			// truncates, but only within whatever width it is given, and the
			// natural width of a branch name is the item's whole title with a
			// prefix on it — so the marks took the row, `available` went
			// negative, and the guard below dropped the title altogether. The
			// title is what somebody is scanning for; it keeps half.
			let room = max(0, bounds.width - x - Theme.current.scaled(8))
			let natural = ceil((marks as NSString).size(withAttributes: markAttributes).width)
				+ Theme.current.scaled(12)
			markWidth = min(natural, room / 2)
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

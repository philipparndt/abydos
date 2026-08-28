import AppKit
import AbydosKit

/// The breakpoints a project has, as a list beside the call stack.
///
/// The gutter answers "is there one on this line" and nothing answers "where
/// are they all" — six across four files could only be established by opening
/// four files. It is a tab rather than a column because the two do not fit side
/// by side at any panel height somebody would choose, and it is *in the
/// debugger* because the list and the stack are read together while a program is
/// stopped: which of these did it hit.
///
/// Every verb goes back out through the window to `DebugCoordinator`, which is
/// the one thing that holds the set. A list with verbs of its own would be a
/// second owner of a set that has one, and the fault that came of two owners is
/// still fresh.
final class BreakpointList: NSView {
	/// The code a line holds, asked for when the row is drawn.
	///
	/// From the editor's document when the file is open — so an unsaved edit
	/// shows the line as it now reads — and from the file otherwise. Nil where
	/// the file has gone, which draws the row with its place and nothing else
	/// rather than reporting an error about a file nobody asked to open.
	var lineText: ((String, Int) -> String?)?
	var onOpen: ((String, Int) -> Void)?
	var onSetEnabled: ((String, Int, Bool) -> Void)?
	var onDelete: ((String, Int) -> Void)?
	var onEditOptions: ((String, Int) -> Void)?
	var onSilenceOthers: ((String, Int, Bool) -> Void)?

	private var rows: [BreakpointRows.Row] = []
	private var table: NSTableView!
	private var emptyLabel: NSTextField!
	/// What each row's line holds, thrown away whenever the set changes.
	///
	/// **Keyed by the line and not only by the file**, which is worth saying
	/// because it was keyed by the file first and the screenshot showed two
	/// breakpoints in one file drawn with the same code: the second row asked the
	/// cache "what is in main.go" and got the answer to the first row's question.
	private var textCache: [String: String?] = [:]

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	func show(_ rows: [BreakpointRows.Row]) {
		self.rows = rows
		textCache = [:]
		emptyLabel.isHidden = !rows.isEmpty
		table.isHidden = rows.isEmpty
		table.reloadData()
	}

	/// What the list is showing, for a run nobody is watching.
	var reportForTesting: String {
		guard !rows.isEmpty else { return "none" }
		return rows.map { row in
			"\(row.name):\(row.line)"
				+ (row.isEnabled ? "" : " off")
				+ (row.condition.map { " if \($0)" } ?? "")
		}.joined(separator: ", ")
	}

	private func build() {
		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.selectionHighlightStyle = .regular
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("breakpoint")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.doubleAction = #selector(rowOpened)
		table.menu = makeMenu()
		self.table = table

		// The one sentence somebody with no breakpoints needs, which is how to
		// make one. An empty table says only that something is broken.
		emptyLabel = NSTextField(labelWithString: "No breakpoints. Click a line's gutter to set one.")
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		emptyLabel.alignment = .center

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		scroll.translatesAutoresizingMaskIntoConstraints = false
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scroll)
		addSubview(emptyLabel)

		NSLayoutConstraint.activate([
			scroll.topAnchor.constraint(equalTo: topAnchor),
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
			emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			emptyLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.current.scaled(18)),
			emptyLabel.leadingAnchor.constraint(
				greaterThanOrEqualTo: leadingAnchor, constant: Theme.current.scaled(8)
			),
		])
	}

	private func makeMenu() -> NSMenu {
		let menu = NSMenu()
		for (title, selector) in [
			("Go to Breakpoint", #selector(rowOpened)),
			("Enable", #selector(enableRow)),
			("Disable", #selector(disableRow)),
			("Condition…", #selector(editRow)),
			("Disable Others", #selector(disableOthers)),
			("Enable All", #selector(enableAll)),
			("Delete", #selector(deleteRow)),
		] {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			menu.addItem(item)
		}
		return menu
	}

	/// The row a menu command is about: the one clicked, or the one selected
	/// when the menu was opened from the keyboard.
	private var actedOn: BreakpointRows.Row? {
		let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
		return rows.indices.contains(row) ? rows[row] : nil
	}

	@objc private func rowOpened() {
		guard let row = actedOn else { return }
		onOpen?(row.path, row.line)
	}

	@objc private func enableRow() {
		guard let row = actedOn else { return }
		onSetEnabled?(row.path, row.line, true)
	}

	@objc private func disableRow() {
		guard let row = actedOn else { return }
		onSetEnabled?(row.path, row.line, false)
	}

	@objc private func editRow() {
		guard let row = actedOn else { return }
		onEditOptions?(row.path, row.line)
	}

	@objc private func deleteRow() {
		guard let row = actedOn else { return }
		onDelete?(row.path, row.line)
	}

	@objc private func disableOthers() {
		guard let row = actedOn else { return }
		onSilenceOthers?(row.path, row.line, false)
	}

	@objc private func enableAll() {
		guard let row = actedOn else { return }
		onSilenceOthers?(row.path, row.line, true)
	}

	/// The code on a row's line, read once per row and kept until the set moves.
	private func code(for row: BreakpointRows.Row) -> String? {
		let key = "\(row.path):\(row.line)"
		if let cached = textCache[key] { return cached }
		let read = lineText?(row.path, row.line)
		textCache[key] = read
		return read
	}

	func applyThemeChange() {
		table.backgroundColor = Theme.current.editorBackground
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		table.reloadData()
	}
}

extension BreakpointList: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		Theme.current.scaled(34)
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		ThemedRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard rows.indices.contains(row) else { return nil }
		return BreakpointCell(row: rows[row], code: code(for: rows[row]))
	}
}

/// One breakpoint: where it is, what is written there, and what it waits for.
private final class BreakpointCell: NSView {
	private let row: BreakpointRows.Row
	private let code: String?

	init(row: BreakpointRows.Row, code: String?) {
		self.row = row
		self.code = code
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let inset = Theme.current.scaled(10)
		let dot = Theme.current.scaled(8)

		// Filled when it is on and bound, hollow otherwise — the gutter's own
		// rule, because a marker drawn solid where execution can never stop is a
		// lie whichever view draws it.
		let circle = NSBezierPath(ovalIn: NSRect(
			x: inset, y: Theme.current.scaled(7), width: dot, height: dot
		))
		let colour = row.isEnabled ? Theme.current.gitConflict : Theme.current.gitIgnored
		if row.isEnabled, row.isVerified {
			colour.setFill()
			circle.fill()
		} else {
			colour.setStroke()
			circle.lineWidth = Theme.current.scaled(1.5)
			circle.stroke()
		}

		let textLeft = inset + dot + Theme.current.scaled(8)
		let width = max(0, bounds.width - textLeft - inset)

		let place = NSAttributedString(string: "\(row.name):\(row.line)", attributes: [
			.font: Theme.current.uiFont(11.5, weight: .medium),
			.foregroundColor: isSelected ? NSColor.hex(0xE8EAED) : Theme.current.sidebarHeaderText,
		])
		place.draw(in: NSRect(x: textLeft, y: Theme.current.scaled(3), width: width, height: Theme.current.scaled(14)))

		// The condition wins the second line where there is one: it is the part
		// that took thought, and the code is on the screen the row points at.
		let second = row.condition.map { "if \($0)" } ?? code?.trimmingCharacters(in: .whitespaces) ?? ""
		guard !second.isEmpty else { return }
		let detail = NSAttributedString(string: second, attributes: [
			.font: Theme.current.monoFont(10.5),
			.foregroundColor: row.condition == nil ? Theme.current.gitIgnored : Theme.current.gitModified,
		])
		detail.draw(in: NSRect(
			x: textLeft, y: Theme.current.scaled(17), width: width, height: Theme.current.scaled(14)
		))
	}
}

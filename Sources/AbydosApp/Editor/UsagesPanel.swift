import AppKit
import AbydosKit

/// Everywhere a symbol is used.
///
/// The language server's answer rather than a text search: it tells a `Close`
/// on one type from a `Close` on another, and finds the ones spelled
/// differently because they came through an alias — neither of which grep will
/// ever do.
@MainActor
final class UsagesPanel: NSObject {
	var onOpen: ((LSPLocation) -> Void)?
	/// Asked to move into the sidebar instead of floating over the code.
	var onDock: ((NSView, String) -> Void)?

	private var window: NSPanel?
	private var table: NSTableView!
	private var heading: NSTextField!
	private var dockButton: NSButton!
	private var rows: [Row] = []
	private var lastTitle = "Usages"

	private enum Row {
		case file(String, count: Int)
		case usage(LSPLocation, line: String)
	}

	func show(locations: [LSPLocation], over parent: NSWindow?) {
		guard let parent else { return }
		rows = Self.rows(from: locations)

		// A window whose content was docked has none left, so it is built afresh.
		if window?.contentView == nil { window = nil }
		let window = self.window ?? makeWindow()
		self.window = window
		let files = Self.fileCount(rows)
		lastTitle = "\(locations.count) usage\(locations.count == 1 ? "" : "s") "
			+ "in \(files) file\(files == 1 ? "" : "s")"
		heading.stringValue = lastTitle
		table.reloadData()

		let frame = parent.frame
		let size = NSSize(width: min(760, frame.width - 80), height: min(520, frame.height - 160))
		window.setFrame(NSRect(
			x: frame.midX - size.width / 2,
			y: frame.midY - size.height / 2,
			width: size.width,
			height: size.height
		), display: true)

		parent.addChildWindow(window, ordered: .above)
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
		} else {
			window.orderFront(nil)
		}
	}

	func hide() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
	}

	/// Grouped by file, in the order they were reported, with the line's text
	/// where it can be read.
	private static func rows(from locations: [LSPLocation]) -> [Row] {
		var byFile: [String: [LSPLocation]] = [:]
		var order: [String] = []

		for location in locations {
			guard let path = location.url?.path else { continue }
			if byFile[path] == nil { order.append(path) }
			byFile[path, default: []].append(location)
		}

		var rows: [Row] = []
		for path in order.sorted() {
			let inFile = (byFile[path] ?? []).sorted { $0.range.start.line < $1.range.start.line }
			rows.append(.file(path, count: inFile.count))

			// Read once per file rather than once per usage: a file with forty
			// hits should be opened once.
			let lines = (try? String(contentsOfFile: path, encoding: .utf8))?
				.components(separatedBy: "\n") ?? []
			for location in inFile {
				let index = location.range.start.line
				let text = lines.indices.contains(index)
					? lines[index].trimmingCharacters(in: .whitespaces)
					: ""
				rows.append(.usage(location, line: text))
			}
		}
		return rows
	}

	private static func fileCount(_ rows: [Row]) -> Int {
		rows.filter { if case .file = $0 { return true } else { return false } }.count
	}

	private func makeWindow() -> NSPanel {
		heading = NSTextField(labelWithString: "")
		heading.font = Theme.current.uiFont(12)
		heading.textColor = Theme.current.gitIgnored

		table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = Theme.current.scaled(24)
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.selectionHighlightStyle = .regular
		table.style = .plain
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("usage")))
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.action = #selector(rowClicked)

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.scrollerStyle = .overlay

		// A list of usages is something you work through, so it can be moved out
		// of the way of the code it is about rather than floating over it.
		dockButton = NSButton(title: "Dock", target: self, action: #selector(dockClicked))
		dockButton.bezelStyle = .rounded
		dockButton.controlSize = .small
		dockButton.font = Theme.current.uiFont(11)
		dockButton.toolTip = "Show these in the sidebar instead"

		let container = ColoredView(color: Theme.current.sidebarBackground)
		container.addSubview(heading)
		container.addSubview(dockButton)
		container.addSubview(scroll)
		heading.translatesAutoresizingMaskIntoConstraints = false
		dockButton.translatesAutoresizingMaskIntoConstraints = false
		scroll.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
			heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),

			dockButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
			dockButton.leadingAnchor.constraint(
				greaterThanOrEqualTo: heading.trailingAnchor, constant: 12
			),
			dockButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

			scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
			scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])

		// No full-size content: the heading would be drawn under the titlebar,
		// on top of the title and the traffic lights.
		let window = UsagesWindow(
			contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: true
		)
		window.title = "Usages"
		window.backgroundColor = Theme.current.sidebarBackground
		window.contentView = container
		window.onClose = { [weak self] in self?.hide() }
		return window
	}

	/// Hands the list to the window, and closes the panel it was floating in.
	///
	/// The same table moves across rather than being rebuilt, so the scroll
	/// position and the selection survive the move.
	@objc private func dockClicked() {
		guard let content = window?.contentView else { return }
		heading.isHidden = true
		dockButton.isHidden = true
		content.removeFromSuperview()
		hide()
		onDock?(content, lastTitle)
	}

	@objc private func rowClicked() {
		let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
		guard rows.indices.contains(row), case let .usage(location, _) = rows[row] else { return }
		onOpen?(location)
	}

	// MARK: - Testing

	func dockForTesting() { dockClicked() }

	var rowsForTesting: [String] {
		rows.map { row in
			switch row {
			case let .file(path, count): return "# \((path as NSString).lastPathComponent) (\(count))"
			case let .usage(location, line): return "\(location.range.start.line + 1): \(line)"
			}
		}
	}
}

extension UsagesPanel: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		guard rows.indices.contains(row) else { return false }
		if case .file = rows[row] { return false }
		return true
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard rows.indices.contains(row) else { return nil }
		switch rows[row] {
		case let .file(path, count):
			return UsageFileRow(path: path, count: count)
		case let .usage(location, line):
			return UsageRow(line: location.range.start.line + 1, text: line)
		}
	}
}

/// Closes rather than hides, so the next search opens a fresh one.
private final class UsagesWindow: NSPanel {
	var onClose: (() -> Void)?
	override var canBecomeKey: Bool { true }

	override func close() {
		onClose?()
		super.close()
	}

	override func cancelOperation(_ sender: Any?) {
		onClose?()
	}
}

private final class UsageFileRow: NSView {
	private let path: String
	private let count: Int
	override var isFlipped: Bool { true }

	init(path: String, count: Int) {
		self.path = path
		self.count = count
		super.init(frame: .zero)
		toolTip = path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let name = NSAttributedString(string: (path as NSString).lastPathComponent, attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(11.5), weight: .semibold),
			.foregroundColor: Theme.current.sidebarText,
		])
		name.draw(at: NSPoint(x: Theme.current.scaled(12), y: bounds.midY - name.size().height / 2))

		let tally = NSAttributedString(string: "\(count)", attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		tally.draw(at: NSPoint(
			x: Theme.current.scaled(12) + name.size().width + Theme.current.scaled(8),
			y: bounds.midY - tally.size().height / 2
		))
	}
}

/// One usage: the line number, and the line.
private final class UsageRow: NSView {
	private let line: Int
	private let text: String
	override var isFlipped: Bool { true }

	init(line: Int, text: String) {
		self.line = line
		self.text = text
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let number = NSAttributedString(string: "\(line)", attributes: [
			.font: Theme.terminalFont(size: Theme.current.fontSize - 2),
			.foregroundColor: Theme.current.gitIgnored,
		])
		// Right-aligned in a fixed gutter, so the code beside them lines up.
		let gutter = Theme.current.scaled(52)
		number.draw(at: NSPoint(
			x: gutter - number.size().width,
			y: bounds.midY - number.size().height / 2
		))

		let code = NSAttributedString(string: text, attributes: [
			.font: Theme.terminalFont(size: Theme.current.fontSize - 1),
			.foregroundColor: Theme.current.sidebarText,
		])
		code.draw(in: NSRect(
			x: gutter + Theme.current.scaled(10),
			y: bounds.midY - code.size().height / 2,
			width: max(0, bounds.width - gutter - Theme.current.scaled(20)),
			height: code.size().height
		))
	}
}

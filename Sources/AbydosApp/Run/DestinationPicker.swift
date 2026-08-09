import AppKit
import AbydosKit

/// Choosing among the simulators that are not in the menu.
///
/// A real project answers with 75 of them — 23 models against every installed
/// runtime — and a menu that long is a column running off the screen with no
/// way to search it. The menu keeps what somebody picks by name; this is where
/// the rest stays reachable.
///
/// A panel rather than a sheet: picking where to run is not a decision about
/// the window it is attached to, and a sheet would stop the app while somebody
/// reads a list.
@MainActor
final class DestinationPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate {
	private let all: [XcodeDestination]
	private var shown: [XcodeDestination]
	private let onChoose: (XcodeDestination) -> Void

	private let panel: NSPanel
	private let field = NSSearchField()
	private let table = NSTableView()

	/// Held while the panel is up, since nothing else owns it.
	private static var open: DestinationPicker?

	static func show(
		among destinations: [XcodeDestination],
		relativeTo window: NSWindow?,
		onChoose: @escaping (XcodeDestination) -> Void
	) {
		open = DestinationPicker(among: destinations, onChoose: onChoose)
		open?.present(relativeTo: window)
	}

	private init(among: [XcodeDestination], onChoose: @escaping (XcodeDestination) -> Void) {
		self.all = among
		self.shown = among
		self.onChoose = onChoose
		panel = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
			styleMask: [.titled, .closable, .resizable, .utilityWindow],
			backing: .buffered,
			defer: false
		)
		super.init()
		build()
	}

	private func build() {
		panel.title = "Choose a simulator"
		panel.isFloatingPanel = true
		panel.hidesOnDeactivate = false

		field.placeholderString = "Filter by model or version"
		field.target = self
		field.action = #selector(filterChanged)
		// Every keystroke rather than only Return: a filter somebody has to
		// commit is a search box, and this is meant to narrow as they type.
		field.sendsSearchStringImmediately = true
		field.sendsWholeSearchString = false

		table.headerView = nil
		table.rowSizeStyle = .default
		table.addTableColumn(
			NSTableColumn(identifier: NSUserInterfaceItemIdentifier("destination"))
		)
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(chooseSelected)

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.borderType = .bezelBorder

		let choose = NSButton(title: "Run Here", target: self, action: #selector(chooseSelected))
		choose.keyEquivalent = "\r"
		let cancel = NSButton(title: "Cancel", target: self, action: #selector(close))
		cancel.keyEquivalent = "\u{1b}"

		let buttons = NSStackView(views: [cancel, choose])
		buttons.orientation = .horizontal
		buttons.spacing = 10

		let stack = NSStackView(views: [field, scroll, buttons])
		stack.orientation = .vertical
		stack.spacing = 10
		stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
		stack.translatesAutoresizingMaskIntoConstraints = false
		panel.contentView = NSView()
		panel.contentView?.addSubview(stack)

		guard let content = panel.contentView else { return }
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			stack.topAnchor.constraint(equalTo: content.topAnchor),
			stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
			buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -14),
		])
	}

	private func present(relativeTo window: NSWindow?) {
		if let window {
			panel.setFrameOrigin(NSPoint(
				x: window.frame.midX - panel.frame.width / 2,
				y: window.frame.midY - panel.frame.height / 2
			))
		} else {
			panel.center()
		}
		panel.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		// The field, not the list: somebody opening this is looking for one of
		// seventy-five, and typing is how they find it.
		panel.makeFirstResponder(field)
		if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
	}

	@objc private func filterChanged() {
		shown = all.filter { XcodeDestinationMenu.matches($0, field.stringValue) }
		table.reloadData()
		if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
	}

	@objc private func chooseSelected() {
		let row = table.selectedRow
		guard shown.indices.contains(row) else { return }
		let chosen = shown[row]
		close()
		onChoose(chosen)
	}

	@objc private func close() {
		panel.orderOut(nil)
		Self.open = nil
	}

	// MARK: - Table

	func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

	func tableView(
		_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
	) -> NSView? {
		guard shown.indices.contains(row) else { return nil }
		let label = NSTextField(labelWithString: shown[row].title)
		label.font = Theme.current.uiFont(12)
		label.lineBreakMode = .byTruncatingTail
		return label
	}

	/// Return in the filter field runs the top match, which is the whole point
	/// of the filter narrowing as it is typed.
	func control(
		_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
	) -> Bool {
		guard control === field else { return false }
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			chooseSelected()
			return true
		case #selector(NSResponder.moveDown(_:)):
			panel.makeFirstResponder(table)
			return true
		default:
			return false
		}
	}
}

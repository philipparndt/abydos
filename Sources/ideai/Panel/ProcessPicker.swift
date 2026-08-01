import AppKit
import IdeaiKit

/// Choosing a running process to attach the debugger to.
///
/// A list you can type into rather than a popup menu: there are two hundred
/// processes on any machine, and the one somebody wants is found by name, not
/// by scrolling. Its own panel rather than a system alert, so it looks like
/// the rest of the window.
@MainActor
final class ProcessPicker: NSObject {
	var onAttach: ((RunningProcess) -> Void)?

	private var window: NSPanel?
	private var searchField: NSTextField!
	private var table: NSTableView!
	private var all: [RunningProcess] = []
	private var shown: [RunningProcess] = []

	func show(processes: [RunningProcess], over parent: NSWindow?) {
		guard let parent else { return }
		all = processes
		shown = processes

		let window = makeWindow()
		self.window = window

		let frame = parent.frame
		let size = NSSize(width: min(620, frame.width - 120), height: min(460, frame.height - 160))
		window.setFrame(NSRect(
			x: frame.midX - size.width / 2,
			y: frame.midY - size.height / 2 + frame.height * 0.05,
			width: size.width,
			height: size.height
		), display: true)

		parent.addChildWindow(window, ordered: .above)
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
			window.makeFirstResponder(searchField)
		} else {
			window.orderFront(nil)
		}
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
	}

	private func close() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		self.window = nil
	}

	// MARK: - Building

	private func makeWindow() -> NSPanel {
		searchField = NSTextField()
		searchField.placeholderString = "Filter by name or id"
		searchField.font = Theme.current.uiFont(13)
		searchField.textColor = Theme.current.sidebarText
		searchField.backgroundColor = Theme.current.editorBackground
		searchField.drawsBackground = true
		searchField.isBezeled = true
		searchField.bezelStyle = .roundedBezel
		searchField.focusRingType = .none
		searchField.delegate = self

		table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = Theme.current.scaled(30)
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.style = .plain
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("process")))
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(attach)

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.scrollerStyle = .overlay

		let hint = NSTextField(labelWithString: "The debugger stops it where it is.")
		hint.font = Theme.current.uiFont(10.5)
		hint.textColor = Theme.current.gitIgnored

		let attachButton = NSButton(title: "Attach", target: self, action: #selector(attach))
		attachButton.bezelStyle = .rounded
		attachButton.keyEquivalent = "\r"

		let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
		cancelButton.bezelStyle = .rounded
		cancelButton.keyEquivalent = "\u{1b}"

		let content = ColoredView(color: Theme.current.sidebarBackground)
		for view in [searchField, scroll, hint, attachButton, cancelButton] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}

		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
			searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
			searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
			searchField.heightAnchor.constraint(equalToConstant: 24),

			scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
			scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: attachButton.topAnchor, constant: -12),

			hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
			hint.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor),

			attachButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
			attachButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
			cancelButton.trailingAnchor.constraint(equalTo: attachButton.leadingAnchor, constant: -8),
			cancelButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor),
		])

		let window = PickerPanel(
			contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: true
		)
		window.title = "Attach to a Process"
		window.backgroundColor = Theme.current.sidebarBackground
		window.contentView = content
		window.onCancel = { [weak self] in self?.cancel() }
		return window
	}

	// MARK: - Actions

	@objc private func attach() {
		let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
		guard shown.indices.contains(row) else { return }
		let chosen = shown[row]
		close()
		onAttach?(chosen)
	}

	@objc private func cancel() { close() }

	private func filter(_ query: String) {
		let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
		shown = trimmed.isEmpty
			? all
			: all.filter {
				$0.name.lowercased().contains(trimmed)
					|| "\($0.pid)".hasPrefix(trimmed)
					|| $0.path.lowercased().contains(trimmed)
			}
		table.reloadData()
		guard !shown.isEmpty else { return }
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
	}

	// MARK: - Testing

	var shownNamesForTesting: [String] { shown.map(\.name) }

	func filterForTesting(_ query: String) { filter(query) }

	func attachForTesting(row: Int) {
		table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		attach()
	}
}

extension ProcessPicker: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard shown.indices.contains(row) else { return nil }
		return ProcessRowView(process: shown[row])
	}
}

extension ProcessPicker: NSTextFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		filter(searchField.stringValue)
	}

	/// Down out of the field moves into the list, so the keyboard alone can
	/// pick a process.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.moveDown(_:)):
			window?.makeFirstResponder(table)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			attach()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			cancel()
			return true
		default:
			return false
		}
	}
}

/// Closes on escape, like every other dialog here.
private final class PickerPanel: NSPanel {
	var onCancel: (() -> Void)?
	override var canBecomeKey: Bool { true }

	override func close() { onCancel?() }
	override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// One process: what it is called, what it is, and where it lives.
private final class ProcessRowView: NSView {
	private let process: RunningProcess
	override var isFlipped: Bool { true }

	init(process: RunningProcess) {
		self.process = process
		super.init(frame: .zero)
		toolTip = process.path == process.name ? process.name : process.path
	}

	/// Centred when there is only a name to show, so a list of unresolved
	/// processes does not look like it is missing a line each.
	private var hasPath: Bool { process.path != process.name && process.path.hasPrefix("/") }

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let name = NSAttributedString(string: process.name, attributes: [
			.font: Theme.current.uiFont(12.5, weight: .medium),
			.foregroundColor: Theme.current.sidebarText,
		])
		let nameY = hasPath ? Theme.current.scaled(3) : bounds.midY - name.size().height / 2
		name.draw(at: NSPoint(x: Theme.current.scaled(14), y: nameY))

		// The id, right where the eye lands after the name, in the font it is
		// read in everywhere else.
		let pid = NSAttributedString(string: "\(process.pid)", attributes: [
			.font: Theme.terminalFont(size: Theme.current.fontSize - 2),
			.foregroundColor: Theme.current.gitIgnored,
		])
		pid.draw(at: NSPoint(
			x: Theme.current.scaled(14) + name.size().width + Theme.current.scaled(8),
			y: nameY + Theme.current.scaled(1)
		))

		// `ps` reports only a name for a process it cannot resolve a path for,
		// and repeating the name underneath itself says nothing.
		guard process.path != process.name, process.path.hasPrefix("/") else { return }
		let path = NSAttributedString(string: process.path, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		path.draw(in: NSRect(
			x: Theme.current.scaled(14),
			y: Theme.current.scaled(16),
			width: max(0, bounds.width - Theme.current.scaled(28)),
			height: path.size().height
		))
	}
}

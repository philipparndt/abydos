import AppKit
import IdeaiKit

/// The dropdown anchored to the project pill: actions on top, then open
/// projects, then recents — each with its badge and home-relative path.
enum ProjectSwitcherPopover {
	private static var active: NSPopover?
	private static weak var activeController: SwitcherViewController?

	/// Drives the filter from a capture run, so the filtered state can be seen.
	static func applyFilterForTesting(_ text: String) {
		activeController?.setFilter(text)
	}

	static func show(relativeTo pill: PillButton, currentProject: Project?) {
		// Clicking the pill while open should dismiss rather than stack popovers.
		if let active, active.isShown {
			active.close()
			Self.active = nil
			return
		}

		let controller = SwitcherViewController(currentProject: currentProject)
		let popover = NSPopover()
		popover.contentViewController = controller
		popover.behavior = .transient
		popover.appearance = NSAppearance(named: .darkAqua)

		controller.onDismiss = { [weak popover] in popover?.close() }
		pill.isMenuOpen = true
		popover.willClose = {
			pill.isMenuOpen = false
			Self.active = nil
		}

		active = popover
		activeController = controller
		popover.show(relativeTo: pill.bounds, of: pill, preferredEdge: .maxY)
		// The table needs to be first responder for arrow keys to work immediately.
		controller.focusTable()
	}
}

/// NSPopover has no close callback, so this small subclass-free shim routes
/// `popoverWillClose` through a stored closure.
private extension NSPopover {
	private static var willCloseKey: UInt8 = 0

	var willClose: (() -> Void)? {
		get { (objc_getAssociatedObject(self, &Self.willCloseKey) as? ClosureBox)?.closure }
		set {
			objc_setAssociatedObject(self, &Self.willCloseKey, newValue.map(ClosureBox.init), .OBJC_ASSOCIATION_RETAIN)
			if delegate == nil { delegate = PopoverCloseObserver.shared }
		}
	}
}

private final class ClosureBox: NSObject {
	let closure: () -> Void
	init(_ closure: @escaping () -> Void) { self.closure = closure }
}

private final class PopoverCloseObserver: NSObject, NSPopoverDelegate {
	static let shared = PopoverCloseObserver()

	func popoverWillClose(_ notification: Notification) {
		guard let popover = notification.object as? NSPopover else { return }
		popover.willClose?()
	}
}

// MARK: - Content

private final class SwitcherViewController: NSViewController {
	enum Row {
		case action(title: String, symbol: String, handler: () -> Void)
		case header(String)
		case project(RecentProject, isOpen: Bool)

		var isSelectable: Bool {
			if case .header = self { return false }
			return true
		}

		var height: CGFloat {
			switch self {
			case .action: return Theme.current.scaled(26)
			case .header: return Theme.current.scaled(28)
			case .project: return Theme.current.scaled(42)
			}
		}
	}

	var onDismiss: (() -> Void)?

	private let currentProject: Project?
	private var rows: [Row] = []
	private var tableView: NSTableView!
	private var filterField: NSSearchField!
	/// What the user has typed. Empty shows the full menu.
	private var filterText = "" 

	init(currentProject: Project?) {
		self.currentProject = currentProject
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func loadView() {
		buildRows()

		// The cached scan is shown immediately and refreshed behind it, so the
		// popover never waits on the file system to appear.
		DiscoveryCache.refresh { [weak self] in
			guard let self, self.isViewLoaded else { return }
			self.buildRows()
			self.tableView.reloadData()
			self.updatePreferredSize()
		}

		let table = SwitcherTableView()
		table.headerView = nil
		table.backgroundColor = .clear
		// Same reason as the navigator: `.none` would stop drawSelection running.
		table.selectionHighlightStyle = .regular
		table.intercellSpacing = .zero
		table.rowSizeStyle = .custom
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.action = #selector(rowClicked)
		table.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
		tableView = table

		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.autohidesScrollers = true

		// A visible field, so what you type is on screen and obviously a filter,
		// rather than an invisible jump-to-match you have to guess at.
		let field = NSSearchField()
		field.placeholderString = "Filter projects"
		field.font = Theme.current.uiFont(12)
		field.delegate = self
		field.focusRingType = .none
		filterField = field

		let container = ColoredView(color: .hex(0x2B2D30))
		container.addSubview(field)
		container.addSubview(scrollView)
		field.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			field.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
			field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
			field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

			scrollView.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 6),
			scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
		])

		view = container
		updatePreferredSize()
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		selectFirstSelectableRow()
	}

	/// The field takes focus, so typing filters immediately. Arrow keys are
	/// forwarded to the list from there.
	func focusTable() {
		view.window?.makeFirstResponder(filterField)
	}

	/// Sets the filter programmatically, used by capture runs.
	func setFilter(_ text: String) {
		filterField.stringValue = text
		applyFilter(text)
	}

	/// Height tracks content up to a cap, so a short list yields a short menu.
	private func updatePreferredSize() {
		let contentHeight = rows.reduce(0) { $0 + $1.height } + Theme.current.scaled(52)
		preferredContentSize = NSSize(
			width: Theme.current.scaled(340),
			height: min(max(contentHeight, Theme.current.scaled(120)), Theme.current.scaled(560))
		)
	}

	/// Checkouts found by scanning, refreshed in the background.
	///
	/// Cached on the type rather than the popover: the popover is rebuilt on
	/// every open, and a fresh scan each time would make the first frame wait on
	/// the file system.
	private enum DiscoveryCache {
		private static var projects: [RecentProject] = []
		private static var isScanning = false

		static var current: [RecentProject] { projects }

		/// Rescans unless one is already in flight.
		static func refresh(completion: @escaping () -> Void) {
			guard !isScanning else { return }
			isScanning = true

			let paths = Settings.shared.projectSearchPaths
			let depth = Settings.shared.projectSearchDepth

			DispatchQueue.global(qos: .userInitiated).async {
				let roots = ProjectDiscovery.resolve(searchPaths: paths)
				let found = ProjectDiscovery.scan(roots: roots, maxDepth: depth)

				// Presented as recents so every downstream rule — filtering,
				// badges, row layout — applies unchanged. The date is when the
				// checkout was last worked on rather than last opened here, which
				// is the ordering the list wants anyway.
				let converted = found.map {
					RecentProject(path: $0.url.path, lastOpened: $0.lastActivity)
				}

				DispatchQueue.main.async {
					projects = converted
					isScanning = false
					completion()
				}
			}
		}
	}

	/// Discovered checkouts that are not already listed above.
	private func discoveredProjects(excluding paths: Set<String>) -> [RecentProject] {
		DiscoveryCache.current.filter { !paths.contains($0.path) }
	}

	// MARK: - Rows

	private func buildRows() {
		let delegate = NSApp.delegate as? AppDelegate
		RecentProjects.shared.pruneMissing()

		// While filtering, the list is only matching projects: the New/Open/Clone
		// actions are not things a filter can match, and keeping them would push
		// the results down.
		guard filterText.isEmpty else {
			buildFilteredRows(delegate: delegate)
			return
		}

		rows = [
			.action(title: "New Project…", symbol: "plus") { [weak self] in
				self?.onDismiss?()
				self?.newProject()
			},
			.action(title: "Open…", symbol: "folder") { [weak self] in
				self?.onDismiss?()
				delegate?.openProjectPanel(nil)
			},
			.action(title: "Clone Repository…", symbol: "arrow.trianglehead.branch") { [weak self] in
				self?.onDismiss?()
				self?.cloneRepository()
			},
		]

		let openRoots = delegate?.openProjectRoots ?? []
		let openPaths = Set(openRoots.map(\.path))

		if !openRoots.isEmpty {
			rows.append(.header("Open Projects"))
			let recents = RecentProjects.shared.entries
			for root in openRoots {
				let entry = recents.first { $0.path == root.path }
					?? RecentProject(path: root.path, lastOpened: Date())
				rows.append(.project(entry, isOpen: true))
			}
		}

		// Recents excludes what is already listed above to avoid duplicates.
		let recents = RecentProjects.shared.entries.filter { !openPaths.contains($0.path) }
		if !recents.isEmpty {
			rows.append(.header("Recent Projects"))
			for entry in recents {
				rows.append(.project(entry, isOpen: false))
			}
		}

		// Everything else found on disk. A switcher that lists only what has
		// been opened before cannot help with the case it exists for: opening a
		// project for the first time.
		var listed = openPaths
		listed.formUnion(recents.map(\.path))
		let discovered = discoveredProjects(excluding: listed)
		if !discovered.isEmpty {
			rows.append(.header("All Projects"))
			for entry in discovered {
				rows.append(.project(entry, isOpen: false))
			}
		}
	}

	/// Matches on both name and path, so "3d" finds everything under ~/dev/3d.
	private func buildFilteredRows(delegate: AppDelegate?) {
		let needle = filterText.lowercased()
		let openPaths = Set((delegate?.openProjectRoots ?? []).map(\.path))

		var candidates = RecentProjects.shared.entries
		for root in delegate?.openProjectRoots ?? [] where !candidates.contains(where: { $0.path == root.path }) {
			candidates.append(RecentProject(path: root.path, lastOpened: Date()))
		}

		// Typing searches everything on disk, not just what has been opened.
		let known = Set(candidates.map(\.path))
		candidates.append(contentsOf: discoveredProjects(excluding: known))

		rows = ProjectFilter.match(candidates, query: needle)
			.map { .project($0, isOpen: openPaths.contains($0.path)) }
	}

	private func applyFilter(_ text: String) {
		filterText = text.trimmingCharacters(in: .whitespaces)
		buildRows()
		tableView.reloadData()
		updatePreferredSize()
		selectFirstSelectableRow()
	}

	// MARK: - Actions

	@objc private func rowClicked() {
		activateRow(at: tableView.clickedRow)
	}

	private func activateRow(at index: Int) {
		guard rows.indices.contains(index) else { return }
		switch rows[index] {
		case let .action(_, _, handler):
			handler()
		case .header:
			break
		case let .project(entry, _):
			onDismiss?()
			(NSApp.delegate as? AppDelegate)?.open(projectAt: entry.url)
		}
	}

	private func newProject() {
		let panel = NSSavePanel()
		panel.title = "New Project"
		panel.prompt = "Create"
		panel.nameFieldLabel = "Project name:"
		panel.canCreateDirectories = true

		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			(NSApp.delegate as? AppDelegate)?.open(projectAt: url)
		} catch {
			NSAlert(error: error).runModal()
		}
	}

	private func cloneRepository() {
		let alert = NSAlert()
		alert.messageText = "Clone Repository"
		alert.informativeText = "Enter a repository URL. It will be cloned into a directory you choose."
		alert.addButton(withTitle: "Choose Location…")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		field.placeholderString = "https://github.com/owner/repo.git"
		alert.accessoryView = field
		alert.window.initialFirstResponder = field

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let remote = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !remote.isEmpty else { return }

		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.prompt = "Clone Here"
		guard panel.runModal() == .OK, let parent = panel.url else { return }

		// Derive the destination the way `git clone` would.
		let name = URL(fileURLWithPath: remote).deletingPathExtension().lastPathComponent
		let destination = parent.appendingPathComponent(name)

		Task {
			let result = await GitRepository.run(["clone", remote, destination.path], in: parent)
			await MainActor.run {
				if result.exitCode == 0 {
					(NSApp.delegate as? AppDelegate)?.open(projectAt: destination)
				} else {
					let alert = NSAlert()
					alert.alertStyle = .warning
					alert.messageText = "Clone failed"
					alert.informativeText = result.stderr.isEmpty ? "git exited with code \(result.exitCode)." : result.stderr
					alert.runModal()
				}
			}
		}
	}

	// MARK: - Keyboard

	private func selectFirstSelectableRow() {
		if let index = rows.firstIndex(where: { $0.isSelectable }) {
			tableView.selectRowIndexes([index], byExtendingSelection: false)
		}
	}

	/// Returns true when the event was consumed.
	private func handleKeyDown(_ event: NSEvent) -> Bool {
		switch event.keyCode {
		case 36, 76: // Return, Keypad Enter
			activateRow(at: tableView.selectedRow)
			return true
		case 53: // Escape
			onDismiss?()
			return true
		case 125: // Down
			moveSelection(by: 1)
			return true
		case 126: // Up
			moveSelection(by: -1)
			return true
		default:
			// Everything else belongs to the filter field.
			return false
		}
	}

	private func moveSelection(by delta: Int) {
		var index = tableView.selectedRow
		// Step past headers so selection never lands on a non-selectable row.
		repeat {
			index += delta
		} while rows.indices.contains(index) && !rows[index].isSelectable

		guard rows.indices.contains(index) else { return }
		tableView.selectRowIndexes([index], byExtendingSelection: false)
		tableView.scrollRowToVisible(index)
	}

}

// MARK: - Table data

extension SwitcherViewController: NSSearchFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		applyFilter(filterField.stringValue)
	}

	/// Arrows and Return work while the field has focus, so filtering and
	/// choosing are one continuous gesture.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.moveDown(_:)):
			moveSelection(by: 1)
			return true
		case #selector(NSResponder.moveUp(_:)):
			moveSelection(by: -1)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			activateRow(at: tableView.selectedRow)
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			// Escape clears the filter first, and only then closes.
			if filterText.isEmpty {
				onDismiss?()
			} else {
				filterField.stringValue = ""
				applyFilter("")
			}
			return true
		default:
			return false
		}
	}
}

extension SwitcherViewController: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		rows[row].height
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		rows[row].isSelectable
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		SwitcherRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		switch rows[row] {
		case let .action(title, symbol, _):
			return SwitcherActionCell(title: title, symbol: symbol)
		case let .header(title):
			return SwitcherHeaderCell(title: title)
		case let .project(entry, isOpen):
			return SwitcherProjectCell(entry: entry, isOpen: isOpen)
		}
	}
}

// MARK: - Table subclass

private final class SwitcherTableView: NSTableView {
	var onKeyDown: ((NSEvent) -> Bool)?

	/// Row under the pointer, so rows light up on hover the way a menu does.
	private var hoveredRow: Int = -1
	private var trackingArea: NSTrackingArea?

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	// The popover's table should take focus so arrow keys work on open.
	override var acceptsFirstResponder: Bool { true }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		setHovered(row(at: point))
	}

	override func mouseExited(with event: NSEvent) {
		setHovered(-1)
	}

	private func setHovered(_ newRow: Int) {
		guard newRow != hoveredRow else { return }
		let previous = hoveredRow
		hoveredRow = newRow

		// Repaint only the two rows involved rather than the whole table.
		for candidate in [previous, newRow] where candidate >= 0 {
			(rowView(atRow: candidate, makeIfNecessary: false) as? SwitcherRowView)?
				.setHovered(candidate == newRow)
		}
	}
}

/// Draws the blue selection band, and a lighter band on hover.
private final class SwitcherRowView: NSTableRowView {
	private var isHovered = false

	func setHovered(_ hovered: Bool) {
		guard hovered != isHovered else { return }
		isHovered = hovered
		needsDisplay = true
	}

	override func drawBackground(in dirtyRect: NSRect) {
		super.drawBackground(in: dirtyRect)
		// Only when not selected, so hover never competes with the selection.
		guard isHovered, !isSelected else { return }
		NSColor.white.withAlphaComponent(0.07).setFill()
		bounds.fill()
	}

	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selectionActive.setFill()
		bounds.fill()
	}

	override var isEmphasized: Bool {
		get { true }
		set {}
	}
}

// MARK: - Cells

private final class SwitcherActionCell: NSView {
	private let title: String
	private let symbol: String

	init(title: String, symbol: String) {
		self.title = title
		self.symbol = symbol
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let tint = Theme.current.sidebarText
		var x: CGFloat = 12

		// Colour baked into the symbol configuration — see Theme.symbol.
		if let rendered = Theme.symbol(symbol, size: 12 * Theme.current.scale, color: tint) {
			// respectFlipped: this view is flipped; without it the glyph mirrors.
			rendered.drawFitted(in: NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14))
		}
		x += 22

		let attributed = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(13),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		attributed.draw(at: NSPoint(x: x, y: bounds.midY - attributed.size().height / 2))
	}
}

private final class SwitcherHeaderCell: NSView {
	private let title: String

	init(title: String) {
		self.title = title
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// A hairline above the group, except at the very top of the list.
		if bounds.minY > 0 {
			Theme.current.separator.setFill()
			NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
		}

		let attributed = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(11, weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		attributed.draw(at: NSPoint(x: 12, y: bounds.height - attributed.size().height - 4))
	}
}

private final class SwitcherProjectCell: NSView {
	private let entry: RecentProject
	private let isOpen: Bool
	private let badge: NSImage

	init(entry: RecentProject, isOpen: Bool) {
		self.entry = entry
		self.isOpen = isOpen
		self.badge = ProjectBadge.image(for: entry.name, colorIndex: entry.colorIndex, size: Theme.current.scaled(22))
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let badgeSize = Theme.current.scaled(22)
		badge.draw(in: NSRect(x: Theme.current.scaled(12), y: bounds.midY - badgeSize / 2, width: badgeSize, height: badgeSize))

		let name = NSAttributedString(string: entry.name, attributes: [
			.font: Theme.current.uiFont(13),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let path = NSAttributedString(string: entry.displayPath, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.gitIgnored,
		])

		// Name and path stacked, matching the reference menu.
		name.draw(at: NSPoint(x: Theme.current.scaled(44), y: bounds.midY - name.size().height - 1))
		path.draw(at: NSPoint(x: Theme.current.scaled(44), y: bounds.midY + 2))
	}
}

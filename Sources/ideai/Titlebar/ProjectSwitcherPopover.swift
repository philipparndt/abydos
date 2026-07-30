import AppKit
import IdeaiKit

/// The dropdown anchored to the project pill: actions on top, then open
/// projects, then recents — each with its badge and home-relative path.
enum ProjectSwitcherPopover {
	private static var active: NSPopover?

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
			case .action: return 26
			case .header: return 28
			case .project: return 42
			}
		}
	}

	var onDismiss: (() -> Void)?

	private let currentProject: Project?
	private var rows: [Row] = []
	private var tableView: NSTableView!
	/// Accumulated keystrokes for type-to-jump, cleared after a short pause.
	private var typeAheadBuffer = ""
	private var typeAheadResetWork: DispatchWorkItem?

	init(currentProject: Project?) {
		self.currentProject = currentProject
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func loadView() {
		buildRows()

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

		let container = ColoredView(color: .hex(0x2B2D30))
		container.addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
			scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
		])

		// Height tracks content up to a cap, so a short recents list yields a
		// short menu instead of a mostly-empty panel.
		let contentHeight = rows.reduce(0) { $0 + $1.height } + 12
		view = container
		preferredContentSize = NSSize(width: 340, height: min(contentHeight, 560))
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		selectFirstSelectableRow()
	}

	func focusTable() {
		view.window?.makeFirstResponder(tableView)
	}

	// MARK: - Rows

	private func buildRows() {
		let delegate = NSApp.delegate as? AppDelegate
		RecentProjects.shared.pruneMissing()

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
			// Letters jump to a matching project name.
			guard let characters = event.charactersIgnoringModifiers,
			      !characters.isEmpty,
			      event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
			      characters.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
			else { return false }
			typeAhead(characters)
			return true
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

	private func typeAhead(_ characters: String) {
		typeAheadBuffer += characters.lowercased()

		// Reset the buffer after a pause so a later burst starts a fresh search.
		typeAheadResetWork?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.typeAheadBuffer = "" }
		typeAheadResetWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)

		let needle = typeAheadBuffer
		let match = rows.firstIndex { row in
			guard case let .project(entry, _) = row else { return false }
			return entry.name.lowercased().hasPrefix(needle)
		} ?? rows.firstIndex { row in
			// Fall back to a substring match so "sonos" finds "mqtt-sonos".
			guard case let .project(entry, _) = row else { return false }
			return entry.name.lowercased().contains(needle)
		}

		guard let match else { return }
		tableView.selectRowIndexes([match], byExtendingSelection: false)
		tableView.scrollRowToVisible(match)
	}
}

// MARK: - Table data

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

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	// The popover's table should take focus so arrow keys work on open.
	override var acceptsFirstResponder: Bool { true }
}

/// Draws the blue selection band behind the whole row.
private final class SwitcherRowView: NSTableRowView {
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
		if let rendered = Theme.symbol(symbol, size: 12, color: tint) {
			// respectFlipped: this view is flipped; without it the glyph mirrors.
			rendered.draw(
				in: NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
		}
		x += 22

		let attributed = NSAttributedString(string: title, attributes: [
			.font: NSFont.systemFont(ofSize: 13),
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
			.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
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
		self.badge = ProjectBadge.image(for: entry.name, colorIndex: entry.colorIndex, size: 22)
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		badge.draw(in: NSRect(x: 12, y: bounds.midY - 11, width: 22, height: 22))

		let name = NSAttributedString(string: entry.name, attributes: [
			.font: NSFont.systemFont(ofSize: 13),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let path = NSAttributedString(string: entry.displayPath, attributes: [
			.font: NSFont.systemFont(ofSize: 11),
			.foregroundColor: Theme.current.gitIgnored,
		])

		// Name and path stacked, matching the reference menu.
		name.draw(at: NSPoint(x: 44, y: bounds.midY - name.size().height - 1))
		path.draw(at: NSPoint(x: 44, y: bounds.midY + 2))
	}
}

import AppKit
import IdeaiKit

extension Notification.Name {
	/// A scratch was made, renamed, moved or thrown away.
	static let ideaiScratchesChanged = Notification.Name("ideai.scratchesChanged")
}

/// Every scratch on the machine, searchable by what is written in it.
///
/// The tab strip only shows the ones you have open, and a scratch worth
/// keeping is usually one you closed weeks ago. This is where they are all
/// still here: the current project's first, then the ones that belong to no
/// project, then everything else — because a note is looked for either where
/// you are or in the pile you keep for good.
final class ScratchesPane: NSView {
	/// Open a scratch; provisional for a click, permanent for a double-click.
	var onOpen: ((URL, _ preview: Bool) -> Void)?
	/// A scratch was renamed or thrown away, so any tab showing it must follow.
	var onMoved: ((_ from: URL, _ to: URL?) -> Void)?
	/// About to move a scratch: anything typed into it and not yet written must
	/// be written first, or the rename would carry the old contents.
	var onWillModify: ((URL) -> Void)?

	/// The project this window has open, whose notes come first.
	private var projectRoot: URL?

	private var matches: [ScratchMatch] = []
	private var rows: [Row] = []
	private var query = ""

	private var searchField: NSSearchField!
	private var tableView: ScratchTableView!
	private var emptyLabel: NSTextField!

	private enum Row {
		case header(String)
		case scratch(ScratchMatch)
	}

	init(projectRoot: URL?) {
		self.projectRoot = projectRoot
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		reload()

		NotificationCenter.default.addObserver(
			self, selector: #selector(reload), name: .ideaiScratchesChanged, object: nil
		)
		// Something else may have written one — another window, or an editor
		// saving. Coming back to the app is when that becomes visible.
		NotificationCenter.default.addObserver(
			self, selector: #selector(reload), name: NSApplication.didBecomeActiveNotification, object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }
	deinit { NotificationCenter.default.removeObserver(self) }

	func setProject(_ root: URL?) {
		guard !ScratchFiles.isSameProject(root, projectRoot) else { return }
		projectRoot = root
		reload()
	}

	// MARK: - Layout

	private func build() {
		searchField = NSSearchField()
		searchField.placeholderString = "Search scratches"
		searchField.font = Theme.current.uiFont(12)
		searchField.focusRingType = .none
		searchField.delegate = self
		searchField.sendsWholeSearchString = false

		let newButton = NSButton(title: "New Scratch", target: self, action: #selector(newScratch))
		newButton.bezelStyle = .rounded
		newButton.controlSize = .small
		newButton.font = Theme.current.uiFont(11)

		let globalButton = NSButton(title: "New Global", target: self, action: #selector(newGlobalScratch))
		globalButton.bezelStyle = .rounded
		globalButton.controlSize = .small
		globalButton.font = Theme.current.uiFont(11)

		tableView = ScratchTableView()
		tableView.headerView = nil
		tableView.backgroundColor = Theme.current.sidebarBackground
		tableView.selectionHighlightStyle = .regular
		tableView.rowSizeStyle = .custom
		tableView.intercellSpacing = .zero
		tableView.gridStyleMask = []
		tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("scratch")))
		tableView.delegate = self
		tableView.dataSource = self
		tableView.menu = makeMenu()
		tableView.onActivate = { [weak self] in self?.openSelected(preview: false) }

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.sidebarBackground
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle

		emptyLabel = NSTextField(labelWithString: "No scratches yet")
		emptyLabel.font = Theme.current.uiFont(12)
		emptyLabel.textColor = Theme.current.gitIgnored
		emptyLabel.alignment = .center

		for view in [searchField, newButton, globalButton, scrollView, emptyLabel] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			newButton.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: inset / 2),
			newButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			globalButton.centerYAnchor.constraint(equalTo: newButton.centerYAnchor),
			globalButton.leadingAnchor.constraint(equalTo: newButton.trailingAnchor, constant: inset / 2),

			scrollView.topAnchor.constraint(equalTo: newButton.bottomAnchor, constant: inset / 2),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

			emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Theme.current.scaled(24)),
		])
	}

	// MARK: - Data

	@objc func reload() {
		matches = ScratchLibrary().search(query)
		rebuildRows()
	}

	private func rebuildRows() {
		rows = []

		// The project you are in, then the ones that belong to no project, then
		// the rest: a note is looked for either where you are or in the pile you
		// keep for good.
		var byProject: [String: [ScratchMatch]] = [:]
		var globals: [ScratchMatch] = []
		var mine: [ScratchMatch] = []
		var names: [String: String] = [:]

		for match in matches {
			guard let root = match.entry.projectRoot else {
				globals.append(match)
				continue
			}
			if ScratchFiles.isSameProject(root, projectRoot) {
				mine.append(match)
			} else {
				names[root.path] = root.lastPathComponent
				byProject[root.path, default: []].append(match)
			}
		}

		if !mine.isEmpty {
			append(section: projectRoot?.lastPathComponent ?? "This Project", mine)
		}
		append(section: "Global", globals)
		for path in byProject.keys.sorted(by: { (names[$0] ?? $0) < (names[$1] ?? $1) }) {
			append(section: names[path] ?? path, byProject[path] ?? [])
		}

		emptyLabel.isHidden = !rows.isEmpty
		emptyLabel.stringValue = query.isEmpty ? "No scratches yet" : "Nothing matches “\(query)”"
		tableView.reloadData()
	}

	private func append(section title: String, _ entries: [ScratchMatch]) {
		guard !entries.isEmpty else { return }
		rows.append(.header(title))
		rows.append(contentsOf: entries.map { Row.scratch($0) })
	}

	private var selectedMatch: ScratchMatch? {
		let clicked = tableView.clickedRow
		let row = clicked >= 0 ? clicked : tableView.selectedRow
		guard rows.indices.contains(row), case let .scratch(match) = rows[row] else { return nil }
		return match
	}

	// MARK: - Actions

	private func openSelected(preview: Bool) {
		guard let match = selectedMatch else { return }
		onOpen?(match.entry.url, preview)
	}

	@objc private func newScratch() {
		create(in: ScratchFiles(projectRoot: projectRoot))
	}

	@objc private func newGlobalScratch() {
		create(in: ScratchFiles.global())
	}

	private func create(in scratches: ScratchFiles) {
		do {
			let url = try scratches.create()
			NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
			onOpen?(url, false)
		} catch {
			present(error, doing: "create a scratch")
		}
	}

	@objc private func contextOpen() { openSelected(preview: false) }

	@objc private func revealInFinder() {
		guard let match = selectedMatch else { return }
		NSWorkspace.shared.activateFileViewerSelecting([match.entry.url])
	}

	@objc private func renameSelected() {
		guard let match = selectedMatch else { return }
		let url = match.entry.url

		let alert = NSAlert()
		alert.messageText = "Rename Scratch"
		alert.informativeText = "A name makes it findable by more than what is written in it."
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		field.stringValue = url.deletingPathExtension().lastPathComponent
		alert.accessoryView = field

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let name = field.stringValue.trimmingCharacters(in: .whitespaces)
			guard !name.isEmpty else { return }
			self.onWillModify?(url)
			do {
				let scratches = ScratchFiles(projectRoot: match.entry.projectRoot)
				let renamed = try scratches.rename(url, to: name)
				self.onMoved?(url, renamed)
				NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
			} catch {
				self.present(error, doing: "rename this scratch")
			}
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	@objc private func moveToGlobal() {
		guard let match = selectedMatch, !match.entry.isGlobal else { return }
		move(match, to: ScratchFiles.global())
	}

	@objc private func moveToProject() {
		guard let match = selectedMatch, let projectRoot, match.entry.projectRoot?.path != projectRoot.path else {
			return
		}
		move(match, to: ScratchFiles(projectRoot: projectRoot))
	}

	private func move(_ match: ScratchMatch, to destination: ScratchFiles) {
		onWillModify?(match.entry.url)
		do {
			let source = ScratchFiles(projectRoot: match.entry.projectRoot)
			let moved = try source.move(match.entry.url, to: destination)
			onMoved?(match.entry.url, moved)
			NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
		} catch {
			present(error, doing: "move this scratch")
		}
	}

	@objc private func deleteSelected() {
		guard let match = selectedMatch else { return }
		let url = match.entry.url

		// Always asked, even for an empty one, and even though it goes to the
		// Trash: a scratch is the only copy of what is in it.
		let alert = NSAlert()
		alert.messageText = "Delete “\(match.entry.title)”?"
		alert.informativeText = match.entry.isEmpty
			? "It is empty. It goes to the Trash."
			: "It goes to the Trash, so it can be put back."
		alert.addButton(withTitle: "Delete")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			do {
				try ScratchFiles(projectRoot: match.entry.projectRoot).remove(url)
				self.onMoved?(url, nil)
				NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
			} catch {
				self.present(error, doing: "delete this scratch")
			}
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	private func present(_ error: Error, doing what: String) {
		Toast.post("Could not \(what)", detail: error.localizedDescription)
	}

	private func makeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	// MARK: - Testing

	func setQueryForTesting(_ text: String) {
		searchField.stringValue = text
		query = text
		reload()
	}

	/// Selects the first result, which is what opens it.
	@discardableResult
	func openFirstForTesting() -> Bool {
		guard let row = rows.firstIndex(where: { if case .scratch = $0 { return true } else { return false } })
		else { return false }
		tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		return true
	}

	var rowTitlesForTesting: [String] {
		rows.map { row in
			switch row {
			case let .header(title): return "# \(title)"
			case let .scratch(match): return match.entry.title
			}
		}
	}
}

// MARK: - Table

extension ScratchesPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		guard rows.indices.contains(row) else { return Theme.current.scaled(22) }
		switch rows[row] {
		case .header: return Theme.current.scaled(22)
		case .scratch: return Theme.current.scaled(38)
		}
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		guard rows.indices.contains(row) else { return false }
		if case .header = rows[row] { return false }
		return true
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard rows.indices.contains(row) else { return nil }
		switch rows[row] {
		case let .header(title): return ScratchSectionView(title: title)
		case let .scratch(match): return ScratchRowView(match: match)
		}
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		// A click opens provisionally, as clicking a file in the tree does, so
		// arrowing through the list shows each one without filling the strip.
		openSelected(preview: true)
	}
}

extension ScratchesPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		guard let match = selectedMatch else { return }

		func item(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			item.isEnabled = enabled
			return item
		}

		menu.addItem(item("Open", #selector(contextOpen)))
		menu.addItem(item("Rename…", #selector(renameSelected)))
		menu.addItem(.separator())
		if match.entry.isGlobal {
			menu.addItem(item(
				projectRoot.map { "Move to \($0.lastPathComponent)" } ?? "Move to Project",
				#selector(moveToProject),
				enabled: projectRoot != nil
			))
		} else {
			menu.addItem(item("Move to Global", #selector(moveToGlobal)))
		}
		menu.addItem(item("Reveal in Finder", #selector(revealInFinder)))
		menu.addItem(.separator())
		menu.addItem(item("Delete…", #selector(deleteSelected)))
	}
}

extension ScratchesPane: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
		reload()
	}
}

/// Table that reports Return and double-click, for opening.
private final class ScratchTableView: NSTableView {
	var onActivate: (() -> Void)?

	override func keyDown(with event: NSEvent) {
		if event.keyCode == 36 || event.keyCode == 76 {
			onActivate?()
			return
		}
		super.keyDown(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?() }
	}
}

private final class ScratchSectionView: NSView {
	private let title: String
	override var isFlipped: Bool { true }

	init(title: String) {
		self.title = title
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let label = NSAttributedString(string: title.uppercased(), attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(10), weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		label.draw(at: NSPoint(x: Theme.current.scaled(10), y: bounds.midY - label.size().height / 2))
	}
}

/// A scratch: what it is called, when it was last touched, and a line of it.
///
/// The line is what identifies most of them. They are unnamed by design, so a
/// list of names alone would be a list of "Scratch 4".
private final class ScratchRowView: NSView {
	private let match: ScratchMatch
	override var isFlipped: Bool { true }

	init(match: ScratchMatch) {
		self.match = match
		super.init(frame: .zero)
		toolTip = match.entry.url.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let left = Theme.current.scaled(18)
		let top = Theme.current.scaled(5)

		let title = NSAttributedString(string: match.entry.title, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		title.draw(at: NSPoint(x: left, y: top))

		let stamp = NSAttributedString(string: Self.age(of: match.entry.modified), attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.gitIgnored,
		])
		stamp.draw(at: NSPoint(x: bounds.maxX - stamp.size().width - Theme.current.scaled(10), y: top + 1))

		var detail = match.excerpt
		if detail.isEmpty { detail = match.entry.isEmpty ? "empty" : "…" }
		if let line = match.line { detail = "\(line): \(detail)" }

		let excerpt = NSAttributedString(string: detail, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		excerpt.draw(in: NSRect(
			x: left,
			y: top + title.size().height + Theme.current.scaled(2),
			width: max(0, bounds.width - left - Theme.current.scaled(10)),
			height: excerpt.size().height
		))
	}

	/// Coarse on purpose: which week it was is what you remember, not the hour.
	private static func age(of date: Date) -> String {
		let seconds = -date.timeIntervalSinceNow
		switch seconds {
		case ..<60: return "now"
		case ..<3600: return "\(Int(seconds / 60))m"
		case ..<86_400: return "\(Int(seconds / 3600))h"
		case ..<(86_400 * 7): return "\(Int(seconds / 86_400))d"
		default: return "\(Int(seconds / (86_400 * 7)))w"
		}
	}
}

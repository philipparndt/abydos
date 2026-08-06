import AppKit
import AbydosKit

/// Project-wide search results (⇧⌘F).
///
/// Results stream in as the walk proceeds rather than appearing all at once, so
/// the first hits are usable immediately on a large tree.
final class SearchPane: NSView {
	var onOpenResult: ((URL, Int, SearchMatch) -> Void)?

	private let search: ProjectSearch
	private let projectRoot: URL

	/// Flattened for display: a file header row, then one row per match.
	private enum Row {
		case file(FileSearchResult)
		case match(FileSearchResult, SearchMatch)
	}

	private var results: [FileSearchResult] = []
	private var rows: [Row] = []
	private var collapsedFiles: Set<String> = []

	private var field: NSSearchField!
	private var statusLabel: NSTextField!
	private var caseButton: NSButton!
	private var wordButton: NSButton!
	private var regexButton: NSButton!
	private var tableView: NSTableView!
	private var debounce: DispatchWorkItem?

	init(projectRoot: URL) {
		self.projectRoot = projectRoot
		self.search = ProjectSearch(root: projectRoot)
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		field = NSSearchField()
		field.placeholderString = "Search in project"
		field.font = Theme.current.uiFont(12)
		field.delegate = self

		statusLabel = NSTextField(labelWithString: "")
		statusLabel.font = Theme.current.uiFont(11)
		statusLabel.textColor = Theme.current.gitIgnored

		caseButton = makeToggle("Aa", "Match case")
		wordButton = makeToggle("W", "Whole word")
		regexButton = makeToggle(".*", "Regular expression")

		let controls = NSStackView(views: [field, caseButton, wordButton, regexButton, statusLabel])
		controls.orientation = .horizontal
		controls.spacing = 6
		controls.alignment = .centerY
		controls.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
		field.setContentHuggingPriority(.defaultLow, for: .horizontal)

		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.selectionHighlightStyle = .regular
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.action = #selector(rowClicked)
		table.doubleAction = #selector(rowClicked)
		tableView = table

		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay

		addSubview(controls)
		addSubview(scrollView)
		controls.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		controlsHeight = controls.heightAnchor.constraint(equalToConstant: Theme.current.scaled(34))
		NSLayoutConstraint.activate([
			controls.topAnchor.constraint(equalTo: topAnchor),
			controls.leadingAnchor.constraint(equalTo: leadingAnchor),
			controls.trailingAnchor.constraint(equalTo: trailingAnchor),
			controlsHeight,

			scrollView.topAnchor.constraint(equalTo: controls.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	private var controlsHeight: NSLayoutConstraint!

	private func makeToggle(_ title: String, _ tooltip: String) -> NSButton {
		let button = NSButton(title: title, target: self, action: #selector(optionsChanged))
		button.setButtonType(.pushOnPushOff)
		button.bezelStyle = .rounded
		button.controlSize = .small
		button.font = Theme.current.uiFont(10, weight: .medium)
		button.toolTip = tooltip
		return button
	}

	private var options: SearchOptions {
		SearchOptions(
			caseSensitive: caseButton.state == .on,
			wholeWord: wordButton.state == .on,
			isRegex: regexButton.state == .on
		)
	}

	@objc private func optionsChanged() { scheduleSearch() }

	func focusField() {
		window?.makeFirstResponder(field)
		field.currentEditor()?.selectAll(nil)
	}

	func setQuery(_ text: String) {
		field.stringValue = text
		scheduleSearch()
	}

	func applySettings() {
		controlsHeight.constant = Theme.current.scaled(34)
		field.font = Theme.current.uiFont(12)
		statusLabel.font = Theme.current.uiFont(11)
		tableView.reloadData()
	}

	// MARK: - Searching

	private func scheduleSearch() {
		debounce?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.runSearch() }
		debounce = work
		// Longer than the in-file debounce: this walks the whole tree.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
	}

	private func runSearch() {
		let query = field.stringValue
		results = []
		rows = []
		tableView.reloadData()

		guard !query.isEmpty else {
			statusLabel.stringValue = ""
			return
		}
		guard TextSearch.isValid(query: query, options: options) else {
			statusLabel.stringValue = "Invalid pattern"
			field.textColor = Theme.current.gitConflict
			return
		}
		field.textColor = .labelColor
		statusLabel.stringValue = "Searching…"

		search.search(
			query: query,
			options: options,
			onResults: { [weak self] batch in
				guard let self else { return }
				self.results.append(contentsOf: batch)
				self.rebuildRows()
				self.updateStatus(finished: false)
			},
			onFinished: { [weak self] completed, _ in
				guard let self, completed else { return }
				self.updateStatus(finished: true)
			}
		)
	}

	private func updateStatus(finished: Bool) {
		let matchCount = results.reduce(0) { $0 + $1.matches.count }
		let fileCount = results.count
		let prefix = finished ? "" : "Searching… "
		statusLabel.stringValue = matchCount == 0
			? (finished ? "No results" : "Searching…")
			: "\(prefix)\(matchCount) in \(fileCount) file\(fileCount == 1 ? "" : "s")"
	}

	private func rebuildRows() {
		rows = []
		for result in results {
			rows.append(.file(result))
			guard !collapsedFiles.contains(result.relativePath) else { continue }
			for match in result.matches {
				rows.append(.match(result, match))
			}
		}
		tableView.reloadData()
	}

	@objc private func rowClicked() {
		let index = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
		guard rows.indices.contains(index) else { return }

		switch rows[index] {
		case let .file(result):
			// Clicking a file header folds it away, which matters once a search
			// returns hundreds of hits.
			if collapsedFiles.contains(result.relativePath) {
				collapsedFiles.remove(result.relativePath)
			} else {
				collapsedFiles.insert(result.relativePath)
			}
			rebuildRows()
		case let .match(result, match):
			onOpenResult?(result.url, match.line + 1, match)
		}
	}
}

extension SearchPane: NSSearchFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		scheduleSearch()
	}
}

extension SearchPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		Theme.current.scaled(22)
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		SearchRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard rows.indices.contains(row) else { return nil }
		switch rows[row] {
		case let .file(result):
			return SearchFileCell(result: result, isCollapsed: collapsedFiles.contains(result.relativePath))
		case let .match(_, match):
			return SearchMatchCell(match: match)
		}
	}
}

private final class SearchRowView: NSTableRowView {
	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selectionActive.setFill()
		bounds.fill()
	}
}

private final class SearchFileCell: NSView {
	private let result: FileSearchResult
	private let isCollapsed: Bool

	init(result: FileSearchResult, isCollapsed: Bool) {
		self.result = result
		self.isCollapsed = isCollapsed
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(8)

		if let chevron = Theme.symbol(
			isCollapsed ? "chevron.right" : "chevron.down",
			size: 9 * Theme.current.scale,
			color: Theme.current.gitIgnored
		) {
			let size = Theme.current.scaled(10)
			chevron.drawFitted(in: NSRect(x: x, y: bounds.midY - size / 2, width: size, height: size))
		}
		x += Theme.current.scaled(14)

		let node = FileNode(url: result.url, isDirectory: false)
		if let icon = FileIcon.image(for: node, isExpanded: false) {
			let size = Theme.current.scaled(13)
			icon.drawFitted(in: NSRect(x: x, y: bounds.midY - size / 2, width: size, height: size))
			x += size + Theme.current.scaled(5)
		}

		let name = (result.relativePath as NSString).lastPathComponent
		let directory = (result.relativePath as NSString).deletingLastPathComponent

		let nameString = NSAttributedString(string: name, attributes: [
			.font: Theme.current.uiFont(12, weight: .medium),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		nameString.draw(at: NSPoint(x: x, y: bounds.midY - nameString.size().height / 2))
		x += nameString.size().width + Theme.current.scaled(8)

		if !directory.isEmpty {
			let path = NSAttributedString(string: directory, attributes: [
				.font: Theme.current.uiFont(10.5),
				.foregroundColor: Theme.current.gitIgnored,
			])
			path.draw(at: NSPoint(x: x, y: bounds.midY - path.size().height / 2))
			x += path.size().width + Theme.current.scaled(8)
		}

		let count = NSAttributedString(string: "\(result.matches.count)", attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		count.draw(at: NSPoint(
			x: bounds.width - count.size().width - Theme.current.scaled(12),
			y: bounds.midY - count.size().height / 2
		))
	}
}

private final class SearchMatchCell: NSView {
	private let match: SearchMatch

	init(match: SearchMatch) {
		self.match = match
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let x = Theme.current.scaled(34)

		let number = NSAttributedString(string: "\(match.line + 1)", attributes: [
			.font: Theme.terminalFont(size: Theme.current.uiFont(10.5).pointSize),
			.foregroundColor: Theme.current.gutterText,
		])
		// Right-aligned in its own column so the code lines up regardless of
		// how many digits the line number has.
		number.draw(at: NSPoint(
			x: x - number.size().width - Theme.current.scaled(6),
			y: bounds.midY - number.size().height / 2
		))

		// Leading whitespace is trimmed so deeply indented code stays readable in
		// a narrow panel.
		let trimmed = match.lineText.drop { $0 == " " || $0 == "\t" }
		let text = NSAttributedString(string: String(trimmed), attributes: [
			.font: Theme.terminalFont(size: Theme.current.uiFont(11).pointSize),
			.foregroundColor: isSelected ? NSColor.hex(0xE8EAED) : Theme.current.editorText,
		])
		text.draw(in: NSRect(
			x: x,
			y: bounds.midY - text.size().height / 2,
			width: max(0, bounds.width - x - Theme.current.scaled(12)),
			height: text.size().height
		))
	}
}

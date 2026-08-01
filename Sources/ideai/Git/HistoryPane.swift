import AppKit
import IdeaiKit

/// The log: commits, and what each one changed.
///
/// Two lists, one above the other. The top is the history — of the repository,
/// or of one file when the editor is showing one — and the bottom is what the
/// selected commit touched. Clicking a file opens that commit's diff for it,
/// which is the question a log is nearly always being asked: not "what
/// happened" but "what happened to this".
final class HistoryPane: NSView {
	/// Show a commit's diff for one of its files.
	var onSelectFile: ((GitCommit, GitCommitFile) -> Void)?

	private let root: URL

	private var commits: [GitCommit] = []
	/// Commits that exist here and nowhere else yet.
	private var unpushed: Set<String> = []
	private var files: [GitCommitFile] = []
	private var selectedCommit: GitCommit?
	private var query = ""
	/// When set, the history of that file rather than of the repository.
	private var scopedPath: String?
	/// Whether there may be more behind what has been loaded.
	private var hasMore = false
	private var isLoading = false

	private static let pageSize = 150

	private var searchField: NSSearchField!
	private var scopeControl: NSSegmentedControl!
	private var commitTable: HistoryTableView!
	private var fileTable: HistoryTableView!
	private var detailLabel: NSTextField!

	init(root: URL) {
		self.root = root
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		reload()

		NotificationCenter.default.addObserver(
			self, selector: #selector(reload), name: .ideaiRepositoryChanged, object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }
	deinit { NotificationCenter.default.removeObserver(self) }

	/// Narrows the log to one file, or widens it back to the repository.
	func setScope(path: String?) {
		guard path != scopedPath else { return }
		scopedPath = path
		updateScopeButton()
		reload()
	}

	/// What the editor has open, offered as a scope rather than applied.
	private var offeredPath: String?

	func offerScope(path: String?) {
		offeredPath = path
		updateScopeButton()
	}

	// MARK: - Layout

	private func build() {
		searchField = NSSearchField()
		searchField.placeholderString = "Search messages"
		searchField.font = Theme.current.uiFont(12)
		searchField.focusRingType = .none
		searchField.delegate = self
		searchField.sendsWholeSearchString = false

		// Both choices visible with the active one lit, rather than one button
		// naming the other state: "Only main.go" and "Whole Repository" each
		// read as a description of what is showing, so a single button cannot
		// say which it is.
		scopeControl = NSSegmentedControl(
			labels: ["Whole Repository", "This File"],
			trackingMode: .selectOne,
			target: self,
			action: #selector(scopeChanged)
		)
		scopeControl.controlSize = .small
		scopeControl.font = Theme.current.uiFont(11)
		scopeControl.selectedSegment = 0

		commitTable = makeTable(rowHeight: Theme.current.scaled(40))
		commitTable.onSelectionChange = { [weak self] in self?.commitSelected() }
		commitTable.menu = makeCommitMenu()
		commitTable.onScrolledToEnd = { [weak self] in self?.loadMore() }

		fileTable = makeTable(rowHeight: Theme.current.scaled(22))
		fileTable.onSelectionChange = { [weak self] in self?.fileSelected() }

		detailLabel = NSTextField(labelWithString: "")
		detailLabel.font = Theme.current.uiFont(11)
		detailLabel.textColor = Theme.current.gitIgnored
		detailLabel.lineBreakMode = .byTruncatingTail
		detailLabel.maximumNumberOfLines = 2
		detailLabel.cell?.usesSingleLineMode = false
		detailLabel.cell?.wraps = true
		// A commit message is arbitrarily long, and a label sized to its text
		// would push the sidebar as wide as somebody's longest paragraph.
		detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		detailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

		let commitScroll = scrollView(around: commitTable)
		let fileScroll = scrollView(around: fileTable)

		for view in [searchField, scopeControl, commitScroll, detailLabel, fileScroll] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			scopeControl.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: inset / 2),
			scopeControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			scopeControl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),

			commitScroll.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: inset / 2),
			commitScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			commitScroll.trailingAnchor.constraint(equalTo: trailingAnchor),

			detailLabel.topAnchor.constraint(equalTo: commitScroll.bottomAnchor, constant: inset / 2),
			detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			// Two lines of it, whatever it says; the whole message is in the
			// tooltip and in the commit itself.
			detailLabel.heightAnchor.constraint(lessThanOrEqualToConstant: Theme.current.scaled(30)),

			fileScroll.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: inset / 2),
			fileScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			fileScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			fileScroll.bottomAnchor.constraint(equalTo: bottomAnchor),

			// The commit list gets the room; the files of one commit are few.
			fileScroll.heightAnchor.constraint(equalTo: commitScroll.heightAnchor, multiplier: 0.45),
		])
	}

	private func makeTable(rowHeight: CGFloat) -> HistoryTableView {
		let table = HistoryTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.selectionHighlightStyle = .regular
		table.rowSizeStyle = .custom
		table.rowHeightOverride = rowHeight
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
		table.delegate = self
		table.dataSource = self
		return table
	}

	private func scrollView(around table: NSTableView) -> NSScrollView {
		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.scrollerStyle = NSScroller.preferredScrollerStyle
		return scroll
	}

	/// Both options say what they show; the lit one is what is showing.
	private func updateScopeButton() {
		let name = (scopedPath ?? offeredPath).map { ($0 as NSString).lastPathComponent }
		scopeControl.setLabel(name ?? "This File", forSegment: 1)
		scopeControl.setEnabled(name != nil, forSegment: 1)
		scopeControl.selectedSegment = scopedPath == nil ? 0 : 1
	}

	// MARK: - Loading

	@objc func reload() {
		let scope = scopedPath
		let search = query
		Task { @MainActor in
			isLoading = true
			let loaded = await GitHistory.log(
				in: root, path: scope, limit: Self.pageSize, search: search.isEmpty ? nil : search
			)
			// Another scope or query landed while this was in flight.
			guard scope == self.scopedPath, search == self.query else { return }

			commits = loaded
			unpushed = await GitHistory.unpushed(in: root)
			hasMore = loaded.count == Self.pageSize
			isLoading = false
			commitTable.reloadData()

			// Selecting the newest commit means the pane opens showing
			// something rather than an empty half.
			if !commits.isEmpty {
				commitTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			} else {
				files = []
				selectedCommit = nil
				detailLabel.stringValue = search.isEmpty ? "No commits." : "Nothing matches “\(search)”."
				fileTable.reloadData()
			}
		}
	}

	/// Reads the next page when the list is scrolled to its end.
	private func loadMore() {
		guard hasMore, !isLoading else { return }
		let scope = scopedPath
		let search = query
		let offset = commits.count

		Task { @MainActor in
			isLoading = true
			let more = await GitHistory.log(
				in: root, path: scope, skip: offset, limit: Self.pageSize,
				search: search.isEmpty ? nil : search
			)
			guard scope == self.scopedPath, search == self.query, offset == self.commits.count else { return }

			commits += more
			hasMore = more.count == Self.pageSize
			isLoading = false
			commitTable.reloadData()
		}
	}

	private func commitSelected() {
		let row = commitTable.selectedRow
		guard commits.indices.contains(row) else { return }
		let commit = commits[row]
		selectedCommit = commit

		let message = [commit.subject, commit.body].filter { !$0.isEmpty }.joined(separator: " — ")
		detailLabel.stringValue = message.replacingOccurrences(of: "\n", with: " ")
		detailLabel.toolTip = message

		Task { @MainActor in
			let loaded = await GitHistory.files(of: commit.hash, in: root)
			guard selectedCommit?.hash == commit.hash else { return }
			files = loaded
			fileTable.reloadData()
		}
	}

	private func fileSelected() {
		let row = fileTable.selectedRow
		guard files.indices.contains(row), let commit = selectedCommit else { return }
		onSelectFile?(commit, files[row])
	}

	// MARK: - Actions

	@objc private func scopeChanged() {
		setScope(path: scopeControl.selectedSegment == 1 ? offeredPath : nil)
	}

	private func makeCommitMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	private var clickedCommit: GitCommit? {
		let clicked = commitTable.clickedRow
		let row = clicked >= 0 ? clicked : commitTable.selectedRow
		return commits.indices.contains(row) ? commits[row] : nil
	}

	@objc private func copyHash() {
		guard let commit = clickedCommit else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(commit.hash, forType: .string)
	}

	@objc private func copySubject() {
		guard let commit = clickedCommit else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(commit.subject, forType: .string)
	}

	// MARK: - Testing

	func setQueryForTesting(_ text: String) {
		searchField.stringValue = text
		query = text
		reload()
	}

	var commitSubjectsForTesting: [String] { commits.map(\.subject) }
	var fileNamesForTesting: [String] { files.map(\.path) }

	func selectCommitForTesting(_ index: Int) {
		guard commits.indices.contains(index) else { return }
		commitTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
	}

	func selectFileForTesting(_ index: Int) {
		guard files.indices.contains(index) else { return }
		fileTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
	}
}

// MARK: - Tables

extension HistoryPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int {
		tableView === commitTable ? commits.count : files.count
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		(tableView as? HistoryTableView)?.rowHeightOverride ?? Theme.current.scaled(22)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		if tableView === commitTable {
			guard commits.indices.contains(row) else { return nil }
			let commit = commits[row]
			return CommitRowView(commit: commit, isUnpushed: unpushed.contains(commit.hash))
		}
		guard files.indices.contains(row) else { return nil }
		return CommitFileRowView(file: files[row])
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		(notification.object as? HistoryTableView)?.onSelectionChange?()
	}
}

extension HistoryPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		guard clickedCommit != nil else { return }

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			return item
		}
		menu.addItem(item("Copy Commit Hash", #selector(copyHash)))
		menu.addItem(item("Copy Subject", #selector(copySubject)))
	}
}

extension HistoryPane: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
		reload()
	}
}

/// A table that says when its selection changed and when it ran out of rows.
private final class HistoryTableView: NSTableView {
	var onSelectionChange: (() -> Void)?
	var onScrolledToEnd: (() -> Void)?
	var rowHeightOverride: CGFloat?

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)

		// Asking for more when the last row has been drawn: a log is read by
		// scrolling, and the page after the one you are on is the one you are
		// about to want.
		guard numberOfRows > 0, let last = rowView(atRow: numberOfRows - 1, makeIfNecessary: false)
		else { return }
		if dirtyRect.intersects(last.frame) { onScrolledToEnd?() }
	}
}

/// A commit: what it did, who did it, and when.
private final class CommitRowView: NSView {
	private let commit: GitCommit
	private let isUnpushed: Bool
	override var isFlipped: Bool { true }

	init(commit: GitCommit, isUnpushed: Bool = false) {
		self.commit = commit
		self.isUnpushed = isUnpushed
		super.init(frame: .zero)
		var lines = [commit.shortHash, commit.subject, commit.body]
		if isUnpushed { lines.append("Not pushed yet") }
		toolTip = lines
			.filter { !$0.isEmpty }
			.joined(separator: "\n\n")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let left = Theme.current.scaled(10)
		let top = Theme.current.scaled(5)

		var x = left
		// Where a branch or tag points, said before the subject: it is how a
		// commit is found by eye when scrolling.
		for ref in commit.refs.prefix(2) {
			let label = NSAttributedString(string: ref.replacingOccurrences(of: "tag: ", with: ""), attributes: [
				.font: NSFont.systemFont(ofSize: Theme.current.scaled(9.5), weight: .semibold),
				.foregroundColor: ref.hasPrefix("tag: ") ? Theme.current.gitModified : Theme.current.gitAdded,
			])
			let size = label.size()
			let pill = NSRect(x: x, y: top, width: size.width + 8, height: size.height + 2)
			let tint = ref.hasPrefix("tag: ") ? Theme.current.gitModified : Theme.current.gitAdded
			tint.withAlphaComponent(0.18).setFill()
			NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
			label.draw(at: NSPoint(x: x + 4, y: top + 1))
			x += pill.width + Theme.current.scaled(5)
		}

		// A commit only on this machine is the one worth spotting: it is the
		// one a lost laptop takes with it.
		if isUnpushed, let arrow = Theme.symbol(
			"arrow.up", size: 9 * Theme.current.scale, color: Theme.current.gitModified
		) {
			let size = Theme.current.scaled(10)
			arrow.drawFitted(in: NSRect(
				x: x, y: top + Theme.current.scaled(2), width: size, height: size
			))
			x += size + Theme.current.scaled(4)
		}

		let subject = NSAttributedString(string: commit.subject, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		subject.draw(in: NSRect(
			x: x, y: top,
			width: max(0, bounds.width - x - Theme.current.scaled(10)),
			height: subject.size().height
		))

		// Merges are worth telling apart at a glance: their diff is against the
		// first parent and reads differently from an ordinary commit's.
		var meta = "\(commit.shortHash)  ·  \(commit.authorName)  ·  \(Self.age(of: commit.date))"
		if commit.isMerge { meta = "merge  ·  " + meta }

		let detail = NSAttributedString(string: meta, attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.gitIgnored,
		])
		detail.draw(in: NSRect(
			x: left,
			y: top + subject.size().height + Theme.current.scaled(2),
			width: max(0, bounds.width - left - Theme.current.scaled(10)),
			height: detail.size().height
		))
	}

	/// Coarse: which week it was is what anybody remembers.
	static func age(of date: Date) -> String {
		let seconds = -date.timeIntervalSinceNow
		switch seconds {
		case ..<60: return "just now"
		case ..<3600: return "\(Int(seconds / 60))m ago"
		case ..<86_400: return "\(Int(seconds / 3600))h ago"
		case ..<(86_400 * 7): return "\(Int(seconds / 86_400))d ago"
		case ..<(86_400 * 365): return "\(Int(seconds / (86_400 * 7)))w ago"
		default: return "\(Int(seconds / (86_400 * 365)))y ago"
		}
	}
}

/// A file a commit touched, marked by what happened to it.
private final class CommitFileRowView: NSView {
	private let file: GitCommitFile
	override var isFlipped: Bool { true }

	init(file: GitCommitFile) {
		self.file = file
		super.init(frame: .zero)
		toolTip = file.originalPath.map { "\($0) → \(file.path)" } ?? file.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let left = Theme.current.scaled(10)
		let colour = Self.color(for: file.kind)

		let letter = NSAttributedString(string: Self.letter(for: file.kind), attributes: [
			.font: NSFont.monospacedSystemFont(ofSize: Theme.current.scaled(10), weight: .bold),
			.foregroundColor: colour,
		])
		letter.draw(at: NSPoint(x: left, y: bounds.midY - letter.size().height / 2))

		var x = left + Theme.current.scaled(16)
		let name = NSAttributedString(string: file.name, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: Theme.current.sidebarText,
		])
		name.draw(at: NSPoint(x: x, y: bounds.midY - name.size().height / 2))
		x += name.size().width + Theme.current.scaled(6)

		guard !file.directory.isEmpty else { return }
		let directory = NSAttributedString(string: file.directory, attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.gitIgnored,
		])
		directory.draw(in: NSRect(
			x: x,
			y: bounds.midY - directory.size().height / 2,
			width: max(0, bounds.width - x - Theme.current.scaled(8)),
			height: directory.size().height
		))
	}

	private static func letter(for kind: GitChange.Kind) -> String {
		switch kind {
		case .added: return "A"
		case .deleted: return "D"
		case .renamed: return "R"
		case .copied: return "C"
		case .untracked: return "?"
		case .conflicted: return "!"
		case .modified: return "M"
		}
	}

	private static func color(for kind: GitChange.Kind) -> NSColor {
		switch kind {
		case .added, .copied: return Theme.current.gitAdded
		case .deleted: return Theme.current.gitUnversioned
		case .conflicted: return Theme.current.gitConflict
		default: return Theme.current.gitModified
		}
	}
}

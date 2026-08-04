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
	/// The shape of what is loaded: one row per commit, in the same order.
	///
	/// Rebuilt whenever the list changes rather than kept in step by hand — it
	/// is a page of a few hundred rows and the layout costs less than the git
	/// call that fetched them.
	private var graph: [GitGraph.Row] = []
	/// Merges whose branch is folded away, and the commits that hides.
	private var collapsedMerges: Set<String> = []
	private var hiddenByCollapse: Set<String> = []
	/// What is actually on screen: the commits, less anything folded away.
	private var visible: [(commit: GitCommit, graph: GitGraph.Row?)] = []
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
		commitTable.onGraphClick = { [weak self] point, row in
			self?.handleGraphClick(at: point, row: row) ?? false
		}

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
			// A fold only means something for the commits it was made on.
			collapsedMerges = []
			rebuildGraph()
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
			rebuildGraph()
			commitTable.reloadData()
		}
	}

	/// Lays the loaded commits out and works out what is on screen.
	///
	/// A search or a path filter leaves a list that is not a graph — the
	/// commits between the ones shown are missing — so the lanes are dropped
	/// and the rows are drawn plainly.
	private func rebuildGraph() {
		StallWatch.mark("history graph") { rebuildGraphMarked() }
	}

	private func rebuildGraphMarked() {
		let isWholeHistory = query.isEmpty && scopedPath == nil
		guard isWholeHistory else {
			graph = []
			hiddenByCollapse = []
			visible = commits.map { ($0, nil) }
			return
		}

		graph = GitGraph.lay(out: commits.map {
			GitGraph.Node(hash: $0.hash, parents: $0.parentHashes)
		})

		// What each folded merge hides: everything its side brought in, which
		// is the same walk the layout does to count them.
		let nodes = commits.map { GitGraph.Node(hash: $0.hash, parents: $0.parentHashes) }
		hiddenByCollapse = []
		for hash in collapsedMerges {
			guard let node = nodes.first(where: { $0.hash == hash }) else { continue }
			hiddenByCollapse.formUnion(GitGraph.mergedHashes(of: node, nodes: nodes))
		}

		visible = zip(commits, graph)
			.filter { !hiddenByCollapse.contains($0.0.hash) }
			.map { ($0.0, $0.1) }
	}

	/// Folds a merge's branch away, or brings it back.
	private func toggleCollapse(at row: Int) {
		guard visible.indices.contains(row) else { return }
		let commit = visible[row].commit
		guard visible[row].graph?.collapsible ?? 0 > 0 else { return }

		if collapsedMerges.contains(commit.hash) {
			collapsedMerges.remove(commit.hash)
		} else {
			collapsedMerges.insert(commit.hash)
		}
		rebuildGraph()
		commitTable.reloadData()
	}

	private func commitSelected() {
		let row = commitTable.selectedRow
		guard visible.indices.contains(row) else { return }
		let commit = visible[row].commit
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

	/// Folds the branch a row's merge brought in, for checking it works.
	func toggleCollapseForTesting(row: Int) -> String {
		guard visible.indices.contains(row) else { return "no row \(row)" }
		let before = visible.count
		toggleCollapse(at: row)
		return "rows \(before) -> \(visible.count)"
	}

	/// A click in the graph column, which is where a fold is opened and closed.
	///
	/// Anywhere else in the row selects the commit, as it always did: the
	/// chevron is small and the lane it sits in is not, so the whole column
	/// under a foldable merge is the target.
	func handleGraphClick(at point: NSPoint, row: Int) -> Bool {
		guard visible.indices.contains(row), let place = visible[row].graph else { return false }
		guard place.collapsible > 0 else { return false }

		// The dot, and the marker beside it.
		let lane = Theme.current.scaled(13)
		let centre = Theme.current.scaled(8) + CGFloat(place.lane) * lane
		let target = centre - lane / 2 ... centre + lane
		guard target.contains(point.x) else { return false }

		toggleCollapse(at: row)
		return true
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
		return visible.indices.contains(row) ? visible[row].commit : nil
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
		tableView === commitTable ? visible.count : files.count
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		(tableView as? HistoryTableView)?.rowHeightOverride ?? Theme.current.scaled(22)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		if tableView === commitTable {
			guard commits.indices.contains(row) else { return nil }
			let commit = visible[row].commit
			return CommitRowView(
				commit: commit,
				isUnpushed: unpushed.contains(commit.hash),
				graph: visible[row].graph,
				isCollapsed: collapsedMerges.contains(commit.hash)
			)
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
	/// A click in the graph column, which the pane may take for a fold.
	var onGraphClick: ((NSPoint, Int) -> Bool)?

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		// The table's own x is the row's x — rows start at its leading edge —
		// so converting through a row view that may not exist yet only ever
		// moved the point into the wrong space.
		let row = self.row(at: point)
		if row >= 0, onGraphClick?(point, row) == true { return }
		super.mouseDown(with: event)
	}

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
	/// Where this commit sits in the drawing, and what runs past it.
	private let graph: GitGraph.Row?
	/// Whether the branch this merge brought in is folded away.
	private let isCollapsed: Bool
	override var isFlipped: Bool { true }

	init(
		commit: GitCommit,
		isUnpushed: Bool = false,
		graph: GitGraph.Row? = nil,
		isCollapsed: Bool = false
	) {
		self.commit = commit
		self.isUnpushed = isUnpushed
		self.graph = graph
		self.isCollapsed = isCollapsed
		super.init(frame: .zero)
		var lines = [commit.shortHash, commit.subject, commit.body]
		if isUnpushed { lines.append("Not pushed yet") }
		toolTip = lines
			.filter { !$0.isEmpty }
			.joined(separator: "\n\n")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// How wide one lane is, and how far the text starts from the graph.
	private var laneWidth: CGFloat { Theme.current.scaled(13) }

	/// The colours lines of descent are drawn in, in order.
	///
	/// Chosen to be told apart at a glance rather than to be pretty: a graph is
	/// read by following one line down past the others.
	private static let laneColours: [NSColor] = [
		.hex(0x6E97F0), .hex(0x71B382), .hex(0xE5BE72), .hex(0xC983C5),
		.hex(0x62B4F0), .hex(0xD8926B), .hex(0x46BDB6), .hex(0xD6706E),
	]

	static func colour(forBranch branch: Int) -> NSColor {
		laneColours[abs(branch) % laneColours.count]
	}

	/// The graph column's width for this row, or nothing when there is no
	/// graph — a filtered log has no shape worth drawing.
	private var graphWidth: CGFloat {
		guard let graph else { return 0 }
		return CGFloat(max(1, graph.width)) * laneWidth + Theme.current.scaled(6)
	}

	override func draw(_ dirtyRect: NSRect) {
		drawGraph()

		let left = Theme.current.scaled(10) + graphWidth
		let top = Theme.current.scaled(5)

		var x = left
		// Where a branch or tag points, said before the subject: it is how a
		// commit is found by eye when scrolling.
		// Four rather than two: a commit at the tip of a branch that is also
		// tagged, pushed and stashed on top of is exactly the commit somebody
		// is looking for, and it is the one whose labels were being dropped.
		for ref in commit.refs.prefix(4) {
			let name = ref.replacingOccurrences(of: "tag: ", with: "")
			// A tag is one thing, a stash another, a branch a third: the colour
			// is what tells them apart while scrolling.
			let tint: NSColor
			if ref.hasPrefix("tag: ") {
				tint = Theme.current.gitModified
			} else if name.hasPrefix("refs/stash") || name.hasPrefix("stash@") {
				tint = Theme.current.gitUnversioned
			} else if name.contains("/") && !name.hasPrefix("feature/") && name.split(separator: "/").count == 2
				&& !name.hasPrefix("fix/") && !name.hasPrefix("chore/") && !name.hasPrefix("release/") {
				// `origin/main` and friends: where it is, not where it is being
				// worked on.
				tint = Theme.current.gitIgnored
			} else {
				tint = Theme.current.gitAdded
			}

			let label = NSAttributedString(string: name, attributes: [
				.font: NSFont.systemFont(ofSize: Theme.current.scaled(9.5), weight: .semibold),
				.foregroundColor: tint,
			])
			let size = label.size()
			let pill = NSRect(x: x, y: top, width: size.width + 8, height: size.height + 2)
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

	/// Draws the lanes, the lines between them, and this commit's dot.
	///
	/// A row is drawn as: everything that passes through it going straight
	/// down, then the lines that bend into or out of this commit, then the dot
	/// on top so nothing crosses it.
	private func drawGraph() {
		guard let graph else { return }
		let centreY = bounds.midY
		func centre(_ lane: Int) -> CGFloat {
			Theme.current.scaled(8) + CGFloat(lane) * laneWidth
		}

		let width = Theme.current.scaled(1.6)
		for edge in graph.edges {
			let path = NSBezierPath()
			let from = centre(edge.from)
			let to = centre(edge.to)
			if from == to {
				// A lane carrying on: the line runs the height of the row, and
				// only from the dot downwards when it starts here.
				let top = (edge.from == graph.lane) ? centreY : bounds.minY
				path.move(to: NSPoint(x: from, y: top))
				path.line(to: NSPoint(x: from, y: bounds.maxY))
			} else if edge.to == graph.lane {
				// A line arriving: it came down its own lane from the row
				// above and bends into this commit. Drawn upwards, which is
				// where it comes from — drawing it downwards left every merged
				// branch ending in mid-air.
				path.move(to: NSPoint(x: from, y: bounds.minY))
				path.curve(
					to: NSPoint(x: to, y: centreY),
					controlPoint1: NSPoint(x: from, y: centreY - (bounds.height / 3)),
					controlPoint2: NSPoint(x: to, y: bounds.minY + (bounds.height / 3))
				)
			} else {
				// A line leaving: from this commit down into another lane.
				path.move(to: NSPoint(x: from, y: centreY))
				path.curve(
					to: NSPoint(x: to, y: bounds.maxY),
					controlPoint1: NSPoint(x: from, y: bounds.maxY - (bounds.height / 3)),
					controlPoint2: NSPoint(x: to, y: centreY + (bounds.height / 3))
				)
			}
			path.lineWidth = width
			Self.colour(forBranch: edge.branch).withAlphaComponent(0.9).setStroke()
			path.stroke()
		}

		// Lines coming from above into this commit's lane: the row above drew
		// them to its own edge, and this one meets them.
		//
		// Unless there is nothing above. The newest commit of a line has
		// nothing continuing into it, and drawing this anyway gave every
		// branch tip a stub of line above the dot, arriving from a history
		// that is not there.
		let own = centre(graph.lane)
		if !graph.isTip {
			let up = NSBezierPath()
			up.move(to: NSPoint(x: own, y: bounds.minY))
			up.line(to: NSPoint(x: own, y: centreY))
			up.lineWidth = width
			Self.colour(forBranch: graph.branch).withAlphaComponent(0.9).setStroke()
			up.stroke()
		}

		let radius = Theme.current.scaled(commit.isMerge ? 4 : 3.5)
		let dot = NSRect(
			x: own - radius, y: centreY - radius, width: radius * 2, height: radius * 2
		)
		let colour = Self.colour(forBranch: graph.branch)
		if commit.isMerge {
			// A merge is drawn hollow, the way a junction is: the two lines
			// meeting are what matters, not the point itself.
			Theme.current.editorBackground.setFill()
			NSBezierPath(ovalIn: dot).fill()
			colour.setStroke()
			let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.8, dy: 0.8))
			ring.lineWidth = Theme.current.scaled(1.8)
			ring.stroke()
		} else {
			colour.setFill()
			NSBezierPath(ovalIn: dot).fill()
		}

		// A merge that brought a branch in can fold it away. The marker sits
		// beside the dot rather than under it, where the lines leaving the row
		// are: a plus for a branch that is folded, a minus for one that is not,
		// which is how a tree says the same thing everywhere else.
		guard graph.collapsible > 0 else { return }
		let box = NSRect(
			x: own + radius + Theme.current.scaled(3),
			y: centreY - Theme.current.scaled(4.5),
			width: Theme.current.scaled(9),
			height: Theme.current.scaled(9)
		)
		colour.withAlphaComponent(0.18).setFill()
		NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()

		let marker = NSBezierPath()
		let arm = Theme.current.scaled(2.4)
		marker.move(to: NSPoint(x: box.midX - arm, y: box.midY))
		marker.line(to: NSPoint(x: box.midX + arm, y: box.midY))
		if isCollapsed {
			marker.move(to: NSPoint(x: box.midX, y: box.midY - arm))
			marker.line(to: NSPoint(x: box.midX, y: box.midY + arm))
		}
		marker.lineWidth = Theme.current.scaled(1.3)
		marker.lineCapStyle = .round
		colour.setStroke()
		marker.stroke()
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

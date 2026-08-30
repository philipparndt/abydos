import AppKit
import AbydosKit

/// The log: commits, and what each one changed.
///
/// Two lists, one above the other. The top is the history — of the repository,
/// or of one file when the editor is showing one — and the bottom is what the
/// selected commit touched. Clicking a file opens that commit's diff for it,
/// which is the question a log is nearly always being asked: not "what
/// happened" but "what happened to this".
final class HistoryPane: NSView {
	/// How much room this has, and therefore what it can draw.
	///
	/// **One pane and not two.** A graph needs width for its lanes and its
	/// refs, and a commit needs its diff beside it rather than beneath it — but
	/// the loader, the collapse rule, the graph and the menu are the same
	/// questions at either size, and two classes asking them would be two
	/// answers that drift. What differs is the arrangement, which is this.
	enum Layout {
		/// A 300 pt column: the log above, the files of one commit below, and
		/// the diff opened as an editor tab because there is nowhere else.
		case sidebar
		/// A tab of its own: the graph at full width with the selected
		/// commit's files and diff beside it.
		case page
	}

	/// Show a commit's diff for one of its files.
	///
	/// Only in `.sidebar`. A page has somewhere to put it.
	var onSelectFile: ((GitCommit, GitCommitFile) -> Void)?

	/// Not `layout`: that is `NSView`'s, and shadowing it means the override
	/// below silently is not one.
	private let arrangement: Layout
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
	/// When set, the history of that ref rather than of the branch checked out.
	///
	/// `GitHistory.log` has taken a revision from the day it was written and
	/// nothing has ever passed one: a branch row could say "take me there" and
	/// could not say "show me where it has been".
	private var scopedRef: String?
	/// Whether there may be more behind what has been loaded.
	private var hasMore = false
	private var isLoading = false

	private static let pageSize = 150

	private var searchField: NSSearchField!
	private var scopeControl: NSSegmentedControl!
	private var commitTable: HistoryTableView!
	/// The changed files of the selected commit — the list a pull request page
	/// hosts too, which is why it is a view of its own rather than an outline
	/// wired up in here. See `ChangedFileList`.
	private var fileList: ChangedFileList!

	/// The pane is a container, and the keyboard has nothing to do in one.
	///
	/// It was where the keyboard came to rest — opened as a page, the first
	/// responder was this view — so the arrows had nothing to move and every
	/// row of both lists was unreachable without a mouse. A container that
	/// accepts the keyboard and does nothing with it is worse than one that
	/// refuses: the focus ring is somewhere, and nothing answers.
	override var acceptsFirstResponder: Bool { true }

	override func becomeFirstResponder() -> Bool {
		// After this call, not during it: the window is still assigning the
		// responder it was asked for, and asking it to assign another one from
		// inside that is how AppKit is made to recurse.
		DispatchQueue.main.async { [weak self] in self?.focusList() }
		return super.becomeFirstResponder()
	}

	/// Puts the keyboard in the list somebody would arrow through.
	///
	/// The commits, because that is what a log is; the files follow from
	/// whichever commit is selected, and clicking one gives it the keyboard the
	/// way any table does.
	func focusList() {
		guard let window, window.firstResponder === self else { return }
		window.makeFirstResponder(commitTable)
	}
	/// The two arrangements, as a control. Only the page has one — see
	/// `arrangesFilesByFolder` for why the column does not.
	private var arrangeControl: NSSegmentedControl?
	private var detailLabel: NSTextField!
	/// The diff of the selected file, in `.page` only.
	private var diffView: DiffView?
	/// The page's splits, and whether their dividers have been put yet.
	private var pageSplit: NSSplitView?
	private var detailSplit: NSSplitView?
	private var hasPlacedDivider = false
	/// The commit message, on the page.
	private var messageView: NSTextView?
	/// How tall the message strip is, and whether it is open.
	/// The two tabs on the right, and what they show.
	private var detailTabs: NSSegmentedControl?
	private var detailMessage: NSScrollView?

	init(root: URL, layout: Layout = .sidebar) {
		self.root = root
		self.arrangement = layout
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		beginFirstRead()
		reload()

		NotificationCenter.default.addObserver(
			self, selector: #selector(reload), name: .abydosRepositoryChanged, object: nil
		)
	}

	/// Shown until the first log comes back — see `ChangesPane.activity` for why
	/// it is the first only.
	private var activity: PaneActivityView?

	private func beginFirstRead() {
		activity = PaneActivityView.install(over: self, message: "Reading history…")
	}

	private func finishFirstRead() {
		activity?.finish()
		activity = nil
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
		commitTable.onFold = { [weak self] expanding, row in
			guard let self, self.visible.indices.contains(row) else { return }
			let hash = self.visible[row].commit.hash
			// Folded already and asked to fold again, or open and asked to
			// open: nothing to do rather than a redraw that looks like a
			// keypress being ignored for a different reason.
			guard expanding == self.collapsedMerges.contains(hash) else { return }
			guard (self.visible[row].graph?.collapsible ?? 0) > 0 else { return }
			self.toggleCollapse(at: row)
		}

		fileList = ChangedFileList(
			rowHeight: Theme.current.scaled(22),
			arrangedByFolder: arrangesFilesByFolder
		)
		fileList.onSelect = { [weak self] file in self?.fileSelected(file) }

		detailLabel = NSTextField(labelWithString: "")
		// Left, like everything else it sits above. A wrapping label defaults
		// to centred, which reads as a heading rather than as the commit's own
		// words.
		detailLabel.alignment = .left
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
		let fileScroll: NSView = fileList

		if arrangement == .page {
			buildPage(commits: commitScroll, files: fileScroll)
			return
		}

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

	/// The graph on one side and what the selected commit did on the other.
	///
	/// A split rather than a fixed fraction: how much room a diff wants depends
	/// entirely on the diff, and a log is read by moving between the two.
	private func buildPage(commits: NSScrollView, files: NSView) {
		diffView = DiffView()
		// **A commit has already happened.** Left writable, the page offered
		// "Stage Selected Lines" and "Discard Selected Lines" over a diff of
		// something already in history — verbs with no meaning here, wired to
		// nothing, doing nothing when pressed. The editor's commit-diff tab has
		// said this since it was written; the page had not.
		diffView?.isReadOnly = true
		let diffScroll = NSScrollView()
		diffScroll.documentView = diffView
		diffScroll.hasVerticalScroller = true
		diffScroll.drawsBackground = true
		diffScroll.backgroundColor = Theme.current.editorBackground

		// **The document view has to be told its width.** A custom view handed
		// to a scroll view keeps whatever frame it was born with — zero — so
		// there was nothing to scroll and nothing to click: the diff was drawn
		// by a view the size of a point. Pinned to the clip view's width, with
		// the height coming from `intrinsicContentSize`, which is what it is
		// for.
		diffView?.translatesAutoresizingMaskIntoConstraints = false
		if let diffView {
			NSLayoutConstraint.activate([
				diffView.leadingAnchor.constraint(equalTo: diffScroll.contentView.leadingAnchor),
				diffView.trailingAnchor.constraint(equalTo: diffScroll.contentView.trailingAnchor),
				diffView.topAnchor.constraint(equalTo: diffScroll.contentView.topAnchor),
			])
		}

		// **A text view rather than a label.** A commit message is prose with
		// paragraphs in it, and the column's label had the newlines replaced
		// with spaces to fit on one line — which on a page is exactly the half
		// of the message nobody can then read.
		let message = NSTextView()
		message.isEditable = false
		message.isSelectable = true
		message.drawsBackground = false
		message.textContainerInset = NSSize(width: 8, height: 8)
		message.font = Theme.current.uiFont(11.5)
		message.textColor = Theme.current.sidebarText
		message.isVerticallyResizable = true
		message.isHorizontallyResizable = false
		message.autoresizingMask = [.width]
		message.textContainer?.widthTracksTextView = true
		messageView = message

		let messageScroll = NSScrollView()
		messageScroll.documentView = message
		messageScroll.hasVerticalScroller = true
		messageScroll.drawsBackground = true
		messageScroll.backgroundColor = Theme.current.sidebarBackground

		// **Every pane of a split is a scroll view, and nothing else.**
		// This was a stack view holding a split, inside another split. A stack
		// has an intrinsic height, a split has none, and one inside the other
		// gives autolayout a size it can satisfy two ways — so the page
		// negotiated with the terminal panel below it once per frame and
		// neither settled: the panel flickered, the divider would not drag, and
		// the contents moved while it was being dragged.
		//
		// A scroll view has no intrinsic content size, which is exactly what a
		// split view wants of its children. Minimums come from the delegate
		// rather than from constraints, for the same reason: a height
		// constraint on a pane is a second opinion about where the divider is.
		// **Two panes, not three.** The message, the files and the diff each
		// took a third, and the diff is what somebody opened the log to read.
		// The message is a strip above them instead — one line of subject,
		// which is all most commits have to say, and a click for the rest.
		// **Two tabs, not three panes.** The message, the files and the diff
		// each took a third and none of them had enough: a commit worth reading
		// the log for has a message worth reading whole, and a diff worth
		// reading whole, and they are not read at the same moment. So each gets
		// the height when it is the one being looked at.
		//
		// It also sidesteps the thing that has gone wrong three times here: a
		// split inside a split needs its panes frame-positioned by the parent,
		// and every arrangement that put something else in between argued with
		// the window once per frame. The tabs are a plain container.
		let changes = NSSplitView()
		changes.isVertical = false
		changes.dividerStyle = .thin
		changes.addArrangedSubview(files)
		changes.addArrangedSubview(diffScroll)
		changes.delegate = self
		changes.translatesAutoresizingMaskIntoConstraints = false
		detailSplit = changes

		let tabs = NSSegmentedControl(
			labels: ["Changes", "Message"],
			trackingMode: .selectOne,
			target: self,
			action: #selector(detailTabChanged)
		)
		tabs.controlSize = .small
		tabs.font = Theme.current.uiFont(11)
		// Changes first and selected: it is what somebody opened the log for.
		tabs.selectedSegment = 0
		tabs.translatesAutoresizingMaskIntoConstraints = false
		detailTabs = tabs

		messageScroll.translatesAutoresizingMaskIntoConstraints = false
		messageScroll.isHidden = true
		detailMessage = messageScroll

		// **The toggle goes in this strip, beside the tabs.** Not in the split
		// below it: that split's own comment says why nothing but a scroll view
		// may go in one — a stack view in there argued with the terminal panel
		// once per frame and the divider could not be dragged. This strip is a
		// plain container that already holds a control, so one more costs
		// nothing.
		//
		// Two segments rather than a button that flips, so the arrangement in
		// force is on screen rather than remembered.
		let arrange = ChangedFileList.makeArrangeControl(
			target: self, action: #selector(fileArrangementChanged)
		)
		arrange.selectedSegment = Settings.shared.commitFilesByFolder ? 1 : 0
		arrangeControl = arrange

		// Frame-positioned, because it is a pane of the split above it.
		let right = NSView()
		right.addSubview(tabs)
		right.addSubview(arrange)
		right.addSubview(changes)
		right.addSubview(messageScroll)

		let gap = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			tabs.topAnchor.constraint(equalTo: right.topAnchor, constant: gap / 2),
			tabs.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: gap),

			// The far end of the same row, so it sits over the list it arranges.
			arrange.centerYAnchor.constraint(equalTo: tabs.centerYAnchor),
			arrange.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -gap),

			changes.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: gap / 2),
			changes.leadingAnchor.constraint(equalTo: right.leadingAnchor),
			changes.trailingAnchor.constraint(equalTo: right.trailingAnchor),
			changes.bottomAnchor.constraint(equalTo: right.bottomAnchor),

			messageScroll.topAnchor.constraint(equalTo: changes.topAnchor),
			messageScroll.leadingAnchor.constraint(equalTo: changes.leadingAnchor),
			messageScroll.trailingAnchor.constraint(equalTo: changes.trailingAnchor),
			messageScroll.bottomAnchor.constraint(equalTo: changes.bottomAnchor),
		])

		let split = NSSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(commits)
		split.addArrangedSubview(right)
		split.delegate = self
		split.translatesAutoresizingMaskIntoConstraints = false
		pageSplit = split

		let head = NSStackView(views: [searchField, scopeControl])
		head.orientation = .horizontal
		head.spacing = Theme.current.scaled(8)
		head.translatesAutoresizingMaskIntoConstraints = false

		addSubview(head)
		addSubview(split)

		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			head.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			head.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			head.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			split.topAnchor.constraint(equalTo: head.bottomAnchor, constant: inset),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),
			split.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	/// Puts the divider somewhere sensible the first time there is a width to
	/// put it at.
	///
	/// **Once, and never again.** A split that reset itself on every layout
	/// would undo the drag somebody had just made — and constraints alone
	/// cannot do this, because "three fifths of whatever this turns out to be"
	/// is not a constraint an `NSSplitView` takes.
	override func layout() {
		super.layout()
		// **Waited for, not assumed.** A divider set while the split is still a
		// point wide lands at nothing and stays there, which is how the file
		// list came to be a sliver above the diff.
		guard !hasPlacedDivider, let pageSplit,
		      bounds.width > 1, (detailSplit?.bounds.height ?? 0) > Theme.current.scaled(120)
		else { return }
		hasPlacedDivider = true
		pageSplit.setPosition(bounds.width * 0.58, ofDividerAt: 0)
		// A short list of files and the rest for the diff, which is what
		// somebody opened the log to read, and a drag away from anything else.
		detailSplit?.setPosition(bounds.height * 0.3, ofDividerAt: 0)
	}

	/// Whether this pane's file list groups its rows under folders.
	///
	/// **The page only.** The other tense of this pane is a 300 pt sidebar
	/// column that hands its diffs to the editor area; a tree of folders in it
	/// is mostly indent, and the four rows of `Sources/AbydosKit/Git` above one
	/// file would leave nothing for the name. The preference is named for
	/// commit files, which is the page's list.
	private var arrangesFilesByFolder: Bool {
		arrangement == .page && Settings.shared.commitFilesByFolder
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

	/// Narrows the log to one ref, or widens it back to what is checked out.
	func setRef(_ ref: String?) {
		guard ref != scopedRef else { return }
		scopedRef = ref
		reload()
	}

	/// Which ref the log is showing, for a tab title and for a driver.
	var scopeName: String? { scopedRef }

	@objc func reload() {
		let scope = scopedPath
		let search = query
		let ref = scopedRef
		Task { @MainActor in
			isLoading = true
			let loaded = await GitHistory.log(
				in: root, path: scope, revision: ref,
				limit: Self.pageSize, search: search.isEmpty ? nil : search
			)
			// Before the guard below: a query that has moved on is still an
			// answer arriving, and the pane has stopped being blank either way.
			finishFirstRead()
			// Another scope or query landed while this was in flight.
			guard scope == self.scopedPath, search == self.query, ref == self.scopedRef else { return }

			// **Remembered by hash, because a reload moves every row.** The log
			// re-reads on every filesystem event, and a reload drops the
			// selection — so the commit somebody was reading came unselected
			// under them and the diff beside it went with it.
			let wasSelected = selectedCommit?.hash

			commits = loaded
			unpushed = await GitHistory.unpushed(in: root)
			hasMore = loaded.count == Self.pageSize
			isLoading = false
			// A fold only means something for the commits it was made on.
			collapsedMerges = []
			rebuildGraph()
			commitTable.reloadData()

			// Whatever was being read, if it is still here; the newest commit
			// otherwise, so the pane opens showing something rather than an
			// empty half.
			if !commits.isEmpty {
				let landing = wasSelected
					.flatMap { hash in visible.firstIndex { $0.commit.hash == hash } } ?? 0
				commitTable.selectRowIndexes(
					IndexSet(integer: landing), byExtendingSelection: false
				)
				commitTable.scrollRowToVisible(landing)
			} else {
				files = []
				selectedCommit = nil
				let nothing = search.isEmpty ? "No commits." : "Nothing matches “\(search)”."
				messageView?.string = nothing
				detailLabel.stringValue = nothing
				fileList.setFiles([])
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
	/// Folds a merge's branch away, or shows it again.
	///
	/// **The selection is kept by hash.** Rebuilding what is visible reloads
	/// the table, which drops it — so folding the row you were reading left
	/// nothing selected and took the diff beside it away. The refs tree keeps
	/// its selection across a rebuild for the same reason and by the same
	/// means; that they are two lists of different kinds is why it is written
	/// twice rather than shared, and it is worth saying so out loud.
	private func keepingSelection(_ change: () -> Void) {
		let wasSelected = selectedCommit?.hash
		change()
		guard let wasSelected,
		      let landing = visible.firstIndex(where: { $0.commit.hash == wasSelected })
		else { return }
		commitTable.selectRowIndexes(IndexSet(integer: landing), byExtendingSelection: false)
		commitTable.scrollRowToVisible(landing)
	}

	private func toggleCollapse(at row: Int) {
		guard visible.indices.contains(row) else { return }
		let commit = visible[row].commit
		guard visible[row].graph?.collapsible ?? 0 > 0 else { return }

		keepingSelection {
			if collapsedMerges.contains(commit.hash) {
				collapsedMerges.remove(commit.hash)
			} else {
				collapsedMerges.insert(commit.hash)
			}
			rebuildGraph()
			commitTable.reloadData()
		}
	}

	private func commitSelected() {
		let row = commitTable.selectedRow
		guard visible.indices.contains(row) else { return }
		let commit = visible[row].commit
		selectedCommit = commit

		// **The message as it was written, where there is room for it.** A
		// column has one line, so it gets the newlines flattened into it; a
		// page has a text view, and a commit message with its paragraphs taken
		// out is exactly the half of it nobody can read.
		let flat = [commit.subject, commit.body]
			.filter { !$0.isEmpty }
			.joined(separator: " — ")
		let whole = [commit.subject, commit.body]
			.filter { !$0.isEmpty }
			.joined(separator: "\n\n")

		if let messageView {
			// **Rendered, because commit messages here are markdown.** This
			// repository writes them with `**emphasis**`, backticked
			// identifiers and paragraphs, and a page with room for the whole
			// message is exactly where the asterisks stop being punctuation and
			// start being noise. The renderer is the app's own — the same one
			// the editor previews with.
			let rendered = MarkdownRenderer.render(whole, baseURL: root)
			messageView.textStorage?.setAttributedString(rendered)
		} else {
			detailLabel.stringValue = flat.replacingOccurrences(of: "\n", with: " ")
			detailLabel.toolTip = whole
		}

		Task { @MainActor in
			let loaded = await GitHistory.files(of: commit.hash, in: root)
			guard selectedCommit?.hash == commit.hash else { return }
			files = loaded
			// One `git show --numstat` for the whole commit, beside the file list
			// rather than before it: the rows are what somebody is waiting for
			// and the counts are something they say about themselves.
			fileList.setFiles(loaded)
			let counts = await GitLineCounts.commit(commit.hash, in: root)
			guard selectedCommit?.hash == commit.hash else { return }
			fileList.setLineCounts(counts)
		}
	}

	private func fileSelected(_ file: GitCommitFile) {
		guard let commit = selectedCommit else { return }

		// A column has nowhere to put a diff, so it hands it to the editor
		// area — which is the journey this whole change is finishing. A page
		// has the room, so it keeps it: that is the difference between reading
		// a log and leaving it every time you want to see anything.
		guard arrangement == .page, let diffView else {
			onSelectFile?(commit, file)
			return
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			let text = await GitHistory.diff(of: commit.hash, path: file.path, in: self.root)
			guard self.selectedCommit?.hash == commit.hash else { return }
			diffView.setDiff(text, staged: false, url: self.root.appendingPathComponent(file.path))
		}
	}

	// MARK: - Actions

	/// Shows the diff of the selected file, or the whole commit message.
	@objc private func detailTabChanged() {
		let showingMessage = detailTabs?.selectedSegment == 1
		detailMessage?.isHidden = !showingMessage
		detailSplit?.isHidden = showingMessage
	}

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

		// **The dot and the box beside it, measured the way they are drawn.**
		// The two were computed in two places and disagreed by three points:
		// the box is drawn from `own + radius + 3` and is nine wide, and the
		// target stopped at `centre + 13` — so the right-hand third of the very
		// thing somebody was aiming at did nothing.
		let centre = GraphMetrics.laneCentre(place.lane)
		let box = GraphMetrics.foldBox(lane: place.lane, isMerge: true, centreY: 0)
		// **Generous on purpose.** This was the drawn box exactly, then the box
		// plus two points, and it was reported unclickable both times — a
		// nine-point square is a hard thing to hit and an easy thing to be
		// three points wrong about. Anything from the lane's left edge to half
		// a lane past the box counts, which is a target somebody can hit and is
		// still nowhere near the text.
		let target = centre - GraphMetrics.laneWidth / 2
			... box.maxX + GraphMetrics.laneWidth / 2
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

	// MARK: - What can be done to a commit

	/// Runs something over the repository and tells the window it moved.
	private func run(_ operation: @escaping () async -> GitRepository.ProcessResult) {
		Task { @MainActor in
			let result = await operation()
			if result.exitCode != 0 {
				Toast.post(
					"That did not work",
					detail: result.stderr.isEmpty ? result.stdout : result.stderr
				)
			}
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: nil)
			reload()
		}
	}

	/// Reports an outcome that has three answers rather than two.
	///
	/// A revert or a cherry-pick that stops in a conflict has *already* changed
	/// the work tree, so "that did not work" would be false about it — the
	/// files are there, half-merged, and somebody has to be told which ones.
	private func report(_ outcome: GitCommits.Outcome, verb: String) {
		switch outcome {
		case .done:
			Toast.post("\(verb) done", kind: .information)
		case let .conflicted(paths):
			Toast.post(Toast(
				kind: .warning,
				title: "\(verb) stopped in \(paths.count) file\(paths.count == 1 ? "" : "s")",
				detail: paths.joined(separator: "\n"),
				actionTitle: "Abort",
				action: { [weak self] in
					guard let self else { return }
					Task { @MainActor in
						let undone = await GitCommits.abort(in: self.root)
						self.report(undone, verb: "Abort")
					}
				}
			))
		case let .failed(said):
			Toast.post("\(verb) did not happen", detail: said)
		}
		NotificationCenter.default.post(name: .abydosRepositoryChanged, object: nil)
		reload()
	}

	@objc private func checkoutCommit() {
		guard let commit = clickedCommit else { return }
		// Detaching HEAD is not destructive — nothing is lost by standing
		// somewhere else — so it asks nothing and keeps nothing.
		run { await GitRepository.run(["checkout", commit.hash], in: self.root) }
	}

	@objc private func branchFromHere() {
		guard let commit = clickedCommit else { return }
		promptForName(
			title: "New branch from \(commit.shortHash)",
			message: commit.subject,
			defaultValue: ""
		) { [weak self] name in
			guard let self, !name.isEmpty else { return }
			self.run { await GitRepository.run(["checkout", "-b", name, commit.hash], in: self.root) }
		}
	}

	@objc private func tagHere() {
		guard let commit = clickedCommit else { return }
		promptForName(
			title: "Tag \(commit.shortHash)",
			message: commit.subject,
			defaultValue: ""
		) { [weak self] name in
			guard let self, !name.isEmpty else { return }
			self.run { await GitTags.create(name, at: commit.hash, in: self.root) }
		}
	}

	@objc private func revertCommit() {
		guard let commit = clickedCommit else { return }
		Task { @MainActor in
			let outcome = await GitCommits.revert(commit.hash, in: root)
			report(outcome, verb: "Revert")
		}
	}

	@objc private func cherryPickCommit() {
		guard let commit = clickedCommit else { return }
		Task { @MainActor in
			let outcome = await GitCommits.cherryPick(commit.hash, in: root)
			report(outcome, verb: "Cherry-pick")
		}
	}

	/// The one on this menu that can lose work, and the only one that asks.
	@objc private func resetToCommit() {
		guard let commit = clickedCommit else { return }
		// The work tree, taken now rather than through `self` later: the sheet
		// is answered minutes afterwards and the pane may be gone by then,
		// while the repository it was reset against certainly is not.
		let root = self.root

		// Weak from the top and nowhere else. A weak capture inside a scope
		// that already holds a strong one reads as care that is not being
		// taken — the compiler says so, and `BranchesPane.recreateTag` learnt
		// it first.
		Task { @MainActor [weak self] in
			let leaving = await GitCommits.count(of: "HEAD", notIn: commit.hash, in: root)
			DestructiveAsk.run(
				.reset(to: commit.shortHash, commits: leaving, mode: .hard),
				in: root,
				over: self?.window
			) { _, _ in
				let outcome = await GitCommits.reset(to: commit.hash, mode: .hard, in: root)
				NotificationCenter.default.post(name: .abydosRepositoryChanged, object: nil)
				self?.reload()
				if case let .failed(said) = outcome { return said }
				return nil
			}
		}
	}

	/// Asks for a name, the way the branches pane does.
	private func promptForName(
		title: String,
		message: String,
		defaultValue: String,
		then act: @escaping (String) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
		field.stringValue = defaultValue
		alert.accessoryView = field

		let handle: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .alertFirstButtonReturn else { return }
			act(field.stringValue.trimmingCharacters(in: .whitespaces))
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: handle)
			window.makeFirstResponder(field)
		} else {
			handle(alert.runModal())
		}
	}

	// MARK: - Testing

	/// What the page is showing, on both sides of its split.
	///
	/// The claim is that a page holds what a column cannot: the graph with
	/// lanes and refs on one side, and the selected commit's files *and its
	/// diff* on the other rather than in a tab somewhere else.
	func pageReportForTesting() -> String {
		var said = ["layout=\(arrangement == .page ? "page" : "sidebar")"]
		said.append("commits=\(visible.count)")
		said += visible.prefix(6).map { row in
			let lanes = row.graph.map { "lane \($0.lane)" } ?? "no graph"
			let refs = row.commit.refs.isEmpty
				? ""
				: " [" + row.commit.refs.joined(separator: ", ") + "]"
			return "  \(row.commit.shortHash) \(lanes) \(row.commit.authorName)\(refs) \(row.commit.subject)"
		}
		said.append("files=\(files.count)")
		said += files.prefix(6).map { "  \($0.path)" }
		said.append("diff=\(diffView?.reportForTesting ?? "none")")
		return said.joined(separator: "\n")
	}

	/// Whether the log has anything in it yet.
	/// What the menu over the log page's diff offers — see
	/// `DiffView.verbsForTesting`. A commit has already happened, so the answer
	/// is that it offers nothing to stage or throw away.
	func diffVerbsForTesting() -> String {
		diffView?.verbsForTesting() ?? "no diff view"
	}

	var hasRowsForTesting: Bool { !visible.isEmpty }

	/// What the menu over a commit offers, one item per line.
	///
	/// The list is the claim — that a commit has verbs at all, and that the one
	/// which can lose work is fenced off from the ones that cannot — and a list
	/// diffs where a photograph of an open menu does not.
	func commitMenuForTesting(row: Int) -> String {
		guard visible.indices.contains(row) else { return "no such row" }
		commitTable.selectRowIndexes([row], byExtendingSelection: false)
		let menu = NSMenu()
		menu.delegate = self
		menuNeedsUpdate(menu)
		return menu.items
			.map { $0.isSeparatorItem ? "--" : $0.title }
			.joined(separator: "\n")
	}

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
		fileList.select(index: index)
	}

	/// The rows as they are drawn, top to bottom, so a driven run can compare
	/// the two arrangements — and compare the flat one against what the page
	/// drew when its file list was a table.
	func fileRowsForTesting() -> [String] { fileList.rowsForTesting() }

	@objc private func fileArrangementChanged() {
		Settings.shared.commitFilesByFolder = arrangeControl?.selectedSegment == 1
		fileList.arrangesByFolder = arrangesFilesByFolder
	}

	/// Draws the file list in whichever arrangement the preference now names.
	///
	/// The menu item flips the preference; this is the page catching up. Public
	/// because the window owns the menu and the page owns the rows.
	func applyFileArrangement() {
		arrangeControl?.selectedSegment = Settings.shared.commitFilesByFolder ? 1 : 0
		fileList.arrangesByFolder = arrangesFilesByFolder
	}

	/// Flips the arrangement, the way the menu item does.
	func toggleFileArrangementForTesting() {
		Settings.shared.commitFilesByFolder.toggle()
		applyFileArrangement()
	}

	func pressStarForTesting() { fileList.expandEveryFolder() }

	/// Works the commit's file list from the keyboard, and says what happened.
	func fileKeysForTesting(_ steps: String) -> String { fileList.keysForTesting(steps) }

	/// Shuts every folder, so `*` has something to do.
	func collapseEveryFolderForTesting() { fileList.collapseEveryFolder() }
}

// MARK: - Tables

extension HistoryPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int {
		// The changes view is an outline and asks its own questions; this is the
		// commit list alone now.
		visible.count
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		(tableView as? HistoryTableView)?.rowHeightOverride ?? Theme.current.scaled(22)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		if tableView === commitTable {
			guard commits.indices.contains(row) else { return nil }
			let commit = visible[row].commit
			let view = CommitRowView(
				commit: commit,
				isUnpushed: unpushed.contains(commit.hash),
				graph: visible[row].graph,
				isCollapsed: collapsedMerges.contains(commit.hash),
				// Who and when, which a 300 pt column has no room for and a
				// page does. They are the two questions a log is asked that the
				// subject cannot answer.
				showsAuthor: arrangement == .page
			)
			// **By hash, and selecting first.** The row index captured here is
			// the one the view was made at, and folding moves every row below
			// it — so a reused view folded whatever had since arrived at that
			// index. And a click on the button is not a click on the row, so
			// nothing was selected for `keepingSelection` to put back: the
			// keyboard path kept its selection because pressing ← requires
			// having one.
			view.onFold = { [weak self] in
				guard let self,
				      let now = self.visible.firstIndex(where: { $0.commit.hash == commit.hash })
				else { return }
				self.commitTable.selectRowIndexes(
					IndexSet(integer: now), byExtendingSelection: false
				)
				self.toggleCollapse(at: now)
			}
			return view
		}
		return nil
	}

	/// The theme's selection colour rather than the system's blue, in both of
	/// the log's tables — the same reason `ThemedRowView` was written.
	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		ThemedRowView()
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
		// Where you can stand, and what you can make from here.
		menu.addItem(item("Checkout", #selector(checkoutCommit)))
		menu.addItem(item("Branch from Here\u{2026}", #selector(branchFromHere)))
		menu.addItem(item("Tag Here\u{2026}", #selector(tagHere)))
		menu.addItem(.separator())

		// What this commit's change can do to the branch you are on. Revert and
		// cherry-pick add a commit; reset takes them away, which is why it is
		// fenced off below and is the only one here that asks first.
		menu.addItem(item("Revert\u{2026}", #selector(revertCommit)))
		menu.addItem(item("Cherry-pick", #selector(cherryPickCommit)))
		menu.addItem(.separator())
		menu.addItem(item("Reset to Here\u{2026}", #selector(resetToCommit)))
		menu.addItem(.separator())

		menu.addItem(item("Copy Commit Hash", #selector(copyHash)))
		menu.addItem(item("Copy Subject", #selector(copySubject)))
	}
}

extension HistoryPane: NSSplitViewDelegate {
	/// How small a pane may be dragged.
	///
	/// **Through the delegate rather than through constraints.** A height
	/// constraint on a pane is a second opinion about where the divider is, and
	/// two opinions is what made the page argue with the panel below it once
	/// per frame.
	func splitView(
		_ splitView: NSSplitView,
		constrainMinCoordinate minimum: CGFloat,
		ofSubviewAt divider: Int
	) -> CGFloat {
		// Two rows of files, or a third of the graph: below either there is
		// nothing to read, and a pane dragged to nothing cannot be found again.
		guard splitView === pageSplit else { return minimum + Theme.current.scaled(48) }
		return minimum + Theme.current.scaled(320)
	}

	func splitView(
		_ splitView: NSSplitView,
		constrainMaxCoordinate maximum: CGFloat,
		ofSubviewAt divider: Int
	) -> CGFloat {
		guard splitView === pageSplit else { return maximum - Theme.current.scaled(80) }
		return maximum - Theme.current.scaled(300)
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
	/// A click from an inactive window lands on the row, rather than being
	/// spent activating the app.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.resignFirstResponder()
	}

	var onSelectionChange: (() -> Void)?
	var onScrolledToEnd: (() -> Void)?
	var rowHeightOverride: CGFloat?
	/// A click in the graph column, which the pane may take for a fold.
	var onGraphClick: ((NSPoint, Int) -> Bool)?
	/// Left and right on a commit: fold the branch it brought in, or show it.
	var onFold: ((_ expanding: Bool, _ row: Int) -> Void)?

	override func keyDown(with event: NSEvent) {
		// A merge folds with ← and opens with →, as a tree does everywhere
		// else. It could only ever be done by hitting a nine-point box.
		if event.keyCode == 123 || event.keyCode == 124, selectedRow >= 0 {
			onFold?(event.keyCode == 124, selectedRow)
			return
		}
		super.keyDown(with: event)
	}

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
	/// Whether there is room for who made it and when.
	private let showsAuthor: Bool
	override var isFlipped: Bool { true }

	/// Pressed to fold the branch this merge brought in.
	var onFold: (() -> Void)?

	init(
		commit: GitCommit,
		isUnpushed: Bool = false,
		graph: GitGraph.Row? = nil,
		isCollapsed: Bool = false,
		showsAuthor: Bool = false
	) {
		self.commit = commit
		self.isUnpushed = isUnpushed
		self.graph = graph
		self.isCollapsed = isCollapsed
		self.showsAuthor = showsAuthor
		super.init(frame: .zero)
		var lines = [commit.shortHash, commit.subject, commit.body]
		if isUnpushed { lines.append("Not pushed yet") }
		toolTip = lines
			.filter { !$0.isEmpty }
			.joined(separator: "\n\n")

		addFoldButton()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Puts a real button where the fold marker is drawn.
	///
	/// **Three attempts at hit-testing the drawing were three attempts too
	/// many.** The box was measured in one place and clicked in another, then
	/// in one place with slack, then with more slack, and it was reported dead
	/// every time. A button cannot be three points out and cannot be argued
	/// with: AppKit routes the click, and the drawing is only a drawing.
	private func addFoldButton() {
		guard let graph, graph.collapsible > 0 else { return }

		let button = NSButton(frame: .zero)
		button.isBordered = false
		button.bezelStyle = .inline
		button.title = ""
		button.target = self
		button.action = #selector(foldPressed)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.toolTip = isCollapsed
			? "Show the \(graph.collapsible) commits this merge brought in"
			: "Fold away the \(graph.collapsible) commits this merge brought in"
		addSubview(button)

		// Bigger than the drawing, because a nine-point square is a hard thing
		// to hit; centred on it, so it still looks like what it is.
		let box = GraphMetrics.foldBox(lane: graph.lane, isMerge: commit.isMerge, centreY: 0)
		let size = Theme.current.scaled(18)
		NSLayoutConstraint.activate([
			button.centerXAnchor.constraint(equalTo: leadingAnchor, constant: box.midX),
			button.centerYAnchor.constraint(equalTo: centerYAnchor),
			button.widthAnchor.constraint(equalToConstant: size),
			button.heightAnchor.constraint(equalToConstant: size),
		])
	}

	@objc private func foldPressed() { onFold?() }

	/// How wide one lane is, and how far the text starts from the graph.
	private var laneWidth: CGFloat { GraphMetrics.laneWidth }

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
			// A row is drawn to its own bounds and nothing clips it, so a
			// commit at the tip of four refs used to draw its last pill over
			// whatever was beside the list. Stop instead: the subject is worth
			// more than a fifth label, and the tooltip has them all.
			guard pill.maxX < bounds.maxX - Theme.current.scaled(60) else { break }
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

		// **On a page, who and when are columns.** In a column they have to be a
		// second line under the subject, which is the only place they fit; with
		// room they belong at the right-hand edge, aligned down the list, where
		// the eye can run past them rather than through them.
		var subjectLimit = max(0, bounds.width - x - Theme.current.scaled(10))
		if showsAuthor {
			let columns = NSAttributedString(
				string: "\(commit.authorName)   \(Self.age(of: commit.date))",
				attributes: [
					.font: Theme.current.uiFont(10.5),
					.foregroundColor: Theme.current.gitIgnored,
				]
			)
			let width = columns.size().width
			let right = bounds.maxX - Theme.current.scaled(12) - width
			columns.draw(at: NSPoint(x: right, y: top + Theme.current.scaled(1)))
			subjectLimit = max(0, right - x - Theme.current.scaled(12))
		}

		let subject = NSAttributedString(string: commit.subject, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		subject.draw(in: NSRect(
			x: x, y: top,
			width: subjectLimit,
			height: subject.size().height
		))

		// Merges are worth telling apart at a glance: their diff is against the
		// first parent and reads differently from an ordinary commit's.
		var meta = showsAuthor
			? commit.shortHash
			: "\(commit.shortHash)  ·  \(commit.authorName)  ·  \(Self.age(of: commit.date))"
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
		func centre(_ lane: Int) -> CGFloat { GraphMetrics.laneCentre(lane) }

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
		// Through the same measurements the click is tested against, so the two
		// cannot drift apart again.
		let box = GraphMetrics.foldBox(
			lane: graph.lane, isMerge: commit.isMerge, centreY: centreY
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

/// Where the graph puts things.
///
/// **One set of numbers for drawing and for hit-testing.** They were written
/// out twice and disagreed by three points, which is how a fold marker came to
/// be drawn where a click on it did nothing.
enum GraphMetrics {
	static var laneWidth: CGFloat { Theme.current.scaled(13) }

	static func laneCentre(_ lane: Int) -> CGFloat {
		Theme.current.scaled(8) + CGFloat(lane) * laneWidth
	}

	static func dotRadius(isMerge: Bool) -> CGFloat {
		Theme.current.scaled(isMerge ? 4 : 3.5)
	}

	/// The box holding the plus or minus, beside the dot.
	static func foldBox(lane: Int, isMerge: Bool, centreY: CGFloat) -> NSRect {
		NSRect(
			x: laneCentre(lane) + dotRadius(isMerge: isMerge) + Theme.current.scaled(3),
			y: centreY - Theme.current.scaled(4.5),
			width: Theme.current.scaled(9),
			height: Theme.current.scaled(9)
		)
	}
}

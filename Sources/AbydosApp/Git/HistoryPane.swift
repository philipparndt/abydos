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
	/// The mirror image: commits the scoped ref's upstream has and it does not.
	/// These rows are drawn dimmed — on the page before a pull, not of the
	/// branch yet.
	private var remoteOnly: Set<String> = []
	/// The upstream the scoped log is showing beside its ref, so paging asks
	/// the same question the first page did.
	private var scopedUpstream: String?
	/// Per visible row, the lanes that are inside an unpulled commit's line to
	/// its parent. The line fades as one piece: dimming only the remote row's
	/// own strokes left the segment snapping back to full strength below the
	/// dot, which read as a bright line through a quiet commit.
	private var fadedLanesByRow: [Set<Int>] = []
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
			// The upstream before the log, because its name goes into the same
			// log call: a repository saying "1 behind" opened "Log · main" with
			// no trace of that commit, and the fix is one union git orders
			// rather than a second list merged here.
			var remote = GitHistory.RemoteOnly.none
			if let ref { remote = await GitHistory.remoteOnly(of: ref, in: root) }
			let loaded = await GitHistory.log(
				in: root, path: scope, revision: ref, upstream: remote.upstream,
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
			remoteOnly = remote.hashes
			scopedUpstream = remote.upstream
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
		// The same question the first page asked. Without the ref, paging a
		// scoped log fell through to the everything-log, and the second page
		// continued every branch there is.
		let ref = scopedRef
		let upstream = scopedUpstream
		let offset = commits.count

		Task { @MainActor in
			isLoading = true
			let more = await GitHistory.log(
				in: root, path: scope, revision: ref, upstream: upstream,
				skip: offset, limit: Self.pageSize,
				search: search.isEmpty ? nil : search
			)
			guard scope == self.scopedPath, search == self.query,
				ref == self.scopedRef, offset == self.commits.count else { return }

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
			rebuildFadedLanes()
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
		rebuildFadedLanes()
	}

	/// One walk down the rows: a lane joins the set below an unpulled commit
	/// and leaves it at the first commit of the branch's own that it reaches —
	/// which is the parent the unpulled work was built on, and whose stub from
	/// above is the last faded piece.
	private func rebuildFadedLanes() {
		fadedLanesByRow = Array(repeating: [], count: visible.count)
		guard !remoteOnly.isEmpty else { return }

		var live: Set<Int> = []
		for (index, row) in visible.enumerated() {
			fadedLanesByRow[index] = live
			guard let graph = row.graph else { continue }
			if remoteOnly.contains(row.commit.hash) {
				for edge in graph.edges where edge.from == graph.lane {
					live.insert(edge.to)
				}
			} else {
				live.remove(graph.lane)
			}
		}
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

	/// A diff belongs in a tab, and the pane does not own the editor: whoever
	/// built this pane says where the diff goes.
	var onOpenWorkingCopyDiff: ((GitChange, URL, String) -> Void)?

	/// How far now is from then, for the one file this log is scoped to.
	/// Selecting the commit already shows what it changed at the time; this
	/// is the other question.
	@objc private func compareCommitWithWorkingCopy() {
		guard let commit = clickedCommit, let path = scopedPath else { return }
		Task { @MainActor in
			let text = await GitWorkingCopy.diffToWorkingCopy(
				since: commit.hash, for: path, in: self.root
			)
			guard !text.isEmpty else {
				Toast.post(
					"Nothing to compare",
					detail: "The working copy matches \(commit.shortHash).",
					kind: .information
				)
				return
			}
			self.onOpenWorkingCopyDiff?(
				GitChange(path: path, kind: .modified, isStaged: false),
				self.root, text
			)
		}
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

	/// Runs a driver's comma-separated step script against this pane. The
	/// steps live here rather than on the controller that owns the page, the
	/// way the pull request list drives itself: every one of them is a
	/// question or a verb of this pane's, and the controller's part is only
	/// to have the page and wait for its first rows.
	func driveForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// The diff of a file is read off the main queue like everything
			// else here, so a report taken in the same turn as the selection
			// sees the state before it.
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.driveForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("LOG-PAGE:\n\(pageReportForTesting())")
			// Narrow to one ref, the way a branch row's "show log" does: the
			// scoped log is where the upstream's unpulled commits appear, and a
			// driver that can only open the everything-log could not ask about
			// them. Follow with `settle` — the reload is asynchronous.
			case "scope":  setRef(argument.isEmpty ? nil : argument)
			// Narrow to one file, the way Compare ▸ History… arrives.
			case "path":
				offerScope(path: argument.isEmpty ? nil : argument)
				setScope(path: argument.isEmpty ? nil : argument)
			case "verbs":  print("LOG-PAGE verbs: \(diffVerbsForTesting())")
			case "menu":   print("LOG-PAGE-MENU:\n\(commitMenuForTesting(row: Int(argument) ?? 0))")
			// `choose:<row>:<title>` fires that row's menu item by title, the
			// way a person picking Compare with Working Copy does.
			case "choose":
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				if parts.count == 2, let row = Int(parts[0]) {
					print("LOG-PAGE choose: \(chooseCommitMenuItemForTesting(row: row, titled: parts[1]))")
				} else {
					print("LOG-PAGE choose: wants row:title, got \(argument)")
				}
			case "file":
				selectCommitForTesting(0)
				selectFileForTesting(Int(argument) ?? 0)
			// The changes view's own rows, which `report` does not carry: how a
			// commit's files are arranged is the question, and the flat
			// arrangement has to match what the page drew before it was an
			// outline at all.
			// The keyboard's own claims: a click gives the list focus, the
			// arrows move, and ← and → shut and open without losing the row.
			case "keys":
				print("LOG-PAGE keys: " + fileKeysForTesting(argument))
				fflush(stdout)
			case "files":
				print("LOG-PAGE files:\n  " + fileRowsForTesting().joined(separator: "\n  "))
			case "arrange": toggleFileArrangementForTesting()
			case "star":    pressStarForTesting()
			case "shut":    collapseEveryFolderForTesting()
			// A script that says so ends the run, as the commit page's does:
			// whatever is waiting on the process gets an exit rather than
			// having to kill it, and an exit is the one ending that flushes.
			case "exit":   fflush(stdout); exit(0)
			default:       print("LOG-PAGE: unknown step \(step)")
			}
		}
		fflush(stdout)
	}

	/// What the page is showing, on both sides of its split.
	///
	/// The claim is that a page holds what a column cannot: the graph with
	/// lanes and refs on one side, and the selected commit's files *and its
	/// diff* on the other rather than in a tab somewhere else.
	func pageReportForTesting() -> String {
		var said = ["layout=\(arrangement == .page ? "page" : "sidebar")"]
		// Which segment is lit, because Compare ▸ History…'s claim is that it
		// lands on "This File" — a state a screenshot of a segmented control
		// says less reliably than the control itself.
		let scope = scopeControl.selectedSegment == 1
			? (scopeControl.label(forSegment: 1) ?? "file") : "whole"
		said.append("scope=\(scope)")
		said.append("commits=\(visible.count)")
		said += visible.prefix(6).map { row in
			let lanes = row.graph.map { "lane \($0.lane)" } ?? "no graph"
			// Dimming is a drawing, and a driven run reads text: the marker is
			// how a test can say which rows are the unpulled ones.
			let side = remoteOnly.contains(row.commit.hash) ? " remote-only" : ""
			let refs = row.commit.refs.isEmpty
				? ""
				: " [" + row.commit.refs.joined(separator: ", ") + "]"
			return "  \(row.commit.shortHash) \(lanes)\(side) \(row.commit.authorName)\(refs) \(row.commit.subject)"
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
	/// Fires one of the commit menu's items by title, through the same menu
	/// `menu:` reports, so the verb is proven to be *in* the menu rather than
	/// merely behind a method the driver knows.
	func chooseCommitMenuItemForTesting(row: Int, titled title: String) -> String {
		guard visible.indices.contains(row) else { return "no such row" }
		commitTable.selectRowIndexes([row], byExtendingSelection: false)
		let menu = NSMenu()
		menu.delegate = self
		menuNeedsUpdate(menu)
		guard let item = menu.items.first(where: { $0.title == title }) else {
			return "\(title) is not in the menu"
		}
		guard let action = item.action, let target = item.target else {
			return "\(title) has no action"
		}
		_ = NSApp.sendAction(action, to: target, from: item)
		return "fired \(title)"
	}

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
				isRemoteOnly: remoteOnly.contains(commit.hash),
				fadedLanes: fadedLanesByRow.indices.contains(row) ? fadedLanesByRow[row] : [],
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
		// Only on a file-scoped log: on the whole log "the working copy
		// against then" spans every file, which is not a diff tab, and the
		// item would lie about what it opens.
		if scopedPath != nil {
			menu.addItem(item(
				"Compare with Working Copy", #selector(compareCommitWithWorkingCopy)
			))
		}
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


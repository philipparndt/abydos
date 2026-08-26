import AppKit
import AbydosKit

/// Staging and committing, in the shape Fork uses: unstaged above, staged
/// below, the commit message under both.
///
/// Two lists rather than one with checkboxes. The index is a real thing with
/// its own contents — a file can be half in it — and a single list with a tick
/// per row cannot show that a file is in both states at once.
///
/// Each list is a tree of the folders the changes are in, because the project
/// is a tree: a flat column of near-identical paths differing in the middle is
/// hard to read, and staging a directory used to mean selecting every file
/// under it by hand. `GitChangeTree` decides the shape; this decides what the
/// rows look like and what happens to them.
final class ChangesPane: NSView {
	/// How much room this has, and therefore what it can draw.
	///
	/// **One pane and not two**, the rule `HistoryPane` already keeps: the
	/// tree, folder staging, the discard question and what a folder says about
	/// being half-staged are the same questions at either size, and two classes
	/// asking them would be two answers that drift.
	enum Layout {
		/// A 300 pt column: the two trees, a one-line summary and Commit. The
		/// diff opens as an editor tab because there is nowhere else, and a
		/// description is written on the page.
		case sidebar
		/// A tab of its own: the two trees with the diff beside them and a
		/// message with room for a body.
		case page
	}

	/// A change was selected, to show its diff. Only in `.sidebar`.
	var onSelectChange: ((GitChange) -> Void)?
	/// Somebody wants the page, carrying whatever summary they have typed.
	var onOpenPage: ((String) -> Void)?
	/// Something was staged, unstaged or committed.
	var onWorkingCopyChanged: (() -> Void)?

	/// Not `layout`: that is `NSView`'s, and shadowing it means an override
	/// silently is not one — which cost an afternoon in `HistoryPane`.
	private let arrangement: Layout
	private let root: URL

	/// The work tree this pane is showing, so the window can tell whether the
	/// one it has is the one it wants rather than building another.
	var repositoryRoot: URL { root }

	private var status = GitWorkingCopyStatus()
	private var unstagedTable: ChangesOutlineView!
	private var stagedTable: ChangesOutlineView!
	private var unstagedHeader: SectionHeaderView!
	private var stagedHeader: SectionHeaderView!

	/// One side of the index, as rows.
	///
	/// The tree is thrown away and built again on every refresh — which happens
	/// on every filesystem event — so everything that has to outlive a rebuild
	/// is kept here as paths. Rebuilding and re-deriving is what `TreeSelection`
	/// exists for in the navigator, and 0446 is why nothing here tries to be
	/// cleverer than that.
	private struct Side {
		var roots: [GitChangeNode] = []
		var byPath: [String: GitChangeNode] = [:]
		/// Folders somebody folded shut. Held the negative way round because a
		/// changes tree wants to arrive open: a pane that shows five folder
		/// names where the flat list showed twenty files has told you less than
		/// it did before, and a folder that appears while you are working is
		/// new work you should see.
		var collapsed: Set<String> = []
		/// Where the selection goes when everything selected has been staged
		/// away. See `rememberWhereTheSelectionGoes`.
		var fallback: String?
		/// What an untracked directory turned out to hold, by its path.
		///
		/// Kept across a rebuild, which is what stops an open folder collapsing
		/// under whoever is reading it: the tree is built from scratch on every
		/// filesystem event, so the rows that were under it are new objects and
		/// the answer has to be put back before the view asks.
		var untrackedContents: [String: [GitChangeNode]] = [:]
		/// Untracked directories somebody has opened. Held the positive way
		/// round, unlike `collapsed`: these arrive shut and cost a git call to
		/// open, so the default is closed and only a deliberate gesture changes
		/// it.
		var opened: Set<String> = []
	}

	private var unstagedSide = Side()
	private var stagedSide = Side()

	/// Set while the pane is putting expansion or selection back after a
	/// rebuild, so that its own work is not mistaken for somebody's.
	private var isRestoring = false

	private var subjectField: NSTextField!
	/// The diff of the selected change, in `.page` only.
	private var diffView: DiffView?
	private var pageSplit: NSSplitView?
	private var hasPlacedDivider = false
	private var draftButton: NSButton?
	private var bodyView: NSTextView!
	private var amendCheckbox: NSButton!
	private var commitButton: NSButton!
	private var pushButton: NSButton!
	/// Where the branch stands against its remote, for what push should say.
	private var pushState: GitPush.State?

	/// Guards against a refresh landing while a git command is still running and
	/// showing a half-applied state.
	private var isBusy = false

	init(root: URL, layout: Layout = .sidebar) {
		self.root = root
		self.arrangement = layout
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		beginFirstRead()
		refresh()

		// The lists have to follow the work tree, not just this view's own
		// commands: editing a file in the editor changes what is stageable.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(workingCopyMayHaveChanged),
			name: .abydosRepositoryChanged,
			object: nil
		)
	}

	deinit { NotificationCenter.default.removeObserver(self) }

	@objc private func workingCopyMayHaveChanged() {
		refresh()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Layout

	private func build() {
		unstagedHeader = SectionHeaderView(title: "Unstaged", actionTitle: "Stage")
		unstagedHeader.onAction = { [weak self] in self?.stageSelected() }
		stagedHeader = SectionHeaderView(title: "Staged", actionTitle: "Unstage")
		stagedHeader.onAction = { [weak self] in self?.unstageSelected() }

		unstagedTable = makeTable()
		unstagedTable.onActivate = { [weak self] row in
			guard let self else { return }
			self.activate(row: row, in: self.unstagedTable)
		}
		unstagedTable.menu = makeChangeMenu()
		stagedTable = makeTable()
		stagedTable.onActivate = { [weak self] row in
			guard let self else { return }
			self.activate(row: row, in: self.stagedTable)
		}
		stagedTable.menu = makeChangeMenu()

		let unstagedScroll = makeScrollView(for: unstagedTable)
		let stagedScroll = makeScrollView(for: stagedTable)

		// The subject is where a commit starts, so it has to look like the
		// field you type in first: the same dark ground and border as the body
		// below it, and a little larger. Flat and grey it read as disabled, and
		// people went to the body instead and left the subject empty.
		subjectField = InsetTextField()
		subjectField.placeholderString = "Summary"
		subjectField.font = Theme.current.uiFont(12, weight: .medium)
		subjectField.delegate = self
		subjectField.focusRingType = .none
		subjectField.isBordered = false
		subjectField.drawsBackground = false
		subjectField.textColor = Theme.current.sidebarText
		subjectField.wantsLayer = true
		subjectField.layer?.backgroundColor = Theme.current.editorBackground.cgColor
		subjectField.layer?.borderColor = Theme.current.separator.cgColor
		subjectField.layer?.borderWidth = 1
		subjectField.layer?.cornerRadius = 3

		bodyView = NSTextView()
		bodyView.font = Theme.current.uiFont(12)
		bodyView.textColor = Theme.current.sidebarText
		bodyView.backgroundColor = Theme.current.editorBackground
		bodyView.isRichText = false
		bodyView.textContainerInset = NSSize(width: 4, height: 4)

		// What a text view in a scroll view needs before it is any size at all.
		// Without it the view keeps its empty starting frame however large the
		// box around it looks, so every click in the details field landed on the
		// scroll view behind it and the caret never arrived — the field looked
		// like a field and refused to be typed in.
		bodyView.isEditable = true
		bodyView.isSelectable = true
		bodyView.isVerticallyResizable = true
		bodyView.isHorizontallyResizable = false
		bodyView.autoresizingMask = [.width]
		bodyView.minSize = .zero
		bodyView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		bodyView.textContainer?.widthTracksTextView = true
		bodyView.textContainer?.containerSize = NSSize(
			width: 0, height: CGFloat.greatestFiniteMagnitude
		)

		let bodyScroll = NSScrollView()
		bodyScroll.documentView = bodyView
		bodyScroll.hasVerticalScroller = true
		bodyScroll.borderType = .lineBorder
		bodyScroll.drawsBackground = true
		bodyScroll.backgroundColor = Theme.current.editorBackground

		amendCheckbox = NSButton(checkboxWithTitle: "Amend", target: self, action: #selector(amendToggled))
		amendCheckbox.font = Theme.current.uiFont(11)

		commitButton = NSButton(title: "Commit", target: self, action: #selector(commit))
		commitButton.bezelStyle = .rounded
		commitButton.controlSize = .small
		commitButton.keyEquivalent = "\r"

		// Beside commit rather than inside it: "commit and push" is one gesture
		// people want, but pushing what somebody else committed is a different
		// decision from making a commit, and hiding it in a split button makes
		// it hard to do on its own.
		pushButton = NSButton(title: "Push", target: self, action: #selector(push))
		pushButton.bezelStyle = .rounded
		pushButton.controlSize = .small
		pushButton.isEnabled = false

		// Commit then push: that is the order the two happen in, and reading the
		// row left to right should not be backwards from doing it.
		let commitRow = NSStackView(views: [amendCheckbox, NSView(), commitButton, pushButton])
		commitRow.spacing = Theme.current.scaled(6)
		commitRow.orientation = .horizontal
		commitRow.distribution = .fill

		if arrangement == .page {
			arrangePage(
				unstaged: unstagedScroll, staged: stagedScroll,
				body: bodyScroll, commitRow: commitRow
			)
			return
		}

		// **The description leaves the column.** Seventy points of text view is
		// where a commit message goes to be one line long; the page is where a
		// message somebody will read in a year gets written, and `…` is how you
		// get there with what you have already typed.
		let more = NSButton(title: "…", target: self, action: #selector(openPage))
		more.bezelStyle = .rounded
		more.controlSize = .small
		more.toolTip = "Write the message on a page, with room for a description"
		commitRow.addArrangedSubview(more)

		let stack = NSStackView(views: [
			unstagedHeader, unstagedScroll,
			stagedHeader, stagedScroll,
			subjectField, commitRow,
		])
		stack.orientation = .vertical
		stack.spacing = 0
		stack.setCustomSpacing(Theme.current.scaled(8), after: stagedScroll)
		stack.setCustomSpacing(Theme.current.scaled(6), after: subjectField)
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: Theme.current.scaled(8), right: 0)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		for view in [subjectField, commitRow] as [NSView] {
			stack.setCustomSpacing(stack.customSpacing(after: view), after: view)
		}

		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),

			// The two lists share the space that is left after the commit box,
			// so neither can squeeze the other out.
			unstagedScroll.heightAnchor.constraint(equalTo: stagedScroll.heightAnchor),
			subjectField.heightAnchor.constraint(equalToConstant: Theme.current.scaled(24)),
		])

		// Inset the message box from the edges without inseting the lists, which
		// read better running the full width.
		for view in [subjectField, commitRow] as [NSView] {
			stack.setHuggingPriority(.defaultLow, for: .horizontal)
			view.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(8)),
				view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(8)),
			])
		}
	}

	/// The trees, the diff beside them, and the message under both.
	///
	/// The same shape the log page takes, because it is the same thing in
	/// another tense: a list of changes on the left, the diff of the selected
	/// one on the right, and what to do with the set along the bottom. The
	/// working copy is the commit that has not happened yet.
	private func arrangePage(
		unstaged: NSScrollView, staged: NSScrollView,
		body: NSScrollView, commitRow: NSStackView
	) {
		diffView = DiffView()
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

		let lists = NSStackView(views: [unstagedHeader, unstaged, stagedHeader, staged])
		lists.orientation = .vertical
		lists.spacing = 0
		unstaged.heightAnchor.constraint(equalTo: staged.heightAnchor).isActive = true

		let split = NSSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(lists)
		split.addArrangedSubview(diffScroll)
		// The list gives way first: a diff with its right-hand columns cut off
		// is unreadable, where a path that has lost a folder or two is not.
		split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
		split.translatesAutoresizingMaskIntoConstraints = false
		pageSplit = split

		// **The draft sits beside the summary**, because that is the field it
		// fills and the one that is hardest to start. Absent rather than
		// disabled when there is no `claude` to run: a control that fails when
		// pressed is worse than one that is not there.
		var summaryRow: [NSView] = [subjectField]
		if ClaudeDraft.isAvailable {
			draftButton = NSButton(title: "Draft", target: self, action: #selector(draftMessage))
			draftButton?.bezelStyle = .rounded
			draftButton?.controlSize = .small
			draftButton?.toolTip = "Write a summary and description from what is staged"
			summaryRow.append(draftButton!)
		}
		let summary = NSStackView(views: summaryRow)
		summary.orientation = .horizontal
		summary.spacing = Theme.current.scaled(6)

		let message = NSStackView(views: [summary, body, commitRow])
		message.orientation = .vertical
		message.spacing = Theme.current.scaled(6)

		for view in [split, message] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			split.topAnchor.constraint(equalTo: topAnchor),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),

			message.topAnchor.constraint(equalTo: split.bottomAnchor, constant: inset),
			message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			message.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),

			subjectField.heightAnchor.constraint(equalToConstant: Theme.current.scaled(26)),
			// Room for a paragraph, which is the whole reason this page exists.
			body.heightAnchor.constraint(equalToConstant: Theme.current.scaled(150)),
			lists.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.current.scaled(280)),
			diffScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.current.scaled(320)),
		])
	}

	/// Puts the divider somewhere sensible the first time there is a width for
	/// it, and never again — a split that reset itself on every layout would
	/// undo the drag somebody had just made.
	override func layout() {
		super.layout()
		guard !hasPlacedDivider, let pageSplit, bounds.width > 1 else { return }
		hasPlacedDivider = true
		pageSplit.setPosition(bounds.width * 0.42, ofDividerAt: 0)
	}

	private func makeTable() -> ChangesOutlineView {
		let table = ChangesOutlineView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.selectionHighlightStyle = .regular
		table.allowsMultipleSelection = true
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		// The navigator's indent, so the two trees in the window line up.
		table.indentationPerLevel = Theme.current.scaled(14)
		table.autoresizesOutlineColumn = false
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change"))
		table.addTableColumn(column)
		table.outlineTableColumn = column
		table.delegate = self
		table.dataSource = self
		return table
	}

	private func makeScrollView(for table: NSTableView) -> NSScrollView {
		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.sidebarBackground
		scrollView.scrollerStyle = .overlay
		return scrollView
	}

	// MARK: - Data

	func refresh() {
		guard !isBusy else { return }
		// Outside the comparison below: a clean working copy produces the same
		// status every time, and the branch can still have moved ahead of its
		// remote since the last look.
		refreshPushState()
		Task { @MainActor in
			let fresh = await GitWorkingCopy.status(in: root)
			// Taken down before the comparison below, not after it. An
			// unchanged status is still an answer, and a spinner that only
			// stopped when something had changed span for ever over a clean
			// working copy.
			finishFirstRead()
			guard fresh != status else { return }
			status = fresh
			reload()
		}
	}

	/// Shown until the first `git status` comes back.
	///
	/// Only the first: after that the pane has rows on it, and covering them
	/// every time a build writes a file would be worse than a moment of
	/// staleness.
	private var activity: PaneActivityView?

	/// Puts the spinner up. Called once, as the pane is built, because that is
	/// when there is nothing on screen and the wait is longest.
	private func beginFirstRead() {
		activity = PaneActivityView.install(over: self, message: "Reading changes…")
	}

	private func finishFirstRead() {
		activity?.finish()
		activity = nil
	}

	private func reload() {
		rebuild(unstagedTable, staged: false, changes: status.unstaged, against: status.staged)
		rebuild(stagedTable, staged: true, changes: status.staged, against: status.unstaged)
		// **Once per set of changes, and only when the set has moved.** `refresh`
		// above returns early on a status equal to the last one, which is every
		// answer over a clean working copy and most of them during a build — so
		// this is not on the per-filesystem-event path even though `reload` is
		// what that path calls. One `--numstat` per side, not one diff per row:
		// the row count is the size of somebody's commit.
		askForLineCounts()
		// Files, not rows: "Commit 7 Files" has to keep meaning seven files
		// however many folders they are spread over.
		unstagedHeader.setCount(status.unstaged.count)
		stagedHeader.setCount(status.staged.count)
		updateCommitButton()
	}

	/// How much each changed file changed, from one `git diff --numstat` a side.
	///
	/// After the trees are built and drawn rather than before: the counts are
	/// something a row says about itself, not something that decides whether the
	/// row exists, and waiting for them would hold the whole pane behind a
	/// second git call.
	private func askForLineCounts() {
		for staged in [false, true] {
			let outline = staged ? stagedTable! : unstagedTable!
			Task { @MainActor in
				let counts = await GitLineCounts.workingCopy(staged: staged, in: root)
				// The tree may have been rebuilt while this was out; the roots
				// read here are whichever ones are on screen now.
				for root in self.side(for: outline).roots { root.applyLineCounts(counts) }
				self.lineCounts[staged] = counts
				outline.reloadData()
				// A reload throws the expansion away, so it goes back the way it
				// does everywhere else in this pane.
				self.isRestoring = true
				self.expand(
					self.side(for: outline).roots, in: outline,
					collapsed: self.side(for: outline).collapsed
				)
				self.isRestoring = false
			}
		}
	}

	/// What the last `--numstat` said, by side, so a row filled later — an
	/// untracked directory somebody opens — can be given its counts without
	/// asking git again.
	private var lineCounts: [Bool: [String: GitLineCount]] = [:]

	/// Builds one side's tree again and puts back what was on screen.
	///
	/// `refreshGitStatus` runs on every filesystem event, so this is the path a
	/// build writing files takes dozens of times a minute. A rebuild that let
	/// the tree fold itself up would collapse the pane under somebody halfway
	/// through reviewing it, which is the fault this ordering exists to avoid.
	/// Nothing here takes the side as `inout`. `reloadData` asks the data source
	/// for the rows while it runs, and the data source reads the very property
	/// that would be exclusively held — which Swift traps on, and did.
	private func rebuild(
		_ outline: ChangesOutlineView,
		staged: Bool,
		changes: [GitChange],
		against other: [GitChange]
	) {
		let selected = selectedPaths(in: outline)
		let collapsed = collapsedPaths(in: outline)
		let roots = GitChangeTree.build(changes, against: other)
		let byPath = GitChangeTree.index(roots)
		if staged {
			stagedSide.roots = roots
			stagedSide.byPath = byPath
			stagedSide.collapsed = collapsed
			// Anything that has gone away since stops being remembered, or the
			// set grows for the life of the window.
			stagedSide.opened.formIntersection(byPath.keys)
			stagedSide.untrackedContents = stagedSide.untrackedContents.filter { byPath[$0.key] != nil }
		} else {
			unstagedSide.roots = roots
			unstagedSide.byPath = byPath
			unstagedSide.collapsed = collapsed
			unstagedSide.opened.formIntersection(byPath.keys)
			unstagedSide.untrackedContents = unstagedSide.untrackedContents.filter { byPath[$0.key] != nil }
		}

		// Before `reloadData`, so the rows are under the open directories by the
		// time the view asks for them.
		refill(side(for: outline), in: outline, staged: staged)

		isRestoring = true
		outline.reloadData()
		expand(roots, in: outline, collapsed: collapsed)
		// The auto-expansion above deliberately skips untracked directories —
		// opening one costs a git call, so it is never done on anybody's behalf.
		// These are the ones somebody opened by hand.
		for path in side(for: outline).opened {
			if let node = byPath[path] { outline.expandItem(node) }
		}
		restore(selection: selected, in: outline, staged: staged)
		isRestoring = false
	}

	/// Which folders are folded shut, read off the tree rather than remembered
	/// as it happened.
	///
	/// Asking the view is the only way to get this right. `collapseItem` posts
	/// `didCollapse` for every folder *under* the one that was folded as well —
	/// they have stopped being displayed — and a set built from those
	/// notifications says somebody shut six folders when they shut one, so
	/// opening it again gave back a folder whose insides were all closed.
	///
	/// The visible rows only, and starting from what was already known: a
	/// folder inside a shut one is not a row and nothing here has anything to
	/// say about it, so whatever it was last seen doing it keeps doing.
	private func collapsedPaths(in outline: NSOutlineView) -> Set<String> {
		var found = side(for: outline).collapsed
		for row in 0..<outline.numberOfRows {
			guard let node = outline.item(atRow: row) as? GitChangeNode, node.isFolder else { continue }
			if outline.isItemExpanded(node) { found.remove(node.path) } else { found.insert(node.path) }
		}
		return found
	}

	private func expand(_ nodes: [GitChangeNode], in outline: NSOutlineView, collapsed: Set<String>) {
		// Counted first, because `expandItem` is not free and there is a number
		// of them past which opening everything is not a favour. A work tree
		// holding untracked build output has thousands of folders in it, and
		// expanding every one meant thousands of `expandItem` calls on the main
		// thread on every filesystem event — a pane that took seconds to appear
		// and then could not be scrolled.
		//
		// Past the limit the top level is opened and the rest is left folded,
		// which is also the more useful shape: a tree that arrives entirely open
		// and ten thousand rows long has told you nothing.
		var folders = 0
		count(nodes, into: &folders, upTo: Self.expandEverythingBelow)
		let deep = folders <= Self.expandEverythingBelow
		expand(nodes, in: outline, collapsed: collapsed, recursively: deep)
	}

	/// How many folders a side may have before it stops opening all of them.
	private static let expandEverythingBelow = 500

	private func count(_ nodes: [GitChangeNode], into total: inout Int, upTo limit: Int) {
		for node in nodes where node.isFolder {
			total += 1
			// Stops as soon as the answer cannot change, so counting a tree of
			// fifteen thousand folders costs five hundred.
			guard total <= limit else { return }
			count(node.children, into: &total, upTo: limit)
			guard total <= limit else { return }
		}
	}

	private func expand(
		_ nodes: [GitChangeNode],
		in outline: NSOutlineView,
		collapsed: Set<String>,
		recursively: Bool
	) {
		for node in nodes where node.isFolder && !collapsed.contains(node.path) {
			outline.expandItem(node)
			guard recursively else { continue }
			expand(node.children, in: outline, collapsed: collapsed, recursively: true)
		}
	}

	/// The paths of every selected row, in tree order.
	///
	/// All of them rather than the first: this is the shrinking-selection fault
	/// `TreeSelection` was written for, and a pane that quietly cut a selection
	/// of five down to one every time a file was saved would be the same bug in
	/// a second place.
	private func selectedPaths(in outline: NSOutlineView) -> [String] {
		TreeSelection.paths(rows: Array(outline.selectedRowIndexes)) { row in
			(outline.item(atRow: row) as? GitChangeNode)?.path
		}
	}

	private func restore(selection paths: [String], in outline: NSOutlineView, staged: Bool) {
		let side = self.side(for: outline)
		let rows = TreeSelection.rows(for: paths) { path in
			guard let node = side.byPath[path] else { return -1 }
			return outline.row(forItem: node)
		}
		if !rows.isEmpty {
			outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
			setFallback(nil, staged: staged)
			return
		}

		// Everything that was selected has gone — which is the ordinary outcome
		// of staging, since a folder with nothing left under it stops being a
		// row. Land on the nearest row above where it was rather than nowhere:
		// the next Return should act on something near what was just staged,
		// and a pane that empties its own selection makes the keyboard useless
		// exactly when it is being used.
		guard !paths.isEmpty, let target = side.fallback else { return }
		setFallback(nil, staged: staged)
		var candidate: String? = target
		while let path = candidate {
			if let node = side.byPath[path] {
				let row = outline.row(forItem: node)
				if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
				return
			}
			// The row above may have been staged in the same gesture, so its
			// folder is gone too; the folder above that is still a row.
			let parent = (path as NSString).deletingLastPathComponent
			candidate = parent.isEmpty ? nil : parent
		}
	}

	/// Notes where the selection should land once these rows have been staged
	/// away, before the command that takes them.
	///
	/// `TreeSelection.surviving` answers it: the nearest row above that is not
	/// going. In an outline view "the sibling above, or the parent when there
	/// is no sibling above" is the same movement, which is why one walk up the
	/// visible rows gives both.
	private func rememberWhereTheSelectionGoes(in outline: NSOutlineView, staged: Bool) {
		setFallback(TreeSelection.surviving(above: Set(outline.selectedRowIndexes)) { row in
			(outline.item(atRow: row) as? GitChangeNode)?.path
		}, staged: staged)
	}

	private func setFallback(_ path: String?, staged: Bool) {
		if staged { stagedSide.fallback = path } else { unstagedSide.fallback = path }
	}

	/// The side an outline view belongs to.
	private func side(for outline: NSOutlineView) -> Side {
		outline === stagedTable ? stagedSide : unstagedSide
	}

	/// Notes that an untracked directory is open, so a rebuild puts it back.
	private func remember(opened path: String, staged: Bool) {
		if staged { stagedSide.opened.insert(path) } else { unstagedSide.opened.insert(path) }
	}

	/// Asks git what one untracked directory holds, and puts the answer under
	/// the row.
	///
	/// `-uall` scoped to one path: it costs what that directory holds rather
	/// than what the work tree holds, which is the difference between 0.11 s and
	/// the seven seconds `GitWorkingCopy.status` measured and refused.
	private func fill(_ node: GitChangeNode, in outline: ChangesOutlineView, staged: Bool) {
		let path = node.path
		Task { @MainActor in
			let files = await GitWorkingCopy.untrackedFiles(inDirectory: path, in: root)
			let rows = GitChangeTree.contents(
				ofUntrackedDirectory: path, files: files, staged: staged
			)
			// The tree may have been rebuilt while this was out, in which case
			// the row it was asked about is not the row on screen any more. The
			// answer is kept against the path either way, and the current row —
			// if there still is one — is the one filled.
			if staged {
				stagedSide.untrackedContents[path] = rows
			} else {
				unstagedSide.untrackedContents[path] = rows
			}
			guard let current = self.side(for: outline).byPath[path] else { return }
			current.fill(with: rows)
			if let counts = self.lineCounts[staged] { current.applyLineCounts(counts) }
			outline.reloadItem(current, reloadChildren: true)
			outline.expandItem(current)
		}
	}

	/// Puts back what open untracked directories held, before the view asks.
	///
	/// The tree is rebuilt from scratch on every filesystem event, so every row
	/// under an open directory is a new object with nothing in it. Filling from
	/// what is already known keeps the row open without a git call; the call
	/// goes out afterwards, because the directory may have gained a file since.
	private func refill(_ side: Side, in outline: ChangesOutlineView, staged: Bool) {
		for path in side.opened {
			guard let node = side.byPath[path] else { continue }
			if let known = side.untrackedContents[path] { node.fill(with: known) }
			fill(node, in: outline, staged: staged)
		}
	}


	private func updateCommitButton() {
		let count = status.staged.count
		let hasSubject = !subjectField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty

		// There has to *be* a last commit to amend. In a repository that has
		// been `git init`ed and not committed to yet the box was live, and
		// ticking it and pressing the button put `fatal: You have nothing to
		// amend` on screen — git's answer to a question the page should not
		// have asked.
		let canAmend = pushState?.hasCommits ?? true
		if !canAmend, amendCheckbox.state == .on { amendCheckbox.state = .off }
		amendCheckbox.isEnabled = canAmend
		amendCheckbox.toolTip = canAmend ? nil : "There is no commit to amend yet"

		// Amend can commit nothing new — rewording the last commit is a normal
		// thing to want — so it is the one case where an empty index is allowed.
		let isAmending = amendCheckbox.state == .on
		commitButton.isEnabled = hasSubject && (count > 0 || isAmending)
		commitButton.title = count > 0
			? "Commit \(count) File\(count == 1 ? "" : "s")"
			: (isAmending ? "Amend" : "Commit")

		pushButton.title = pushState?.buttonTitle ?? "Push"
		pushButton.isEnabled = !isBusy && pushState?.canPush == true
		pushButton.toolTip = pushTooltip

		// The accent goes to whichever action the page is actually for: with
		// nothing staged there is nothing to commit, and what is left to do is
		// send what is already committed. Return follows the accent, since the
		// default button is what Return means.
		let primary = CommitPageAction.primary(
			staged: count, isAmending: isAmending, canPush: pushButton.isEnabled
		)
		commitButton.keyEquivalent = primary == .commit ? "\r" : ""
		pushButton.keyEquivalent = primary == .push ? "\r" : ""
	}

	/// Nil only where there is no branch at all — a detached HEAD, or a pane
	/// still waiting for its first read. Every other reason the button is the
	/// way it is comes from the state itself, so that it can be checked without
	/// a window.
	private var pushTooltip: String {
		pushState?.explanation ?? "Push this branch"
	}

	/// Re-reads where the branch stands, and says so on the button.
	private func refreshPushState() {
		Task { @MainActor in
			pushState = await GitPush.state(in: root)
			updateCommitButton()
		}
	}

	@objc private func push() {
		guard let state = pushState, state.canPush else { return }
		let setsUpstream = state.upstream == nil

		isBusy = true
		updateCommitButton()
		Task { @MainActor in
			let result = await GitPush.push(in: root, setUpstream: setsUpstream)
			isBusy = false

			if result.exitCode == 0 {
				// git reports a push on stderr, which is where the branch and
				// the range it sent are named.
				let summary = result.stderr.isEmpty ? result.stdout : result.stderr
				Toast.post(
					"Pushed \(state.branch)",
					detail: summary.trimmingCharacters(in: .whitespacesAndNewlines),
					kind: .information
				)
			} else {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}

			refreshPushState()
			// The history and the branch list both show what has been pushed.
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			onWorkingCopyChanged?()
		}
	}

	// MARK: - Actions

	private func makeChangeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	/// The row the menu was opened on, whichever list it is in.
	private var clickedNode: (node: GitChangeNode, isStaged: Bool)? {
		for table in [unstagedTable, stagedTable] {
			guard let table, table.clickedRow >= 0 else { continue }
			guard let node = table.item(atRow: table.clickedRow) as? GitChangeNode else { continue }
			return (node, table === stagedTable)
		}
		return nil
	}

	@objc private func revealClicked() {
		guard let clicked = clickedNode else { return }
		NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(clicked.node.path)])
	}

	@objc private func copyClickedPath() {
		guard let clicked = clickedNode else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(clicked.node.path, forType: .string)
	}

	/// Offers a pattern for this file and writes it once it is agreed.
	///
	/// Offered rather than imposed: "ignore this" can mean this exact file,
	/// anything with this name, or everything this build step produces, and
	/// guessing wrong writes a line into a tracked file somebody else has to
	/// notice and undo.
	@objc private func ignoreClicked() {
		guard let clicked = clickedNode else { return }
		let path = clicked.node.path
		let isDirectory = (try? root.appendingPathComponent(path)
			.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
		let suggestions = GitIgnore.suggestions(for: path, isDirectory: isDirectory)

		let alert = NSAlert()
		alert.messageText = "Ignore \((path as NSString).lastPathComponent)"
		alert.informativeText = "The pattern is written to .gitignore. Edit it if it is not quite right."
		alert.addButton(withTitle: "Ignore")
		alert.addButton(withTitle: "Cancel")

		let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 54))
		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 360, height: 24))
		popup.addItems(withTitles: suggestions.map { "\($0.pattern)   —   \($0.explanation)" })
		container.addSubview(popup)

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
		field.stringValue = suggestions.first?.pattern ?? path
		field.font = Theme.terminalFont(size: 12)
		container.addSubview(field)

		// Choosing from the list fills the field, which stays editable: the
		// suggestions are a starting point, not the only answers.
		popup.target = self
		popup.action = #selector(ignorePatternChosen)
		ignoreSuggestions = suggestions
		ignoreField = field

		alert.accessoryView = container
		let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let pattern = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !pattern.isEmpty else { return }
			do {
				try GitIgnore.add(pattern, toRepositoryAt: self.root)
				self.refresh()
				NotificationCenter.default.post(name: .abydosRepositoryChanged, object: self.root)
			} catch {
				Toast.post("Could not write .gitignore", detail: error.localizedDescription)
			}
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: apply) } else { apply(alert.runModal()) }
	}

	private var ignoreSuggestions: [GitIgnore.Suggestion] = []
	private weak var ignoreField: NSTextField?

	@objc private func ignorePatternChosen(_ sender: NSPopUpButton) {
		guard ignoreSuggestions.indices.contains(sender.indexOfSelectedItem) else { return }
		ignoreField?.stringValue = ignoreSuggestions[sender.indexOfSelectedItem].pattern
	}

	// MARK: - Stashing

	/// Which paths a stash from the menu would take.
	///
	/// The selection when the click landed inside it, and the clicked row
	/// otherwise — the rule every list follows, and the one that makes
	/// stashing a handful of files a single gesture.
	/// What git is given, and how many changed files that covers — no longer the
	/// same number, now that one of those paths can be a folder.
	private func stashable() -> (paths: [String], files: Int) {
		guard let clicked = clickedNode, let table = clicked.isStaged ? stagedTable : unstagedTable else {
			let everything = status.staged + status.unstaged
			return (GitChangeTree.reduce(everything.map(\.path)), everything.count)
		}
		let selected = selectedPaths(in: table)
		let chosen = GitChangeTree.reduce(
			selected.contains(clicked.node.path) ? selected : [clicked.node.path]
		)
		let side = self.side(for: table)
		return (chosen, chosen.reduce(0) { $0 + (side.byPath[$1]?.count ?? 1) })
	}

	@objc private func stashSelected() {
		let (paths, files) = stashable()
		guard !paths.isEmpty else { return }
		let name = (paths[0] as NSString).lastPathComponent
		promptForStashMessage(
			title: files == 1 ? "Stash “\(name)”" : "Stash \(files) files",
			message: "The changes come out of the working copy and wait in the list, "
				+ "under whatever this says.",
			suggestion: files == 1 ? name : ""
		) { [weak self] message in
			guard let self else { return }
			self.run { await GitStash.push(in: self.root, message: message, paths: paths) }
		}
	}

	@objc private func stashEverything() {
		let count = status.staged.count + status.unstaged.count
		guard count > 0 else { return }
		promptForStashMessage(
			title: "Stash all changes",
			message: "\(count) file\(count == 1 ? "" : "s") come out of the working copy and "
				+ "wait in the list, under whatever this says.",
			suggestion: ""
		) { [weak self] message in
			guard let self else { return }
			self.run { await GitStash.push(in: self.root, message: message) }
		}
	}

	/// Asks what the entry should be called.
	///
	/// A stash nobody named says `WIP on main` and nothing else, which is no
	/// help at all once there are three of them.
	private func promptForStashMessage(
		title: String,
		message: String,
		suggestion: String,
		then act: @escaping (String) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: "Stash")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
		field.placeholderString = "What this is"
		field.stringValue = suggestion
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

	// MARK: - Discarding

	/// What a discard from the menu would take: the paths git is given, the
	/// unstaged changes they cover, and the row it is named after.
	///
	/// Nil for a staged row, which is the decision this entry turned on.
	/// `checkout --` restores the work tree *from the index*, so over a staged
	/// change it would throw away nothing that is staged: the change would
	/// survive, the row would not go away, and the menu would have offered to
	/// destroy something and then not done it. `restore --staged --worktree` was
	/// the other answer and is deliberately not this one — a file staged and
	/// then edited again is a row in each list, and discarding it from the
	/// staged row would also take the later edit, which is only shown in the
	/// other list. Unstage first: that is recoverable, it is one item up the
	/// same menu, and it puts the row where discard already is. The diff view
	/// hides Discard Selected Lines over a staged hunk for the same reason, and
	/// the two should not disagree about what the word means.
	///
	/// The selection when the click landed inside it and the clicked row
	/// otherwise — the rule stash and every other list here follows.
	private func discardable() -> (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)? {
		guard let clicked = clickedNode, !clicked.isStaged else { return nil }
		return discardable(node: clicked.node)
	}

	/// The same question asked about a row by name, so that what the menu would
	/// say can be printed without a right-click. `clickedRow` is set by the
	/// event and by nothing else, which is what makes the split worth having.
	private func discardable(
		node: GitChangeNode
	) -> (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)? {
		guard let table = unstagedTable else { return nil }
		let selected = selectedPaths(in: table)
		let paths = GitChangeTree.reduce(
			selected.contains(node.path) ? selected : [node.path]
		)
		let changes = GitDiscard.changes(status.unstaged, under: paths)
		guard !changes.isEmpty else { return nil }

		// Never over a conflict. `git checkout -- <unmerged path>` refuses with
		// "path is unmerged", so the entry would be one that always fails; and
		// throwing away a half-resolved merge is a different question, with
		// more than one right answer, that this item did not decide.
		guard !changes.contains(where: { $0.kind == .conflicted }) else { return nil }

		// One path may still be a folder standing for forty files, and it is not
		// necessarily the row that was clicked: `reduce` drops a file whose
		// folder is selected too, and the folder is what git is handed.
		let subject: GitDiscard.Subject
		if paths.count == 1, let only = unstagedSide.byPath[paths[0]] {
			subject = only.isFolder ? .folder(only.name) : .file(only.name)
		} else {
			subject = .rows
		}
		return (paths, changes, subject)
	}

	/// How many files a discard covers, and how many of those git has never seen.
	private func discardCounts(
		_ target: (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)
	) -> (files: Int, untracked: Int) {
		(target.changes.count, target.changes.filter { $0.kind == .untracked }.count)
	}

	/// Asks, and only then throws the work away.
	///
	/// Everything else in this menu is recoverable — a stash can be popped,
	/// staging can be unstaged, a `.gitignore` line can be deleted. This is the
	/// one entry with no way back, and for an untracked file there is not even a
	/// git object left afterwards, so it is the one entry that asks.
	@objc private func discardClicked() {
		guard let target = discardable() else { return }
		let counts = discardCounts(target)

		let alert = NSAlert()
		alert.messageText = GitDiscard.question(
			subject: target.subject, files: counts.files, untracked: counts.untracked
		)
		alert.informativeText = GitDiscard.explanation(
			files: counts.files, untracked: counts.untracked
		)
		alert.addButton(withTitle: GitDiscard.buttonTitle(
			files: counts.files, untracked: counts.untracked
		))
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			self?.performDiscard(target)
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	/// What pressing the confirmation's button does.
	private func performDiscard(
		_ target: (paths: [String], changes: [GitChange], subject: GitDiscard.Subject)
	) {
		// Discarding empties rows out of the tree exactly as staging does, so
		// the selection is given somewhere to land first.
		rememberWhereTheSelectionGoes(in: unstagedTable, staged: false)

		// **The most-used destructive verb in the app, now insured.** The
		// question above is `GitDiscard`'s and stays that way — it names the
		// folder and counts what git has never seen, which no general dialog
		// could — so what is borrowed from the safety net is the ref, made
		// before anything is restored, and the toast that says where it went.
		run {
			await DestructiveAsk.insureWorkingCopy(in: self.root)
			return await GitWorkingCopy.discard(paths: target.paths, in: self.root)
		}
	}

	/// Return, or a double-click.
	///
	/// A double-click on a folder opens it, as it does in the project tree, and
	/// only Return or the button stages one. Staging forty files off a stray
	/// second click is a lot to have to undo, and the two trees in this window
	/// answering the same gesture differently would be worse than either.
	private func activate(row: Int, in outline: ChangesOutlineView) {
		if row >= 0, let node = outline.item(atRow: row) as? GitChangeNode, node.isFolder {
			if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
			return
		}
		if outline === stagedTable { unstageSelected() } else { stageSelected() }
	}

	@objc private func stageClicked() {
		guard let clicked = clickedNode else { return }
		run { await GitWorkingCopy.stage(paths: [clicked.node.path], in: self.root) }
	}

	@objc private func unstageClicked() {
		guard let clicked = clickedNode else { return }
		run { await GitWorkingCopy.unstage(paths: [clicked.node.path], in: self.root) }
	}

	/// Stages what is selected — a folder as one path, which is the whole of
	/// what folder staging costs.
	///
	/// `git add` has always taken a directory and `-A` already means a deletion
	/// under it is staged as a deletion, so a folder is one argument instead of
	/// forty in the same argument list. `unstage` is the same shape.
	private func stageSelected() {
		let paths = GitChangeTree.reduce(selectedPaths(in: unstagedTable))
		guard !paths.isEmpty else { return }
		rememberWhereTheSelectionGoes(in: unstagedTable, staged: false)
		run { await GitWorkingCopy.stage(paths: paths, in: self.root) }
	}

	private func unstageSelected() {
		let paths = GitChangeTree.reduce(selectedPaths(in: stagedTable))
		guard !paths.isEmpty else { return }
		rememberWhereTheSelectionGoes(in: stagedTable, staged: true)
		run { await GitWorkingCopy.unstage(paths: paths, in: self.root) }
	}

	/// Clicks into the details field and types, and says what happened.
	///
	/// Through the window's hit testing, because what was wrong was that the
	/// click never reached the text view: a test that typed into it directly
	/// would have passed while the field stayed impossible to use.
	func typeInCommitBodyForTesting(_ text: String) -> String {
		guard let window, let root = window.contentView else { return "no window" }

		let middle = NSPoint(x: bodyView.bounds.midX, y: bodyView.bounds.midY)
		let inWindow = bodyView.convert(middle, to: nil)
		let hit = root.hitTest(inWindow)
		let landed = hit === bodyView || (hit?.isDescendant(of: bodyView) ?? false)

		if landed {
			window.makeFirstResponder(bodyView)
			bodyView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
		}

		let name = hit.map { String(describing: type(of: $0)) } ?? "nothing"
		return "hit=\(landed ? "body" : name) frame=\(NSStringFromRect(bodyView.frame))"
			+ " body=\(bodyView.string.debugDescription)"
	}

	/// Hands what has been typed to whoever opens the page.
	@objc private func openPage() {
		onOpenPage?(subjectField.stringValue)
	}

	/// Fills the two fields from what is staged.
	///
	/// **A draft, and never a commit.** Nothing is staged, nothing is
	/// committed, both fields stay editable, and `Commit` is not disabled while
	/// this is thinking — a slow answer must not become a blocked one.
	@objc private func draftMessage() {
		guard let button = draftButton else { return }
		let root = self.root

		// **Said once, before it happens.** The staged diff leaves this machine
		// when this button is pressed, and that is not something to find out
		// from a release note afterwards. Per project, because agreeing for a
		// scratch repository is not agreeing for a client's.
		guard Settings.shared.maySendDiffs(from: root) else {
			askBeforeSending(from: root)
			return
		}

		button.isEnabled = false
		button.title = "Drafting…"

		Task { @MainActor [weak self] in
			let answer = await ClaudeDraft.draft(in: root)
			button.isEnabled = true
			button.title = "Draft"

			switch answer {
			case let .success(draft):
				// Put in rather than typed over: somebody who started writing
				// while it was thinking has not lost it — the draft goes where
				// the field is empty and is offered where it is not.
				guard let self else { return }
				if self.subjectField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
					self.subjectField.stringValue = draft.summary
				}
				if self.bodyView.string.trimmingCharacters(in: .whitespaces).isEmpty {
					self.bodyView.string = draft.description
				}
				self.updateCommitButton()
			case .failure(.nothingStaged):
				Toast.post("Nothing is staged", detail: "There is no commit to describe yet.")
			case .failure(.notInstalled):
				Toast.post("claude is not on the PATH")
			case let .failure(.said(what)):
				Toast.post("The draft did not come back", detail: what)
			}
		}
	}

	/// Says what drafting will do, once per project, before it does it.
	private func askBeforeSending(from root: URL) {
		let alert = NSAlert()
		alert.messageText = "Send this project's staged diff to Anthropic?"
		alert.informativeText = "Drafting a message runs the claude command with what is staged, "
			+ "and the last twenty commit subjects from this repository, so the summary matches "
			+ "how this project is written.\n\nAsked once for this project."
		alert.addButton(withTitle: "Draft Messages Here")
		alert.addButton(withTitle: "Cancel")

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			Settings.shared.agreeToSendDiffs(from: root)
			self?.draftMessage()
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	@objc private func amendToggled() {
		// Turning amend on offers the previous message, since rewording is the
		// usual reason to amend. It is not forced on a message already typed.
		if amendCheckbox.state == .on, subjectField.stringValue.isEmpty, bodyView.string.isEmpty {
			Task { @MainActor in
				guard let previous = await GitWorkingCopy.lastCommitMessage(in: root) else { return }
				subjectField.stringValue = previous.subject
				bodyView.string = previous.body
				updateCommitButton()
			}
		}
		updateCommitButton()
	}

	@objc private func commit() {
		let subject = subjectField.stringValue
		let body = bodyView.string
		let amend = amendCheckbox.state == .on
		guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else { return }

		isBusy = true
		Task { @MainActor in
			let result = await GitWorkingCopy.commit(subject: subject, body: body, amend: amend, in: root)
			isBusy = false

			guard result.exitCode == 0 else {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
				return
			}

			subjectField.stringValue = ""
			bodyView.string = ""
			amendCheckbox.state = .off
			refresh()
			onWorkingCopyChanged?()
		}
	}

	/// Runs a git command, then refreshes both this view and the navigator.
	private func run(_ operation: @escaping () async -> GitRepository.ProcessResult) {
		isBusy = true
		Task { @MainActor in
			let result = await operation()
			isBusy = false

			if result.exitCode != 0 {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}
			refresh()
			onWorkingCopyChanged?()
		}
	}

	private func presentFailure(_ message: String) {
		Toast.post(
			"git reported a problem",
			detail: message.trimmingCharacters(in: .whitespacesAndNewlines)
		)
	}

	func pushForTesting() { push() }

	/// Selects the first unstaged change, so the screenshot harness can verify
	/// the diff without a click.
	///
	/// The first *file*: row 0 is a folder as soon as anything has changed
	/// below the root, and a folder has no diff to show.
	func selectFirstChangeForTesting() {
		for row in 0..<unstagedTable.numberOfRows {
			guard (unstagedTable.item(atRow: row) as? GitChangeNode)?.change != nil else { continue }
			unstagedTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			return
		}
	}

	/// What the two trees are showing, as lines, for driving the pane from the
	/// command line. Indented by depth, with a folder's tally after its name.
	/// Puts a summary in, as `…` does when it carries one across.
	func carrySummaryForTesting(_ text: String) {
		subjectField.stringValue = text
		updateCommitButton()
	}

	/// Selects a change by path, in whichever list holds it.
	func selectChangeForTesting(_ path: String) {
		for table in [unstagedTable, stagedTable].compactMap({ $0 }) {
			for row in 0..<table.numberOfRows {
				guard let node = table.item(atRow: row) as? GitChangeNode,
				      node.path == path else { continue }
				table.selectRowIndexes([row], byExtendingSelection: false)
				return
			}
		}
	}

	/// What the page is showing on both sides, and in its message.
	func pageReportForTesting() -> String {
		var said = ["layout=\(arrangement == .page ? "page" : "sidebar")"]
		said.append("unstaged=\(status.unstaged.count) staged=\(status.staged.count)")
		said.append("summary=\(subjectField.stringValue)")
		said.append("body=\(bodyView.string.isEmpty ? "empty" : "\(bodyView.string.count) characters")")
		said.append("draft=\(draftButton == nil ? "absent" : "offered")")
		said.append("diff=\(diffView?.reportForTesting ?? "none")")
		return said.joined(separator: "\n")
	}

	/// How much changed, for a driven report — and nothing at all when git gave
	/// no answer, which is the distinction the whole thing turns on.
	private func said(_ lines: GitLineCount?) -> String {
		guard let lines else { return "" }
		return "  +\(lines.added)/-\(lines.removed)"
	}

	func changesTreeForTesting() -> String {
		var lines: [String] = []
		for (title, outline) in [("Unstaged", unstagedTable!), ("Staged", stagedTable!)] {
			lines.append("\(title) (\(outline.numberOfRows) rows)")
			for row in 0..<outline.numberOfRows {
				guard let node = outline.item(atRow: row) as? GitChangeNode else { continue }
				let indent = String(repeating: "  ", count: outline.level(forRow: row) + 1)
				let selected = outline.selectedRowIndexes.contains(row) ? " <-" : ""
				if node.holdsFiles {
					// A folder this pane invented says how much of it is on this
					// side. A wholly untracked directory says what it is instead:
					// git reports it as one entry, so a count would be a 1 that
					// means something different from every other 1 in this tree.
					let tally = node.isFolder
						? (node.isPartial ? "\(node.count) of \(node.total)" : "\(node.count)")
						: (node.isFilled ? "untracked folder" : "untracked folder, not opened")
					let shut = outline.isItemExpanded(node) ? "" : " [shut]"
					lines.append("\(indent)\(node.name)/  \(tally)\(said(node.lines))\(shut)\(selected)")
				} else {
					lines.append("\(indent)\(node.name)\(said(node.lines))\(selected)")
				}
			}
		}
		return lines.joined(separator: "\n")
	}

	/// Selects the rows whose paths these are, in the named list, and stages or
	/// unstages them — the keyboard's gesture, driven from outside.
	func stageForTesting(paths: [String], staged: Bool) {
		let outline = staged ? stagedTable! : unstagedTable!
		let side = self.side(for: outline)
		let rows = TreeSelection.rows(for: paths) { path in
			guard let node = side.byPath[path] else { return -1 }
			return outline.row(forItem: node)
		}
		guard !rows.isEmpty else { return }
		outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		// What git is actually given, which is the claim worth printing: a
		// screenshot of the tree afterwards cannot show whether the folder went
		// as one argument or as forty.
		print("CHANGES \(staged ? "unstage" : "stage"): "
			+ GitChangeTree.reduce(selectedPaths(in: outline)).joined(separator: " "))
		if staged { unstageSelected() } else { stageSelected() }
	}

	/// What the menu would offer over a row and what the confirmation would say,
	/// as lines.
	///
	/// The whole of what this entry had to decide is wording and counting, and a
	/// screenshot of a menu cannot be asked whether the number in it is right. A
	/// staged row answers "not offered", which is the claim that is hardest of
	/// all to see in a picture.
	func discardWordingForTesting(path: String, staged: Bool) -> String {
		let side = staged ? stagedSide : unstagedSide
		guard let node = side.byPath[path] else { return "DISCARD \(path): no such row" }
		guard !staged, let target = discardable(node: node) else {
			return "DISCARD \(path): not offered"
		}
		let (files, untracked) = discardCounts(target)
		let subject = target.subject
		return [
			"DISCARD \(path)",
			"  menu: " + GitDiscard.menuTitle(subject: subject, files: files, untracked: untracked),
			"  asks: " + GitDiscard.question(subject: subject, files: files, untracked: untracked),
			"  says: " + GitDiscard.explanation(files: files, untracked: untracked),
			"  button: " + GitDiscard.buttonTitle(files: files, untracked: untracked),
			"  git: " + target.paths.joined(separator: " "),
		].joined(separator: "\n")
	}

	/// Goes through with a discard over a row, as pressing the confirmation's
	/// button does. The sheet is what is skipped, and nothing else.
	func discardForTesting(path: String) {
		guard let node = unstagedSide.byPath[path], let target = discardable(node: node) else {
			print("DISCARD \(path): not offered")
			return
		}
		print("DISCARD \(path): " + target.paths.joined(separator: " "))
		performDiscard(target)
	}

	/// Folds a folder shut or open, so a refresh can be asked what it did with
	/// it — and so that reopening one by hand can be asked whether what is
	/// inside it came back open too.
	func setExpandedForTesting(path: String, expanded: Bool, staged: Bool) {
		let outline = staged ? stagedTable! : unstagedTable!
		guard let node = side(for: outline).byPath[path] else { return }
		if expanded { outline.expandItem(node) } else { outline.collapseItem(node) }
	}

	func applyThemeChange() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		subjectField.font = Theme.current.uiFont(12)
		bodyView.font = Theme.current.uiFont(12)
		// A zoom changes the indent as well as the type, and through `reload`
		// so that the trees come back open where they were open.
		unstagedTable.indentationPerLevel = Theme.current.scaled(14)
		stagedTable.indentationPerLevel = Theme.current.scaled(14)
		reload()
	}
}

// MARK: - Table

extension ChangesPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			entry.target = self
			return entry
		}

		guard let clicked = clickedNode else {
			// Nothing under the pointer, so the only thing on offer is what
			// applies to the lot.
			if !status.staged.isEmpty || !status.unstaged.isEmpty {
				menu.addItem(item("Stash All Changes…", #selector(stashEverything)))
			}
			return
		}

		// A folder says how much it is about to take. "Stage" over a folder of
		// forty files is the same three words as over one file, and the
		// difference between them is the whole reason folder staging is worth
		// having and the whole reason it is worth being careful with.
		let verb = clicked.isStaged ? "Unstage" : "Stage"
		let title = clicked.node.isFolder
			? "\(verb) “\(clicked.node.name)” (\(clicked.node.count) file"
				+ "\(clicked.node.count == 1 ? "" : "s"))"
			: verb
		menu.addItem(item(title, clicked.isStaged ? #selector(unstageClicked) : #selector(stageClicked)))
		menu.addItem(.separator())
		// Only for something git is not already tracking: ignoring a tracked
		// file does nothing, which is a confusing thing to offer.
		//
		// The condition is `change?.kind`, so it covers an untracked *directory*
		// as well — which is right, and is what somebody who has just made a
		// folder of build output wants. The comment here used to say the
		// opposite: that `-uall` reports the files inside such a directory
		// individually and a folder row is therefore always one this pane
		// invented. That stopped being true when the listing became `-unormal`,
		// and it is doubly untrue now that such a row has children of its own.
		if clicked.node.change?.kind == .untracked {
			menu.addItem(item("Add to .gitignore\u{2026}", #selector(ignoreClicked)))
		}
		menu.addItem(.separator())
		// What is chosen, or what was clicked when nothing is.
		let chosen = stashable().files
		menu.addItem(item(
			chosen > 1 ? "Stash \(chosen) Files…" : "Stash This File…",
			#selector(stashSelected)
		))
		menu.addItem(item("Stash All Changes…", #selector(stashEverything)))
		// Under stash rather than beside stage, and fenced off on its own: the
		// recoverable version of the same wish is the line above it, which is
		// what the confirmation goes on to name.
		if let target = discardable() {
			let counts = discardCounts(target)
			menu.addItem(.separator())
			menu.addItem(item(
				GitDiscard.menuTitle(
					subject: target.subject, files: counts.files, untracked: counts.untracked
				),
				#selector(discardClicked)
			))
		}
		menu.addItem(.separator())
		menu.addItem(item("Reveal in Finder", #selector(revealClicked)))
		menu.addItem(item("Copy Path", #selector(copyClickedPath)))
	}
}

extension ChangesPane: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? GitChangeNode else { return side(for: outlineView).roots.count }
		return node.children.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let node = item as? GitChangeNode else { return side(for: outlineView).roots[index] }
		return node.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		// `holdsFiles`, so an untracked directory gets a triangle. It has one
		// entry as far as git is concerned and a folder's worth of work inside,
		// and until now it was drawn as a file with nothing under it.
		(item as? GitChangeNode)?.holdsFiles ?? false
	}

	/// Fills an untracked directory the first time it is opened.
	///
	/// Nothing is asked for until this happens, which is the whole arrangement:
	/// the listing runs on every filesystem event and cannot afford `-uall`,
	/// while one directory's worth of it is what that directory holds.
	func outlineViewItemWillExpand(_ notification: Notification) {
		guard let node = notification.userInfo?["NSObject"] as? GitChangeNode,
		      let outline = notification.object as? ChangesOutlineView,
		      node.change?.isDirectory == true
		else { return }

		let staged = outline === stagedTable
		remember(opened: node.path, staged: staged)
		guard !node.isFilled else { return }

		// From what is already known, if this row has been opened before in this
		// session — so a rebuild does not blink.
		if let known = side(for: outline).untrackedContents[node.path] {
			node.fill(with: known)
			outline.reloadItem(node, reloadChildren: true)
			return
		}
		fill(node, in: outline, staged: staged)
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		Theme.current.scaled(22)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? GitChangeNode else { return nil }
		guard let change = node.change else {
			return ChangeFolderRowView(node: node, isStaged: outlineView === stagedTable)
		}
		// A change that is a whole directory keeps its badge — it is untracked,
		// and that is what the badge says — and gains a folder beside it, rather
		// than becoming a folder row: a folder row says how much of it is on
		// this side, and this one is a single entry to git.
		return ChangeRowView(node: node, change: change)
	}

	func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor column: NSTableColumn?, item: Any) -> String? {
		(item as? GitChangeNode)?.name
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		guard !isRestoring, let outline = notification.object as? NSOutlineView else { return }
		guard let node = notification.userInfo?["NSObject"] as? GitChangeNode else { return }
		// What is inside it comes back open too, unless it was shut on purpose.
		// The children are new objects since the last rebuild, so the outline
		// view has no memory of them and would otherwise hand back a folder
		// whose insides are shut while everything around it is open.
		isRestoring = true
		expand(node.children, in: outline, collapsed: side(for: outline).collapsed)
		isRestoring = false
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		// Not while the pane is putting its own selection back: a refresh runs
		// on every filesystem event, and reopening the diff each time would
		// throw away wherever somebody had scrolled to in it.
		guard !isRestoring else { return }
		guard let outline = notification.object as? NSOutlineView else { return }
		guard outline.numberOfSelectedRows > 0 else { return }

		// Selecting in one list clears the other, so the diff on screen always
		// belongs to the row that is highlighted.
		let other = outline === stagedTable ? unstagedTable : stagedTable
		if !(other?.selectedRowIndexes.isEmpty ?? true) {
			other?.deselectAll(nil)
		}

		// A folder has no diff of its own — it is not a thing git can be asked
		// about — so selecting one leaves up whatever was being read. Clearing
		// the pane on the way past a folder row would make arrowing down
		// through the tree flash it empty every second row.
		let changes = outline.selectedRowIndexes.sorted().compactMap {
			(outline.item(atRow: $0) as? GitChangeNode)?.change
		}
		guard let change = changes.first else { return }

		// A column hands the diff to the editor area; a page keeps it, which is
		// the whole difference between staging with a trip out to a tab per
		// file and staging in one place.
		guard arrangement == .page, let diffView else {
			onSelectChange?(change)
			return
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			let text = await GitWorkingCopy.diff(
				for: change.path, staged: change.isStaged, in: self.root
			)
			diffView.setDiff(
				text, staged: change.isStaged,
				url: self.root.appendingPathComponent(change.path)
			)
		}
	}
}

extension ChangesPane: NSTextFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		updateCommitButton()
	}
}

/// Tree that reports Return and double-click, for stage/unstage.
///
/// Left and right arrows are left to `NSOutlineView`, which already folds and
/// unfolds with them — the keyboard expansion the navigator has, for nothing.
private final class ChangesOutlineView: NSOutlineView {
	/// The row under the pointer for a click, and -1 from the keyboard, where
	/// the selection is what counts rather than any one row.
	var onActivate: ((Int) -> Void)?

	override func keyDown(with event: NSEvent) {
		// 36 is Return, 76 the numeric keypad's.
		if event.keyCode == 36 || event.keyCode == 76 {
			onActivate?(-1)
			return
		}
		super.keyDown(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?(clickedRow) }
	}
}

/// A section title with a count and its bulk action.
private final class SectionHeaderView: NSView {
	var onAction: (() -> Void)?

	private let title: String
	private var count = 0
	private let button: NSButton

	override var isFlipped: Bool { true }

	init(title: String, actionTitle: String) {
		self.title = title
		button = NSButton(title: actionTitle, target: nil, action: nil)
		super.init(frame: .zero)

		button.bezelStyle = .rounded
		button.controlSize = .small
		button.font = Theme.current.uiFont(11)
		button.target = self
		button.action = #selector(buttonClicked)
		button.translatesAutoresizingMaskIntoConstraints = false
		addSubview(button)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Theme.current.scaled(26)),
			button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(8)),
			button.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func setCount(_ count: Int) {
		self.count = count
		button.isEnabled = count > 0
		needsDisplay = true
	}

	@objc private func buttonClicked() { onAction?() }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		let text = count > 0 ? "\(title) (\(count))" : title
		let label = NSAttributedString(string: text, attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(11), weight: .semibold),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		label.draw(at: NSPoint(x: Theme.current.scaled(8), y: bounds.midY - label.size().height / 2))
	}
}

/// One changed file: git's status letter, then the name.
///
/// No directory after the name any more. The row sits under the folders it is
/// in, so repeating them on every row would be the flat list drawn inside the
/// tree — and it was only ever there because there was nowhere else to say
/// which of three `GitBlame.swift` was which.
/// `+12 −3`, in the colours added and removed already have.
///
/// One place, because two views draw it and they would drift on the dash: a
/// hyphen-minus is narrower than the digits beside it and reads as a hyphen in a
/// filename, so this uses a real minus sign.
private enum LineCountLabel {
	static func make(_ lines: GitLineCount?) -> NSAttributedString? {
		guard let lines else { return nil }
		let font = Theme.current.uiFont(10.5)
		let text = NSMutableAttributedString()
		if lines.added > 0 {
			text.append(NSAttributedString(string: "+\(lines.added)", attributes: [
				.font: font, .foregroundColor: Theme.current.gitAdded,
			]))
		}
		if lines.removed > 0 {
			if text.length > 0 {
				text.append(NSAttributedString(string: " ", attributes: [.font: font]))
			}
			text.append(NSAttributedString(string: "\u{2212}\(lines.removed)", attributes: [
				.font: font, .foregroundColor: Theme.current.gitConflict,
			]))
		}
		// A file git counted as nothing changed — a mode change it did count, a
		// rename with no edit — has a count and it is zero. Saying "0" is
		// clearer than an empty gap where every other row has numbers.
		if text.length == 0 {
			text.append(NSAttributedString(string: "0", attributes: [
				.font: font, .foregroundColor: Theme.current.gitIgnored,
			]))
		}
		return text
	}
}

private final class ChangeRowView: NSView {
	private let node: GitChangeNode
	private let change: GitChange

	override var isFlipped: Bool { true }

	init(node: GitChangeNode, change: GitChange) {
		self.node = node
		self.change = change
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(8)
		let badgeSize = Theme.current.scaled(13)

		// The status letter in its colour, as git prints it — the same letter
		// people already read in `git status`.
		let badge = NSRect(x: x, y: bounds.midY - badgeSize / 2, width: badgeSize, height: badgeSize)
		color(for: change.kind).setFill()
		NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()

		let letter = NSAttributedString(string: letter(for: change.kind), attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(9), weight: .bold),
			.foregroundColor: NSColor.black.withAlphaComponent(0.85),
		])
		letter.draw(at: NSPoint(
			x: badge.midX - letter.size().width / 2,
			y: badge.midY - letter.size().height / 2
		))
		x = badge.maxX + Theme.current.scaled(6)

		// A whole untracked directory keeps the badge — it is untracked, and
		// that is what the badge says — and gains a folder beside it. Both,
		// because neither alone is the truth: `.abydos` and `PI-12` were drawn
		// with the badge and nothing else, and read as files.
		if change.isDirectory,
		   let folder = Theme.symbol(
		   	"folder", size: badgeSize, color: Theme.current.gitUnversioned
		   ) {
			folder.drawFitted(in: NSRect(
				x: x, y: bounds.midY - badgeSize / 2, width: badgeSize, height: badgeSize
			))
			x += badgeSize + Theme.current.scaled(5)
		}

		// **The counts are measured first and the name is given what is left.**
		// A long path and `+1234 −567` do not both fit in a sidebar, and of the
		// two it is the name that can be cut and still be recognised — the
		// counts are three characters and the answer to the question the row is
		// being read for.
		let counts = LineCountLabel.make(node.lines)
		let countsWidth = counts?.size().width ?? 0
		let trailing = RowMetrics.trailingInset
		RowMetrics.draw(
			change.name,
			font: Theme.current.uiFont(12),
			colour: Theme.current.sidebarText,
			at: x, in: bounds,
			limit: bounds.maxX - trailing - (counts == nil ? 0 : countsWidth + Theme.current.scaled(8))
		)
		if let counts {
			counts.draw(at: NSPoint(
				x: bounds.maxX - trailing - countsWidth,
				y: bounds.midY - counts.size().height / 2
			))
		}
	}

	private func letter(for kind: GitChange.Kind) -> String {
		switch kind {
		case .added:      return "A"
		case .modified:   return "M"
		case .deleted:    return "D"
		case .renamed:    return "R"
		case .copied:     return "C"
		case .untracked:  return "U"
		case .conflicted: return "!"
		}
	}

	private func color(for kind: GitChange.Kind) -> NSColor {
		switch kind {
		case .added, .copied:  return Theme.current.gitAdded
		case .modified, .renamed: return Theme.current.gitModified
		case .deleted:         return Theme.current.gitUnversioned
		case .untracked:       return Theme.current.gitUnversioned
		case .conflicted:      return Theme.current.gitUnversioned
		}
	}
}


/// A folder with changes under it: the navigator's folder glyph, the name, and
/// how much of what changed under it is on this side of the index.
///
/// **Half staged is a state git does not have.** A folder is not something it
/// tracks, so nothing in `git status` can be asked whether a directory is
/// wholly in the index; the pane works it out by counting, and then has to say
/// so, because two lists make a folder sitting under "Staged" look finished and
/// somebody who reads it that way commits half of it.
///
/// It says so as a number rather than a new symbol to learn: `6` when
/// everything that changed under the folder is on this side, and `4 of 6` — in
/// the colour a modified file is drawn in, so it reads as something to look at
/// — when it is not. There is no checkbox to give a mixed state to and there
/// was never going to be one: the pane is deliberately two lists rather than
/// one with ticks, which is what lets it show a file that is in both.
private final class ChangeFolderRowView: NSView {
	private let node: GitChangeNode

	override var isFlipped: Bool { true }

	init(node: GitChangeNode, isStaged: Bool) {
		self.node = node
		super.init(frame: .zero)

		// The count is small and the arithmetic behind it is not obvious, so
		// the sentence is on the row rather than in a release note.
		let side = isStaged ? "staged" : "not staged"
		toolTip = node.isPartial
			? "\(node.count) of the \(node.total) changes under \(node.path) are \(side). "
				+ "\(isStaged ? "Unstaging" : "Staging") the folder takes all of them."
			: "\(node.count) change\(node.count == 1 ? "" : "s") under \(node.path), all \(side)."
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(8)
		let glyph = Theme.current.scaled(13)

		// In the slot the status letter occupies on a file row, and fitted
		// rather than stretched to fill it: `folder.fill` is half again as wide
		// as it is tall, and squeezed into a square it stops looking like a
		// folder at all — a rounded box with a notch, next to a tree of real
		// folders in the same window.
		FileIcon.folder()?.drawFitted(
			in: NSRect(x: x, y: bounds.midY - glyph / 2, width: glyph, height: glyph)
		)
		x += glyph + Theme.current.scaled(6)

		let tally = NSAttributedString(
			string: node.isPartial ? "\(node.count) of \(node.total)" : "\(node.count)",
			attributes: [
				.font: Theme.current.uiFont(10.5, weight: node.isPartial ? .semibold : .regular),
				.foregroundColor: node.isPartial ? Theme.current.gitModified : Theme.current.gitIgnored,
			]
		)
		let size = tally.size()
		let right = bounds.maxX - RowMetrics.trailingInset
		tally.draw(at: NSPoint(x: right - size.width, y: bounds.midY - size.height / 2))

		// The sum of what is under it, inside the tally: how many changed, and
		// then how much. Two numbers that answer different questions, which is
		// why the folder keeps both.
		var limit = right - size.width - Theme.current.scaled(6)
		if let counts = LineCountLabel.make(node.lines) {
			let width = counts.size().width
			counts.draw(at: NSPoint(
				x: limit - width, y: bounds.midY - counts.size().height / 2
			))
			limit -= width + Theme.current.scaled(6)
		}

		RowMetrics.draw(
			node.name,
			font: Theme.current.uiFont(12, weight: .medium),
			colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: limit
		)
	}
}

/// A text field with room around its text.
///
/// The commit subject draws its own background, and a field's text otherwise
/// sits hard against the left edge of it.
private final class InsetTextField: NSTextField {
	override class var cellClass: AnyClass? {
		get { InsetTextFieldCell.self }
		set { super.cellClass = newValue }
	}
}

private final class InsetTextFieldCell: NSTextFieldCell {
	/// Inset from the edges, and sitting in the middle of them.
	///
	/// A field taller than its line — which this one is, to be comfortable to
	/// click — draws the text against the top otherwise, and the placeholder
	/// sits above the line everything else is on.
	private func inset(_ rect: NSRect) -> NSRect {
		let room = rect.insetBy(dx: 5, dy: 0)
		let height = ceil(font?.boundingRectForFont.height ?? room.height)
		guard height < room.height else { return room }
		return NSRect(
			x: room.minX,
			y: room.minY + ((room.height - height) / 2).rounded(),
			width: room.width,
			height: height
		)
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: inset(rect))
	}

	override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
		super.edit(withFrame: inset(rect), in: view, editor: editor, delegate: delegate, event: event)
	}

	override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
		super.select(withFrame: inset(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
	}
}

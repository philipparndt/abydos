import AppKit
import AbydosKit

final class BacklogPane: NSView {
	/// The ticks made from this pane's cards, for ⌘Z — see `BacklogPane+Undo`.
	let tickUndo = UndoManager()
	override var undoManager: UndoManager? { tickUndo }
	/// Open a file of the backlog's in the editor: an item, or the instructions
	/// a backlog that has just been made was given.
	var onOpenItem: ((URL) -> Void)?
	/// Pick an item up: a worktree of its own, and an agent in it.
	var onStartAgent: ((BacklogItem) -> Void)?
	/// Open the worktree an item is being worked on in, as a project.
	var onOpenWorktree: ((URL) -> Void)?
	/// Open a shell in that worktree.
	var onOpenWorktreeTerminal: ((URL) -> Void)?
	/// Say something in the corner of the window.
	var onNotify: ((String, String?) -> Void)?

	/// Runs a command in a terminal pane beside this one.
	///
	/// One callback rather than a verb of its own, because the pane has no
	/// business knowing what a terminal is: `BottomPanel` owns them and already
	/// runs commands in them for runs and for agents. What goes through it is
	/// `openspec init`, which asks questions.
	var onRunCommand: ((_ title: String, _ command: String, _ directory: URL) -> Void)?

	/// **Not `let`.** A pane is made once per window and kept; a project is not.
	/// Bound at birth, `reload()` after a project switch re-read the folders of
	/// the project that was left — so the board had to be closed and reopened.
	var backlog: Backlog
	private var openSpec: OpenSpec
	private var watcher: FileSystemWatcher?
	private var openSpecWatcher: FileSystemWatcher?
	/// Runs only while the pane is showing its offer. See
	/// `watchForARecordAppearing`.
	private var appearanceTimer: Timer?

	private var cardsByState: [BacklogState: [BacklogCard]] = [:]
	/// **The archived ones are in here too**, under `.archived`, because that is
	/// a column now. They were a list of their own while it was not, on the
	/// argument that keeps the backlog's `history` off its board — and that
	/// argument is the opposite of this case: the backlog has `completed/` on
	/// the board beside it, OpenSpec has no `completed/` at all, so the archive
	/// *is* where finished work lives. A project that had just archived nine
	/// changes showed five empty columns.
	private var changesByState: [OpenSpecState: [OpenSpecCard]] = [:]

	/// Whether this project has a backlog at all.
	///
	/// Remembered rather than asked each time: the answer decides which view is
	/// installed and whether the header means anything, and both are consulted
	/// on every reload. Re-read by `reload`, which is what runs when somebody
	/// makes one in a terminal.
	var hasBacklog = false
	/// And whether it keeps its work in `openspec/changes` as well, or instead.
	private var hasOpenSpec = false

	enum Mode: Int { case list, board }
	var mode: Mode = .board

	/// Which record of the work is being looked at.
	///
	/// Orthogonal to `Mode`, which is how it is drawn: "which record" and "list
	/// or board" are different questions and neither answers the other. The
	/// control for this appears only where the project has both — a switch to a
	/// thing that is not there is a switch that does nothing.
	///
	/// **Not remembered between launches**, and neither is `Mode` — a pane that
	/// opens on whatever was last looked at is a pane that opens differently for
	/// two people looking at the same project, and the switch is one click. It
	/// opens on the backlog where there is one, because that is where a project
	/// with both keeps the work somebody is picking up.
	enum Source: Int { case backlog, openSpec }
	private var source: Source = .backlog

	private var header: NSStackView!
	private var headerHeight: NSLayoutConstraint!
	private var modeControl: NSSegmentedControl!
	private var sourceControl: NSSegmentedControl!
	private var summaryLabel: NSTextField!
	private var startButton: NSButton!
	private var newButton: NSButton!
	private var contentArea: NSView!
	private var listView: BacklogListView!
	var boardView: BacklogBoardView!
	private var absentView: BacklogAbsentView!

	init(projectRoot: URL) {
		self.backlog = Backlog(projectRoot: projectRoot)
		self.openSpec = OpenSpec(projectRoot: projectRoot)
		self.hasBacklog = backlog.exists
		self.hasOpenSpec = openSpec.exists
		// A project that keeps its work only in `openspec/` opens on it. The
		// switch is for a project with both; with one, there is nothing to
		// choose and the pane shows what is there.
		self.source = hasBacklog ? .backlog : (hasOpenSpec ? .openSpec : .backlog)
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		reload()
		watch()
	}

	/// Shows another project's work, without being closed and reopened.
	///
	/// **Everything `init` worked out is worked out again**, in one function, so
	/// the two cannot come to disagree about what a project means: which folders
	/// there are, whether there is a backlog at all, whether there is an
	/// `openspec/`, and therefore which of the two is being shown and whether
	/// the switch between them is offered.
	///
	/// Re-pointed rather than rebuilt: a pane's place in the tab strip is an
	/// arrangement somebody made, and a rebuild loses it.
	func setProject(_ projectRoot: URL) {
		guard projectRoot.standardizedFileURL != backlog.projectRoot.standardizedFileURL else { return }

		// **Stopped and dropped, not kept.** `watch()` starts a watcher only
		// where there is none, so a pane that kept its old ones would be woken
		// by the project it left and never by the one it is in — right when it
		// is opened and stale a moment later, which is harder to notice than
		// being stale throughout.
		watcher?.stop()
		watcher = nil
		openSpecWatcher?.stop()
		openSpecWatcher = nil

		backlog = Backlog(projectRoot: projectRoot)
		openSpec = OpenSpec(projectRoot: projectRoot)
		hasBacklog = backlog.exists
		hasOpenSpec = openSpec.exists
		// Re-picked, because it can become impossible: arriving at a project
		// with only `openspec/` while the backlog is showing would otherwise
		// leave the pane on a record that is not there.
		source = hasBacklog ? .backlog : (hasOpenSpec ? .openSpec : .backlog)
		cardsByState = [:]
		changesByState = [:]

		showContent()
		reload()
		watch()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		watcher?.stop()
		openSpecWatcher?.stop()
		appearanceTimer?.invalidate()
	}

	override var isFlipped: Bool { true }

	// MARK: - Building

	private func build() {
		modeControl = NSSegmentedControl(
			labels: ["List", "Board"],
			trackingMode: .selectOne,
			target: self,
			action: #selector(modeChanged)
		)
		modeControl.selectedSegment = mode.rawValue
		modeControl.font = Theme.current.uiFont(11)

		sourceControl = NSSegmentedControl(
			labels: ["Backlog", "OpenSpec"],
			trackingMode: .selectOne,
			target: self,
			action: #selector(sourceChanged)
		)
		sourceControl.selectedSegment = source.rawValue
		sourceControl.font = Theme.current.uiFont(11)

		summaryLabel = NSTextField(labelWithString: "")
		summaryLabel.font = Theme.current.uiFont(11)
		summaryLabel.textColor = Theme.current.gitIgnored

		startButton = NSButton(title: "Start the next ready item", target: self, action: #selector(startNext))
		startButton.bezelStyle = .rounded
		startButton.controlSize = .small
		startButton.font = Theme.current.uiFont(11)

		// Beside "start the next ready item" and deliberately not next to a
		// column: a button that belonged to a column would have to be offered
		// on `ready` too, and pressing it there would be the app making a
		// promise that only a person can make. There is one place a new item
		// goes, so there is one button and it does not ask.
		newButton = NSButton(title: "New item\u{2026}", target: self, action: #selector(newItemClicked))
		newButton.bezelStyle = .rounded
		newButton.controlSize = .small
		newButton.font = Theme.current.uiFont(11)

		let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked))
		refresh.bezelStyle = .rounded
		refresh.controlSize = .small
		refresh.font = Theme.current.uiFont(11)

		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

		header = NSStackView(views: [
			sourceControl, modeControl, summaryLabel, spacer, newButton, startButton, refresh,
		])
		header.orientation = .horizontal
		header.spacing = Theme.current.scaled(8)
		header.edgeInsets = NSEdgeInsets(
			top: 0, left: Theme.current.scaled(8), bottom: 0, right: Theme.current.scaled(8)
		)

		listView = BacklogListView()
		listView.pane = self
		boardView = BacklogBoardView()
		boardView.pane = self
		absentView = BacklogAbsentView(projectName: backlog.projectRoot.lastPathComponent)
		absentView.onMake = { [weak self] in self?.confirmMakeBacklog() }
		absentView.onSetUpOpenSpec = { [weak self] in self?.setUpOpenSpec() }

		contentArea = NSView()
		addSubview(header)
		addSubview(contentArea)
		header.translatesAutoresizingMaskIntoConstraints = false
		contentArea.translatesAutoresizingMaskIntoConstraints = false

		headerHeight = header.heightAnchor.constraint(equalToConstant: Theme.current.scaled(34))
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: topAnchor),
			header.leadingAnchor.constraint(equalTo: leadingAnchor),
			header.trailingAnchor.constraint(equalTo: trailingAnchor),
			headerHeight,

			contentArea.topAnchor.constraint(equalTo: header.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		showContent()
	}

	/// Whether there is any record of the work to show at all.
	private var hasSomething: Bool { hasBacklog || hasOpenSpec }

	private func showContent() {
		// Whether anything is being waited for, decided here because this is the
		// one place that knows which view is up.
		watchForARecordAppearing(hasSomething ? false : true)

		// The header is about a record of the work: which one, two presentations
		// of it, how many are in each column, and what to start next. With no
		// record at all there is nothing for it to say, and a row of disabled
		// controls above "there is no backlog here" reads as a broken pane
		// rather than an empty one.
		header.isHidden = !hasSomething
		headerHeight.constant = hasSomething ? Theme.current.scaled(34) : 0

		// Only where the project has both. One record is not a choice, and a
		// switch to something that is not there does nothing twice.
		sourceControl.isHidden = !(hasBacklog && hasOpenSpec)
		sourceControl.selectedSegment = source.rawValue

		// **Neither applies to a change.** Starting one means a worktree and an
		// agent, which `BacklogRun` keys by an item's number and a change has
		// none; filing one is `openspec new change`, which is the CLI's.
		startButton.isHidden = source == .openSpec
		newButton.isHidden = source == .openSpec

		let wanted: NSView = hasSomething ? (mode == .list ? listView : boardView) : absentView
		guard wanted.superview !== contentArea else { return }
		contentArea.subviews.forEach { $0.removeFromSuperview() }
		contentArea.addSubview(wanted)
		wanted.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			wanted.topAnchor.constraint(equalTo: contentArea.topAnchor),
			wanted.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			wanted.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
			wanted.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
		])
	}

	@objc private func modeChanged() {
		mode = Mode(rawValue: modeControl.selectedSegment) ?? .board
		showContent()
		refreshViews()
	}

	@objc private func sourceChanged() {
		source = Source(rawValue: sourceControl.selectedSegment) ?? .backlog
		showContent()
		refreshViews()
	}

	/// Which project this pane is reading, and what it found there.
	///
	/// The two together, because the fault was that they disagreed: the pane
	/// went on naming the project it was made for and showing that project's
	/// items, in a window that had moved on.
	var projectReportForTesting: String {
		let name = backlog.projectRoot.lastPathComponent
		let items = BacklogState.board.reduce(0) { $0 + cards(in: $1).count }
		let changes = changesByState.values.reduce(0) { $0 + $1.count }
		return "project=\(name) backlog=\(hasBacklog) openspec=\(hasOpenSpec)"
			+ " items=\(items) changes=\(changes)"
	}

	/// The geometry every card is drawn with.
	///
	/// Written for a progress bar reported missing from the change cards, which
	/// turned out to be an **older build being looked at** — the bar was in the
	/// current one all along, photographed at 96.8% of the card's width in
	/// `gitModified`. Kept because it is what settled it: two impressions of a
	/// screenshot were not going anywhere, and a line of numbers was.
	///
	/// It prints the scale first, because `scaled(_:)` rounds and a small enough
	/// scale would round a 3-point bar to nothing — which was the best theory
	/// until the numbers came back `bar=3.0` on both machines and killed it.
	var cardGeometryReportForTesting: String {
		let scale = Theme.current.scale
		var lines = [
			"scheme=\(Theme.current.name) scale=\(scale)"
				+ " bar=\(Theme.current.scaled(3)) gap=\(Theme.current.scaled(4))"
				+ " inset=\(Theme.current.scaled(6)) gutter=\(Theme.current.scaled(6))",
		]
		for view in boardView.columnViewsForTesting where !entries(in: view.column).isEmpty {
			lines.append("  [\(view.column.key)] measured at width \(view.cardWidth)")
			lines.append(view.rowHeightReportForTesting)
		}
		for column in columns {
			for entry in entries(in: column) {
				guard case let .change(card) = entry else { continue }
				let progress = card.progress
				let footer = BacklogCardView.footerForTesting(
					marks: card.marks, progress: progress != nil, width: 300
				)
				lines.append(
					"  \(card.name): progress=\(progress?.summary ?? "none")"
						+ " marks=\u{201C}\(card.marks)\u{201D}"
						+ " footer=\(footer)"
						+ " height=\(BacklogCardView.height(for: entry, width: 300))"
				)
			}
		}
		return lines.joined(separator: "\n")
	}

	/// What is on the board, for a driver to print.
	///
	/// The columns of whichever record is showing, in board order, with what is
	/// in each — the archive among them rather than after them, because it is a
	/// column now.
	var boardReportForTesting: String {
		var lines: [String] = []
		lines.append("source: \(source == .openSpec ? "openspec" : "backlog")"
			+ ", backlog: \(hasBacklog), openspec: \(hasOpenSpec)"
			+ ", switch shown: \(!(sourceControl?.isHidden ?? true))")
		lines.append("columns: " + columns.map(\.key).joined(separator: ", "))
		for column in columns {
			let entries = self.entries(in: column)
			guard !entries.isEmpty else { continue }
			let names = entries.map { entry -> String in
				switch entry {
				case let .item(card):   return String(format: "%04d", card.number)
				case let .change(card):
					// What the card itself shows, so a report and a photograph
					// of the same board cannot say different things.
					return ([card.name, card.progress?.summary ?? "", card.marks]
						.filter { !$0.isEmpty }).joined(separator: " ")
				}
			}
			lines.append("\(column.key): \(names.joined(separator: ", "))")
		}
		return lines.joined(separator: "\n")
	}

	/// Whether the first card of a column can be dragged, and what is said when
	/// it cannot.
	///
	/// By the column's name rather than by a `BacklogState`, because the two
	/// records no longer share a vocabulary and a driver asking for "ready" means
	/// whichever record is showing.
	/// Where the header is in the pane, for the panel to measure against its
	/// strip.
	var headerFrameForTesting: NSRect { header.frame }

	func dragReportForTesting(column key: String) -> String {
		guard let column = columns.first(where: { $0.key == key }) else {
			return "no column called \(key) in this record"
		}
		guard let entry = entries(in: column).first else { return "nothing in \(key)" }
		switch entry {
		case let .item(card):
			return "\(String(format: "%04d", card.number)) drags"
		case let .change(card):
			refuseDrag(of: card)
			return "\(card.name) refuses, and says why"
		}
	}

	/// Which record is showing, set from outside for `--backlog openspec`.
	func showOpenSpec(_ wanted: Bool) {
		source = wanted ? .openSpec : .backlog
		sourceControl.selectedSegment = source.rawValue
		showContent()
		refreshViews()
	}

	/// Which presentation is showing, set from outside for `--backlog list`.
	func showList(_ list: Bool) {
		mode = list ? .list : .board
		modeControl.selectedSegment = mode.rawValue
		showContent()
		refreshViews()
	}

	@objc private func refreshClicked() { reload() }

	/// The theme or the zoom changed.
	///
	/// Every card and every row is drawn rather than laid out, so there is
	/// nothing to re-measure by hand: the surfaces take their new colour and
	/// the tables are told to draw again, and the row heights come back through
	/// `heightOfRow` at the new scale.
	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		modeControl.font = Theme.current.uiFont(11)
		summaryLabel.font = Theme.current.uiFont(11)
		summaryLabel.textColor = Theme.current.gitIgnored
		startButton.font = Theme.current.uiFont(11)
		newButton.font = Theme.current.uiFont(11)
		// **The same rule as `showContent`, and that is the whole of the fix.**
		// This read `hasBacklog` while `showContent` read `hasSomething`, so a
		// project kept in `openspec/changes` alone — which this one became on
		// 2026-09-01 — had a header on opening and a zero-height header after
		// the first zoom, theme or presentation change while the pane was up.
		// A stack view of height nought does not clip: its `List` / `Board`
		// control and its `Refresh` drew around the pane's top edge, half over
		// the strip above, which was reported as the pane sitting under the
		// tabs "sometimes". The ordering the design suspected was never the
		// cause; two predicates for one height were.
		headerHeight.constant = hasSomething ? Theme.current.scaled(34) : 0
		header.isHidden = !hasSomething
		listView.applySettings()
		boardView.applySettings()
		absentView.applySettings()
		// The tip is a window of its own, so nothing above reaches it: a theme
		// or zoom change with one open would leave a panel in the old ink over
		// a board in the new.
		TaskTip.shared.applySettings()
		refreshViews()
	}

	// MARK: - Reading

	/// Re-reads the folder, off the main thread.
	///
	/// Off it because everything a card says comes out of the file system: the
	/// title and the checklist are the item's own markdown, the image count and
	/// the delta are two directory reads each. Forty items is a hundred and
	/// sixty syscalls, and on a cold cache that is long enough to be a stutter
	/// in a window somebody is dragging a card across.
	///
	/// Read once into a card and not asked again while drawing, which is the
	/// other half: `draw(_:)` runs on every scroll, and a fraction that costs a
	/// file open is a fraction nobody should be able to put on a card.
	func reload() {
		let backlog = self.backlog
		let openSpec = self.openSpec
		DispatchQueue.global(qos: .userInitiated).async {
			// Asked here rather than on the main thread, and asked every time:
			// `abydos-backlog init` in a terminal is the other way a project
			// gets a backlog, and the watcher cannot report a folder appearing
			// that it was never able to watch. `openspec init` is the same
			// story one directory along.
			let exists = backlog.exists
			let hasOpenSpec = openSpec.exists
			let runs = Dictionary(
				uniqueKeysWithValues: BacklogRuns(projectRoot: backlog.projectRoot).all().map { ($0.number, $0) }
			)
			var found: [BacklogState: [BacklogCard]] = [:]
			for state in BacklogState.board {
				found[state] = backlog.items(in: state).map { BacklogCard($0, run: runs[$0.number]) }
			}

			// On the same walk, and cheaper than the items beside them: a change
			// is one directory listing and one file read, where an item is four
			// reads. Nothing is asked again while drawing, and **nothing is
			// spawned at all** — `openspec list --json` costs 0.60 s of Node
			// start-up, and this runs whenever anything under either directory
			// changes, including an agent ticking a checkbox.
			var changes: [OpenSpecState: [OpenSpecCard]] = [:]
			for card in (openSpec.changes() + openSpec.archived()).map(OpenSpecCard.init) {
				changes[card.state, default: []].append(card)
			}

			DispatchQueue.main.async {
				self.cardsByState = found
				self.changesByState = changes
				if exists != self.hasBacklog || hasOpenSpec != self.hasOpenSpec {
					self.hasBacklog = exists
					self.hasOpenSpec = hasOpenSpec
					if !exists, hasOpenSpec { self.source = .openSpec }
					self.showContent()
					self.watch()
				}
				self.refreshViews()
				// After the walk, with the card as it now stands: a task ticked
				// in a terminal drops its row from a tip that is open, exactly
				// as it drops off the card's fraction. A card that has left In
				// progress — which is what ticking the last task does — takes
				// its tip with it.
				if let identity = TaskTip.shared.identity {
					TaskTip.shared.boardReloaded(entry: self.entry(with: identity))
				}
			}
		}
	}

	/// Looks again, while there is nothing to look at.
	///
	/// **A watcher cannot be started on a directory that does not exist**, and
	/// that is the whole reason this exists. `watch()` starts FSEvents on
	/// `.abydos/backlog` and on `openspec/changes` where those are there; a
	/// project with neither has nothing to attach to, so the pane sat on its
	/// offer until it was closed and opened again — reported after `openspec
	/// init` had finished in the terminal beside it.
	///
	/// Ruled out: watching the project root instead. That is watching a whole
	/// source tree to notice one folder, which is the reason `watch()` gives for
	/// not doing it — and it would not even work, because `openspec init` makes
	/// `openspec/` before `openspec/changes`, so the event for the entry
	/// appearing arrives while there is still nothing to read.
	///
	/// So: two `fileExists` calls every two seconds, and only while the offer is
	/// showing. That is a project with no record of work at all, which is nobody
	/// scrolling anything, and it stops for good the moment there is one — the
	/// reload that finds it puts a board up, and this is asked to stop from
	/// there.
	private func watchForARecordAppearing(_ wanted: Bool) {
		guard wanted else {
			appearanceTimer?.invalidate()
			appearanceTimer = nil
			return
		}
		guard appearanceTimer == nil else { return }
		appearanceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				guard self.backlog.exists || self.openSpec.exists else { return }
				// The cheap question is answered here; the walk that reads what
				// is in them is `reload`'s, off the main thread as ever.
				self.reload()
			}
		}
	}

	/// Watches the backlog for somebody else moving a file.
	///
	/// The point of a dashboard over files is that the files are the truth. An
	/// agent finishing an item in a worktree writes into this folder, and a
	/// board that only updated when it was clicked would be the one place in
	/// the app that disagreed with the disk.
	///
	/// Nothing is watched while there is no backlog: FSEvents wants a path that
	/// exists, and the alternative — watching the project root — is watching
	/// the whole source tree to notice one folder being made. A backlog made in
	/// a terminal is picked up by Refresh, or by showing the pane again, both of
	/// which reload; a backlog made from the button below starts the watcher on
	/// the spot.
	private func watch() {
		if watcher == nil, FileManager.default.fileExists(atPath: backlog.directory.path) {
			let watcher = FileSystemWatcher(root: backlog.directory) { [weak self] _ in
				DispatchQueue.main.async { self?.reload() }
			}
			watcher.start()
			self.watcher = watcher
		}

		// The changes directory is watched the same way and for the same reason:
		// a box ticked in a worktree or in a terminal moves a card, without the
		// pane being clicked.
		if openSpecWatcher == nil, FileManager.default.fileExists(atPath: openSpec.changesDirectory.path) {
			let watcher = FileSystemWatcher(root: openSpec.changesDirectory) { [weak self] _ in
				DispatchQueue.main.async { self?.reload() }
			}
			watcher.start()
			openSpecWatcher = watcher
		}
	}

	private func refreshViews() {
		// The columns of whichever record is showing, which is also what makes
		// this line change when the switch is clicked.
		let counts = columns.map { "\(entries(in: $0).count) \($0.key)" }
		summaryLabel.stringValue = counts.joined(separator: "   ")
		startButton.isEnabled = !cards(in: .ready).isEmpty

		guard hasSomething else { return }
		if mode == .list {
			listView.reload()
		} else {
			boardView.setColumns(columns)
			boardView.reload()
		}
	}

	/// The columns on the board, from whichever record is being looked at.
	///
	/// **Not one set for both.** The backlog's are its folders; OpenSpec's are
	/// its lifecycle, and the archive is the last of them.
	var columns: [BoardColumn] {
		switch source {
		case .backlog:  return BacklogState.board.map(BoardColumn.backlog)
		case .openSpec: return OpenSpecState.board.map(BoardColumn.openSpec)
		}
	}

	func cards(in state: BacklogState) -> [BacklogCard] { cardsByState[state] ?? [] }

	/// What belongs in one column.
	///
	/// A column of the other record's is empty rather than an error: the two
	/// vocabularies share `ready` and `in-progress` and nothing else, and asking
	/// a backlog for its Archived column is a question with a true answer.
	func entries(in column: BoardColumn) -> [BoardEntry] {
		switch (source, column) {
		case let (.backlog, .backlog(state)):   return cards(in: state).map(BoardEntry.item)
		case let (.openSpec, .openSpec(state)): return (changesByState[state] ?? []).map(BoardEntry.change)
		default: return []
		}
	}

	/// The card with this number or this name, wherever it now is.
	///
	/// Over every column rather than the one it was in, because where it is is
	/// the answer being asked for: a change whose last task was just ticked is
	/// in Complete now, and the tip that asked has to be told so rather than
	/// told the card is gone.
	func entry(with identity: BoardEntry.Identity) -> BoardEntry? {
		columns.lazy.flatMap { self.entries(in: $0) }.first { $0.identity == identity }
	}

	func item(number: Int) -> BacklogItem? {
		BacklogState.board.compactMap { cards(in: $0).first { $0.item.number == number }?.item }.first
	}

	// MARK: - Acting

	func open(_ item: BacklogItem) {
		onOpenItem?(item.file)
	}

	/// Opens what a change is: the documents, in the order they are read.
	///
	/// The proposal first, because opening a change means reading why it exists
	/// before reading what it does. Every document in one go rather than a
	/// chooser: there are at most four and a spec apiece, and reading a change
	/// means reading them together.
	func open(_ card: OpenSpecCard) {
		let files = card.change.openableFiles()
		guard !files.isEmpty else {
			onNotify?("Nothing to open in \(card.name)", "The change has no documents in it yet.")
			return
		}
		for file in files { onOpenItem?(file) }
	}

	/// **Says why, rather than the card simply not moving.**
	///
	/// A backlog item drags between columns because moving its file is what
	/// changing its state means. A change's column is read out of its files, so
	/// a drag could only mean ticking or unticking checkboxes in a file nobody
	/// opened — a gesture that rewrote a file would be discovered by accident
	/// and distrusted afterwards.
	///
	/// **A box ticked in the task tip is not that rewrite**, which is why the
	/// sentence now points at it. The tip lists each open task by its words and
	/// the click lands on the one task it ticks, so the person has read what
	/// they are ticking; a drag names a column, and which boxes would get it
	/// there is nobody's decision.
	func refuseDrag(of card: OpenSpecCard) {
		onNotify?(
			"\(card.name) cannot be moved",
			"A change's column comes from its tasks."
				+ " Tick them on the card, or in tasks.md, and the card follows."
		)
	}

	func menu(for card: OpenSpecCard) -> NSMenu {
		let menu = NSMenu()

		let open = NSMenuItem(title: "Open", action: #selector(openChangeFromMenu(_:)), keyEquivalent: "")
		open.target = self
		open.representedObject = card.change.directory
		menu.addItem(open)

		// **The command that picks it up, where it can be picked up.**
		//
		// First, above the archive entry: no change is ever offered both — one
		// is for a change with work left and the other for a change with none —
		// but the order is fixed here rather than left to which branch runs.
		//
		// **No `Executables.locate` on this path, deliberately.** `openspec
		// archive` goes into a terminal and wants the CLI found, which is the
		// entry below. This goes into an assistant: it is a slash command, it
		// lives in `.claude/commands/opsx/apply.md` in the project, and asking
		// whether Node is installed before offering it would be answering a
		// question nobody asked — and answering it wrong for a Dock-launched
		// app, whose `PATH` is four directories.
		//
		// **A change part-way through offers three rather than one**, because
		// there are three things to say about one and only the person looking
		// at it knows which: archive it as it stands, tick the rest off because
		// they were verified by hand, or carry on. `OpenSpec.commands` is where
		// that lives and why.
		for command in OpenSpec.commands(for: card.change, in: card.state) {
			// The name is last and set apart: a separator is what keeps it from
			// reading as a fourth sentence under the three, and it is not quoted
			// because it is not a thing somebody says.
			let isName = command.command == card.change.name
			if isName { menu.addItem(.separator()) }
			let entry = NSMenuItem(
				title: isName ? "Copy name" : "Copy \u{201C}\(command.title)\u{201D}",
				action: isName ? #selector(copyNameFromMenu(_:)) : #selector(copyApplyCommandFromMenu(_:)),
				keyEquivalent: ""
			)
			entry.target = self
			entry.representedObject = command.command
			// The whole of what would be copied, for anybody who wants to see it
			// before they paste it.
			entry.toolTip = command.command
			menu.addItem(entry)
		}

		// A change with every task ticked is one somebody is about to archive,
		// and archiving rewrites the project's specs — so the command is handed
		// over rather than run. Where the tool is not installed, that is what
		// this says instead of quietly not being here.
		if card.state == .complete, !card.change.isArchived {
			let archive = NSMenuItem(
				title: OpenSpec.commandLine() == nil
					? "openspec is not installed\u{2026}"
					: "Copy \u{201C}openspec archive\u{201D}",
				action: #selector(copyArchiveCommandFromMenu(_:)),
				keyEquivalent: ""
			)
			archive.target = self
			archive.representedObject = card.change
			archive.toolTip = OpenSpec.archiveCommand(for: card.change)
			menu.addItem(archive)
		}

		menu.addItem(.separator())
		for file in card.change.openableFiles() {
			let entry = NSMenuItem(
				title: file.lastPathComponent == "spec.md"
					// A spec is named by the capability it is about; every one
					// of them is called `spec.md` and the folder is the name.
					? "spec: \(file.deletingLastPathComponent().lastPathComponent)"
					: file.lastPathComponent,
				action: #selector(openChangeFileFromMenu(_:)),
				keyEquivalent: ""
			)
			entry.target = self
			entry.representedObject = file
			entry.toolTip = file.path
			menu.addItem(entry)
		}
		return menu
	}

	@objc private func openChangeFromMenu(_ sender: NSMenuItem) {
		guard let directory = sender.representedObject as? URL else { return }
		guard let change = OpenSpecChange(at: directory) else { return }
		open(OpenSpecCard(change))
	}

	@objc private func openChangeFileFromMenu(_ sender: NSMenuItem) {
		guard let file = sender.representedObject as? URL else { return }
		onOpenItem?(file)
	}

	/// The string is what the menu item carries, because it was worked out when
	/// the menu was built and re-deriving it here would be a second place for
	/// the rule about which states offer it to live.
	@objc private func copyApplyCommandFromMenu(_ sender: NSMenuItem) {
		guard let command = sender.representedObject as? String else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(command, forType: .string)
		onNotify?("Copied", command)
	}

	@objc private func copyNameFromMenu(_ sender: NSMenuItem) {
		guard let name = sender.representedObject as? String else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(name, forType: .string)
		onNotify?("Copied the change\u{2019}s name", name)
	}

	@objc private func copyArchiveCommandFromMenu(_ sender: NSMenuItem) {
		guard let change = sender.representedObject as? OpenSpecChange else { return }
		guard OpenSpec.commandLine() != nil else {
			onNotify?("openspec is not installed", OpenSpec.installHint)
			return
		}
		let command = OpenSpec.archiveCommand(for: change)
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(command, forType: .string)
		onNotify?("Copied", command)
	}

	/// Moves an item, and says so if it will not go.
	func move(_ item: BacklogItem, to state: BacklogState) {
		do {
			_ = try backlog.move(item, to: state)
		} catch {
			onNotify?("Could not move \(String(format: "%04d", item.number))", "\(error)")
		}
		reload()
	}

	@objc private func startNext() {
		guard let card = cards(in: .ready).first else { return }
		onStartAgent?(card.item)
	}

	func start(_ item: BacklogItem) {
		onStartAgent?(item)
	}

	// MARK: Making one, and putting something in it

	/// Makes this project a backlog, through the same code `init` runs.
	///
	/// `BacklogSetup.run` and not a second implementation: the whole design of
	/// this backlog is that the app, the command line and an agent read and move
	/// the same files, and two implementations of `init` would be two answers to
	/// what a backlog is — one of which would drift.
	///
	/// The assistants are the ones installed, which is the answer
	/// `abydos-backlog init` gives itself when it is not talking to a terminal.
	/// They are named in the sheet rather than chosen there: a chooser is a
	/// second copy of a question the command line already asks well, and `init`
	/// run again adds a tool without disturbing anything.
	private func confirmMakeBacklog() {
		let installed = BacklogAssistant.allCases.filter(\.isInstalled)

		let alert = NSAlert()
		alert.messageText = "Make a backlog in \(backlog.projectRoot.lastPathComponent)?"
		alert.informativeText = """
		This writes .abydos/backlog — the state folders, the workflow, project.md \
		and the spec — and points \(installed.isEmpty
			? "no assistant at it, because none is installed"
			: installed.map(\.name).joined(separator: ", ")) at it.

		Nothing that is already there is overwritten, and `abydos-backlog init` \
		run later adds another assistant.
		"""
		alert.addButton(withTitle: "Make a Backlog")
		alert.addButton(withTitle: "Cancel")

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			self?.makeBacklog(for: installed)
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	/// The whole of what the button does, once it has been agreed to.
	///
	/// Separated from the sheet for the same reason `createItem` is: a pane in
	/// the app target cannot be reached by the suite, so the way to show that
	/// this writes a real backlog is to drive it and then look at the folder.
	func makeBacklog(for assistants: [BacklogAssistant]) {
		do {
			try BacklogSetup.run(projectRoot: backlog.projectRoot, assistants: assistants)
		} catch {
			onNotify?("Could not make a backlog", "\(error)")
			return
		}
		hasBacklog = true
		showContent()
		watch()
		reload()
		// The instructions, because that is what `init` says to read next on
		// the command line, and the pane should not be the version of the same
		// command that says nothing.
		onOpenItem?(backlog.instructionsFile)
	}

	/// Sets a project up for OpenSpec, by running `openspec init` where its
	/// questions can be answered.
	///
	/// **In a terminal, and no sheet in front of it**, which is where this stops
	/// looking like the offer beside it. `Make a Backlog…` asks first because
	/// `BacklogSetup.run` then writes without asking anything — the sheet is the
	/// only chance to say what will happen, and to name the assistants it will
	/// point at the folder. `openspec init` asks better questions than a sheet
	/// could, in the terminal it is asked in, and answering them for somebody
	/// writes slash commands and skills into their repository.
	///
	/// Nothing is claimed afterwards. The directory appears when the person has
	/// finished answering, which is long after this returns, and the pane
	/// re-reads both records every time it is shown — so coming back to this tab
	/// is what shows the board, without the pane being reopened.
	func setUpOpenSpec() {
		guard OpenSpec.commandLine() != nil else {
			onNotify?("OpenSpec is not installed", OpenSpec.installHint)
			return
		}
		onRunCommand?("OpenSpec", OpenSpec.initCommand(), backlog.projectRoot)
	}

	/// What the empty state is offering, for a driver to print.
	///
	/// Nil where the pane has something to show, which is the other half of the
	/// answer: a report saying "there is no offer" is how a driver tells a
	/// project that was set up from one that was not.
	var offerReportForTesting: String? {
		hasSomething ? nil : absentView.offerReportForTesting
	}

	/// Files a new item, in `open/`.
	///
	/// **Never `ready/`**, and there is deliberately no control here that could
	/// send it there. `ready` is the promise that the deciding is done, and it
	/// is the one human gate in this workflow: a button that dropped items into
	/// it would turn that gate into a formality, and the tool would be making a
	/// promise on somebody's behalf. `Backlog.create` defaults to `.open` and
	/// this call does not pass a state, which is the same thing
	/// `abydos-backlog new` does. Moving it on afterwards is a drag, a menu
	/// item or an `mv`, and all three are somebody deciding.
	@objc private func newItemClicked() {
		let alert = NSAlert()
		alert.messageText = "New backlog item"
		alert.informativeText = "It gets the next number and lands in open/, "
			+ "which is where something written down but not yet agreed belongs."
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		field.placeholderString = "what is wrong, or what is missing"
		field.font = Theme.current.uiFont(12)
		alert.accessoryView = field

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			self?.createItem(titled: field.stringValue)
		}
		// The field, not the button, so the title can just be typed.
		alert.window.initialFirstResponder = field
		if let window { alert.beginSheetModal(for: window, completionHandler: act) } else { act(alert.runModal()) }
	}

	/// The whole of what the button does, once it has a title.
	///
	/// Separated from the sheet so that it can be driven: this pane is in the
	/// app target and the suite cannot reach it, so the only way to show where
	/// a new item lands is to run the real thing and look. See
	/// `newItemForTesting`, which calls this and nothing else.
	@discardableResult
	func createItem(titled typed: String) -> BacklogItem? {
		let title = typed.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !title.isEmpty else { return nil }
		do {
			// No `state:`. The default is `.open`, which is where
			// `abydos-backlog new` puts one too.
			let item = try backlog.create(title: title)
			reload()
			// Opened rather than merely made: what lands on disk is a template
			// with four headings and nothing under them, and an item nobody
			// fills in is a title in a folder.
			open(item)
			return item
		} catch {
			onNotify?("Could not make an item", "\(error)")
			return nil
		}
	}
}

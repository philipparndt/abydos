import AppKit
import AbydosKit

/// One item, with everything a row or a card says about it already worked out.
///
/// Exists so that drawing costs nothing. An item's title, its checklist, its
/// screenshots and its spec delta are four reads of the file system, and a
/// board redraws on every scroll — so they are done once, on the thread that
/// re-reads the folder, and what reaches `draw(_:)` is five fields.
struct BacklogCard {
	/// Which copy of the item the checklist, the pictures and the delta were
	/// read from.
	///
	/// **State from the project, progress from the worktree**, and the two are
	/// not the same question. Where an item stands is the project's answer —
	/// `in-progress/` until the branch lands, because work finished on a branch
	/// nobody has merged is not done here. How far along it is is the branch's
	/// answer, because the ticking happens there: measured while 0454 was being
	/// worked, the project's copy said 0 of 6 and the branch's said 3 of 6, and
	/// the card showed the first — the fraction the item had at the moment it was
	/// picked up, held there until the merge, which is when nobody needs to watch
	/// it any more.
	enum Source: Equatable {
		/// The project's own copy, which for an item nobody has picked up is the
		/// only copy there is.
		case project
		/// The checkout the work is happening in. Which one is `run`, which the
		/// card carries anyway in order to draw the branch and to offer the
		/// three things its menu does with it.
		case worktree
	}

	let item: BacklogItem
	let progress: BacklogItem.Progress?
	let estimate: BacklogItem.Estimate?
	let images: Int
	let hasSpecDelta: Bool
	let run: BacklogRun?
	let source: Source

	init(_ item: BacklogItem, run: BacklogRun?) {
		self.item = item
		self.run = run

		// The second read, and it is here rather than anywhere nearer the
		// drawing on purpose: this initialiser runs on the walk that re-reads
		// the folder, off the main thread, and `draw(_:)` runs on every scroll.
		// A fraction that costs a file open is a fraction nobody should be able
		// to put on a card.
		//
		// Nothing extra is paid by the cards that have no run, which is nearly
		// all of them: `itemInWorktree` is `nil` without touching the disk
		// unless a checkout was recorded for this number and is still there.
		let onBranch = run?.itemInWorktree
		let copy = onBranch ?? item
		self.progress = copy.progress()
		self.estimate = copy.estimate()
		self.images = copy.images().count
		self.hasSpecDelta = !copy.specDeltas().isEmpty
		self.source = onBranch == nil ? .project : .worktree
	}

	var number: Int { item.number }
	var title: String { item.title }
	var state: BacklogState { item.state }
}

/// One OpenSpec change, with everything a card says about it worked out.
///
/// The same shape as `BacklogCard` and for the same reason — the reads happen on
/// the walk, not while drawing — and cheaper: a change is one directory listing
/// and one file, where an item is four reads.
///
/// **It has no number**, and that is the difference that matters rather than a
/// missing field. A backlog item is `0540` for ever and its state is the folder
/// it sits in; a change is a name, and its state is worked out from what is in
/// its directory. That is why a card for one cannot be dragged: dragging an item
/// between columns *is* the `mv` that changes its state, and dragging a change
/// could only mean ticking somebody's checkboxes.
struct OpenSpecCard: Equatable {
	let change: OpenSpecChange
	let progress: BacklogItem.Progress?
	/// **In OpenSpec's own vocabulary**, not the backlog's folders. Answering in
	/// `BacklogState` is what put a change into a column it has no notion of.
	let state: OpenSpecState

	init(_ change: OpenSpecChange) {
		self.change = change
		// The second read, here rather than nearer the drawing, exactly as
		// `BacklogCard` does it: this runs on the walk that re-reads the folder,
		// and `draw(_:)` runs on every scroll.
		let progress = change.progress()
		self.progress = progress
		self.state = change.state(progress: progress)
	}

	var name: String { change.name }

	/// The line under the name, and **in one place** because three of them read
	/// it: the card, the row in the list, and the measurement that decides how
	/// tall the card is. Those had the same expression written out three times,
	/// and the one that can disagree is the height — a card measured without a
	/// line it is then drawn with comes out short.
	///
	/// What is written and what is wanted next, while there are no tasks to
	/// count. **And where the schema is one this cannot read, always**: that
	/// change has a fraction like any other — `- [x]` means the same thing in
	/// any schema — so keying on "no progress" alone would count its tasks and
	/// never say that the column it is in was not derived.
	var marks: String {
		guard progress == nil || !change.isSchemaUnderstood else { return "" }
		return change.artifactSummary
	}
}

/// One thing on the board, whichever record it came from.
enum BoardEntry {
	case item(BacklogCard)
	case change(OpenSpecCard)

	var column: BoardColumn {
		switch self {
		case let .item(card):   return .backlog(card.state)
		case let .change(card): return .openSpec(card.state)
		}
	}
}

/// One column of the board, from whichever record is showing.
///
/// **Each source brings its own**, which is the whole of this: the backlog's are
/// its folders and OpenSpec's are its lifecycle, and one set of columns over two
/// records is what sorted a change into `waiting` — a folder OpenSpec has no
/// notion of and nothing can ever be in.
///
/// The two are not merged into a common five. They have `ready` and
/// `in-progress` in common and nothing else, and a column called Open that means
/// "written down, not agreed" for one record and "the proposal is not finished"
/// for the other is a heading that has to be read twice.
enum BoardColumn: Hashable {
	case backlog(BacklogState)
	case openSpec(OpenSpecState)

	var title: String {
		switch self {
		case let .backlog(state):  return state.title
		case let .openSpec(state): return state.title
		}
	}

	/// The one line that says what belongs here, for a column with nothing in it.
	var summary: String {
		switch self {
		case let .backlog(state):  return state.summary
		case let .openSpec(state): return state.summary
		}
	}

	/// What a driver prints and what the summary line counts by. The backlog's
	/// is its folder name, because that is a real path somebody can `cd` to;
	/// OpenSpec's is the state's own name, because there is no folder.
	var key: String {
		switch self {
		case let .backlog(state):  return state.directoryName
		case let .openSpec(state): return state.rawValue
		}
	}

	/// The backlog state this column is, where it is one.
	///
	/// **Nil for every OpenSpec column, and that is what makes a drop into one
	/// impossible to write.** A drag moves a file between folders; there are no
	/// folders on that side, so the type says so rather than a guard hoping to.
	var backlogState: BacklogState? {
		switch self {
		case let .backlog(state): return state
		case .openSpec:           return nil
		}
	}
}

/// The backlog, as a list and as a board.
///
/// Two presentations of one directory, and the toggle between them is a view
/// change rather than a mode: the list is for reading — everything in one
/// column, in number order, which is how you find the thing you half remember
/// — and the board is for moving, because dragging a card from `ready` to
/// `in-progress` is the same `mv` and is the one gesture a list cannot make.
///
/// Neither holds any state of its own. What is on screen is what is in
/// `.abydos/backlog`, re-read when it changes, so somebody moving a file in a
/// terminal sees the board move too.
final class BacklogPane: NSView {
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
	private var backlog: Backlog
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
	private var hasBacklog = false
	/// And whether it keeps its work in `openspec/changes` as well, or instead.
	private var hasOpenSpec = false

	private enum Mode: Int { case list, board }
	private var mode: Mode = .board

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
	private enum Source: Int { case backlog, openSpec }
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
	private var boardView: BacklogBoardView!
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
		headerHeight.constant = hasBacklog ? Theme.current.scaled(34) : 0
		listView.applySettings()
		boardView.applySettings()
		absentView.applySettings()
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
	func refuseDrag(of card: OpenSpecCard) {
		onNotify?(
			"\(card.name) cannot be moved",
			"A change's column comes from its tasks. Tick them in tasks.md and the card follows."
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
			let entry = NSMenuItem(
				title: "Copy \u{201C}\(command.title)\u{201D}",
				action: #selector(copyApplyCommandFromMenu(_:)),
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

	// MARK: - Driving it

	/// What a card's menu offers, as one line.
	///
	/// A menu is the part of this pane a screenshot cannot photograph without a
	/// click, and the pane is in the app target where the suite cannot reach it.
	/// So it is checked by opening the real window on a real backlog and asking
	/// the real menu what it says.
	/// Whether the board has anything on it yet, for a driver that must not ask
	/// before it does.
	///
	/// **The report used to be printed on a three-second timer**, and against
	/// the OpenSpec record three seconds is not enough: every change's fraction
	/// comes from the CLI, which is found through the login shell and started
	/// once per change. The board was empty, and what the driver printed was
	/// "no change called … on the board" — which reads exactly like a card that
	/// is missing.
	var hasCardsForTesting: Bool {
		columns.contains { !entries(in: $0).isEmpty }
	}

	func menuTitlesForTesting(number: Int) -> String {
		let found = BacklogState.board
			.compactMap { cards(in: $0).first { $0.number == number } }
			.first
		guard let card = found else { return "no item \(number) on the board" }
		return menu(for: card).items
			.map { $0.isSeparatorItem ? "\u{2014}" : $0.title }
			.joined(separator: " | ")
	}

	/// The same, for a change — which has a name where an item has a number.
	///
	/// Its own verb rather than a cleverness over the other one: the two records
	/// are addressed differently, and a driver that had to know `0540` means an
	/// item and `find-bands-follow-soft-wrap` means a change would be one that
	/// guesses.
	func menuTitlesForTesting(change name: String) -> String {
		let found = columns
			.flatMap { entries(in: $0) }
			.compactMap { entry -> OpenSpecCard? in
				guard case let .change(card) = entry, card.name == name else { return nil }
				return card
			}
			.first
		guard let card = found else { return "no change called \(name) on the board" }
		return "[\(card.state.rawValue)] " + menu(for: card).items
			.map { $0.isSeparatorItem ? "\u{2014}" : $0.title }
			.joined(separator: " | ")
	}

	/// Files an item the way the button does, and says where it landed.
	func newItemForTesting(titled title: String) -> String {
		guard hasBacklog else { return "no backlog" }
		guard let item = createItem(titled: title) else { return "nothing made" }
		let where_ = (item.folder ?? item.file).path
		let prefix = backlog.projectRoot.path + "/"
		return "\(String(format: "%04d", item.number))  \(item.state.directoryName)/  "
			+ (where_.hasPrefix(prefix) ? String(where_.dropFirst(prefix.count)) : where_)
	}

	/// Whether the pane is offering to make a backlog rather than showing one.
	var isOfferingToMakeOneForTesting: Bool { !hasBacklog }

	/// Makes a backlog the way the button does, and says what is there now.
	func makeBacklogForTesting() -> String {
		guard !hasBacklog else { return "there is one already" }
		makeBacklog(for: BacklogAssistant.allCases.filter(\.isInstalled))
		return hasBacklog ? "made, and the pane is showing it" : "not made"
	}

	/// The menu a card and a row both use.
	///
	/// Given the card rather than the item, because where an item is being
	/// worked on is not in the item: it is a run recorded beside the project,
	/// which the card already carries in order to draw the branch on it.
	func menu(for card: BacklogCard) -> NSMenu {
		let item = card.item
		let menu = NSMenu()

		let open = NSMenuItem(title: "Open", action: #selector(openFromMenu(_:)), keyEquivalent: "")
		open.target = self
		open.representedObject = item
		menu.addItem(open)

		if item.state == .ready {
			let start = NSMenuItem(
				title: "Start in a Worktree\u{2026}",
				action: #selector(startFromMenu(_:)),
				keyEquivalent: ""
			)
			start.target = self
			start.representedObject = item
			menu.addItem(start)
		}

		// Offered only where there is something to open.
		//
		// `isPresent` is the question, not whether a run was ever recorded: the
		// run file is this machine's note that a checkout was made, and a
		// checkout somebody removed with `rm -rf` leaves the note behind. An
		// entry that opened a window on a directory that is not there would
		// fail after the click rather than before it — and the card already
		// uses the same test to decide whether to draw the branch name, so the
		// menu and the card agree by construction.
		if let run = card.run, run.isPresent {
			let asProject = NSMenuItem(
				title: "Open Worktree as a Project",
				action: #selector(openWorktreeFromMenu(_:)),
				keyEquivalent: ""
			)
			asProject.target = self
			asProject.representedObject = run.worktree
			asProject.toolTip = run.worktreePath
			menu.addItem(asProject)

			let terminal = NSMenuItem(
				title: "Open Terminal in Worktree",
				action: #selector(openWorktreeTerminalFromMenu(_:)),
				keyEquivalent: ""
			)
			terminal.target = self
			terminal.representedObject = run.worktree
			terminal.toolTip = run.worktreePath
			menu.addItem(terminal)

			// The third thing to do with a worktree, and the one for when
			// somebody wants the files rather than the project or a shell —
			// a diff to drag somewhere, a screenshot the agent left in the
			// item's folder. Under the same guard as the other two, so all
			// three appear and disappear together with the checkout.
			let inFinder = NSMenuItem(
				title: "Reveal Worktree in Finder",
				action: #selector(revealWorktreeFromMenu(_:)),
				keyEquivalent: ""
			)
			inFinder.target = self
			inFinder.representedObject = run.worktree
			inFinder.toolTip = run.worktreePath
			menu.addItem(inFinder)
		}

		menu.addItem(.separator())
		for state in BacklogState.board where state != item.state {
			let move = NSMenuItem(
				title: "Move to \(state.title)",
				action: #selector(moveFromMenu(_:)),
				keyEquivalent: ""
			)
			move.target = self
			move.representedObject = MoveRequest(item: item, state: state)
			menu.addItem(move)
		}

		menu.addItem(.separator())
		let reveal = NSMenuItem(
			title: item.carriesFiles ? "Show Folder in Finder" : "Show in Finder",
			action: #selector(revealFromMenu(_:)),
			keyEquivalent: ""
		)
		reveal.target = self
		reveal.representedObject = item
		menu.addItem(reveal)
		return menu
	}

	/// A pair, because a menu item carries one object.
	private final class MoveRequest: NSObject {
		let item: BacklogItem
		let state: BacklogState
		init(item: BacklogItem, state: BacklogState) {
			self.item = item
			self.state = state
		}
	}

	@objc private func openFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		open(item)
	}

	@objc private func startFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		start(item)
	}

	@objc private func openWorktreeFromMenu(_ sender: NSMenuItem) {
		guard let worktree = sender.representedObject as? URL else { return }
		onOpenWorktree?(worktree)
	}

	@objc private func openWorktreeTerminalFromMenu(_ sender: NSMenuItem) {
		guard let worktree = sender.representedObject as? URL else { return }
		onOpenWorktreeTerminal?(worktree)
	}

	/// The worktree itself, selected in its parent — not opened as a window on
	/// its contents. A checkout of this project has forty entries at its root
	/// and none of them is what somebody asked to see; the directory is.
	@objc private func revealWorktreeFromMenu(_ sender: NSMenuItem) {
		guard let worktree = sender.representedObject as? URL else { return }
		NSWorkspace.shared.activateFileViewerSelecting([worktree])
	}

	@objc private func moveFromMenu(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? MoveRequest else { return }
		move(request.item, to: request.state)
	}

	@objc private func revealFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		NSWorkspace.shared.activateFileViewerSelecting([item.folder ?? item.file])
	}
}

// MARK: - The list

/// Everything, in one column, grouped by state.
final class BacklogListView: NSView {
	weak var pane: BacklogPane?

	private enum Row {
		case header(BoardColumn, Int)
		case entry(BoardEntry)
	}

	private var rows: [Row] = []
	private var tableView: NSTableView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.doubleAction = #selector(rowDoubleClicked)
		tableView = table

		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
		scrollView.autohidesScrollers = true

		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	func reload() {
		guard let pane else { return }
		rows = []
		// The columns of whichever record is showing, the archive among them —
		// it used to be a section of its own down here because it was not a
		// column anywhere.
		for column in pane.columns {
			let entries = pane.entries(in: column)
			guard !entries.isEmpty else { continue }
			rows.append(.header(column, entries.count))
			rows += entries.map(Row.entry)
		}
		tableView.reloadData()
	}

	@objc private func rowDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < rows.count else { return }
		guard case let .entry(entry) = rows[tableView.clickedRow] else { return }
		switch entry {
		case let .item(card):   pane?.open(card.item)
		case let .change(card): pane?.open(card)
		}
	}

	func applySettings() {
		tableView.backgroundColor = Theme.current.editorBackground
		tableView.enclosingScrollView?.backgroundColor = Theme.current.editorBackground
	}
}

extension BacklogListView: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		switch rows[row] {
		case .header: return Theme.current.scaled(26)
		case .entry: return Theme.current.scaled(22)
		}
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		switch rows[row] {
		case let .header(column, count):
			return BacklogSectionHeader(column: column, count: count)
		case let .entry(entry):
			let view = BacklogRowCell()
			switch entry {
			case let .item(card):
				view.configure(card)
				view.menu = pane?.menu(for: card)
			case let .change(card):
				view.configure(card)
				view.menu = pane?.menu(for: card)
			}
			return view
		}
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		switch rows[row] {
		case .header: return false
		case .entry: return true
		}
	}
}

/// `Ready — 3`, over the items in it.
private final class BacklogSectionHeader: NSView {
	private let column: BoardColumn
	private let count: Int

	init(column: BoardColumn, count: Int) {
		self.column = column
		self.count = count
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let font = Theme.current.uiFont(11, weight: .semibold)
		let text = "\(column.title.uppercased())  \(count)"
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: BacklogPalette.colour(for: column),
		]
		let size = (text as NSString).size(withAttributes: attributes)
		(text as NSString).draw(
			at: NSPoint(x: Theme.current.scaled(10), y: (bounds.height - size.height) / 2),
			withAttributes: attributes
		)

		Theme.current.separator.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
	}
}

/// One item on one line.
private final class BacklogRowCell: NSView {
	private var number = ""
	private var title = ""
	private var marks = ""
	private var tint = NSColor.gray

	func configure(_ card: BacklogCard) {
		number = String(format: "%04d", card.number)
		title = card.title
		tint = BacklogPalette.colour(for: card.state)
		marks = BacklogPalette.marks(for: card)
		needsDisplay = true
	}

	/// A change has no number, so the column that holds one holds its fraction
	/// instead — and, before there is one to hold, what has been written.
	func configure(_ card: OpenSpecCard) {
		number = card.progress?.summary ?? ""
		title = card.name
		tint = BacklogPalette.colour(for: card.state)
		marks = card.marks
		needsDisplay = true
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// Every piece is drawn into a rect of the same height at the same y,
		// with the same line-fragment origin. Mixing `draw(at:)` — which places
		// a baseline — with `draw(with:options:)` — which places the top of a
		// line box — put the number and the title on two different lines that
		// were four points apart, which reads as a misprint.
		let font = Theme.current.uiFont(12)
		let line = ceil(font.ascender - font.descender + font.leading)
		let y = ((bounds.height - line) / 2).rounded()
		let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]

		let truncating = NSMutableParagraphStyle()
		truncating.lineBreakMode = .byTruncatingTail

		var x = Theme.current.scaled(10)
		let numberAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(12, weight: .medium),
			.foregroundColor: tint,
		]
		let numberWidth = ceil((number as NSString).size(withAttributes: numberAttributes).width)
		(number as NSString).draw(
			with: NSRect(x: x, y: y, width: numberWidth, height: line),
			options: options,
			attributes: numberAttributes
		)
		x += numberWidth + Theme.current.scaled(10)

		var markWidth: CGFloat = 0
		if !marks.isEmpty {
			let markAttributes: [NSAttributedString.Key: Any] = [
				.font: Theme.current.uiFont(11),
				.foregroundColor: Theme.current.gitIgnored,
				.paragraphStyle: truncating,
			]
			// Measured, then capped at half the room. The paragraph style
			// truncates, but only within whatever width it is given, and the
			// natural width of a branch name is the item's whole title with a
			// prefix on it — so the marks took the row, `available` went
			// negative, and the guard below dropped the title altogether. The
			// title is what somebody is scanning for; it keeps half.
			let room = max(0, bounds.width - x - Theme.current.scaled(8))
			let natural = ceil((marks as NSString).size(withAttributes: markAttributes).width)
				+ Theme.current.scaled(12)
			markWidth = min(natural, room / 2)
			(marks as NSString).draw(
				with: NSRect(x: bounds.width - markWidth, y: y, width: markWidth, height: line),
				options: options,
				attributes: markAttributes
			)
		}

		let available = bounds.width - x - markWidth - Theme.current.scaled(8)
		guard available > 0 else { return }
		(title as NSString).draw(
			with: NSRect(x: x, y: y, width: available, height: line),
			options: options,
			attributes: [
				.font: font,
				.foregroundColor: Theme.current.editorText,
				.paragraphStyle: truncating,
			]
		)
	}
}

// MARK: - The board

/// One column per state, and cards that can be dragged between them.
final class BacklogBoardView: NSView {
	weak var pane: BacklogPane? {
		didSet { columns.forEach { $0.pane = pane } }
	}

	private var columns: [BacklogColumnView] = []
	private var stack: NSStackView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// The columns this board is over, which the source decides.
	///
	/// Rebuilt rather than relabelled: the two records do not have the same
	/// number of columns in general, and a column view carries the drop
	/// behaviour of the state it was made for. Nothing happens where the set is
	/// already the right one, which is every reload but the two that follow a
	/// click on the switch.
	func setColumns(_ wanted: [BoardColumn]) {
		guard wanted != columns.map(\.column) else { return }
		for column in columns {
			stack.removeArrangedSubview(column)
			column.removeFromSuperview()
		}
		columns = wanted.map { BacklogColumnView(column: $0) }
		for column in columns {
			column.pane = pane
			stack.addArrangedSubview(column)
		}
	}

	private func build() {
		columns = BacklogState.board.map { BacklogColumnView(column: .backlog($0)) }
		stack = NSStackView(views: columns)
		stack.orientation = .horizontal
		stack.distribution = .fillEqually
		stack.spacing = 1
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

		let scrollView = NSScrollView()
		scrollView.documentView = stack
		scrollView.hasHorizontalScroller = true
		scrollView.hasVerticalScroller = false
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.separator
		scrollView.scrollerStyle = .overlay

		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		stack.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

			stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
			stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			// Never narrower than five legible columns. Below that the board
			// scrolls sideways, because a kanban board squeezed to sixty points
			// a column is five lists of numbers.
			stack.widthAnchor.constraint(
				greaterThanOrEqualToConstant: Theme.current.scaled(
					CGFloat(max(BacklogState.board.count, OpenSpecState.board.count)) * 190
				)
			),
		])

		// The pane's width, and only as strongly as that.
		//
		// Required, this fights the minimum above in a narrow window and one of
		// them has to lose. Absent, the stack takes the width its columns ask
		// for — and a column asks for whatever its widest label would like,
		// which made a board that fitted easily scroll sideways anyway.
		let fit = stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
		fit.priority = .defaultHigh
		fit.isActive = true
	}

	/// The columns themselves, for a report about what each is drawing.
	var columnViewsForTesting: [BacklogColumnView] { columns }

	func reload() {
		columns.forEach { $0.reload() }
	}

	func applySettings() {
		columns.forEach { $0.applySettings() }
	}
}

/// One state, with its cards.
final class BacklogColumnView: NSView {
	weak var pane: BacklogPane?
	let column: BoardColumn

	/// What a dragged card carries: the number, which is the only durable name
	/// an item has.
	static let dragType = NSPasteboard.PasteboardType("dev.abydos.backlog.item")

	private var entries: [BoardEntry] = []
	private var tableView: NSTableView!
	private var headerLabel: NSTextField!
	private var emptyLabel: NSTextField!
	/// The width the cached row heights were measured at. See `widthChanged`.
	private var measuredWidth: CGFloat = 0

	override func layout() {
		super.layout()
		widthChanged(to: cardWidth)
	}

	/// The table says when its own width changed, because `layout()` is too
	/// early to ask.
	///
	/// `layout()` runs on this view, and the table lays its column out during
	/// its *own* pass afterwards — so `cardWidth` read from here is still the
	/// previous width, `widthChanged` sees no difference, and the cached row
	/// heights are never thrown away. That is invisible while a board is only
	/// ever built once, and obvious the moment somebody drags the panel to the
	/// side and back: every card keeps the height it had at the old width while
	/// its text is drawn at the new one, so titles truncate, marks land on them
	/// and the text runs outside the card altogether.
	///
	/// A frame notification fires when the width has actually changed, which is
	/// the thing being waited for. It cannot loop: `measuredWidth` tracks only
	/// the width, and re-measuring rows changes the table's *height*.
	private func watchTableWidth() {
		tableView.postsFrameChangedNotifications = true
		NotificationCenter.default.addObserver(
			forName: NSView.frameDidChangeNotification, object: tableView, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.widthChanged(to: self?.cardWidth ?? 0) }
		}
	}

	init(column: BoardColumn) {
		self.column = column
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		headerLabel = NSTextField(labelWithString: column.title.uppercased())
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: column)

		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.rowSizeStyle = .custom
		table.intercellSpacing = NSSize(width: 0, height: Theme.current.scaled(6))
		table.gridStyleMask = []
		table.selectionHighlightStyle = .none
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("card")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.doubleAction = #selector(cardDoubleClicked)
		table.registerForDraggedTypes([Self.dragType])
		table.setDraggingSourceOperationMask(.move, forLocal: true)
		tableView = table
		watchTableWidth()

		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
		// Five columns, five scrollers, four of which are usually over nothing.
		// A board is mostly whitespace by design and a permanent grey bar down
		// the side of every column is most of what the eye lands on.
		scrollView.autohidesScrollers = true
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.contentInsets = NSEdgeInsets(
			top: Theme.current.scaled(6), left: 0, bottom: Theme.current.scaled(6), right: 0
		)

		// What belongs in this column, for a column with nothing in it.
		//
		// An empty board is the state somebody is in on their first day with
		// one, and five unlabelled columns explain nothing. `ready` is the one
		// that matters: it is the folder an agent picks from, and the reason
		// nothing is in it is that moving something there is a decision.
		emptyLabel = NSTextField(wrappingLabelWithString: column.summary)
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		emptyLabel.alignment = .left
		emptyLabel.isSelectable = false
		// Neither label gets to decide how wide a column is. Five columns each
		// asking for the width of a sentence is a board that scrolls sideways
		// in a window twice as wide as it needs to be.
		emptyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		emptyLabel.preferredMaxLayoutWidth = Theme.current.scaled(160)
		headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		addSubview(headerLabel)
		addSubview(scrollView)
		addSubview(emptyLabel)
		headerLabel.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.current.scaled(8)),
			headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(10)),
			headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

			scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: Theme.current.scaled(6)),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

			emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Theme.current.scaled(8)),
			emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(18)),
			emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(18)),
		])
	}

	/// What the table is using for each row and what the card view was given,
	/// against what the card wants — the three that a cached height lets drift
	/// apart.
	///
	/// `uses` is `rect(ofRow:)`, which includes the intercell spacing, so it is
	/// a row taller than the card by design and compared with that allowed for.
	/// `draws` is the card view's own frame, and it is the one that matters:
	/// everything at the foot of a card — the bar above all — is measured from
	/// its bottom edge, and a view left taller than its row has that edge, and
	/// the bar on it, below the row's clip. A card whose bottom corners are
	/// square in a photograph is this, and nothing else.
	var rowHeightReportForTesting: String {
		var lines: [String] = []
		let spacing = tableView.intercellSpacing.height
		for (index, entry) in entries.enumerated() {
			let wanted = BacklogCardView.height(for: entry, width: cardWidth)
			let used = tableView.rect(ofRow: index).height - spacing
			let drawn = tableView.view(atColumn: 0, row: index, makeIfNecessary: false)?.frame.height
			let name: String
			switch entry {
			case let .item(card): name = String(format: "%04d", card.number)
			case let .change(card): name = card.name
			}
			let clipped = drawn.map { $0 - used > 0.5 } ?? false
			lines.append("    \(name): wants=\(wanted) uses=\(used)"
				+ " draws=\(drawn.map(String.init(describing:)) ?? "not made")"
				+ (abs(wanted - used) > 0.5 ? "  ← DIFFERS" : "")
				+ (clipped ? "  ← CLIPPED" : ""))
		}
		return lines.joined(separator: "\n")
	}

	func reload() {
		entries = pane?.entries(in: column) ?? []
		headerLabel.stringValue = entries.isEmpty
			? column.title.uppercased()
			: "\(column.title.uppercased())  \(entries.count)"
		emptyLabel.isHidden = !entries.isEmpty
		tableView.reloadData()
	}

	@objc private func cardDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < entries.count else { return }
		switch entries[tableView.clickedRow] {
		case let .item(card):   pane?.open(card.item)
		case let .change(card): pane?.open(card)
		}
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: column)
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		tableView.backgroundColor = Theme.current.editorBackground
		tableView.intercellSpacing = NSSize(width: 0, height: Theme.current.scaled(6))
		tableView.enclosingScrollView?.backgroundColor = Theme.current.editorBackground
	}
}

extension BacklogColumnView: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		BacklogCardView.height(for: entries[row], width: cardWidth)
	}

	/// The width a card will actually be drawn at.
	///
	/// **Not `tableView.bounds.width`**, which is what this asked before and is
	/// the width of the table *before* it has been laid out inside its scroll
	/// view. Measured: 375 against the 343 the cell then got, a difference of a
	/// scroller — enough that a title fitting one line while being measured
	/// needed two while being drawn, and the card came out a line short. The
	/// column's width is what the row is given.
	var cardWidth: CGFloat {
		let column = tableView.tableColumns.first?.width ?? 0
		return column > 0 ? column : tableView.bounds.width
	}

	/// Measured heights are only true for the width they were measured at.
	///
	/// A card's height is how many lines its title wraps to, and AppKit asks
	/// once and then caches: the first answer comes back at whatever width the
	/// table had while the board was still being laid out, and nothing asks
	/// again when the column settles. A title that wraps to two lines at the
	/// real width and one at the width it was measured at gets a card a line
	/// short — which is how a branch name came to be drawn across the second
	/// line of a title.
	///
	/// So the heights are thrown away when the width actually changes, and only
	/// then: `layout()` runs for every scroll and every reload, and telling a
	/// table its rows have all changed height is not free.
	///
	/// **The rows are reloaded rather than re-measured**, which is the
	/// difference between a card view built for the new height and one left at
	/// the old. `noteHeightOfRows` is the cheaper call and it was the one made
	/// here: it tells the table what each row is worth now, and a card view
	/// already on screen could be left at the height it was made with. A view
	/// taller than its row is clipped at the row's foot, and everything a card
	/// draws from its bottom edge — the progress bar, the rounded corners — is
	/// under that clip. Photographed, that is a card with square bottom corners
	/// and no bar, which is what was reported: the bar arrived when Refresh was
	/// pressed, and Refresh is a `reloadData`.
	func widthChanged(to width: CGFloat) {
		guard abs(width - measuredWidth) > 0.5 else { return }
		// Remembered even with nothing to re-measure, which is the state a
		// column is in for the moment between being built and the walk coming
		// back off its own thread. Left at zero through that moment, the first
		// layout after the cards arrive reports a width change that has already
		// been accounted for — the cards were measured at that width — and
		// reloads the rows in the middle of a layout pass for nothing.
		measuredWidth = width
		guard !entries.isEmpty else { return }
		tableView.reloadData()
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let view = BacklogCardView()
		switch entries[row] {
		case let .item(card):
			view.configure(card)
			view.menu = pane?.menu(for: card)
		case let .change(card):
			view.configure(card)
			view.menu = pane?.menu(for: card)
		}
		return view
	}

	// MARK: Dragging

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
		switch entries[row] {
		case let .item(card):
			let entry = NSPasteboardItem()
			entry.setString(String(card.number), forType: BacklogColumnView.dragType)
			return entry
		case let .change(card):
			// **Refused here, where the drag begins, so that it can be said.**
			// Returning nil is what stops it; the sentence is what stops it
			// being a card that mysteriously will not move. A change's column is
			// read out of its files, so the only thing a drag could mean is
			// ticking somebody's checkboxes.
			pane?.refuseDrag(of: card)
			return nil
		}
	}

	func tableView(
		_ tableView: NSTableView,
		validateDrop info: any NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation operation: NSTableView.DropOperation
	) -> NSDragOperation {
		// Onto the column, never between two cards. The order within a state is
		// the number order and nothing else — an item's place in the list is
		// not something a drag should be able to change, because two people
		// dragging would then disagree and neither would know.
		tableView.setDropRow(-1, dropOperation: .on)
		// A column that is not a folder cannot be dropped into, and the type is
		// what says so: an OpenSpec column has no `BacklogState` to move a file
		// to. The drag itself is refused where it starts, with a sentence.
		guard let target = column.backlogState else { return [] }
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else {
			return []
		}
		return item.state == target ? [] : .move
	}

	func tableView(
		_ tableView: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation: NSTableView.DropOperation
	) -> Bool {
		guard let target = column.backlogState else { return false }
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else { return false }
		guard item.state != target else { return false }
		pane?.move(item, to: target)
		return true
	}

	private func draggedNumber(from info: any NSDraggingInfo) -> Int? {
		guard let entries = info.draggingPasteboard.pasteboardItems else { return nil }
		return entries.compactMap { $0.string(forType: BacklogColumnView.dragType) }.compactMap(Int.init).first
	}
}

/// One item as a card: the number, the title, and what it carries.
private final class BacklogCardView: NSView {
	/// **A resized card redraws.**
	///
	/// A row's height is measured once and cached, and `widthChanged` re-measures
	/// them all when the column's width changes — at which point AppKit resizes
	/// the cell view that is already on screen. A resized `NSView` keeps the
	/// drawing it already has unless it is told otherwise, and everything on a
	/// card is positioned from one edge or the other: the stripe, the number and
	/// the title hang off the top and survive, and the progress bar is measured
	/// from `card.maxY` and does not. It stayed at the old bottom — outside the
	/// new bounds, and therefore gone.
	///
	/// That is why the bar was missing on some cards and not others: the ones
	/// whose height had changed since they were drawn. Scrolling the column or
	/// resizing the window brought them back, because either forces the redraw
	/// this asks for in the first place.
	override func setFrameSize(_ newSize: NSSize) {
		let changed = newSize.height != frame.height || newSize.width != frame.width
		super.setFrameSize(newSize)
		if changed { needsDisplay = true }
	}

	private var number = ""
	private var title = ""
	private var marks = ""
	private var tint = NSColor.gray
	private var progress: BacklogItem.Progress?

	/// The breathing room inside a card, and the gap between a card and the
	/// column's edge.
	///
	/// Both came down — 8 to 6, and 10 to 6 — because a board is read by
	/// scanning it, and padding is space that pushes the next card off the
	/// screen. At the old numbers a column of five cards showed four, and the
	/// gutter was doing the work the gap between rows already does.
	private static let inset: CGFloat = 6
	private static let gutter: CGFloat = 6
	private static let barHeight: CGFloat = 3

	/// Whether every card says what it drew, for `--draw-report`.
	static var reportsDrawing = false

	func configure(_ card: BacklogCard) {
		number = String(format: "%04d", card.number)
		title = card.title
		tint = BacklogPalette.colour(for: card.state)
		marks = BacklogPalette.marks(for: card)
		progress = card.progress
		needsDisplay = true
	}

	/// A change: its name where an item has its title, its fraction where an
	/// item has its number, and — before there is a fraction — what has been
	/// written of it, which is what "how far along" means at that stage.
	func configure(_ card: OpenSpecCard) {
		number = card.progress?.summary ?? ""
		title = card.name
		tint = BacklogPalette.colour(for: card.state)
		marks = card.marks
		progress = card.progress
		needsDisplay = true
	}

	/// Tall enough for the title to fit, which is what makes the board readable
	/// — a card that truncates at forty characters is a card whose title is
	/// "the settings page will not stay the width" for four different items.
	static func height(for entry: BoardEntry, width: CGFloat) -> CGFloat {
		switch entry {
		case let .item(card):
			return height(
				title: card.title,
				marks: BacklogPalette.marks(for: card),
				hasProgress: card.progress != nil,
				width: width
			)
		case let .change(card):
			return height(
				title: card.name,
				marks: card.marks,
				hasProgress: card.progress != nil,
				width: width
			)
		}
	}

	private static func height(
		title: String, marks: String, hasProgress: Bool, width: CGFloat
	) -> CGFloat {
		let inset = Theme.current.scaled(Self.inset)
		let gutter = Theme.current.scaled(Self.gutter)
		let available = max(width - gutter * 2 - inset * 2, 40)
		let font = Theme.current.uiFont(12)
		let bounds = (title as NSString).boundingRect(
			with: NSSize(width: available, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: font]
		)
		return ceil(bounds.height) + numberLine + Theme.current.scaled(2)
			+ footer(
				markLines: markLines(marks, width: available),
				progress: hasProgress
			)
			+ inset * 2 + Theme.current.scaled(6)
	}

	/// How many lines the marks want, and never more than three.
	///
	/// One line was enough while the longest thing on it was a branch name at
	/// the end, which is the one mark that can be lost. It stopped being enough
	/// when the fraction gained "in the worktree" and an estimate arrived behind
	/// it: photographed on a board at the width a five-column panel gives, `1/12
	/// in the worktree` filled the line and the estimate came out as `a…`, which
	/// is worse than not drawing it — a card that shows the first letter of a
	/// fact is a card somebody has to open anyway. At two lines the estimate got
	/// as far as `as of 07:…`, which loses the half of it that matters.
	///
	/// Three, and no more. A card only takes the lines its marks need, so this
	/// is a line taller for the four or five items being worked on and unchanged
	/// for the rest of the board; and past three the tail is a branch name that
	/// is the item's number and title with a prefix on it, which the card is
	/// already showing and the menu can open.
	static func markLines(_ marks: String, width: CGFloat) -> Int {
		guard !marks.isEmpty else { return 0 }
		let bounds = (marks as NSString).boundingRect(
			with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: Theme.current.uiFont(11)]
		)
		return min(3, max(1, Int((ceil(bounds.height) / markLine).rounded())))
	}

	/// The two measures the height and the drawing must agree on.
	///
	/// They did not. The height reserved two of `boundingRectForFont.height`
	/// while the drawing advanced by `size(withAttributes:).height`, which is
	/// the larger of the two — so a card came out about a line short, and a
	/// two-line title had nowhere for its second line. That is the whole of the
	/// fault: not the width, not the wrap, a font metric asked two ways.
	///
	/// Both sides read these now, so the only way they can disagree again is if
	/// somebody changes one of these and not the drawing that uses it.
	static var numberLine: CGFloat {
		("0000" as NSString)
			.size(withAttributes: [.font: Theme.current.uiFont(11, weight: .medium)]).height
	}

	/// One line of the marks, measured the way the marks are drawn.
	///
	/// `boundingRect` and not `size(withAttributes:)`, which is what this used
	/// while the marks were a single line placed by its baseline. They are wrapped
	/// into a rect now, and a wrapped line advances by the line-fragment height —
	/// so counting lines with one metric and reserving them with the other is the
	/// same fault this comment was written about the first time, one font metric
	/// asked two ways.
	static var markLine: CGFloat {
		("0/0" as NSString).boundingRect(
			with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: Theme.current.uiFont(11)]
		).height
	}

	/// What sits below the title: the marks, and the bar when there is one.
	/// The footer a card reserves, for the geometry report.
	static func footerForTesting(marks: String, progress: Bool, width: CGFloat) -> CGFloat {
		footer(markLines: markLines(marks, width: width), progress: progress)
	}

	static func footer(markLines: Int, progress: Bool) -> CGFloat {
		var footer = markLine * CGFloat(markLines)
		if progress { footer += Theme.current.scaled(Self.barHeight) + Theme.current.scaled(4) }
		return footer
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let gutter = Theme.current.scaled(Self.gutter)
		let inset = Theme.current.scaled(Self.inset)
		// **The height this card's own contents want, where that is less than
		// the frame it was given**, and the frame otherwise.
		//
		// The two agree whenever the table asked for a height at the width the
		// card is drawn at, which is every ordinary pass — so this changes
		// nothing that is already right. It is here for the pass that is not:
		// a card left in a frame taller than its row hangs over the row's foot,
		// and the foot is where the bar and the bottom corners are. Drawn to
		// the height the contents want, they stay above the clip and the card
		// is whole, with the spare points left blank where they can be seen and
		// fixed rather than swallowing the bar where they cannot.
		let wanted = Self.height(
			title: title, marks: marks, hasProgress: progress != nil, width: bounds.width
		)
		let card = NSRect(
			x: gutter, y: 0,
			width: max(bounds.width - gutter * 2, 0),
			height: min(bounds.height, wanted)
		)

		let path = NSBezierPath(roundedRect: card, xRadius: Theme.current.scaled(5), yRadius: Theme.current.scaled(5))
		Theme.current.selectionInactive.setFill()
		path.fill()

		// Nothing a card draws leaves the card.
		//
		// A guard rather than a feature, and it earns its place: a row's height
		// is measured once and cached, so any moment where the cached height is
		// wrong for the width being drawn at puts more text on a card than fits.
		// Without a clip that text simply carries on — over the card's rounded
		// edge, over the gap, and over the card below, which is what dragging
		// the panel to the side and back used to look like.
		//
		// With it, the same fault truncates instead: still wrong, still worth
		// fixing, and contained to the card it belongs to rather than making
		// three of its neighbours unreadable as well.
		NSGraphicsContext.saveGraphicsState()
		defer { NSGraphicsContext.restoreGraphicsState() }
		path.setClip()
		// A stripe in the state's colour down the left edge, which is what
		// makes a card recognisable at the speed somebody scans a board: the
		// title is what it is about, the stripe is where it stands.
		let stripe = NSBezierPath(
			roundedRect: NSRect(x: card.minX, y: card.minY, width: Theme.current.scaled(3), height: card.height),
			xRadius: Theme.current.scaled(1.5),
			yRadius: Theme.current.scaled(1.5)
		)
		tint.setFill()
		stripe.fill()

		var y = card.minY + inset
		let x = card.minX + inset
		let width = card.width - inset * 2

		let numberAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11, weight: .medium),
			.foregroundColor: tint,
		]
		(number as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: numberAttributes)
		y += (number as NSString).size(withAttributes: numberAttributes).height + Theme.current.scaled(2)

		let titleAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.editorText,
		]
		// The title stops above the footer rather than running to the bottom of
		// the card.
		//
		// It used to be given every point left, and the marks were then drawn on
		// top of whatever the title had put in that space — a branch name across
		// the second line of a two-line title, both unreadable. That only shows
		// when the height is a line short, which `height(for:width:)` can be
		// when it measured at a different width from the one the card is drawn
		// at, so this is the half that makes the overlap impossible rather than
		// unlikely. `lines` is the same measure the height reserves two of.
		// The same count the height reserved, from the same string at the same
		// width, so that the two can only disagree when the cached height is
		// stale for the width being drawn at — which the clip above contains.
		let markLines = Self.markLines(marks, width: width)
		let footer = Self.footer(markLines: markLines, progress: progress != nil)
		let titleRect = NSRect(
			x: x, y: y, width: width, height: max(0, card.maxY - y - inset - footer)
		)
		(title as NSString).draw(
			with: titleRect,
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: titleAttributes
		)

		var bottom = card.maxY - inset

		// What this card actually drew, when asked. A progress bar that is
		// missing until something forces a second pass is a question about the
		// pass that drew it first, and nothing outside `draw` can answer it.
		if BacklogCardView.reportsDrawing {
			let has = progress != nil
			print("DRAW \(title.prefix(38)): bounds=\(bounds.size)"
				+ " card=\(card.size) progress=\(has)"
				+ " footer=\(Self.footer(markLines: Self.markLines(marks, width: width), progress: has))")
			fflush(stdout)
		}

		// The checklist, as a bar along the foot of the card.
		//
		// A bar as well as the `3/7` in the line above it, because they answer
		// the question at two speeds: the fraction is what you read when you
		// have stopped at a card, and the bar is what you see when you have
		// not. A board is mostly looked at rather than read.
		if let progress {
			let height = Theme.current.scaled(Self.barHeight)
			bottom -= height + Theme.current.scaled(4)
			let track = NSRect(x: x, y: bottom + Theme.current.scaled(4), width: width, height: height)
			let radius = height / 2
			Theme.current.separator.setFill()
			NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

			// Nothing drawn at zero rather than a sliver: a bar with a dot at
			// the left end reads as "started", and an item with five unticked
			// steps has not been.
			if progress.done > 0 {
				var filled = track
				filled.size.width = max(track.width * CGFloat(progress.fraction), height)
				tint.setFill()
				NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
			}
		}

		guard !marks.isEmpty else { return }
		// Into a rect, and truncating, because this is the one line on a card
		// whose length is not ours: a branch name is
		// `backlog/0435-the-plantuml-server-test-fails-only-when-the-suite-is-busy`,
		// which is the item's whole title with a prefix on it. Drawn `at:` a
		// point it had no width to obey and ran out past the card's rounded
		// edge and over its neighbour.
		//
		// Wrapping, with the last visible line truncated: what a mark says first
		// is what identifies it — `3/7`, `2 images`, `spec`, and a branch that
		// begins with the number — so the end is the part that can go, and the
		// order the marks are built in is the order they are lost in.
		//
		// **`byWordWrapping`, not `byTruncatingTail`.** A truncating line break
		// mode means "this is one line", so with it the second line of the rect
		// was reserved, paid for in card height, and left empty while the first
		// line ended in `a…`. Photographed before it was understood, which is
		// the only way this pane's faults have ever been found.
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byWordWrapping
		let markAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		]
		let markHeight = Self.markLine * CGFloat(markLines)
		(marks as NSString).draw(
			with: NSRect(x: x, y: bottom - markHeight, width: width, height: markHeight),
			options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
			attributes: markAttributes
		)
	}
}

// MARK: - No backlog yet

/// What the pane shows for a project that has no `.abydos/backlog`.
///
/// It used to show the board regardless: five empty columns, each with its
/// one-line description of what belongs in it, and nothing anywhere saying that
/// the folder those columns are over does not exist. That is the worst of both
/// — it looks like a backlog with nothing in it, which is a state somebody
/// would sensibly try to fix by dragging something into it.
///
/// So this says the folder is missing, says what making one would write, and
/// names the command that does the same thing, because the command line is not
/// a fallback here: it is the other half of the same tool, and somebody who
/// learns the name once can run it in a project this app has never opened.
/// What the pane shows a project that keeps no record of work yet.
///
/// **Both kinds, because the pane reads both.** It offered a backlog and only a
/// backlog for as long as that was the only record there was; the source switch
/// made `openspec/` the other half of this pane and left the empty state saying
/// the app knew about one of them. A project with neither was then told its
/// options, and the one it was not told about is the one this repository has
/// been keeping its own changes in.
///
/// **Drawn as the editor draws a file it cannot show.** `FileNoticeView` is the
/// same sentence about a different subject — there is nothing here, and here is
/// what to do about it — so it is the same shape: an icon, a name, one line of
/// reason, a row of `NoticeButton`s. That button is shared rather than copied,
/// which is the half of the resemblance that cannot drift.
final class BacklogAbsentView: NSView {
	var onMake: (() -> Void)?
	var onSetUpOpenSpec: (() -> Void)?

	private let projectName: String
	private var iconView: NSImageView!
	private var titleLabel: NSTextField!
	private var bodyLabel: NSTextField!
	private var commandLabel: NSTextField!
	private var hintLabel: NSTextField!
	private var makeButton: NoticeButton!
	private var openSpecButton: NoticeButton!

	/// Whether the `openspec` CLI is on this machine.
	///
	/// Asked once, when the view is built, and not on a drawing path:
	/// `Executables.locate` runs a login shell. This view is made when a pane
	/// is, and a project that has neither record is a project nobody is
	/// scrolling — but the shell is expensive enough that it should be asked
	/// deliberately rather than in a layout pass.
	private let hasOpenSpecTool: Bool

	/// Makes this view answer as a machine with no `openspec` on it, for
	/// `--backlog-offer missing`.
	///
	/// A seam rather than a driven install: `Executables.locate` asks the login
	/// shell, and on this machine the tool is under an fnm directory that the
	/// shell will always find — so the state where it is absent cannot be
	/// reached by a launch flag, only pretended. The same shape as
	/// `BacklogCardViewDrawReport`, and off unless a driver asked.
	static var pretendsTheToolIsMissing = false

	init(projectName: String) {
		self.projectName = projectName
		self.hasOpenSpecTool = !Self.pretendsTheToolIsMissing && OpenSpec.commandLine() != nil
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		iconView = NSImageView()
		iconView.image = Theme.symbol("checklist", size: 34, color: Theme.current.gitIgnored)
		iconView.imageScaling = .scaleProportionallyUpOrDown
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.widthAnchor.constraint(equalToConstant: 40).isActive = true
		iconView.heightAnchor.constraint(equalToConstant: 40).isActive = true

		// The project's name where the notice has a file's, because that is what
		// this is about: not a missing folder, but this project having nowhere
		// to keep what is left to do.
		titleLabel = NSTextField(labelWithString: projectName)
		titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
		titleLabel.textColor = Theme.current.sidebarHeaderText
		titleLabel.alignment = .center

		bodyLabel = NSTextField(labelWithString: "No backlog and no OpenSpec directory yet.")
		bodyLabel.font = .systemFont(ofSize: 12)
		bodyLabel.textColor = Theme.current.gitIgnored
		bodyLabel.alignment = .center

		makeButton = NoticeButton(title: "Make a Backlog\u{2026}", symbol: "checklist")
		makeButton.onClick = { [weak self] in self?.onMake?() }

		openSpecButton = NoticeButton(title: "Set Up OpenSpec\u{2026}", symbol: "square.and.pencil")
		openSpecButton.onClick = { [weak self] in self?.onSetUpOpenSpec?() }
		openSpecButton.isEnabled = hasOpenSpecTool

		let buttons = NSStackView(views: [makeButton, openSpecButton])
		buttons.orientation = .horizontal
		buttons.spacing = 10

		// What each button is, so that somebody who would rather type it can.
		// The OpenSpec half is dropped where the tool is not there — a command
		// nothing on this machine can run is not an alternative.
		commandLabel = NSTextField(labelWithString: commandLine)
		commandLabel.font = Theme.current.uiFont(11)
		commandLabel.textColor = Theme.current.gitIgnored
		commandLabel.alignment = .center
		commandLabel.isSelectable = true

		hintLabel = NSTextField(labelWithString: "openspec is not installed.  \(OpenSpec.installHint)")
		hintLabel.font = Theme.current.uiFont(11)
		hintLabel.textColor = Theme.current.gitIgnored
		hintLabel.alignment = .center
		hintLabel.isSelectable = true
		hintLabel.isHidden = hasOpenSpecTool

		let stack = NSStackView(views: [iconView, titleLabel, bodyLabel, buttons, commandLabel, hintLabel])
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 10
		stack.setCustomSpacing(16, after: bodyLabel)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
		])
	}

	private var commandLine: String {
		let backlog = "abydos-backlog init"
		guard hasOpenSpecTool else { return "in a terminal:  \(backlog)" }
		return "in a terminal:  \(backlog)   \u{00B7}   \(OpenSpec.initCommand())"
	}

	/// What this view is offering, for a driver to print.
	///
	/// The four states this has — neither record, no CLI, and either one made —
	/// are a view in the app target, which the suite cannot reach. A line of
	/// text can be read; a photograph has to be looked at by somebody.
	var offerReportForTesting: String {
		[
			"title: \(titleLabel.stringValue)",
			"detail: \(bodyLabel.stringValue)",
			"button: \(makeButton.caption) enabled=\(makeButton.isEnabled)",
			"button: \(openSpecButton.caption) enabled=\(openSpecButton.isEnabled)",
			"commands: \(commandLabel.stringValue)",
			"hint: \(hintLabel.isHidden ? "none" : hintLabel.stringValue)",
		].joined(separator: "\n")
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		iconView.image = Theme.symbol("checklist", size: 34, color: Theme.current.gitIgnored)
		titleLabel.textColor = Theme.current.sidebarHeaderText
		bodyLabel.textColor = Theme.current.gitIgnored
		commandLabel.font = Theme.current.uiFont(11)
		commandLabel.textColor = Theme.current.gitIgnored
		hintLabel.font = Theme.current.uiFont(11)
		hintLabel.textColor = Theme.current.gitIgnored
		// The buttons draw themselves from the theme every time, so a scheme
		// change reaches them through this.
		makeButton.needsDisplay = true
		openSpecButton.needsDisplay = true
	}
}

// MARK: - Shared drawing

/// What a state looks like, and what an item is wearing.
enum BacklogPalette {
	/// Borrowed from the version-control colours rather than invented.
	///
	/// Not laziness: those five are already the palette of "something is going
	/// on with this file" everywhere else in the window, and a board with its
	/// own green means two greens in one app that mean different things.
	static func colour(for state: BacklogState) -> NSColor {
		switch state {
		case .open: return Theme.current.gitUnversioned
		case .ready: return Theme.current.gitAdded
		case .inProgress: return Theme.current.gitModified
		case .waiting: return Theme.current.gitConflict
		case .completed, .history: return Theme.current.gitIgnored
		}
	}

	/// The same five colours for OpenSpec's states, matched by what they mean
	/// rather than by position: `ready` is the one an agent can pick up on
	/// either board, so it is the same green on both, and a change being written
	/// is the same grey as an item nobody has agreed yet.
	static func colour(for state: OpenSpecState) -> NSColor {
		switch state {
		case .writing: return Theme.current.gitUnversioned
		case .ready: return Theme.current.gitAdded
		case .inProgress: return Theme.current.gitModified
		case .complete, .archived: return Theme.current.gitIgnored
		}
	}

	static func colour(for column: BoardColumn) -> NSColor {
		switch column {
		case let .backlog(state):  return colour(for: state)
		case let .openSpec(state): return colour(for: state)
		}
	}

	/// The line under a card: how far along it is, how much longer it has, what
	/// it carries, and where it is being worked on.
	///
	/// The order is the order it can be lost in. This line truncates at the tail
	/// on a narrow column, so what is written first is what survives — and the
	/// fraction and the estimate are the two things that change while somebody is
	/// watching the board, while the branch name is both the longest and the one
	/// that has not changed since the item was picked up.
	static func marks(for card: BacklogCard, now: Date = Date()) -> String {
		var marks: [String] = []

		if let progress = card.progress {
			// The fraction says which copy it came from, because a fraction read
			// off a branch three commits ahead of the project is not the same
			// fact as one read off the project, and a card that shows the one as
			// the other is how somebody comes to trust a number they should not.
			//
			// Four words rather than the branch name, though the branch is the
			// more precise answer and is already on the line: this end of the
			// line is the end that survives a narrow column, and a branch name
			// here would push everything after it off every in-progress card on
			// the board. Which worktree is at the tail, where it can be lost;
			// that there is one is at the head, where it cannot.
			switch card.source {
			case .worktree: marks.append("\(progress.summary) in the worktree")
			case .project:
				// Said only where there is something to mistake it for. An item
				// nobody has picked up has one copy, and "in the project" on
				// every card of a board is a distinction without a difference —
				// but on an item with a checkout recorded and gone, it is the
				// difference between an old number and a current one.
				marks.append(card.run == nil
					? progress.summary
					: "\(progress.summary) in the project")
			}
		}
		if let estimate = card.estimate { marks.append(estimate.summary(now: now)) }
		if card.images > 0 { marks.append("\(card.images) image\(card.images == 1 ? "" : "s")") }
		if card.hasSpecDelta { marks.append("spec") }
		if let run = card.run, run.isPresent { marks.append(run.branch) }
		return marks.joined(separator: "  \u{00B7}  ")
	}
}


/// Turns on the per-card drawing report, which lives on a private type.
enum BacklogCardViewDrawReport {
	static func enable() { BacklogCardView.reportsDrawing = true }
}

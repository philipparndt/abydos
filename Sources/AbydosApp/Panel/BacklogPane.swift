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

	private let backlog: Backlog
	private var watcher: FileSystemWatcher?

	private var cardsByState: [BacklogState: [BacklogCard]] = [:]

	/// Whether this project has a backlog at all.
	///
	/// Remembered rather than asked each time: the answer decides which view is
	/// installed and whether the header means anything, and both are consulted
	/// on every reload. Re-read by `reload`, which is what runs when somebody
	/// makes one in a terminal.
	private var hasBacklog = false

	private enum Mode: Int { case list, board }
	private var mode: Mode = .board

	private var header: NSStackView!
	private var headerHeight: NSLayoutConstraint!
	private var modeControl: NSSegmentedControl!
	private var summaryLabel: NSTextField!
	private var startButton: NSButton!
	private var newButton: NSButton!
	private var contentArea: NSView!
	private var listView: BacklogListView!
	private var boardView: BacklogBoardView!
	private var absentView: BacklogAbsentView!

	init(projectRoot: URL) {
		self.backlog = Backlog(projectRoot: projectRoot)
		self.hasBacklog = backlog.exists
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		reload()
		watch()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		watcher?.stop()
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

		header = NSStackView(views: [modeControl, summaryLabel, spacer, newButton, startButton, refresh])
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

	private func showContent() {
		// The header is about a backlog: two presentations of it, how many are
		// in each folder, and what to start next. With no backlog there is
		// nothing for it to say, and a row of disabled controls above "there is
		// no backlog here" reads as a broken pane rather than an empty one.
		header.isHidden = !hasBacklog
		headerHeight.constant = hasBacklog ? Theme.current.scaled(34) : 0

		let wanted: NSView = hasBacklog ? (mode == .list ? listView : boardView) : absentView
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
		DispatchQueue.global(qos: .userInitiated).async {
			// Asked here rather than on the main thread, and asked every time:
			// `abydos-backlog init` in a terminal is the other way a project
			// gets a backlog, and the watcher cannot report a folder appearing
			// that it was never able to watch.
			let exists = backlog.exists
			let runs = Dictionary(
				uniqueKeysWithValues: BacklogRuns(projectRoot: backlog.projectRoot).all().map { ($0.number, $0) }
			)
			var found: [BacklogState: [BacklogCard]] = [:]
			for state in BacklogState.board {
				found[state] = backlog.items(in: state).map { BacklogCard($0, run: runs[$0.number]) }
			}

			DispatchQueue.main.async {
				self.cardsByState = found
				if exists != self.hasBacklog {
					self.hasBacklog = exists
					self.showContent()
					if exists { self.watch() }
				}
				self.refreshViews()
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
		guard watcher == nil else { return }
		guard FileManager.default.fileExists(atPath: backlog.directory.path) else { return }
		let watcher = FileSystemWatcher(root: backlog.directory) { [weak self] _ in
			DispatchQueue.main.async { self?.reload() }
		}
		watcher.start()
		self.watcher = watcher
	}

	private func refreshViews() {
		let counts = BacklogState.board.map { "\(cards(in: $0).count) \($0.directoryName)" }
		summaryLabel.stringValue = counts.joined(separator: "   ")
		startButton.isEnabled = !cards(in: .ready).isEmpty

		guard hasBacklog else { return }
		if mode == .list {
			listView.reload()
		} else {
			boardView.reload()
		}
	}

	func cards(in state: BacklogState) -> [BacklogCard] { cardsByState[state] ?? [] }

	func item(number: Int) -> BacklogItem? {
		BacklogState.board.compactMap { cards(in: $0).first { $0.item.number == number }?.item }.first
	}

	// MARK: - Acting

	func open(_ item: BacklogItem) {
		onOpenItem?(item.file)
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
	func menuTitlesForTesting(number: Int) -> String {
		let found = BacklogState.board
			.compactMap { cards(in: $0).first { $0.number == number } }
			.first
		guard let card = found else { return "no item \(number) on the board" }
		return menu(for: card).items
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
		case header(BacklogState, Int)
		case item(BacklogCard)
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
		for state in BacklogState.board {
			let cards = pane.cards(in: state)
			guard !cards.isEmpty else { continue }
			rows.append(.header(state, cards.count))
			rows += cards.map(Row.item)
		}
		tableView.reloadData()
	}

	@objc private func rowDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < rows.count else { return }
		guard case let .item(card) = rows[tableView.clickedRow] else { return }
		pane?.open(card.item)
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
		case .item: return Theme.current.scaled(22)
		}
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		switch rows[row] {
		case let .header(state, count):
			return BacklogSectionHeader(state: state, count: count)
		case let .item(card):
			let view = BacklogRowCell()
			view.configure(card)
			view.menu = pane?.menu(for: card)
			return view
		}
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		if case .header = rows[row] { return false }
		return true
	}
}

/// `Ready — 3`, over the items in it.
private final class BacklogSectionHeader: NSView {
	private let state: BacklogState
	private let count: Int

	init(state: BacklogState, count: Int) {
		self.state = state
		self.count = count
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let font = Theme.current.uiFont(11, weight: .semibold)
		let text = "\(state.title.uppercased())  \(count)"
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: BacklogPalette.colour(for: state),
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

	private func build() {
		columns = BacklogState.board.map { BacklogColumnView(state: $0) }
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
				greaterThanOrEqualToConstant: Theme.current.scaled(CGFloat(BacklogState.board.count) * 190)
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
	let state: BacklogState

	/// What a dragged card carries: the number, which is the only durable name
	/// an item has.
	static let dragType = NSPasteboard.PasteboardType("dev.abydos.backlog.item")

	private var cards: [BacklogCard] = []
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

	init(state: BacklogState) {
		self.state = state
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		headerLabel = NSTextField(labelWithString: state.title.uppercased())
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: state)

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
		emptyLabel = NSTextField(wrappingLabelWithString: state.summary)
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

	func reload() {
		cards = pane?.cards(in: state) ?? []
		headerLabel.stringValue = cards.isEmpty
			? state.title.uppercased()
			: "\(state.title.uppercased())  \(cards.count)"
		emptyLabel.isHidden = !cards.isEmpty
		tableView.reloadData()
	}

	@objc private func cardDoubleClicked() {
		guard tableView.clickedRow >= 0, tableView.clickedRow < cards.count else { return }
		pane?.open(cards[tableView.clickedRow].item)
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		headerLabel.font = Theme.current.uiFont(11, weight: .semibold)
		headerLabel.textColor = BacklogPalette.colour(for: state)
		emptyLabel.font = Theme.current.uiFont(11)
		emptyLabel.textColor = Theme.current.gitIgnored
		tableView.backgroundColor = Theme.current.editorBackground
		tableView.intercellSpacing = NSSize(width: 0, height: Theme.current.scaled(6))
		tableView.enclosingScrollView?.backgroundColor = Theme.current.editorBackground
	}
}

extension BacklogColumnView: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { cards.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		BacklogCardView.height(for: cards[row], width: cardWidth)
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
	func widthChanged(to width: CGFloat) {
		guard abs(width - measuredWidth) > 0.5, !cards.isEmpty else { return }
		measuredWidth = width
		tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<cards.count))
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let card = cards[row]
		let view = BacklogCardView()
		view.configure(card)
		view.menu = pane?.menu(for: card)
		return view
	}

	// MARK: Dragging

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
		let entry = NSPasteboardItem()
		entry.setString(String(cards[row].number), forType: BacklogColumnView.dragType)
		return entry
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
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else {
			return []
		}
		return item.state == state ? [] : .move
	}

	func tableView(
		_ tableView: NSTableView,
		acceptDrop info: any NSDraggingInfo,
		row: Int,
		dropOperation: NSTableView.DropOperation
	) -> Bool {
		guard let number = draggedNumber(from: info), let item = pane?.item(number: number) else { return false }
		guard item.state != state else { return false }
		pane?.move(item, to: state)
		return true
	}

	private func draggedNumber(from info: any NSDraggingInfo) -> Int? {
		guard let entries = info.draggingPasteboard.pasteboardItems else { return nil }
		return entries.compactMap { $0.string(forType: BacklogColumnView.dragType) }.compactMap(Int.init).first
	}
}

/// One item as a card: the number, the title, and what it carries.
private final class BacklogCardView: NSView {
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

	func configure(_ card: BacklogCard) {
		number = String(format: "%04d", card.number)
		title = card.title
		tint = BacklogPalette.colour(for: card.state)
		marks = BacklogPalette.marks(for: card)
		progress = card.progress
		needsDisplay = true
	}

	/// Tall enough for the title to fit, which is what makes the board readable
	/// — a card that truncates at forty characters is a card whose title is
	/// "the settings page will not stay the width" for four different items.
	static func height(for card: BacklogCard, width: CGFloat) -> CGFloat {
		let inset = Theme.current.scaled(Self.inset)
		let gutter = Theme.current.scaled(Self.gutter)
		let available = max(width - gutter * 2 - inset * 2, 40)
		let font = Theme.current.uiFont(12)
		let bounds = (card.title as NSString).boundingRect(
			with: NSSize(width: available, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: font]
		)
		return ceil(bounds.height) + numberLine + Theme.current.scaled(2)
			+ footer(
				markLines: markLines(BacklogPalette.marks(for: card), width: available),
				progress: card.progress != nil
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
	static func footer(markLines: Int, progress: Bool) -> CGFloat {
		var footer = markLine * CGFloat(markLines)
		if progress { footer += Theme.current.scaled(Self.barHeight) + Theme.current.scaled(4) }
		return footer
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let gutter = Theme.current.scaled(Self.gutter)
		let inset = Theme.current.scaled(Self.inset)
		let card = bounds.insetBy(dx: gutter, dy: 0)

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
final class BacklogAbsentView: NSView {
	var onMake: (() -> Void)?

	private let projectName: String
	private var titleLabel: NSTextField!
	private var bodyLabel: NSTextField!
	private var commandLabel: NSTextField!
	private var makeButton: NSButton!

	init(projectName: String) {
		self.projectName = projectName
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		titleLabel = NSTextField(labelWithString: "\(projectName) has no backlog")
		titleLabel.font = Theme.current.uiFont(13, weight: .semibold)
		titleLabel.textColor = Theme.current.editorText

		bodyLabel = NSTextField(wrappingLabelWithString: """
		A backlog is a folder of markdown beside the project: open, ready, \
		in-progress, waiting and completed, the workflow that says how they are \
		worked, and a spec of what the project does today. Making one writes \
		.abydos/backlog and points the assistants installed on this machine at it.
		""")
		bodyLabel.font = Theme.current.uiFont(11)
		bodyLabel.textColor = Theme.current.gitIgnored
		bodyLabel.preferredMaxLayoutWidth = Theme.current.scaled(420)

		makeButton = NSButton(title: "Make a Backlog\u{2026}", target: self, action: #selector(makeClicked))
		makeButton.bezelStyle = .rounded
		makeButton.controlSize = .regular

		commandLabel = NSTextField(labelWithString: "or, in a terminal:  abydos-backlog init")
		commandLabel.font = Theme.current.uiFont(11)
		commandLabel.textColor = Theme.current.gitIgnored
		commandLabel.isSelectable = true

		let stack = NSStackView(views: [titleLabel, bodyLabel, makeButton, commandLabel])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(10)
		stack.setCustomSpacing(Theme.current.scaled(16), after: bodyLabel)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(24)),
			// Never the pane's whole width: a paragraph across a maximised
			// window is one long line, which is the hardest thing to read that
			// a panel can contain.
			stack.widthAnchor.constraint(lessThanOrEqualToConstant: Theme.current.scaled(420)),
			stack.trailingAnchor.constraint(
				lessThanOrEqualTo: trailingAnchor, constant: -Theme.current.scaled(24)
			),
		])
	}

	@objc private func makeClicked() { onMake?() }

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		titleLabel.font = Theme.current.uiFont(13, weight: .semibold)
		titleLabel.textColor = Theme.current.editorText
		bodyLabel.font = Theme.current.uiFont(11)
		bodyLabel.textColor = Theme.current.gitIgnored
		bodyLabel.preferredMaxLayoutWidth = Theme.current.scaled(420)
		commandLabel.font = Theme.current.uiFont(11)
		commandLabel.textColor = Theme.current.gitIgnored
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

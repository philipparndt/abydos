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
final class ChangesPane: NSView, ScaleFollowing {

	// Kept here because a stored property cannot live in an extension; what
	// each is for is said where it is used.
	var wantsAnotherRefresh = false
	var activity: PaneActivityView?
	var fillsInFlight: Set<String> = []

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
	/// Where a finished draft goes: the window's inbox, keyed by this pane's
	/// own root.
	///
	/// Not into the fields from inside the task. A pane is neither long-lived
	/// nor tied to a project — it is rebuilt whenever the sidebar tool is, and
	/// a project switch closes the commit page and leaves the *old* project's
	/// sidebar pane on screen until the new project's branch read finishes. So
	/// the answer goes somewhere that outlives the view and knows which
	/// project it is about.
	var onDraft: ((URL, ClaudeDraft.Draft) -> Void)?
	/// What is waiting for this pane's root, asked when the pane is built and
	/// whenever a remembered message is put back.
	var heldDraft: ((URL) -> ClaudeDraft.Draft?)?
	/// Throws away what is waiting, because the message it was offered against
	/// has been committed.
	var onDraftTaken: ((URL) -> Void)?

	/// Lines were selected in the page's own diff and something is to be done
	/// with them. Only in `.page`: the sidebar hands its diff to a tab, and the
	/// tab carries these itself.
	///
	/// **The page's diff had none of these and said nothing about it.** The
	/// menu over it is `DiffView`'s, which offers "Stage Selected Lines"
	/// whenever the diff is not read-only — so on the page the item was there,
	/// was enabled, and called a closure nobody had set. Fifteen lines selected,
	/// the item pressed, and the working copy exactly as it was.
	///
	/// The root travels with the change because a file inside a submodule is
	/// staged in that submodule: the diff was read there, so its patch names
	/// paths relative to it, and `git apply --cached` in the superproject would
	/// be applying a patch about files it does not track.
	var onApplyDiffSelection: ((GitChange, String, Set<Int>, URL) -> Void)?
	var onDiscardDiffSelection: ((GitChange, String, Set<Int>, URL) -> Void)?
	/// Nil where git is too old for `stash push --staged`, so the item is
	/// absent rather than failing when pressed.
	var onStashDiffSelection: ((GitChange, String, Set<Int>, URL) -> Void)?

	/// Not `layout`: that is `NSView`'s, and shadowing it means an override
	/// silently is not one — which cost an afternoon in `HistoryPane`.
	let arrangement: Layout
	let root: URL

	/// The work tree this pane is showing, so the window can tell whether the
	/// one it has is the one it wants rather than building another.
	var repositoryRoot: URL { root }

	var status = GitWorkingCopyStatus()

	/// The submodules this repository holds, and what each of them has changed.
	/// See `EstateChanges` — empty for a repository that has none, down the
	/// same code path.
	let submodules: EstateChanges
	var unstagedTable: ChangesOutlineView!
	var stagedTable: ChangesOutlineView!

	/// The keyboard belongs in a list, not in the box around it — see the same
	/// override on `HistoryPane`, which is where this was found.
	override var acceptsFirstResponder: Bool { true }

	override func becomeFirstResponder() -> Bool {
		DispatchQueue.main.async { [weak self] in self?.focusList() }
		return super.becomeFirstResponder()
	}

	/// Which list the keyboard is in, and what it has selected, for a driven
	/// run — the same three claims the log page's `keys` step makes.
	func keyboardReportForTesting() -> String {
		guard let responder = window?.firstResponder else { return "keyboard=nobody" }
		let where_: String
		if responder === unstagedTable { where_ = "the unstaged list" }
		else if responder === stagedTable { where_ = "the staged list" }
		else if responder === self { where_ = "the pane itself" }
		else { where_ = String(describing: type(of: responder)) }
		let table = responder === stagedTable ? stagedTable : unstagedTable
		let row = table?.selectedRow ?? -1
		let selected = row >= 0
			? ((table?.item(atRow: row) as? GitChangeNode).map { $0.holdsFiles ? $0.name + "/" : $0.path } ?? "?")
			: "nothing"
		return "keyboard=\(where_) rows=\(table?.numberOfRows ?? 0) selected=\(selected)"
	}

	/// Works the list from the keyboard and says what happened, the way the log
	/// page's `keys` step does. The characters matter as well as the key codes:
	/// a table maps arrows through the key-binding manager, which reads what the
	/// key produced.
	func keysForTesting(_ steps: String) -> String {
		guard let window else { return "no window" }
		var said: [String] = []
		func table() -> ChangesOutlineView? {
			window.firstResponder as? ChangesOutlineView
		}
		func key(_ code: UInt16, _ scalar: UnicodeScalar) {
			let characters = String(Character(scalar))
			guard let table = table(), let event = NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: .function,
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber, context: nil,
				characters: characters, charactersIgnoringModifiers: characters,
				isARepeat: false, keyCode: code
			) else { return }
			table.keyDown(with: event)
		}
		func selection() -> String {
			guard let table = table(), table.selectedRow >= 0,
			      let node = table.item(atRow: table.selectedRow) as? GitChangeNode
			else { return "nothing" }
			return node.holdsFiles ? node.name + "/" : node.path
		}
		for step in steps.split(separator: "+").map(String.init) {
			switch step {
			// A real click, through the window server, on the list with rows:
			// the question is whether the click gives the tree the keyboard so
			// the arrow after it moves the selection, and only a real click can
			// ask it. `TreeKeys` is the same instrument the other trees use.
			case let step where step.hasPrefix("click"):
				let row = Int(step.dropFirst("click".count)) ?? 0
				said.append(TreeKeys.click(row: row, in: listWithRows())
					+ " keyboard=\(TreeKeys.keyboardHolder(in: window)) \(selection())")
			case "down":  key(125, UnicodeScalar(0xF701)!); said.append("down \(selection())")
			case "up":    key(126, UnicodeScalar(0xF700)!); said.append("up \(selection())")
			case "left":  key(123, UnicodeScalar(0xF702)!); said.append("left \(selection())")
			case "right": key(124, UnicodeScalar(0xF703)!); said.append("right \(selection())")
			case "who":   said.append(keyboardReportForTesting())
			default:      said.append("unknown step \(step)")
			}
		}
		return said.joined(separator: " | ")
	}

	/// Puts the keyboard in whichever list has rows, unstaged first: that is
	/// the one somebody is working through.
	func focusList() {
		guard let window, window.firstResponder === self else { return }
		window.makeFirstResponder(listWithRows())
	}

	private func listWithRows() -> ChangesOutlineView {
		(unstagedTable?.numberOfRows ?? 0) > 0 ? unstagedTable : stagedTable
	}

	/// The keyboard is in one of our lists and that list is empty.
	func moveKeyboardOffAnEmptyList() {
		guard let window else { return }
		let responder = window.firstResponder
		let ours = responder === unstagedTable || responder === stagedTable || responder === self
		guard ours else { return }
		if let table = responder as? ChangesOutlineView, table.numberOfRows > 0 { return }
		let wanted = listWithRows()
		guard wanted.numberOfRows > 0, responder !== wanted else { return }
		window.makeFirstResponder(wanted)
		if wanted.selectedRow < 0, wanted.numberOfRows > 0 {
			wanted.selectRowIndexes([0], byExtendingSelection: false)
		}
	}
	var unstagedHeader: SectionHeaderView!
	var stagedHeader: SectionHeaderView!

	/// One side of the index, as rows.
	///
	/// The tree is thrown away and built again on every refresh — which happens
	/// on every filesystem event — so everything that has to outlive a rebuild
	/// is kept here as paths. Rebuilding and re-deriving is what `TreeSelection`
	/// exists for in the navigator, and 0446 is why nothing here tries to be
	/// cleverer than that.
	struct Side {
		var roots: [GitChangeNode] = []
		var byPath: [String: GitChangeNode] = [:]
		/// Folders somebody folded shut. Held the negative way round because a
		/// changes tree wants to arrive open: a pane that shows five folder
		/// names where the flat list showed twenty files has told you less than
		/// it did before, and a folder that appears while you are working is
		/// new work you should see.
		var collapsed: Set<String> = []
		/// Where the selection goes when everything selected has been staged
		/// away, in the order to try. See `rememberWhereTheSelectionGoes`.
		var fallback: [String] = []
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

	var unstagedSide = Side()
	var stagedSide = Side()

	/// What somebody folded and unfolded on each side, for the session.
	///
	/// Two sides and two sets each: `collapsed` is negative because a changes
	/// tree wants to arrive open, and `opened` is positive because an untracked
	/// directory costs a git call to unroll. Keyed `changes.unstaged` and
	/// `changes.staged`, since the two lists are arranged separately and a
	/// folder shut above is not a folder shut below.
	var folds: [String: ProjectSession.TreeFolds] {
		get {
			[
				"changes.unstaged": .init(
					shut: unstagedSide.collapsed.sorted(), opened: unstagedSide.opened.sorted()
				),
				"changes.staged": .init(
					shut: stagedSide.collapsed.sorted(), opened: stagedSide.opened.sorted()
				),
			].filter { !$0.value.isEmpty }
		}
		set {
			if let unstaged = newValue["changes.unstaged"] {
				unstagedSide.collapsed = Set(unstaged.shut)
				unstagedSide.opened = Set(unstaged.opened)
			}
			if let staged = newValue["changes.staged"] {
				stagedSide.collapsed = Set(staged.shut)
				stagedSide.opened = Set(staged.opened)
			}
		}
	}

	/// Set while the pane is putting expansion or selection back after a
	/// rebuild, so that its own work is not mistaken for somebody's.
	var isRestoring = false

	/// Stops restoring, but not until the run loop comes round again.
	///
	/// **Because `NSTableView` posts its selection change on a later turn.**
	/// The flag was cleared on the line after the restore, so a notification
	/// the restore itself caused arrived with the pane no longer claiming to be
	/// restoring — and was treated as somebody clicking. The handler's job when
	/// somebody clicks is to clear the *other* list, so staging put the
	/// selection on the right row, the staged list's own restore posted a
	/// moment later, and the row that had just been chosen was deselected.
	///
	/// That is the report exactly: *it shortly blinks at the right selection
	/// and is then refreshed again and cleared out* — and its mirror, the
	/// staged rows briefly taking the selection while unstaging.
	///
	/// A person cannot click in the same turn the restore ran in, so nothing
	/// real is swallowed by waiting one.
	func stopRestoring() {
		DispatchQueue.main.async { [weak self] in self?.isRestoring = false }
	}

	var subjectField: NSTextField!
	/// The diff of the selected change, in `.page` only.
	var diffView: DiffView?
	/// The text diff and the picture diff, and which is in the scroll view: a
	/// changed picture diffs as two pictures rather than as one sentence.
	///
	/// **Built on the first ask that can build it, not lazily.** A `lazy var`
	/// here cached the nil from the first ask, which arrives before the page is
	/// arranged and the diff view is in a scroll view at all — and a cached nil
	/// is a picture that diffs as prose for the life of the pane.
	private var builtDiffDocuments: DiffDocuments?
	var diffDocuments: DiffDocuments? {
		if let builtDiffDocuments { return builtDiffDocuments }
		guard let diffView, let made = DiffDocuments(text: diffView) else { return nil }
		builtDiffDocuments = made
		return made
	}
	var pageSplit: NSSplitView?
	var hasPlacedDivider = false
	var draftButton: DrawnButton?

	/// Which of the draft button's three states it is in.
	///
	/// **An enum rather than the label it used to be read from.**
	/// `updateCommitButton` asked `draft.title == "Draft"` to decide whether it
	/// was looking at the idle button — so relabelling it fell out of that
	/// branch and quietly stopped refreshing its availability and its tooltip.
	/// A third label would have made three ways to be wrong.
	enum DraftState: Equatable {
		/// Nothing out, nothing held.
		case idle
		/// The `claude` process is running.
		case drafting
		/// An answer came back onto a message with words in it, and is being
		/// offered rather than written over them.
		case offering
	}

	var draftState: DraftState = .idle {
		didSet {
			guard draftState != oldValue else { return }
			applyDraftState()
		}
	}

	/// The label, the spinner, the colour and whether it can be pressed — from
	/// one switch, so the four cannot disagree.
	func applyDraftState() {
		guard let button = draftButton else { return }
		switch draftState {
		case .idle:
			button.setLabel("Draft")
			button.isWorking = false
			button.tint = nil
			button.isEnabled = ClaudeDraft.isAvailable
			button.tip = ClaudeDraft.isAvailable
				? StyledTip.Tip(
					title: "Draft the message",
					detail: "An agent reads what is staged and writes a summary and description."
				)
				: StyledTip.Tip(
					title: "Draft the message",
					detail: "The claude command was not found on the PATH."
				)
		case .drafting:
			button.setLabel("Drafting…")
			// The spinner `DrawnButton` has had since Push used it, and this
			// button never did: a disabled button with a changed word says
			// "broken" as readily as "working".
			button.isWorking = true
			button.tint = nil
			button.isEnabled = false
			button.tip = StyledTip.Tip(
				title: "Drafting",
				detail: "Asking claude for a summary and description."
			)
		case .offering:
			button.setLabel("Use draft instead")
			button.isWorking = false
			// The palette's own red, which every scheme defines; no new key.
			button.tint = Theme.current.gitConflict
			button.isEnabled = true
			button.tip = StyledTip.Tip(
				title: "Use the draft instead",
				detail: "A draft came back while this message had words in it. "
					+ "Press to replace both fields with it."
			)
		}
	}
	var historyButton: DrawnButton?
	var bodyView: NSTextView!
	/// Opens the description, which the page starts with put away.
	var descriptionChevron: DrawnButton!
	/// The description's own height, turned off while it is collapsed.
	var descriptionHeight: NSLayoutConstraint!
	/// Every height this pane takes out of the theme — see `ScaledHeights`.
	let heights = ScaledHeights()
	/// The scroll view around the description, which is what is hidden: an
	/// `NSStackView` collapses a hidden arranged subview, and hiding rather than
	/// removing is what keeps the text through being put away.
	var descriptionBox: NSScrollView!
	/// Kept for as long as the page is open, so somebody who writes a
	/// description opens it once rather than once per commit.
	var isDescriptionShowing = false
	/// The summary, description and commit row together, for saying where they
	/// ended up.
	var messageStack: NSStackView!
	var amendCheckbox: DrawnCheckbox!
	var commitButton: DrawnButton!
	var pushButton: DrawnButton!
	/// Where the branch stands against its remote, for what push should say.
	var pushState: GitPush.State?

	/// Guards against a refresh landing while a git command is still running and
	/// showing a half-applied state.
	var isBusy = false
	/// A push is out, and the button is saying so.
	var isPushing = false
	/// Which selection the diff on its way belongs to. Bumped by every
	/// `showDiff`, and a render that comes back to a different number is for
	/// a row nobody is looking at any more — see `showDiff`.
	var diffGeneration = 0

	init(root: URL, layout: Layout = .sidebar) {
		self.root = root
		self.submodules = EstateChanges(root: root)
		self.arrangement = layout
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		beginFirstRead()
		refresh()
		heights.follow(self.unstagedTable)
		heights.follow(self.stagedTable)
		ScaledControls.register(self)

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
		// No paths with it, so nothing here knows what moved. That is the right
		// answer for what posts this: a commit, a checkout, a pull, a branch
		// switch — every one of which can move every gitlink in the estate, and
		// none of which happens per keystroke. The event that *does* arrive
		// dozens a minute is a file being written, and that one comes through
		// `refresh(after:)` with its paths.
		refresh()
	}

	/// Re-reads only the repositories the filesystem event named.
	///
	/// **This is what makes a superproject affordable to hold open.** Sweeping
	/// an estate is 0.45 s over two hundred submodules and this is called on
	/// every write inside the project; re-reading the one repository the write
	/// landed in is 0.01 s. `GitEstateRefresh` does the attribution, from the
	/// paths the navigator's watcher already has.
	func refresh(after change: FileSystemChange) {
		refresh(submodules.read(after: change))
	}

	required init?(coder: NSCoder) { fatalError("not used") }


	// MARK: - Actions

	func makeChangeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	/// The row the menu was opened on, whichever list it is in.
	var clickedNode: (node: GitChangeNode, isStaged: Bool)? {
		for table in [unstagedTable, stagedTable] {
			guard let table, table.clickedRow >= 0 else { continue }
			guard let node = table.item(atRow: table.clickedRow) as? GitChangeNode else { continue }
			return (node, table === stagedTable)
		}
		return nil
	}

	@objc func revealClicked() {
		guard let clicked = clickedNode else { return }
		NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(clicked.node.path)])
	}

	@objc func copyClickedPath() {
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
	@objc func ignoreClicked() {
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
	func stashable() -> (paths: [String], files: Int) {
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

	@objc func stashSelected() {
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

	@objc func stashEverything() {
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

	private var operationChain: Task<Void, Never>?

	func runAcrossOwners(
		_ paths: [String],
		reporting: Bool = true,
		moving: OptimisticMove? = nil,
		_ operation: @escaping ([String], GitEstate) async -> [GitEstateOutcome]
	) {
		let estate = submodules.estate
		// **Where the selection lands, remembered here and not at the call
		// sites.** Three of them staged and only two said where the selection
		// should go, so staging from the context menu emptied the selection —
		// the same fault as the pane forgetting to re-apply a font, one floor
		// down. Every path that moves rows comes through here.
		switch moving {
		case .toStaged:   rememberWhereTheSelectionGoes(in: unstagedTable, staged: false)
		case .toUnstaged: rememberWhereTheSelectionGoes(in: stagedTable, staged: true)
		case nil:         break
		}
		isBusy = true
		let asked = Date()
		let previous = operationChain
		operationChain = Task { @MainActor in
			await previous?.value
			let outcomes = await operation(paths, estate)
			// A gap between these two is not git being slow: the command took
			// `asked → returned`, and everything before `asked` was this task
			// waiting its turn on the main actor.
			operationTiming = (asked: asked, returned: Date())
			isBusy = false
			// The row moves now, on the command's own word; the status read
			// that follows replaces the whole answer as it always did. Not on
			// a partial failure: half-truths are the status's to sort out, and
			// it is already on its way.
			if let moving, !outcomes.contains(where: \.didFail) {
				apply(move: moving, to: paths)
			}
			if reporting { report(outcomes) }
			wantsAnotherRefresh = false
			refresh()
			onWorkingCopyChanged?()
		}
	}

	/// Moves the operation's paths between the sides in the model the trees
	/// draw from — `GitWorkingCopyStatus.moveToStaged`'s presentation, not
	/// truth: the porcelain status remains the one authority and lands within
	/// the moment. But the click has to be seen to have worked before a second
	/// one is made to be sure.
	private func apply(move: OptimisticMove, to paths: [String]) {
		let before = status
		switch move {
		case .toStaged:   status.moveToStaged(paths)
		case .toUnstaged: status.moveToUnstaged(paths)
		}
		guard status != before else { return }
		// Said to a driven run before the status lands, so a test can see the
		// order: the move first, the confirming read after.
		if DrivenRun.isActive {
			print("OPTIMISTIC: moved \(paths.count) path\(paths.count == 1 ? "" : "s")")
			fflush(stdout)
		}
		reload()
	}

	/// When the last operation was asked for and when its command returned, so
	/// the refresh that follows can say where the time went. Printed on driven
	/// runs only — a person's stage is not a benchmark.
	private var operationTiming: (asked: Date, returned: Date)?

	/// One line naming the three spans somebody slow-staging would ask about.
	func sayOperationTiming(statusReturned: Date, reloadDone: Date) {
		guard DrivenRun.isActive, let timing = operationTiming else { return }
		operationTiming = nil
		func ms(_ from: Date, _ to: Date) -> String {
			"\(Int(to.timeIntervalSince(from) * 1000))ms"
		}
		print("STAGE-TIMING: command \(ms(timing.asked, timing.returned))"
			+ " · status \(ms(timing.returned, statusReturned))"
			+ " · reload \(ms(statusReturned, reloadDone))")
		fflush(stdout)
	}

	/// Says what failed, per repository, and says nothing when nothing did.
	///
	/// Named repositories rather than one summary: an estate operation that
	/// half-worked is a state somebody has to act on, and "git reported a
	/// problem" over two hundred repositories is not something anybody can.
	private func report(_ outcomes: [GitEstateOutcome]) {
		let failed = outcomes.filter(\.didFail)
		guard !failed.isEmpty else { return }
		let detail = failed.map { outcome -> String in
			guard case .failed(let why) = outcome.result else { return outcome.name }
			return "\(outcome.name): \(why)"
		}.joined(separator: "\n")
		presentFailure(detail)
	}

	private func run(_ operation: @escaping () async -> GitRepository.ProcessResult) {
		isBusy = true
		Task { @MainActor in
			let result = await operation()
			isBusy = false

			if result.exitCode != 0 {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}
			// The unconditional refresh below is the kept one, if one was kept.
			wantsAnotherRefresh = false
			refresh()
			onWorkingCopyChanged?()
		}
	}

	func presentFailure(_ message: String) {
		Toast.post(
			"git reported a problem",
			detail: message.trimmingCharacters(in: .whitespacesAndNewlines)
		)
	}

}

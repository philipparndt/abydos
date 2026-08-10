import AppKit
import AbydosKit

/// Project-wide search results (⇧⌘F).
///
/// Results stream in as the walk proceeds rather than appearing all at once, so
/// the first hits are usable immediately on a large tree.
///
/// ## The list is a checklist
///
/// Going through a search is a job: open one, decide, move on. So rows can be
/// selected several at a time and marked **done**, which strikes them through
/// and leaves them where they are. Nothing about it touches a file.
///
/// The word and the key are both chosen against the pane one window away. In
/// the project tree ⌘⌫ moves a file to the trash, and that tree is the same
/// list-shaped thing full of file names — so a gesture here that reads as a
/// deletion would be avoided by anybody sensible, and the feature would be
/// worth nothing. Hence:
///
/// - The word is **done**, never "delete", "remove" or "clear". "Mark as Done"
///   and "Mark as Not Done" cannot be read as touching the disk, which
///   "Dismiss" — halfway between putting a thing aside and getting rid of it —
///   can.
/// - The key is **␣**, which is what ticks a checkbox everywhere in the system,
///   is destructive nowhere, and is nowhere near ⌫. ⌫ and ⌘⌫ are deliberately
///   left unanswered here: a key that trashes files one pane over must do
///   nothing at all in this one, rather than something merely different.
/// - It is a toggle, so the way out of a wrong tick is the key that made it,
///   and ⌘Z is the second way rather than the only one.
///
/// ## Struck through rather than gone
///
/// A done row stays in place, greyed and struck through, and the file heading
/// above it shows how many of its matches are done. A list that removed rows as
/// they were ticked would move everything under the pointer on every press —
/// and the next ␣ would then land on something nobody had looked at, which is
/// the one mistake this must not make easy. Keeping the row is also what makes
/// unticking possible at all.
///
/// The shortening list is still available, as a toggle: `✓` in the controls
/// hides everything already marked, and a file whose matches are all done goes
/// with them, heading and all.
final class SearchPane: NSView {
	var onOpenResult: ((URL, Int, SearchMatch) -> Void)?

	private let search: ProjectSearch
	private let projectRoot: URL

	/// Flattened for display: a file header row, then one row per match.
	///
	/// The done state is carried on the row rather than looked up while drawing:
	/// a cell is made per visible row on every reload, and asking the checklist
	/// from inside `viewFor` would recompute a file's marks once per row of it.
	private enum Row {
		case file(FileSearchResult, done: Int, isDone: Bool)
		case match(FileSearchResult, SearchMatch, SearchChecklist.Mark, isDone: Bool)
	}

	private var results: [FileSearchResult] = []
	private var rows: [Row] = []
	private var collapsedFiles: Set<String> = []

	/// What has been ticked off, per question.
	///
	/// Held by the pane, which is one per window and lives as long as it, so the
	/// marks survive the search being run again — which is the whole point, and
	/// is what a re-run does not otherwise get: ⇧⌘F with the same term after a
	/// file has been edited rebuilds `results` from nothing.
	private var checklist = SearchChecklist()
	private var searchFinished = true

	private var field: NSSearchField!
	private var statusLabel: NSTextField!
	private var caseButton: NSButton!
	private var wordButton: NSButton!
	private var regexButton: NSButton!
	private var hideDoneButton: NSButton!
	private var tableView: SearchResultsTable!
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
		// Not one of the three: the others change what the search finds and so
		// re-run it, this one only changes what is shown of what was found.
		hideDoneButton = makeToggle("✓", "Hide the rows marked done (␣ marks the selection)")
		hideDoneButton.action = #selector(hideDoneChanged)

		let controls = NSStackView(
			views: [field, caseButton, wordButton, regexButton, hideDoneButton, statusLabel]
		)
		controls.orientation = .horizontal
		controls.spacing = 6
		controls.alignment = .centerY
		controls.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
		field.setContentHuggingPriority(.defaultLow, for: .horizontal)

		let table = SearchResultsTable()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.selectionHighlightStyle = .regular
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		// The whole feature starts here: without it a selection is one row and
		// "several at once" is not a gesture the table can make.
		table.allowsMultipleSelection = true
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.action = #selector(rowClicked)
		table.doubleAction = #selector(rowClicked)
		table.onKeyDown = { [weak self] event in self?.handleTableKey(event) ?? false }
		table.markUndoManager = { [weak self] in self?.markUndo }
		table.menu = makeRowMenu()
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

	/// The search the ticks belong to. Marks are kept against this and not
	/// against the project, because two searches over the same file are two
	/// different questions and having answered one is not having answered the
	/// other.
	private var question: SearchChecklist.Question {
		SearchChecklist.Question(query: field.stringValue, options: options)
	}

	@objc private func optionsChanged() { scheduleSearch() }

	@objc private func hideDoneChanged() {
		rebuildRows()
		updateStatus()
	}

	private var hidesDone: Bool { hideDoneButton.state == .on }

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
		searchFinished = false
		tableView.reloadData()

		guard !query.isEmpty else {
			statusLabel.stringValue = ""
			searchFinished = true
			return
		}
		guard TextSearch.isValid(query: query, options: options) else {
			statusLabel.stringValue = "Invalid pattern"
			field.textColor = Theme.current.gitConflict
			searchFinished = true
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
				self.updateStatus()
			},
			onFinished: { [weak self] completed, _ in
				guard let self, completed else { return }
				self.searchFinished = true
				self.updateStatus()
			}
		)
	}

	private func updateStatus() {
		let matchCount = results.reduce(0) { $0 + $1.matches.count }
		let fileCount = results.count
		let prefix = searchFinished ? "" : "Searching… "
		guard matchCount > 0 else {
			statusLabel.stringValue = searchFinished ? "No results" : "Searching…"
			return
		}
		var text = "\(prefix)\(matchCount) in \(fileCount) file\(fileCount == 1 ? "" : "s")"
		// The progress, which is the reason the pane keeps marks at all: after an
		// hour the list looked the same as it did at the start, and this is where
		// that stops being true.
		let done = checklist.doneCount(in: results, for: question)
		if done > 0 { text += " · \(done) done" }
		statusLabel.stringValue = text
	}

	private func rebuildRows() {
		let question = self.question
		let hiding = hidesDone
		rows = []
		for result in results {
			let marks = SearchChecklist.marks(for: result)
			let flags = marks.map { checklist.isDone($0, for: question) }
			let doneCount = flags.filter { $0 }.count
			// A heading is done when everything under it is, rather than being
			// marked in its own right: a re-run that turns up one new match in a
			// finished file must bring that file back with the new match under
			// it, and a file marked as a whole could not do that.
			let allDone = doneCount == marks.count && !marks.isEmpty
			if hiding && allDone { continue }

			rows.append(.file(result, done: doneCount, isDone: allDone))
			guard !collapsedFiles.contains(result.relativePath) else { continue }
			for (index, match) in result.matches.enumerated() {
				if hiding && flags[index] { continue }
				rows.append(.match(result, match, marks[index], isDone: flags[index]))
			}
		}
		tableView.reloadData()
	}

	@objc private func rowClicked() {
		let index = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
		guard rows.indices.contains(index) else { return }

		// A click that is building a selection is not a click that opens. ⇧- and
		// ⌘-clicking still send the table's action, so without this every row
		// added to a selection would open a file and take the keyboard into the
		// editor — which is the one thing that must not happen while somebody is
		// picking out rows to tick off.
		if let event = NSApp.currentEvent,
		   !event.modifierFlags.intersection([.shift, .command]).isEmpty { return }
		if tableView.selectedRowIndexes.count > 1 { return }

		switch rows[index] {
		case let .file(result, _, _):
			// Clicking a file header folds it away, which matters once a search
			// returns hundreds of hits.
			if collapsedFiles.contains(result.relativePath) {
				collapsedFiles.remove(result.relativePath)
			} else {
				collapsedFiles.insert(result.relativePath)
			}
			rebuildRows()
		case let .match(result, match, _, _):
			open(result, match)
		}
	}

	/// Counted so a script can tell "the click did not open anything" from "the
	/// click opened something and the picture happens to look the same".
	private var opened: [String] = []

	private func open(_ result: FileSearchResult, _ match: SearchMatch) {
		opened.append("\(result.relativePath):\(match.line + 1)")
		onOpenResult?(result.url, match.line + 1, match)
	}

	// MARK: - Marking done

	/// The marks under a set of rows, in order and without repeats.
	///
	/// A file heading brings every match in the file with it, collapsed or not:
	/// the heading *is* the file, and a selection that took only the rows on
	/// screen would quietly leave a folded file half-ticked.
	private func marks(under indexes: IndexSet) -> [SearchChecklist.Mark] {
		var seen: Set<SearchChecklist.Mark> = []
		var collected: [SearchChecklist.Mark] = []
		for index in indexes where rows.indices.contains(index) {
			switch rows[index] {
			case let .file(result, _, _):
				for mark in SearchChecklist.marks(for: result) where seen.insert(mark).inserted {
					collected.append(mark)
				}
			case let .match(_, _, mark, _):
				if seen.insert(mark).inserted { collected.append(mark) }
			}
		}
		return collected
	}

	/// ␣, and the two menu items. `done` nil means toggle.
	///
	/// A mixed selection where some are already ticked finishes the job rather
	/// than inverting each row: ␣ over a block of rows means "these are dealt
	/// with", and a gesture that left half of them unticked would be one nobody
	/// could use on a run of rows without checking afterwards.
	private func setDone(_ done: Bool?, at indexes: IndexSet) {
		let marks = marks(under: indexes)
		guard !marks.isEmpty else { return }
		let question = self.question
		let allDone = marks.allSatisfy { checklist.isDone($0, for: question) }
		let becoming = done ?? !allDone

		let previous = checklist.set(marks, done: becoming, for: question)
		remember(previous, for: question, named: becoming ? "Mark as Done" : "Mark as Not Done")
		reload(keeping: indexes)
	}

	/// Rebuilds and puts the selection back where the eye expects it.
	///
	/// With the done rows showing, the same indexes still name the same rows, so
	/// the selection stays and ␣ pressed twice is a tick and an untick. With
	/// them hidden the rows have gone, and the cursor lands on whatever moved up
	/// into the first of their places — the next thing to look at.
	private func reload(keeping indexes: IndexSet) {
		let anchor = indexes.first ?? 0
		rebuildRows()
		updateStatus()
		guard !rows.isEmpty else { return }
		let restored = hidesDone
			? IndexSet(integer: min(anchor, rows.count - 1))
			: indexes.filteredIndexSet { $0 < rows.count }
		tableView.selectRowIndexes(restored, byExtendingSelection: false)
		if let first = restored.first { tableView.scrollRowToVisible(first) }
	}

	// MARK: - Undo

	/// ⌘Z over this list, which is ticks and never files.
	///
	/// Its own manager rather than the window's, for the reason the tree keeps
	/// its own: `undo:` is sent from the Edit menu at nobody in particular and
	/// AppKit stops at the first responder that answers it, so a stack per pane
	/// is what stops a ⌘Z aimed at a stray character from unticking a hundred
	/// rows. This is the same shape as `ProjectNavigatorViewController`'s file
	/// undo and deliberately not a second private mechanism.
	///
	/// Unlike the tree's, this one does have a redo. The tree has none because
	/// redoing a copy means keeping the source it came from, which is a promise
	/// it cannot make; here nothing was destroyed in either direction, so
	/// registering the inverse from inside the handler is free and ⇧⌘Z puts the
	/// ticks back.
	private let markUndo = UndoManager()

	/// What the manager holds instead of the pane. `registerUndo` keeps its
	/// target alive, and a pane that outlived its window would take the whole
	/// result list with it.
	private lazy var undoTarget: SearchUndoTarget = {
		let target = SearchUndoTarget()
		target.pane = self
		return target
	}()

	private func remember(
		_ previous: Set<SearchChecklist.Mark>,
		for question: SearchChecklist.Question,
		named name: String
	) {
		markUndo.registerUndo(withTarget: undoTarget) { target in
			target.pane?.takeBack(previous, for: question, named: name)
		}
		markUndo.setActionName(name)
	}

	private func takeBack(
		_ previous: Set<SearchChecklist.Mark>,
		for question: SearchChecklist.Question,
		named name: String
	) {
		let current = checklist.marks(for: question)
		checklist.restore(previous, for: question)
		// Registering while undoing is what makes this a redo, which the manager
		// works out for itself from the state it is in.
		markUndo.registerUndo(withTarget: undoTarget) { target in
			target.pane?.takeBack(current, for: question, named: name)
		}
		markUndo.setActionName(name)
		rebuildRows()
		updateStatus()
	}

	// MARK: - Keyboard

	/// Returns true when the event was consumed.
	private func handleTableKey(_ event: NSEvent) -> Bool {
		switch event.keyCode {
		case 49 where event.modifierFlags.intersection([.command, .option, .control]).isEmpty:
			setDone(nil, at: tableView.selectedRowIndexes)
			return true
		// ⏎ shows what is selected and gives the keyboard straight back, so the
		// whole pass can be done from the keyboard: ↓ into the list, ⏎ to look,
		// ␣ to tick, ↓ to the next one.
		//
		// Opening a result normally takes the keyboard into the editor, which is
		// right for a click — somebody who clicked a line of code means to be in
		// it. It is wrong for the key in the middle of a checklist: the next ␣
		// would type a space into the file. So the responder is put back, one
		// turn of the run loop later because the editor moves it while opening.
		// A click and a double-click are unchanged and still hand over.
		case 36:
			for index in tableView.selectedRowIndexes where rows.indices.contains(index) {
				if case let .match(result, match, _, _) = rows[index] {
					open(result, match)
					DispatchQueue.main.async { [weak self] in
						guard let self else { return }
						self.window?.makeFirstResponder(self.tableView)
					}
					return true
				}
			}
			return false
		default:
			return false
		}
	}

	// MARK: - The row menu

	private func makeRowMenu() -> NSMenu {
		let menu = NSMenu()
		// Spelled out in both directions rather than one item whose title
		// changes: a menu that reads "Mark as Done" over a selection that is
		// already done is a menu that has to be read twice.
		menu.addItem(withTitle: "Mark as Done", action: #selector(markSelectionDone), keyEquivalent: "")
		menu.addItem(
			withTitle: "Mark as Not Done", action: #selector(markSelectionNotDone), keyEquivalent: ""
		)
		menu.addItem(.separator())
		menu.addItem(
			withTitle: "Hide Rows Marked Done", action: #selector(toggleHideDone), keyEquivalent: ""
		)
		for item in menu.items { item.target = self }
		return menu
	}

	@objc private func markSelectionDone() { setDone(true, at: tableView.selectedRowIndexes) }
	@objc private func markSelectionNotDone() { setDone(false, at: tableView.selectedRowIndexes) }

	@objc private func toggleHideDone() {
		hideDoneButton.state = hidesDone ? .off : .on
		hideDoneChanged()
	}

	// MARK: - Driving it from a script

	/// One step of `--search-steps`, so the pane can be worked from the command
	/// line. Nothing in the window layer has a test, so this is how a claim
	/// about it gets checked at all.
	func stepForTesting(_ step: String) {
		switch step {
		case "focus": window?.makeFirstResponder(tableView)
		case "field": focusField()
		case "who": print("SEARCH who: \(String(describing: window?.firstResponder.map { type(of: $0) }))")
		// ↓ out of the field, sent through the window so the field editor gets it
		// the way a press does: it is the delegate call underneath that turns it
		// into a move into the list, and calling that directly would be checking
		// the wrong half.
		case "field-down":
			if let event = NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window?.windowNumber ?? 0, context: nil,
				characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
				isARepeat: false, keyCode: 125
			) {
				window?.sendEvent(event)
			}
		case "down": moveSelection(by: 1, extending: false)
		case "up": moveSelection(by: -1, extending: false)
		case "shift-down": moveSelection(by: 1, extending: true)
		case "shift-up": moveSelection(by: -1, extending: true)
		// The key itself rather than the method under it, because the claim is
		// about `handleTableKey`: ␣ has to reach the table at all, and ⌫ and ⌘⌫
		// have to reach it and be ignored. The second is the whole hazard — the
		// same key one pane over moves a file to the trash — and it can only be
		// checked by pressing it.
		case "space-key": pressForTesting(49)
		case "delete-key": pressForTesting(51)
		case "cmd-delete-key": pressForTesting(51, modifiers: .command)
		case "return-key": pressForTesting(36)
		case "space": setDone(nil, at: tableView.selectedRowIndexes)
		case "hide": toggleHideDone()
		case "rerun": runSearch()
		case "undo": markUndo.undo()
		case "redo": markUndo.redo()
		case "status":
			print("SEARCH status: \(statusLabel.stringValue) "
				+ "undo=\(markUndo.canUndo ? markUndo.undoActionName : "—") "
				+ "redo=\(markUndo.canRedo ? markUndo.redoActionName : "—") "
				+ "opened=[\(opened.joined(separator: " "))]")
		case "rows":
			print("SEARCH rows: \(rows.count)")
			for (index, row) in rows.enumerated() {
				let selected = tableView.selectedRowIndexes.contains(index) ? "*" : " "
				switch row {
				case let .file(result, done, isDone):
					print("  \(selected)\(index) file \(result.relativePath) "
						+ "\(done)/\(result.matches.count)\(isDone ? " DONE" : "")")
				case let .match(_, match, _, isDone):
					print("  \(selected)\(index) match \(match.line + 1) "
						+ "\(match.lineText.trimmingCharacters(in: .whitespaces))"
						+ "\(isDone ? " DONE" : "")")
				}
			}
		default:
			if step.hasPrefix("select:") {
				let wanted = step.dropFirst("select:".count).split(separator: "+").compactMap { Int($0) }
				tableView.selectRowIndexes(IndexSet(wanted), byExtendingSelection: false)
			}
			// `click:4` and `shift-click:4`, as the pointer sends them. The
			// modifier is the point: a ⇧-click extends the selection and must not
			// also open a file, and that is decided by `NSApp.currentEvent`, which
			// only a real event sets.
			if step.hasPrefix("click:") {
				clickForTesting(Int(step.dropFirst("click:".count)) ?? -1, modifiers: [])
			}
			if step.hasPrefix("shift-click:") {
				clickForTesting(Int(step.dropFirst("shift-click:".count)) ?? -1, modifiers: .shift)
			}
		}
	}

	/// A click on a row, posted rather than sent.
	///
	/// `NSTableView.mouseDown` runs its own tracking loop and pulls the mouse-up
	/// out of the event queue itself, so handing it the two events directly
	/// deadlocks — the loop waits for an event that is already on the stack
	/// below it. Posted, they arrive the way the window server delivers them,
	/// which is also what sets `NSApp.currentEvent` for the action that follows.
	private func clickForTesting(_ row: Int, modifiers: NSEvent.ModifierFlags) {
		guard rows.indices.contains(row), let window else { return }
		let rect = tableView.rect(ofRow: row)
		let inWindow = tableView.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
		for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
			guard let event = NSEvent.mouseEvent(
				with: type, location: inWindow, modifierFlags: modifiers,
				timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
				context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
			) else { continue }
			NSApp.postEvent(event, atStart: false)
		}
	}

	/// A keystroke put through the table's own `keyDown`, so what is exercised is
	/// the path a real press takes.
	private func pressForTesting(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
		guard let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: modifiers,
			timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window?.windowNumber ?? 0,
			context: nil, characters: "", charactersIgnoringModifiers: "",
			isARepeat: false, keyCode: keyCode
		) else { return }
		tableView.keyDown(with: event)
	}

	private func moveSelection(by delta: Int, extending: Bool) {
		guard !rows.isEmpty else { return }
		let from = delta > 0
			? (tableView.selectedRowIndexes.last ?? -1)
			: (tableView.selectedRowIndexes.first ?? rows.count)
		let next = max(0, min(rows.count - 1, from + delta))
		tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: extending)
		tableView.scrollRowToVisible(next)
	}
}

/// Which of the two marking items can do anything to what is selected.
///
/// `NSView` is not an `NSMenuItemValidation` on its own, and the menu's items
/// target this view — so without the conformance both items would always be
/// live, including "Mark as Not Done" over a selection nobody has touched.
extension SearchPane: NSMenuItemValidation {
	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		let selected = marks(under: tableView.selectedRowIndexes)
		let question = self.question
		switch item.action {
		case #selector(markSelectionDone):
			return selected.contains { !checklist.isDone($0, for: question) }
		case #selector(markSelectionNotDone):
			return selected.contains { checklist.isDone($0, for: question) }
		case #selector(toggleHideDone):
			item.state = hidesDone ? .on : .off
			return true
		default:
			return true
		}
	}
}

extension SearchPane: NSSearchFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		scheduleSearch()
	}

	/// ↓ out of the field and into the list.
	///
	/// Without it the results can only be reached with the mouse, and a
	/// checklist worked with ␣ that needs a click to get to is not one.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		guard selector == #selector(NSResponder.moveDown(_:)), !rows.isEmpty else { return false }
		window?.makeFirstResponder(tableView)
		if tableView.selectedRow < 0 {
			tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		}
		return true
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
		case let .file(result, done, isDone):
			return SearchFileCell(
				result: result,
				isCollapsed: collapsedFiles.contains(result.relativePath),
				done: done,
				isDone: isDone
			)
		case let .match(_, match, _, isDone):
			return SearchMatchCell(match: match, isDone: isDone)
		}
	}
}

/// What the pane's undo manager holds instead of the pane, for the reason
/// `FileUndoTarget` exists: a registered undo keeps its target alive.
private final class SearchUndoTarget {
	weak var pane: SearchPane?
}

/// The results table, which answers ⌘Z for the ticks and hands its keys to the
/// pane first.
///
/// `undo:` is answered here and not through an `undoManager` override, exactly
/// as `NavigatorOutlineView` does it: the property would hand this stack to any
/// field editor that came asking, and the two stacks would become one.
///
/// ⌫ and ⌘⌫ are not answered and are not bound. In the tree ⌘⌫ moves the
/// selection to the trash, and the two panes look alike enough that a
/// half-remembered key must do nothing here rather than something.
private final class SearchResultsTable: NSTableView {
	var onKeyDown: ((NSEvent) -> Bool)?
	var markUndoManager: (() -> UndoManager?)?

	override var acceptsFirstResponder: Bool { true }

	@objc func undo(_ sender: Any?) { markUndoManager?()?.undo() }
	@objc func redo(_ sender: Any?) { markUndoManager?()?.redo() }

	override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		// Greyed out over an empty stack rather than swallowing the key: an Undo
		// that is enabled and does nothing is the same lie as one that undoes the
		// wrong thing, only quieter.
		if item.action == #selector(undo(_:)) { return markUndoManager?()?.canUndo ?? false }
		if item.action == #selector(redo(_:)) { return markUndoManager?()?.canRedo ?? false }
		return super.validateUserInterfaceItem(item)
	}

	/// A right-click outside the selection takes the row under the pointer.
	///
	/// The standard table behaviour, and the one that matters here: without it
	/// the menu would act on whatever happened to be selected somewhere else in
	/// the list, which for a gesture that ticks a hundred rows at once is a
	/// surprise nobody wants.
	override func menu(for event: NSEvent) -> NSMenu? {
		let point = convert(event.locationInWindow, from: nil)
		let clicked = row(at: point)
		if clicked >= 0, !selectedRowIndexes.contains(clicked) {
			selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
		}
		return super.menu(for: event)
	}

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
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
	private let done: Int
	private let isDone: Bool

	init(result: FileSearchResult, isCollapsed: Bool, done: Int, isDone: Bool) {
		self.result = result
		self.isCollapsed = isCollapsed
		self.done = done
		self.isDone = isDone
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

		var nameAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(12, weight: .medium),
			.foregroundColor: isDone ? Theme.current.gitIgnored : Theme.current.sidebarHeaderText,
		]
		if isDone { nameAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
		let nameString = NSAttributedString(string: name, attributes: nameAttributes)
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

		// The right-hand end of a row is where its state lives, on headings and
		// on matches alike: a tick when the whole file is done, "2/5" while it is
		// part way, the plain count when none of it has been looked at.
		var right = bounds.width - Theme.current.scaled(12)
		if isDone, let tick = Theme.symbol(
			"checkmark", size: 10 * Theme.current.scale, color: Theme.current.gitAdded
		) {
			let size = Theme.current.scaled(11)
			right -= size
			tick.drawFitted(in: NSRect(x: right, y: bounds.midY - size / 2, width: size, height: size))
			right -= Theme.current.scaled(5)
		}

		let count = NSAttributedString(
			string: done > 0 && !isDone ? "\(done)/\(result.matches.count)" : "\(result.matches.count)",
			attributes: [
				.font: Theme.current.uiFont(10.5),
				.foregroundColor: Theme.current.gitIgnored,
			]
		)
		count.draw(at: NSPoint(
			x: right - count.size().width,
			y: bounds.midY - count.size().height / 2
		))
	}
}

private final class SearchMatchCell: NSView {
	private let match: SearchMatch
	private let isDone: Bool

	init(match: SearchMatch, isDone: Bool) {
		self.match = match
		self.isDone = isDone
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

		var right = bounds.width - Theme.current.scaled(12)
		// The tick, in the same column the file heading's goes in, so a done row
		// is legible without reading the line: struck-through text alone is easy
		// to miss in a monospaced font at eleven points.
		if isDone, let tick = Theme.symbol(
			"checkmark", size: 10 * Theme.current.scale, color: Theme.current.gitAdded
		) {
			let size = Theme.current.scaled(11)
			right -= size
			tick.drawFitted(in: NSRect(x: right, y: bounds.midY - size / 2, width: size, height: size))
			right -= Theme.current.scaled(4)
		}

		// Leading whitespace is trimmed so deeply indented code stays readable in
		// a narrow panel.
		let trimmed = match.lineText.drop { $0 == " " || $0 == "\t" }
		var attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.terminalFont(size: Theme.current.uiFont(11).pointSize),
			.foregroundColor: isDone
				? Theme.current.gitIgnored
				: (isSelected ? NSColor.hex(0xE8EAED) : Theme.current.editorText),
		]
		if isDone { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
		let text = NSAttributedString(string: String(trimmed), attributes: attributes)
		text.draw(in: NSRect(
			x: x,
			y: bounds.midY - text.size().height / 2,
			width: max(0, right - x),
			height: text.size().height
		))
	}
}

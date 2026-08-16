import AppKit
import AbydosKit

/// Project-wide search results (⇧⌘F).
///
/// Results stream in as the walk proceeds rather than appearing all at once, so
/// the first hits are usable immediately on a large tree.
///
/// The list itself is a `ResultChecklist` and is not written here: the ticking,
/// the undo, the file headings and the key handling are shared with the usages
/// pane, which is the same job over a different question. This pane is the query
/// field, the three options, the `✓` toggle and the status line — everything that
/// is about *what is in* the list rather than about working through it.
final class SearchPane: NSView, ResultsPane {
	var onOpenResult: ((URL, Int, SearchMatch, ResultChecklist.Intent) -> Void)?
	/// Asked to move to one of the four homes. Search goes wherever usages
	/// goes: item 506's third decision, and the reason is in `ResultsPane`.
	var onPlace: ((ResultPlacement) -> Void)?

	private let search: ProjectSearch
	private let projectRoot: URL
	private var searchFinished = true

	private var field: NSSearchField!
	private var statusLabel: NSTextField!
	private var caseButton: NSButton!
	private var wordButton: NSButton!
	private var regexButton: NSButton!
	private var hideDoneButton: NSButton!
	private var placeControl: PlacementControl!
	private let list = ResultChecklist()
	private var debounce: DispatchWorkItem?

	/// Where the pane is showing.
	private(set) var placement: ResultPlacement = .panel

	func setPlacement(_ placement: ResultPlacement) {
		self.placement = placement
		placeControl.setPlacement(placement)
	}

	/// What its tab and its window are called. Search has one name however many
	/// questions have been asked in it, which is the difference from usages —
	/// there the symbol is the subject and here the query is being refined.
	var paneTitle: String { "Search" }

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

		placeControl = PlacementControl()
		placeControl.onChoose = { [weak self] home in self?.onPlace?(home) }

		queryRow = NSStackView(views: [field])
		queryRow.orientation = .horizontal
		queryRow.spacing = 6
		queryRow.alignment = .centerY
		queryRow.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

		optionRow = NSStackView(views: [])
		optionRow.orientation = .horizontal
		optionRow.spacing = 6
		optionRow.alignment = .centerY
		optionRow.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

		let controls = NSStackView(views: [queryRow, optionRow])
		controls.orientation = .vertical
		controls.spacing = 4
		controls.alignment = .leading
		controls.distribution = .fillEqually
		field.setContentHuggingPriority(.defaultLow, for: .horizontal)
		// The rows are as wide as the pane, whichever of them is showing.
		for row in [queryRow!, optionRow!] {
			row.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
		}

		// Search shows a result when it is asked to — ⏎ or a click — and not as
		// the selection moves. Walking a project-wide search with ↓ crosses files
		// nobody asked about, and the query is usually being refined rather than
		// worked through row by row.
		list.opensOnSelectionChange = false
		list.logPrefix = "SEARCH"
		list.onOpen = { [weak self] result, match, intent in
			self?.onOpenResult?(result.url, match.line + 1, match, intent)
		}
		list.onProgressChanged = { [weak self] in self?.updateStatus() }
		list.onHideDoneChanged = { [weak self] in
			guard let self else { return }
			self.hideDoneButton.state = self.list.hidesDone ? .on : .off
		}

		addSubview(controls)
		addSubview(list)
		controls.translatesAutoresizingMaskIntoConstraints = false
		list.translatesAutoresizingMaskIntoConstraints = false

		controlsHeight = controls.heightAnchor.constraint(equalToConstant: Theme.current.scaled(34))
		NSLayoutConstraint.activate([
			controls.topAnchor.constraint(equalTo: topAnchor),
			controls.leadingAnchor.constraint(equalTo: leadingAnchor),
			controls.trailingAnchor.constraint(equalTo: trailingAnchor),
			controlsHeight,

			list.topAnchor.constraint(equalTo: controls.bottomAnchor),
			list.leadingAnchor.constraint(equalTo: leadingAnchor),
			list.trailingAnchor.constraint(equalTo: trailingAnchor),
			list.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	private var controlsHeight: NSLayoutConstraint!
	private var queryRow: NSStackView!
	private var optionRow: NSStackView!
	/// Whether the controls are on two rows because one will not fit.
	private var isNarrow: Bool?

	/// Where the query field, the three options, the `✓`, the status line and
	/// the Place control go.
	///
	/// One row while there is room, which is what the panel and a window have,
	/// and two when there is not — which is what the sidebar has. Item 506 found
	/// this the hard way: the very first search list put under the project view
	/// had its query field squeezed to the width of the magnifying glass, with
	/// the toggles sitting on top of it. A results list that cannot be re-asked
	/// is not the same list somewhere else.
	///
	/// The threshold is a width rather than a home. The sidebar is the narrow
	/// one today, but a panel dragged down to a third of the window is the same
	/// shape, and asking "which home am I in" would be right about the sidebar
	/// and wrong about that.
	private func arrangeControls(narrow: Bool) {
		guard narrow != isNarrow else { return }
		isNarrow = narrow

		let options: [NSView] = [
			caseButton, wordButton, regexButton, hideDoneButton, statusLabel, placeControl,
		]
		let wanted = narrow ? optionRow! : queryRow!
		for view in options {
			guard view.superview !== wanted else { continue }
			(view.superview as? NSStackView)?.removeArrangedSubview(view)
			view.removeFromSuperview()
			wanted.addArrangedSubview(view)
		}
		optionRow.isHidden = !narrow
		controlsHeight.constant = Theme.current.scaled(narrow ? 62 : 34)
	}

	override func layout() {
		super.layout()
		arrangeControls(narrow: bounds.width < Theme.current.scaled(460))
	}

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
		list.setHidesDone(hideDoneButton.state == .on)
		updateStatus()
	}

	func focusField() {
		window?.makeFirstResponder(field)
		field.currentEditor()?.selectAll(nil)
	}

	/// The keyboard, in the list rather than in the field.
	///
	/// A move puts it here rather than in the field: the pane has just been
	/// picked up and put down with rows already in it, and the rows are what
	/// somebody is looking at. Asking for search in the first place still lands
	/// in the field, which is where a question is typed.
	func focusList() { list.focusList() }

	func setQuery(_ text: String) {
		field.stringValue = text
		scheduleSearch()
	}

	func applySettings() {
		controlsHeight.constant = Theme.current.scaled(isNarrow == true ? 62 : 34)
		field.font = Theme.current.uiFont(12)
		statusLabel.font = Theme.current.uiFont(11)
		placeControl.applySettings()
		list.applySettings()
	}

	// MARK: - Searching

	private func scheduleSearch() {
		debounce?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.runSearch() }
		debounce = work
		// Longer than the in-file debounce: this walks the whole tree.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
	}

	private var results: [FileSearchResult] = []

	private func runSearch() {
		let query = field.stringValue
		results = []
		searchFinished = false
		list.question = question
		list.setResults([])

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
				self.list.setResults(self.results)
			},
			onFinished: { [weak self] completed, _ in
				guard let self, completed else { return }
				self.searchFinished = true
				self.updateStatus()
			}
		)
	}

	private func updateStatus() {
		let matchCount = list.matchCount
		let fileCount = list.results.count
		let prefix = searchFinished ? "" : "Searching… "
		guard matchCount > 0 else {
			statusLabel.stringValue = searchFinished ? "No results" : "Searching…"
			return
		}
		var text = "\(prefix)\(matchCount) in \(fileCount) file\(fileCount == 1 ? "" : "s")"
		// The progress, which is the reason the pane keeps marks at all: after an
		// hour the list looked the same as it did at the start, and this is where
		// that stops being true.
		let done = list.doneCount
		if done > 0 { text += " · \(done) done" }
		statusLabel.stringValue = text
	}

	// MARK: - Driving it from a script

	/// One step of `--search-steps`, so the pane can be worked from the command
	/// line. Nothing in the window layer has a test, so this is how a claim
	/// about it gets checked at all. Anything about the list itself is the list's
	/// step; what is left here is the field, the search and the status line.
	func stepForTesting(_ step: String) {
		switch step {
		case "field": focusField()
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
		case "rerun": runSearch()
		case "list": focusList()
		case "status":
			print("SEARCH status: \(statusLabel.stringValue) "
				+ "where=\(placement.rawValue) "
				+ list.undoStateForTesting
				+ " opened=[\(list.openedForTesting.joined(separator: " "))]")
			fflush(stdout)
		default:
			if step.hasPrefix("place:"),
			   let home = ResultPlacement(rawValue: String(step.dropFirst("place:".count))) {
				onPlace?(home)
				return
			}
			// The control itself rather than the callback under it.
			if step.hasPrefix("menu:"),
			   let home = ResultPlacement(rawValue: String(step.dropFirst("menu:".count))) {
				print("SEARCH menu: \(placeControl.chooseForTesting(home))")
				fflush(stdout)
				return
			}
			if step.hasPrefix("window-key:") {
				pressAtWindowForTesting(String(step.dropFirst("window-key:".count)))
				return
			}
			// A different term is a different question, and the marks under the
			// old one must not follow: `query:return` over a list ticked under
			// `needle` is the check that they do not.
			if step.hasPrefix("query:") {
				setQuery(String(step.dropFirst("query:".count)))
				return
			}
			list.stepForTesting(step)
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
		guard selector == #selector(NSResponder.moveDown(_:)) else { return false }
		return list.takeKeyboardFromAbove()
	}
}

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
final class SearchPane: NSView {
	var onOpenResult: ((URL, Int, SearchMatch, ResultChecklist.Intent) -> Void)?

	private let search: ProjectSearch
	private let projectRoot: URL
	private var searchFinished = true

	private var field: NSSearchField!
	private var statusLabel: NSTextField!
	private var caseButton: NSButton!
	private var wordButton: NSButton!
	private var regexButton: NSButton!
	private var hideDoneButton: NSButton!
	private let list = ResultChecklist()
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

	func setQuery(_ text: String) {
		field.stringValue = text
		scheduleSearch()
	}

	func applySettings() {
		controlsHeight.constant = Theme.current.scaled(34)
		field.font = Theme.current.uiFont(12)
		statusLabel.font = Theme.current.uiFont(11)
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
		case "status":
			print("SEARCH status: \(statusLabel.stringValue) "
				+ list.undoStateForTesting
				+ " opened=[\(list.openedForTesting.joined(separator: " "))]")
		default:
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

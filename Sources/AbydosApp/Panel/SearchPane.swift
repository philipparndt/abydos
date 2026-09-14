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
///
/// And, since the pane learnt to replace, the replace half: a field for what
/// the matches should become, a Replace for the rows that are selected and a
/// Replace All for every row showing. What a replacement *is* — one edit per
/// file, made against the file as it is now and keyed on the marks the ticks
/// already use — is `ProjectReplace` in `AbydosKit`, where it has a test. What
/// is here is which rows, which files are open, and the one ⌘Z.
final class SearchPane: NSView, ResultsPane {
	var onOpenResult: ((URL, Int, SearchMatch, ResultChecklist.Intent) -> Void)?
	/// Asked to move to one of the four homes. Search goes wherever usages
	/// goes: item 506's third decision, and the reason is in `ResultsPane`.
	var onPlace: ((ResultPlacement) -> Void)?

	/// **Not `let`.** The pane is made once and cached for the life of the
	/// window — under the panel, under the project view, or in a window of its
	/// own — so a root bound at birth meant a window that had moved to another
	/// project went on searching the one it left. A stale board shows work that
	/// is not yours; a stale search *opens files in a tree you are not in*.
	private var search: ProjectSearch
	private var projectRoot: URL
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

	// The replace half.
	private var replaceField: NSTextField!
	private var replaceButton: NSButton!
	private var replaceAllButton: NSButton!
	private var replaceToggle: NSButton!
	private var replaceRow: NSStackView!
	/// Whether the replace half is showing. The pane's, one per window like
	/// the query, and it survives a project switch with it.
	private(set) var isReplacing = false

	/// One edit into a file that is open in the editor, wherever it is open.
	///
	/// Handed a function of the text rather than an edit, because only the
	/// editor has the buffer: the edit is made against the document's text as
	/// it is now, a dirty tab's included. Answers how many open copies there
	/// were — none means the file belongs to the disk and is written there.
	var editOpenFile: ((URL, (String) -> TextSearch.ReplaceAll?) -> Int)?

	/// What the last replacement came to, leading the status line until the
	/// question changes: `143 replaced in 27 files`. The re-run that follows a
	/// replacement would otherwise overwrite the only record of what happened
	/// with `No results`.
	private var replacementStatus: String?

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

	/// Searches another project, without being closed and reopened.
	///
	/// **Results go, the query stays.** A result is a path into the tree the
	/// window has left, and one left on screen still opens — which is the whole
	/// reason this matters more than a stale board does. The query is a person's
	/// words: it costs nothing to ask again and is the thing they would type.
	func setProject(_ root: URL) {
		guard root.standardizedFileURL != projectRoot.standardizedFileURL else { return }
		projectRoot = root
		search = ProjectSearch(root: root)

		debounce?.cancel()
		list.setResults([])
		wasCapped = false
		searchFinished = true
		statusLabel.stringValue = ""
	}

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
		// Nor this one: it shows the replace half and changes nothing found.
		replaceToggle = makeToggle("⇄", "Replace in the project (⇧⌘R)")
		replaceToggle.action = #selector(replaceToggleChanged)

		// The replacement, under the query rather than beside it, as the find
		// bar has it: the two fields line up at the same edge, which is what
		// makes the second read as the answer to the first.
		replaceField = NSTextField()
		replaceField.placeholderString = "Replace with"
		replaceField.font = Theme.current.uiFont(12)
		replaceField.focusRingType = .none
		replaceField.delegate = self

		replaceButton = makePush("Replace", "Replace the selected rows (⏎)", #selector(replacePressed))
		replaceAllButton = makePush(
			"Replace All", "Replace every row showing, as one edit per file", #selector(replaceAllPressed)
		)

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

		replaceRow = NSStackView(views: [replaceField, replaceButton, replaceAllButton])
		replaceRow.orientation = .horizontal
		replaceRow.spacing = 6
		replaceRow.alignment = .centerY
		replaceRow.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
		replaceRow.isHidden = true

		let controls = NSStackView(views: [queryRow, optionRow, replaceRow])
		controls.orientation = .vertical
		controls.spacing = 4
		controls.alignment = .leading
		controls.distribution = .fillEqually
		field.setContentHuggingPriority(.defaultLow, for: .horizontal)
		replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		// The rows are as wide as the pane, whichever of them is showing.
		for row in [queryRow!, optionRow!, replaceRow!] {
			row.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
		}

		// The same as the usages list, since item 529: ↓ through the results shows
		// each one. The two are one widget and answering ↓ differently in them was
		// the surprise — what a walk crosses is bounded to the rows it stops on
		// here exactly as it is there, and a held key opens the row it stops on.
		list.opensOnSelectionChange = true
		list.logPrefix = "SEARCH"
		list.onOpen = { [weak self] result, match, intent in
			self?.onOpenResult?(result.url, match.line + 1, match, intent)
		}
		list.onProgressChanged = { [weak self] in self?.updateStatus() }
		list.onSelectionChanged = { [weak self] in self?.updateReplaceControls() }
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
			caseButton, wordButton, regexButton, hideDoneButton, replaceToggle, statusLabel, placeControl,
		]
		let wanted = narrow ? optionRow! : queryRow!
		for view in options {
			guard view.superview !== wanted else { continue }
			(view.superview as? NSStackView)?.removeArrangedSubview(view)
			view.removeFromSuperview()
			wanted.addArrangedSubview(view)
		}
		optionRow.isHidden = !narrow
		controlsHeight.constant = wantedControlsHeight
	}

	/// One row of 34, and 28 for each further row showing: the options when
	/// the pane is narrow, the replacement when the pane is replacing.
	private var wantedControlsHeight: CGFloat {
		Theme.current.scaled(34 + (isNarrow == true ? 28 : 0) + (isReplacing ? 28 : 0))
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

	private func makePush(_ title: String, _ tooltip: String, _ action: Selector) -> NSButton {
		let button = NSButton(title: title, target: self, action: action)
		button.bezelStyle = .rounded
		button.controlSize = .small
		button.font = Theme.current.uiFont(11)
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

	@objc private func optionsChanged() {
		// A switch changes what the term means, so the question is a new one and
		// what the last replacement did is no longer about it.
		replacementStatus = nil
		scheduleSearch()
	}

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
		replacementStatus = nil
		scheduleSearch()
	}

	func applySettings() {
		controlsHeight.constant = wantedControlsHeight
		field.font = Theme.current.uiFont(12)
		replaceField.font = Theme.current.uiFont(12)
		statusLabel.font = Theme.current.uiFont(11)
		for button in [replaceButton!, replaceAllButton!] { button.font = Theme.current.uiFont(11) }
		placeControl.applySettings()
		list.applySettings()
	}

	// MARK: - Replacing

	/// Shows or hides the replace half. Nothing found is touched either way.
	func setReplacing(_ replacing: Bool) {
		guard replacing != isReplacing else { return }
		isReplacing = replacing
		replaceRow.isHidden = !replacing
		replaceToggle.state = replacing ? .on : .off
		controlsHeight.constant = wantedControlsHeight
		updateReplaceControls()
		updateStatus()
	}

	func focusReplaceField() {
		window?.makeFirstResponder(replaceField)
		replaceField.currentEditor()?.selectAll(nil)
	}

	var replacement: String { replaceField.stringValue }

	func setReplacement(_ text: String) {
		replaceField.stringValue = text
		updateReplaceControls()
		updateStatus()
	}

	@objc private func replaceToggleChanged() {
		setReplacing(replaceToggle.state == .on)
		if isReplacing { focusReplaceField() }
	}

	@objc private func replacePressed() { replace(list.selectedMarks) }

	@objc private func replaceAllPressed() {
		// The list as a prefix of the project is not a list to replace all of:
		// a replacement that stopped part-way through the project with nothing
		// said is the failure the in-file Replace All was written to avoid, and
		// the button is disabled for it — this guard is for a driven run, which
		// calls the verb rather than the button.
		guard searchFinished, !capped else { return }
		replace(list.showingMarks)
	}

	/// Whether the replacement can be used with the pattern beside it.
	///
	/// The same question the find bar asks, for the same reason: Foundation
	/// substitutes the empty string for a group the pattern does not have, so
	/// `$7` against two captures would delete every chosen match rather than
	/// refuse. Asked again whenever the query, the switches or the replacement
	/// change, because it is a question about both.
	private var isTemplateValid: Bool {
		!isReplacing
			|| TextSearch.isValid(template: replaceField.stringValue, query: field.stringValue, options: options)
	}

	/// Which of the two buttons can do anything right now.
	///
	/// Replace needs rows selected; Replace All needs a list that is whole and
	/// finished. Both need a template the pattern can use.
	private func updateReplaceControls() {
		guard isReplacing else { return }
		let usable = isTemplateValid && !field.stringValue.isEmpty
		replaceButton.isEnabled = usable && list.hasSelection
		replaceAllButton.isEnabled = usable && searchFinished && !capped && list.matchCount > 0
	}

	/// The replacement: every chosen mark, grouped by file, one edit per file.
	///
	/// An open file is edited through the editor so the tab is dirty and its
	/// own ⌘Z works; a closed one is read again, edited and written back
	/// atomically. Either way the edit is made against the text as it is *now*
	/// and the rows are found in it by their marks, so a row whose line has
	/// gone replaces nothing and is counted rather than replacing whatever now
	/// sits at its old offset. Then one entry on the list's ⌘Z holding every
	/// span, and the search run again so the replaced rows leave.
	private func replace(_ marks: [SearchChecklist.Mark]) {
		guard isReplacing, isTemplateValid, !marks.isEmpty else { return }
		let template = replaceField.stringValue
		let question = self.question
		let chosen = Set(marks)
		let wantedPaths = Set(marks.map(\.path))

		var record = ProjectReplace.Record()
		StallWatch.mark("project replace") {
			for result in list.fileResults where wantedPaths.contains(result.relativePath) {
				let path = result.relativePath
				var span: ProjectReplace.Record.File?
				var notFound = 0
				var replaced = 0
				let makeEdit: (String) -> TextSearch.ReplaceAll? = { text in
					let outcome = ProjectReplace.edit(
						in: text, path: path, question: question, template: template, choosing: chosen
					)
					notFound = outcome.notFound.count
					guard let edit = outcome.edit else { return nil }
					let before = (text as NSString).substring(
						with: NSRange(location: edit.utf16Range.lowerBound, length: edit.utf16Range.count)
					)
					span = ProjectReplace.Record.File(
						url: result.url, relativePath: path, start: edit.utf16Range.lowerBound,
						before: before, after: edit.text, wasOpen: true
					)
					replaced = edit.count
					return edit
				}

				let open = editOpenFile?(result.url, makeEdit) ?? 0
				if open == 0 {
					// Not open anywhere: the disk is the truth, by the same tests the
					// search reads it with.
					guard let text = ProjectReplace.readText(at: result.url) else { continue }
					if let edit = makeEdit(text) {
						do {
							try ProjectReplace.write(ProjectReplace.applying(edit, to: text), to: result.url)
							span = span.map {
								ProjectReplace.Record.File(
									url: $0.url, relativePath: $0.relativePath, start: $0.start,
									before: $0.before, after: $0.after, wasOpen: false
								)
							}
						} catch {
							// A file that could not be written is a file where nothing
							// was replaced, and it is counted with the rows not found.
							span = nil
							notFound += replaced
							replaced = 0
						}
					}
				}
				if let span { record.files.append(span) }
				record.replaced += replaced
				record.notFound += notFound
			}
		}

		guard record.replaced > 0 || record.notFound > 0 else { return }
		if !record.files.isEmpty {
			list.registerUndo(named: "Replace in Project") { [weak self] in
				self?.revert(record, forward: false)
			}
		}
		// `0 replaced in 0 files` is what a run of stale rows came to, and the
		// second number says nothing the first did not.
		replacementStatus = (record.files.isEmpty
			? "0 replaced"
			: "\(record.replaced) replaced in \(Self.files(record.fileCount))")
			+ (record.notFound > 0 ? " · \(record.notFound) not found" : "")
		runSearch()
	}

	/// ⌘Z over a replacement, and ⇧⌘Z back again.
	///
	/// Each span goes back only where it still reads what the replacement left
	/// — the file has otherwise been changed since, and a blind write would take
	/// somebody's edit with it. What was skipped is said. The inverse is
	/// registered from inside the handler, which is what makes it a redo.
	private func revert(_ record: ProjectReplace.Record, forward: Bool) {
		var skipped = 0
		StallWatch.mark("project replace undo") {
			for file in record.files {
				var applied = false
				let makeEdit: (String) -> TextSearch.ReplaceAll? = { text in
					let edit = ProjectReplace.reversal(of: file, in: text, forward: forward)
					if edit != nil { applied = true }
					return edit
				}
				let open = editOpenFile?(file.url, makeEdit) ?? 0
				if open == 0 {
					if let text = ProjectReplace.readText(at: file.url), let edit = makeEdit(text) {
						applied = (try? ProjectReplace.write(ProjectReplace.applying(edit, to: text), to: file.url)) != nil
					}
				}
				if !applied { skipped += 1 }
			}
		}
		list.registerUndo(named: "Replace in Project") { [weak self] in
			self?.revert(record, forward: !forward)
		}
		let verb = forward ? "replaced again" : "put back"
		replacementStatus = "\(record.replaced) \(verb) in \(Self.files(record.fileCount - skipped))"
			+ (skipped > 0 ? " · \(skipped) not \(verb)" : "")
		runSearch()
	}

	private static func files(_ count: Int) -> String {
		"\(count) file\(count == 1 ? "" : "s")"
	}

	// MARK: - Searching

	private func scheduleSearch() {
		debounce?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.runSearch() }
		debounce = work
		// Longer than the in-file debounce: this walks the whole tree.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
	}

	/// Whether the *walk* stopped at a bound. Held here rather than asked of the
	/// search, because the status line is redrawn — a row ticked, the `✓`
	/// toggled — long after the walk has finished and the outcome has gone.
	private var wasCapped = false

	/// Whether what is in the list is a prefix of what is there.
	///
	/// Either end can cap: the walk stops at `maximumResults` or
	/// `maximumMatches`, and the list itself refuses to grow past its own
	/// ceiling whatever it is handed. Neither is the whole answer on its own —
	/// a usages list is handed its results in one go and never walks anything.
	private var capped: Bool { wasCapped || list.isCapped }

	private func runSearch() {
		let query = field.stringValue
		wasCapped = false
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
		updateStatus()

		search.search(
			query: query,
			options: options,
			// What arrived, and not everything found so far. The pane used to keep
			// its own growing array and hand the whole of it back on every batch,
			// so batch *n* rebuilt batches 1…*n*: item 519 measured 440 854
			// matches over a one-character query and seven seconds in which the
			// window did not answer at all. Named for the stall log, which had
			// nothing but `idle` against those seven seconds.
			onResults: { [weak self] batch in
				StallWatch.mark("search results") { self?.list.appendResults(batch) }
			},
			onFinished: { [weak self] outcome in
				guard let self, outcome.completed else { return }
				self.searchFinished = true
				self.wasCapped = outcome.capped
				self.updateStatus()
				self.updateReplaceControls()
			}
		)
	}

	private func updateStatus() {
		let matchCount = list.matchCount
		let fileCount = list.fileCount
		let prefix = searchFinished ? "" : "Searching… "
		// What the last replacement did leads, and the count of what is left
		// follows in the same line: `143 replaced in 27 files · No results`.
		let lead = replacementStatus.map { "\($0) · " } ?? ""
		// The template's trouble is said where the pattern's is, and it is said
		// instead of a count: a count beside it would read as what Replace All
		// is about to do, and it is about to do nothing.
		guard isTemplateValid else {
			statusLabel.stringValue = "Replacement cannot be used"
			updateReplaceControls()
			return
		}
		guard matchCount > 0 else {
			statusLabel.stringValue = lead + (searchFinished ? "No results" : "Searching…")
			return
		}
		// A capped list says it is capped, in the same breath as the count.
		//
		// This is the half of item 519 that is not about speed. The 500-file
		// bound has been there all along and `onFinished` reported `completed`
		// whether the tree had been walked or the bound had been hit, so a
		// truncated list printed a bare count and looked complete — which is the
		// one failure this program refuses everywhere else. "the first" in front
		// of the number is what stops it being read as all of them.
		var text = capped
			? "\(prefix)the first \(matchCount) in \(fileCount) file\(fileCount == 1 ? "" : "s")"
				+ " · more not shown"
			: "\(prefix)\(matchCount) in \(fileCount) file\(fileCount == 1 ? "" : "s")"
		// The progress, which is the reason the pane keeps marks at all: after an
		// hour the list looked the same as it did at the start, and this is where
		// that stops being true.
		let done = list.doneCount
		if done > 0 { text += " · \(done) done" }
		// Said in the same breath as the cap, because it is the cap's consequence
		// for the button beside it.
		if isReplacing && capped { text += " · too broad to replace all at once" }
		statusLabel.stringValue = lead + text
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
		// The replace half, worked as the buttons and the key work it. `replace`
		// and `replace-all` call the verbs the buttons call, so a run proves the
		// path and not a private shortcut through it; `replace-field` puts the
		// keyboard where ⇧⌘R leaves it, so `window-key:return` can then be ⏎.
		case "replacing":
			setReplacing(!isReplacing)
			print("SEARCH replacing: \(isReplacing)")
			fflush(stdout)
		case "replace-field": focusReplaceField()
		// The `.*` switch as the button flips it, so a template's `$1` can be
		// asked about from a script.
		case "regex":
			regexButton.state = regexButton.state == .on ? .off : .on
			optionsChanged()
		case "replace": replacePressed()
		case "replace-all": replaceAllPressed()
		case "status":
			print("SEARCH status: \(statusLabel.stringValue) "
				+ "where=\(placement.rawValue) "
				+ list.undoStateForTesting
				+ " replacing=\(isReplacing)"
				+ " replace-enabled=\(replaceButton.isEnabled) replace-all-enabled=\(replaceAllButton.isEnabled)"
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
			if step.hasPrefix("replacement:") {
				setReplacement(String(step.dropFirst("replacement:".count)))
				return
			}
			// The file as the disk has it, read back so a run can say what a
			// replacement did to it and not only what the list says it did.
			if step.hasPrefix("read:") {
				let path = String(step.dropFirst("read:".count))
				let url = projectRoot.appendingPathComponent(path)
				let text = ProjectReplace.readText(at: url) ?? "<unreadable>"
				print("SEARCH read \(path): " + text.replacingOccurrences(of: "\n", with: "⏎"))
				fflush(stdout)
				return
			}
			list.stepForTesting(step)
		}
	}
}

extension SearchPane: NSSearchFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		// The replacement changing is not a new question: the rows stay and only
		// the buttons' answer to "can this be used" moves. The query changing is.
		if (obj.object as? NSControl) === replaceField {
			updateReplaceControls()
			updateStatus()
			return
		}
		replacementStatus = nil
		scheduleSearch()
	}

	/// ↓ out of the query field and into the list; ⏎ in the replacement field
	/// is Replace, as it is in the find bar.
	///
	/// Without the first the results can only be reached with the mouse, and a
	/// checklist worked with ␣ that needs a click to get to is not one.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		if control === replaceField {
			guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
			replacePressed()
			return true
		}
		guard selector == #selector(NSResponder.moveDown(_:)) else { return false }
		return list.takeKeyboardFromAbove()
	}
}

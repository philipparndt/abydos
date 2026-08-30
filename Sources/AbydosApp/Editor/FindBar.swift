import AppKit
import AbydosKit

/// The find bar above the editor (⌘F).
///
/// A strip rather than a floating panel: it never covers the code you are
/// searching, and the match count stays visible while you navigate.
final class FindBar: NSView {
	var onQueryChanged: ((String, SearchOptions) -> Void)?
	var onNext: (() -> Void)?
	var onPrevious: (() -> Void)?
	var onClose: (() -> Void)?
	/// Replace the match the bar calls current, then step by this much — forward
	/// for Return and the button, backward for ⇧Return, the way the query field's
	/// Return and ⇧Return already differ.
	var onReplace: ((Int) -> Void)?
	/// Replace every match, as one edit.
	var onReplaceAll: (() -> Void)?
	/// What is typed in the replacement, so the tab can keep it.
	var onReplacementChanged: ((String) -> Void)?

	private var field: NSSearchField!
	private var statusLabel: NSTextField!
	private var caseButton: NSButton!
	private var wordButton: NSButton!
	private var regexButton: NSButton!
	private var replaceField: NSTextField!
	private var replaceButton: NSButton!
	private var replaceAllButton: NSButton!
	private var replaceRow: NSStackView!

	private(set) var options = SearchOptions()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		field = NSSearchField()
		field.placeholderString = "Find"
		field.font = Theme.current.uiFont(12)
		field.target = self
		field.action = #selector(queryChanged)
		// Fire while typing, not only on Return.
		field.sendsSearchStringImmediately = false
		field.sendsWholeSearchString = false
		(field.cell as? NSSearchFieldCell)?.searchButtonCell?.isTransparent = false
		field.delegate = self

		statusLabel = NSTextField(labelWithString: "")
		statusLabel.font = Theme.current.uiFont(11)
		statusLabel.textColor = Theme.current.gitIgnored
		statusLabel.alignment = .right

		caseButton = makeToggle(title: "Aa", tooltip: "Match case")
		wordButton = makeToggle(title: "W", tooltip: "Whole word")
		regexButton = makeToggle(title: ".*", tooltip: "Regular expression")

		let previous = makeIconButton(symbol: "chevron.up", tooltip: "Previous (⇧⌘G)") { [weak self] in
			self?.onPrevious?()
		}
		let next = makeIconButton(symbol: "chevron.down", tooltip: "Next (⌘G)") { [weak self] in
			self?.onNext?()
		}
		let close = makeIconButton(symbol: "xmark", tooltip: "Close (⎋)") { [weak self] in
			self?.onClose?()
		}

		let findRow = NSStackView(views: [
			field, statusLabel, caseButton, wordButton, regexButton, previous, next, close,
		])
		findRow.orientation = .horizontal
		findRow.spacing = 6
		findRow.alignment = .centerY

		// The replacement, under the query rather than beside it: the two fields
		// line up at the same edge, which is what makes the second one read as
		// the answer to the first.
		replaceField = NSTextField()
		replaceField.placeholderString = "Replace with"
		replaceField.font = Theme.current.uiFont(12)
		replaceField.focusRingType = .none
		replaceField.delegate = self

		replaceButton = NSButton(title: "Replace", target: self, action: #selector(replacePressed))
		replaceButton.bezelStyle = .rounded
		replaceButton.controlSize = .small
		replaceButton.font = Theme.current.uiFont(11)
		replaceButton.toolTip = "Replace the current match (⏎)"

		replaceAllButton = NSButton(title: "Replace All", target: self, action: #selector(replaceAllPressed))
		replaceAllButton.bezelStyle = .rounded
		replaceAllButton.controlSize = .small
		replaceAllButton.font = Theme.current.uiFont(11)
		replaceAllButton.toolTip = "Replace every match, as one edit"

		replaceRow = NSStackView(views: [replaceField, replaceButton, replaceAllButton])
		replaceRow.orientation = .horizontal
		replaceRow.spacing = 6
		replaceRow.alignment = .centerY
		replaceRow.isHidden = true

		let stack = NSStackView(views: [findRow, replaceRow])
		stack.orientation = .vertical
		stack.spacing = 4
		stack.alignment = .leading
		stack.distribution = .fill
		stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		field.setContentHuggingPriority(.defaultLow, for: .horizontal)
		replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			findRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: Theme.current.scaled(10)),
			findRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -Theme.current.scaled(10)),
			replaceRow.leadingAnchor.constraint(equalTo: findRow.leadingAnchor),
			replaceRow.trailingAnchor.constraint(equalTo: findRow.trailingAnchor),
			field.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.current.scaled(220)),
			// The two fields the same width, so the replacement sits under the
			// query rather than under whichever switch happens to be that wide.
			replaceField.widthAnchor.constraint(equalTo: field.widthAnchor),
		])
	}

	@objc private func replacePressed() { onReplace?(1) }
	@objc private func replaceAllPressed() { onReplaceAll?() }

	private func makeToggle(title: String, tooltip: String) -> NSButton {
		let button = NSButton(title: title, target: self, action: #selector(optionToggled))
		button.setButtonType(.pushOnPushOff)
		button.bezelStyle = .rounded
		button.controlSize = .small
		button.font = Theme.current.uiFont(10, weight: .medium)
		button.toolTip = tooltip
		return button
	}

	private func makeIconButton(symbol: String, tooltip: String, action: @escaping () -> Void) -> NSButton {
		let button = NSButton(
			image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
			target: nil,
			action: nil
		)
		button.bezelStyle = .accessoryBarAction
		button.controlSize = .small
		button.toolTip = tooltip
		button.onAction = action
		return button
	}

	/// Puts the switches where the options say, for a tab coming back.
	private func applyOptionsToButtons() {
		caseButton.state = options.caseSensitive ? .on : .off
		wordButton.state = options.wholeWord ? .on : .off
		regexButton.state = options.isRegex ? .on : .off
	}

	@objc private func optionToggled() {
		options.caseSensitive = caseButton.state == .on
		options.wholeWord = wordButton.state == .on
		options.isRegex = regexButton.state == .on
		notifyQueryChanged()
	}

	@objc private func queryChanged() {
		notifyQueryChanged()
	}

	private func notifyQueryChanged() {
		let query = field.stringValue
		markValidity(of: query)
		onQueryChanged?(query, options)
	}

	/// Colours the field for a pattern that will not compile.
	///
	/// **Red now means two things** — this, and a search that found nothing —
	/// and the words beside it are what tell them apart. Before, an unfinished
	/// pattern was marked here and then reported as `No results` by the label a
	/// few pixels away, which is the reading the comment here set out to avoid.
	private func markValidity(of query: String) {
		let valid = TextSearch.isValid(query: query, options: options)
		isPatternValid = valid
		// The replacement's usability is a question about the pattern as much as
		// about itself — `$1` is fine against one capture group and names nothing
		// against none — so it is asked again whenever either changes.
		isTemplateValid = !isReplacing
			|| TextSearch.isValid(template: replaceField.stringValue, query: query, options: options)
		colourQuery(valid ? .labelColor : Theme.current.gitConflict)
	}

	/// Colours the query — as far as `NSSearchField` allows, which is not far.
	///
	/// **Measured: this does not reach the screen.** With `field.textColor`, the
	/// field editor's `textColor` and the attributed string all holding the
	/// scheme's red, a capture of the window has the query at
	/// `(236, 235, 235)` — white, over 1007 glyph pixels, none of them reddish —
	/// while the `No results` beside it is `(212, 114, 112)`, which is that same
	/// red. `NSSearchField` paints its text in a colour of its own choosing.
	///
	/// So **the label is what carries the signal**, and this is left in rather
	/// than removed: it costs one line, it is right wherever the control does
	/// honour it, and taking it out would also take out the invalid-pattern
	/// marking that has been here since before this change — which, by the same
	/// measurement, was never visible either.
	///
	/// Owning the text colour outright means drawing the magnifier and the clear
	/// button by hand. That is a bigger change than this one and is not it.
	private func colourQuery(_ colour: NSColor) {
		field.textColor = colour
		guard let editor = field.currentEditor() as? NSTextView else { return }
		editor.textColor = colour
		// The selected range keeps its own attributes, so typing straight after
		// this would come out in the old colour.
		editor.typingAttributes[.foregroundColor] = colour
	}

	/// Whether what is typed is a pattern that compiles.
	///
	/// Read by `setStatus`, which must not say `No results` about a search that
	/// never ran.
	private(set) var isPatternValid = true

	/// Whether the replacement can be used with the pattern beside it.
	///
	/// **Foundation does not refuse a template naming a group that does not
	/// exist** — measured: `$7` against two capture groups returns the empty
	/// string — so a Replace All with a mistyped number would delete every match
	/// instead of saying no. Read by `setStatus` and by the editor, which does
	/// not replace while it is false.
	private(set) var isTemplateValid = true

	// MARK: - Replacing

	/// Whether the replace half is showing.
	private(set) var isReplacing = false

	/// What the bar wants to be tall, which is one row or two.
	///
	/// Read by the editor, which owns the height constraint: the bar knows how
	/// many rows it is showing and nothing else does.
	var wantedHeight: CGFloat { Theme.current.scaled(isReplacing ? 64 : 34) }

	var replacement: String { replaceField.stringValue }

	/// Shows or hides the replace half.
	///
	/// ⌘F never calls this with `false`: somebody who pressed it to re-read their
	/// query has not asked for the replacement they typed to be taken away.
	func setReplacing(_ replacing: Bool) {
		guard replacing != isReplacing else { return }
		isReplacing = replacing
		replaceRow.isHidden = !replacing
		markValidity(of: field.stringValue)
		sayStatusAgain()
	}

	/// Puts a replacement in the field without saying it changed: this is a tab
	/// coming back with what it was left holding, not somebody typing.
	func setReplacement(_ text: String) {
		replaceField.stringValue = text
		markValidity(of: field.stringValue)
		sayStatusAgain()
	}

	func focusReplaceField(selectingAll: Bool = true) {
		window?.makeFirstResponder(replaceField)
		if selectingAll { replaceField.currentEditor()?.selectAll(nil) }
	}

	// MARK: - State

	var query: String { field.stringValue }

	/// What the bar says, and whether it says it in red.
	///
	/// Four states, and the two red ones differ only in the words — which is why
	/// the words have to differ:
	///
	/// | query | field | label |
	/// | --- | --- | --- |
	/// | empty | plain | *nothing* |
	/// | matches | plain | `3 of 17` |
	/// | no matches | red | `No results` |
	/// | will not compile | red | `Incomplete pattern` |
	///
	/// The last row used to say `No results` in grey: an invalid pattern still
	/// reached the search, the search found nothing in a regex that never
	/// compiled, and the bar reported an answer to a question it never asked.
	func setStatus(matchCount: Int, currentIndex: Int?) {
		shownMatchCount = matchCount
		shownIndex = currentIndex

		// An empty query has not found nothing; it has not been asked.
		guard !field.stringValue.isEmpty else {
			statusLabel.stringValue = ""
			statusLabel.textColor = Theme.current.gitIgnored
			return
		}

		guard isPatternValid else {
			// Nothing was searched, so "no results" would be a wrong answer
			// rather than an empty one.
			statusLabel.stringValue = "Incomplete pattern"
			statusLabel.textColor = Theme.current.gitConflict
			return
		}

		// After the pattern and before the count: a replacement that cannot be
		// used is a reason nothing will be replaced, and the matches behind it
		// are real and worth still being told about — but this is the thing to
		// fix, so it is the thing said.
		guard isTemplateValid else {
			statusLabel.stringValue = "Replacement cannot be used"
			statusLabel.textColor = Theme.current.gitConflict
			return
		}

		if matchCount == 0 {
			// **The label is the signal.** The two states somebody acts on
			// differently — there are matches, there are none — differed by one
			// grey word in the corner; now that word is red. Colouring the query
			// too was tried and does not reach the screen: see `colourQuery`.
			statusLabel.stringValue = "No results"
			statusLabel.textColor = Theme.current.gitConflict
			colourQuery(Theme.current.gitConflict)
			return
		}

		statusLabel.textColor = Theme.current.gitIgnored
		colourQuery(.labelColor)
		if let currentIndex {
			statusLabel.stringValue = "\(currentIndex + 1) of \(matchCount)"
		} else {
			statusLabel.stringValue = "\(matchCount)"
		}
	}

	/// What was last reported, so the label can be worked out again when what it
	/// depends on changes without the document being searched again — typing in
	/// the replacement field, or the replace half appearing.
	private var shownMatchCount = 0
	private var shownIndex: Int?

	private func sayStatusAgain() {
		setStatus(matchCount: shownMatchCount, currentIndex: shownIndex)
	}

	/// What the bar is saying and how, for a test that cannot open a window.
	var statusReportForTesting: String {
		let red = statusLabel.textColor == Theme.current.gitConflict
		let fieldRed = field.textColor == Theme.current.gitConflict
		// What is actually drawn, as against what was set. A photograph showed
		// `No results` red beside a query still white, with both colours set —
		// so the question is which of the three places the text's colour can
		// live is the one being painted from.
		let editor = field.currentEditor() as? NSTextView
		let editorColour = editor?.textColor.map { $0 == Theme.current.gitConflict ? "red" : "plain" }
		let drawn = field.attributedStringValue.length > 0
			? field.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
			: nil
		return "query=\u{201C}\(field.stringValue)\u{201D} says=\u{201C}\(statusLabel.stringValue)\u{201D}"
			+ " labelRed=\(red) queryRed=\(fieldRed)"
			+ " editor=\(editor == nil ? "none" : (editorColour ?? "unset"))"
			+ " attributed=\(drawn.map { $0 == Theme.current.gitConflict ? "red" : "plain" } ?? "none")"
	}

	func focusField(selectingAll: Bool = true) {
		window?.makeFirstResponder(field)
		if selectingAll { field.currentEditor()?.selectAll(nil) }
	}

	func setQuery(_ text: String) {
		field.stringValue = text
		notifyQueryChanged()
	}

	/// Shows a query and its switches without asking for the search again.
	///
	/// For a tab coming back to the front: its matches are already known and
	/// kept, so re-running would be work whose answer is in hand — and it would
	/// move the current match, since `runFind` starts from the caret.
	func setQueryWithoutSearching(_ text: String, options: SearchOptions) {
		field.stringValue = text
		self.options = options
		applyOptionsToButtons()
		markValidity(of: text)
	}

	func applyThemeChange() {
		field.font = Theme.current.uiFont(12)
		replaceField.font = Theme.current.uiFont(12)
		replaceButton.font = Theme.current.uiFont(11)
		replaceAllButton.font = Theme.current.uiFont(11)
		statusLabel.font = Theme.current.uiFont(11)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}
}

extension FindBar: NSSearchFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		// The replacement changes what the bar can say and asks nothing of the
		// document: searching again on every character typed into it would be a
		// scan of the file for an answer that has not changed.
		guard (obj.object as AnyObject?) !== replaceField else {
			markValidity(of: field.stringValue)
			sayStatusAgain()
			onReplacementChanged?(replaceField.stringValue)
			return
		}
		notifyQueryChanged()
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
			// In the replacement, Return replaces rather than steps: it is the
			// button under the caret's own field, and reaching for the mouse to
			// press what Return is over is not a replace loop anybody would use.
			if control === replaceField {
				onReplace?(backwards ? -1 : 1)
				return true
			}
			// Return steps forward, shift-Return backward — the convention every
			// find bar uses.
			if backwards {
				onPrevious?()
			} else {
				onNext?()
			}
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			onClose?()
			return true
		default:
			return false
		}
	}
}

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

	private var field: NSSearchField!
	private var statusLabel: NSTextField!
	private var caseButton: NSButton!
	private var wordButton: NSButton!
	private var regexButton: NSButton!

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

		let stack = NSStackView(views: [
			field, statusLabel, caseButton, wordButton, regexButton, previous, next, close,
		])
		stack.orientation = .horizontal
		stack.spacing = 6
		stack.alignment = .centerY
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		field.setContentHuggingPriority(.defaultLow, for: .horizontal)
		statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			field.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.current.scaled(220)),
		])
	}

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
		notifyQueryChanged()
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			// Return steps forward, shift-Return backward — the convention every
			// find bar uses.
			if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
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

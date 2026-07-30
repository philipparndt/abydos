import AppKit
import IdeaiKit

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
		// An unfinished regex is marked invalid rather than reported as "no
		// results", which would read as a wrong answer.
		let valid = TextSearch.isValid(query: query, options: options)
		field.textColor = valid ? .labelColor : Theme.current.gitConflict
		onQueryChanged?(query, options)
	}

	// MARK: - State

	var query: String { field.stringValue }

	func setStatus(matchCount: Int, currentIndex: Int?) {
		if matchCount == 0 {
			statusLabel.stringValue = field.stringValue.isEmpty ? "" : "No results"
		} else if let currentIndex {
			statusLabel.stringValue = "\(currentIndex + 1) of \(matchCount)"
		} else {
			statusLabel.stringValue = "\(matchCount)"
		}
	}

	func focusField(selectingAll: Bool = true) {
		window?.makeFirstResponder(field)
		if selectingAll { field.currentEditor()?.selectAll(nil) }
	}

	func setQuery(_ text: String) {
		field.stringValue = text
		notifyQueryChanged()
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

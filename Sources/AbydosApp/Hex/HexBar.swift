import AbydosKit
import AppKit

/// The strip above the bytes: where to go, what to find, how to read.
///
/// One strip rather than the editor's find bar with a byte mode bolted on:
/// the find bar's query, options and replace row are about text, and every
/// one of its controls would have needed an "unless this is a hex tab". The
/// offset field is ⌘L's target, the find field is ⌘F's, and the kind popup
/// says whether the query is hex, text or a number.
///
/// A measured member of the scaled controls, in the library's words: the
/// fields and popups keep AppKit's behaviour and take their font and their
/// heights from the theme, never from a `controlSize`, so the strip follows
/// the zoom at every step rather than walling out at the largest size.
final class HexBar: NSView, ScaleFollowing {
	enum FindKind: String, CaseIterable {
		case hex = "Hex", text = "Text", number = "Number"
	}

	/// The offset field was entered. Returns a complaint to show, or nil.
	var onGoTo: ((String) -> String?)?
	/// The query or its kind changed.
	var onFindChanged: ((String, FindKind) -> Void)?
	var onFindNext: (() -> Void)?
	var onFindPrevious: (() -> Void)?
	var onBytesPerRowChanged: ((Int) -> Void)?
	var onEncodingChanged: ((ByteEncoding) -> Void)?
	var onWidthChanged: ((Int) -> Void)?
	var onOrderChanged: ((ByteOrder) -> Void)?
	var onInsertToggled: (() -> Void)?
	var onInspectorToggled: (() -> Void)?

	private var offsetField: NSTextField!
	private var findField: ScaledSearchField!
	private var kindPopup: NSPopUpButton!
	private var encodingPopup: NSPopUpButton!
	private var widthPopup: NSPopUpButton!
	private var orderPopup: NSPopUpButton!
	private var statusLabel: NSTextField!
	/// What `reserveStatus(for:)` keeps clear; see where it is made.
	private var statusWidth: NSLayoutConstraint!
	private var statusReservedFor: String?
	private var statusIsComplaint = false
	private var progress: NSProgressIndicator!
	private var rowsPopup: NSPopUpButton!
	private var insertButton: NSButton!
	private var inspectorButton: NSButton!
	private var stack: NSStackView!
	/// The constants the zoom moves, with their design-time values.
	private let heights = ScaledHeights()
	private var offsetWidth: NSLayoutConstraint!
	private var findMinimum: NSLayoutConstraint!
	private var progressWidth: NSLayoutConstraint!

	private(set) var kind: FindKind = .hex
	private(set) var encoding: ByteEncoding = .ascii
	private(set) var width = 32
	private(set) var order: ByteOrder = .little

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		build()
		applyTheme()
		ScaledControls.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func popup(_ titles: [String], _ action: Selector) -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.addItems(withTitles: titles)
		popup.target = self
		popup.action = action
		popup.setContentHuggingPriority(.required, for: .horizontal)
		return popup
	}

	private func build() {
		offsetField = NSTextField()
		offsetField.placeholderString = "Offset"
		offsetField.target = self
		offsetField.action = #selector(offsetEntered)
		offsetField.toolTip = "Go to an offset: hex with or without 0x, decimal, or +/- from the caret (⌘L)"
		offsetWidth = offsetField.widthAnchor.constraint(equalToConstant: 0)
		offsetWidth.isActive = true

		findField = ScaledSearchField(placeholder: "Find bytes", fontSize: 11)
		findField.sendsSearchStringImmediately = false
		findField.sendsWholeSearchString = false
		findField.delegate = self
		findField.target = self
		findField.action = #selector(findEntered)
		findMinimum = findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
		findMinimum.isActive = true

		kindPopup = popup(FindKind.allCases.map(\.rawValue), #selector(kindChanged))
		kindPopup.toolTip = "What the query is: bytes in hex with ?? wildcards, text, or a number"
		encodingPopup = popup(ByteEncoding.allCases.map(\.said), #selector(encodingChanged))
		encodingPopup.toolTip = "How the text column and a text query read their bytes"
		widthPopup = popup(["8-bit", "16-bit", "32-bit", "64-bit"], #selector(widthChanged))
		widthPopup.selectItem(at: 2)
		widthPopup.toolTip = "How wide the number is"
		orderPopup = popup(ByteOrder.allCases.map(\.said), #selector(orderChanged))
		orderPopup.toolTip = "Which end of the number comes first"

		statusLabel = NSTextField(labelWithString: "")
		statusLabel.lineBreakMode = .byTruncatingTail
		statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		// Room kept for the widest thing this search will say, so stepping
		// through matches does not resize the field beside it: the status goes
		// "1 of 128 matches", "12 of …", "128 of …", and each of those is wider
		// than the last. The label sizes to its text and the find field is only
		// pinned to a minimum, so every step used to move the field somebody
		// was typing in.
		statusWidth = statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
		statusWidth.isActive = true

		progress = NSProgressIndicator()
		progress.style = .bar
		progress.isIndeterminate = false
		progress.minValue = 0
		progress.maxValue = 1
		progress.isHidden = true
		progressWidth = progress.widthAnchor.constraint(equalToConstant: 0)
		progressWidth.isActive = true

		let previous = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous")!, target: self, action: #selector(previousPressed))
		previous.bezelStyle = .accessoryBarAction
		previous.toolTip = "Previous match (⇧⌘G)"
		let next = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next")!, target: self, action: #selector(nextPressed))
		next.bezelStyle = .accessoryBarAction
		next.toolTip = "Next match (⌘G)"

		rowsPopup = popup(["8 a row", "16 a row", "32 a row"], #selector(rowsChanged))
		rowsPopup.selectItem(at: 1)
		rowsPopup.toolTip = "Bytes in each row"

		insertButton = NSButton(title: "Insert", target: self, action: #selector(insertPressed))
		insertButton.bezelStyle = .accessoryBarAction
		insertButton.setButtonType(.pushOnPushOff)
		insertButton.toolTip = "Insert mode: typing adds bytes and Delete removes them. Off, typing overwrites."

		inspectorButton = NSButton(image: NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Inspector")!, target: self, action: #selector(inspectorPressed))
		inspectorButton.bezelStyle = .accessoryBarAction
		inspectorButton.toolTip = "Show or hide the inspector"

		stack = NSStackView(views: [
			offsetField, findField, kindPopup, encodingPopup, widthPopup, orderPopup,
			previous, next, progress, statusLabel, NSView(), rowsPopup, insertButton, inspectorButton,
		])
		stack.orientation = .horizontal
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			heights.height(self, design: 30),
		])
		showControlsForKind()
	}

	/// The font, the metrics and the colours again. The height constraints
	/// go through `ScaledHeights`, which re-takes them itself.
	func applyTheme() {
		let theme = Theme.current
		layer?.backgroundColor = theme.sidebarBackground.cgColor
		offsetField.font = theme.monoFont(11)
		for popup in [kindPopup, encodingPopup, widthPopup, orderPopup, rowsPopup] {
			popup?.font = theme.uiFont(11)
		}
		insertButton.font = theme.uiFont(11)
		statusLabel.font = theme.uiFont(11)
		statusLabel.textColor = statusIsComplaint ? theme.gitConflict : theme.gitIgnored
		offsetWidth.constant = theme.scaled(96)
		findMinimum.constant = theme.scaled(140)
		progressWidth.constant = theme.scaled(60)
		stack.spacing = theme.scaled(6)
		stack.edgeInsets = NSEdgeInsets(top: 0, left: theme.scaled(8), bottom: 0, right: theme.scaled(8))
		// The reservation was measured in the old font.
		if let widest = statusReservedFor { reserveStatus(for: widest) }
		needsDisplay = true
	}

	private func showControlsForKind() {
		encodingPopup.isHidden = kind == .number
		widthPopup.isHidden = kind != .number
		orderPopup.isHidden = kind != .number
	}

	// MARK: - Actions

	@objc private func offsetEntered() {
		let complaint = onGoTo?(offsetField.stringValue)
		setStatus(complaint ?? "", isComplaint: complaint != nil)
	}

	@objc private func findEntered() {
		// Return in the field steps, as the editor's find bar does.
		onFindNext?()
	}

	@objc private func kindChanged() {
		kind = FindKind.allCases[max(0, kindPopup.indexOfSelectedItem)]
		showControlsForKind()
		onFindChanged?(findField.stringValue, kind)
	}

	@objc private func encodingChanged() {
		encoding = ByteEncoding.allCases[max(0, encodingPopup.indexOfSelectedItem)]
		onEncodingChanged?(encoding)
		onFindChanged?(findField.stringValue, kind)
	}

	@objc private func widthChanged() {
		width = [8, 16, 32, 64][max(0, widthPopup.indexOfSelectedItem)]
		onWidthChanged?(width)
		onFindChanged?(findField.stringValue, kind)
	}

	@objc private func orderChanged() {
		order = ByteOrder.allCases[max(0, orderPopup.indexOfSelectedItem)]
		onOrderChanged?(order)
		onFindChanged?(findField.stringValue, kind)
	}

	@objc private func rowsChanged() {
		onBytesPerRowChanged?([8, 16, 32][max(0, rowsPopup.indexOfSelectedItem)])
	}

	@objc private func insertPressed() { onInsertToggled?() }
	@objc private func inspectorPressed() { onInspectorToggled?() }
	@objc private func nextPressed() { onFindNext?() }
	@objc private func previousPressed() { onFindPrevious?() }

	// MARK: - What the controller tells it

	var query: String { findField.stringValue }

	func setQuery(_ text: String) {
		findField.stringValue = text
		onFindChanged?(text, kind)
	}

	func setKind(_ kind: FindKind) {
		self.kind = kind
		kindPopup.selectItem(at: FindKind.allCases.firstIndex(of: kind) ?? 0)
		showControlsForKind()
	}

	func setInsert(_ on: Bool) {
		insertButton.state = on ? .on : .off
		insertButton.contentTintColor = on ? Theme.current.gitModified : nil
	}

	func setInspectorShown(_ shown: Bool) {
		inspectorButton.state = shown ? .on : .off
	}

	func setEncoding(_ encoding: ByteEncoding) {
		self.encoding = encoding
		encodingPopup.selectItem(at: ByteEncoding.allCases.firstIndex(of: encoding) ?? 0)
	}

	func setBytesPerRow(_ count: Int) {
		rowsPopup.selectItem(at: [8, 16, 32].firstIndex(of: count) ?? 1)
	}

	/// The count, the complaint, or how far the search has got.
	func setStatus(_ text: String, isComplaint: Bool = false) {
		statusLabel.stringValue = text
		statusIsComplaint = isComplaint
		statusLabel.textColor = isComplaint ? Theme.current.gitConflict : Theme.current.gitIgnored
	}

	var status: String { statusLabel.stringValue }

	/// Keeps room for `widest`, so that everything narrower than it can be
	/// shown without anything moving.
	///
	/// Asked for by the caller rather than measured from what is shown,
	/// because the widest form is known before it is reached: it is the last
	/// match's index against the count, and by the time the label is showing
	/// it the field has already jumped.
	func reserveStatus(for widest: String) {
		guard let font = statusLabel.font else { return }
		statusReservedFor = widest
		let width = (widest as NSString).size(withAttributes: [.font: font]).width
		statusWidth.constant = ceil(width) + Theme.current.scaled(4)
	}

	/// Gives the room back, for a search that is over or has no matches.
	func clearStatusReservation() {
		statusReservedFor = nil
		statusWidth.constant = 0
	}

	func setProgress(_ fraction: Double?) {
		guard let fraction else {
			progress.isHidden = true
			return
		}
		progress.isHidden = false
		progress.doubleValue = fraction
	}

	func focusFind() { window?.makeFirstResponder(findField) }
	func focusOffset() {
		window?.makeFirstResponder(offsetField)
		offsetField.selectText(nil)
	}
}

extension HexBar: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		guard (notification.object as? NSSearchField) === findField else { return }
		onFindChanged?(findField.stringValue, kind)
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		guard control === findField else { return false }
		if selector == #selector(NSResponder.insertNewline(_:)) {
			if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
				onFindPrevious?()
			} else {
				onFindNext?()
			}
			return true
		}
		return false
	}
}

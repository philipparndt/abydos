import AppKit
import AbydosKit

/// A filter over a list, opened with `⌘F` and shut with `⎋`.
///
/// **Over the list rather than above it.** The field this replaces was a
/// permanent row — 22 points and an inset, in a pane whose whole job is a list
/// — for a job done occasionally, and it was the *second* branch filter in the
/// window: the branch pill in the titlebar opens a popover that lists, groups
/// and filters branches already, without this pane being open at all.
///
/// It is not `FindBar`. That one carries case, whole-word, regular expressions,
/// next and previous, and a match count, because searching a file is a walk
/// through matches. Filtering a list is not a walk — the list becomes the
/// matches — so this is a field and a way out of it, and sharing the object
/// would have meant five controls that do nothing here.
final class PaneFilterStrip: NSView {
	var onTextChanged: ((String) -> Void)?
	var onClose: (() -> Void)?

	private let field = NSSearchField()

	/// The last text handed out, so *emptied* can be told from *opened empty*.
	///
	/// Shutting on empty is right when somebody clears a filter they are done
	/// with and wrong the instant it fires on the strip's own first moment,
	/// which is empty by definition.
	private var said = ""

	init(placeholder: String) {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor

		field.placeholderString = placeholder
		field.font = Theme.current.uiFont(12)
		field.focusRingType = .none
		field.sendsWholeSearchString = false
		field.delegate = self
		field.translatesAutoresizingMaskIntoConstraints = false
		addSubview(field)

		let close = NSButton()
		close.image = NSImage(
			systemSymbolName: "xmark", accessibilityDescription: "Close the filter"
		)
		close.isBordered = false
		close.imageScaling = .scaleProportionallyDown
		close.toolTip = "Close (⎋)"
		close.target = self
		close.action = #selector(closePressed)
		close.translatesAutoresizingMaskIntoConstraints = false
		addSubview(close)

		let inset = Theme.current.scaled(6)
		NSLayoutConstraint.activate([
			field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			field.topAnchor.constraint(equalTo: topAnchor, constant: inset / 2),
			field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset / 2),
			close.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: inset / 2),
			close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			close.centerYAnchor.constraint(equalTo: centerYAnchor),
			close.widthAnchor.constraint(equalToConstant: Theme.current.scaled(16)),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// A line under it, so the list below reads as a list and not as more strip.
	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setStroke()
		let line = NSBezierPath()
		line.move(to: NSPoint(x: 0, y: 0.5))
		line.line(to: NSPoint(x: bounds.maxX, y: 0.5))
		line.lineWidth = 1
		line.stroke()
	}

	/// Puts the keyboard in the field, which is the point of opening it.
	func takeKeyboard() { window?.makeFirstResponder(field) }

	var text: String { field.stringValue.trimmingCharacters(in: .whitespaces) }

	func setTextForTesting(_ value: String) {
		field.stringValue = value
		announce()
	}

	@objc private func closePressed() { onClose?() }

	private func announce() {
		let now = text
		defer { said = now }
		onTextChanged?(now)
		// **Emptied shuts it; opened empty does not.** Without the previous
		// text to compare against, the first keystroke-less moment of every
		// strip would close the strip.
		if now.isEmpty, !said.isEmpty { onClose?() }
	}

	func applyThemeChange() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		field.font = Theme.current.uiFont(12)
		needsDisplay = true
	}
}

extension PaneFilterStrip: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) { announce() }

	func control(
		_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
	) -> Bool {
		// ⎋ in a search field clears it by default, which would leave the strip
		// open over the list with nothing in it — the state this has no reason
		// to have.
		if selector == #selector(NSResponder.cancelOperation(_:)) {
			onClose?()
			return true
		}
		return false
	}
}

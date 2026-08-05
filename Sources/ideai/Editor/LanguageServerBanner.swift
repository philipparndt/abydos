import AppKit
import IdeaiKit

/// The strip above the editor saying that this file could have a language
/// server, and does not.
///
/// The gap it fills: an editor with no server for the language in front of you
/// behaves exactly like one whose server is broken. Nothing is underlined,
/// nothing completes, go-to-declaration finds nothing — and the only place that
/// ever said why was the empty state of a palette somebody had to think to
/// open. This says it where the file is, once it is opened, in a sentence with
/// the command in it.
///
/// A strip rather than a dialog, for the reason the find bar is one: it never
/// covers the code, it can be read at a glance and ignored, and it costs a
/// click to be rid of rather than a click to continue. Three ways out, which is
/// the point — "not now" (✕), "not for this language, ever" (Ignore), and the
/// one that solves it (How to install).
final class LanguageServerBanner: NSView {
	/// Read the manual: what to install, where it has to end up, how to check.
	var onDetails: (() -> Void)?
	/// Never for this language again.
	var onIgnore: (() -> Void)?
	/// Not now. Comes back for the next file of this language.
	var onDismiss: (() -> Void)?

	private var label: NSTextField!
	private var ignoreButton: NSButton!
	private var detailsButton: NSButton!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		build()
		applyTheme()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	/// A hairline under it, so the strip reads as chrome above the file rather
	/// than as the file's first line.
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.editorBackground.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}

	private func build() {
		let icon = NSImageView()
		icon.image = NSImage(
			systemSymbolName: "lightbulb", accessibilityDescription: "Suggestion"
		)
		icon.contentTintColor = Theme.current.gitModified
		icon.translatesAutoresizingMaskIntoConstraints = false
		icon.widthAnchor.constraint(equalToConstant: Theme.current.scaled(14)).isActive = true

		label = NSTextField(labelWithString: "")
		label.font = Theme.current.uiFont(11.5)
		label.textColor = Theme.current.sidebarHeaderText
		label.lineBreakMode = .byTruncatingTail

		detailsButton = makeButton(title: "How to install") { [weak self] in self?.onDetails?() }
		ignoreButton = makeButton(title: "Ignore") { [weak self] in self?.onIgnore?() }

		let close = NSButton(
			image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss") ?? NSImage(),
			target: nil,
			action: nil
		)
		close.bezelStyle = .accessoryBarAction
		close.controlSize = .small
		close.toolTip = "Not now"
		close.onAction = { [weak self] in self?.onDismiss?() }

		let stack = NSStackView(views: [icon, label, detailsButton, ignoreButton, close])
		stack.orientation = .horizontal
		stack.spacing = 6
		stack.alignment = .centerY
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		// The sentence gives way first: on a narrow window the buttons are what
		// the strip is for.
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	private func makeButton(title: String, action: @escaping () -> Void) -> NSButton {
		let button = NSButton(title: title, target: nil, action: nil)
		button.bezelStyle = .accessoryBarAction
		button.controlSize = .small
		button.font = Theme.current.uiFont(11)
		button.onAction = action
		return button
	}

	// MARK: - Contents

	private(set) var suggestion: LanguageServers.Suggestion?

	/// What is being offered, and for which language.
	func show(_ suggestion: LanguageServers.Suggestion) {
		self.suggestion = suggestion
		// The command is in the sentence: it is the searchable part, the thing
		// somebody types, and the name they will recognise if they already know
		// the language's tooling.
		label.stringValue = "\(suggestion.languageName) has no language server. "
			+ "Install \(suggestion.command) for completion, problems and go-to-declaration."
		label.toolTip = suggestion.installHint
		ignoreButton.title = "Ignore for \(suggestion.languageName)"
		ignoreButton.toolTip = "Never offer a \(suggestion.languageName) server again"
		needsDisplay = true
	}

	func applyTheme() {
		label?.font = Theme.current.uiFont(11.5)
		label?.textColor = Theme.current.sidebarHeaderText
		detailsButton?.font = Theme.current.uiFont(11)
		ignoreButton?.font = Theme.current.uiFont(11)
		needsDisplay = true
	}

	/// How tall the strip is when it is showing.
	static var height: CGFloat { Theme.current.scaled(26) }

	// MARK: - Testing

	var textForTesting: String { label.stringValue }
	func pressIgnoreForTesting() { onIgnore?() }
	func pressDetailsForTesting() { onDetails?() }
	func pressDismissForTesting() { onDismiss?() }
}

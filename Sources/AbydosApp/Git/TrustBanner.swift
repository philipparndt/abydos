import AppKit
import AbydosKit

/// The strip that says a project is not trusted, and the one gesture that
/// changes it.
///
/// **A strip and not a modal.** A window that cannot be looked at until a
/// security question is answered is a security question answered by reflex —
/// and the whole point of an untrusted project is that it is fully readable:
/// the tree, the editor, search, the git history and the diffs all work while
/// this is up. So it sits above the editor, says what is held back, and waits.
///
/// The shape is `LanguageServerBanner`'s, which is this app's answer to "a
/// sentence and a button, above the file": same ground, same hairline, same
/// drawn buttons, so a second strip does not read as a different kind of thing.
final class TrustBanner: NSView {
	/// Trust this project — the sheet, not the deed.
	var onTrust: (() -> Void)?
	/// What is held back, in a sentence somebody can act on.
	var onDetails: (() -> Void)?

	private var label: NSTextField!
	private var trustButton: DrawnButton!
	private var detailsButton: DrawnButton!
	private var icon: NSImageView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		build()
		applyTheme()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.editorBackground.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}

	private func build() {
		icon = NSImageView()
		icon.translatesAutoresizingMaskIntoConstraints = false
		icon.widthAnchor.constraint(equalToConstant: Theme.current.scaled(16)).isActive = true

		label = NSTextField(labelWithString: "")
		label.lineBreakMode = .byTruncatingTail

		trustButton = DrawnButton(title: "Trust This Project") { [weak self] in self?.onTrust?() }
		trustButton.prominence = .prominent
		trustButton.tip = StyledTip.Tip(
			title: "Trust this project",
			detail: "Lets it run: configurations, builds, language servers, containers and a terminal."
		)
		detailsButton = DrawnButton(title: "What is held back") { [weak self] in self?.onDetails?() }
		detailsButton.prominence = .quiet

		let stack = NSStackView(views: [icon, label, trustButton, detailsButton])
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		// The sentence gives way first: on a narrow window the button is what
		// the strip is for.
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(12)),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(12)),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		stack.spacing = Theme.current.scaled(8)
	}

	/// The project this is about, or nil to hide the strip.
	func show(project: URL?) {
		guard let project else {
			isHidden = true
			return
		}
		isHidden = false
		label.stringValue = "\(project.lastPathComponent) is not trusted — "
			+ "nothing in it runs, and its environment reaches nothing."
		applyTheme()
		needsDisplay = true
	}

	func applyTheme() {
		label.font = Theme.current.uiFont(11.5)
		label.textColor = Theme.current.sidebarHeaderText
		icon.image = Theme.symbol(
			"hand.raised.fill", size: 12 * Theme.current.scale, color: Theme.current.gitModified
		)
		trustButton.applyTheme()
		detailsButton.applyTheme()
		needsDisplay = true
	}

	/// What the strip says, for a driven run: the words are the requirement.
	var reportForTesting: String {
		isHidden ? "no banner" : label.stringValue
	}
}

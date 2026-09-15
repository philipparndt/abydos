import AppKit
import AbydosKit

/// The strip that says git cannot run on this machine, and the command that
/// fixes it.
///
/// `TrustBanner`'s shape, in `TrustBanner`'s place: a sentence and a button
/// above everything the project can reach. What it is *not* is dismissable.
/// The trust strip can be put away because it names a decision somebody may
/// be about to make; this one names a machine whose git will not run, and
/// putting it away changes nothing about that. It goes when git runs.
///
/// Why a strip and not a line in the git pane: the morning this was written,
/// the trust strip was the first thing seen and the empty git pane the second,
/// and a message in the second place would not have explained the first.
final class GitAvailabilityBanner: NSView {
	private var icon: NSImageView!
	private var label: NSTextField!
	private var command: NSTextField!
	private var copyButton: DrawnButton!
	private var cause: GitAvailability.Cause?

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

		// The command in the strip itself, in monospace, so it can be read and
		// typed without pressing anything; the button is for the hand that
		// would rather paste it.
		command = NSTextField(labelWithString: "")
		command.lineBreakMode = .byTruncatingTail
		command.isSelectable = true

		copyButton = DrawnButton(title: "Copy Command") { [weak self] in self?.copyCommand() }
		copyButton.prominence = .prominent
		copyButton.tip = StyledTip.Tip(
			title: "Copy the command",
			detail: "Run it in a terminal, then come back — the strip goes when git runs."
		)

		let stack = NSStackView(views: [icon, label, command, copyButton])
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		// The sentence gives way first, then the command: on a narrow window
		// the button is what the strip is for.
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		command.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(12)),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(12)),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		stack.spacing = Theme.current.scaled(8)
	}

	/// Why git cannot run, or nil to hide the strip.
	func show(cause: GitAvailability.Cause?) {
		self.cause = cause
		guard let cause else {
			isHidden = true
			return
		}
		isHidden = false
		label.stringValue = cause.sentence
		command.stringValue = cause.command
		applyTheme()
		needsDisplay = true
	}

	private func copyCommand() {
		guard let cause else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(cause.command, forType: .string)
	}

	func applyTheme() {
		label.font = Theme.current.uiFont(11.5)
		label.textColor = Theme.current.sidebarHeaderText
		command.font = Theme.current.monoFont(11)
		command.textColor = Theme.current.sidebarHeaderText
		icon.image = Theme.symbol(
			"exclamationmark.triangle.fill", size: 12 * Theme.current.scale, color: Theme.current.gitConflict
		)
		copyButton.applyTheme()
		needsDisplay = true
	}

	/// What the strip says, for a driven run: the words are the requirement.
	var reportForTesting: String {
		isHidden ? "no strip" : "\(label.stringValue) \(command.stringValue)"
	}
}

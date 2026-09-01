import AppKit
import AbydosKit

/// A section title with a count and its bulk action.
final class SectionHeaderView: NSView, ScaleFollowing {
	var onAction: (() -> Void)?

	private let title: String
	private var count = 0
	private let button: DrawnButton
	private var strip: NSLayoutConstraint?

	override var isFlipped: Bool { true }

	init(title: String, actionTitle: String) {
		self.title = title
		let made = DrawnButton(title: actionTitle) {}
		button = made
		super.init(frame: .zero)

		made.onAction = { [weak self] in self?.buttonClicked() }
		button.translatesAutoresizingMaskIntoConstraints = false
		addSubview(button)

		// **Taken again on a zoom, which it was not.** The strip's height was
		// read once when the pane was built and the button inside it now grows
		// with the type, so at a large zoom the button had no room left in a
		// strip that had stayed 26 points — reported as `Stage` and `Unstage`
		// not having enough room.
		let height = heightAnchor.constraint(equalToConstant: Theme.current.scaled(26))
		strip = height
		ScaledControls.register(self)

		NSLayoutConstraint.activate([
			height,
			button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(8)),
			button.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func applyTheme() {
		strip?.constant = Theme.current.scaled(26)
		needsDisplay = true
	}

	func setCount(_ count: Int) {
		self.count = count
		button.isEnabled = count > 0
		needsDisplay = true
	}

	@objc private func buttonClicked() { onAction?() }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		let text = count > 0 ? "\(title) (\(count))" : title
		let label = NSAttributedString(string: text, attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(11), weight: .semibold),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		label.draw(at: NSPoint(x: Theme.current.scaled(8), y: bounds.midY - label.size().height / 2))
	}
}

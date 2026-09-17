import AppKit
import AbydosKit

/// One line of complaint over a pane, clickable.
///
/// Drawn rather than an `NSButton`, so it takes the theme's colours and the
/// zoom the way everything else in the strip does.
final class ErrorStripView: NSView {
	private let label = ScaledLabel("", size: 11) { Theme.current.editorText }
	private var height: NSLayoutConstraint!
	var onClick: (() -> Void)?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		height = heightAnchor.constraint(equalToConstant: Theme.current.scaled(22))
		NSLayoutConstraint.activate([
			height,
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(10)),
			label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Theme.current.scaled(10)),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyTheme()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Whether what is shown is a warning over a render that worked, rather
	/// than the error of one that did not: amber rather than red.
	private var isWarning = false

	func show(_ text: String, warning: Bool = false, detail: String? = nil) {
		isWarning = warning
		label.stringValue = "⚠︎ " + text
		label.toolTip = detail ?? text
		applyTheme()
	}

	func applyTheme() {
		height.constant = isHidden ? 0 : Theme.current.scaled(22)
		let tint = isWarning ? Theme.current.gitModified : Theme.current.gitConflict
		layer?.backgroundColor = tint.withAlphaComponent(0.18).cgColor
	}

	override var isHidden: Bool {
		didSet { height.constant = isHidden ? 0 : Theme.current.scaled(22) }
	}

	override func mouseDown(with event: NSEvent) { onClick?() }

	override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

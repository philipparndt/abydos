import AppKit
import IdeaiKit

/// Shown in the editor area when a file cannot be displayed as text.
///
/// Deliberately not an alert: a modal interrupts, has to be dismissed before you
/// can do anything, and leaves you with nothing to show for it. As editor
/// content it can sit there, explain itself, and offer the two things actually
/// worth doing with a binary file.
final class FileNoticeView: NSView {
	var onOpenExternally: (() -> Void)?
	var onOpenHexEditor: (() -> Void)?

	private let url: URL
	private let reason: String

	init(url: URL, reason: String) {
		self.url = url
		self.reason = reason
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		let icon = NSImageView()
		icon.image = FileIcon.image(for: FileNode(url: url, isDirectory: false), isExpanded: false)
		icon.imageScaling = .scaleProportionallyUpOrDown
		icon.translatesAutoresizingMaskIntoConstraints = false
		icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
		icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

		let title = NSTextField(labelWithString: url.lastPathComponent)
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		title.textColor = Theme.current.sidebarHeaderText
		title.alignment = .center

		let detail = NSTextField(labelWithString: reason)
		detail.font = .systemFont(ofSize: 12)
		detail.textColor = Theme.current.gitIgnored
		detail.alignment = .center

		let hexButton = makeButton(title: "Open in Hex Editor", symbol: "number") { [weak self] in
			self?.onOpenHexEditor?()
		}
		let externalButton = makeButton(title: "Open Externally", symbol: "arrow.up.forward.app") { [weak self] in
			self?.onOpenExternally?()
		}

		let buttons = NSStackView(views: [hexButton, externalButton])
		buttons.orientation = .horizontal
		buttons.spacing = 10

		let stack = NSStackView(views: [icon, title, detail, buttons])
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 10
		stack.setCustomSpacing(16, after: detail)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
		])
	}

	private func makeButton(title: String, symbol: String, action: @escaping () -> Void) -> NSButton {
		let button = NoticeButton(title: title, symbol: symbol)
		button.onClick = action
		return button
	}
}

/// Flat themed button; `NSButton`'s stock appearance does not match this window.
private final class NoticeButton: NSButton {
	var onClick: (() -> Void)?

	private let label: String
	private let symbol: String
	private var isHovered = false {
		didSet { needsDisplay = true }
	}
	private var trackingArea: NSTrackingArea?

	init(title: String, symbol: String) {
		self.label = title
		self.symbol = symbol
		super.init(frame: .zero)
		isBordered = false
		title.isEmpty ? () : (self.title = "")
		translatesAutoresizingMaskIntoConstraints = false
		heightAnchor.constraint(equalToConstant: 30).isActive = true
		widthAnchor.constraint(equalToConstant: measuredWidth()).isActive = true
		target = self
		action = #selector(clicked)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func measuredWidth() -> CGFloat {
		let font = NSFont.systemFont(ofSize: 12.5)
		let width = (label as NSString).size(withAttributes: [.font: font]).width
		return ceil(width) + 24 + 20
	}

	@objc private func clicked() { onClick?() }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) { isHovered = true }
	override func mouseExited(with event: NSEvent) { isHovered = false }

	override func draw(_ dirtyRect: NSRect) {
		let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
		(isHovered ? NSColor.white.withAlphaComponent(0.10) : NSColor.white.withAlphaComponent(0.05)).setFill()
		path.fill()
		Theme.current.separator.setStroke()
		path.lineWidth = 1
		path.stroke()

		var x: CGFloat = 10
		if let icon = Theme.symbol(symbol, size: 12, color: Theme.current.sidebarText) {
			icon.draw(
				in: NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
		}
		x += 20

		let attributed = NSAttributedString(string: label, attributes: [
			.font: NSFont.systemFont(ofSize: 12.5),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		attributed.draw(at: NSPoint(x: x, y: bounds.midY - attributed.size().height / 2))
	}
}

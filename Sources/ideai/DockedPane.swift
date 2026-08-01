import AppKit

/// Something docked into the sidebar, with a strip saying what it is.
///
/// The strip is the whole difference between a docked pane and a view that
/// merely appeared: it names what you are looking at and gives you a way to
/// put it away, which a window's titlebar was doing until it was docked.
final class DockedPane: NSView {
	var onClose: (() -> Void)?

	private let titleText: String
	private let content: NSView
	private var closeButton: NSButton!

	private static var headerHeight: CGFloat { Theme.current.scaled(26) }

	init(title: String, content: NSView) {
		self.titleText = title
		self.content = content
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		closeButton = NSButton(title: "", target: self, action: #selector(closeClicked))
		closeButton.isBordered = false
		closeButton.image = Theme.symbol("xmark", size: 9 * Theme.current.scale, color: Theme.current.gitIgnored)
		closeButton.imagePosition = .imageOnly
		closeButton.toolTip = "Close"

		content.translatesAutoresizingMaskIntoConstraints = false
		closeButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(content)
		addSubview(closeButton)

		NSLayoutConstraint.activate([
			closeButton.topAnchor.constraint(equalTo: topAnchor, constant: Theme.current.scaled(5)),
			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(8)),
			closeButton.widthAnchor.constraint(equalToConstant: Theme.current.scaled(16)),
			closeButton.heightAnchor.constraint(equalToConstant: Theme.current.scaled(16)),

			content.topAnchor.constraint(equalTo: topAnchor, constant: Self.headerHeight),
			content.leadingAnchor.constraint(equalTo: leadingAnchor),
			content.trailingAnchor.constraint(equalTo: trailingAnchor),
			content.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@objc private func closeClicked() { onClose?() }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()

		let title = NSAttributedString(string: titleText.uppercased(), attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(10), weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		title.draw(at: NSPoint(
			x: Theme.current.scaled(10),
			y: (Self.headerHeight - title.size().height) / 2
		))

		Theme.current.separator.setFill()
		NSRect(x: 0, y: Self.headerHeight - 1, width: bounds.width, height: 1).fill()
	}
}

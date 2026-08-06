import AppKit
import AbydosKit

/// The whole story behind a toast.
///
/// Its own panel rather than an alert. What lands here is usually output —
/// what helm said, what the compiler said, what kubectl said — and a system
/// alert reflows that into a paragraph, wraps the paths in the middle of a
/// word and offers no way to read past the twentieth line. Here it is
/// monospaced, scrollable, and can be copied whole.
@MainActor
final class DetailDialog: NSObject {
	private var window: NSPanel?
	private let title: String
	private let detail: String
	private let isError: Bool

	init(title: String, detail: String, isError: Bool) {
		self.title = title
		self.detail = detail
		self.isError = isError
		super.init()
	}

	/// Kept alive while it is on screen: a child window has no other owner.
	private static var open: [DetailDialog] = []

	func show(over parent: NSWindow?) {
		guard let parent else { return }
		let window = makeWindow()
		self.window = window
		Self.open.append(self)

		let frame = parent.frame
		let size = window.frame.size
		window.setFrameOrigin(NSPoint(
			x: frame.midX - size.width / 2,
			y: frame.midY - size.height / 2 + frame.height * 0.08
		))

		parent.addChildWindow(window, ordered: .above)
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
		} else {
			window.orderFront(nil)
		}
	}

	@objc private func close() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		self.window = nil
		Self.open.removeAll { $0 === self }
	}

	@objc private func copyAll() {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString("\(title)\n\n\(detail)", forType: .string)
	}

	private func makeWindow() -> NSPanel {
		let heading = NSTextField(labelWithString: title)
		heading.font = Theme.current.uiFont(15, weight: .semibold)
		heading.textColor = isError ? .hex(0xE05252) : Theme.current.sidebarHeaderText
		heading.lineBreakMode = .byTruncatingTail

		// Monospaced and selectable: this is output, and the first thing
		// anybody does with output is copy a line of it into a search.
		let text = NSTextView()
		text.string = detail
		text.isEditable = false
		text.isSelectable = true
		text.drawsBackground = true
		text.backgroundColor = Theme.current.editorBackground
		text.textColor = Theme.current.sidebarText
		text.font = Theme.terminalFont(size: Theme.current.fontSize - 1)
		text.textContainerInset = NSSize(width: 8, height: 8)
		text.isAutomaticQuoteSubstitutionEnabled = false

		let scroll = NSScrollView()
		scroll.documentView = text
		scroll.hasVerticalScroller = true

		// Without these the text is laid out into a container of zero width, and
		// a container that narrow cannot fit a single character: every glyph is
		// pushed onto a line of its own, off the left edge, and the dialog comes
		// up empty with a scroller that says there is a great deal of it. Which
		// is what "the install instructions are missing" turned out to be.
		//
		// A plain `NSTextView()` has a zero frame, and a scroll view does not
		// size its document view unless the view says it tracks the width.
		text.autoresizingMask = [.width]
		text.isVerticallyResizable = true
		text.isHorizontallyResizable = false
		text.textContainer?.widthTracksTextView = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.editorBackground
		scroll.borderType = .noBorder
		scroll.wantsLayer = true
		scroll.layer?.cornerRadius = 6

		let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyAll))
		copyButton.bezelStyle = .rounded

		let okButton = NSButton(title: "OK", target: self, action: #selector(close))
		okButton.bezelStyle = .rounded
		okButton.keyEquivalent = "\r"

		let content = ColoredView(color: Theme.current.sidebarBackground)
		for view in [heading, scroll, copyButton, okButton] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}

		NSLayoutConstraint.activate([
			heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
			heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
			heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),

			scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
			scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
			scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
			scroll.bottomAnchor.constraint(equalTo: okButton.topAnchor, constant: -14),

			okButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
			okButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
			copyButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -8),
			copyButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
		])

		// As tall as the text needs, within reason: a one-line message should
		// not open a window the size of a document.
		let lines = detail.components(separatedBy: "\n").count
		let height = min(560, max(220, CGFloat(lines) * 16 + 150))

		let window = DetailPanel(
			contentRect: NSRect(x: 0, y: 0, width: 620, height: height),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: true
		)
		window.title = isError ? "Error" : "Details"
		window.backgroundColor = Theme.current.sidebarBackground
		window.contentView = content
		window.onCancel = { [weak self] in self?.close() }
		return window
	}
}

private final class DetailPanel: NSPanel {
	var onCancel: (() -> Void)?
	override var canBecomeKey: Bool { true }

	override func close() { onCancel?() }
	override func cancelOperation(_ sender: Any?) { onCancel?() }
}

import AppKit
import IdeaiKit

/// A terminal that was dragged out of the panel, in a window of its own.
///
/// One shell, no tabs: the point of pulling a terminal out is to put it on
/// another display or beside something else, and a second tab strip in a
/// second window is a place for terminals to get lost in.
@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
	/// Kept alive while it is on screen — nothing else owns it.
	private static var open: [TerminalWindowController] = []

	private let pane: TerminalPane

	init(pane: TerminalPane, title: String, at screenPoint: NSPoint) {
		self.pane = pane

		let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
		let frame = TearOff.windowFrame(
			droppedAt: screenPoint,
			size: NSSize(width: 720, height: 420),
			visibleFrame: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
		)

		let window = NSWindow(
			contentRect: frame,
			styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.title = title
		window.titlebarAppearsTransparent = true
		window.backgroundColor = Theme.current.editorBackground
		window.isReleasedWhenClosed = false
		window.minSize = NSSize(width: 320, height: 180)
		super.init(window: window)

		let content = ColoredView(color: Theme.current.editorBackground)
		pane.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(pane)
		NSLayoutConstraint.activate([
			pane.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			pane.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			// Clear of the titlebar it draws under.
			pane.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
			pane.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])
		window.contentView = content
		window.delegate = self

		// The shell reports what it is running, and out here the window title
		// is the only place left to say so.
		pane.terminalView.onTitleChange = { [weak window] reported in
			let trimmed = reported.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty else { return }
			window?.title = trimmed
		}

		Self.open.append(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func show() {
		if ProcessInfo.processInfo.environment["IDEAI_TEAROFF_DEBUG"] != nil {
			FileHandle.standardError.write(Data(
				"[tearoff] window \"\(window?.title ?? "?")\" at \(window?.frame ?? .zero)\n".utf8
			))
		}
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
		pane.focus()
	}

	/// Closing the window ends the shell: it has nowhere else to be.
	func windowWillClose(_ notification: Notification) {
		pane.terminalView.terminateProcess()
		Self.open.removeAll { $0 === self }
	}
}

import AppKit
import IdeaiKit

/// Terminals that were dragged out of the panel, in a window of their own.
///
/// The same terminal area as the panel's, chrome aside: tabs, a +, renaming,
/// dragging between windows and splitting side by side all work out here,
/// because a terminal put on a second display is still a terminal somebody
/// works in. What it does not have is a panel's own controls — there is
/// nothing to hide it into, and following a shell's project belongs to a
/// window that has a project.
@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
	/// Kept alive while it is on screen — nothing else owns it.
	private static var open: [TerminalWindowController] = []

	private let panel = BottomPanel()
	/// Opens another of these, for a terminal dragged out of this one.
	private let openAnother: (DetachedTerminal, NSPoint) -> Void

	init(
		detached: DetachedTerminal,
		at screenPoint: NSPoint,
		workingDirectory: URL?,
		openAnother: @escaping (DetachedTerminal, NSPoint) -> Void
	) {
		self.openAnother = openAnother

		let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
		let frame = TearOff.windowFrame(
			droppedAt: screenPoint,
			size: NSSize(width: 760, height: 460),
			visibleFrame: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
		)

		let window = NSWindow(
			contentRect: frame,
			styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.title = detached.title
		window.titlebarAppearsTransparent = true
		window.backgroundColor = Theme.current.editorBackground
		window.isReleasedWhenClosed = false
		window.minSize = NSSize(width: 360, height: 200)
		super.init(window: window)

		panel.becomeTerminalWindow()
		panel.setWorkingDirectory(workingDirectory ?? detached.directory)
		panel.adoptTerminal(detached)

		// A terminal can leave here too, into a window of its own.
		panel.onTearOffTerminal = { [weak self] detached, point in
			self?.openAnother(detached, point)
		}
		// The last tab closing leaves an empty window, which is a window with
		// nothing to be.
		panel.onRequestHide = { [weak self] in self?.window?.performClose(nil) }
		panel.onActiveTerminalChanged = { [weak self] in
			guard let self else { return }
			self.window?.title = self.panel.activeTerminalTitle ?? "Terminal"
		}

		let content = ColoredView(color: Theme.current.editorBackground)
		panel.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(panel)
		NSLayoutConstraint.activate([
			panel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			panel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			// Clear of the titlebar the window draws under.
			panel.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
			panel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])
		window.contentView = content
		window.delegate = self

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
		panel.focusActive()
	}

	/// Closing the window ends its shells: they have nowhere else to be.
	func windowWillClose(_ notification: Notification) {
		panel.closeTerminals()
		Self.open.removeAll { $0 === self }
	}
}

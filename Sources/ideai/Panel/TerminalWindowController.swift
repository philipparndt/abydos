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
	private var name: String
	private var isRenamed: Bool
	private let directory: URL?
	/// This window, as somewhere a terminal can be dragged from.
	private let sourceID = UUID()
	private let strip = PanelTabStrip()
	/// Set while the terminal is being handed to somebody else, so closing the
	/// window does not also kill the shell.
	private var isGivingUpTerminal = false

	init(
		pane: TerminalPane,
		title: String,
		at screenPoint: NSPoint,
		isRenamed: Bool = false,
		directory: URL? = nil
	) {
		self.pane = pane
		self.name = title
		self.isRenamed = isRenamed
		self.directory = directory

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

		// A strip with the one tab in it, so the terminal can be dragged back
		// into the panel it came from. Without it a torn-off terminal is out
		// there for good, which makes tearing one off a decision rather than a
		// gesture.
		strip.panelID = sourceID
		strip.showsPanelControls = false
		strip.setUpTabDropping()
		strip.canDrag = { _ in true }
		strip.setItems([PanelTabItem(title: title, hasExited: false, canRename: true, isShowing: true)], activeIndex: 0)
		strip.onRename = { [weak self] _, newName in self?.rename(to: newName) }
		strip.onClose = { [weak self] _ in self?.window?.performClose(nil) }

		for view in [strip, pane] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}
		NSLayoutConstraint.activate([
			// Clear of the titlebar the window draws under.
			strip.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
			strip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			strip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			strip.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30)),

			pane.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			pane.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			pane.topAnchor.constraint(equalTo: strip.bottomAnchor),
			pane.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])
		window.contentView = content
		window.delegate = self

		// The shell reports what it is running, and out here the window title
		// is the only place left to say so.
		pane.terminalView.onTitleChange = { [weak self] reported in
			guard let self, !self.isRenamed else { return }
			let trimmed = reported.split(separator: " ").first.map(String.init) ?? reported
			guard !trimmed.isEmpty else { return }
			self.name = trimmed
			self.window?.title = trimmed
			self.strip.setItems(
				[PanelTabItem(title: trimmed, hasExited: false, canRename: true, isShowing: true)],
				activeIndex: 0
			)
		}

		TerminalDragSources.register(self, as: sourceID)
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

	private func rename(to newName: String) {
		let trimmed = newName.trimmingCharacters(in: .whitespaces)
		isRenamed = !trimmed.isEmpty
		name = trimmed.isEmpty ? name : trimmed
		window?.title = name
		strip.setItems(
			[PanelTabItem(title: name, hasExited: false, canRename: true, isShowing: true)],
			activeIndex: 0
		)
	}

	/// Closing the window ends the shell: it has nowhere else to be — unless it
	/// has just been dragged somewhere that does want it.
	func windowWillClose(_ notification: Notification) {
		if !isGivingUpTerminal { pane.terminalView.terminateProcess() }
		TerminalDragSources.unregister(sourceID)
		Self.open.removeAll { $0 === self }
	}
}


/// Dragging the terminal back where it came from.
extension TerminalWindowController: TerminalDragSource {
	func detachTerminal(at index: Int) -> DetachedTerminal? {
		isGivingUpTerminal = true
		pane.terminalView.onTitleChange = nil
		pane.removeFromSuperview()
		window?.close()
		return DetachedTerminal(pane: pane, title: name, isRenamed: isRenamed, directory: directory)
	}
}

import AppKit
import IdeaiKit

/// The tool panel below the editor: terminals now, agent sessions next.
///
/// Sessions are owned here rather than by whichever view is showing them. That
/// is what lets a pane be hidden and shown again — or handed over for manual
/// takeover — while its process keeps running.
final class BottomPanel: NSView {
	/// Fired when the panel wants to be hidden, so the window can collapse it.
	var onRequestHide: (() -> Void)?

	private final class Session {
		enum Kind {
			case terminal(TerminalPane)
			/// A review keeps its agent terminal inside the pane, so switching to
			/// the chat is a view change rather than a new process.
			case review(ReviewPane, TerminalPane)
			case search(SearchPane)
			case debug(DebugPane)
		}

		let title: String
		var displayTitle: String
		let kind: Kind
		var hasExited = false

		init(title: String, kind: Kind) {
			self.title = title
			self.displayTitle = title
			self.kind = kind
		}

		/// The view installed in the content area.
		var view: NSView {
			switch kind {
			case let .terminal(pane): return pane
			case let .review(pane, _): return pane
			case let .search(pane): return pane
			case let .debug(pane): return pane
			}
		}

		/// The terminal behind this session, if it has one.
		var terminal: TerminalPane? {
			switch kind {
			case let .terminal(pane): return pane
			case let .review(_, pane): return pane
			case .search, .debug: return nil
			}
		}
	}

	private var sessions: [Session] = []
	private var activeIndex: Int?
	private var workingDirectory: URL?

	/// Forwarded when a review finding or a search result is activated.
	var onOpenFinding: ((URL, Int) -> Void)?

	private var tabStrip: PanelTabStrip!
	private var contentArea: NSView!
	private var placeholder: NSTextField!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		tabStrip = PanelTabStrip()
		tabStrip.onSelect = { [weak self] index in self?.activate(index: index, focus: true) }
		tabStrip.onClose = { [weak self] index in self?.close(index: index) }
		tabStrip.onAdd = { [weak self] in self?.newTerminal() }
		tabStrip.onHide = { [weak self] in self?.onRequestHide?() }

		contentArea = NSView()

		placeholder = NSTextField(labelWithString: "No terminal open")
		placeholder.font = Theme.current.uiFont(12)
		placeholder.textColor = Theme.current.gitIgnored

		for subview in [tabStrip, contentArea, placeholder] as [NSView] {
			addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		tabStripHeight = tabStrip.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))

		NSLayoutConstraint.activate([
			tabStrip.topAnchor.constraint(equalTo: topAnchor),
			tabStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
			tabStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
			tabStripHeight,

			contentArea.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),

			placeholder.centerXAnchor.constraint(equalTo: contentArea.centerXAnchor),
			placeholder.centerYAnchor.constraint(equalTo: contentArea.centerYAnchor),
		])
	}

	private var tabStripHeight: NSLayoutConstraint!

	// MARK: - Project

	func setWorkingDirectory(_ url: URL?) {
		workingDirectory = url
	}

	var hasSessions: Bool { !sessions.isEmpty }

	// MARK: - Sessions

	/// Opens a shell, or focuses the existing one if there already is a terminal.
	@discardableResult
	func showTerminal() -> TerminalPane? {
		if sessions.isEmpty {
			return newTerminal()
		}
		activate(index: activeIndex ?? 0, focus: true)
		return sessions[activeIndex ?? 0].terminal
	}

	/// Opens a shell rooted at a specific directory, for "Open Terminal Here".
	///
	/// Always a new session: the point is the directory, and reusing a shell that
	/// is already somewhere else — possibly mid-command — would not honour it.
	@discardableResult
	func newTerminal(in directory: URL) -> TerminalPane? {
		newTerminal(rootedAt: directory, title: directory.lastPathComponent)
	}

	@discardableResult
	func newTerminal() -> TerminalPane? {
		newTerminal(rootedAt: workingDirectory, title: "Local")
	}

	@discardableResult
	private func newTerminal(rootedAt directory: URL?, title: String) -> TerminalPane? {
		let pane = TerminalPane(workingDirectory: directory)
		let session = Session(title: title, kind: .terminal(pane))
		wire(session)

		sessions.append(session)
		activate(index: sessions.count - 1, focus: true)
		return pane
	}

	/// Runs a command in a new pane, in a directory of its own.
	///
	/// Through a login shell rather than exec'd directly: a run configuration
	/// names `go` or `make`, and a GUI app's PATH does not have them — the
	/// shell is what knows where the user's tools are.
	@discardableResult
	func runCommand(
		title: String,
		command: String,
		directory: URL,
		environment: [String: String] = [:]
	) -> TerminalPane? {
		let assignments = environment
			.sorted { $0.key < $1.key }
			.map { "\($0.key)=\($0.value.replacingOccurrences(of: "'", with: "'\\''"))" }
			.joined(separator: " ")
		let line = assignments.isEmpty ? command : "env \(assignments) \(command)"

		return runCommand(
			title: title,
			executable: "/bin/sh",
			arguments: ["-lc", line],
			workingDirectory: directory
		)
	}

	/// Runs a command in a new pane. The basis for "Run" and for agent sessions.
	@discardableResult
	func runCommand(
		title: String,
		executable: String,
		arguments: [String],
		workingDirectory: URL? = nil
	) -> TerminalPane? {
		let pane = TerminalPane(
			workingDirectory: workingDirectory ?? self.workingDirectory,
			command: (executable: executable, arguments: arguments)
		)
		let session = Session(title: title, kind: .terminal(pane))
		wire(session)

		sessions.append(session)
		activate(index: sessions.count - 1, focus: true)
		return pane
	}

	// MARK: - Search

	/// Shows project search, reusing the existing pane if there is one.
	@discardableResult
	func showSearch(query: String? = nil) -> SearchPane? {
		guard let root = workingDirectory else { return nil }

		if let index = sessions.firstIndex(where: { if case .search = $0.kind { return true }; return false }),
		   case let .search(pane) = sessions[index].kind {
			activate(index: index, focus: false)
			if let query { pane.setQuery(query) }
			pane.focusField()
			return pane
		}

		let pane = SearchPane(projectRoot: root)
		pane.onOpenResult = { [weak self] url, line, _ in
			self?.onOpenFinding?(url, line)
		}
		let session = Session(title: "Search", kind: .search(pane))
		sessions.append(session)
		activate(index: sessions.count - 1, focus: false)
		if let query { pane.setQuery(query) }
		pane.focusField()
		return pane
	}

	// MARK: - Debugging

	/// Starts a native debug session for a Go package.
	@discardableResult
	func startDebugging(delve: String, package: String) -> DebugSession? {
		guard let root = workingDirectory else { return nil }

		// One debug session at a time; a second would fight over breakpoints.
		if let index = sessions.firstIndex(where: { if case .debug = $0.kind { return true }; return false }) {
			close(index: index)
		}

		let session = DebugSession(projectRoot: root)
		let pane = DebugPane(session: session, projectRoot: root)
		pane.onNavigate = { [weak self] url, line in
			self?.onOpenFinding?(url, line)
		}
		// Straight to the pane's console: `debugOutput` was a hook nobody ever
		// assigned, so every build error and every line the program printed was
		// dropped on the floor.
		session.onOutput = { [weak self, weak pane] text in
			pane?.appendOutput(text)
			self?.debugOutput?(text)
		}
		session.onLaunchStalled = { [weak self, weak pane] message in
			pane?.appendOutput("\n" + message + "\n")
			self?.debugOutput?("\n" + message + "\n")
			let alert = NSAlert()
			alert.messageText = "The debugger did not start"
			alert.informativeText = message
			if let window = self?.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
		}

		let panelSession = Session(title: "Debug", kind: .debug(pane))
		sessions.append(panelSession)
		activate(index: sessions.count - 1, focus: false)

		Task {
			do {
				try await session.launch(delveExecutable: delve, package: package)
			} catch {
				await MainActor.run {
					let alert = NSAlert()
					alert.messageText = "Could not start the debugger"
					alert.informativeText = error.localizedDescription
					alert.runModal()
				}
			}
		}
		return session
	}

	/// Forwarded debuggee output.
	var debugOutput: ((String) -> Void)?

	/// The running debug session, if any.
	var activeDebugSession: DebugSession? {
		for session in sessions {
			if case let .debug(pane) = session.kind { return pane.debugSession }
		}
		return nil
	}

	// MARK: - Review

	/// Starts an agent review of whatever `scope` names.
	///
	/// The agent reports through this window's own MCP server, so findings
	/// arrive as typed data rather than as text to be parsed out of a TUI.
	@discardableResult
	func startReview(scope: AgentLauncher.ReviewScope) -> Result<Void, ReviewStartError> {
		guard let root = workingDirectory else { return .failure(.noProject) }
		guard let executable = AgentLauncher.findClaudeExecutable() else {
			return .failure(.claudeNotFound)
		}

		let reviewSession = ReviewSession(projectRoot: root)
		let server = MCPServer()
		for tool in reviewSession.makeTools() { server.register(tool) }

		do {
			try server.start()
		} catch {
			return .failure(.serverFailed)
		}

		let command = AgentLauncher.reviewCommand(
			executable: executable,
			server: server,
			prompt: AgentLauncher.reviewPrompt(scope: scope)
		)
		let terminal = TerminalPane(
			workingDirectory: root,
			command: (executable: command.executable, arguments: command.arguments)
		)
		let reviewPane = ReviewPane(session: reviewSession, server: server, terminalPane: terminal)
		reviewPane.onOpenFinding = { [weak self] url, line in
			self?.onOpenFinding?(url, line)
		}

		let session = Session(title: scope.title, kind: .review(reviewPane, terminal))
		wire(session)
		sessions.append(session)
		activate(index: sessions.count - 1, focus: false)
		return .success(())
	}

	enum ReviewStartError: Error {
		case noProject
		case claudeNotFound
		case serverFailed

		var message: String {
			switch self {
			case .noProject: return "Open a project first."
			case .claudeNotFound:
				return "Could not find the `claude` executable. Install Claude Code, or make sure it is in /opt/homebrew/bin or /usr/local/bin."
			case .serverFailed: return "Could not start the local MCP server."
			}
		}
	}

	private func wire(_ session: Session) {
		guard let terminal = session.terminal else { return }
		terminal.terminalView.onProcessExit = { [weak self, weak session] _ in
			guard let self, let session else { return }
			session.hasExited = true
			self.refreshTabs()
		}
		// A review's tab keeps its own name; only a shell borrows the command
		// name from the title sequence.
		guard case .terminal = session.kind else { return }
		terminal.terminalView.onTitleChange = { [weak self, weak session] title in
			guard let self, let session else { return }
			// A shell reports its running command via the title, which is the
			// most useful label a terminal tab can carry.
			let trimmed = title.split(separator: " ").first.map(String.init) ?? title
			guard !trimmed.isEmpty, session.displayTitle != trimmed else { return }
			session.displayTitle = trimmed
			self.refreshTabs()
		}
	}

	private func activate(index: Int, focus: Bool) {
		guard sessions.indices.contains(index) else { return }
		contentArea.subviews.forEach { $0.removeFromSuperview() }

		activeIndex = index
		let session = sessions[index]
		let view = session.view
		view.translatesAutoresizingMaskIntoConstraints = false
		contentArea.addSubview(view)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: contentArea.topAnchor),
			view.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
		])

		placeholder.isHidden = true
		refreshTabs()
		if focus, case .terminal = session.kind { session.terminal?.focus() }
	}

	private func close(index: Int) {
		guard sessions.indices.contains(index) else { return }
		let session = sessions[index]
		switch session.kind {
		case let .review(pane, _): pane.shutdown()
		case let .debug(pane): pane.shutdown()
		default: session.terminal?.terminalView.terminateProcess()
		}
		session.view.removeFromSuperview()
		sessions.remove(at: index)

		if sessions.isEmpty {
			activeIndex = nil
			contentArea.subviews.forEach { $0.removeFromSuperview() }
			placeholder.isHidden = false
			refreshTabs()
			onRequestHide?()
			return
		}
		activeIndex = nil
		activate(index: min(index, sessions.count - 1), focus: false)
	}

	private func refreshTabs() {
		tabStrip.setItems(
			sessions.map { PanelTabItem(title: $0.displayTitle, hasExited: $0.hasExited) },
			activeIndex: activeIndex
		)
	}

	// MARK: - Commands

	func focusActive() {
		guard let activeIndex, sessions.indices.contains(activeIndex) else { return }
		sessions[activeIndex].terminal?.focus()
	}

	func applySettings() {
		tabStripHeight.constant = Theme.current.scaled(30)
		placeholder.font = Theme.current.uiFont(12)
		tabStrip.applyThemeChange()
		for session in sessions {
			switch session.kind {
			case let .review(pane, _): pane.applySettings()
			case let .search(pane): pane.applySettings()
			case let .debug(pane): pane.applySettings()
			case let .terminal(pane): pane.terminalView.applyThemeChange()
			}
		}
	}

	/// Terminates every session. Called when the window closes.
	func shutdown() {
		for session in sessions {
			switch session.kind {
			case let .review(pane, _): pane.shutdown()
			case let .debug(pane): pane.shutdown()
			default: session.terminal?.terminalView.terminateProcess()
			}
		}
		sessions.removeAll()
	}
}

// MARK: - Tab strip

struct PanelTabItem {
	let title: String
	let hasExited: Bool
}

/// Compact tab strip with add and hide affordances.
final class PanelTabStrip: NSView {
	var onSelect: ((Int) -> Void)?
	var onClose: ((Int) -> Void)?
	var onAdd: (() -> Void)?
	var onHide: (() -> Void)?

	private var items: [PanelTabItem] = []
	private var activeIndex: Int?
	private var frames: [NSRect] = []
	private var addButtonFrame: NSRect = .zero
	private var hideButtonFrame: NSRect = .zero
	private var hoveredIndex: Int?
	private var trackingArea: NSTrackingArea?

	override var isFlipped: Bool { true }

	func setItems(_ items: [PanelTabItem], activeIndex: Int?) {
		self.items = items
		self.activeIndex = activeIndex
		recomputeLayout()
		needsDisplay = true
	}

	func applyThemeChange() {
		recomputeLayout()
		needsDisplay = true
	}

	private var font: NSFont { Theme.current.uiFont(11.5) }
	private var closeSize: CGFloat { Theme.current.scaled(12) }
	private var padding: CGFloat { Theme.current.scaled(10) }

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		recomputeLayout()
	}

	private func recomputeLayout() {
		frames.removeAll()
		var x = Theme.current.scaled(8)
		for item in items {
			let width = (item.title as NSString).size(withAttributes: [.font: font]).width
				+ padding * 2 + closeSize
			frames.append(NSRect(x: x, y: 0, width: ceil(width), height: bounds.height))
			x += ceil(width) + Theme.current.scaled(2)
		}
		addButtonFrame = NSRect(x: x + Theme.current.scaled(4), y: 0, width: Theme.current.scaled(24), height: bounds.height)
		hideButtonFrame = NSRect(
			x: bounds.width - Theme.current.scaled(30),
			y: 0,
			width: Theme.current.scaled(24),
			height: bounds.height
		)
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp], owner: self)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let index = frames.firstIndex { $0.contains(point) }
		if index != hoveredIndex {
			hoveredIndex = index
			needsDisplay = true
		}
	}

	override func mouseExited(with event: NSEvent) {
		hoveredIndex = nil
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)

		if addButtonFrame.contains(point) { onAdd?(); return }
		if hideButtonFrame.contains(point) { onHide?(); return }

		guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return }
		let closeRect = NSRect(
			x: frames[index].maxX - padding - closeSize,
			y: frames[index].midY - closeSize / 2,
			width: closeSize,
			height: closeSize
		)
		if closeRect.contains(point) {
			onClose?(index)
		} else {
			onSelect?(index)
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		for (index, item) in items.enumerated() where index < frames.count {
			draw(item: item, in: frames[index], isActive: index == activeIndex, isHovered: index == hoveredIndex)
		}

		drawGlyph(in: addButtonFrame, symbol: "plus")
		drawGlyph(in: hideButtonFrame, symbol: "chevron.down")
	}

	private func draw(item: PanelTabItem, in rect: NSRect, isActive: Bool, isHovered: Bool) {
		if isActive {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.10).setFill()
			path.fill()
		} else if isHovered {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.05).setFill()
			path.fill()
		}

		// An exited session is dimmed rather than removed, so output stays
		// readable after the process finishes.
		let color = item.hasExited
			? Theme.current.gitIgnored
			: (isActive ? Theme.current.sidebarHeaderText : Theme.current.sidebarText)

		let label = NSAttributedString(string: item.title, attributes: [
			.font: font,
			.foregroundColor: color,
		])
		let size = label.size()
		label.draw(at: NSPoint(x: rect.minX + padding, y: rect.midY - size.height / 2))

		if isActive || isHovered {
			let close = NSRect(
				x: rect.maxX - padding - closeSize,
				y: rect.midY - closeSize / 2,
				width: closeSize,
				height: closeSize
			)
			let cross = NSBezierPath()
			let inset = Theme.current.scaled(3)
			cross.move(to: NSPoint(x: close.minX + inset, y: close.minY + inset))
			cross.line(to: NSPoint(x: close.maxX - inset, y: close.maxY - inset))
			cross.move(to: NSPoint(x: close.maxX - inset, y: close.minY + inset))
			cross.line(to: NSPoint(x: close.minX + inset, y: close.maxY - inset))
			cross.lineWidth = 1.2
			cross.lineCapStyle = .round
			Theme.current.sidebarText.setStroke()
			cross.stroke()
		}
	}

	private func drawGlyph(in rect: NSRect, symbol: String) {
		guard let image = Theme.symbol(symbol, size: 11 * Theme.current.scale, color: Theme.current.sidebarText) else {
			return
		}
		let size = Theme.current.scaled(12)
		image.draw(
			in: NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size),
			from: .zero,
			operation: .sourceOver,
			fraction: 1.0,
			respectFlipped: true,
			hints: nil
		)
	}
}

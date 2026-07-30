import AppKit
import IdeaiKit

/// A review driven by an agent: structured findings, with the live session
/// behind a toggle.
///
/// One session, two presentations. The findings come in over MCP as typed data,
/// so they are navigable rather than scraped text. The same session's terminal
/// is one click away, which is what "jump in and take over" means here — the
/// process never stopped, the view just changed.
final class ReviewPane: NSView {
	/// Called when a finding is activated, to open the file at that line.
	var onOpenFinding: ((URL, Int) -> Void)?

	private let session: ReviewSession
	private let terminalPane: TerminalPane
	private let server: MCPServer

	private var header: ReviewHeaderView!
	private var contentArea: NSView!
	private var findingsScrollView: NSScrollView!
	private var tableView: NSTableView!

	private enum Mode { case findings, chat }
	private var mode: Mode = .findings

	init(session: ReviewSession, server: MCPServer, terminalPane: TerminalPane) {
		self.session = session
		self.server = server
		self.terminalPane = terminalPane
		super.init(frame: .zero)

		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()

		session.onChange = { [weak self] in
			guard let self else { return }
			self.tableView.reloadData()
			self.header.update(
				status: self.session.statusMessage,
				findingCount: self.session.findings.count,
				isComplete: self.session.isComplete
			)
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		server.stop()
	}

	private func build() {
		header = ReviewHeaderView()
		header.onModeChange = { [weak self] showChat in
			self?.setMode(showChat ? .chat : .findings)
		}
		header.onStop = { [weak self] in
			self?.terminalPane.terminalView.sendInterrupt()
		}

		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.editorBackground
		table.selectionHighlightStyle = .regular
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("finding")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.action = #selector(rowClicked)
		tableView = table

		findingsScrollView = NSScrollView()
		findingsScrollView.documentView = table
		findingsScrollView.hasVerticalScroller = true
		findingsScrollView.drawsBackground = true
		findingsScrollView.backgroundColor = Theme.current.editorBackground
		findingsScrollView.scrollerStyle = .overlay

		contentArea = NSView()

		addSubview(header)
		addSubview(contentArea)
		header.translatesAutoresizingMaskIntoConstraints = false
		contentArea.translatesAutoresizingMaskIntoConstraints = false

		headerHeight = header.heightAnchor.constraint(equalToConstant: Theme.current.scaled(32))
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: topAnchor),
			header.leadingAnchor.constraint(equalTo: leadingAnchor),
			header.trailingAnchor.constraint(equalTo: trailingAnchor),
			headerHeight,

			contentArea.topAnchor.constraint(equalTo: header.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		setMode(.findings)
	}

	private var headerHeight: NSLayoutConstraint!

	private func setMode(_ newMode: Mode) {
		mode = newMode
		contentArea.subviews.forEach { $0.removeFromSuperview() }

		let view: NSView = (mode == .findings) ? findingsScrollView : terminalPane
		view.translatesAutoresizingMaskIntoConstraints = false
		contentArea.addSubview(view)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: contentArea.topAnchor),
			view.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
		])

		// Switching to the chat hands over the keyboard, so the user is talking
		// to the agent immediately rather than having to click first.
		if mode == .chat { terminalPane.focus() }
		header.setShowingChat(mode == .chat)
	}

	func applySettings() {
		headerHeight.constant = Theme.current.scaled(32)
		tableView.reloadData()
		terminalPane.terminalView.applyThemeChange()
		header.needsDisplay = true
	}

	func shutdown() {
		terminalPane.terminalView.terminateProcess()
		server.stop()
	}

	@objc private func rowClicked() {
		let row = tableView.clickedRow
		guard session.findings.indices.contains(row) else { return }
		let finding = session.findings[row]
		onOpenFinding?(session.absoluteURL(for: finding), finding.line)
	}
}

// MARK: - Findings table

extension ReviewPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int {
		session.findings.count
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		Theme.current.scaled(52)
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		FindingRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard session.findings.indices.contains(row) else { return nil }
		return FindingCellView(finding: session.findings[row])
	}
}

private final class FindingRowView: NSTableRowView {
	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selectionActive.setFill()
		bounds.fill()
	}

	override var isSelected: Bool {
		didSet { subviews.forEach { $0.needsDisplay = true } }
	}
}

private final class FindingCellView: NSView {
	private let finding: ReviewFinding

	init(finding: ReviewFinding) {
		self.finding = finding
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private var severityColor: NSColor {
		switch finding.severity {
		case .error: return Theme.current.gitConflict
		case .warning: return .hex(0xE8BF6A)
		case .info: return Theme.current.gitModified
		}
	}

	private var severitySymbol: String {
		switch finding.severity {
		case .error: return "exclamationmark.octagon.fill"
		case .warning: return "exclamationmark.triangle.fill"
		case .info: return "info.circle.fill"
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let inset = Theme.current.scaled(12)

		if let icon = Theme.symbol(severitySymbol, size: 12 * Theme.current.scale, color: severityColor) {
			let size = Theme.current.scaled(14)
			icon.draw(
				in: NSRect(x: inset, y: Theme.current.scaled(10), width: size, height: size),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
		}

		let textX = inset + Theme.current.scaled(22)
		let titleColor = isSelected ? NSColor.hex(0xE8EAED) : Theme.current.sidebarHeaderText

		let title = NSAttributedString(string: finding.title, attributes: [
			.font: Theme.current.uiFont(12.5, weight: .medium),
			.foregroundColor: titleColor,
		])
		title.draw(at: NSPoint(x: textX, y: Theme.current.scaled(7)))

		// Location and detail on one line, since a finding is only useful with
		// somewhere to go.
		let location = "\(finding.file):\(finding.line)"
		let locationString = NSAttributedString(string: location, attributes: [
			.font: Theme.terminalFont(size: Theme.current.uiFont(11).pointSize),
			.foregroundColor: isSelected ? NSColor.hex(0xC8CBD0) : Theme.current.gitModified,
		])
		locationString.draw(at: NSPoint(x: textX, y: Theme.current.scaled(26)))

		let detailX = textX + locationString.size().width + Theme.current.scaled(10)
		let detail = NSAttributedString(string: finding.detail, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: isSelected ? NSColor.hex(0xC8CBD0) : Theme.current.gitIgnored,
		])
		detail.draw(in: NSRect(
			x: detailX,
			y: Theme.current.scaled(26),
			width: max(0, bounds.width - detailX - inset),
			height: Theme.current.scaled(16)
		))
	}
}

// MARK: - Header

/// Status line with the findings/chat toggle.
private final class ReviewHeaderView: NSView {
	var onModeChange: ((Bool) -> Void)?
	var onStop: (() -> Void)?

	private var status: String?
	private var findingCount = 0
	private var isComplete = false
	private var showingChat = false

	private var findingsButtonFrame: NSRect = .zero
	private var chatButtonFrame: NSRect = .zero
	private var stopButtonFrame: NSRect = .zero

	override var isFlipped: Bool { true }

	func update(status: String?, findingCount: Int, isComplete: Bool) {
		self.status = status
		self.findingCount = findingCount
		self.isComplete = isComplete
		needsDisplay = true
	}

	func setShowingChat(_ showing: Bool) {
		showingChat = showing
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		if findingsButtonFrame.contains(point) { onModeChange?(false) }
		else if chatButtonFrame.contains(point) { onModeChange?(true) }
		else if stopButtonFrame.contains(point) { onStop?() }
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		// Status on the left: what the agent is doing, or the outcome.
		let text: String
		if let status, !status.isEmpty {
			text = status
		} else if isComplete {
			text = "Review complete"
		} else {
			text = "Reviewing…"
		}
		let summary = findingCount > 0 ? "\(text)  ·  \(findingCount) finding\(findingCount == 1 ? "" : "s")" : text

		let label = NSAttributedString(string: summary, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: isComplete ? Theme.current.gitAdded : Theme.current.sidebarText,
		])
		label.draw(at: NSPoint(x: Theme.current.scaled(12), y: bounds.midY - label.size().height / 2))

		// Toggle on the right.
		let buttonWidth = Theme.current.scaled(74)
		let buttonHeight = Theme.current.scaled(20)
		let y = bounds.midY - buttonHeight / 2
		var x = bounds.width - Theme.current.scaled(12) - buttonWidth

		chatButtonFrame = NSRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
		x -= buttonWidth + Theme.current.scaled(4)
		findingsButtonFrame = NSRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
		x -= Theme.current.scaled(28)
		stopButtonFrame = NSRect(x: x, y: y, width: Theme.current.scaled(22), height: buttonHeight)

		draw(button: findingsButtonFrame, title: "Findings", symbol: "list.bullet", isActive: !showingChat)
		draw(button: chatButtonFrame, title: "Chat", symbol: "bubble.left.and.bubble.right", isActive: showingChat)

		if !isComplete, let stop = Theme.symbol("stop.circle", size: 12 * Theme.current.scale, color: Theme.current.gitUnversioned) {
			let size = Theme.current.scaled(14)
			stop.draw(
				in: NSRect(x: stopButtonFrame.midX - size / 2, y: stopButtonFrame.midY - size / 2, width: size, height: size),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
		}
	}

	private func draw(button rect: NSRect, title: String, symbol: String, isActive: Bool) {
		let path = NSBezierPath(roundedRect: rect, xRadius: Theme.current.scaled(5), yRadius: Theme.current.scaled(5))
		(isActive ? NSColor.white.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.05)).setFill()
		path.fill()

		let color = isActive ? Theme.current.sidebarHeaderText : Theme.current.sidebarText
		var x = rect.minX + Theme.current.scaled(7)

		if let icon = Theme.symbol(symbol, size: 10 * Theme.current.scale, color: color) {
			let size = Theme.current.scaled(11)
			icon.draw(
				in: NSRect(x: x, y: rect.midY - size / 2, width: size, height: size),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
			x += size + Theme.current.scaled(5)
		}

		let label = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: color,
		])
		label.draw(at: NSPoint(x: x, y: rect.midY - label.size().height / 2))
	}
}

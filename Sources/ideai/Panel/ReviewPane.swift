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
	private var activity: ReviewActivityView!
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
			self.refreshActivity()
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
		// Findings are often related, and acting on a group of them — copying
		// them out, or asking about them together — is the common case.
		table.allowsMultipleSelection = true
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("finding")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.action = #selector(rowClicked)
		tableView = table
		table.menu = makeFindingsMenu()

		findingsScrollView = NSScrollView()
		findingsScrollView.documentView = table
		findingsScrollView.hasVerticalScroller = true
		findingsScrollView.drawsBackground = true
		findingsScrollView.backgroundColor = Theme.current.editorBackground
		findingsScrollView.scrollerStyle = .overlay

		contentArea = NSView()
		activity = ReviewActivityView()

		addSubview(header)
		addSubview(contentArea)
		addSubview(activity)
		header.translatesAutoresizingMaskIntoConstraints = false
		contentArea.translatesAutoresizingMaskIntoConstraints = false
		activity.translatesAutoresizingMaskIntoConstraints = false

		headerHeight = header.heightAnchor.constraint(equalToConstant: Theme.current.scaled(32))
		activityHeight = activity.heightAnchor.constraint(
			equalToConstant: ReviewActivityView.height(forLines: Self.activityLineCount)
		)
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: topAnchor),
			header.leadingAnchor.constraint(equalTo: leadingAnchor),
			header.trailingAnchor.constraint(equalTo: trailingAnchor),
			headerHeight,

			contentArea.topAnchor.constraint(equalTo: header.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: activity.topAnchor),

			activity.leadingAnchor.constraint(equalTo: leadingAnchor),
			activity.trailingAnchor.constraint(equalTo: trailingAnchor),
			activity.bottomAnchor.constraint(equalTo: bottomAnchor),
			activityHeight,
		])

		installContent()

		// The tail follows the same session the findings come from.
		terminalPane.terminalView.onOutput = { [weak self] in
			self?.refreshActivity()
		}
		refreshActivity()

		setMode(.findings)
	}

	// MARK: - Acting on findings

	/// The findings a command applies to.
	///
	/// A right-click inside the selection acts on the whole selection; outside
	/// it, it acts on the clicked row and selects it, which is what every list
	/// in the system does.
	private var targetFindings: [ReviewFinding] {
		let clicked = tableView.clickedRow
		let selected = tableView.selectedRowIndexes

		let rows: IndexSet
		if clicked >= 0 && !selected.contains(clicked) {
			rows = IndexSet(integer: clicked)
			tableView.selectRowIndexes(rows, byExtendingSelection: false)
		} else if !selected.isEmpty {
			rows = selected
		} else if clicked >= 0 {
			rows = IndexSet(integer: clicked)
		} else {
			return []
		}

		return rows.compactMap { session.findings.indices.contains($0) ? session.findings[$0] : nil }
	}

	@objc func copy(_ sender: Any?) {
		let findings = targetFindings
		guard !findings.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(session.clipboardText(for: findings), forType: .string)
	}

	@objc private func chatAboutSelection() {
		discuss(targetFindings, visual: false)
	}

	@objc private func explainSelectionVisually() {
		discuss(targetFindings, visual: true)
	}

	/// Hands findings to the live session and switches to it.
	private func discuss(_ findings: [ReviewFinding], visual: Bool) {
		guard !findings.isEmpty else { return }

		setMode(.chat)
		header.setShowingChat(true)

		// The session may still be working; Claude Code queues what arrives while
		// it is, so this does not need to wait for the review to finish.
		terminalPane.terminalView.send(session.discussionPrompt(for: findings, visual: visual) + "\n")
	}

	private func makeFindingsMenu() -> NSMenu {
		let menu = NSMenu()
		// AppKit recomputes isEnabled from the responder chain unless told not
		// to, which silently discards whatever the items were built with.
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	private var headerHeight: NSLayoutConstraint!
	private var activityHeight: NSLayoutConstraint!

	/// Enough lines to show movement, few enough to stay a footnote.
	private static let activityLineCount = 3

	/// Mirrors the agent's last few output lines under the findings.
	private func refreshActivity() {
		let isRunning = terminalPane.terminalView.isProcessRunning && !session.isComplete
		// Shown only over the findings: in chat you are already looking at the
		// session, so a tail of it below would be the same lines twice. Once the
		// review is over the tail is just whatever scrolled past last, so the
		// space goes back to the findings.
		let shouldShow = isRunning && mode == .findings

		activity.update(
			lines: terminalPane.terminalView.recentOutput(Self.activityLineCount),
			isRunning: isRunning
		)
		activity.isHidden = !shouldShow
		activityHeight.constant = shouldShow
			? ReviewActivityView.height(forLines: Self.activityLineCount)
			: 0
	}

	/// Installs both views once and switches between them by visibility.
	///
	/// The terminal waits for a real size before starting the agent, so that it
	/// does not hand a full-screen program a grid a few rows tall. Swapping the
	/// views in and out meant the terminal had no size until the chat was opened
	/// — and so the review did not start until someone went looking for it.
	/// A hidden view is still laid out, which is what makes this work.
	private func installContent() {
		for view in [findingsScrollView, terminalPane] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			contentArea.addSubview(view)
			NSLayoutConstraint.activate([
				view.topAnchor.constraint(equalTo: contentArea.topAnchor),
				view.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
				view.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
				view.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
			])
		}
	}

	private func setMode(_ newMode: Mode) {
		mode = newMode
		refreshActivity()

		findingsScrollView.isHidden = (mode != .findings)
		terminalPane.isHidden = (mode != .chat)

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
			icon.drawFitted(in: NSRect(x: inset, y: Theme.current.scaled(10), width: size, height: size))
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
	/// When the review started, so the header can say how long it has been
	/// going. A number that keeps climbing is the cheapest possible proof that
	/// nothing has silently died.
	private let startedAt = Date()
	private var elapsedTimer: Timer?

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

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		elapsedTimer?.invalidate()
		guard window != nil else { return }
		elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			guard let self, !self.isComplete else { return }
			self.needsDisplay = true
		}
	}

	deinit { elapsedTimer?.invalidate() }

	private var elapsedDescription: String {
		let seconds = Int(Date().timeIntervalSince(startedAt))
		if seconds < 60 { return "\(seconds)s" }
		return "\(seconds / 60)m \(seconds % 60)s"
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
		var summary = text
		if findingCount > 0 {
			summary += "  ·  \(findingCount) finding\(findingCount == 1 ? "" : "s")"
		}
		if !isComplete { summary += "  ·  \(elapsedDescription)" }

		// The buttons are laid out first: the status is a whole sentence and the
		// buttons are fixed, so the status is what has to give way. Measuring it
		// afterwards is what let it run underneath them.
		let buttonWidth = Theme.current.scaled(74)
		let buttonHeight = Theme.current.scaled(20)
		let y = bounds.midY - buttonHeight / 2
		var x = bounds.width - Theme.current.scaled(12) - buttonWidth

		chatButtonFrame = NSRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
		x -= buttonWidth + Theme.current.scaled(4)
		findingsButtonFrame = NSRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
		x -= Theme.current.scaled(28)
		stopButtonFrame = NSRect(x: x, y: y, width: Theme.current.scaled(22), height: buttonHeight)

		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let label = NSAttributedString(string: summary, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: isComplete ? Theme.current.gitAdded : Theme.current.sidebarText,
			.paragraphStyle: paragraph,
		])
		let labelLeft = Theme.current.scaled(12)
		let labelWidth = max(0, stopButtonFrame.minX - Theme.current.scaled(10) - labelLeft)
		label.draw(in: NSRect(
			x: labelLeft,
			y: bounds.midY - label.size().height / 2,
			width: labelWidth,
			height: label.size().height
		))

		draw(button: findingsButtonFrame, title: "Findings", symbol: "list.bullet", isActive: !showingChat)
		draw(button: chatButtonFrame, title: "Chat", symbol: "bubble.left.and.bubble.right", isActive: showingChat)

		if !isComplete, let stop = Theme.symbol("stop.circle", size: 12 * Theme.current.scale, color: Theme.current.gitUnversioned) {
			let size = Theme.current.scaled(14)
			stop.drawFitted(in: NSRect(x: stopButtonFrame.midX - size / 2, y: stopButtonFrame.midY - size / 2, width: size, height: size))
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
			icon.drawFitted(in: NSRect(x: x, y: rect.midY - size / 2, width: size, height: size))
			x += size + Theme.current.scaled(5)
		}

		let label = NSAttributedString(string: title, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: color,
		])
		label.draw(at: NSPoint(x: x, y: rect.midY - label.size().height / 2))
	}
}

extension ReviewPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		let count = targetFindings.count
		guard count > 0 else { return }
		let suffix = count == 1 ? "" : " (\(count))"

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			item.isEnabled = true
			return item
		}

		menu.addItem(item("Copy\(suffix)", #selector(copy(_:))))
		menu.addItem(.separator())
		menu.addItem(item("Chat About This\(suffix)", #selector(chatAboutSelection)))
		menu.addItem(item("Explain Visually\(suffix)", #selector(explainSelectionVisually)))
	}
}

/// A live tail of the agent's own output, shown under the findings.
///
/// The agent's reported status is sparse — it sends one when it thinks to —
/// which leaves long gaps where a review looks indistinguishable from a hung
/// one. Its raw output never stops moving, so a few lines of it answer "is this
/// still running" without making anyone switch views to find out.
private final class ReviewActivityView: NSView {
	private var lines: [String] = []
	private var isRunning = true
	private var phase = 0
	private var timer: Timer?

	override var isFlipped: Bool { true }

	/// Braille frames: they animate in place without changing width, so the
	/// text beside them does not jitter.
	private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		timer?.invalidate()
		guard window != nil else { return }
		timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
			guard let self, self.isRunning else { return }
			self.phase = (self.phase + 1) % Self.spinnerFrames.count
			self.needsDisplay = true
		}
	}

	deinit { timer?.invalidate() }

	func update(lines: [String], isRunning: Bool) {
		guard lines != self.lines || isRunning != self.isRunning else { return }
		self.lines = lines
		self.isRunning = isRunning
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

		let font = Theme.terminalFont(size: Theme.current.fontSize - 1)
		let lineHeight = font.ascender - font.descender + Theme.current.scaled(3)
		let left = Theme.current.scaled(12)
		let spinnerWidth = Theme.current.scaled(16)

		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail

		for (index, line) in lines.enumerated() {
			let y = Theme.current.scaled(4) + CGFloat(index) * lineHeight
			// The newest line is the one worth reading; the ones above it are
			// context, so they fade.
			let isLast = index == lines.count - 1
			let text = NSAttributedString(string: line, attributes: [
				.font: font,
				.foregroundColor: Theme.current.gitIgnored.withAlphaComponent(isLast ? 0.95 : 0.45),
				.paragraphStyle: paragraph,
			])
			text.draw(in: NSRect(
				x: left + spinnerWidth,
				y: y,
				width: max(0, bounds.width - left - spinnerWidth - Theme.current.scaled(12)),
				height: lineHeight
			))

			if isLast, isRunning {
				let spinner = NSAttributedString(string: Self.spinnerFrames[phase], attributes: [
					.font: font,
					.foregroundColor: Theme.current.gitModified,
				])
				spinner.draw(at: NSPoint(x: left, y: y))
			}
		}
	}

	/// Height for a given number of lines, so the container can size itself.
	static func height(forLines count: Int) -> CGFloat {
		let font = Theme.terminalFont(size: Theme.current.fontSize - 1)
		let lineHeight = font.ascender - font.descender + Theme.current.scaled(3)
		return CGFloat(count) * lineHeight + Theme.current.scaled(8)
	}
}

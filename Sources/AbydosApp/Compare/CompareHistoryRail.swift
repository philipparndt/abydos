import AppKit
import AbydosKit

/// The file's history down the edge of a compare page: one row per commit
/// that touched the path, each with an A chip and a B chip, so any two
/// revisions are the two sides by clicking.
///
/// The row itself does not navigate — a click on it is how a chip is reached
/// — and the hash is what opens the commit on the log page, because a hash is
/// what a commit is known by everywhere else in the window.
final class CompareHistoryRail: NSView, NSTableViewDataSource, NSTableViewDelegate {
	/// A chip was clicked: this commit, as A or as B.
	var onChoose: ((GitCommit, Bool) -> Void)?
	/// The hash was clicked.
	var onOpenCommit: ((GitCommit) -> Void)?

	private(set) var commits: [GitCommit] = []
	/// Which commits hold the chips, by hash; nil when a side is the disk.
	private(set) var chosenA: String?
	private(set) var chosenB: String?
	private let table = NSTableView()
	private let scroll = NSScrollView()
	private let heading = ScaledLabel("History", size: 11, weight: .semibold, colour: { Theme.current.sidebarHeaderText })

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.selectionHighlightStyle = .none
		table.intercellSpacing = .zero
		table.rowSizeStyle = .custom
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("commit"))
		table.addTableColumn(column)
		table.dataSource = self
		table.delegate = self
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.scrollerStyle = .overlay
		addSubview(heading)
		addSubview(scroll)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	/// Framed by hand rather than by constraints, so a new size places the
	/// subviews itself — AppKit's own layout pass is not to be waited for.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		arrange()
	}

	override func layout() {
		super.layout()
		arrange()
	}

	private func arrange() {
		let top = Theme.current.scaled(24)
		heading.sizeToFit()
		heading.frame = NSRect(x: Theme.current.scaled(10), y: (top - heading.frame.height) / 2, width: bounds.width - Theme.current.scaled(20), height: heading.frame.height)
		scroll.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
	}

	func show(commits: [GitCommit], chosenA: String?, chosenB: String?) {
		self.commits = commits
		self.chosenA = chosenA
		self.chosenB = chosenB
		table.reloadData()
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		table.backgroundColor = Theme.current.sidebarBackground
		scroll.backgroundColor = Theme.current.sidebarBackground
		arrange()
		table.reloadData()
	}

	func numberOfRows(in tableView: NSTableView) -> Int { commits.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Theme.current.scaled(40) }

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let view = (table.makeView(withIdentifier: CompareHistoryRowView.identifier, owner: nil) as? CompareHistoryRowView)
			?? CompareHistoryRowView()
		let commit = commits[row]
		view.show(commit, isA: commit.hash == chosenA, isB: commit.hash == chosenB)
		view.onChip = { [weak self] sideA in self?.onChoose?(commit, sideA) }
		view.onHash = { [weak self] in self?.onOpenCommit?(commit) }
		return view
	}

	/// The rows, for a driven run: chips first, then the commit.
	var reportForTesting: String {
		commits.map { commit in
			let a = commit.hash == chosenA ? "[A]" : "[ ]"
			let b = commit.hash == chosenB ? "[B]" : "[ ]"
			return "\(a)\(b) \(commit.shortHash) \(commit.subject)"
		}.joined(separator: "\n")
	}

	func chooseForTesting(row: Int, sideA: Bool) -> String {
		guard commits.indices.contains(row) else { return "no row \(row)" }
		onChoose?(commits[row], sideA)
		return "\(sideA ? "A" : "B") on \(commits[row].shortHash)"
	}
}

/// One commit on the rail: the two chips, who, when, the hash, the subject.
final class CompareHistoryRowView: NSView {
	static let identifier = NSUserInterfaceItemIdentifier("compare-history-row")
	var onChip: ((Bool) -> Void)?
	var onHash: (() -> Void)?
	private var commit: GitCommit?
	private var isA = false
	private var isB = false
	private var chipARect: NSRect = .zero
	private var chipBRect: NSRect = .zero
	private var hashRect: NSRect = .zero

	override var isFlipped: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// A layer-backed view displayed at one size keeps that picture at the
	/// next unless it is told; a view drawn by hand is told here.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsDisplay = true
	}


	private static let dates: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .none
		return formatter
	}()

	func show(_ commit: GitCommit, isA: Bool, isB: Bool) {
		self.commit = commit
		self.isA = isA
		self.isB = isB
		identifier = Self.identifier
		toolTip = "\(commit.subject)\n\(commit.authorName) · \(commit.shortHash)\n\nA or B makes this revision a side; the hash opens the commit."
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		guard let commit else { return }
		let theme = Theme.current
		if isA || isB {
			theme.selectionInactive.withAlphaComponent(0.5).setFill()
			NSBezierPath(roundedRect: bounds.insetBy(dx: theme.scaled(4), dy: 1), xRadius: theme.scaled(6), yRadius: theme.scaled(6)).fill()
		}
		let font = Theme.font(size: theme.fontSize * 0.85, weight: .regular, monospaced: false)
		let bold = Theme.font(size: theme.fontSize * 0.85, weight: .semibold, monospaced: false)
		let mono = Theme.font(size: theme.fontSize * 0.8, weight: .regular, monospaced: true)
		let inset = theme.scaled(10)
		let chipSize = NSSize(width: theme.scaled(18), height: theme.scaled(16))
		let topRowY = theme.scaled(5)

		chipARect = NSRect(x: inset, y: topRowY, width: chipSize.width, height: chipSize.height)
		chipBRect = NSRect(x: inset + chipSize.width + theme.scaled(3), y: topRowY, width: chipSize.width, height: chipSize.height)
		drawChip("A", in: chipARect, lit: isA, theme: theme)
		drawChip("B", in: chipBRect, lit: isB, theme: theme)

		let hash = commit.shortHash as NSString
		let hashAttributes: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: theme.gitModified]
		let hashWidth = hash.size(withAttributes: hashAttributes).width
		hashRect = NSRect(x: bounds.width - inset - hashWidth, y: topRowY, width: hashWidth, height: chipSize.height)
		hash.draw(at: NSPoint(x: hashRect.minX, y: topRowY + (chipSize.height - mono.pointSize * 1.3) / 2), withAttributes: hashAttributes)

		let authorX = chipBRect.maxX + theme.scaled(8)
		let author = commit.authorName as NSString
		let date = Self.dates.string(from: commit.date) as NSString
		let dateAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.gitIgnored]
		let dateWidth = date.size(withAttributes: dateAttributes).width
		author.draw(
			with: NSRect(x: authorX, y: topRowY + (chipSize.height - bold.pointSize * 1.3) / 2, width: max(0, hashRect.minX - authorX - dateWidth - theme.scaled(12)), height: bold.pointSize * 1.4),
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
			attributes: [.font: bold, .foregroundColor: theme.sidebarText]
		)
		date.draw(at: NSPoint(x: hashRect.minX - dateWidth - theme.scaled(8), y: topRowY + (chipSize.height - font.pointSize * 1.3) / 2), withAttributes: dateAttributes)

		let subjectY = topRowY + chipSize.height + theme.scaled(3)
		(commit.subject as NSString).draw(
			with: NSRect(x: inset, y: subjectY, width: bounds.width - inset * 2, height: font.pointSize * 1.4),
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
			attributes: [.font: font, .foregroundColor: theme.sidebarText.withAlphaComponent(0.85)]
		)
	}

	private func drawChip(_ letter: String, in rect: NSRect, lit: Bool, theme: Theme) {
		let path = NSBezierPath(roundedRect: rect, xRadius: theme.scaled(4), yRadius: theme.scaled(4))
		(lit ? theme.gitModified : theme.gitIgnored.withAlphaComponent(0.25)).setFill()
		path.fill()
		let font = Theme.font(size: theme.fontSize * 0.75, weight: .bold, monospaced: false)
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font, .foregroundColor: lit ? NSColor.white : theme.sidebarText.withAlphaComponent(0.7),
		]
		let size = (letter as NSString).size(withAttributes: attributes)
		(letter as NSString).draw(
			at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes
		)
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		if chipARect.insetBy(dx: -2, dy: -2).contains(point) { onChip?(true); return }
		if chipBRect.insetBy(dx: -2, dy: -2).contains(point) { onChip?(false); return }
		if hashRect.insetBy(dx: -4, dy: -2).contains(point) { onHash?(); return }
		super.mouseDown(with: event)
	}
}

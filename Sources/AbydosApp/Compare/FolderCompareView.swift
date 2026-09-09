import AppKit
import AbydosKit

/// Two folders as two trees, aligned row for row, with a gutter between them
/// where a row is marked to be copied one way or the other, or deleted.
///
/// **One list of nodes, shown twice.** Both outlines are fed the same
/// `FolderComparison.Node` objects in the same order, so a row is at the same
/// height on both sides by construction, and expanding a folder on one side is
/// one `expandItem` on the other. A side the row has nothing on draws an
/// absence; nothing is ever aligned by arithmetic.
final class FolderCompareView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
	let comparison: FolderComparison
	/// A file row was opened — a double-click, or Return.
	var onOpenRow: ((FolderComparison.Node) -> Void)?
	/// A mark was made or cleared, for the count in the footer.
	var onMarksChanged: (() -> Void)?

	private let leftOutline = CompareOutlineView()
	private let rightOutline = CompareOutlineView()
	private let leftScroll = NSScrollView()
	private let rightScroll = NSScrollView()
	private let gutter: CompareGutterView
	private var syncing = false

	var showsEqual = false {
		didSet { reload() }
	}

	var filter = "" {
		didSet { reload() }
	}

	init(comparison: FolderComparison) {
		self.comparison = comparison
		gutter = CompareGutterView(comparison: comparison)
		super.init(frame: .zero)
		wantsLayer = true
		clipsToBounds = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor

		for (outline, scroll, isLeft) in [(leftOutline, leftScroll, true), (rightOutline, rightScroll, false)] {
			outline.headerView = nil
			outline.backgroundColor = Theme.current.editorBackground
			outline.selectionHighlightStyle = .regular
			outline.allowsMultipleSelection = false
			outline.rowSizeStyle = .custom
			outline.intercellSpacing = .zero
			outline.gridStyleMask = []
			outline.indentationPerLevel = Theme.current.scaled(14)
			outline.autoresizesOutlineColumn = false
			outline.isLeftSide = isLeft
			let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("side"))
			outline.addTableColumn(column)
			outline.outlineTableColumn = column
			outline.dataSource = self
			outline.delegate = self
			outline.onActivate = { [weak self] row in self?.activate(row: row, in: outline) }
			outline.onPress = { [weak self] row in self?.mirror(row: row, from: outline) }
			scroll.documentView = outline
			scroll.hasVerticalScroller = true
			scroll.drawsBackground = true
			scroll.backgroundColor = Theme.current.editorBackground
			scroll.scrollerStyle = .overlay
			scroll.contentView.postsBoundsChangedNotifications = true
			addSubview(scroll)
			NotificationCenter.default.addObserver(
				self, selector: #selector(clipViewMoved(_:)),
				name: NSView.boundsDidChangeNotification, object: scroll.contentView
			)
		}
		gutter.rowRect = { [weak self] row in
			guard let self else { return .zero }
			// The row's height and position from the tree; the width is the
			// gutter's own, which the tree knows nothing about.
			let rect = self.gutter.convert(self.leftOutline.rect(ofRow: row), from: self.leftOutline)
			return NSRect(x: 0, y: rect.minY, width: self.gutter.bounds.width, height: rect.height)
		}
		gutter.visibleRows = { [weak self] in
			guard let self else { return 0..<0 }
			let range = self.leftOutline.rows(in: self.leftOutline.visibleRect)
			return range.location..<(range.location + range.length)
		}
		gutter.node = { [weak self] row in self?.leftOutline.item(atRow: row) as? FolderComparison.Node }
		gutter.isSelected = { [weak self] row in self?.leftOutline.selectedRowIndexes.contains(row) ?? false }
		gutter.hasKeyboard = { [weak self] in
			guard let self, let responder = self.window?.firstResponder as? NSView else { return false }
			return responder === self.leftOutline || responder === self.rightOutline
		}
		gutter.onMarksChanged = { [weak self] in
			self?.leftOutline.needsDisplay = true
			self?.rightOutline.needsDisplay = true
			self?.onMarksChanged?()
		}
		addSubview(gutter)

		reload()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit { NotificationCenter.default.removeObserver(self) }

	/// Framed by hand rather than by constraints, so a new size places the
	/// subviews itself — AppKit's own layout pass is not to be waited for.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		arrange()
		needsDisplay = true
	}

	override func layout() {
		super.layout()
		arrange()
	}

	private func arrange() {
		let gutterWidth = Theme.current.scaled(34)
		let half = ((bounds.width - gutterWidth) / 2).rounded(.down)
		leftScroll.frame = NSRect(x: 0, y: 0, width: half, height: bounds.height)
		gutter.frame = NSRect(x: half, y: 0, width: gutterWidth, height: bounds.height)
		rightScroll.frame = NSRect(x: half + gutterWidth, y: 0, width: bounds.width - half - gutterWidth, height: bounds.height)
	}

	func applySettings() {
		for outline in [leftOutline, rightOutline] {
			outline.indentationPerLevel = Theme.current.scaled(14)
			outline.backgroundColor = Theme.current.editorBackground
		}
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		arrange()
		reload()
	}

	/// The same rows again, keeping what was expanded and what was selected:
	/// the nodes are the same objects across a refresh, which is what
	/// `reloadItem` keys on, and the selection is put back by node because a
	/// reload drops it.
	func reload() {
		let selected = leftOutline.selectedRowIndexes.compactMap { leftOutline.item(atRow: $0) as? FolderComparison.Node }
		syncing = true
		for outline in [leftOutline, rightOutline] {
			outline.reloadItem(nil, reloadChildren: true)
			let rows = IndexSet(selected.map { outline.row(forItem: $0) }.filter { $0 >= 0 })
			if outline.selectedRowIndexes != rows { outline.selectRowIndexes(rows, byExtendingSelection: false) }
			outline.needsDisplay = true
		}
		syncing = false
		gutter.needsDisplay = true
	}

	// MARK: - Keeping the two sides together

	@objc private func clipViewMoved(_ note: Notification) {
		guard !syncing, let moved = note.object as? NSClipView else { return }
		let other = moved === leftScroll.contentView ? rightScroll.contentView : leftScroll.contentView
		guard other.bounds.origin != moved.bounds.origin else { return }
		syncing = true
		other.scroll(to: moved.bounds.origin)
		(other === leftScroll.contentView ? leftScroll : rightScroll).reflectScrolledClipView(other)
		syncing = false
		gutter.needsDisplay = true
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		guard !syncing, let outline = notification.object as? NSOutlineView,
		      let item = notification.userInfo?["NSObject"] else { return }
		let other = outline === leftOutline ? rightOutline : leftOutline
		syncing = true
		other.expandItem(item)
		syncing = false
		gutter.needsDisplay = true
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		guard !syncing, let outline = notification.object as? NSOutlineView,
		      let item = notification.userInfo?["NSObject"] else { return }
		let other = outline === leftOutline ? rightOutline : leftOutline
		syncing = true
		other.collapseItem(item)
		syncing = false
		gutter.needsDisplay = true
	}

	/// Selects a row on both sides at once, and lights the gutter, so a press
	/// on either tree is one gesture on one control.
	private func mirror(row: Int, from outline: NSOutlineView) {
		guard !syncing else { return }
		syncing = true
		for tree in [leftOutline, rightOutline] where !tree.selectedRowIndexes.contains(row) || tree.selectedRowIndexes.count != 1 {
			tree.selectRowIndexes([row], byExtendingSelection: false)
		}
		syncing = false
		gutter.needsDisplay = true
	}

	func outlineViewSelectionIsChanging(_ notification: Notification) {
		outlineViewSelectionDidChange(notification)
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard !syncing, let outline = notification.object as? NSOutlineView else { return }
		let other = outline === leftOutline ? rightOutline : leftOutline
		syncing = true
		other.selectRowIndexes(outline.selectedRowIndexes, byExtendingSelection: false)
		syncing = false
		gutter.needsDisplay = true
	}

	private func activate(row: Int, in outline: NSOutlineView) {
		let index = row >= 0 ? row : outline.selectedRow
		guard index >= 0, let node = outline.item(atRow: index) as? FolderComparison.Node else { return }
		if node.isDirectory {
			if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
			return
		}
		onOpenRow?(node)
	}

	// MARK: - Data source

	private func children(of item: Any?) -> [FolderComparison.Node] {
		let node = (item as? FolderComparison.Node) ?? comparison.root
		return comparison.children(of: node, showingEqual: showsEqual, filter: filter)
	}

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		children(of: item).count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		children(of: item)[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let node = item as? FolderComparison.Node else { return false }
		return node.isDirectory && !node.state.isIgnored && !node.isKindMismatch
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		Theme.current.scaled(22)
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		CompareTreeRowView(isLeft: outlineView === leftOutline, hasKeyboard: gutter.hasKeyboard)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? FolderComparison.Node, let outline = outlineView as? CompareOutlineView else { return nil }
		let view = (outline.makeView(withIdentifier: CompareRowView.identifier, owner: nil) as? CompareRowView) ?? CompareRowView()
		view.show(node, isLeft: outline.isLeftSide, mark: comparison.mark(at: node.relativePath))
		return view
	}

	// MARK: - For a driven run

	/// Every row shown, as the tree lists it, one line each.
	var reportForTesting: String {
		var lines: [String] = []
		let selected = leftOutline.selectedRowIndexes.map { row in
			(leftOutline.item(atRow: row) as? FolderComparison.Node)?.relativePath ?? "?"
		}
		let mirrored = rightOutline.selectedRowIndexes.count
		lines.append("selected: \(selected.isEmpty ? "nothing" : selected.joined(separator: ", ")) (\(mirrored) on the right), keyboard: \(TreeKeys.keyboardHolder(in: window))")
		for row in 0..<leftOutline.numberOfRows {
			guard let node = leftOutline.item(atRow: row) as? FolderComparison.Node else { continue }
			let depth = String(repeating: "  ", count: leftOutline.level(forRow: row))
			var said = "\(depth)\(node.name)\(node.isDirectory ? "/" : "")  \(Self.said(node.state))"
			if let mark = comparison.mark(at: node.relativePath) { said += "  [\(mark.said)]" }
			lines.append(said)
		}
		return lines.joined(separator: "\n")
	}

	static func said(_ state: FolderComparison.State) -> String {
		switch state {
		case .unknown: return "comparing"
		case .different: return "different"
		case .equal: return "equal"
		case .unmatched: return "unmatched"
		case .ignored(let rule): return "ignored (\(rule))"
		}
	}

	/// The row with this relative path, for a step that names one.
	func row(at relativePath: String) -> Int? {
		guard let node = comparison.node(at: relativePath) else { return nil }
		var ancestors: [FolderComparison.Node] = []
		var current = node.parent
		while let parent = current, parent !== comparison.root {
			ancestors.append(parent)
			current = parent.parent
		}
		for ancestor in ancestors.reversed() { leftOutline.expandItem(ancestor) }
		let row = leftOutline.row(forItem: node)
		return row >= 0 ? row : nil
	}

	func openForTesting(_ relativePath: String) -> String {
		guard let row = row(at: relativePath) else { return "open \(relativePath): no such row" }
		activate(row: row, in: leftOutline)
		return "open \(relativePath)"
	}

	/// Clicks a row in the left tree the way a person does, so the selection
	/// and the keyboard land where a click puts them.
	///
	/// The click is the changes tree's own instrument; when it does not take —
	/// the steps here run inside a task, and a tracking loop's nested run loop
	/// does not always see the release queued for it there — the row is
	/// selected outright and the report says which of the two happened.
	func selectForTesting(_ relativePath: String) -> String {
		guard let row = row(at: relativePath) else { return "select \(relativePath): no such row" }
		let clicked = TreeKeys.click(row: row, in: leftOutline)
		guard !leftOutline.selectedRowIndexes.contains(row) else { return "select \(relativePath): " + clicked }
		leftOutline.selectRowIndexes([row], byExtendingSelection: false)
		window?.makeFirstResponder(leftOutline)
		return "select \(relativePath): selected outright after \(clicked)"
	}

	func markForTesting(_ relativePath: String, _ mark: FolderComparison.Mark?) -> String {
		let done = comparison.setMark(mark, at: relativePath)
		gutter.onMarksChanged?()
		return "mark \(relativePath) \(mark?.said ?? "cleared"): \(done ? "done" : "refused")"
	}
}

/// The row behind a selected row in one of the two trees: the project tree's
/// pill, squared off on the side that faces the gutter, so that with the band
/// the gutter draws a selected row is one shape across both trees rather than
/// two pills with a hole between them.
final class CompareTreeRowView: TreeRowView {
	private let isLeft: Bool
	/// Whether *either* tree has the keyboard: the two are one control, and
	/// a band strong on one side of the gutter and quiet on the other is two.
	private let hasKeyboard: () -> Bool

	init(isLeft: Bool, hasKeyboard: @escaping () -> Bool) {
		self.isLeft = isLeft
		self.hasKeyboard = hasKeyboard
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isTreeFocused: Bool { hasKeyboard() }

	override func drawSelection(in dirtyRect: NSRect) {
		let colour = Theme.current.selection(.row, hasKeyboard: hasKeyboard())
		let inset = Theme.current.scaled(5)
		let radius = Theme.current.scaled(6)
		// Rounded on the outer end only: the pill is drawn past the inner
		// edge by its own radius, and the scroll view clips the rest away.
		var rect = bounds.insetBy(dx: inset, dy: 1)
		if isLeft {
			rect.size.width += inset + radius
		} else {
			rect.origin.x -= inset + radius
			rect.size.width += inset + radius
		}
		colour.setFill()
		NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
	}
}

/// The outline of one side: it reports Return and a double-click, and knows
/// which side it is.
final class CompareOutlineView: NSOutlineView {
	var isLeftSide = true
	var onActivate: ((Int) -> Void)?
	/// The row under a press, before the table's own tracking has started:
	/// a table selects on the press but says so only after the release and
	/// the drag check, and the other tree and the gutter were half a second
	/// behind the one that was clicked.
	var onPress: ((Int) -> Void)?

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		if event.keyCode == 36 || event.keyCode == 76 {
			onActivate?(-1)
			return
		}
		super.keyDown(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		let pressed = row(at: convert(event.locationInWindow, from: nil))
		if pressed >= 0, event.modifierFlags.intersection([.command, .shift]).isEmpty { onPress?(pressed) }
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?(clickedRow) }
	}
}

/// One side of one row: its state as a coloured mark, its icon and name, and
/// what the listing said about it — or an absence, shaded, where this side
/// has nothing.
final class CompareRowView: NSView {
	static let identifier = NSUserInterfaceItemIdentifier("compare-row")
	private var node: FolderComparison.Node?
	private var isLeft = true
	private var mark: FolderComparison.Mark?

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
		formatter.timeStyle = .short
		formatter.doesRelativeDateFormatting = true
		return formatter
	}()

	func show(_ node: FolderComparison.Node, isLeft: Bool, mark: FolderComparison.Mark?) {
		self.node = node
		self.isLeft = isLeft
		self.mark = mark
		identifier = Self.identifier
		toolTip = Self.tip(for: node, mark: mark)
		needsDisplay = true
	}

	static func tip(for node: FolderComparison.Node, mark: FolderComparison.Mark?) -> String {
		var lines = [FolderCompareView.said(node.state).capitalized]
		if let mark { lines.append("Marked: \(mark.said)") }
		if node.isKindMismatch { lines.append("A file on one side and a folder on the other.") }
		return lines.joined(separator: "\n")
	}

	override func draw(_ dirtyRect: NSRect) {
		guard let node else { return }
		let theme = Theme.current
		let entry = isLeft ? node.left : node.right
		let font = Theme.font(size: theme.fontSize * 0.92, weight: .regular, monospaced: false)
		let selected = (superview as? NSTableRowView)?.isSelected ?? false
		let textColour = selected ? theme.sidebarText : (node.state.isIgnored ? theme.gitIgnored : theme.sidebarText)

		guard let entry else {
			// Nothing on this side of the row: a shade, so a file that exists
			// only opposite reads as an absence rather than a blank.
			theme.gitIgnored.withAlphaComponent(0.06).setFill()
			bounds.fill()
			return
		}

		let x0 = theme.scaled(4)
		// The state, as a small filled mark down the left: the colour is the
		// state and the shape says whether the row is here on one side or on
		// both.
		let markSize = theme.scaled(8)
		let markRect = NSRect(x: x0, y: (bounds.height - markSize) / 2, width: markSize, height: markSize)
		Self.colour(for: node.state, theme: theme).setFill()
		NSBezierPath(roundedRect: markRect, xRadius: 2, yRadius: 2).fill()

		var x = x0 + markSize + theme.scaled(6)
		let icon = node.isDirectory ? FileIcon.folder() : FileIcon.image(forFileNamed: node.name)
		let iconSize = theme.scaled(14)
		if let icon {
			icon.draw(in: NSRect(x: x, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize))
		}
		x += iconSize + theme.scaled(5)

		// Size and date on the right, in the grey half, and blue where the
		// size differs from the other side's: the number that decided the row.
		let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColour]
		let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.gitIgnored]
		var rightEdge = bounds.width - theme.scaled(8)
		if !node.isDirectory {
			let other = isLeft ? node.right : node.left
			let differs = other != nil && other?.size != entry.size
			let size = ByteSize.said(Int64(entry.size)) as NSString
			let sizeAttributes: [NSAttributedString.Key: Any] = [
				.font: font, .foregroundColor: differs ? theme.gitModified : theme.gitIgnored,
			]
			let width = size.size(withAttributes: sizeAttributes).width
			rightEdge -= width
			size.draw(at: NSPoint(x: rightEdge, y: (bounds.height - font.pointSize * 1.3) / 2), withAttributes: sizeAttributes)
			rightEdge -= theme.scaled(12)
		}
		if let date = entry.modified, bounds.width > theme.scaled(260) {
			let said = Self.dates.string(from: date) as NSString
			let width = said.size(withAttributes: secondary).width
			rightEdge -= width
			said.draw(at: NSPoint(x: rightEdge, y: (bounds.height - font.pointSize * 1.3) / 2), withAttributes: secondary)
			rightEdge -= theme.scaled(12)
		}

		let name = node.name as NSString
		let nameWidth = max(0, rightEdge - x)
		name.draw(
			with: NSRect(x: x, y: (bounds.height - font.pointSize * 1.3) / 2, width: nameWidth, height: font.pointSize * 1.4),
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
			attributes: attributes
		)
	}

	static func colour(for state: FolderComparison.State, theme: Theme) -> NSColor {
		switch state {
		case .unknown: return theme.gitIgnored.withAlphaComponent(0.5)
		case .different: return theme.gitModified
		case .equal: return theme.gitIgnored.withAlphaComponent(0.35)
		case .unmatched: return theme.gitAdded
		case .ignored: return theme.gitIgnored.withAlphaComponent(0.5)
		}
	}
}

/// The strip between the trees: for every row on screen, the mark it carries
/// or the marks it could take, and a click that cycles through them.
///
/// It draws from the left outline's row rectangles rather than keeping rows
/// of its own, so it cannot disagree with the trees about where a row is.
final class CompareGutterView: NSView {
	private let comparison: FolderComparison
	var rowRect: (Int) -> NSRect = { _ in .zero }
	var visibleRows: () -> Range<Int> = { 0..<0 }
	var node: (Int) -> FolderComparison.Node? = { _ in nil }
	var onMarksChanged: (() -> Void)?
	private var hoveredRow: Int?
	private var trackingArea: NSTrackingArea?

	init(comparison: FolderComparison) {
		self.comparison = comparison
		super.init(frame: .zero)
		wantsLayer = true
		clipsToBounds = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	/// A layer-backed view displayed at one size keeps that picture at the
	/// next unless it is told; a view drawn by hand is told here.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsDisplay = true
	}


	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let row = visibleRows().first { rowRect($0).contains(point) }
		if row != hoveredRow {
			hoveredRow = row
			needsDisplay = true
		}
	}

	override func mouseExited(with event: NSEvent) {
		hoveredRow = nil
		needsDisplay = true
	}

	/// Whether a row is selected, and whether the trees have the keyboard, so
	/// the band drawn here is the same colour as the pills either side of it.
	var isSelected: (Int) -> Bool = { _ in false }
	var hasKeyboard: () -> Bool = { false }

	override func draw(_ dirtyRect: NSRect) {
		let theme = Theme.current
		// `bounds`, not `dirtyRect` — see `CompareShelfView.draw`.
		theme.sidebarBackground.setFill()
		bounds.fill()
		for row in visibleRows() {
			guard let node = node(row) else { continue }
			let rect = rowRect(row)
			guard rect.intersects(dirtyRect) else { continue }
			// The selection runs through the gap: the two trees draw their
			// pills squared off towards this strip, and this is the piece
			// between them, so a selected row reads as one band — at half
			// strength here, so the two trees still read as two things joined
			// rather than one wide row with a mark floating in it.
			if isSelected(row) {
				theme.selection(.row, hasKeyboard: hasKeyboard()).withAlphaComponent(0.5).setFill()
				NSRect(x: 0, y: rect.minY + 1, width: bounds.width, height: rect.height - 2).fill()
			}
			let offered = comparison.offeredMarks(for: node)
			guard !offered.isEmpty else { continue }
			let mark = comparison.mark(at: node.relativePath)
			let glyph: String
			switch mark ?? offered[0] {
			case .copyToRight: glyph = "arrowtriangle.right.fill"
			case .copyToLeft: glyph = "arrowtriangle.left.fill"
			case .delete: glyph = "trash"
			}
			let lit = mark != nil
			let colour = lit
				? (mark == .delete ? theme.gitUnversioned : theme.gitModified)
				: theme.gitIgnored.withAlphaComponent(row == hoveredRow ? 0.9 : 0.35)
			let size = theme.scaled(11)
			guard let image = NSImage(systemSymbolName: glyph, accessibilityDescription: mark?.said ?? offered[0].said)?
				.withSymbolConfiguration(.init(pointSize: size, weight: .regular)) else { continue }
			let tinted = image.tinted(with: colour)
			let place = NSRect(
				x: rect.midX - tinted.size.width / 2, y: rect.midY - tinted.size.height / 2,
				width: tinted.size.width, height: tinted.size.height
			)
			// `respectFlipped`: this view is flipped and an image drawn without
			// saying so comes out upside down — the bin did, in the demo.
			tinted.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
		}
	}

	/// A click cycles the row through what it can take, then back to
	/// nothing: copy one way, copy the other, delete, clear.
	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let row = visibleRows().first(where: { rowRect($0).contains(point) }), let node = node(row) else { return }
		let offered = comparison.offeredMarks(for: node)
		guard !offered.isEmpty else { return }
		let current = comparison.mark(at: node.relativePath)
		let next: FolderComparison.Mark?
		if let current, let index = offered.firstIndex(of: current) {
			next = index + 1 < offered.count ? offered[index + 1] : nil
		} else {
			next = offered[0]
		}
		comparison.setMark(next, at: node.relativePath)
		needsDisplay = true
		onMarksChanged?()
	}
}

private extension NSImage {
	func tinted(with colour: NSColor) -> NSImage {
		let image = NSImage(size: size, flipped: false) { rect in
			self.draw(in: rect)
			colour.set()
			rect.fill(using: .sourceAtop)
			return true
		}
		image.isTemplate = false
		return image
	}
}

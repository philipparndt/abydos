import AppKit
import AbydosKit

/// The files a change touches, drawn as a list somebody walks.
///
/// **One list, two pages.** This is what the log page's commit view has always
/// been — an outline over the changed files, arranged flat or by folder, with
/// the line counts at the far end of each row, `*` to open everything, and a
/// selection held by path so it survives a rebuild. It was written inside
/// `HistoryPane` because there was one page that wanted it; a pull request
/// wants the same list of the same rows, and the alternative to moving it is a
/// second one drifting apart from the first in what a rename looks like, in
/// which arrangement is remembered, and in what ← does.
///
/// What it deliberately does *not* know: where the files came from. A commit, a
/// pull request against its merge base, a range — all of them are a
/// `[GitCommitFile]` and a `[String: GitLineCount]`, and both arrive from
/// outside. It owns the drawing and the keyboard and nothing else.
final class ChangedFileList: NSView {
	/// A row was chosen — by click, by arrow, or by being selected in code.
	var onSelect: ((GitCommitFile) -> Void)?

	/// What git answered, which stays the source of truth: `roots` is only the
	/// shape it is drawn in.
	private(set) var files: [GitCommitFile] = []
	private var roots: [GitChangeNode] = []
	/// What `--numstat` said, so a rebuild — a change of arrangement — does not
	/// have to ask again.
	private var lineCounts: [String: GitLineCount] = [:]

	private let outline = FileOutlineView()
	private let scroll = NSScrollView()

	/// Whether the rows are grouped under the folders holding them.
	///
	/// Settable rather than read from `Settings` here: the preference belongs to
	/// the page that shows the control, and a sidebar column arranges flat
	/// whatever the preference says — see `HistoryPane.rebuildFileRows` for why.
	var arrangesByFolder: Bool {
		didSet {
			guard arrangesByFolder != oldValue else { return }
			rebuild()
		}
	}

	init(rowHeight: CGFloat, arrangedByFolder: Bool = false) {
		self.arrangesByFolder = arrangedByFolder
		super.init(frame: .zero)
		build(rowHeight: rowHeight)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// The changes view: an outline in both arrangements.
	///
	/// One view and not two. A table for files and an outline for folders is two
	/// data sources, two selection paths and two sets of row-view code, and the
	/// arrangement nobody had chosen would be the one nobody exercised. An
	/// outline over childless nodes draws what a table draws.
	private func build(rowHeight: CGFloat) {
		outline.headerView = nil
		outline.backgroundColor = Theme.current.sidebarBackground
		outline.selectionHighlightStyle = .regular
		outline.rowSizeStyle = .custom
		outline.rowHeightOverride = rowHeight
		outline.intercellSpacing = .zero
		outline.gridStyleMask = []
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column"))
		outline.addTableColumn(column)
		outline.outlineTableColumn = column
		// A flat arrangement has no folders, so the indent would be a margin
		// down the left of every row for nothing.
		outline.indentationPerLevel = Theme.current.scaled(14)
		outline.delegate = self
		outline.dataSource = self
		outline.onSelectionChange = { [weak self] in self?.selectionChanged() }
		outline.onExpandAll = { [weak self] in self?.expandEveryFolder() }

		scroll.documentView = outline
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.scrollerStyle = NSScroller.preferredScrollerStyle
		scroll.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scroll)
		NSLayoutConstraint.activate([
			scroll.topAnchor.constraint(equalTo: topAnchor),
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	// MARK: - What is in it

	/// The rows, and optionally what is known about their lengths.
	///
	/// The counts are a second argument rather than a second call because they
	/// usually arrive later — one `--numstat` beside the file list rather than
	/// before it — and a page that has both at once should not have to reload
	/// twice to say so.
	func setFiles(_ files: [GitCommitFile], lineCounts: [String: GitLineCount] = [:]) {
		self.files = files
		self.lineCounts = lineCounts
		rebuild()
	}

	/// What `--numstat` answered, once it has.
	func setLineCounts(_ counts: [String: GitLineCount]) {
		lineCounts = counts
		for row in roots { row.applyLineCounts(counts) }
		outline.reloadData()
		expandEveryFolder()
	}

	/// Builds the rows for the file list from what git answered.
	private func rebuild() {
		let previous = selectedPath
		roots = Self.rows(for: files, byFolder: arrangesByFolder)
		for row in roots { row.applyLineCounts(lineCounts) }
		outline.reloadData()
		expandEveryFolder(keepingSelection: false)
		// By path, because the two arrangements put the same file at different
		// depths and different indices — so a row number means a *different*
		// file after a change of arrangement, which looks like it worked.
		if let previous { select(path: previous) }
	}

	/// One arrangement or the other, from the same files.
	static func rows(for files: [GitCommitFile], byFolder: Bool) -> [GitChangeNode] {
		let changes = files.map {
			GitChange(path: $0.path, kind: $0.kind, isStaged: true)
		}
		guard byFolder else {
			// Childless nodes in git's own order. `GitChangeTree.build` sorts and
			// groups, which is the other arrangement; this one is the list the
			// page has always drawn.
			return changes.map { GitChangeNode(path: $0.path, change: $0) }
		}
		return GitChangeTree.build(changes)
	}

	static func find(path: String, in nodes: [GitChangeNode]) -> GitChangeNode? {
		for node in nodes {
			if node.path == path, !node.holdsFiles { return node }
			if let found = find(path: path, in: node.children) { return found }
		}
		return nil
	}

	/// The two arrangements, as a control.
	///
	/// Made here rather than by each page, so that both say the same two things
	/// in the same order with the same tooltips. Where it goes is the page's
	/// business — the log page puts it in the strip beside its tabs, and that
	/// strip's own comment says why nothing may go in the split below it.
	static func makeArrangeControl(target: AnyObject, action: Selector) -> NSSegmentedControl {
		let arrange = NSSegmentedControl(
			images: [
				Theme.symbol("list.bullet", size: 11, color: Theme.current.sidebarText)
					?? NSImage(),
				Theme.symbol("folder", size: 11, color: Theme.current.sidebarText)
					?? NSImage(),
			],
			trackingMode: .selectOne,
			target: target,
			action: action
		)
		arrange.controlSize = .small
		arrange.translatesAutoresizingMaskIntoConstraints = false
		arrange.setToolTip("List the files a commit touched", forSegment: 0)
		arrange.setToolTip("Group them under the folders holding them", forSegment: 1)
		return arrange
	}

	// MARK: - The selection, held by path

	/// The path of the selected row, which is how a selection is held here.
	var selectedPath: String? {
		(outline.item(atRow: outline.selectedRow) as? GitChangeNode)?.path
	}

	/// The file the selection lands on, if it is one.
	var selectedFile: GitCommitFile? {
		guard let path = selectedPath else { return nil }
		return files.first { $0.path == path }
	}

	func select(path: String) {
		guard let node = Self.find(path: path, in: roots) else { return }
		let row = outline.row(forItem: node)
		guard row >= 0 else { return }
		outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
	}

	/// Selects by index into the files as git gave them, for a driven run.
	func select(index: Int) {
		guard files.indices.contains(index) else { return }
		select(path: files[index].path)
	}

	private func selectionChanged() {
		guard let file = selectedFile else { return }
		onSelect?(file)
	}

	/// Puts the keyboard in the list.
	@discardableResult
	func focusList() -> Bool {
		window?.makeFirstResponder(outline) ?? false
	}

	var hasKeyboard: Bool { outline.window?.firstResponder === outline }

	// MARK: - Folders

	/// `*`: every folder open, from wherever the selection is.
	///
	/// Row by row from the top, re-reading `numberOfRows` as it goes, because
	/// rows appear beneath the one just opened. Recursing the model and calling
	/// `expandItem` on each node would visit rows the view has never been
	/// handed.
	func expandEveryFolder(keepingSelection: Bool = true) {
		let held = keepingSelection ? selectedPath : nil
		var row = 0
		while row < outline.numberOfRows {
			if let item = outline.item(atRow: row), outline.isExpandable(item) {
				outline.expandItem(item)
			}
			row += 1
		}
		if let held { select(path: held) }
	}

	/// Shuts every folder, so `*` has something to do. A driven run needs this
	/// because the arrangement arrives open — a tree of folders with nothing
	/// showing under them has told you less than the flat list did.
	func collapseEveryFolder() {
		let held = selectedPath
		for row in stride(from: outline.numberOfRows - 1, through: 0, by: -1) {
			if let item = outline.item(atRow: row), outline.isExpandable(item) {
				outline.collapseItem(item)
			}
		}
		if let held { select(path: held) }
	}

	// MARK: - Testing

	/// The rows as they are drawn, top to bottom, so a driven run can compare
	/// the two arrangements — and compare the flat one against what the page
	/// drew when its file list was a table.
	func rowsForTesting() -> [String] {
		(0..<outline.numberOfRows).compactMap { row in
			guard let node = outline.item(atRow: row) as? GitChangeNode else { return nil }
			let indent = String(repeating: "  ", count: outline.level(forRow: row))
			let shut = outline.isExpandable(node) && !outline.isItemExpanded(node)
				? " [shut]" : ""
			let selected = outline.selectedRow == row ? " <-" : ""
			// The path for a file, because two commits' worth of `spec.md` and
			// `design.md` are indistinguishable by name in the flat arrangement.
			let said = node.holdsFiles ? node.name + "/" : node.path
			return indent + said + shut + selected
		}
	}

	/// Works the file list from the keyboard, and says what happened.
	///
	/// Three claims in one report, because they fail together: a click gives the
	/// list the keyboard, the arrows move the selection, and ← and → shut and
	/// open a folder without losing the row that was selected.
	///
	/// The events are synthesised and handed to the view, so what is exercised
	/// is the view's own `mouseDown` and `keyDown` rather than a shortcut past
	/// them.
	func keysForTesting(_ steps: String) -> String {
		var said: [String] = []
		func who() -> String {
			guard let responder = outline.window?.firstResponder else { return "nobody" }
			return responder === outline ? "the file list" : String(describing: type(of: responder))
		}
		func selection() -> String {
			let row = outline.selectedRow
			guard row >= 0, let node = outline.item(atRow: row) as? GitChangeNode else {
				return "nothing"
			}
			return node.holdsFiles ? node.name + "/" : node.path
		}
		/// **The characters matter, not only the key code.** A table maps arrows
		/// through the key-binding manager, which reads what the key produced —
		/// `NSUpArrowFunctionKey` and its three neighbours — so an event with an
		/// empty string moves nothing however right its key code is. A first
		/// attempt at this report said the arrows did not work and the fault was
		/// here.
		func key(_ code: UInt16, _ scalar: UnicodeScalar) {
			let characters = String(Character(scalar))
			guard let event = NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: .function,
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: outline.window?.windowNumber ?? 0, context: nil,
				characters: characters, charactersIgnoringModifiers: characters,
				isARepeat: false, keyCode: code
			) else { return }
			outline.keyDown(with: event)
		}

		// `+` and not a comma: the step arrives as one field of a
		// comma-separated script, and a colon already means "and its argument".
		for step in steps.split(separator: "+").map(String.init) {
			switch step {
			case let step where step.hasPrefix("click"):
				let row = Int(step.dropFirst("click".count)) ?? 0
				guard row < outline.numberOfRows else { said.append("click\(row) no such row"); break }
				// Posted through the window server rather than handed to the
				// view. A table's `mouseDown` runs a tracking loop waiting for
				// the release, so a synthesised press on its own selects
				// nothing — which a first version of this did, and it read as
				// the click being broken when the instrument was.
				let rect = outline.rect(ofRow: row)
				let inWindow = outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
				guard let screen = outline.window?.convertPoint(toScreen: inWindow) else { break }
				let flipped = CGPoint(
					x: screen.x,
					y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y
				)
				NSApp.activate(ignoringOtherApps: true)
				for type in [CGEventType.leftMouseDown, .leftMouseUp] {
					CGEvent(
						mouseEventSource: nil, mouseType: type,
						mouseCursorPosition: flipped, mouseButton: .left
					)?.post(tap: .cghidEventTap)
				}
				// The loop above returns before AppKit has delivered them.
				RunLoop.current.run(until: Date().addingTimeInterval(0.4))
				said.append("click\(row) keyboard=\(who()) selected=\(selection())")
			case "down":  key(125, UnicodeScalar(0xF701)!); said.append("down selected=\(selection())")
			case "up":    key(126, UnicodeScalar(0xF700)!); said.append("up selected=\(selection())")
			case "left":  key(123, UnicodeScalar(0xF702)!); said.append("left selected=\(selection())")
			case "right": key(124, UnicodeScalar(0xF703)!); said.append("right selected=\(selection())")
			case "focus":
				outline.window?.makeFirstResponder(outline)
				said.append("focus keyboard=\(who())")
			case "select0":
				outline.selectRowIndexes([0], byExtendingSelection: false)
				said.append("select0 selected=\(selection())")
			case "who":   said.append("keyboard=\(who())")
			case "rows":  said.append("rows=\(outline.numberOfRows)")
			default:      said.append("unknown step \(step)")
			}
		}
		return said.joined(separator: " | ")
	}
}

// MARK: - The outline

extension ChangedFileList: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? GitChangeNode else { return roots.count }
		return node.children.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let node = item as? GitChangeNode else { return roots[index] }
		return node.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? GitChangeNode)?.holdsFiles ?? false
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? GitChangeNode else { return nil }
		guard let file = files.first(where: { $0.path == node.path }) else {
			return CommitFolderRowView(node: node)
		}
		return CommitFileRowView(file: file, lines: node.lines)
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		ThemedRowView()
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		(notification.object as? FileOutlineView)?.onSelectionChange?()
	}
}

/// The changes view of a git page: an outline in both arrangements.
///
/// Its own class rather than `HistoryTableView`, which the commit list is: the
/// two answer different keys. A commit folds with ← and → because a merge brings
/// a branch in; a list of files opens all of itself with `*` and has no merges.
private final class FileOutlineView: NSOutlineView {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	/// AppKit posts nothing when the first responder changes, and the editor's
	/// tab strip draws which tab holds the keyboard. Without this a click here
	/// moved the keyboard and the tab went on looking unfocused.
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

	var onSelectionChange: (() -> Void)?
	var rowHeightOverride: CGFloat?
	/// `*` — open everything.
	var onExpandAll: (() -> Void)?

	override func keyDown(with event: NSEvent) {
		// The character, not the key code: `*` is shift-8 on an ANSI layout and
		// somewhere else on every other one, and this is the key people press in
		// a file manager to mean "all of it".
		if event.charactersIgnoringModifiers == "*" {
			onExpandAll?()
			return
		}
		super.keyDown(with: event)
	}
}

// MARK: - The rows

/// `+12 −3`, drawn the same way for a file row and for the folder above it.
///
/// Two callers in this file, which is why it is one function rather than two
/// nearly-identical blocks; if a third appears, it belongs where a third caller
/// can see it.
private enum CommitLineCountLabel {
	static func make(_ lines: GitLineCount?) -> NSAttributedString? {
		guard let lines else { return nil }
		let font = Theme.current.uiFont(10)
		let text = NSMutableAttributedString()
		if lines.added > 0 {
			text.append(NSAttributedString(string: "+\(lines.added)", attributes: [
				.font: font, .foregroundColor: Theme.current.gitAdded,
			]))
		}
		if lines.removed > 0 {
			if text.length > 0 {
				text.append(NSAttributedString(string: " ", attributes: [.font: font]))
			}
			// A real minus, not a hyphen: a hyphen is narrower than the digits
			// beside it and reads as part of a filename.
			text.append(NSAttributedString(string: "\u{2212}\(lines.removed)", attributes: [
				.font: font, .foregroundColor: Theme.current.gitConflict,
			]))
		}
		guard text.length > 0 else { return nil }
		return text
	}
}

/// A folder in the changes view, when it is arranged by folder.
///
/// Only the folder arrangement makes these: the flat one is childless nodes and
/// every row is a file.
private final class CommitFolderRowView: NSView {
	private let node: GitChangeNode
	override var isFlipped: Bool { true }

	init(node: GitChangeNode) {
		self.node = node
		super.init(frame: .zero)
		toolTip = node.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(6)
		let glyph = Theme.current.scaled(13)
		FileIcon.folder()?.drawFitted(
			in: NSRect(x: x, y: bounds.midY - glyph / 2, width: glyph, height: glyph)
		)
		x += glyph + Theme.current.scaled(6)

		// How many files are under it, and — since `git-changes-detail` — how
		// much of them changed. Two numbers answering two questions, the way the
		// changes pane's folders say both.
		let right = bounds.maxX - Theme.current.scaled(8)
		var limit = right
		if let counts = CommitLineCountLabel.make(node.lines) {
			let size = counts.size()
			counts.draw(at: NSPoint(x: right - size.width, y: bounds.midY - size.height / 2))
			limit -= size.width + Theme.current.scaled(8)
		}
		let tally = NSAttributedString(string: "\(node.count)", attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		tally.draw(at: NSPoint(x: limit - tally.size().width, y: bounds.midY - tally.size().height / 2))
		limit -= tally.size().width + Theme.current.scaled(6)

		RowMetrics.draw(
			node.name,
			font: Theme.current.uiFont(12, weight: .medium),
			colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: limit
		)
	}
}

private final class CommitFileRowView: NSView {
	private let file: GitCommitFile
	override var isFlipped: Bool { true }

	private let lines: GitLineCount?

	init(file: GitCommitFile, lines: GitLineCount?) {
		self.file = file
		self.lines = lines
		super.init(frame: .zero)
		toolTip = file.originalPath.map { "\($0) → \(file.path)" } ?? file.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let left = Theme.current.scaled(10)
		let colour = Self.color(for: file.kind)

		// Noted before the measuring, not after: this row is where the CoreText
		// abort has twice been raised, and a note written afterwards would never
		// be written at all.
		LastDrawn.note("commit file row \(file.path)", font: Theme.current.uiFont(11.5))

		let letter = NSAttributedString(string: Self.letter(for: file.kind), attributes: [
			// Through the guard, not straight to `NSFont`: this is the row the
			// abort has been raised in three times, and a nullable font is what
			// it was.
			.font: Theme.current.monoFont(10, weight: .bold),
			.foregroundColor: colour,
		])
		letter.draw(at: NSPoint(x: left, y: bounds.midY - letter.size().height / 2))

		var x = left + Theme.current.scaled(16)
		let name = NSAttributedString(string: file.name, attributes: [
			.font: Theme.current.uiFont(11.5),
			.foregroundColor: Theme.current.sidebarText,
		])
		name.draw(at: NSPoint(x: x, y: bounds.midY - name.size().height / 2))
		x += name.size().width + Theme.current.scaled(6)

		// How much of it changed, at the far end of the row — the answer somebody
		// scanning a commit's files is scanning for, and the reason they would
		// otherwise open each one to find out it was a one-line change.
		var right = bounds.maxX - Theme.current.scaled(8)
		if let counts = CommitLineCountLabel.make(lines) {
			let size = counts.size()
			counts.draw(at: NSPoint(x: right - size.width, y: bounds.midY - size.height / 2))
			right -= size.width + Theme.current.scaled(8)
		}

		guard !file.directory.isEmpty else { return }
		let directory = NSAttributedString(string: file.directory, attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.gitIgnored,
		])
		directory.draw(in: NSRect(
			x: x,
			y: bounds.midY - directory.size().height / 2,
			width: max(0, right - x),
			height: directory.size().height
		))
	}

	private static func letter(for kind: GitChange.Kind) -> String {
		switch kind {
		case .added: return "A"
		case .deleted: return "D"
		case .renamed: return "R"
		case .copied: return "C"
		case .untracked: return "?"
		case .conflicted: return "!"
		case .modified: return "M"
		}
	}

	private static func color(for kind: GitChange.Kind) -> NSColor {
		switch kind {
		case .added, .copied: return Theme.current.gitAdded
		case .deleted: return Theme.current.gitUnversioned
		case .conflicted: return Theme.current.gitConflict
		default: return Theme.current.gitModified
		}
	}
}

import AppKit
import AbydosKit

/// The debug pane's Stack: every thread at the root, its frames under it.
///
/// Asked for on 2026-09-15 of a song being debugged — "the debugger should be a
/// tree", "a tree for the root threads". It replaced a list of one thread's
/// frames with a picker above it. The tree is `CallTree`'s; this keeps the
/// rows' identities across rebuilds so what is open stays open and what is
/// selected stays selected while a song plays under it.
///
/// A thread is open when it is the one the session is showing, when somebody
/// opened it, or when its adapter says it is busy (`isQuiet == false`, which
/// only a song's does); a thread that nobody said anything about stays shut, so
/// a Go program's thousand goroutines are a thousand rows and not a thousand
/// stacks read.
@MainActor
final class CallStackOutline: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
	weak var session: DebugSession?
	let projectRoot: URL
	var onNavigate: ((URL, Int) -> Void)?
	private(set) var outline: NSOutlineView!

	private var roots: [CallTree.Node] = []
	private var nodes: [String: CallTree.Node] = [:]
	/// What somebody opened or shut by hand, which beats every default.
	private var chosen: [String: Bool] = [:]
	/// Rows being opened by a rebuild rather than by a click.
	private var rebuilding = false
	/// The selected frame's row the tree last scrolled to.
	private var shownSelection: String?
	/// The session's frame as of the last rebuild, to tell a frame it moved to
	/// from the one it is still catching up with.
	private var lastSessionKey: String?
	/// Until when rebuilds keep the selected row in sight.
	private var followSelectionUntil = Date.distantPast
	/// The rows as they stand, in order, and what each one says: a rebuild that
	/// changes neither is no rebuild at all — `reloadData` drops the selection
	/// and every open row, and a song's stack arrives several times a second.
	private var shape: [String] = []
	private var drawn: [String: String] = [:]
	/// A selection being set here rather than by somebody at the keyboard.
	private var selecting = false

	init(session: DebugSession?, projectRoot: URL) {
		self.session = session
		self.projectRoot = projectRoot
		super.init()
	}

	func makeOutline() -> NSOutlineView {
		let view = NSOutlineView()
		view.headerView = nil
		view.backgroundColor = Theme.current.editorBackground
		view.selectionHighlightStyle = .regular
		view.rowSizeStyle = .custom
		view.intercellSpacing = .zero
		view.indentationPerLevel = Theme.current.scaled(12)
		view.gridStyleMask = []
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("frame"))
		view.addTableColumn(column)
		view.outlineTableColumn = column
		view.dataSource = self
		view.delegate = self
		view.target = self
		view.action = #selector(clicked)
		outline = view
		return view
	}

	/// Rebuilds from what the session holds, keeping rows that are still there.
	func reload() {
		guard let outline else { return }
		guard let session else {
			roots = []
			nodes = [:]
			outline.reloadData()
			return
		}
		var kept: [String: CallTree.Node] = [:]
		func reuse(_ fresh: [CallTree.Node]) -> [CallTree.Node] {
			fresh.map { node in
				let same = nodes[node.key] ?? node
				same.kind = node.kind
				same.children = reuse(node.children)
				kept[node.key] = same
				return same
			}
		}
		roots = reuse(CallTree.nodes(threads: session.threads, stacks: session.threadStacks))
		nodes = kept

		rebuilding = true
		let fresh = order(of: roots)
		if fresh == shape {
			// The same rows: only the ones whose text changed are drawn again.
			for node in nodes.values where drawn[node.key] != said(node) {
				drawn[node.key] = said(node)
				let row = outline.row(forItem: node)
				if row >= 0 { outline.reloadItem(node) }
			}
		} else {
			shape = fresh
			drawn = Dictionary(uniqueKeysWithValues: nodes.values.map { ($0.key, said($0)) })
			outline.reloadData()
			open(roots)
		}
		// **The session's frame moves the selection only when it moves.** It
		// follows the arrow keys a moment behind, and re-asserting it on every
		// rebuild put the selection back where it had just come from.
		let sessionKey = session.selectedThreadID.flatMap { thread in
			session.selectedFrameID.map { "f:\(thread):\($0)" }
		}
		let moved = sessionKey != lastSessionKey
		lastSessionKey = sessionKey
		if let key = moved ? sessionKey : (outline.selectedRow < 0 ? shownSelection ?? sessionKey : nil),
		   let node = nodes[key] {
			let row = outline.row(forItem: node)
			if row >= 0 {
				selecting = true
				outline.selectRowIndexes([row], byExtendingSelection: false)
				selecting = false
				// Scrolled to when the selection is new — a stop, a click — and not
				// on every rebuild, which would take the tree out of somebody's
				// hands while a song plays under it.
				// After layout: the first stop opens the panel, and a row scrolled to
				// in a view that has no height yet was not scrolled to at all. And
				// for a moment after, not once: the other threads' stacks are read
				// just after a stop, open above the selected row, and pushed it out
				// of sight again — measured, row 17 of 29 with rows 0–12 showing.
				if node.key != shownSelection { followSelectionUntil = Date().addingTimeInterval(1.5) }
				if Date() < followSelectionUntil {
					DispatchQueue.main.async { [weak outline, node] in
						guard let outline else { return }
						let row = outline.row(forItem: node)
						if row >= 0 { outline.scrollRowToVisible(row) }
					}
				}
				shownSelection = node.key
			}
		}
		rebuilding = false
	}

	/// Every row the tree would show, in order, opened rows' children included.
	private func order(of list: [CallTree.Node]) -> [String] {
		list.flatMap { [$0.key] + order(of: $0.children) }
	}

	private func said(_ node: CallTree.Node) -> String {
		CallTree.describe([CallTree.Node(key: node.key, kind: node.kind)]).first ?? node.key
	}

	private func open(_ list: [CallTree.Node]) {
		for node in list where !node.children.isEmpty || isThread(node) {
			if chosen[node.key] ?? opensByDefault(node) {
				outline.expandItem(node)
				open(node.children)
			}
		}
	}

	private func isThread(_ node: CallTree.Node) -> Bool {
		if case .thread = node.kind { return true }
		return false
	}

	private func opensByDefault(_ node: CallTree.Node) -> Bool {
		switch node.kind {
		case .group, .frame: return true
		case let .thread(thread): return thread.id == session?.selectedThreadID || thread.isQuiet == false
		}
	}

	// MARK: - Clicks

	/// Somebody moved the selection — an arrow key, a click, a drag: the frame
	/// under it is the one to show.
	///
	/// Every selection that this object did not make itself, rather than only
	/// the ones arriving with a key event: `NSApp.currentEvent` is whatever the
	/// app last dequeued, which is nothing at all for a key delivered straight
	/// to the responder, and a selection the tree then forgot on its next
	/// rebuild.
	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard !selecting, !rebuilding else { return }
		choose(row: outline.selectedRow)
	}

	@objc private func clicked() {
		// The keyboard comes with the click: an outline walks itself with the
		// arrows, and never had it here.
		outline.window?.makeFirstResponder(outline)
		choose(row: outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow)
	}

	/// Hands the frame on a row to the session, and opens where it is.
	///
	/// **And keeps the keyboard.** Opening the frame's line gives it to the
	/// editor, so walking the tree with ↓ moved one row and then typed into the
	/// code: every step after the first went somewhere else.
	private func choose(row: Int) {
		guard let session, let node = outline.item(atRow: row) as? CallTree.Node else { return }
		let hadKeyboard = outline.window?.firstResponder === outline
		defer {
			if hadKeyboard {
				DispatchQueue.main.async { [weak outline] in
					guard let outline, outline.window?.firstResponder !== outline else { return }
					outline.window?.makeFirstResponder(outline)
				}
			}
		}
		switch node.kind {
		case let .frame(frame, thread):
			shownSelection = node.key
			lastSessionKey = node.key
			Task { await session.selectFrame(id: frame.id, thread: thread) }
			if let file = frame.file { onNavigate?(URL(fileURLWithPath: file), frame.line) }
		case let .thread(thread):
			// A thread's row goes where it is: the top of its stack, without
			// moving the selection off the row somebody is on.
			guard let top = session.threadStacks[thread.id]?.first else { return }
			shownSelection = "f:\(thread.id):\(top.id)"
			lastSessionKey = shownSelection
			Task { await session.selectFrame(id: top.id, thread: thread.id) }
			if let file = top.file { onNavigate?(URL(fileURLWithPath: file), top.line) }
		case .group:
			break
		}
	}

	// MARK: - Data

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? CallTree.Node else { return roots.count }
		return node.children.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let node = item as? CallTree.Node else { return roots[index] }
		return node.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let node = item as? CallTree.Node else { return false }
		// A thread can be opened before its stack is read; opening reads it.
		return !node.children.isEmpty || isThread(node)
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		guard let node = notification.userInfo?["NSObject"] as? CallTree.Node else { return }
		if !rebuilding { chosen[node.key] = true }
		guard case let .thread(thread) = node.kind, let session else { return }
		session.expandedThreads.insert(thread.id)
		if session.threadStacks[thread.id] == nil {
			Task { await session.loadStack(thread: thread.id) }
		}
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		guard let node = notification.userInfo?["NSObject"] as? CallTree.Node else { return }
		if !rebuilding { chosen[node.key] = false }
		if case let .thread(thread) = node.kind { session?.expandedThreads.remove(thread.id) }
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		guard let node = item as? CallTree.Node, case .frame = node.kind else { return Theme.current.scaled(22) }
		return Theme.current.scaled(34)
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		ThemedRowView()
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? CallTree.Node else { return nil }
		switch node.kind {
		case let .group(name):
			return ScopeCell(name: name)
		case let .thread(thread):
			let cell = ThreadCell(name: thread.name.isEmpty ? "Thread \(thread.id)" : thread.name)
			cell.alphaValue = thread.isQuiet == true ? 0.5 : 1
			return cell
		case let .frame(frame, _):
			let cell = StackFrameCell(stackFrame: frame, projectRoot: projectRoot)
			cell.alphaValue = frame.isSubtle ? 0.5 : 1
			return cell
		}
	}

	/// Gives the tree the keyboard, with a row for the arrows to start from.
	func focus() {
		guard let window = outline.window else { return }
		window.makeFirstResponder(outline)
		if outline.selectedRow < 0, outline.numberOfRows > 0 {
			selecting = true
			outline.selectRowIndexes([0], byExtendingSelection: false)
			selecting = false
		}
	}

	var hasKeyboardForTesting: Bool { outline.window?.firstResponder === outline }

	/// The tree as the pane shows it, open rows only, for a driven run.
	var reportForTesting: String {
		let visible = outline.map { $0.rows(in: $0.visibleRect) } ?? NSRange()
		var lines: [String] = ["rows=\(outline?.numberOfRows ?? 0) selected=\(outline?.selectedRow ?? -1) visible=\(visible.location)..<\(NSMaxRange(visible)) shown=\(shownSelection ?? "none")"]
		for row in 0..<(outline?.numberOfRows ?? 0) {
			guard let node = outline.item(atRow: row) as? CallTree.Node else { continue }
			let pad = String(repeating: "  ", count: outline.level(forRow: row))
			let open = outline.isItemExpanded(node) ? "v " : (outline.isExpandable(node) ? "> " : "  ")
			let selected = outline.selectedRow == row ? " *" : ""
			lines.append(pad + open + (CallTree.describe([CallTree.Node(key: node.key, kind: node.kind)]).first ?? "") + selected)
		}
		return lines.joined(separator: "\n")
	}
}

/// A thread's row: its name, on one line.
final class ThreadCell: NSView {
	private let name: String

	init(name: String) {
		self.name = name
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let label = NSAttributedString(string: name, attributes: [
			.font: Theme.current.uiFont(11.5, weight: .semibold),
			.foregroundColor: isSelected ? NSColor.hex(0xE8EAED) : Theme.current.sidebarHeaderText,
		])
		label.draw(at: NSPoint(x: Theme.current.scaled(2), y: (bounds.height - label.size().height) / 2))
	}
}

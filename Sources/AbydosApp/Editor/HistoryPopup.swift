import AppKit
import AbydosKit

/// The states a file has been in, and a way back to any of them.
///
/// Undo and redo reach most of them, but not the ones on a branch you left:
/// those are only reachable by name, which is what this is. Shown as a list
/// rather than a drawn tree — a tree of edits looks impressive and tells you
/// nothing, whereas "what changed and when" is the question actually being
/// asked, and branches only need marking rather than drawing.
final class HistoryPopup: NSObject {
	/// Go to one of the states.
	var onTravel: ((Int) -> Void)?

	private var window: NSPanel?
	private var tableView: NSTableView?
	private var rows: [Row] = []

	private struct Row {
		let node: UndoTree.Node
		/// Whether this state is on the way to where the document is now.
		let isOnPath: Bool
		let isCurrent: Bool
		/// How far from the trunk, so a branch can be indented.
		let depth: Int
	}

	var isVisible: Bool { window?.isVisible ?? false }

	func toggle(history: UndoTree, over view: NSView) {
		if isVisible {
			hide()
		} else {
			show(history: history, over: view)
		}
	}

	func show(history: UndoTree, over view: NSView) {
		rows = Self.rows(from: history)
		guard let parent = view.window else { return }

		let window = self.window ?? makeWindow()
		self.window = window

		let height = min(CGFloat(rows.count) * 34 + 2, 420)
		let width: CGFloat = 380

		// Top-right of the editor, out of the way of the text being read.
		let viewFrame = view.convert(view.bounds, to: nil)
		let onScreen = parent.convertToScreen(viewFrame)
		let origin = NSPoint(x: onScreen.maxX - width - 24, y: onScreen.maxY - height - 24)

		window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
		tableView?.reloadData()

		if let index = rows.firstIndex(where: \.isCurrent) {
			tableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
			tableView?.scrollRowToVisible(index)
		}

		if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
		window.orderFront(nil)
	}

	func hide() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
	}

	/// The timeline, oldest first, with branches marked.
	private static func rows(from history: UndoTree) -> [Row] {
		history.timeline.map { node in
			var depth = 0
			var cursor: Int? = node.parent
			while let id = cursor {
				// A state whose parent had more than one child begins a branch,
				// and everything under it is one step further from the trunk.
				if history.nodes[id].children.count > 1 { depth += 1 }
				cursor = history.nodes[id].parent
			}
			return Row(
				node: node,
				isOnPath: history.isOnCurrentPath(node.id),
				isCurrent: node.id == history.current,
				depth: min(depth, 4)
			)
		}
		.reversed()
	}

	private func makeWindow() -> NSPanel {
		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = 34
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.selectionHighlightStyle = .regular
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state")))
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.action = #selector(rowClicked)
		tableView = table

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.wantsLayer = true
		scroll.layer?.cornerRadius = 6
		scroll.layer?.borderWidth = 1
		scroll.layer?.borderColor = Theme.current.separator.cgColor

		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		window.hasShadow = true
		window.isOpaque = false
		window.backgroundColor = Theme.current.sidebarBackground
		window.level = .floating
		window.contentView = scroll
		return window
	}

	@objc private func rowClicked() {
		guard let row = tableView?.clickedRow, rows.indices.contains(row) else { return }
		onTravel?(rows[row].node.id)
		hide()
	}

	// MARK: - Testing

	var summariesForTesting: [String] { rows.map(\.node.summary) }
	func travelToRowForTesting(_ index: Int) {
		guard rows.indices.contains(index) else { return }
		onTravel?(rows[index].node.id)
	}
}

extension HistoryPopup: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard rows.indices.contains(row) else { return nil }
		let entry = rows[row]
		return HistoryRowView(
			summary: entry.node.summary,
			time: entry.node.time,
			isOnPath: entry.isOnPath,
			isCurrent: entry.isCurrent,
			depth: entry.depth
		)
	}
}

/// One state: what it did, when, and whether it is on the way to here.
private final class HistoryRowView: NSView {
	private let summary: String
	private let time: Date
	private let isOnPath: Bool
	private let isCurrent: Bool
	private let depth: Int

	override var isFlipped: Bool { true }

	init(summary: String, time: Date, isOnPath: Bool, isCurrent: Bool, depth: Int) {
		self.summary = summary
		self.time = time
		self.isOnPath = isOnPath
		self.isCurrent = isCurrent
		self.depth = depth
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let left = Theme.current.scaled(10) + CGFloat(depth) * Theme.current.scaled(14)

		// A dot on the line down the left: filled for where the document is,
		// hollow for a state on the way there, faint for one on a branch that
		// was left behind.
		let dotSize = Theme.current.scaled(7)
		let dot = NSRect(
			x: left, y: bounds.midY - dotSize / 2, width: dotSize, height: dotSize
		)
		let colour = isCurrent
			? Theme.current.gitAdded
			: (isOnPath ? Theme.current.gitModified : Theme.current.gitIgnored)
		colour.setStroke()
		colour.withAlphaComponent(isCurrent ? 1 : 0.25).setFill()
		let path = NSBezierPath(ovalIn: dot)
		path.fill()
		path.stroke()

		let x = left + dotSize + Theme.current.scaled(8)
		let title = NSAttributedString(string: summary, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: isOnPath ? Theme.current.sidebarText : Theme.current.gitIgnored,
		])
		title.draw(in: NSRect(
			x: x, y: Theme.current.scaled(4),
			width: max(0, bounds.width - x - Theme.current.scaled(70)),
			height: title.size().height
		))

		let stamp = NSAttributedString(string: Self.clock.string(from: time), attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.gitIgnored,
		])
		stamp.draw(at: NSPoint(
			x: bounds.maxX - stamp.size().width - Theme.current.scaled(10),
			y: Theme.current.scaled(5)
		))

		guard !isOnPath else { return }
		let note = NSAttributedString(string: "on another branch", attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.gitIgnored,
		])
		note.draw(at: NSPoint(x: x, y: Theme.current.scaled(18)))
	}

	private static let clock: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "HH:mm:ss"
		return formatter
	}()
}

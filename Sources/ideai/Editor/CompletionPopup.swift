import AppKit
import IdeaiKit

/// One thing that could be typed next.
struct CompletionItem: Equatable {
	let label: String
	/// What actually gets inserted, which is not always what is shown.
	let insertText: String
	/// A type, a signature — whatever the server had to say about it.
	let detail: String?
	/// Whether this came from a language server or from the words in the file.
	let isFromServer: Bool

	init(label: String, insertText: String? = nil, detail: String? = nil, isFromServer: Bool) {
		self.label = label
		self.insertText = insertText ?? label
		self.detail = detail
		self.isFromServer = isFromServer
	}

	init(_ completion: LSPCompletion) {
		self.init(
			label: completion.label,
			insertText: completion.insertText,
			detail: completion.detail,
			isFromServer: true
		)
	}
}

/// The list that appears under the caret while typing.
///
/// A borderless window rather than a view inside the editor: it has to be able
/// to hang past the bottom of the editor and over the status bar, which a
/// subview cannot do. It never takes focus — the keys that drive it are
/// intercepted by the editor and forwarded, so typing continues into the
/// document while the list narrows.
final class CompletionPopup: NSObject {
	private var window: NSWindow?
	private var tableView: NSTableView?
	private var items: [CompletionItem] = []
	private var selection = 0

	/// The user chose something.
	var onCommit: ((CompletionItem) -> Void)?

	var isVisible: Bool { window?.isVisible ?? false }
	var selectedItem: CompletionItem? { items.indices.contains(selection) ? items[selection] : nil }

	private static var rowHeight: CGFloat { Theme.current.scaled(22) }
	private static let maximumVisibleRows = 9

	override init() { super.init() }

	/// Shows the list under a point in screen coordinates, or hides it when
	/// there is nothing to say.
	func show(items: [CompletionItem], below point: NSPoint, lineHeight: CGFloat, parent: NSWindow?) {
		guard !items.isEmpty, let parent else {
			hide()
			return
		}

		self.items = items
		selection = 0

		let window = self.window ?? makeWindow()
		self.window = window

		let width = Self.width(for: items)
		let height = Self.rowHeight * CGFloat(min(items.count, Self.maximumVisibleRows)) + 2

		// Clear of the line it belongs to. `point` is the top of the caret, so
		// the line's bottom is a line-height below it; a list placed straight
		// under the point covers the very text being completed.
		let lineBottom = point.y - lineHeight
		let screen = parent.screen ?? NSScreen.main
		var origin = NSPoint(x: point.x, y: lineBottom - height - 4)
		if let frame = screen?.visibleFrame, origin.y < frame.minY {
			// No room underneath: above the line, where a menu would go.
			origin.y = point.y + 4
		}

		window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
		tableView?.reloadData()
		tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		tableView?.scrollRowToVisible(0)

		if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
		window.orderFront(nil)
	}

	func hide() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		items = []
	}

	/// Moves the highlight. Returns false when there is nothing to move.
	@discardableResult
	func moveSelection(by delta: Int) -> Bool {
		guard isVisible, !items.isEmpty else { return false }
		selection = max(0, min(items.count - 1, selection + delta))
		tableView?.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
		tableView?.scrollRowToVisible(selection)
		return true
	}

	func commitSelection() -> Bool {
		guard isVisible, let item = selectedItem else { return false }
		hide()
		onCommit?(item)
		return true
	}

	private static func width(for items: [CompletionItem]) -> CGFloat {
		let font = Theme.current.uiFont(12)
		let widest = items.reduce(CGFloat(200)) { widest, item in
			var text = item.label
			if let detail = item.detail { text += "   \(detail)" }
			let size = (text as NSString).size(withAttributes: [.font: font])
			return max(widest, size.width + 28)
		}
		return min(widest, 460)
	}

	private func makeWindow() -> NSWindow {
		let table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = Self.rowHeight
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.selectionHighlightStyle = .regular
		// Plain, or AppKit insets every row and draws the selection as a
		// rounded capsule floating inside it — which in a list this small is
		// most of the popup, and clips the text it is meant to be showing.
		table.style = .plain
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion")))
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
		scroll.autohidesScrollers = true
		// Overlay, so a scroller does not take a strip out of a list that is
		// only a couple of hundred points wide.
		scroll.scrollerStyle = .overlay

		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		window.hasShadow = true
		window.isOpaque = false
		window.backgroundColor = Theme.current.sidebarBackground
		window.level = .popUpMenu
		// Never takes focus: the caret must keep blinking in the document and
		// the keys must keep reaching it.
		window.ignoresMouseEvents = false
		window.contentView = scroll

		scroll.wantsLayer = true
		scroll.layer?.cornerRadius = 5
		scroll.layer?.borderWidth = 1
		scroll.layer?.borderColor = Theme.current.separator.cgColor
		return window
	}

	@objc private func rowClicked() {
		guard let row = tableView?.clickedRow, items.indices.contains(row) else { return }
		selection = row
		_ = commitSelection()
	}

	// MARK: - Testing

	/// Draws the list to a PNG, since a child window is invisible to a capture
	/// of the main one.
	@discardableResult
	func writeImageForTesting(to path: String) -> Bool {
		guard let view = window?.contentView else { return false }
		view.layoutSubtreeIfNeeded()
		guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
		view.cacheDisplay(in: view.bounds, to: rep)
		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		return (try? data.write(to: URL(fileURLWithPath: path))) != nil
	}

	var labelsForTesting: [String] { items.map(\.label) }
	var selectedIndexForTesting: Int { selection }
	var frameForTesting: NSRect { window?.frame ?? .zero }
}

extension CompletionPopup: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { items.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard items.indices.contains(row) else { return nil }
		return CompletionRowView(item: items[row])
	}
}

/// A row: what would be inserted, and whatever the server knows about it.
private final class CompletionRowView: NSView {
	private let item: CompletionItem
	override var isFlipped: Bool { true }

	init(item: CompletionItem) {
		self.item = item
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let left = Theme.current.scaled(8)

		let label = NSAttributedString(string: item.label, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		label.draw(at: NSPoint(x: left, y: bounds.midY - label.size().height / 2))

		guard let detail = item.detail, !detail.isEmpty else { return }
		let attributed = NSAttributedString(string: detail, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		let x = left + label.size().width + Theme.current.scaled(10)
		attributed.draw(in: NSRect(
			x: x,
			y: bounds.midY - attributed.size().height / 2,
			width: max(0, bounds.width - x - Theme.current.scaled(8)),
			height: attributed.size().height
		))
	}
}

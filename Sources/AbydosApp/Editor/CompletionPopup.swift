import AppKit
import AbydosKit

/// One thing that could be typed next.
struct CompletionItem: Equatable {
	let label: String
	/// What actually gets inserted, which is not always what is shown.
	let insertText: String
	/// A type, a signature — whatever the server had to say about it.
	let detail: String?
	/// The server's prose about this item, already reduced to text.
	///
	/// **Carried because it is the answer to the question that started this.**
	/// openscad-lsp sends 1530 characters with `cube`, of which two lines say
	/// that `size` is either one number or `[x, y, z]`; they were parsed into
	/// `LSPCompletion` and then dropped here, one assignment short of the
	/// screen.
	let documentation: String?
	/// The same prose with its markup still on.
	///
	/// **Both are kept, and the reason is a fault this had.** A parameter's
	/// heading is only recognisable while it is still `**size**`: reduced, it is
	/// a line saying `size`, indistinguishable from a line of prose, so
	/// `description(ofParameter:in:)` found where `size` started and had nothing
	/// to tell it where `center` began. The hint for `size` ran to the end of
	/// the page, examples and all.
	let documentationSource: String?
	/// Whether this came from a language server or from the words in the file.
	let isFromServer: Bool
	/// Whether `insertText` is a snippet — placeholders and a caret position
	/// rather than text to paste.
	let isSnippet: Bool

	init(
		label: String,
		insertText: String? = nil,
		detail: String? = nil,
		documentation: String? = nil,
		documentationSource: String? = nil,
		isFromServer: Bool,
		isSnippet: Bool = false
	) {
		self.label = label
		self.insertText = insertText ?? label
		self.detail = detail
		self.documentation = documentation
		self.documentationSource = documentationSource
		self.isFromServer = isFromServer
		self.isSnippet = isSnippet
	}

	init(_ completion: LSPCompletion) {
		// Reduced here rather than while drawing: the panel is redrawn as the
		// selection moves, and a wiki page taken apart on every ↓ is a cost per
		// keystroke. Twenty items is twenty reductions once.
		let prose = completion.documentation.map(ServerDocumentation.readable)
		self.init(
			label: completion.label,
			insertText: completion.insertText,
			detail: completion.detail,
			documentation: (prose?.isEmpty ?? true) ? nil : prose,
			documentationSource: completion.documentation,
			isFromServer: true,
			isSnippet: completion.isSnippet
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
	private var listScroll: NSScrollView?
	private var documentationScroll: NSScrollView?
	private var documentationText: NSTextView?
	private var items: [CompletionItem] = []
	private var selection = 0
	/// Shown instead of a list: a sentence about why there is nothing to offer
	/// *yet*, which is not the same as having nothing to offer.
	private var notice: String?

	/// The user chose something.
	var onCommit: ((CompletionItem) -> Void)?

	var isVisible: Bool { window?.isVisible ?? false }
	var selectedItem: CompletionItem? { items.indices.contains(selection) ? items[selection] : nil }
	/// Whether what is up is a sentence rather than a list.
	///
	/// Read by the editor so that the moment a server finishes preparing, the
	/// list it was told to wait for is asked for again — and so that nothing
	/// else is re-asked, since every other popup on screen is already an answer.
	var isWaitingOnAServer: Bool { isVisible && notice != nil }

	private static var rowHeight: CGFloat { Theme.current.scaled(22) }
	private static let maximumVisibleRows = 9
	/// How wide the prose beside the list is drawn.
	///
	/// Wide enough for a sentence and no wider: this hangs over the code being
	/// typed, and a panel as wide as the documentation would like to be is a
	/// panel covering the file.
	private static var documentationWidth: CGFloat { Theme.current.scaled(320) }
	/// And no taller than this, however long the page is. openscad-lsp answers
	/// `cube` with a wiki page; a panel sized to its content would be the
	/// window.
	private static var documentationMaximumHeight: CGFloat { Theme.current.scaled(260) }

	override init() { super.init() }

	/// Shows the list under a point in screen coordinates, or hides it when
	/// there is nothing to say.
	func show(items: [CompletionItem], below point: NSPoint, lineHeight: CGFloat, parent: NSWindow?) {
		guard !items.isEmpty, let parent else {
			hide()
			return
		}

		notice = nil
		self.items = items
		selection = 0
		present(below: point, lineHeight: lineHeight, parent: parent)
	}

	/// Shows a sentence where the list would be.
	///
	/// **Because an empty answer and a server that has not finished starting
	/// look identical from here.** Measured against a Cadova package,
	/// sourcekit-lsp answered nothing at 1, 11, 32 and 62 seconds after the file
	/// was opened — no error, just nothing — and the enum cases somebody was
	/// waiting for at 123, once it had built 651 files to index them. What was
	/// shown in that window was the words already in the file, which reads as an
	/// answer and is not one.
	func show(notice text: String, below point: NSPoint, lineHeight: CGFloat, parent: NSWindow?) {
		guard let parent else {
			hide()
			return
		}

		items = []
		selection = 0
		notice = text
		present(below: point, lineHeight: lineHeight, parent: parent)
	}

	private func present(below point: NSPoint, lineHeight: CGFloat, parent: NSWindow) {
		let window = self.window ?? makeWindow()
		self.window = window

		let listWidth = notice == nil ? Self.width(for: items) : Self.width(forNotice: notice ?? "")
		let rows = notice == nil ? min(items.count, Self.maximumVisibleRows) : 1
		let listHeight = Self.rowHeight * CGFloat(rows) + 2

		tableView?.reloadData()
		if notice == nil {
			tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			tableView?.scrollRowToVisible(0)
		}

		// The prose the selected item carries, if it carries any and if there is
		// anywhere to put it.
		let screen = parent.screen ?? NSScreen.main
		let prose = notice == nil ? selectedItem?.documentation : nil
		let side = prose == nil ? nil : Self.side(
			forListAt: point.x, listWidth: listWidth, on: screen
		)
		let totalWidth = side == nil ? listWidth : listWidth + Self.documentationWidth
		let height = side == nil ? listHeight : max(listHeight, Self.documentationMaximumHeight)

		// Clear of the line it belongs to. `point` is the top of the caret, so
		// the line's bottom is a line-height below it; a list placed straight
		// under the point covers the very text being completed.
		let lineBottom = point.y - lineHeight
		var origin = NSPoint(x: point.x, y: lineBottom - height - 4)
		if let frame = screen?.visibleFrame, origin.y < frame.minY {
			// No room underneath: above the line, where a menu would go.
			origin.y = point.y + 4
		}
		// **The list never moves to make room for the panel.** Where the prose
		// goes on the left, the window starts further left and the list stays
		// exactly where it would have been without any documentation at all —
		// otherwise turning a panel on would shift the thing somebody is reading.
		if side == .left { origin.x -= Self.documentationWidth }

		window.setFrame(
			NSRect(origin: origin, size: NSSize(width: totalWidth, height: height)),
			display: true
		)
		layout(
			listWidth: listWidth,
			listHeight: listHeight,
			documentationOn: side,
			in: NSSize(width: totalWidth, height: height)
		)
		showDocumentation(prose, visible: side != nil)

		if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
		window.orderFront(nil)
	}

	func hide() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		items = []
		notice = nil
	}

	/// Moves the highlight. Returns false when there is nothing to move.
	@discardableResult
	func moveSelection(by delta: Int) -> Bool {
		guard isVisible, !items.isEmpty else { return false }
		selection = max(0, min(items.count - 1, selection + delta))
		tableView?.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
		tableView?.scrollRowToVisible(selection)
		// The panel follows the selection: it says something about the item that
		// is highlighted, and a panel a row behind is worse than none.
		documentationText?.string = selectedItem?.documentation ?? ""
		documentationScroll?.documentView?.scroll(.zero)
		return true
	}

	func commitSelection() -> Bool {
		// A sentence is not something to take. Return means the newline it
		// always meant, and Tab indents.
		guard isVisible, notice == nil, let item = selectedItem else { return false }
		hide()
		onCommit?(item)
		return true
	}

	/// Which side of the list the prose goes on, or nothing where neither side
	/// has room for it.
	private enum Side { case left, right }

	private static func side(forListAt x: CGFloat, listWidth: CGFloat, on screen: NSScreen?) -> Side? {
		guard let frame = screen?.visibleFrame else { return .right }
		if x + listWidth + documentationWidth <= frame.maxX { return .right }
		if x - documentationWidth >= frame.minX { return .left }
		return nil
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

	private static func width(forNotice text: String) -> CGFloat {
		let size = (text as NSString).size(withAttributes: [.font: Theme.current.uiFont(12)])
		return min(max(200, size.width + 28), 460)
	}

	/// Puts the list and the prose side by side inside the one window.
	///
	/// One window rather than two: the popup is a non-activating child panel so
	/// that the caret keeps blinking in the document, and a second one of those
	/// is a second thing to place, to order and to hide — and one chance for the
	/// two to come apart when the list is repositioned near the edge of a screen.
	private func layout(
		listWidth: CGFloat,
		listHeight: CGFloat,
		documentationOn side: Side?,
		in size: NSSize
	) {
		// The list keeps its own height and sits at the top. Stretched to the
		// panel's height it is a tall empty box under one row, which reads as a
		// list still loading rather than as a list with one answer in it.
		let listX = side == .left ? Self.documentationWidth : 0
		listScroll?.frame = NSRect(
			x: listX, y: size.height - listHeight, width: listWidth, height: listHeight
		)
		guard let side else {
			documentationScroll?.frame = .zero
			return
		}
		documentationScroll?.frame = NSRect(
			x: side == .left ? 0 : listWidth,
			y: 0,
			width: Self.documentationWidth,
			height: size.height
		)
	}

	private func showDocumentation(_ prose: String?, visible: Bool) {
		documentationScroll?.isHidden = !visible || prose == nil
		documentationText?.string = prose ?? ""
		documentationScroll?.documentView?.scroll(.zero)
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
		listScroll = scroll

		let prose = NSTextView()
		prose.isEditable = false
		// Selectable, because half of what a server says is an example somebody
		// wants to copy rather than retype.
		prose.isSelectable = true
		prose.drawsBackground = false
		prose.font = Theme.current.uiFont(11.5)
		prose.textColor = Theme.current.sidebarText
		prose.textContainerInset = NSSize(width: 8, height: 8)
		prose.isVerticallyResizable = true
		prose.autoresizingMask = [.width]
		documentationText = prose

		let proseScroll = NSScrollView()
		proseScroll.documentView = prose
		proseScroll.hasVerticalScroller = true
		proseScroll.drawsBackground = true
		proseScroll.backgroundColor = Theme.current.sidebarBackground
		proseScroll.autohidesScrollers = true
		proseScroll.scrollerStyle = .overlay
		proseScroll.isHidden = true
		documentationScroll = proseScroll

		let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 120))
		container.addSubview(scroll)
		container.addSubview(proseScroll)

		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		window.hasShadow = true
		window.isOpaque = false
		// Clear, now that there are two boxes in here rather than one. A window
		// painted the same colour as the list was invisible behind it while the
		// list was the whole of the window; with a panel beside it and the list
		// only as tall as its rows, the same colour becomes a dark rectangle
		// filling the gap under the list — which reads as a list still loading.
		window.backgroundColor = .clear
		window.level = .popUpMenu
		// Never takes focus: the caret must keep blinking in the document and
		// the keys must keep reaching it.
		window.ignoresMouseEvents = false
		window.contentView = container

		for view in [scroll, proseScroll] {
			view.wantsLayer = true
			view.layer?.cornerRadius = 5
			view.layer?.borderWidth = 1
			view.layer?.borderColor = Theme.current.separator.cgColor
		}
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
	/// What the panel beside the list is showing, or nothing when there is no
	/// panel — which is the difference a test about `cube` is making.
	var documentationForTesting: String? {
		guard documentationScroll?.isHidden == false else { return nil }
		let shown = documentationText?.string ?? ""
		return shown.isEmpty ? nil : shown
	}
	var noticeForTesting: String? { notice }
}

extension CompletionPopup: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { notice == nil ? items.count : 1 }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		if let notice { return NoticeRowView(text: notice) }
		guard items.indices.contains(row) else { return nil }
		return CompletionRowView(item: items[row])
	}

	/// Nothing to select while a sentence is up: a highlight over it would say
	/// it was something to take, and Return would then look like it should
	/// insert it.
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { notice == nil }
}

/// The row that says why there is no list yet.
private final class NoticeRowView: NSView {
	private let text: String
	override var isFlipped: Bool { true }

	init(text: String) {
		self.text = text
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let attributed = NSAttributedString(string: text, attributes: [
			.font: Theme.current.uiFont(12),
			// Dimmed, because it is not an answer and must not read as one.
			.foregroundColor: Theme.current.gitIgnored,
		])
		attributed.draw(at: NSPoint(
			x: Theme.current.scaled(8),
			y: bounds.midY - attributed.size().height / 2
		))
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

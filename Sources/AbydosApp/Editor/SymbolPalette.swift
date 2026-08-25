import AppKit
import AbydosKit

/// Go to a symbol by typing its name.
///
/// The fastest way through a codebase you know: you remember what a thing is
/// called long before you remember which file it is in. Two scopes — this file
/// and the whole project — because "jump to that function I am looking at" and
/// "find that type somewhere in here" are different questions asked at
/// different moments.
@MainActor
final class SymbolPalette: NSObject {
	enum Scope {
		case document, workspace

		var placeholder: String {
			switch self {
			case .document: return "Go to a declaration in this file — esc to close"
			case .workspace: return "Go to a symbol in this project — esc to close"
			}
		}
	}

	/// Open the symbol that was chosen.
	var onOpen: ((LSPLocation) -> Void)?
	/// Asked for the symbols to show; nil query means everything.
	var provider: ((_ query: String, _ scope: Scope) async -> [LSPSymbol])?
	/// Asked why there is nothing to show, when there is nothing to show.
	var emptyReason: ((_ query: String, _ scope: Scope) -> String)?

	private var window: NSPanel?
	private var field: NSSearchField!
	private var table: NSTableView!
	private var symbols: [LSPSymbol] = []
	private var scope: Scope = .document
	private var status: NSTextField!
	private var searchWork: Task<Void, Never>?
	/// What was last asked for, so the same question can be asked again when a
	/// server that could not answer it becomes able to.
	private var lastQuery = ""
	private var serverObserver: NSObjectProtocol?

	func show(scope: Scope, over parent: NSWindow?) {
		guard let parent else { return }
		self.scope = scope

		let window = self.window ?? makeWindow()
		self.window = window
		field.placeholderString = scope.placeholder
		field.stringValue = ""
		symbols = []
		table.reloadData()

		// Centred near the top, where every palette in every editor is.
		let frame = parent.frame
		let size = NSSize(width: min(680, frame.width - 80), height: 420)
		window.setFrame(NSRect(
			x: frame.midX - size.width / 2,
			y: frame.maxY - size.height - 140,
			width: size.width,
			height: size.height
		), display: true)

		parent.addChildWindow(window, ordered: .above)
		// Only takes the keyboard if this app already has it. Opening a palette
		// is a response to a keystroke, so it always will in normal use; in a
		// capture run it never does, and nobody else's typing lands here.
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
			window.makeFirstResponder(field)
		} else {
			window.orderFront(nil)
		}
		watchForServers()
		search("")
	}

	func hide() {
		searchWork?.cancel()
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
	}

	/// Asks the same question again when a language server changes state.
	///
	/// **Reported from use: the dialog is empty and then works out of nothing.**
	/// Opened before a server has finished starting it has nothing to show, and
	/// nothing ever asked again — so it sat empty until it was closed and
	/// reopened, and whether that was worth doing was a guess. The completion
	/// list already re-asks on this notification for exactly this reason; this
	/// is the same fix in the other place people meet a cold server.
	private func watchForServers() {
		guard serverObserver == nil else { return }
		serverObserver = NotificationCenter.default.addObserver(
			forName: .ideaiLanguageServersChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self, self.window?.isVisible == true, self.symbols.isEmpty else { return }
				self.search(self.lastQuery)
			}
		}
	}

	deinit {
		if let serverObserver { NotificationCenter.default.removeObserver(serverObserver) }
	}

	private func search(_ query: String) {
		searchWork?.cancel()
		lastQuery = query
		let scope = self.scope
		searchWork = Task { @MainActor in
			// A short pause, so typing a name does not ask the server about
			// every prefix of it.
			try? await Task.sleep(nanoseconds: 120_000_000)
			guard !Task.isCancelled, let provider else { return }

			let found = await provider(query, scope)
			guard !Task.isCancelled else { return }
			symbols = found
			table.reloadData()
			if !found.isEmpty {
				table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			}

			// An empty list has to say why. "Nothing here" and "no server for
			// this language" look identical otherwise, and one of them is
			// something the user can fix.
			status.stringValue = found.isEmpty ? (emptyReason?(query, scope) ?? "") : ""
			status.isHidden = !found.isEmpty
		}
	}

	fileprivate func openSelected() {
		let row = table.selectedRow
		guard symbols.indices.contains(row) else { return }
		let symbol = symbols[row]
		hide()
		onOpen?(symbol.location)
	}

	private func makeWindow() -> NSPanel {
		field = NSSearchField()
		field.font = Theme.current.uiFont(15)
		field.focusRingType = .none
		field.delegate = self
		field.sendsWholeSearchString = false

		table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = Theme.current.scaled(34)
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.selectionHighlightStyle = .regular
		table.style = .plain
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol")))
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(rowDoubleClicked)

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.scrollerStyle = .overlay

		status = NSTextField(labelWithString: "")
		status.font = Theme.current.uiFont(12)
		status.textColor = Theme.current.gitIgnored
		status.alignment = .center
		status.maximumNumberOfLines = 3
		status.isHidden = true

		let container = ColoredView(color: Theme.current.sidebarBackground)
		container.addSubview(field)
		container.addSubview(scroll)
		container.addSubview(status)
		field.translatesAutoresizingMaskIntoConstraints = false
		scroll.translatesAutoresizingMaskIntoConstraints = false
		status.translatesAutoresizingMaskIntoConstraints = false

		// Below the titlebar, whose buttons are drawn over the content when the
		// window fills its own frame.
		NSLayoutConstraint.activate([
			field.topAnchor.constraint(equalTo: container.topAnchor, constant: 34),
			field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
			field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

			scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
			scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

			status.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 24),
			status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
			status.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
		])

		let window = SymbolPanel(
			contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: true
		)
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.isMovableByWindowBackground = true
		window.backgroundColor = Theme.current.sidebarBackground
		window.contentView = container
		window.onKey = { [weak self] event in self?.handle(event) ?? false }
		// Clicking anywhere else puts it away, which is what every palette does
		// and what somebody tries after pressing escape has not occurred to
		// them.
		window.onResignKey = { [weak self] in self?.hide() }
		return window
	}

	/// The keys that drive the list, taken before the field sees them.
	private func handle(_ event: NSEvent) -> Bool {
		switch event.keyCode {
		case 53: // escape
			hide()
			return true
		case 36, 76: // return
			openSelected()
			return true
		case 125: // down
			move(by: 1)
			return true
		case 126: // up
			move(by: -1)
			return true
		case 116: // page up
			move(by: -pageSize)
			return true
		case 121: // page down
			move(by: pageSize)
			return true
		case 115: // home
			move(by: -symbols.count)
			return true
		case 119: // end
			move(by: symbols.count)
			return true
		default:
			return false
		}
	}

	/// How far a page moves: what fits in the list, less one row of overlap, so
	/// the place somebody was reading is still on screen afterwards. The same
	/// rule the project switcher's list uses, from the same helper.
	private var pageSize: Int {
		ListSelection.pageSize(
			viewportHeight: table.enclosingScrollView?.contentSize.height ?? table.bounds.height,
			rowHeight: table.rowHeight
		)
	}

	fileprivate func move(by delta: Int) {
		guard !symbols.isEmpty else { return }
		// Clamped rather than wrapped, so ⇞ at the top and ⇟ at the bottom land
		// on the ends instead of jumping to the other one.
		let from = table.selectedRow < 0 ? 0 : table.selectedRow
		let next = max(0, min(symbols.count - 1, from + delta))
		table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
		table.scrollRowToVisible(next)
	}

	@objc private func rowDoubleClicked() { openSelected() }

	/// Opens with a query already typed, for arriving from somewhere that
	/// knows what it is looking for — a flame graph frame, say.
	func show(scope: Scope, query: String, over parent: NSWindow?) {
		show(scope: scope, over: parent)
		field?.stringValue = query
		search(query)
	}

	// MARK: - Testing

	func setQueryForTesting(_ query: String) {
		field?.stringValue = query
		search(query)
	}

	var resultsForTesting: [String] {
		symbols.map { symbol in
			[symbol.kind.label, symbol.name].filter { !$0.isEmpty }.joined(separator: " ")
		}
	}

	/// Presses a key in the list and says where the selection ended up.
	///
	/// Through the field editor's `doCommandBy`, the same door the keyboard
	/// uses: the question is not whether the movement rule is right but whether
	/// ⇞ reaches it at all, and which selector a key sends depends on the field
	/// it lands in.
	func pressForTesting(_ command: String) -> String {
		let selectors: [String: Selector] = [
			"down": #selector(NSResponder.moveDown(_:)),
			"up": #selector(NSResponder.moveUp(_:)),
			"pageDown": #selector(NSResponder.pageDown(_:)),
			"pageUp": #selector(NSResponder.pageUp(_:)),
			"scrollPageDown": #selector(NSResponder.scrollPageDown(_:)),
			"scrollPageUp": #selector(NSResponder.scrollPageUp(_:)),
			"end": #selector(NSResponder.moveToEndOfDocument(_:)),
			"start": #selector(NSResponder.moveToBeginningOfDocument(_:)),
		]
		guard let selector = selectors[command] else { return "unknown key \(command)" }
		let handled = control(field, textView: NSTextView(), doCommandBy: selector)
		let row = table.selectedRow
		let what = symbols.indices.contains(row) ? symbols[row].name : "none"
		return "handled=\(handled) row=\(row) of \(symbols.count): \(what)"
	}

	func openFirstForTesting() {
		guard !symbols.isEmpty else { return }
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		openSelected()
	}
}

extension SymbolPalette: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		search(field.stringValue.trimmingCharacters(in: .whitespaces))
	}

	/// The keys that drive the list, taken from the field.
	///
	/// A search field handles the arrow keys itself — they open its list of
	/// recent searches — so they never reach the window and the list below
	/// never moves. Nothing else can intercept them either: this is the only
	/// place they are still on their way somewhere.
	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy selector: Selector
	) -> Bool {
		switch selector {
		case #selector(NSResponder.moveDown(_:)):
			move(by: 1)
			return true
		case #selector(NSResponder.moveUp(_:)):
			move(by: -1)
			return true
		// Both spellings of each, because which one a key sends depends on the
		// field it lands in — a list that answers only one of them works in some
		// places and not others. The same pair the project switcher answers.
		case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
			move(by: pageSize)
			return true
		case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
			move(by: -pageSize)
			return true
		case #selector(NSResponder.moveToBeginningOfDocument(_:)),
		     #selector(NSResponder.scrollToBeginningOfDocument(_:)):
			move(by: -symbols.count)
			return true
		case #selector(NSResponder.moveToEndOfDocument(_:)),
		     #selector(NSResponder.scrollToEndOfDocument(_:)):
			move(by: symbols.count)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			openSelected()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			hide()
			return true
		default:
			return false
		}
	}
}

extension SymbolPalette: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { symbols.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard symbols.indices.contains(row) else { return nil }
		return SymbolRowView(symbol: symbols[row])
	}
}

/// A panel that hands its key events to the palette first.
private final class SymbolPanel: NSPanel {
	var onKey: ((NSEvent) -> Bool)?
	var onResignKey: (() -> Void)?

	override var canBecomeKey: Bool { true }

	override func keyDown(with event: NSEvent) {
		guard onKey?(event) != true else { return }
		super.keyDown(with: event)
	}

	/// Escape reaches here even when the search field has the keyboard, since
	/// a field swallows it as "stop editing" rather than passing it on.
	override func cancelOperation(_ sender: Any?) {
		onResignKey?()
	}

	override func resignKey() {
		super.resignKey()
		onResignKey?()
	}
}

/// A symbol: what kind it is, what it is called, and where it lives.
private final class SymbolRowView: NSView {
	private let symbol: LSPSymbol
	override var isFlipped: Bool { true }

	init(symbol: LSPSymbol) {
		self.symbol = symbol
		super.init(frame: .zero)
		toolTip = symbol.location.url?.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(12)
		let top = Theme.current.scaled(4)

		// The kind as a small word rather than an icon: there are twenty-six of
		// them and no icon set tells a struct from a class at this size.
		if !symbol.kind.label.isEmpty {
			let kind = NSAttributedString(string: symbol.kind.label, attributes: [
				.font: Theme.current.uiFont(10),
				.foregroundColor: Theme.current.gitModified,
			])
			kind.draw(at: NSPoint(x: x, y: top + Theme.current.scaled(2)))
			x += max(kind.size().width, Theme.current.scaled(52)) + Theme.current.scaled(6)
		}

		let name = NSAttributedString(string: symbol.name, attributes: [
			.font: Theme.current.uiFont(13),
			.foregroundColor: Theme.current.sidebarText,
		])
		name.draw(at: NSPoint(x: x, y: top))

		var detail = symbol.container ?? ""
		if let path = symbol.location.url?.lastPathComponent {
			detail = detail.isEmpty ? path : "\(detail)  ·  \(path)"
		}
		guard !detail.isEmpty else { return }

		let attributed = NSAttributedString(string: detail, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		attributed.draw(in: NSRect(
			x: x,
			y: top + name.size().height + Theme.current.scaled(1),
			width: max(0, bounds.width - x - Theme.current.scaled(12)),
			height: attributed.size().height
		))
	}
}

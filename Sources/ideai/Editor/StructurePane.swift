import AppKit
import IdeaiKit

/// The active file's declarations, as an outline you can jump from.
///
/// Driven by the same tree-sitter parse the editor already keeps, so it costs
/// one query rather than a second model of the file.
final class StructurePane: NSView {
	/// A symbol was activated; the line is zero-based.
	var onSelectSymbol: ((Int) -> Void)?

	private var symbols: [DocumentSymbol] = []
	private var fileName: String?
	private var filterText = ""

	private var filterField: NSSearchField!
	private var outlineView: NSOutlineView!
	private var placeholder: NSTextField!

	/// Wraps a symbol so `NSOutlineView`, which needs reference identity, can
	/// hold on to it.
	private final class Node {
		let symbol: DocumentSymbol
		let children: [Node]

		init(_ symbol: DocumentSymbol) {
			self.symbol = symbol
			children = symbol.children.map(Node.init)
		}
	}

	private var roots: [Node] = []

	init() {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Layout

	private func build() {
		filterField = NSSearchField()
		filterField.placeholderString = "Filter symbols"
		filterField.font = Theme.current.uiFont(12)
		filterField.focusRingType = .none
		filterField.delegate = self
		filterField.sendsWholeSearchString = false

		outlineView = NSOutlineView()
		outlineView.headerView = nil
		outlineView.backgroundColor = Theme.current.sidebarBackground
		outlineView.selectionHighlightStyle = .regular
		outlineView.rowSizeStyle = .custom
		outlineView.intercellSpacing = .zero
		outlineView.gridStyleMask = []
		outlineView.indentationPerLevel = Theme.current.scaled(14)
		outlineView.autoresizesOutlineColumn = false

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol"))
		outlineView.addTableColumn(column)
		outlineView.outlineTableColumn = column
		outlineView.delegate = self
		outlineView.dataSource = self
		outlineView.target = self
		outlineView.action = #selector(rowClicked)

		let scrollView = NSScrollView()
		scrollView.documentView = outlineView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.sidebarBackground
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle

		placeholder = NSTextField(labelWithString: "No symbols")
		placeholder.font = Theme.current.uiFont(12)
		placeholder.textColor = Theme.current.gitIgnored
		placeholder.alignment = .center

		for view in [filterField, scrollView, placeholder] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			filterField.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			filterField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			filterField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			scrollView.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: inset / 2),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

			placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
			placeholder.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: inset * 3),
		])
	}

	// MARK: - Content

	func setSymbols(_ symbols: [DocumentSymbol], fileName: String?) {
		self.symbols = symbols
		self.fileName = fileName
		rebuild()
	}

	private func rebuild() {
		let filtered = filter(symbols, needle: filterText.lowercased())
		roots = filtered.map(Node.init)
		outlineView.reloadData()

		// Expanded by default: an outline that has to be unfolded before it
		// shows anything is slower to read than the file itself.
		for node in roots { expandAll(node) }

		let isEmpty = roots.isEmpty
		placeholder.isHidden = !isEmpty
		placeholder.stringValue = fileName == nil
			? "No file open"
			: (filterText.isEmpty ? "No symbols in this file" : "No matching symbols")
	}

	/// Keeps a symbol when it matches, or when anything beneath it does — a
	/// method found under a type is no use without the type above it.
	private func filter(_ symbols: [DocumentSymbol], needle: String) -> [DocumentSymbol] {
		guard !needle.isEmpty else { return symbols }

		return symbols.compactMap { symbol in
			let children = filter(symbol.children, needle: needle)
			guard symbol.name.lowercased().contains(needle) || !children.isEmpty else { return nil }

			var copy = symbol
			copy.children = children
			return copy
		}
	}

	private func expandAll(_ node: Node) {
		outlineView.expandItem(node)
		for child in node.children { expandAll(child) }
	}

	@objc private func rowClicked() {
		let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
		onSelectSymbol?(node.symbol.line)
	}

	func applyThemeChange() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		filterField.font = Theme.current.uiFont(12)
		outlineView.indentationPerLevel = Theme.current.scaled(14)
		outlineView.reloadData()
	}
}

extension StructurePane: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		(item as? Node)?.children.count ?? roots.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		(item as? Node)?.children[index] ?? roots[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		!((item as? Node)?.children.isEmpty ?? true)
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		Theme.current.scaled(22)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? Node else { return nil }
		return SymbolRowView(symbol: node.symbol)
	}
}

extension StructurePane: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		filterText = filterField.stringValue.trimmingCharacters(in: .whitespaces)
		rebuild()
	}
}

private final class SymbolRowView: NSView {
	private let symbol: DocumentSymbol
	override var isFlipped: Bool { true }

	init(symbol: DocumentSymbol) {
		self.symbol = symbol
		super.init(frame: .zero)
		toolTip = "\(symbol.name) — line \(symbol.line + 1)"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x: CGFloat = 0
		let iconSize = Theme.current.scaled(13)

		if let icon = Theme.symbol(
			symbol.kind.symbolName,
			size: 11 * Theme.current.scale,
			color: colour(for: symbol.kind)
		) {
			icon.draw(
				in: NSRect(x: x, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
		}
		x += iconSize + Theme.current.scaled(6)

		let name = NSAttributedString(string: symbol.name, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		name.draw(at: NSPoint(x: x, y: bounds.midY - name.size().height / 2))
		x += name.size().width + Theme.current.scaled(8)

		// The line number, right-aligned, so the outline doubles as a map of
		// where things are in the file.
		let line = NSAttributedString(string: "\(symbol.line + 1)", attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		let width = line.size().width
		guard bounds.width - width - Theme.current.scaled(8) > x else { return }
		line.draw(at: NSPoint(
			x: bounds.width - width - Theme.current.scaled(8),
			y: bounds.midY - line.size().height / 2
		))
	}

	private func colour(for kind: DocumentSymbol.Kind) -> NSColor {
		switch kind {
		case .type, .protocolType, .enumeration: return Theme.current.gitModified
		case .function, .method:                 return Theme.current.gitAdded
		case .property, .constant:               return Theme.current.sidebarText
		case .module, .other:                    return Theme.current.gitIgnored
		}
	}
}

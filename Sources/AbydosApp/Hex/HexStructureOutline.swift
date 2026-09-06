import AbydosKit
import AppKit

/// The explanation of a file as a tree, parsed rows and Claude's apart.
///
/// A row selects its bytes; the caret's field is named above the bytes by the
/// controller from the same tree. Claude's rows sit under a heading that
/// says so and in a lighter weight, because an answer about a sample is a
/// reading and not a fact, and the two must never look the same.
final class HexStructureOutline: NSView, ScaleFollowing {
	var onSelectRange: ((Range<Int>) -> Void)?
	var onAsk: (() -> Void)?
	var onShowPrompt: (() -> Void)?

	/// Wraps a node so the outline, which needs reference identity, can hold
	/// on to it.
	final class Node {
		let node: StructureNode
		let children: [Node]
		init(_ node: StructureNode) {
			self.node = node
			children = node.children.map(Node.init)
		}
	}

	private var roots: [Node] = []
	private var outline: NSOutlineView!
	private var scroll: NSScrollView!
	private var header: NSTextField!
	private var summary: NSTextField!
	/// Shows and hides `summary`; see where it is made.
	private var summaryToggle: NSButton!
	private var summaryShown = false
	private var askButton: NSButton!
	private var promptButton: NSButton!
	private var spinner: NSProgressIndicator!
	private var buttons: NSStackView!
	private var stack: NSStackView!
	private let heights = ScaledHeights()

	init() {
		super.init(frame: .zero)
		build()
		applyTheme()
		ScaledControls.register(self)
	}

	/// The fonts, the row height and the spacing again, as the zoom moves.
	func applyTheme() {
		let theme = Theme.current
		header.font = theme.uiFont(11)
		header.textColor = theme.gitIgnored
		summary.font = theme.uiFont(11)
		askButton.font = theme.uiFont(11)
		promptButton.font = theme.uiFont(10)
		summaryToggle.font = theme.uiFont(10)
		summaryToggle.contentTintColor = theme.gitIgnored
		outline.rowHeight = theme.scaled(18)
		outline.indentationPerLevel = theme.scaled(12)
		outline.reloadData()
		buttons.spacing = theme.scaled(6)
		stack.spacing = theme.scaled(6)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		header = NSTextField(wrappingLabelWithString: "")

		outline = NSOutlineView()
		outline.headerView = nil
		outline.backgroundColor = .clear
		outline.selectionHighlightStyle = .regular
		outline.style = .plain
		let column = NSTableColumn(identifier: .init("node"))
		column.resizingMask = .autoresizingMask
		outline.addTableColumn(column)
		outline.outlineTableColumn = column
		outline.dataSource = self
		outline.delegate = self
		outline.target = self
		outline.action = #selector(rowClicked)

		scroll = NSScrollView()
		scroll.documentView = outline
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		heights.height(scroll, design: 200).isActive = true

		askButton = NSButton(title: "Ask Claude", target: self, action: #selector(askPressed))
		askButton.bezelStyle = .rounded
		askButton.toolTip = "Sends a bounded sample of the file — never the whole file — to the claude command and adds what it says as rows marked as Claude's"

		promptButton = NSButton(title: "Show what was asked", target: self, action: #selector(promptPressed))
		promptButton.bezelStyle = .inline
		promptButton.isHidden = true

		spinner = NSProgressIndicator()
		spinner.style = .spinning
		spinner.isHidden = true
		// Sized by a constraint the zoom moves, not by a `controlSize`.
		heights.height(spinner, design: 16).isActive = true
		spinner.widthAnchor.constraint(equalTo: spinner.heightAnchor).isActive = true

		summary = NSTextField(wrappingLabelWithString: "")
		summary.isHidden = true
		summary.isSelectable = true

		// Folded away by default, because the fields are the answer and the
		// summary is the preamble to it. Claude's prose runs to several lines
		// and it sat above nothing else somebody wanted, pushing the rows it
		// describes off the bottom of a pane that is already a column.
		summaryToggle = NSButton(title: "", target: self, action: #selector(summaryToggled))
		summaryToggle.bezelStyle = .inline
		summaryToggle.isBordered = false
		summaryToggle.isHidden = true
		summaryToggle.toolTip = "What Claude said about this file, in prose"

		buttons = NSStackView(views: [askButton, spinner, promptButton, NSView()])
		buttons.orientation = .horizontal

		stack = NSStackView(views: [header, scroll, buttons, summaryToggle, summary])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
			header.widthAnchor.constraint(equalTo: stack.widthAnchor),
			summary.widthAnchor.constraint(equalTo: stack.widthAnchor),
		])
	}

	// MARK: - What is shown

	/// The parsed tree, or none, and Claude's rows under their own heading.
	func show(parsed: StructureNode?, claude: [StructureNode], claudeSummary: String?) {
		var roots: [Node] = []
		if let parsed {
			roots.append(Node(parsed))
			header.stringValue = "\(parsed.name), \(parsed.totalCount - 1) fields"
		} else {
			header.stringValue = "No built-in format recognised this file."
		}
		if !claude.isEmpty {
			roots.append(Node(StructureNode(
				name: "Claude says", range: 0..<0, meaning: "from a sample, not parsed", children: claude, source: .claude
			)))
		}
		self.roots = roots
		// No tree, no box for it: two hundred points of empty outline under
		// "no built-in format recognised this file" pushed the values away.
		scroll.isHidden = roots.isEmpty
		outline.reloadData()
		for root in roots { outline.expandItem(root) }
		if let first = roots.first, first.children.count <= 40 {
			for child in first.children where !child.children.isEmpty && child.children.count <= 12 {
				outline.expandItem(child)
			}
		}
		summary.stringValue = claudeSummary ?? ""
		summaryToggle.isHidden = claudeSummary == nil
		// A fresh answer arrives folded: the rows moved, and the pane should
		// not scroll out from under whoever asked for them.
		if claudeSummary == nil { summaryShown = false }
		applySummaryDisclosure()
		promptButton.isHidden = claudeSummary == nil
	}

	func setAskAvailable(_ available: Bool) {
		askButton.isHidden = !available
	}

	func setAsking(_ asking: Bool, selection: Bool) {
		spinner.isHidden = !asking
		if asking { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
		askButton.title = asking ? "Cancel" : (selection ? "Ask Claude about the selection" : "Ask Claude")
	}

	func showFailure(_ said: String) {
		summary.stringValue = said
		// A complaint is not prose anybody asked to fold away.
		summaryToggle.isHidden = true
		summaryShown = true
		applySummaryDisclosure()
		promptButton.isHidden = true
	}

	@objc private func summaryToggled() {
		summaryShown.toggle()
		applySummaryDisclosure()
	}

	private func applySummaryDisclosure() {
		summary.isHidden = summary.stringValue.isEmpty || (!summaryShown && !summaryToggle.isHidden)
		summaryToggle.title = summaryShown ? "▾ What Claude said" : "▸ What Claude said"
	}

	var headerText: String { header.stringValue }
	var summaryText: String { summary.stringValue }
	/// Whether the prose is folded away, for a driven run to report.
	var summaryIsShownForTesting: Bool { !summary.isHidden }

	/// Every row as text, for the driver's report.
	var rowsForTesting: [String] {
		var lines: [String] = []
		func walk(_ node: Node, _ depth: Int) {
			let n = node.node
			var line = String(repeating: "  ", count: depth) + n.name
			if !n.range.isEmpty { line += " @0x\(String(n.range.lowerBound, radix: 16, uppercase: true))+\(n.range.count)" }
			if let value = n.value { line += " = \(value)" }
			if let meaning = n.meaning { line += " (\(meaning))" }
			if n.source == .claude { line += " [claude]" }
			if n.source == .problem { line += " [problem]" }
			lines.append(line)
			for child in node.children { walk(child, depth + 1) }
		}
		for root in roots { walk(root, 0) }
		return lines
	}

	@objc private func rowClicked() {
		guard let item = outline.item(atRow: outline.clickedRow) as? Node, !item.node.range.isEmpty else { return }
		onSelectRange?(item.node.range)
	}

	@objc private func askPressed() { onAsk?() }
	@objc private func promptPressed() { onShowPrompt?() }
}

extension HexStructureOutline: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		(item as? Node)?.children.count ?? roots.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		((item as? Node)?.children ?? roots)[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		!((item as? Node)?.children.isEmpty ?? true)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = (item as? Node)?.node else { return nil }
		let theme = Theme.current
		let cell = NSTextField(labelWithAttributedString: attributed(node, theme))
		cell.lineBreakMode = .byTruncatingTail
		cell.toolTip = tooltip(node)
		return cell
	}

	private func attributed(_ node: StructureNode, _ theme: Theme) -> NSAttributedString {
		let line = NSMutableAttributedString()
		let weight: NSFont.Weight = node.source == .claude ? .light : .regular
		let nameColour = node.source == .problem ? theme.gitConflict : theme.editorText
		line.append(NSAttributedString(string: node.name, attributes: [.font: theme.uiFont(11, weight: weight), .foregroundColor: nameColour]))
		if let value = node.value {
			line.append(NSAttributedString(string: "  \(value)", attributes: [.font: theme.monoFont(11, weight: weight), .foregroundColor: theme.gitAdded]))
		}
		if let meaning = node.meaning, node.source != .claude || node.value == nil {
			line.append(NSAttributedString(string: "  \(meaning)", attributes: [.font: theme.uiFont(10, weight: weight), .foregroundColor: theme.gitIgnored]))
		}
		return line
	}

	private func tooltip(_ node: StructureNode) -> String {
		var said = node.range.isEmpty ? "" : String(format: "0x%llX, %lld bytes", node.range.lowerBound, node.range.count)
		if let meaning = node.meaning { said += (said.isEmpty ? "" : "\n") + meaning }
		if node.source == .claude { said += (said.isEmpty ? "" : "\n") + "Said by Claude about a sample of the file." }
		return said
	}

	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard let item = outline.item(atRow: outline.selectedRow) as? Node, !item.node.range.isEmpty else { return }
		onSelectRange?(item.node.range)
	}
}
